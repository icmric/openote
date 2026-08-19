//! Importer for Microsoft OneNote `.one` section files (MS-ONESTORE +
//! MS-ONE), reverse-engineered against real Office-365 OneNote output.
//!
//! There is scant practical documentation for this format, so this parser was
//! built empirically: it walks the ONESTORE revision-store container (header →
//! file-node-list fragments → object groups → object declarations), reads each
//! object's `ObjectSpaceObjectPropSet`, and pulls out the MS-ONE properties
//! that carry user content. The property IDs (see the `PID_*` consts below)
//! were identified by decoding a real section and matching the output to the
//! notebook; the primary body text is `0x003498` (UTF-8), with `0x001C22`
//! (UTF-16) holding secondary/diagram-label runs. See each const for details.
//!
//! Embedded images are stored inline in the file data store; for v1 we recover
//! them by scanning for PNG signatures (the only image type this exporter
//! emitted), which is robust and avoids a full file-data-store walk.
//!
//! Scope: pages (one per content object space; the current revision of every
//! object = its highest-file-offset occurrence); the page root's children as
//! separate positioned **boxes** (0x1C14/15 offsets, 0x1C1B width); outline
//! text with **bold/italic/strikethrough**, font family and colour (0x1C04-0C
//! styles via the 0x1E12/0x1E13 run arrays); bulleted/indented lists;
//! **in-flow images** (an image as a list item stays inside its box's markdown
//! as `![image](onote-img://N)`); floating images at their offset-chain
//! positions; **equations** (Cambria-Math runs, Office linear-math Unicode →
//! LaTeX, see [`office_math_to_latex`]) as their own boxes; and **ink**: the
//! InkContainer→InkDataNode→InkStrokeNode chain with MS-ISF multi-byte
//! delta-encoded paths (see [`decode_multibyte_signed`]), X/Y/pressure
//! dimension tables, pen size/colour/alpha — decoded into page-pixel strokes.
//! Run `cargo run --example dump_one -- file.one [--import|--ink]` to inspect.

use serde::Serialize;
use std::collections::{HashMap, HashSet};

// ── MS-ONE property IDs (empirically identified against real files) ────────
/// Outline/paragraph body text, stored UTF-8 (the main content property).
// Note tags (TEXT-5). Decoded against a real tagged `.one`; see the
// property-walk fix that made them readable at all — 0x3489 is an
// ArrayOfPropertyValues, and until its length was computed properly every
// property after it was read from the wrong offset.
const JCID_TAG_DEF: u32 = 0x00120043;
const PID_TAG_STATES: u32 = 0x003489; // paragraph → array of tag states
const PID_TAG_DEF_OID: u32 = 0x003488; // state → the tag definition it applies
const PID_TAG_LABEL: u32 = 0x003468; // definition → "To Do", "Question", …
const PID_TAG_SHAPE: u32 = 0x003464; // definition → OneNote's icon index

const PID_TEXT_UTF8: u32 = 0x003498;
/// Secondary rich text, stored UTF-16 (diagram labels, some runs).
const PID_TEXT_UTF16: u32 = 0x001C22;
/// Page/section title text (UTF-16). On a page-metadata object (0x00020030)
/// this is the tab title; 0x1CF3 = CachedTitleString.
const PID_TITLE: u32 = 0x001CF3;
/// Page-metadata subpage level (0-based: 0 = top-level, 1..2 = subpage).
const PID_PAGE_LEVEL: u32 = 0x001DFF;

// ── Section → pages structure (directory object space, MS-ONE §2.2) ────────
// SectionNode (0x00060007) → ElementChildNodes (0x1C20) = ordered PageSeries
// refs. Each PageSeriesNode (0x00060008) carries two PARALLEL arrays:
// ChildGraphSpaceElementNodes (0x1D63, object-SPACE refs → page content) and
// MetaDataObjectsAboveGraphSpace (0x3442, object refs → PageMetadata: title +
// level). A section has MANY series; concatenating their pages in section
// order gives the true page order (the earlier code read a single series, so
// order was wrong and only that series' subpage levels applied).
const JCID_SECTION_NODE: u32 = 0x00060007;
/// PageNode — the top of a page object space's content tree, and what a page
/// space's live role-1 root resolves to. See [live_anchor].
const JCID_PAGE_NODE: u32 = 0x00060037;
const JCID_PAGE_SERIES: u32 = 0x00060008;
const PID_ELEMENT_CHILDREN: u32 = 0x001C20; // section → page-series refs
const PID_PAGE_METADATA: u32 = 0x003442; // page-series → PageMetadata refs
const PID_PAGE_SPACES: u32 = 0x001D63; // page-series → page object-space refs
/// PageMetadata object. Two copies of each exist: one in the section directory
/// space (the tab: title + subpage level) and one inside the page's own object
/// space. Both carry the same [PID_PAGE_GUID], which is what ties them together.
const JCID_PAGE_METADATA: u32 = 0x00020030;
/// The page's identity GUID on a PageMetadata object. This — not the position
/// of the metadata in the page-series array — says which page a title belongs
/// to; see the pairing in [import_one].
const PID_PAGE_GUID: u32 = 0x001C30;

/// The page a PageMetadata object names, if it names one.
fn page_guid(r: &Reader, o: &Obj) -> Option<[u8; 16]> {
    match read_propset(r, o.stp, o.cb).get(PID_PAGE_GUID) {
        Some(PVal::Str(b)) if b.len() == 16 => {
            let mut g = [0u8; 16];
            g.copy_from_slice(b);
            Some(g)
        }
        _ => None,
    }
}

/// Which PageMetadata object each page of a section takes its title and subpage
/// level from — **by the page's identity, not by its position**.
///
/// `metas`: every metadata object this section's page series reference, as (the
/// page GUID it names, object index). `pages`: the section's pages in display
/// order, as (the page's own identity GUID, the metadata the k-th-with-k-th
/// pairing would give it). Returns one metadata per page, in the same order.
///
/// Position is only the fallback. `0x1D63` lists a series' pages in display
/// order while `0x3442` lists its metadata in creation order, so on any section
/// whose pages have been reordered the two arrays are a permutation apart and
/// pairing them by index hands pages each other's titles.
fn pair_page_metadata(
    metas: &[([u8; 16], usize)],
    pages: &[(Option<[u8; 16]>, Option<usize>)],
) -> Vec<Option<usize>> {
    let mut by_page: HashMap<[u8; 16], usize> = HashMap::new();
    // A GUID two different metadata objects both claim names no one page; such
    // a page keeps the positional pairing rather than guessing between them.
    let mut ambiguous: HashSet<[u8; 16]> = HashSet::new();
    for &(g, mi) in metas {
        if by_page.insert(g, mi).is_some_and(|prev| prev != mi) {
            ambiguous.insert(g);
        }
    }
    pages
        .iter()
        .map(|(own, by_index)| {
            own.filter(|g| !ambiguous.contains(g))
                .and_then(|g| by_page.get(&g).copied())
                // No identity to go on (or it names nothing we hold): an
                // approximate title beats no title at all.
                .or(*by_index)
        })
        .collect()
}

// ── MS-ONE object types (JCID) we navigate ─────────────────────────────────
const JCID_OUTLINE: u32 = 0x0006000B;
const JCID_OUTLINE_ELEMENT: u32 = 0x0006000C;
const JCID_RICHTEXT: u32 = 0x0006000D;
const JCID_RICHTEXT_RUN: u32 = 0x0006000E;
const JCID_TITLE: u32 = 0x0006002C;
const JCID_OUTLINE_GROUP: u32 = 0x00060019;
// Tables (MEDIA-3 on import). Rows hang off the table and cells off the rows,
// both through the same 0x1C20 ElementChildNodes list every container uses, so
// the only new thing here is knowing to stop and build a grid instead of
// flattening the cells into loose paragraphs.
const JCID_TABLE: u32 = 0x00060022;
const JCID_TABLE_ROW: u32 = 0x00060023;
const JCID_TABLE_CELL: u32 = 0x00060024;
/// Declared row count on a table node (0x1D57) — cross-checked against the
/// number of row children we actually resolve.
const PID_TABLE_ROWS: u32 = 0x001D57;
/// Declared column count (0x1D58); short rows are padded to it.
const PID_TABLE_COLS: u32 = 0x001D58;
/// Column widths (0x1D66), in the same units as image positions and sizes.
/// Packed into the *string* property slot as a `u8` count followed by that many
/// little-endian `f32`s — verified against real tables: 13 bytes for 3 columns,
/// 9 bytes for 2. Without these every column rendered at an identical guessed
/// width, so imported tables were the wrong overall size and collided with
/// whatever sat below them.
const PID_TABLE_COL_WIDTHS: u32 = 0x001D66;
const JCID_NUMBER_LIST: u32 = 0x00060012;
const JCID_IMAGE: u32 = 0x00060011;

// Character/paragraph styling (on 00020001 / 0012004D style objects).
const PID_FONT: u32 = 0x001C0A; // font family name (UTF-16)
const PID_FONT_SIZE: u32 = 0x001C0B; // font size in half-points (22 = 11pt)
const PID_FONT_COLOR: u32 = 0x001C0C; // font colour (u32; FF000000 = auto/black)
const PID_HIGHLIGHT: u32 = 0x001C0D; // highlight colour (FF000000 = none)
const PID_BOLD: u32 = 0x001C04;
const PID_ITALIC: u32 = 0x001C05;
const PID_UNDERLINE: u32 = 0x001C06;
const PID_STRIKE: u32 = 0x001C07;
// Plain-text superscript/subscript — a property of the character run, NOT
// maths. OneNote's ribbon has x² / x₂ buttons that set exactly these, and a
// student writing "a₁, a₂, … aₘ" in ordinary prose uses them rather than the
// equation editor. Both were parsed as unknown properties and dropped, so every
// such subscript imported flat ("a1"), silently changing what the note says.
const PID_SUPERSCRIPT: u32 = 0x001C08;
const PID_SUBSCRIPT: u32 = 0x001C09;
const PID_RUN_INDEX: u32 = 0x001E12; // TextRunIndex: array of u32 char offsets
const PID_RUN_FORMATTING: u32 = 0x001E13; // TextRunFormatting: style OIDs per run

// ── The maths-structure sidecar (0x3499) ───────────────────────────────────
//
// A OneNote equation is stored as ordinary run text sprinkled with the Office
// structure noncharacters — U+FDD0 opens an argument list, U+FDEE separates
// arguments, U+FDEF closes — and NOTHING in that text says what kind of object
// each U+FDD0 opens. The importer used to assume "fraction" for every one of
// them, which is why the reference page's piecewise definition came back as
// `\frac{n}{2}\text{ if }2 n) −\frac{n+1}{2}…` with its curly brace, its
// equation array and its delimiters all gone.
//
// The type IS in the file: 0x3499 is an ArrayOfPropertyValues with ONE ENTRY
// PER TEXT RUN (same indexing as 0x1E12/0x1E13), and the entry belonging to the
// run that *starts* with the U+FDD0 describes the object it opens. Decoded
// against 1 154 equations in the owner's notebook (every distinct maths
// paragraph in `Eric - Computing Science (Honours).onepkg`); the `beg`
// character each type carries is Office's own linear-format marker for it,
// which is what pins the mapping down.
const PID_MATH_OBJECTS: u32 = 0x003499;
const PID_MATH_KIND: u32 = 0x00344F; // MATH_* below
const PID_MATH_ARGS: u32 = 0x003450; // on an opening run: argument/cell count
const PID_MATH_COLS: u32 = 0x003451; // columns (matrices, equation arrays)
const PID_MATH_BEG: u32 = 0x003453; // opening delimiter / operator character
const PID_MATH_END: u32 = 0x003454; // closing delimiter character

// Observed kinds, each identified by the linear-format character it carries.
const MATH_ACCENT: u32 = 10; // beg = a combining accent (U+0302 ̂, U+20D7 ⃗)
const MATH_DELIM: u32 = 13; // beg/end = ( ) [ ] { } | | ⌊ ⌋ …
const MATH_DELIM_SEP: u32 = 14; // as above but the arguments are `|`-separated
const MATH_EQ_ARRAY: u32 = 15; // beg = █ (U+2588)
const MATH_FRACTION: u32 = 16; // beg = /
const MATH_FUNC: u32 = 17; // beg = U+2061 FUNCTION APPLICATION
const MATH_LIM_LOW: u32 = 19; // beg = _  (the limit under `lim`)
const MATH_MATRIX: u32 = 20; // beg = ■ (U+25A0)
const MATH_NARY: u32 = 21; // beg = ∑ ∏ ∫ ∮ …
const MATH_RADICAL: u32 = 25; // beg = √
const MATH_NO_BAR: u32 = 27; // beg = ¦ — the binomial-coefficient stack
const MATH_SUB: u32 = 29; // beg = _
const MATH_SUB_SUP: u32 = 30; // beg = _ , three arguments
const MATH_SUP: u32 = 31; // beg = ^
const MATH_UNDERBAR: u32 = 32; // beg = ▁ (U+2581)
const PID_PARA_STYLE: u32 = 0x00342C; // paragraph style OID

// ── Ink (MS-ONE ink object model; encoding per MS-ISF multi-byte) ──────────
// Chain: InkContainer (0x00060014; offsets 0x1C14/15, scaling 0x1C46/47)
//   ─0x3415→ InkDataNode (0x0002003B) ─0x3416→ [InkStrokeNode (0x00020047)]
//   each stroke: packed path 0x340B + ─0x3409→ StrokeProperties (0x0012004⁠8:
//   dimension table 0x340A, pen size 0x340C/0D, colour 0x340F, alpha 0x3414).
const JCID_INK_CONTAINER: u32 = 0x00060014;
const JCID_INK_DATA: u32 = 0x0002003B;
const JCID_INK_STROKE: u32 = 0x00020047;
const PID_INK_DATA_REF: u32 = 0x3415; // container → data node
const PID_INK_STROKES: u32 = 0x3416; // data node → stroke nodes
const PID_INK_PATH: u32 = 0x340B; // packed point data (multi-byte signed)
const PID_INK_STROKE_PROPS: u32 = 0x3409; // stroke → properties node
const PID_INK_DIMENSIONS: u32 = 0x340A; // 32-byte entries: guid + lo/hi limits
const PID_INK_HEIGHT: u32 = 0x340C; // pen tip size, HIMETRIC (0.01 mm)
const PID_INK_WIDTH: u32 = 0x340D;
const PID_INK_COLOR: u32 = 0x340F; // COLORREF 0x00BBGGRR
const PID_INK_TRANSPARENCY: u32 = 0x3414; // 0 translucent … 255 opaque
const PID_INK_SCALING_X: u32 = 0x1C46; // ink units → half-inch page units
const PID_INK_SCALING_Y: u32 = 0x1C47;
/// Ink dimension GUIDs (little-endian bytes as stored): X, Y, and ISF
/// NormalPressure.
const DIM_X: [u8; 16] = [
    0x8f, 0x6a, 0x8a, 0x59, 0xc0, 0x52, 0xa0, 0x4b, 0x93, 0xaf, 0xaf, 0x35, 0x74, 0x11, 0xa5, 0x61,
];
const DIM_Y: [u8; 16] = [
    0x75, 0x9f, 0x3f, 0xb5, 0xe0, 0x04, 0x98, 0x44, 0xa7, 0xee, 0xc3, 0x0d, 0xbb, 0x5a, 0x90, 0x11,
];
const DIM_P: [u8; 16] = [
    0x2d, 0x50, 0x07, 0x73, 0xf4, 0xf9, 0x18, 0x4e, 0xb3, 0xf2, 0x2c, 0xe1, 0xb1, 0xa3, 0x61, 0x0c,
];

// List + image layout properties.
const PID_BULLET: u32 = 0x001C1A; // NumberListNode bullet string (UTF-16)
const PID_IMG_POSX: u32 = 0x001C14; // image horizontal offset (units)
const PID_IMG_POSY: u32 = 0x001C15; // image vertical offset (units)
const PID_IMG_DISPW: u32 = 0x001C1B; // displayed width
const PID_IMG_DISPH: u32 = 0x001C1C; // displayed height
const PID_IMG_NATW: u32 = 0x0034CD; // natural width (matches PNG px/UNIT)
const PID_IMG_NATH: u32 = 0x0034CE; // natural height

/// OneNote layout units → pixels. Calibrated: a 5.35×4.23-unit image is a
/// 321×254-px PNG (321/5.35 ≈ 60), so ~60 px per unit.
const UNIT_PX: f32 = 60.0;

const MAGIC_FRAG_HEADER: u64 = 0xA4567AB1F5F7F4C4;
const PNG_SIG: &[u8] = &[0x89, b'P', b'N', b'G', b'\r', b'\n', 0x1A, b'\n'];

#[derive(Serialize, Default)]
pub struct ImportedImage {
    pub name: String,
    /// Page position + display size, in Openote page pixels (0 if unknown).
    pub x: f32,
    pub y: f32,
    pub disp_w: f32,
    pub disp_h: f32,
    pub width: u32,  // natural PNG pixel width
    pub height: u32, // natural PNG pixel height
    /// True for an image that lives IN a text box's flow (a list item that is
    /// an image): it's referenced from the box markdown via
    /// `![image](onote-img://N)` and must NOT become a floating image block.
    pub in_flow: bool,
    /// PNG bytes, base64-encoded (so the whole result is a JSON string).
    pub data_base64: String,
}

/// A tag on one line of a box: [ParaTag] plus where it landed.
#[derive(Serialize)]
pub struct BoxTag {
    /// 0-based line index within the box's markdown.
    pub line: usize,
    pub label: String,
    pub shape: u32,
}

/// One positioned content box on the page. `kind` is `"text"` (markdown set)
/// or `"math"` (latex set) — equations become their own box so Openote mounts
/// a real math block instead of burying `$$…$$` mid-paragraph.
#[derive(Serialize, Default)]
pub struct PageBox {
    pub kind: String,
    pub x: f32,
    pub y: f32,
    /// Box width in page px, when OneNote recorded one (0x1C1B).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub w: Option<f32>,
    /// kind=="text": one line per paragraph, indented, list items keeping their
    /// original bullet, with **bold**/*italic*/~~strike~~/`{{#hex}}` inline
    /// (Openote's live-Markdown dialect).
    #[serde(skip_serializing_if = "String::is_empty")]
    pub markdown: String,
    /// kind=="math": the equation's LaTeX.
    #[serde(skip_serializing_if = "String::is_empty")]
    pub latex: String,
    /// kind=="table": row-major cells, each cell's own Markdown. Rectangular —
    /// short rows are padded — because the app's table view requires it.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub cells: Vec<Vec<String>>,
    /// kind=="table": per-column widths in page px, from 0x1D66. One entry per
    /// column of `cells`. Empty when OneNote didn't record them, in which case
    /// the app falls back to equal columns.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub col_w: Vec<f32>,
    /// Note tags, each pinned to a 0-based line index within [markdown].
    ///
    /// Per LINE rather than per box because that is Openote's model (and
    /// OneNote's): a tag marks a paragraph, and one box holds many.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub tags: Vec<BoxTag>,
    /// Boxes that came out of one OneNote container, in document order, share a
    /// flow id (0 = not in a flow).
    ///
    /// Their `y` here is only an estimate: this side counts *source* lines at a
    /// fixed pitch, so a paragraph that wraps to three visual lines is costed as
    /// one and everything below it rides up — which is why an imported table
    /// landed too high and consecutive tables overlapped. The app re-stacks each
    /// flow using real text measurement, where the font metrics actually live.
    /// The first box of a flow keeps its parsed position; only the offsets of
    /// those after it are recomputed.
    #[serde(skip_serializing_if = "is_zero")]
    pub flow: u32,
    /// The box's dominant font family (Openote applies it box-level), if known.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub font: Option<String>,
    /// The box's dominant font size in points. Openote renders imported boxes
    /// at this size (scaled to the page's 120 dpi space) so box heights track
    /// OneNote's layout — absolutely-positioned siblings then line up instead
    /// of leaving gaps where OneNote's taller text used to be.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub font_size_pt: Option<f32>,
}

/// One decoded ink stroke, in Openote page pixels.
#[derive(Serialize, Default)]
pub struct ImportedStroke {
    pub x: Vec<f32>,
    pub y: Vec<f32>,
    /// Pressure 0..1 per point; empty when the stroke has no pressure channel.
    pub p: Vec<f32>,
    /// "#RRGGBB" when OneNote stored an explicit pen colour, else "auto" — the
    /// renderer resolves "auto" from the active theme (dark ink on light,
    /// light ink on dark), the same way default text colour works.
    pub color: String,
    pub size: f32,    // pen width in page px
    pub opacity: f32, // 0..1
}

#[derive(Serialize, Default)]
pub struct ImportedPage {
    pub title: String,
    /// The title box's date/time lines (e.g. "Tuesday, 29 July 2025\n8:05 AM"),
    /// for the importer to parse into the page's created timestamp. The title
    /// box itself is NOT emitted as a content box — Openote's page title band
    /// already renders the title and date.
    #[serde(skip_serializing_if = "String::is_empty")]
    pub date_text: String,
    pub boxes: Vec<PageBox>,
    pub images: Vec<ImportedImage>,
    pub ink: Vec<ImportedStroke>,
    /// Subpage indent level, 0-based (0 = top-level page, 1..2 = subpage).
    pub level: u32,
    /// Ink strokes that could not be decoded and were dropped (~0.02 % on the
    /// reference notebook). Counted so the app can SAY so — a silent drop reads
    /// as "my notes imported fine" when they did not quite.
    #[serde(skip_serializing_if = "is_zero")]
    pub dropped_strokes: u32,
}

#[derive(Serialize, Default)]
pub struct ImportedSection {
    pub ok: bool,
    pub error: Option<String>,
    pub pages: Vec<ImportedPage>,
}

/// Parse a `.one` section file into structured content, returned as JSON.
pub fn import_one_json(bytes: &[u8]) -> String {
    // Serialization runs INSIDE the guard: a panic while serializing would
    // otherwise unwind across the C ABI, which is undefined behaviour.
    std::panic::catch_unwind(|| {
        let section = import_one(bytes);
        serde_json::to_string(&section).unwrap_or_else(|_| "{\"ok\":false}".into())
    })
    .unwrap_or_else(|_| {
        "{\"ok\":false,\"error\":\"failed to parse .one (unexpected structure)\"}".into()
    })
}

pub(crate) fn import_one(bytes: &[u8]) -> ImportedSection {
    let r = Reader { d: bytes };
    // Validate the ONESTORE header magic (guidFileType = .one section).
    if bytes.len() < 1024 || !r.is_one_section() {
        return ImportedSection {
            ok: false,
            error: Some("not a OneNote .one section file".into()),
            pages: vec![],
        };
    }

    let root = r.fcr(172); // fcrFileNodeListRoot (FileChunkReference64x32)
    let mut wo = WalkOut::default();
    let mut visited = HashSet::new();
    let mut next_space = 0usize;
    let mut cur_rev = 0usize;
    let mut in_version = false;
    walk(
        &r, root, &mut wo, &mut visited, 0, 0, &mut next_space, &mut cur_rev,
        &mut in_version,
    );
    let objs = wo.objs;

    // ── Group objects by object space ──────────────────────────────────────
    // CompactIDs are per-space, and each page's content tree lives in its own
    // space. Directory spaces (no content root) carry the page titles.
    let mut spaces: std::collections::BTreeMap<usize, Vec<usize>> = Default::default();
    for (i, o) in objs.iter().enumerate() {
        spaces.entry(o.space).or_default().push(i);
    }

    // ── Definitive page order / titles / levels (MS-ONE section structure) ──
    // Directory space: SectionNode (0x1C20 → ordered PageSeries refs); each
    // PageSeries (0x1D63 page-space refs ‖ 0x3442 PageMetadata refs). Walk the
    // series in section order, and each series' pages in order, assigning a
    // running global ordinal — that is the tab order the user sees. Each page:
    // resolve its object-space ID (guidIndex high 24 | n low 8) through the
    // space's global-id table to a GUID, matched against the gosid captured for
    // every content space; then find the PageMetadata that names THAT page.
    //
    // The two arrays are NOT parallel. Reading the k-th metadata for the k-th
    // page space is what put other pages' titles on pages: 0x1D63 is the page
    // list in DISPLAY order, while 0x3442 keeps the order the metadata objects
    // were created, so moving a page inside a section leaves the arrays
    // permuted against each other. Measured on the reference notebook, **16 of
    // 329 pages** paired with the wrong metadata — "Dominance and Big-O
    // Notation" and "Uncountable Sets and Cantor's Diagonalisation Argument"
    // wore each other's titles, and five consecutive "Maths 1" pages were
    // rotated by one.
    //
    // The link that IS reliable is the page's own identity GUID: every page
    // object space carries a PageMetadata object (0x00020030) whose 0x1C30 is
    // that page's GUID, and the section directory's copy of that page's
    // metadata repeats it. Matching on the GUID reproduced the page's own title
    // outline on all 16 of those pages and disagreed with it on none.
    let mut space_meta: HashMap<usize, (String, u32, usize)> = HashMap::new();
    let mut global_ord = 0usize;
    for (&dir_sp, idxs) in &spaces {
        // A directory space is where the section node lives.
        let Some(&si) = idxs
            .iter()
            .filter(|&&i| objs[i].jcid == JCID_SECTION_NODE)
            .max_by_key(|&&i| currency(&objs[i]))
        else {
            continue;
        };
        let mut latest: HashMap<u32, usize> = HashMap::new();
        for &i in idxs {
            let e = latest.entry(objs[i].own_oid).or_insert(i);
            if currency(&objs[i]) > currency(&objs[*e]) {
                *e = i;
            }
        }
        let table = wo.gid_tables.get(&dir_sp);
        let section = read_propset(&r, objs[si].stp, objs[si].cb);
        // Pass 1: the section's pages in display order — each with its own
        // identity GUID and with the metadata the positional pairing would give
        // it — plus every metadata object the page series reference. Only
        // referenced metadata goes in, so a re-pairing can never pull in a
        // title from outside the section's own page list.
        let mut page_list: Vec<(Option<[u8; 16]>, Option<usize>)> = Vec::new();
        let mut page_spaces_in_order: Vec<usize> = Vec::new();
        let mut metas: Vec<([u8; 16], usize)> = Vec::new();
        for series_oid in section.oids(PID_ELEMENT_CHILDREN) {
            let Some(&pi) = latest.get(&series_oid) else { continue };
            if objs[pi].jcid != JCID_PAGE_SERIES {
                continue;
            }
            let series = read_propset(&r, objs[pi].stp, objs[pi].cb);
            let page_spaces = series.osids(PID_PAGE_SPACES);
            let page_metas = series.oids(PID_PAGE_METADATA);
            for oid in &page_metas {
                let Some(&mi) = latest.get(oid) else { continue };
                if let Some(g) = page_guid(&r, &objs[mi]) {
                    metas.push((g, mi));
                }
            }
            for (k, osid) in page_spaces.iter().enumerate() {
                let (n, gidx) = (osid & 0xFF, osid >> 8);
                let Some(guid) = table.and_then(|t| t.get(&gidx)) else {
                    continue;
                };
                let Some((&sp, _)) = wo.space_gosids.iter().find(|(_, g)| {
                    &g[..16] == guid.as_slice()
                        && u32::from_le_bytes([g[16], g[17], g[18], g[19]]) == n
                }) else {
                    continue;
                };
                // The page's own copy of its PageMetadata — its identity.
                let own = spaces
                    .get(&sp)
                    .and_then(|page_idxs| {
                        page_idxs
                            .iter()
                            .filter(|&&i| objs[i].jcid == JCID_PAGE_METADATA)
                            .max_by_key(|&&i| currency(&objs[i]))
                    })
                    .and_then(|&i| page_guid(&r, &objs[i]));
                page_spaces_in_order.push(sp);
                page_list.push((own, page_metas.get(k).and_then(|oid| latest.get(oid)).copied()));
            }
        }
        // Pass 2: title + level from the metadata that names THIS page.
        for (&sp, chosen) in page_spaces_in_order
            .iter()
            .zip(pair_page_metadata(&metas, &page_list))
        {
            let (mut title, mut level) = (String::new(), 0u32);
            if let Some(mi) = chosen {
                let ps = read_propset(&r, objs[mi].stp, objs[mi].cb);
                title = ps.utf16(PID_TITLE).unwrap_or_default();
                // OneNote PageLevel is 1-based (1 = top-level page, 2/3 =
                // sub/sub-sub). Openote's subpage indent is 0-based, so
                // shift down; a missing level defaults to top-level.
                level = ps.u32(PID_PAGE_LEVEL).unwrap_or(1).saturating_sub(1).min(2);
            }
            space_meta.insert(sp, (title, level, global_ord));
            global_ord += 1;
        }
    }

    // Unique PNGs recovered from the file data store, matched to image objects
    // below by natural pixel size (±2px).
    struct Png {
        bytes: Vec<u8>,
        /// The type the BYTES are, not an assumption — the Dart side stores it
        /// as the blob's mime, and a JPEG announced as PNG renders as nothing.
        mime: &'static str,
        w: u32,
        h: u32,
        used: bool,
    }
    let mut pngs: Vec<Png> = Vec::new();
    let mut seen_png = HashSet::new();
    for img in scan_images(bytes) {
        // Content hash, not (len, first byte, last byte): every PNG starts with
        // 0x89, so that key was effectively (len, last CRC byte) and two
        // same-length images collided ~1/256 of the time, silently dropping one.
        if !seen_png.insert(crate::ids::content_hash(&img.bytes)) {
            continue;
        }
        let (w, h) = if img.mime == "image/png" {
            png_dimensions(&img.bytes)
        } else {
            jpeg_dimensions(&img.bytes)
        };
        pngs.push(Png { bytes: img.bytes, mime: img.mime, w, h, used: false });
    }

    // OneNote's stored offsets are absolute in its own page space, whose origin
    // includes the title area — the same layout Openote's page presents. Trust
    // them verbatim (adding our own margin on top double-shifts everything).
    const MX: f32 = 0.0;
    const MY: f32 = 0.0;
    /// Fallback stacking start (below Openote's title band).
    const CONTENT_TOP: f32 = 92.0;
    /// What one dropped leading blank paragraph is worth in y. The same 22px
    /// pitch [emit_boxes] costs every other source line at, and within half a
    /// pixel of what OneNote itself left for one: on the reference notebook the
    /// gap between an element with a leading blank and its blank-less siblings
    /// measures 22.38px (0.373 units) at 11pt.
    const BLANK_LINE_H: f32 = 22.0;
    // Collected as (display order, page); sorted after the loop.
    let mut pages: Vec<(usize, ImportedPage)> = Vec::new();
    let mut img_counter = 0usize;
    // Live image objects that found no pixel data. See the leftover-blob pass
    // at the end of the import.
    let mut unmatched_images = 0usize;

    // ── Canonical object identity across revisions ──────────────────────────
    // The global-id table is PER-REVISION, so the same CompactID names
    // different objects in different revisions (heavily-edited pages otherwise
    // lose their text). Map every object to its ExGuid (revision-resolved
    // GUID + n) → a canonical id; references resolve via the referencing
    // object's revision (see [Resolver]).
    let exg_of = |o: &Obj| -> Option<[u8; 20]> {
        let g = wo.rev_tables.get(o.rev)?.get(&(o.own_oid >> 8))?;
        let mut e = [0u8; 20];
        e[..16].copy_from_slice(g);
        e[16] = (o.own_oid & 0xFF) as u8;
        Some(e)
    };
    let mut registry: HashMap<[u8; 20], u32> = HashMap::new();
    for o in &objs {
        if let Some(e) = exg_of(o) {
            let n = registry.len() as u32;
            registry.entry(e).or_insert(n);
        }
    }
    let canon_of = |o: &Obj| -> Option<u32> { exg_of(o).map(|e| registry[&e] | CANON_BIT) };

    for (&sp, idxs) in &spaces {
        // Canonical (ExGuid) → the LATEST declaration of that object in this
        // space. Keying by ExGuid unifies an object's per-revision copies; the
        // Resolver turns any CompactID reference into the current object.
        let mut by_canon: HashMap<u32, usize> = HashMap::new();
        for &i in idxs {
            if let Some(c) = canon_of(&objs[i]) {
                let ent = by_canon.entry(c).or_insert(i);
                if currency(&objs[i]) > currency(&objs[*ent]) {
                    *ent = i;
                }
            }
        }
        let res = Resolver {
            objs: &objs,
            rev_tables: &wo.rev_tables,
            registry: &registry,
            by_canon,
        };

        // ── The one authority: what this space's LIVE root still reaches ─────
        // Text boxes, images, tables and ink were each collected by their own
        // flat scan of the object space, and each therefore resurrected its own
        // kind of deleted content — on ONE page of the reference notebook a
        // deleted note came back as the whole body, a deleted picture came back
        // beside it, and 121 erased ink containers came back under both. They
        // are found by different scans; they are dead for the same reason. Every
        // collector below now answers to this one set. `None` = the file gave us
        // no root we could resolve, and each collector falls back to the scan it
        // used before rather than emitting nothing.
        let anchor = live_anchor(&r, &res, wo.live_roots.get(&sp), &registry);

        let root_is = live_box_roots(&r, &res, idxs, anchor.as_ref());

        // Title/date: the title outline; its text feeds page metadata, never a box.
        let mut date_text = String::new();
        let mut title_plains: HashSet<String> = HashSet::new();
        if let Some(&ti) = idxs
            .iter()
            .filter(|&&i| objs[i].jcid == JCID_TITLE)
            .max_by_key(|&&i| currency(&objs[i]))
        {
            let mut lines = Vec::new();
            let mut guard = HashSet::new();
            collect_tree(&r, &objs[ti], &res, 0, &mut lines, &mut guard);
            let plains: Vec<String> = lines.iter().map(|l| l.plain()).collect();
            date_text = plains.join("\n");
            title_plains.extend(plains);
        }

        // ── Images first (boxes reference them inline by index) ──────────────
        // Absolute position = the offset chain up the parent tree (0x1C14/15
        // are offsets *from the parent*). An image that is NOT a direct child
        // of the page root is **in-flow** (a list item that is an image): it is
        // referenced from a box's markdown and rides the text flow.
        // Direct children of ANY outline container count as "placed at the page
        // root", which is what decides whether an image floats or rides a text
        // box's flow. Restricting this to one container mis-classified images in
        // every other container.
        let root_children: HashSet<u32> = {
            let mut set = HashSet::new();
            for &ri in &root_is {
                let ps = read_propset(&r, objs[ri].stp, objs[ri].cb);
                let rev = objs[ri].rev;
                for c in ps.oids(0x001C20) {
                    set.insert(res.canon(c, rev));
                }
            }
            set
        };
        // canonical child → canonical parent (offset chain).
        let mut parent: HashMap<u32, u32> = HashMap::new();
        for (&canon, &i) in &res.by_canon {
            let o = &objs[i];
            let (_t, kids) = parse_obj(&r, o.stp, o.cb);
            for k in kids {
                parent.entry(res.canon(k, o.rev)).or_insert(canon);
            }
        }
        let abs_offset = |canon: u32| -> Option<(f32, f32)> {
            let (mut x, mut y, mut cur, mut hops) = (0.0f32, 0.0f32, canon, 0);
            let mut any = false;
            loop {
                let i = *res.by_canon.get(&cur)?;
                let ps = read_propset(&r, objs[i].stp, objs[i].cb);
                if let Some(v) = ps.f32(PID_IMG_POSX) {
                    x += v;
                    any = true;
                }
                if let Some(v) = ps.f32(PID_IMG_POSY) {
                    y += v;
                    any = true;
                }
                match parent.get(&cur) {
                    Some(&p) if hops < 32 => {
                        cur = p;
                        hops += 1;
                    }
                    _ => break,
                }
            }
            any.then_some((x, y))
        };

        let mut images = Vec::new();
        let mut img_idx: HashMap<u32, String> = HashMap::new(); // canonical → placeholder
        let mut fallback_y = CONTENT_TOP;
        // Image objects (latest per canonical), in file order for determinism.
        let img_objs = live_objects(&res, idxs, JCID_IMAGE, anchor.as_ref());
        for (canon, i) in img_objs {
            let o = &objs[i];
            let ps = read_propset(&r, o.stp, o.cb);
            // Match the object to its PNG by ASPECT RATIO: the natural size
            // (0x34CD/CE) → pixel factor isn't constant across images (paste vs
            // insert give ~60 vs ~96 px/unit), so absolute-size matching leaves
            // most PNGs unclaimed (they then pile onto page 1). Aspect is
            // scale-invariant; a plausible-pixel-factor gate (PNG ≈ 40–130
            // px/unit) disambiguates same-aspect images and rejects thumbnails.
            let (nw_u, nh_u) = (
                ps.f32(PID_IMG_NATW).unwrap_or(0.0),
                ps.f32(PID_IMG_NATH).unwrap_or(0.0),
            );
            let obj_aspect = if nh_u > 0.1 { nw_u / nh_u } else { 0.0 };
            let best = pngs
                .iter()
                .enumerate()
                .filter(|(_, p)| !p.used && p.w > 0 && p.h > 0 && obj_aspect > 0.0)
                .filter(|(_, p)| {
                    let factor = p.w as f32 / nw_u;
                    (40.0..=130.0).contains(&factor)
                })
                .map(|(k, p)| {
                    let a = p.w as f32 / p.h as f32;
                    (k, (a - obj_aspect).abs() / obj_aspect)
                })
                .filter(|(_, d)| *d < 0.04)
                .min_by(|a, b| a.1.total_cmp(&b.1))
                .map(|(k, _)| k)
                // Fall back to exact absolute-size (a valid match when the
                // natural size already equals the PNG pixels).
                .or_else(|| {
                    let nw = (nw_u * UNIT_PX).round() as i64;
                    let nh = (nh_u * UNIT_PX).round() as i64;
                    pngs.iter().position(|p| {
                        !p.used && (nw - p.w as i64).abs() <= 2 && (nh - p.h as i64).abs() <= 2
                    })
                });
            let png = match best {
                Some(k) => &mut pngs[k],
                None => {
                    // A live image object whose pixels we did not recover. The
                    // only evidence that an unclaimed blob might still belong on
                    // a page — see the leftover pass after the loop.
                    unmatched_images += 1;
                    continue;
                }
            };
            png.used = true;
            let (mut dw, mut dh) = (png.w as f32, png.h as f32);
            if let Some(v) = ps.f32(PID_IMG_DISPW).filter(|v| *v * UNIT_PX > 1.0) {
                dw = v * UNIT_PX;
            }
            if let Some(v) = ps.f32(PID_IMG_DISPH).filter(|v| *v * UNIT_PX > 1.0) {
                dh = v * UNIT_PX;
            }
            let in_flow = !root_children.contains(&canon);
            let (x, y) = if in_flow {
                (0.0, 0.0) // position comes from the text flow, not coordinates
            } else {
                match abs_offset(canon) {
                    Some((ox, oy)) => (MX + ox * UNIT_PX, MY + oy * UNIT_PX),
                    None => {
                        let p = (720.0, fallback_y);
                        fallback_y += dh + 24.0;
                        p
                    }
                }
            };
            img_counter += 1;
            if std::env::var("ONOTE_IMG_DEBUG").is_ok() {
                eprintln!(
                    "IMG: in_flow={} own_posy={:?} own_posx={:?} abs={:?} disp={}x{} nat={}x{}",
                    in_flow,
                    ps.f32(PID_IMG_POSY),
                    ps.f32(PID_IMG_POSX),
                    abs_offset(canon),
                    dw.round(),
                    dh.round(),
                    png.w,
                    png.h
                );
            }
            // In-flow placeholder carries the DISPLAY size (` =WxH`) so the
            // renderer shows the image at OneNote's size, not natural pixels —
            // otherwise a user-resized image adds phantom height to the flow.
            img_idx.insert(
                canon,
                format!(
                    "![image](onote-img://{} ={}x{})",
                    images.len(),
                    dw.round() as i64,
                    dh.round() as i64
                ),
            );
            images.push(ImportedImage {
                // Extension follows the real type: the Dart side derives the
                // blob mime from it, and a JPEG named .png renders as nothing.
                name: format!("onenote-image-{img_counter}.{}", ext_of(png.mime)),
                x,
                y,
                disp_w: dw,
                disp_h: dh,
                width: png.w,
                height: png.h,
                in_flow,
                data_base64: base64_encode(&png.bytes),
            });
        }

        // ── Boxes: each root child is ONE box, kept unified — in-flow images
        // become `![image](onote-img://N)` lines inside the box's markdown
        // (the Dart importer rewrites N to the stored blob hash), so the text
        // and its images stay one OneNote-style container.
        let mut boxes: Vec<PageBox> = Vec::new();
        let mut stack_y = CONTENT_TOP; // fallback stacking for boxes without offsets
        let mut flow_id: u32 = 0;
        // One pass per outline container. `seen_box` guards against the same
        // paragraph object being reachable from two containers.
        let mut seen_box: HashSet<u32> = HashSet::new();
        // Containers that sit INSIDE another container's element. Their
        // paragraphs are already emitted, at OneNote's own coordinates, by the
        // outer container's walk — `live_box_roots` finds every outline and
        // outline group on the page, and a group nested under an
        // OutlineElement qualifies exactly like a page-level one.
        //
        // Walking a nested group as a page-level container emitted its
        // paragraphs a SECOND time. The duplicate carries no offsets of its own
        // (the position lives on the enclosing OutlineElement), so it fell to
        // `stack_y` at x = 0 and drew on top of the correctly-placed copy —
        // measured on the reference notebook, 55 such boxes across 21 pages,
        // every one of them line-for-line already present in another box on its
        // own page. `seen_box` cannot see it: the duplicate's target is the
        // RichText, the original's is the OutlineElement above it, and those are
        // two different canonical objects.
        //
        // Only the box walk is filtered. Images and ink are placed from
        // `abs_offset`, which sums the whole parent chain and is already right
        // for a nested group's children; `root_children` (which decides whether
        // an image floats or rides a text flow) keeps the unfiltered list.
        let nested_containers: HashSet<u32> = {
            let mut nested = HashSet::new();
            let mut seen: HashSet<u32> = HashSet::new();
            for &ri in &root_is {
                let rev = objs[ri].rev;
                // A CompactID only means anything inside the revision that
                // declared it, so the revision follows the object down the
                // tree (as `collect_inner` does). Resolving every level
                // against the ROOT's revision stopped the walk at the first
                // container declared in another one, and left its nested
                // groups looking page-level.
                let mut stack: Vec<(u32, usize)> = read_propset(&r, objs[ri].stp, objs[ri].cb)
                    .oids(0x001C20)
                    .into_iter()
                    .map(|c| (c, rev))
                    .collect();
                while let Some((cid, crev)) = stack.pop() {
                    let canon = res.canon(cid, crev);
                    if !seen.insert(canon) {
                        continue; // already walked (or a cycle)
                    }
                    let Some(ci) = res.get(cid, crev) else { continue };
                    let o = res.obj(ci);
                    match o.jcid {
                        JCID_OUTLINE | JCID_OUTLINE_GROUP => {
                            nested.insert(canon);
                        }
                        // Descend through elements and paragraphs, but no
                        // further: an indented sub-list hangs its group off the
                        // PARAGRAPH above it, and stopping at paragraphs left
                        // six such groups looking page-level. Everything else
                        // (ink, images, tables) is skipped, which is what keeps
                        // this cheap on the pages whose outline lists tens of
                        // thousands of ink containers.
                        JCID_OUTLINE_ELEMENT | JCID_RICHTEXT => {}
                        _ => continue,
                    }
                    stack.extend(
                        read_propset(&r, o.stp, o.cb)
                            .oids(0x001C20)
                            .into_iter()
                            .map(|c| (c, o.rev)),
                    );
                }
            }
            nested
        };
        let mut box_targets: Vec<(u32, usize)> = Vec::new();
        for &ri in &root_is {
            if res.own_canon(&objs[ri]).is_some_and(|c| nested_containers.contains(&c)) {
                continue;
            }
            let ps = read_propset(&r, objs[ri].stp, objs[ri].cb);
            let rev = objs[ri].rev;
            for cid in ps.oids(0x001C20) {
                box_targets.push((cid, rev));
            }
        }
        if std::env::var("ONOTE_WALK_DEBUG").is_ok() {
            let rt = idxs
                .iter()
                .filter(|&&i| matches!(objs[i].jcid, JCID_RICHTEXT | JCID_RICHTEXT_RUN))
                .count();
            let outlines = idxs
                .iter()
                .filter(|&&i| objs[i].jcid == JCID_OUTLINE)
                .filter(|&&i| {
                    !read_propset(&r, objs[i].stp, objs[i].cb)
                        .oids(0x001C20)
                        .is_empty()
                })
                .count();
            eprintln!(
                "PAGE: outline_containers={} used={} boxes_to_walk={} richtext_in_space={}",
                outlines,
                root_is.len(),
                box_targets.len(),
                rt
            );
        }
        for (cid, rev) in box_targets {
            let ci = match res.get(cid, rev) {
                Some(i) => i,
                None => continue,
            };
            if !seen_box.insert(res.canon(cid, rev)) {
                continue; // already emitted from another container
            }
            let child = res.obj(ci);
            if child.jcid == JCID_TITLE || child.jcid == JCID_IMAGE {
                continue; // title → metadata; floating images → handled above
            }
            let ps = read_propset(&r, child.stp, child.cb);
            let has_pos = ps.get(PID_IMG_POSX).is_some() || ps.get(PID_IMG_POSY).is_some();
            let x = MX + ps.f32(PID_IMG_POSX).unwrap_or(0.0) * UNIT_PX;
            let y = if has_pos {
                MY + ps.f32(PID_IMG_POSY).unwrap_or(0.0) * UNIT_PX
            } else {
                stack_y
            };
            let w = ps.f32(PID_IMG_DISPW).filter(|v| *v > 0.5).map(|v| v * UNIT_PX);
            let mut lines: Vec<Line> = Vec::new();
            let mut guard = HashSet::new();
            collect_tree(&r, child, &res, 0, &mut lines, &mut guard);
            // De-duplicate the title only where it is genuinely a duplicate:
            // the LEADING lines of the FIRST box. JCID_TITLE children are
            // already skipped above, so the old page-wide `retain` could only
            // ever delete real body text — a page whose body repeats its own
            // title as a heading (very common) silently lost that paragraph,
            // which then shifted everything below it.
            // A box commonly opens with an empty paragraph in the source.
            // Now that empties survive the walk, that would become a leading
            // blank line in every imported box (the trailing end is already
            // handled by `out.trim_end()` when the markdown is assembled).
            //
            // This runs BEFORE the title dedup below and again after it, and
            // the order is the whole point: with a blank line first, the
            // dedup's `lines.first()` was the blank, so it matched no title,
            // stopped immediately, and the duplicated title one line down
            // survived into the body — every such page then showed its title
            // twice, once in the title band and once as the first line.
            //
            // Dropping them has to be PAID FOR in y. OneNote's recorded offset
            // is the top of the element's FIRST line, blank or not, and the
            // content below it starts one line lower — so deleting the blank
            // while keeping the offset rides the real content up by a line, on
            // top of whatever OneNote put there. On "Natural Language and Intro
            // to Truth Tables" that is exactly what happened: the AND table's
            // element opens with an empty paragraph, so the table landed at
            // y=628.25 — its own caption's y — while the OR and NOT tables,
            // whose elements have no leading blank, sit correctly at 650.63,
            // one 22px line lower. The table drew straight through the word
            // "AND".
            let mut blank_lead = 0.0f32;
            let mut trim_leading_blanks = |lines: &mut Vec<Line>| {
                while lines.first().is_some_and(Line::is_blank) {
                    lines.remove(0);
                    blank_lead += BLANK_LINE_H;
                }
            };
            trim_leading_blanks(&mut lines);
            if boxes.is_empty() {
                // `!plain.trim().is_empty()` guards the blank lines that now
                // survive: an empty Line's `plain()` is "", and if the title
                // set ever held an empty string this loop would eat every
                // leading blank in the body as a "duplicate title".
                while lines.first().is_some_and(|l| {
                    let plain = l.plain();
                    l.image.is_none()
                        && !plain.trim().is_empty()
                        && title_plains.contains(&plain)
                }) {
                    lines.remove(0);
                }
            }
            // Again: a blank commonly sits between the repeated title and the
            // body, and removing the title would otherwise expose it.
            trim_leading_blanks(&mut lines);
            if lines.is_empty() {
                continue;
            }
            // One flow per container: the app re-stacks each flow's boxes using
            // real text measurement (see `PageBox::flow`). Ids start at 1 so 0
            // stays "not in a flow".
            flow_id += 1;
            let end_y = emit_boxes(&lines, x, y + blank_lead, w, &mut boxes, &img_idx, flow_id);
            stack_y = stack_y.max(end_y) + 24.0;
        }

        // Drop boxes whose content we already emitted. Reaching a paragraph
        // through two container paths can yield two CompactIDs that don't
        // canonicalise to the same id, so `seen_box` alone can't always tell —
        // but identical rendered content is unambiguous. Only substantial boxes
        // are compared, so two genuinely repeated short labels survive.
        {
            let mut seen_content: HashSet<String> = HashSet::new();
            boxes.retain(|b| {
                let key = format!("{}|{}|{:?}", b.markdown, b.latex, b.cells);
                if key.chars().filter(|c| !c.is_whitespace()).count() < 20 {
                    return true;
                }
                seen_content.insert(key)
            });
        }

        // Tables that no outline reached. A table can hang off a container the
        // outline walk never visits, in which case its whole grid — often the
        // bulk of the page — simply vanished. Emitting the leftovers is strictly
        // better than losing them: worst case the position is approximate,
        // whereas the alternative is silent data loss. `by_canon` gives the
        // latest declaration of each table, and `seen_tables` covers the ones
        // already emitted in the flow above.
        {
            // Already-emitted grids, compared by content: cheaper and more
            // robust than threading a "seen" set through the recursive walk, and
            // a table that really is duplicated on a page is duplicated content
            // we would not want twice anyway.
            let emitted: Vec<Vec<Vec<String>>> = boxes
                .iter()
                .filter(|b| b.kind == "table")
                .map(|b| b.cells.clone())
                .collect();
            // "No outline reached it" must not mean "the page does not have
            // it": a deleted table is unreachable for the same reason erased ink
            // is, and this pass would put it back. Measured on the reference
            // notebook this changes nothing — all 22 tables the pass considers
            // are live — but the mechanism is the one that resurrected
            // everything else.
            for (_, i) in live_objects(&res, idxs, JCID_TABLE, anchor.as_ref()) {
                let grid = parse_table(&r, &objs[i], &res, &img_idx);
                if grid.is_empty() || emitted.contains(&grid.cells) {
                    continue;
                }
                let rows = grid.cells.len() as f32;
                boxes.push(PageBox {
                    tags: Vec::new(),
kind: "table".into(),
                    x: MX,
                    y: stack_y,
                    w: table_width(&grid),
                    markdown: String::new(),
                    latex: String::new(),
                    cells: grid.cells,
                    col_w: grid.col_w,
                    flow: 0,
                    font: None,
                    font_size_pt: None,
                });
                stack_y += rows * 33.0 + 44.0;
            }
        }

        // ── Ink: container → data node → stroke nodes → packed paths ────────
        let mut ink: Vec<ImportedStroke> = Vec::new();
        let mut dropped_strokes: u32 = 0;
        // Without an anchor, fall back to what this page had before: reachable
        // from the outline containers the scan found. Anchoring on the page's
        // own root is strictly better — a scan can land on a stale declaration,
        // and on "Working out" it did — but a page whose root we cannot read
        // must keep its ink rather than silently lose all of it.
        let ink_live = match &anchor {
            Some(a) => Some(a.clone()),
            None => (!root_is.is_empty()).then(|| reachable_canons(&r, &res, &root_is)),
        };
        for i in live_ink_containers(&res, idxs, ink_live.as_ref()) {
            let o = &objs[i];
            let cps = read_propset(&r, o.stp, o.cb);
            // Ink-space → half-inch page units. When the container carries no
            // explicit scaling, raw units are HIMETRIC-like (2540/inch →
            // 1270 per half-inch), verified against a real file's layout.
            const DEFAULT_INK_SCALE: f32 = 1.0 / 1270.0;
            let scale_x = cps.f32(PID_INK_SCALING_X).unwrap_or(DEFAULT_INK_SCALE);
            let scale_y = cps.f32(PID_INK_SCALING_Y).unwrap_or(DEFAULT_INK_SCALE);
            // Page offset: the container's own offsets plus its ancestors'.
            let (bx, by) = canon_of(o).and_then(abs_offset).unwrap_or((0.0, 0.0));
            for data_oid in cps.oids(PID_INK_DATA_REF) {
                let Some(di) = res.get(data_oid, o.rev) else { continue };
                if objs[di].jcid != JCID_INK_DATA {
                    continue; // ref must land on an InkDataNode
                }
                let dps = read_propset(&r, objs[di].stp, objs[di].cb);
                let data_rev = objs[di].rev;
                for stroke_oid in dps.oids(PID_INK_STROKES) {
                    let Some(si) = res.get(stroke_oid, data_rev) else { continue };
                    if objs[si].jcid != JCID_INK_STROKE {
                        continue;
                    }
                    let sps = read_propset(&r, objs[si].stp, objs[si].cb);
                    let stroke_rev = objs[si].rev;
                    let Some(PVal::Str(path_bytes)) = sps.get(PID_INK_PATH) else {
                        continue;
                    };
                    let Some(path) = decode_multibyte_signed(path_bytes) else {
                        continue;
                    };
                    // Stroke properties: dimensions, pen size, colour, alpha.
                    let (mut idx_x, mut idx_y, mut idx_p) = (0usize, 1usize, None);
                    let mut ndims = 2usize;
                    let mut p_limits = (0i64, 0i64);
                    let mut size_px = 2.2f32;
                    let mut color = String::from("auto"); // themed unless stored
                    let mut opacity = 1.0f32;
                    let mut table_valid = false;
                    if let Some(pi) = sps
                        .oids(PID_INK_STROKE_PROPS)
                        .first()
                        .and_then(|&d| res.get(d, stroke_rev))
                    {
                        let pps = read_propset(&r, objs[pi].stp, objs[pi].cb);
                        if let Some(PVal::Str(dims)) = pps.get(PID_INK_DIMENSIONS) {
                            let entries: Vec<&[u8]> = dims.chunks_exact(32).collect();
                            if entries.len() >= 2 {
                                table_valid = true;
                                ndims = entries.len();
                                for (k, e) in entries.iter().enumerate() {
                                    let guid = &e[..16];
                                    let lo =
                                        i32::from_le_bytes([e[16], e[17], e[18], e[19]]) as i64;
                                    let hi =
                                        i32::from_le_bytes([e[20], e[21], e[22], e[23]]) as i64;
                                    if guid == DIM_X {
                                        idx_x = k;
                                    } else if guid == DIM_Y {
                                        idx_y = k;
                                    } else if guid == DIM_P {
                                        idx_p = Some(k);
                                        p_limits = (lo, hi);
                                    }
                                }
                            }
                        }
                        // Pen size, HIMETRIC (0.01 mm) → page px at 120 dpi.
                        // OneNote renders its pens visually ~2× their nominal
                        // tip width (a 0.25 mm pen paints ~2.4 px, not 1.2),
                        // and the painter's pressure thinning multiplies the
                        // width down further — without the 2× and a legible
                        // floor, imported handwriting came out as sub-pixel
                        // hairlines that read as "no ink at all".
                        let hm = pps
                            .f32(PID_INK_WIDTH)
                            .into_iter()
                            .chain(pps.f32(PID_INK_HEIGHT))
                            .fold(0.0f32, f32::max);
                        if hm > 0.0 {
                            size_px = (hm * 120.0 / 2540.0 * 2.0).clamp(1.8, 24.0);
                        }
                        if let Some(c) = pps.u32(PID_INK_COLOR) {
                            // COLORREF: 0x00BBGGRR.
                            let (cr, cg, cb) = (c & 0xFF, (c >> 8) & 0xFF, (c >> 16) & 0xFF);
                            color = format!("#{cr:02X}{cg:02X}{cb:02X}");
                        }
                        if let Some(t) = pps.u32(PID_INK_TRANSPARENCY) {
                            opacity = (t.min(255) as f32 / 255.0).clamp(0.05, 1.0);
                        }
                    }
                    // Cumulative X/Y span in PAGE PIXELS (scale-aware) for a
                    // candidate layout — the wrong channel split makes X bleed
                    // into Y and the cumsum run away across the page (the "giant
                    // scribble"). Pixels, not raw units, so a page with a large
                    // ink-scaling factor is judged on what actually renders.
                    let span_of = |nd: usize, ix: usize, iy: usize| -> f32 {
                        if nd == 0 || path.is_empty() || path.len() % nd != 0 {
                            return f32::MAX;
                        }
                        let per = path.len() / nd;
                        let ch = |idx: usize, sc: f32| -> f32 {
                            let mut a = 0i64;
                            let (mut lo, mut hi) = (i64::MAX, i64::MIN);
                            for &v in &path[idx * per..(idx + 1) * per] {
                                a += v;
                                lo = lo.min(a);
                                hi = hi.max(a);
                            }
                            if hi < lo { 0.0 } else { (hi - lo) as f32 * sc.abs() * UNIT_PX }
                        };
                        ch(ix.min(nd - 1), scale_x).max(ch(iy.min(nd - 1), scale_y))
                    };
                    // Sane maximum stroke span in px; beyond this the decode is
                    // wrong, not a genuinely huge stroke.
                    const SANE_MAX: f32 = 3200.0;
                    // Trust the dimension table only if its layout is compact.
                    let table_ok = table_valid
                        && path.len() % ndims == 0
                        && span_of(ndims, idx_x, idx_y) < SANE_MAX;
                    if !table_ok {
                        // Infer the channel count by compactness: X,Y are the
                        // first two channels; a 3rd is pressure (no limits to
                        // normalise, so it's dropped).
                        let (s3, s2) = (span_of(3, 0, 1), span_of(2, 0, 1));
                        ndims = if s3 <= s2 && s3.is_finite() {
                            3
                        } else if s2.is_finite() {
                            2
                        } else {
                            dropped_strokes += 1; // no usable channel split
                            continue;
                        };
                        idx_x = 0;
                        idx_y = 1;
                        idx_p = None;
                    }
                    // Final guard: a stroke that still spans absurdly is
                    // undecodable — drop it rather than paint a page-crossing
                    // scribble (a handful per notebook; better lost than wrong).
                    if span_of(ndims, idx_x, idx_y) > SANE_MAX {
                        dropped_strokes += 1;
                        continue;
                    }
                    let per = path.len() / ndims;
                    // Each dimension block is delta-encoded: an absolute first
                    // value, then per-point deltas — cumulative-sum to recover
                    // the real coordinates (MS-ISF delta encoding).
                    let cumsum = |idx: usize| -> Vec<i64> {
                        let mut acc = 0i64;
                        path[idx * per..(idx + 1) * per]
                            .iter()
                            .map(|&v| {
                                acc += v;
                                acc
                            })
                            .collect()
                    };
                    let xs: Vec<f32> = cumsum(idx_x)
                        .into_iter()
                        .map(|v| MX + (bx + v as f32 * scale_x) * UNIT_PX)
                        .collect();
                    let ys: Vec<f32> = cumsum(idx_y)
                        .into_iter()
                        .map(|v| MY + (by + v as f32 * scale_y) * UNIT_PX)
                        .collect();
                    let ps: Vec<f32> = match idx_p {
                        Some(k) if p_limits.1 > p_limits.0 => cumsum(k)
                            .into_iter()
                            .map(|v| {
                                ((v - p_limits.0) as f32 / (p_limits.1 - p_limits.0) as f32)
                                    .clamp(0.05, 1.0)
                            })
                            .collect(),
                        _ => Vec::new(),
                    };
                    if std::env::var("ONOTE_INK_DEBUG").is_ok() {
                        let sx = xs.iter().cloned().fold(f32::MIN, f32::max)
                            - xs.iter().cloned().fold(f32::MAX, f32::min);
                        let sy = ys.iter().cloned().fold(f32::MIN, f32::max)
                            - ys.iter().cloned().fold(f32::MAX, f32::min);
                        if sx.max(sy) > 700.0 {
                            let dims: Vec<u8> = sps
                                .oids(PID_INK_STROKE_PROPS)
                                .first()
                                .and_then(|&d| res.get(d, stroke_rev))
                                .map(|pi| {
                                    let pps = read_propset(&r, objs[pi].stp, objs[pi].cb);
                                    match pps.get(PID_INK_DIMENSIONS) {
                                        Some(PVal::Str(dd)) => (dd.len() / 32) as u8,
                                        _ => 0,
                                    }
                                })
                                .into_iter()
                                .collect();
                            eprintln!(
                                "RUNAWAY vals={} ndims={ndims} idx_x={idx_x} idx_y={idx_y} idx_p={idx_p:?} dimtable={dims:?} span=({sx:.0},{sy:.0})",
                                path.len()
                            );
                        }
                    }
                    ink.push(ImportedStroke { x: xs, y: ys, p: ps, color: color.clone(), size: size_px, opacity });
                }
            }
        }

        // Identity from the gosid correlation: title, subpage level, and
        // display order all come from THIS space's entry in the section's page
        // list — no ordinal guessing. A page listed there imports even when we
        // recovered no content (an empty page beats a silently missing one);
        // an unlisted space with no content is skipped.
        let meta = space_meta.get(&sp);
        if boxes.is_empty() && images.is_empty() && ink.is_empty() && meta.is_none() {
            continue;
        }
        let title = meta
            .map(|m| m.0.clone())
            .filter(|t| !t.is_empty())
            // Fallback: the on-page title box's first line (same text the tab
            // shows) — better than a generic label when correlation misses.
            // The first NON-BLANK line, not simply the first. Now that empty
            // paragraphs survive the walk, a title box that opens with one —
            // which is common — handed this an empty string, so the page fell
            // through to the generic label and lost its real name.
            .or_else(|| {
                date_text
                    .lines()
                    .map(|s| s.trim())
                    .find(|s| !s.is_empty())
                    .map(|s| s.to_string())
            })
            .unwrap_or_else(|| "Imported page".into());
        let level = meta.map(|m| m.1).unwrap_or(0);
        let ord = meta.map(|m| m.2).unwrap_or(usize::MAX);
        pages.push((ord, ImportedPage { title, date_text, boxes, images, ink, level, dropped_strokes }));
    }

    // Sort by the section's display order; unmatched pages keep file order at
    // the end.
    let mut keyed: Vec<(usize, usize, ImportedPage)> = pages
        .into_iter()
        .enumerate()
        .map(|(i, (ord, p))| (ord, i, p))
        .collect();
    keyed.sort_by_key(|(ord, i, _)| (*ord, *i));
    let mut pages: Vec<ImportedPage> = keyed.into_iter().map(|(_, _, p)| p).collect();

    // PNGs no image object claimed. A blob is in the file's data store whether
    // or not any page still shows it, so the leftovers are mostly pictures that
    // were deleted years ago — dumping them all on page 1 put 11 of them across
    // three sections of the reference notebook, including 8 photos stacked 4000
    // pixels down "Maths 1"'s otherwise-empty divider page.
    //
    // But the leftovers are also where a LIVE image lands when the object→blob
    // match fails, and losing a picture the user still has is the worse error.
    // So the evidence decides: while every live image object found its pixels
    // (measured: all 365 of them), nothing on any page is missing and the
    // leftovers are dead. Let one live image go unmatched and the whole
    // leftover pile comes back, exactly as before.
    if unmatched_images > 0 {
        if let Some(first) = pages.first_mut() {
            let mut fy = 40.0f32;
            for p in pngs.iter().filter(|p| !p.used) {
                img_counter += 1;
                first.images.push(ImportedImage {
                    name: format!("onenote-image-{img_counter}.{}", ext_of(p.mime)),
                    x: 980.0,
                    y: fy,
                    disp_w: p.w as f32,
                    disp_h: p.h as f32,
                    width: p.w,
                    height: p.h,
                    in_flow: false,
                    data_base64: base64_encode(&p.bytes),
                });
                fy += p.h as f32 + 24.0;
            }
        }
    }

    if pages.is_empty() {
        return ImportedSection {
            ok: false,
            error: Some("no recognizable page content found".into()),
            pages: vec![],
        };
    }
    ImportedSection { ok: true, error: None, pages }
}

/// Turn one outline's lines into boxes. The outline stays ONE unified text box
/// — in-flow images become `![image](onote-img://N)` markdown lines inside it
/// (rendered in the flow by Openote's text renderer, exactly as OneNote keeps
/// an image as a list item). Only math paragraphs split out, becoming their own
/// math box beside the text (as in OneNote, where an equation is a distinct
/// object). Returns the y just below the last emitted box (fallback stacking).
/// Flow height of one line. Text is a single line-pitch, but an in-flow image
/// occupies its whole display height: counting a 200px picture as one 22px text
/// line under-measured the box by an order of magnitude, so every stacked box
/// below it rode up into the image. The display size is already encoded in the
/// placeholder (` =WxH`), which is the only place it survives to here.
fn line_flow_h(l: &Line, img_idx: &HashMap<u32, String>) -> f32 {
    const LINE_H: f32 = 22.0;
    let Some(oid) = l.image else {
        return LINE_H;
    };
    img_idx
        .get(&oid)
        .and_then(|p| p.rsplit_once(" ="))
        .and_then(|(_, wh)| wh.trim_end_matches(')').split_once('x'))
        .and_then(|(_, h)| h.parse::<f32>().ok())
        .filter(|h| h.is_finite())
        .unwrap_or(LINE_H)
        .max(LINE_H)
}

fn emit_boxes(
    lines: &[Line],
    x: f32,
    y: f32,
    w: Option<f32>,
    out: &mut Vec<PageBox>,
    img_idx: &HashMap<u32, String>,
    flow: u32,
) -> f32 {
    const LINE_H: f32 = 22.0;
    let mut cy = y;
    let mut seg: Vec<&Line> = Vec::new();
    // Depth base for the WHOLE outline, not per segment: flushing at every
    // math/table line used to re-normalise each segment against its own
    // minimum, so a segment consisting only of deep lines was pulled back to
    // the left margin — indent lost exactly where the page mixed prose with
    // equations.
    let base_depth = lines
        .iter()
        .filter(|l| l.math.is_none() && l.table.is_none() && !l.is_blank())
        .map(|l| l.depth)
        .min()
        .unwrap_or(0);
    // A nested helper threading the enclosing function's own parameters; the
    // count is the price of not capturing `out` mutably in a closure.
    #[allow(clippy::too_many_arguments)]
    fn flush(
        seg: &mut Vec<&Line>,
        x: f32,
        w: Option<f32>,
        cy: &mut f32,
        out: &mut Vec<PageBox>,
        img_idx: &HashMap<u32, String>,
        flow: u32,
        base_depth: usize,
    ) {
        if seg.is_empty() {
            return;
        }
        let (md, tags) = outline_markdown_tagged(seg, img_idx, Some(base_depth));
        if !md.trim().is_empty() {
            out.push(PageBox {
                kind: "text".into(),
                tags,
                x,
                y: *cy,
                w,
                markdown: md,
                latex: String::new(),
                cells: Vec::new(),
                col_w: Vec::new(),
                flow,
                font: dominant_font(seg),
                font_size_pt: dominant_size(seg),
            });
            *cy += seg.iter().map(|l| line_flow_h(l, img_idx)).sum::<f32>() + 14.0;
        }
        seg.clear();
    }
    for l in lines {
        if let Some(grid) = &l.table {
            flush(&mut seg, x, w, &mut cy, out, img_idx, flow, base_depth);
            let rows = grid.cells.len() as f32;
            out.push(PageBox {
                tags: Vec::new(),
kind: "table".into(),
                x,
                y: cy,
                w: table_width(grid),
                markdown: String::new(),
                latex: String::new(),
                cells: grid.cells.clone(),
                col_w: grid.col_w.clone(),
                flow,
                font: None,
                font_size_pt: None,
            });
            // Advance the flow by the table's own height so whatever follows
            // keeps its spacing (one row ≈ 1.5 text lines, plus chrome).
            cy += rows * LINE_H * 1.5 + 20.0;
            continue;
        }
        if let Some(latex) = &l.math {
            flush(&mut seg, x, w, &mut cy, out, img_idx, flow, base_depth);
            out.push(PageBox {
                tags: Vec::new(),
kind: "math".into(),
                x: x + 24.0,
                y: cy,
                w: None,
                markdown: String::new(),
                latex: latex.clone(),
                cells: Vec::new(),
                col_w: Vec::new(),
                flow,
                font: None,
                font_size_pt: None,
            });
            cy += 48.0;
        } else {
            seg.push(l); // text AND in-flow image lines stay in the one box
        }
    }
    flush(&mut seg, x, w, &mut cy, out, img_idx, flow, base_depth);
    cy
}

// ── ONESTORE container walk ────────────────────────────────────────────────

struct Reader<'a> {
    d: &'a [u8],
}
impl<'a> Reader<'a> {
    fn u8(&self, o: usize) -> u8 {
        self.d.get(o).copied().unwrap_or(0)
    }
    // Bounds use `checked_add` so a hostile offset near usize::MAX can't wrap
    // past the length check into an out-of-bounds slice (review M2). Every
    // multi-byte read on untrusted `.one` bytes funnels through these three.
    fn u16(&self, o: usize) -> u16 {
        match o.checked_add(2) {
            Some(e) if e <= self.d.len() => u16::from_le_bytes([self.d[o], self.d[o + 1]]),
            _ => 0,
        }
    }
    fn u32(&self, o: usize) -> u32 {
        match o.checked_add(4) {
            Some(e) if e <= self.d.len() => {
                u32::from_le_bytes([self.d[o], self.d[o + 1], self.d[o + 2], self.d[o + 3]])
            }
            _ => 0,
        }
    }
    fn u64(&self, o: usize) -> u64 {
        match o.checked_add(8) {
            Some(e) if e <= self.d.len() => {
                let mut b = [0u8; 8];
                b.copy_from_slice(&self.d[o..o + 8]);
                u64::from_le_bytes(b)
            }
            _ => 0,
        }
    }
    fn fcr(&self, o: usize) -> Fcr {
        Fcr { stp: self.u64(o), cb: self.u32(o + 8) }
    }
    fn is_one_section(&self) -> bool {
        // guidFileType {7B5C52E4-D88C-4DA7-AEB1-5378D02996D3}
        const GUID: [u8; 16] = [
            0xe4, 0x52, 0x5c, 0x7b, 0x8c, 0xd8, 0xa7, 0x4d, 0xae, 0xb1, 0x53, 0x78, 0xd0, 0x29,
            0x96, 0xd3,
        ];
        self.d.len() >= 16 && self.d[..16] == GUID
    }
}

#[derive(Clone, Copy)]
struct Fcr {
    stp: u64,
    cb: u32,
}
impl Fcr {
    fn is_nil(&self) -> bool {
        self.stp == u64::MAX || (self.stp == 0 && self.cb == 0)
    }
}

/// One object: its own CompactID (for reference resolution), its type, the
/// location of its property set, and the **object space** it belongs to.
/// CompactIDs are only unique within a space (MS-ONESTORE): resolving them
/// globally collapses every page's identically-numbered objects into one tree —
/// the bug that used to merge all pages/boxes into a single outline.
struct Obj {
    own_oid: u32,
    jcid: u32,
    stp: usize,
    cb: usize,
    space: usize,
    /// Which revision's global-id table this object's CompactIDs resolve
    /// against. The gid table is PER-REVISION (a page edited N times has N
    /// tables), so the same CompactID means different objects in different
    /// revisions — resolving globally mixes them (lost text on revised pages).
    rev: usize,
    /// This declaration belongs to a revision that carries a **revision
    /// context** — a stored PAGE VERSION, not the page as it stands. See
    /// [FNID_REV_MANIFEST_START7].
    versioned: bool,
}

/// How current a declaration of an object is; the greatest wins.
///
/// File offset alone was the whole answer, and it is the wrong one: ONESTORE is
/// a revision store over a free-chunk allocator, so "further down the file" is
/// not "newer", and OneNote's page-version snapshots are interleaved with live
/// content. Live content therefore outranks every version snapshot, and file
/// order only breaks ties within one of those two groups.
fn currency(o: &Obj) -> (bool, usize) {
    (!o.versioned, o.stp)
}

/// FileNode ID that introduces a new object space's manifest list
/// (ObjectSpaceManifestListReferenceFND, MS-ONESTORE §2.5.2). Recursing through
/// one of these means "everything below is a different object space".
const FNID_OBJECT_SPACE_LIST_REF: u16 = 0x008;
/// GlobalIdTableStartFNDX / …Start2FND — begin a new revision's gid table.
const FNID_GID_TABLE_START: u16 = 0x021;
const FNID_GID_TABLE_START2: u16 = 0x022;
/// GlobalIdTableEntryFNDX: `{ index: u32, guid: [u8;16] }` — maps a CompactID's
/// guidIndex to a real GUID within the current revision.
const FNID_GID_TABLE_ENTRY: u16 = 0x024;
/// GlobalIdTableEntry2FNDX: `{ from: u32, to: u32 }` — copy one entry from the
/// dependency (previous) revision's table into this one.
const FNID_GID_TABLE_ENTRY2: u16 = 0x025;
/// GlobalIdTableEntry3FNDX: `{ from_start: u32, count: u32, to_start: u32 }` —
/// bulk-copy a range of entries from the previous table.
const FNID_GID_TABLE_ENTRY3: u16 = 0x026;

/// RevisionManifestStart4FND / …6FND — a revision with NO revision context:
/// the object space as it currently stands.
const FNID_REV_MANIFEST_START4: u16 = 0x01B;
const FNID_REV_MANIFEST_START6: u16 = 0x01E;
/// RevisionManifestStart7FND — a 6FND **plus a `gctxid`** (revision context).
///
/// This is OneNote's page-version history, and reading it as content is how a
/// page loses a whole section. A revision context names a stored *past* state
/// of the object space; the space as it stands is the one revision whose
/// manifest declares no context at all. Measured on the reference notebook:
/// every one of its 56 object spaces has **exactly one** context-free manifest
/// and up to five context-bearing ones, and the context-bearing revisions are
/// scattered through the file — the last one physically is routinely not the
/// newest logically, because ONESTORE is a revision store with a free-chunk
/// allocator. Picking the declaration with the highest file offset therefore
/// resurrected an arbitrary old version: on "Logic: Tautologies…" it replaced
/// the outline's 21-paragraph child list with an 18-paragraph one from a
/// version snapshot, deleting the page's last five lines.
const FNID_REV_MANIFEST_START7: u16 = 0x01F;
/// RevisionManifestEndFND — closes the manifest opened above.
const FNID_REV_MANIFEST_END: u16 = 0x01C;
/// RootObjectReference3FND (MS-ONESTORE): `{ oidRoot: ExtendedGUID(20),
/// RootRole: u32 }`. A revision manifest names its own roots with these — the
/// file's own answer to "what does this revision consider the top of the tree",
/// which the importer used to guess at by scanning the space for outline
/// declarations instead. Read from the manifest with no revision context, it
/// names the LIVE root. See [live_anchor].
const FNID_ROOT_OBJECT_REF3: u16 = 0x05A;
/// Body offset of `RootRole` inside a RootObjectReference3FND: after the
/// 20-byte ExtendedGUID.
const ROOT_REF3_ROLE_OFFSET: usize = 20;
/// The RootRole that names an object space's CONTENT root. Measured on the
/// reference notebook: role 1 resolves to a PageNode on all 329 pages and to a
/// SectionNode on all 25 section directories, with no space naming two. The
/// other roles name the page's metadata and the revision's, and anchoring on
/// either of those would reach no content at all.
const ROOT_ROLE_CONTENT: u32 = 1;
/// Body offset of `gctxid` inside a RevisionManifestStart7FND: rid (20) +
/// ridDependent (20) + RevisionRole (4) + odcsDefault (2).
const REV7_GCTXID_OFFSET: usize = 46;

/// Everything the file-node walk collects.
#[derive(Default)]
struct WalkOut {
    objs: Vec<Obj>,
    /// space index → the space's ExtendedGUID (16-byte GUID + 4-byte n), from
    /// the ObjectSpaceManifestListReferenceFND body. This is the identity that
    /// page-series ObjectSpaceID references resolve to.
    space_gosids: HashMap<usize, [u8; 20]>,
    /// space index → its global-id table (guidIndex → GUID), accumulated
    /// across revisions (later entries overwrite). Used for the section→page
    /// object-space correlation (the directory spaces are single-revision).
    gid_tables: HashMap<usize, HashMap<u32, [u8; 16]>>,
    /// PER-REVISION global-id tables (guidIndex → GUID). `objs[i].rev` indexes
    /// this; a CompactID on that object resolves via `rev_tables[rev]`.
    rev_tables: Vec<HashMap<u32, [u8; 16]>>,
    /// space index → every role-1 root ExtendedGUID declared by a revision
    /// manifest of that space that carries NO revision context, i.e. the space
    /// as it currently stands. See [FNID_ROOT_OBJECT_REF3] and [live_anchor].
    live_roots: HashMap<usize, Vec<[u8; 20]>>,
}

/// Walk the file-node graph, collecting every object declaration as an [Obj]
/// tagged with its object space. `space` is the current space; `next_space`
/// mints a fresh space index every time we cross an object-space boundary.
#[allow(clippy::too_many_arguments)]
fn walk(
    r: &Reader,
    fcr: Fcr,
    out: &mut WalkOut,
    visited: &mut HashSet<u64>,
    depth: usize,
    space: usize,
    next_space: &mut usize,
    cur_rev: &mut usize,
    in_version: &mut bool,
) {
    // The `visited` set stops cycles, but a crafted file can still nest
    // distinct sub-lists thousands deep. Cap recursion depth (like
    // `collect_inner`) so a malicious `.one` can't overflow the stack — an
    // abort would unwind past the FFI `catch_unwind` and crash the host.
    if depth > 64 || fcr.is_nil() || fcr.cb == 0 || !visited.insert(fcr.stp) {
        return;
    }
    if out.rev_tables.is_empty() {
        out.rev_tables.push(HashMap::new()); // revision 0
    }
    let (mut stp, mut cb) = (fcr.stp, fcr.cb);
    loop {
        let base = stp as usize;
        // checked_add so a bogus stp/cb can't wrap the bounds checks (M2).
        match base.checked_add(16) {
            Some(e) if e <= r.d.len() => {}
            _ => return,
        }
        if r.u64(base) != MAGIC_FRAG_HEADER {
            return;
        }
        let frag_end = match base.checked_add(cb as usize) {
            Some(e) => e,
            None => return,
        };
        if frag_end > r.d.len() || frag_end < base + 20 {
            return;
        }
        let nodes_end = frag_end - 20;
        let next = r.fcr(nodes_end);
        let mut o = base + 16;
        while o + 4 <= nodes_end {
            let header = r.u32(o);
            let id = (header & 0x3FF) as u16;
            let size = ((header >> 10) & 0x1FFF) as usize;
            let stp_fmt = ((header >> 23) & 0x3) as u8;
            let cb_fmt = ((header >> 25) & 0x3) as u8;
            let base_type = ((header >> 27) & 0xF) as u8;
            if id == 0x0FF || size < 4 {
                break;
            }
            if base_type == 2 {
                if let Some(sub) = node_ref(r, o + 4, stp_fmt, cb_fmt) {
                    let child_space = if id == FNID_OBJECT_SPACE_LIST_REF {
                        *next_space += 1;
                        // The ref body carries the space's ExtendedGUID right
                        // after the chunk reference — its durable identity.
                        let gp = o + 4 + ref_size(stp_fmt, cb_fmt);
                        if gp + 20 <= r.d.len() {
                            let mut g = [0u8; 20];
                            g.copy_from_slice(&r.d[gp..gp + 20]);
                            out.space_gosids.entry(*next_space).or_insert(g);
                        }
                        *next_space
                    } else {
                        space
                    };
                    walk(
                        r, sub, out, visited, depth + 1, child_space, next_space, cur_rev,
                        in_version,
                    );
                }
            } else if base_type == 1 {
                // Object declaration: BlobRef → ObjectSpaceObjectPropSet, then
                // ObjectDeclaration2Body { oid(CompactID), jcid, flags }.
                if let Some(blob) = node_ref(r, o + 4, stp_fmt, cb_fmt) {
                    let body = o + 4 + ref_size(stp_fmt, cb_fmt);
                    out.objs.push(Obj {
                        own_oid: r.u32(body),
                        jcid: r.u32(body + 4),
                        stp: blob.stp as usize,
                        cb: blob.cb as usize,
                        space,
                        rev: *cur_rev,
                        versioned: *in_version,
                    });
                }
            } else if base_type == 0 {
                let body = o + 4;
                match id {
                    // Which revision this declaration belongs to: the space as
                    // it stands (no context), or a stored page version (7FND's
                    // `gctxid`). See [FNID_REV_MANIFEST_START7].
                    FNID_REV_MANIFEST_START4 | FNID_REV_MANIFEST_START6 => {
                        *in_version = false;
                    }
                    FNID_REV_MANIFEST_START7 => {
                        let g = body + REV7_GCTXID_OFFSET;
                        // A 7FND whose context is nil is still current content —
                        // read the bytes rather than assuming the shape implies
                        // the meaning.
                        *in_version =
                            g + 20 > r.d.len() || r.d[g..g + 20].iter().any(|&b| b != 0);
                    }
                    FNID_REV_MANIFEST_END => {
                        *in_version = false;
                    }
                    // The revision's own declaration of its content root. Only
                    // the context-free (live) manifest's is recorded: a stored
                    // page version names the root of the tree AS IT WAS, which
                    // is precisely the tree whose erased content must not come
                    // back.
                    FNID_ROOT_OBJECT_REF3 => {
                        if !*in_version
                            && body + ROOT_REF3_ROLE_OFFSET + 4 <= r.d.len()
                            && r.u32(body + ROOT_REF3_ROLE_OFFSET) == ROOT_ROLE_CONTENT
                        {
                            let mut e = [0u8; 20];
                            e.copy_from_slice(&r.d[body..body + 20]);
                            out.live_roots.entry(space).or_default().push(e);
                        }
                    }
                    // A new revision's global-id table begins EMPTY (MS-ONESTORE
                    // §2.5.10): entries come from explicit 0x024 declarations and
                    // selective copies (0x025/0x026) from the previous table.
                    FNID_GID_TABLE_START | FNID_GID_TABLE_START2 => {
                        out.rev_tables.push(HashMap::new());
                        *cur_rev = out.rev_tables.len() - 1;
                    }
                    FNID_GID_TABLE_ENTRY => {
                        if body + 20 <= r.d.len() {
                            let idx = r.u32(body);
                            let mut g = [0u8; 16];
                            g.copy_from_slice(&r.d[body + 4..body + 20]);
                            out.gid_tables.entry(space).or_default().insert(idx, g);
                            if let Some(t) = out.rev_tables.get_mut(*cur_rev) {
                                t.insert(idx, g);
                            }
                        }
                    }
                    // Inherit one entry from the dependency (previous) table.
                    FNID_GID_TABLE_ENTRY2 => {
                        let (from, to) = (r.u32(body), r.u32(body + 4));
                        if *cur_rev >= 1 {
                            if let Some(&g) = out.rev_tables[*cur_rev - 1].get(&from) {
                                out.rev_tables[*cur_rev].insert(to, g);
                                out.gid_tables.entry(space).or_default().insert(to, g);
                            }
                        }
                    }
                    // Inherit a range of entries from the previous table.
                    FNID_GID_TABLE_ENTRY3 => {
                        let (from0, count, to0) =
                            (r.u32(body), r.u32(body + 4), r.u32(body + 8));
                        if *cur_rev >= 1 {
                            for k in 0..count.min(4096) {
                                if let Some(&g) =
                                    out.rev_tables[*cur_rev - 1].get(&(from0 + k))
                                {
                                    out.rev_tables[*cur_rev].insert(to0 + k, g);
                                    out.gid_tables.entry(space).or_default().insert(to0 + k, g);
                                }
                            }
                        }
                    }
                    _ => {}
                }
            }
            o += size;
        }
        if next.is_nil() || next.cb == 0 || !visited.insert(next.stp) {
            break;
        }
        stp = next.stp;
        cb = next.cb;
    }
}

fn ref_size(s: u8, c: u8) -> usize {
    (match s { 0 => 8, 1 => 4, 2 => 2, 3 => 4, _ => 0 })
        + (match c { 0 => 4, 1 => 8, 2 => 1, 3 => 2, _ => 0 })
}

// ── Text styling (bold/italic/font/size/colour) + math ──────────────────────

/// Resolved character formatting for a run of text.
#[derive(Clone, Default)]
struct Style {
    bold: bool,
    italic: bool,
    underline: bool,
    strike: bool,
    highlight: bool,
    font: Option<String>,
    size_half_pt: u32, // 0 = unset
    color: u32,        // 0 = unset; else 0x00BBGGRR-ish (FF000000 = auto/black)
    is_math: bool,     // font == "Cambria Math"
    /// Plain-text sub/superscript (0x1C09 / 0x1C08), not maths notation.
    sub: bool,
    sup: bool,
    /// This run's text is Markdown we generated, not the writer's characters.
    /// Set only on the `[label](url)` runs [`linkify_hyperlink_runs`] builds,
    /// and read by [`run_markdown`] to skip character escaping: a URL such as
    /// `https://example.com/~eric` must not have its tilde backslash-escaped
    /// into the link target. Never read from the file, so [`merge_style`]
    /// clears it; it takes part in [`same_visible`] so a generated link run can
    /// never coalesce with the prose beside it and take the prose with it.
    verbatim_md: bool,
}

/// Read a style object (00020001 / 0012004D) into a [Style].
/// Bit set on canonical (ExGuid-resolved) ids so they can't collide with a raw
/// CompactID fallback (a real guidIndex never reaches 2^23 entries).
const CANON_BIT: u32 = 0x8000_0000;

/// Resolves a CompactID reference to the current object it names, correctly
/// across revisions. A CompactID is `{guidIndex(hi 24) | n(lo 8)}`; the
/// guidIndex→GUID mapping is PER-REVISION, so the SAME CompactID means
/// different objects in different revisions. We canonicalise every reference to
/// its ExGuid (GUID + n) via the referencing object's revision table, then look
/// up the latest declaration of that ExGuid. This is what lets heavily-revised
/// pages resolve their content instead of losing it.
struct Resolver<'a> {
    objs: &'a [Obj],
    rev_tables: &'a [HashMap<u32, [u8; 16]>],
    registry: &'a HashMap<[u8; 20], u32>,
    by_canon: HashMap<u32, usize>, // canonical id → obj index (latest, this space)
}

impl<'a> Resolver<'a> {
    /// CompactID + referencing revision → canonical id (or the raw id if it
    /// can't be resolved — harmless, it just won't be found in `by_canon`).
    fn canon(&self, cid: u32, rev: usize) -> u32 {
        self.rev_tables
            .get(rev)
            .and_then(|t| t.get(&(cid >> 8)))
            .and_then(|g| {
                let mut e = [0u8; 20];
                e[..16].copy_from_slice(g);
                e[16] = (cid & 0xFF) as u8;
                self.registry.get(&e).copied()
            })
            .map(|i| i | CANON_BIT)
            .unwrap_or(cid)
    }
    /// CompactID + referencing revision → the object it names, if present.
    fn get(&self, cid: u32, rev: usize) -> Option<usize> {
        self.by_canon.get(&self.canon(cid, rev)).copied()
    }
    /// An object's OWN canonical id — its identity, not a reference to one.
    /// `None` when the revision tables do not name it: such an object cannot be
    /// compared against any reference, so a caller must not read its absence
    /// from a reachable set as "the page does not have it".
    fn own_canon(&self, o: &Obj) -> Option<u32> {
        let g = self.rev_tables.get(o.rev)?.get(&(o.own_oid >> 8))?;
        let mut e = [0u8; 20];
        e[..16].copy_from_slice(g);
        e[16] = (o.own_oid & 0xFF) as u8;
        self.registry.get(&e).map(|&n| n | CANON_BIT)
    }
    fn obj(&self, idx: usize) -> &Obj {
        &self.objs[idx]
    }
}

fn read_style(r: &Reader, o: &Obj) -> Style {
    let ps = read_propset(r, o.stp, o.cb);
    let font = ps.utf16(PID_FONT).filter(|f| !f.is_empty());
    let is_math = font.as_deref() == Some("Cambria Math");
    // 0x1C0D is the highlight colour: 0xFF000000 = "automatic"/none, 0 = unset;
    // anything else means the run is highlighted (colour degrades to generic
    // `==highlight==` in our dialect).
    let hl = ps.u32(PID_HIGHLIGHT).unwrap_or(0);
    Style {
        bold: ps.flag(PID_BOLD),
        italic: ps.flag(PID_ITALIC),
        underline: ps.flag(PID_UNDERLINE),
        strike: ps.flag(PID_STRIKE),
        highlight: hl != 0 && hl != 0xFF00_0000,
        font,
        size_half_pt: ps.u32(PID_FONT_SIZE).unwrap_or(0),
        color: ps.u32(PID_FONT_COLOR).unwrap_or(0),
        is_math,
        sub: ps.flag(PID_SUBSCRIPT),
        sup: ps.flag(PID_SUPERSCRIPT),
        verbatim_md: false,
    }
}

fn resolve_style(r: &Reader, res: &Resolver, oid: u32, rev: usize) -> Style {
    res.get(oid, rev)
        .map(|i| read_style(r, res.obj(i)))
        .unwrap_or_default()
}

/// Overlay a run's style on the paragraph base: booleans OR together, and the
/// run's font/size/colour win when set.
fn merge_style(base: &Style, run: &Style) -> Style {
    Style {
        bold: base.bold || run.bold,
        italic: base.italic || run.italic,
        underline: base.underline || run.underline,
        strike: base.strike || run.strike,
        highlight: base.highlight || run.highlight,
        font: run.font.clone().or_else(|| base.font.clone()),
        size_half_pt: if run.size_half_pt > 0 { run.size_half_pt } else { base.size_half_pt },
        color: if run.color != 0 { run.color } else { base.color },
        is_math: base.is_math || run.is_math,
        sub: base.sub || run.sub,
        sup: base.sup || run.sup,
        // Never comes from the file — only [`linkify_hyperlink_runs`] sets it,
        // on runs it builds itself, and those are not merged from a base style.
        verbatim_md: false,
    }
}

/// One maths object opened by a U+FDD0 in a run's text — read from the run's
/// own entry in [`PID_MATH_OBJECTS`]. See that constant for how it was decoded.
#[derive(Clone, Debug, Default, PartialEq)]
struct MathObj {
    kind: u32,
    /// Argument count on the opening run (cells, for a matrix).
    args: u32,
    /// Columns, for the grid kinds. 0 when unrecorded.
    cols: u32,
    beg: Option<char>,
    end: Option<char>,
}

/// One styled span of text within a paragraph.
#[derive(Default)]
struct SRun {
    text: String,
    style: Style,
    /// Maths objects opened inside `text`, as (char offset of the U+FDD0,
    /// descriptor). Carried per run because that is how OneNote records it, and
    /// accumulated when [`render_runs`] coalesces runs — an equation's
    /// structure spans a dozen runs, so it can only be converted once they are
    /// back together.
    math_objs: Vec<(usize, MathObj)>,
}

/// Concatenate a paragraph's runs and re-base their maths-object offsets onto
/// the joined string, so a display equation converts as one structure however
/// many runs OneNote split it across.
fn joined_math(runs: &[SRun]) -> (String, Vec<(usize, MathObj)>) {
    let mut text = String::new();
    let mut objs: Vec<(usize, MathObj)> = Vec::new();
    let mut base = 0usize;
    for r in runs {
        objs.extend(r.math_objs.iter().map(|(o, m)| (base + o, m.clone())));
        base += r.text.chars().count();
        text.push_str(&r.text);
    }
    (text, objs)
}

/// TextRunIndex (0x1E12) → char-offset boundaries (array of little-endian u32).
fn parse_run_index(v: Option<&PVal>) -> Vec<usize> {
    match v {
        Some(PVal::Str(b)) => b
            .chunks(4)
            .filter(|c| c.len() == 4)
            .map(|c| u32::from_le_bytes([c[0], c[1], c[2], c[3]]) as usize)
            .collect(),
        _ => Vec::new(),
    }
}

/// Split a paragraph object's text into styled runs, resolving the paragraph
/// style (0x342C) and per-run formatting (0x1E12 boundaries + 0x1E13 styles).
/// The note tags OneNote applied to this paragraph.
///
/// The chain, decoded against a real tagged `.one`: the paragraph carries
/// `0x3489`, an array of tag *states*; each state holds `0x3488`, an ObjectID
/// pointing at a tag *definition* (jcid `0x00120043`); the definition carries
/// the label (`0x3468`) and OneNote's icon index (`0x3464`).
///
/// **The completion state is deliberately not read.** The two candidate
/// properties disagree on the only fixture available: on a Question the
/// timestamp-shaped `0x346F` is set and `0x3470` is 1, while on an unticked
/// To Do both are 0 — so "non-zero means done" would mark a question complete.
/// A wrongly-ticked to-do is worse than an unticked one, and this file's own
/// rule is that guessing at property semantics is how working imports get
/// broken. Imported to-dos arrive unticked until there is a fixture containing
/// a *completed* one to settle it.
fn paragraph_tags(r: &Reader, o: &Obj, res: &Resolver) -> Vec<ParaTag> {
    let ps = read_propset(r, o.stp, o.cb);
    let Some(PVal::Array(states)) = ps.get(PID_TAG_STATES) else {
        return Vec::new();
    };
    let mut out = Vec::new();
    for state in states {
        for (pid, val) in &state.props {
            if *pid != PID_TAG_DEF_OID {
                continue;
            }
            let PVal::Oids(oids) = val else { continue };
            for &oid in oids {
                let Some(idx) = res.get(oid, o.rev) else { continue };
                let def = res.obj(idx);
                if def.jcid != JCID_TAG_DEF {
                    continue;
                }
                let dps = read_propset(r, def.stp, def.cb);
                let label = dps
                    .bytes(PID_TAG_LABEL)
                    .map(|b| decode_utf16(b).trim_end_matches('\0').to_string())
                    .unwrap_or_default();
                if label.trim().is_empty() {
                    continue;
                }
                let shape = dps.u32(PID_TAG_SHAPE).unwrap_or(0);
                // One paragraph can carry the same tag twice in the file; the
                // note only means it once.
                if !out.iter().any(|t: &ParaTag| t.label == label) {
                    out.push(ParaTag { label, shape });
                }
            }
        }
    }
    out
}

fn styled_runs(r: &Reader, o: &Obj, res: &Resolver) -> Vec<SRun> {
    let ps = read_propset(r, o.stp, o.cb);
    let text = match ps.run_text() {
        // Strip only a trailing NUL terminator so run-index offsets stay valid.
        Some(t) => t.trim_end_matches('\0').to_string(),
        None => return Vec::new(),
    };
    let base = ps
        .oids(PID_PARA_STYLE)
        .first()
        .map(|&oid| resolve_style(r, res, oid, o.rev))
        .unwrap_or_default();
    let fmt = ps.oids(PID_RUN_FORMATTING);
    let bounds = parse_run_index(ps.get(PID_RUN_INDEX));
    let chars: Vec<char> = text.chars().collect();
    let math = parse_math_objects(&ps);

    // Single style (or a shape we can't split cleanly): one merged run.
    if fmt.len() <= 1 || bounds.len() + 1 != fmt.len() {
        let mut st = base;
        for &f in &fmt {
            st = merge_style(&st, &resolve_style(r, res, f, o.rev));
        }
        // One run means one 0x3499 entry, so it can only describe an object
        // opened at offset 0. Anything richer needs the run split, and the
        // converter's fraction fallback covers the rest exactly as before.
        let objs = match (math.first(), chars.first()) {
            (Some(Some(m)), Some('\u{FDD0}')) => vec![(0usize, m.clone())],
            _ => Vec::new(),
        };
        let mut runs = vec![SRun { text, style: st, math_objs: objs }];
        translate_symbol_pua(&mut runs);
        linkify_hyperlink_runs(&mut runs);
        return runs;
    }

    // Multi-run: boundaries [0, b0, b1, …, len] split the char stream.
    //
    // 0x1E12's offsets count UTF-16 CODE UNITS — that is how OneNote stores the
    // text — while we split a `Vec<char>`. The two agree exactly until the
    // paragraph contains an astral character, and every maths-italic letter
    // (U+1D400…, which is what an equation is made of) is one: each surrogate
    // pair slides every later boundary one unit further off. On the reference
    // page's piecewise definition that shifted the runs by up to six positions,
    // which handed each U+FDD0 the maths descriptor belonging to a different
    // object — a fraction came back as an equation array.
    let mut u16_to_char: Vec<usize> = Vec::with_capacity(chars.len() + 1);
    for (ci, ch) in chars.iter().enumerate() {
        for _ in 0..ch.len_utf16() {
            u16_to_char.push(ci);
        }
    }
    u16_to_char.push(chars.len());
    let to_char = |u: usize| u16_to_char.get(u).copied().unwrap_or(chars.len());
    let mut starts = vec![0usize];
    starts.extend(bounds.iter().map(|&b| to_char(b)));
    starts.push(chars.len());
    let mut runs = Vec::new();
    for i in 0..fmt.len() {
        let a = starts[i].min(chars.len());
        let b = starts[i + 1].min(chars.len());
        if a >= b {
            continue;
        }
        let seg: String = chars[a..b].iter().collect();
        let st = merge_style(&base, &resolve_style(r, res, fmt[i], o.rev));
        // A run's 0x3499 entry describes the object it OPENS, and OneNote puts
        // every opening U+FDD0 in a run of its own — so the descriptor is only
        // trusted when this run actually begins with one. An entry on a run
        // that merely sits inside an object describes the enclosing context,
        // and reading it as an opener would nest the equation wrongly.
        let objs = match (math.get(i).and_then(|m| m.as_ref()), chars.get(a)) {
            (Some(m), Some('\u{FDD0}')) => vec![(0usize, m.clone())],
            _ => Vec::new(),
        };
        runs.push(SRun { text: seg, style: st, math_objs: objs });
    }
    if runs.is_empty() {
        runs.push(SRun { text, style: base, math_objs: Vec::new() });
    }
    translate_symbol_pua(&mut runs);
    linkify_hyperlink_runs(&mut runs);
    runs
}

/// Decode [`PID_MATH_OBJECTS`] into one slot per text run: `Some` when that
/// entry names a maths-object kind, `None` for a plain run (and for the
/// entries whose kind field is out of range, which a few carry).
fn parse_math_objects(ps: &PropSet) -> Vec<Option<MathObj>> {
    let Some(PVal::Array(sets)) = ps.get(PID_MATH_OBJECTS) else {
        return Vec::new();
    };
    sets.iter()
        .map(|s| {
            let kind = s.u32(PID_MATH_KIND)?;
            // Real kinds are small ordinals; some entries carry a large
            // sentinel in this slot (0x90000000 on top-level runs), and
            // treating one as a kind would invent structure that is not there.
            if kind > 0xFF {
                return None;
            }
            Some(MathObj {
                kind,
                args: s.u32(PID_MATH_ARGS).unwrap_or(0),
                cols: s.u32(PID_MATH_COLS).unwrap_or(0),
                beg: s.u32(PID_MATH_BEG).and_then(char::from_u32),
                end: s.u32(PID_MATH_END).and_then(char::from_u32),
            })
        })
        .collect()
}

/// Adobe Symbol encoding, byte → Unicode. `None` for glyphs with no clean
/// Unicode identity (bracket/radical extender pieces).
///
/// Office stores a character typed in a symbol font as `U+F000 + byte`. That
/// PUA code point is meaningless alone — but the run records its FONT, and
/// when the font is `Symbol` the byte maps deterministically through this
/// table. (The review's worry that `0xAC` is ambiguous — Symbol's `←` vs a
/// user's `¬` — only applies without the font: keyed on it, `F0AC` in a
/// Symbol run IS the left arrow, and `¬` in Symbol is byte 0xD8.)
fn symbol_pua_char(b: u8) -> Option<char> {
    Some(match b {
        // ASCII-coincident slots, with Symbol's own deviations.
        0x20 => ' ', 0x21 => '!', 0x22 => '\u{2200}', 0x23 => '#',
        0x24 => '\u{2203}', 0x25 => '%', 0x26 => '&', 0x27 => '\u{220B}',
        0x28 => '(', 0x29 => ')', 0x2A => '\u{2217}', 0x2B => '+',
        0x2C => ',', 0x2D => '\u{2212}', 0x2E => '.', 0x2F => '/',
        0x30..=0x39 => b as char, // digits
        0x3A => ':', 0x3B => ';', 0x3C => '<', 0x3D => '=', 0x3E => '>',
        0x3F => '?', 0x40 => '\u{2245}',
        // Greek capitals.
        0x41 => 'Α', 0x42 => 'Β', 0x43 => 'Χ', 0x44 => 'Δ', 0x45 => 'Ε',
        0x46 => 'Φ', 0x47 => 'Γ', 0x48 => 'Η', 0x49 => 'Ι', 0x4A => 'ϑ',
        0x4B => 'Κ', 0x4C => 'Λ', 0x4D => 'Μ', 0x4E => 'Ν', 0x4F => 'Ο',
        0x50 => 'Π', 0x51 => 'Θ', 0x52 => 'Ρ', 0x53 => 'Σ', 0x54 => 'Τ',
        0x55 => 'Υ', 0x56 => 'ς', 0x57 => 'Ω', 0x58 => 'Ξ', 0x59 => 'Ψ',
        0x5A => 'Ζ',
        0x5B => '[', 0x5C => '\u{2234}', 0x5D => ']', 0x5E => '\u{22A5}',
        0x5F => '_',
        // Greek lowercase.
        0x61 => 'α', 0x62 => 'β', 0x63 => 'χ', 0x64 => 'δ', 0x65 => 'ε',
        0x66 => 'φ', 0x67 => 'γ', 0x68 => 'η', 0x69 => 'ι', 0x6A => 'ϕ',
        0x6B => 'κ', 0x6C => 'λ', 0x6D => 'μ', 0x6E => 'ν', 0x6F => 'ο',
        0x70 => 'π', 0x71 => 'θ', 0x72 => 'ρ', 0x73 => 'σ', 0x74 => 'τ',
        0x75 => 'υ', 0x76 => 'ϖ', 0x77 => 'ω', 0x78 => 'ξ', 0x79 => 'ψ',
        0x7A => 'ζ',
        0x7B => '{', 0x7C => '|', 0x7D => '}', 0x7E => '\u{223C}',
        // Symbols proper.
        0xA1 => 'ϒ', 0xA2 => '\u{2032}', 0xA3 => '\u{2264}',
        0xA4 => '\u{2044}', 0xA5 => '\u{221E}', 0xA6 => 'ƒ',
        0xA7 => '\u{2663}', 0xA8 => '\u{2666}', 0xA9 => '\u{2665}',
        0xAA => '\u{2660}', 0xAB => '\u{2194}', 0xAC => '\u{2190}',
        0xAD => '\u{2191}', 0xAE => '\u{2192}', 0xAF => '\u{2193}',
        0xB0 => '°', 0xB1 => '±', 0xB2 => '\u{2033}', 0xB3 => '\u{2265}',
        0xB4 => '×', 0xB5 => '\u{221D}', 0xB6 => '\u{2202}', 0xB7 => '•',
        0xB8 => '÷', 0xB9 => '\u{2260}', 0xBA => '\u{2261}',
        0xBB => '\u{2248}', 0xBC => '\u{2026}', 0xBF => '\u{21B5}',
        0xC0 => '\u{2135}', 0xC1 => '\u{2111}', 0xC2 => '\u{211C}',
        0xC3 => '\u{2118}', 0xC4 => '\u{2297}', 0xC5 => '\u{2295}',
        0xC6 => '\u{2205}', 0xC7 => '\u{2229}', 0xC8 => '\u{222A}',
        0xC9 => '\u{2283}', 0xCA => '\u{2287}', 0xCB => '\u{2284}',
        0xCC => '\u{2282}', 0xCD => '\u{2286}', 0xCE => '\u{2208}',
        0xCF => '\u{2209}',
        0xD0 => '\u{2220}', 0xD1 => '\u{2207}', 0xD2 => '®', 0xD3 => '©',
        0xD4 => '\u{2122}', 0xD5 => '\u{220F}', 0xD6 => '\u{221A}',
        0xD7 => '\u{22C5}', 0xD8 => '¬', 0xD9 => '\u{2227}',
        0xDA => '\u{2228}', 0xDB => '\u{21D4}', 0xDC => '\u{21D0}',
        0xDD => '\u{21D1}', 0xDE => '\u{21D2}', 0xDF => '\u{21D3}',
        0xE0 => '\u{25CA}', 0xE1 => '\u{27E8}', 0xE2 => '®', 0xE3 => '©',
        0xE4 => '\u{2122}', 0xE5 => '\u{2211}', 0xF1 => '\u{27E9}',
        0xF2 => '\u{222B}',
        // Everything else (bracket pieces, radical extenders, 0x60, 0xA0,
        // 0xBD/0xBE, 0xE6…) has no standalone Unicode identity.
        _ => return None,
    })
}

/// Translate Office's symbol-font PUA storage (`U+F000 + byte`) to real
/// Unicode for runs whose font is `Symbol`. Applied only when EVERY PUA char
/// in the run maps — a partial translation would leave a run that half-renders
/// in the wrong alphabet. On success the run's font is cleared: the characters
/// are ordinary Unicode now, and keeping `Symbol` would re-encode them wrongly
/// (Symbol's cmap maps `A` to Alpha).
fn translate_symbol_pua(runs: &mut [SRun]) {
    for run in runs {
        if run.style.font.as_deref() != Some("Symbol") {
            continue;
        }
        if !run.text.chars().any(|c| ('\u{F020}'..='\u{F0FF}').contains(&c)) {
            continue;
        }
        let mut out = String::with_capacity(run.text.len());
        let mut ok = true;
        for c in run.text.chars() {
            if ('\u{F020}'..='\u{F0FF}').contains(&c) {
                match symbol_pua_char((c as u32 - 0xF000) as u8) {
                    Some(mapped) => out.push(mapped),
                    None => {
                        ok = false;
                        break;
                    }
                }
            } else {
                out.push(c);
            }
        }
        if ok {
            run.text = out;
            run.style.font = None;
        }
    }
}

/// Fold a Mathematical-Alphanumeric-Symbols code point back to plain ASCII
/// (e.g. 𝐿→L, 𝑏→b, 𝟏→1). Non-math code points pass through unchanged. This is a
/// dependency-free stand-in for NFKC over the U+1D400–U+1D7FF block.
fn fold_math_char(c: char) -> char {
    let u = c as u32;
    // Letterlike holes that live outside the main block.
    match u {
        0x210E => return 'h', // PLANCK CONSTANT = italic h
        0x212C => return 'B',
        0x2130 => return 'E',
        0x2131 => return 'F',
        0x210B | 0x2110 => return 'H',
        0x2112 => return 'L',
        0x2133 => return 'M',
        0x211B => return 'R',
        _ => {}
    }
    // Latin letter styles: 15 groups of 52 (A–Z then a–z) from U+1D400.
    if (0x1D400..=0x1D6A3).contains(&u) {
        let idx = (u - 0x1D400) % 52;
        return if idx < 26 {
            (b'A' + idx as u8) as char
        } else {
            (b'a' + (idx - 26) as u8) as char
        };
    }
    // Digit styles: groups of 10 from U+1D7CE.
    if (0x1D7CE..=0x1D7FF).contains(&u) {
        return (b'0' + ((u - 0x1D7CE) % 10) as u8) as char;
    }
    c
}

fn is_math_control(c: char) -> bool {
    let u = c as u32;
    // Office linear-math structure noncharacters + invisible operators.
    (0xFDD0..=0xFDEF).contains(&u) || matches!(u, 0x2061..=0x2064) || u == 0x200B
}

// ── Word/OneNote field codes: hyperlinks ────────────────────────────────────
//
// A hyperlink is not a property in the OneNote file. It is a Word-style FIELD
// embedded in the paragraph's own text buffer: a begin marker, the instruction
// `HYPERLINK "https://…"`, and the display text. `PropSet::run_text` returns
// that buffer verbatim and nothing downstream filtered it, so every imported
// link arrived in the note as literal junk — `﷟HYPERLINK "https://…"` sitting
// next to the words it was supposed to be attached to, with no way to follow
// it.
//
// These markers live in the same Office noncharacter block as
// [`is_math_control`]'s fraction delimiters (U+FDD0..U+FDEF). That overlap is
// why the conversion lives here and runs only on PROSE runs: a math run's
// U+FDD0 is structure that `office_math_to_latex` consumes, not a field.

/// Field-begin markers. U+FDDF is what OneNote writes; U+0013 is Word's
/// classic field-begin, accepted because content pasted from Word keeps it.
const FIELD_BEGIN: [char; 3] = ['\u{FDDF}', '\u{FDDE}', '\u{0013}'];
/// Separates a field's instruction from its cached result (the display text).
const FIELD_SEP: char = '\u{0014}';
/// Ends a field's result.
const FIELD_END: char = '\u{0015}';

fn is_field_begin(c: char) -> bool {
    FIELD_BEGIN.contains(&c)
}

/// Any field scaffolding character. None of these may ever reach a note.
fn is_field_control(c: char) -> bool {
    is_field_begin(c) || c == FIELD_SEP || c == FIELD_END
}

/// A located `HYPERLINK` instruction: the marker through the closing quote and
/// any switches. Deliberately does NOT cover the display text — OneNote writes
/// that on either side of the instruction depending on version, so who owns it
/// is the caller's decision (see [`linkify_hyperlink_runs`]).
struct FieldLink {
    /// Char index of the begin marker.
    start: usize,
    /// Char index one past the instruction (and its `\u{0014}`, if present).
    end: usize,
    url: String,
}

/// Find the next `HYPERLINK` field instruction at or after `from`.
///
/// A field whose instruction is anything else (`PAGEREF`, `TOC`, `DATE`) is
/// skipped rather than consumed: its visible text is the user's writing and
/// must survive, and the stray marker is removed by the caller's final sweep.
fn find_field_link(chars: &[char], from: usize) -> Option<FieldLink> {
    const KW: &str = "HYPERLINK";
    let mut i = from;
    while i < chars.len() {
        if !is_field_begin(chars[i]) {
            i += 1;
            continue;
        }
        let start = i;
        let mut j = i + 1;
        while j < chars.len() && chars[j].is_whitespace() {
            j += 1;
        }
        let matched = KW
            .chars()
            .enumerate()
            .all(|(k, c)| chars.get(j + k).is_some_and(|d| d.eq_ignore_ascii_case(&c)));
        if !matched {
            i += 1;
            continue;
        }
        j += KW.len();
        while j < chars.len() && chars[j].is_whitespace() {
            j += 1;
        }
        let mut url = String::new();
        if chars.get(j) == Some(&'"') {
            j += 1;
            while j < chars.len() && chars[j] != '"' {
                url.push(chars[j]);
                j += 1;
            }
            j = (j + 1).min(chars.len()); // closing quote
        } else {
            while j < chars.len() && !chars[j].is_whitespace() && !is_field_control(chars[j]) {
                url.push(chars[j]);
                j += 1;
            }
        }
        // Switches. `\l "anchor"` names a bookmark inside the target and is the
        // one that changes where you land; `\o` (tooltip) and `\t` (target
        // frame) carry nothing we can show, but must still be consumed or they
        // would be mistaken for display text.
        loop {
            let mut k = j;
            while k < chars.len() && chars[k] == ' ' {
                k += 1;
            }
            if chars.get(k) != Some(&'\\') {
                break;
            }
            let Some(sw) = chars.get(k + 1).map(|c| c.to_ascii_lowercase()) else {
                break;
            };
            k += 2;
            while k < chars.len() && chars[k] == ' ' {
                k += 1;
            }
            let mut arg = String::new();
            if chars.get(k) == Some(&'"') {
                k += 1;
                while k < chars.len() && chars[k] != '"' {
                    arg.push(chars[k]);
                    k += 1;
                }
                k = (k + 1).min(chars.len());
            } else {
                while k < chars.len() && !chars[k].is_whitespace() && !is_field_control(chars[k]) {
                    arg.push(chars[k]);
                    k += 1;
                }
            }
            if sw == 'l' && !arg.is_empty() && !url.contains('#') {
                url.push('#');
                url.push_str(&arg);
            }
            j = k;
        }
        if chars.get(j) == Some(&FIELD_SEP) {
            j += 1;
        }
        if url.trim().is_empty() {
            i += 1;
            continue;
        }
        return Some(FieldLink {
            start,
            end: j,
            url: url.trim().to_string(),
        });
    }
    None
}

/// Percent-encode only what would break the app's link regex.
///
/// `md_render`'s pattern reads the target as `[^)\s]+`, so a space or a
/// parenthesis truncates it. Everything else is left exactly as OneNote stored
/// it — a URL is not ours to normalise — and an existing `%XX` escape is
/// stepped over so `%20` never becomes `%2520`.
fn encode_url(u: &str) -> String {
    let c: Vec<char> = u.chars().collect();
    let mut out = String::with_capacity(u.len());
    let mut i = 0;
    while i < c.len() {
        if c[i] == '%'
            && c.get(i + 1).is_some_and(|d| d.is_ascii_hexdigit())
            && c.get(i + 2).is_some_and(|d| d.is_ascii_hexdigit())
        {
            out.push('%');
            i += 1;
            continue;
        }
        match c[i] {
            ' ' => out.push_str("%20"),
            '(' => out.push_str("%28"),
            ')' => out.push_str("%29"),
            ch if is_field_control(ch) || ch.is_control() => {}
            ch => out.push(ch),
        }
        i += 1;
    }
    out
}

/// Render one link as the app's Markdown, or degrade to plain text.
///
/// Emitted NAKED, with no emphasis wrapper, and that is load-bearing: the app's
/// inline parser is non-recursive, so a link nested inside the blue-underlined
/// styling OneNote gives it — `{{#0563C1 ++[x](y)++}}` — would print as
/// literal source. An imported link therefore loses OneNote's link colouring
/// and picks up the app's own, which is what every Markdown editor does anyway.
///
/// `onenote:` and `file:` targets degrade to their label: the app opens three
/// schemes on purpose (a deliberate security decision), so emitting a link it
/// would print literally only swaps one kind of junk for another.
fn markdown_link(url: &str, label: &str) -> String {
    let url = encode_url(url);
    let lower = url.to_ascii_lowercase();
    let openable = lower.starts_with("http://")
        || lower.starts_with("https://")
        || lower.starts_with("mailto:");
    let label: String = label
        .chars()
        .filter(|c| !matches!(c, '[' | ']' | '\n' | '\r') && !is_field_control(*c))
        .collect();
    let label = label.trim();
    if !openable {
        // The app opens three schemes on purpose, so `[x](onenote:…)` would
        // print as literal source — but DROPPING the address is worse than
        // showing it. This runs over already-imported notes too (the repair
        // path), where the `.one` may be long gone, and a silently discarded
        // link target is unrecoverable user data. Plain text keeps it.
        return if label.is_empty() {
            url
        } else {
            format!("{label} ({url})")
        };
    }
    if label.is_empty() {
        // The URL as its own label: still clickable, and the address is
        // information the student can act on.
        return format!("[{url}]({url})");
    }
    format!("[{label}]({url})")
}

/// Convert `HYPERLINK` fields in a bare string, then strip every marker.
///
/// For text with no run structure — titles, bullet strings. Where the styled
/// runs are available, [`linkify_hyperlink_runs`] does better.
pub(crate) fn linkify_field_codes(s: &str) -> String {
    if !s.chars().any(is_field_control) {
        return s.to_string();
    }
    let chars: Vec<char> = s.chars().collect();
    let mut out = String::with_capacity(s.len());
    let mut at = 0usize;
    while let Some(f) = find_field_link(&chars, at) {
        out.extend(chars[at..f.start].iter());
        // Display text after the instruction is Word's documented layout.
        let mut k = f.end;
        let mut label = String::new();
        while k < chars.len() && chars[k] != FIELD_END && chars[k] != '\n' && !is_field_begin(chars[k])
        {
            label.push(chars[k]);
            k += 1;
        }
        if chars.get(k) == Some(&FIELD_END) {
            k += 1;
        }
        out.push_str(&markdown_link(&f.url, label.trim()));
        at = k;
    }
    out.extend(chars[at..].iter());
    out.chars().filter(|c| !is_field_control(*c)).collect()
}

/// Convert hyperlink fields across a paragraph's styled runs.
///
/// **Measured against a real `.one` file**, not inferred. The paragraph
/// `Video: <link>` stores one text buffer:
///
/// ```text
/// Video: \u{FDDF}HYPERLINK "https://…/watch?v=DsT_YiMiUQo"Natural Language and …
/// ^run 0 ^run 1 (boundary 7)                              ^run 2 (boundary 63)
/// ```
///
/// So the display text FOLLOWS the instruction, and — this is the part worth
/// knowing — it is its own run, because OneNote gives the invisible instruction
/// characters the *surrounding prose's* formatting and the visible label the
/// link's. In that file "Video: " and the instruction are both bold and the
/// label is not.
///
/// That is why the label is found by the **run boundary at the instruction's
/// end**, not by comparing styles with the instruction. Comparing styles gets
/// it exactly backwards: it stops before the real label and then walks
/// backwards into the prose, which is how `Video: <link>` first came out as
/// `[Video:](url)Natural Language …` — the label wrong and the sentence's
/// lead-in eaten.
///
/// Runs in `styled_runs`, AFTER the run split — the 0x1E12 boundaries are char
/// offsets into the raw buffer, so rewriting the text before the split would
/// misalign every style boundary in the paragraph.
fn linkify_hyperlink_runs(runs: &mut Vec<SRun>) {
    if !runs.iter().any(|r| r.text.chars().any(is_field_control)) {
        return;
    }
    let mut chars: Vec<char> = Vec::new();
    let mut owner: Vec<usize> = Vec::new();
    for (i, r) in runs.iter().enumerate() {
        for c in r.text.chars() {
            chars.push(c);
            owner.push(i);
        }
    }
    let multi = runs.len() > 1;
    // Non-overlapping, ascending: (span to replace, replacement markdown).
    let mut edits: Vec<(usize, usize, String)> = Vec::new();
    let mut cursor = 0usize;
    while let Some(f) = find_field_link(&chars, cursor) {
        cursor = f.end;
        // Forward: the display text, which follows the instruction.
        let mut hi = f.end;
        // A run boundary exactly at the instruction's end means OneNote split
        // the label into its own run — take that run and any following runs
        // that look identical, and stop. This is the reliable case.
        let split_here = f.end < chars.len() && f.end > 0 && owner[f.end] != owner[f.end - 1];
        let label_run = split_here.then(|| owner[f.end]);
        while hi < chars.len()
            && chars[hi] != FIELD_END
            && chars[hi] != '\n'
            && !is_field_begin(chars[hi])
        {
            // Bounded by the label's OWN run when there is one. Extending
            // through following runs that merely compare equal under
            // `same_visible` swallows the prose after the link — the styles we
            // parse are few, so "looks the same" is a much weaker signal than
            // the run boundary that put the label in its own run to begin
            // with. Truncating a label that OneNote split across runs costs a
            // few words of link text; over-reading costs the sentence.
            //
            // (Written as a match rather than `Option::is_some_and`, which is
            // newer than this crate's MSRV of 1.75 — clippy's
            // `incompatible_msrv` fires, and CI runs clippy with `-D warnings`.)
            if let Some(r) = label_run {
                if owner[hi] != r {
                    break;
                }
            }
            hi += 1;
        }
        let mut lo = f.start;
        let mut label: String = chars[f.end..hi].iter().collect();
        label = label.trim().to_string();
        if chars.get(hi) == Some(&FIELD_END) {
            hi += 1;
        }
        if label.is_empty() && multi {
            // Nothing after the instruction at all. Some versions put the label
            // BEFORE it, so take the preceding run only when it actually looks
            // like link text — underlined or coloured. Deliberately NOT a
            // same-style-as-the-instruction test: the instruction is formatted
            // like the prose around it, so that test eats the sentence.
            let floor = edits.last().map(|e| e.1).unwrap_or(0);
            let mut k = f.start;
            while k > floor && chars[k - 1] != '\n' && !is_field_control(chars[k - 1]) {
                let s = &runs[owner[k - 1]].style;
                // `color_hex`, not `color != 0`: OneNote writes FF000000 for
                // *automatic* black, and 75 of the 78 styled runs in the one
                // real file we have carry exactly that. Testing `!= 0` treats
                // ordinary prose as link-coloured, so the walk ran to the
                // start of the line and turned the whole sentence into the
                // label — the `[Video:](url)…` failure, still reachable.
                if !(s.underline || color_hex(s.color).is_some()) {
                    break;
                }
                k -= 1;
            }
            let back: String = chars[k..f.start].iter().collect();
            if !back.trim().is_empty() {
                // Keep any leading space outside the link, so "see foo" doesn't
                // become "see[ foo](…)".
                let kept = back.len() - back.trim_start().len();
                lo = k + back[..kept].chars().count();
                label = back.trim().to_string();
            }
        }
        edits.push((lo, hi, markdown_link(&f.url, &label)));
    }
    if edits.is_empty() {
        // Only unrecognised fields: strip the scaffolding in place.
        for r in runs.iter_mut() {
            if r.text.chars().any(is_field_control) {
                r.text = r.text.chars().filter(|c| !is_field_control(*c)).collect();
            }
        }
        return;
    }

    // Rebuild. Text outside the edits keeps the style of the run it came from.
    let mut out: Vec<SRun> = Vec::new();
    let push_span = |out: &mut Vec<SRun>, a: usize, b: usize| {
        let mut i = a;
        while i < b {
            let who = owner[i];
            let mut j = i;
            while j < b && owner[j] == who {
                j += 1;
            }
            let text: String = chars[i..j].iter().filter(|c| !is_field_control(**c)).collect();
            if !text.is_empty() {
                // Maths-object offsets are deliberately dropped here. This
                // rebuild deletes field-control characters, so every offset in
                // the run shifts by an amount that depends on where they were;
                // carrying them unadjusted would attach a fraction's descriptor
                // to the wrong U+FDD0. A paragraph holding BOTH a hyperlink and
                // an equation therefore converts with the fraction fallback —
                // exactly what every paragraph got before this sidecar existed.
                out.push(SRun {
                    text,
                    style: runs[who].style.clone(),
                    math_objs: Vec::new(),
                });
            }
            i = j;
        }
    };
    let mut at = 0usize;
    for (lo, hi, md) in &edits {
        push_span(&mut out, at, *lo);
        if !md.is_empty() {
            // Every emphasis flag cleared — see [`markdown_link`].
            let mut st = runs[owner[*lo]].style.clone();
            st.bold = false;
            st.italic = false;
            st.underline = false;
            st.strike = false;
            st.highlight = false;
            st.color = 0;
            st.is_math = false;
            st.sub = false;
            st.sup = false;
            // Generated Markdown, not the writer's characters: `run_markdown`
            // must not escape `~`/`^` inside it (see [`Style::verbatim_md`]).
            st.verbatim_md = true;
            out.push(SRun {
                text: md.clone(),
                style: st,
                math_objs: Vec::new(),
            });
        }
        at = *hi;
    }
    push_span(&mut out, at, chars.len());
    *runs = out;
}

/// Best-effort conversion of OneNote's Office linear-math Unicode (as stored in
/// a Cambria-Math run's 0x1C22 text) to LaTeX. Handles fraction delimiters
/// (U+FDD0 numerator … U+FDEE bar … U+FDEF end) and folds math-italic letters;
/// strips invisible operators. Unrecognised structure degrades to plain text.
/// Structure markers: U+FDD0 opens an object's argument list, U+FDEE separates
/// arguments, U+FDEF closes.
const MATH_OPEN: char = '\u{FDD0}';
const MATH_SEP: char = '\u{FDEE}';
const MATH_CLOSE: char = '\u{FDEF}';

/// Best-effort conversion of OneNote's Office linear-maths Unicode (as stored
/// in a Cambria-Math run's 0x1C22 text) to LaTeX, told what each U+FDD0
/// actually opens. Folds maths-italic letters and strips invisible operators;
/// unrecognised structure degrades to plain text rather than disappearing.
///
/// `objs` is `(char offset of the U+FDD0, descriptor)`, assembled by
/// [`styled_runs`] from [`PID_MATH_OBJECTS`] and reassembled by
/// [`render_runs`]. An offset with no descriptor — a file that predates the
/// sidecar, or a paragraph whose runs had to be rebuilt around a hyperlink —
/// falls back to the rule this function used for everything: a two-argument
/// object is a fraction. That fallback is why the reference notebook's
/// fractions were the one construct that always survived, and why nothing else
/// did.
fn office_math_to_latex(s: &str, objs: &[(usize, MathObj)]) -> String {
    // Fold FIRST, over the whole string: `fold_math_char` is one-char-in,
    // one-char-out, so every offset in `objs` still points where it did.
    let chars: Vec<char> = s.chars().map(fold_math_char).collect();
    let mut i = 0usize;
    let mut budget = 4096usize;
    math_seq(&chars, &mut i, objs, 0, &mut budget)
}

/// Convert one argument: characters, and the objects nested in them, up to the
/// next separator/close at this level (or the end of the input).
fn math_seq(
    chars: &[char],
    i: &mut usize,
    objs: &[(usize, MathObj)],
    depth: u32,
    budget: &mut usize,
) -> String {
    let mut out = String::new();
    // Literal characters accumulate until an object boundary, then convert as
    // one piece. Running `latexify_prose` over the ASSEMBLED string instead
    // would find the `cases` in `\begin{cases}` and wrap it as prose —
    // `\begin{\text{cases}}` — which renders as nothing at all.
    let mut lit = String::new();
    let flush = |lit: &mut String, out: &mut String| {
        if !lit.is_empty() {
            out.push_str(&latexify_prose(&collapse_spaces(lit)));
            lit.clear();
        }
    };
    while *i < chars.len() {
        let c = chars[*i];
        if c == MATH_SEP || c == MATH_CLOSE {
            break; // the caller owns this marker
        }
        if c == MATH_OPEN {
            let at = *i;
            *i += 1;
            // Runaway guards: a malformed file must degrade, not hang. Depth
            // also bounds the recursion this function does on its own stack.
            if depth > 32 || *budget == 0 {
                continue;
            }
            *budget -= 1;
            let mut args: Vec<String> = Vec::new();
            loop {
                args.push(math_seq(chars, i, objs, depth + 1, budget));
                match chars.get(*i) {
                    Some(&MATH_SEP) => *i += 1,
                    Some(&MATH_CLOSE) => {
                        *i += 1;
                        break;
                    }
                    // Truncated input: take what we have rather than lose it.
                    _ => break,
                }
            }
            let obj = objs.iter().find(|(o, _)| *o == at).map(|(_, m)| m);
            flush(&mut lit, &mut out);
            out.push_str(&render_math_obj(obj, &args));
            continue;
        }
        // Carriage returns and NULs are not text (see [`run_markdown`]), and
        // dropping them HERE rather than in the caller is what lets the caller
        // hand us the run's untouched string — every offset in `objs` is an
        // index into that string, and pre-filtering it would slide them.
        if !is_math_control(c) && c != '\r' && c != '\0' {
            lit.push(c);
        }
        *i += 1;
    }
    flush(&mut lit, &mut out);
    out
}

/// Runs of whitespace → one space, leading/trailing kept (they are what makes
/// `\text{ if }` read as " if " rather than "if", and maths mode eats the
/// difference otherwise).
fn collapse_spaces(s: &str) -> String {
    let core = s.split_whitespace().collect::<Vec<_>>().join(" ");
    if core.is_empty() {
        return if s.is_empty() { String::new() } else { " ".into() };
    }
    let lead = if s.starts_with(char::is_whitespace) { " " } else { "" };
    let trail = if s.ends_with(char::is_whitespace) { " " } else { "" };
    format!("{lead}{core}{trail}")
}

/// `{x}`, with the argument trimmed — LaTeX ignores the spaces anyway, and
/// braces keep multi-character arguments together under `_`, `^` and `\frac`.
fn grp(s: &str) -> String {
    format!("{{{}}}", s.trim())
}

/// One maths object → LaTeX. `obj` is `None` when the file gave us no
/// descriptor for this U+FDD0; see [`office_math_to_latex`].
fn render_math_obj(obj: Option<&MathObj>, args: &[String]) -> String {
    let empty = String::new();
    let a = |n: usize| args.get(n).unwrap_or(&empty).trim().to_string();
    let Some(o) = obj else {
        return unknown_math_obj(args);
    };
    match o.kind {
        MATH_FRACTION => format!("\\frac{}{}", grp(&a(0)), grp(&a(1))),
        MATH_NO_BAR => format!("{{{} \\atop {}}}", a(0), a(1)),
        MATH_SUB => format!("{}_{}", grp(&a(0)), grp(&a(1))),
        MATH_SUP => format!("{}^{}", grp(&a(0)), grp(&a(1))),
        MATH_SUB_SUP => format!("{}_{}^{}", grp(&a(0)), grp(&a(1)), grp(&a(2))),
        MATH_RADICAL => {
            // Two arguments are (degree, radicand); OneNote leaves the degree
            // empty for a plain square root rather than dropping the slot.
            if args.len() >= 2 && !a(0).is_empty() {
                format!("\\sqrt[{}]{}", a(0), grp(&a(1)))
            } else {
                format!("\\sqrt{}", grp(&a(args.len().saturating_sub(1))))
            }
        }
        MATH_ACCENT => match accent_cmd(o.beg) {
            Some(cmd) => format!("{cmd}{}", grp(&a(0))),
            // An accent we cannot name must not silently vanish the letter
            // under it.
            None => grp(&a(0)),
        },
        MATH_UNDERBAR => format!("\\underline{}", grp(&a(0))),
        MATH_NARY => {
            // (lower, upper, body). Empty limits are the common case for ∫ and
            // must not become `\int_{}^{}`, which KaTeX renders as empty boxes.
            let mut out = nary_cmd(o.beg);
            if !a(0).is_empty() {
                out.push_str(&format!("_{}", grp(&a(0))));
            }
            if !a(1).is_empty() {
                out.push_str(&format!("^{}", grp(&a(1))));
            }
            out.push(' ');
            out.push_str(&a(2));
            out
        }
        MATH_FUNC => format!("{} {}", func_cmd(&a(0)), a(1)),
        // The limit sits UNDER the operator, which is what `\lim_{x → 0}`
        // means; `\underset` says it for any base, named operator or not.
        MATH_LIM_LOW => format!("\\underset{}{{{}}}", grp(&a(1)), func_cmd(&a(0))),
        MATH_MATRIX => {
            let cols = if o.cols == 0 { 1 } else { o.cols as usize };
            // Empty CELLS are kept: a blank cell is a position in the grid, and
            // dropping one would slide every later entry into the wrong column.
            format!("\\begin{{matrix}}{}\\end{{matrix}}", math_grid(args, cols))
        }
        MATH_EQ_ARRAY => {
            let cols = if o.cols == 0 { 1 } else { o.cols as usize };
            // Empty ROWS are dropped, which a matrix's cells are not. OneNote
            // records the blank line a writer left between two branches of a
            // piecewise definition as a real row — the reference page's has
            // three rows for two branches — and it carries no content, only the
            // risk that a renderer chokes on `\\ \\` and loses the whole
            // equation. The vertical gap is not worth that trade.
            let rows: Vec<String> = args
                .chunks(cols.max(1))
                .filter(|row| row.iter().any(|c| !c.trim().is_empty()))
                .map(|row| row.iter().map(|c| c.trim()).collect::<Vec<_>>().join(" & "))
                .collect();
            // One row is not an array. OneNote uses a two-row array with the
            // second row empty for the top half of a binomial coefficient, and
            // wrapping that lone `n` in `\begin{aligned}` both reads as noise
            // and — because a stacked environment is what promotes an equation
            // out of its sentence — moved prose maths into a block of its own.
            match rows.len() {
                0 => String::new(),
                1 => rows.into_iter().next().unwrap_or_default(),
                _ => format!("\\begin{{aligned}}{}\\end{{aligned}}", rows.join(" \\\\ ")),
            }
        }
        MATH_DELIM | MATH_DELIM_SEP => render_math_delim(o, args),
        _ => unknown_math_obj(args),
    }
}

/// Cells → `a & b \\ c & d`, row-major over `cols` columns.
fn math_grid(args: &[String], cols: usize) -> String {
    args.chunks(cols.max(1))
        .map(|row| row.iter().map(|c| c.trim()).collect::<Vec<_>>().join(" & "))
        .collect::<Vec<_>>()
        .join(" \\\\ ")
}

/// A bracketed group: `(x)`, `|x|`, `⌊x⌋`, or the big brace of a piecewise
/// definition.
fn render_math_delim(o: &MathObj, args: &[String]) -> String {
    let inner = args.iter().map(|a| a.trim()).collect::<Vec<_>>().join(" \\mid ");
    // The piecewise definition. OneNote writes it as a left brace with NO
    // closing character wrapped around an equation array — which is exactly
    // what `\begin{cases}` is — and rendering it as `\left\{\begin{aligned}…`
    // would put the brace and the rows in two different groups. This is the
    // shape the owner's reference page uses and the one that came back as a
    // flat run of text with the brace gone.
    if o.beg == Some('{') && o.end.is_none() && args.len() == 1 {
        if let Some(rows) = args[0]
            .trim()
            .strip_prefix("\\begin{aligned}")
            .and_then(|r| r.strip_suffix("\\end{aligned}"))
        {
            return format!("\\begin{{cases}}{rows}\\end{{cases}}");
        }
    }
    format!("\\left{}{inner}\\right{}", latex_delim(o.beg), latex_delim(o.end))
}

/// No descriptor: keep the old rule, which is right far more often than not —
/// a two-argument object in a student's notes is nearly always a fraction.
fn unknown_math_obj(args: &[String]) -> String {
    match args.len() {
        0 => String::new(),
        1 => grp(args[0].trim()),
        2 => format!("\\frac{}{}", grp(args[0].trim()), grp(args[1].trim())),
        _ => args.iter().map(|a| a.trim()).collect::<Vec<_>>().join(" "),
    }
}

/// A delimiter character as LaTeX. `.` is `\left`/`\right`'s "no delimiter",
/// which is what an absent one means (the `┤` of a piecewise definition).
fn latex_delim(c: Option<char>) -> String {
    match c {
        None => ".".into(),
        Some('{') => "\\{".into(),
        Some('}') => "\\}".into(),
        Some('\u{2016}') => "\\|".into(),
        Some('\u{230A}') => "\\lfloor".into(),
        Some('\u{230B}') => "\\rfloor".into(),
        Some('\u{2308}') => "\\lceil".into(),
        Some('\u{2309}') => "\\rceil".into(),
        Some('\u{27E8}') | Some('<') => "\\langle".into(),
        Some('\u{27E9}') | Some('>') => "\\rangle".into(),
        Some(c @ ('(' | ')' | '[' | ']' | '|' | '/')) => c.to_string(),
        // Anything else is not a delimiter LaTeX knows; sizing it would be a
        // parse error, so the group simply has no bracket on that side.
        Some(_) => ".".into(),
    }
}

/// The combining accent OneNote records → the LaTeX command that draws it.
fn accent_cmd(c: Option<char>) -> Option<&'static str> {
    Some(match c? {
        '\u{0300}' => "\\grave",
        '\u{0301}' => "\\acute",
        '\u{0302}' => "\\hat",
        '\u{0303}' => "\\tilde",
        '\u{0304}' => "\\bar",
        '\u{0305}' => "\\overline",
        '\u{0306}' => "\\breve",
        '\u{0307}' => "\\dot",
        '\u{0308}' => "\\ddot",
        '\u{030A}' => "\\mathring",
        '\u{030C}' => "\\check",
        '\u{20D0}' => "\\overleftarrow",
        '\u{20D1}' | '\u{20D7}' => "\\vec",
        '\u{20DB}' => "\\dddot",
        _ => return None,
    })
}

/// The n-ary operator character → its LaTeX command. Unknown operators pass
/// through as the character itself, which is what they did before.
fn nary_cmd(c: Option<char>) -> String {
    match c {
        Some('\u{2211}') => "\\sum".into(),
        Some('\u{220F}') => "\\prod".into(),
        Some('\u{2210}') => "\\coprod".into(),
        Some('\u{222B}') => "\\int".into(),
        Some('\u{222C}') => "\\iint".into(),
        Some('\u{222D}') => "\\iiint".into(),
        Some('\u{222E}') => "\\oint".into(),
        Some('\u{22C0}') => "\\bigwedge".into(),
        Some('\u{22C1}') => "\\bigvee".into(),
        Some('\u{22C2}') => "\\bigcap".into(),
        Some('\u{22C3}') => "\\bigcup".into(),
        Some('\u{2A01}') => "\\bigoplus".into(),
        Some('\u{2A02}') => "\\bigotimes".into(),
        Some('\u{2A04}') => "\\biguplus".into(),
        Some(c) => c.to_string(),
        None => String::new(),
    }
}

/// A function name applied to an argument. LaTeX has upright operators for the
/// standard ones; without them `sin θ` is typeset as the product s·i·n·θ, and
/// `latexify_prose` would wrap the word as `\text{sin}` — right shape, wrong
/// spacing, and wrong for `\lim`, which also needs its limit set underneath.
fn func_cmd(name: &str) -> String {
    const KNOWN: &[&str] = &[
        "arccos", "arcsin", "arctan", "arg", "cos", "cosh", "cot", "coth", "csc", "deg", "det",
        "dim", "exp", "gcd", "hom", "inf", "ker", "lg", "lim", "liminf", "limsup", "ln", "log",
        "max", "min", "sec", "sin", "sinh", "sup", "tan", "tanh",
    ];
    // The name arrives already converted, so a real word came through
    // `latexify_prose` as `\text{cos}`; unwrap that before matching.
    let bare = name
        .trim()
        .strip_prefix("\\text{")
        .and_then(|r| r.strip_suffix('}'))
        .unwrap_or(name)
        .trim();
    if KNOWN.contains(&bare) {
        format!("\\{bare}")
    } else {
        bare.to_string()
    }
}

/// Unwrap inline `$…$` spans that never needed to be maths.
///
/// **For notes that were imported before the fix.** A character inserted from
/// OneNote's symbol palette arrives as a maths run, and every maths run used to
/// be wrapped in `$…$` — so a page reads correctly until you click into it and
/// find `$∀$` in the middle of your sentence. Fixing the importer does nothing
/// for a notebook already on disk; by then the delimiters are stored user data.
///
/// The test is the same one the importer now applies: a span whose content is
/// character-for-character what it would render as is not notation, it is a
/// character. Anything containing a backslash command, a script marker or a
/// brace is left exactly alone, so real equations are never touched.
pub fn unwrap_needless_math(text: &str) -> String {
    let chars: Vec<char> = text.chars().collect();
    let mut out = String::with_capacity(text.len());
    let mut i = 0;
    while i < chars.len() {
        if chars[i] != '$' {
            out.push(chars[i]);
            i += 1;
            continue;
        }
        // `$$` is display maths on its own line — a different dialect, and not
        // this function's business.
        if chars.get(i + 1) == Some(&'$') {
            out.push('$');
            out.push('$');
            i += 2;
            continue;
        }
        match chars[i + 1..].iter().position(|c| *c == '$') {
            Some(rel) => {
                let inner: String = chars[i + 1..i + 1 + rel].iter().collect();
                if inner.is_empty() || is_real_notation(&inner) {
                    out.push('$');
                    i += 1;
                } else {
                    out.push_str(&inner);
                    i += rel + 2;
                }
            }
            // An unpaired `$` is just a dollar sign.
            None => {
                out.push('$');
                i += 1;
            }
        }
    }
    out
}

/// Does this span actually need typesetting?
fn is_real_notation(inner: &str) -> bool {
    inner.contains('\\')
        || inner.contains('^')
        || inner.contains('_')
        || inner.contains('{')
        || inner.contains('}')
}

/// Wrap prose words (≥2 consecutive letters) in `\text{…}`, grouping runs of
/// words so their spaces survive LaTeX math mode. OneNote math zones freely mix
/// sentences with symbols ("A path is a sequence of edges e1, …, en ∈ E such
/// that …"); rendered as raw math the words mash together ("Apathisasequence…")
/// because math mode ignores spaces. Single letters stay math-italic variables;
/// existing `\commands` pass through untouched.
fn latexify_prose(s: &str) -> String {
    let chars: Vec<char> = s.chars().collect();
    let mut out = String::new();
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        if c == '\\' {
            // A LaTeX command (e.g. \frac): copy the backslash + name verbatim.
            out.push(c);
            i += 1;
            while i < chars.len() && chars[i].is_ascii_alphabetic() {
                out.push(chars[i]);
                i += 1;
            }
            continue;
        }
        if c.is_alphabetic() {
            let start = i;
            while i < chars.len() && chars[i].is_alphabetic() {
                i += 1;
            }
            if i - start < 2 {
                out.push(chars[start]); // single letter → math variable
                continue;
            }
            // Prose group: this word plus any following space-separated words.
            let mut group: String = chars[start..i].iter().collect();
            loop {
                let sp = i;
                while i < chars.len() && chars[i] == ' ' {
                    i += 1;
                }
                let w = i;
                while i < chars.len() && chars[i].is_alphabetic() {
                    i += 1;
                }
                // A single letter ("a", "I") counts as prose when the word
                // after it is prose too ("is a sequence"); otherwise it's a
                // math variable ("edges e1", "for all i ∈") and ends the group.
                let prose = i - w >= 2
                    || (i - w == 1 && {
                        let mut j = i;
                        while j < chars.len() && chars[j] == ' ' {
                            j += 1;
                        }
                        let ws = j;
                        while j < chars.len() && chars[j].is_alphabetic() {
                            j += 1;
                        }
                        j > ws && j - ws >= 2
                    });
                if prose && i > w {
                    group.push(' ');
                    group.push_str(&chars[w..i].iter().collect::<String>());
                } else {
                    i = w; // put back the non-word (variable/symbol/space run)
                    // Keep the boundary spaces readable: math mode would eat
                    // them, so fold one into the \text group on each side.
                    if out.ends_with(' ') {
                        out.pop();
                        group.insert(0, ' ');
                    }
                    out.push_str("\\text{");
                    out.push_str(&group);
                    if w > sp {
                        out.push(' '); // trailing space inside \text
                    }
                    out.push('}');
                    break;
                }
            }
            continue;
        }
        out.push(c);
        i += 1;
    }
    out
}

/// A colour word for the Markdown projection, or None for black/auto/unset.
/// OneNote stores the colour low-byte-first (R,G,B); the high byte is a flag.
fn color_hex(color: u32) -> Option<String> {
    if color == 0 || (color & 0x00FF_FFFF) == 0 {
        return None; // unset or black
    }
    let (r, g, b) = (color & 0xFF, (color >> 8) & 0xFF, (color >> 16) & 0xFF);
    Some(format!("{r:02X}{g:02X}{b:02X}"))
}

/// Wrap each whitespace-free WORD of `s` in `mark`, keeping the spacing
/// between them: `a b` with `~` becomes `~a~ ~b~`, never `~a b~`.
///
/// The app's grammar is Pandoc's, and Pandoc forbids whitespace inside the
/// markers (`~(?!~)([^\s~]+)~(?!~)`). That rule is what keeps "about ~5 to
/// ~10", "a ~ b" and `~/Documents` literal on screen — and it means a pair
/// spanning a space matches NOTHING and renders as two visible tildes. A
/// OneNote subscript run is usually one or two characters, but it can be a
/// phrase, and that phrase would have arrived with its markers showing.
///
/// A word already containing the marker cannot be marked at all — the inner
/// class excludes it — so those are left plain rather than wrapped in a pair
/// that would render as literal punctuation around the word. Losing the
/// baseline shift on such a word beats printing tildes at the reader.
fn mark_each_word(s: &str, mark: char) -> String {
    let mut out = String::with_capacity(s.len() + 4);
    let mut word = String::new();
    fn flush(word: &mut String, out: &mut String, mark: char) {
        if word.is_empty() {
            return;
        }
        if word.contains(mark) {
            out.push_str(word);
        } else {
            out.push(mark);
            out.push_str(word);
            out.push(mark);
        }
        word.clear();
    }
    for c in s.chars() {
        if c.is_whitespace() {
            flush(&mut word, &mut out, mark);
            out.push(c);
        } else {
            word.push(c);
        }
    }
    flush(&mut word, &mut out, mark);
    out
}

/// Render one styled run as Markdown, applying bold/italic/strike (Openote's
/// live-Markdown dialect) and the `{{#RRGGBB …}}` colour extension.
fn run_markdown(run: &SRun) -> String {
    // NULs go with the carriage returns. `styled_runs` strips only a TRAILING
    // NUL — deliberately, so run-index offsets stay valid — which leaves
    // interior ones in prose. Every other emit path already strips them (tag
    // labels, maths runs, display equations, bullets, titles); prose was the
    // gap. They are not text, they render as nothing, and downstream they are
    // actively destructive: the app's field-code repair hands note text to a
    // C API as a NUL-terminated string, so one interior NUL amputated the
    // rest of the page the first time it was opened, permanently.
    let mut s: String = run.text.chars().filter(|c| *c != '\r' && *c != '\0').collect();
    if s.trim().is_empty() {
        return s;
    }
    // Preserve leading/trailing spaces outside the emphasis markers.
    let lead: String = s.chars().take_while(|c| *c == ' ').collect();
    let trail: String = s.chars().rev().take_while(|c| *c == ' ').collect();
    // A math run sitting inside a prose paragraph becomes INLINE math (`$…$`,
    // the app's TEXT-1a dialect) instead of promoting the whole paragraph to a
    // display equation. OneNote renders these inline too — "E ∩ O = ⊘" belongs
    // in the sentence, it is not a centred equation.
    //
    // If conversion yields nothing, fall back to the folded plain characters.
    // Dropping the run would delete the user's writing, and that is never the
    // right trade — an empty conversion is exactly what used to empty whole
    // pages of content.
    if run.style.is_math {
        let src = s.trim_end_matches('\0');
        let plain: String = src
            .chars()
            .map(fold_math_char)
            .filter(|c| !is_math_control(*c) && *c != '\0')
            .collect();
        // Converted from the run's UNTOUCHED text: `s` above dropped `\r` and
        // `\0`, and every offset in `math_objs` indexes the original string.
        let latex = office_math_to_latex(&run.text, &run.math_objs);
        if latex.trim().is_empty() {
            return plain;
        }
        // **A symbol is not an equation.** OneNote marks a single character as
        // a math run the moment you insert it from the symbol palette, so a
        // sentence like "for all x in S" came back as "$∀$ x in S": rendered
        // correctly in the read-only view, and then showing raw `$∀$` the
        // instant you clicked into the box. Reported as exactly that.
        //
        // The test is whether the conversion actually produced any LaTeX. When
        // the "LaTeX" is character-for-character the plain text, there is no
        // notation to typeset — it is a character the app's font chain already
        // renders — so emit the character and leave the delimiters out. A real
        // equation converts to something different (\frac, ^, _, \sum) and
        // still gets its `$…$`.
        // Compared after normalising BOTH the same way, which the first
        // attempt at this did not do — and that is why it looked fixed and
        // wasn't. `office_math_to_latex` strips trailing NULs and collapses
        // runs of whitespace; the plain string did neither, and `str::trim`
        // does not remove a NUL because a NUL is not whitespace. So the
        // comparison was "∀" against "∀\0", which never matches, and every
        // symbol stayed wrapped exactly as before.
        let norm = |x: &str| x.split_whitespace().collect::<Vec<_>>().join(" ");
        if norm(&latex) == norm(&plain) {
            return plain;
        }
        return format!("{lead}${latex}${trail}");
    }
    let mut core = s[lead.len()..s.len() - trail.len()].to_string();
    // Innermost, next to the characters: sub/superscript is a property of the
    // glyphs, so `**a~1~**` (bold containing a subscript) is right and
    // `~**a**1~` is not. Pandoc's single-tilde/single-caret dialect, which the
    // app's Markdown grammar now parses — note `~~x~~` is strikethrough below,
    // and a run that is both lands as `~~~x~~~`, which is what OneNote means.
    //
    // Nothing is escaped on the way out, and that is a decision, not an
    // oversight: the app's inline grammar has NO backslash escape (only
    // `md_table.dart` unescapes, and only `\|`), so emitting `\~` would put a
    // visible backslash in the note — a certain, widespread regression traded
    // against a rare one. What guards a literal tilde instead is the grammar's
    // own Pandoc rule that the marked text may contain no whitespace, so
    // "roughly ~5 to ~10" and "a ~ b" stay literal. The gap it leaves —
    // `x~y~z`, with no space between the two markers — occurs 0 times in the
    // 355 pages of the reference notebook, measured.
    if run.style.sub {
        core = mark_each_word(&core, '~');
    }
    if run.style.sup {
        core = mark_each_word(&core, '^');
    }
    if run.style.underline {
        // `++u++` — the app's dialect (Markdown has none, and `__x__` is bold).
        // Underline was parsed here and then silently discarded, so underlined
        // OneNote text imported as plain text.
        core = format!("++{core}++");
    }
    if run.style.strike {
        core = format!("~~{core}~~");
    }
    if run.style.highlight {
        core = format!("=={core}==");
    }
    if run.style.bold && run.style.italic {
        core = format!("***{core}***");
    } else if run.style.bold {
        core = format!("**{core}**");
    } else if run.style.italic {
        core = format!("*{core}*");
    }
    if let Some(hex) = color_hex(run.style.color) {
        core = format!("{{{{#{hex} {core}}}}}");
    }
    s = format!("{lead}{core}{trail}");
    s
}

/// One rendered paragraph: indent depth, whether OneNote marked it a list item,
/// its bullet string, the styled runs, and (if it's a math paragraph) LaTeX.
/// A note tag OneNote applied to one paragraph.
///
/// Carries the label and the icon index rather than a mapped kind: the mapping
/// to Openote's built-ins is the app's business (that is where `TagKind`
/// lives), and an unrecognised label must survive as a custom tag rather than
/// being dropped on the way through.
#[derive(Clone, Debug, Serialize)]
pub struct ParaTag {
    /// OneNote's own name for it, e.g. "To Do".
    pub label: String,
    /// OneNote's icon index (0x3464). Kept because it is locale-independent
    /// where the label is not — a German notebook says "Aufgabe" — and a later
    /// pass can map by shape once there is a fixture to verify the table
    /// against. Nothing reads it yet.
    pub shape: u32,
}

struct Line {
    depth: usize,
    is_list: bool,
    /// Tags on this paragraph, if OneNote put any there.
    tags: Vec<ParaTag>,
    bullet: String,
    runs: Vec<SRun>,
    math: Option<String>,
    /// A table sitting in the outline flow, already reduced to its cell grid.
    table: Option<TableGrid>,
    /// An image sitting in the outline flow (a list item that IS an image):
    /// the image object's OID. Rendered as its own block whose height advances
    /// the flow, so following text (and the boxes below) keep their spacing.
    image: Option<u32>,
}

impl Line {
    /// Plain text (styling stripped), for dedup keys and title filtering.
    fn plain(&self) -> String {
        if let Some(m) = &self.math {
            return m.clone();
        }
        self.runs.iter().map(|r| r.text.as_str()).collect()
    }

    /// True for a line that renders as an empty paragraph — a blank line the
    /// writer typed (see the `JCID_RICHTEXT_RUN` branch in [collect_inner]).
    ///
    /// Kept as one predicate because three places have to agree on it, and
    /// they disagreed once already: a blank still carries the `depth` of the
    /// paragraph it sat in, so when `emit_boxes` let it into the indent
    /// baseline a blank one level out from the text re-based the whole box and
    /// pushed every line right — measured on five pages of the reference
    /// notebook ("Pigeonhole Principle", "Permutations", …). A blank emits no
    /// indent of its own, so it must not define the indent of its neighbours.
    fn is_blank(&self) -> bool {
        self.image.is_none()
            && self.math.is_none()
            && self.table.is_none()
            && self.runs.iter().all(|r| r.text.trim().is_empty())
    }
}

/// Reduce a table object to a rectangular grid of per-cell Markdown.
///
/// The shape is uniform: table → rows → cells, each level listing its children
/// in `0x1C20`, and a cell holds ordinary outline content. So each cell is just
/// another `collect_tree` + `outline_markdown`, which means cell text keeps its
/// bold/italic/colour/inline-maths exactly as body text does.
///
/// Rows are padded to the declared column count (`0x1D58`) because the app's
/// table view requires a rectangle, and a ragged row would otherwise be padded
/// silently at render time instead of here where the intent is visible.
fn parse_table(
    r: &Reader,
    o: &Obj,
    res: &Resolver,
    img_idx: &HashMap<u32, String>,
) -> TableGrid {
    let ps = read_propset(r, o.stp, o.cb);
    let declared_cols = ps.u32(PID_TABLE_COLS).unwrap_or(0) as usize;
    let declared_rows = ps.u32(PID_TABLE_ROWS).unwrap_or(0) as usize;
    if std::env::var("ONOTE_TABLE_DEBUG").is_ok() {
        eprintln!("TABLE rows={declared_rows} cols={declared_cols}");
        for (pid, v) in &ps.props {
            eprintln!(
                "  pid=0x{:06X} {}",
                pid,
                match v {
                    PVal::Bool(b) => format!("bool {b}"),
                    PVal::U32(n) => format!("u32 {n} (f32 {})", f32::from_bits(*n)),
                    PVal::U64(n) => format!("u64 {n}"),
                    PVal::Str(b) => format!("str[{}] {:?}", b.len(), decode_utf16(b)),
                    PVal::Oids(v) => format!("oids[{}]", v.len()),
                    PVal::Osids(v) => format!("osids[{}]", v.len()),
                    PVal::Array(sets) => {
            let inner: Vec<String> = sets
                .iter()
                .map(|s| {
                    let ps: Vec<String> = s
                        .props
                        .iter()
                        .map(|(pid, v)| format!("{pid:06X}={}", fmt_pval(v)))
                        .collect();
                    format!("{{{}}}", ps.join(" "))
                })
                .collect();
            format!("array[{}]{}", sets.len(), inner.join(""))
        }
        PVal::Other(t) => format!("other(type=0x{t:02X})"),
                }
            );
        }
    }
    let mut grid: Vec<Vec<String>> = Vec::new();
    for rid in ps.oids(0x001C20) {
        let Some(ri) = res.get(rid, o.rev) else { continue };
        let row = res.obj(ri);
        if row.jcid != JCID_TABLE_ROW {
            continue;
        }
        let row_ps = read_propset(r, row.stp, row.cb);
        let mut cells: Vec<String> = Vec::new();
        for cid in row_ps.oids(0x001C20) {
            let Some(ci) = res.get(cid, row.rev) else { continue };
            let cell = res.obj(ci);
            if cell.jcid != JCID_TABLE_CELL {
                continue;
            }
            let mut lines: Vec<Line> = Vec::new();
            let mut guard = HashSet::new();
            collect_tree(r, cell, res, 0, &mut lines, &mut guard);
            let refs: Vec<&Line> = lines.iter().collect();
            cells.push(outline_markdown(&refs, img_idx, None).trim().to_string());
        }
        if !cells.is_empty() {
            grid.push(cells);
        }
    }
    if grid.is_empty() {
        return TableGrid::default();
    }
    // Rectangularise: widest actual row, but never narrower than declared.
    let cols = grid.iter().map(|r| r.len()).max().unwrap_or(0).max(declared_cols);
    for row in &mut grid {
        while row.len() < cols {
            row.push(String::new());
        }
    }
    debug_assert!(declared_rows == 0 || grid.len() <= declared_rows.max(grid.len()));
    // Column widths: `u8` count, then that many little-endian f32s. Trust the
    // array only if its own count agrees with the byte length *and* covers the
    // columns we found — a partial or mismatched array would stretch the wrong
    // columns, which looks worse than uniform ones.
    let col_w = ps
        .bytes(PID_TABLE_COL_WIDTHS)
        .and_then(|b| {
            let n = *b.first()? as usize;
            if n == 0 || b.len() < 1 + n * 4 {
                return None;
            }
            let w: Vec<f32> = (0..n)
                .map(|i| {
                    let o = 1 + i * 4;
                    f32::from_le_bytes([b[o], b[o + 1], b[o + 2], b[o + 3]]) * UNIT_PX
                })
                .collect();
            // Every width must be a sane, finite, positive size.
            if w.iter().any(|v| !v.is_finite() || *v <= 1.0 || *v > 4000.0) || w.len() < cols {
                return None;
            }
            Some(w)
        })
        .unwrap_or_default();
    TableGrid { cells: grid, col_w }
}

/// A parsed table: rectangular cell grid plus the column widths OneNote
/// recorded for it. The two travel together because a grid whose widths came
/// from a different table would be worse than no widths at all.
#[derive(Clone, Default)]
struct TableGrid {
    cells: Vec<Vec<String>>,
    /// Page px, one per column of `cells`. Empty when unrecorded.
    col_w: Vec<f32>,
}

impl TableGrid {
    fn is_empty(&self) -> bool {
        self.cells.is_empty()
    }
}

fn is_zero(v: &u32) -> bool {
    *v == 0
}

/// A table's total width, when OneNote recorded its columns. `None` leaves the
/// app to size the table from its content.
fn table_width(g: &TableGrid) -> Option<f32> {
    let total: f32 = g.col_w.iter().sum();
    (total > 1.0).then_some(total)
}

/// Every object canonically reachable from `roots`, following object references
/// exactly as [collect_tree] does (`parse_obj` children, resolved through the
/// referencing object's revision by [Resolver]).
///
/// This is what tells LIVE page content from content the page no longer has.
/// Erasing ink in OneNote does **not** remove the ink objects from the file — it
/// writes a new revision whose page node simply stops referencing them, and the
/// orphaned objects stay behind forever. A flat scan of the object space
/// therefore resurrects every stroke ever erased on a page: measured on the
/// reference notebook, the "Symbols" page imported 39 strokes that OneNote does
/// not show, because its live page node lists 6 children while a stored page
/// VERSION lists 43. Across that notebook 536 of 64 616 strokes were such
/// ghosts, and not one of them was referenced by any live-revision object.
/// (356 of those went when reachability was first measured from the outline
/// containers a scan found; the last 180 needed [live_anchor], because on one
/// page the scan's own starting point was a version snapshot.)
///
/// Reachability subsumes [currency] for this purpose: you can only reach what
/// the current page points at. The reverse test — "does this object have a
/// declaration outside a version revision?" — is NOT equivalent and must not be
/// substituted: 180 containers on the same notebook hold live ink whose only
/// stored declaration sits inside a version revision (unchanged since, so no
/// newer copy was ever written), and dropping those would delete ink the user
/// can still see.
fn reachable_canons(r: &Reader, res: &Resolver, roots: &[usize]) -> HashSet<u32> {
    let mut seen: HashSet<u32> = HashSet::new();
    let mut stack: Vec<usize> = roots.to_vec();
    while let Some(i) = stack.pop() {
        let o = res.obj(i);
        // Every referenced OID, not a hand-picked list of properties: ink can
        // hang off a table cell, an outline group or an image just as well as
        // off the page node, and a PID allow-list would silently delete it.
        let (_text, kids) = parse_obj(r, o.stp, o.cb);
        for k in kids {
            if seen.insert(res.canon(k, o.rev)) {
                if let Some(ki) = res.get(k, o.rev) {
                    stack.push(ki);
                }
            }
        }
    }
    seen
}

/// Everything the object space's LIVE root still reaches: the single authority
/// the text, image, table and ink collectors all answer to.
///
/// Every revision manifest names its own roots ([FNID_ROOT_OBJECT_REF3]), and
/// the manifest with no revision context names the space AS IT STANDS. That is
/// the file's own answer to "what is on this page", and the importer used to
/// guess at it instead — each collector with a different flat scan of the space,
/// so each resurrected a different kind of deleted content. Measured on the
/// reference notebook: **329 of 329 pages** resolve exactly one live role-1
/// root, a PageNode, and 664 objects sit in those spaces that the roots do not
/// reach — not one of which is referenced by any live-revision declaration
/// anywhere in the file.
///
/// The walk descends through [Resolver::get], so every hop lands on the object's
/// CURRENT declaration. That is what a root-anchored walk buys over rooting on
/// whatever declaration a scan happened to find: on "Working out" the live
/// outline lists no children while a stored version of it lists 180 ink
/// containers, and a scan that starts at the version's declaration walks
/// straight into 180 erased strokes.
///
/// `None` — no roots, roots that disagree, or a root we cannot resolve to a
/// PageNode/SectionNode declaration — means we have no evidence about this
/// space, and every caller must then fall back to its unanchored behaviour. No
/// evidence is not evidence of absence, and deleting a page's content because we
/// failed to read its root is far worse than importing something stale.
fn live_anchor(
    r: &Reader,
    res: &Resolver,
    roots: Option<&Vec<[u8; 20]>>,
    registry: &HashMap<[u8; 20], u32>,
) -> Option<HashSet<u32>> {
    let roots = roots?;
    let first = *roots.first()?;
    // A space that names two different live content roots tells us nothing we
    // can act on; guessing between them is how a page loses the wrong half.
    if roots.iter().any(|e| *e != first) {
        return None;
    }
    // Object identity is keyed on a CompactID's 8-bit `n` (see [Resolver]), so
    // an ExtendedGUID whose `n` needs more than a byte cannot be matched back to
    // a declaration — better no anchor than the wrong object.
    if u32::from_le_bytes([first[16], first[17], first[18], first[19]]) > 0xFF {
        return None;
    }
    let mut key = first;
    key[17..20].fill(0);
    let canon = registry.get(&key).map(|&n| n | CANON_BIT)?;
    let i = res.by_canon.get(&canon).copied()?;
    // The role names a content root; if it does not resolve to one of the two
    // objects that can BE a content root, we have misread something and the
    // reachable set would be arbitrary.
    if !matches!(res.obj(i).jcid, JCID_PAGE_NODE | JCID_SECTION_NODE) {
        return None;
    }
    let mut set = reachable_canons(r, res, &[i]);
    set.insert(canon); // the root is on the page too (ink can hang off it)
    Some(set)
}

/// The page's outline containers: the current declaration of every outline or
/// outline group the LIVE root still reaches, in file order. These are the roots
/// the text walk descends, one box per child.
///
/// ALL of the page's containers, not just one. A OneNote page stores its
/// content in several outlines (a page with separate text areas has one per
/// area), and this used to take a single `max_by_key(stp)` outline, silently
/// discarding the rest: measured on one real section, pages had up to **5**
/// qualifying outlines while we read 1, and 11 pages had *no* qualifying outline
/// at all and so imported completely empty despite holding text. That is the
/// "content beyond the first couple of lines is missing" report. An OutlineGroup
/// counts as a container for the same reason — a page can hang its content off a
/// group rather than a plain outline, and scanning only for JCID_OUTLINE left
/// those pages empty.
///
/// Taking all of them cannot duplicate anything: each canonical container
/// appears once, at one declaration, and `seen_box` in the caller covers a group
/// that is also reachable from an outline.
///
/// `live` is the page's [live_anchor]; `None` disables both anchor-dependent
/// rules and restores exactly the scan this had before.
fn live_box_roots(
    r: &Reader,
    res: &Resolver,
    idxs: &[usize],
    live: Option<&HashSet<u32>>,
) -> Vec<usize> {
    let children = |i: usize| {
        let o = res.obj(i);
        read_propset(r, o.stp, o.cb).oids(PID_ELEMENT_CHILDREN).len()
    };
    // Live content first, then the RICHEST declaration of this container, and
    // only then file order.
    //
    // A revision's declaration can be a partial stub: on a real page the
    // newest-by-offset declaration listed 2 paragraphs while an earlier one
    // listed the page's full content (and OneNote itself still shows all of it).
    // That symptom is what [currency] explains — the fuller declaration was the
    // live revision and the stub a page-version snapshot — but child count stays
    // as the second key, because it costs nothing and it is the one rule that
    // cannot lose text.
    let rank = |i: usize| (currency(res.obj(i)).0, children(i), res.obj(i).stp);
    // Scan EVERY object in the space (not `by_canon`, which only holds objects
    // with a resolvable ExGuid and so misses outlines entirely), then collapse
    // each container's per-revision copies to one declaration. Identity is the
    // canonical ExGuid where there is one, else the object itself — an
    // un-canonicalisable outline is still real content.
    let mut best: HashMap<u64, usize> = HashMap::new();
    for &i in idxs {
        let o = res.obj(i);
        if o.jcid != JCID_OUTLINE && o.jcid != JCID_OUTLINE_GROUP {
            continue;
        }
        // An empty declaration is no candidate at all — UNLESS the anchor can
        // say which declaration is the live one, in which case the live one
        // decides even when it is empty. On "Working out" the live outline lists
        // no children while a stored version of it lists 180 ink containers:
        // skipping empty declarations here left the version's as the only
        // candidate, so the page's root became a snapshot of a page that has
        // since been cleared, and 180 erased strokes came back on a page that is
        // blank in OneNote.
        if live.is_none() && children(i) == 0 {
            continue;
        }
        let key = match res.own_canon(o) {
            Some(c) => c as u64,
            None => (1u64 << 32) | i as u64,
        };
        let e = best.entry(key).or_insert(i);
        if rank(i) > rank(*e) {
            *e = i;
        }
    }
    let mut out: Vec<usize> = best
        .into_values()
        // Now that empty declarations reach here, drop the containers whose live
        // state holds nothing.
        .filter(|&i| children(i) > 0)
        // Containers the live page no longer reaches: 2 of the reference
        // notebook's 287 — five duplicated bullet boxes on the Euler page, and a
        // deleted note that was appearing as the ENTIRE content of an
        // otherwise-empty "Questions" page. An object we cannot canonicalise
        // cannot be tested, and is kept: unprovable is not dead.
        .filter(|&i| match (live, res.own_canon(res.obj(i))) {
            (Some(l), Some(c)) => l.contains(&c),
            _ => true,
        })
        .collect();
    // File order keeps boxes in a stable, roughly top-down sequence.
    out.sort_unstable_by_key(|&i| res.obj(i).stp);
    out
}

/// Every object of one type the LIVE root still reaches, at its current
/// declaration, in file order — the pictures and the tables.
///
/// Deleting a picture or a table in OneNote unlinks it exactly as erasing ink
/// does; the object stays in the file forever. 3 of the reference notebook's 368
/// image objects are these, and each was importing as a picture on the page AND
/// as a stored blob nothing references. Its 22 tables are all live, but they
/// were being collected by the same kind of flat scan, and a table is the one
/// object big enough that resurrecting it would swamp a page.
///
/// `live` is the page's [live_anchor]; `None` keeps everything, as before.
fn live_objects(
    res: &Resolver,
    idxs: &[usize],
    jcid: u32,
    live: Option<&HashSet<u32>>,
) -> Vec<(u32, usize)> {
    let mut out = Vec::new();
    let mut seen = HashSet::new();
    for &i in idxs {
        let o = res.obj(i);
        if o.jcid != jcid {
            continue;
        }
        let Some(c) = res.own_canon(o) else { continue };
        if live.is_some_and(|l| !l.contains(&c)) {
            continue;
        }
        if let Some(&cur) = res.by_canon.get(&c) {
            if seen.insert(c) {
                out.push((c, cur));
            }
        }
    }
    out.sort_by_key(|&(_, i)| res.obj(i).stp);
    out
}

/// The ink containers a page should import: the current declaration of every
/// container the LIVE page still reaches, in file order.
///
/// `live` is the page's [live_anchor]. `None` disables the reachability filter
/// entirely: with no live tree to test against we have no evidence either way,
/// and failing to identify a page's root must not silently delete all of its
/// ink.
fn live_ink_containers(
    res: &Resolver,
    idxs: &[usize],
    live: Option<&HashSet<u32>>,
) -> Vec<usize> {
    let mut out = Vec::new();
    let mut seen = HashSet::new();
    for &i in idxs {
        let o = res.obj(i);
        if o.jcid != JCID_INK_CONTAINER {
            continue;
        }
        // An object's own CompactID resolved through its own revision is its
        // canonical id; unresolvable ones fall back to the raw id, which is
        // never a key of `by_canon`, so they drop out here as they always did.
        let c = res.canon(o.own_oid, o.rev);
        if res.by_canon.get(&c) != Some(&i) {
            continue; // not the current declaration of this container
        }
        if live.is_some_and(|l| !l.contains(&c)) {
            continue; // erased in OneNote: the live page no longer reaches it
        }
        if seen.insert(c) {
            out.push(i);
        }
    }
    out
}

/// Depth-first walk of an object subtree in reading order. A paragraph node
/// (RichText 0x0D) is a list item iff it references a NumberListNode child; that
/// list context (and the bullet) is carried down to the paragraph's text run.
fn collect_tree(
    r: &Reader,
    o: &Obj,
    res: &Resolver,
    depth: usize,
    out: &mut Vec<Line>,
    guard: &mut HashSet<usize>,
) {
    collect_inner(r, o, res, depth, false, String::new(), out, guard);
}

#[allow(clippy::too_many_arguments)]
fn collect_inner(
    r: &Reader,
    o: &Obj,
    res: &Resolver,
    depth: usize,
    list_ctx: bool,
    bullet_ctx: String,
    out: &mut Vec<Line>,
    guard: &mut HashSet<usize>,
) {
    if depth > 64 || !guard.insert(o.stp) {
        return;
    }
    let (_text, children) = parse_obj(r, o.stp, o.cb);

    // If this is a paragraph, does it carry a list bullet?
    let (mut ctx, mut bullet) = (list_ctx, bullet_ctx);
    if o.jcid == JCID_RICHTEXT {
        if let Some(b) = list_bullet(r, &children, res, o.rev) {
            ctx = true;
            bullet = b;
        } else {
            ctx = false;
        }
    }

    if matches!(o.jcid, JCID_RICHTEXT | JCID_RICHTEXT_RUN) {
        let runs = styled_runs(r, o, res);
        let tags = paragraph_tags(r, o, res);
        let plain: String = runs.iter().map(|s| s.text.as_str()).collect();
        if !plain.trim().is_empty() {
            // Classify PER RUN, not per paragraph. A paragraph is a display
            // equation only when every run that carries text is a math run;
            // a sentence that merely contains a symbol ("… E ∩ O = ⊘") is prose
            // with inline math, and [run_markdown] emits `$…$` for those runs.
            //
            // The old test was `runs.iter().any(is_math)`, which promoted any
            // sentence containing one symbol to a whole display equation — and
            // if the conversion then came back empty the line was DROPPED,
            // silently deleting page content (the "Subsets and Empty Sets" page
            // kept two lines and lost the rest).
            let substantive = || runs.iter().filter(|r| !r.text.trim().is_empty());
            let all_math = substantive().count() > 0 && substantive().all(|r| r.style.is_math);
            let latex = if all_math {
                let (text, objs) = joined_math(&runs);
                office_math_to_latex(&text, &objs)
            } else {
                String::new()
            };
            // **A symbol is not an equation** — the same rule [run_markdown]
            // applies to an inline maths run, and it has to be applied here too.
            // OneNote marks a character from the symbol palette as a maths run,
            // so a table cell holding just `ℕ` (or `0`, or `-1`) became a
            // maths-only paragraph, and a maths Line carries LaTeX with NO runs.
            // [outline_markdown_tagged] renders runs, so every one of those
            // cells came out EMPTY: on the owner's reference page the second
            // table imported with its first and last columns entirely blank,
            // the middle (arrow) column intact because arrows are prose.
            // Folded and normalised exactly as [run_markdown] does it, because
            // the two must agree: comparing the raw text against folded LaTeX
            // never matches, which is the bug that made the first attempt at
            // this rule in [run_markdown] look fixed when it was not.
            let folded: String = plain
                .chars()
                .map(fold_math_char)
                .filter(|c| !is_math_control(*c) && *c != '\0')
                .collect();
            let norm = |x: &str| x.split_whitespace().collect::<Vec<_>>().join(" ");
            let notation = norm(&latex) != norm(&folded);
            if all_math && notation && !latex.trim().is_empty() {
                out.push(Line {
                    depth,
                    tags: tags.clone(),
                    is_list: ctx,
                    bullet: bullet.clone(),
                    runs: Vec::new(),
                    math: Some(latex),
                    table: None,
                    image: None,
                });
            } else {
                // Prose, mixed prose+math, or a display equation whose
                // conversion failed — all keep their runs, so nothing is lost.
                //
                // **Including a paragraph that ENDS in a stacked equation.** A
                // previous pass here split "We can define the bijection
                // f(n) = ⟨cases⟩" into a text Line plus a maths Line, on the
                // theory that a two-row brace cannot live inside a sentence.
                // Measured against OneNote's own PDF export of that very page,
                // it can and it does: the prose baseline is y=407.69 and its
                // last glyph ends at x=246.3, and the equation's glyphs start
                // at x=252.9 on the SAME line, spanning y 380.3…428.0 — above
                // and below the line, which is the only thing OneNote changes
                // to make room. Splitting it produced the reported defect:
                // "it seems like we cant have maths in the same box and on the
                // same line as text… i think it got broken out into its own
                // thing."
                //
                // Inline-ness needs no separate signal, because splitting was
                // the only thing that ever removed it: [render_runs] merges
                // adjacent maths runs (offsets rebased, so a structure spread
                // over a dozen runs still converts as one) and [run_markdown]
                // wraps the result in `$…$`. A paragraph that is maths ALL
                // THROUGH still takes the `all_math` branch above and becomes
                // a block of its own, which is the case where the equation
                // genuinely did stand alone in OneNote.
                //
                // Blast radius, measured over the owner's whole notebook
                // (`dump_one --pkg`, 329 pages): 1154 boxes → 1148, on TWO
                // pages. One is the reference page. The other five boxes are
                // all on "M: Eigenvectors and Eigenvalues", every one of them
                // a sentence of the shape "so the eigenvector is ⟨column
                // vector⟩" — which is exactly the sentence this restores.
                out.push(Line {
                    depth,
                    tags,
                    is_list: ctx,
                    bullet: bullet.clone(),
                    runs,
                    math: None,
                    table: None,
                    image: None,
                });
            }
        } else if o.jcid == JCID_RICHTEXT_RUN {
            // An empty TEXT RUN is a blank line the writer typed. An empty
            // RichText is not — it is the paragraph node, and it is textless by
            // construction.
            //
            // "The blank lines ive added havent once been respected" is a real
            // complaint, and an earlier attempt answered it by emitting a Line
            // for every empty rich-text object of either type. That
            // double-spaced the whole notebook: 24 lines of content came back
            // separated by 31 blank lines, so it was reverted with the note
            // that emptiness of the text was the wrong signal. Half right — the
            // missing half is WHICH object is empty.
            //
            // Measured on two real files (the reference notebook's
            // `Discrete Mathematics.one` and a single-page export): every
            // paragraph is a PAIR — a RichText (0x0D) container followed by its
            // one RichText_Run (0x0E) child — and of the 1600 RichText objects
            // across both, **not one** carries text; every one of the 1588
            // text runs is a 0x0E. So a blank 0x0D is structural noise once per
            // paragraph (which is exactly where the doubling came from), while
            // a blank 0x0E — a run with no 0x3498/0x1C22 property at all — is
            // the paragraph the writer left empty.
            //
            // Keying on the object type rather than on "is the text empty"
            // takes the Logic: Tautologies page from 24 content lines + 31
            // blanks to 24 + 4, which is what OneNote's own PDF export of that
            // page shows.
            out.push(Line {
                depth,
                tags,
                is_list: ctx,
                bullet: bullet.clone(),
                runs: Vec::new(),
                math: None,
                table: None,
                image: None,
            });
        }
    }

    for cid in children {
        if res.get(cid, o.rev).is_none() && std::env::var("ONOTE_WALK_DEBUG").is_ok() {
            eprintln!(
                "WALK: unresolved child cid={cid:#010x} under jcid={:#010x} rev={} depth={depth}",
                o.jcid, o.rev
            );
        }
        if let Some(idx) = res.get(cid, o.rev) {
            let child = res.obj(idx);
            if child.jcid == JCID_TABLE {
                // Stop here: recursing would scatter the cells through the
                // surrounding text as loose paragraphs, which is how table
                // content used to arrive (or vanish, when the table hung off
                // something the outline walk never reached).
                let grid = parse_table(r, child, res, &HashMap::new());
                if !grid.is_empty() {
                    out.push(Line {
                        depth,
                        tags: Vec::new(),
                        is_list: false,
                        bullet: String::new(),
                        runs: Vec::new(),
                        math: None,
                        table: Some(grid),
                        image: None,
                    });
                }
                continue;
            }
            if child.jcid == JCID_IMAGE {
                // An image in the outline flow (e.g. a list item that is an
                // image) — record it (canonicalised) as a line so the box
                // splitter can place it and advance the flow by its height.
                out.push(Line {
                    depth: depth + 1,
                    tags: Vec::new(),
                    is_list: false,
                    bullet: String::new(),
                    runs: Vec::new(),
                    math: None,
                    table: None,
                    image: Some(res.canon(cid, o.rev)),
                });
                continue;
            }
            let deeper = matches!(
                child.jcid,
                JCID_OUTLINE | JCID_OUTLINE_ELEMENT | JCID_RICHTEXT | JCID_OUTLINE_GROUP
            );
            collect_inner(
                r,
                child,
                res,
                if deeper { depth + 1 } else { depth },
                ctx,
                bullet.clone(),
                out,
                guard,
            );
        }
    }
}

/// If any child is a NumberListNode, return its bullet string (control chars
/// stripped; empty → a plain dash). None if the paragraph isn't a list item.
fn list_bullet(r: &Reader, children: &[u32], res: &Resolver, rev: usize) -> Option<String> {
    for &cid in children {
        if let Some(idx) = res.get(cid, rev) {
            let c = res.obj(idx);
            if c.jcid == JCID_NUMBER_LIST {
                let mut bullet = String::new();
                for (pid, bytes) in string_props(r, c.stp, c.cb) {
                    if pid == PID_BULLET {
                        bullet = decode_utf16(&bytes)
                            .chars()
                            .filter(|ch| !ch.is_control() && *ch != '\0')
                            .collect();
                        break;
                    }
                }
                if bullet.trim().is_empty() {
                    bullet = "-".into();
                }
                return Some(bullet);
            }
        }
    }
    None
}

/// A parsed property value. Reference properties (ObjectID / ArrayOfObjectIDs)
/// are resolved against the object's OID stream so callers get real child OIDs.
#[derive(Clone, Debug)]
enum PVal {
    Bool(bool),
    U32(u32),
    U64(u64),
    Str(Vec<u8>),
    Oids(Vec<u32>),
    /// ObjectSpaceID references (compact IDs from the OSID stream) — resolve
    /// via the global-id table to a space's ExtendedGUID.
    Osids(Vec<u32>),
    /// A decoded `ArrayOfPropertyValues` (type 0x10) — a property whose value
    /// is itself a list of property sets. OneNote writes a paragraph's tag
    /// references this way.
    Array(Vec<PropSet>),
    /// A property this parser does not decode, tagged with its MS-ONESTORE
    /// property type so the dumper can say WHICH one — the difference between
    /// "something is here" and a diagnosis.
    Other(u8),
}

/// One object's fully-parsed property set, in declaration order.
#[derive(Clone, Debug)]
struct PropSet {
    props: Vec<(u32, PVal)>,
}

impl PropSet {
    fn get(&self, pid: u32) -> Option<&PVal> {
        self.props.iter().find(|(p, _)| *p == pid).map(|(_, v)| v)
    }
    fn u32(&self, pid: u32) -> Option<u32> {
        match self.get(pid) {
            Some(PVal::U32(v)) => Some(*v),
            _ => None,
        }
    }
    /// A 4-byte (type 0x05) scalar reinterpreted as an f32 — positions, sizes
    /// and the like are IEEE floats stored in the same slot as ints.
    fn f32(&self, pid: u32) -> Option<f32> {
        // Reject non-finite values: any 4-byte property can be reinterpreted as
        // a float, and serde_json renders NaN/±Inf as `null` — which the Dart
        // importer reads with `(e as num).toDouble()` and dies on. A malformed
        // file must degrade, not crash the whole import.
        self.u32(pid)
            .map(f32::from_bits)
            .filter(|v| v.is_finite())
    }
    fn flag(&self, pid: u32) -> bool {
        matches!(self.get(pid), Some(PVal::Bool(true)))
    }
    /// Raw bytes of a string-typed property. Some properties use the string
    /// slot for packed binary — table column widths (0x1D66) are a `u8` count
    /// followed by one little-endian `f32` per column — so they must be read as
    /// bytes, not decoded as UTF-16.
    fn bytes(&self, pid: u32) -> Option<&[u8]> {
        match self.get(pid) {
            Some(PVal::Str(b)) => Some(b),
            _ => None,
        }
    }
    fn utf16(&self, pid: u32) -> Option<String> {
        match self.get(pid) {
            Some(PVal::Str(b)) => Some(clean_str(decode_utf16(b))),
            _ => None,
        }
    }
    fn oids(&self, pid: u32) -> Vec<u32> {
        match self.get(pid) {
            Some(PVal::Oids(v)) => v.clone(),
            _ => Vec::new(),
        }
    }
    fn osids(&self, pid: u32) -> Vec<u32> {
        match self.get(pid) {
            Some(PVal::Osids(v)) => v.clone(),
            _ => Vec::new(),
        }
    }
    /// Text of a rich-text run: 8-bit body (0x3498) preferred, else UTF-16.
    fn run_text(&self) -> Option<String> {
        if let Some(PVal::Str(b)) = self.get(PID_TEXT_UTF8) {
            return Some(decode_8bit_text(b));
        }
        if let Some(PVal::Str(b)) = self.get(PID_TEXT_UTF16) {
            return Some(decode_utf16(b));
        }
        None
    }
}

fn clean_str(s: String) -> String {
    let s = s.trim_matches(|c: char| c == '\0').trim_end();
    // Defence in depth: titles and bullet strings have no run structure, so a
    // field marker there would otherwise reach the UI. `run_text` itself is
    // deliberately NOT filtered — the structure dumps rely on the raw buffer.
    linkify_field_codes(s)
}

/// Full property-set parse with stream resolution for reference properties.
/// The OID stream is consumed in property order: an ObjectID (0x08) takes one
/// entry, an ArrayOfObjectIDs (0x09) takes `count`. The OSID (object-space)
/// stream is consumed the same way by 0x0A/0x0B — those compact IDs resolve
/// through the global-id table to space GUIDs (how a section's page list
/// points at each page's object space). Context refs (0x0C/0x0D) are skipped.
fn read_propset(r: &Reader, start: usize, len: usize) -> PropSet {
    let mut props = Vec::new();
    if start + len > r.d.len() || len < 6 {
        return PropSet { props };
    }
    let end = start + len;
    let mut o = start;
    let h = r.u32(o);
    o += 4;
    let oid_count = (h & 0x00FF_FFFF) as usize;
    let oid_stream = o;
    o += oid_count * 4;
    let ext_present = (h >> 30) & 1 == 1;
    let osid_absent = (h >> 31) & 1 == 1;
    let (mut osid_stream, mut osid_count) = (0usize, 0usize);
    if !osid_absent {
        let h2 = r.u32(o);
        osid_count = (h2 & 0x00FF_FFFF) as usize;
        osid_stream = o + 4;
        o += 4 + osid_count * 4;
        if ext_present {
            let h3 = r.u32(o);
            o += 4 + (h3 & 0x00FF_FFFF) as usize * 4;
        }
    }
    if o + 2 > end {
        return PropSet { props };
    }
    let c_props = r.u16(o) as usize;
    o += 2;
    let prids = o;
    let mut data_o = prids + c_props * 4;
    if data_o > end || c_props > 4096 {
        return PropSet { props };
    }
    let max_oids = oid_count.min((end.saturating_sub(oid_stream)) / 4);
    let read_oid = |k: usize| -> u32 { r.u32(oid_stream + k * 4) };
    let mut oid_cursor = 0usize;
    let max_osids = osid_count.min((end.saturating_sub(osid_stream)) / 4);
    let read_osid = |k: usize| -> u32 { r.u32(osid_stream + k * 4) };
    let mut osid_cursor = 0usize;

    for i in 0..c_props {
        let prid = r.u32(prids + i * 4);
        let pid = prid & 0x03FF_FFFF;
        let ptype = ((prid >> 26) & 0x1F) as u8;
        let bool_val = (prid >> 31) & 1 == 1;
        let val = match ptype {
            0x02 => PVal::Bool(bool_val),
            0x03 => PVal::U32(r.u8(data_o) as u32),
            0x04 => PVal::U32(r.u16(data_o) as u32),
            0x05 => PVal::U32(r.u32(data_o)),
            0x06 => PVal::U64(r.u32(data_o) as u64 | ((r.u32(data_o + 4) as u64) << 32)),
            0x07 => {
                let cb = r.u32(data_o) as usize;
                if data_o + 4 + cb <= end && cb <= 1 << 20 {
                    PVal::Str(r.d[data_o + 4..data_o + 4 + cb].to_vec())
                } else {
                    PVal::Other(0x07)
                }
            }
            0x08 => {
                let v = if oid_cursor < max_oids { read_oid(oid_cursor) } else { 0 };
                oid_cursor += 1;
                PVal::Oids(vec![v])
            }
            0x09 => {
                let count = r.u32(data_o) as usize;
                let mut v = Vec::new();
                for _ in 0..count {
                    if oid_cursor < max_oids {
                        v.push(read_oid(oid_cursor));
                    }
                    oid_cursor += 1;
                }
                PVal::Oids(v)
            }
            0x0A => {
                let v = if osid_cursor < max_osids { read_osid(osid_cursor) } else { 0 };
                osid_cursor += 1;
                PVal::Osids(vec![v])
            }
            0x0B => {
                let count = r.u32(data_o) as usize;
                let mut v = Vec::new();
                for _ in 0..count {
                    if osid_cursor < max_osids {
                        v.push(read_osid(osid_cursor));
                    }
                    osid_cursor += 1;
                }
                PVal::Osids(v)
            }
            // Decoded in place, sharing the id cursors, because a nested set's
            // ObjectIDs come from THIS object's stream: reading them anywhere
            // else would resolve them against the wrong list.
            0x10 => {
                let sets = read_prop_array(
                    r,
                    data_o,
                    end,
                    oid_stream,
                    max_oids,
                    &mut oid_cursor,
                    osid_stream,
                    max_osids,
                    &mut osid_cursor,
                    0,
                );
                PVal::Array(sets)
            }
            _ => PVal::Other(ptype),
        };
        // 0x05 (4-byte) is stored as raw bits (PVal::U32); callers read it as
        // either f32() or u32() since the type alone doesn't say which.
        props.push((pid, val));
        let span = prop_span(r, data_o, ptype, end, 0);
        // A nested property set can itself hold ObjectIDs, which come from THIS
        // object's id stream — so the cursors have to skip what the nesting
        // consumed, or every id-typed property after it reads someone else's
        // reference. The simple types advance their own cursor in the match
        // above; only the nested ones are accounted for here.
        if ptype == 0x11 {
            oid_cursor += span.oids;
            osid_cursor += span.osids;
        }
        data_o += span.bytes;
        if data_o > end {
            break;
        }
    }
    PropSet { props }
}

/// Parse one object's property set: return its text (if any) and the ordered
/// list of referenced object OIDs (its children, from the OID stream).
fn parse_obj(r: &Reader, start: usize, len: usize) -> (Option<String>, Vec<u32>) {
    let mut text = None;
    let mut children = Vec::new();
    if start + len > r.d.len() || len < 6 {
        return (text, children);
    }
    let end = start + len;
    let mut o = start;
    let h = r.u32(o);
    o += 4;
    let oid_count = (h & 0x00FF_FFFF) as usize;
    let oid_stream = o;
    o += oid_count * 4;
    let ext_present = (h >> 30) & 1 == 1;
    let osid_absent = (h >> 31) & 1 == 1;
    if !osid_absent {
        let h2 = r.u32(o);
        o += 4 + (h2 & 0x00FF_FFFF) as usize * 4;
        if ext_present {
            let h3 = r.u32(o);
            o += 4 + (h3 & 0x00FF_FFFF) as usize * 4;
        }
    }
    if o + 2 > end {
        return (text, children);
    }
    let c_props = r.u16(o) as usize;
    o += 2;
    let prids = o;
    let mut data_o = prids + c_props * 4;
    if data_o > end || c_props > 4096 {
        return (text, children);
    }
    for i in 0..c_props {
        let prid = r.u32(prids + i * 4);
        let pid = prid & 0x03FF_FFFF;
        let ptype = ((prid >> 26) & 0x1F) as u8;
        if ptype == 0x07 {
            let cb = r.u32(data_o) as usize;
            if data_o + 4 + cb <= end {
                let bytes = &r.d[data_o + 4..data_o + 4 + cb];
                if pid == PID_TEXT_UTF8 {
                    text = Some(decode_8bit_text(bytes));
                } else if pid == PID_TEXT_UTF16 && text.is_none() {
                    text = Some(decode_utf16(bytes));
                }
            }
        }
        data_o += data_size(r, data_o, ptype);
        if data_o > end {
            break;
        }
    }
    // Every referenced object, in stream order, is a potential child.
    for k in 0..oid_count.min((end.saturating_sub(oid_stream)) / 4) {
        children.push(r.u32(oid_stream + k * 4));
    }
    (text, children)
}

fn same_visible(a: &Style, b: &Style) -> bool {
    // `is_math` participates so consecutive math runs MERGE (a fraction's
    // delimiters can span runs, so the span must convert as one unit) while a
    // math run never merges into the prose around it.
    a.is_math == b.is_math
        && a.bold == b.bold
        && a.italic == b.italic
        && a.underline == b.underline
        && a.strike == b.strike
        && a.highlight == b.highlight
        && a.sub == b.sub
        && a.sup == b.sup
        && a.verbatim_md == b.verbatim_md
        && color_hex(a.color) == color_hex(b.color)
}

/// Render a paragraph's styled runs to Markdown, coalescing adjacent runs that
/// share visible formatting so we emit `**Host:**` rather than `**Ho****st:**`.
fn render_runs(runs: &[SRun]) -> String {
    let mut merged: Vec<SRun> = Vec::new();
    for run in runs {
        if let Some(last) = merged.last_mut() {
            if same_visible(&last.style, &run.style) {
                // Shift the incoming run's object offsets by what is already
                // in the buffer: an equation's structure is spread over a
                // dozen runs, and it only converts correctly once they are
                // reassembled with their offsets still pointing at the right
                // U+FDD0.
                let base = last.text.chars().count();
                last.math_objs.extend(run.math_objs.iter().map(|(o, m)| (base + o, m.clone())));
                last.text.push_str(&run.text);
                continue;
            }
        }
        merged.push(SRun {
            text: run.text.clone(),
            style: run.style.clone(),
            math_objs: run.math_objs.clone(),
        });
    }
    merged.iter().map(run_markdown).collect()
}

/// The most-used (by character count) real font across an outline's runs,
/// ignoring math runs. Openote applies one font per text box, so we pick the
/// dominant body font.
fn dominant_font(lines: &[&Line]) -> Option<String> {
    let mut counts: HashMap<String, usize> = HashMap::new();
    for l in lines {
        for run in &l.runs {
            if let Some(f) = &run.style.font {
                if f != "Cambria Math" && !f.is_empty() {
                    *counts.entry(f.clone()).or_default() += run.text.chars().count().max(1);
                }
            }
        }
    }
    counts.into_iter().max_by_key(|(_, n)| *n).map(|(f, _)| f)
}

/// The most-used (by character count) font size across an outline's runs, in
/// points (stored half-points / 2). None when no run carries a size.
fn dominant_size(lines: &[&Line]) -> Option<f32> {
    let mut counts: HashMap<u32, usize> = HashMap::new();
    for l in lines {
        for run in &l.runs {
            if run.style.size_half_pt > 0 {
                *counts.entry(run.style.size_half_pt).or_default() +=
                    run.text.chars().count().max(1);
            }
        }
    }
    counts
        .into_iter()
        .max_by_key(|(_, n)| *n)
        .map(|(hp, _)| hp as f32 / 2.0)
}

/// Render collected lines as indented Markdown for Openote's renderer. List
/// items keep their original bullet; in-flow images render as
/// `![image](onote-img://N)` placeholder lines (the importer rewrites N to the
/// stored blob hash). Math never reaches here: [emit_boxes] splits equations
/// into their own boxes first. 2 spaces per indent level, emitted for EVERY
/// line kind — non-list paragraphs used to stay flush-left, which silently
/// discarded their OneNote indent and produced the measured `45u × levels`
/// residual offset on exactly those rows (review §K.1's last open item).
///
/// [base_depth] is the depth to normalise against. `emit_boxes` splits an
/// outline into segments at every math/table line, and each segment
/// re-normalising against its own minimum pulled post-math indented content
/// back to the margin — so the caller computes the base once per outline and
/// passes it to every segment. `None` keeps per-call normalisation (table
/// cells, where each cell is its own little document).
fn outline_markdown(
    lines: &[&Line],
    img_idx: &HashMap<u32, String>,
    base_depth: Option<usize>,
) -> String {
    outline_markdown_tagged(lines, img_idx, base_depth).0
}

/// The markdown, plus each tag pinned to the line index it actually landed on.
///
/// Counted as lines are emitted rather than by position in `lines`, because an
/// image whose placeholder is missing is skipped — so the two would drift apart
/// exactly on the pages that have images, and a tag would mark the wrong
/// sentence.
fn outline_markdown_tagged(
    lines: &[&Line],
    img_idx: &HashMap<u32, String>,
    base_depth: Option<usize>,
) -> (String, Vec<BoxTag>) {
    // Blank lines are excluded from the baseline for the same reason as in
    // [emit_boxes]: they carry a depth but render no indent, so letting one set
    // the minimum indents every real line beside it.
    let min_depth = base_depth.unwrap_or_else(|| {
        lines
            .iter()
            .filter(|l| !l.is_blank())
            .map(|l| l.depth)
            .min()
            .unwrap_or(0)
    });
    let mut out = String::new();
    let mut tags = Vec::new();
    let mut emitted = 0usize;
    for l in lines {
        let level = l.depth.saturating_sub(min_depth);
        if let Some(oid) = l.image {
            if let Some(placeholder) = img_idx.get(&oid) {
                out.push_str(&"  ".repeat(level));
                out.push_str(placeholder);
                out.push('\n');
                emitted += 1;
            }
            continue;
        }
        // A blank line carries no indentation. Emitting `"  ".repeat(level)`
        // for one would write trailing whitespace that the reader shows as an
        // indented empty paragraph and that every diff of the exported
        // Markdown would flag.
        if !l.is_blank() {
            out.push_str(&"  ".repeat(level));
            if l.is_list {
                out.push_str(&l.bullet);
                out.push(' ');
            }
            // A maths line carries LaTeX and NO runs. [emit_boxes] intercepts
            // those before they reach here, so this only fires for the callers
            // that render lines directly — table cells — and rendering only the
            // (empty) runs is how a cell holding an equation came out blank.
            // Inline `$…$` rather than a box: a cell IS an inline context.
            match &l.math {
                Some(latex) => out.push_str(&format!("${latex}$")),
                None => out.push_str(&render_runs(&l.runs)),
            }
        }
        out.push('\n');
        for t in &l.tags {
            tags.push(BoxTag {
                line: emitted,
                label: t.label.clone(),
                shape: t.shape,
            });
        }
        emitted += 1;
    }
    (out.trim_end().to_string(), tags)
}

/// (property_id, raw_bytes) for each type-7 property. Used for title lookup.
fn string_props(r: &Reader, start: usize, len: usize) -> Vec<(u32, Vec<u8>)> {
    let mut out = Vec::new();
    each_prop(r, start, len, |pid, ptype, _b, data_o, end| {
        if ptype == 0x07 {
            let cb = r.u32(data_o) as usize;
            if data_o + 4 + cb <= end {
                out.push((pid, r.d[data_o + 4..data_o + 4 + cb].to_vec()));
            }
        }
    });
    out
}

/// Shared property-set iterator: calls `f(pid, type, bool_value, data_offset,
/// end)` for each property. For boolean properties (type 0x02) the value is bit
/// 31 of the PropertyID (MS-ONESTORE §2.6.6 `boolValue`), passed as `bool_value`;
/// for other types `bool_value` is false and irrelevant.
fn each_prop(
    r: &Reader,
    start: usize,
    len: usize,
    mut f: impl FnMut(u32, u8, bool, usize, usize),
) {
    if start + len > r.d.len() || len < 6 {
        return;
    }
    let end = start + len;
    let mut o = start;
    let h = r.u32(o);
    o += 4 + (h & 0x00FF_FFFF) as usize * 4;
    let ext_present = (h >> 30) & 1 == 1;
    let osid_absent = (h >> 31) & 1 == 1;
    if !osid_absent {
        let h2 = r.u32(o);
        o += 4 + (h2 & 0x00FF_FFFF) as usize * 4;
        if ext_present {
            let h3 = r.u32(o);
            o += 4 + (h3 & 0x00FF_FFFF) as usize * 4;
        }
    }
    if o + 2 > end {
        return;
    }
    let c_props = r.u16(o) as usize;
    o += 2;
    let prids = o;
    let mut data_o = prids + c_props * 4;
    if data_o > end || c_props > 4096 {
        return;
    }
    for i in 0..c_props {
        let prid = r.u32(prids + i * 4);
        let pid = prid & 0x03FF_FFFF;
        let ptype = ((prid >> 26) & 0x1F) as u8;
        let bool_val = (prid >> 31) & 1 == 1;
        f(pid, ptype, bool_val, data_o, end);
        data_o += data_size(r, data_o, ptype);
        if data_o > end {
            break;
        }
    }
}

fn node_ref(r: &Reader, o: usize, s: u8, c: u8) -> Option<Fcr> {
    let (stp, adv) = match s {
        0 => (r.u64(o), 8),
        1 => (r.u32(o) as u64, 4),
        2 => ((r.u16(o) as u64) * 8, 2),
        3 => ((r.u32(o) as u64) * 8, 4),
        _ => return None,
    };
    let co = o + adv;
    let cb = match c {
        0 => r.u32(co) as u64,
        1 => r.u64(co),
        2 => (r.u8(co) as u64) * 8,
        3 => (r.u16(co) as u64) * 8,
        _ => return None,
    };
    Some(Fcr { stp, cb: cb as u32 })
}

// ── Property-set parsing (MS-ONE ObjectSpaceObjectPropSet) ──────────────────

/// Decode an `ArrayOfPropertyValues` into its nested property sets.
///
/// Shares the parent object's id cursors by reference: a nested set's
/// `ObjectID` properties are indices into the *parent's* stream, taken in
/// document order along with the parent's own. Passing the cursors down is what
/// keeps a tag reference pointing at the tag it was written for.
#[allow(clippy::too_many_arguments)]
fn read_prop_array(
    r: &Reader,
    o: usize,
    end: usize,
    oid_stream: usize,
    max_oids: usize,
    oid_cursor: &mut usize,
    osid_stream: usize,
    max_osids: usize,
    osid_cursor: &mut usize,
    depth: u32,
) -> Vec<PropSet> {
    let mut out = Vec::new();
    if depth >= MAX_PROP_NESTING || o + 8 > end {
        return out;
    }
    let count = r.u32(o) as usize;
    if count == 0 || count > 1 << 16 {
        return out;
    }
    let mut p = o + 8;
    for _ in 0..count {
        if p + 2 > end {
            break;
        }
        let (set, size) = read_nested_propset(
            r, p, end, oid_stream, max_oids, oid_cursor, osid_stream, max_osids,
            osid_cursor, depth + 1,
        );
        out.push(set);
        if size == 0 {
            break; // malformed: refuse to spin
        }
        p += size;
    }
    out
}

/// One embedded `PropertySet`, returning it and the bytes it occupied.
#[allow(clippy::too_many_arguments)]
fn read_nested_propset(
    r: &Reader,
    o: usize,
    end: usize,
    oid_stream: usize,
    max_oids: usize,
    oid_cursor: &mut usize,
    osid_stream: usize,
    max_osids: usize,
    osid_cursor: &mut usize,
    depth: u32,
) -> (PropSet, usize) {
    let mut props = Vec::new();
    if depth >= MAX_PROP_NESTING || o + 2 > end {
        return (PropSet { props }, 0);
    }
    let count = r.u16(o) as usize;
    let prids = o + 2;
    let mut data_o = prids + count * 4;
    if data_o > end || count > 4096 {
        return (PropSet { props }, 2);
    }
    for i in 0..count {
        let prid = r.u32(prids + i * 4);
        let pid = prid & 0x03FF_FFFF;
        let ptype = ((prid >> 26) & 0x1F) as u8;
        let bool_val = (prid >> 31) & 1 == 1;
        let val = match ptype {
            0x02 => PVal::Bool(bool_val),
            0x03 => PVal::U32(r.u8(data_o) as u32),
            0x04 => PVal::U32(r.u16(data_o) as u32),
            0x05 => PVal::U32(r.u32(data_o)),
            0x06 => PVal::U64(r.u32(data_o) as u64 | ((r.u32(data_o + 4) as u64) << 32)),
            0x07 => {
                let cb = r.u32(data_o) as usize;
                if data_o + 4 + cb <= end && cb <= 1 << 20 {
                    PVal::Str(r.d[data_o + 4..data_o + 4 + cb].to_vec())
                } else {
                    PVal::Other(0x07)
                }
            }
            0x08 => {
                let v = if *oid_cursor < max_oids {
                    r.u32(oid_stream + *oid_cursor * 4)
                } else {
                    0
                };
                *oid_cursor += 1;
                PVal::Oids(vec![v])
            }
            0x09 => {
                let n = r.u32(data_o) as usize;
                let mut v = Vec::new();
                for _ in 0..n {
                    if *oid_cursor < max_oids {
                        v.push(r.u32(oid_stream + *oid_cursor * 4));
                    }
                    *oid_cursor += 1;
                }
                PVal::Oids(v)
            }
            0x0A => {
                let v = if *osid_cursor < max_osids {
                    r.u32(osid_stream + *osid_cursor * 4)
                } else {
                    0
                };
                *osid_cursor += 1;
                PVal::Osids(vec![v])
            }
            0x0B => {
                let n = r.u32(data_o) as usize;
                let mut v = Vec::new();
                for _ in 0..n {
                    if *osid_cursor < max_osids {
                        v.push(r.u32(osid_stream + *osid_cursor * 4));
                    }
                    *osid_cursor += 1;
                }
                PVal::Osids(v)
            }
            0x10 => PVal::Array(read_prop_array(
                r, data_o, end, oid_stream, max_oids, oid_cursor, osid_stream,
                max_osids, osid_cursor, depth + 1,
            )),
            _ => PVal::Other(ptype),
        };
        props.push((pid, val));
        data_o += prop_span(r, data_o, ptype, end, depth).bytes;
        if data_o > end {
            break;
        }
    }
    (PropSet { props }, data_o.saturating_sub(o))
}

/// How much space one property's data occupies, and how many ids it consumes.
///
/// The id counts matter as much as the byte count: `ObjectID`-typed properties
/// carry no inline data at all and instead take the next entry from the
/// object's own id stream, so a nested structure that contains one shifts every
/// id read after it.
#[derive(Default, Clone, Copy)]
struct PropSpan {
    bytes: usize,
    oids: usize,
    osids: usize,
}

/// Bytes occupied by one property's data.
///
/// Kept as a thin wrapper over [prop_span] because most callers only walk
/// forward and never look at an id.
fn data_size(r: &Reader, o: usize, ptype: u8) -> usize {
    prop_span(r, o, ptype, r.d.len(), 0).bytes
}

/// The full span of one property's data.
///
/// **Types 0x10 and 0x11 are variable-length, and getting that wrong is not a
/// cosmetic bug.** `ArrayOfPropertyValues` (0x10) and `PropertySet` (0x11)
/// embed whole property sets inside a property. They were previously sized at a
/// flat 4 and 0 bytes, which meant every property *after* one of them was read
/// from the wrong offset — and OneNote writes a tag reference (0x3489) as a
/// 0x10 array, immediately before the paragraph's own text on a tagged
/// paragraph. So a tagged to-do lost its text entirely: the string's length
/// prefix was read out of the middle of the tag array, came back as nonsense,
/// failed the bounds check, and the paragraph silently vanished from the
/// import. Reproduced from a real tagged `.one`; see the tests.
///
/// [depth] bounds the recursion. The structures are self-describing and a
/// corrupt file can claim arbitrary nesting, so this refuses to follow it
/// rather than growing the stack — every other parser entry point in this file
/// is hardened the same way.
fn prop_span(r: &Reader, o: usize, ptype: u8, end: usize, depth: u32) -> PropSpan {
    let bytes = |n: usize| PropSpan { bytes: n, ..Default::default() };
    match ptype {
        0x01 | 0x02 => bytes(0),
        0x03 => bytes(1),
        0x04 => bytes(2),
        0x05 => bytes(4),
        0x06 => bytes(8),
        0x07 => bytes(4 + r.u32(o) as usize),
        0x08 => PropSpan { bytes: 0, oids: 1, osids: 0 },
        0x09 => PropSpan { bytes: 4, oids: r.u32(o) as usize, osids: 0 },
        0x0A => PropSpan { bytes: 0, oids: 0, osids: 1 },
        0x0B => PropSpan { bytes: 4, oids: 0, osids: r.u32(o) as usize },
        // ContextIDs come from a stream this parser does not track; the byte
        // sizes are still correct, which is what keeps the walk aligned.
        0x0C => bytes(0),
        0x0D => bytes(4),
        0x10 => array_of_property_values_span(r, o, end, depth),
        0x11 => nested_propset_span(r, o, end, depth),
        _ => bytes(0),
    }
}

/// Deepest nesting followed before giving up. Real files use one or two levels;
/// anything beyond this is corruption or an attack, and the safe answer is to
/// stop rather than to recurse.
const MAX_PROP_NESTING: u32 = 8;

/// `ArrayOfPropertyValues`: cProperties (4) + prid (4) + cProperties property
/// sets, each laid out exactly like a nested [nested_propset_span].
fn array_of_property_values_span(
    r: &Reader,
    o: usize,
    end: usize,
    depth: u32,
) -> PropSpan {
    if depth >= MAX_PROP_NESTING || o + 4 > end {
        return PropSpan { bytes: 4, ..Default::default() };
    }
    let count = r.u32(o) as usize;
    // An empty array still carries its prid, and a count large enough to be
    // nonsense means the file is not what it claims — walk no further.
    if count == 0 || count > 1 << 16 {
        return PropSpan { bytes: 8, ..Default::default() };
    }
    let mut span = PropSpan { bytes: 8, ..Default::default() };
    let mut p = o + 8;
    for _ in 0..count {
        if p >= end {
            break;
        }
        let inner = nested_propset_span(r, p, end, depth + 1);
        p += inner.bytes;
        span.bytes += inner.bytes;
        span.oids += inner.oids;
        span.osids += inner.osids;
    }
    span
}

/// A `PropertySet` embedded inside a property: cProperties (2) + the prid
/// array + each property's data.
fn nested_propset_span(r: &Reader, o: usize, end: usize, depth: u32) -> PropSpan {
    if depth >= MAX_PROP_NESTING || o + 2 > end {
        return PropSpan::default();
    }
    let count = r.u16(o) as usize;
    let mut span = PropSpan {
        bytes: 2 + count * 4,
        ..Default::default()
    };
    let mut data = o + span.bytes;
    if data > end {
        return PropSpan { bytes: 2, ..Default::default() };
    }
    for i in 0..count {
        if data >= end {
            break;
        }
        let prid = r.u32(o + 2 + i * 4);
        let ptype = ((prid >> 26) & 0x1F) as u8;
        let inner = prop_span(r, data, ptype, end, depth + 1);
        data += inner.bytes;
        span.bytes += inner.bytes;
        span.oids += inner.oids;
        span.osids += inner.osids;
    }
    span
}

/// Decode an MS-ISF multi-byte stream of signed numbers: a length-prefixed
/// sequence of 7-bit little-endian varints (high bit = continuation), each
/// zigzag-ish signed (LSB = sign flag, value = v >> 1). Both the length prefix
/// and the values use the signed form. Returns None on malformed input.
fn decode_multibyte_signed(b: &[u8]) -> Option<Vec<i64>> {
    fn uint(b: &[u8], at: usize) -> Option<(u64, usize)> {
        let (mut v, mut n) = (0u64, 0usize);
        loop {
            let byte = *b.get(at + n)?;
            if n >= 10 {
                return None; // >64-bit — corrupt
            }
            v |= ((byte & 0x7F) as u64) << (n * 7);
            n += 1;
            if byte & 0x80 == 0 {
                return Some((v, n));
            }
        }
    }
    let (len_raw, mut at) = uint(b, 0)?;
    let count = (len_raw >> 1) as usize;
    if count > 1 << 20 {
        return None; // absurd point count — corrupt
    }
    let mut out = Vec::with_capacity(count);
    for _ in 0..count {
        let (v, n) = uint(b, at)?;
        at += n;
        let signed = (v >> 1) as i64;
        out.push(if v & 1 == 1 { -signed } else { signed });
    }
    Some(out)
}

/// Decode a UTF-16LE string property.
/// The 8-bit text body (0x3498). Despite the property's "UTF-8" name,
/// OneNote writes the ANSI code page here whenever every character of a run
/// fits it — so a run holding ¬ (0xAC in cp1252) arrives as a lone Latin
/// byte that is INVALID UTF-8. `from_utf8_lossy` turned exactly those runs
/// into U+FFFD, which is how a user's NOT symbols became � while the same
/// symbol survived in runs OneNote happened to store as UTF-16. Strict
/// UTF-8 first — pure ASCII and genuine UTF-8 pass through unchanged —
/// then Windows-1252, which maps every byte, so nothing is ever replaced.
fn decode_8bit_text(b: &[u8]) -> String {
    match std::str::from_utf8(b) {
        Ok(s) => s.to_owned(),
        Err(_) => b.iter().map(|&c| cp1252(c)).collect(),
    }
}

/// Windows-1252 → Unicode: identical to Latin-1 except 0x80–0x9F, which
/// hold the printable punctuation below (undefined slots pass through).
fn cp1252(b: u8) -> char {
    match b {
        0x80 => '\u{20AC}', // €
        0x82 => '\u{201A}',
        0x83 => '\u{0192}',
        0x84 => '\u{201E}',
        0x85 => '\u{2026}', // …
        0x86 => '\u{2020}',
        0x87 => '\u{2021}',
        0x88 => '\u{02C6}',
        0x89 => '\u{2030}',
        0x8A => '\u{0160}',
        0x8B => '\u{2039}',
        0x8C => '\u{0152}',
        0x8E => '\u{017D}',
        0x91 => '\u{2018}', // '
        0x92 => '\u{2019}', // '
        0x93 => '\u{201C}', // "
        0x94 => '\u{201D}', // "
        0x95 => '\u{2022}', // •
        0x96 => '\u{2013}', // –
        0x97 => '\u{2014}', // —
        0x98 => '\u{02DC}',
        0x99 => '\u{2122}', // ™
        0x9A => '\u{0161}',
        0x9B => '\u{203A}',
        0x9C => '\u{0153}',
        0x9E => '\u{017E}',
        0x9F => '\u{0178}',
        other => other as char,
    }
}

fn decode_utf16(b: &[u8]) -> String {
    let pairs = b.len() / 2;
    let mut s = String::with_capacity(pairs);
    let mut units = Vec::with_capacity(pairs);
    for i in 0..pairs {
        units.push(u16::from_le_bytes([b[i * 2], b[i * 2 + 1]]));
    }
    for ch in char::decode_utf16(units.iter().copied()) {
        match ch {
            Ok(c) => s.push(c),
            Err(e) => {
                if std::env::var("ONOTE_CHAR_DEBUG").is_ok() {
                    eprintln!(
                        "CHAR: unpaired unit 0x{:04X} in units {:04X?}",
                        e.unpaired_surrogate(),
                        units
                    );
                }
                s.push('\u{fffd}');
            }
        }
    }
    s
}

// ── Inline PNG recovery ─────────────────────────────────────────────────────

/// One recovered image and the MIME type its bytes say it is.
pub struct ScannedImage {
    pub bytes: Vec<u8>,
    pub mime: &'static str,
}

/// Recover embedded images by signature.
///
/// **PNG and JPEG**, not PNG alone. Student notebooks are full of phone photos
/// of whiteboards and worksheets, and those are JPEG — so a PNG-only scan meant
/// a switcher's photographs silently vanished at import. That is data loss, not
/// a fidelity gap, which is why JPEG earns a place next to PNG rather than
/// waiting behind EMF and the rest.
fn scan_images(d: &[u8]) -> Vec<ScannedImage> {
    let mut out = Vec::new();
    let mut i = 0;
    while i < d.len() {
        let png_at = find(&d[i..], PNG_SIG).map(|r| i + r);
        let jpg_at = find_jpeg(d, i);
        // Take whichever comes first so images stay in document order.
        let (start, is_png) = match (png_at, jpg_at) {
            (Some(p), Some(j)) => {
                if p <= j {
                    (p, true)
                } else {
                    (j, false)
                }
            }
            (Some(p), None) => (p, true),
            (None, Some(j)) => (j, false),
            (None, None) => break,
        };
        let end = if is_png {
            // End = the IEND chunk: 'IEND' marker + 4-byte CRC.
            match find(&d[start..], b"IEND") {
                Some(erel) => (start + erel + 8).min(d.len()),
                None => break,
            }
        } else {
            match jpeg_end(d, start) {
                Some(e) => e,
                // A truncated JPEG: skip past its header and keep looking
                // rather than abandoning every later image in the blob.
                None => {
                    i = start + 2;
                    continue;
                }
            }
        };
        if end > start {
            out.push(ScannedImage {
                bytes: d[start..end].to_vec(),
                mime: if is_png { "image/png" } else { "image/jpeg" },
            });
        }
        i = end.max(start + 2);
    }
    out
}

/// File extension for a recovered image's real MIME type.
fn ext_of(mime: &str) -> &'static str {
    if mime == "image/jpeg" { "jpg" } else { "png" }
}

/// PNG pixel dimensions from the IHDR chunk.
fn png_dimensions(d: &[u8]) -> (u32, u32) {
    if d.len() < 24 {
        return (0, 0);
    }
    (
        u32::from_be_bytes([d[16], d[17], d[18], d[19]]),
        u32::from_be_bytes([d[20], d[21], d[22], d[23]]),
    )
}

/// JPEG pixel dimensions from the first SOF segment (walking markers, since a
/// JPEG has no fixed-offset header the way PNG does).
fn jpeg_dimensions(d: &[u8]) -> (u32, u32) {
    let mut i = 2;
    for _ in 0..1024 {
        if i + 9 >= d.len() || d[i] != 0xFF {
            return (0, 0);
        }
        let marker = d[i + 1];
        // SOF0-SOF15, excluding DHT(C4), JPGA(C8) and DAC(CC) which share the range.
        if (0xC0..=0xCF).contains(&marker)
            && marker != 0xC4
            && marker != 0xC8
            && marker != 0xCC
        {
            let h = u16::from_be_bytes([d[i + 5], d[i + 6]]) as u32;
            let w = u16::from_be_bytes([d[i + 7], d[i + 8]]) as u32;
            return (w, h);
        }
        if marker == 0xD8 || marker == 0x01 || (0xD0..=0xD7).contains(&marker) {
            i += 2;
            continue;
        }
        let len = u16::from_be_bytes([d[i + 2], d[i + 3]]) as usize;
        if len < 2 {
            return (0, 0);
        }
        i += 2 + len;
    }
    (0, 0)
}

/// Offset of the next JPEG SOI that is followed by a plausible marker.
///
/// `FF D8` alone occurs constantly inside compressed data, so the third byte
/// must also be `FF` (the start of the next marker) — this is what stops the
/// scanner manufacturing images out of LZX noise.
fn find_jpeg(d: &[u8], from: usize) -> Option<usize> {
    let mut i = from;
    while i + 3 < d.len() {
        let rel = find(&d[i..], &[0xFF, 0xD8, 0xFF])?;
        let at = i + rel;
        // A real JFIF/EXIF stream begins APP0/APP1/… (0xE0-0xEF) or DQT.
        match d.get(at + 3) {
            Some(&m) if (0xE0..=0xEF).contains(&m) || m == 0xDB => return Some(at),
            Some(_) => i = at + 2,
            None => return None,
        }
    }
    None
}

/// End offset (exclusive) of the JPEG beginning at `start`, walking its marker
/// segments to the EOI. Segment-walking rather than searching for `FF D9`,
/// because that byte pair appears inside entropy-coded scan data too.
fn jpeg_end(d: &[u8], start: usize) -> Option<usize> {
    let mut i = start + 2; // past SOI
    // Bounded: a malformed file must not spin here on hostile input.
    for _ in 0..4096 {
        if i + 1 >= d.len() {
            return None;
        }
        if d[i] != 0xFF {
            return None;
        }
        let marker = d[i + 1];
        match marker {
            0xD8 => i += 2,                    // another SOI
            0xD9 => return Some(i + 2),        // EOI
            0x01 | 0xD0..=0xD7 => i += 2,      // standalone markers
            0xDA => {
                // Start of scan: entropy-coded data follows, terminated by the
                // next marker that isn't a stuffed FF00 or a restart marker.
                let len = u16::from_be_bytes([*d.get(i + 2)?, *d.get(i + 3)?]) as usize;
                let mut j = i + 2 + len;
                while j + 1 < d.len() {
                    if d[j] == 0xFF
                        && d[j + 1] != 0x00
                        && !(0xD0..=0xD7).contains(&d[j + 1])
                    {
                        break;
                    }
                    j += 1;
                }
                i = j;
            }
            _ => {
                let len = u16::from_be_bytes([*d.get(i + 2)?, *d.get(i + 3)?]) as usize;
                if len < 2 {
                    return None;
                }
                i += 2 + len;
            }
        }
    }
    None
}

fn find(hay: &[u8], needle: &[u8]) -> Option<usize> {
    if needle.is_empty() || hay.len() < needle.len() {
        return None;
    }
    hay.windows(needle.len()).position(|w| w == needle)
}

// ── Minimal base64 (no external dep) ────────────────────────────────────────

fn base64_encode(data: &[u8]) -> String {
    const T: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(data.len().div_ceil(3) * 4);
    for chunk in data.chunks(3) {
        let b0 = chunk[0] as u32;
        let b1 = *chunk.get(1).unwrap_or(&0) as u32;
        let b2 = *chunk.get(2).unwrap_or(&0) as u32;
        let n = (b0 << 16) | (b1 << 8) | b2;
        out.push(T[(n >> 18 & 63) as usize] as char);
        out.push(T[(n >> 12 & 63) as usize] as char);
        out.push(if chunk.len() > 1 { T[(n >> 6 & 63) as usize] as char } else { '=' });
        out.push(if chunk.len() > 2 { T[(n & 63) as usize] as char } else { '=' });
    }
    out
}

// ── Diagnostics (empirical reverse-engineering aid) ─────────────────────────

fn jcid_name(j: u32) -> &'static str {
    match j {
        JCID_OUTLINE => "Outline",
        JCID_OUTLINE_ELEMENT => "OutlineElement",
        JCID_RICHTEXT => "RichText",
        JCID_RICHTEXT_RUN => "RichTextRun",
        JCID_TITLE => "Title",
        JCID_OUTLINE_GROUP => "OutlineGroup",
        JCID_NUMBER_LIST => "NumberList",
        JCID_IMAGE => "Image",
        _ => "?",
    }
}

/// Human-readable dump of the object graph and every property on every object,
/// for empirically identifying property IDs (position, styling, math, ink). Not
/// used by the importer; called by `cargo run --example dump_one -- file.one`.
pub fn dump_structure(bytes: &[u8]) -> String {
    let r = Reader { d: bytes };
    if bytes.len() < 1024 || !r.is_one_section() {
        return "not a .one section".into();
    }
    let root = r.fcr(172);
    let mut wo = WalkOut::default();
    let mut visited = HashSet::new();
    let mut next_space = 0usize;
    let mut cur_rev = 0usize;
    let mut in_version = false;
    walk(
        &r, root, &mut wo, &mut visited, 0, 0, &mut next_space, &mut cur_rev,
        &mut in_version,
    );
    let objs = wo.objs;

    // Per-space JCID histogram — the space boundaries ARE the page/box
    // boundaries, so this summary is the map of the file.
    let mut hist: std::collections::BTreeMap<(usize, u32), usize> = Default::default();
    for o in &objs {
        *hist.entry((o.space, o.jcid)).or_default() += 1;
    }
    let mut out = String::new();
    out.push_str(&format!(
        "objects={} spaces={}\nper-space JCID histogram:\n",
        objs.len(),
        next_space + 1
    ));
    let mut cur_space = usize::MAX;
    for ((sp, j), n) in &hist {
        if *sp != cur_space {
            out.push_str(&format!("space {sp}:\n"));
            cur_space = *sp;
        }
        out.push_str(&format!("  {:08X} {:<14} x{}\n", j, jcid_name(*j), n));
    }

    for (i, o) in objs.iter().enumerate() {
        out.push_str(&format!(
            "\n#{i} sp={} jcid={:08X} {} oid={:08X} stp={} cb={}\n",
            o.space,
            o.jcid,
            jcid_name(o.jcid),
            o.own_oid,
            o.stp,
            o.cb
        ));
        let ps = read_propset(&r, o.stp, o.cb);
        for (pid, v) in &ps.props {
            out.push_str(&format!("    pid={pid:06X} {}\n", fmt_pval(v)));
        }
    }
    out
}

/// Diagnostic: dump every section's page-series correlation — for each page,
/// the raw metadata OID + resolved title/level, the page-space OSID + whether
/// it resolved, and a short content fingerprint (first text/title of the
/// resolved content space). Lets us eyeball whether titles line up with content
/// and whether subpage levels are right, against the OneNote reference.
pub fn dump_sections(bytes: &[u8]) -> String {
    let r = Reader { d: bytes };
    if bytes.len() < 1024 || !r.is_one_section() {
        return "not a .one section".into();
    }
    let root = r.fcr(172);
    let mut wo = WalkOut::default();
    let mut visited = HashSet::new();
    let mut next_space = 0usize;
    let mut cur_rev = 0usize;
    let mut in_version = false;
    walk(
        &r, root, &mut wo, &mut visited, 0, 0, &mut next_space, &mut cur_rev,
        &mut in_version,
    );
    let objs = wo.objs;

    let mut spaces: std::collections::BTreeMap<usize, Vec<usize>> = Default::default();
    for (i, o) in objs.iter().enumerate() {
        spaces.entry(o.space).or_default().push(i);
    }
    // space → latest-revision oid map (matches import).
    let latest_of = |idxs: &[usize]| -> HashMap<u32, usize> {
        let mut m: HashMap<u32, usize> = HashMap::new();
        for &i in idxs {
            let e = m.entry(objs[i].own_oid).or_insert(i);
            if currency(&objs[i]) > currency(&objs[*e]) {
                *e = i;
            }
        }
        m
    };
    // Resolve a content space's fingerprint: first non-empty text-ish string.
    let space_fingerprint = |sp: usize| -> String {
        let Some(idxs) = spaces.get(&sp) else { return "<no space>".into() };
        let latest = latest_of(idxs);
        // Title node text first, else first rich-text run.
        for &i in idxs {
            let o = &objs[i];
            if o.jcid == JCID_TITLE || o.jcid == JCID_RICHTEXT || o.jcid == JCID_RICHTEXT_RUN {
                let ps = read_propset(&r, o.stp, o.cb);
                if let Some(t) = ps.run_text() {
                    let t = t.trim_matches('\0').trim();
                    if !t.is_empty() {
                        let _ = &latest; // (kept for parity with import)
                        return t.chars().take(50).collect();
                    }
                }
            }
        }
        "<no text>".into()
    };

    let mut out = String::new();
    for (&dir_sp, idxs) in &spaces {
        let Some(&si) = idxs
            .iter()
            .filter(|&&i| objs[i].jcid == JCID_SECTION_NODE)
            .max_by_key(|&&i| currency(&objs[i]))
        else {
            continue;
        };
        let latest = latest_of(idxs);
        let table = wo.gid_tables.get(&dir_sp);
        let section = read_propset(&r, objs[si].stp, objs[si].cb);
        let series_refs = section.oids(PID_ELEMENT_CHILDREN);
        out.push_str(&format!(
            "\n═══ SECTION dir_space={dir_sp} node_oid={:08X} series={} gidtable={} ═══\n",
            objs[si].own_oid,
            series_refs.len(),
            table.map(|t| t.len()).unwrap_or(0),
        ));
        let mut page_no = 0;
        for series_oid in series_refs {
            let Some(&pi) = latest.get(&series_oid) else {
                out.push_str(&format!("  series {series_oid:08X}: <unresolved>\n"));
                continue;
            };
            if objs[pi].jcid != JCID_PAGE_SERIES {
                out.push_str(&format!(
                    "  series {series_oid:08X}: jcid={:08X} (not a PageSeries)\n",
                    objs[pi].jcid
                ));
                continue;
            }
            let series = read_propset(&r, objs[pi].stp, objs[pi].cb);
            let page_spaces = series.osids(PID_PAGE_SPACES);
            let page_metas = series.oids(PID_PAGE_METADATA);
            out.push_str(&format!(
                "  PageSeries oid={series_oid:08X}: spaces={} metas={}\n",
                page_spaces.len(),
                page_metas.len()
            ));
            for (k, osid) in page_spaces.iter().enumerate() {
                page_no += 1;
                let (n, gidx) = (osid & 0xFF, osid >> 8);
                let guid = table.and_then(|t| t.get(&gidx));
                let sp = guid.and_then(|g| {
                    wo.space_gosids
                        .iter()
                        .find(|(_, gg)| {
                            &gg[..16] == g.as_slice()
                                && u32::from_le_bytes([gg[16], gg[17], gg[18], gg[19]]) == n
                        })
                        .map(|(&s, _)| s)
                });
                let (mut title, mut level) = ("<none>".to_string(), 0i64);
                let meta_oid = page_metas.get(k).copied();
                let meta_resolved = meta_oid.and_then(|o| latest.get(&o));
                if let Some(&mi) = meta_resolved {
                    let ps = read_propset(&r, objs[mi].stp, objs[mi].cb);
                    title = ps.utf16(PID_TITLE).unwrap_or_else(|| "<empty>".into());
                    level = ps.u32(PID_PAGE_LEVEL).map(|v| v as i64).unwrap_or(-1);
                }
                let fp = sp.map(space_fingerprint).unwrap_or_else(|| "<no space>".into());
                out.push_str(&format!(
                    "    p{page_no:>3} osid={osid:08X}→sp={:?} meta={:08X?}{} L{level} title={title:?}\n           content: {fp:?}\n",
                    sp,
                    meta_oid.unwrap_or(0),
                    if meta_resolved.is_some() { "" } else { "(unresolved!)" },
                ));
            }
        }
    }
    if out.is_empty() {
        out.push_str("no section nodes found\n");
    }
    out
}

/// Diagnostic: for a given space, dump its revisions — the declared roots
/// (RootObjectReference3FND) with their resolved ExGuid, and for the current
/// (role-1, latest) root, which object it resolves to and its content children.
/// Reveals the per-revision gid-table structure behind lost-content pages.
pub fn dump_revisions(bytes: &[u8], want_space: usize) -> String {
    let r = Reader { d: bytes };
    if bytes.len() < 1024 || !r.is_one_section() {
        return "not a .one section".into();
    }
    let root = r.fcr(172);
    let mut wo = WalkOut::default();
    let mut visited = HashSet::new();
    let mut next_space = 0usize;
    let mut cur_rev = 0usize;
    let mut in_version = false;
    walk(
        &r, root, &mut wo, &mut visited, 0, 0, &mut next_space, &mut cur_rev,
        &mut in_version,
    );
    let objs = &wo.objs;

    let exg = |oid: u32, rev: usize| -> Option<[u8; 20]> {
        let g = wo.rev_tables.get(rev)?.get(&(oid >> 8))?;
        let mut e = [0u8; 20];
        e[..16].copy_from_slice(g);
        e[16] = (oid & 0xFF) as u8;
        Some(e)
    };
    // ExGuid → latest object index, within the target space.
    let mut by_exg: HashMap<[u8; 20], usize> = HashMap::new();
    for (i, o) in objs.iter().enumerate() {
        if o.space != want_space {
            continue;
        }
        if let Some(e) = exg(o.own_oid, o.rev) {
            let ent = by_exg.entry(e).or_insert(i);
            if currency(o) > currency(&objs[*ent]) {
                *ent = i;
            }
        }
    }

    let short = |e: Option<[u8; 20]>| -> String {
        e.map(|e| format!("{:02X}{:02X}{:02X}..n{}", e[0], e[1], e[2], e[16]))
            .unwrap_or_else(|| "??".into())
    };
    let mut out = String::new();
    out.push_str(&format!(
        "space {want_space}: {} gid-table revisions\n",
        wo.rev_tables.len()
    ));
    // Every PageNode (0x0006000B) declaration: its rev, raw oid, resolved
    // ExGuid, and its 0x1C20 content children (raw + ExGuid-resolved). If the
    // revisions of one page share an ExGuid, ExGuid-keying unifies them.
    out.push_str("PageNode (0006000B) declarations:\n");
    for o in objs.iter().filter(|o| o.space == want_space && o.jcid == JCID_OUTLINE) {
        let ps = read_propset(&r, o.stp, o.cb);
        let kids = ps.oids(PID_ELEMENT_CHILDREN);
        let kids_exg: Vec<String> = kids.iter().map(|&k| short(exg(k, o.rev))).collect();
        out.push_str(&format!(
            "  rev={} oid={:08X} stp={} exg={} 1C20={:08X?}→{:?} 1D5F={:08X?}\n",
            o.rev, o.own_oid, o.stp, short(exg(o.own_oid, o.rev)),
            kids, kids_exg, ps.oids(0x001D5F),
        ));
    }
    // The latest object per ExGuid that is a PageNode with content children.
    out.push_str("\nExGuid-unified PageNodes with content:\n");
    let mut seen: HashSet<[u8; 20]> = HashSet::new();
    for (&e, &i) in &by_exg {
        let o = &objs[i];
        if o.jcid != JCID_OUTLINE || !seen.insert(e) {
            continue;
        }
        let ps = read_propset(&r, o.stp, o.cb);
        let kids = ps.oids(PID_ELEMENT_CHILDREN);
        if kids.is_empty() {
            continue;
        }
        // Resolve children to objects and show their jcids + any text.
        let mut kidinfo = Vec::new();
        for &k in &kids {
            if let Some(&ci) = exg(k, o.rev).and_then(|ke| by_exg.get(&ke)) {
                let co = &objs[ci];
                let cps = read_propset(&r, co.stp, co.cb);
                let t = cps.run_text().unwrap_or_default();
                let t: String = t.trim_matches('\0').chars().take(24).collect();
                kidinfo.push(format!("{}{}", jcid_name(co.jcid), if t.is_empty() { String::new() } else { format!("({t:?})") }));
            } else {
                kidinfo.push("UNRESOLVED".into());
            }
        }
        out.push_str(&format!(
            "  exg={} stp={} 1C20 children [{}]: {}\n",
            short(Some(e)), o.stp, kids.len(), kidinfo.join(", ")
        ));
    }
    out
}

/// Hexdump every ink-stroke data object (JCID 0x00020047): all scalar props +
/// full hex of the packed point data (0x340B), for reverse-engineering the
/// stroke encoding. `limit` caps how many strokes are dumped.
pub fn dump_ink(bytes: &[u8], limit: usize) -> String {
    let r = Reader { d: bytes };
    if bytes.len() < 1024 || !r.is_one_section() {
        return "not a .one section".into();
    }
    let root = r.fcr(172);
    let mut wo = WalkOut::default();
    let mut visited = HashSet::new();
    let mut next_space = 0usize;
    let mut cur_rev = 0usize;
    let mut in_version = false;
    walk(
        &r, root, &mut wo, &mut visited, 0, 0, &mut next_space, &mut cur_rev,
        &mut in_version,
    );
    let objs = wo.objs;

    // True span of a delta channel: cumsum (first value = absolute start),
    // then max-min of the resulting positions (no phantom origin).
    fn cum_range(vals: &[i64]) -> (i64, i64) {
        if vals.is_empty() {
            return (0, 0);
        }
        let mut acc = 0i64;
        let (mut lo, mut hi) = (i64::MAX, i64::MIN);
        for &v in vals {
            acc += v;
            lo = lo.min(acc);
            hi = hi.max(acc);
        }
        (lo, hi)
    }
    let mut out = String::new();
    let mut n = 0;
    let mut seen = HashSet::new();
    let mut dumped = 0;
    for o in &objs {
        if o.jcid != 0x00020047 || !seen.insert(o.own_oid) {
            continue;
        }
        if n >= limit {
            break;
        }
        n += 1;
        let ps = read_propset(&r, o.stp, o.cb);
        let Some(PVal::Str(path_b)) = ps.get(0x340B) else { continue };
        let Some(vals) = decode_multibyte_signed(path_b) else {
            out.push_str(&format!("stroke {:08X}: DECODE FAIL\n", o.own_oid));
            continue;
        };
        // Compare the 2- and 3-channel interpretations: for each, the X/Y
        // cumulative span. The correct channel count gives a compact stroke.
        let l = vals.len();
        // For a 3-channel split, show each channel's cumulative span; dump full
        // values for the first few strokes whose 2nd channel runs away.
        if l % 3 == 0 && l > 0 {
            let per = l / 3;
            let sp = |s: &[i64]| {
                let (a, b) = cum_range(s);
                b - a
            };
            let (c0, c1, c2) = (sp(&vals[..per]), sp(&vals[per..2 * per]), sp(&vals[2 * per..]));
            // True runaway: X or Y channel SPAN (not position) exceeds a page.
            let runaway = c0 > 15000 || c1 > 15000;
            out.push_str(&format!(
                "stroke {:08X} vals={l} 3ch pts={per} ch-spans=[{c0},{c1},{c2}]{}\n",
                o.own_oid,
                if runaway { " RUNAWAY" } else { "" }
            ));
            if runaway && dumped < 3 {
                dumped += 1;
                out.push_str(&format!("   ch0: {:?}\n", &vals[..per.min(24)]));
                out.push_str(&format!("   ch1: {:?}\n", &vals[per..(per + 24).min(2 * per)]));
                out.push_str(&format!("   ch2: {:?}\n", &vals[2 * per..(2 * per + 24).min(l)]));
            }
        } else {
            out.push_str(&format!("stroke {:08X} vals={l} (not /3)\n", o.own_oid));
        }
    }
    out
}

fn fmt_pval(v: &PVal) -> String {
    match v {
        PVal::Bool(b) => format!("bool={b}"),
        PVal::U32(u) => format!("u32={u:08X} i32={} f32={}", *u as i32, f32::from_bits(*u)),
        PVal::U64(u) => format!("u64={u}"),
        PVal::Str(b) => {
            let u16s: String = decode_utf16(b)
                .chars()
                .take(50)
                .map(|c| if c.is_control() { '·' } else { c })
                .collect();
            let u8s: String = String::from_utf8_lossy(b)
                .chars()
                .take(50)
                .map(|c| if c.is_control() { '·' } else { c })
                .collect();
            format!("str(cb={}) u16={u16s:?} u8={u8s:?}", b.len())
        }
        PVal::Oids(v) => format!("oids={v:08X?}"),
        PVal::Osids(v) => format!("osids={v:08X?}"),
        PVal::Array(sets) => {
            let inner: Vec<String> = sets
                .iter()
                .map(|set| {
                    let ps: Vec<String> = set
                        .props
                        .iter()
                        .map(|(pid, v)| format!("{pid:06X}={}", fmt_pval(v)))
                        .collect();
                    format!("{{{}}}", ps.join(" "))
                })
                .collect();
            format!("array[{}] {}", sets.len(), inner.join(" "))
        }
        PVal::Other(t) => format!("other(type=0x{t:02X})"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Build one object property set the way MS-ONESTORE lays it out, so the
    /// property walk can be exercised without a real file.
    ///
    /// Header: oid count (bit 31 set = no object-space stream), the oid stream,
    /// then the property count, the property-id array, and the data.
    fn propset_blob(oids: &[u32], props: &[(u32, u8, Vec<u8>)]) -> Vec<u8> {
        propset_blob_osids(oids, &[], props)
    }

    /// The same, with an object-SPACE id stream as well.
    ///
    /// A page series references its pages through one — 0x1D63 is an
    /// ArrayOfObjectSpaceIDs — and CLEARING bit 31 of the header is the only
    /// thing that tells [read_propset] the stream is there at all. With no
    /// osids this emits byte-for-byte what [propset_blob] always did.
    fn propset_blob_osids(
        oids: &[u32],
        osids: &[u32],
        props: &[(u32, u8, Vec<u8>)],
    ) -> Vec<u8> {
        let mut b = Vec::new();
        let no_osids = if osids.is_empty() { 0x8000_0000 } else { 0 };
        b.extend_from_slice(&((oids.len() as u32) | no_osids).to_le_bytes());
        for o in oids {
            b.extend_from_slice(&o.to_le_bytes());
        }
        if !osids.is_empty() {
            b.extend_from_slice(&(osids.len() as u32).to_le_bytes());
            for s in osids {
                b.extend_from_slice(&s.to_le_bytes());
            }
        }
        b.extend_from_slice(&(props.len() as u16).to_le_bytes());
        for (pid, ptype, _) in props {
            b.extend_from_slice(&(pid | ((*ptype as u32) << 26)).to_le_bytes());
        }
        for (_, _, data) in props {
            b.extend_from_slice(data);
        }
        b
    }

    /// A tagged paragraph, reduced to the shape that broke it.
    ///
    /// Measured from a real tagged `.one`: OneNote writes the paragraph's tag
    /// reference as property 0x3489, type 0x10 (`ArrayOfPropertyValues`), whose
    /// single element is a property set holding 0x3488 — an ObjectID pointing at
    /// the tag definition. On the *to-do* paragraph that array is written BEFORE
    /// the run's own text (0x3498), and 0x10 was sized at a flat 4 bytes.
    ///
    /// So the text's length prefix was read out of the middle of the tag array,
    /// came back as nonsense, failed its bounds check, and the paragraph
    /// vanished from the import with no warning at all. One line of a page,
    /// gone, on every tagged to-do anyone ever imported.
    #[test]
    fn a_tag_array_before_the_text_does_not_eat_it() {
        // ArrayOfPropertyValues: count, prid, then one nested PropertySet
        // holding a single ObjectID property (0x3488).
        let mut array = Vec::new();
        array.extend_from_slice(&1u32.to_le_bytes()); // cProperties
        array.extend_from_slice(&0x3488u32.to_le_bytes()); // prid
        array.extend_from_slice(&1u16.to_le_bytes()); // nested count
        array.extend_from_slice(&(0x3488u32 | (0x08 << 26)).to_le_bytes());

        let mut text = Vec::new();
        text.extend_from_slice(&4u32.to_le_bytes());
        text.extend_from_slice(b"Todo");

        let blob = propset_blob(
            &[0x15],
            &[(0x3489, 0x10, array), (0x3498, 0x07, text)],
        );
        let r = Reader { d: &blob };
        let set = read_propset(&r, 0, blob.len());

        let text = set.props.iter().find(|(pid, _)| *pid == 0x3498);
        match text {
            Some((_, PVal::Str(b))) => assert_eq!(b, b"Todo"),
            other => panic!("the tagged line lost its text: {other:?}"),
        }
        // And the tag itself is readable, which is what makes import possible.
        match set.props.iter().find(|(pid, _)| *pid == 0x3489) {
            Some((_, PVal::Array(sets))) => {
                assert_eq!(sets.len(), 1);
                assert!(matches!(
                    sets[0].props.first(),
                    Some((0x3488, PVal::Oids(v))) if v == &vec![0x15]
                ));
            }
            other => panic!("tag reference not decoded: {other:?}"),
        }
    }

    /// The same walk, with the array LAST — the case that always worked, kept
    /// so a future change can't fix one ordering by breaking the other.
    #[test]
    fn a_tag_array_after_the_text_still_reads_both() {
        let mut array = Vec::new();
        array.extend_from_slice(&1u32.to_le_bytes());
        array.extend_from_slice(&0x3488u32.to_le_bytes());
        array.extend_from_slice(&1u16.to_le_bytes());
        array.extend_from_slice(&(0x3488u32 | (0x08 << 26)).to_le_bytes());
        let mut text = Vec::new();
        text.extend_from_slice(&8u32.to_le_bytes());
        text.extend_from_slice(b"Question");

        let blob = propset_blob(
            &[0x19],
            &[(0x3498, 0x07, text), (0x3489, 0x10, array)],
        );
        let r = Reader { d: &blob };
        let set = read_propset(&r, 0, blob.len());
        assert!(matches!(
            set.props.iter().find(|(pid, _)| *pid == 0x3498),
            Some((_, PVal::Str(b))) if b == b"Question"
        ));
    }

    /// A malformed nested structure must stop, not recurse until the stack does.
    #[test]
    fn absurd_nesting_is_refused_rather_than_followed() {
        // cProperties large, then a nested set that claims to contain itself.
        let mut array = Vec::new();
        array.extend_from_slice(&0xFFFF_FFFFu32.to_le_bytes());
        array.extend_from_slice(&0x3488u32.to_le_bytes());
        let blob = propset_blob(&[], &[(0x3489, 0x10, array)]);
        let r = Reader { d: &blob };
        let set = read_propset(&r, 0, blob.len()); // must return, not hang
        assert_eq!(set.props.len(), 1);
    }

    /// Reported: "some symbols end up with $x$ around them when I start
    /// editing a box". They do: OneNote marks a character inserted from the
    /// symbol palette as a math run, and every math run was wrapped in `$…$`.
    /// The view renders that as maths and the editor shows the source, so the
    /// delimiters appear the moment you click in.
    #[test]
    fn a_lone_symbol_is_not_wrapped_in_math_delimiters() {
        let math = Style { is_math: true, ..Default::default() };
        for sym in ["∀", "∈", "ℝ", "θ", "≤", "∑"] {
            let run = SRun { math_objs: Vec::new(), text: sym.into(), style: math.clone() };
            assert_eq!(
                run_markdown(&run),
                sym,
                "a bare {sym} should import as itself, not as ${sym}$"
            );
        }
    }

    /// The shape that occurs in a real file, and that the first attempt at this
    /// fix missed entirely.
    ///
    /// OneNote run text is NUL-terminated, and `str::trim` does not strip a NUL
    /// because a NUL is not whitespace — so comparing the converted LaTeX
    /// against an un-normalised plain string compared "∀" with "∀\0" and never
    /// matched. The symbols stayed wrapped, the tests passed, and the bug was
    /// still there on the next import. Both sides are normalised now.
    #[test]
    fn a_symbol_with_a_trailing_nul_is_still_just_a_symbol() {
        let math = Style { is_math: true, ..Default::default() };
        for raw in ["∀\0", "∈\0\0", "ℝ\0"] {
            let run = SRun { math_objs: Vec::new(), text: raw.into(), style: math.clone() };
            let out = run_markdown(&run);
            assert!(
                !out.contains('$'),
                "{raw:?} imported as {out:?} — still wrapped"
            );
            assert!(!out.contains('\0'), "{out:?} kept a NUL");
        }
    }

    /// Internal whitespace is collapsed by the LaTeX path too, so it must not
    /// count as a difference either.
    #[test]
    fn spacing_alone_does_not_make_it_an_equation() {
        let run = SRun { math_objs: Vec::new(),
            text: "E  ∩  O\0".into(),
            style: Style { is_math: true, ..Default::default() },
        };
        assert!(!run_markdown(&run).contains('$'));
    }

    /// …while something that genuinely needs typesetting keeps its delimiters.
    #[test]
    fn real_notation_still_becomes_inline_math() {
        let run = SRun { math_objs: Vec::new(),
            text: "\u{FDD0}a\u{FDEE}b\u{FDEF}".into(),
            style: Style { is_math: true, ..Default::default() },
        };
        let out = run_markdown(&run);
        assert!(out.starts_with('$') && out.ends_with('$'), "got {out:?}");
        assert!(out.contains("\\frac"), "got {out:?}");
    }

    #[test]
    fn healing_unwraps_a_symbol_but_never_an_equation() {
        // What an already-imported page looks like.
        assert_eq!(
            unwrap_needless_math("for all $∀$ x in $S$"),
            "for all ∀ x in S"
        );
        // Real notation keeps its delimiters, whatever else is on the line.
        for eq in [
            "$\\frac{a}{b}$",
            "$x^2$",
            "$a_1$",
            "$\\sum_{i=1}^{n}$",
        ] {
            assert_eq!(unwrap_needless_math(eq), eq, "{eq} must stay maths");
        }
        // Display maths is a different dialect and is left alone.
        assert_eq!(unwrap_needless_math("$$x^2$$"), "$$x^2$$");
        // A lone dollar is a dollar.
        assert_eq!(unwrap_needless_math("costs $5 today"), "costs $5 today");
        // Mixed line: unwrap the symbol, keep the equation.
        assert_eq!(
            unwrap_needless_math("if $θ$ then $x^2$"),
            "if θ then $x^2$"
        );
    }

    #[test]
    fn healing_leaves_ordinary_prose_untouched() {
        for s in ["nothing here", "", "a $ b $ c"] {
            let out = unwrap_needless_math(s);
            assert!(out.len() <= s.len() + 1, "{s:?} -> {out:?}");
        }
    }

    /// Tags land on the line they marked, counted as lines are EMITTED.
    ///
    /// The trap this pins: an image whose placeholder is missing is skipped
    /// during emission, so counting by position in the input list would drift
    /// on exactly the pages that have images — and a tag would then mark a
    /// sentence it was never on.
    #[test]
    fn a_tag_lands_on_the_line_it_marked() {
        let tag = |label: &str| ParaTag { label: label.into(), shape: 0 };
        let mut first = text_line(0, "This is a question", false);
        first.tags = vec![tag("Question")];
        let mut third = text_line(0, "And now a todo", false);
        third.tags = vec![tag("To Do")];
        // An image with no stored placeholder sits between them and is skipped.
        let ghost = Line {
            depth: 0,
            tags: Vec::new(),
            is_list: false,
            bullet: String::new(),
            runs: Vec::new(),
            math: None,
            table: None,
            image: Some(999),
        };
        let lines = vec![&first, &ghost, &third];
        let (md, tags) = outline_markdown_tagged(&lines, &HashMap::new(), Some(0));

        assert_eq!(md, "This is a question\nAnd now a todo");
        assert_eq!(tags.len(), 2);
        assert_eq!((tags[0].line, tags[0].label.as_str()), (0, "Question"));
        assert_eq!(
            (tags[1].line, tags[1].label.as_str()),
            (1, "To Do"),
            "the skipped image must not push the tag off its line"
        );
    }

    /// A paragraph with no tags costs nothing and reports nothing.
    #[test]
    fn an_untagged_paragraph_reports_no_tags() {
        let l = text_line(0, "just prose", false);
        let (_, tags) = outline_markdown_tagged(&[&l], &HashMap::new(), Some(0));
        assert!(tags.is_empty());
    }

    #[test]
    fn rejects_non_one_input() {
        let out = import_one_json(b"not a onenote file at all, padding.......................");
        assert!(out.contains("\"ok\":false"));
    }

    fn text_line(depth: usize, text: &str, is_list: bool) -> Line {
        Line {
            depth,
            tags: Vec::new(),
            is_list,
            bullet: if is_list { "-".into() } else { String::new() },
            runs: vec![SRun { math_objs: Vec::new(), text: text.into(), style: Style::default() }],
            math: None,
            table: None,
            image: None,
        }
    }

    fn blank_line(depth: usize) -> Line {
        Line {
            depth,
            tags: Vec::new(),
            is_list: false,
            bullet: String::new(),
            runs: Vec::new(),
            math: None,
            table: None,
            image: None,
        }
    }

    /// One paragraph as OneNote actually stores it: a RichText (0x0D) container
    /// whose single OID child is a RichText_Run (0x0E). `run_text` of `None`
    /// makes the run textless — the shape of a line the writer left empty.
    ///
    /// Returns the walked lines, so a test can assert how many the PAIR
    /// produced. That count is the whole ballgame: one line per pair is
    /// correct, two is the double-spacing defect.
    fn walk_paragraph_pair(run_text: Option<&str>) -> Vec<Line> {
        let container = propset_blob(&[0x0000_0002], &[]);
        let run = match run_text {
            Some(t) => {
                let mut data = (t.len() as u32).to_le_bytes().to_vec();
                data.extend_from_slice(t.as_bytes());
                propset_blob(&[], &[(PID_TEXT_UTF8, 0x07, data)])
            }
            None => propset_blob(&[], &[]),
        };
        let mut blob = container.clone();
        let run_at = blob.len();
        blob.extend_from_slice(&run);

        let objs = vec![
            Obj {
                own_oid: 0x0000_0001,
                jcid: JCID_RICHTEXT,
                stp: 0,
                cb: container.len(),
                space: 0,
                rev: 0,
                versioned: false,
            },
            Obj {
                own_oid: 0x0000_0002,
                jcid: JCID_RICHTEXT_RUN,
                stp: run_at,
                cb: run.len(),
                space: 0,
                rev: 0,
                versioned: false,
            },
        ];
        // One revision whose guidIndex 0 is some GUID; CompactID = idx<<8 | n.
        let guid = [7u8; 16];
        let rev_tables = vec![HashMap::from([(0u32, guid)])];
        let exg = |n: u8| {
            let mut e = [0u8; 20];
            e[..16].copy_from_slice(&guid);
            e[16] = n;
            e
        };
        let registry = HashMap::from([(exg(1), 0u32), (exg(2), 1u32)]);
        let res = Resolver {
            objs: &objs,
            rev_tables: &rev_tables,
            registry: &registry,
            by_canon: HashMap::from([(CANON_BIT, 0usize), (1 | CANON_BIT, 1usize)]),
        };
        let r = Reader { d: &blob };
        let mut out = Vec::new();
        let mut guard = HashSet::new();
        collect_tree(&r, &objs[0], &res, 0, &mut out, &mut guard);
        out
    }

    /// The blank-line discriminator, pinned at the object level.
    ///
    /// Reported: "across every page ive checked the blank lines ive added
    /// havent once been respected and are always ignored in the import" — and
    /// the earlier attempt to honour them keyed on "is the text empty", which
    /// double-spaced everything (24 content lines came back separated by 31
    /// blanks) and had to be reverted.
    ///
    /// The signal is WHICH object is empty, not that it is. A paragraph is
    /// always a 0x0D container plus a 0x0E run, and the container is textless
    /// by construction — of the 1600 RichText objects across the two reference
    /// files, none carried text. So the container must never produce a line and
    /// the run always must.
    #[test]
    fn an_empty_text_run_is_a_blank_line_but_its_container_is_not() {
        let lines = walk_paragraph_pair(None);
        // ONE line, not two: the container contributed nothing. Two here is
        // exactly the double-spacing that got the first attempt reverted.
        assert_eq!(lines.len(), 1, "a paragraph pair must yield one line");
        assert!(lines[0].is_blank(), "the empty run should read as a blank line");
    }

    /// The same pair with text: still one line, and it is the text. Guards the
    /// other direction — suppressing the container must not cost the content.
    #[test]
    fn a_paragraph_pair_with_text_yields_exactly_one_content_line() {
        let lines = walk_paragraph_pair(Some("Tautology"));
        assert_eq!(lines.len(), 1, "a paragraph pair must yield one line");
        assert!(!lines[0].is_blank());
        assert_eq!(lines[0].plain(), "Tautology");
    }

    /// A blank renders as a genuinely empty row — no indent, no bullet. Trailing
    /// whitespace here reads as an indented empty paragraph and shows up in
    /// every diff of the exported Markdown.
    ///
    /// **This covers the TABLE-CELL path, not the import path.** `base_depth:
    /// None` is [outline_markdown_tagged]'s own fallback minimum, and the only
    /// caller that passes `None` is [parse_table], once per cell. Every page
    /// outline arrives from `emit_boxes` with `Some(base_depth)` already
    /// computed, so the two minimums are separate code and need separate tests
    /// — see [a_blank_outdented_from_the_prose_does_not_re_base_the_box] for
    /// the one that guards the import path.
    #[test]
    fn a_blank_in_a_table_cell_renders_empty_and_does_not_re_base_the_cell() {
        let lines = [
            text_line(2, "Can be seen in a truth table as a column of 0s", false),
            blank_line(1),
            text_line(2, "Variables", false),
        ];
        let refs: Vec<&Line> = lines.iter().collect();
        let md = outline_markdown(&refs, &HashMap::new(), None);
        assert_eq!(
            md.lines().collect::<Vec<_>>(),
            ["Can be seen in a truth table as a column of 0s", "", "Variables"]
        );
    }

    /// The indent baseline for a page outline is computed in `emit_boxes`, and
    /// it has to be measured over the lines that actually render an indent.
    ///
    /// A blank keeps the `depth` of the paragraph it was typed in, so a writer
    /// who presses Enter at the outer level between two indented paragraphs
    /// leaves a blank one level OUT from its neighbours. Letting that into the
    /// minimum re-bases the WHOLE box, because the base is taken once for the
    /// whole outline: measured across the reference notebook, honouring blanks
    /// without excluding them here pushed 130 lines in 14 boxes on 12 pages one
    /// level right — two spaces each — including "Permutations", "Methods of
    /// Proof: Principle of Mathematical Induction" and "Finite and Infinite
    /// Countable Sets".
    ///
    /// Goes through `emit_boxes` deliberately. It is the only caller that
    /// computes this minimum; `outline_markdown`'s own fallback is reached from
    /// a table cell alone, so a test written against that one leaves the line
    /// that does the work here unguarded (it did, and deleting the filter kept
    /// the suite green).
    #[test]
    fn a_blank_outdented_from_the_prose_does_not_re_base_the_box() {
        let lines = [
            text_line(2, "Can be seen in a truth table as a column of 0s", false),
            blank_line(1), // Enter pressed at the outer level
            text_line(2, "Variables", false),
        ];
        let mut boxes = Vec::new();
        emit_boxes(&lines, 100.0, 50.0, None, &mut boxes, &HashMap::new(), 1);
        assert_eq!(boxes.len(), 1, "prose and its blank stay one text box");
        assert_eq!(
            boxes[0].markdown.lines().collect::<Vec<_>>(),
            ["Can be seen in a truth table as a column of 0s", "", "Variables"],
            "a blank emits no indent, so it must not set the indent of the box"
        );
    }

    /// The same trap one segment further in. `emit_boxes` splits an outline at
    /// every math line but shares ONE base depth across the pieces, so a blank
    /// admitted to the minimum shifts the segments after the equation too — the
    /// mechanism by which a single stray blank moved lines on pages whose gap
    /// and whose indented prose were nowhere near each other.
    #[test]
    fn the_shared_base_depth_survives_a_math_split_with_a_blank_in_it() {
        let mut math = text_line(1, "", false);
        math.math = Some("x^2".into());
        let lines = [
            text_line(2, "before the equation", false),
            blank_line(1),
            math,
            text_line(2, "after the equation", false),
        ];
        let mut boxes = Vec::new();
        emit_boxes(&lines, 0.0, 0.0, None, &mut boxes, &HashMap::new(), 1);
        let text: Vec<&str> = boxes
            .iter()
            .filter(|b| b.kind == "text")
            .map(|b| b.markdown.as_str())
            .collect();
        assert_eq!(text, ["before the equation", "after the equation"]);
    }

    /// Regression for the last known layout defect: non-list paragraphs used
    /// to be emitted flush-left whatever their depth, losing OneNote's indent
    /// (a measured 45u-per-lost-level horizontal offset on those rows).
    #[test]
    fn indented_prose_keeps_its_level() {
        let lines = [
            text_line(1, "top", false),
            text_line(3, "deep paragraph", false),
            text_line(2, "item", true),
        ];
        let refs: Vec<&Line> = lines.iter().collect();
        let md = outline_markdown(&refs, &HashMap::new(), None);
        let rows: Vec<&str> = md.lines().collect();
        assert_eq!(rows[0], "top"); // shallowest normalises to the margin
        assert_eq!(rows[1], "    deep paragraph"); // 2 levels = 4 spaces, NOT flush
        assert_eq!(rows[2], "  - item");
    }

    /// Office stores a Symbol-font char as U+F000+byte; keyed on the run's
    /// font the byte maps deterministically. `∈` is Symbol 0xCE, `¬` is 0xD8,
    /// and the reference notebook's 17× U+F0AC are left arrows.
    #[test]
    fn symbol_pua_translates_when_the_font_says_symbol() {
        let mut runs = vec![SRun { math_objs: Vec::new(),
            text: "x \u{F0CE} A \u{F0D8}B \u{F0AC}".into(),
            style: Style { font: Some("Symbol".into()), ..Default::default() },
        }];
        translate_symbol_pua(&mut runs);
        assert_eq!(runs[0].text, "x \u{2208} A ¬B \u{2190}");
        assert_eq!(runs[0].style.font, None, "now real Unicode, not Symbol-encoded");

        // A different font must NOT translate — Wingdings 0xCE is a different
        // glyph entirely, and guessing would corrupt content.
        let mut wd = vec![SRun { math_objs: Vec::new(),
            text: "\u{F0CE}".into(),
            style: Style { font: Some("Wingdings".into()), ..Default::default() },
        }];
        translate_symbol_pua(&mut wd);
        assert_eq!(wd[0].text, "\u{F0CE}");
        assert_eq!(wd[0].style.font.as_deref(), Some("Wingdings"));

        // An unmappable byte (bracket extender 0xE6) keeps the whole run
        // untouched rather than half-translating it.
        let mut partial = vec![SRun { math_objs: Vec::new(),
            text: "\u{F0CE}\u{F0E6}".into(),
            style: Style { font: Some("Symbol".into()), ..Default::default() },
        }];
        translate_symbol_pua(&mut partial);
        assert_eq!(partial[0].text, "\u{F0CE}\u{F0E6}");
    }

    /// A hyperlink is a Word FIELD inside the paragraph's own text, not a
    /// property — so an unfiltered import put `﷟HYPERLINK "https://…"` in the
    /// note next to the words it was attached to, and there was nothing to
    /// click.
    #[test]
    fn hyperlink_field_becomes_a_markdown_link() {
        assert_eq!(
            linkify_field_codes(
                "See \u{FDDF}HYPERLINK \"https://www.youtube.com/watch?v=DsT_YiMiUQo\"this video"
            ),
            "See [this video](https://www.youtube.com/watch?v=DsT_YiMiUQo)"
        );
        // Word's full form, with the separator and end markers.
        assert_eq!(
            linkify_field_codes(
                "\u{13}HYPERLINK \"https://a.test/x\"\u{14}label\u{15} tail"
            ),
            "[label](https://a.test/x) tail"
        );
        // A `\l` switch names a fragment inside the target.
        assert_eq!(
            linkify_field_codes("\u{FDDF}HYPERLINK \"https://a.test/p\" \\l \"sec2\"Jump"),
            "[Jump](https://a.test/p#sec2)"
        );
    }

    /// No display text at all still has to produce something clickable, and the
    /// address is information the student can act on.
    #[test]
    fn hyperlink_without_display_text_links_the_url() {
        assert_eq!(
            linkify_field_codes("\u{FDDF}HYPERLINK \"https://a.test/x\""),
            "[https://a.test/x](https://a.test/x)"
        );
    }

    /// The app opens http/https/mailto only (a deliberate security decision),
    /// so anything else must degrade to plain text — emitting
    /// `[x](onenote:…)` would print as literal source, i.e. new junk.
    ///
    /// But the ADDRESS is kept. This same conversion runs over notes that were
    /// imported long ago (the repair path), where the `.one` may be gone, so a
    /// silently discarded link target is user data nothing can bring back.
    #[test]
    fn unopenable_schemes_degrade_to_text_but_keep_the_address() {
        assert_eq!(
            linkify_field_codes("\u{FDDF}HYPERLINK \"onenote:///C:/notes/a.one\"My page"),
            "My page (onenote:///C:/notes/a.one)"
        );
        assert_eq!(
            linkify_field_codes("a \u{FDDF}HYPERLINK \"file:///c:/x.pdf\"the PDF b"),
            "a the PDF b (file:///c:/x.pdf)"
        );
    }

    /// The app's link regex reads the target as `[^)\s]+`, so a space or a
    /// paren truncates it — but an existing escape must not be double-encoded.
    #[test]
    fn url_is_encoded_only_where_the_renderer_would_break() {
        assert_eq!(
            linkify_field_codes("\u{FDDF}HYPERLINK \"https://a.test/my file (1).pdf\"doc"),
            "[doc](https://a.test/my%20file%20%281%29.pdf)"
        );
        assert_eq!(encode_url("https://a.test/a%20b"), "https://a.test/a%20b");
    }

    /// An instruction we don't understand must never cost the user text — but
    /// the scaffolding still has to go.
    #[test]
    fn unknown_field_keeps_its_text_and_loses_its_markers() {
        let out = linkify_field_codes("see \u{13}PAGEREF _Toc1 \\h \u{14}page 4\u{15}.");
        assert_eq!(out, "see PAGEREF _Toc1 \\h page 4.");
        assert!(
            !out.chars().any(|c| is_field_control(c) || is_math_control(c)),
            "no field scaffolding may reach the note: {out:?}"
        );
    }

    /// The real layout, taken byte-for-byte from
    /// `Natural Language and Intro to Truth Tables.one`: one text buffer,
    /// 0x1E12 boundaries at 7 and 63, three 0x1E13 style OIDs.
    ///
    /// The trap this pins: OneNote gives the invisible instruction characters
    /// the *surrounding prose's* formatting (here, bold — the same as
    /// "Video: ") and the visible label the link's. Matching the label by
    /// "same style as the instruction" therefore gets it exactly backwards —
    /// it stops before the real label and walks back into the sentence, which
    /// is how this line first came out as `[Video:](url)Natural Language …`.
    /// The run BOUNDARY at the instruction's end is the reliable signal.
    #[test]
    fn real_onenote_hyperlink_labels_the_text_that_follows() {
        let bold = Style { bold: true, ..Default::default() };
        let mut runs = vec![
            SRun { math_objs: Vec::new(), text: "Video: ".into(), style: bold.clone() },
            SRun { math_objs: Vec::new(),
                text: "\u{FDDF}HYPERLINK \"https://www.youtube.com/watch?v=DsT_YiMiUQo\""
                    .into(),
                style: bold,
            },
            SRun { math_objs: Vec::new(),
                text: "Natural Language and Introduction to Truth Tables".into(),
                style: Style::default(),
            },
        ];
        // Boundaries line up with the file: "Video: " is 7 chars, and the
        // marker plus `HYPERLINK "<43-char url>"` is 56 more.
        assert_eq!(runs[0].text.chars().count(), 7);
        assert_eq!(runs[1].text.chars().count(), 56);

        linkify_hyperlink_runs(&mut runs);
        assert_eq!(
            render_runs(&runs),
            "**Video:** [Natural Language and Introduction to Truth Tables]\
             (https://www.youtube.com/watch?v=DsT_YiMiUQo)"
        );
    }

    /// The fallback, for a field with nothing after it: take the preceding run
    /// only when it actually looks like link text. Deliberately not a
    /// same-style-as-the-instruction test — that is what ate the sentence.
    #[test]
    fn a_trailing_field_labels_the_link_styled_run_before_it() {
        let link = Style { underline: true, color: 0x0563C1, ..Default::default() };
        let mut runs = vec![
            SRun { math_objs: Vec::new(), text: "Watch ".into(), style: Style::default() },
            SRun { math_objs: Vec::new(), text: "this video".into(), style: link },
            SRun { math_objs: Vec::new(),
                text: "\u{FDDF}HYPERLINK \"https://a.test/v\"".into(),
                style: Style::default(),
            },
        ];
        linkify_hyperlink_runs(&mut runs);
        assert_eq!(render_runs(&runs), "Watch [this video](https://a.test/v)");
    }

    /// Plain prose before a trailing field is NOT a label — it stays prose,
    /// and the address stands in for itself.
    #[test]
    fn plain_prose_before_a_trailing_field_is_not_eaten() {
        // Run for BOTH colour shapes, because the real file distinguishes
        // them: OneNote writes FF000000 for *automatic* black, and 75 of the
        // 78 styled runs in it carry exactly that. A fixture built only from
        // `Style::default()` (colour 0) passes for a reason unrelated to the
        // guard working — and that false assurance is how the sentence-eating
        // `[Video:](url)…` behaviour survived a rewrite meant to kill it.
        for color in [0u32, 0xFF00_0000] {
            let style = Style { color, ..Default::default() };
            let mut runs = vec![
                SRun { math_objs: Vec::new(),
                    text: "Some notes about logic ".into(),
                    style: style.clone(),
                },
                SRun { math_objs: Vec::new(),
                    text: "\u{FDDF}HYPERLINK \"https://a.test/v\"".into(),
                    style,
                },
            ];
            linkify_hyperlink_runs(&mut runs);
            let md = render_runs(&runs);
            assert!(
                md.starts_with("Some notes about logic "),
                "color {color:08X}: {md:?}"
            );
            assert!(
                md.contains("[https://a.test/v](https://a.test/v)"),
                "color {color:08X}: {md:?}"
            );
        }
    }

    /// The label is bounded by its OWN run. Extending through following runs
    /// that merely compare equal under `same_visible` swallows the prose after
    /// the link — we parse few style properties, so "looks the same" is a much
    /// weaker signal than the boundary that put the label in its own run.
    #[test]
    fn the_label_does_not_absorb_the_prose_after_it() {
        let link = Style { underline: true, ..Default::default() };
        let mut runs = vec![
            SRun { math_objs: Vec::new(),
                text: "\u{FDDF}HYPERLINK \"https://a.test/v\"".into(),
                style: Style::default(),
            },
            SRun { math_objs: Vec::new(), text: "watch this".into(), style: link },
            SRun { math_objs: Vec::new(), text: " before the exam".into(), style: Style::default() },
        ];
        linkify_hyperlink_runs(&mut runs);
        assert_eq!(
            render_runs(&runs),
            "[watch this](https://a.test/v) before the exam"
        );
    }

    /// The emitted link must be NAKED. The app's inline parser is
    /// non-recursive, so `{{#0563C1 ++[x](y)++}}` renders as literal source —
    /// the single easiest way to ship a fix that fixes nothing.
    #[test]
    fn imported_link_carries_no_emphasis_wrapper() {
        let mut runs = vec![SRun { math_objs: Vec::new(),
            text: "\u{FDDF}HYPERLINK \"https://a.test/v\"watch".into(),
            style: Style {
                underline: true,
                color: 0x0563C1,
                bold: true,
                ..Default::default()
            },
        }];
        linkify_hyperlink_runs(&mut runs);
        let md = render_runs(&runs);
        assert_eq!(md, "[watch](https://a.test/v)");
        assert!(!md.contains("++") && !md.contains("{{#") && !md.contains("**"));
    }

    /// Student notebooks are full of phone photos, which are JPEG — a PNG-only
    /// scan meant those silently vanished at import.
    #[test]
    fn scans_jpeg_alongside_png() {
        // Minimal but structurally real JPEG: SOI, APP0, SOF0 (2x3), SOS with
        // a tiny scan, EOI.
        let mut jpg: Vec<u8> = vec![0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x04, 0x00, 0x00];
        // SOF0: length 0x0B = 2 + precision(1) + h(2) + w(2) + ncomp(1) + 3.
        jpg.extend_from_slice(&[
            0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x03, 0x00, 0x02, 0x01, 0x01, 0x11,
            0x00,
        ]);
        jpg.extend_from_slice(&[0xFF, 0xDA, 0x00, 0x04, 0x00, 0x00]);
        jpg.extend_from_slice(&[0x12, 0x34, 0xFF, 0x00, 0x56]); // stuffed FF00
        jpg.extend_from_slice(&[0xFF, 0xD9]);

        let mut png: Vec<u8> = PNG_SIG.to_vec();
        png.extend_from_slice(&[0, 0, 0, 13]);
        png.extend_from_slice(b"IHDR");
        png.extend_from_slice(&7u32.to_be_bytes()); // width
        png.extend_from_slice(&5u32.to_be_bytes()); // height
        png.extend_from_slice(&[8, 6, 0, 0, 0]);
        png.extend_from_slice(b"IEND");
        png.extend_from_slice(&[0, 0, 0, 0]);

        // Interleaved with junk, as they are inside a real .one blob.
        let mut blob = vec![0xAA; 16];
        blob.extend_from_slice(&png);
        blob.extend_from_slice(&[0xBB; 8]);
        blob.extend_from_slice(&jpg);

        let found = scan_images(&blob);
        assert_eq!(found.len(), 2, "both images recovered");
        assert_eq!(found[0].mime, "image/png", "document order preserved");
        assert_eq!(found[1].mime, "image/jpeg");
        assert_eq!(png_dimensions(&found[0].bytes), (7, 5));
        assert_eq!(jpeg_dimensions(&found[1].bytes), (2, 3));
        assert_eq!(ext_of(found[1].mime), "jpg");
    }

    /// `FF D8` occurs constantly inside compressed data; only a real marker
    /// sequence may start an image, or the scanner invents images from noise.
    #[test]
    fn does_not_invent_jpegs_from_noise() {
        let noise = vec![0xFF, 0xD8, 0x42, 0x00, 0xFF, 0xD8, 0x11, 0x22, 0x33];
        assert!(scan_images(&noise).is_empty());
    }

    /// A segment made only of deep lines must not be pulled back to the
    /// margin: the base depth comes from the whole outline, not the segment.
    #[test]
    fn segment_after_math_keeps_outline_base() {
        let deep = [text_line(3, "after the equation", false)];
        let refs: Vec<&Line> = deep.iter().collect();
        // Per-segment normalisation (None) would emit flush-left; the outline
        // base (Some(1)) preserves the two extra levels.
        assert_eq!(
            outline_markdown(&refs, &HashMap::new(), Some(1)),
            "    after the equation"
        );
    }

    #[test]
    fn base64_roundtrip_vector() {
        assert_eq!(base64_encode(b"Man"), "TWFu");
        assert_eq!(base64_encode(b"Ma"), "TWE=");
        assert_eq!(base64_encode(b"M"), "TQ==");
    }

    #[test]
    fn folds_math_alphanumerics() {
        assert_eq!(fold_math_char('\u{1D43F}'), 'L'); // italic capital L
        assert_eq!(fold_math_char('\u{1D445}'), 'R'); // italic capital R
        assert_eq!(fold_math_char('\u{1D44F}'), 'b'); // italic small b
        assert_eq!(fold_math_char('\u{210E}'), 'h'); // Planck const (italic h hole)
        assert_eq!(fold_math_char('\u{1D7CF}'), '1'); // bold digit 1
        assert_eq!(fold_math_char('x'), 'x'); // ASCII passes through
    }

    #[test]
    fn office_math_fraction_to_latex() {
        // "= ⟦frac-start⟧ L ⟦bar⟧ R ⟦frac-end⟧" as OneNote stores it.
        let s = "= \u{FDD0}\u{1D43F} \u{FDEE}\u{1D445}\u{FDEF}";
        assert_eq!(office_math_to_latex(s, &[]), r"= \frac{L}{R}");
    }

    #[test]
    fn multibyte_signed_stream_decodes() {
        // Length prefix 0x06 → 3 values (signed form: 6>>1). Values: 0x06 → +3,
        // 0x05 → -2, then a two-byte varint 0x82 0x01 (0x82 = cont|0x02,
        // then 0x01<<7) = 0x82 → 130 → signed +65.
        let out = decode_multibyte_signed(&[0x06, 0x06, 0x05, 0x82, 0x01]).unwrap();
        assert_eq!(out, vec![3, -2, 65]);
        // Truncated stream (says 2 values, has 1) → None, not a panic.
        assert!(decode_multibyte_signed(&[0x04, 0x06]).is_none());
    }

    #[test]
    fn office_math_strips_invisibles_when_no_structure() {
        // Function application (U+2061) and math letters, no fraction.
        let s = "\u{1D453}\u{2061}(\u{1D465})"; // f(x)
        assert_eq!(office_math_to_latex(s, &[]), "f(x)");
    }

    #[test]
    fn prose_in_math_keeps_spaces() {
        // Sentences inside a math zone must not mash together: prose words wrap
        // in \text{} (keeping their spaces); single-letter variables stay math.
        assert_eq!(
            latexify_prose("A path is a sequence of edges e1, e2"),
            r"A\text{ path is a sequence of edges }e1, e2"
        );
        // \commands survive untouched; surrounding words still wrap.
        assert_eq!(
            latexify_prose(r"probability is \frac{1}{2} exactly"),
            r"\text{probability is }\frac{1}{2}\text{ exactly}"
        );
        // Pure math stays pure.
        assert_eq!(latexify_prose("x + y = z"), "x + y = z");
    }

    /// OneNote stores a run as single ANSI bytes whenever its characters fit
    /// the code page. ¬ (0xAC) is the byte that reached a user as U+FFFD —
    /// a discrete-maths NOT symbol — because the old decode was
    /// from_utf8_lossy; the same page kept ¬ intact in runs OneNote happened
    /// to store as UTF-16, which is what made it look random.
    #[test]
    fn ansi_text_runs_decode_without_replacement_chars() {
        let mut b = b"denoted as ".to_vec();
        b.push(0xAC);
        assert_eq!(decode_8bit_text(&b), "denoted as \u{00AC}");
        // The 0x80–0x9F table: smart quotes and the en dash.
        assert_eq!(
            decode_8bit_text(&[0x93, 0x41, 0x94, 0x96]),
            "\u{201C}A\u{201D}\u{2013}"
        );
        // Genuine UTF-8 (all-ASCII included) passes through untouched.
        assert_eq!(
            decode_8bit_text("¬ already utf-8 ∧".as_bytes()),
            "¬ already utf-8 ∧"
        );
    }

    /// A page's object space reduced to the shape that resurrected erased ink,
    /// and run through [live_ink_containers]. Returns the CompactIDs of the
    /// containers selected for import.
    ///
    /// Modelled on the measured file. ONE canonical page node with TWO
    /// declarations: the live one lists only the table, the page-VERSION
    /// snapshot also lists a second ink container. Both containers are still in
    /// the file — erasing ink in OneNote removes the reference, never the
    /// object — so a flat scan of the space finds both.
    ///
    /// The live stroke sits three hops down, inside a table cell, because ink
    /// is not always a direct child of the page node and a walk that only
    /// looked at the root's own children would delete it.
    ///
    /// * `roots` — the live containers the text walk descends, by object index.
    /// * `live_ink_versioned` — whether the surviving container's only stored
    ///   declaration sits inside a version revision (the real case that rules
    ///   out judging ink by [currency] alone).
    fn select_ink(roots: &[usize], live_ink_versioned: bool) -> Vec<u32> {
        // cid = guidIndex << 8 | n; one revision whose guidIndex 0 is `guid`,
        // so each object's CompactID is just its `n`.
        let guid = [7u8; 16];
        let exg = |n: u8| {
            let mut e = [0u8; 20];
            e[..16].copy_from_slice(&guid);
            e[16] = n;
            e
        };
        // (own cid, jcid, referenced cids, versioned)
        let decls: [(u32, u32, &[u32], bool); 7] = [
            (1, JCID_OUTLINE, &[2], false),      // 0: live page node
            (1, JCID_OUTLINE, &[2, 6], true),    // 1: stored page VERSION
            (2, JCID_TABLE, &[3], false),        // 2
            (3, JCID_TABLE_ROW, &[4], false),    // 3
            (4, JCID_TABLE_CELL, &[5], false),   // 4
            (5, JCID_INK_CONTAINER, &[], live_ink_versioned), // 5: still drawn
            (6, JCID_INK_CONTAINER, &[], true),  // 6: erased
        ];
        let mut blob = Vec::new();
        let mut objs = Vec::new();
        for (oid, jcid, kids, versioned) in decls {
            let bytes = propset_blob(kids, &[]);
            objs.push(Obj {
                own_oid: oid,
                jcid,
                stp: blob.len(),
                cb: bytes.len(),
                space: 0,
                rev: 0,
                versioned,
            });
            blob.extend_from_slice(&bytes);
        }
        let rev_tables = vec![HashMap::from([(0u32, guid)])];
        let registry: HashMap<[u8; 20], u32> =
            (1u8..=6).map(|n| (exg(n), n as u32 - 1)).collect();
        // Latest declaration per canonical id, ranked by `currency` exactly as
        // the importer builds it — so the page node resolves to the LIVE one.
        let mut by_canon: HashMap<u32, usize> = HashMap::new();
        for (i, o) in objs.iter().enumerate() {
            let c = (registry[&exg(o.own_oid as u8)]) | CANON_BIT;
            let e = by_canon.entry(c).or_insert(i);
            if currency(o) > currency(&objs[*e]) {
                *e = i;
            }
        }
        let res = Resolver { objs: &objs, rev_tables: &rev_tables, registry: &registry, by_canon };
        let r = Reader { d: &blob };
        let idxs: Vec<usize> = (0..objs.len()).collect();
        // What the importer's unanchored fallback passes: reachability from the
        // containers the scan found, and no filter at all when it found none.
        let live = (!roots.is_empty()).then(|| reachable_canons(&r, &res, roots));
        live_ink_containers(&res, &idxs, live.as_ref())
            .into_iter()
            .map(|i| objs[i].own_oid)
            .collect()
    }

    /// Reported: "on some pages (like symbols in DM) there is some inking there
    /// i guess was there originally in some old version but it isnt there if i
    /// open up onenote."
    ///
    /// It was. Ink was collected by a FLAT SCAN of the object space that asked
    /// only "is this the newest declaration of this container?" and never "does
    /// the live page still reference it at all" — so every stroke ever erased on
    /// a page came back. Measured on the reference notebook: 536 of 64 616
    /// strokes across 9 pages, including all 39 on "Symbols", whose live page
    /// node lists 6 children while a stored version lists 43.
    #[test]
    fn ink_the_live_page_no_longer_references_is_not_imported() {
        // Root = the live page node (index 0), as `root_is` would supply it.
        assert_eq!(
            select_ink(&[0], false),
            vec![5],
            "the erased container (6) must not come back, and the live one must survive"
        );
    }

    /// The other direction, and the one that makes this fix safe: ink whose only
    /// stored declaration sits inside a version revision is still LIVE if the
    /// page reaches it — OneNote simply never rewrote an object that had not
    /// changed. 180 containers on the reference notebook are exactly this, so
    /// judging ink by [currency] instead of reachability would delete strokes
    /// the user can still see.
    #[test]
    fn ink_declared_only_in_a_version_revision_survives_if_the_page_reaches_it() {
        assert_eq!(select_ink(&[0], true), vec![5]);
    }

    /// No live root means no evidence either way. A page whose content root we
    /// fail to identify must keep its ink rather than silently lose all of it —
    /// resurrecting an old stroke is a blemish, deleting a real one is data
    /// loss.
    #[test]
    fn a_page_with_no_identified_root_keeps_all_of_its_ink() {
        assert_eq!(select_ink(&[], false), vec![5, 6]);
    }

    /// The ExtendedGUID a revision manifest would write for object `n` of the
    /// synthetic page space below: one GUID, `n` in the low byte.
    fn root_exg(n: u8) -> [u8; 20] {
        let mut e = [0u8; 20];
        e[..16].copy_from_slice(&[9u8; 16]);
        e[16] = n;
        e
    }

    /// What the four collectors select, by object id.
    #[derive(Debug, PartialEq)]
    struct Selected {
        anchored: bool,
        boxes: Vec<u32>,
        images: Vec<u32>,
        ink: Vec<u32>,
    }

    /// A page object space carrying BOTH shapes the live-root anchor exists for,
    /// run through the anchor and every collector that answers to it.
    ///
    /// Measured from the reference notebook and reduced. One canonical outline
    /// with two declarations: the LIVE one lists nothing — the page was cleared —
    /// while a stored page VERSION of it still lists a paragraph, a picture and
    /// an ink container ("Working out", where the version lists 180 of them).
    /// Beside it, an outline GROUP that only a version revision ever declared:
    /// a note deleted from the page ("Questions", where it was importing as the
    /// page's entire content). Clearing a page or deleting a note in OneNote
    /// unlinks the objects; it never removes them, so a flat scan of the space
    /// finds every one of them still there.
    ///
    /// `roots` is the space's role-1 root list as the revision manifests declare
    /// it — empty for a file we could not read one out of.
    fn select(roots: &[[u8; 20]]) -> Selected {
        // (own cid, jcid, referenced cids, versioned)
        let decls: [(u32, u32, &[u32], bool); 8] = [
            (1, JCID_PAGE_NODE, &[2], false),      // 0: the live page root
            (2, JCID_OUTLINE, &[], false),         // 1: …whose outline is empty now
            (2, JCID_OUTLINE, &[4, 5, 6], true),   // 2: a stored version of it
            (3, JCID_OUTLINE_GROUP, &[7], true),   // 3: a deleted note
            (4, JCID_RICHTEXT, &[], true),         // 4
            (5, JCID_IMAGE, &[], true),            // 5
            (6, JCID_INK_CONTAINER, &[], true),    // 6
            (7, JCID_RICHTEXT, &[], true),         // 7
        ];
        let mut blob = Vec::new();
        let mut objs = Vec::new();
        for (oid, jcid, kids, versioned) in decls {
            // A container's children are an ArrayOfObjectIDs (0x09) under
            // 0x1C20, whose data is the count and whose ids come out of the
            // object's oid stream — the shape the real files use, because the
            // root selection reads that property and reachability reads the
            // stream, and only a declaration with both exercises both.
            let bytes = propset_blob(
                kids,
                &if kids.is_empty() {
                    vec![]
                } else {
                    vec![(
                        PID_ELEMENT_CHILDREN,
                        0x09,
                        (kids.len() as u32).to_le_bytes().to_vec(),
                    )]
                },
            );
            objs.push(Obj {
                own_oid: oid,
                jcid,
                stp: blob.len(),
                cb: bytes.len(),
                space: 0,
                rev: 0,
                versioned,
            });
            blob.extend_from_slice(&bytes);
        }
        let rev_tables = vec![HashMap::from([(0u32, [9u8; 16])])];
        let registry: HashMap<[u8; 20], u32> =
            (1u8..=7).map(|n| (root_exg(n), n as u32 - 1)).collect();
        let mut by_canon: HashMap<u32, usize> = HashMap::new();
        for (i, o) in objs.iter().enumerate() {
            let c = registry[&root_exg(o.own_oid as u8)] | CANON_BIT;
            let e = by_canon.entry(c).or_insert(i);
            if currency(o) > currency(&objs[*e]) {
                *e = i;
            }
        }
        let res =
            Resolver { objs: &objs, rev_tables: &rev_tables, registry: &registry, by_canon };
        let r = Reader { d: &blob };
        let idxs: Vec<usize> = (0..objs.len()).collect();
        let roots = roots.to_vec();
        let anchor = live_anchor(&r, &res, (!roots.is_empty()).then_some(&roots), &registry);
        // The ink fallback the importer uses when there is no anchor.
        let ink_live = match &anchor {
            Some(a) => Some(a.clone()),
            None => {
                let rs = live_box_roots(&r, &res, &idxs, None);
                (!rs.is_empty()).then(|| reachable_canons(&r, &res, &rs))
            }
        };
        Selected {
            anchored: anchor.is_some(),
            boxes: live_box_roots(&r, &res, &idxs, anchor.as_ref())
                .into_iter()
                .map(|i| objs[i].own_oid)
                .collect(),
            images: live_objects(&res, &idxs, JCID_IMAGE, anchor.as_ref())
                .into_iter()
                .map(|(_, i)| objs[i].own_oid)
                .collect(),
            ink: live_ink_containers(&res, &idxs, ink_live.as_ref())
                .into_iter()
                .map(|i| objs[i].own_oid)
                .collect(),
        }
    }

    /// Reported: erased ink and deleted notes coming back on pages that are
    /// empty in OneNote. Text boxes, pictures and ink were each collected by
    /// their own flat scan of the object space, so each resurrected its own kind
    /// of deleted content, and no scan ever asked the file the one question it
    /// answers directly: what does this page's LIVE revision manifest say its
    /// root is?
    ///
    /// Measured on the reference notebook: 329 of 329 pages name exactly one
    /// live role-1 root, and 664 objects in those spaces are unreachable from
    /// it — not one of them referenced by any live-revision declaration anywhere
    /// in the file. Anchoring on the root drops all of them and nothing else.
    #[test]
    fn only_what_the_live_root_reaches_is_imported() {
        assert_eq!(
            select(&[root_exg(1)]),
            Selected { anchored: true, boxes: vec![], images: vec![], ink: vec![] },
            "the cleared page keeps nothing: not the version's paragraph, \
             picture or ink, and not the deleted note beside them"
        );
    }

    /// …and that is genuinely not what the scans said, or the test above proves
    /// nothing. Without the anchor every one of them comes back — the outline at
    /// its VERSION declaration (the live one is empty, so the scan skips it),
    /// the deleted note as a second box, the picture, and the ink.
    #[test]
    fn without_a_live_root_the_old_scan_answers_and_it_answers_wrongly() {
        assert_eq!(
            select(&[]),
            Selected { anchored: false, boxes: vec![2, 3], images: vec![5], ink: vec![6] }
        );
    }

    /// The safety net, and the property that matters most: no evidence is not
    /// evidence of absence. A root we cannot resolve — none declared, two that
    /// disagree, an `n` too wide for the CompactID identity everything else is
    /// keyed on, or one that does not land on an object that can BE a content
    /// root — must leave the page exactly as the unanchored scan had it, not
    /// empty it.
    #[test]
    fn a_root_we_cannot_resolve_leaves_the_page_alone() {
        let unanchored =
            Selected { anchored: false, boxes: vec![2, 3], images: vec![5], ink: vec![6] };
        // Two live roots that disagree.
        assert_eq!(select(&[root_exg(1), root_exg(3)]), unanchored);
        // A root naming an object no declaration in the file matches.
        assert_eq!(select(&[root_exg(99)]), unanchored);
        // A root that resolves to an outline rather than a page or section node.
        assert_eq!(select(&[root_exg(2)]), unanchored);
        // An ExtendedGUID whose `n` needs more than the one byte a CompactID
        // carries: identity cannot be matched, so it must not be guessed.
        let mut wide = root_exg(1);
        wide[17] = 1;
        assert_eq!(select(&[wide]), unanchored);
        // Two declarations of the SAME root still agree, and still anchor.
        assert!(select(&[root_exg(1), root_exg(1)]).anchored);
    }

    /// Distinct page-identity GUID for page `n`.
    fn pg(n: u8) -> [u8; 16] {
        let mut g = [0u8; 16];
        g[0] = n;
        g
    }

    /// One entry of the section's `0x3442` array: the page guid a metadata
    /// object names, and that object's index.
    type MetaEntry = ([u8; 16], usize);
    /// One entry of the `0x1D63` display-order array as `pair_page_metadata`
    /// consumes it: the page's own guid and its positionally-paired meta index,
    /// either of which a real file can fail to carry.
    type PageEntry = (Option<[u8; 16]>, Option<usize>);

    /// "Week 6: More sets and Algorithms" of the reference notebook's Discrete
    /// Mathematics section, reduced to the two arrays that pair a title to a
    /// page. Six pages; `metas` is the section's `0x3442` array in FILE order
    /// and `pages` is the `0x1D63` display order — measured, they are a
    /// permutation apart, so the k-th metadata belongs to the k-th page on only
    /// two of the six.
    ///
    /// Metadata object indices are 100 + their position in the `0x3442` array,
    /// which is exactly what the old positional pairing handed each page.
    fn week6() -> (Vec<MetaEntry>, Vec<PageEntry>) {
        // 0x3442, in file order: the pages it names are 0, 5, 4, 3, 2, 1.
        let named = [0u8, 5, 4, 3, 2, 1];
        let metas: Vec<([u8; 16], usize)> =
            named.iter().enumerate().map(|(i, &p)| (pg(p), 100 + i)).collect();
        // 0x1D63, in display order: page k, paired positionally with meta k.
        let pages: Vec<(Option<[u8; 16]>, Option<usize>)> =
            (0..6).map(|k| (Some(pg(k as u8)), Some(100 + k))).collect();
        (metas, pages)
    }

    /// Reported: "in a few cases the titles are swaped with another one a few
    /// pages after it… the content is on the right page… but the title is
    /// wrong" — "Dominance and Big O, and Uncountable sets" naming each other.
    ///
    /// The page series' two arrays are not parallel: `0x1D63` lists a section's
    /// pages in DISPLAY order while `0x3442` lists their metadata in the order
    /// those objects were created, so reordering a page inside a section leaves
    /// the arrays permuted and the k-th-with-k-th pairing gives pages each
    /// other's titles. Measured on the reference notebook, 16 of 329 pages;
    /// matching on the page's identity GUID instead reproduced the page's own
    /// title outline on all 16 and disagreed with it on none.
    #[test]
    fn a_page_takes_the_title_of_the_metadata_that_names_it_not_the_one_beside_it() {
        let (metas, pages) = week6();
        assert_eq!(
            pair_page_metadata(&metas, &pages),
            vec![Some(100), Some(105), Some(104), Some(103), Some(102), Some(101)],
            "each page must get the metadata naming it, whatever its position"
        );
        // And that is genuinely not the positional answer, or this proves
        // nothing: four of the six pages move.
        let positional: Vec<Option<usize>> = pages.iter().map(|p| p.1).collect();
        assert_eq!(
            pair_page_metadata(&metas, &pages)
                .iter()
                .zip(&positional)
                .filter(|(a, b)| a != b)
                .count(),
            4
        );
    }

    /// Every page must still end up with a title. A page space we could not read
    /// an identity GUID out of keeps the positional pairing — approximate beats
    /// "Untitled", which is what dropping the page's metadata would produce.
    #[test]
    fn a_page_with_no_identity_falls_back_to_its_position() {
        let (metas, mut pages) = week6();
        pages[1].0 = None;
        assert_eq!(pair_page_metadata(&metas, &pages)[1], Some(101));
        // An identity that names no metadata we hold falls back the same way.
        pages[1].0 = Some(pg(200));
        assert_eq!(pair_page_metadata(&metas, &pages)[1], Some(101));
    }

    /// Two metadata objects claiming the same page name no page between them.
    /// Guessing would be how one page's title lands on another again, so an
    /// ambiguous GUID falls back to position for every page that carries it.
    #[test]
    fn a_guid_two_metadata_objects_claim_decides_nothing() {
        let (mut metas, pages) = week6();
        metas.push((pg(1), 106)); // a second claim on page 1
        let paired = pair_page_metadata(&metas, &pages);
        assert_eq!(paired[1], Some(101), "the contested page keeps its position");
        assert_eq!(paired[5], Some(101), "…and so does the page that held it");
        // The pages nobody contests are still matched by identity.
        assert_eq!(paired[2], Some(104));
        assert_eq!(paired[4], Some(102));
    }

    // ── A synthetic ONESTORE section, assembled byte for byte ───────────────
    //
    // Every test above this line hands a pure function a hand-built `Obj`
    // vector. That pins the DECISION and leaves the read that FEEDS it
    // unguarded — which is the same mistake, one layer up, as the import bugs
    // themselves. It is measurable: reverting [currency] to rank declarations
    // by file offset, or making [walk] never mark one versioned, puts back the
    // two largest regressions this importer has had (16 % of the reference
    // notebook, 73 pages, 12 sections) with the entire Rust suite still green.
    //
    // The files that would catch it are the owner's own study notes and must
    // never be committed, so the bytes are synthesised instead: the 1 KB
    // header, file-node-list fragments, revision manifests with and without a
    // revision context, root-object references, global-id tables and object
    // declarations — mirroring the constants the parser itself reads, so a
    // change to one moves both. Nothing below contains a byte of anyone's
    // notes, and it all goes in through [import_one]'s front door, so the
    // container walk is under test alongside the decisions it feeds.

    /// The `.one` `guidFileType` — the 16 bytes [Reader::is_one_section] looks
    /// for, and the reason a synthetic file is recognised at all.
    const ONE_GUID: [u8; 16] = [
        0xe4, 0x52, 0x5c, 0x7b, 0x8c, 0xd8, 0xa7, 0x4d, 0xae, 0xb1, 0x53, 0x78, 0xd0, 0x29,
        0x96, 0xd3,
    ];
    /// Where `fcrFileNodeListRoot` (a FileChunkReference64x32) sits in the
    /// header — the offset [import_one] reads the whole graph from.
    const FCR_ROOT_OFFSET: usize = 172;
    /// ObjectDeclaration2RefCountFND. [walk] dispatches on `base_type`, not on
    /// this id, but writing the real one keeps the file honest.
    const FNID_OBJ_DECL2: u16 = 0x0A4;
    /// StrokeProperties (the object a stroke's 0x3409 points at).
    const JCID_STROKE_PROPS: u32 = 0x0012_0048;

    /// One FileNode: `{ FileNodeID: 10 bits, Size: 13, StpFormat: 2,
    /// CbFormat: 2, BaseType: 4 }` packed little-endian, then the body.
    ///
    /// `Size` counts the 4-byte header, which is what makes the walk's
    /// `o += size` land on the next node rather than inside this one. Both
    /// format fields stay 0 — an 8-byte offset and a 4-byte length, so
    /// `ref_size(0, 0) == 12` and no reference this builder writes is ever
    /// narrowed to something that cannot hold the offset.
    fn fnode(id: u16, base_type: u8, body: &[u8]) -> Vec<u8> {
        let size = 4 + body.len();
        assert!(size < (1 << 13), "a FileNode's Size field is only 13 bits");
        let h = id as u32 | ((size as u32) << 10) | ((base_type as u32) << 27);
        let mut v = h.to_le_bytes().to_vec();
        v.extend_from_slice(body);
        v
    }

    /// A FileChunkReference64x32: a 64-bit offset then a 32-bit length.
    fn fcr_bytes(stp: u64, cb: u32) -> Vec<u8> {
        let mut v = stp.to_le_bytes().to_vec();
        v.extend_from_slice(&cb.to_le_bytes());
        v
    }

    /// An ExtendedGUID as ONESTORE stores it: the GUID, then `n` as a u32.
    fn exguid(guid: [u8; 16], n: u8) -> [u8; 20] {
        let mut e = [0u8; 20];
        e[..16].copy_from_slice(&guid);
        e[16] = n;
        e
    }

    /// The CompactID of object `n`: `guidIndex << 8 | n`. Every synthetic
    /// revision maps guidIndex 1 to its own space's GUID, so `n` alone names an
    /// object within a space and the same `n` in two spaces is two objects.
    fn cid(n: u8) -> u32 {
        (1 << 8) | n as u32
    }

    /// One object declaration inside a synthetic revision.
    struct Decl {
        /// The object's CompactID `n` — see [cid].
        n: u8,
        jcid: u32,
        /// Its ObjectSpaceObjectPropSet bytes, from [propset_blob].
        blob: Vec<u8>,
    }

    fn decl(n: u8, jcid: u32, blob: Vec<u8>) -> Decl {
        Decl { n, jcid, blob }
    }

    /// One revision manifest of a synthetic object space.
    struct Rev {
        /// A stored page VERSION — a RevisionManifestStart7FND carrying a
        /// non-nil `gctxid` — rather than the space as it stands (a 6FND, no
        /// context at all). This one bit is what [currency] reads, and getting
        /// it out of the bytes is what these tests add over the ones above.
        versioned: bool,
        /// The role-1 content roots this manifest declares, by CompactID `n`.
        /// [walk] records them only from a context-free manifest, so a
        /// versioned revision may carry them and must be ignored.
        roots: Vec<u8>,
        /// Extra guidIndex → GUID entries for this revision's global-id table,
        /// on top of guidIndex 1 → the space's own GUID. A section directory
        /// needs one per page space, or its 0x1D63 ObjectSpaceIDs resolve to
        /// nothing and the section lists no pages at all.
        gids: Vec<(u32, [u8; 16])>,
        decls: Vec<Decl>,
    }

    impl Rev {
        /// The space as it stands: no revision context, and it names the roots.
        fn live(roots: &[u8], decls: Vec<Decl>) -> Rev {
            Rev { versioned: false, roots: roots.to_vec(), gids: Vec::new(), decls }
        }
        /// A stored page version of the same space.
        fn version(decls: Vec<Decl>) -> Rev {
            Rev { versioned: true, roots: Vec::new(), gids: Vec::new(), decls }
        }
    }

    /// A synthetic `.one` section under construction.
    ///
    /// Blobs and fragments are appended in call order, so **the order things
    /// are built IS their order in the file**. That is load-bearing, not
    /// incidental: a page version declared after the live revision lands at a
    /// higher file offset, which is exactly the arrangement that made "further
    /// down the file" look like "newer" and cost the notebook 60 143
    /// characters.
    struct OneFile {
        d: Vec<u8>,
    }

    impl OneFile {
        fn new() -> Self {
            // 1 KB header; everything in it but the type GUID and the root
            // reference is zero, which is all the parser reads.
            let mut d = vec![0u8; 1024];
            d[..16].copy_from_slice(&ONE_GUID);
            OneFile { d }
        }

        /// Place one property set and return the chunk reference to it.
        fn blob(&mut self, b: &[u8]) -> (u64, u32) {
            let stp = self.d.len() as u64;
            self.d.extend_from_slice(b);
            (stp, b.len() as u32)
        }

        /// Place a FileNodeListFragment around `nodes`: the magic, the list
        /// header, the nodes, then the 20 trailing bytes the walk reserves for
        /// the next-fragment reference and the footer. It reads that reference
        /// at `frag_end - 20`, so those bytes are not optional padding.
        fn fragment(&mut self, nodes: &[u8]) -> (u64, u32) {
            let stp = self.d.len() as u64;
            self.d.extend_from_slice(&MAGIC_FRAG_HEADER.to_le_bytes());
            self.d.extend_from_slice(&1u32.to_le_bytes()); // FileNodeListID
            self.d.extend_from_slice(&0u32.to_le_bytes()); // nFragmentSequence
            self.d.extend_from_slice(nodes);
            self.d.extend_from_slice(&fcr_bytes(u64::MAX, 0)); // nextFragment = nil
            self.d.extend_from_slice(&0u64.to_le_bytes()); // footer
            (stp, (self.d.len() as u64 - stp) as u32)
        }

        /// One object space: each revision's global-id table, its manifest, the
        /// roots that manifest declares, and its object declarations — in that
        /// order, because that is the order the walk depends on to know which
        /// revision a declaration belongs to.
        fn space(&mut self, guid: [u8; 16], revs: &[Rev]) -> (u64, u32) {
            let mut nodes = Vec::new();
            for rev in revs {
                // A revision's table begins EMPTY (MS-ONESTORE §2.5.10), so
                // every revision restates guidIndex 1. Two revisions both
                // mapping it to this space's GUID is precisely what makes their
                // declarations of object `n` two declarations of the SAME
                // object rather than of two unrelated ones.
                nodes.extend(fnode(FNID_GID_TABLE_START, 0, &[]));
                let mut gids = vec![(1u32, guid)];
                gids.extend(rev.gids.iter().copied());
                for (idx, g) in gids {
                    let mut body = idx.to_le_bytes().to_vec();
                    body.extend_from_slice(&g);
                    nodes.extend(fnode(FNID_GID_TABLE_ENTRY, 0, &body));
                }
                if rev.versioned {
                    // rid(20) + ridDependent(20) + RevisionRole(4) +
                    // odcsDefault(2) = REV7_GCTXID_OFFSET, then the gctxid
                    // whose non-nil-ness is the whole signal.
                    let mut body = vec![0u8; REV7_GCTXID_OFFSET];
                    body.extend_from_slice(&exguid([0x5A; 16], 1));
                    nodes.extend(fnode(FNID_REV_MANIFEST_START7, 0, &body));
                } else {
                    let body = [0u8; REV7_GCTXID_OFFSET];
                    nodes.extend(fnode(FNID_REV_MANIFEST_START6, 0, &body));
                }
                for &n in &rev.roots {
                    // RootObjectReference3FND: ExtendedGUID(20) + RootRole(u32).
                    let mut body = exguid(guid, n).to_vec();
                    body.extend_from_slice(&ROOT_ROLE_CONTENT.to_le_bytes());
                    nodes.extend(fnode(FNID_ROOT_OBJECT_REF3, 0, &body));
                }
                for d in &rev.decls {
                    let (stp, cb) = self.blob(&d.blob);
                    // ObjectDeclaration2RefCountFND: the BlobRef to the property
                    // set, then ObjectDeclaration2Body { oid, jcid, flags } and
                    // a reference count. The walk reads oid and jcid at body+0
                    // and body+4, immediately after the 12-byte reference.
                    let mut body = fcr_bytes(stp, cb);
                    body.extend_from_slice(&cid(d.n).to_le_bytes());
                    body.extend_from_slice(&d.jcid.to_le_bytes());
                    body.extend_from_slice(&[0, 1]); // flags, cRef
                    nodes.extend(fnode(FNID_OBJ_DECL2, 1, &body));
                }
                nodes.extend(fnode(FNID_REV_MANIFEST_END, 0, &[]));
            }
            self.fragment(&nodes)
        }

        /// The root file-node list: one ObjectSpaceManifestListReference per
        /// space, in the order the spaces are to be indexed. The 20 bytes right
        /// after each chunk reference are the space's ExtendedGUID — the
        /// durable identity a page series' 0x1D63 reference resolves to, and
        /// without which a section lists no pages.
        fn root(&mut self, spaces: &[((u64, u32), [u8; 16])]) -> (u64, u32) {
            let mut nodes = Vec::new();
            for &((stp, cb), guid) in spaces {
                let mut body = fcr_bytes(stp, cb);
                // `n` = 0 on the space itself; objects start at 1, so a space's
                // identity can never collide with one of its own objects'.
                body.extend_from_slice(&exguid(guid, 0));
                nodes.extend(fnode(FNID_OBJECT_SPACE_LIST_REF, 2, &body));
            }
            self.fragment(&nodes)
        }

        /// Stamp the root reference into the header and hand back the bytes.
        fn finish(mut self, root: (u64, u32)) -> Vec<u8> {
            self.d[FCR_ROOT_OFFSET..FCR_ROOT_OFFSET + 12]
                .copy_from_slice(&fcr_bytes(root.0, root.1));
            self.d
        }
    }

    /// A container declaration: the oid stream its children come out of AND the
    /// 0x1C20 ElementChildNodes property that names them.
    ///
    /// Both, because the importer reads both — root selection counts the
    /// property while reachability walks the stream — and a declaration
    /// carrying only one of them would exercise only half of the code the
    /// tests below are here to hold still.
    fn kids_blob(kids: &[u8]) -> Vec<u8> {
        let oids: Vec<u32> = kids.iter().map(|&n| cid(n)).collect();
        let props = if kids.is_empty() {
            Vec::new()
        } else {
            vec![(
                PID_ELEMENT_CHILDREN,
                0x09,
                (kids.len() as u32).to_le_bytes().to_vec(),
            )]
        };
        propset_blob(&oids, &props)
    }

    /// A string property's data: the 4-byte length, then the bytes.
    fn str_data(b: &[u8]) -> Vec<u8> {
        let mut v = (b.len() as u32).to_le_bytes().to_vec();
        v.extend_from_slice(b);
        v
    }

    /// The same, for a UTF-16 property (titles are stored this way).
    fn utf16_data(s: &str) -> Vec<u8> {
        let bytes: Vec<u8> = s.encode_utf16().flat_map(u16::to_le_bytes).collect();
        str_data(&bytes)
    }

    /// A text run (0x0E) carrying 8-bit body text — one visible line of a page.
    fn run_blob(text: &str) -> Vec<u8> {
        propset_blob(&[], &[(PID_TEXT_UTF8, 0x07, str_data(text.as_bytes()))])
    }

    /// A page's own PageMetadata object: the identity GUID that ties it to the
    /// section directory's copy of its metadata.
    fn page_id_blob(page_guid: &[u8; 16]) -> Vec<u8> {
        propset_blob(&[], &[(PID_PAGE_GUID, 0x07, str_data(page_guid))])
    }

    /// MS-ISF multi-byte signed encoding: a varint holding twice the value
    /// count, then one varint per value with the sign in the low bit.
    /// [decode_multibyte_signed] is the reader this has to satisfy.
    fn ink_path(values: &[i64]) -> Vec<u8> {
        fn varint(out: &mut Vec<u8>, mut v: u64) {
            loop {
                let b = (v & 0x7F) as u8;
                v >>= 7;
                if v == 0 {
                    out.push(b);
                    return;
                }
                out.push(b | 0x80);
            }
        }
        let mut out = Vec::new();
        varint(&mut out, (values.len() as u64) << 1);
        for &v in values {
            varint(&mut out, if v < 0 { (((-v) as u64) << 1) | 1 } else { (v as u64) << 1 });
        }
        out
    }

    /// The four objects one ink stroke needs — container ─0x3415→ data node
    /// ─0x3416→ stroke ─0x3409→ properties — at CompactIDs `n ..= n + 3`.
    ///
    /// `color` is a COLORREF (0x00BBGGRR), and it is how a test says WHICH
    /// stroke survived rather than merely how many did. The X/Y dimension table
    /// is declared so the decoder uses it instead of inferring a channel count,
    /// making the three decoded points exactly the three written here.
    fn ink_chain(n: u8, color: u32) -> Vec<Decl> {
        let mut dims = Vec::new();
        for g in [DIM_X, DIM_Y] {
            dims.extend_from_slice(&g); // 32-byte entry: guid, lo, hi, padding
            dims.extend_from_slice(&0i32.to_le_bytes());
            dims.extend_from_slice(&32767i32.to_le_bytes());
            dims.extend_from_slice(&[0u8; 8]);
        }
        vec![
            decl(
                n,
                JCID_INK_CONTAINER,
                propset_blob(&[cid(n + 1)], &[(PID_INK_DATA_REF, 0x08, Vec::new())]),
            ),
            decl(
                n + 1,
                JCID_INK_DATA,
                propset_blob(
                    &[cid(n + 2)],
                    &[(PID_INK_STROKES, 0x09, 1u32.to_le_bytes().to_vec())],
                ),
            ),
            decl(
                n + 2,
                JCID_INK_STROKE,
                propset_blob(
                    &[cid(n + 3)],
                    &[
                        // Two channels of three points: an absolute first value
                        // then two deltas, X block followed by Y block.
                        (
                            PID_INK_PATH,
                            0x07,
                            str_data(&ink_path(&[100, 20, 20, 200, 20, 20])),
                        ),
                        (PID_INK_STROKE_PROPS, 0x08, Vec::new()),
                    ],
                ),
            ),
            decl(
                n + 3,
                JCID_STROKE_PROPS,
                propset_blob(
                    &[],
                    &[
                        (PID_INK_DIMENSIONS, 0x07, str_data(&dims)),
                        (PID_INK_COLOR, 0x05, color.to_le_bytes().to_vec()),
                    ],
                ),
            ),
        ]
    }

    /// The section directory space: a SectionNode with one PageSeries listing
    /// `pages` in DISPLAY order (0x1D63) and their PageMetadata objects in
    /// `meta_order` (0x3442).
    ///
    /// The two orders are given separately because in a real file they are two
    /// different orders — display versus creation — and pairing them by index
    /// is what handed 16 of the reference notebook's pages each other's titles.
    ///
    /// `pages` is (the page's object-space GUID, its identity GUID, its title).
    fn dir_space(
        f: &mut OneFile,
        guid: [u8; 16],
        pages: &[([u8; 16], [u8; 16], &str)],
        meta_order: &[usize],
    ) -> (u64, u32) {
        // CompactIDs here: 1 = the section, 2 = its page series, 3.. = one
        // PageMetadata per page, declared in creation order.
        let mut decls = vec![decl(1, JCID_SECTION_NODE, kids_blob(&[2]))];
        // ObjectSpaceIDs, in display order. guidIndex 2.. are the page spaces'
        // GUIDs (added to this revision's table below) and `n` matches the
        // identity the root list wrote for each space.
        let osids: Vec<u32> = (0..pages.len()).map(|k| (k as u32 + 2) << 8).collect();
        let metas: Vec<u32> = meta_order.iter().map(|&k| cid(3 + k as u8)).collect();
        decls.push(decl(
            2,
            JCID_PAGE_SERIES,
            propset_blob_osids(
                &metas,
                &osids,
                &[
                    (PID_PAGE_SPACES, 0x0B, (osids.len() as u32).to_le_bytes().to_vec()),
                    (PID_PAGE_METADATA, 0x09, (metas.len() as u32).to_le_bytes().to_vec()),
                ],
            ),
        ));
        for (k, (_, page_guid, title)) in pages.iter().enumerate() {
            decls.push(decl(
                3 + k as u8,
                JCID_PAGE_METADATA,
                propset_blob(
                    &[],
                    &[
                        (PID_PAGE_GUID, 0x07, str_data(page_guid)),
                        (PID_TITLE, 0x07, utf16_data(title)),
                        // OneNote's PageLevel is 1-based; 1 = a top-level page.
                        (PID_PAGE_LEVEL, 0x05, 1u32.to_le_bytes().to_vec()),
                    ],
                ),
            ));
        }
        let gids: Vec<(u32, [u8; 16])> =
            pages.iter().enumerate().map(|(k, p)| (k as u32 + 2, p.0)).collect();
        f.space(guid, &[Rev { versioned: false, roots: vec![1], gids, decls }])
    }

    /// Every non-blank line of a parsed page, trimmed, across all of its boxes.
    fn page_lines(page: &ImportedPage) -> Vec<String> {
        page.boxes
            .iter()
            .flat_map(|b| b.markdown.lines())
            .map(str::trim)
            .filter(|l| !l.is_empty())
            .map(str::to_string)
            .collect()
    }

    /// Reported as pages losing their last lines, and measured at 60 143
    /// characters across 73 pages and 12 sections: the parser chose between
    /// competing declarations of an object by raw file offset, and ONESTORE is
    /// a revision store over a free-chunk allocator, so "further down the file"
    /// is not "newer". A stored page version sitting below the live content
    /// silently replaced it — on "Logic: Tautologies…" a 21-paragraph outline
    /// became an 18-paragraph one.
    ///
    /// Here the live revision lists five paragraphs and a version snapshot,
    /// written afterwards and therefore at a HIGHER file offset, lists two. The
    /// answer is five. Both the fix's halves are under this one assertion: the
    /// bit [walk] sets from the 7FND's `gctxid`, and [currency] preferring it
    /// over the offset.
    #[test]
    fn a_version_snapshot_further_down_the_file_does_not_replace_live_content() {
        let mut f = OneFile::new();
        let (space_guid, page_guid, dir_guid) = ([0xA1; 16], [0x11; 16], [0xD1; 16]);
        // Live: the page node, its outline, and the outline element listing
        // FIVE paragraphs. Built first, so all of it sits at a lower offset
        // than the snapshot below.
        let mut live = vec![
            decl(1, JCID_PAGE_NODE, kids_blob(&[2])),
            decl(2, JCID_OUTLINE, kids_blob(&[3])),
            decl(3, JCID_OUTLINE_ELEMENT, kids_blob(&[4, 5, 6, 7, 8])),
        ];
        for k in 0..5u8 {
            live.push(decl(4 + k, JCID_RICHTEXT_RUN, run_blob(&format!("Line {}", k + 1))));
        }
        live.push(decl(9, JCID_PAGE_METADATA, page_id_blob(&page_guid)));
        // A stored version of the SAME outline element listing two paragraphs.
        // Written after the live revision, so it wins on file offset — and has
        // to lose anyway.
        let version = vec![decl(3, JCID_OUTLINE_ELEMENT, kids_blob(&[4, 5]))];
        let page = f.space(space_guid, &[Rev::live(&[1], live), Rev::version(version)]);
        let dir = dir_space(&mut f, dir_guid, &[(space_guid, page_guid, "Currency")], &[0]);
        let root = f.root(&[(dir, dir_guid), (page, space_guid)]);
        let section = import_one(&f.finish(root));

        assert!(section.ok, "the synthetic section must parse: {:?}", section.error);
        assert_eq!(section.pages.len(), 1, "one page space, one page");
        assert_eq!(
            page_lines(&section.pages[0]),
            ["Line 1", "Line 2", "Line 3", "Line 4", "Line 5"],
            "the live revision's five paragraphs must survive a two-paragraph \
             snapshot stored further down the file"
        );
    }

    /// Reported: "in a few cases the titles are swaped with another one a few
    /// pages after it… the content is on the right page… but the title is
    /// wrong". A page series lists its pages in DISPLAY order (0x1D63) and
    /// their metadata in CREATION order (0x3442), so any section with a
    /// reordered page leaves the two arrays a permutation apart — and pairing
    /// them by index gave 16 of the reference notebook's 329 pages each other's
    /// titles.
    ///
    /// Three pages here, with the metadata array rotated against the display
    /// order so that positional pairing gets ALL THREE wrong. The link that
    /// works is the page's own identity: each page space carries a PageMetadata
    /// of its own whose 0x1C30 the directory's copy repeats. That read is what
    /// the pure-function pairing tests above cannot see.
    #[test]
    fn each_page_wears_the_title_of_the_metadata_that_names_it() {
        let mut f = OneFile::new();
        let titles = ["Alpha", "Beta", "Gamma"];
        let space_guids: Vec<[u8; 16]> = (0..3).map(|k| [0xB0 + k as u8; 16]).collect();
        let page_guids: Vec<[u8; 16]> = (0..3).map(|k| [0x20 + k as u8; 16]).collect();
        let mut frags = Vec::new();
        for k in 0..3 {
            frags.push(f.space(
                space_guids[k],
                &[Rev::live(
                    &[1],
                    vec![
                        decl(1, JCID_PAGE_NODE, kids_blob(&[2])),
                        decl(2, JCID_OUTLINE, kids_blob(&[3])),
                        decl(
                            3,
                            JCID_RICHTEXT_RUN,
                            run_blob(&format!("Body of {}", titles[k])),
                        ),
                        // The page's own copy of its metadata — its identity.
                        decl(4, JCID_PAGE_METADATA, page_id_blob(&page_guids[k])),
                    ],
                )],
            ));
        }
        let pages: Vec<([u8; 16], [u8; 16], &str)> = (0..3)
            .map(|k| (space_guids[k], page_guids[k], titles[k]))
            .collect();
        // 0x3442 rotated against 0x1D63: metadata 2, 0, 1 for pages 0, 1, 2.
        let dir_guid = [0xDB; 16];
        let dir = dir_space(&mut f, dir_guid, &pages, &[2, 0, 1]);
        let mut spaces = vec![(dir, dir_guid)];
        spaces.extend(frags.iter().zip(&space_guids).map(|(&fr, &g)| (fr, g)));
        let root = f.root(&spaces);
        let section = import_one(&f.finish(root));

        assert!(section.ok, "the synthetic section must parse: {:?}", section.error);
        assert_eq!(
            section.pages.iter().map(|p| p.title.as_str()).collect::<Vec<_>>(),
            titles,
            "each page must take the title of the metadata that NAMES it"
        );
        // And the titles must sit on the right bodies, which is the form the
        // complaint actually took: right content, wrong name above it.
        for p in &section.pages {
            assert_eq!(
                page_lines(p),
                [format!("Body of {}", p.title)],
                "page \"{}\" is wearing another page's title",
                p.title
            );
        }
        // The positional pairing really is a different answer, or this proves
        // nothing: all three pages move.
        assert_eq!(
            section
                .pages
                .iter()
                .zip(["Gamma", "Alpha", "Beta"])
                .filter(|(p, positional)| p.title == *positional)
                .count(),
            0,
            "the permutation must be one that positional pairing gets wrong"
        );
    }

    /// Reported: "on some pages… there is some inking there i guess was there
    /// originally in some old version but it isnt there if i open up onenote."
    /// Erasing ink in OneNote removes the REFERENCE and never the object, so a
    /// flat scan of the object space finds every stroke ever erased — 536 of
    /// the reference notebook's 64 616.
    ///
    /// One container the live page node still reaches and one only its stored
    /// version reaches, both fully decodable and told apart by pen colour, so
    /// this says which stroke survived and not merely how many did.
    #[test]
    fn ink_only_a_version_snapshot_reaches_is_not_imported() {
        let mut f = OneFile::new();
        let (space_guid, page_guid, dir_guid) = ([0xC1; 16], [0x31; 16], [0xDC; 16]);
        let mut live = vec![
            // The live page node reaches its outline and ONE ink container.
            decl(1, JCID_PAGE_NODE, kids_blob(&[2, 4])),
            decl(2, JCID_OUTLINE, kids_blob(&[3])),
            decl(3, JCID_RICHTEXT_RUN, run_blob("Kept")),
        ];
        live.extend(ink_chain(4, 0x0000_00FF)); // red: still drawn
        live.push(decl(9, JCID_PAGE_METADATA, page_id_blob(&page_guid)));
        // The stored version of the page node lists a second container as well
        // — ink the user has since erased. The object is still in the file.
        let mut version = vec![decl(1, JCID_PAGE_NODE, kids_blob(&[2, 4, 10]))];
        version.extend(ink_chain(10, 0x00FF_0000)); // blue: erased
        let page = f.space(space_guid, &[Rev::live(&[1], live), Rev::version(version)]);
        let dir = dir_space(&mut f, dir_guid, &[(space_guid, page_guid, "Symbols")], &[0]);
        let root = f.root(&[(dir, dir_guid), (page, space_guid)]);
        let section = import_one(&f.finish(root));

        assert!(section.ok, "the synthetic section must parse: {:?}", section.error);
        let p = &section.pages[0];
        assert_eq!(page_lines(p), ["Kept"], "the page's text must import");
        assert_eq!(p.dropped_strokes, 0, "both synthetic strokes must decode");
        assert_eq!(
            p.ink.iter().map(|s| s.color.as_str()).collect::<Vec<_>>(),
            ["#FF0000"],
            "the erased container must not come back, and the live one must stay"
        );
    }

    /// The shape that survived the first ink fix, and the reason a page's root
    /// has to be read rather than guessed at: on "Working out" the outline's
    /// LIVE declaration lists 0 children while a stored version of it lists
    /// 180 ink containers. Empty declarations were skipped before the
    /// per-object pick, so the snapshot became the page's root and a
    /// reachability filter rooted there called 180 erased strokes live.
    ///
    /// The file answers this directly: the revision manifest with no context
    /// names the live role-1 root, and reading it makes the cleared page come
    /// back cleared — text, ink and all — while still importing as a page,
    /// because the section lists it.
    #[test]
    fn a_page_whose_live_root_shows_it_cleared_comes_back_cleared() {
        let mut f = OneFile::new();
        let (space_guid, page_guid, dir_guid) = ([0xC2; 16], [0x41; 16], [0xDD; 16]);
        let live = vec![
            decl(1, JCID_PAGE_NODE, kids_blob(&[2])),
            // The live outline lists nothing at all: the page was cleared.
            decl(2, JCID_OUTLINE, kids_blob(&[])),
            decl(3, JCID_PAGE_METADATA, page_id_blob(&page_guid)),
        ];
        // A stored version of that same outline still lists the page's old
        // content, and sits further down the file.
        let mut version = vec![
            decl(2, JCID_OUTLINE, kids_blob(&[4, 5, 6])),
            decl(4, JCID_RICHTEXT_RUN, run_blob("Working out, line one")),
            decl(5, JCID_RICHTEXT_RUN, run_blob("Working out, line two")),
        ];
        version.extend(ink_chain(6, 0x00FF_0000));
        let page = f.space(space_guid, &[Rev::live(&[1], live), Rev::version(version)]);
        let dir = dir_space(&mut f, dir_guid, &[(space_guid, page_guid, "Working out")], &[0]);
        let root = f.root(&[(dir, dir_guid), (page, space_guid)]);
        let section = import_one(&f.finish(root));

        assert!(section.ok, "the synthetic section must parse: {:?}", section.error);
        assert_eq!(section.pages.len(), 1, "a cleared page is still a page");
        let p = &section.pages[0];
        assert_eq!(p.title, "Working out");
        assert_eq!(page_lines(p), Vec::<String>::new(), "the snapshot's text must stay gone");
        assert!(p.ink.is_empty(), "the snapshot's ink must stay gone");
    }

    /// An element's page offset: 0x1C14/0x1C15 in half-inch units, which the
    /// importer multiplies by [UNIT_PX]. Written as a 4-byte property whose
    /// bits are an f32, which is how a real file stores them.
    fn offset_props(x: f32, y: f32) -> Vec<(u32, u8, Vec<u8>)> {
        vec![
            (PID_IMG_POSX, 0x05, x.to_bits().to_le_bytes().to_vec()),
            (PID_IMG_POSY, 0x05, y.to_bits().to_le_bytes().to_vec()),
        ]
    }

    /// A positioned OutlineElement: the children an element lists, plus the
    /// offset OneNote recorded for it.
    fn placed_kids_blob(kids: &[u8], x: f32, y: f32) -> Vec<u8> {
        let oids: Vec<u32> = kids.iter().map(|&n| cid(n)).collect();
        let mut props = offset_props(x, y);
        props.push((
            PID_ELEMENT_CHILDREN,
            0x09,
            (kids.len() as u32).to_le_bytes().to_vec(),
        ));
        propset_blob(&oids, &props)
    }

    /// One OneNote paragraph, at CompactIDs `n` (the RichText container) and
    /// `n + 1` (its one text run) — the PAIR every real paragraph is.
    ///
    /// `text: None` is the blank line a writer typed: a run carrying no text
    /// property at all. The container is textless either way, because it is
    /// textless by construction in every real file.
    fn para(n: u8, text: Option<&str>) -> Vec<Decl> {
        vec![
            decl(n, JCID_RICHTEXT, kids_blob(&[n + 1])),
            decl(
                n + 1,
                JCID_RICHTEXT_RUN,
                match text {
                    Some(t) => run_blob(t),
                    None => propset_blob(&[], &[]),
                },
            ),
        ]
    }

    /// The markdown of a page's boxes with blank lines KEPT — [page_lines]
    /// filters them out, and a blank line is the whole subject here.
    fn box_markdown(page: &ImportedPage) -> Vec<&str> {
        page.boxes.iter().map(|b| b.markdown.as_str()).collect()
    }

    /// Backlog #56, "collisions across flow groups", half one: the same
    /// paragraphs came out TWICE, and the second copy landed on top of the
    /// first.
    ///
    /// [live_box_roots] collects every outline and outline group the live page
    /// reaches, which is right for a page that hangs its content off a group —
    /// and wrong for a group nested inside another container's element, whose
    /// paragraphs the outer container already walks. The nested copy carries no
    /// offset of its own (the position lives on the enclosing OutlineElement),
    /// so it fell to the `stack_y` fallback at x = 0 and drew straight through
    /// the correctly-placed original. `seen_box` cannot catch it: the two
    /// targets are different objects — a RichText here, an OutlineElement there.
    ///
    /// Measured on the reference notebook: 55 such boxes across 21 pages, every
    /// one of them line-for-line already present in another box on its own
    /// page ("Set Theory", "Subsets and Empty Sets", "Intro to Graph Theory"…).
    #[test]
    fn a_group_nested_in_an_element_does_not_emit_its_paragraphs_a_second_time() {
        let mut f = OneFile::new();
        let (space_guid, page_guid, dir_guid) = ([0xC3; 16], [0x51; 16], [0xDE; 16]);
        let mut live = vec![
            decl(1, JCID_PAGE_NODE, kids_blob(&[2])),
            decl(2, JCID_OUTLINE, kids_blob(&[3])),
            // The element OneNote placed, at 1.0 x 2.0 units = 60 x 120 px.
            decl(3, JCID_OUTLINE_ELEMENT, placed_kids_blob(&[4], 1.0, 2.0)),
        ];
        // Its paragraph, which hangs an indented sub-group off itself — the
        // shape an indented sub-list takes, and the one six of the reference
        // notebook's duplicates had.
        live.push(decl(4, JCID_RICHTEXT, kids_blob(&[5, 20])));
        live.push(decl(5, JCID_RICHTEXT_RUN, run_blob("Set: a collection of objects")));
        live.push(decl(20, JCID_OUTLINE_GROUP, kids_blob(&[21, 23])));
        live.extend(para(21, Some("Element: an object inside the set")));
        live.extend(para(23, Some("Cardinality: how many distinct elements")));
        live.push(decl(9, JCID_PAGE_METADATA, page_id_blob(&page_guid)));
        let page = f.space(space_guid, &[Rev::live(&[1], live)]);
        let dir = dir_space(&mut f, dir_guid, &[(space_guid, page_guid, "Set Theory")], &[0]);
        let root = f.root(&[(dir, dir_guid), (page, space_guid)]);
        let section = import_one(&f.finish(root));

        assert!(section.ok, "the synthetic section must parse: {:?}", section.error);
        let p = &section.pages[0];
        // Nothing is lost: all three paragraphs are on the page…
        assert_eq!(
            page_lines(p),
            [
                "Set: a collection of objects",
                "Element: an object inside the set",
                "Cardinality: how many distinct elements",
            ],
            "the nested group's paragraphs must still import, through the \
             outer container"
        );
        // …once each, in ONE box, at the offset OneNote recorded for the
        // element that holds them.
        assert_eq!(p.boxes.len(), 1, "one placed element is one box: {:?}", box_markdown(p));
        assert_eq!((p.boxes[0].x, p.boxes[0].y), (60.0, 120.0));
        // The failure this prevents is positional, so assert on the position:
        // the duplicate had no offset and landed at the left edge, above the
        // page's own content.
        assert!(
            !p.boxes.iter().any(|b| b.x == 0.0),
            "a box at x = 0 is the unpositioned duplicate: {:?}",
            p.boxes.iter().map(|b| (b.x, b.y)).collect::<Vec<_>>()
        );
    }

    /// Backlog #56, half two: an element whose first paragraph is blank had its
    /// content pulled a line UP the page.
    ///
    /// OneNote's recorded offset is the top of the element's FIRST line, blank
    /// or not. The importer drops leading blanks (so a box does not open on an
    /// empty line) but kept the offset, so everything below the blank rode up
    /// by one line and ran into whatever OneNote had put there.
    ///
    /// On "Natural Language and Intro to Truth Tables" that is exactly what
    /// happened: the AND table's element opens with an empty paragraph, so the
    /// table landed at y = 628.25 — its own caption's y — while the OR and NOT
    /// tables, whose elements carry no leading blank, sat correctly at 650.63,
    /// one line lower. The table drew through the word "AND".
    ///
    /// Two elements at the SAME y here, one with a leading blank and one
    /// without, because the bug is a difference between them and a test on one
    /// alone would pass on any constant.
    #[test]
    fn a_dropped_leading_blank_is_paid_for_in_y() {
        let mut f = OneFile::new();
        let (space_guid, page_guid, dir_guid) = ([0xC4; 16], [0x61; 16], [0xDF; 16]);
        let mut live = vec![
            decl(1, JCID_PAGE_NODE, kids_blob(&[2])),
            decl(2, JCID_OUTLINE, kids_blob(&[3, 4])),
            // Both elements start at 10.0 units down = 600 px.
            decl(3, JCID_OUTLINE_ELEMENT, placed_kids_blob(&[10, 12], 1.0, 10.0)),
            decl(4, JCID_OUTLINE_ELEMENT, placed_kids_blob(&[20], 5.0, 10.0)),
        ];
        live.extend(para(10, None)); // the blank line the writer typed
        live.extend(para(12, Some("Below the blank")));
        live.extend(para(20, Some("No blank above me")));
        live.push(decl(9, JCID_PAGE_METADATA, page_id_blob(&page_guid)));
        let page = f.space(space_guid, &[Rev::live(&[1], live)]);
        let dir = dir_space(&mut f, dir_guid, &[(space_guid, page_guid, "Truth Tables")], &[0]);
        let root = f.root(&[(dir, dir_guid), (page, space_guid)]);
        let section = import_one(&f.finish(root));

        assert!(section.ok, "the synthetic section must parse: {:?}", section.error);
        let p = &section.pages[0];
        assert_eq!(p.boxes.len(), 2, "two elements, two boxes: {:?}", box_markdown(p));
        let with_blank = p.boxes.iter().find(|b| b.x == 60.0).expect("the first element's box");
        let without = p.boxes.iter().find(|b| b.x == 300.0).expect("the second element's box");
        assert_eq!(
            without.y, 600.0,
            "an element with no leading blank keeps OneNote's offset verbatim"
        );
        assert_eq!(
            with_blank.y, 622.0,
            "the dropped blank occupied a line, so the content below it starts \
             one line lower — not at the element's own offset"
        );
        // The blank is dropped, not rendered: paying for it in y is the whole
        // point, and leaving it in the markdown would double-count it.
        assert!(
            with_blank.markdown.starts_with("Below the blank"),
            "the leading blank must not survive into the box: {:?}",
            with_blank.markdown
        );
    }

    /// The blank-line fix from the bytes up.
    ///
    /// A OneNote paragraph is a PAIR — a RichText container (0x0D) and its one
    /// text run (0x0E) — and the fix turns on WHICH of the two is empty: a
    /// blank RUN is a line the writer typed, a blank CONTAINER is structural
    /// noise present once per paragraph. Keying on emptiness alone instead of
    /// on the object type is what double-spaced the notebook the first time
    /// this shipped (24 lines of content came back separated by 31 blanks) and
    /// got it reverted.
    ///
    /// Until now that discriminator was only pinned by tests that hand-build
    /// `Line` values, which is one layer ABOVE the code that reads the
    /// objects — so breaking the read itself was invisible. This one starts at
    /// the bytes: three real paragraph pairs, the middle run empty. It fails in
    /// BOTH directions — drop the branch and the blank disappears, widen it to
    /// the container and three textless containers add three more blanks.
    #[test]
    fn a_blank_run_is_a_blank_line_and_a_blank_container_is_not() {
        let mut f = OneFile::new();
        let (space_guid, page_guid, dir_guid) = ([0xC5; 16], [0x71; 16], [0xE0; 16]);
        let mut live = vec![
            decl(1, JCID_PAGE_NODE, kids_blob(&[2])),
            decl(2, JCID_OUTLINE, kids_blob(&[3])),
            decl(3, JCID_OUTLINE_ELEMENT, kids_blob(&[10, 12, 14])),
        ];
        live.extend(para(10, Some("Above the gap")));
        live.extend(para(12, None)); // the run the writer left empty
        live.extend(para(14, Some("Below the gap")));
        live.push(decl(9, JCID_PAGE_METADATA, page_id_blob(&page_guid)));
        let page = f.space(space_guid, &[Rev::live(&[1], live)]);
        let dir = dir_space(&mut f, dir_guid, &[(space_guid, page_guid, "Tautologies")], &[0]);
        let root = f.root(&[(dir, dir_guid), (page, space_guid)]);
        let section = import_one(&f.finish(root));

        assert!(section.ok, "the synthetic section must parse: {:?}", section.error);
        let p = &section.pages[0];
        assert_eq!(
            box_markdown(p),
            ["Above the gap\n\nBelow the gap"],
            "the empty RUN is one blank line, and the three textless \
             CONTAINERS are none"
        );
    }

    // ── Character formatting and maths structure ───────────────────────────

    /// A property whose value is a list of property sets (type 0x10): the
    /// element count, the array's own prid, then each element as an embedded
    /// `PropertySet` — a `u16` property count, the prid words, then the data.
    fn propset_array(pid: u32, sets: &[Vec<(u32, u8, Vec<u8>)>]) -> Vec<u8> {
        let mut b = (sets.len() as u32).to_le_bytes().to_vec();
        b.extend_from_slice(&pid.to_le_bytes());
        for set in sets {
            b.extend_from_slice(&(set.len() as u16).to_le_bytes());
            for (p, t, _) in set {
                b.extend_from_slice(&(p | ((*t as u32) << 26)).to_le_bytes());
            }
            for (_, _, d) in set {
                b.extend_from_slice(d);
            }
        }
        b
    }

    /// A boolean property. ONESTORE keeps the VALUE in bit 31 of the prid
    /// word and gives the property no data at all, so `true` needs the type
    /// nibble carried up with it — `0x22` is type 0x02 with bit 31 set.
    fn bool_prop(pid: u32, v: bool) -> (u32, u8, Vec<u8>) {
        (pid, if v { 0x22 } else { 0x02 }, Vec::new())
    }

    /// A `u32` property (type 0x05).
    fn u32_prop(pid: u32, v: u32) -> (u32, u8, Vec<u8>) {
        (pid, 0x05, v.to_le_bytes().to_vec())
    }

    /// A character-formatting object: whatever properties it is given.
    fn style_decl(n: u8, props: &[(u32, u8, Vec<u8>)]) -> Decl {
        decl(n, 0x0002_0001, propset_blob(&[], props))
    }

    /// A paragraph split into runs: `text`, the UTF-16 offsets where each run
    /// after the first begins (0x1E12) and the style object per run (0x1E13).
    fn runs_blob(text: &str, bounds: &[u32], styles: &[u8], math: Option<Vec<u8>>) -> Vec<u8> {
        let idx: Vec<u8> = bounds.iter().flat_map(|b| b.to_le_bytes()).collect();
        let oids: Vec<u32> = styles.iter().map(|&s| cid(s)).collect();
        let mut props = vec![
            (PID_RUN_FORMATTING, 0x09, (styles.len() as u32).to_le_bytes().to_vec()),
            (PID_TEXT_UTF16, 0x07, utf16_data(text)),
            (PID_RUN_INDEX, 0x07, str_data(&idx)),
        ];
        if let Some(m) = math {
            props.push((PID_MATH_OBJECTS, 0x10, m));
        }
        propset_blob(&oids, &props)
    }

    /// Reported: "all of the subscript wasnt respected, this wasnt done in
    /// mathematical notation, onenote lets you set regular text as subscript or
    /// superscript which is what i did here. This was for the a1, a2, and am."
    ///
    /// 0x1C09 and 0x1C08 are ordinary character formatting — the ribbon's x₂
    /// and x² buttons — and the style reader parsed neither, so `a₁` imported
    /// as the two characters "a1" and the note stopped saying what it said.
    /// Emitted in the Pandoc dialect the app's Markdown grammar parses.
    #[test]
    fn plain_text_subscript_and_superscript_survive_the_import() {
        let mut f = OneFile::new();
        let (space_guid, page_guid, dir_guid) = ([0xE1; 16], [0x51; 16], [0xE9; 16]);
        let live = vec![
            decl(1, JCID_PAGE_NODE, kids_blob(&[2])),
            decl(2, JCID_OUTLINE, kids_blob(&[3])),
            // "a" plain, "1" subscript, "x" plain, "2" superscript, then a
            // subscript run of TWO words — the app's grammar forbids
            // whitespace inside the markers, so one pair around the phrase
            // would render as visible tildes.
            decl(
                3,
                JCID_RICHTEXT_RUN,
                runs_blob("a1x2 max val", &[1, 2, 3, 4, 5], &[10, 11, 10, 12, 10, 11], None),
            ),
            style_decl(10, &[bool_prop(PID_SUBSCRIPT, false), bool_prop(PID_SUPERSCRIPT, false)]),
            style_decl(11, &[bool_prop(PID_SUBSCRIPT, true)]),
            style_decl(12, &[bool_prop(PID_SUPERSCRIPT, true)]),
            decl(9, JCID_PAGE_METADATA, page_id_blob(&page_guid)),
        ];
        let page = f.space(space_guid, &[Rev::live(&[1], live)]);
        let dir = dir_space(&mut f, dir_guid, &[(space_guid, page_guid, "Countable Sets")], &[0]);
        let root = f.root(&[(dir, dir_guid), (page, space_guid)]);
        let section = import_one(&f.finish(root));

        assert!(section.ok, "the synthetic section must parse: {:?}", section.error);
        assert_eq!(
            page_lines(&section.pages[0]),
            ["a~1~x^2^ ~max~ ~val~"],
            "the subscript and the superscript must each survive as their own \
             marked span, the unformatted characters beside them must not, and \
             a two-word subscript must be marked word by word"
        );
    }

    /// Reported: "the second table included the arrows in the middle however
    /// the first and last columns are both entirley empty."
    ///
    /// OneNote marks a character inserted from the symbol palette as a MATHS
    /// run, so a cell holding just `ℕ` was a maths-only paragraph — and a
    /// maths Line carries LaTeX with no runs, while the cell renderer rendered
    /// only runs. Every such cell came out blank; the arrow column survived
    /// because an arrow typed as prose is prose. Both halves are fixed here:
    /// a lone symbol is no longer promoted to an equation at all, and a cell
    /// that really does hold one renders it.
    #[test]
    fn a_table_cell_holding_a_symbol_is_not_emptied_by_it() {
        let mut f = OneFile::new();
        let (space_guid, page_guid, dir_guid) = ([0xE2; 16], [0x52; 16], [0xEA; 16]);
        // The row's three cells: a symbol, an arrow typed as prose, a symbol.
        let cell = |n: u8, run: u8| decl(n, JCID_TABLE_CELL, kids_blob(&[run]));
        let live = vec![
            decl(1, JCID_PAGE_NODE, kids_blob(&[2])),
            decl(2, JCID_OUTLINE, kids_blob(&[3])),
            decl(3, JCID_OUTLINE_ELEMENT, kids_blob(&[4])),
            decl(4, JCID_TABLE, kids_blob(&[5])),
            decl(5, JCID_TABLE_ROW, kids_blob(&[6, 7, 8, 12])),
            cell(6, 20),
            cell(7, 21),
            cell(8, 22),
            // A cell that really does hold notation, not a symbol: it must
            // arrive as inline maths rather than as the blank the renderer
            // used to leave, and it is the other half of the same fix.
            cell(12, 23),
            decl(20, JCID_RICHTEXT_RUN, runs_blob("ℕ", &[], &[30], None)),
            decl(21, JCID_RICHTEXT_RUN, runs_blob("→", &[], &[31], None)),
            decl(22, JCID_RICHTEXT_RUN, runs_blob("ℤ", &[], &[30], None)),
            decl(
                23,
                JCID_RICHTEXT_RUN,
                runs_blob("\u{FDD0}n\u{FDEE}2\u{FDEF}", &[], &[30], None),
            ),
            // The maths font is the ONLY thing that marks a run as maths.
            style_decl(30, &[(PID_FONT, 0x07, utf16_data("Cambria Math"))]),
            style_decl(31, &[(PID_FONT, 0x07, utf16_data("Calibri"))]),
            decl(9, JCID_PAGE_METADATA, page_id_blob(&page_guid)),
        ];
        let page = f.space(space_guid, &[Rev::live(&[1], live)]);
        let dir = dir_space(&mut f, dir_guid, &[(space_guid, page_guid, "Countable Sets")], &[0]);
        let root = f.root(&[(dir, dir_guid), (page, space_guid)]);
        let section = import_one(&f.finish(root));

        assert!(section.ok, "the synthetic section must parse: {:?}", section.error);
        let cells: Vec<Vec<String>> = section.pages[0]
            .boxes
            .iter()
            .filter(|b| b.kind == "table")
            .flat_map(|b| b.cells.clone())
            .collect();
        assert_eq!(
            cells,
            vec![vec![
                "ℕ".to_string(),
                "→".to_string(),
                "ℤ".to_string(),
                r"$\frac{n}{2}$".to_string(),
            ]],
            "the outer columns must carry their symbols, not be blanked by them"
        );
    }

    /// Reported: "the maths equation was not rendered quite properly. If you
    /// refer to the pdf from onenote you will see it is meant to render one
    /// part on top of the other there with the single large curly brace."
    ///
    /// A piecewise definition, as OneNote stores one: a delimiter whose
    /// opening character is `{` and which has no closing character, wrapped
    /// around an equation array. NOTHING in the run text says that — every
    /// object is the same U+FDD0 — so the importer assumed "fraction" for all
    /// of them and the brace, the array and the delimiters all vanished. The
    /// kinds come from the per-run sidecar 0x3499, and this is the shape that
    /// has to survive it.
    ///
    /// It also has to survive it **in the sentence it was written in**. This
    /// test used to expect two boxes — `("text", "f(n) =")` and a separate
    /// `("math", …)` — and the owner reported the result: "it seems like we
    /// cant have maths in the same box and on the same line as text… i think
    /// it got broken out into its own thing." OneNote's own PDF export of the
    /// page settles it: the prose ends at x=246.3 on baseline y=407.69 and the
    /// equation's first glyph is at x=252.9 on that same line, growing the
    /// line upwards and downwards (y 380.3…428.0) rather than leaving it. One
    /// box, `$…$` inline, is the shape that matches.
    #[test]
    fn a_piecewise_definition_imports_inline_in_its_sentence() {
        let mut f = OneFile::new();
        let (space_guid, page_guid, dir_guid) = ([0xE3; 16], [0x53; 16], [0xEB; 16]);
        // "f(n) = " then 𝑥⟨{ ⟨█ ⟨/ n ¦ 2 ⟩ ¦ −x ⟩ ⟩ — the reference page's own
        // shape: a sentence that ENDS in the equation, and three opening
        // markers each in its own run, exactly as OneNote splits them.
        //
        // The `𝑥` is MATHEMATICAL ITALIC SMALL X, and it is here on purpose:
        // it is ASTRAL, so 0x1E12's UTF-16 offsets stop agreeing with
        // character positions right at the first marker. Reading them as
        // character offsets — which is what this file did — hands each U+FDD0
        // the descriptor belonging to the object after it.
        //
        // The array has THREE rows for two branches, because the writer left a
        // blank line between them and OneNote records that as a row — the
        // reference page's does exactly this.
        let text = "f(n) = \u{1D465}\u{FDD0}\u{FDD0}\u{FDD0}n\u{FDEE}2\u{FDEF}\
                    \u{FDEE} \u{FDEE}−x\u{FDEF}\u{FDEF}";
        let math = propset_array(
            PID_MATH_OBJECTS,
            &[
                // The prose and the `𝑥` sit outside every object.
                Vec::new(),
                Vec::new(),
                // The big brace: one argument, opens with `{`, never closes.
                vec![
                    u32_prop(PID_MATH_KIND, MATH_DELIM),
                    u32_prop(PID_MATH_ARGS, 1),
                    u32_prop(PID_MATH_BEG, '{' as u32),
                ],
                // The equation array: three rows, one column.
                vec![
                    u32_prop(PID_MATH_KIND, MATH_EQ_ARRAY),
                    u32_prop(PID_MATH_ARGS, 3),
                    u32_prop(PID_MATH_COLS, 1),
                    u32_prop(PID_MATH_BEG, 0x2588),
                ],
                vec![
                    u32_prop(PID_MATH_KIND, MATH_FRACTION),
                    u32_prop(PID_MATH_ARGS, 2),
                    u32_prop(PID_MATH_BEG, '/' as u32),
                ],
                // The two content runs describe only their enclosing context.
                vec![u32_prop(PID_MATH_KIND, MATH_FRACTION)],
                vec![u32_prop(PID_MATH_KIND, MATH_EQ_ARRAY)],
            ],
        );
        let live = vec![
            decl(1, JCID_PAGE_NODE, kids_blob(&[2])),
            decl(2, JCID_OUTLINE, kids_blob(&[3])),
            decl(
                3,
                JCID_RICHTEXT_RUN,
                // UTF-16 offsets, as OneNote writes them: the astral `𝑥`
                // occupies units 7 and 8, so the first marker begins at 9.
                runs_blob(text, &[7, 9, 10, 11, 12, 16], &[31, 30, 30, 30, 30, 30, 30], Some(math)),
            ),
            style_decl(30, &[(PID_FONT, 0x07, utf16_data("Cambria Math"))]),
            style_decl(31, &[(PID_FONT, 0x07, utf16_data("Calibri"))]),
            decl(9, JCID_PAGE_METADATA, page_id_blob(&page_guid)),
        ];
        let page = f.space(space_guid, &[Rev::live(&[1], live)]);
        let dir = dir_space(&mut f, dir_guid, &[(space_guid, page_guid, "Countable Sets")], &[0]);
        let root = f.root(&[(dir, dir_guid), (page, space_guid)]);
        let section = import_one(&f.finish(root));

        assert!(section.ok, "the synthetic section must parse: {:?}", section.error);
        let shapes: Vec<(&str, &str)> = section.pages[0]
            .boxes
            .iter()
            .map(|b| {
                (b.kind.as_str(), if b.kind == "math" { &b.latex } else { &b.markdown }.as_str())
            })
            .collect();
        assert_eq!(
            shapes,
            [("text", r"f(n) = $x\begin{cases}\frac{n}{2} \\ −x\end{cases}$")],
            "the brace and the stacked rows must both survive, and the equation \
             must stay in the sentence it was written in — ONE box, delimited \
             inline, the way OneNote's own export sets it"
        );
    }

    /// The rest of the constructs a student's notes actually contain, against
    /// the same sidecar. Decoded from 1 154 equations in the owner's notebook,
    /// and held here because the alternative — every one of them arriving as a
    /// fraction — is what the import looked like: a matrix came back as five
    /// fractions inside each other, and `aᵢ` as `\frac{a}{i}`.
    #[test]
    fn the_maths_object_kinds_each_convert_to_their_own_latex() {
        // ⟨ a ¦ b ⟩ — the shape every two-argument object shares. What it
        // MEANS is the kind, and only the kind.
        let two = "\u{FDD0}a\u{FDEE}b\u{FDEF}";
        let obj = |kind: u32, args: u32, cols: u32, beg: Option<char>| {
            vec![(0usize, MathObj { kind, args, cols, beg, end: None })]
        };
        let cases: [(u32, Option<char>, &str); 7] = [
            (MATH_FRACTION, Some('/'), r"\frac{a}{b}"),
            (MATH_SUB, Some('_'), r"{a}_{b}"),
            (MATH_SUP, Some('^'), r"{a}^{b}"),
            (MATH_NO_BAR, Some('¦'), r"{a \atop b}"),
            (MATH_NARY, Some('\u{2211}'), r"\sum_{a}^{b} "),
            (MATH_RADICAL, Some('√'), r"\sqrt[a]{b}"),
            (MATH_MATRIX, Some('■'), r"\begin{matrix}a & b\end{matrix}"),
        ];
        for (kind, beg, want) in cases {
            let cols = if kind == MATH_MATRIX { 2 } else { 0 };
            assert_eq!(
                office_math_to_latex(two, &obj(kind, 2, cols, beg)),
                want,
                "kind {kind}"
            );
        }
        // A delimiter carries its own brackets, and an absent one is `\right.`
        // — LaTeX's "no delimiter", which is what the piecewise brace needs.
        let one = "\u{FDD0}a\u{FDEF}";
        let delim = |beg: char, end: Option<char>| {
            vec![(0usize, MathObj { kind: MATH_DELIM, args: 1, cols: 0, beg: Some(beg), end })]
        };
        assert_eq!(office_math_to_latex(one, &delim('(', Some(')'))), r"\left(a\right)");
        assert_eq!(office_math_to_latex(one, &delim('|', Some('|'))), r"\left|a\right|");
        assert_eq!(office_math_to_latex(one, &delim('{', None)), r"\left\{a\right.");
        // An accent names the command that draws it; a function name becomes
        // LaTeX's upright operator so `sin θ` is not typeset as s·i·n·θ.
        let acc = |c: char| {
            vec![(0usize, MathObj { kind: MATH_ACCENT, args: 1, cols: 0, beg: Some(c), end: None })]
        };
        assert_eq!(office_math_to_latex(one, &acc('\u{0302}')), r"\hat{a}");
        assert_eq!(office_math_to_latex(one, &acc('\u{20D7}')), r"\vec{a}");
        let func =
            vec![(0usize, MathObj { kind: MATH_FUNC, args: 2, cols: 0, beg: None, end: None })];
        assert_eq!(office_math_to_latex("\u{FDD0}sin\u{FDEE}x\u{FDEF}", &func), r"\sin x");
        // …and with no descriptor at all, the old rule still answers, so a
        // file that predates the sidecar imports exactly as it always did.
        assert_eq!(office_math_to_latex(two, &[]), r"\frac{a}{b}");
    }
}
