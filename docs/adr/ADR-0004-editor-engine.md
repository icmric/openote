# ADR-0004: Rich-text editor engine — keep the engine we own, behind a seam

> **Status:** **Accepted** — the incumbent engine wins on the spike criteria; the bake-off is not run · decided 2026-07-27 (opened 2026-07-22)
> **Related:** [Technology Evaluation §7.2](../03-technology-evaluation.md) · [Data Model Spec §5](../specs/11-data-model-spec.md)

## Decision

**Keep the editor we own** (`LiveMarkdownEngine`: a `TextField` driven by
`LiveMarkdownController`, with `MarkdownView` for read-only containers), and put
it behind the `OnoteTextEditor` seam that this ADR already required of any
winner. **Do not run the two 1–2 week spikes.**

The bake-off was framed as a two-way choice, which quietly assumed we had no
third option. By the time the criteria were written we did: the incumbent
already satisfies criteria 1 and 2 in production code, in ~450 lines
(`live_markdown_controller.dart` + the engine wrapper) that we control
end-to-end. Spending 2–4 weeks proving that a dev-channel dependency
(`super_editor`) or a block-tree editor built for a different layout model
(`appflowy_editor`) can be bent back into free-floating canvas containers — in
order to replace something that already works — is effort spent to *acquire a
dependency*, not to reduce risk.

The deciding factor is the shape mismatch, not the line count. Both candidates
own their own document layout; Openote's text containers are absolutely
positioned boxes on a canvas whose geometry comes from the OneNote importer and
must match it to fractions of a millimetre (see
`onenote_metrics_test.dart`). An engine that owns layout is a liability at that
seam, not an asset.

### Evidence against the spike's own criteria

Measured against the demo scope below, using the shipped engine. Pinned by
`app/test/editor_engine_test.dart`.

| # | Criterion | Status |
|---|-----------|--------|
| 1 | 20 containers, 19 read-only + 1 live following focus | **Met.** One session is opened for the focused block and disposed on exit; the other 19 render through `buildReadOnly`. Asserted directly. |
| 2 | Live Markdown-as-you-type (`# `, `**bold**`, `- `, `[[wiki-link]]`, `==highlight==`) | **Met.** Markers collapse when the caret leaves the construct and reveal when it re-enters — `LiveMarkdownController._buildLine`/`_inline`. Also `~~strike~~`, `++underline++`, `` `code` ``, quotes, numbered lists, tasks, dividers. |
| 3 | Inline math chip, atom-like caret, de-build on backspace-into | **Partly met — open work.** `$…$` and `$$…$$` render through `flutter_math_fork` in the read-only view, and inline maths survives import. In the *live* field the caret still walks the source character by character; it is not an atom. Tracked as TEXT-1b. |
| 4 | Byte-stable round-trip to Data Model §5 JSON | **Partly met — open work.** The stored string round-trips byte-for-byte, but storage is still the interim Markdown string in `content['text']`, not the structured `{nodes:[…]}` model of §5.1. The conversion now has exactly one place to land: `OnoteTextEditor.serialize`/`deserialize` and `textStorageKey`. |
| 5 | CJK IME pass on Linux + Windows | **Not done.** The field is a stock Flutter `TextField`, so platform IME behaviour is inherited rather than reimplemented, but it is untested on both targets. Tracked as a Phase-2 verification task. |

Criteria 3–5 are **not** claimed as met. They are the same work under any engine —
adopting `appflowy_editor` would not have delivered 4 or 5 either — so they do
not distinguish the options, and they are cheaper to finish on an engine we can
edit than on one we would have to fork.

### Why this is still reversible

The seam is the point. `OnoteEditors.use(engine)` swaps the implementation in one
call; `editor_engine_test.dart` installs a substitute engine that shares no code
with the shipped one and asserts the host still works, which is what makes
"reversible" a checked property rather than an intention. If criterion 3 turns
out to need a real inline-widget document model, the spike can be run then, with
the seam already in place and the requirement understood — a better-informed
bake-off than one run now on speculation.

### Revisit triggers

- Criterion 3 (atom-like math caret) proves impractical on a `TextField`-based
  engine — the likeliest trigger, and the one that would justify `super_editor`
  specifically, for its inline widgets.
- Collaborative editing (ADR-0002) needs per-character attribution that a
  Markdown string cannot carry, forcing the §5.1 structured model anyway.
- Maintaining `LiveMarkdownController` starts costing more per quarter than
  tracking an upstream would.

## Context (as written when this ADR was opened)

Rich text on the canvas is Openote's single biggest technical risk. Two Flutter engines have real production evidence:

- **super_editor (0.3.0-dev line)** — a build-your-own-editor toolkit (Document/Editor/attributions, inline widgets, stylesheet system, `super_editor_markdown`). Ships in Superlist and client apps, but on perpetual dev releases (API churn).
- **appflowy_editor (v6.x)** — a shipped block editor (block tree + per-block Delta, custom block components, **live Markdown-as-you-type built in**, MD/JSON import-export). Proven at scale in AppFlowy; roadmap tracks AppFlowy's needs; dual AGPL/MPL licensing (MPL path is compatible with our licensing proposal).

Both can express our text model (Data Model Spec §5); the question is which costs less to bend to *our* shape: free-floating containers on a canvas, inline math chips, our Markdown dialect, and dozens of read-only instances per page.

## Decision process (as proposed; superseded by the Decision above)

One spike per engine, **1–2 weeks each**, same demo scope — retained because the
five criteria are still the right acceptance bar for the text engine, and the
table above scores the incumbent against them:

1. A canvas page with ≥20 text containers: 19 rendered read-only/rasterized, one live editor that follows focus (the multi-instance pattern).
2. Live Markdown-as-you-type: `# `, `**bold**`, `- `, `[[wiki-link]]` chip, `==highlight==`.
3. An **inline math chip** (`$…$` → rendered `flutter_math_fork` widget, atom-like caret behavior, de-build on backspace-into).
4. Serialization round-trip to the Data Model Spec §5 JSON, byte-stable.
5. Basic IME sanity (one CJK input pass on Linux + Windows).

**Scoring (weighted):** integration effort actually spent (30%) · fidelity of the four behaviors (30%) · perf of the 20-container page (20%) · API stability/maintenance outlook (10%) · fork-ability if upstream stalls (10%). Stakeholder reviews both demos; ties break toward **appflowy_editor** (shipped-product pragmatism, built-in live Markdown) unless super_editor's inline-widget fidelity is decisively better.

## Fallback

If **both** fail criteria 1–4, that is Revisit Trigger 1 of [ADR-0001](ADR-0001-application-framework.md) (reopen posture question) — recorded here so the escalation path is explicit rather than improvised.

## Consequences

- The editor is wrapped behind an `OnoteTextEditor` interface (model in, edits out) so any engine remains a swap candidate and the format never depends on engine internals. **Done** — `app/lib/editor/onote_text_editor.dart`.
- The multi-instance pattern (one live editor, read-only elsewhere) is committed regardless of engine. **Done** — one session at a time, created on focus and disposed on blur.
- `TextBlockView` is now a host, not an editor: it owns the edit-target, the undo checkpoint, focus/exit lifecycle and the resolved type metrics, and nothing else. Engine-specific code above the seam is a review defect.
- An engine that does not expose a `TextEditingController` reports `commandController == null`; the command bar then disables rather than acting on a stale target. This keeps the formatting UI honest across a swap.
- Two acknowledged debts carried forward, both listed above: the atom-like inline-math caret (TEXT-1b) and the §5.1 structured-`nodes` migration.
