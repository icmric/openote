//! Importer for OneNote `.onepkg` notebook packages.
//!
//! A `.onepkg` is a Microsoft Cabinet archive (typically LZX-compressed)
//! containing the notebook's `.one` section files (plus `.onetoc2` tables of
//! contents, which carry ordering/metadata we don't need — the sections are
//! self-contained). Each `.one` inside is parsed with the section importer
//! ([`crate::onenote`]); a file stored under a subdirectory belonged to a
//! **section group**, preserved via the `group` field.

use serde::Serialize;
use std::io::Cursor;

use crate::onenote::{import_one, ImportedSection};

/// Cap per-file decompressed size (a hostile cabinet can otherwise expand
/// without bound — the classic zip-bomb).
const MAX_SECTION_BYTES: u64 = 256 * 1024 * 1024;

/// Cap the TOTAL decompressed bytes we hold at once.
///
/// Single-pass folder extraction (the import speed-up) keeps every section's
/// bytes in memory simultaneously because the parse phase runs in parallel over
/// them, so the per-section cap above is no longer the whole story: a cabinet
/// declaring 65k sections could still exhaust memory one legal section at a
/// time. Collection stops at this budget and the skipped sections are reported.
const MAX_TOTAL_BYTES: u64 = 512 * 1024 * 1024;

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
    /// Sections present in the package that could NOT be read, by name.
    ///
    /// These used to vanish: the result still said `ok: true` and the user
    /// simply received fewer sections than their notebook contained, with
    /// nothing said. The importer surfaces this so a partial import announces
    /// itself.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub failed: Vec<String>,
}

fn fail(msg: &str) -> ImportedPackage {
    ImportedPackage {
        ok: false,
        error: Some(msg.into()),
        sections: vec![],
        failed: vec![],
    }
}

/// Parse a `.onepkg` notebook package into structured content, as JSON.
pub fn import_onepkg_json(bytes: &[u8]) -> String {
    // Serialization runs INSIDE the guard — a panic there would otherwise
    // unwind across the C ABI (undefined behaviour).
    std::panic::catch_unwind(|| {
        let pkg = import_onepkg(bytes);
        serde_json::to_string(&pkg).unwrap_or_else(|_| "{\"ok\":false}".into())
    })
    .unwrap_or_else(|_| {
        "{\"ok\":false,\"error\":\"failed to parse .onepkg (unexpected structure)\"}"
            .into()
    })
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
    let mut failed: Vec<String> = Vec::new();
    let mut budget = MAX_TOTAL_BYTES;
    for (fi, files) in folder_files.iter().enumerate() {
        if !files.iter().any(|(n, _, _)| n.to_ascii_lowercase().ends_with(".one")) {
            continue; // folder holds only metadata (.onetoc2 etc.)
        }
        // Cap the folder stream at the declared extent, and never beyond one
        // section's worth of slack. Both `uncompressed_offset` and
        // `uncompressed_size` come from attacker-controlled headers, so the cap
        // has to be ours, not theirs.
        let extent = files
            .iter()
            .map(|(_, off, size)| off.saturating_add(*size))
            .max()
            .unwrap_or(0)
            .min(MAX_SECTION_BYTES);
        let data = match cabinet.read_folder_data(fi, extent) {
            Ok(d) => d,
            Err(_) => {
                // The patched reader hands back what it managed to decompress,
                // so an error here means nothing usable at all.
                failed.extend(
                    files
                        .iter()
                        .filter(|(n, _, _)| n.to_ascii_lowercase().ends_with(".one"))
                        .map(|(n, _, _)| n.clone()),
                );
                continue;
            }
        };
        for (name, off, size) in files {
            if !name.to_ascii_lowercase().ends_with(".one") {
                continue;
            }
            if *size > MAX_SECTION_BYTES || *size > budget {
                failed.push(name.clone()); // too big, or the budget is spent
                continue;
            }
            let (start, end) = (*off as usize, off.saturating_add(*size) as usize);
            if end > data.len() {
                // A truncated (or dishonestly-declared) folder: only part of
                // this section is present. Say so instead of dropping it.
                failed.push(name.clone());
                continue;
            }
            budget -= *size;
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
            // Damaged or unsupported entry — import the rest, but RECORD it so
            // the user is told their notebook came across incomplete.
            failed.push(name.clone());
            continue;
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
    // Report by section name (the stem), matching what the user sees in the app.
    let failed = failed
        .iter()
        .map(|n| {
            let norm = n.replace('\\', "/");
            let file = norm.rsplit('/').next().unwrap_or(&norm).to_string();
            file.strip_suffix(".one").unwrap_or(&file).to_string()
        })
        .collect();
    ImportedPackage { ok: true, error: None, sections, failed }
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
