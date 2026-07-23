# OneNote Teardown & Gap Analysis

> **Document status:** Draft v0.1 · Planning phase · Last updated 2026-07-22
> **Purpose:** A structured teardown of Microsoft OneNote — what it does, what it does *better than anyone*, and where it fails users — used to define what Openote must match, what it must fix, and what it can safely skip.
> **Related:** [Product Vision](00-product-vision.md) · [Product Requirements](02-product-requirements.md)

---

## 1. How to read this document

This is competitive intelligence, not a review. Each section catalogues a capability area, then draws an explicit **→ Openote implication** so the analysis feeds directly into the requirements. Three tags recur:

- **🛡️ Moat** — something OneNote does better than any competitor. We must at least approach it to be credible.
- **⚠️ Weakness** — something users consistently complain about. Our opportunity.
- **🎯 Wedge** — a weakness so acute it can justify switching on its own.

Sourcing note: features and complaints below are drawn from Microsoft's own documentation, the MS-ONESTORE open specification, review aggregators (G2 ~4.5★/1,860 reviews; Capterra ~4.6★/1,900 reviews), and real user voices (Reddit r/OneNote, Microsoft community forums, migration blogs), 2023–2026. Where a figure comes from a single third-party source it is flagged.

---

## 2. Feature catalogue

### 2.1 Organization model 🛡️
Notebooks → Section Groups (optional, nestable) → Sections → Pages → Subpages (roughly two indent levels). The "tabbed ring binder" metaphor is widely found intuitive and scales to thousands of pages while staying navigable. Sections and groups reorder by drag.

Under the hood, **each section is one `.one` file**; a notebook is a folder of section files plus a `.onetoc2` table of contents. This granularity matters — it is the seam along which sync conflicts and corruption occur.

**→ Openote implication:** Replicate the hierarchy (notebook / section group / section / page / subpage) — it is a core part of what users mean by "OneNote." But do **not** inherit the one-file-per-section storage model that causes sync fragility. See [Architecture](04-architecture-overview.md).

### 2.2 The freeform canvas 🛡️🎯
The signature capability. Click anywhere on a page to create a floating **text container**; drag, resize, and place it freely. Pages are **unbounded** — no page size, growing in any direction. Optional rule/grid lines exist for print. No competitor with a real organizational model matches this "drop content anywhere on an infinite page" surface; document-flow and Markdown editors (Notion, Obsidian, Evernote) simply do something else.

**→ Openote implication:** This is requirement zero. The infinite pannable/zoomable canvas with drag-anywhere, snap-or-free-placed containers is the heart of the product. It is also the hardest thing to build well — see the [Technology Evaluation](03-technology-evaluation.md).

### 2.3 Rich text, tags, to-dos
Standard rich text (fonts, sizes, colors, emphasis, lists, styles, highlighting). A built-in **tag library** (To-Do checkbox, Important, Question, Remember, Definition, custom tags) with **Find Tags** to aggregate tagged items across a notebook — e.g. roll every checkbox into one summary. Clickable to-do checkboxes.

**⚠️ Weakness — code:** Code support is monospace-only with **no syntax highlighting**, and formatting frequently breaks on edit. A repeated complaint from technical users.

