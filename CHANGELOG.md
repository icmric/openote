# Changelog

All notable changes to Openote. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [SemVer](https://semver.org/) with the caveat that **the file format has its own versioning** (File Format Spec §2) and format compatibility is the promise that matters most here.

## [Unreleased — 0.2.0] · the first public release

### Compatibility promise

From 0.2.0 onward: **notebooks created by any Openote release open in every later release.** Format v1 (the `.onote` container) and op-log v1 (the `.onotebook` directory) freeze at this release; future format changes bump the format version and migrate one-way-forward.

### Added — student release features (2026-08-03)
- **Flashcards from your own notes.** Tag a line Question or Definition while taking notes; the week before the exam Openote quizzes you on them, with spaced repetition. A `==highlight==` inside a tagged line becomes a fill-in-the-blank. Export to Anki if you'd rather revise there.
- **Maths that computes.** Type an expression in an equation block and see the answer — arithmetic, powers, roots, trig, logs, factorials, constants. OneNote charges an Education subscription for this.
- **Cloud sync through a folder your cloud already syncs.** Move a notebook into Drive, OneDrive, iCloud, Dropbox, Nextcloud or Syncthing and your devices stay in step — no account, no sign-in, and Openote never gets access to the rest of your Drive. Changes from other devices are pulled automatically. Self-hosting works the same way, with nothing exposed to the network.
- **Annotate lecture slides.** Insert ▸ PDF slides turns each page of a PDF into a page you can write on with the pen, and the slide's text stays searchable. GoodNotes and Notability charge for this and only on Apple; OneNote's version loses the text.
- **Paste and drag-drop.** Paste a screenshot straight onto the page; drop files on it to add them.
- **Resize anything properly** — corner and bottom handles, with ink scaling instead of being clipped; **alignment guides** that snap a block flush with its neighbours; **drag pages to reorder** them, with subpages coming along; **recolour lassoed ink**.
- **Find and replace**, spell-check **suggestions** on right-click with "Add to dictionary", **Ctrl+1–5** tag shortcuts, **copy link to page**, and ``` + Enter to open a code fence.

### Fixed — student release (2026-08-03)
- **JPEG photos now survive a OneNote import.** The importer only recovered PNGs, so phone photos of whiteboards and worksheets silently vanished.

### Added
- **Licence** — the project is now legally open source: AGPL-3.0-or-later (app), Apache-2.0 (`onote_core` — build anything on the format, including closed tools), CC0-1.0 (format spec). DCO sign-off, no CLA.
- **Sync between your own devices.** A notebook gains a `.onotebook` directory of append-only per-device operation logs and content-addressed blobs. Put it in any synced folder (Drive, OneDrive, Syncthing, rsync) and pull the other device's changes in — because each device only ever appends to its *own* file, conflicting versions cannot arise, and merging is just reading. Delete wins, into the recycle bin, so it's always recoverable.
- **Tags** (To Do, Important, Question, Remember, Definition, Idea, Critical, Contact) applied per line, with markers in the gutter, click-to-complete to-dos, and a **find-tags** panel listing every tagged line in the notebook.
- **Spell check** while editing, English, with misspellings underlined in place.
- **Bundled fonts** — Inter and JetBrains Mono ship with the app, so it looks the same on every OS instead of borrowing whatever the system had.
- **Notebook-wide search** — the navigator's search box now finds text inside pages, not just page titles.
- **Page outline panel** — jump between the current page's headings.
- **Favourites and recents**, and **sort a section** A→Z or by last edited.
- **Six built-in page templates** (meeting, Cornell, weekly plan, lecture, project kickoff, math worksheet) — the feature existed, but a fresh install showed an empty list.
- **Finger drawing** — palm rejection is now stylus-conditional instead of absolute; ink is reachable on touch-only tablets. Auto/Always/Never control on the Draw tab.
- **Whole-stroke eraser** alongside the existing area eraser.
- **Markdown pipe tables render** — GFM tables pasted as text display as real tables (alignment, escaped pipes, ragged rows).
- **Downloads for Windows, macOS and Linux**, built by CI from a tag.
- **CI** — analyze/build/test on Windows, macOS and Linux; `cargo test`/`clippy`; a `cargo-deny` job enforcing that the core stays permissively licensed.

### Fixed
- **Imported OneNote pages: indented paragraphs kept their indent.** Non-list paragraphs were emitted flush-left whatever their depth, and content after an equation was pulled back to the margin — the last known cause of imported text sitting left of where OneNote had it.
- **Symbol-font characters import as real Unicode** (∈, ¬, ←, Greek) instead of Private Use Area boxes, when the run's font identifies them unambiguously.
- **Undecodable ink strokes are now reported** rather than silently dropped ("3 ink strokes could not be decoded and were left out").
- **Erasing ink no longer bloats the sync log** — a gesture used to append the entire ink block (megabytes on an imported page); it now records only the strokes that changed.
- The dead CRDT placeholder layer (`page_docs`, `page_updates`, `fts_pages`) is no longer created or written; `page_mirror` is documented as the authoritative store (spec v0.2).
- A broken git submodule (`onenote-ref`) that dirtied every checkout.
- Leaked text controllers in the template dialog and import progress.

### Changed
- **`flutter build` now builds the Rust core** on Windows and Linux and bundles it automatically, ending the stale-library trap where fixes appeared not to work.
- The File Format Spec is corrected to describe what is actually stored, and now states where the format is going (ADR-0006) so third-party implementers aren't surprised.

### Known limitations
- **OneNote tags are not yet imported.** Tags work for notes you write; extracting them from `.one` files needs the property IDs verified against a real tagged notebook, and the investigation found a latent parser bug in the same area — guessing would risk imports that work today.
- **Spell check is English only.** The upgrade path (hunspell dictionaries via the Rust core) is recorded but not built.
- **Touch drawing has not been tested on real touch hardware** — the logic is unit-tested, the feel is not.
- There is no first-party sync service, by design — Openote never talks to a server, so nothing of yours passes through us.
- Two people editing **the same paragraph at the same moment** in a shared notebook resolve last-writer-wins. Different pages, different blocks and different paragraphs all merge correctly; true concurrent editing of one paragraph waits for the structured text model.

*(This entry grows as the release is built — see [docs/planning/v0.2-release-plan.md](docs/planning/v0.2-release-plan.md) for the full plan.)*

## [0.1.0] · unreleased baseline

The pre-release walking skeleton: freeform canvas, notebook hierarchy, live-Markdown text, math blocks, pressure ink, images/attachments, tables, code blocks, themes, Markdown/PDF/open-folder export, the reverse-engineered OneNote `.one`/`.onepkg` importer, and the `.onote` SQLite container. Never tagged or distributed; recorded here as the baseline 0.2.0 builds on.
