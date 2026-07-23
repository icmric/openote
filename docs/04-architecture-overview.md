# Architecture Overview

> **Document status:** Draft v0.2 · Planning phase · Last updated 2026-07-22
> **Purpose:** The overview of how Openote is put together — the layers, the data model, the open file format, and the hard subsystems (canvas, text, math, ink, **embeds**) plus sync. The deep specs it previews now exist: [File Format](specs/10-file-format-spec.md) · [Data Model](specs/11-data-model-spec.md) · [Math Input](specs/12-math-input-spec.md) · [Ink Data](specs/13-ink-data-spec.md) · [ADRs](adr/README.md).
> **Related:** [PRD](02-product-requirements.md) · [Technology Evaluation](03-technology-evaluation.md)
> **v0.2 status:** the stack is now provisionally decided — **Flutter/Dart UI + Rust core, Loro CRDT, SQLite container** (ADRs 0001–0003) — and this overview is written against it, while the domain model and file format remain deliberately framework-independent (tenet 4). Live embeds (transclusion) added as §4a.

---

## 1. Design tenets (how the vision constrains the architecture)

Five tenets, each a direct consequence of a vision principle, act as architectural fixed points:

1. **The document model is the product.** A clean, open, well-specified data model is the asset; the UI is a renderer of it. Get the model right and everything — storage, sync, export, third-party tools — follows.
2. **Open format, no lock-in — by construction.** Every stored byte is either a documented Openote structure or a well-known open format (Markdown, LaTeX, MathML, InkML, JSON Canvas, PNG). Nothing requires our servers or our survival to read.
3. **Local-first.** The device is the source of truth. The network is an optional accelerant, never a dependency.
4. **Separate the model from the renderer from the framework.** The data model and file format are defined independently of the UI framework, so the (still-open) framework choice — and even a future re-platforming — does not touch the format.
5. **Concurrency-ready from day one.** Even before real-time collaboration ships, the model is built so that merging divergent edits (two offline devices) is conflict-free. This is why a CRDT sits at the core rather than being bolted on later.

---

## 2. Layered architecture

Openote is organized into layers with strict downward dependencies (upper layers depend on lower, never the reverse). This is what lets the framework choice stay isolated.

```
┌───────────────────────────────────────────────────────────────┐
│  PRESENTATION  (Flutter/Dart — ADR-0001)                        │
│  • Canvas view & interaction   • Navigator/sidebar              │
│  • Text editor UI  • Math editor UI  • Ink surface  • Toolbars  │
├───────────────────────────────────────────────────────────────┤
│  APPLICATION  (framework-agnostic app logic)                    │
│  • Commands & undo/redo   • Selection & tools   • Search        │
│  • Import/export orchestration   • Settings                     │
├───────────────────────────────────────────────────────────────┤
│  DOMAIN / DOCUMENT MODEL  (the core asset — pure, portable)     │
│  • Workspace▸Notebook▸SectionGroup▸Section▸Page▸Block tree      │
│  • Block types: text, ink, math, image, table, code, file…      │
│  • Canvas geometry (transforms, z-order, snap)                  │
│  • CRDT-backed, offline-mergeable                               │
├───────────────────────────────────────────────────────────────┤
│  PERSISTENCE  (the open file format + storage engine)           │
│  • On-disk container   • Blob store (images, files, ink)        │
│  • Crash-safe writes   • Format versioning & migration          │
├───────────────────────────────────────────────────────────────┤
│  SYNC  (optional, pluggable)                                    │
│  • CRDT update exchange   • Transport adapters (WebDAV/S3/…)     │
│  • Optional E2E encryption   • Optional first-party service     │
└───────────────────────────────────────────────────────────────┘
```

**Cross-cutting:** a **rendering abstraction** (math renderer, ink renderer) and a **platform-services abstraction** (file dialogs, stylus input, secure storage) keep platform-specific code at the edges.

---

## 3. The document model

### 3.1 Hierarchy

```
Workspace
└── Notebook
    ├── SectionGroup (optional, nestable)
    │   └── Section
    │       └── Page
    │           ├── Subpage
    │           └── Block[]        ← the page's content lives here
    └── Section …
```

Each level has a stable **UUID**, human title, timestamps, and metadata (tags, color). The mapping of this hierarchy onto files is a persistence decision (§5), deliberately *not* baked into the model.

### 3.2 The page as a canvas of blocks

A **Page** is not a linear document — it is a **canvas holding positioned Blocks**. Every Block carries:

