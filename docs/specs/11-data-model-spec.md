# Openote Data Model Specification

> **Document status:** Draft v0.1 · Last updated 2026-07-22
> **Purpose:** The concrete, implementable definition of Openote's document model — identity rules, every block type's fields, the text model, and the live-embed (transclusion) reference model. The [File Format Spec](10-file-format-spec.md) defines where these structures live; this document defines what they are.
> **Related:** [Architecture §3–§4a](../04-architecture-overview.md) · [Math Input Spec](12-math-input-spec.md) · [Ink Data Spec](13-ink-data-spec.md)
> **Notation:** structures are shown as JSON (the exact shape used in the `page_mirror` / Page JSON and the open-folder export). The CRDT mapping is §8.3 of the File Format Spec; field names are identical.

---

## 1. The tree

```
Workspace ─▶ Notebook ─▶ [SectionGroup*] ─▶ Section ─▶ Page (level 0..2) ─▶ Block*
```

- `SectionGroup` nests arbitrarily; `Section` contains only pages; a `Page` with `level > 0` is a subpage of the nearest preceding page at `level-1`.
- Ordering at every level uses **fractional-index position strings** (lexicographic order; insertion between neighbors never renumbers siblings — CRDT- and sync-friendly).

## 2. Identity (the load-bearing rules — OPEN-12)

1. Every entity (notebook, section group, section, page, block, frame) gets a **UUIDv7** at creation. UUIDv7 is time-ordered → B-tree-friendly primary keys and rough creation-time forensics for free.
2. IDs are **eager** (assigned at creation, not first reference) and **immutable**. *Rationale (from prior-art research): lazy, text-persisted IDs are the root cause of Obsidian/Logseq's chronic broken-reference bugs (IDs destroyed by cut/paste, merges, external edits). Eager IDs in a database-native model cost nothing and eliminate the class.*
3. **Never reuse or duplicate an ID.** Paste/duplicate/import always mints new IDs (with an ID-map so intra-selection links are rewritten to the new copies).
4. **Cut/paste within the app preserves IDs** (it is a move).
5. **Split:** the fragment containing the original block's first character keeps the ID; other fragments get new IDs.
6. **Merge:** the surviving (first) block keeps its ID; each absorbed block's ID is recorded in the survivor's `absorbedIds` list — a **redirect alias** so inbound refs degrade to "nearest surviving container" instead of dangling.
7. Refs are always `(pageId, blockId)`-shaped — never titles, paths, or coordinates — making them immune to rename and move.

## 3. The Block envelope

Every block shares this envelope; `content` is per-type (§5–§7):

```jsonc
{
  "id": "0198f3c2-7b1e-7cc3-9f10-3d2a8c41e977",
  "type": "text",                    // §5–§7 registry
  "x": 120.0, "y": 96.0,             // canvas position, logical px (page space)
  "w": 340.0, "h": null,             // width; h=null → auto-height from content
  "rotation": 0,                     // degrees, reserved (0 in v1)
  "z": 3,                            // paint order among page blocks
  "placement": "free",               // "free" | "snapped"
  "frameId": null,                   // membership in a frame (§6), or null
  "absorbedIds": [],                 // §2 rule 6
  "access": null,                    // RESERVED for block ownership/locking (P3 collaboration):
                                     // { "ownerId": "...", "lock": "unlocked"|"owner-only"|"locked" }
                                     // null = unlocked. Readers MUST preserve; v1 writers emit null.
  "createdAt": 1753142400000,
  "updatedAt": 1753142400000,
  "content": { /* type-specific */ }
}
```

**Unknown-field rule:** readers MUST preserve fields they don't understand (round-trip unknown keys); writers MUST NOT emit fields with semantics conflicting with this spec. This is the forward-compatibility contract.

**Page-level properties:** `background` (`"blank" | "ruled" | "grid" | "dotted"`), `gridSize` (px, default 24), `pageWidth` (logical px, default 1100 — the page-surface width per CANVAS-1 v0.4: at normal zoom the page presents *seamlessly*, filling the window as one continuous surface; zoomed out it presents as a bounded sheet whose height/right edge grow with content), `defaultPlacement` (default **snapped** — snap-to-grid is on by default, with the alignment grid visible only while a block is being dragged), `tags`, `titleBlockId` (optional).

## 4. Block type registry (v1)

| `type` | Phase | Content summary |
|--------|-------|-----------------|
| `text` | M | rich text (§5) |
| `ink` | M | stroke set → [Ink Data Spec](13-ink-data-spec.md) |
| `math` | M | display math (§5.4) |
| `image` | M | blob ref + sizing |
| `code` | M | language + source |
| `file` | M/P2 | blob ref + display metadata |
| `table` | P2 | rows/cols of rich-text cells |
| `frame` | P2 | named region (§6) |
| `embed` | P2 | live transclusion (§7) |
| `shape`, `connector` | P3 | reserved |

