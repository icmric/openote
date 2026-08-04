# Changelog

All notable changes to Openote. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [SemVer](https://semver.org/) with the caveat that **the file format has its own versioning** (File Format Spec §2) and format compatibility is the promise that matters most here.

## [Unreleased — 0.2.0] · the first public release

### Changed — navigator redesign (2026-08-04)
- **Sections and pages are side-by-side columns now**, the OneNote shape: both
  independently scrollable and resizable, so you can see the section list and a
  page list at once instead of the two fighting over one column's height.
- **Browsing never loses your place.** Opening a section returns you to the
  page you were last on there — not its first page.
- **Home** — favourites and recent pages finally have a surface, above the
  section list. Right-click a page ▸ Favourite to pin it.
- **Collapse to a rail** (Ctrl+\): a 44px strip with the notebook, Home, and a
  chip per section, so the canvas gets the width back while everything stays
  one click away.
- **Keyboard**: Ctrl+PageDown/PageUp — next/previous page; Ctrl+Tab /
  Ctrl+Shift+Tab — next/previous section.

### Fixed — edit/view text parity (2026-08-04)
- **Text no longer compresses when you click into a box.** Three separate
  causes, all pinned by tests now: the editor's implicit strut forced every
  line to the base height so headings could not be tall while editing; the
  field's decoration added 8px the read view doesn't have; and the editor used
  different heading sizes (23/19/16.5 vs 22/18.5/16) with none of the read
  view's heading spacing. Checkbox and quote rows also reserve the same room
  in both modes.

### Compatibility promise

From 0.2.0 onward: **notebooks created by any Openote release open in every later release.** Format v1 (the `.onote` container) and op-log v1 (the `.onotebook` directory) freeze at this release; future format changes bump the format version and migrate one-way-forward.

### Added — student release features (2026-08-03)
- **Flashcards from your own notes.** Tag a line Question or Definition while taking notes; the week before the exam Openote quizzes you on them, with spaced repetition. A `==highlight==` inside a tagged line becomes a fill-in-the-blank. Export to Anki if you'd rather revise there.
- **Maths that computes.** Type an expression in an equation block and see the answer — arithmetic, powers, roots, trig, logs, factorials, constants. OneNote charges an Education subscription for this.
- **Cloud sync through a folder your cloud already syncs.** Move a notebook into Drive, OneDrive, iCloud, Dropbox, Nextcloud or Syncthing and your devices stay in step — no account, no sign-in, and Openote never gets access to the rest of your Drive. Changes from other devices are pulled automatically. Self-hosting works the same way, with nothing exposed to the network.
- **Annotate lecture slides.** Insert ▸ PDF lays the deck down the page you are on as a printout you write on with the pen — inserting at your cursor if you have one, otherwise below your last note — or, from the arrow, one page per slide. Either way the slide's text stays searchable. GoodNotes and Notability charge for this and only on Apple; OneNote's version loses the text.
- **Export a page as a real PDF.** Text goes in as text, so it is searchable, selectable and copyable in any reader; ink goes in as vector paths, so a diagram stays crisp at any zoom; and a long page splits into sheets instead of being cut off. Files are a few hundred KB rather than tens of megabytes. (The old whole-page screenshot is still there as "PDF — picture of the page".)
- **Paste and drag-drop.** Paste a screenshot straight onto the page; drop files on it to add them.
- **Resize anything properly** — corner and bottom handles, with ink scaling instead of being clipped; **alignment guides** that snap a block flush with its neighbours; **drag pages to reorder** them, with subpages coming along; **recolour lassoed ink**.
- **Find and replace**, spell-check **suggestions** on right-click with "Add to dictionary", **Ctrl+1–5** tag shortcuts, **copy link to page**, and ``` + Enter to open a code fence.

### Added — sharing, printing and the way out of a deck (2026-08-04)
- **Hand the annotated deck back in.** Writing on lecture slides worked; getting
  the result out did not. A section now exports as **one PDF** — "Export section
  as PDF…" on the section, in navigator order — and each slide keeps its own
  shape instead of being squeezed onto a portrait sheet with white space under
  it. The slide's text goes out with it, invisibly, so the exported deck is
  still searchable in any reader. Losing the picture no longer loses the words.
- **Share as PDF** from a page's menu, and **Print** (Ctrl+P) for a page or a
  whole section — the same searchable, selectable, few-hundred-KB page that
  export produces, straight to the printer.
- **An import now says what arrived.** "Imported 324 pages, 372 images and
  64,616 ink strokes from OneNote." Previously it reported only what it could
  *not* read, so a clean import of five years of notes was a page count and a
  silence.

### Added — study stats and the exam countdown (2026-08-04)
- **A reason to open the study panel tomorrow.** The deck now says how much of
  it you have actually seen, how many cards you reviewed today, and how many
  days in a row you have turned up — with a fortnight of activity underneath it.
  A streak stays alive until a whole day has gone by empty, so a morning you
  haven't studied yet shows the number you are about to keep, not a zero.
- **Put your exam date on a section** — from the section's right-click menu in
  the navigator, or from the study panel. It becomes a countdown and a pace:
  *"14 days · 40 to learn · 3 a day covers them by then."* The target counts
  cards you have never seen, so it is a number that stays true as you approach
  it rather than one that recedes. The study button's badge turns brass once the
  exam is inside a week.
- Practising counts towards your streak. It still never touches your schedule.
- Exam dates and review history stay on your own machine: they are personal, so
  they don't travel to everyone else through a shared notebook.

### Fixed — post-merge pass (2026-08-04)
- **The Draw tools work again.** The pen, highlighter, eraser and lasso could not be selected at all: the Draw row contained a spacer that is illegal inside a horizontally scrolling toolbar, so the entire row failed to lay out.
- **Toolbar buttons on a narrow window respond again.** The tab row overflowed instead of scrolling, and an overflowing row is clipped — clipped pixels do not receive clicks, so the right-hand buttons silently stopped working on smaller screens.
- **Importing a PDF no longer scatters it across new pages** when you happen to be looking at a section rather than a page. It creates one page and stacks the deck down it, as asked.
- **Another device's changes can no longer be missed.** If an edit arrived while Openote was already pulling, it was dropped and would only appear the next time something else changed — which might be never.

### Fixed — student release (2026-08-03)
- **JPEG photos now survive a OneNote import.** The importer only recovered PNGs, so phone photos of whiteboards and worksheets silently vanished.

### Added
- **Licence** — the project is now legally open source: AGPL-3.0-or-later (app), Apache-2.0 (`onote_core` — build anything on the format, including closed tools), CC0-1.0 (format spec). DCO sign-off, no CLA.
- **Sync between your own devices.** A notebook gains a `.onotebook` directory of append-only per-device operation logs and content-addressed blobs. Put it in any synced folder (Drive, OneDrive, Syncthing, rsync) and pull the other device's changes in — because each device only ever appends to its *own* log file, two devices cannot produce conflicting logs, and merging is just reading. Delete wins, into the recycle bin, so it's always recoverable. A device that joins an existing notebook keeps its **own** copy of the `.onote` container and shares only the logs: the container is a SQLite database rewritten on every save, and two machines writing one copy of it through a cloud client is exactly what the log design exists to avoid.
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
