# Code Review — Phase 1 exit readiness

> **Date:** 2026-07-27 · **Scope:** the whole tree — `app/lib` (37 Dart files, ~11.2k lines), `rust/onote_core/src` (7 Rust files, ~3.6k lines), `vendor/cab`, the test suites (23 Dart + 26 Rust), and all project documentation — audited against the [PRD](../02-product-requirements.md) (all 102 requirement IDs), the four [specs](../specs/), the [Style Guide](../05-style-guide.md), and the [Roadmap](../../ROADMAP.md).
> **Method:** requirement-by-requirement traceability (search for the implementing code, not the annotating comment), independent Dart and Rust code reviews, verification of headline findings by reading the cited code, and a feature comparison against OneNote for the web using a real notebook.
> **Previous review:** [MVP iteration 2](2026-07-code-review-mvp-iter2.md) — that document has become an append-only iteration log (sections A–N, out of order); this is a fresh full-tree review.

## A. Verdict

**The product is in good shape and the engineering is above the bar for a project this age.** The format/storage layer conforms to spec, the canvas is genuinely pleasant, the OneNote importer is a real technical achievement that works on a 324-page notebook, and the recent performance pass was measured rather than guessed (import ~53 s → ~14 s; startup and in-page responsiveness materially better).

Three things temper that:

1. **The requirement scoreboard is much softer than the roadmap claimed.** Of 102 PRD requirements: **25 fully done, 47 partial, 6 missing, 24 deferred by design.** "Partial" is usually *"the headline behaviour works, a named sub-requirement doesn't"* — e.g. blocks can't be grouped, ink can't be resized, a finger can't draw. Six roadmap items marked `[x]` were downgraded in this pass, and three implemented items were credited that weren't. The roadmap and PRD have been corrected.
2. **The recent perf work introduced two robustness regressions** (§C-3, §C-5) — both in the untrusted-input path, neither caught by tests, because the parser core has **no test coverage at all**. It also moved two hot paths rather than fixing them (§E-4: ink tessellation and erase still do O(page) work per stylus sample).
3. **Two Phase 0 gates are still open and now cost real money:** the editor-engine decision (ADR-0004) blocks three stakeholder-visible features, and the licence is unratified with **no `LICENSE` file in the repo** — so the project isn't yet legally open source.

**Recommended posture:** don't add features next. Spend one cycle on the correctness/robustness items in §C, decide the two open gates, and add the missing test coverage. Then resume feature work from a foundation you can trust.

## B. Requirement scoreboard

Full per-requirement evidence (with `file:line`) was produced during this review; the summary:

| Family | Done | Partial | Missing | Deferred by design |
|---|---|---|---|---|
| CANVAS (12) | 5 | 7 | 0 | 0 |
| ORG (10) | 2 | 6 | 2 | 0 |
| TEXT (12) | 2 | 6 | 3 | 1 |
| CODE (2) | 1 | 1 | 0 | 0 |
| MATH (8) | 3 | 4 | 0 | 1 |
| INK (11) | 3 | 5 | 1 | 2 |
| MEDIA (7) | 0 | 3 | 0 | 4 |
| EMBED (9) | 0 | 1 | 0 | 8 |
| OPEN (12) | 5 | 7 | 0 | 0 |
| SYNC (9) | 1 | 1 | 0 | 7 |
| PLAT (10) | 3 | 6 | 0 | 1 |
| **Total (102)** | **25** | **47** | **6** | **24** |

**Roadmap claims corrected in this pass:** stroke-eraser (is an area eraser), tables (Markdown interop is one-way), backlinks (bare `[[Page]]` produces none — a bug), lasso ink (no resize/recolor), page templates (no built-ins), sync merge (never invoked; no delete propagation). **Credited:** page backgrounds (CANVAS-11), zoom-to-fit/reset (half of CANVAS-10), and the CANVAS-1 v0.5 seamless-page refinement.

**Six genuinely missing requirements:** ORG-8 (auto-sort), ORG-10 (favourites/recents), TEXT-5 (tags), TEXT-10 (page outline/TOC), TEXT-11 (spell-check), INK-10 (ruler/shape assist).

## C. Highest-priority findings

Ordered by expected user harm. Every one is a surgical change; none needs a rewrite.

### C-0 (High, data loss) — nothing flushes on app exit, and a failed save reports success
Two independent defects in the save path, either of which loses work:

1. **No flush on exit.** There is no `AppLifecycleListener`, no `WidgetsBindingObserver`, and no `didRequestAppExit` handler anywhere in `lib/`; `_OpenoteBootState` creates the `AppState` and never disposes it. Autosave is a **700 ms debounce** (`app_state.dart:1290`), so **any edit made in the last 700 ms before the window closes is silently lost**, and SQLite handles are never closed (no WAL checkpoint on exit).
2. **A failed save is reported as "Saved".** `flushSave` sets `_dirty = false` *before* awaiting the write (`app_state.dart:1297`), and the timer callback discards the returned future. If `engine.savePage` throws — disk full, DB locked — the page is marked clean, the status bar shows "Saved on this device", and the exception surfaces as an unhandled async error nobody sees.

**Fix:** register `AppLifecycleListener(onExitRequested: …)` that awaits `flushSave()`, dispose the `AppState`; and in `flushSave`, wrap the write in try/catch, restore `_dirty = true` on failure, and surface a `saveError` the status bar can render.

### C-1 (High, data loss) — `workspace.json` is written non-atomically, unawaited, and constantly
`Repository._saveWorkspace` uses a plain `writeAsString` (truncate-then-write) and `setSetting` calls it **fire-and-forget** (`repository.dart:95`, `:121-124`). That file is the registry of **every notebook**, and it is rewritten on every theme change, every page switch and every zoom/scroll change (via `_persistSession` → `viewMemory`) — many times a minute. A crash or power loss inside that window truncates it, and `_loadWorkspace` then silently loads **zero notebooks**: the user's notebooks are still on disk, but the app looks empty.
Worse, `_persistSession` fires **three** of these back-to-back (`app_state.dart:529-533`), so three overlapping truncate-and-write cycles race on one file, and `_loadWorkspace` does an **unguarded `jsonDecode`** — a torn file throws and the user lands on the startup-error screen.
**Fix:** write to `workspace.json.tmp`, `flush`, then `rename` over the original (atomic on all three platforms), keep one `.bak`, and serialise the writes through a single chained future with a debounce. Guard the decode so a corrupt registry degrades instead of blocking boot.

### C-1b (High, silent data loss) — a non-zero `rotation` is destroyed on every save
`Block._known` lists `'rotation'` (`models.dart:116`), so an incoming `rotation: 15` is **excluded** from `unknownFields`; there is no `rotation` field on `Block`; and `toJson` hard-codes `'rotation': 0` (`models.dart:124`). Any rotation in a file — ours in future, or a third party's — is silently zeroed on the first load→save cycle, violating the forward-compatibility invariant the Data Model Spec promises. `model_roundtrip_test.dart:22` uses `'rotation': 0`, which is exactly the value that hides it. `PageProps` has **no** unknown-field capture at all, so any future page-level property is dropped the same way.
**Fix:** either add a real `rotation` field or remove `'rotation'` from `_known` so it round-trips as an unknown; add unknown-field capture to `PageProps`; and change the test fixture to a non-default value.

### C-2 (High, crash) — non-finite floats from a malformed file crash the import in Dart
`PropSet::f32` reinterprets any 4-byte property as a float with no finiteness check (`onenote.rs:1778-1780`). `serde_json` renders NaN/±Inf as `null`, and the Dart ink path does `(e as num).toDouble()` on every coordinate (`onenote_import.dart:373`) → `TypeError` on a whole notebook import. Images survive only because they happen to be read with `as num?`.
**Fix:** one line — `.filter(|v| v.is_finite())` in `f32`. Also worth hardening the Dart side to tolerate nulls.

### C-3 (High, robustness regression from the perf pass) — the zip-bomb budget was loosened ~4× and lost its aggregate cap
Single-pass folder extraction caps the folder buffer at `MAX_SECTION_BYTES * 4` = **1 GiB** derived from attacker-controlled header fields (`onepkg.rs:87`), and **every** section's decompressed bytes are now retained simultaneously with no total budget (`onepkg.rs:99`) because the parallel phase needs them. Previously peak decompressed memory was bounded at 256 MiB.
**Fix:** cap `extent` at `MAX_SECTION_BYTES` (a section is the unit the guard was written for) and add a running total budget (~512 MiB) that stops collecting. Store payloads as `Mutex<Option<Vec<u8>>>` and `take()` them in the worker so input frees as it's consumed.

### C-4 (High, silent data loss) — a failed section vanishes from a package import with no signal
`onepkg.rs:125-138` only keeps a section `if section.ok` and otherwise skips the slot; the result still reports `"ok": true`. The user simply receives fewer sections than their notebook contains, with nothing said. The same pattern appears throughout the parser: images that match no PNG, ink strokes that fail the sanity span, and boxes emptied by title de-duplication are all dropped with only an offline `dump_*` diagnostic.
**Fix:** add `failed: Vec<String>` to `ImportedPackage` and a `warnings: Vec<String>` to `ImportedPage`; surface them in the import snackbar ("imported 24 of 27 sections; 4 ink strokes and 2 images could not be read"). This is the single highest-value observability change in the codebase.

### C-5 (High, correctness regression from the perf pass) — one bad data block now loses every section in the folder
`read_folder_data` propagates the `io::Error` (`vendor/cab/src/cabinet.rs:186-189`), and `onepkg.rs:88-90` treats that as fatal for the whole folder — which, in a `.onepkg`, is the entire notebook. The old per-file path lost only the affected section.
**Fix:** return the partially-decompressed buffer instead of the error; `onepkg.rs:96-98` already skips sections it can't slice.

### C-6 (Medium, silent content loss) — title de-duplication can delete real body text
`onenote.rs:602-605` drops **any** line anywhere on the page whose text equals **any** line of the title outline, then drops the box if that empties it. A page whose body repeats its own title — a heading paragraph, very common — silently loses that paragraph. This is a plausible contributor to the "positioning isn't quite right" reports, since a removed line changes everything below it.
**Fix:** scope the filter to the title box itself (the `JCID_TITLE` child is already identified at `onenote.rs:587`) rather than matching by text across the page.

### C-7 (Medium, spec violation) — ink tilt is discarded on both write and read
The Ink Data Spec and INK-11 require tilt to be stored losslessly. `Stroke.toJson` hard-codes `'tx': const [], 'ty': const []` and `fromJson` never reads them (`models.dart:191`, `:194-208`) — so tilt is dropped **even when round-tripping a file that contains it**, and the InkML exporter can never emit those channels.
**Fix:** either capture and round-trip tilt, or amend the spec to declare it reserved-not-captured. Silently dropping data the spec promises is the worst of the three options.

### C-8 (Medium, accessibility/platform) — a finger can never draw
`onPointerDown` routes **every** `PointerDeviceKind.touch` to pan/pinch unconditionally (`page_canvas.dart:755-761`). Palm rejection (INK-4) is meant to be *stylus-conditional*; as written, ink is simply unreachable on a touch-only tablet, and INK-1 explicitly requires finger input.
**Fix:** only divert touch while a stylus is active (or recently active), and add a "draw with touch" toggle.

