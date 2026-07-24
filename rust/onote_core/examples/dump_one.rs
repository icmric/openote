// Inspect a real .one file's object graph + properties, for reverse-engineering:
//   cargo run --example dump_one -- path/to/Section.one           (structure dump)
//   cargo run --example dump_one -- path/to/Section.one --import   (importer output)
use onote_core::onenote::{dump_structure, import_one_json};

fn main() {
    let mut args = std::env::args().skip(1);
    let path = args.next().expect("usage: dump_one <file.one> [--import]");
    let mode = args.next();
    let bytes = std::fs::read(&path).expect("read file");

    if mode.as_deref() == Some("--import") {
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
