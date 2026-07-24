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
//! Scope: section title; outline text with **bold/italic/strikethrough**, font
//! family and colour (0x1C04-0C styles resolved via the 0x1E12/0x1E13 run
//! arrays); bulleted/indented lists; **equations** (Cambria-Math runs, Office
//! linear-math Unicode → LaTeX, see [`office_math_to_latex`]); and PNG images at
//! their stored page offsets (0x1C14/0x1C15) and display sizes. A section's
//! pages currently merge into one page (object-space→page mapping is not yet
//! recovered), and ink awaits a sample file to identify its object types.
//! Run `cargo run --example dump_one -- file.one [--import]` to inspect a file.

use serde::Serialize;
use std::collections::{HashMap, HashSet};

// ── MS-ONE property IDs (empirically identified against real files) ────────
/// Outline/paragraph body text, stored UTF-8 (the main content property).
const PID_TEXT_UTF8: u32 = 0x003498;
/// Secondary rich text, stored UTF-16 (diagram labels, some runs).
const PID_TEXT_UTF16: u32 = 0x001C22;
/// Page/section title text (UTF-16).
const PID_TITLE: u32 = 0x001CF3;
/// Vertical offset of an outline on the page (float) — used to order outlines.
const PID_OFFSET_Y: u32 = 0x001C02;

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
const PID_BOLD: u32 = 0x001C04;
const PID_ITALIC: u32 = 0x001C05;
const PID_UNDERLINE: u32 = 0x001C06;
const PID_STRIKE: u32 = 0x001C07;
const PID_RUN_INDEX: u32 = 0x001E12; // TextRunIndex: array of u32 char offsets
const PID_RUN_FORMATTING: u32 = 0x001E13; // TextRunFormatting: style OIDs per run
const PID_PARA_STYLE: u32 = 0x00342C; // paragraph style OID

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
    /// PNG bytes, base64-encoded (so the whole result is a JSON string).
    pub data_base64: String,
}

#[derive(Serialize, Default)]
pub struct TextBox {
    pub x: f32,
    pub y: f32,
    /// Rendered content — one line per paragraph, indented, list items keeping
    /// their original bullet, with **bold**/*italic*/~~strike~~/`{{#hex}}` and
    /// `$$…$$` math inline (Openote's live-Markdown dialect).
    pub markdown: String,
    /// The box's dominant font family (Openote applies it box-level), if known.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub font: Option<String>,
}

