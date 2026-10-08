# Openote Data Model Specification

> **Normative for the shape of a page**: identity rules, every block type's
> fields, the text model, and the live-embed reference model. The [file format
> spec](10-file-format-spec.md) says where these structures live; this says what
> they are.
>
> Structures are shown as JSON — the exact shape used in `page_mirror`, in the op
> log's `block.set`, and in the open-folder export. All three are the same bytes.
>
> **Related:** [File format](10-file-format-spec.md) · [Maths](12-math-input-spec.md) · [Ink](13-ink-data-spec.md) · [MCP API](14-external-api-mcp.md)

---

## 1. The tree

```
Workspace → Notebook → [SectionGroup*] → Section → Page (level 0..2) → Block*
```

A `SectionGroup` nests arbitrarily. A `Section` contains only pages. A `Page` with
`level > 0` is a subpage of the nearest preceding page at `level - 1`.

Ordering at every level uses **fractional-index position strings**, compared
lexicographically. Inserting between two neighbours never renumbers their
siblings, which is what lets two devices insert in the same place without
conflicting.

## 2. Identity

The rules here are load-bearing: references in this format are made of ids, so
anything that breaks an id breaks a link.

1. **Every entity gets a UUIDv7 at creation** — notebook, section group, section,
   page, block, frame. v7 is time-ordered, which makes it a well-behaved primary
   key and gives rough creation-time forensics for nothing.
2. **Ids are eager and immutable**: assigned at creation, not at first reference,
   and never rewritten. Lazy ids persisted in text are the root cause of the
   chronic broken-reference bugs in Obsidian and Logseq, where cut-and-paste, a
   merge or an external edit destroys them. In a database-native model eager ids
   cost nothing and remove the whole class.
3. **Never reuse or duplicate an id.** Paste, duplicate and import all mint new
   ones, carrying an id-map so that links *within* the pasted selection are
   rewritten to point at the new copies rather than the originals.
4. **Cut and paste inside the app preserves ids**, because that is a move.
5. **Splitting a block:** the fragment holding the original's first character
   keeps the id. The others get new ones.
6. **Merging blocks:** the survivor keeps its id, and each absorbed block's id
   goes into the survivor's `absorbedIds`. That list is a redirect alias, so an
   inbound reference degrades to "the nearest surviving container" instead of
   dangling.
7. **A reference is always `(pageId, blockId)`** — never a title, a path or a
   coordinate. That is what makes it immune to renaming and moving.

## 3. The block envelope

Every block shares this envelope. `content` is per type, and §4 is the registry.

