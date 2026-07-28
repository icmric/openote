# Contributing to Openote

Thank you for your interest in Openote — an open-source, cross-platform alternative to Microsoft OneNote, built so that no one is ever locked into their notes again.

> **Current phase: implementation.** There is a working desktop app — Flutter/Dart in [`app/`](app/README.md) plus a native Rust core in [`rust/onote_core/`](rust/onote_core/README.md). Start with [`app/README.md`](app/README.md) to build and run it, and read [`INTEGRATION.md`](rust/onote_core/INTEGRATION.md) (including its **stale-DLL warning**) before touching the core. Design critique on [`docs/`](docs/README.md) is still very welcome.
>
> **Before submitting code:** `flutter analyze` must be clean of errors and warnings, `flutter test` (82 tests) and `cargo test` (26 tests) must pass, and `cargo clippy --all-targets` must be clean. Match the surrounding comment density — this codebase explains *why*, not *what*.
>
> **Licensing is ratified** ([ADR-0005](docs/adr/ADR-0005-licensing.md), 2026-07-27): **AGPL-3.0-or-later** for the app, **Apache-2.0** for `onote_core`, **CC0-1.0** for the format specs. Contributions are accepted under the licence of the directory they touch. See [LICENSING.md](LICENSING.md) — and note the invariant that **`onote_core` must never gain a copyleft dependency**.

## Ways to help right now

**1. Read and critique the plans.** The [documentation set](docs/README.md) — vision, teardown, PRD, technology evaluation, architecture, and style guide — is where the project is being shaped. Open an issue if you:
- disagree with a decision or spot a flaw in the reasoning,
- know of prior art (an app, a format, a library) we should learn from,
- have hands-on experience with one of the hard problems below.

**2. Bring domain expertise.** Openote sits at the intersection of several genuinely hard areas. If you have real experience with any of these, your input is especially wanted:
- **Flutter canvas & ink pipelines** (infinite-canvas performance, viewport culling, `perfect_freehand`-style stroke rendering)
- **Rich-text / block editing** on a canvas (ProseMirror/Lexical/BlockSuite, or native text engines)
- **CRDTs & local-first sync** (Yjs/`yrs`, Loro, Automerge; E2E-encrypted sync)
- **Math input & rendering** (UnicodeMath/LaTeX/MathML, KaTeX/MathJax/MathLive)
- **Open file-format design** and long-term data durability
- **Flutter, Qt, or the other candidate frameworks** — especially real ink/text experience
- **Accessibility** on custom-drawn canvases

**3. Review the decisions.** The major technical decisions are recorded as [Architecture Decision Records](docs/adr/README.md) — framework (Flutter + Rust core), CRDT (Loro), storage container (SQLite `.onote`), editor engine (keep the engine we own, behind a swappable seam), licensing (proposed), and the sync storage layout (proposed). Each documents its revisit triggers; reasoned challenges backed by evidence are welcome.

**4. Prototype a spike.** The remaining open work is spike-shaped: the editor-engine bake-off ([ADR-0004](docs/adr/ADR-0004-editor-engine.md)), the first-party canvas core, the Saber-style ink pipeline feel-check, and the Loro-via-FFI round-trip benchmark. If you want to build one, say so in an issue — spike evidence settles arguments here.

## Principles contributions are held to

Every contribution is weighed against the project's [design principles](docs/00-product-vision.md#5-design-principles) and [non-goals](docs/00-product-vision.md#9-non-goals). In short:

- **Openness is non-negotiable.** No feature may compromise the open, documented, local-first format or lock users in.
- **The canvas is sacred.** Freeform placement, fast startup, and responsive ink come first — and we deliberately don't trade startup speed or consistency for micro-latency ink tricks.
- **We don't overreach.** Openote is a notebook, not an office suite, task manager, or AI product. Scope discipline is a feature.
- **Accuracy matters.** We describe competitors and technical trade-offs precisely, even when a looser claim would be more flattering.

## How to propose changes

1. **Open an issue** describing the idea/problem before large work — it saves everyone effort and invites discussion.
2. For **documentation edits**, small corrections can go straight to a pull request; larger structural changes should start as an issue.
3. Keep discussion **respectful and constructive.** We assume good faith and expect the same.
4. When code begins, this guide will add: dev environment setup, coding standards, testing requirements, commit/PR conventions, and a code of conduct.

## Communication

- **Issues** — proposals, bugs (later), and design discussion.
- **Discussions** (when enabled) — open-ended questions and ideas.
- A **Code of Conduct** will be adopted alongside the first code contributions.

## Licensing of contributions

**Inbound = outbound**, with a [Developer Certificate of Origin](https://developercertificate.org/) sign-off rather than a CLA. Sign your commits:

```bash
git commit -s -m "your message"
```

That adds a `Signed-off-by:` line certifying you have the right to submit the work under the project's licence — AGPL-3.0-or-later for the app, Apache-2.0 for `onote_core`, CC0-1.0 for `docs/specs/` ([ADR-0005](docs/adr/ADR-0005-licensing.md), [LICENSING.md](LICENSING.md)). There is deliberately no CLA: it would buy the project an option to relicense that we are not preserving. Contributors will be credited.

---

*Openote is being built in the open, deliberately and carefully, so that it's worth trusting with your notes. Thanks for helping make that real.*