#[derive(Serialize, Default)]
pub struct ImportedPage {
    pub title: String,
    pub texts: Vec<TextBox>,
    pub images: Vec<ImportedImage>,
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

fn import_one(bytes: &[u8]) -> ImportedSection {
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
    let mut objs: Vec<Obj> = Vec::new();
    let mut visited = HashSet::new();
    walk(&r, root, &mut objs, &mut visited, 0);

    // Index objects by their own OID (CompactID) so references resolve. First
    // occurrence wins (later revisions repeat the same content).
    let mut by_oid: HashMap<u32, usize> = HashMap::new();
    for (i, o) in objs.iter().enumerate() {
        by_oid.entry(o.own_oid).or_insert(i);
    }

    // Title: first PID_TITLE string found (UTF-16).
    let mut title = String::new();
    for o in &objs {
        if let Some(s) = find_title(&r, o.stp, o.cb) {
            title = s;
            break;
        }
    }

    // Collect title/date lines separately, so they aren't also glued onto the
    // end of the main content outline (they live in the object graph twice).
    let mut title_lines: HashSet<String> = HashSet::new();
    for o in &objs {
        if o.jcid == JCID_TITLE {
            let mut lines = Vec::new();
            let mut guard = HashSet::new();
            collect_tree(&r, o, &objs, &by_oid, 0, &mut lines, &mut guard);
            for l in &lines {
                title_lines.insert(l.plain());
            }
        }
    }

    // Walk each outline / title node as a tree in reading order. The same
    // outline recurs across revisions, so dedup by first line, keeping the
    // fullest copy. Title/date content is dropped from non-title outlines.
    struct Candidate {
        y: f32,
        is_title: bool,
        lines: Vec<Line>,
    }
    let mut best: HashMap<String, Candidate> = HashMap::new();
    let mut order: Vec<String> = Vec::new();
    for o in &objs {
        if o.jcid != JCID_OUTLINE && o.jcid != JCID_TITLE {
            continue;
        }
        let is_title = o.jcid == JCID_TITLE;
        let mut lines: Vec<Line> = Vec::new();
        let mut guard: HashSet<usize> = HashSet::new();
        collect_tree(&r, o, &objs, &by_oid, 0, &mut lines, &mut guard);
        if !is_title {
            lines.retain(|l| !title_lines.contains(&l.plain()));
        }
        if lines.is_empty() {
            continue;
        }
        let key = lines[0].plain();
        let y = find_offset_y(&r, o.stp, o.cb);
        match best.get(&key) {
            Some(prev) if prev.lines.len() >= lines.len() => {}
            _ => {
                if !best.contains_key(&key) {
                    order.push(key.clone());
                }
                best.insert(key, Candidate { y, is_title, lines });
            }
        }
    }
    let mut cands: Vec<&Candidate> = order.iter().filter_map(|k| best.get(k)).collect();
    // Titles first (top of page), then content by vertical offset.
    cands.sort_by(|a, b| {
        b.is_title
            .cmp(&a.is_title)
            .then(a.y.partial_cmp(&b.y).unwrap_or(std::cmp::Ordering::Equal))
    });
    // Lay the text boxes down the left; the title sits above the content.
    let mut texts = Vec::new();
    let mut ty = 40.0f32;
    for c in cands {
        texts.push(TextBox {
            x: 44.0,
            y: ty,
            markdown: outline_markdown(&c.lines),
            font: dominant_font(&c.lines),
        });
        let line_count = c.lines.len() as f32;
        ty += line_count * 24.0 + 48.0;
    }

    // Images: correlate each inline PNG to its image object by natural pixel
    // size, so we can place it at the object's real page coordinates.
    let img_objs: Vec<&Obj> = objs.iter().filter(|o| o.jcid == JCID_IMAGE).collect();
    let mut images = Vec::new();
    let mut seen_img = HashSet::new();
    let mut fallback_y = 40.0f32;
    for (i, png) in scan_pngs(bytes).into_iter().enumerate() {
        if !seen_img.insert((png.len(), png.first().copied(), png.last().copied())) {
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
        // Find the image object whose natural size matches this PNG (±2 px).
        let matched = img_objs.iter().find(|o| {
            let nw = (get_f32(&r, o.stp, o.cb, PID_IMG_NATW) * UNIT_PX).round() as i64;
            let nh = (get_f32(&r, o.stp, o.cb, PID_IMG_NATH) * UNIT_PX).round() as i64;
            (nw - w as i64).abs() <= 2 && (nh - h as i64).abs() <= 2
        });
        let (mut x, mut y, mut dw, mut dh) = (0.0, 0.0, w as f32, h as f32);
        let mut positioned = false;
        if let Some(o) = matched {
            let px = get_f32(&r, o.stp, o.cb, PID_IMG_POSX);
            let py = get_f32(&r, o.stp, o.cb, PID_IMG_POSY);
            let ddw = get_f32(&r, o.stp, o.cb, PID_IMG_DISPW) * UNIT_PX;
            let ddh = get_f32(&r, o.stp, o.cb, PID_IMG_DISPH) * UNIT_PX;
            if ddw > 1.0 {
                dw = ddw;
            }
            if ddh > 1.0 {
                dh = ddh;
            }
            if px != 0.0 || py != 0.0 {
                x = 44.0 + px * UNIT_PX;
                y = 40.0 + py * UNIT_PX;
                positioned = true;
            }
        }
        if !positioned {
            // No stored offset — stack in a right-hand column so it never lands
            // on top of the title/content.
            x = 720.0;
            y = fallback_y;
            fallback_y += dh + 24.0;
        }
        images.push(ImportedImage {
            name: format!("onenote-image-{}.png", i + 1),
            x,
            y,
            disp_w: dw,
            disp_h: dh,
            width: w,
            height: h,
            data_base64: base64_encode(&png),
        });
    }

    if title.is_empty() {
        title = "Imported page".into();
    }
    ImportedSection {
        ok: true,
        error: None,
        pages: vec![ImportedPage { title, texts, images }],
    }
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

/// One object: its own CompactID (for reference resolution), its type, and the
/// location of its property set.
struct Obj {
    own_oid: u32,
    jcid: u32,
    stp: usize,
    cb: usize,
}

/// Walk the file-node graph, collecting every object declaration as an [Obj].
fn walk(r: &Reader, fcr: Fcr, objs: &mut Vec<Obj>, visited: &mut HashSet<u64>, depth: usize) {
    // The `visited` set stops cycles, but a crafted file can still nest
    // distinct sub-lists thousands deep. Cap recursion depth (like
    // `collect_inner`) so a malicious `.one` can't overflow the stack — an
    // abort would unwind past the FFI `catch_unwind` and crash the host.
    if depth > 64 || fcr.is_nil() || fcr.cb == 0 || !visited.insert(fcr.stp) {
        return;
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
                    walk(r, sub, objs, visited, depth + 1);
                }
            } else if base_type == 1 {
                // Object declaration: BlobRef → ObjectSpaceObjectPropSet, then
                // ObjectDeclaration2Body { oid(CompactID), jcid, flags }.
                if let Some(blob) = node_ref(r, o + 4, stp_fmt, cb_fmt) {
                    let body = o + 4 + ref_size(stp_fmt, cb_fmt);
                    objs.push(Obj {
                        own_oid: r.u32(body),
                        jcid: r.u32(body + 4),
                        stp: blob.stp as usize,
                        cb: blob.cb as usize,
                    });
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
    font: Option<String>,
    size_half_pt: u32, // 0 = unset
    color: u32,        // 0 = unset; else 0x00BBGGRR-ish (FF000000 = auto/black)
    is_math: bool,     // font == "Cambria Math"
}

/// Read a style object (00020001 / 0012004D) into a [Style].
fn read_style(r: &Reader, o: &Obj) -> Style {
    let ps = read_propset(r, o.stp, o.cb);
    let font = ps.utf16(PID_FONT).filter(|f| !f.is_empty());
    let is_math = font.as_deref() == Some("Cambria Math");
    Style {
        bold: ps.flag(PID_BOLD),
        italic: ps.flag(PID_ITALIC),
        underline: ps.flag(PID_UNDERLINE),
        strike: ps.flag(PID_STRIKE),
        font,
        size_half_pt: ps.u32(PID_FONT_SIZE).unwrap_or(0),
        color: ps.u32(PID_FONT_COLOR).unwrap_or(0),
        is_math,
    }
}

fn resolve_style(r: &Reader, objs: &[Obj], by_oid: &HashMap<u32, usize>, oid: u32) -> Style {
    by_oid
        .get(&oid)
        .map(|&i| read_style(r, &objs[i]))
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
fn styled_runs(r: &Reader, o: &Obj, objs: &[Obj], by_oid: &HashMap<u32, usize>) -> Vec<SRun> {
    let ps = read_propset(r, o.stp, o.cb);
    let text = match ps.run_text() {
        // Strip only a trailing NUL terminator so run-index offsets stay valid.
        Some(t) => t.trim_end_matches('\0').to_string(),
        None => return Vec::new(),
    };
    let base = ps
        .oids(PID_PARA_STYLE)
        .first()
        .map(|&oid| resolve_style(r, objs, by_oid, oid))
        .unwrap_or_default();
    let fmt = ps.oids(PID_RUN_FORMATTING);
    let bounds = parse_run_index(ps.get(PID_RUN_INDEX));
    let chars: Vec<char> = text.chars().collect();

    // Single style (or a shape we can't split cleanly): one merged run.
    if fmt.len() <= 1 || bounds.len() + 1 != fmt.len() {
        let mut st = base;
        for &f in &fmt {
            st = merge_style(&st, &resolve_style(r, objs, by_oid, f));
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
        let st = merge_style(&base, &resolve_style(r, objs, by_oid, fmt[i]));
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
    objs: &[Obj],
    by_oid: &HashMap<u32, usize>,
    depth: usize,
    out: &mut Vec<Line>,
    guard: &mut HashSet<usize>,
) {
    collect_inner(r, o, objs, by_oid, depth, false, String::new(), out, guard);
}

#[allow(clippy::too_many_arguments)]
fn collect_inner(
    r: &Reader,
    o: &Obj,
    objs: &[Obj],
    by_oid: &HashMap<u32, usize>,
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
        if let Some(b) = list_bullet(r, &children, objs, by_oid) {
            ctx = true;
            bullet = b;
        } else {
            ctx = false;
        }
    }

    if matches!(o.jcid, JCID_RICHTEXT | JCID_RICHTEXT_RUN) {
        let runs = styled_runs(r, o, objs, by_oid);
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
                    });
                }
            } else {
                out.push(Line {
                    depth,
                    is_list: ctx,
                    bullet: bullet.clone(),
                    runs,
                    math: None,
                });
            }
        }
    }

    for cid in children {
        if let Some(&idx) = by_oid.get(&cid) {
            let child = &objs[idx];
            let deeper = matches!(
                child.jcid,
                JCID_OUTLINE | JCID_OUTLINE_ELEMENT | JCID_RICHTEXT | JCID_OUTLINE_GROUP
            );
            collect_inner(
                r,
                child,
                objs,
                by_oid,
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
fn list_bullet(
    r: &Reader,
    children: &[u32],
    objs: &[Obj],
    by_oid: &HashMap<u32, usize>,
) -> Option<String> {
    for cid in children {
        if let Some(&idx) = by_oid.get(cid) {
            let c = &objs[idx];
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

/// Full property-set parse with OID-stream resolution for reference properties.
/// The OID stream (declared in the header) is consumed in property order: an
/// ObjectID (0x08) takes one entry, an ArrayOfObjectIDs (0x09) takes `count`.
/// ObjectSpace/Context reference streams are skipped (not needed for content).
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
    if !osid_absent {
        let h2 = r.u32(o);
        o += 4 + (h2 & 0x00FF_FFFF) as usize * 4;
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
fn dominant_font(lines: &[Line]) -> Option<String> {
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

/// Render collected lines as indented Markdown for Openote's renderer. List
/// items keep their original bullet; non-list paragraphs stay flush-left (bold
/// runs become `**…**` — the OneNote heading look). Math paragraphs emit as
/// `$$…$$` so Openote renders them as equations inline. Normalised so the
/// shallowest line sits at the left margin; 2 spaces per indent level.
fn outline_markdown(lines: &[Line]) -> String {
    let min_depth = lines.iter().map(|l| l.depth).min().unwrap_or(0);
    let mut out = String::new();
    for l in lines {
        let level = l.depth.saturating_sub(min_depth);
        let indent = "  ".repeat(level);
        if let Some(latex) = &l.math {
            out.push_str(&indent);
            out.push_str("$$");
            out.push_str(latex);
            out.push_str("$$\n");
            continue;
        }
        if l.is_list {
            out.push_str(&indent);
            out.push_str(&l.bullet);
            out.push(' ');
        }
        out.push_str(&render_runs(&l.runs));
        out.push('\n');
    }
    out.trim_end().to_string()
}

/// First title string (PID_TITLE, UTF-16) in an object, if present.
fn find_title(r: &Reader, start: usize, len: usize) -> Option<String> {
    for (pid, bytes) in string_props(r, start, len) {
        if pid == PID_TITLE {
            let s = decode_utf16(&bytes);
            let s = s.trim_matches(|c: char| c == '\0').trim().to_string();
            if !s.is_empty() {
                return Some(s);
            }
        }
    }
    None
}

/// The float value of PID_OFFSET_Y in an object (0.0 if absent).
fn find_offset_y(r: &Reader, start: usize, len: usize) -> f32 {
    get_f32(r, start, len, PID_OFFSET_Y)
}

/// The float (type-5) value of a property in an object, 0.0 if absent.
fn get_f32(r: &Reader, start: usize, len: usize, want: u32) -> f32 {
    for (pid, ty, at) in scalar_props(r, start, len) {
        if pid == want && ty == 0x05 {
            return f32::from_bits(r.u32(at));
        }
    }
    0.0
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

/// (property_id, type, data_offset) for each fixed-size scalar property.
fn scalar_props(r: &Reader, start: usize, len: usize) -> Vec<(u32, u8, usize)> {
    let mut out = Vec::new();
    each_prop(r, start, len, |pid, ptype, _b, data_o, _end| {
        out.push((pid, ptype, data_o));
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
    let mut objs: Vec<Obj> = Vec::new();
    let mut visited = HashSet::new();
    walk(&r, root, &mut objs, &mut visited, 0);

    // JCID histogram.
    let mut hist: std::collections::BTreeMap<u32, usize> = Default::default();
    for o in &objs {
        *hist.entry(o.jcid).or_default() += 1;
    }
    let mut out = String::new();
    out.push_str(&format!("objects={}\nJCID histogram:\n", objs.len()));
    for (j, n) in &hist {
        out.push_str(&format!("  {:08X} {:<14} x{}\n", j, jcid_name(*j), n));
    }

    for (i, o) in objs.iter().enumerate() {
        out.push_str(&format!(
            "\n#{i} jcid={:08X} {} oid={:08X} stp={} cb={}\n",
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
    fn office_math_strips_invisibles_when_no_structure() {
        // Function application (U+2061) and math letters, no fraction.
        let s = "\u{1D453}\u{2061}(\u{1D465})"; // f(x)
        assert_eq!(office_math_to_latex(s), "f(x)");
    }
}
