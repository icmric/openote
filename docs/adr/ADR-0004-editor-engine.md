# ADR-0004: Rich-text editor engine — super_editor vs appflowy_editor (spike-gated)

> **Status:** Open — decided by bake-off, criteria below · 2026-07-22
> **Related:** [Technology Evaluation §7.2](../03-technology-evaluation.md) · [Data Model Spec §5](../specs/11-data-model-spec.md)

## Context

Rich text on the canvas is Openote's single biggest technical risk. Two Flutter engines have real production evidence:

- **super_editor (0.3.0-dev line)** — a build-your-own-editor toolkit (Document/Editor/attributions, inline widgets, stylesheet system, `super_editor_markdown`). Ships in Superlist and client apps, but on perpetual dev releases (API churn).
- **appflowy_editor (v6.x)** — a shipped block editor (block tree + per-block Delta, custom block components, **live Markdown-as-you-type built in**, MD/JSON import-export). Proven at scale in AppFlowy; roadmap tracks AppFlowy's needs; dual AGPL/MPL licensing (MPL path is compatible with our licensing proposal).

Both can express our text model (Data Model Spec §5); the question is which costs less to bend to *our* shape: free-floating containers on a canvas, inline math chips, our Markdown dialect, and dozens of read-only instances per page.

## Decision process (normative for the spike)

One spike per engine, **1–2 weeks each**, same demo scope:

1. A canvas page with ≥20 text containers: 19 rendered read-only/rasterized, one live editor that follows focus (the multi-instance pattern).
2. Live Markdown-as-you-type: `# `, `**bold**`, `- `, `[[wiki-link]]` chip, `==highlight==`.
3. An **inline math chip** (`$…$` → rendered `flutter_math_fork` widget, atom-like caret behavior, de-build on backspace-into).
4. Serialization round-trip to the Data Model Spec §5 JSON, byte-stable.
5. Basic IME sanity (one CJK input pass on Linux + Windows).

**Scoring (weighted):** integration effort actually spent (30%) · fidelity of the four behaviors (30%) · perf of the 20-container page (20%) · API stability/maintenance outlook (10%) · fork-ability if upstream stalls (10%). Stakeholder reviews both demos; ties break toward **appflowy_editor** (shipped-product pragmatism, built-in live Markdown) unless super_editor's inline-widget fidelity is decisively better.

## Fallback

If **both** fail criteria 1–4, that is Revisit Trigger 1 of [ADR-0001](ADR-0001-application-framework.md) (reopen posture question) — recorded here so the escalation path is explicit rather than improvised.

## Consequences (either winner)

- The editor is wrapped behind an `OnoteTextEditor` interface from day one (model in, edits out) so the loser remains a swap candidate and the format never depends on engine internals.
- The multi-instance pattern (one live editor, read-only elsewhere) is committed regardless of winner.
