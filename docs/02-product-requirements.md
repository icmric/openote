# Openote — Product Requirements Document (PRD)

> **Document status:** Draft v0.6 · **Implementation phase** · Last updated 2026-07-27
> **v0.6 (this revision):** every requirement below was audited against the code on 2026-07-27 — **25 done · 47 partial · 6 missing · 24 deferred by design** out of 102. Per-requirement evidence lives in the [Phase 1 exit review](reviews/2026-07-code-review-phase1-exit.md); the [Roadmap](../ROADMAP.md) now carries `[~]` markers naming the exact sub-requirements that are unmet. CANVAS-1's body text was corrected to match the shipped behaviour (default width 1100, top-left anchoring, fit-to-width on open). **Counts for reference:** CANVAS has 12 IDs, ORG 10, TEXT 12 (incl. TEXT-1a), MATH 8, INK 11, MEDIA 7, EMBED 9, OPEN 12, SYNC 9, PLAT 10, CODE 2 — §11's traceability table understates several of these.
> **v0.5 changes (iterations 7–9):** the page is now **fully seamless** — the backdrop is the page colour at every zoom (no "page-on-canvas" split), and zooming out lets you place content out in the margin, which extends the page; unused space reconstrains to content (CANVAS-1 v0.5). Added **text auto-width** (grows with content to a max, locks on manual resize), **inline text colour** (`{{#RRGGBB …}}` with a last-colour "flick" hotkey Ctrl+Shift+C) and **box-level font family** (TEXT-14/15); **tables** (MEDIA-3) with spreadsheet-style cell navigation; **backlinks** (TEXT-8); **recycle bin** (ORG-7); the **tabbed command bar** + right-click menus + block clipboard (UI overhaul). New-page cursor lands in the **in-page title**; Enter there drops into the first body box. Math **evaluation/CAS**, **point-and-click math UI**, and **sandboxed code execution** recorded as future "everything-app" goals (Roadmap ▸ Beyond).
> **v0.4 changes (stakeholder-directed, iterations 4–6):** CANVAS-1 refined again — the page presents **seamlessly** at normal zoom (fills the window as one continuous page; the bounded-sheet-on-backdrop look appears only when zoomed out): "a page that can be a canvas," not "a page on a canvas." CANVAS-3 extended with **intelligent placement** (align to writing margin/neighbours; ongoing margin snap on drop). CANVAS-5 amended: **snap-to-grid is ON by default** and the grid is **visible only while dragging** a block. TEXT-2/4 **delivered as true as-you-type rendering** (live-Markdown controller: markers collapse on completion, reveal on caret entry). New **TEXT-13: wrap-selection** — typing a paired character over a selection wraps it (VS Code style). ORG amended: sections, groups, and pages-with-subpages are **collapsible**; pages **drag-and-drop** between sections and onto pages (subpage). Titles edit **in-page**. Keyboard shortcuts must never shadow text input (F-8 class).
> **v0.3 change:** CANVAS-1 refined — the unbounded canvas now *presents* as an auto-growing **page surface** (OneNote-like), per stakeholder direction; see the [iteration-2 code review](reviews/2026-07-code-review-mvp-iter2.md).
> **v0.2 changes:** added **live page embeds / transclusion** (§5.6, EMBED-*); reprioritized ink per stakeholder guidance (near-native latency is no longer a hard requirement — startup speed, consistency, and feature richness rank above it); added the stable-block-identity format requirement (OPEN-12) that embeds depend on; open questions updated now that the framework and stack are provisionally decided (see [ADRs](adr/README.md)).
> **Owner:** Eric · **Audience:** Core team, contributors
> **Related:** [Product Vision](00-product-vision.md) · [OneNote Teardown](01-onenote-teardown.md) · [Technology Evaluation](03-technology-evaluation.md) · [Architecture Overview](04-architecture-overview.md) · [Style Guide](05-style-guide.md)

---

## 1. Purpose and scope

This document specifies *what* Openote does, at a level of detail sufficient to plan and build, while deferring most *how* questions to the [Architecture Overview](04-architecture-overview.md). It is the contract between the vision and the code.