Unknown `type`: render a placeholder preserving the envelope + content verbatim (never drop).

## 5. Text model

### 5.1 Structure

> **Implementation status (2026-07-27).** The app does **not** store this model yet — a text block's content is an interim Markdown string in `content['text']`. That is now the highest-value gap in the spec-vs-code reconciliation, and the reason is [ADR-0006](../adr/ADR-0006-sync-transport-and-text-model.md): an opaque string makes the smallest representable edit *"the whole block is now this"*, so two people editing different sentences of one paragraph cannot both win, and no sync layer can fix that afterwards. Per-character convergence needs the sequence identity this section defines. The migration has exactly one landing site — `OnoteTextEditor.serialize`/`deserialize`/`textStorageKey` ([ADR-0004](../adr/ADR-0004-editor-engine.md)) — so nothing above the editor seam changes.

`text` block content is a list of **paragraph-level nodes**, each with inline content:

```jsonc
"content": {
  "nodes": [
    { "kind": "paragraph", "inline": [ /* spans */ ] },
    { "kind": "heading", "level": 2, "inline": [...] },
    { "kind": "listItem", "list": "bullet" | "ordered" | "task",
      "indent": 0, "checked": false, "inline": [...] },
    { "kind": "quote", "inline": [...] },
    { "kind": "divider" }
  ]
}
```

Inline spans: `{ "t": "run", "text": "…", "marks": ["bold","italic","underline","strike","code","highlight"], "color": null, "link": null }` plus **atomic inline objects**: `{"t":"math","latex":"…"}` (inline math chip), `{"t":"image","blob":"sha256:…","w":240,"h":null,"alt":""}` (inline image, sized to the line flow; `h:null` = aspect-preserving), `{"t":"tag","tag":"todo"}`, `{"t":"pageLink","pageId":"…","blockId":null,"notebookId":null}` (wiki-link chip).

> **Mixed content is the rule, not the exception (normative).** A `text` block is a **container of mixed content**: prose, inline math, inline images, tags, and links coexist in one block's flow — the user never has to leave a block to add an equation or picture mid-paragraph (the OneNote text-container behavior). The *standalone* block types (`image`, `math`, `ink`, …) exist for content placed freely on the canvas *outside* any text flow; "insert image/equation" inserts **inline** when the caret is in text, and creates a standalone block when invoked on empty canvas. Display math typed on its own line within a text block (`$$…$$`) renders as a full-width line within that block — still inside the block. Ink is the one deliberate exception (strokes don't reflow with text; overlaying ink on a text area simply layers an ink block above it).

### 5.2 Markdown mapping (normative for export/import)
CommonMark + GFM (tables, task lists, strikethrough) plus documented extensions: `==highlight==`, `[[wiki-links]]` (exported as `[title](onote://notebook/page#block)` in strict-Markdown mode), inline math `$…$`, block math `$$…$$`, inline images `![alt](assets/<hash>.<ext>)`. Everything in §5.1 has a defined Markdown projection; `color` degrades to plain text with a documented HTML-span option. The editor renders Markdown syntax **in place as typed** (TEXT-2/4); the *stored* form is always the structured model above — Markdown is a projection, not the storage.

