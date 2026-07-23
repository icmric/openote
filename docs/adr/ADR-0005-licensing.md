# ADR-0005: Licensing — AGPL-3.0 app · Apache-2.0 libraries · CC0/MIT format spec

> **Status:** Proposed — needs stakeholder ratification · 2026-07-22
> **Related:** [Vision §5.1/§5.7](../00-product-vision.md) · [File Format Spec](../specs/10-file-format-spec.md)

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
3. **Dependency compatibility check before ratification:** appflowy_editor is used under its MPL-2.0 option; Loro/`flutter_rust_bridge`/`drift`/`sqlite3` are MIT/Apache-family; `perfect_freehand` MIT; `flutter_math_fork` Apache-2.0 — all compatible with an AGPL app and Apache libs. (Re-verify at code start; record results here.)

## Revisit triggers

Ratification itself (flips status to Accepted); or a dependency licensing conflict discovered at integration time.
