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

    // Phase 1 (sequential — LZX folders are one continuous stream): decompress
    // each folder ONCE and slice the .one payloads out at their offsets.
    // Per-file `read_file` re-decompresses the folder prefix for every file
    // (quadratic): on a real 27-file/85MB notebook that was ~35s of a ~41s
    // import; a single pass is the folder's actual size.
    let folder_files: Vec<Vec<(String, u64, u64)>> = cabinet
        .folder_entries()
        .map(|f| {
            f.file_entries()
                .map(|fe| {
                    (
                        fe.name().to_string(),
                        fe.uncompressed_offset() as u64,
                        fe.uncompressed_size() as u64,
                    )
                })
                .collect()
        })
        .collect();
    let mut payloads: Vec<(String, Vec<u8>)> = Vec::new();
    for (fi, files) in folder_files.iter().enumerate() {
        if !files.iter().any(|(n, _, _)| n.to_ascii_lowercase().ends_with(".one")) {
            continue; // folder holds only metadata (.onetoc2 etc.)
        }
        // Cap the folder stream at the declared extent (zip-bomb guard).
        let extent = files
            .iter()
            .map(|(_, off, size)| off + size)
            .max()
            .unwrap_or(0)
            .min(MAX_SECTION_BYTES * 4);
        let Ok(data) = cabinet.read_folder_data(fi, extent) else {
            continue;
        };
        for (name, off, size) in files {
            if !name.to_ascii_lowercase().ends_with(".one") || *size > MAX_SECTION_BYTES {
                continue;
            }
            let (start, end) = (*off as usize, (*off + *size) as usize);
            if end > data.len() {
                continue; // truncated folder — skip what we can't slice
            }
            payloads.push((name.clone(), data[start..end].to_vec()));
        }
    }

    // Phase 2 (parallel): each .one parses independently — fan out across
    // cores. This is the dominant cost of a big notebook import (measured ~80%
    // of wall time), and parallelising it cut a 324-page import's parse from
    // ~42s to a fraction. Per-section catch_unwind means one damaged section
    // is skipped instead of failing the whole package.
    let workers = std::thread::available_parallelism()
        .map(|p| p.get())
        .unwrap_or(4)
        .min(payloads.len().max(1));
    let next = std::sync::atomic::AtomicUsize::new(0);
    let slots: Vec<std::sync::Mutex<Option<ImportedSection>>> =
        payloads.iter().map(|_| std::sync::Mutex::new(None)).collect();
    std::thread::scope(|s| {
        for _ in 0..workers {
            s.spawn(|| loop {
                let i = next.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                if i >= payloads.len() {
                    break;
                }
                let parsed = std::panic::catch_unwind(std::panic::AssertUnwindSafe(
                    || import_one(&payloads[i].1),
                ));
                if let Ok(section) = parsed {
                    if section.ok {
                        *slots[i].lock().unwrap() = Some(section);
                    }
                }
            });
        }
    });

    let mut sections = Vec::new();
    for (i, (name, _)) in payloads.iter().enumerate() {
        let Some(section) = slots[i].lock().unwrap().take() else {
            continue; // damaged or unsupported entry — import the rest
        };
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
