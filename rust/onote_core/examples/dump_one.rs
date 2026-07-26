// Inspect a real .one file's object graph + properties, for reverse-engineering:
//   cargo run --example dump_one -- path/to/Section.one           (structure dump)
//   cargo run --example dump_one -- path/to/Section.one --import   (importer output)
use onote_core::onenote::{
    dump_ink, dump_revisions, dump_sections, dump_structure, import_one_json,
};

fn main() {
    let mut args = std::env::args().skip(1);
    let path = args.next().expect("usage: dump_one <file.one> [--import|--ink]");
    let mode = args.next();
    let bytes = std::fs::read(&path).expect("read file");

    if mode.as_deref() == Some("--pkg") {
        let json = onote_core::onepkg::import_onepkg_json(&bytes);
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        let filter = args.next(); // optional section-name substring
        println!("ok={}", v["ok"]);
        for s in v["sections"].as_array().cloned().unwrap_or_default() {
            let name = s["name"].as_str().unwrap_or("");
            if let Some(f) = &filter {
                if !name.to_lowercase().contains(&f.to_lowercase()) {
                    continue;
                }
            }
            let pages = s["section"]["pages"].as_array().cloned().unwrap_or_default();
            println!(
                "section {:?} group={:?} pages={}",
                name,
                s["group"].as_str(),
                pages.len()
            );
            for p in &pages {
                let lvl = p["level"].as_u64().unwrap_or(0) as usize;
                println!(
                    "  {}{:?}  [boxes={} img={} ink={}]",
                    "    ".repeat(lvl),
                    p["title"].as_str().unwrap_or(""),
                    p["boxes"].as_array().map(|a| a.len()).unwrap_or(0),
                    p["images"].as_array().map(|a| a.len()).unwrap_or(0),
                    p["ink"].as_array().map(|a| a.len()).unwrap_or(0),
                );
            }
        }
    } else if mode.as_deref() == Some("--pkgink") {
        // Per-stroke ink diagnostics for one section: point count + bbox, so
        // runaway (giant-scribble) or dropped strokes stand out.
        let json = onote_core::onepkg::import_onepkg_json(&bytes);
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        let filter = args.next().unwrap_or_default().to_lowercase();
        for s in v["sections"].as_array().cloned().unwrap_or_default() {
            if !s["name"].as_str().unwrap_or("").to_lowercase().contains(&filter) {
                continue;
            }
            for p in s["section"]["pages"].as_array().cloned().unwrap_or_default() {
                let ink = p["ink"].as_array().cloned().unwrap_or_default();
                if ink.is_empty() {
                    continue;
                }
                // True runaways: importer x/y span exceeds ~700px.
                let mut runaways = 0;
                let mut worst = (0.0f64, 0usize, 0usize);
                for st in &ink {
                    let xs: Vec<f64> = st["x"].as_array().unwrap().iter().map(|v| v.as_f64().unwrap()).collect();
                    let ys: Vec<f64> = st["y"].as_array().unwrap().iter().map(|v| v.as_f64().unwrap()).collect();
                    let w = xs.iter().cloned().fold(f64::MIN, f64::max) - xs.iter().cloned().fold(f64::MAX, f64::min);
                    let h = ys.iter().cloned().fold(f64::MIN, f64::max) - ys.iter().cloned().fold(f64::MAX, f64::min);
                    let span = w.max(h);
                    if span > 700.0 { runaways += 1; }
                    if span > worst.0 { worst = (span, xs.len(), 0); }
                }
                let flag = if runaways > 0 { format!("  <<< {runaways} RUNAWAY, worst span={:.0}px pts={}", worst.0, worst.1) } else { String::new() };
                println!("PAGE {:?} strokes={}{}", p["title"].as_str().unwrap_or(""), ink.len(), flag);
            }
        }
    } else if mode.as_deref() == Some("--extract") {
        // Write the first .one whose name matches <substr> to <outpath>.
        let sub = args.next().unwrap_or_default().to_lowercase();
        let out = args.next().expect("usage: --extract <substr> <outpath>");
        let mut cab = cab::Cabinet::new(std::io::Cursor::new(&bytes[..])).unwrap();
        let names: Vec<String> = cab
            .folder_entries()
            .flat_map(|f| f.file_entries().map(|fe| fe.name().to_string()))
            .collect();
        let name = names
            .iter()
            .find(|n| n.to_lowercase().contains(&sub) && n.to_lowercase().ends_with(".one"))
            .unwrap_or_else(|| panic!("no .one matching {sub:?}"));
        let mut data = Vec::new();
        std::io::Read::read_to_end(&mut cab.read_file(name).unwrap(), &mut data).unwrap();
        std::fs::write(&out, &data).unwrap();
        println!("extracted {name:?} ({} bytes) → {out}", data.len());
    } else if mode.as_deref() == Some("--revs") {
        let sp: usize = args.next().and_then(|s| s.parse().ok()).unwrap_or(2);
        println!("{}", dump_revisions(&bytes, sp));
    } else if mode.as_deref() == Some("--sections") {
        println!("{}", dump_sections(&bytes));
    } else if mode.as_deref() == Some("--json") {
        // Raw single-object importer JSON (machine-parseable).
        println!("{}", import_one_json(&bytes));
    } else if mode.as_deref() == Some("--ink") {
        println!("{}", dump_ink(&bytes, 100000));
    } else if mode.as_deref() == Some("--import") {
        let json = import_one_json(&bytes);
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        let pages = v["pages"].as_array().cloned().unwrap_or_default();
        println!("ok={} pages={}", v["ok"], pages.len());
        for (i, p) in pages.iter().enumerate() {
            println!("\n== page {} title={:?} ==", i + 1, p["title"].as_str().unwrap_or(""));
            println!("{}", serde_json::to_string_pretty(p).unwrap());
        }
    } else {
        println!("{}", dump_structure(&bytes));
    }
}