### C-9 (Medium) — bare `[[Page]]` links create no backlink
`repository.dart:470` skips refs without an explicit id, so the exact syntax the PRD names produces no backlink, even though navigation resolves it by title. Roadmap claimed TEXT-8 complete.
**Fix:** on write, resolve the title to a page id (or store the title as `dst_target`, which the schema already reserves) so the refs index is populated.

### C-10 (Medium) — panic guard has a small hole at both import entry points
`catch_unwind` wraps the parse but **not** `serde_json::to_string` (`onenote.rs:217-225`, `onepkg.rs:44-48`). A panic during serialization would unwind across the C ABI — undefined behaviour. Everything else on the FFI path is correctly guarded, and `panic = "unwind"` is verified in effect.
**Fix:** move serialization inside the closure.

## D. Rust core — structure and remaining notes

The FFI ownership contract is **correct**: `CString::into_raw` ↔ `from_raw` in `onote_core_string_free`, null-checked, and Dart always frees through that symbol and never `malloc.free`s a Rust string. Null/zero-length inputs degrade gracefully and are tested.

**The vendored `cab` patch is correct and genuinely minimal** — a byte-for-byte diff against crates.io `cab 0.6.0` shows exactly two additions and no other changes; upstream's MIT `LICENSE` is retained and both methods are marked `(Openote patch)`. Two asks: add a `vendor/cab/OPENOTE-PATCH.md` so the delta is discoverable without diffing the registry, and add a test on the vendored side exercising the two methods.

Other notes worth queueing:
- **`import_one` is 662 lines** (`onenote.rs:228-890`) with a 212-line ink block nested 6–7 deep. `onenote.rs` as a whole (2752 lines) has clean seams already visible as comment banners; a `src/onenote/` split into `model / store / propset / resolver / style / markdown / outline / math / ink / images / section / diagnostics` is mechanical and would make the parser reviewable.
- **The propset header parse exists four times and has already drifted** — only one of the four caps `cb` (`onenote.rs:1879` vs `:1971`, `:2091`). Extracting one `propset_header` removes ~120 lines and a class of bugs.
- **`checked_add` hardening wasn't applied to the propset entry points** (`onenote.rs:1826`, `:1935`, `:2109`, and derived offsets) even though the `Reader` was deliberately hardened. I could not reach an out-of-bounds slice — reads funnel through the guarded `Reader` — so this is fuzz-noise rather than UB, but it should match the rest of the file.
- **PNG dedup collides:** the key is `(len, first byte, last byte)` and a PNG's first byte is always `0x89`, so two same-length PNGs collide ~1/256 and the second is dropped (`onenote.rs:328`). `crate::ids::content_hash` is already available.
- **`f32::MAX` is used as a "bad split" sentinel but is finite** (`onenote.rs:717-719`), so the ink channel-count inference can pick a wrong split and rely on a later sanity check to save it. Return `Option<f32>`.
- **`ONOTE_INK_DEBUG` calls `std::env::var` once per stroke** inside the hot loop (`onenote.rs:794`) — hoist to a `OnceLock<bool>`.
- **Underline is parsed and then silently dropped** (`onenote.rs:1293` vs `run_markdown`), because the app's Markdown dialect has no underline token — which is also TEXT-1's missing underline. One decision fixes both.
- **Non-PNG images are never recovered** — only the PNG signature is scanned, so JPEG/EMF content is skipped silently.

## E. Dart app — structure, correctness, performance

**The good news first:** the seams that exist (`DocumentEngine`, `Repository`, `CanvasController`) are real and well-documented; comment density is high and explains *why*, often naming the bug a line fixed; and there are **no TODOs, no FIXMEs, no stray `print`s and no commented-out code anywhere in `lib/`**. The analyzer reports 0 errors and 0 warnings.

### E-1 Layering: one breach, repeated
`AppState.repo` is public, so any widget can do SQLite I/O directly — blob reads inside `build()` closures (`text_block_view.dart:162`, `image_block_view.dart:44`, `file_block_view.dart:60`), blob writes from the toolbar (`command_bar.dart:531`, `:547`), and `repo.notebooks` iterated in `build()` (`sidebar.dart:495`, `:522`, `:696`, `app_shell.dart:292`).

More significant: **`lib/export/` is not an export layer — it's a second, unguarded write path into the store.** Both importers call `repo.upsertNode` / `repo.putBlob` / `repo.writePage` directly and then hand-patch `app.nodes = repo.loadNodes(...)` (`onenote_import.dart:108`, `:120`, `:218`, `:294`, `:422`; `md_import.dart:39`, `:73`, `:104`, `:114`), and `onenote_import.dart:162` calls `repo.createNotebook` directly, bypassing `AppState.createNotebook` and therefore skipping its `flushSave`. Any future invariant on `nodes` is silently violated by imports.

**Fix (surgical, ~15 call sites):** add `blob()`/`addBlob()`/`notebooks` facades and a `reloadNodes()` to `AppState`, make `_repo` private, and route import writes through it. Keep parsing where it is.

### E-2 `AppState` is a god-object — 1314 lines, 18 responsibilities
Engine selection, notebook CRUD, tree CRUD, navigator UI state, page load/save, undo/redo, selection, block CRUD + clipboard, page geometry, **live rich-text editing commands**, find, templates, version history, links, theme + colour palette, view memory, `CanvasController` ownership, and two runtime registries.

Five clean extractions, in value order — all pure moves, no behaviour change:

| Extract | Size | Why |
|---|---|---|
| `editor/text_commands.dart` | ~215 lines (`:164-377`) | Pure string/selection manipulation; zero framework deps once out → **directly unit-testable**, and the most regression-prone code in the file (its own comment cites a user-reported regression) |
| `canvas/page_geometry.dart` | ~85 lines (`:697-780`) | `smartTextPosition`/`contentExtent`/`contentBounds`/`pageSize` are pure functions |
| `state/outline.dart` | ~250 lines | Node CRUD + navigator state — the API the importers should be using |
| `state/page_session.dart` | ~110 lines | Consolidates the three places that persist |
| `state/find_controller.dart` | ~60 lines | Small, self-contained, untested |

That leaves `AppState` ≈450 lines as a coordinator. Separately, **the ink domain lives inside a widget**: `_eraseAt`, `_gatherLassoedStrokes`, `_strokeInsidePoly`, `_refitInkBounds` (`page_canvas.dart:187-266`, `:295-364`) are the most intricate algorithms in the app, are pure functions of `(blocks, point/poly)`, and **cannot be unit-tested where they sit**. Move to `canvas/ink_ops.dart`. Same for the subpage collapse algorithm in `sidebar.dart:22-41`. `sidebar.dart` itself is now the largest file (1518 lines) and holds the navigator, notebook menus, recycle bin, version history, node menus and five dialogs — worth splitting along those lines.

### E-3 Correctness risks (beyond §C)
- **`nodes.firstWhere` without `orElse` across async menu gaps** — `renameNode`/`indentPage`/`moveNode`/`moveSectionToGroup` (`app_state.dart:832`, `:840`, `:849`, `:867`) throw `StateError` if the node vanished while `showMenu` was awaited (and `selectNotebook` replaces `nodes` wholesale). `node(id)` already returns a nullable — use it.
- **Table edits bypass undo** — `table_block_view.dart:68-72` calls `markDirty()` without `pushUndo()`, unlike every other editor. Ctrl+Z after typing in a table jumps past all of it.
- **Unawaited `selectPage` inside synchronous mutators** (`app_state.dart:65`, `:935`) — it starts with `await flushSave()`, so listeners can observe `activeSectionId` already moved while `pageId` still points at the old page.
- **`_withBusyDialog` can pop the wrong route** — `showDialog` isn't awaited, so if the work finishes before the route is pushed, the `finally` pops whatever *is* topmost (`onenote_import.dart:33-55`).
- **Leaks:** two `TextEditingController`s never disposed (`sidebar.dart:739`, `:1435`), a `ValueNotifier` never disposed (`onenote_import.dart:90`), and `AppState.canvas` (a `ChangeNotifier`) never disposed.
- **Risky `catch (_)`:** both import entry points collapse *every* failure — Rust panic, isolate death, OOM, malformed JSON — into `return 0`, surfacing as "Couldn't read any content from that file" (`onenote_import.dart:93`, `:153`). Users can't distinguish "unsupported file" from "the parser crashed". The other 11 `catch (_)` sites are genuinely best-effort and correctly commented.
- **Dead code from my tree-navigator removal:** `collapsedSections` and `toggleSectionCollapsed` have **zero readers** (`app_state.dart:108-115`), and two comments in `sidebar.dart:20-21`, `:43-45` still describe "both navigator layouts". Also dead: `OnoteCore.available`, `loadedFrom` (assigned, never read), the `mergeMirrors` binding (no Dart caller), `BlockType.frame`/`frameId`/`absorbedIds`, and the `fts_pages` + `page_updates` tables — created on every open, never written or queried (so sidebar search is a Dart `contains()` scan, not FTS).

### E-4 Performance — what the pass left behind
The recent work was real, but it moved two bottlenecks rather than removing them:

- **`InkPainter` re-tessellates every dry stroke on every repaint — including once per stylus sample.** The wet-ink fix correctly stopped the *widget* rebuild, but the painter still runs a full `getStroke` solve for all `visibleStrokes` on each `_wetTick` (`ink_painter.dart:32-49`). Strokes are immutable by spec, so cache `Map<String, Path>` by `Stroke.id` and tessellate only `wet`. **This is the highest-value remaining perf fix.**
- **Erasing is O(all strokes on the page) JSON decode + re-encode per pointer sample** (`page_canvas.dart:194-246`), and each `updateBlock` bumps `updatedAt`, invalidating the `_strokeCache` key — then the cache's `if (length > 128) clear()` nukes everything ~128 samples into a gesture. Keep decoded strokes as the working representation during a gesture; evict per block id.
- **The entire chrome rebuilds on every keystroke.** One root `ListenableBuilder` wraps `Sidebar`, `CommandBar`, `_PageHeader`, `_StatusBar` and the canvas (`app_shell.dart:179`), so every `markDirty()` re-runs three `app.nodes.where(...)` scans plus a nested per-group scan (O(groups × nodes)) and reconstructs every `_PageTile` (each a `StatefulWidget` with `DragTarget` + `Draggable` + `InkWell`). The codebase already has the right memoisation pattern twice (`main.dart:137-141`, `md_render.dart:71-83`) — apply it to `Sidebar`/`CommandBar` keyed on a cheap `nodesRevision`.
- **`_LinksPanel` runs a synchronous SQLite query and compiles a regex on every notify** while open (`app_shell.dart:325-326`).
- **Regex churn:** `md_render._renderLine` compiles 8 regexes *per line* (~4000 per parse of a 500-line block); `linearToLatex` compiles ~14 per call, two inside a fixpoint loop, and `math_block_view.dart:112` calls it from `build()` *and* again in `_commit`. All literal patterns — hoist to `static final`.
- **Also:** z-order sort of all blocks inside the per-frame builder (`page_canvas.dart:683`); `_MeasureSize` registers a post-frame callback per block per build; unbounded static image caches shared **across notebooks** (`md_render.dart:56`) plus a fresh `MemoryImage` per load with no `evict`, re-read from SQLite on every `docRevision` bump; and `SystemFonts.families()` parses every font file on the **UI isolate**, re-launched from `build()` on each keystroke in the font picker (`font_picker.dart:46`).
- **Import polish:** the Markdown importer isn't transactional (the OneNote one is, deliberately), and `.one` import shows its spinner only for the parse — the hundreds of DB writes afterwards freeze the UI with no indicator, unlike the `.onepkg` path.

