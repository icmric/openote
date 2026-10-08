# Backlog

> Everything open that is not already planned into a release document, plus
> everything that has been **decided against** — recorded so it is not
> re-proposed every round.
>
> [CHANGELOG.md](../../CHANGELOG.md) is what shipped. [PLANNING.md](../../PLANNING.md)
> is Eric's raw asks in his own words. When an item here grows a plan it moves
> to a release document in this folder.
>
> Sizes: **S** ≈ hours · **M** ≈ 1–3 days · **L** ≈ ~a week · **XL** ≈ multi-week.
>
> The bar every item is judged against: *does this help a student the week
> before an exam?* Secondary, always: does it keep working for someone who
> switched from OneNote and judges us on whether their daily habits survived.

---

## Next

Ranked by value ÷ effort, which is not the order things were thought of.

| # | Item | Size | Why here |
|---|---|---|---|
| 1 | **Use the macOS and Linux builds** | S | Three platforms ship; two have never been run by a human. CI proves they compile. §1.1 |
| 2 | **Split `AppState`** | M | It holds most of the app's state and keeps growing, because every feature since the last split landed in it. This is the tax on everything below. §1.2 |
| 3 | **Blob garbage collection** | M | Nothing has ever deleted a blob. Unblocked now there is one store rather than two. §1.3 |
| 4 | **Fix the imported-image mime label** | S | Every image imported from OneNote is labelled `image/png`, so the open-folder export names a JPEG `.png`. §1.4 |
| 5 | **Specify the ink blob format** | S | The one place the format spec does not let somebody else read a notebook. §1.7 |
| 5 | Dark slides | S | Annotating a white 2× raster at night is a flashlight. |
| 6 | Page thumbnails for slide sections | S–M | A 60-slide deck is navigated by eye; the outline is text only. |
| 7 | Group / ungroup | M | The last piece of CANVAS-7. Alignment guides shipped without it. |
| 8 | A graph face on the object row | S | Graphs are the only first-class canvas object with no control row, which is the rule the row exists to hold. Its controls already exist. |
| 9 | HTML export | M | The only export a phone reads losslessly, and it is linkable. |
| 10 | The spreadsheet engine | L | Eric's long-standing second ask. Blocked on a design decision, not on effort. §2.1 |
| 11 | Audio pinned to notes | L–XL | Arguably bigger than flashcards for lecture-goers. Wants #3 done first. |
| 12 | OCR on images | L | Additive — search already indexes a hidden text layer. |
| 13 | The structured `nodes` text model | XL | Gates per-run styling, paragraph collapse and real co-editing. §2.2 |

---

## 1. Engineering debt

### 1.1 Run the builds we ship · **S**

Launch each, import a PDF, draw, and sync a notebook between two machines.
pdfium is a per-platform native binary and the likeliest thing to fail
differently. This is the difference between "we support Linux" being a claim
and a fact, and it is the cheapest credibility risk on the list.

The macOS Rust build hook has never been run either — `app/README.md` carries
the seven-step check for the first Mac to try it.

### 1.2 Split `AppState` · **M**

`notifyListeners` offers a rebuild of everything to every listener, which is
why there are per-keystroke caches and `ui/memo.dart` instead of narrower
notifications. `StudyState` and `PlannerState` came out; `SyncCoordinator` and
`TagOps` have not.

The split has been done once and did not change the gradient, only the
intercept — everything built since landed back in the same class. So the useful
version of this is a rule about where new state goes, not another extraction.

### 1.3 Blob garbage collection · **M**

Designed in [ADR-0007](../adr/ADR-0007-blob-lifecycle.md), never built. Two
things to settle before writing any:

- **The op log names every blob ever written and is never compacted.** A sweep
  that treats a `blob.put` as a reference can therefore collect nothing. This
  is the same problem as the dead video in [v1.0.2 §19](v1.0.2.md), and
  `blob.forget` is the sketched answer.
- **The clipboard and the undo stack are reachability roots** and ADR-0007's
  list of four does not mention them. A blob whose only reference was just cut
  is reachable from the cut.

`store/media_gc.dart` is the shape to copy: a wrong keep costs disk, a wrong
delete costs somebody's lecture, so every decision in it is deliberately
asymmetric, and no evidence is never treated as evidence of absence.

### 1.4 The imported-image mime label · **S**

`onenote/` writes `image/png` for every image it extracts, whatever the bytes
actually are — the parser does not transcode, so a JPEG stays a JPEG and gets
the wrong label. `export/open_export.dart` derives the asset filename from the
mime, so the open folder contains JPEGs named `.png`. Sniff the magic bytes.

### 1.5 Large file drops read the whole file into memory

`canvas/media_drop.dart`, in the two drop handlers. Insert ▸ Video already
streams. The half of this that *lied* — a drop that landed nothing and said
nothing — is fixed; the progress half is not.

### 1.6 `lib/` must not touch a `debug*` member outside an assert

`RenderObject.debugNeedsLayout` is assigned inside an `assert`, so it throws
with asserts stripped — release and profile only. Every open inline equation
broke its paragraph's layout in the build a student downloads, and the whole
suite passed. A sweep is the only way to check for more.

