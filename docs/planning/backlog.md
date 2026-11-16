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
| 1 | **Use the macOS and Linux builds** | S | Windows is the only platform a human has used end to end. Linux has now been opened and updated on a Fedora VM, but import, draw and sync there are unchecked, and macOS has never been run by a person. CI proves both compile. §1.1 |
| 2 | **Split `AppState`** | M | It holds most of the app's state and keeps growing, because every feature since the last split landed in it. This is the tax on everything below. §1.2 |
| 3 | **Blob garbage collection** | M | Nothing has ever deleted a blob. Unblocked now there is one store rather than two. §1.3 |
| 4 | **The spell checker knows mitochondria and not Monday** | M | Four reports in one: the bundled list is a Scrabble lexicon, so every name and most of this decade is underlined. §1.16 |
| 5 | Dark slides | S | Annotating a white 2× raster at night is a flashlight. |
| 6 | Page thumbnails for slide sections | S–M | A 60-slide deck is navigated by eye; the outline is text only. |
| 7 | HTML export | M | The only export a phone reads losslessly, and it is linkable. |
| 8 | The spreadsheet engine | L | Eric's long-standing second ask. Blocked on a design decision, not on effort. §2.1 |
| 9 | Audio pinned to notes | L–XL | Arguably bigger than flashcards for lecture-goers. Wants #3 done first. |
| 10 | OCR on images | L | Additive — search already indexes a hidden text layer. |
| 11 | The structured `nodes` text model | XL | Gates paragraph collapse and real co-editing. Not per-run styling any more — two styles on one word work in the Markdown the blocks already hold. §2.2 |

---

## Raised on GitHub, not yet placed