### E-5 Duplication worth folding
Six clusters, all mechanical: the **block→Markdown projection duplicated ~35 lines** between `markdown_export.dart:36-67` and `open_export.dart:220-251` (`md_common.dart` exists precisely to hold this — it was the piece missed); **"create a text block" in five places** with inconsistent widths/positions; **position-key generation in three places**, each with the same comment about 15-digit padding; **hex→Color parsing in five places**; two hand-rolled date formatters; and ink bounding-box computation in three places. Also: `deletedNodes`/`restoreDeleted`/`purgeDeleted` sit beside `trashedNotebooks`/`restoreNotebook`/`purgeNotebook` — two vocabularies ("deleted", "trashed") for one concept, and `Repository` mixes both.

## F. Repo & process hygiene

- **No `LICENSE` file.** ADR-0005 is still a proposal, yet `rust/onote_core/Cargo.toml` declares `AGPL-3.0-or-later` provisionally and `README.md` describes a licence publicly. Without a `LICENSE`, the repo is legally all-rights-reserved: nobody can contribute, and "open format, open app" is unbacked. **Highest-priority non-code item.**
- **`rust/onote_core/onenote-ref` is a broken submodule.** It's tracked as a gitlink with **no `.gitmodules`**, so a fresh clone gets an empty directory and `git submodule update` has no URL to fetch; it also shows permanently dirty in `git status`. It is an **MPL-2.0** third-party reference implementation (`onenote.rs`) sitting inside our AGPL crate directory. **Fix:** move it to `rust/third_party/` (or drop it and reference the upstream URL), record it properly, and state the MPL-2.0-reference vs AGPL-crate relationship in the README so the reverse-engineering provenance is unambiguous.
- **The Flutter build does not build the Rust core.** `INTEGRATION.md` documents a CMake hook as "optional"; it is **not wired**, so `flutter run` silently uses whatever DLL was last copied. This "stale DLL" trap cost multiple debugging cycles in real sessions — symptoms look exactly like parser bugs. The docs now carry a prominent warning with a hash-verification snippet, but **wiring the hook is the actual fix**.
- **No CI.** With two toolchains, an FFI boundary, a vendored patch and 49 tests, a GitHub Actions workflow running `flutter analyze && flutter test` + `cargo test && cargo clippy` on Linux/macOS/Windows would catch the cross-platform claim the roadmap makes but nobody has verified.
- **MVP exit criteria are unverified off-Windows.** Runner projects exist for macOS and Linux; there is no evidence either has been built or run. PLAT-1 claims all three as first-class.
- **The iteration-2 review doc has become an append-only log** with sections out of order (A–N, `F` landing between `L` and `M`). Suggest renaming it `docs/reviews/iteration-log.md` and keeping dated review documents separate.

## G. Test coverage — the biggest structural gap

49 tests pass, and what they cover they cover well (merge semantics, content-hash vectors, the math grammar, the linear-math codec, block JSON round-trip, and a real end-to-end `.onepkg` import). **But:**

- **The parser core has zero unit coverage.** `walk` → `read_propset` → `Resolver` → boxes/images/order is exercised only by the e2e test, which is skipped unless a specific 48 MB notebook is present in the user's Downloads folder. Every finding in §C-2…C-6 lives in untested code. Fixtures already exist on disk at `onenote-ref/crates/parser/tests/samples/*.one`.
- **Nothing tests the `cab` patch.** The invariant `onepkg.rs` depends on — that slicing a folder buffer at each `uncompressed_offset()` equals `read_file` — can be pinned by a ~30-line test that builds a cabinet in memory with `CabinetBuilder` (already public). No fixture needed.
- **Nothing tests the parallel path.** Two runs should produce byte-identical JSON; a package with one corrupt section should still import the good ones *and report the bad one*.
- **No malformed-input battery.** A deterministic loop (truncate a valid sample at every 64-byte boundary; set the root FCR to `u64::MAX`) asserting "always parseable JSON, never a panic" would have caught the overflow and finiteness issues.
- **No performance regression test.** The perf pass produced a 3.8× import win with no test to keep it — and the win depends on a vendored patch that a routine `cargo update` could quietly bypass.
- **No widget tests at all.** The navigator, canvas interaction, and the fit-to-width-on-open behaviour are all verified only by hand.

**Two problems with the harness itself, before adding any test:**
- **The most valuable test in the repo runs on exactly one machine.** `onenote_import_e2e_test.dart:46-48` hard-codes `USERPROFILE/Downloads/Eric - Computing Science (Honours).onepkg` and `markTestSkipped`s everywhere else — including CI. **Commit a small fixture** (one section, ~3 pages, one subpage, one image, one stroke) under `test/fixtures/` and assert against that; keep the big personal notebook as an opt-in extra behind an env var.
- **Both SQLite tests locate `sqlite3.dll` under `build/windows/...` and skip if absent**, so `flutter test` on a clean checkout silently exercises almost nothing. Factor the bootstrap into `test/support/sqlite.dart`.