### 1.7 Specify the ink blob format · **S**

[Ink spec §2.2](../specs/13-ink-data-spec.md) describes the reference an ink
block stores and then says the bytes behind it are not specified here. That is
the one place the openness guarantee is unmet: an independent implementation can
read every other part of a notebook and cannot draw the handwriting.

It is a writing job, not a design one. `app/lib/ink/ink_codec.dart` documents the
format thoroughly and the encoding is deterministic; it needs transcribing into
the spec as a byte layout, with a worked example.

### 1.8 MathML export · **S–M**

[Maths spec §6](../specs/12-math-input-spec.md) specifies it and nothing builds
it, so an equation leaves Openote as LaTeX only. Two consumers want it: a tool
importing an exported notebook, and a screen reader — which is the same audience
as the accessibility work in [v1.0.2](v1.0.2.md), and the reason this is worth
more than its size suggests.

Derive it from the stored LaTeX at export time rather than storing it. There is
already a MathML parser in the tree, `onenote/mathml_latex.dart`, going the other
way for OneNote import; it is a reference for the vocabulary, not something to
reverse.

### 1.9 Two acceptance criteria this project set itself and did not meet

Both are [ADR-0004](../adr/ADR-0004-editor-engine.md)'s, and both are small.

**The opening `$` of an inline equation is still a character the caret steps
onto**, so one press of an arrow key moves nothing you can see. Criterion 3 asked
for the equation to behave as a single atom, and arrowing into one now hands over
to the equation editor properly — this last step is what is left of it. Measured on
`a $x^2$ b`: eight presses of the right arrow from the start give offsets 1, 2, 3,
3, 3, 3, 3, 3. Update the ADR's own table when it is fixed, rather than this line
alone.

**A CJK and IME pass on Windows and Linux**, criterion 5, has never been done.
Composition is inherited from a stock `TextField` rather than reimplemented, so it
is probably fine. "Probably" is the problem, and it needs somebody who types in one
of those languages rather than a test.

### 1.10 Finish the translation coverage

Several dialogs are still Dart string literals rather than `.arb` messages —
sync, AI access, the planner and study panels, and the passcode dialog, whose
warning about what protection does *not* cover is the one most worth
translating.

---

## 2. Structural, blocked on a decision

### 2.1 The spreadsheet engine · **L**

Formulas, cell styling and charts cannot be *imported* because there is nothing
to import into: the table block has no formula model, no per-cell styling and no
chart. So this is not an importer gap, it is a design pass — decide what a table
block can hold, then the importer fills it. Live data from an API belongs to the
same pass.

### 2.2 The structured `nodes` text model · **XL**

Specified in [Data Model §5.1](../specs/11-data-model-spec.md), unbuilt. One
landing site by design: `OnoteTextEditor.serialize` / `deserialize` /
`textStorageKey`. `block.patch` bought most of the *size* win a finer model
promised, so what remains is the correctness half — two edits to one paragraph
still resolve last-writer-wins.

### 2.3 Op-log segments and compaction

[v0.11 Phase 2](archive/v0.11-size-and-speed-overhaul.md) plans rotation,
gzipped closed segments and per-device compaction. **Read
[v0.13](v0.13-op-log-compaction-review.md) first** — it designed the same thing
twice, found it unsafe, and is recorded as rejected. The disk cost is real; the
proposed fix was not safe. Do not implement without answering every objection
in v0.13.

---

## 3. Decided against — for now

Each would be welcome; each has a reason it is not next, and a trigger.