> **In-container image references (interim dialect).** While text storage is the interim Markdown string, an in-flow image (§5.1's `{"t":"image"}` atomic inline) is written `![alt](sha256:<hash>)` — the `src` is the blob-store content address, resolved by the renderer at paint time and rewritten to `assets/<hash>.<ext>` on open-folder export. An image on its own line renders block-level within the text flow (the OneNote "image as a list item" case, which the `.one` importer produces); readers that don't resolve `sha256:` URIs degrade to the literal Markdown. The structured-model migration maps these 1:1 onto `{"t":"image","blob":…}` inlines.
>
> **Authoring.** Dropping or pasting a picture onto a text container splices this reference in, on a line of its own (the renderer matches it line-anchored, so one sharing a line with prose would print as source). The picture is therefore ordinary characters in the container's own text, which is what makes it selectable, cuttable and pasteable with no special handling — the blob store is content-addressed and never garbage-collected, so a reference cut and pasted later still resolves. While editing, the reference stays visible as dimmed monospace text rather than being swapped for the picture: the live editor's span tree must reproduce the raw text character-for-character, and a `WidgetSpan` would replace N characters with one `U+FFFC` and desync every selection offset. A drop that hits no text container still creates a standalone image block.

### 5.3 Anchors for embeds
A `range` embed target uses `(startBlockId, endBlockId)` at block granularity in v1. Sub-block (line-level) anchoring is deliberately deferred: inside a CRDT text block, stable positions require anchoring to CRDT item IDs, which is planned as `range.startOffset/endOffset` opaque anchor tokens in a minor revision (kept out of v1 for simplicity; the field names are reserved).

### 5.4 Math blocks
`math` content: `{ "latex": "\\sum_{n=1}^{\\infty} \\frac{1}{n^2}", "display": true }` — canonical LaTeX only (the [Math Input Spec](12-math-input-spec.md) defines how linear input normalizes into it; MathML is derived on export, never stored).

## 6. Frames (named regions)

```jsonc
{ "type": "frame", "content": { "label": "Derivation", "background": null, "collapsed": false } }
```
- A frame is an ordinary block whose bounds define a region; blocks inside carry `frameId` and **move with the frame**.
- Frames are the preferred **spatial embed target**: they have identity, they grow/move with their content, and they appear in backlinks. (Raw-rect embeds drift as the user rearranges the canvas — research on Miro/Figma converges on frame-like objects as the durable region primitive.)
- The "Embed this region" marquee gesture auto-creates an **implicit frame** (`label:""`, invisible chrome) so every region embed gets a durable target.

## 7. Embed model (live transclusion — EMBED-*)

### 7.1 The reference

```jsonc
{
  "type": "embed",
  "content": {
    "ref": {
      "notebookId": null,               // null = this notebook
      "pageId": "0198f3c2-…",
      "target":                          // exactly one of:
        { "kind": "page" }                                    // whole page
        | { "kind": "block", "blockId": "…" }
        | { "kind": "range", "startBlockId": "…", "endBlockId": "…" }
        | { "kind": "frame", "frameId": "…" }
        | { "kind": "rect", "x": 0, "y": 0, "w": 400, "h": 300 }   // discouraged
    },
    "snapshotBlob": "sha256:ab12…",     // last-known rendered content (§7.3)
    "snapshotAt": 1753142400000,
    "scale": "fit"                       // "fit" | "actual" | number (zoom)
  }
}
```

### 7.2 Semantics (normative)
1. **Read-only.** v1 embeds never accept edits; the renderer mounts read-only. (EMBED-9 reserves editable synced blocks; nothing here precludes them.)
2. **Live.** While the source page's doc is loaded, the embed subscribes to its changes and re-renders. Rendering uses the same block renderers as a normal page — an embed is a viewport onto real blocks, not a copy.
3. **Resolution order:** live source doc → snapshot blob (with "syncing…" affordance if the doc is expected but not yet local) → tombstone (§7.4).
4. **Click-through:** activating the embed (empty area or its source badge) navigates to `(pageId, target)`; links inside the embedded content keep their own behavior.
5. **Range semantics:** all blocks with `start ≤ position ≤ end` in the source page's block order; if exactly one endpoint has been deleted, the range degrades to the surviving endpoint's block plus a "range endpoint missing" badge (both deleted → tombstone).
6. **Frame semantics:** the frame block + all blocks whose `frameId` matches, rendered in source-page layout, cropped to the frame bounds.

### 7.3 Snapshot cache
On every successful live render (throttled; RECOMMENDED ≥ 1/min or on host-page save), the host writes a **snapshot blob**: the target's Page-JSON fragment + rendered thumbnail (`application/x-onote-snapshot+json`). One mechanism serves instant paint, offline rendering, tombstones, and export inlining (EMBED-8: PDF inlines the snapshot with a "from: *Page*" caption).

### 7.4 Broken refs & deletion
- Source deleted → tombstone: snapshot rendered grayed + "source deleted" badge + actions **Remove embed** / **Detach as static copy** (materializes the snapshot as real blocks with fresh IDs).
- Deleting a page/block/frame with inbound `refs` entries triggers a warning: "This content is embedded in N pages." (The `refs` projection makes this O(1).)

### 7.5 Cycles
Render-time cycle detection over the ancestor chain of `(pageId, targetKey)`; on revisit → placeholder chip ("circular embed — open source"). Depth cap **3** as backstop. MUST live in the shared renderer used by screen, print, and export (the Obsidian PDF-export infinite-loop bug is the canonical failure this rule prevents).

## 8. Invariants (testable)

1. Every `id` in a notebook is unique; no block references a nonexistent `frameId` on the same page.
2. `page_mirror` ≡ projection(CRDT doc) after every save.
3. Deleting a page removes its `blob_refs`; unreferenced blobs are GC-eligible only after export-safety checks.
4. For every embed/pageLink in any page's mirror, a matching `refs` row exists (index completeness).
5. No render path can recurse deeper than the cycle cap.
6. Round-trip: Page JSON → import → Page JSON is byte-stable modulo timestamps (`absorbedIds` preserved).

---

*This model is implementation-ready but not frozen; field additions ride minor format versions under the unknown-field rule (§3). Breaking changes require a major version and a migration note in the File Format Spec.*
