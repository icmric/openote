//! Importer for OneNote `.onepkg` notebook packages.
//!
//! A `.onepkg` is a Microsoft Cabinet archive (typically LZX-compressed)
//! containing the notebook's `.one` section files (plus `.onetoc2` tables of
//! contents, which carry ordering/metadata we don't need — the sections are
//! self-contained). Each `.one` inside is parsed with the section importer
//! ([`crate::onenote`]); a file stored under a subdirectory belonged to a
//! **section group**, preserved via the `group` field.

use serde::Serialize;
use std::io::{Cursor, Read};

use crate::onenote::{import_one, ImportedSection};

/// Cap per-file decompressed size (a hostile cabinet can otherwise expand
/// without bound — the classic zip-bomb).
const MAX_SECTION_BYTES: u64 = 256 * 1024 * 1024;

#[derive(Serialize)]
pub struct PackageSection {
    /// Section display name (the file stem).
    pub name: String,
    /// Section-group path when the file sat in a subdirectory (`None` = root).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub group: Option<String>,
    /// The parsed section, same shape as a single-file `.one` import.
    pub section: ImportedSection,
}

#[derive(Serialize)]
pub struct ImportedPackage {
    pub ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
    pub sections: Vec<PackageSection>,
}

fn fail(msg: &str) -> ImportedPackage {
    ImportedPackage { ok: false, error: Some(msg.into()), sections: vec![] }
}

/// Parse a `.onepkg` notebook package into structured content, as JSON.
pub fn import_onepkg_json(bytes: &[u8]) -> String {
    let pkg = match std::panic::catch_unwind(|| import_onepkg(bytes)) {
        Ok(p) => p,
        Err(_) => fail("failed to parse .onepkg (unexpected structure)"),
    };
    serde_json::to_string(&pkg).unwrap_or_else(|_| "{\"ok\":false}".into())
}

fn import_onepkg(bytes: &[u8]) -> ImportedPackage {
    let mut cabinet = match cab::Cabinet::new(Cursor::new(bytes)) {
        Ok(c) => c,
        Err(e) => return fail(&format!("not a OneNote package (cabinet): {e}")),
    };

    // Collect entry names first — reading borrows the cabinet mutably.
    let names: Vec<String> = cabinet
        .folder_entries()
        .flat_map(|f| f.file_entries().map(|fe| fe.name().to_string()))
        .collect();

    let mut sections = Vec::new();
    for name in names {
        let lower = name.to_ascii_lowercase();
        if !lower.ends_with(".one") {
            continue; // .onetoc2 and any stray metadata files
        }
        let mut data = Vec::new();
        match cabinet.read_file(&name) {
            Ok(reader) => {
                if reader.take(MAX_SECTION_BYTES).read_to_end(&mut data).is_err() {
                    continue;
                }
            }
            Err(_) => continue,
        }
        let section = import_one(&data);
        if !section.ok {
            continue; // damaged or unsupported entry — import the rest
        }
        // "Group/Sub/Section.one" → group "Group/Sub", name "Section".
        let norm = name.replace('\\', "/");
        let (group, file) = match norm.rsplit_once('/') {
            Some((dir, file)) if !dir.is_empty() => (Some(dir.to_string()), file),
            _ => (None, norm.as_str()),
        };
        let stem = file.strip_suffix(".one").unwrap_or(file);
        sections.push(PackageSection {
            name: if stem.is_empty() { "Section".into() } else { stem.to_string() },
            group,
            section,
        });
    }

    if sections.is_empty() {
        return fail("package contained no readable .one sections");
    }
    ImportedPackage { ok: true, error: None, sections }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_non_cabinet_input() {
        let out = import_onepkg_json(b"definitely not a cabinet file............");
        assert!(out.contains("\"ok\":false"));
    }
}