| Item | Why not now | Trigger |
|---|---|---|
| **3D graphs** | Needs a second grammar (two variables), a second painter and a projection. Measured cheap to *draw* — 0.60 ms/frame at 60×60 — and expensive to *fit in*. 2D is shaped so 3D lands as an added file. | The owner asking for it directly |
| **Android / tablet** | Not the same app on a smaller screen: sync is a folder, and scoped storage makes that a new storage backend | Desktop settled, and demand |
| **Ink-to-math** | High appeal, XL cost, no recognition surface to build on | Usage evidence from the study loop |
| **Real-time co-editing** | A transport swap over the op log *later*; per-character merge needs §2.2 first. Shared-folder and git group notebooks already cover group study | §2.2 landing |
| **A first-party sync service** | Contradicts "point it at a folder you already have", which is what makes self-hosting trivial | Users asking |
| **PPTX rendering** | Needs a converter on import, or export-to-PDF first. A `.pptx` lands as an attachment | Someone needing it |
| **Code signing** | A few hundred a year per platform. MSIX, winget, Chocolatey, Homebrew and Flatpak are each gated on it, and MSIX is the only route to OS-scheduled notifications | A funded year, or a distro asking |
| **Per-machine (admin) install** | Easy to add to the same script. Nobody has asked | A lab or school asking |
| **Multiple calendar subscriptions** | Two feeds is a manager — add, remove, rename, colour, enable. One feed covers a student's timetable | Someone genuinely having two |
| **A week/day timetable grid** | The month grid exists and is off by default, because the agenda is what gets read daily. A grid is a nice thing, not the same feature as knowing what is next | Demand |
| **Attaching notes to an event** | "Open my notes for this lecture" wants a feed-UID→section mapping, which is per-workspace state of exactly the kind that has bitten before | Two-machine sync testing done |
| **Number bases** (binary, hex, octal) | Explicitly not a priority, and nothing in the current maths design earns it a place without clutter | A design that absorbs it cleanly |
| **`Ctrl+Space` into the symbol panels** | `Shift+F10` and the object row's F6 region cover the need; this was the last of the keyboard pass and nobody has missed it | A report |
| **A blank graph on the Insert menu** | A graph is a graph *of* something and has no editor of its own, so a blank one is a box with nothing to change. The route is the Graph button on the equation's row | — |
| **System interpreters for code cells** | Needs real per-platform OS sandboxing — AppContainer, bubblewrap, sandbox-exec. A confirmation prompt is not a sandbox, and a system interpreter's default authority is the whole machine | Sandbox work being worth a release |
| **Code cells: page sessions, write-back, chart output** | A session reintroduces "works only if you ran that other cell first", which standalone cells are free of. Write-back crosses the compute/mutate line. Charts share a component with the spreadsheet ask (§2.1), so building one twice would be the waste. [Archived plan](archive/v0.14-local-code.md) §5 | §2.1, for charts |
| **Equation numbering, units, chemistry, MathML import** | Each is real and each is small next to the maths work already done. Owned by [v0.21](v0.21-outdo-onenote-maths.md), ranked there | — |

One idea worth keeping from a rejected design: **press a symbol with the caret
in a paragraph and an inline equation starts, seeded with that symbol.** The
dock it came with was rejected; this part was not.

---

## 4. Not doing

| Item | Why |
|---|---|
| **Writing to a calendar** | Openote has no account and no credentials. A re-date control that appeared to work until the next refresh is the wrong answer to "read-only" |
| **Timezone conversion** | Dart ships no IANA database, so a `TZID` reads as floating local time. Correct for a student's own timetable on their own machine, wrong abroad, and said out loud in the calendar warnings rather than guessed at |
| **Step-by-step worked solutions** | The deep well the vision's non-goals name. Showing working is the part a student would most want right, and getting it wrong is worse than not offering it |
| **A CAS** | Same |

---

## 5. Carried verification

Things believed to work that no human has confirmed. Carried so they do not
silently become "known good".

- [ ] The macOS and Linux builds, used for five minutes each (§1.1).
- [ ] Touch and stylus drawing on real hardware — pressure, tilt, palm
      rejection, the barrel button. The logic is unit-tested; the feel is not.
- [ ] `rebuild-from-log` against the real imported notebook —
      `syncMissingBlobs` empty, plus a page-sample mirror comparison.
- [ ] One OneNote PDF export of a page with a floating image, to close the
      circular image-`y` check in the importer.
- [ ] The [style guide](../05-style-guide.md) read against `theme/tokens.dart`
      and `theme/onote_theme.dart`, value by value.
- [ ] That the ChatGPT desktop app picks up the MCP entry Openote writes into
      `~/.codex/config.toml`.

---

## Appendix A — the git join that produced an empty notebook

Kept because the *dead ends* are worth more than the fix. Reported as: *"it got to
the first step, it even created the notebook, but after several minutes it still
hadnt imported any pages and had made no further progress."*

`git_join_test.dart` passed throughout. It only ever joined a notebook **created
inside the test**; every defect was on the path of joining a notebook someone
**already had**. Six causes, each of which alone produces an empty notebook:

1. **No page-content backfill.** Two backfills existed — nodes and blob bytes —
   and none for blocks. Ops are only written at the moment of a mutation, so
   every page written before a notebook was shared was invisible to the log.
2. **A deleted page rolled back the entire pull.** Pages were written for every id
   the ops mentioned, including deleted ones whose node row is deliberately not
   written → `page_mirror` foreign key → and the pull is ONE transaction, so one
   dead page discarded every page.
3. **A deleted section orphaned its pages** — the same foreign key one level up,
   because `deleteNode` recorded one op for a whole subtree.
4. **…but a parent that was merely never recorded had to be rescued, not
   dropped.** Logs are permanent, so repositories from older builds exist for
   good. The materializer now tracks *purged* ids to tell the two apart.
5. **The push raced the backfills**, and the recorder decided whether to back-fill
   at *open* time — so a warm started before sharing installed with it off.
   Decided at **install** time now, so no caller has to say it twice.
6. **Any failure looked like a hang.** `joinNotebookFromGit` documented "never
   throws" and only guarded the clone; the dialog cleared its busy flag on one
   branch only. A constraint error hundreds of lines away presented as a spinner
   with Cancel greyed out — and retrying the same address reported success
   without pulling, so there was no way to recover from inside the app.

**The durable lesson:** a green end-to-end test proved nothing here, because it
constructed its own subject. The bugs lived in the difference between a notebook
the test made and a notebook a person had.
