# Code review — the v0.2 merge and the v0.3 student work (2026-08-04)

> **Scope:** the 33 commits between the previous review's merge (`dae13a8`, PR #1)
> and `master` today (`2b5df3f`, PR #2) — licence ratification, CI, tags, search,
> two-device sync, the format freeze, and the v0.3 student work: paste/drag-drop,
> flashcards, math evaluation, PDF slide annotation, cloud-folder sync, the
> move-bar/caret pass, and two field-report fix rounds.
> **Method:** independent verification of the claimed baseline, then a read of the
> new subsystems (`sync/` in full; study, tags, spell, evaluate, PDF import, the
> canvas pointer work) looking for what previous passes missed — not a re-audit of
> what they already fixed.

## A. Verification — the claims hold

| Claim (v0.3 plan, 2026-08-04) | Measured today |
|---|---|
| 291 Dart + 40 Rust tests green | **294 Dart + 41 Rust, all green** |
| `flutter analyze` clean | **Clean** (errors and warnings) |
| `clippy -D warnings` clean | **Clean** on `onote_core` (the 5 vendored-`cab` lifetime lints remain, as accepted) |
| CI on three OSes + release packaging | `ci.yml` + `release.yml` present; last recorded run green |

The planning docs are **accurate and current** — the v0.3 plan's implementation
table, the two field-report passes, and the "still open" list all match the code
I read. This is worth stating because it was not true a month ago: the docs and
the tree have converged, and the field-report loop (use it → report → diagnose →
adversarial review → fix before merge) is visibly producing better code than the
first-draft passes were.

## B. Where the project actually is

v0.2 shipped the infrastructure a real product needs (licence, CI, release
packaging, format freeze, tags, search, sync). The v0.3 work then delivered, in
order of user impact:

- **The capture flow works**: paste/drag-drop images, including into a text
  box's flow at the drop point. This was the single most-felt gap.
- **PDF slide annotation** (the flagship): printout-style stacking onto the
  current page by default, one-page-per-slide behind the split button, locked
  backgrounds, hidden searchable text layer. pdfium licensing and bundling
  resolved on Windows.
- **The study loop**: tags → flashcards → SM-2 with sub-day learning steps →
  session summary → Anki TSV export. The SM-2 deviations (ease floor, learning
  steps, cram mode) are the right ones and are documented in the code.
- **Sync that a student can set up**: cloud-folder detection for six providers,
  non-destructive move, auto-pull on foreign change, onboarding that finds
  existing notebooks. The no-OAuth argument (`cloud_folders.dart`) is sound and
  well recorded.
- **The editing feel pass**: move bar (OneNote's model), caret-where-you-clicked,
  drag-to-select from an unfocused box. The `_editableState` walk-up fix is
  correct, and the known marker-width caret imprecision is documented so it
  won't be refiled.

**Verdict on the new code:** the sync core (`op.dart`, `op_log.dart`,
`materializer.dart`, `sync_recorder.dart`, `device_identity.dart`) is the best
code in the repository — single-writer logs, torn-tail tolerance, delete-wins
implemented as one deliberate omission with the comment to protect it, ink-diff
write-amplification guards, and a shadow-mode verification that makes the log's
completeness a *testable* property. The study and evaluation code is scoped
honestly (a calculator, not a CAS; cards as a view of notes, not an authoring
suite) and says so.

## C. New findings

Ordered by how much they matter. None are release blockers; #1 and #2 are the
ones I'd fix before the next feature lands.

### C.1 A foreign change arriving mid-pull is dropped until the next event

`AppState.syncPull` guards re-entrancy with `if (_pulling) return 0;`. The
watcher's debounce has already fired by then, so a foreign log change that
lands **while a pull is in flight** folds in only when a *later* filesystem
event (or the manual button) happens to fire. If the other device stops writing,
that can be indefinitely. The ops aren't lost — the watermark hasn't advanced —
but "auto-pull" quietly becomes "auto-pull, usually".

**Fix shape:** set a `_pullAgain` flag instead of returning, and loop after the
in-flight pull completes. Three lines, and the re-entrancy guard keeps its
purpose (never two concurrent container writes).

### C.2 `app_state.dart` is 2,976 lines and every feature lands in it

Twenty-six section banners: storage facade, op log, cloud sync, mirrors,
import, tags, study, favourites, chrome state, colour, fonts, titles,
clipboard, z-order, engine, view memory, history, templates, geometry, tree
ops, recycle bin, backlinks, undo, selection, find, persistence. Each section
is individually fine — the problem is structural: **there is nowhere else for
state to land**, so every v0.3 feature grew the same class, and `notifyListeners`
means every keystroke offers a rebuild to every listener of all of it. The
per-keystroke performance regressions this session (deck cache, sync status
cache, device count cache) are all symptoms: caches added one at a time to
compensate for a god object that notifies globally.

**Fix shape:** not a rewrite. Extract the three most separable clusters into
owned sub-objects with their own `ChangeNotifier`s — `SyncCoordinator`
(recorders, watcher, pull, mirrors, status caches), `StudyState` (card states,
deck caches, revisions), `TagOps` — and have `AppState` expose them as finals.
The UI already reads these through narrow surfaces, so the mechanical cost is
mostly import lines. Do it **before** v0.4 features, or they'll land in the god
object too and the extraction gets strictly more expensive.

### C.3 Blob storage is duplicated, unbounded, and PDF import made it acute

Known and ranked #2 in the plan's own list; this review agrees and adds the
numbers: every blob is stored **twice** (SQLite `blobs` table + loose file in
`.onotebook/blobs/`), nothing ever deletes either copy, and a 60-slide deck at
2× render is ~120 MB → **~240 MB per import**, before mirrors and backups copy
it again. A student who imports a semester of lecture decks fills a small SSD.
GC is genuinely subtle here (a blob is referenced by pages, history snapshots,
*and* other devices' logs that may not have synced yet), so the design deserves
its own short ADR — but the duplication half (stop double-storing, pick one
home) is cheaper and could land first.

### C.4 The first device's container still lives in the synced folder

The plan's #1 open item; agreed, with one sharpening: the risk is not only
re-upload waste. The `.onote` sitting in the Drive folder is **double-clickable
on the second machine** — the exact two-writers-on-one-WAL-database case the
joining flow was just fixed to avoid. Until the container is demoted to
`cache.onote` inside the `.onotebook` (excluded from sync), the corruption case
is one user mistake away rather than structurally impossible.

### C.5 Hygiene, quick

- **`rust/onote_core/onenote-ref/` is back as an untracked directory.** The
  gitlink was removed from the index (good — that closes the broken-submodule
  defect), but the working tree still holds the MPL-2.0 checkout and it shows
  up in every `git status`. Add `rust/onote_core/onenote-ref/` to `.gitignore`.
- **The dirty generated-plugin files are pure CRLF noise** — no content change
  (verified byte-wise; the Windows one adds `pdfium_flutter`, already
  committed). A `.gitattributes` declaring `* text=auto eol=lf` would stop the
  flip-flopping, at the cost of a one-time normalisation commit. Recommended,
  deliberately not done in this pass.
- **macOS registrant and pdfium:** `GeneratedPluginRegistrant.swift` doesn't
  mention pdfium — expected, since `pdfium_flutter` is an FFI plugin with no
  method channel; it arrives via CocoaPods at build time. The cheap
  verification stands (one `flutter build macos` + one PDF import), but this
  is likely fine.

### C.6 Accepted-and-agreed (no action, recorded so they aren't refiled)

- `NoteTag.rebase` returns early when the line count is unchanged, so a
  same-line-count *rewrite* keeps tags pointing at replaced text. Consistent
  with the documented trade (exact for insert/delete, cheap per keystroke);
  the alternative is content diffing on every edit.
- Caret placement on marker-bearing lines is approximate, by construction —
  documented in `live_markdown_engine.dart`.
- Spell-check learned words are a process-global set with a persistence
  callback. A singleton seam, but the isolation cost of threading it through
  is not worth it at this size.

## D. What's next — reconciled

The plan's own "still open" list is right. Merged with this review's findings,
the order I'd argue for:

1. **The `_pulling` liveness fix** (C.1) — three lines, protects the feature
   that was just shipped.
2. **Vector PDF export** — the last daily-frequency parity gap (shared notes
   are unsearchable raster today), and one work package with **printing** (P13)
   and **Phase B step 4** (re-export annotated slides): all three draw the same
   vector page. Doing them together amortises the `pdf`-package layout work.
3. **Blob dedup, then GC** (C.3) — dedup first (pick one storage home), GC
   behind a small ADR that accounts for logs-not-yet-synced.
4. **Demote the container to `cache.onote`** (C.4) — closes the last structural
   corruption path and finishes ADR-0006 §3 as specified.
5. **The `AppState` split** (C.2) — before v0.4 features, not after.
6. **macOS/Linux human runs** including one PDF import each — the flagship's
   only untested platform risk.
7. Carried verification debt, unchanged: touch hardware, image-`y`, the
   re-imported reference notebook, rebuild-from-log on real data.

## E. Product review — rounding out the student story

Asked directly: what else would make this well-rounded for students first,
OneNote switchers second. Judged against the plan's own bar — *does it help a
student the week before an exam?* — and ordered by value-for-cost.

### E.1 Cheap, high-leverage (do in v0.3.x)

- **Study stats + exam countdown.** The loop exists; motivation doesn't. A
  per-deck "cards seen / due today / streak" line and an optional exam date on
  a section ("14 days → 12 cards/day clears the deck") is a few hundred lines
  on data already in `CardState`, and it's the difference between a feature
  that exists and one that gets opened daily. Anki's retention comes from
  exactly this surface.
- **Share a page/section as PDF** (falls out of vector export, #2 above) — the
  actual unit of student sharing is "my notes for week 6", sent to a classmate
  who will never install anything. Worth surfacing as a one-click "Share as
  PDF" rather than leaving it inside the export menu.
- **HTML export** (OPEN-7's other half) — same motivation, but linkable;
  also the only export a phone can read losslessly today.
- **Dark-slide mode.** Students annotate at night; a white 2× slide raster in
  a dark room is a flashlight. An invert/dim toggle on locked background
  blocks is a shader/filter, not a re-render.
- **Page thumbnails for slide sections.** A 60-slide printout is navigated by
  eye; the outline panel is text-only. Thumbnails for pages whose first block
  is a locked background image would make slide decks navigable.

### E.2 The two structural student features worth planning properly

- **Audio recording pinned to notes (D5, the Notability feature).** For
  lecture-goers this is arguably bigger than flashcards: record the lecture,
  and tapping a line jumps the audio to when it was written. The hard part is
  *not* recording — it's the timestamp↔block correlation and the blob-size
  story (which lands on the same GC work as C.3, another reason to do GC
  early). Recommend: spike the recording+seek plumbing in v0.4, ship pinning
  in v0.5.
- **OCR on images (D6).** Whiteboard photos and JPEG-imported worksheets are
  invisible to search — and the search already indexes a hidden text layer
  (built for PDF), so OCR is *additive*: run Tesseract (via the Rust core, so
  it's offline and licence-clean) over image blobs in the background, store
  into the same `sourceText` mechanism. The plan says "investigate"; the PDF
  text-layer work has quietly answered the integration half already.

### E.3 For the OneNote-switcher audience specifically

- **Import completeness report.** The *failure* half is already surfaced —
  skipped sections and dropped-stroke counts show in the notebook manager
  (shipped with the Tier-1 data-safety pass). What's missing is the *positive*
  half: a switcher who just imported five years of notes should also see what
  arrived — "324 pages, 372 images, 64,616 strokes" — because trust in minute
  one is what converts them, and the numbers are already counted by the parser.
- **OneNote tag import (P10)** — the fixture blocker stands, but note the
  ecosystem is now *ready* for it (tags, rollup, flashcards), so its value went
  up since it was first deferred: an imported notebook's To-Dos and Questions
  would light up the whole study loop on day one.
- **Password-protected sections (P14)** — the one OneNote feature with no
  Openote answer at all. Spec-first remains right; worth scheduling the spec
  now so the crypto questions (key derivation, what's encrypted at rest, how
  it interacts with the op log — which is plaintext JSONL today, and the
  `encryption` envelope field is already reserved) get thought rather than
  improvised.

### E.4 Deliberately not recommended yet

- **Android/tablet (D7)** — the sync transport (folder providers) does not
  exist in the same shape on Android (SAF, scoped storage), so it is not "the
  same app, smaller screen"; it's a new storage backend. Wait for the
  container demotion and blob GC to land first, or the port inherits both.
- **Ink-to-math / handwriting recognition** — high student appeal, XL cost,
  and the current importer/recognition surface has no foundation for it.
  Revisit when the study loop has usage evidence.
- **Real-time co-editing** — the op log makes it a transport swap *later*;
  shared-folder group notebooks (D4) already cover the group-study case that
  students actually have.

## F. Docs state

The v0.3 plan and ADR-0006 are current and good. Two things need updating
after this review: the ROADMAP's "At a glance" block (still describes sync as
click-to-pull and canvas parity as open — both shipped) and its header date;
done in this pass. The two stale root PDFs remain, as previously recorded.

---

## G. Follow-up — what this review's own findings turned into (2026-08-04)

Written after acting on the list above, so the document records outcomes rather
than only recommendations. **309 Dart + 41 Rust tests pass; analyzer clean.**

| Finding | Outcome |
|---|---|
| **C.1** foreign change dropped mid-pull | **Fixed.** A `_pullAgain` flag drives a loop, so the re-entrancy guard keeps its purpose (never two concurrent container writes, so no double-apply) while gaining liveness. Both properties have a test. |
| **C.2** `AppState` god object | **Deferred, scheduled.** Item E3 of [v0.4-and-beyond](../planning/v0.4-and-beyond.md), explicitly *before* v0.4 features so they don't land in it. |
| **C.3** blob duplication + no GC | **Deferred with a corrected diagnosis.** De-duplication is not a standalone change: SQLite is what the app reads and `.onotebook/blobs/` is what sync replicates, so removing either breaks a real path — it **is** the C.4 container demotion, and GC needs its own ADR because a blob is referenced by pages, history snapshots *and* unsynced foreign logs. E1/E2 of v0.4. |
| **C.4** container in the synced folder | **Deferred**, now paired with C.3 as one piece of work. |
| **C.5** hygiene | **Done 2026-08-04** — and the diagnosis was wrong in a useful way; see §H below. |
| **D.2** vector PDF export | **Shipped.** Text as embedded-subset Inter with a `/ToUnicode` CMap (so Ctrl+F and copy-paste work in any reader), ink as stroked PDF paths, images embedded, tall pages paginated into sheets. `buildPagePdf` is factored out so **printing (P13)** and **annotated-slide re-export (Phase B step 4)** reuse it. Seven tests. |
| **§E** product suggestions | **Recorded** in [v0.4-and-beyond.md](../planning/v0.4-and-beyond.md) with sizes, rationale and blockers, rather than living in a review. |

### Two bugs found by use, not by review

Both were reported by the user in the same session, and both are worth recording
because neither would have been caught by reading the code:

- **The Draw tools could not be selected at all.** `_drawRow` returned a `Row`
  containing a `Spacer`, and every command row is built inside a horizontal
  `SingleChildScrollView` — an unbounded width constraint, where a flex child is
  a *hard* layout assertion. The entire row failed to lay out. The symptom
  ("buttons are dead") pointed nowhere near layout.
- **The tab row overflowed by 18 px at 560 px wide**, found while writing the
  regression test for the above. An overflowing `Row` is clipped, and clipped
  pixels do not hit-test, so the right-hand toolbar buttons silently stopped
  responding on a laptop with the navigator open.

The lesson worth keeping: **the command bar had no widget tests at all.** Three
now cover tool selection, the rebuild a tool tap causes, and a narrow window.
The v0.3 plan already lists "smoke tests for the surfaces with none"
(`pdf_import`, `study_panel`, `sync_dialog`, `onboarding`) — this is evidence
that item is worth more than it looks.

---

## H. The hygiene pass, and what it turned out to be (2026-08-04)

§C.5 read the symptom correctly — generated files churning on every checkout —
and prescribed for the wrong cause. Measuring first changed all three items.

**The line endings were never the problem.** Of 268 tracked files, the only ones
holding a CR in the index are the two PDFs, the fourteen bundled font files and
the seven icons. **Not one text file is stored with CRLF.** So the "one-time
whole-tree normalisation commit" that this review priced as the cost of a
`.gitattributes` costs nothing: `git add --renormalize .` afterwards reports no
changes at all. The file is in now, purely as a guard against a contributor
whose `core.autocrlf` differs — with `*.bat`/`*.cmd`/`*.ps1` pinned to CRLF,
because `sync-core.bat` is a build script and cmd.exe mis-parses an LF-only
batch file in ways that look like a `goto` silently doing nothing.

**What was actually churning** is `app/.flutter-plugins-dependencies`: a file
whose own first line says *"This is a generated file; do not edit or check into
version control"*, which records **absolute pub-cache paths** (the committed
copy carries `C:\Users\ericm\AppData\Local\Pub\Cache\...`), and which
`app/.gitignore` already names — with no effect, because a `.gitignore` entry
does nothing for a file that is already tracked. `git rm --cached` removes the
source instead of normalising the symptom, and `flutter pub get` regenerates it
on every machine including CI, which runs `pub get` before it builds.

**And a worse one found on the way.** `app/.gitignore` also listed `windows/`,
`linux/` and `macos/` — while 56 files under those directories are tracked.
Ignore rules do not apply to tracked files, so the entries did nothing for what
was already there and everything to what was not: **a new file added to any
runner project was invisible to `git status`** and would be silently left out of
a commit. Demonstrated rather than assumed — `touch app/windows/_probe.txt`
produced no output from `git status` before the change and `?? app/windows/_probe.txt`
after it.

That is not an abstract risk for this project. The hook that builds and bundles
the Rust core lives in `app/windows/CMakeLists.txt` and `app/linux/CMakeLists.txt`;
the plugin registrants and the pdfium bundling live beside them. A missing file
there reproduces the stale-library trap that cost several sessions, and CI is
the only thing that would have caught it. Each of those directories already
carries Flutter's own `.gitignore` covering the parts that genuinely are
generated (`flutter/ephemeral/`, `Pods/`, `xcuserdata/`), which is the right
granularity and was already working — so the blanket rules were pure downside.
`ios/`, `android/` and `web/` stay ignored, since none exists, with a comment
saying to delete the line *before* generating one.

**`app/README.md` was the most misleading file in the repository.** Its "Running
it" section instructed the reader to run `flutter create --platforms=windows,macos,linux .`
on the claim that the runner directories "are not committed" — they are, and
`flutter create` would overwrite the CMake hooks and quietly reintroduce the
stale-library trap. The same passage told them to delete `test/widget_test.dart`,
which holds seven real tests today. Below that, two thirds of the file was an
iteration-2-to-9 changelog duplicating the record that this document already is,
and the "still not implemented" list named tags, notebook-wide find and external
links — all shipped. Rewritten as a description of the app as it stands, with
the macOS gap stated plainly (there is no CMake hook on macOS, so a local
`flutter build macos` produces an app with no Rust core and therefore no OneNote
import; `release.yml` handles it explicitly, so releases are unaffected).

Verified after: 340 Dart tests and 41 Rust tests pass, `flutter analyze` clean
(74 pre-existing infos, none in the changed files), and `git status` stays clean
across a `flutter pub get`.