- `id` — a UUID **assigned eagerly at creation and immutable for the block's lifetime** (OPEN-12). This is a hard rule with a specific pedigree: Obsidian and Logseq assign block IDs lazily inside text files and suffer chronic broken-reference bugs; Notion/AFFiNE/Roam assign eagerly in the data model and don't. Links, backlinks, embeds, and sync all hang off these IDs. Split/merge/copy semantics are specified in the [Data Model Spec §4](specs/11-data-model-spec.md).
- `type`, and type-specific `content`
- **canvas transform:** `x, y, width, height, rotation?, zIndex`
- `placement`: `free` or `snapped` (with the page/notebook grid settings)
- optional `groupId`, `style`, `createdAt/modifiedAt`

**Block types (v1 → later):**

| Type | Content (canonical form) | Phase |
|------|--------------------------|-------|
| `text` | rich text as a Markdown-compatible model (see §4) | M |
| `ink` | stroke set: arrays of x/y/pressure/tilt/time + brush (see §7) | M |
| `math` | canonical **LaTeX** source (+ derived MathML) (see §6) | M |
| `image` | reference to a blob + intrinsic size | M |
| `code` | language + source text | M (render), P2 (extras) |
| `table` | rows/cols of cell content (Markdown-table-interoperable) | P2 |
| `file` | reference to an embedded blob + display metadata | M/P2 |
| `embed` | **live transclusion reference**: `(pageId, target)` + cached snapshot (see §4a) | P2 |
| `frame` | a named region grouping blocks — the durable target for spatial embeds | P2 |
| `shape`/`connector` | geometry + style | P3 |

This "positioned blocks on a canvas" model is what simultaneously gives us OneNote's freeform placement **and** a clean, exportable structure. A block with `placement: snapped` and default position also degrades gracefully to a linear Markdown document on export.

### 3.3 Why a CRDT at the core

The document model is backed by a **CRDT (Conflict-free Replicated Data Type)** so that:

- Two devices edited offline **merge automatically** with no conflict dialogs — the direct antidote to OneNote's #1 complaint (sync conflicts/corruption).
- Real-time collaboration (later) is the *same* mechanism, not a new one.
- The **CRDT document can *be* the on-disk artifact** (persist its snapshot + incremental updates), so we do not sync one representation and serialize another.

Trade-offs we accept and manage: the raw CRDT log is opaque binary (mitigated by always offering an open export, §8), and history grows over time (mitigated by periodic **snapshot + compaction/GC**). The library decision is **Loro** behind our own Rust API ([ADR-0002](adr/ADR-0002-crdt-library.md)), with a note-shaped benchmark as a Phase-0 validation task and `yrs` as the documented fallback.

> **Modeling note:** a CRDT is a document/key-value store, not relational. We model **one page (or one notebook) as one CRDT document** and treat cross-references (backlinks, embeds) as soft links resolved by walking the structure — not as foreign keys expecting conflict-free joins.

---

## 4. Text subsystem (rich text + inline Markdown)

The hardest UI subsystem (see Tech Evaluation §2.2). Design intent:

