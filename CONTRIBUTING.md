# Contributing to Openote

Thank you for your interest in Openote — an open-source, cross-platform alternative to Microsoft OneNote, built so that no one is ever locked into their notes again.

> **Current phase: planning & design.** There is **no application code yet**. Right now the most valuable contributions are *ideas, critique, and expertise* on the design documents in [`docs/`](docs/README.md). This guide will grow as the codebase begins.

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

**3. Review the decisions.** The major technical decisions are recorded as [Architecture Decision Records](docs/adr/README.md) — framework (Flutter + Rust core), CRDT (Loro), storage container (SQLite `.onote`), editor engine (open bake-off), and licensing (proposed). Each documents its revisit triggers; reasoned challenges backed by evidence are welcome.

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

The proposed licensing model ([ADR-0005](docs/adr/ADR-0005-licensing.md), pending ratification): AGPL-3.0 application, Apache-2.0 reference libraries, CC0/MIT format specification. By contributing, you agree your contributions will be licensed under the project's chosen license. Contributors will be credited.

---

*Openote is being built in the open, deliberately and carefully, so that it's worth trusting with your notes. Thanks for helping make that real.*