**→ Openote implication:** Match rich text and tags (including cross-notebook tag aggregation — it is quietly one of OneNote's best organizational features). Beat OneNote outright on code blocks with real syntax highlighting.

### 2.4 Ink and handwriting 🛡️
Best-in-class. Multiple pen/pencil/highlighter types (fountain and brush pens added 2025), pressure sensitivity, palm rejection across Surface / iPad (Apple Pencil) / Wacom. **Lasso Select**, **Ink-to-Shape**, **Ink-to-Text** (multi-language), a **ruler** tool, **ink replay** (animated stroke playback), an ink eyedropper, and AI handwriting straightening.

**→ Openote implication:** Strong pen support is non-negotiable for the pen-and-math persona and a headline differentiator versus the open Markdown crowd. v1 target: smooth, low-latency, pressure-sensitive ink you can write and mark with, plus lasso-move. Ink-to-text and ink-to-shape are desirable but **later** — recognition is a deep, and currently not-fully-open, problem.

### 2.5 Math 🛡️ / ⚠️
Two input paths: **type** a linear format (UnicodeMath, e.g. `(x^2+4)/(x-3)`) that builds up into 2-D notation, or **handwrite** and convert via the Ink Math Assistant. A symbol/structure palette supports complex notation — summation with limits above and below, integrals, matrices, fractions. Downstream, the Math Assistant **solves**, shows **step-by-step** methods, and **graphs**.

**⚠️ Weakness — paywall:** Per Microsoft's own support docs, solving and step-by-step require an **Enterprise or Education** Microsoft 365 subscription — not consumer Personal/Family. (Enforcement has historically been inconsistent across builds; treat as directionally true.)

**→ Openote implication:** The *entry and rendering* experience is what users love and can be matched with open tech (UnicodeMath-style linear input + LaTeX/MathML storage + fast rendering). Match that. **Solving is an explicit non-goal for v1** — it is a deep well, and it is the part Microsoft paywalls, so skipping it costs us little goodwill and saves enormous effort.

### 2.6 Media, capture, OCR
Images (with **OCR** — extract and search text from pictures/scans), embedded files and "insert as printout," in-app audio/video recording with **audio time-linked to notes** (jump the recording to the moment a note was typed), screen clipping, and a browser **Web Clipper**. Document scanning historically via Office Lens → Microsoft Lens (being retired late 2025 / early 2026, folding into OneDrive scan / Copilot).

**⚠️ Weakness — clipping fidelity:** Web/paste-from-web fidelity is poor — broken spacing, tiny heading fonts, pulled-in ads; mobile doesn't capture the source URL. This specific failure is documented as the trigger that drove a 13-year OneNote user to Obsidian.

**→ Openote implication:** Images with searchable OCR text, embedded files, and audio-linked-to-notes are strong, differentiated features to target (OCR and audio-link later; embeds earlier). A clean, high-fidelity web clipper is a concrete way to win switchers.

### 2.7 Tables and embeds
Native tables (convertible to Excel; cell-merge added 2025), embedded live Excel spreadsheets, and embeds of online video, files, and Microsoft Loop components.

**→ Openote implication:** Tables are expected — include them (ideally with Markdown-table interop). Deep Office/Loop embedding is out of scope; generic file and image embeds are in.

### 2.8 Search
Full-text search across all notebooks, including **OCR text inside images** and, on supported platforms, **handwriting/ink search**. (Legacy phonetic audio search is largely deprecated.)

**⚠️ Weakness:** Locked (password-protected) sections are excluded from search; the Android app has historically lacked "find next"; query depth is shallow.

**→ Openote implication:** Fast local full-text search across the whole workspace is table stakes. Searching OCR'd image text and ink is a later differentiator. Design the index so encrypted content can be searched locally (index stays on-device) — avoiding OneNote's "locked = invisible" trap.

### 2.9 Sync, offline, history ⚠️🎯
Sync via OneDrive (personal) or SharePoint/OneDrive for Business. **The free tier is cloud-only — no local-only notebooks** without a paid Office/365 license. Each device keeps an offline cache and merges on reconnect. Desktop keeps **page version history** and a notebook recycle bin (deleted pages recoverable ~60 days); version history is a paid/desktop feature.

**⚠️ Weakness — the #1 complaint:** Sync problems dominate every review source — delays, silent failures ("not connected" with no error), merge conflicts, and outright **corruption**, made worse by large sections (a ~2 GB/section soft ceiling on personal OneDrive is widely reported; single-third-party-source figure). Attachment inserts are capped (<100 MB on personal accounts).

**→ Openote implication:** This is a wedge. Local-first storage with robust, conflict-free merging (CRDT-based — see [Architecture](04-architecture-overview.md)) directly attacks OneNote's most-hated failure. And local notebooks must be **free and default**, never a paywalled tier.

### 2.10 Collaboration
Real-time co-authoring on a shared page; sharing by link or invite with **notebook-level** permissions (coarse — no per-section/page permissions in consumer). Reviews note it is "less seamless than Google Docs."

**→ Openote implication:** Real-time collaboration is a *nice-to-have* for us (per the brief), but the architecture we need for good sync (CRDTs) gives us a credible collaboration path almost for free. Design for it; ship it later.

### 2.11 Templates ⚠️
Built-in page templates and custom templates (save any page as a template, set a section default).

**⚠️ Weakness — parity:** Custom templates are effectively **Windows-desktop-only**; Mac, iOS and web lack or limit them. A recurring cross-platform-parity complaint.

**→ Openote implication:** Ship templates as a genuinely cross-platform feature — the parity gap is an easy win.

### 2.12 Integrations, AI, security
Outlook / Teams / Word / Excel / Loop / Immersive Reader / Class Notebook, and two tiers of **Copilot** AI (in-OneNote summarize/draft, and 2025's "Copilot Notebooks"), both requiring a Copilot license. **Section-level** password protection (128-bit AES; Microsoft cannot recover a forgotten password) — but section-only (no page/notebook granularity), unsupported on the retired Windows 10 app, and locked sections aren't searched.

**→ Openote implication:** Deep Microsoft-ecosystem integration is neither achievable nor desirable for us — our audience is partly *fleeing* that ecosystem. Encryption, however, matters: design for optional, well-scoped encryption whose content stays locally searchable. AI is explicitly not our positioning.

### 2.13 Page linking ⚠️
OneNote can create links to notebooks, sections, pages, and even individual paragraphs ("Copy Link to Paragraph"). But the feature is **navigation-only and brittle**: no content is rendered at the link site (no preview, no live view), paragraph links give no visual anchor at the destination, behavior differs across OneNote versions, and recent builds changed paragraph links to web-only URLs, breaking established `onenote:` workflows. Users who want to *see* related content from another page must duplicate it — and duplicates immediately drift out of date.

**→ Openote implication (a headline feature):** go beyond links to **live embeds (transclusion)** — render a chosen block, range, or region of another page inside the current page, read-only, always current, click-through to the source. The open-source world has proven the pattern (Obsidian embeds, Logseq `{{embed}}`, Notion synced blocks, Dendron range refs); no OneNote-style freeform app has it. See PRD §5.6.

### 2.14 Platform availability ⚠️🎯
Windows (a single unified desktop app since the Windows 10 UWP app reached end of support October 2025 — ending years of two-coexisting-apps confusion), macOS, iOS/iPadOS, Android, ChromeOS, and web. **No native Linux client** — only the web app, Wine, or unofficial third-party wrappers.

**→ Openote implication:** **Linux is a first-class target and a clean wedge.** True feature parity across desktop platforms is a differentiator in itself, given OneNote's uneven parity even among its supported platforms.

---

## 3. The file-format problem (the central wedge) 🎯

This deserves its own section because it is the strategic core of the whole project.

**What the format is.** A `.one` file is a single *section*, stored as a binary **Revision Store** (a revision-log structure of cross-referenced object spaces). `.onetoc2` is the notebook's table of contents. `.onepkg` is a CAB archive bundling `.one` files — the only "whole notebook as one file" export, and it is useless outside OneNote.

**Why it is lock-in.** The Revision Store is binary and hard to parse outside Microsoft's stack, and in the consumer product your notes are tied to OneDrive — on the free tier you cannot keep a purely local copy. Reviewers routinely describe the data as "trapped."

**The important nuance (state it precisely).** Microsoft *does* publish **[MS-ONESTORE]** (v13.3, May 2025) under the Open Specification Promise. So "completely closed/proprietary," as many blog comparisons claim, is **technically inaccurate**. The accurate framing is: *the format is documented but impractical to use outside OneNote* — the spec covers the storage container, not a friendly semantic document model, and real third-party implementations are scarce and fragile. **We should use this precise framing publicly; overstating the lock-in is easy to rebut and damages credibility.**

**Export reality.** Windows desktop exports pages/sections/notebooks to PDF, Word, `.one`, `.onepkg`. Mac exports **PDF only, page-by-page** (no whole-notebook export). Web has **no native export** at all. On export, ink, tags and embedded media are frequently lost or mangled; images inside tables break; password-protected sections are skipped. There is **no first-party Markdown export**; migrating out relies on third-party tools that need desktop OneNote + Word + Pandoc, run on Windows only, and drop handwriting, tags, and formatting.

**→ Openote implication — this is our thesis made concrete:**
1. Openote's own format is **open, documented, versioned, and permissively licensed** from day one — the opposite of "documented but impractical."
2. We provide a **clean, lossless importer** from `.one` / `.onepkg` (preserving ink and tags as far as possible) — the single strongest wedge against OneNote, because Microsoft makes leaving so hard.
3. We provide **first-class export** (including Markdown and open interchange formats) so Openote never becomes the thing it replaced.

---

## 4. Ranked complaints (our opportunity map)

Aggregated across review sites, Reddit, forums and migration blogs, most-frequent first:

1. **Sync problems / conflicts / corruption** — the #1 complaint everywhere. → *local-first + CRDT merge.*
2. **Performance with large notebooks** — laggy typing, slow load/scroll. → *performance budget as a first-class requirement.*
3. **Proprietary format / cloud lock-in / no true local storage** on free tier. → *open format, local-first, free.*
4. **Weak, lossy export; no Markdown.** → *first-class open export + Markdown.*
5. **Cross-platform parity gaps** — templates, find-and-replace, password protection missing on some platforms. → *genuine parity, Linux included.*
6. **The historical Win10-app vs desktop confusion.** → *one app, one experience.*
7. **Poor web-clipping / paste fidelity.** → *a clipper that actually works.*
8. **Weak code support (no syntax highlighting).** → *real code blocks.*
9. **Freeform gets messy; cluttered ribbon.** → *snap-to-grid option; calm, uncluttered UI.*
10. **No native Linux client.** → *Linux is first-class.*
11. **Subscription creep** (math solve, AI, local notebooks). → *free and open.*
12. **Search limitations** (locked sections invisible, weak operators). → *whole-workspace search incl. encrypted, on-device.*
13. **Size limits** (2 GB/section, 100 MB attachments). → *no artificial ceilings.*

**Most-requested features OneNote lacks:** native Markdown, true local/offline storage, **bidirectional links / backlinks / graph view**, **live embeds of other pages' content** (its paragraph links are navigation-only — see §2.13), auto table-of-contents / page outline, cross-platform templates and find-and-replace, lossless export, syntax-highlighted code, a Linux client, section/page auto-sort, and nested tags.

Several of these (backlinks, graph view, Markdown, code) are things the *open* ecosystem already does well — so we can adopt proven patterns rather than invent.

---

## 5. The moat, summarized

To be a credible alternative, Openote must at minimum approach OneNote on the things no one else has matched:

1. **A genuine freeform infinite canvas** with drag-anywhere containers.
2. **Strong pen/ink** (and, later, ink-to-text/math).
3. **The notebook/section/page hierarchy.**
4. **Beautiful complex-equation entry.**
5. (Bonus moat items OneNote also holds: OCR-searchable images, audio-linked-to-notes.)

While **winning on OneNote's weaknesses**: open/local/free format, Markdown, backlinks, **live embeds/transclusion**, clean import/export, Linux, code blocks, and rock-solid sync.

---

## 6. What we deliberately skip (at least for v1)

Learning from OneNote's *scope*, not just its faults:

- **Math solving / CAS / graphing** — non-goal (deep, and the paywalled part).
- **Handwriting recognition** — deferred; store ink losslessly first.
- **Deep Office/Teams/Loop/Copilot integration** — not our audience.
- **AI-first features** — not our positioning.
- **Enterprise governance / Class Notebook** — post-v1 at the earliest.

---

## 7. One-paragraph synthesis

OneNote is beloved for four things nobody else combines — a freeform canvas, real ink, a notebook hierarchy, and beautiful math entry — and resented for four things Microsoft won't fix: a locked format, a mandatory cloud, uneven cross-platform parity (no Linux), and subscription gates on core capabilities. **Openote's entire strategy is to match the first four with open technology and eliminate the second four by construction.** The importer that frees trapped `.one` notebooks, the open documented format, the Linux client, and local-first sync that doesn't corrupt are, together, a reason to switch that no existing product offers.

---

## 8. Competitive landscape (reference)

Condensed from landscape research; full detail feeds the [Vision positioning table](00-product-vision.md#7-positioning).

- **AFFiNE** — closest architecturally (unified docs + edgeless canvas + database, local-first, Yjs CRDT). But **no real ink**, **open-*core*** (MIT client, proprietary server for sync/collab), and a reputation for instability and breaking changes. *Lesson: the unified canvas+blocks+CRDT model is right; the ink gap and open-core caveat are its opening for us.*
- **Obsidian** — the openness benchmark: notes are **plain Markdown files on disk**, and its **Canvas** uses the open **JSON Canvas** format (spec v1.0, MIT). But the **app itself is closed-source freeware**, has no real-time collab, and no first-class ink. *Lesson: "your notes are just files" is the openness gold standard; adopt/extend JSON Canvas for interop.*
- **Logseq** — open-source outliner; its migration from plain Markdown files to a **SQLite DB** version is a live cautionary tale of the *plain-files-vs-database* trade-off (the DB version breaks folder-based sync). *Lesson: choose the storage model deliberately; it is load-bearing.*
- **Joplin** — mature, truly open (MIT), the **widest sync-target list** (Dropbox/OneDrive/Nextcloud/WebDAV/S3/Joplin Cloud) with E2E encryption. But Markdown-only, no canvas, no ink. *Lesson: flexible, bring-your-own sync targets are a real differentiator.*
- **Saber** — the most directly relevant reference: an **open-source (GPL-3) Flutter handwriting app** shipping on Windows/macOS/Linux/iOS/Android/web, with Nextcloud/WebDAV E2E sync and a BSON-based single-file bundle format. *Proof that high-quality cross-platform ink in Flutter is achievable.*
- **Xournal++** — the FOSS **ink/PDF-annotation** benchmark (pressure pens, `.xopp` gzipped-XML stroke format). *Study its stroke representation.*
- **Excalidraw** — open **`.excalidraw` JSON** canvas format, plus the clever trick of embedding the editable scene inside a PNG/SVG. *A model for open, self-contained canvas artifacts.*
- **Anytype** — local-first, E2E-encrypted object graph over its open `any-sync` protocol — but the **clients are source-available, not OSI open source**, and there's no canvas or ink.
- **Nebo / MyScript, Apple Notes, Samsung Notes** — set user expectations for stylus latency and ink/math recognition, but are all **proprietary and platform-locked**, with no Linux and no interop. *They define the ink/math bar; their lock-in is the exact gap we exploit.*

**The through-line:** the FOSS world has each ingredient — canvas (Excalidraw, tldraw), ink (Xournal++, Saber), notebooks (Joplin, Logseq), open formats (Obsidian, JSON Canvas) — but **no one has combined all of them, cross-platform with Linux, in a fully open product.** That un-combined intersection is Openote.

---

*Sources are catalogued in the research briefs backing this document. Figures flagged as single-third-party-source (2 GB/section, 100 MB attachment) should be primary-source-confirmed before any public claim.*