Requirements are identified (e.g. **`CANVAS-3`**) so they can be referenced from issues, tests, and design docs. Each is prioritized with **MoSCoW** (Must / Should / Could / Won't-for-now) and tagged to a release phase (**M** = MVP, **P2**/**P3** = later phases). Priorities reflect the [Roadmap](../ROADMAP.md); where they differ, the Roadmap wins.

### 1.1 Priority legend

| Tag | Meaning |
|-----|---------|
| **Must** | v1 is not credible without it. |
| **Should** | Important; targeted for the first stable release, not necessarily the first MVP. |
| **Could** | Desirable; included if it doesn't cost the schedule. |
| **Won't (now)** | Explicitly out of scope for the current horizon (revisit later). |

### 1.2 Platform priority (from stakeholder input)

Desktop-first (**Windows, macOS, Linux**), with **tablet (iPad, Android tablets, Surface) a close second**, and phone/web later. Linux is a first-class desktop target, not an afterthought — it is one of our clearest wedges against OneNote.

---

## 2. Product pillars → requirement map

Every requirement traces to one of six pillars derived from the vision:

1. **Freeform Canvas** — the infinite, zoomable page with drag-anywhere objects.
2. **Structured Notebooks** — the notebook/section/page hierarchy and navigation.
3. **Expressive Content** — rich text, inline Markdown, math, ink, media, tables, code.
4. **Open & Local** — the open file format, local-first storage, import/export.
5. **Sync & Collaboration** — optional cloud sync and (later) real-time collaboration.
6. **Platform & Craft** — cross-platform parity, performance, accessibility, and polish.

---

## 3. Freeform Canvas

The single most important area. This is what makes Openote *Openote* and not another Markdown app.

| ID | Requirement | Priority | Phase |
|----|-------------|----------|-------|
| CANVAS-1 | The page is an **unbounded 2-D canvas** in the data model, but **presents as a page surface** (v0.3 refinement, per stakeholder): a visibly bounded page (default width **1100** logical px) on a neutral backdrop that **grows automatically** — right and down — as content approaches its edges. Content cannot be placed above/left of the page origin. Panning is clamped so the page cannot be lost off-screen; **the initial view anchors the page top-left** (v0.5: the backdrop is drawn in the page colour so there is no "page floating on canvas" seam), and a page **wider than the window fits-to-width on open** so off-column content — e.g. OneNote-imported images placed right of the text — is visible without hunting. The OneNote page feel, without a hard size limit. | Must | M |
| CANVAS-2 | **Pan** in any direction (drag with hand tool / space-drag / two-finger / trackpad) and **zoom** (pinch, Ctrl-scroll, keyboard), smoothly, at high frame rates. Both vertical and horizontal scrolling are supported. | Must | M |
| CANVAS-3 | **Click (or tap) anywhere** on the canvas to create a **text container** at that point; begin typing immediately. | Must | M |
| CANVAS-4 | Containers and objects can be **freely dragged, moved, and resized** anywhere on the canvas. | Must | M |
| CANVAS-5 | **Placement mode toggle:** objects can be placed **free-form** (any pixel) or **snapped to a configurable grid** to keep pages tidy. The mode is per-page or per-notebook, user-switchable, with a visible (optional) grid overlay. | Must | M |
| CANVAS-6 | **Object types** on the canvas: text container, ink stroke(s), image, math block, code block, table, embedded file, and (later) shapes/connectors. All share a common transform/selection model. | Must (text, ink, image, math); Should (table, code, file) | M / P2 |
| CANVAS-7 | **Selection & manipulation:** single and multi-select (marquee + shift-click), move, resize, delete, duplicate, group/ungroup, z-order (bring forward/back), and alignment guides when moving near other objects. | Must (core); Should (group, align guides) | M / P2 |
| CANVAS-8 | **Lasso select** for ink (and mixed content) to move/transform freehand selections. | Should | P2 |
| CANVAS-9 | **Infinite scroll performance:** the canvas must remain responsive with large pages (target: thousands of objects / hundreds of ink strokes) via viewport culling and level-of-detail rendering. | Must | M |
| CANVAS-10 | **Minimap / overview** and "zoom to fit" / "reset view" controls for navigating large pages. | Could | P2 |
| CANVAS-11 | **Optional page backgrounds:** blank, ruled lines, grid, dotted — as a visual aid (independent of the snap grid). | Should | P2 |
| CANVAS-12 | **Read/write both axes:** content placed far to the right or far down is reachable and the canvas indicates off-screen content (edge hints / minimap). | Should | P2 |

**Acceptance north-star:** a user can reproduce the core OneNote gesture — click in empty space, type, then drag the resulting box elsewhere — within the first minute, on desktop with a mouse and on a tablet with touch/pen, at a frame rate that feels instant.

---

## 4. Structured Notebooks

| ID | Requirement | Priority | Phase |
|----|-------------|----------|-------|
| ORG-1 | Hierarchy: **Notebook → Section Group (nestable, optional) → Section → Page → Subpage.** | Must | M |
| ORG-2 | Create, rename, delete, reorder (drag), and move items between parents at every level. | Must | M |
| ORG-3 | **Multiple notebooks open** simultaneously; switch quickly between them. | Must | M |
| ORG-4 | **Navigation UI:** a notebook/section/page navigator (collapsible sidebar and/or tabs) that scales to thousands of pages without lag. | Must | M |
| ORG-5 | **Page metadata:** title, created/modified timestamps, optional tags, optional color/label. | Must | M |
| ORG-6 | **Subpage nesting** with at least two indent levels, collapsible. | Should | M |
| ORG-7 | **Recycle bin / trash** with recovery for deleted pages and sections (configurable retention). | Should | P2 |
| ORG-8 | **Section/page auto-sort options** (manual, alphabetical, by date) — an oft-requested OneNote gap. | Could | P2 |
| ORG-9 | **Page templates:** built-in templates and user-saved custom templates, applicable on **all platforms** (fixing OneNote's parity gap). | Should | P2 |
| ORG-10 | **Favorites / pinned pages** and a **recent pages** list for fast return. | Could | P2 |

---

## 5. Expressive Content

### 5.1 Rich text & inline Markdown

| ID | Requirement | Priority | Phase |
|----|-------------|----------|-------|
| TEXT-1 | **Rich text editing** within containers: bold, italic, underline, strikethrough, inline code, headings, font family/size/color, highlight, text alignment, bulleted/numbered/checkbox lists, indentation, links. | Must | M |
| TEXT-1a | **Mixed content in one container:** a text block hosts prose, **inline math**, **inline images**, tags, and links in a single flow — the user never leaves the block to insert an equation or picture mid-paragraph (OneNote container behavior). Standalone blocks remain for free canvas placement. ([Data Model Spec §5.1](specs/11-data-model-spec.md)) | Must | M |
| TEXT-2 | **Inline-rendered Markdown ("interpret as you go"):** typing Markdown syntax renders formatting **in place, in the same spot it is written**, as the user types — not in a separate preview pane. E.g. `# ` becomes a heading, `**x**` becomes bold, `- ` starts a list, ``` starts a code block. | Must | M |
| TEXT-3 | Markdown and the formatting toolbar are **two views of one model** — toolbar actions and Markdown syntax produce identical results; content round-trips to Markdown losslessly where the Markdown spec allows. | Must | M |
| TEXT-4 | **Reveal-on-edit syntax:** when the caret enters a formatted span, its Markdown markers become visible/editable (so users can see and adjust the source), then re-render on exit — the Obsidian "Live Preview" pattern. | Should | M |
| TEXT-5 | **Tags** with a built-in library (to-do, important, question, etc.), custom tags, and **cross-notebook tag aggregation / "find tags" summary.** | Should | P2 |
| TEXT-6 | **Clickable to-do checkboxes** with completion state; roll up open items across a notebook. | Should | M (checkbox) / P2 (rollup) |
| TEXT-7 | **Find and replace** within a page and across a notebook — on **every platform** (fixing OneNote's Mac/iOS gap). | Should | M (find) / P2 (replace, cross-notebook) |
| TEXT-8 | **Bidirectional links / backlinks** between pages (`[[Page]]` wiki-links), with a backlinks panel — a top OneNote gap the open ecosystem has proven. | Should | P2 |
| TEXT-9 | **Graph / link view** visualizing connections between pages. | Could | P3 |
| TEXT-10 | **Auto table-of-contents / page outline** from headings, for navigating long content. | Could | P2 |
| TEXT-11 | **Spell-check** using platform facilities. | Should | P2 |

### 5.2 Code

| ID | Requirement | Priority | Phase |
|----|-------------|----------|-------|
| CODE-1 | **Fenced code blocks** with **syntax highlighting** across common languages, monospace font, and preserved formatting on edit — beating OneNote's monospace-only blocks. | Should | M |
| CODE-2 | Language selection (auto-detect + manual), copy-to-clipboard, and optional line numbers. | Could | P2 |

### 5.3 Math

| ID | Requirement | Priority | Phase |
|----|-------------|----------|-------|
| MATH-1 | **Math blocks** (block and inline) rendered as proper 2-D notation. | Must | M |
| MATH-2 | **Linear input that builds up into 2-D**, OneNote-style: a UnicodeMath-like syntax where typing `\sum`, `/`, `^`, `_`, `\int`, etc. autoformats into summations (with limits above/below), fractions, sub/superscripts, integrals, matrices — interpreted as you type. | Must | M |
| MATH-3 | **LaTeX input** accepted as an alternative syntax (the lingua franca) and **used as the canonical stored form**; export to **MathML** for interchange/accessibility. | Must | M |
| MATH-4 | A **symbol & structure palette / virtual math keyboard** for discovering and inserting operators, Greek letters, and templates (fraction, matrix, root, n-ary) — the OneNote equation-toolbar experience. | Should | M / P2 |
| MATH-5 | **Complex notation support:** summation/product/integral with limits, matrices, cases, nested fractions, roots with degree, decorated operators (notation "around the sides"), per the stakeholder's explicit requirement. | Must | M |
| MATH-6 | Math renders **natively** (no separate app feel), re-renders crisply at any zoom/theme, and remains **editable** (source-preserved). | Must | M |
| MATH-7 | **Optional input modes:** AsciiMath as a casual syntax; ink-to-math (see Ink). | Could | P2 |
| MATH-8 | **Solving / step-by-step / graphing.** | **Won't (now)** | — |

### 5.4 Ink & handwriting

| ID | Requirement | Priority | Phase |
|----|-------------|----------|-------|
| INK-1 | **Draw / write anywhere** on the page with a stylus, finger, or mouse — the minimum handwriting bar. | Must | M |
| INK-2 | **Pen tools:** at least pen, highlighter, and eraser; configurable color and width; **pressure sensitivity** (and tilt where available) for natural strokes. | Must | M |
| INK-3 | **Responsive inking:** strokes follow the pen comfortably with no distracting lag. *Near-native ("pen-on-glass") latency is explicitly a non-goal* — per stakeholder direction, ink is an important feature but not the app's center of gravity, and we make no architectural concessions (per-platform front-buffer overlays, etc.) that would cost startup speed, consistency, or feature velocity for marginal latency gains. Flutter's standard pointer/render pipeline is the accepted baseline (the bar: Saber-quality ink). | Must | M |
| INK-4 | **Palm rejection** when a stylus is in use. | Must | M |
| INK-5 | **Smooth stroke rendering** with pressure-responsive variable width (natural pen look, not jagged polylines). | Must | M |
| INK-6 | **Erase** by stroke and by area; **undo/redo** for ink. | Must | M |
| INK-7 | **Lasso-select ink** to move, resize, delete, or recolor freehand selections. | Should | P2 |
| INK-8 | **Ink-to-text** and **ink-to-shape** conversion. | Could | P3 |
| INK-9 | **Ink-to-math** conversion (handwrite an equation → math block). | Could | P3 |
| INK-10 | **Ruler / straight-line** and basic shape assist. | Could | P2 |
| INK-11 | Ink is stored **losslessly** (full stroke geometry, pressure, tilt, timing) in the open format, independent of any recognition. | Must | M |

### 5.5 Media, tables, embeds

| ID | Requirement | Priority | Phase |
|----|-------------|----------|-------|
| MEDIA-1 | **Insert images** (paste, drag-drop, file) as freely-placeable, resizable objects. | Must | M |
| MEDIA-2 | **Embed/attach files** on the page (open with the system default; stored in the notebook bundle). | Should | M |
| MEDIA-3 | **Tables** with add/remove rows-columns, cell editing, and **Markdown-table interop**. | Should | P2 |
| MEDIA-4 | **OCR of inserted images** so their text is searchable. | Could | P3 |
| MEDIA-5 | **Audio recording linked to notes** (jump playback to when a note was written) — a distinctive OneNote feature. | Could | P3 |
| MEDIA-6 | **Web clipper** (browser extension) that captures pages/regions with **high fidelity** and the source URL — directly attacking a known OneNote weakness. | Could | P3 |
| MEDIA-7 | **Embed video / web content** links. | Could | P3 |

### 5.6 Links, references & live embeds (transclusion)

OneNote's page/paragraph links are navigation-only — a known weak spot. Openote goes further: in addition to ordinary links and wiki-links (TEXT-8), a user can **embed a live, rendered view of part of another page** inside the current page. The embed is a box on the canvas that renders the *actual current content* of the source — a block, a set of blocks, or a spatial region — updating when the source changes. Per stakeholder direction, embeds are **read-only** in v1: clean, uncluttered, click-through to the source. (Prior art: Obsidian `![[Note#^block]]` embeds, Logseq `{{embed}}`, Notion synced blocks, Dendron range references, BlockSuite synced-doc blocks; design lessons from each are baked into the requirements below and the [Data Model Spec](specs/11-data-model-spec.md).)

| ID | Requirement | Priority | Phase |
|----|-------------|----------|-------|
| EMBED-1 | **Page links:** link to any notebook, section, page, or block; clicking navigates there. Links are by **stable ID**, so they survive rename and move. | Must | M |
| EMBED-2 | **Live embeds (transclusion):** embed a rendered, live view of another page's content — (a) a single block, (b) a contiguous set of blocks / range between two anchors, or (c) a **spatial region** of a canvas page — as a resizable box on the current page. Content re-renders when the source changes. | Should | P2 |
| EMBED-3 | Embeds are **read-only** in place. Interaction affordances: click-through (empty area or a dedicated "open source" button) navigates to the source; a subtle badge shows the source page's name; hover shows a preview/affordance. Links *inside* embedded content remain clickable. | Should | P2 |
| EMBED-4 | **Visual treatment:** embeds are visibly distinct from native content (quiet border + source badge per the [Style Guide](05-style-guide.md)) without shouting. | Should | P2 |
| EMBED-5 | **Robust identity:** embeds reference `(pageID, target)` — never titles or coordinates alone — so they survive source rename, move, and reorganization. Spatial-region embeds prefer targeting a **frame/group object** (which moves with its content) over a raw coordinate rectangle; a marquee-created region is auto-promoted to a lightweight frame. | Should | P2 |
| EMBED-6 | **Broken-reference handling:** if the source is deleted, the embed renders its **last-known snapshot**, grayed, with a "source deleted" badge and actions (remove embed / detach as static copy). Deleting content that is embedded elsewhere warns the user ("embedded in N pages"). | Should | P2 |
| EMBED-7 | **Cycle safety:** circular embeds (A embeds B embeds A) are detected in the shared render path (not per-surface) and render as a placeholder chip; a depth cap (default 3) bounds legitimate nesting. Applies identically to on-screen rendering **and** export. | Should | P2 |
| EMBED-8 | **Export semantics:** PDF/print inlines a snapshot of the embed with a "from: *Page*" caption (cycle-safe); Markdown export offers inline-snapshot-with-attribution or plain-link. Proprietary embed syntax is never the only exported representation. | Should | P2 |
| EMBED-9 | **Editable embeds / synced blocks** (edit-in-place propagating to the source, Notion-style). | **Won't (now)** — the data model must not preclude it | — |

> **Format dependency (why part of this is MVP):** live embeds ship in P2, but they only work if every block already has a **stable, eagerly-assigned UUID** from day one (see OPEN-12). Obsidian and Logseq assign IDs lazily inside text files and suffer chronic broken-reference bugs (IDs destroyed by cut/paste and merges); Notion, AFFiNE, and Roam assign eagerly in the data model and don't. We are database-native, so eager IDs cost nothing — this decision is locked at MVP even though the feature it enables comes later.

---

## 6. Open & Local (format, storage, import/export)

This pillar is the reason the project exists. See the [Architecture Overview](04-architecture-overview.md) for the format design; requirements here state the guarantees.

| ID | Requirement | Priority | Phase |
|----|-------------|----------|-------|
| OPEN-1 | Openote's file format is **open, publicly documented, versioned, and permissively licensed** — the specification ships alongside v1. | Must | M |
| OPEN-2 | Notes are stored **locally by default**; the app is fully usable offline with no account and no cloud. | Must | M |
| OPEN-3 | The format **does not require Openote, our servers, or the project's continued existence** to read — it is built from inspectable, well-understood building blocks (see Architecture). | Must | M |
| OPEN-4 | **Math is stored semantically** (canonical LaTeX + MathML export), never as a flattened image, so equations stay editable and re-renderable. | Must | M |
| OPEN-5 | **Ink is stored as open, documented stroke data** (geometry + pressure/tilt/time), with **InkML** as an import/export interchange target. | Must | M / P2 (InkML I/O) |
| OPEN-6 | **Canvas geometry** is representable in / interoperable with an open canvas format; we adopt or extend **JSON Canvas** for interchange where practical. | Should | P2 |
| OPEN-7 | **Export:** to Markdown, PDF, HTML, and open interchange (MathML, InkML, JSON Canvas) — first-class, lossless where the target allows, and available on **every platform** (fixing OneNote's export gaps). | Should | P2 (Markdown/PDF earlier) |
| OPEN-8 | **Import from OneNote** (`.one` / `.onepkg`) preserving structure, text, images, and — as far as feasible — ink and tags. The headline migration wedge. | Should | P3 |
| OPEN-9 | **Import from Markdown / Obsidian / JSON Canvas** and other open formats. | Could | P2 |
| OPEN-10 | **No artificial size limits** on notebooks, sections, pages, or attachments (unlike OneNote's caps). | Must | M |
| OPEN-11 | Data is **inspectable and recoverable** — a technically-minded user can open the storage and understand it; corruption in one part does not destroy the whole notebook. | Must | M |
| OPEN-12 | **Stable identity everywhere:** every notebook, section, page, and block carries an **eagerly-assigned, immutable UUID** from creation, preserved across edit, move, and cut/paste within the app; split/merge semantics are specified (see [Data Model Spec](specs/11-data-model-spec.md)). This underpins links, backlinks, embeds, and sync. | Must | M |

---

## 7. Sync & Collaboration

Per the brief, live collaboration is a *helpful* nice-to-have; **cloud sync in some form is a real requirement** for cross-device use. The architecture (CRDT-based) is chosen so that good sync and future collaboration share one foundation.

| ID | Requirement | Priority | Phase |
|----|-------------|----------|-------|
| SYNC-1 | **Cross-device sync** so a user can work on the same notebooks across multiple devices. | Should (a real requirement, targeted early-P2) | P2 |
| SYNC-2 | **Local-first, conflict-free merge:** offline edits on multiple devices merge without data loss or manual conflict resolution (CRDT-based) — directly attacking OneNote's #1 complaint. | Should | P2 |
| SYNC-3 | **Bring-your-own sync target:** support syncing via user-controlled backends (e.g. WebDAV/Nextcloud, S3-compatible, a synced folder in an existing cloud drive), not only a first-party service — following Joplin's flexibility. | Should | P2 |
| SYNC-4 | **Optional first-party sync service** for users who want turnkey sync. | Could | P3 |
| SYNC-5 | **End-to-end encryption option** for synced data, designed so content stays **locally searchable** (index on-device) and the server can be a blind relay. | Could | P3 |
| SYNC-6 | **Real-time collaboration:** multiple people editing a shared notebook/page live, with presence/cursors. | Could | P3 |
| SYNC-7 | **Sharing & permissions** (view/edit) at notebook and, ideally, section/page granularity (finer than OneNote's notebook-level). | Could | P3 |
| SYNC-8 | **Version history** browsing and restore for pages. | Could | P2 |
| SYNC-9 | **Block ownership & locking** (stakeholder-noted, for large-team/classroom collaboration): a block's owner can set it **unlocked**, **locked-except-owner**, or **fully locked**, governing who may edit its content, position, and properties. Enforced at the sync/collab layer; the data model reserves the `access` field from v1 so the format never needs a breaking change to add it ([Data Model Spec §3](specs/11-data-model-spec.md)). | **Won't (now)** — field reserved at MVP | P3+ |

---

## 8. Platform & Craft (non-functional requirements)

| ID | Requirement | Priority | Phase |
|----|-------------|----------|-------|
| PLAT-1 | **Native desktop apps for Windows, macOS, and Linux** from a single codebase, with Linux treated as first-class. | Must | M |
| PLAT-2 | **Tablet support** (iPad, Android tablets, Surface) with touch + pen as a close-second priority. | Must (pen/touch canvas) | M / P2 |
| PLAT-3 | **Phone** and **web** builds. | Could | P3 |
| PLAT-4 | **Performance budgets (priority order per stakeholder):** (1) **fast startup** — cold start to an editable page in ≤ 2 s on a mid-range machine, warm start ≤ 1 s; (2) **consistency** — identical behavior and rendering across Windows/macOS/Linux (one bundled renderer, no per-platform surprises); (3) instant-feeling canvas pan/zoom (≥ 60 fps target) and fast page load even for large notebooks; (4) **comfortable** ink responsiveness (see INK-3 — near-native pen latency is explicitly not chased at the expense of 1–3). | Must | M |
| PLAT-5 | **Accessibility:** keyboard navigation, screen-reader support, adjustable text sizing, sufficient contrast, and reduced-motion support — on desktop and mobile. (A known weak spot in some frameworks; treat as a requirement, not a hope.) | Should | M/P2 |
| PLAT-6 | **Internationalization:** correct text input for complex scripts and IMEs (CJK etc.), RTL support, and translatable UI. | Should | P2 |
| PLAT-7 | **Light and dark themes**, honoring the OS preference, per the [Style Guide](05-style-guide.md). | Must | M |
| PLAT-8 | **Native platform conventions:** menus, keyboard shortcuts, file dialogs, and drag-drop that feel right per OS. | Should | M/P2 |
| PLAT-9 | **Data safety:** autosave, crash-safe writes (no half-written corruption), and a clear backup/export story. | Must | M |
| PLAT-10 | **Open-source project hygiene:** public repo, permissive/appropriate license, contribution guide, and a published format spec (see [CONTRIBUTING](../CONTRIBUTING.md)). | Must | M |

---

## 9. MVP definition (the "core essentials" cut)

The MVP is the smallest build that is *unmistakably Openote* and genuinely useful to the switcher on day one. It is **desktop-first (Win/macOS/Linux), single-device, local-only, no sync.**

**In the MVP:**

- Freeform infinite canvas: pan, zoom (both axes), click-to-create text container, drag/resize/move, free **and** snap-to-grid placement. *(CANVAS-1–7, 9)*
- Notebook hierarchy: notebook / section / page / subpage, create/rename/reorder, navigator sidebar, multiple notebooks. *(ORG-1–6)*
- Rich text with **inline-rendered Markdown** and reveal-on-edit; lists, headings, links, checkboxes; find. *(TEXT-1–4, 6, 7 find)*
- **Math blocks** with linear-builds-to-2D input, LaTeX canonical storage, native rendering, complex notation, a basic symbol palette. *(MATH-1–6)*
- **Ink:** write/draw anywhere with pen/highlighter/eraser, pressure, palm rejection, smooth responsive strokes, lossless storage, undo. *(INK-1–6, 11)*
- **Page & block links** by stable ID; **eager UUIDs on every block** (the format foundation live embeds build on). *(EMBED-1, OPEN-12)*
- Images inline; file attach. *(MEDIA-1–2)*
- Code blocks with syntax highlighting. *(CODE-1)*
- **The open, documented file format v1**, local-first, no size limits, crash-safe, inspectable; Markdown + PDF export. *(OPEN-1–5, 10, 11; OPEN-7 partial)*
- Light/dark themes; the core of the style guide; baseline accessibility. *(PLAT-1, 4, 7, 9)*

**Explicitly deferred past MVP:** sync/collaboration, OneNote import, **live embeds/transclusion (EMBED-2+)**, ink recognition, backlinks/graph, tables, OCR, audio, web clipper, templates, phone/web, and math solving.

**MVP success test:** *A OneNote user installs Openote on Linux, recreates a typical page — mixed typed text, a hand-drawn diagram, and a summation equation, freely arranged — saves it as an open file on their own disk, and reopens it cleanly. Nothing about that flow required a Microsoft account, a subscription, or a supported OS list that excludes them.*

---

## 10. Decision status (formerly "open questions")

Most of v0.1's open questions are now **provisionally decided** and recorded as [Architecture Decision Records](adr/README.md); the remainder stay open.

| Question | Status | Where |
|----------|--------|-------|
| Framework | **Decided (provisional):** Flutter/Dart UI + Rust core | [ADR-0001](adr/ADR-0001-application-framework.md) |
| CRDT library | **Decided (provisional):** Loro via Rust FFI (`yrs` as documented fallback) | [ADR-0002](adr/ADR-0002-crdt-library.md) |
| Storage container | **Decided (provisional):** SQLite-based `.onote` package + lossless open-folder export | [ADR-0003](adr/ADR-0003-storage-container.md), [File Format Spec](specs/10-file-format-spec.md) |
| Rich-text editor engine | **Decided — keep the engine we own**, behind the `OnoteTextEditor` seam; the two-way bake-off was not run | [ADR-0004](adr/ADR-0004-editor-engine.md) |
| Sync storage layout | **Proposed** — append-only per-device op log in a `.onotebook` directory; SQLite demoted to a local cache | [ADR-0006](adr/ADR-0006-sync-transport-and-text-model.md) |
| Math canonical form | **Decided:** LaTeX canonical, MathML export, UnicodeMath-style input mode | [Math Input Spec](specs/12-math-input-spec.md) |
| License | **Proposed, needs stakeholder ratification:** app AGPL-3.0; format spec CC0/MIT; reference libraries Apache-2.0 | [ADR-0005](adr/ADR-0005-licensing.md) |
| Ink recognition vendor | Open (deferred by design — P3) | [Ink Data Spec](specs/13-ink-data-spec.md) |
| JSON Canvas interop depth | Open (export-side interop committed; import fidelity TBD) | [File Format Spec §9](specs/10-file-format-spec.md) |
| Real-time collab in first stable? | Open (architecture supports it; scheduling call for P3) | [Roadmap](../ROADMAP.md) |

---

## 11. Traceability summary

| Pillar | Key requirement IDs | MVP? |
|--------|--------------------|------|
| Freeform Canvas | CANVAS-1…12 | Core in MVP |
| Structured Notebooks | ORG-1…10 | Core in MVP |
| Expressive Content | TEXT, CODE, MATH, INK, MEDIA, EMBED | Text/Math/Ink/Code/Images + links in MVP; live embeds P2 |
| Open & Local | OPEN-1…11 | Format + export in MVP |
| Sync & Collaboration | SYNC-1…8 | Post-MVP (P2/P3) |
| Platform & Craft | PLAT-1…10 | Desktop + perf + themes in MVP |

---

*The deep specifications this PRD defers to now exist: the [File Format Spec](specs/10-file-format-spec.md), [Data Model Spec](specs/11-data-model-spec.md), [Math Input Spec](specs/12-math-input-spec.md), [Ink Data Spec](specs/13-ink-data-spec.md), and the [ADRs](adr/README.md).*
