# onote-core

The Rust core for Openote. This is the seam described in
`app/lib/core/engine.dart` and [ADR-0002](../../docs/adr/ADR-0002-crdt-library.md):
the place where the fast, portable, well-tested parts of the document model
live, shared identically across every platform and exposed to the Flutter app
through [`flutter_rust_bridge`](https://cjycode.com/flutter_rust_bridge/).

It ships **nothing that end users must install.** The core is compiled at build
time into a small native library that links into the app; users still get a
plain executable with no Rust runtime requirement. This crate is a build-time
dependency, not a runtime one.

## What's in it today

| Module | Responsibility |
| --- | --- |
| `mirror` | The page **mirror** model (the open glass-box JSON from File Format Spec §4) and a deterministic, conflict-free `merge` of two page snapshots — the seed of cross-device sync (SYNC-1/2). |
| `ids` | A dependency-free FNV-1a content hash for cheap "did this page change?" sync gating. |
| `onenote` | A reverse-engineered MS-ONESTORE/MS-ONE reader (OPEN-8): pages in tab order with subpage levels, **separate text boxes at true positions** with styling, lists, in-flow + floating images, Office-linear-math → LaTeX equations, and MS-ISF ink with pressure. Also the `dump_*` diagnostics used to reverse-engineer the format. |
| `onepkg` | Whole-notebook `.onepkg` import: LZX cabinet extraction (single-pass per folder) + **parallel per-section parsing** across cores. |
| `ffi` | The C-ABI shim the app links today via `dart:ffi` (see `app/lib/core/onote_ffi.dart`). Every entry point catches panics so nothing unwinds across the ABI. |
| `api` | The thin surface `flutter_rust_bridge` turns into Dart bindings (opt-in, for a future FRB integration). |

### Vendored dependency: `vendor/cab`

`vendor/cab` is a **copy of the MIT-licensed [`cab`](https://crates.io/crates/cab) 0.6.0 crate with a two-method patch**, wired in via `[patch.crates-io]` in `Cargo.toml`. It adds `FileEntry::uncompressed_offset()` and `Cabinet::read_folder_data()`.

**Why:** a `.onepkg` is a single LZX cabinet *folder* holding every section, and upstream's `read_file()` restarts decompression from the folder start for each file — quadratic. On a real 27-section / 85 MB notebook that was ~35 s of a ~41 s import. Decompressing each folder once and slicing sections out at their offsets removed almost all of it.

Both added methods are marked with `(Openote patch)` comments, and upstream's `LICENSE` is retained in the vendor directory. If you bump `cab`, re-apply the patch (or upstream it) rather than dropping the `[patch.crates-io]` entry — the import will silently get much slower. The full delta, the invariant it depends on, and the update procedure are written up in [`vendor/cab/OPENOTE-PATCH.md`](vendor/cab/OPENOTE-PATCH.md) so nobody has to diff against crates.io to discover them.

### Licence, and the provenance of the format knowledge

This crate is **Apache-2.0** ([`LICENSE`](LICENSE), [`NOTICE`](NOTICE)) — deliberately *not* the application's AGPL-3.0. It is the permissive tier of [ADR-0005](../../docs/adr/ADR-0005-licensing.md): anyone should be able to read and write `.onote` files from any software, including proprietary software. **Adding a copyleft dependency to this crate would silently break that promise** — treat it as an invariant, and see [LICENSING.md](../../LICENSING.md).

The OneNote reader implements Microsoft's published **[MS-ONESTORE]** and **[MS-ONE]** open specifications. During development it was cross-checked against [`onenote.rs`](https://github.com/msiemens/onenote.rs), an independent third-party reference implementation under **MPL-2.0**.

That is a *reference consulted, not a dependency*: no MPL-2.0 code is copied into or linked by this crate. It previously sat in-tree as `onenote-ref`, a broken git submodule (a gitlink with no `.gitmodules`, so every fresh clone got an empty directory and a permanently dirty `git status`) — and, more to the point, MPL-2.0 code parked inside what is now an Apache-2.0 crate. It has been removed and replaced by this note. If you want its `.one` test samples, clone it separately outside the tree.

**Release profile note:** `opt-level = 3` (not `"z"`) — size-optimising measurably slowed LZX decompression and parsing. `panic = "unwind"` is **required**: the FFI layer's `catch_unwind` guards depend on it.

`merge` is intentionally CRDT-*shaped* — commutative, associative, and
idempotent over the snapshot-exchange model — so the Loro-backed engine
(ADR-0002) can replace it behind the same API without touching the Dart call
sites. It stops deliberately short of inventing a second tombstone scheme for
deletions; that is Loro's job when it lands.

## Verify your toolchain (no Flutter needed)

The default build has no bridge dependency, so this is all it takes to confirm
Rust is set up correctly:

```bash
cd rust/onote_core
cargo test
```

You should see **`26 passed`**. That exercises the merge semantics
(newer-wins, union, idempotence, order-independent commutativity + tie-break,
forward-compatible field round-trip), the content hash against known FNV-1a
vectors and field-order independence, the FFI round-trip, and the `.one` parser
(varint/multi-byte stream decoding, math-alphanumeric folding, Office-math →
LaTeX including prose spacing, and cabinet rejection of non-cabinet input).

### Diagnostics (reverse-engineering aids)

The `dump_one` example is the tool the parser was built with — invaluable when a
real notebook imports wrongly:

```bash
cargo run --release --example dump_one -- <file.one>              # object/property structure
cargo run --release --example dump_one -- <file.one> --import     # importer JSON, per page
cargo run --release --example dump_one -- <file.one> --sections   # section→page correlation
cargo run --release --example dump_one -- <file.one> --revs       # per-revision ExGuid resolution
cargo run --release --example dump_one -- <file.one> --ink        # per-stroke ink diagnostics
cargo run --release --example dump_one -- <pkg.onepkg> --pkg      # whole-package page tree
cargo run --release --example dump_one -- <pkg.onepkg> --timing   # extract vs parse timing
```

## Wiring the Flutter bindings (opt-in)

This is only needed when you want the Dart app to actually call into Rust; the
app compiles and runs today without it via the pure-Dart `MirrorEngine`.

1. Install the codegen and the runtime helper:

   ```bash
   cargo install flutter_rust_bridge_codegen
   ```

2. Generate the Dart + Rust glue from the annotated `api.rs`:

   ```bash
   flutter_rust_bridge_codegen generate \
     --rust-input crate::api \
     --rust-root rust/onote_core \
     --dart-output app/lib/core/gen
   ```

3. Build the core with the bridge feature so the `#[frb]` annotations take
   effect and the native library is produced:

   ```bash
   cargo build --release --features bridge
   ```

4. Add the platform build hook (cargokit) so `flutter build` compiles and
   bundles the library automatically per OS. Track this in
   [ADR-0002](../../docs/adr/ADR-0002-crdt-library.md) once the spike is green.

5. Swap `MirrorEngine` for a `RustEngine` that calls `mergePageMirrors` /
   `pageContentHash` behind the existing `DocumentEngine` interface. Because the
   interface is unchanged, no UI or repository code changes.

Until step 5 is done and verified on all three desktop OSes, the app stays on
the Dart fallback — shipping never blocks on the bridge being wired.

## Layout

```
rust/onote_core/
├── Cargo.toml        # default build = zero bridge deps; `bridge` feature adds frb
└── src/
    ├── lib.rs        # crate root, module docs, core_version()
    ├── mirror.rs     # PageMirror + merge (the sync seed)
    ├── ids.rs        # content hashing
    └── api.rs        # #[frb] surface for Dart
```
