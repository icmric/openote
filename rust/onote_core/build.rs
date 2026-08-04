//! Stamp the built library with an identity you can read from inside the app.
//!
//! **Why this exists.** The core ships as a compiled library beside the
//! executable, and the app loads whatever is there. So "my source is on the
//! right branch" and "the behaviour I am seeing is that source" are two
//! different claims, and the second one has been wrong several times in this
//! project's history — the stale-DLL trap that `INTEGRATION.md` warns about and
//! that has cost whole sessions chasing fixes that were never running.
//!
//! Git tells you about the source. Nothing told you about the library. Now the
//! library says when it was built and from which commit, the app shows it, and
//! the question is answered by looking rather than by guessing.
//!
//! No dependencies: this crate is the permissive tier (ADR-0005) and stays
//! that way, so the timestamp is raw epoch seconds and the app formats it.

use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

fn main() {
    // Re-stamp when the source changes, and only then — stamping on every
    // no-op build would relink the library each time for nothing.
    println!("cargo:rerun-if-changed=src");
    println!("cargo:rerun-if-changed=Cargo.toml");

    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);

    // Best effort: a checkout without git, or a source tarball, still builds.
    let commit = Command::new("git")
        .args(["rev-parse", "--short=8", "HEAD"])
        .output()
        .ok()
        .filter(|o| o.status.success())
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "nogit".to_string());

    println!("cargo:rustc-env=ONOTE_CORE_BUILD={secs} {commit}");
}
