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
const JCID_PAGE_SERIES: u32 = 0x00060008;
const PID_ELEMENT_CHILDREN: u32 = 0x001C20; // section → page-series refs
const PID_PAGE_METADATA: u32 = 0x003442; // page-series → PageMetadata refs
const PID_PAGE_SPACES: u32 = 0x001D63; // page-series → page object-space refs

// ── MS-ONE object types (JCID) we navigate ─────────────────────────────────
const JCID_OUTLINE: u32 = 0x0006000B;
const JCID_OUTLINE_ELEMENT: u32 = 0x0006000C;
const JCID_RICHTEXT: u32 = 0x0006000D;
const JCID_RICHTEXT_RUN: u32 = 0x0006000E;
const JCID_TITLE: u32 = 0x0006002C;
const JCID_OUTLINE_GROUP: u32 = 0x00060019;
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
const PID_RUN_INDEX: u32 = 0x001E12; // TextRunIndex: array of u32 char offsets
const PID_RUN_FORMATTING: u32 = 0x001E13; // TextRunFormatting: style OIDs per run
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
}

#[derive(Serialize, Default)]
pub struct ImportedSection {
    pub ok: bool,
    pub error: Option<String>,
    pub pages: Vec<ImportedPage>,
}

/// Parse a `.one` section file into structured content, returned as JSON.
pub fn import_one_json(bytes: &[u8]) -> String {
    let section = match std::panic::catch_unwind(|| import_one(bytes)) {
        Ok(s) => s,
        Err(_) => ImportedSection {
            ok: false,
            error: Some("failed to parse .one (unexpected structure)".into()),
            pages: vec![],
        },
    };
    serde_json::to_string(&section).unwrap_or_else(|_| "{\"ok\":false}".into())
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
    walk(&r, root, &mut wo, &mut visited, 0, 0, &mut next_space, &mut cur_rev);
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
    // every content space; read the parallel PageMetadata for title + level.
    let mut space_meta: HashMap<usize, (String, u32, usize)> = HashMap::new();
    let mut global_ord = 0usize;
    for (&dir_sp, idxs) in &spaces {
        // A directory space is where the section node lives.
        let Some(&si) = idxs
            .iter()
            .filter(|&&i| objs[i].jcid == JCID_SECTION_NODE)
            .max_by_key(|&&i| objs[i].stp)
        else {
            continue;
        };
        let mut latest: HashMap<u32, usize> = HashMap::new();
        for &i in idxs {
            let e = latest.entry(objs[i].own_oid).or_insert(i);
            if objs[i].stp > objs[*e].stp {
                *e = i;
            }
        }
        let table = wo.gid_tables.get(&dir_sp);
        let section = read_propset(&r, objs[si].stp, objs[si].cb);
        for series_oid in section.oids(PID_ELEMENT_CHILDREN) {
            let Some(&pi) = latest.get(&series_oid) else { continue };
            if objs[pi].jcid != JCID_PAGE_SERIES {
                continue;
            }
            let series = read_propset(&r, objs[pi].stp, objs[pi].cb);
            let page_spaces = series.osids(PID_PAGE_SPACES);
            let page_metas = series.oids(PID_PAGE_METADATA);
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
                let (mut title, mut level) = (String::new(), 0u32);
                if let Some(&mi) = page_metas.get(k).and_then(|oid| latest.get(oid)) {
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
    }

    // Unique PNGs recovered from the file data store, matched to image objects
    // below by natural pixel size (±2px).
    struct Png {
        bytes: Vec<u8>,
        w: u32,
        h: u32,
        used: bool,
    }
    let mut pngs: Vec<Png> = Vec::new();
    let mut seen_png = HashSet::new();
    for png in scan_pngs(bytes) {
        if !seen_png.insert((png.len(), png.first().copied(), png.last().copied())) {
            continue;
        }
        let (w, h) = if png.len() >= 24 {
            (
                u32::from_be_bytes([png[16], png[17], png[18], png[19]]),
                u32::from_be_bytes([png[20], png[21], png[22], png[23]]),
            )
        } else {
            (0, 0)
        };
        pngs.push(Png { bytes: png, w, h, used: false });
    }

    // OneNote's stored offsets are absolute in its own page space, whose origin
    // includes the title area — the same layout Openote's page presents. Trust
    // them verbatim (adding our own margin on top double-shifts everything).
    const MX: f32 = 0.0;
    const MY: f32 = 0.0;
    /// Fallback stacking start (below Openote's title band).
    const CONTENT_TOP: f32 = 92.0;
    // Collected as (display order, page); sorted after the loop.
    let mut pages: Vec<(usize, ImportedPage)> = Vec::new();
    let mut img_counter = 0usize;

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
                if objs[i].stp > objs[*ent].stp {
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

        // The page's content root is the PageNode (JCID 0x0006000B) declaration
        // with actual 0x1C20 content children and the highest file offset. The
        // literal latest revision of a page can be a title-only stub with no
        // 0x1C20 — picking it drops the whole page's text.
        let root_i = idxs
            .iter()
            .copied()
            .filter(|&i| objs[i].jcid == JCID_OUTLINE)
            .filter(|&i| !read_propset(&r, objs[i].stp, objs[i].cb).oids(0x001C20).is_empty())
            .max_by_key(|&i| objs[i].stp);
        let root_ps = root_i.map(|i| read_propset(&r, objs[i].stp, objs[i].cb));
        let root_rev = root_i.map(|i| objs[i].rev).unwrap_or(0);

        // Title/date: the title outline; its text feeds page metadata, never a box.
        let mut date_text = String::new();
        let mut title_plains: HashSet<String> = HashSet::new();
        if let Some(&ti) = idxs
            .iter()
            .filter(|&&i| objs[i].jcid == JCID_TITLE)
            .max_by_key(|&&i| objs[i].stp)
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
        let root_children: HashSet<u32> = root_ps
            .as_ref()
            .map(|ps| ps.oids(0x001C20).into_iter().map(|c| res.canon(c, root_rev)).collect())
            .unwrap_or_default();
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
        let mut img_objs: Vec<(u32, usize)> = Vec::new();
        let mut seen_img = HashSet::new();
        for &i in idxs {
            let o = &objs[i];
            if o.jcid != JCID_IMAGE {
                continue;
            }
            if let Some(c) = canon_of(o) {
                if seen_img.insert(c) {
                    img_objs.push((c, res.by_canon[&c]));
                }
            }
        }
        img_objs.sort_by_key(|&(_, i)| objs[i].stp);
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
                None => continue, // no pixel data recovered for this object
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
                name: format!("onenote-image-{img_counter}.png"),
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
        let root_child_oids = root_ps.as_ref().map(|ps| ps.oids(0x001C20)).unwrap_or_default();
        for cid in root_child_oids {
            let ci = match res.get(cid, root_rev) {
                Some(i) => i,
                None => continue,
            };
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
            lines.retain(|l| l.image.is_some() || !title_plains.contains(&l.plain()));
            if lines.is_empty() {
                continue;
            }
            let end_y = emit_boxes(&lines, x, y, w, &mut boxes, &img_idx);
            stack_y = stack_y.max(end_y) + 24.0;
        }

        // ── Ink: container → data node → stroke nodes → packed paths ────────
        let mut ink: Vec<ImportedStroke> = Vec::new();
        let mut seen_ink = HashSet::new();
        for &i in idxs {
            let o = &objs[i];
            if o.jcid != JCID_INK_CONTAINER {
                continue;
            }
            match canon_of(o) {
                Some(c) if res.by_canon.get(&c) == Some(&i) && seen_ink.insert(c) => {}
                _ => continue, // not the current declaration, or a duplicate
            }
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
                            continue; // no usable channel split
                        };
                        idx_x = 0;
                        idx_y = 1;
                        idx_p = None;
                    }
                    // Final guard: a stroke that still spans absurdly is
                    // undecodable — drop it rather than paint a page-crossing
                    // scribble (a handful per notebook; better lost than wrong).
                    if span_of(ndims, idx_x, idx_y) > SANE_MAX {
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
            .or_else(|| {
                date_text
                    .lines()
                    .next()
                    .map(|s| s.trim().to_string())
                    .filter(|s| !s.is_empty())
            })
            .unwrap_or_else(|| "Imported page".into());
        let level = meta.map(|m| m.1).unwrap_or(0);
        let ord = meta.map(|m| m.2).unwrap_or(usize::MAX);
        pages.push((ord, ImportedPage { title, date_text, boxes, images, ink, level }));
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

    // Any PNGs no object claimed: append to the first page's fallback column so
    // the pixels are never silently dropped.
    if let Some(first) = pages.first_mut() {
        let mut fy = 40.0f32;
        for p in pngs.iter().filter(|p| !p.used) {
            img_counter += 1;
            first.images.push(ImportedImage {
                name: format!("onenote-image-{img_counter}.png"),
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
fn emit_boxes(
    lines: &[Line],
    x: f32,
    y: f32,
    w: Option<f32>,
    out: &mut Vec<PageBox>,
    img_idx: &HashMap<u32, String>,
) -> f32 {
    const LINE_H: f32 = 22.0;
    let mut cy = y;
    let mut seg: Vec<&Line> = Vec::new();
    fn flush(
        seg: &mut Vec<&Line>,
        x: f32,
        w: Option<f32>,
        cy: &mut f32,
        out: &mut Vec<PageBox>,
        img_idx: &HashMap<u32, String>,
    ) {
        if seg.is_empty() {
            return;
        }
        let md = outline_markdown(seg, img_idx);
        if !md.trim().is_empty() {
            out.push(PageBox {
                kind: "text".into(),
                x,
                y: *cy,
                w,
                markdown: md,
                latex: String::new(),
                font: dominant_font(seg),
                font_size_pt: dominant_size(seg),
            });
            *cy += seg.len() as f32 * LINE_H + 14.0;
        }
        seg.clear();
    }
    for l in lines {
        if let Some(latex) = &l.math {
            flush(&mut seg, x, w, &mut cy, out, img_idx);
            out.push(PageBox {
                kind: "math".into(),
                x: x + 24.0,
                y: cy,
                w: None,
                markdown: String::new(),
                latex: latex.clone(),
                font: None,
                font_size_pt: None,
            });
            cy += 48.0;
        } else {
            seg.push(l); // text AND in-flow image lines stay in the one box
        }
    }
    flush(&mut seg, x, w, &mut cy, out, img_idx);
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
                    walk(r, sub, out, visited, depth + 1, child_space, next_space, cur_rev);
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
                    });
                }
            } else if base_type == 0 {
                let body = o + 4;
                match id {
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
    }
}

/// One styled span of text within a paragraph.
struct SRun {
    text: String,
    style: Style,
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

    // Single style (or a shape we can't split cleanly): one merged run.
    if fmt.len() <= 1 || bounds.len() + 1 != fmt.len() {
        let mut st = base;
        for &f in &fmt {
            st = merge_style(&st, &resolve_style(r, res, f, o.rev));
        }
        return vec![SRun { text, style: st }];
    }

    // Multi-run: boundaries [0, b0, b1, …, len] split the char stream.
    let mut starts = vec![0usize];
    starts.extend(bounds.iter().copied());
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
        runs.push(SRun { text: seg, style: st });
    }
    if runs.is_empty() {
        runs.push(SRun { text, style: base });
    }
    runs
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

/// Best-effort conversion of OneNote's Office linear-math Unicode (as stored in
/// a Cambria-Math run's 0x1C22 text) to LaTeX. Handles fraction delimiters
/// (U+FDD0 numerator … U+FDEE bar … U+FDEF end) and folds math-italic letters;
/// strips invisible operators. Unrecognised structure degrades to plain text.
fn office_math_to_latex(s: &str) -> String {
    let mut t: String = s.chars().map(fold_math_char).collect();
    // Collapse fractions innermost-first: FDD0 num FDEE den FDEF → \frac{num}{den}.
    let (d0, dbar, dend) = ('\u{FDD0}', '\u{FDEE}', '\u{FDEF}');
    let mut guard = 0;
    while let Some(end) = t.find(dend) {
        guard += 1;
        if guard > 256 {
            break;
        }
        let before = &t[..end];
        if let (Some(s0), Some(bar)) = (before.rfind(d0), before.rfind(dbar)) {
            if s0 < bar {
                let num = t[s0 + d0.len_utf8()..bar].trim().to_string();
                let den = t[bar + dbar.len_utf8()..end].trim().to_string();
                let repl = format!("\\frac{{{num}}}{{{den}}}");
                t.replace_range(s0..end + dend.len_utf8(), &repl);
                continue;
            }
        }
        // Malformed — drop the stray end marker and carry on.
        t.replace_range(end..end + dend.len_utf8(), "");
    }
    // Strip any leftover structure/invisible chars, collapse runs of spaces.
    let cleaned: String = t.chars().filter(|c| !is_math_control(*c)).collect();
    cleaned.split_whitespace().collect::<Vec<_>>().join(" ")
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

/// Render one styled run as Markdown, applying bold/italic/strike (Openote's
/// live-Markdown dialect) and the `{{#RRGGBB …}}` colour extension.
fn run_markdown(run: &SRun) -> String {
    let mut s = run.text.replace('\r', "");
    if s.trim().is_empty() {
        return s;
    }
    // Preserve leading/trailing spaces outside the emphasis markers.
    let lead: String = s.chars().take_while(|c| *c == ' ').collect();
    let trail: String = s.chars().rev().take_while(|c| *c == ' ').collect();
    let core = s[lead.len()..s.len() - trail.len()].to_string();
    let mut core = core;
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
struct Line {
    depth: usize,
    is_list: bool,
    bullet: String,
    runs: Vec<SRun>,
    math: Option<String>,
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
        let plain: String = runs.iter().map(|s| s.text.as_str()).collect();
        if !plain.trim().is_empty() {
            if runs.iter().any(|s| s.style.is_math) {
                // Math paragraph: the run text is Office linear-math Unicode.
                let latex = office_math_to_latex(plain.trim_end_matches('\0'));
                if !latex.trim().is_empty() {
                    out.push(Line {
                        depth,
                        is_list: ctx,
                        bullet: bullet.clone(),
                        runs: Vec::new(),
                        math: Some(latex),
                        image: None,
                    });
                }
            } else {
                out.push(Line {
                    depth,
                    is_list: ctx,
                    bullet: bullet.clone(),
                    runs,
                    math: None,
                    image: None,
                });
            }
        }
    }

    for cid in children {
        if let Some(idx) = res.get(cid, o.rev) {
            let child = res.obj(idx);
            if child.jcid == JCID_IMAGE {
                // An image in the outline flow (e.g. a list item that is an
                // image) — record it (canonicalised) as a line so the box
                // splitter can place it and advance the flow by its height.
                out.push(Line {
                    depth: depth + 1,
                    is_list: false,
                    bullet: String::new(),
                    runs: Vec::new(),
                    math: None,
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
    Other,
}

/// One object's fully-parsed property set, in declaration order.
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
        self.u32(pid).map(f32::from_bits)
    }
    fn flag(&self, pid: u32) -> bool {
        matches!(self.get(pid), Some(PVal::Bool(true)))
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
    /// Text of a rich-text run: UTF-8 body (0x3498) preferred, else UTF-16.
    fn run_text(&self) -> Option<String> {
        if let Some(PVal::Str(b)) = self.get(PID_TEXT_UTF8) {
            return Some(String::from_utf8_lossy(b).into_owned());
        }
        if let Some(PVal::Str(b)) = self.get(PID_TEXT_UTF16) {
            return Some(decode_utf16(b));
        }
        None
    }
}

fn clean_str(s: String) -> String {
    s.trim_matches(|c: char| c == '\0').trim_end().to_string()
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
                    PVal::Other
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
            _ => PVal::Other,
        };
        // 0x05 (4-byte) is stored as raw bits (PVal::U32); callers read it as
        // either f32() or u32() since the type alone doesn't say which.
        props.push((pid, val));
        data_o += data_size(r, data_o, ptype);
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
                    text = Some(String::from_utf8_lossy(bytes).into_owned());
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
    a.bold == b.bold
        && a.italic == b.italic
        && a.strike == b.strike
        && a.highlight == b.highlight
        && color_hex(a.color) == color_hex(b.color)
}

/// Render a paragraph's styled runs to Markdown, coalescing adjacent runs that
/// share visible formatting so we emit `**Host:**` rather than `**Ho****st:**`.
fn render_runs(runs: &[SRun]) -> String {
    let mut merged: Vec<SRun> = Vec::new();
    for run in runs {
        if let Some(last) = merged.last_mut() {
            if same_visible(&last.style, &run.style) {
                last.text.push_str(&run.text);
                continue;
            }
        }
        merged.push(SRun {
            text: run.text.clone(),
            style: run.style.clone(),
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
/// items keep their original bullet; non-list paragraphs stay flush-left (bold
/// runs become `**…**` — the OneNote heading look); in-flow images render as
/// `![image](onote-img://N)` placeholder lines (the importer rewrites N to the
/// stored blob hash). Math never reaches here: [emit_boxes] splits equations
/// into their own boxes first. Normalised so the shallowest line sits at the
/// left margin; 2 spaces per indent level.
fn outline_markdown(lines: &[&Line], img_idx: &HashMap<u32, String>) -> String {
    let min_depth = lines.iter().map(|l| l.depth).min().unwrap_or(0);
    let mut out = String::new();
    for l in lines {
        let level = l.depth.saturating_sub(min_depth);
        if let Some(oid) = l.image {
            if let Some(placeholder) = img_idx.get(&oid) {
                out.push_str(&"  ".repeat(level));
                out.push_str(placeholder);
                out.push('\n');
            }
            continue;
        }
        if l.is_list {
            out.push_str(&"  ".repeat(level));
            out.push_str(&l.bullet);
            out.push(' ');
        }
        out.push_str(&render_runs(&l.runs));
        out.push('\n');
    }
    out.trim_end().to_string()
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

fn data_size(r: &Reader, o: usize, ptype: u8) -> usize {
    match ptype {
        0x01 | 0x02 => 0,
        0x03 => 1,
        0x04 => 2,
        0x05 => 4,
        0x06 => 8,
        0x07 => 4 + r.u32(o) as usize,
        0x08 => 0,
        0x09 => 4,
        0x0A => 0,
        0x0B => 4,
        0x0C => 0,
        0x0D => 4,
        0x10 => 4,
        0x11 => 0,
        _ => 0,
    }
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
fn decode_utf16(b: &[u8]) -> String {
    let pairs = b.len() / 2;
    let mut s = String::with_capacity(pairs);
    let mut units = Vec::with_capacity(pairs);
    for i in 0..pairs {
        units.push(u16::from_le_bytes([b[i * 2], b[i * 2 + 1]]));
    }
    for ch in char::decode_utf16(units) {
        s.push(ch.unwrap_or('\u{fffd}'));
    }
    s
}

// ── Inline PNG recovery ─────────────────────────────────────────────────────

fn scan_pngs(d: &[u8]) -> Vec<Vec<u8>> {
    let mut out = Vec::new();
    let mut i = 0;
    while let Some(rel) = find(&d[i..], PNG_SIG) {
        let start = i + rel;
        // End = the IEND chunk: 'IEND' marker + 4-byte CRC.
        if let Some(erel) = find(&d[start..], b"IEND") {
            let end = (start + erel + 8).min(d.len());
            out.push(d[start..end].to_vec());
            i = end;
        } else {
            break;
        }
    }
    out
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
    walk(&r, root, &mut wo, &mut visited, 0, 0, &mut next_space, &mut cur_rev);
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
    walk(&r, root, &mut wo, &mut visited, 0, 0, &mut next_space, &mut cur_rev);
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
            if objs[i].stp > objs[*e].stp {
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
            .max_by_key(|&&i| objs[i].stp)
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
    walk(&r, root, &mut wo, &mut visited, 0, 0, &mut next_space, &mut cur_rev);
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
            if o.stp > objs[*ent].stp {
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
    walk(&r, root, &mut wo, &mut visited, 0, 0, &mut next_space, &mut cur_rev);
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
        PVal::Other => "other".into(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_non_one_input() {
        let out = import_one_json(b"not a onenote file at all, padding.......................");
        assert!(out.contains("\"ok\":false"));
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
        assert_eq!(office_math_to_latex(s), r"= \frac{L}{R}");
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
        assert_eq!(office_math_to_latex(s), "f(x)");
    }
}
