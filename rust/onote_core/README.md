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
| `api` | The thin surface `flutter_rust_bridge` turns into Dart bindings. |

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

You should see `13 passed`. That exercises the merge semantics
(newer-wins, union, idempotence, commutativity, forward-compatible field
round-trip) and the content hash against known FNV-1a vectors.

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