```jsonc
{
  "id": "0198f3c2-7b1e-7cc3-9f10-3d2a8c41e977",
  "type": "text",                    // §4 registry
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

### 3.1 Page properties

A page carries its own properties beside its blocks, under `page` in the Page
JSON. Unknown keys round-trip, by the same rule as a block's.

| Key | | |
|---|---|---|
| `background` | `"blank"` \| `"ruled"` \| `"grid"` \| `"dotted"` | default `"blank"` |
| `gridSize` | px | default 24 |
| `pageWidth` | logical px | default 1100 — see below |
| `layout` | `"canvas"` \| `"paged"` | default `"canvas"` |
| `paperSize` | `"A3"` \| `"A4"` \| `"A5"` \| `"Letter"` \| `"Legal"` \| `"Tabloid"` | only meaningful when `layout` is `"paged"` |
| `landscape` | boolean | as above |

**`layout` is per page, not per notebook**, and deliberately so: one notebook
holds lecture notes you scribble on and an essay you have to hand in, and forcing
one shape on both is why people keep two apps. A canvas page is boundless and
free — blocks go where you put them. A paged page is a sheet of a fixed size that
you write down, more like a word processor.

**The three paged keys are written only when they say something.** A canvas page
emits none of them, so its JSON is byte-identical to what every earlier release
wrote. That matters beyond tidiness: emitting them unconditionally would rewrite
every page in every notebook on the next save, and hand the op log a diff for all
of them.

`pageWidth` is the width of the presented page surface. At normal zoom the page
fills the window as one continuous surface; zoomed out it presents as a bounded
sheet whose height and right edge grow with content.

## 4. Block types

`type` is the registry below. A reader that meets a `type` it does not know MUST
render a placeholder and MUST preserve the envelope and `content` verbatim — the
rule that lets a notebook written by a newer release round-trip through an older
one without losing work.

| `type` | `content` | |
|---|---|---|
| `text` | `{text, atoms?}` | Markdown with extensions, plus anything inline that is not text. §5 |
| `ink` | `{ink}` or legacy `{strokes}` | [Ink spec](13-ink-data-spec.md) §2.2 |
| `math` | `{latex, display}` | Canonical LaTeX. §5.4 |
| `image` | `{blob, w?, h?}` or `{pdf, page}` | A blob reference, or one rendered page of a stored PDF |
| `file` | `{blob, mime, name, size?}`, `{media, name, size}` or `{url}` | An attachment, a video or audio file, or a link |
| `code` | `{language, source, output?, ranAt?}` | §4.1 |
| `table` | `{cells, colWidths?, impliedColWidths?}` | Also an inline atom. §5.2 |
| `flashcard` | `{front, back}` | Two faces of a card. The study system also reads the `?[front](back)` line form inside a text block |
| `board` | `{columns: [{title, cards: [string]}]}` | Columns of draggable cards |
| `graph` | `{latex, view: {x0, x1, y0, y1}, fitY}` | A curve plotted from an equation. §4.2 |
| `substitute` | `{latex, values: {name: string}, value?}` | An equation with values plugged in. §4.2 |
| `embed` | `{ref, snapshotBlob?, snapshotAt?, scale}` | A live window onto another page. §7 |
| `frame` | `{label, background, collapsed}` | **Reserved.** §6 |

### 4.1 Code blocks

`language` is one of the supported language names; `source` is the text.
`output`, when present, is the result of the last run, and `ranAt` is when. Both
are stored so a cell's result survives a reload and reaches another device, and
neither is ever re-executed on open — **nothing runs without a click.**

A reader MUST treat `output` as data. It is not evidence that the code is safe,
and a reader that executes a cell it did not run is doing something this format
does not ask for.

### 4.2 Graphs and substitutions

Both hold an equation and something derived from it, and both are additive block
types a reader may not know.

A `graph` plots `latex` as a curve. `view` is the window it is looking through,
in graph coordinates, and is stored rather than derived so that panning and
zooming are undoable and travel between devices. `fitY` true means the vertical
range is chosen to fit the curve; it goes false the moment somebody moves the
view by hand.

A `substitute` evaluates `latex` with a value bound to each variable it names.
`values` is keyed by variable name. `value` is the pre-v1.0.2 spelling, a single
string with no name attached — see the [file format
spec](10-file-format-spec.md#changelog) for which to read and when each is
written.

Neither solves anything: nothing is rearranged and nothing is solved for an
unknown.

## 5. Text model

### 5.1 Structure

**What is stored today is a Markdown string**, in `content.text`, with anything
that is not text alongside it in `content.atoms` (§5.2). Every notebook on disk
holds that shape, and a reader implementing this specification should implement
it first.

The structured model below is **specified and not built**. It is the target, and
knowing why it is the target explains a limitation a reader will otherwise
discover by accident: an opaque string makes the smallest representable edit
*"the whole block is now this"*, so two devices editing different sentences of
one paragraph cannot both win. The op log narrows what a keystroke costs — see
the file format spec's `block.patch` — but it cannot make those two edits
converge. That needs per-element identity, which is what this section defines.

The migration has one landing site by design:
`OnoteTextEditor.serialize` / `deserialize` / `textStorageKey`
([ADR-0004](../adr/ADR-0004-editor-engine.md)). Nothing above the editor seam
changes, which is what makes it a contained piece of work rather than a rewrite.

#### The structured form (designed, not built)

`text` block content becomes a list of **paragraph-level nodes**, each with
inline content:

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

A run is
`{"t": "run", "text": "…", "marks": ["bold", "italic", "underline", "strike", "code", "highlight"], "color": null, "link": null}`.
Alongside runs sit **atomic inline objects**: `{"t": "math", "latex": "…"}`,
`{"t": "image", "blob": "sha256:…", "w": 240, "h": null, "alt": ""}` — `h: null`
preserves the aspect ratio — `{"t": "tag", "tag": "todo"}`, and
`{"t": "pageLink", "pageId": "…", "blockId": null, "notebookId": null}`.

#### Mixed content is the rule, not the exception (normative)

A `text` block is a **container of mixed content**: prose, maths, pictures, tags
and links coexist in one block's flow, and nobody has to leave a block to add an
equation or a picture mid-paragraph. This is OneNote's text-container behaviour
and it is deliberate.

The standalone block types — `image`, `math`, `graph` and the rest — exist for
content placed freely on the canvas *outside* any text flow. "Insert a picture"
or "insert an equation" therefore means two different things depending on where
the caret is: **inline when it is in text, a standalone block when it is not.**

Display maths typed on its own line inside a text block (`$$…$$`) renders
full-width, still inside that block.

**Ink is the one deliberate exception.** Strokes do not reflow with text, so ink
over a text area is an ink block layered above it, never part of its flow.

### 5.2 The Markdown dialect

**CommonMark + GFM** — tables, task lists, strikethrough — plus five documented
extensions:

| | |
|---|---|
| `==highlight==` | |
| `[[wiki-links]]` | exported as `[title](onote://notebook/page#block)` in strict-Markdown mode |
| `$…$` and `$$…$$` | inline and display maths |
| `![alt](sha256:<hash>)` | an in-flow picture, §5.2.1 |
| `![alt](onote://atom/<id>)` | anything else that is not text, §5.2.2 |

Everything in §5.1's structured form has a defined projection into this dialect.
`color` degrades to plain text, with a documented HTML-span option.

The editor renders this syntax **in place as typed**: markers collapse when a
construct completes and reappear when the caret enters it, so a reader never
sees raw asterisks. On export, `![alt](sha256:…)` is rewritten to
`assets/<hash>.<ext>`, which is what makes the exported folder readable by any
Markdown tool.

#### 5.2.1 Pictures in a text flow

An in-flow picture is written `![alt](sha256:<hash>)`. The `src` is the blob
store's content address, resolved by the renderer at paint time. A reader that
does not resolve `sha256:` URIs degrades to the literal Markdown, which is valid
CommonMark rather than a syntax error. The structured-model migration maps these
one-to-one onto `{"t": "image", "blob": …}` inlines.

**A reference must sit on a line of its own.** The renderer matches it
line-anchored, so one sharing a line with prose prints as source. That is the
OneNote "image as a list item" case, which the `.one` importer produces.

Because the picture is ordinary characters in the container's own text, it is
selectable, cuttable and pasteable with no special handling. **A blob is
immutable and nothing deletes one today**, so a reference cut and pasted later
still resolves. Any future collection of unreferenced blobs has to treat the
clipboard and the undo stack as roots, or this stops being true — see
[ADR-0007](../adr/ADR-0007-blob-lifecycle.md).

While the block is being edited the reference stays visible as dimmed monospace
rather than being swapped for the picture. The live editor's span tree must
reproduce the raw text character for character, and a `WidgetSpan` replaces N
characters with one `U+FFFC`, which would desync every selection offset.

#### 5.2.2 Inline atoms — anything else that is not text

A thing that is not text, living inside a text container, is written
`![alt](onote://atom/<id>)`, with its payload beside the text in the same block:

```jsonc
"content": {
  "text": "Results: ![3x2 table — update Openote to see it](onote://atom/0198…) and it holds.",
  "atoms": {
    "0198…": {"id": "0198…", "type": "table",
              "content": {"cells": [["a", "b"]], "colWidths": [0, 120]}}
  }
}
```

**`type` is a string rather than one of §4's names**, because an atom of a type
this build has never heard of must survive being read and written back. A newer
device's notebook is not a corrupt one, and dropping the payload would delete
their work on the next sync. The payload is a block's own `content` shape, so it
rides through every path a block takes — the op log's `block.set`, the MCP tools,
the open-folder export — with no new schema anywhere.

**The payload lives in the host block, not as a sibling.** Cut, copy, undo and
sync then move the text and its atoms as one thing: there are no orphans to
collect, and every path that walks a page's blocks — culling, marquee selection,
z-order, an exporter's reading-order sort — needs no "skip the inline ones"
clause. An atom whose reference is deleted has its payload dropped; one whose
reference arrives without a payload, which is what a paste looks like, has it
recalled from the session's memory of what was cut.

**The alt text is load-bearing**, which is unusual for alt text. It is what every
renderer that cannot draw the atom shows instead — an older build of Openote, a
foreign Markdown viewer, an export. For a table it should therefore say both what
the thing is and what to do about it.

`page.md` writes each atom as its native Markdown, so a table becomes a GFM
table. `page.json` keeps the reference and is the fidelity path. An atom this
build cannot project keeps its reference verbatim, which is valid CommonMark, so
a foreign reader shows the alt text rather than a syntax error.

**`table` is therefore both a block type and an atom type.** A table on the
canvas outside any text flow is a `table` block; a table inside a paragraph is an
atom in that paragraph's `content.atoms`. One widget draws both.

##### A table's two width lists mean different things

`colWidths` holds widths somebody **chose** — dragged by hand, or sent by
OneNote. They are used exactly, so text too long for a column wraps inside it.

`impliedColWidths` holds widths nobody chose: what a conversion worked out a
table used to occupy, from the width of the block it used to live in. Those are a
starting size rather than a limit, so the column opens at that width and grows
past it once its contents no longer fit.

Both are optional and per column, and `0` means "work it out". A reader that
knows only `colWidths` still draws a converted table, just at its natural width.

### 5.3 Anchors for embeds

A `range` embed target addresses blocks, not offsets: `(startBlockId,
endBlockId)`. Sub-block anchoring is deferred rather than forgotten — a stable
position inside a paragraph needs per-element identity, which §5.1's structured
form provides and the stored string does not. `range.startOffset` and
`range.endOffset` are reserved for it.

### 5.4 Maths blocks

```jsonc
{"latex": "\\sum_{n=1}^{\\infty} \\frac{1}{n^2}", "display": true}
```

**Canonical LaTeX only.** The [maths spec](12-math-input-spec.md) defines how
linear input normalises into it. MathML is derived on export and never stored,
and rendered output is never stored at all.

## 6. Frames — reserved

A frame would be an ordinary block whose bounds define a region, with the blocks
inside it carrying `frameId` and moving with it.

```jsonc
{"type": "frame", "content": {"label": "Derivation", "background": null, "collapsed": false}}
```

**Nothing creates one.** The type is reserved, a reader should expect never to
meet it, and it MUST round-trip like any other unknown block if it does.

It is specified because it is the shape a durable *spatial* embed target wants:
frames have identity, they grow and move with their content, and they appear in
backlinks, where a raw rectangle drifts as soon as somebody rearranges the canvas.
Prior art on Miro and Figma converges on frame-like objects for the same reason.
Until frames exist, §7's `rect` target is what region embeds use, with the
drifting that implies.

## 7. Embeds — a live window onto another page

> **What is built:** the `page` and `rect` targets, same-notebook only, resolving
> live then falling back to a tombstone. `block` and `range` targets round-trip
> and render as an inert chip rather than an error, and `frame` waits on §6.
>
> **`snapshotBlob` is deliberately not written.** A snapshot is a copy, and for a
> same-notebook embed the source is always local, so it buys nothing until
> cross-notebook embeds exist. The field stays reserved, and §7.3 describes what
> it is for rather than what happens.

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

1. **Read-only.** An embed never accepts edits; the renderer mounts read-only.
   EMBED-9 reserves editable synced blocks, and nothing here precludes them.
2. **Live.** While the source page is loaded, the embed subscribes to its changes
   and re-renders. It uses the same block renderers as an ordinary page, because
   an embed is a viewport onto real blocks rather than a copy of them.
3. **Resolution order:** the live source, then the snapshot blob — showing
   "syncing…" if the source is expected but not yet local — then a tombstone
   (§7.4).
4. **Click-through.** Activating the embed, by its empty area or its source badge,
   navigates to `(pageId, target)`. Links inside the embedded content keep their
   own behaviour.
5. **A `range`** is every block between its two endpoints in the source page's
   block order. If exactly one endpoint has been deleted it degrades to the
   survivor plus a badge saying so; if both have, it becomes a tombstone.
6. **A `frame`** is the frame block plus every block whose `frameId` matches,
   rendered in the source page's layout and cropped to the frame's bounds.

### 7.3 Snapshot cache

On each successful live render, throttled to roughly once a minute or to the host
page's save, the host writes a **snapshot blob**: the target's Page JSON fragment
plus a rendered thumbnail, under the mime type
`application/x-onote-snapshot+json`.

One mechanism serves four purposes — painting instantly, rendering offline,
drawing a tombstone, and inlining into an export, where a PDF carries the
snapshot with a "from *Page*" caption.

### 7.4 Broken references

**The source was deleted** → a tombstone: the snapshot greyed out, a "source
deleted" badge, and two actions. *Remove embed* deletes it; *detach as a static
copy* materialises the snapshot as real blocks with fresh ids.

**Deleting something with inbound `refs` rows** warns first — "this content is
embedded in N pages". The `refs` projection is what makes that question cheap
enough to ask on every delete.

### 7.5 Cycles

Cycle detection runs at render time over the ancestor chain of
`(pageId, targetKey)`. On revisiting one, the embed draws a placeholder chip
reading "circular embed — open source". A depth cap of **3** is the backstop.

**This MUST live in the shared renderer** used by the screen, printing and every
export. Putting it anywhere else is how Obsidian's PDF export came to loop
forever, which is the canonical failure this rule exists to prevent.

## 8. Invariants

Each of these is checkable, and each has a test behind it.

1. **Ids are unique** within a notebook, and no block names a `frameId` that does
   not exist on its own page.
2. **The container agrees with the log.** Replaying every operation reproduces
   `page_mirror`, `nodes` and the projections. This is not a nicety: it is the
   check that makes the container safely rebuildable, and it is what a second
   device uses to join a notebook.
3. **Deleting a page removes its `blob_refs` rows.** The blob bytes stay — nothing
   deletes a blob today — so this is about the root set being accurate, not about
   reclaiming space.
4. **Index completeness.** For every embed and page link in any page, a matching
   `refs` row exists.
5. **No render path recurses past the cycle cap.**
6. **Round-trip is byte-stable.** Page JSON → read → write → Page JSON differs
   only in timestamps. `absorbedIds` survives, and so does every field this build
   does not understand.

---

*This model is implementation-ready and not frozen. Field additions ride minor
format versions under the unknown-field rule in §3. A breaking change needs a
major version and a migration note in the [file format
spec](10-file-format-spec.md#compatibility-promise).*
