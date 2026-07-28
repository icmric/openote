# ADR-0005: Licensing — AGPL-3.0 app · Apache-2.0 libraries · CC0 format spec

> **Status:** **Accepted** — ratified by the stakeholder 2026-07-27 · proposed 2026-07-22
> **Related:** [Vision §5.1/§5.7](../00-product-vision.md) · [File Format Spec](../specs/10-file-format-spec.md) · [LICENSING.md](../../LICENSING.md)

## Ratification (2026-07-27)

Accepted **as proposed**, with CC0 (not MIT) chosen for the specification. Applied in the tree as:

| Path | File | Licence |
|---|---|---|
| `app/` and everything not listed below | `LICENSE` | AGPL-3.0-or-later |
| `rust/onote_core/` | `rust/onote_core/LICENSE` + `NOTICE` | Apache-2.0 |
| `docs/specs/` | `docs/specs/LICENSE` | CC0-1.0 |
| `rust/onote_core/vendor/cab/` | upstream `LICENSE` retained | MIT (third party) |

`Cargo.toml`'s `license` field was corrected from the provisional
`AGPL-3.0-or-later` to `Apache-2.0` — the crate is the permissive tier, and the
provisional value contradicted the very proposal it cited. Contributor terms are
inbound = outbound with a DCO sign-off and no CLA, as proposed. The full map,
including the rule that `onote_core` must never take a copyleft dependency, is
in [LICENSING.md](../../LICENSING.md).

## Context

Openote's licensing must serve two goals that pull in different directions: (1) **the app must stay open** — the project exists to end lock-in, so a closed fork (especially a closed *hosted* fork) would be a betrayal of the premise; (2) **the format must spread maximally** — every importer, exporter, or competing implementation of `.onote` increases user freedom, so the format layer should carry zero licensing friction.

## Proposal

Three tiers, matching the two goals:

| Component | License | Why |
|-----------|---------|-----|
| **Application** (Flutter app, UI) | **AGPL-3.0** | Copyleft including network use: anyone may fork/self-host, but improvements must stay open — including SaaS forks. Precedent: AppFlowy, Logseq, Joplin (all AGPL), Standard Notes. |
| **Core libraries** (`onote-core` Rust crate, format reader/writer, importers) | **Apache-2.0** | Permissive + patent grant, so *any* project (including proprietary tools users depend on) can read/write `.onote` files. Lock-in dies fastest when reading our format is legally frictionless. |
| **File Format Specification** (the document itself) | **CC0** (or MIT if attribution is preferred) | The spec is the public contract; nothing should impede implementing it. |

Contributor terms: inbound = outbound (DCO sign-off), no CLA — keeps the door open for community trust; the cost is that a future *license change* would need consent or rewrite, which is acceptable given the project's premise (we are not preserving a relicensing option; that optionality is what CLAs buy and what communities distrust).

## Points the stakeholder should weigh before ratifying

1. **AGPL vs GPL vs MPL for the app:** AGPL maximally protects against closed hosted forks; GPL-3.0 is slightly more conventional for desktop apps (Saber's choice) but leaves the SaaS loophole; MPL-2.0 would even allow proprietary shells. Recommendation stands at AGPL given the anti-lock-in premise, but this is a values call, not a technical one.
2. **Boundary discipline:** the Apache-2.0 zone must be genuinely useful standalone (parse/serialize/mirror-read at minimum) or the "open format" claim rings hollow.
3. **Dependency compatibility check before ratification:** **done 2026-07-27**, and the dependency set had changed since this was written. `appflowy_editor` was never adopted (ADR-0004 kept the engine we own), and Loro, `flutter_rust_bridge` and `drift` are not dependencies — so the MPL-2.0 question this point was chiefly about does not arise. Verified against the actual locked set by reading each package's own `LICENSE`:

   | Dependency | Licence |
   |---|---|
   | `sqlite3`, `sqlite3_flutter_libs`, `perfect_freehand`, `uuid`, `cab` (vendored) | MIT |
   | `path`, `path_provider`, `ffi`, `file_selector`, `flutter_lints` | BSD-3-Clause |
   | `flutter_math_fork`, `pdf` | Apache-2.0 |
   | `serde`, `serde_json` | MIT OR Apache-2.0 |

   All permissive; nothing in the tree is copyleft except Openote's own application code. Compatible with both an AGPL-3.0 application and an Apache-2.0 core.

## Consequences

- The repository is legally open source for the first time; outside contributions can be accepted.
- **`onote_core` must never take a copyleft dependency.** The permissive tier is a promise to third-party tool authors, and a single AGPL/GPL crate in that graph silently voids it. Re-run the audit above when adding crates.
- The absence of a CLA means a future licence change needs contributor consent or a rewrite. Accepted knowingly: that optionality is exactly what communities distrust, and this project's premise makes relicensing away from openness unthinkable anyway.

## Revisit triggers

A dependency licensing conflict discovered at integration time; or a distribution channel whose terms conflict with the AGPL (notably: **the Apple App Store's terms are widely held to be incompatible with GPL-family licences** — if a first-party iOS/iPadOS build is ever wanted, this ADR must be revisited *before* that work starts, not after).
