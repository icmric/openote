# Licensing

Openote is licensed in **three tiers**, ratified in
[ADR-0005](docs/adr/ADR-0005-licensing.md). The split is deliberate and follows
directly from the project's premise: *the application must stay open, and the
format must spread with zero friction.*

| Path | Licence | Why |
|---|---|---|
| `app/` — the Flutter application | **AGPL-3.0-or-later** (`LICENSE`) | Copyleft including network use. Anyone may fork or self-host, but improvements stay open — including hosted forks. A closed fork of a project that exists to end lock-in would be a betrayal of the premise. |
| `rust/onote_core/` — the core library: `.onote` reader/writer, content hashing, mirror merge, OneNote importers | **Apache-2.0** (`rust/onote_core/LICENSE`) | Permissive, with an explicit patent grant, so *any* tool — including proprietary ones users depend on — can read and write `.onote` files. Lock-in dies fastest when reading our format is legally frictionless. |
| `docs/specs/` — the file-format, data-model, math and ink specifications | **CC0-1.0** (`docs/specs/LICENSE`) | The spec is a public contract. Nothing should impede implementing it, including attribution requirements. |
| `rust/onote_core/vendor/cab/` | **MIT** (upstream licence retained) | Third-party code, vendored with a documented two-method patch. Not ours to relicense. |
| `app/assets/fonts/` | **OFL-1.1** (upstream licences retained beside the assets) | Bundled typefaces: Inter (The Inter Project Authors) and JetBrains Mono (JetBrains). The OFL permits bundling and redistribution with the licence text attached, which is why `OFL.txt` ships in each directory. |
| Everything else (other docs, build tooling, assets) | **AGPL-3.0-or-later** | The default; anything not explicitly listed above falls here. |

## What this means in practice

- **You can build a tool that reads or writes `.onote` files, under any licence
  you like**, including a closed commercial one. Use `onote_core` (Apache-2.0)
  or implement the spec (CC0) from scratch. This is the point.
- **If you fork the Openote application** — including running a modified version
  as a network service — the AGPL requires you to offer your users the source of
  your modified version.
- **Linking direction matters.** The application depends on the core library, not
  the reverse. Apache-2.0 code can be used by an AGPL application; the core must
  therefore not take on AGPL dependencies, or its permissive promise breaks.
  Treat that as an invariant when adding crates to `onote_core`.

## Contributions

**Inbound = outbound.** Contributions are accepted under the licence of the
directory they touch, and we use a [DCO](https://developercertificate.org/)
sign-off rather than a CLA:

```bash
git commit -s -m "your message"
```

The `-s` adds a `Signed-off-by:` line, certifying you have the right to submit
the work under the project's licence. There is deliberately **no CLA** — a CLA
buys the project the option to relicense later, and we are not preserving that
option. The cost is that a future licence change would need contributor consent
or a rewrite, which is an acceptable price for the trust it buys.

## Third-party dependency audit

Verified 2026-07-27 (ADR-0005 required this before ratification); `printing`
added and audited 2026-08-04 (Apache-2.0, same author as `pdf`). All direct
dependencies are permissive and compatible with both an AGPL-3.0 application and
an Apache-2.0 core:

| Dependency | Licence |
|---|---|
| `sqlite3`, `sqlite3_flutter_libs`, `perfect_freehand`, `uuid` | MIT |
| `super_clipboard`, `super_native_extensions`, `irondash_*` | MIT |
| `pdfrx`, `pdfrx_engine`, `pdfium_dart`, `pdfium_flutter`, `synchronized` | MIT |
| **pdfium** (the bundled PDF engine binary, ~5.6 MB) | BSD-3-Clause (Google) |
| `path`, `path_provider`, `ffi`, `file_selector`, `flutter_lints`, `win32`, `win32_registry` | BSD-3-Clause |
| `html` (added and audited 2026-09-04 — tolerant HTML5 parser for the OneNote-over-Graph import) | BSD-3-Clause (Dart team) |
| `flutter_math_fork`, `pdf`, `printing`, `desktop_drop`, `rxdart` | Apache-2.0 |
| `serde`, `serde_json` | MIT OR Apache-2.0 |
| `cab` (vendored) | MIT |

Nothing in the tree is copyleft except Openote's own application code. Re-run
this audit when adding a dependency — particularly to `onote_core`, where a
copyleft crate would silently break the permissive tier.