Read 8 November. Each is waiting for a decision on which release, if any; the
sizes are first guesses. When one is placed it moves to that release's document. Rows
marked **→** were placed on 8 November and are kept here, with their reasoning in
[v1.0.3](v1.0.3.md#raised-since-6-november), until the release is cut, so the issue
numbers stay findable.

| Issue | Item | Size | Notes |
|---|---|---|---|
| [#20](https://github.com/icmric/openote/issues/20) | **Configurable pan and zoom chords** | M–L | The rest of #20 is diagnosed and planned in [v1.0.2](archive/v1.0.2.md#14-selecting-and-moving-over-pictures-and-pdfs). What stays here is the asked-for Alt-drag pan and Shift+Alt-drag zoom for tablet users, and Alt-drag already moves a text box. Space-drag pan is the cheap, conflict-free part and could go first |
| [#20](https://github.com/icmric/openote/issues/20) | **Split ink that has already merged** | M | Strokes written within two seconds of each other became one object wherever they were (v1.0.2 fixes the cause). Existing merged ink can be split with the lasso; a "separate the pieces" command that splits by the gaps between strokes is the discoverable version |
| [#15](https://github.com/icmric/openote/issues/15) | **An interface scale** | M | One multiplier for the app's chrome, leaving note text alone. Do it beside the text-scaling bug ([carried into v1.0.3](v1.0.3.md#carried-over-from-v102)), which is the same widths measured without a scale |
| [#14](https://github.com/icmric/openote/issues/14) | **An all-notebooks navigator** | L | Every notebook as a top-level row, expandable. Navigation only — the issue rules out several editors. The smaller cousin of v1.0.3's [several notebooks open at once](v1.0.3.md#several-notebooks-open-at-once) |
| [#18](https://github.com/icmric/openote/issues/18), [#43](https://github.com/icmric/openote/issues/43) | **Navigator suggestions** (the right-click "new" menu from #43 is [placed in v1.0.3](v1.0.3.md#from-github), and should take the add buttons with it) | S each | Put "add section", "add group" and "add page" below the last item, where people look; show the recycle bin as a summary ("3 pages · 1 goes in 5 days") rather than a button that looks like delete; the section name repeated above its pages, where right-click does nothing; "Move to group" offering a new group; "exam date" as a general countdown; shorter menu labels; choosing a section's or page's icon |
| [#7](https://github.com/icmric/openote/issues/7) | **Custom colours** | S–M | Saved palettes and an eyedropper for ink and text |
| [#7](https://github.com/icmric/openote/issues/7) | **Self-hosted sync, explained** | S | Plain instructions for keeping a notebook on your own server (Nextcloud, WebDAV) with the folder sync that exists |
| [#7](https://github.com/icmric/openote/issues/7) | **German handwriting recognition and spelling** | XL | Recognition is the surface ink-to-math is waiting for (decided against, below); spelling may be smaller on its own |
| [#13](https://github.com/icmric/openote/issues/13) | **A pinned second side panel** | M | Tagged for v1.0.2 and did not ship; the issue has had no reply. The design is settled in [v1.0.2 addition 26](archive/v1.0.2.md): one panel by default, a pin keeps it open beside the next, at most two, and on a narrow window the pinned one becomes a drawer |
| [#34](https://github.com/icmric/openote/issues/34) | **Hold the stylus still to erase** | S–M | Asked for by a OneNote-on-Android user: hold the pen in place for a moment and it becomes the eraser, lift it and the pen you had comes back. The pen's side button already switches tools (v1.0.2); what is new is a dwell detector that cannot fire on a deliberate dot or the pause between two words |
| [#36](https://github.com/icmric/openote/issues/36) | **Import a OneNote notebook from a share link** | M | **Investigated; a way exists, the route is not chosen. Not in v1.0.3.** For an "Anyone with the link" share the link opens an anonymous session and the notebook is a folder of real `.one` files, so nothing about the *person* needs signing in. What does is the *app*: a plain client is refused and **impersonating a browser is ruled out**. Two routes are left — Microsoft Graph signed in as any Microsoft account (documented, stable, one sign-in, probably a broader permission), and an embedded browser (no sign-in, heavy, leans on endpoints that are not a contract) — and three yes/no questions decide between them. All of it, with the order to answer them in, is in [onenote-share-link.md](onenote-share-link.md). The reply on the issue said "the next update"; that is owed a correction |
| [#38](https://github.com/icmric/openote/issues/38) | **→ v1.0.3 M6.** **Coded on the branch 10 Nov; hand test owed.** The "Deleted … Undo" toast never goes away | S | Cause found: Flutter keeps any toast that has a button, and this is the only one. `persist: false` and a duration. Also hide it when Ctrl+Z has already undone the delete |
| [#39](https://github.com/icmric/openote/issues/39) | **→ v1.0.3 S4.** **Coded on the branch 10 Nov (text on the clipboard; hand test owed). Still open: handwriting- or graph-only copies, which an older image can beat.** Ctrl+V pastes the wrong clipboard | S–M | Not reproduced. Copying a box never touches the system clipboard, so an image or file already there always wins. Write the boxes to the real clipboard on copy; copy-to-another-app and paste-after-restart come with it |
| [#40](https://github.com/icmric/openote/issues/40) | **→ v1.0.3 M7.** **Coded on the branch 10 Nov (pastes at the pointer; hand test owed).** A pasted box lands on top of the last one | S | Every paste goes to the source's position plus 28 px, so repeats stack; and right-click → Paste puts every copied box on one point. Ask the reporter where they expected it to land |
| [#41](https://github.com/icmric/openote/issues/41) | **→ v1.0.3 S5.** Buttons are too small to hit | S–M | Measured: dialog buttons are *drawn* 20 px tall (compact density takes 8 off a 28 px minimum) with a 40 px clickable box. One theme change plus a look at every dialog. Which reading the reporter means is open |
| [#42](https://github.com/icmric/openote/issues/42) | **→ v1.0.3 S5.** The Sync dialog is cramped | S | A 480 × 460 box with the 8 px scrollbar drawn over its controls. Wider, taller as a share of the window, a gutter for the scrollbar — in one shared place, since seven dialogs scroll |
| [#43](https://github.com/icmric/openote/issues/43) | **→ v1.0.3 C8.** A context menu to create things | S–M | Right-click on empty space does nothing today. One menu: section, group, page, notebook, open a notebook. The buttons stay — folding them into a menu adds a click. Same code as #18's *add below the last item* |
| — (found on #39) | **→ v1.0.3, with S4.** Does a picture survive being pasted into another notebook? | S to check | Blobs are per notebook and a copied box carries the picture's hash, not its bytes, so it should not. Untested. If confirmed, carry the bytes or copy the blob across by the source notebook's id |
| — (found on #41) | **→ v1.0.4.** *Comfortable / Compact* buttons, and comfortable by default for a pen or touch | S–M | The tablet people. Build it with [#15](https://github.com/icmric/openote/issues/15)'s interface scale, which is the same question about text. S5 fixes the default first |
| — (found on #43) | **→ v1.0.4.** Ctrl+T for a new section | S | OneNote's chord, and Ctrl+N (a new page) is already bound. Belongs with the button-size setting |

## Found in the 16 November trial, to fix before release

Done the same day: a new section goes below the active one and into its group; "section group" is now "group"; popup-menu rows get the click pointer from the theme (`click_cursor_test.dart` fails if a control family is left out); the shortcut text is gone from the status bar; the review panel glides to a suggestion (`CanvasController.glideTo`); an empty text box is dropped when the person leaves the page by clicking another (`_dropEmptyBoxBeingEdited`; the box was only cleaned up when its editor closed on the same page).

| Item | Size | Notes |
|---|---|---|
| **Highlight the word being reviewed** | M | The panel selects the box and glides to it, but the word itself is not marked. Find has the same limit (it works per box). Needs a "mark this range" in the read renderer (`MarkdownView`), fed by the open review item (`blockId`, `start`, `end`), and cleared when the card closes. The editor already draws underlines by range (`fixedMarks`, `misspellings`), so the edit view is the easy half |
| **Drag a section straight to a spot inside a group** | S–M | The drop pill offers "Move into group" over a group's rows, but a drop there lands the section at the end (or on the header) and a second drag is needed to place it. Dropping on the top or bottom quarter of a section *in* the group already places it (`reorderNode` re-parents). Find which zone the pill is promising and make the drop honour the row under the pointer |
| **Undo and redo for creating a page or section, and redo that is always there** | M–L | Undo is a snapshot of the *open page* (`pushUndo`), so tree changes (new page, new section, group, move, rename, delete) are outside it. Wants one history that holds both, so Ctrl+Z after "new section" removes it and Ctrl+Y brings it back. **Redo:** the automatic-correction undo (`_undoAutoFix`, Backspace and Ctrl+Z) bypasses the redo stack; it should push what it undid, so redo is there after *any* undo, however small. Check every other undo that bypasses the stack the same way |
| **Boxes that make room for each other** | L, needs a design | Typing in a box that grows into the box below should nudge that box down to keep a gap, cascading down the page. **Rules to settle first:** only boxes that are *stacked* (overlapping horizontally, below, close by), never a box off to the side or a drawing; keep a gap rather than snapping to a grid; never move anything that was not touched by the growth; one undo step for the whole nudge; and an **undo pill in the same style as the autocorrect marker** (`fix_notice.dart`), so it is plain that the app moved something and one click puts it back. Mock the cascade on the design canvas before building |
| **Bring the design canvas up to date and keep it organised** | M | The review boards still show the old red/amber/blue colours (now orange, blue and reddish purple, with a wavy, double or dotted line: `spell/review_marks.dart`), the old text chip, no grip on the sheet, no autocorrect marker. Keep the per-menu and planning boards, but give the canvas a fixed order (shell, navigator, panels, menus, dialogs, planning) and a short "what changed" note per release, so a change starts from a current board |

## The owner's UI notes, 11 November

From going through the [design recreation](design-mockups.md) next to the real app. **None is placed in a
release**: they were noted to be thought through, not fixed now. Sizes are first guesses.

| Note | Size | What was said, and what is already known |
|---|---|---|
| **A default text style for new boxes** (owner, 13 Nov) | S–M; bullets and the rest later | Settings: the font, size and colour a NEW text box starts with. Today these are set per box (`fontSize`, `font` and colour live in each box) and there is no global default, so a new box always starts in the app default. **Recommended shape:** stamp the chosen values into a box when it is created, rather than changing what an unstyled box looks like, so no existing page changes under anyone. The work is finding every place a text box is made (a click, type-through, paste, import) and giving them one creation path. **Flagged, not started:** default bullet style, numbering style, line spacing and heading sizes, which want the same one path plus a place in Settings that does not become a wall of options. Pairs with S8 (interface size) and the comfort pass S5 |
| **Offer to turn pasted Markdown into real objects** (owner, 15 Nov) | M, not placed | When Markdown is pasted (a table from an AI agent, a fenced code block, and the like), **do not convert it silently**: the owner wants nothing in a note changed without permission. Instead, while editing, **highlight it and offer a one-click "make this a table" (or code block, and so on)**. Out of edit mode it should still *render* as a table, as it does now. **Plain styling stays automatic**: headings, bullets, bold and italic are already what Markdown means in a text box and keep converting as they are typed. **Also asked:** Ctrl+Shift+V as a *plain paste* (text without source formatting), as in other apps; **unchecked** whether paste already carries formatting from other apps, which decides whether this is needed. The same offer pattern as the marker under an autocorrected word (`editor/fix_notice.dart`: show what happened, one click to choose, gone after a few more words). Wants a look at how `MathPasteFormatter` and the table and code importers already recognise pasted text, so the offer and the importers share one detector |
| **An icon per section, on top of the colour** (owner and dad, 13 Nov) | M, v1.0.4 | Pick a glyph for a section; the colour stays and tints it, and an unset section keeps the open ring. **Recommended scope:** a curated set of 100 to 150 Material icons in groups (school, science, work, life, shapes) with a search box, compiled in as constants so Flutter keeps only the glyphs used (a few KB, not the 1.5 MB font). **Store the icon by name, not by code point**, so it survives a Flutter upgrade and syncs between versions. A new optional field on a section, handled like its colour (format spec and sync rule updated; older notebooks stay valid). **Every Material icon** is a second step and the owner asked for it to be cheap on space: either ship the full font (about 1.5 MB), or fetch it once on request from our own release assets the way the video engine already is (checksummed, one line added to PRIVACY.md), **not** from Google Fonts at run time, which would add an unpinned connection and break the offline promise. A device without the full set shows a plain placeholder for an icon it does not have. Mock it on the design canvas first |
| **New sections cycle through colours** | S, plus design time | Today every section defaults to the same colour. **Decided:** cycle through a palette as sections are *made*; **existing sections are never touched**. The palette is the real work — it is the same for everyone unless they change it — and the owner finds today's look generic, too close to OneNote's tabs. **Explored on 11 November** on the design canvas ("Exploration: section colours"): eight colours with a dark and a light value each, warm and cool alternating, and three ways of marking a section — **A** the thin stripe (as today), **B** a chip with the selected row tinted in the section's own colour, **C** an open ring echoing the app icon. **Chosen (11 November): C, the open ring**, because it is the logo used somewhere it does some work, with a soft tint of the section's own colour on the *selected* row. **Hover** gets a matching but quieter wash: neutral rather than coloured, so selected and hovered never read alike (drawn in the sketch). *The palette values are still a first pass, not checked for colour-blindness.* **Quick picker:** offer the same eight the app cycles through, plus a custom colour, so any colour a section was given can always be chosen back. **Order:** the eight run round the colour wheel (Coral, Brass, Lime, Fern, Sky, Ink, Orchid, Rose), not alternating warm and cool, so a run of sections flows down the list and the eighth meets the first. **Group colour:** by default a group takes its first section's colour softened towards slate (no extra palette is needed, since it is computed), so it flows into its sections; the picker still lists only the eight. Both are tried on the Workspace artboard, where sections can be clicked, in dark and light. **Built on this branch, 11 November** (`theme/section_palette.dart`, `ui/sidebar.dart`; hand test owed): ring, tinted selection, quiet hover, group dot and rail, the eight in the picker, new sections cycling through the eight. Sections from earlier versions keep their colours exactly (tested), and a section wearing one shows it, chosen, in the picker. The light Ink is the app's own accent (`#5B5BE6`), not the sketch's first guess. **Still open:** the *custom colour* in the picker (it needs a picker that is not a hex box), colour-blind checking, and whether the collapsed strip should use the ring |
| **"New section" does not make sense beside a bare "+"** | S | The footer says *Section* with a folder icon while the new-page button, up in the pages header, is a plain plus. Two buttons that make a thing, said two ways. Settle it together with [#43 and #18](v1.0.3.md#43--one-menu-to-create-things): one way of saying "new", used for page, section and group |
| **Hide the Home tab** | S | Home (favourites and recents) has never earned its place for the owner. At minimum an option to hide it; whether it should exist at all is the larger question |
| **Drop "· open" and "1 open" from the notebook list** | S | The open notebook is already highlighted, so both say it twice |
| **More themes, and how to choose one** | M–L | Already [#12 and PR #22](v1.0.3.md#the-theme-catalogue-12). New here: the default stays *follow the computer*, and how a person *picks* one is undecided — a short list, swatches, or a gallery. Settle the picker before the themes |
| **One phrase for "follow the system"** | S | Theme says *System*, Language right under it says *Same as my computer*. **Decided:** *System default* (or *System*) for both, because a mobile version is intended and some people dislike a phone being called a computer. Use the same words wherever the app follows the device — theme, language, and any later setting |
| **The Sync dialog does too much** | M | See below. **Git stays in it, and stays visible**: it is not how most people would sync, nor the best way, but the owner wants the option, so it is *not* folded behind Advanced |
| **A popup animation from the lab project** | — | The one meant is the **"voice note uploaded" confirmation in the advent editor**. To be looked at for how it moves, **not** copied in style: that one is informational, and the undo toast has a real job (a button that works). **It was not found** in `C:\src\lab` on `main` (clean tree): the only animations in the source are a pulsing recording dot and a blinking cursor. It may be uncommitted elsewhere or live only on the deployed site; the owner will say where. The toast fix ([#38](https://github.com/icmric/openote/issues/38)) has not yet been tried by hand |
| **Bring notebooks over from other apps** | M–L, later | Obsidian first, as it is popular. **A Markdown-folder importer already exists** (`export/md_import.dart`, in the notebook list as *Markdown folder*): the chosen folder becomes a section, files become pages, nested folders become pages with subpages, `[[wiki-links]]` render, and YAML front matter is stripped. What it does **not** do is the list that makes an Obsidian vault feel moved: **pictures** (`![[img.png]]` stays literal text — the biggest gap), tags and front matter (dropped), the vault as a *notebook* with its folders as groups rather than one section, and `.canvas` files (Openote *exports* Canvas; it does not read it). It is a very different way of working — links and folders, not a page you place things on — so expect it to need decisions, not just code. Flagged for later. The same importer is the likely base for Notion, Joplin and Evernote exports, which are mostly Markdown or HTML; unchecked |

### The Sync dialog, backups and restore

**The dialog is three things at once.** *Where this notebook syncs* is one. *Backups* and *extra
copies* are another. Git is a third, for a few people. A great deal of the text on it explains what
the controls are rather than helping to use them. It was already capped and folded once, because
stacked open it was four screens (see `sync_dialog.dart`); it is still too much.

**Mirror and backup are the same mechanism with one number.** In `sync/mirrors.dart` a target with
`keepVersions` of 0 is a *mirror*: one copy, overwritten each time. One above 0 is a *backup*: that
many dated copies, oldest dropped first. The person never meant to choose a number, and the two words
mean nothing to someone who has not read the code. The fix is the vocabulary: **one thing, "Backups"**,
with *how many to keep* hidden away. (The first two parts of [v1.0.3's C2](v1.0.3.md#could--in-order-cut-from-the-bottom),
which make the label match what the code does, are the cheap start.)

**There is no way to restore, and that is the real gap.** Taking copies nobody can read back is not a
backup. v1.0.3's C2 calls restore L.
The owner's requirements, as stated:

1. **A default place that just works.** Nobody is made to pick a folder. They can change it, and add
   more than one (a local copy *and* one in a cloud folder).
2. **Somewhere the notebook being deleted or corrupted cannot reach.** Not inside the notebook's own
   folder, and a synced folder is a poor home for the only copy, because a sync *replicates* a delete.
3. **Restore inside the app, in two cases:** put an existing notebook back to an earlier point, or
   bring back a notebook that has since been deleted, which means making a new one and filling it in.

**Where to keep them — a view, not a decision.**

| | Beside each notebook | One place for everything |
|---|---|---|
| Survives the notebook being deleted | **No** | Yes |
| Survives its folder being corrupted or synced-away | No | Yes |
| Finds a *deleted* notebook's backups | Cannot | One list holds them all |
| Cost | None | A new default folder the person did not choose |

One place wins on the owner's own test. A sensible default is a folder in the person's own documents,
outside any cloud folder, with *add another place* for the cloud copy.

**Size, and how to keep it down.** Settled by the owner: most pages and pictures do not change between
backups, so storing each backup in full would be wasteful, and they should be stored as little as
possible. Two ideas were raised — compress, or store only the differences — and they are not the same:

| | What it saves | Where it falls short |
|---|---|---|
| **Compress each copy** | Text and the op log shrink well | Pictures, PDFs and video are already compressed and barely move. The bulk of a student's notebook is exactly those |
| **Store each thing once, and let backups point to it** | Everything that did not change costs nothing, pictures and PDFs included | Needs the bookkeeping below |
| **Store differences, rebuild on request** | The same saving for text | More machinery, and a restore has to replay a chain; one damaged link spoils everything after it |

**Recommend the middle row, with compression on top.** Openote already stores pictures and files **by
their hash**, so a backup can be a small list ("this page at this version, these pictures") over one
shared store, and a restore is just reading the list. If the op log is append-only a backup of it may be
no more than *how far it had got*, which would make it nearly free; that needs confirming in the store
format. This is also how deduplicating backup tools work. **The price is the one hazard this
project already knows:** once backups share files, deleting an old backup means deciding which shared
files nothing else uses, which is the same unsettled question as [blob collection](#13-blob-garbage-collection--m),
and a wrong delete costs a backup somebody was counting on. Do that bookkeeping once, and test it hardest.

**When, and how many are kept.** *Set by the user.* The default is **every two days**, with choices from
about every hour to about every two weeks. Keep the typical thinning: the few latest copies, then one
from about two weeks ago, one from a month ago, two months, and so on, spacing out as they age. The
numbers are the owner's to tune; the shape is the standard one. Two cases to decide: a backup that finds
nothing changed (skip it, and say so), and a computer that was off when one was due (take it at the next
start, not never).

**Still to measure:** the real size of a stack of backups of a real notebook, once the shape above is
chosen. The owner's old OneNote one is 184 MB.

**Restore, in two verbs.** *Restore as a new notebook* is always safe: nothing is overwritten, and it is the
only route for a notebook that no longer exists. *Put this notebook back to then* replaces what is there,
so it should take a fresh backup of the present first, and be the second choice, never the first button.
The list shows dates in plain words, grouped by notebook, with a *Notebooks no longer in Openote* group.

**The dialog after that.** *Sync* keeps the folder choice and the computer name, and loses its prose.
*Backups* becomes its own place — a list, a *Back up now* button, a place to add destinations, and
restore. Git stays visible in Sync, as its own labelled choice. Each question has one home, which is the design rule the
rest of the app follows.

---

## 1. Engineering debt

*Section numbers are references other documents use, so they are not reused or closed up: §1.4 (the imported-image label) and §1.8 (the ink format) shipped and are gone.*

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
  is the same problem as the dead video in [v1.0.2's decision on deleted media](archive/v1.0.2.md#decisions-taken), and
  `blob.forget` is the sketched answer.
- **The clipboard and the undo stack are reachability roots** and ADR-0007's
  list of four does not mention them. A blob whose only reference was just cut
  is reachable from the cut.

`store/media_gc.dart` is the shape to copy: a wrong keep costs disk, a wrong
delete costs somebody's lecture, so every decision in it is deliberately
asymmetric, and no evidence is never treated as evidence of absence.

### 1.5 Large file drops read the whole file into memory

`canvas/media_drop.dart`, in the two drop handlers. Insert ▸ Video already
streams. The half of this that *lied* — a drop that landed nothing and said
nothing — is fixed; the progress half is not.

**Check first whether this is [#33](https://github.com/icmric/openote/issues/33)** — PDFs of about 4 MB and up will not open, reproduced on every route that inserts one. No size limit turned up in a search of `lib/` and `onote_core`, so the cause is unknown; a whole-file read is one suspect among several.

### 1.6 Keep source files searchable

`test/source_hygiene_test.dart` now refuses any control character in `lib/` or
`test/`, because ripgrep treats a file containing one as binary and skips it
entirely. That is how nine hundred lines of `text_block_view.dart` became
invisible to every code search in the repo.

The rule is live and the trap is one keystroke away: a LaTeX escape typed into a
comment through a shell that interprets it becomes a control character silently.
Ten files were carrying one when the check was widened, and two of them were tests
whose assertions had been vacuous as a result.

### 1.7 `lib/` must not touch a `debug*` member outside an assert

`RenderObject.debugNeedsLayout` is assigned inside an `assert`, so it throws
with asserts stripped — release and profile only. Every open inline equation
broke its paragraph's layout in the build a student downloads, and the whole
suite passed. A sweep is the only way to check for more.

### 1.9 MathML export · **S–M**

[Maths spec §6](../specs/12-math-input-spec.md) specifies it and nothing builds
it, so an equation leaves Openote as LaTeX only. Two consumers want it: a tool
importing an exported notebook, and a screen reader — which is the same audience
as the accessibility work [carried into v1.0.3](v1.0.3.md#carried-over-from-v102), and the reason this is worth
more than its size suggests.

Derive it from the stored LaTeX at export time rather than storing it. There is
already a MathML parser in the tree, `onenote/mathml_latex.dart`, going the other
way for OneNote import; it is a reference for the vocabulary, not something to
reverse.

### 1.10 Two acceptance criteria this project set itself and did not meet

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

### 1.11 Nothing ever deletes an orphaned op log

`ops/` keeps every log any device ever wrote. The device **count** no longer
counts the abandoned ones, but the files stay — on a real notebook that is 1.6 MB
of history from a laptop that last wrote in September.

The identity fork that was minting them is fixed, so this stops growing. What is
left is the backlog of ones already there, and removing one is **deleting
content**: an old device's ops are as valid as any other, and the materialiser
reads them to build the notebook. Dropping a log drops whatever only it recorded.

So this is the same question as §1.3, and wants the same answer: retire a log
deliberately, with evidence that everything in it has been superseded, rather
than sweeping by age. Worth doing together.

### 1.12 The blob repair leaves Drive's old duplicates behind · **S**

Measured on the owner's notebook: **17 files, about 5 MB**, named
`<hash> (1).pdf` through `<hash> (8).pdf`.

These are from before the `.blob` suffix landed, so the cause is fixed and the
pile is not growing — every one is dated the day before the fix ran. What the
repair did was recover the *bytes* (the canonical file is there) without removing
the copies, because it looks for `<hash>` and `<hash>.blob` and these have a
space and a provider-chosen extension.

**The safety property is unusually good here, which is why it is worth doing:**
the hash is the filename, so a file called `<hash> (N).anything` whose contents
hash to `<hash>` is *provably* a redundant copy of a file we already have. Verify
the bytes, then delete. It cannot be wrong about what it is removing, which is not
something that can be said of §1.3.

### 1.13 `cloud_sync_test`'s purge assertion still flakes

*"Purging a joined notebook leaves the other device alone"* passes alone and fails
under a full suite, roughly once in several runs:

```
Expected: null
  Actual: 'GREW   ops\<device>.oplog  1489 -> 1936 B'
```

**Do not weaken the assertion.** Byte equality is the right bar — a purge that
appended one op to a log in a shared folder would replicate the deletion to every
other device, which is the data-loss class commit 320e0be was.

The test has been de-flaked three times and its comments record each cause: the
watcher's stop was not awaited, then a pull that watch had already fired, then the
fact that settling drains the jobs in flight at the moment it looks and not the one
that starts a millisecond later. The current baseline waits for two consecutive
reads to agree, and this is a fourth occurrence of the same shape — **something
still appends to the shared folder after both devices' auto-sync is off.** That is
worth finding on its own terms, because a write nobody expects into a replicated
folder is interesting whether or not a test is watching.

### 1.14 Finish the translation coverage

Several dialogs are still Dart string literals rather than `.arb` messages (the update notice was the last to move, in v1.0.2) —
sync, AI access, the planner and study panels, and the passcode dialog, whose
warning about what protection does *not* cover is the one most worth
translating.

---

### 1.15 There is no way to pan with a pen · **S**

Middle-drag pans, two fingers pan, the wheel scrolls, and a graphics tablet
has none of those. A pen drag on empty page is a selection box, so somebody
working with a stylus can only move around the page by the scroll bar.

From [#20](https://github.com/icmric/openote/issues/20): *"customizable
shortcuts would be really helpful for graphics tablet users. For example,
holding Alt + left-drag to pan and Shift + Alt + left-drag to zoom."*

Two sizes of answer, and the small one is worth shipping on its own: **one
modifier that means pan**, chosen rather than configured. Space-drag is the
convention everywhere else and is free here; Alt is not, because Alt-drag
already means "move this box instead of selecting its text", which is the
escape hatch a text block needs.

The large one is bindings somebody can change, which wants a settings surface,
a store, and a decision about what is bindable — a release of its own, and the
owner has said as much on the issue.

### 1.16 The spell checker knows mitochondria and not Monday · **M**

The owner: *"we do currently have spellcheck but its not particularly good (it
doesnt pick up on many words, lots of the time it can tell you something is
wrong but doesnt give options for what it thinks it might be, doesnt auto
correct if it has high confidence, doesnt as far as im aware support different
styles of language like Australia vs Brittish vs US English)."*

All four are true, and three of them are one cause: the bundled list is
**ENABLE**, a Scrabble lexicon. 172,823 words, public domain, and chosen for
coverage — of playable words. Measured against the asset we ship:

| in it | not in it |
|---|---|
| mitochondria, photosynthesis, calculus, semester | Monday, January, Australia, any name |
| colour, realise, organisation | favourite |
| laptop, okay | email, internet, website, online, app, blog, wifi, dataset |
| | don't, isn't — no contraction is in it |
| | etc, vs, PhD, OK |

So every date, every place, every person and most of this decade is underlined,
which is what "doesn't pick up on many words" means. Note the dialect row: some
British spellings are in and others are out, because playability is not a
dialect. There is no dialect to choose because there is no dialect in there.

**The work, in the order it pays:**

1. **Replace the word list.** SCOWL (permissive, same licence shape as ENABLE)
   publishes exactly the pieces this needs as separate files: a base list in
   size tiers, plus `british-`, `canadian-` and `australian-words`,
   `english-proper-names` and `english-abbreviations`. Assemble at build time,
   union with ENABLE — strictly better coverage than either — and let Settings
   pick the dialect, which is then a real choice rather than a label.
2. **Tokenise contractions and possessives as one word.** `don't` is one token
   or it is two misspellings.
3. **Better suggestions.** Generation is edit distance 1, unranked, which is
   why there is often nothing to offer: a transposition plus an omission is
   distance 2, and so is every typo in a long word. Add distance 2 for short
   words, split and join candidates (`alot`), a capitalisation-only candidate
   once proper names are in, and order by frequency rather than by the order
   the alphabet loop happened to generate.
4. **Autocorrect, narrowly.** Only on a word boundary, only when there is
   exactly one distance-1 candidate, and reversible — which is the same
   escape-hatch question as [v1.0.2 #28](archive/v1.0.2.md#28-auto-capitalisation),
   and should be decided once for both.

**Can we piggyback on the operating system?** Partly, and not the part that
would help most.

  * **Windows 8+** has one: `ISpellCheckerFactory` / `ISpellChecker` (COM),
    per-BCP-47-locale, with suggestions, a user dictionary and autocorrect
    pairs. Which dialects a machine actually has is a per-machine question
    answered by `get_SupportedLanguages`, and is tied to installed language
    features — so en-AU may simply not be there. That needs measuring on a
    real machine before it is designed around.
  * **macOS** has the best of them: `NSSpellChecker`, multi-locale, with
    `guesses`, `correction` and language auto-detection.
  * **Linux** has nothing system-wide. The convention is enchant brokering
    hunspell against the distribution's dictionaries, which is LGPL code and
    mixed-licence dictionary data — a question [ADR-0005](../adr/) has an
    opinion about.
  * **iOS and Android** have `UITextChecker` and `SpellCheckerSession`, which
    is what Flutter's own `DefaultSpellCheckService` wraps, and why
    `spell/spell_checker.dart` exists at all.

So a platform provider is two native plugins for two of five platforms, and it
buys a result that differs per machine: a word underlined on the laptop and
clean on the desktop, with no way to reproduce either in CI. The call: keep our
own checker as the default and the only one tested, fix the list — which is
where the complaint actually comes from — and leave a platform provider as an
opt-in behind a `SpellService` seam if anyone still wants it afterwards.

#### Investigated 11 November: grammar, dialects and other languages

Asked for by the owner: grammar checking too, and the dialect and language following the system —
Australian against American English in particular. Today's checker is one American word list
(`assets/dict/en_us.txt.gz`), distance-1 suggestions, no grammar, and a plain on/off setting.

**Harper** ([Automattic](https://github.com/Automattic/harper), Rust, Apache-2.0, offline) is a spell
*and* grammar checker, and it has real dialects: `American`, `Canadian`, `Australian`, `British` and
`Indian`. A throwaway program (built outside the repo) ran it on real sentences:

| | Result |
|---|---|
| The words that are all underlined today (Monday, January, Australia, *don't*, email, website, dataset, laptop, mitochondria) | **None flagged** |
| *colour*, *favourite*, *organisation* | American flags them and offers *color*, *favorite*, *organization*; **Australian and British accept them** |
| Typos (*recieve*, *lecure*, *definately*, *seperate*, *beleive*, *studnets*, *Teh*, *alot*) | All found, and **the first suggestion was right every time**; *alot* was also reported as "write it as two words" |
| Grammar (nine deliberate errors) | Caught five: *a orange*, *Its* for *it's*, *could of*, *Their* for *they're*, a missing Oxford comma. **Missed** *Me and him goes*, *This are*, *which was* and the wrong tense in *went yesterday*. Treat it as a good proof-reader of common slips, not a full grammar engine |
| Speed | First load of its dictionary **about 1 s**; a paragraph then lints in **about 30 ms**. Both must run off the UI thread |
| Size | The test program is 15.6 MB, dictionary included. Not measured as a library in a Flutter build |

**What it does not do.** **English only**: no German, French, Spanish, Italian, Portuguese or Chinese,
which are the app's other six languages. Its Markdown handling is its own, and the app's text is its own
dialect, so the text has to be cut into prose spans first (the current `_wordSpans` already does that)
and the results mapped back to raw offsets.

**Cost to know about.**
  * **The first build took 15 minutes** and the dependency tree is large (over 500 packages listed by
    `cargo metadata`, which overcounts for platforms we will not build; it includes the `burn` machine
    learning crate). A one-off, but CI time and the three-platform build both pay it.
  * **It must not go in `onote_core`.** That crate is the permissive tier with an allow-list of five
    licences ([`deny.toml`](../../rust/onote_core/deny.toml)); Harper's tree adds BSD, ISC, CC0, CDLA and
    four MPL-2.0 packages. All are fine for the AGPL app, none is fine for that promise. So: **a separate
    small crate and library** (say `onote_text`), reached the same way over `dart:ffi`.
  * The Rust, FFI and per-platform library are real work for something the user sees as a squiggle.

**Following the system.** Flutter reports the language and region the operating system is set to, so
`en-AU` should arrive as `en-AU` (**to confirm on a real machine**; Windows keeps display language and
regional format apart). The mapping would be: `en-AU` → Australian, `en-GB`, `en-IE`, `en-NZ`, `en-ZA` →
British (Harper has no New Zealand), `en-CA` → Canadian, `en-IN` → Indian, anything else → American. It
is the default, with a *Spelling and grammar → Language* setting that says *System default* and can be
overridden. Changing it must not reload the whole checker; Harper takes the dialect as a plain argument.

**Other languages: spelling is possible, grammar is not (yet).**

| | How | Catch |
|---|---|---|
| **Spelling in the other six** | Hunspell dictionaries, read by [`spellbook`](https://github.com/helix-editor/spellbook) (Rust, MPL-2.0, "alpha") or by our own Dart checker once a list is converted | Each dictionary has its **own licence**, several of them copyleft, so each needs checking before it is bundled. Suggestions are Hunspell's, which are good. Chinese has no word spaces and needs no spell check at all |
| **Grammar in the other six** | LanguageTool is the only mature one | Java, **gigabytes** of memory with its n-gram data (by Harper's own comparison), and LGPL. Not something to embed in a note-taking app. Skipped |

**Recommended order.** (1) The word-list fix already in this section, since it is cheap and needs no
Rust. (2) **Harper behind a `SpellService` seam**, for English: dialect-aware spelling, better
suggestions, and grammar underlines in a different colour from spelling, with a *Check grammar* setting
apart from the spelling one. (3) Hunspell spelling for the other languages when someone asks. The seam
matters most: the editor reaches the checker at three places (`live_markdown_engine.dart`, the right-click
menu, and the Settings toggle), so the engine can change without touching them.

**Open questions for the owner.** Is English-only grammar acceptable for a first release (the app is
used in seven languages, and a *Check grammar* switch that does nothing in German needs to say so)? Should
a grammar underline *replace* the word, or only offer a fix on right-click? And autocorrect: on, off, or
only for the sure cases (*teh* → *the*), which is still the escape-hatch question shared with
auto-capitalisation.

#### Decided 11 November, and the licence and build-cost checks

**Decided by the owner.**
  * **English-only grammar is acceptable for now, with a plan to widen it.** The plan is the table above:
    Hunspell spelling for the other six languages first, grammar later and only if a small enough engine
    exists. The settings must say plainly what a switch covers in the current language.
  * **Autocorrect is on by default**, for small high-confidence typos only (*teh* → *the*): a word that is
    not in the dictionary, has exactly one clear candidate one edit away, and is corrected on the word
    boundary, undoable with one Ctrl+Z (the same escape hatch as everywhere else in the editor).
  * **Auto-capitalisation is on by default** (the start of a sentence, a lone *i*) with the same undo.
  * **Each has its own switch in Settings**, next to the spelling one, so spelling, grammar,
    autocorrect and auto-capitalisation are four independent choices.
  * **None of it may touch other languages.** Autocorrect and auto-capitalisation run **only when the
    spelling language is English**. In German, French, Spanish, Italian, Portuguese or Chinese they do
    nothing, because capitalisation rules differ (German nouns), and a wrong "fix" in someone's
    language is worse than none. The language comes from the *Spelling language* setting
    (*System default*, overridable), **not** guessed from each paragraph; a note written in two
    languages is a known limit, with a per-section language as the later answer. Needs a test that
    types German and French and expects no change.

**Licence check — Harper (`harper-core` 2.13.0).**

| Part | Finding |
|---|---|
| **The code** | `Apache-2.0`, stated in the crate and the repository. Apache-2.0 may be combined into an AGPL-3.0 application (one-way compatible; the combined app stays AGPL). Obligations: ship the Apache licence text and Harper's notices with the app, keep the copyright lines, and mark anything we modify. We would not modify it |
| **Its dependencies** (268 entries in the real runtime tree) | Overwhelmingly MIT, Apache-2.0, Unlicense, Zlib, Unicode-3.0 and CC0. **Three are MPL-2.0** (`colored`, `cssparser`, `dtoa-short`, all pulled in by Harper's HTML sanitiser): a file-level copyleft that is permitted in an AGPL app (MPL-2.0 names the GPL family as compatible) as long as those files stay under MPL and their source stays available, which crates.io already does. One crate is offered as `MIT OR Apache-2.0 OR LGPL`; we take the permissive option |
| **The word list and the trained models** | **Not documented.** The crate ships no statement of where `dictionary.dict` (55,000 lines, "original dictionary import" with the dialect spellings) or the two trained grammar models came from, and a comment in the list says some entries were "probably imported from Wiktionary". The repository as a whole is Apache-2.0, so redistributing it on their claim is the normal basis, and individual words are not usually protectable, but **the provenance is a question for upstream**, not something we can establish. Worth asking before the release that ships it. (Not done from here: it is a conversation on their issue tracker, which is the owner's to hold.) |
| **The 24 MB thesaurus** | A default feature we do not need; turning it off removes it, and its data, from the build |
| **Where it may live** | **Not `onote_core`.** Its `deny.toml` allows five licences and ADR-0005 promises no copyleft in that graph; Harper's tree would add BSD, ISC and MPL. A separate crate, audited and added to the table in [LICENSING.md](../../LICENSING.md), keeps that promise intact. MPL and AGPL are both outside the permissive tier by design |

**The build cost, measured.**

| | Time | Size |
|---|---|---|
| First build, from nothing, as it would be with the defaults and full link-time optimisation | **15 min 29 s** | 15.6 MB test program |
| First build, with the thesaurus off and no link-time optimisation | **13 min 03 s** | 11.4 MB |
| Rebuild after changing only our own wrapper code | **4 to 5 min** (4:37 with optimisation, 3:55 without) | |

So it is **not 15 minutes on every build.** The bulk is one-off compilation of about 270 packages, and
`burn`, a machine-learning library Harper needs for its part-of-speech tagger and cannot be built
without, is a large share of it. CI already caches Rust dependencies for the core (`Swatinem/rust-cache`
in `ci.yml` and `release.yml`), so after the first run the dependencies are restored and only our own
crate rebuilds. **The cache is paid again** when `Cargo.lock` changes (a Harper upgrade), when GitHub
evicts it after a week unused, and once per operating system and Mac chip, because each builds its own.
Expect a cold release to take about 15 minutes longer on the slowest runner, then a warm one to add a few
minutes. Not measured: GitHub's runners (slower or faster than this machine), and the library built as a
`cdylib` inside the Flutter build. The release workflow would need the same cache line for the new crate.

**Is Rust necessary? No, but it is the best fit.**

| Option | Verdict |
|---|---|
| **Pure Dart packages** (`spell_check_on_client`, `simple_spell_checker`, a Norvig-style `spell_checker`) | Spelling only, from a word list, with no dialects and no grammar. They would match or slightly beat what we have now, not what Harper does |
| **The system checker** (`native_spell_checker`) | Differs per machine, no grammar, no tests in CI. The reasons in the first part of this section still hold |
| **Harper as a separate program**, speaking the language-server protocol (`harper-ls`) | No FFI, but ships an extra executable per platform and a process to manage. Keeps the Dart side simple; costs packaging |
| **Harper as a Rust library behind `dart:ffi`** | One native library the app already knows how to load (same pattern as `onote_core`), fastest, offline. The cost is the build above. **Recommended**, as a small crate beside `onote_core` rather than in it |

**Newer version.** Harper 3.0.0 (27 October) exists; 2.13.0 is what is pinned. Compared on 12 November by
building the crate against both: **it compiles with no code change and 22 of the 23 tests pass.** The
difference is exactly what an upgrade should be expected to bring: its release notes list one breaking
change (case-sensitivity in dictionaries) and a long run of new grammar rules, and one of them, "gonna,
gotta, wanna", underlines informal words that 2.13 leaves alone, which is the one test that failed. So the
upgrade is cheap in code and costs a pass through the rules it adds, silencing the ones that are advice
(see `new_group`). Pin the exact version either way, so a rebuild cannot change what gets underlined.

#### Built on the branch, 11 November (hand test owed)

Decided to ship it **inside the app**, not as a download or a separate program: `rust/onote_text` is
built and bundled by the same hooks as the core (Windows and Linux CMake, a macOS script chained from
the core's, both release workflows and the Linux package check). Harper is pinned at 2.13.0, thesaurus off.

| Piece | What it does | Where |
|---|---|---|
| **Spelling and grammar** | Red wavy line for spelling, blue for grammar; right-click shows the reason and the fixes. Dialect from the computer's region (en-AU is Australian) or *Settings → Writing → Spelling language*. Falls back to the old word list if the library is missing | `rust/onote_text`, `spell/writing_checker.dart`, `spell/writing_language.dart`, `editor/live_markdown_engine.dart` |
| **Typo fixes** | `teh` → `the`, only when one word is a sure answer; one typed character; never in code, links, equations, names or after an abbreviation | `editor/auto_writing.dart` |
| **Capitals** | First word of a sentence and a lone `i`; not after *e.g.*, *Dr.*, an initial, a number or an ellipsis | same |
| **Take-back** | Backspace straight after a fix returns the word as typed and the fix is not made again | `_undoAutoFix` in the engine |
| **Settings** | Spell check, Check grammar, Fix small typos, Capitalise sentences, each on by default and independent; *Spelling language* with *System default*; one line saying they are English-only for now | `ui/settings_dialog.dart`, all seven languages (translations are mine: want a native eye) |
| **Other languages** | Everything above is gated on one value, `AppState.writingDialect`, which is null when the computer (or the choice) is not English: no underline, no fix, no capital. Tested on German, French, Spanish, Italian, Portuguese and Chinese computers. **A change from before:** those computers used to have the English list applied to their notes and now get no checking at all, until Hunspell spelling is added for them | `writing_language.dart` |

**Checked.** 11 tests on the crate, 51 new Dart tests (including typing into the real editor one character
at a time, and Backspace taking a fix back), the whole suite (4,243 passed), the analyzer, and
`cargo deny` on the crate's licences. **Not checked:** a real `flutter build` of the CMake hook (a build
would have rewritten the core's DLL, which is left alone while the app is in use), the macOS script
(unverified on a Mac like the one it follows), the release and CI workflows (YAML parses, nothing ran),
and the app on screen. The first build on any machine compiles Harper: **about 13 minutes**.

**Reviewed and hardened, 12 November.** Running real student notes through it found and fixed:
words with digits and all-capitals acronyms (`H2O`, `CO2`, `UNSW`) were flagged as misspellings; every
lower-case bullet was marked "not a capital"; heading title-case, "expand `idk`", contraction and
spelled-out-number advice was underlined as if it were an error; one mistake produced up to three
overlapping underlines (`that that`); a line that began with a link or code span was silently not checked
at all (Markdown read the blanked indent as a code block); the right-click menu looked suggestions up for
only the first twelve misspellings and took them from a list that ignores the person's English (now they
come from the underline itself); a long check on a worker thread could stall a keystroke on the UI thread
(autocorrect now never takes the engine's lock); the old word list could still produce a "misspelled"
menu for a word the new checker accepted; and someone who had switched spell check off would have had
grammar switched on under them (it now follows that choice until they say otherwise). A fix spliced
in at a stale underline can no longer damage the note (the finding must still match the characters it
points at). **Measured:** about **112 MB resident** once the checker has loaded (peak 138 MB), loaded
in the background about 0.7 s after the first English text is edited; a 1,800-character block checks in
about 20 ms; an automatic-fix lookup about 0.7 ms. The memory is the real cost, and it is paid only by
someone who edits English text.

**Still open.** Harper's data provenance (see [LICENSING.md](../../LICENSING.md)); the 3.0 upgrade;
Hunspell spelling for the other six languages; whether an underline-free *Add to dictionary* for
grammar is wanted; a per-section language for notes that mix two.

#### Found in the owner's hand test, 13 November, and fixed

* **Autocorrect appeared never to fire.** Probed against the real engine: the "one letter away" rule *did* correct `definately`, `seperate` and `occured`, and it **missed** `dont`, `im` and `cant`, which are the first things anyone types. Worse, it picked rare real words for four common slips: `alot` became *alto*, `isnt` became *inst*, `realy` became *relay*, `dosent` became *docent*. **Replaced by a list** (`spell/autocorrect_table.dart`): the missing apostrophes (`dont`, `doesnt`, `im`, `ive`, `youre`, `thats` and the rest; never `its`, `lets`, `were`, `well`, `ill`, which are words) plus about 130 classic misspellings that could only mean one thing. Case follows the typed word (`Dont` becomes *Don't*); an all-capitals word is left alone; no entry depends on the dialect. It needs no native library, so it also works in the browser demo. The engine's own `autocorrect` function is now unused (left in `rust/onote_text` for now; remove at the next rebuild).
* **Ctrl+Z took the whole word away.** The app's undo steps back a burst of typing, so after an automatic fix the first Ctrl+Z removed the entire word and a second one brought back a half-state. Now the first Ctrl+Z straight after a fix takes back **only** the fix (the same as Backspace there), and from then on it is the ordinary undo.
* **Right-clicking a misspelling offered only Paste and Select all**, until the word had been left-clicked: the menu asked where the *caret* was, and a right-click does not always move it first. It now asks where the *pointer* is.
* **"its" and the words before.** `its` is a real word, so it cannot go in the list; but the word that FOLLOWS can show it was a slip. When the next word is finished the earlier one is put right: `its` before *a, an, the, not, been, got* becomes *it's*; `your` before *a, an, not* becomes *you're*; `their` before *is, are, was, were* becomes *there*. Only pairs where the other reading cannot exist (no one owns an *a*): `its going` is left alone (*its going rate*), as is `your welcome` (*your welcome pack*). Ctrl+Z and Backspace take it back, and it is not repeated for that pair. This is the first of the "highly likely" grammar fixes; more pairs are cheap to add.
* **A confidence for autocorrect.** Harper gives no probability, but ranks candidates by a score (lower is better) built from edit distance, whether the first letter is kept, apostrophe patterns, a *common word* flag on the dictionary entry, and dialect variants. Our own engine code can read it. **Plan:** autocorrect when the best candidate is flagged common, its score is under a threshold, and it beats the runner-up by a margin, with the threshold chosen against a few hundred real typos and their right answers (the test set comes first). Needs a Rust rebuild.
* **The suggestions are set apart** in the menu: bold, lightly tinted, no icon, a rule beneath, at most four. Tested against the old behaviour (the new test fails without the fix).

### 1.17 Two settings the rail was built to hold

Named by the owner while redesigning Settings — *"In time we will include more
options such as being able to adjust the text/icon size of the UI, custom
keybinding, and some other jazz like that"* — so they are written down here
rather than left as the reason a layout changed.

  * **The size of the interface's text and icons.** Blocked on, and not merely
    related to, [text scaling](v1.0.3.md#carried-over-from-v102): nothing in the app reads
    `textScaler`, so every width it measures for itself is measured at 100%
    while the widgets draw larger. A control that scaled the interface before
    that is fixed would ship the bug on purpose. Text scaling first, then the control,
    in Settings → Appearance.
  * **Custom keybindings · M.** `ui/keyboard_map.dart` is display data — the
    keys as a string and a sentence saying what they do — while the bindings
    themselves are 37 `SingleActivator`s wired straight to their call sites.
    Rebinding needs the actions to become addressable things with the map as
    their labels, which is the same registry a command palette would need
    ([v1.0.2 #30](archive/v1.0.2.md#30-the-command-bar) option C). Its home is a
    Keyboard group split out of Help, where the shortcut reference already is.

### 1.18 Say when a note holds something this build cannot read · **M**

The owner, on shipping `{{=RRGGBB text}}` for coloured highlights knowing an
older Openote shows the braces as text:

> *"Its fine if older versions just show the raw markdown, thats annoying but
> not a breaking bug, and no one is at this stage forced to stay on an older
> version due to lack of support AFAIK. That is the best case scenario for not
> handling something in an older version ... however ideally it should always
> just display the raw text like that if its something small or otherwise
> easily shown as raw text, otherwise just get hidden but kept and not touched
> so that when they update it all appears. Maybe displaying a message like
> 'unknown element, check for an available update' would be helpful instead of
> fully hiding it, although that adds a lot of complexity and i dont think is
> worth doing for this release as it is something i want to plan out the
> implementation more before doing."*

**So the rule, in the order it is wanted**, and it is worth writing down
because it is already most of what the format does:

1. **Small and readable as text → show the raw text.** What an inline run
   does today: a build with no `{{=…}}` draws the characters. Annoying,
   never lossy, and it costs nothing.
2. **Otherwise → keep it, draw nothing, change nothing.** What a block does
   today: `Block.rawType` and `unknownFields` carry a type this build has
   never heard of through every read and write (Data Model §3.2), and the
   canvas draws "Unsupported block: …".
3. **Better than silence → say an update would show it.** Not built, and the
   part that needs designing.

**What makes (3) more than a string.** There is no inventory of what a file
can contain, so nothing can currently tell "a thing from the future" from
"a thing we chose not to draw" (`frame`, a `file` with no viewer) or from a
typo. The pieces it would need:

- **A format feature list in the container.** `notebook_meta` already carries
  `features: []`, written and never read. A writer adding a new construct
  records its name; a reader that does not know a name there knows, before it
  opens a page, that something in this notebook is newer than it is.
- **One notice per notebook, not per block.** A deck annotated on a newer
  build could be fifty unknown blocks, and fifty cards saying the same
  sentence is worse than the silence. The status bar is where "this notebook
  was written by a newer Openote" already goes (`notebookIsReadOnly`), and
  that wording is the precedent to match.
- **A decision about inline runs**, which is where it gets hard: an unknown
  `{{?hex x}}` is indistinguishable from somebody typing braces, so the
  honest answer there may stay (1) for ever.

Until then the two rules that hold are (1) and (2), and every new construct
should be able to say which one it relies on. The coloured highlight relies
on (1); `board`, `graph` and `substitute` each relied on (2) when they
shipped.

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
| **Android / tablet** | Not the same app on a smaller screen: sync is a folder, and scoped storage makes that a new storage backend | Desktop settled, and demand. One request so far ([#34](https://github.com/icmric/openote/issues/34)): an Android tablet is that reporter's only OneNote device. **The owner intends to ship it at some stage** — a downloadable `.apk` first, the Play Store if it is free or a small one-off cost. The hard part is syncing with cloud folders (scoped storage; Drive and OneDrive are not ordinary folders there), then pen input and the touch layout. The plan is to mock it up in Claude Design first, from a faithful copy of the desktop UI (see [the design note](design-mockups.md)). Check the current Play Console registration fee and testing requirements for a new personal account before choosing the store route |
| **Ink-to-math** | High appeal, XL cost, no recognition surface to build on | Usage evidence from the study loop |
| **Beta updates you opt into** | Ruled out for now — "just going to add too much complication". Costed in full, so it need not be rederived: the switch must ship in a STABLE release before any beta can reach anyone (every installed copy asks for `/releases/latest`, which never returns a prerelease); `compareVersions` treats `1.0.3-beta.1` and `1.0.3` as equal; Inno's `VersionInfoVersion` must be numeric and `.deb`/`.rpm` want `1.0.3~beta.1`. About a day, most of it packaging | Releases slowing enough that finished work waits weeks |
| **Plugins** | A plugin runs with the app's access to every note, and the owner's answer on [#10](https://github.com/icmric/openote/issues/10) is security: "no plans as of yet … due to the potential security implications" | A design that sandboxes one |
| **Real-time co-editing** | A transport swap over the op log *later*; per-character merge needs §2.2 first. Shared-folder and git group notebooks already cover group study | §2.2 landing |
| **A first-party sync service** | Contradicts "point it at a folder you already have", which is what makes self-hosting trivial | Users asking |
| **PPTX rendering** | Needs a converter on import, or export-to-PDF first. A `.pptx` lands as an attachment | Someone needing it |
| **Code signing** | A few hundred a year per platform. MSIX, winget, Chocolatey, Homebrew and Flatpak are each gated on it, and MSIX is the only route to OS-scheduled notifications (but v1.0.3's [signing section](v1.0.3.md#signing-the-builds-and-the-warnings-on-all-three-platforms) argues a Homebrew cask and a Flathub manifest are **not** gated on it — settle which is right when this is decided) | A funded year, or a distro asking |
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
- [ ] The v1.0.2 touch fixes — two fingers zooming with one on a box, a finger scrolling over a box — on a real
      tablet. They were written against simulated pointers.
- [ ] That the macOS `.app` carries `Contents/Resources/AppIcon.icns`, as opposed to Launch Services showing a stale
      icon (v1.0.2 bug 11). Check the artefact, not the screenshot.

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