- **One model, two surfaces.** Text is stored as a structured rich-text model that is **losslessly Markdown-compatible** for the common subset (headings, emphasis, lists, code, links, checkboxes, tables). The toolbar and Markdown syntax are two editing paths into the same model.
- **Interpret-as-you-type.** Markdown tokens render **in place** as typed (`# `→heading, `**b**`→bold). When the caret enters a formatted span, the underlying markers reveal for editing, then re-render on exit (the "live preview" pattern). This satisfies TEXT-2/TEXT-4 and the stakeholder's "render it in the same place it's written" requirement.
- **Storage form:** a portable inline model (Markdown-serializable + a small set of typed extensions for things Markdown can't express — e.g. text color, highlight, tags). Extensions are documented so the format stays open and any Markdown reader gets a faithful degraded view.
- **Rendering:** a Flutter editor engine — **super_editor or appflowy_editor, decided by the [ADR-0004](adr/ADR-0004-editor-engine.md) bake-off** — mounted live on the focused container only, with read-only/rasterized renderings for every other box on the canvas. The *model* is engine-independent — this is precisely why the editor decision doesn't touch the format.

---

## 4a. Embeds subsystem (live transclusion)

The stakeholder-requested "render part of another page inside this page" feature. Design distilled from prior art (Obsidian embeds, Logseq `{{embed}}`, Notion synced blocks, Dendron range refs, BlockSuite synced-doc blocks, Miro viewport embeds); full data structures in the [Data Model Spec §7](specs/11-data-model-spec.md).

- **Reference model.** An `embed` block stores an `EmbedRef`: `{ sourcePageId, target }` where `target` is one of `block(blockId)` · `range(startBlockId, endBlockId)` · `frame(frameId)` · `rect(x,y,w,h)` (discouraged; see below). References are **by stable ID, never by title, path, or line number** — immune to rename/move.
- **Spatial regions prefer frames.** Embedding "a certain area" of a canvas targets a **frame** (a named region object that moves and grows with its content) rather than raw coordinates, which silently drift as the user rearranges the page. A marquee "Embed this region" gesture auto-promotes the selection to a lightweight frame so the region gains an ID and participates in backlinks and delete-warnings. (`rect` remains as a last-resort literal.)
- **Read-only rendering.** The embed mounts a read-only renderer over the source blocks — same rendering stack, no editing surface (v1 policy per stakeholder; the model deliberately doesn't preclude Notion-style editable synced blocks later, EMBED-9). Links inside embedded content stay clickable; click-through and a source badge provide navigation.
- **Live updates, local-first.** Each page is its own CRDT document, so an embed is a **cross-document subscription**: the host page lazily loads the source doc (on viewport entry) and re-renders on its change events — exactly the BlockSuite/Yjs mechanism, via our Rust core.
- **Snapshot cache (one mechanism, three problems).** The host page stores a **denormalized snapshot** of the embedded content, refreshed whenever the live source is available. It provides: (1) instant paint before the source doc loads, (2) correct offline rendering when the source isn't yet synced to this device, (3) tombstone content when the source is deleted (grayed, "source deleted" badge, detach-or-remove actions), and (4) export inlining for free.
- **Integrity is checked at render time.** CRDTs give us subscriptions but not referential integrity — the target can be deleted concurrently on another device. Every render validates the ref; the backlink index warns at delete time ("embedded in N pages").
- **Cycle safety lives in the shared renderer.** Cycle detection tracks the ancestor chain of `(pageId, target)` during rendering and renders a placeholder chip on revisit, with a depth cap (3) as backstop — enforced in the one shared render path so screen and PDF export can't diverge (the Obsidian PDF-export infinite-loop bug is the cautionary tale).

---

## 5. Persistence & the open file format

This is the strategic heart. The section previews the format; a full **File Format Specification** is the top-priority item in the next documentation pass.

### 5.1 Requirements the format must meet

Open & documented (OPEN-1/3), local-first (OPEN-2), semantic math (OPEN-4), open ink (OPEN-5), canvas-interoperable (OPEN-6), crash-safe & inspectable & partially-recoverable (OPEN-11), no size limits (OPEN-10), and versioned for forward/backward compatibility.

### 5.2 Three candidate container strategies (decision deferred)

| Strategy | What it is | Pros | Cons |
|----------|-----------|------|------|
| **A. Folder of open files** (Obsidian/Zim model) | notebook = directory; pages as Markdown/JSON + a `blobs/` dir; canvas as JSON Canvas | maximal portability; sync with any file tool; greppable; longevity | many small files; weak transactions (crash mid-write); attachment sprawl; hard to embed CRDT history cleanly |
| **B. SQLite as the application file format** (Trilium/Logseq-DB model) | notebook = one `.db`; blocks/blobs as rows | ACID crash-safety; incremental writes; queryable; single-file portability; archival longevity | breaks "notes are plain files"; not folder-syncable; naive whole-file sync causes conflicts (the Logseq-DB lesson) |
| **C. CRDT-native bundle** (AFFiNE/Automerge model) | notebook = CRDT snapshot + update log (+ blob store), packaged as a documented bundle | offline-merge & collab for free; the sync unit *is* the file | opaque binary (needs an open export to stay "open"); history growth needs GC |

### 5.3 The decision (ratified in the [File Format Spec](specs/10-file-format-spec.md) and [ADR-0003](adr/ADR-0003-storage-container.md))

A **hybrid that gets the best of B and C while honoring openness via export:**

- **Container:** the **`.onote` package — a SQLite database per notebook** (ACID, incremental, crash-safe, single-file) storing the CRDT document(s), block data, and a blob table for images/files/ink. This directly fixes OneNote's corruption-prone one-file-per-section model.
- **Openness guaranteed by three things, not by the container being text:**
  1. a **published, permissively-licensed specification** of the schema and encodings;
  2. **canonical open encodings inside** — text as Markdown-compatible, math as LaTeX+MathML, ink as documented stroke data (InkML-interchangeable), canvas as JSON-Canvas-interoperable;
  3. **first-class, lossless-where-possible export** to a *folder of open files* (Strategy A) so any user can, at any moment, materialize their notes as plain Markdown + JSON Canvas + assets. **Export is the escape hatch that makes the efficient container safe to adopt.**
- **Blobs** (images, attachments, ink bitmapped caches) are content-addressed and stored once, referenced by id.
- **Versioning:** every file carries a format version; migrations are forward-only and documented.

> This resolves the openness-vs-collaboration tension (Vision §10.3): the *working* format is an efficient, crash-safe, CRDT-capable SQLite bundle; the *openness guarantee* is the published spec **plus** a lossless open-folder export. A user is never trapped, and we never pay the "thousands of tiny files" tax at runtime.

### 5.4 What we explicitly avoid

OneNote's mistakes: an undocumented binary; one fragile file per section; a hard dependency on a cloud; and export paths that silently drop ink, tags, and structure.

---

## 6. Math subsystem

- **Canonical storage: LaTeX** (smallest, best-tooled, round-trips through every renderer), with **MathML** as a derived export for interchange and accessibility.
- **Input modes:** (1) **LaTeX**; (2) **UnicodeMath-style linear input** — typing `\sum`, `/`, `^`, `_`, `\int`, `&`/`@` for matrices — that **builds up into 2-D as you type** (the OneNote experience, satisfying MATH-2/5), normalized to canonical LaTeX on commit; (3) optional **AsciiMath** casual mode; (4) later, **ink-to-math**. A **symbol/structure palette / virtual math keyboard** (MathLive-style) aids discovery.
- **Rendering:** native (`flutter_math_fork`, a KaTeX-subset Dart renderer, no WebView) or web (KaTeX for speed / MathJax for coverage / MathLive for interactive editing), depending on posture. Renders crisply at any zoom/theme and stays editable (source preserved).
- **A reusable bridge:** `UnicodeMathML` (Murray Sargent's reference implementation) translates UnicodeMath↔LaTeX/MathML and is worth mining for the build-up grammar.
- **Non-goal:** solving/graphing (Vision §9) — we make equations beautiful to *write*, not to *solve*.

The linear-input grammar deserves its own **Math Input Specification** in the next pass (it is subtle — spacing is semantically load-bearing in UnicodeMath).

---

## 7. Ink subsystem

- **Data model:** each stroke as parallel typed arrays — `x[] y[] pressure[] tiltX[] tiltY[] t[]` — plus a per-stroke `brush` (tool, color, base width). Compact, cache-friendly, diff-friendly, and a clean CRDT value. Capture **coalesced high-frequency points** to avoid under-sampling fast strokes.
- **Rendering:** natural, pressure-responsive **variable-width outlines** (the `perfect-freehand` approach; Dart port `perfect_freehand`), not jagged polylines. Velocity-based width when pressure is unavailable (mouse/trackpad).
- **Latency (revised per stakeholder direction):** near-native pen latency is a **non-goal**. Ink renders through Flutter's standard pointer → `CustomPainter` pipeline — the Saber approach, proven acceptable in a shipping cross-platform ink app. No per-platform front-buffer overlays or motion-prediction layers are planned; the complexity they add works against the top priorities (startup, consistency, velocity). The remaining ink performance work is ordinary engineering: consume coalesced pointer events, draw the wet stroke on a dedicated layer, rasterize completed strokes into cached layers.
- **Openness:** strokes stored in the documented format; **InkML** (W3C) as the import/export interchange (not the hot-path storage — XML InkML is too heavy for stroke-dense pages, mirroring how OneNote's compact ISF coexists with InkML).
- **Recognition: deferred.** Store losslessly now; add optional on-device **ML Kit Digital Ink** (stroke-based, offline, 300+ languages) or commercial **MyScript** later. We do not architect as though a fully-open cross-platform online recognizer exists — it doesn't.

An **Ink Data Model Specification** is a next-pass deliverable.

---

## 8. Sync subsystem

- **Mechanism:** exchange **CRDT updates** between replicas. Because the document is already a CRDT (§3.3), sync is "ship opaque updates and merge," and the server can be **dumb** (relay + ordered storage).
- **Transports (pluggable, bring-your-own):** a synced folder in an existing cloud drive; **WebDAV/Nextcloud**; **S3-compatible**; and an optional **first-party service** — following Joplin's flexibility (SYNC-3). No mandatory vendor.
- **E2E encryption (optional):** if enabled, clients encrypt updates/snapshots and the server is a **blind relay** (model on `secsync`). Content stays **locally searchable** because the search index is built and kept **on-device** — avoiding OneNote's "locked sections are invisible to search" trap. Decide E2E early: it constrains the server to relay-only and pushes compaction to clients.
- **Collaboration (later):** presence/cursors and live editing ride the same CRDT channel; no new mechanism (SYNC-6).
- **History/versioning:** periodic snapshots enable page version browsing/restore (SYNC-8) and bound history growth via compaction.

---

## 9. Search & indexing

A **local full-text index** across the whole workspace (fast, offline), designed to include OCR'd image text (P3) and, later, ink recognition results. The index is **on-device and covers encrypted content locally**, so encryption never blinds search. Backlink and tag indexes support the graph/backlinks and find-tags features.

---

## 10. Import / export

- **Export (the openness guarantee):** Markdown, PDF, HTML, and open interchange (MathML, InkML, JSON Canvas), plus the **lossless "materialize as a folder of open files"** path (§5.3). Available on **every platform** (fixing OneNote's Mac/web export gaps).
- **Import:** Markdown / Obsidian / JSON Canvas (open ecosystem, earlier), and the headline **OneNote `.one`/`.onepkg` importer** (later, P3) preserving structure, text, images, and — as far as feasible — ink and tags. The MS-ONESTORE spec is published, so a faithful importer is *possible*, if substantial.

---

## 11. Cross-cutting concerns

- **Performance:** viewport culling + level-of-detail on the canvas (CANVAS-9); incremental persistence (SQLite/CRDT deltas); lazy-load pages; budget ink to a native low-latency path.
- **Data safety:** ACID container writes; autosave; snapshot history; corruption in one page recoverable without losing the notebook (OPEN-11).
- **Accessibility & i18n:** treated as requirements (PLAT-5/6), with special attention to the known IME/screen-reader weaknesses of own-canvas frameworks — a factor in the posture decision.
- **Security:** optional at-rest encryption; optional E2E sync; secure key handling via platform secure storage.
- **Extensibility:** the documented model + import/export paths are the first extension surface; a plugin API is a long-horizon goal.

---

## 12. The deep specs (now written)

The follow-up documents this overview previewed now exist and are the build-ready layer:

1. **[File Format Specification](specs/10-file-format-spec.md)** (§5) — the `.onote` container schema (SQLite DDL), encodings, versioning, and the open-folder export mapping.
2. **[Data Model Specification](specs/11-data-model-spec.md)** (§3, §4a) — concrete block structures, identity rules, and the embed reference model.
3. **[Math Input & Storage Specification](specs/12-math-input-spec.md)** (§6) — the linear-input grammar and LaTeX/MathML canonicalization.
4. **[Ink Data Model Specification](specs/13-ink-data-spec.md)** (§7) — stroke encoding, brushes, and InkML interchange.
5. **[Architecture Decision Records](adr/README.md)** — framework (0001), CRDT (0002), storage container (0003), editor engine (0004, open pending bake-off), licensing (0005, proposed).

Still to come in a later pass: the **Sync Protocol Specification** (§8) — update exchange, transports, and the E2E/blind-relay design — deliberately deferred until the CRDT integration is validated in code.

---

## 13. One-diagram summary

```
        OPEN, DOCUMENTED FORMAT (spec + lossless open export)
                          ▲
                          │ persist / export
   pen ─▶ INK ─┐          │
  type ─▶ TEXT ─┼─▶  PAGE = canvas of positioned BLOCKS  ─┐
  math ─▶ MATH ─┘        (CRDT-backed document model)     │ merge
  media ─▶ IMG/FILE ─────┘                                ▼
                                              SYNC (optional, BYO transport,
                                              optional E2E blind-relay) ──▶ your other devices / collaborators
```

*Everything flows through one clean, open, concurrency-ready document model. The UI framework renders it; the file format stores it; sync replicates it — and none of them can trap it.*

---

*This is a design sketch for planning, not a build spec. Every "leading direction" here is a hypothesis to be ratified by the deep specs and de-risked by the prototypes named in the Technology Evaluation.*