**Highest-value missing Dart tests, in order:**
1. **Undo/redo** (`app_state.dart:1019-1055`) — the riskiest state machine in the app, zero coverage, and pure (no widgets, no DB). Assert: add→undo restores; undo→redo is identity; `pushUndo` clears redo; `selectPage` clears both; the 100-cap drops the *oldest*; `_restore` clears selection. **This also catches the table-edit-bypasses-undo bug.**
2. **The save path** — `markDirty` → debounce → `flushSave`, with a fake `DocumentEngine` counting calls: two `markDirty`s inside 700 ms coalesce; `_dirty` is false after success; and — regression for §C-0 — **`_dirty` stays true when `savePage` throws**.
3. **`writePage` side-table projections** — `refs` and `blob_refs` are rebuilt DELETE-then-INSERT on every save, drive a user-visible panel, and have zero coverage. A `[[Title|pageB]]` link must produce a backlink; removing it must remove the row; an inline `![](sha256:…)` must produce a `blob_refs` row (this test would have caught the §C-9 bare-`[[Page]]` bug).
4. **`restoreNode` ancestor reattachment** (`repository.dart:295-309`) — delete a section, then restore one page from the bin: the page must reappear **and its section must be un-deleted**, or it's an invisible orphan. Only notebook-level trash is tested today.
5. **Ink erase splitting and lasso gathering** — after extracting them per §E-2: erasing mid-stroke yields exactly 2 strokes with fresh ids; a 2-point stroke's middle yields 0; an emptied block is removed; the lasso includes at 60 % of points inside but not 55 %.
6. **The text commands** (`applyTextColor`'s three re-colour cases, `toggleTextColor`'s strip, `wrapSelection`'s toggle-off) — pure, and their own comments record a prior user-reported regression.
7. **`LiveMarkdownController`'s coverage invariant** — its doc promises that a failed span build falls back to unstyled text; a ~20-line property test over generated malformed Markdown would guard the most fragile rendering code in the app.
8. **Position-key ordering** — that `makeSubpageOf`'s `'${target.position}m…'` suffix really sorts after the target and before its next sibling. An easily-broken lexicographic property, only checked transitively today.

## H. Compared with OneNote — what a switcher still misses

Checked against OneNote for the web with a real notebook. Openote already beats OneNote on the things it set out to beat it on: an open inspectable format, no account, real Linux support, Markdown fluency, and a genuinely fast whole-notebook import. The remaining switcher-visible gaps, in rough order of how often they'd be noticed:

| Gap | OneNote | Openote | Requirement |
|---|---|---|---|
| **Tags** (To-Do, Important, Question…) + "find tags" rollup | Signature feature, prominent in Home | Absent entirely | TEXT-5 |
| **Paste / drag-drop an image** | Both work everywhere | File picker only | MEDIA-1 |
| **External hyperlinks** | Insert Link; URLs autolink | Only internal `[[Page]]` links; `[text](url)` isn't even parsed | TEXT-1 |
| **Underline** | Ctrl+U | Not in the dialect or the toolbar | TEXT-1 |
| **Font size** | Ribbon control | Importer writes it; no user control | TEXT-1 |
| **Spell-check** | Yes | None (`spellCheckConfiguration` unset on every field) | TEXT-11 |
| **Open an attachment** | Double-click opens in default app | "Save a copy…" only | MEDIA-2 |
| **Drag to reorder pages/sections** | Native | Menu-driven "Move up/down" only | ORG-2 |
| **Grouping objects on the canvas** | Yes | No group/ungroup at all | CANVAS-7 |
| **Height/corner resize** | Yes | Width-only, single right-edge handle | CANVAS-4 |
| **Insert symbol / emoji** | Insert tab | Math palette only | — |
| **Audio recording** | Yes | Deferred by design | MEDIA-5 |

The first four are small, high-frequency, and would each be felt within an hour of switching; I'd treat them as Phase 1 polish rather than Phase 2 features. Tags are the one genuinely large missing subsystem, and worth an explicit decision: OneNote users organise around them, and the importer currently drops them.

## I. Documentation reconciled in this pass

All project documentation was audited for drift and updated:

| Document | Change |
|---|---|
| `ROADMAP.md` | Status → implementation phase; Phase 0 gates called out as open and costly; Phase 1 checkboxes converted to `[~]` with the exact unmet sub-requirements named; six over-claims corrected; three implemented items credited; importer entry updated with the perf work and the real remaining-fidelity list |
| `docs/README.md` | Removed "planning phase / before any application code is written"; documents reframed as living specs, with the code/spec-disagreement rule stated |
| `docs/02-product-requirements.md` | v0.6 header with the audited scoreboard; CANVAS-1 corrected to shipped behaviour (width 1100, top-left anchor, fit-to-width on open); per-family ID counts noted where §11 understates them |
| `docs/05-style-guide.md` | v0.3, implementation phase; **§4.1 typography marked NOT met** (no fonts bundled — the app uses each OS's system font, contradicting "consistent in soul"); tags/chips marked unimplemented against TEXT-5; **new normative §7b specifying the navigator** (why stacked over OneNote's three columns, anatomy, and the interaction/recoverability rules) |
| `README.md` | "Now" section rewritten to describe the working app; later-phase wins credited; next steps corrected; licence gap stated |
| `CONTRIBUTING.md` | "No application code yet" → implementation phase with the real quality gates (`flutter analyze`/`flutter test`/`cargo test`/`clippy`) and the licence blocker flagged |
| `app/README.md` | No longer "pure-Dart"; documents both engines and the `dart:ffi` core; "since shipped" vs "still not implemented" split made honest; stale-DLL warning linked |
| `rust/onote_core/README.md` | Module table updated (`onenote`, `onepkg`); **new section documenting the vendored `cab` patch** and why it must survive dependency bumps; `opt-level = 3` / `panic = "unwind"` rationale; test count 20 → 26; `dump_*` diagnostics documented |
| `rust/onote_core/INTEGRATION.md` | Prominent **stale-DLL trap** warning with hash-verification commands; the CMake hook re-labelled recommended and noted as not wired |

### The two PDFs are stale and cannot be regenerated from the repo

`Openote-Brand-and-Style-Guide.pdf` (5 pp.) and `Openote-Product-and-Design-Overview.pdf` (7 pp.), both dated 22 July 2026, have **no source file in the repo** — only the rendered PDFs — so they can't be updated the way the Markdown was. What is now wrong in them:

- **"PHASE 0 · WE ARE HERE"** — we are in Phase 1, with a working app and a shipped Phase 3 importer.
- **"Deferred past MVP: OneNote (.one) import · Backlinks & graph view · Tables · Page templates"** — the importer, backlinks, tables and templates have all shipped (backlinks and graph view being separate: graph view is still absent).
- **Typography page** presents Inter / JetBrains Mono / Source Serif as the type system; **no fonts are bundled**, so the product renders in system fonts.
- **"Tags & chips"** shows a built-in tag library that doesn't exist.
- The brand PDF lists **lasso as "(later)"** — it shipped (partially).
- Colour tokens, the five design principles, voice and the accessibility page are all **still accurate** and match the code.

**Recommendation:** rebuild both from the Markdown docs as a single-source-of-truth HTML template that prints to PDF, so they can never drift again. I can produce that on request — it's the one piece of this task I deliberately didn't attempt, since faithfully reproducing the existing visual design without its source would have meant guessing at it.

## J. Recommended order of work

**Now (one cycle, no new features):**
1. **C-1** atomic `workspace.json` — the only finding that can lose a user's notebook list.
2. **C-2 … C-5** — the four import robustness items, three of which are regressions from the perf pass.
3. **C-4's warning channel** — surface skipped sections/images/strokes in the import result. Cheap, and turns every silent heuristic failure into something you can see.
4. **Add the missing tests** (§G) — in order: undo/redo, the save path (incl. the failed-save regression), `refs`/`blob_refs` projections, a committed `.onepkg` fixture so the e2e runs everywhere, the `cab` patch invariant, and a malformed-input battery.
5. **Wire the CMake hook** so the Rust core can't go stale, and add **CI** on all three platforms.
6. **Two cheap perf wins while you're in there** (§E-4): cache tessellated ink `Path`s by stroke id, and hoist `Sidebar`/`CommandBar` out of the root `ListenableBuilder`. Together these address the remaining "sluggish at times".

**Decisions to take (not code):**
7. **Ratify ADR-0005 and add `LICENSE`.** Also resolve `onenote-ref` (move + attribute) so provenance and licensing are clean.
8. **Run the ADR-0004 bake-off.** It now blocks in-flow-image editing, per-run styling, the imported-layout gap, and arguably underline. The interim `TextField`+Markdown seam has quietly become load-bearing.

**Then (Phase 1 polish, all user-visible):**
9. The four small OneNote parity wins: image paste/drag-drop, external links, underline, font size.
10. Bundle Inter + JetBrains Mono to make the app look the same on every OS and satisfy style guide §4.1.
11. `CANVAS-7` group/ungroup + alignment guides, `CANVAS-4` full resize, `ORG-2` drag-to-reorder — the "it feels unfinished" cluster.
12. Decide on **tags** (TEXT-5) explicitly: build them, or record why not.

**Structural, when convenient:** make `AppState.repo` private behind facades and route imports through `AppState` (§E-1); extract the five `AppState` modules and `canvas/ink_ops.dart` (§E-2); split `onenote.rs` into its natural modules and fold the four duplicated propset headers (§D); fold the six duplication clusters (§E-5). Also delete the dead tree-navigator leftovers and fix the two stale comments (§E-3).

---

## K. Fixes applied (2026-07-27, autonomous session)

Everything in §C plus the layout blocker. **44 Dart + 26 Rust tests green; `flutter analyze` clean of errors and warnings; `cargo clippy` clean for `onote_core`** (the 5 remaining warnings are upstream `cab`'s own lifetime-elision style).

### K.1 The layout blocker — root cause found, measured, and fixed

The stakeholder's adoption blocker ("text doesn't align with the other elements … text boxes, inking and images all get misaligned … not good enough") had **one cause family, and it was not where it appeared to be.**

**The parser was never wrong.** Fitting our parsed coordinates against OneNote's own PDF export of the same pages:

| quantity | fit | R² | max residual |
|---|---|---|---|
| box origins, y | `onenote = 0.999985·ours + 0.033 u` | 0.999999999 | 0.078 u = **0.017 mm** |
| box origins, x | `onenote = 0.999891·ours + 0.092 u` | 0.999999990 | 0.068 u |
| floating images | — | — | ≤ 0.14 u |
| ink (n=184) | `0.583183·ours` vs page scale `0.583101` | 0.99999998 | ≈ 0.05 mm |

Box origins, image positions and the ink transform are all accurate to better than 0.05 mm, and `UNIT_PX = 60.0` is right to 0.039 % for text, images **and** ink simultaneously. Two hypotheses (wrong unit conversion; incomplete parent-offset chain) were tested and **ruled out with high confidence**.

**The renderer was wrong, in exactly four constants.** Fitting the *rendered* output row by row:

```
dy = -2.3693 · rendered_row - 7.998 u    R² = 0.99999993, max residual 0.030 u (0.006 mm), n = 213
dx = 45.0·onenote_level - 10 - 12·md_level - 22·is_bullet          every group within 0.13 u
```

Two free parameters explain 213 rows to six microns. The four terms, and the fix for each:

1. **Line pitch.** We rendered `lineHeight 1.35`; OneNote uses **1.2207031** — which is not an empirical constant but Calibri's own `(usWinAscent 1950 + usWinDescent 550) / 2048`. Grid fits on two unrelated pages gave 1.220890 and 1.220588. At 1.35 every line was ~10.6 % too tall, so a 62-line box drifted **~150 u** and its text slid past the images and ink sitting at their own correct positions. → `oneNoteLineHeight`.
2. **Box inset.** Our text blocks pad `(10, 8)`; a OneNote box's stored origin *is* its first line's position. That is exactly the measured `-8 u` vertical and `+10 u` horizontal intercepts. → imported boxes are now pinned to the origin (`TextBlockView.insetFor`).
3. **Indent per level.** We indented a flat 12 u per level; OneNote indents **2.45 × font size** (≈45 u at 11 pt) — measured 2.452 and 2.442 on the two samples — and it scales with type size. → `kIndentPerLevel`, `indentPx()`.
4. **Bullet gutter.** The marker occupied 22 u of inline width, pushing every bulleted line right of its own indent. → the marker now **hangs** in the gutter, as OneNote and print typography both do (`kBulletGutter`).

**No re-import needed.** The metrics were stored per box *at import time*, so notebooks already imported carried the old values. `TextBlockView` now heals them at render time: a stored pitch of exactly `1.35` is treated as "OneNote default" and any box carrying an explicit `fontSize` (only the importer writes one) is origin-pinned. Deliberate values are never overridden. Verified on the real 324-page notebook — the existing import renders correctly without touching the data.

Regression-tested in `test/onenote_metrics_test.dart`, which pins both ratios against the measured ground truth so they cannot silently drift back.

**Still open (parser, not renderer):** the markdown emitter sometimes encodes fewer indent levels than the source has (`md_level < onenote_level`), leaving a residual `45 u × levels_lost` on those rows. That is the last known contributor and is a genuine parser bug.

### K.2 Data-loss and correctness fixes

| # | Fix |
|---|---|
| C-0 | **Flush on exit** via `AppLifecycleListener.onExitRequested` → `AppState.shutdown()`; the `AppState` is now disposed. Up to 700 ms of edits were silently lost on every window close. **A failed save no longer reports "Saved"** — `_dirty` stays set until the write lands, and the status bar shows the error with a tooltip. |
| C-1 | **`workspace.json` is atomic** (tmp + flush + `.bak` + rename), **serialised** through one chained future, and **coalesced**. Load falls back to the `.bak`, then to adopting orphan `.onote` files, so a torn registry can never present as "you have no notebooks". `Repository.dispose()` cancels the pending write. |
| C-1b | **`rotation` is a real field.** It was listed in `_known` but hard-coded to `0` on write, so any non-zero rotation was destroyed on the first load→save. `PageProps` gained unknown-field capture too. |
| C-2 | **Non-finite floats filtered** in `PropSet::f32` — a NaN/±Inf position serialised as JSON `null` and crashed the Dart ink import with a `TypeError`. |
| C-3 | **Zip-bomb budget restored**: folder extent capped at `MAX_SECTION_BYTES` (was 4×) plus a `MAX_TOTAL_BYTES` running budget, since single-pass extraction holds every section at once. |
| C-4 | **Partial imports announce themselves.** `ImportedPackage.failed` carries unreadable section names; the snackbar says "imported N pages, but 3 sections could not be read: …". A crashed isolate is no longer reported as "unsupported file". |
| C-5 | **One bad LZX block no longer loses the whole notebook** — the vendored `read_folder_data` returns the recovered prefix and the caller skips only what it cannot slice. |
| C-6 | **Title de-duplication no longer deletes body text.** It matched any line anywhere on the page against any title line; title children were already skipped, so it could *only* delete real content. Now it strips only leading duplicate lines of the first box. |
| C-7 | **Ink tilt round-trips.** `tx`/`ty` were written as `const []` and never read, so tilt was destroyed by opening and saving. Erase splits carry them through. |
| C-9 | **Bare `[[Page]]` links produce backlinks** — resolved by title on write. |
| C-10 | **Panic guards cover serialization** at both import entry points (a panic there would unwind across the C ABI). |
| M6 | PNG dedup keys on a content hash, not `(len, first byte, last byte)` — every PNG starts `0x89`, so same-length images collided ~1/256 and one was dropped. |
| L6 | **Underline survives import** — it was parsed and then discarded; now emitted as `++u++`, and `same_visible` distinguishes it so adjacent runs do not merge it away. |

### K.3 Performance (finishing the earlier pass)

- **Ink outlines are cached** per stroke via an `Expando` keyed on object identity — `getStroke` used to re-solve every visible stroke on every repaint, i.e. once per stylus sample. Identity keying is deliberate: stroke coordinates are mutated in place when a block is dragged, so an id-keyed cache would serve stale geometry, while re-decoded strokes invalidate automatically.
- **Erase** no longer re-parses JSON per pointer sample: it reuses decoded strokes, rejects blocks whose rect the eraser does not touch, and compares squared distances. The stroke cache is keyed per block id with the revision alongside, so a gesture no longer piles up 128 dead entries and then wipes the cache for the whole page mid-stroke.
- **The navigator no longer rebuilds on every keystroke.** It is memoised on a cheap key (`nodesRevision`, page, active section, split, notebook count); `AppState.nodes` is now a setter that bumps that revision, and in-place mutators call `bumpNodes()`.
- **The links panel** cached its synchronous SQLite query and its regex scan (both ran per keystroke while open).
- Regexes hoisted to statics: 8 per *line* in `md_render` (~4 000 allocations per 500-line block) plus the 12-branch inline alternation, and the two in `Repository.writePage`.

### K.4 Notebook UX — decision recorded

The stakeholder reported the right-click flow as "really messy" and notebook handling generally as "nowhere near as elegant as OneNote". **Decision taken: split switching from managing.**

- The **dropdown is now purely a fast switcher** — notebook rows, then `Manage notebooks…`, `New notebook…`, an `Import ▸` submenu, and the recycle bin.
- All management moved to a **notebook manager panel** (`ui/notebook_manager.dart`): every notebook as a row with section/page counts, **rename in place**, **duplicate**, and delete behind an **inline confirm** — the list never disappears, so several notebooks can be dealt with in a row. Trashed notebooks sit in the same panel with their remaining lifetime and a Restore button.
- **Right-click anywhere on a notebook** (the header bar *or* a dropdown row) opens the manager focused on that notebook, still acting on it without switching to it. That was the actual fix for "messy": a context menu opened over a `MenuAnchor` dismisses it, so the surface you were working in vanished. Moving to a stable surface makes the dropdown's closing purposeful.
- **Notebook duplicate** is new, and is a byte copy of the `.onote` (self-contained SQLite), so pages, blobs, versions and history all come across exactly, with a fresh notebook id.

Recorded normatively in style guide §7b.

### K.5 OneNote parity shipped

- **Underline** — `++u++` in the dialect, toolbar button, **Ctrl+U**, live-Markdown styling, and importer support.
- **External links** — `[label](https://…)` renders as a tappable link and opens in the system browser. Scheme allow-list (`http`/`https`/`mailto`) because note content is untrusted; `file:` is deliberately excluded so a link in a note cannot launch a local executable.
- **Font size** — a points dropdown on the Home tab that also *shows* the size imported boxes carry (previously invisible and unchangeable).
- **Open an attachment with the default app** (MEDIA-2) — materialises the blob to a temp file under its original name so the extension drives the association.
- All of it dependency-free, via `core/platform_open.dart` (`Process.start` with an argument list — never a shell).

### K.6 Tests added (25 → 44)

`undo_redo_test.dart` (8: restore, redo identity, redo-cleared-on-divergence, selection cleared, 100-cap drops oldest, page props, empty stack, **table edits undoable**) · `persistence_test.dart` (6: failed save stays dirty, shutdown flushes, both link forms backlink, `=WxH` blob refs, restore reattaches ancestors, torn registry recovers) · `onenote_metrics_test.dart` (5: both OneNote ratios) · plus tilt and `PageProps` round-trips. `test/support/sqlite.dart` centralises the native-library bootstrap.

**Also fixed by writing them:** table edits genuinely bypassed `pushUndo` (now one undo step per editing session, structural row/column changes their own), and `Repository.dispose()` leaked a pending debounced write.

### K.7 Still outstanding from this review

Not done, and honestly flagged rather than quietly dropped: **tags (TEXT-5)** — the one large missing subsystem; **CANVAS-7** group/ungroup and alignment guides; **CANVAS-4** height/corner resize and ink scaling; **ORG-2** drag-to-reorder; **MEDIA-1** image paste and drag-drop (needs a package — `desktop_drop`/`pasteboard` — and platform wiring); bundling Inter + JetBrains Mono; MathML/HTML export; spell-check; the `AppState`/`sidebar.dart` structural splits and the `export/` write-path layering (§E-1, §E-2); the `onenote.rs` module split; CI; and the two Phase 0 gates (**`LICENSE`**, **ADR-0004**), which remain decisions rather than code.


## L. Follow-up pass (2026-07-27, later)

**45 Dart + 26 Rust tests green; analyzer clean.**

### L.1 Missing page content — two real losses found and fixed

Reported: "the text beyond the first 2 lines is just missing on the *Subsets and Empty Sets* page". Diagnosed against OneNote (which shows set-difference paragraphs, a Subsets heading and more) plus a new `ONOTE_WALK_DEBUG=1` diagnostic that reports, per page, how many outline containers exist versus how many we read.

1. **Prose containing a symbol was promoted to a whole display equation, and dropped if conversion failed.** The classifier was `runs.iter().any(is_math)`, so a sentence like "… E ∩ O = ⊘" became an equation; if `office_math_to_latex` then returned empty the **line was silently discarded**. Now classification is **per run**: a paragraph is a display equation only when every text-carrying run is math, otherwise it stays prose and math runs become **inline `$…$`** (the app's TEXT-1a dialect, which OneNote also renders inline). `same_visible` gained `is_math` so consecutive math runs merge and a fraction spanning runs still converts as one unit. And there is now **no path that drops a run** — a failed conversion falls back to the folded plain characters.
2. **Only one of a page's outline containers was read.** The code took a single `max_by_key(stp)` outline. Measured on one real section: pages had up to **5** qualifying containers while we read 1, and 11 pages had *no* qualifying container and so imported **completely empty** despite holding text. Boxes are now collected from **every** container, deduplicated by canonical identity so revisions can't double up, with a `seen_box` guard for paragraphs reachable from two containers.
3. **"Latest revision" is not "richest revision".** Preferring the newest declaration that has any `0x1C20` children already fixed the title-only-stub case; the same trap exists one level down — on the reported page the newest declaration listed **2** paragraphs while an earlier one listed the page's full content. Selection now ranks by child count, using file order only to break ties.

**Measured across the real 324-page notebook: content boxes 985 → 1146 (+16%)**, with pages (324), images (372) and ink strokes (64 616) all unchanged — recovery, not duplication. On the Discrete Maths section alone, empty pages 10 → 9 and total characters up despite the `	ext{}` wrappers disappearing from mixed paragraphs.

**Not fully resolved:** the reported page still yields only its two paragraphs. Its space holds 132 RichText objects and *none* of its three outline declarations reference more than two, so the remaining content is not reachable from any outline — a different linkage than the one the walk follows. That is the precise next step, and it is now observable via `ONOTE_WALK_DEBUG=1` (compare `outline_containers` / `boxes_to_walk` against `richtext_in_space`).

**Note:** the reclassification affects **new imports**. Existing imported pages keep their stored `kind: math` boxes and will re-render as prose with inline math only after a re-import.

### L.2 One notebook menu, not two

Reported as inconsistent to have two kinds of menu for one job. The dropdown is **gone**: the notebook bar now opens the manager directly, whose rows both switch notebooks (click a row) and carry the per-notebook actions. Import moved in as an **inline expander** rather than a popup — a popup there would have been the second menu again. The recycle bin stays on the navigator footer where it already lived. Switching still costs the same two clicks it did through the dropdown.

Pinned by `test/notebook_menu_test.dart`, which asserts the bar opens the manager, that both notebooks are listed (so it can switch), and that **no `MenuAnchor` remains** in the navigator to reintroduce the second surface. Writing that test immediately caught a real crash: `Spacer` inside `AlertDialog.actions` throws, because `actions` is an `OverflowBar` and `Spacer` needs a Flex parent — the manager's action row would have failed at runtime.

### L.3 Not done in this pass

- **The ADR-0004 editor spike was approved but not started.** The content-loss investigation took the session, and a 1–2 week-scoped spike begun badly is worse than one begun deliberately. Its scope is unchanged and specified in the ADR.
- **Images sit slightly too high** (reported). Layout is right, offset is vertical — consistent with a per-image constant rather than the accumulating error already fixed. Not yet measured against the PDF ground truth; the harness for doing so is in place.


## M. Follow-up pass (2026-07-27, evening)

**53 Dart + 26 Rust tests green; analyzer clean of errors and warnings; Windows build succeeds; DLL rebuilt and hash-verified.**

Three items were requested, in order: table import, the image offset, then the editor spike.

### M.1 Tables were not imported at all

Reported: "it appears we are also not yet handling table imports yet". Correct â€” no table JCID was recognised anywhere in the parser, so a table's text either flattened into loose paragraphs or, where the table hung off a container the outline walk never entered, vanished with the rest of that container.

OneNote stores a table as three nested container levels, each using the same `0x1C20` child list as outlines: `TABLE (0x00060022)` â†’ `TABLE_ROW (0x00060023)` â†’ `TABLE_CELL (0x00060024)`, with declared dimensions in `0x1D57` (rows) and `0x1D58` (columns). `parse_table` walks those levels and runs the existing `collect_tree` + `outline_markdown` per cell, so **a cell gets the full dialect** â€” inline maths, bold, lists â€” rather than a second, poorer text path. The grid is rectangularised to `max(widest row, declared columns)`, so a ragged or partly-unreadable table still lands as a table instead of being rejected.

Two placement paths, because tables reach the page two ways:

- **In the flow** â€” `collect_inner` intercepts `JCID_TABLE` among an outline's children and emits a `Line { table: Some(grid) }`, keeping the table in document order relative to the paragraphs around it. Without this the cells were flattened into the enclosing paragraph.
- **Orphaned** â€” a safety net scans for `JCID_TABLE` objects no outline reached and appends them stacked. Worst case the position is approximate; the alternative is silent loss of what is often the bulk of the page.

Dart side maps `kind: "table"` to a `BlockType.table` block with `content['cells']`, seeding a width from the column count so culling and hit-testing have a sane footprint.

**Measured: 8 tables recovered in the Discrete Maths section, from 0.** Pinned by `test/table_import_test.dart` (3 cases: cells intact including inline maths, correct ordering against surrounding text, degenerate grid skipped rather than producing an empty block) â€” driven through the real import pipeline with a synthesised parser payload, so it needs no binary fixture.

### M.2 The Subsets page â€” `OUTLINE_GROUP` was not a container

Section L.1 left this unresolved and mis-diagnosed the remainder as "not reachable from any outline". It was reachable; the walk just didn't recognise the container type. The user's own observation is what redirected it: inline maths renders correctly on the *De Morgan's Laws* page with the following text intact, so the maths classifier "was just coincidental" â€” which ruled out the hypothesis L.1 had been built on and pointed back at the container walk.

Root cause: root selection accepted `JCID_OUTLINE` only. OneNote also groups content under `JCID_OUTLINE_GROUP (0x00060019)`, and everything below such a group was unreachable. Accepting it â€” and keeping the child-count ranking and canonical dedup from L.1 â€” recovered the missing content, including the "Set Difference" paragraph.

**Measured on the Discrete Maths section: characters 54 713 â†’ 60 643, empty pages 10 â†’ 9, tables 0 â†’ 8. Across the full 324-page notebook: content boxes 985 â†’ 1133, with pages, images (372) and ink strokes (64 616) unchanged** â€” recovery, not duplication.

A first attempt at this *regressed* content (boxes 306 â†’ 132) by scanning `res.by_canon`, which only holds objects with a resolvable ExGuid. The scan now runs over all candidate indices with manual dedup instead.

### M.3 Image offset â€” parser exonerated, two renderer defects fixed, one open question

The parser is not the cause. Floating-image geometry was checked against OneNote's own PDF export: **width error âˆ’0.09 pt, height error âˆ’0.01 pt (â‰ˆ0.03 mm)**, and the page offset derived from the image also places the first text box's baseline to within ~1.2 pt. Images and text share one correct coordinate system.

A structural hypothesis â€” that `ImageBlockView`'s `AspectRatio` child was being *centred* inside `BlockView`'s fixed-height container â€” was **measured and disproved**: across all 22 images in the section the computed centring shift was 0.0 (min, median and max). The top-left anchoring fix is retained because it is strictly more correct, but it is not the reported cause.

A diagnostic (`ONOTE_IMG_DEBUG=1`) then established the real split: of 22 images, **18 are floating** (their own `POSX`/`POSY`) and **4 are in-flow**. The in-flow ones have **no position of their own** â€” their `abs_offset` resolves only to the parent box's origin â€” so OneNote genuinely flows them, and their vertical position is inherited entirely from the text above. Four of twenty-two matches the report of "*some* of the images".

Two real defects on that path, both fixed:

1. **`maxWidth: 640` letterboxed imported images.** Clamping an image wider than 640 px scaled it down but left `height: h` intact, so `BoxFit.contain` drew it small and **centred** in a taller slot. An explicit ` =WxH` only ever comes from import, where the size *is* OneNote's display rectangle, so it is now authoritative: no clamp, top-left anchored.
2. **4 px of phantom leading, top and bottom.** OneNote has no such gap, so every in-flow image sat low and everything after it in the same box inherited the drift. Removed for sized (imported) images; hand-authored notes keep the comfortable spacing.

Also on the parser side: `flush` counted an in-flow image as one 22 px text line when advancing the flow, under-measuring a 200 px picture by an order of magnitude, so stacked boxes below it rode up into the image. `line_flow_h` now reads the display height back out of the placeholder.

**Open, and stated plainly:** image `y` has never been *independently* validated, because the page offset used to check it was itself derived from an image. Closing that needs a fresh OneNote PDF export of a page where the offset is visible â€” the earlier exports were in a scratch directory that has since been cleaned. Note also that a notebook imported before this pass carries the old geometry, so judging the result needs a re-import.

### M.4 ADR-0004 decided â€” keep the engine we own, behind the seam

The spike was approved twice and is now **resolved without running it**, which is the substantive finding: the bake-off was framed as a two-way choice between `super_editor` and `appflowy_editor`, and that framing assumed there was no third option. There is â€” the incumbent already meets criteria 1 and 2 in shipped code, in roughly 450 lines we control end-to-end.

The deciding factor is a shape mismatch, not line count. Both candidates own their own document layout; Openote's text containers are absolutely positioned canvas boxes whose geometry comes from the importer and must match it to fractions of a millimetre. An engine that owns layout is a liability at that seam, not an asset.

What was built is the thing ADR-0004 required of *any* winner, and had listed as a consequence rather than a deliverable:

- **`OnoteTextEditor`** â€” the engine seam. Four responsibilities and no more: read-only surface, per-block editing session, intrinsic-width measurement (answerable during layout, without mounting an editor), and the serialization contract.
- **`LiveMarkdownEngine`** â€” the shipped engine behind it.
- **`TextBlockView` is now a host, not an editor.** It owns only what is the app's business under any engine: which block is being edited, the undo checkpoint, focus/exit lifecycle, resolved type metrics.
- **One session at a time**, created on focus and disposed on blur, so a 20-container page pays for one editor and nineteen cheap renders.
- An engine with its own selection model reports `commandController == null`, and the formatting UI then **disables** rather than acting on a stale target.

Reversibility is a checked property, not an intention: `editor_engine_test.dart` installs a substitute engine sharing no code with the shipped one and asserts the host still works, alongside criterion 1 (one session, nineteen read-only), session disposal on blur, and the storage round-trip.

**Criteria 3â€“5 are explicitly not claimed as met** and are recorded in the ADR: the inline-math caret is not yet an atom (TEXT-1b); storage is still the interim Markdown string, not the Â§5.1 structured `nodes` model â€” though the conversion now has exactly one place to land; and the CJK IME pass on Linux + Windows is undone. None of the three distinguished the options â€” adopting `appflowy_editor` would not have delivered 4 or 5 either â€” and all are cheaper on an engine we can edit than on one we would have to fork. Revisit triggers are written down.

### M.5 Still outstanding

Unchanged from K.7 apart from the two items closed above (tables; ADR-0004): **tags (TEXT-5)** remains the one large missing subsystem; **CANVAS-7** group/ungroup and alignment guides; **CANVAS-4** height/corner resize and ink scaling; **ORG-2** drag-to-reorder; **MEDIA-1** image paste and drag-drop; bundling Inter + JetBrains Mono; MathML/HTML export; spell-check; the `AppState`/`sidebar.dart` structural splits and the `export/` write-path layering (E-1, E-2); the `onenote.rs` module split; CI; and **`LICENSE`**, still a decision rather than code and now the only remaining Phase 0 gate.

Also still open: the markdown emitter sometimes encodes fewer indent levels than the source, leaving a residual horizontal offset; and `rust/onote_core/onenote-ref` is a broken submodule (a gitlink with no `.gitmodules`) carrying MPL-2.0 code.



## N. Table geometry, Unicode, and sync groundwork (2026-07-27, late)

**77 Dart + 26 Rust tests green; analyzer clean of errors and warnings.**

### N.1 Tables overlapped because the width was guessed

Reported: "cell sizes differ noticeably from the original resulting in the tables overlapping". Both halves had one cause.

OneNote records a width per column in **0x1D66**, packed into the *string* property slot as a `u8` count followed by that many little-endian `f32`s â€” verified against real tables: 13 bytes for 3 columns, 9 for 2. Nothing read it, so the importer guessed `140 Ã— columns` (clamped 240â€“900) and `TableBlockView` divided that equally with `FlexColumnWidth`. Every column came out the same width, and the total was wrong.

The overlap follows directly, and it was **horizontal, not vertical**. On the *Natural Language and Intro to Truth Tables* page the three tables sit **side by side** at x = 60.0, 350.9 and 641.9. Their real widths are 185.6, 185.6 and 123.7 px, so they span 60â†’246, 351â†’537 and 642â†’766 â€” no collision. The guessed width for a 3-column table was 420 px, which made the first one span 60â†’480 and run straight through the second.

Widths are now parsed (rejected unless the array's own count matches the byte length *and* covers every column found, so a partial array can't stretch the wrong columns), carried as `col_w`, stored as `content['colWidths']`, and applied as `FixedColumnWidth` per column.

### N.2 Flow re-stacking â€” the parser can't see wrapping, so the app measures

The parser assigns every box in a container a `y` by counting **source** lines at a fixed 22 px pitch. A paragraph that wraps to three visual lines is therefore charged for one, and everything below it rides up. That is the mechanism behind an imported table sitting too high, and it also affected in-flow images and maths.

Font metrics only exist in the renderer's process, so the correction belongs there. Boxes emitted from one container now share a `flow` id, and `restackFlows` re-stacks each group with a real `TextPainter` layout at the box's own width, font and size. The **first** box of a flow keeps its parsed position â€” that one is OneNote's own recorded offset and is already right â€” so only what follows moves. In-flow images are costed at their declared display height rather than as a text line, which was an order-of-magnitude undercount for a 200 px picture.

Measured on the sample section: 177 flow groups, of which 2 contain more than one box. So most imported tables are single-box flows carrying OneNote's own offset and are untouched by this â€” which is why the width fix, not this one, is what resolves the reported overlap. This matters for the pages that *do* mix wrapped prose with tables and equations.

Pinned by `test/flow_restack_test.dart` (6 cases, including the same paragraph in a narrow vs wide box, and the image-height case) and two new cases in `test/table_import_test.dart`.

### N.3 Unicode â€” three separate problems, and no rebuild needed

The question raised was whether Unicode support needs a substantial rebuild, and if so whether to fold the structured-`nodes` migration in at the same time. **It does not, so they stay separate.** The reasoning is recorded in [ADR-0006 Â§1](../adr/ADR-0006-sync-transport-and-text-model.md).

Dart strings are already UTF-16 code units; SQLite text is UTF-8; nothing in the storage path is byte- or ASCII-oriented. What actually failed:

1. **Glyph coverage** â€” we bundle no fonts (style guide Â§4.1), so `âˆƒ âˆ€ âˆ§ âˆ¨ âŠ† âŠ˜ Â¬ â„` fell back to whatever the OS had. **Fixed:** an explicit `onoteFontFallback` chain naming wide-coverage families per platform, applied both in the theme and in `TextBlockView.baseStyle` â€” imported boxes name their own family, which was bypassing the theme's list entirely.
2. **Private Use Area characters** â€” 17 Ã— `U+F0AC` in the sample. Office stores a Symbol/Wingdings character as `U+F000+n`, and no ordinary font claims the PUA, so it renders as a blank box however good the fallback chain is. **Mitigated** by naming `Symbol` and `Wingdings` in the chain: Microsoft's own fonts map that range in their cmaps, so the font that defines the encoding draws the glyph. Deliberately *not* translated in the importer â€” Symbol's 0xAC is `â†` while a user typing the negation sign means `U+00AC`, and after the fact those are indistinguishable, so guessing would corrupt content. Tracked as its own task.
3. **Replacement characters already in the source** â€” 37 Ã— `U+FFFD` exist in the `.one` file itself. Our UTF-16 decoder was instrumented and produces **zero** unpaired surrogates across the whole notebook, so these were lost before Openote saw the file. Nothing to fix.

One measurement error worth recording: an earlier count of replacement characters was taken through a PowerShell pipe, which re-encodes native stdout and manufactured FFFDs of its own. The byte-clean re-measurement is the one above.

### N.4 Alt+X code-point conversion

`lib/editor/unicode_input.dart` â€” type a code point, press **Alt+X**, get the character; press again to get the code back. `U+` prefix optional (bare `U1F600` also works), operates on the selection when there is one, otherwise on the run before the caret.

A pure string-and-selection transform, which is what makes the ambiguous cases specifiable: hex digits are also ordinary letters, so scanning is **greedy-longest** (matching Word/OneNote) â€” `1F600` beats `600`. The cost is that hex letters glued to a preceding word get absorbed: `word2764` reads as `d2764`. That is unavoidable from text alone, so the selection rule is the escape hatch, and both behaviours are asserted rather than left to chance. Surrogate halves and out-of-range values are refused instead of inserting something that would corrupt the string; astral characters round-trip without being split.

16 tests. Writing them changed the design once: an early expectation assumed scanning stopped at 4 digits, and the greedy behaviour was correct while the test was wrong.

It needed no changes anywhere else in the codebase, which is the clearest evidence that text handling was never the problem.

### N.5 Sync groundwork â€” [ADR-0006](../adr/ADR-0006-sync-transport-and-text-model.md)

Written now, ahead of any sync code, because cloud sync constrains the **storage layout** far more than it constrains the sync code, and the layout is what everything else keeps getting built on.

The finding that drives it: **Google Drive, OneDrive and a home server over rsync all replicate whole files and resolve conflicts by making a second copy.** A single SQLite `.onote` per notebook is close to the worst possible layout for them â€” one large binary that every edit rewrites, so two devices editing *different pages* produce two whole-file versions whose only resolution is `notebook (1).onote`. Nothing can merge those afterwards; the edits are already indistinguishable. WAL makes it worse, since `-wal`/`-shm` are only meaningful paired with the database at the same instant â€” a live risk today, not a future one.

Proposed instead: a `.onotebook` **directory** containing an append-only **per-device op log**, content-addressed blobs, and the SQLite container demoted to a local, never-synced cache rebuildable from the logs. The load-bearing property is **one writer per file** â€” a device only appends to its own log, so the conflicting-versions case never arises and sync degenerates to "copy files you don't have", which every provider and every home server does correctly. Merging becomes reading. Self-hosting needs nothing but file storage, and live collaboration becomes a transport swap rather than a redesign.

This is also what finally forces the structured `nodes` model, and for the right reason: an op log is only as granular as its operations, and an opaque Markdown string makes the smallest possible edit "the whole block is now this" â€” so two people editing different sentences of one paragraph cannot both win. That is ADR-0004's recorded revisit trigger #2, reached sooner than expected because sync arrived first. The migration lands behind `OnoteTextEditor.serialize`/`deserialize`, which is why it is contained rather than an editor rewrite.

Sequencing, alternatives considered (including the obvious "just sync the file"), and **three open questions for the stakeholder** â€” sync granularity, eager vs lazy first sync, and whether a notebook may become a visible folder on Windows/Linux â€” are in the ADR.

### N.6 Not done in this pass

- **The Symbol/Wingdings PUA â†’ Unicode mapping** (mitigated by font fallback, not solved).
- **Image `y` validation** remains circular and still needs a fresh OneNote PDF export of an affected page.
- **No sync code**, deliberately: ADR-0006 is groundwork and has open questions that change the shape of step 1.
- The **DLL could not be redeployed** at the end of this pass because the running app held it open; the app needs a restart to pick up the parser changes, and imported notebooks need a re-import to gain column widths and re-stacked flows.



## O. Why the previous pass appeared to do nothing (2026-07-27, late evening)

**82 Dart + 26 Rust tests green; analyzer clean.**

Reported: after rebuilding the core and reloading, tables still had the sizing issue and many Unicode characters still didn't render. The fixes were real; **they were never in the running app.**

### O.1 The build script only built half the project

`sync-core.bat` ran `cargo build` and copied `onote_core.dll`. It never rebuilt the Flutter app â€” and *every* fix from the previous pass is Dart-side: column widths (`FixedColumnWidth` from `content['colWidths']`), flow re-stacking, the font-fallback chain, Alt+X. The reported build log confirms the Rust half was already done: `Finished release profile in 0.41s` means cargo rebuilt nothing, and the deployed DLL hash matched the current build exactly.

The `cab` lifetime warnings in that log are unrelated â€” `mismatched_lifetime_syntaxes`, a style lint in the vendored crate, on by default in current Rust. Harmless, and cosmetic to silence.

**Fixed** in `sync-core.bat`: it now builds Rust, then Flutter, *then* copies the DLL. The order is load-bearing â€” `flutter build` recreates the runner directory, so a DLL copied before it is silently deleted, which is what the old script did if anyone reordered it. A `rust` argument keeps the old fast path, with an explicit warning that Dart changes won't be included. The copy step now reports failure (the app holding the DLL open) instead of continuing silently, and the script ends by reminding that importer changes only affect *new* imports.

### O.2 A correction: `openote.exe`'s timestamp proved nothing

The staleness was diagnosed from `openote.exe` being three days old. That was the wrong evidence: on Windows the executable is only the runner shell, and a Dart-only change never relinks it â€” it stayed 24 July even across a successful build. The Dart payload is `data/flutter_assets/kernel_blob.bin` (debug) or `data/app.so` (release), and *that* is what a build regenerates. The conclusion held; the reasoning given for it did not.

### O.3 The font chain, verified against the actual font files

The previous pass asserted that Microsoft's Symbol and Wingdings map the `U+F0xx` Private Use Area. That is now checked rather than claimed, by reading the cmaps directly:

| Font | Code points | `U+F0AC` | `U+00AC` | âˆ§ âˆ€ âˆƒ â„¤ âŠ† âˆ… |
|---|---|---|---|---|
| `Symbol` | 381 | **yes** | yes | no |
| `Wingdings` | 451 | **yes** | yes | no |
| `Segoe UI Symbol` | 7 536 | no | yes | **yes** |
| `Cambria Math` | â€” | no | yes | **yes** |

Two things follow, and the second was nearly a bug:

1. The characters actually missing from the reported notebook â€” âˆ§ âˆ€ âˆƒ â„¤ âŠ† âˆ… â€” are all covered by `Segoe UI Symbol`, so the fallback chain does fix them once the Dart code is built.
2. **Symbol and Wingdings also claim `U+00AC`**, and Symbol's glyph there is a *left arrow*, not the negation sign. Had they been placed early in the chain, ordinary punctuation would have started rendering as dingbats on any character the primary font happened to lack. They are last, so they are only ever reached for the PUA â€” which is exactly what they are there for. The ordering constraint is now documented and asserted.

Family names were also checked against each font's name table, because a misspelled family fails *silently* â€” the worst failure mode for this kind of fix. All four resolve; `Cambria Math` is a separate face inside `cambria.ttc`, not the `Cambria` family.

Pinned by `test/font_fallback_test.dart` (5 cases): the chain reaches a plain block, reaches an **imported** block despite it naming its own family (the original bug â€” an explicit `fontFamily` bypasses the theme's list), is the app-wide default in both brightnesses, and the PUA-only fonts sort after the wide-coverage ones.

### O.4 What still requires a re-import, and why

Font fallback is render-time and applies immediately. **Table column widths are not**: they are parsed from `0x1D66` and written into the block at import time, so an already-imported notebook has no `colWidths` and keeps rendering equal columns however new the binary is. The same is true of the flow re-stacking and of Â§M.2's `OUTLINE_GROUP` content recovery â€” all three are import-time.

So a re-import is required regardless, and it is the same re-import that recovers the previously-missing page text.



## P. Backlog pass — licence, CI, storage layer, layering (2026-07-27, night)

**81 Dart tests pass, 1 skipped; analyzer clean of errors and warnings.** Rust was **not** run this pass: `cargo` is not installed on the development machine, so every Rust-side claim below is unverified locally and rests on CI.

Five items were taken in the order licence → gitlink → CI → storage → layering, chosen so the cheap unblocking work landed before anything structural.

### P.1 The licence gate is closed

ADR-0005 ratified **as proposed** and applied: `LICENSE` (AGPL-3.0-or-later), `rust/onote_core/LICENSE` + `NOTICE` (Apache-2.0), `docs/specs/LICENSE` (CC0-1.0), and a new root `LICENSING.md` mapping all three plus the vendored MIT `cab`. Licence texts were downloaded from their canonical sources and byte-checked rather than reproduced from memory.

`Cargo.toml` declared `AGPL-3.0-or-later`, which **contradicted the very ADR it cited** — the crate is the permissive tier. Corrected to `Apache-2.0`.

The dependency audit ADR-0005 required before ratification was done properly for the first time, by reading each package's own `LICENSE` in the pub cache rather than trusting the ADR's list — which had drifted: it discussed `appflowy_editor` (MPL-2.0), Loro, `flutter_rust_bridge` and `drift`, **none of which are dependencies**. The real set is 15 packages, all MIT / BSD-3-Clause / Apache-2.0. Recorded in both the ADR and `LICENSING.md`, with the invariant that `onote_core` must never gain a copyleft dependency — now enforced mechanically by a `cargo-deny` CI job, because that failure mode is silent.

**New revisit trigger recorded:** GPL-family licences are widely held to be incompatible with the Apple App Store's terms. PLAT-3 (phone builds) and the iPad persona therefore collide with this ADR, and it must be revisited *before* that work starts rather than after.

### P.2 `onenote-ref` removed, provenance written down

The gitlink pointed at commit `f9cdc59` with no `.gitmodules` **and an empty directory** — so there was nothing to move, only a dangling reference. Removed from the index; the MPL-2.0 upstream is now documented as a *reference consulted, not a dependency* in `NOTICE` and the core README. Note this also removes the `.one` test samples §G suggested using as parser fixtures — anyone wanting them must clone upstream separately.

`vendor/cab/OPENOTE-PATCH.md` was written (asked for in §D): the two-method delta, why the quadratic `read_file` mattered, the deliberate keep-the-recovered-prefix behaviour from C-5, the invariant the patch depends on, and the update procedure.

### P.3 CI exists — and immediately paid for itself

`.github/workflows/ci.yml`: three OSes × (analyze → build → test) for the app, three OSes × (`cargo test`, `cargo clippy -D warnings`) for the core, plus the licence-invariant job.

Two deliberate choices:

- **Build before test.** `flutter test` on a clean checkout was exercising **62 of 82 tests — the other 20 silently skipped**, because `initSqliteForTests` couldn't find a native SQLite and every storage, persistence and import suite gates on it. Building first puts the bundled library in place. Measured here: 62 passed / 20 skipped before the build, 81 passed / 1 skipped after.
- **`initSqliteForTests` now throws under `CI=true`** instead of returning false. A skip is right on a developer machine that hasn't built the runner; in CI it is a suite that passes without running, which is precisely the false confidence CI exists to prevent.

`cargo fmt --check` was deliberately **not** added — it is a gate nobody has been meeting and could not be verified locally, and a red-on-arrival CI teaches people to ignore CI.

**Unverified:** the workflow has never executed. The Rust jobs and `cargo-deny` in particular are written blind, and the macOS/Linux app jobs are the first actual test of the PLAT-1 cross-platform claim. Expect the first run to need adjustment.

### P.4 The "two copies" question — the premise was wrong, the instinct was right

Raised by the stakeholder: the JSON mirror seems wasteful, so why keep two copies of every notebook rather than offering export on demand?

**There are not two copies.** `page_mirror` *is* the storage — `readPage` reads it, `writePage` writes it. What existed alongside it was not a second copy but **dead machinery shaped like one**:

| Table | Appeared to be | Actually |
|---|---|---|
| `page_docs` | the CRDT source of truth, written every save | a **zero-byte** blob, carrying nothing |
| `page_updates` | the incremental update log | never written, never read |
| `fts_pages` | the search index | never written, never queried — sidebar search is a Dart `contains()` scan |

So the honest answer to "why keep two copies" is that we weren't; we were paying an INSERT-or-UPDATE per save for a CRDT layer that never arrived — and that **ADR-0006 has already replaced**, moving the operation log out of the container and into files precisely because a single rewritten-in-full binary is the worst possible unit for consumer file sync.

All three are now neither created nor written. Existing notebooks keep whatever tables they have; nothing touches them, and the container becomes a rebuildable cache once the log lands, so a migration would be paying to tidy something that is about to be regenerated anyway.

The **File Format Spec is corrected to v0.2** with this stated at the top rather than buried: `page_mirror` documented as authoritative and not a projection, §5's CRDT encoding marked superseded-and-never-implemented (retained, because v0.1 readers deserve to know what those bytes were meant to be), `dirty_mirror` retired, and a new **§11** putting ADR-0006's direction into the published spec.

Worth stating plainly, because it is the substantive point: **the openness guarantee gets stronger, not weaker.** v0.1's openness rested on a JSON copy kept beside an opaque authoritative one. Removing the opaque one means the open representation *is* the thing. And a third-party writer no longer needs a Loro-compatible library or a documented lossy "mirror-write mode" — SQLite and JSON now suffice, which is what OPEN-1 always claimed.

### P.5 §E-1 closed: one funnel for persistent mutation

`AppState.repo` is private. A documented storage facade replaces it — `blob`, `addBlob`, `notebooks`, `currentNotebook`, `readPage`, `reloadNodes` for the app, and an explicitly-named bulk path (`importNode`, `importPage`, `importBlob`, `importPurgeNode`, `importNodes`, `importBatch`, `importCreateNotebook`) for the importers. 28 call sites across 11 files migrated; the 12 copies of `nodes = repo.loadNodes(id)` collapsed into `reloadNodes()`.

This was done **before** any op-log code on purpose. A log is only correct if it observes every mutation, and the failure mode of a second write path is not a crash but a log that is quietly incomplete — surfacing much later as a device that won't converge. ADR-0006 step 2 ("rebuild from the log and compare against the container") is only a usable check if there is one funnel to instrument.

One review claim was **not** confirmed while doing this: §E-1 said the importer calling `repo.createNotebook` directly "bypasses `AppState.createNotebook` and therefore skips its `flushSave`". It does skip it, but the import path calls `selectNotebook` when it finishes, and that flushes — so no edit was ever at risk. The asymmetry is deliberate (switching mid-import would show a half-built notebook) and is now documented at the facade rather than silently relied upon.

### P.6 Not done in this pass

- **No Rust was run.** `cargo` isn't installed here; `cargo test`, `clippy` and `cargo-deny` are unverified.
- **CI has never executed.** Until it does, "builds on macOS and Linux" remains a claim, not a fact.
- Unchanged from §M.5: tags (TEXT-5), CANVAS-7 group/ungroup, CANVAS-4 resize, ORG-2 drag-to-reorder, MEDIA-1 paste/drag-drop, bundled fonts, MathML/HTML export, spell-check, the `AppState`/`sidebar.dart` file splits, the `onenote.rs` module split, and the finger-cannot-draw defect (C-8, still live at `page_canvas.dart:781`).
- **No op-log code.** P.4 and P.5 are its preconditions, not its beginning.


## Q. The operation log — ADR-0006 steps 1–2, in shadow mode (2026-07-27, night)

**102 Dart tests pass (81 → 102), 1 skipped; analyzer clean of errors and warnings.** Rust untouched and still unrun locally.

`app/lib/sync/` — five files, ~700 lines — implements the log ADR-0006 specifies, with the container still authoritative and the log written alongside. Nothing syncs yet, deliberately.

### Q.1 Why shadow mode is the whole point

The log's correctness property is **completeness**, and completeness fails silently. A mutation path that forgets to record itself throws no error, shows no symptom, and corrupts nothing today — it simply produces a log that, months later, cannot reconstruct a notebook on a second device. There is no way to notice that by inspection.

So the log is written *beside* the container and checked against it: `sync_shadow_test.dart` saves a page through the real `AppState` → engine → SQLite path, then rebuilds that page **from the log alone** and asserts the two are identical. A forgotten recording call fails that test on the machine that introduced it, rather than on a user's second device a release later.

This is the entire reason §E-1 (one funnel for mutation) was done first. Without it the check would be unimplementable.

### Q.2 What the design forced, that the ADR had not anticipated

Three things only became visible while writing it:

1. **Ops must be recorded *after* the container write succeeds.** Recording first is the obvious ordering and is wrong: a failed save (disk full, DB locked) would leave the log claiming a change the notebook does not have, so rebuild-from-log would differ from the container *on every failed save* — and that divergence reads as a recording bug rather than the disk error it actually is. The check would have been abandoned as noisy.

2. **A page save must be diffed, not dumped.** The app saves whole pages, so the naive recorder appends the whole page per autosave — unbounded log growth, and it discards the block granularity §6a.1 exists to provide. `SyncRecorder.page` diffs against its replayed state using a canonical JSON compare. Pinned by two tests: an unchanged save appends **nothing**, and editing one block of a two-block page appends **exactly one** `block.set`.

3. **Recorders must be keyed per notebook, not per session.** Imports write into a notebook that is not the open one — by far the most likely place for the log to end up quietly incomplete, and precisely the write path §E-1 had just finished rerouting.

### Q.3 Decisions visible in the code

- **Ordering is Lamport → device id → seq.** The device-id tie-break is what makes the order *total* rather than partial. Two concurrent ops sharing a Lamport value must sort identically on every device or replicas diverge — the one failure this design exists to prevent, and the hardest to notice. Asserted by sorting a shuffled list two ways.
- **Delete-wins is one deliberate omission.** `node.upsert` does not touch `deletedAt`; only `node.restore` clears it. That single line is the whole of §6a.3: an edit that raced a delete still applies its field changes but cannot resurrect the node, whichever sorts later.
- **Blocks are *not* tombstoned**, unlike nodes — block removal is an ordinary edit within a page, and tombstoning would break undo, which legitimately re-adds a block under its own id.
- **Unknown op kinds round-trip verbatim.** Character-level text editing will arrive as new op kinds, so a v1 device replaying a newer device's log must skip what it cannot apply without corrupting what it can. `Materializer.skipped` records them, and the verification path reports "inconclusive" rather than "incomplete" when any are present — otherwise a newer peer's log would look like data loss.
- **A torn final line costs one op, not the file.** Append-only logs are routinely interrupted mid-write by a crash or by a sync client copying the file. `Op.decode` returns null instead of throwing.
- **The `enc` field is on the wire, always `"none"`.** Nothing is encrypted; the field exists because adding it later would mean rewriting every log on every device at once.

### Q.4 Visible change on disk

Running the app now creates a **`<Notebook>.onotebook/` directory beside each `<Notebook>.onote`**, containing `manifest.json` and `ops/<device>.oplog`. It is additive and non-destructive — the `.onote` is untouched and remains the only thing read at startup. Deleting a `.onotebook` directory loses nothing today; it is rebuilt on next save.

`AppState.syncLogEnabled` turns recording off wholesale, and a log that cannot be opened degrades to no recording rather than failing the save — shadow mode must never be able to break persistence it is only shadowing.

### Q.5 Not done

- **Blob bytes are not copied into `blobs/`.** Only hash, mime and size are recorded, so a rebuild-from-log today reconstructs page *structure* referencing blobs that live only in the container. This is the first gap to close before the container can be demoted.
- No `cache.onote` demotion, no `nodes` migration, no Loro, **no transport of any kind**.
- Notebook-level operations (create/rename/trash a whole notebook) are recorded only as far as their nodes; `workspace.json` remains local-only registry state by design (§6a.5).
- The eager-vs-lazy blob fetch question (§6) is still open and still does not block.


## R. Blobs, notebook metadata, touch drawing, Markdown tables (2026-07-27, later still)

**120 Dart tests pass (102 → 120), 1 skipped; analyzer clean of errors and warnings.** Rust still untouched and unrun locally (no `cargo` on this machine).

Four items, taken in the order they unblock things: close the log's remaining completeness gaps first, then two user-visible defects.

### R.1 Blob bytes now live in `blobs/` — the log can reconstruct content, not just structure

§Q left the log recording blob *metadata* only, so a rebuild produced pages referencing images it could not supply. Closed:

- `OpLogStore.writeBlob/readBlob/hasBlob/blobHashes` — content-addressed files under `<Notebook>.onotebook/blobs/<sha256>`, written temp-then-rename. Unlike the append-only logs a torn blob is not a recoverable tail; it is a corrupt image that would look like a decoding bug forever.
- **Immutable and idempotent**: an existing file is by definition already correct, so re-importing the same notebook rewrites nothing.
- **`SyncRecorder.backfillBlobs`** copies blobs that exist only in the container, because every notebook created before the log holds its images in SQLite alone. It runs in the background on first open, streams one blob at a time via `Repository.blobIndex` + `getBlob` (a real imported notebook is 372 images — loading them all to build a map would be hundreds of megabytes), and yields between each so it cannot stall a frame.
- **`AppState.syncMissingBlobs`** reports blobs the log references but cannot supply. Empty is the precondition for demoting the container to a cache; it is now assertable rather than assumed.

**Transitional cost, stated plainly:** blobs exist in both the container and `blobs/` until the container is demoted. For the 48 MB sample notebook that is ~48 MB of duplication. It is the target layout, and the duplicate copy in SQLite is what disappears at the flip — but it is a real cost being paid now for a feature that does nothing yet.

### R.2 Notebook renames reach the log

A rebuild recovered every page and the whole tree, but not what the notebook was *called* — the manifest carried the title only from creation. `notebook.meta` ops close it, diffed so a rename to the same title records nothing, and seeded on first open so a never-renamed notebook still carries one.

### R.3 C-8 fixed: a finger can draw

`onPointerDown` routed **every** `PointerDeviceKind.touch` to pan unconditionally. That is palm rejection implemented as "a finger never draws" — which also meant ink was unreachable on a touch-only tablet, contradicting INK-1 outright. The pen tools were dead controls on that hardware.

The distinction the old rule missed: **a resting palm is only a hazard while a pen is in use.** With no pen present, a finger is the only input the user has. So:

- A finger draws, unless a stylus was seen within 2 s — the window has to outlive the gap *between* strokes, not just the stroke.
- **Two fingers always pan and zoom**, whatever the mode, or a drawing tool would make the canvas unnavigable. A second finger landing mid-stroke cancels the wet stroke, so a pinch never leaves a stray mark.
- `onPointerCancel` now drops the stroke too — previously absent.
- A **Draw ▸ touch-drawing** control (Auto / Always / Never) because the right answer depends on hardware we cannot detect: "Auto" suits a convertible, "Always" a tablet, "Never" anyone who rests a hand on the glass. Persisted.

The decision is a pure function in the new **`canvas/ink_ops.dart`** — the file review §E-2 asked for, now started — so it is unit-testable, which the in-widget version was not. 8 tests.

**Not verified on real touch hardware.** The logic is tested; the gesture feel is not. That remains the never-run tablet spike from Phase 0.

### R.4 Markdown tables render

Table interop was one-way: `tableToMarkdown` wrote GFM happily and the renderer could not read one back, so a table pasted in as Markdown showed as rows of raw pipes.

`markdown/md_table.dart` parses pipe tables — escaped `\|`, `:---:` alignment, ragged rows padded (and overlong rows trimmed) to the header width. Detection requires the **two-line header + delimiter signature**, so ordinary prose containing a pipe is not swallowed as a table. Rendered as a real `Table`, wrapped in a horizontal scroller so a wide pasted table does not push the whole page sideways.

The test that matters is the round-trip: our own exporter's output, escaped pipes and all, must parse back to the same grid.

### R.5 Not done

- **No Rust run.** Unchanged; `cargo` is not installed here.
- **CI still never executed.** Everything above is verified on Windows only.
- **Touch drawing untested on hardware.**
- Unchanged from §M.5: tags (TEXT-5), CANVAS-7 group/ungroup, CANVAS-4 resize, ORG-2 drag-to-reorder, MEDIA-1 paste/drag-drop, bundled fonts, MathML/HTML export, spell-check, the `AppState`/`sidebar.dart` file splits, the `onenote.rs` module split.
- Sync: no `cache.onote` demotion, no `nodes` migration, no Loro, **no transport**.

## S. Rust toolchain installed — local verification closed (2026-07-27, follow-up)

Sections P–R repeatedly flagged that no Rust was run locally because `cargo` was not installed. It now is (cargo 1.97.1), and the claims are verified:

- **`cargo test`: 26/26 pass** — the count every earlier session reported is confirmed for the first time on this machine.
- **`cargo clippy --all-targets`: `onote_core` clean.** The only warnings are the 5 known `mismatched_lifetime_syntaxes` style lints in the vendored `cab`, which CI deliberately scopes out of `-D warnings` (editing the vendored crate beyond its documented two-method patch would be worse than the lint).
- **`cargo deny check licenses`: ok.** The §P.3 allow-list, written blind, held against the real dependency graph — and was then **trimmed to what the graph actually uses** (MIT, Apache-2.0, Zlib, Unlicense, Unicode-3.0). Six allowances (BSD-2/3, ISC, CC0, LLVM-exception, Unicode-DFS) were never encountered and are removed: cargo-deny warns on unmatched entries, and an allow-list padded with plausible-but-unused licences defeats its purpose as a tripwire.

Still outstanding: CI itself has never executed (needs a push), and macOS/Linux remain unverified.
