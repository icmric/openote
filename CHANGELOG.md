# Changelog

All notable changes to Openote. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [SemVer](https://semver.org/) with the caveat that **the file format has its own versioning** (File Format Spec §2) and format compatibility is the promise that matters most here.

## [Unreleased]

### Security — your GitHub key now lives in your computer's own password storage

- **Openote now keeps your GitHub key in your computer's own password storage
  instead of a plain file** — Credential Manager on Windows, the Keychain on
  Mac, and the desktop's keyring on Linux. If you connected GitHub before this
  change, your key is quietly moved there the next time Openote starts, and the
  plain file no longer holds it.

### Added — Openote can tuck a notebook's working file out of the way

- **Openote keeps a working file for each notebook, and it can now tuck that
  file away and build it again from your notes whenever it needs to.** Your
  notes have never lived in that file — they live in the notebook's own folder,
  and the working file is only the copy Openote reads from while you have the
  notebook open. That is what makes it safe to move.
- **It is offered one notebook at a time, and nothing happens to a notebook you
  do not choose.** You will find it in the panel that already tells you where
  each notebook keeps its things. If you change your mind, **Put it back** puts
  the working file exactly where it was.
- **Notebooks you make from now on are unchanged.** They are still made the way
  they always have been; this is something you turn on for a notebook yourself,
  when you want it.

### Removed — the copy Openote took of every page every ten minutes

- **Openote used to quietly keep a copy of each page every ten minutes or so,
  and those copies are now gone.** They are cleared out of notebooks you
  already have, and they cannot be brought back — so if there is an old page
  you still want, get it out before you update.
- **Undo, the recycle bin and your backups all carry on exactly as before.**
  Undo still works the way it always has while you are writing, deleted pages
  still go to the recycle bin and still come back from it, and nothing your
  backups hold is touched. **Who changed this page** and the last ten deletions
  you can put back are both still there too.

### Added — a notebook can be built again from its own history

- **If a notebook's working file is ever damaged or lost, Openote can build it
  again from the history kept in the notebook's own folder** — your pages, what
  is on them, and their version history. It changes nothing at all unless it
  first finds everything it needs, and if it is interrupted partway you are left
  with either the old notebook or the new one, never half of each.

### Changed — your notebook is the folder, and there is one thing to double-click

- **Your notebook is a folder — `Physics.onotebook` — and everything inside it
  belongs to that notebook.** Inside it there is now a file called **Open this
  notebook**. Double-click that and your notebook opens, in the Openote you
  already have running if there is one. It is put there for every notebook,
  including the ones you already have, the next time Openote opens them. If you
  rename the folder, nothing breaks: the file is only a door, and Openote reads
  the folder it is sitting in rather than anything written inside it.
- **On some Linux desktops you can double-click the notebook folder itself.**
  Whether that works depends on which file manager you use, and we have not yet
  been able to check them all. The **Open this notebook** file inside works
  either way.
- **Openote now says so, plainly, if you try to open its working file by
  mistake.** The file that sits beside your notebook is Openote's own scratch
  copy, not your notes — opening it used to look as though it had worked. It
  now tells you to open the notebook folder instead.
- **Openote no longer puts itself in charge of `.onote` files**, and updating
  takes that away again rather than leaving it behind. You can still open one
  from inside Openote, and it is still copied into a notebook folder for you,
  exactly as before.
- **On a Mac, double-clicking a notebook still does not open it.** That needs
  work inside the Mac app which has not been done, and shipping only half of it
  would have made Openote open the wrong notebook. Open your notebooks from
  inside Openote there for now.

### Changed — your pictures and drawings now live in the notebook's own folder

- **Openote used to keep every picture and drawing in two places at once: one
  copy inside its working file, and one as an ordinary file in the notebook's
  own folder. From now on it writes only the file in the folder.** That is the
  copy that has always been the useful one — it is what another computer reads,
  what a backup picks up, and what you get if you copy the folder somewhere.
  Keeping a second copy inside the working file only made the file grow. Nothing
  on screen changes, and a notebook made this way opens in an older Openote.
- **Notebooks you already have carry on working while they catch up.** A picture
  that so far only exists inside the working file is still shown to you exactly
  as before, and is copied out into the folder in the background the first time
  you open the notebook. You can keep working the whole time.
- **A picture that arrived from another computer only half-copied is now thrown
  away rather than shown.** Openote checks that a picture really is what its name
  says before it goes on the page, so a download that was still in progress no
  longer turns into a broken image you cannot get rid of; the other computer
  simply sends it again.

### Changed — your notebook can now take about half the room it did

- **There is one button that stops Openote keeping every picture and drawing
  twice, and it gives you back about half the space the notebook was using.**
  On two real notebooks it took them from 63 MB down to 33 MB apiece. What it
  removes is the copy inside Openote's own working file; the copy in the
  notebook's own folder is kept — that is the one your notes point at, the one
  your other computers read, and the one your backups pick up. You will find it
  in the sharing window under Storage, and it says what it will remove and what
  it will keep before you press it.
- **It checks every single picture and drawing first, and changes nothing at
  all unless every one of them is already safe in that folder.** It also stops
  if there is not enough free space on your disk to do the job safely. When it
  stops it tells you why in a sentence, and not one picture has been touched.
- **If you ever want the second copies back, Openote can put them there
  again**, and it checks each one on the way in.

### Added — see who changed what, and get recent deletions back

- **Openote now keeps track of who last changed each part of a page.** Open the
  page history button and every paragraph, picture and drawing you can see says
  which computer it last came from and when. It costs nothing extra: Openote
  works it out from the record of your edits it already keeps, so no notebook
  gets bigger and nothing extra is synced.
- **The last ten notable deletions are remembered, and you can put any of them
  back with one click.** Notable means the things you would actually miss — a
  deleted page, section or section group, a picture, recording, PDF, drawing or
  file you removed, or a long stretch of writing. Ordinary typing and rubbing
  things out with the eraser are not on the list; that is what undo is for.
- **Anything still on that list keeps its files.** A video you deleted is not
  cleared off your disk while it can still be put back — only once it has
  dropped off the end of the ten.
- **You can say what other people should call this computer.** There is one box
  in the sharing window for it. Until you fill it in your computer goes by
  something plain like "Windows computer", and a computer that has never been
  named shows up as "another computer" — never as a string of letters and
  numbers.

### Fixed — pictures and drawings always keep their second copy in the notebook's folder

- **Openote keeps every picture and drawing twice: once in its working file,
  and once as an ordinary file in the notebook's own folder.** The second copy
  is the one that travels — it is what another computer reads, and what ends up
  in a backup or in a copy of the folder. Until now Openote only wrote it for
  notebooks you had already shared, so a picture added to a notebook you had
  not shared yet had no travelling copy, and could come up blank later on. It
  is written for every notebook now, whatever you go on to do with it.
- **Openote checks the copies really are there, and really are right.** When a
  notebook opens, Openote reads back every picture and drawing in the folder
  and compares it with what it should be. Anything missing is written again,
  and anything that does not match is replaced. It happens quietly in the
  background and you can carry on working while it does.
- **Notebooks you already have are filled in the first time you open them**,
  from what is already inside the notebook. Nothing you have written is
  touched.

### Changed — Openote's download is about half the size

- **Openote's download is about half the size it was.** Openote used to carry
  a video player around inside it, and everybody paid for that in download and
  disk space whether or not they ever played a video. It is now fetched
  separately — once, the first time you play one — and that takes about 48 MB
  off the download.
- **Your videos stay on your computer either way.** A video you have added is
  saved inside your notebook exactly as before, and nothing about it changes.
  If the player has not been fetched yet, the card on the page says so and
  there is one button to get it. Opening the video in your usual player, or
  saving a copy of it, works with no download at all.
- **If you are updating from an older Openote, you do not need to download
  anything** — the player that came with your existing copy keeps working.

### Changed — sharing a notebook now leaves its working file on your computer

- **Sharing a notebook through Drive, OneDrive, Dropbox, iCloud or Syncthing
  used to put Openote's own working file in the shared folder too.** Your
  notes were never the problem: the working file is a database Openote writes
  to constantly, and a sync app copying it while Openote is in the middle of
  writing can damage it. From now on only your notes go into the folder, and
  the working file stays on this computer — nothing you can see changes, and
  every device still gets everything.
- **If one of your notebooks already has its working file in a shared folder,
  Openote leaves it exactly where it is and offers to move it.** It will not
  move or delete anything in your cloud folder on its own. Open the sync
  window for that notebook and there is one button, in plain words, that does
  it: the file is copied out, checked, and only then removed from the folder.
  Your notes stay in the folder and keep syncing.
- **Openote now finds a shared notebook on your second computer even though
  there is no working file beside it**, and joining one this way gives that
  computer its own working file, as joining always has.
- **Setting up sharing checks every copied file, rather than just its size.**
  A copy that was interrupted halfway can be exactly the right size, and the
  old check called that finished.

### Fixed — a notebook made by a newer Openote can be read, and cannot be damaged

- **Openote used to read changes it did not understand as though it did.** If
  a newer version of Openote wrote something into a notebook's history that
  this version has never heard of, this version would carry on regardless —
  and anything typed here afterwards could quietly undo it. Openote now
  notices, shows you the notebook without changing it, and says so in one
  sentence: update Openote to edit it again. Notebooks written by this version
  or any older one are completely unaffected.
- **Section groups are now written down by the name the file format actually
  uses.** Openote had been recording them under an internal name, so a section
  group arriving from another one of your computers turned into a page. Both
  names are understood when reading, for ever, so notebooks written by older
  versions are read correctly.

### Fixed — Openote says so when a save did not make it into the notebook's history

- **Openote could save your notes and then fail to add the change to this
  notebook's history without saying a word.** The notes were safe on this
  computer, but the history is the copy your other devices, your backups and
  your shared folders read from — so those quietly fell behind while the
  status bar still said "Saved". It now tells you, in plain words, and keeps
  trying every time you save.

### Fixed — syncing that has stopped between your computers starts again by itself

- **If another one of your computers made a page and deleted it again before
  Openote next synced, syncing could stop on this one for good** — with no
  message and nothing to press, so the only sign was that your notes quietly
  went out of date. It now takes that in its stride, and a copy of Openote
  that is already stuck picks itself up the next time it syncs.

### Fixed — a big notebook stays usable while it catches up with another computer

- **Picking up changes made on another one of your computers could freeze
  Openote for about a second at a time**, on notebooks with a long history.
  It now reads those changes in small pieces, so the window keeps drawing and
  you can keep typing while it catches up. You get exactly the same notes at
  the end of it either way.

### Fixed — importing the same OneNote file twice no longer doubles up your handwriting

- **Importing a OneNote file you had already imported saved a second copy of
  every pen stroke in it.** The handwriting was the same handwriting, but
  Openote kept the lot again — on a section with a lot of ink that is
  megabytes of disk space for nothing, every time. It now recognises
  handwriting it already has and keeps one copy. Anything you have written
  yourself is untouched, and pages look exactly as they did.

### Fixed — a page that comes back after a permanent delete comes back empty, not old

- **Deleting a section for good left Openote still holding the pages that were
  inside it.** You could not see them in the notebook, but the summary
  screens — the tags list, the flashcard deck, the planner — were reading from
  that leftover copy. If a page from that section ever turned up again under
  the same name, from another one of your computers or from a restore, it
  would have shown you the deleted version of itself instead of what it
  actually contains. The same thing happened by itself, with nothing pressed,
  when a page's 30 days in the recycle bin ran out. Pages you did not delete
  are untouched either way.

### Fixed — deleting a page for good takes its version history with it

- **Deleting a page or a section permanently used to leave its saved
  Version history sitting on disk for ever** — up to 30 copies of the page,
  which on a big imported notebook is megabytes apiece. It goes with the
  page now, and anything an older version of Openote left behind is cleared
  up the next time you open the notebook. Pages in the recycle bin are not
  touched: they keep every version until you empty it.

### Added — get the space back from videos you no longer use

- **Notebook ▸ Sync ▸ "Where the files are" now has "Check for videos you no
  longer use…".** It tells you how many there are and how much space they are
  taking, and one button deletes them. Until now a video you copied in stayed
  on disk for ever, even after you deleted the block that played it — a term of
  lectures you had finished with was simply gone from your notes and still
  gone from your disk space.
- **It is careful to the point of being stubborn, and that is deliberate.** A
  video is left alone if it is still on a page, still in a page you deleted (it
  can come back for 30 days), named by an earlier version of a page, saved into
  a template, still undoable, still on the clipboard, or in use on another one
  of your computers. Videos added in the last month are left alone too. If any
  part of the notebook cannot be read at that moment, it removes nothing and
  says so rather than guessing.
- **Nothing happens on its own.** Openote tidies some things quietly in the
  background, but never deletes anything without being asked — the cost of
  being wrong is your notes, and the cost of asking is one click.

### Added — videos come with you when you export to Markdown

- **Exporting a page to Markdown now carries the videos and recordings you
  copied in.** They land in the `assets` folder beside the `.md`, under the
  name *you* gave them rather than the long internal one, and the export links
  to them — so opening the `.md` anywhere else gives you a link that plays.
  Before this the video was not just left out, there was no sign in the export
  that there had ever been one.
- Two recordings you happened to call the same thing stay two files. A video
  whose file is not on this computer yet leaves a link and your writing intact
  rather than failing the export.

### Added — double-click a notebook and it opens

- **Your `.onote` files open when you double-click them.** Windows and Linux
  now know Openote is what a notebook is for: the icon is right, the Type
  column says "Openote notebook", and double-clicking one opens *that*
  notebook. It used to open the app showing whichever notebook you had last —
  which is why the association was left unclaimed until now.
- **One Openote, not two.** Double-clicking a second notebook while Openote is
  open switches the one you already have to it and brings it to the front,
  rather than starting a second copy. Two copies would have been sharing one
  set of files: whichever saved last would have won, and notebooks made in one
  window would have disappeared when the other saved.
- **From a terminal, if that is your thing:** `openote path/to/notebook.onote`.
  Relative paths, folder names with spaces, all of it.
- **It tells you when it can't.** A shortcut pointing at a notebook you have
  since moved, or a file that only looks like a notebook, gets a sentence
  saying so — and Openote still starts, on the notebook you were last using.
  A file from outside your Openote folder is copied in, and it says that too,
  because from then on your changes are saved to the copy.

### Added — lists work the way lists work everywhere

- **Enter continues a list.** Type `- milk`, press Enter, and the next
  bullet is already there — with the marker you used, the indent you were
  at, and the next number if it is a numbered list. Enter on an empty item
  leaves the list; on an empty *nested* item it steps out one level, so a
  run of Enters walks back out of a deep outline instead of trapping you.
- **Tab nests, Shift+Tab un-nests.** Tab used to leave the text box
  entirely, which made outlining impossible.
- **Backspace at the start of an item unwraps it** — outdenting first if
  it is nested — instead of eating the marker one character at a time.
- **Numbered lists count themselves.** They never renumbered before, so
  the toolbar's "1. " on five lines rendered "1. 1. 1. 1. 1." and deleting
  an item left a hole. A list you deliberately start at 7 still counts
  7, 8, 9.
- **Shift+Enter** adds a second line inside the same bullet.
- `* item` and `+ item` are bullets too. They used to grey out like a real
  marker while you typed and come back as plain text when you clicked
  away — the editor promising something the page would not honour. No
  setting was added for which character to use: Enter simply continues
  with whichever one that line already has.

### Fixed — the text stops moving when you click into it

- Bulleted lines jumped sideways on entering edit mode, and the error grew
  with every nesting level. The editor now hangs the bullet in the same
  gutter the page uses, so the words start in exactly the same place
  whether you are reading or writing — at any depth, for bullets, numbers
  and tasks alike.

### Fixed — bold, italic and the rest

- **Ctrl+B with nothing selected now formats the word your cursor is in**
  instead of writing a bare `****` into the note that no amount of typing
  removes — and one Backspace could leave `***` behind. It can no longer
  leave unbalanced markers at all.
- **The toolbar lights up** for whatever is switched on where your cursor
  is, which is how you can tell without the symbols being visible.
- **Turning formatting off works from inside the word**, not only when you
  select it exactly. Before, a cursor inside bold text plus Ctrl+B quietly
  nested a second pair and everything typed afterwards came out un-bold.
- **`***bold italic***` renders as both.** It came out bold with a stray
  asterisk beside it — the imported-formatting bug, and reachable without
  importing anything by pressing Ctrl+B then Ctrl+I.
- Literal asterisks and underscores are safe: `2 * 3 * 4` and
  `snake_case_name` keep their characters instead of silently becoming
  emphasis and losing them.
- Ctrl+B no longer injects Markdown into a **code block**, the heading
  button no longer crashes at the very start of a block, the bullet button
  no longer destroys a checkbox or eats indentation, and "blank out" now
  actually saves (it wrote the change and threw it away one frame later).

### Added — the code block types like a code editor

- **Pairs close themselves.** Typing `(`, `[`, `{`, `"`, `'` or a backtick
  adds the partner with the cursor between them; typing the closing one
  when it is already there steps over it instead of doubling it; Backspace
  between an empty pair removes both.
- **Enter between `{` and `}`** opens a blank indented line and moves the
  `}` down to its own line, at the right indent. Enter anywhere else keeps
  the current line's indentation, and adds a level after a line that opens
  a block (or ends in `:` in Python).
- **Tab indents, Shift+Tab outdents** — including every line of a
  multi-line selection.
- **The language names itself.** A cell works out whether it is Python,
  C++, SQL, JSON and so on from what you have typed, and never overrides a
  language you picked yourself. It needs to be reasonably sure, so a
  two-line snippet is left alone rather than guessed at.
- **C++ and C# are supported**, with the tokens that actually distinguish
  them (`#include`, `std::`, `nullptr`; `using System;`, `namespace`,
  `[Attributes]`).
- **The language list is grouped and ordered sensibly** — the two that
  actually run on your device come first with a Run badge, then the C
  family, then everything else — so what will execute is visible before
  you type anything.
- Fixed on the way through: indentation added with Tab could not be
  undone, picking a language could not be undone, and a block imported as
  ```javascript showed a Run button that then said "No runner for node".

### Fixed — blank lines survive the OneNote import

- An empty paragraph produced no line at all, so the gaps you left between
  thoughts were gone before the page was built. Existing imports are not
  rewritten; re-import to get the spacing back.

### Fixed
- **CI is green again on all four app platforms — and the cause was not what it looked like.** The red Analyze step was one real `unused_field` warning left behind by the PDF rework, invisible on the dev machine because a local check filtered analyzer output down to nothing and reported success regardless. The field is gone. Two genuine hardenings came out of chasing it: the Flutter SDK is now **pinned** in CI and release (an SDK release could previously change what every branch built with, with no commit to bisect), and six tests that asserted on wall-clock time — "200 calls in under 50 ms", "first progress inside the first quarter of the import" — now count the work instead (page reads, directory listings, measurement round-trips), because `flutter test` runs files in parallel and a stopwatch bar measures the machine's spare CPU, not the code.
- **The intermittent Windows CI failure is fixed.** The git suites spawn real git — `init`, `config`, `clone`, `commit`, `push`, each its own process — and were running under the test framework's default 30-second timeout, which was never a decision about them. They take 20 seconds on an idle sixteen-core machine, so on a two-core CI runner one test crossing the line was a coin flip. They now carry a three-minute hang guard.
- **CI is ~3.5 minutes faster and a third cheaper.** Measured per-step: the duplicate `ubuntu-latest` job (same image as the pinned 24.04) is gone, analyze and icon-font subsetting run once instead of on every OS, and the test reporter is the one built for Actions.

### Fixed — a test that was measuring the hardware

- The probe guarding double-click-to-rename compared **wall-clock** times
  while the test only advanced Flutter's fake clock, so it was really
  asserting that the machine could rebuild the sidebar between two clicks
  in under 300 ms. It passed where that was true and failed where it was
  not, which left the suite red on `master`. The window now reads a clock
  the test can drive; the shipped behaviour is unchanged, because a
  double-click is a real-time gesture and has to stay one.

### Fixed — sidebar clicks act INSTANTLY

- **The real half-second, found**: every click on a page, section or
  group in the sidebar was silently waiting out the double-click window
  before acting — the double-click-to-rename binding forced every single
  click to pause and check whether a second was coming. That one wait was
  the whole "consistent half second", which is why keyboard navigation
  was always instant and page size never mattered. Clicks now act the
  moment you release; double-click still renames (the first click
  selects, like a file explorer), and the group open/close animation
  actually plays instead of arriving late.
- Separately, images no longer load from the database before the page's
  first frame: the page appears immediately, pictures fill in a beat
  later, and revisited pages cost no reads at all (a memory cache keyed
  by content).

### Added — the sidebar moves

- Opening and closing groups animates — section groups and a page's
  subpages slide open and closed in the app's one motion register,
  instead of blinking in and out.

### Fixed — editing keys behave (follow-up to 0.7.1)

- While editing any box, arrow keys moved the box SELECTION instead of
  the caret, and Enter could be eaten instead of making a new line — the
  canvas's keyboard traversal was shadowing the editor. It now stands
  down entirely whenever an editor holds focus.
- **Typing on a selected box just works**: select a text or code box and
  start typing — it opens at the end and your letters land. Tool letters
  still switch tools when nothing typeable is selected.

### Added — more of the motion list

- Toolbar tab switches crossfade; the PDF viewer grows out of its
  thumbnail card.

### Changed — cleaner status bar

- The bottom bar shows saved state and sync only. The engine/build chip
  ("Rust · a3f9c210") is debug-builds-only now.

## [0.7.1] — 2026-08-10

### Fixed — the Linux push finally says what it needs

- Joining a shared notebook on a second computer pulled fine and then
  failed to push with git's own "could not read Username … terminal
  prompts disabled". The cause is by design — your GitHub access key
  lives per-computer and is never written into the notebook — but the
  message now says the useful thing: open Sync, press Connect GitHub on
  THIS computer, sync again.

### Changed — code blocks behave like text blocks

- **Click position is respected**: tapping into a code block opens the
  editor with the caret where you clicked, not at the end.
- **Text is selectable without editing**: drag over a code block to
  highlight, Ctrl+C to copy — no editor needed, same as a text box.

### Fixed — copy/paste carries every block whole

- Pasting rebuilt blocks field-by-field and silently dropped rotation and
  — worse — the identity of block types this build doesn't know, so a
  block written by a newer Openote lost its type when pasted. The clone
  now goes through the same open-format round-trip everything else uses.

### Added — consistency polish

- **One settings page** (the gear in the top bar): theme, spell check,
  pen behaviour, the doors to Sync / AI access / keyboard shortcuts, and
  About with a check-for-updates button.
- **Every dialog opens with the same quick fade-and-settle** — the
  "little bounce" — instead of each popup arriving differently.

## [0.7.0] — 2026-08-10

### Added — AI access (MCP)

- **Openote is an MCP server now** (View tab ▸ the robot icon): AI tools
  you already use — Claude, editors, agents — can list notebooks, read
  pages (as the open page-JSON format or as Markdown), search, create
  pages, append content, and **make flashcards** that land straight in the
  study deck. Everything an AI writes is an ordinary edit: it syncs, and
  Ctrl+Z undoes it.
- **Off by default, and locked down when on**: the server binds
  127.0.0.1 only, every request needs the bearer token the dialog shows
  you (paste-ready client config included), browser cross-origin requests
  are rejected, and closing Openote takes the API down with it.
- The design is a spec, not an implementation detail:
  docs/specs/14-external-api-mcp.md — its core rule ("the file format IS
  the API") means new block types are readable and writable through the
  API the day they exist, with no API change. The test suite proves it by
  round-tripping a board block through an API layer that contains no
  board code.

### Added — code that runs (SQL and JavaScript cells)

- **A code block set to `sql` or `js` gets a Run button** (and Ctrl+Enter
  while editing). Output lands under the source — text, an error, or rows
  as a real table — and **persists with the note**: it syncs, it undoes,
  and the page reads like a finished notebook without re-running anything.
- **Every table block on the page is queryable.** SQL sees them as tables
  (named from the first header cell, and as `t1…tn`; the wrong-name error
  lists what exists); JS sees them as `tables.<name>` arrays. Drop a CSV,
  write `SELECT unit, AVG(mark) FROM marks GROUP BY unit`, run.
- **Sandboxed by construction**: runs only ever start from your click; the
  engines have no file, network or process access to escape to (the JS
  engine is built without the fetch bridge its wrapper enables by
  default); five-second timeout, 64 KB output cap, 200-row table cap. The
  honest residual is documented in code: a stuck native call keeps its
  thread until it finishes — the UI always gets its answer on time.
- Other languages (including ones installed on your system) are planned —
  behind real per-platform OS sandboxing, not a trust prompt. See
  docs/planning/v0.14-local-code.md.

### Added — a task board on the page

- **A trello-style board block** (Insert ▸ Board, or right-click the canvas ▸
  *Task board here*): columns with counts, cards you add and edit in place,
  drag cards between and within columns, rename columns by clicking their
  title, add columns as you need them (an empty one can be removed). It is a
  block, on purpose — stretched wide on an empty page it *is* a board page,
  and a small one sits beside lecture notes, which a whole-page board could
  never do. Boards ride the normal undo/save/sync path and export to
  Markdown as headings with lists.

### Added — Excel files become tables

- **Drop an .xlsx onto the page** (or right-click ▸ *Table from a file*) and
  the first worksheet becomes the same editable table a .csv does — shared
  and inline strings, numbers, booleans, and a formula cell's *cached value*,
  which is the numbers you saw rather than a formula engine. Dates arrive as
  Excel's serial numbers for now. Same 500×64 cap as CSV, reported when it
  cuts.

### Fixed — the PDF popup behaves

- **The viewer is a window over the page, not a takeover** — about 760px
  wide, with the notebook visible behind it.
- **A mouse-wheel tick scrolls a real distance** (it moved a fifth of a
  screen), and a **draggable page-numbered scroll thumb** on the right edge
  covers a hundred-page deck in one gesture.

### Added — a PDF is a PDF now

- **Importing a PDF stores the file once and renders pages on demand.** The
  old importer rasterised every page into stored images — a 60-slide deck
  became hundreds of megabytes standing in for a 4 MB file. Now the notebook
  keeps the PDF itself (it syncs like any picture does) and slides on the
  page are drawn from it as they come into view, pixel-identical to before.
  Imports finish in seconds instead of minutes, and annotating slides works
  exactly as it did.
- **Right-click any slide ▸ "Open the PDF…"** for the popup viewer, where
  the text is real: drag to select, Ctrl+C to copy — the "highlight and copy
  text from within it" ask, answered where the text actually lives.
- **Import "As a card"** (the arrow next to PDF slides, or just drop a .pdf
  onto the page): one small thumbnail card instead of a spread of slides —
  click it to open the whole document in the viewer. "Embed my lectures into
  the page … and not have to flick between the notebook and browser."

### Added — the pen knows what it is for

- **Bringing the pen near the page switches to inking.** On its approach the
  tool flips from Select to Pen — no toolbar trip. Picking another tool
  while the pen hovers sticks until the pen leaves and returns, and a toggle
  in the Draw tab turns the whole behaviour off.
- **The pen's tail erases, and so does its barrel button** held while
  drawing. (What a pen button reports is up to the OS and driver — the
  barrel signal is the one that reliably reaches applications, so it maps to
  the eraser, which is what it means nearly everywhere.)

### Added — one-click AI connections, no jargon

- **Connect Claude Code / Connect Gemini CLI buttons** in the AI-access
  dialog: Openote writes the connection into the tool's own settings file
  itself — no terminal, no copying config. It merges (never overwrites),
  refuses files it can't parse, backs up before its first write, and keeps
  the connection current if the port ever moves. MCP, ports and tokens now
  live behind an "Other AI tools (advanced)" fold.
- The dialog is honest about ChatGPT and the Gemini app: their connectors
  run on the vendor's servers, which can't see apps on your computer — so
  no button pretends otherwise.

### Added — the app updates itself

- **Openote checks for a newer release at launch** (silently — offline
  costs you nothing) and shows a small Update button when one exists.
  Pressing it saves everything, downloads the installer behind a progress
  bar, closes, installs silently, and **reopens as the new version by
  itself** (Windows; other platforms get the download page). This is the
  last version you install by hand.

### Added — full keyboard control, first two phases

- **Ctrl+/ shows every shortcut in the app**, rendered from one keyboard
  map in code — the documentation can't drift from reality, and a test
  walks every row. The View tab has a button for the mouse-first path.
- **The canvas works one-handed**: Tab/Shift+Tab select boxes in reading
  order, arrows jump to the nearest box in that direction, Enter opens the
  box's editor, Esc climbs back out, Ctrl+arrows move the selected box a
  grid step (Shift for 1 px) with one undo entry per burst, like a drag.

### Added — a page scroll bar

- A vertical bar on the page's right edge whenever the page is taller than
  the window: drag it, click the track to jump. It claims the pointer
  properly, so no selection box appears behind it.

### Changed — typing a bracket over selected text wraps it, everywhere

- Selecting a word and typing `(`, `"`, `*` … wraps the selection instead
  of replacing it in every text surface — code blocks, table cells, board
  cards, flashcards, math, the page title — matching what the markdown
  editor already did.

### Fixed — OneNote import ate ¬ and friends

- OneNote stores a text run as single ANSI bytes whenever its characters
  fit the old Windows character set; the importer read those bytes as
  UTF-8, so a ¬ (and smart quotes, dashes, €) in exactly those runs became
  the � replacement character — while the same symbol survived elsewhere on
  the page. The importer now falls back to the proper Windows-1252 table,
  which maps every byte. Pages already imported keep their � until
  re-imported; fresh imports arrive intact.

## [0.6.2] — 2026-08-09

### Fixed — boxes under the mouse

- **Resize works along the whole edge of a box**, not only on the little
  grab pill. The strip changed the cursor all along the edge but accepted
  the drag only over the handle.
- **A selected box outranks its neighbours for the mouse.** Where a selected
  box ran under another, the neighbour swallowed the clicks — the end of the
  box could not be grabbed to resize, and its text could not be reached.
  The box you selected now lifts above everything while selected (visually
  too), and drops back into place on deselect.

### Fixed — page windows

- **Videos inside a page window have their shape back** — the poster card
  collapsed to its play icon because the window sized it by width alone, so
  the play button was unreachable. Play, open-externally and save-a-copy all
  work in place now.

### Fixed — CI was measuring the weather

- Two tests timed the runner instead of testing the code (a cache asserted
  by stopwatch, a file-watcher burst asserting an exact OS batching factor),
  and one assumed macOS never echoes a file event from just before a watcher
  starts. All three now assert the actual claim — decode counts, "fewer
  events than writes", one echo of grace on Darwin — and CI is green on all
  four platforms for the first time in two days.

## [0.6.1] — 2026-08-09

### Fixed — git sync on a fresh computer

- **"Create and push" on a machine that had never run git synced nothing,
  forever.** Creating the repository goes through the GitHub API and needs no
  git, so the repository appeared — and then every commit died on git's
  "Author identity unknown", because a fresh computer has no `user.name` or
  `user.email` configured. A developer's machine always does, which is why
  this survived every test on ours: the test harness even *set one up* as a
  workaround, hiding the product bug from the exact suite that should have
  caught it. Openote now supplies its own commit identity (`Openote
  <openote@localhost>`) through the environment on every git call — commits,
  and the merge commits a pull creates — so syncing never depends on the
  machine being configured. The tests run without the workaround now, which
  on CI (also unconfigured) makes the whole git suite the fresh-laptop case.
- `GitSync.init` no longer swallows a failed first commit — that green light
  is what made the empty repository the first visible symptom.

### Fixed — quiet failures get a face

- If the file picker itself fails to open (Insert ▸ Image / File / video),
  the error now appears as a message instead of a button that does nothing.

## [0.6.0] — 2026-08-09

Page windows, and a video dialog that works again.

### Added — page windows (live embeds)

- **A window onto another page** (right-click the canvas ▸ *Page window
  here…*, or Insert ▸ *Page window*): pick a page, drag out the part of it
  you want — on a real rendering of that page — and it appears on the current
  page as a live, read-only view. Edit the source page and the window shows
  the change; rename it and the window's badge follows (the reference is by
  id, not title). Text inside the window can be selected and copied; **links
  inside it follow** (wiki-links open their page, web links open the browser)
  and **videos and attachments play and open in place** — but nothing inside
  it can be *changed*: checkboxes don't tick, tags don't toggle, ink doesn't
  erase. Interaction is drawn on one line: anything that navigates or plays
  works, anything that writes cannot. The badge opens the source page.
- **It is a pointer, not a copy.** The block stores a page id and a
  rectangle — a few dozen bytes — and renders straight from the same decoded-
  page cache the rest of the app reads, so a window costs no storage and no
  duplicate state, and can never drift out of date.
- Windows inside windows render three levels deep; a circular chain (A shows
  B shows A) is detected and shown as a labelled chip instead of recursing.
  A window whose source page was deleted says so instead of erroring, and
  greys itself while the page is in the recycle bin. Backlinks count windows
  as references to the source page.
- Resizing a window keeps its region's proportions — the one handle zooms
  the view. Markdown export writes an attribution link in its place; PDF
  export draws the frame with a "window onto" caption.

### Fixed

- **The "Embed a video or link" dialog rendered as a full-screen grey box**
  on release builds — reported from Linux, but broken everywhere since it
  shipped in 0.5.0. Its button row used a layout widget (`Spacer`) that is
  only legal inside a `Flex`, and a dialog's action bar is not one; the
  failed build painted as the grey error box. The dialog now has a widget
  test that builds it, which is how this class of bug gets caught before a
  release instead of on someone's laptop.

## [0.5.0] — 2026-08-08

Sync through GitHub, and a notebook that is a fraction of the size it was.

### Added — handwriting stops being text

- **Ink is stored as compact binary instead of JSON.** Measured on a real
  imported notebook: 63.09 MB of stroke data becomes **3.22 MB** — 19.6× — and
  every point is preserved to within 1/16 of a pixel, which is a quarter of a
  device pixel at full zoom. New handwriting is binary from this release;
  **Sync ▸ Where the files are ▸ "Shrink handwriting"** converts what you
  already have, and reports the bytes it gave back.
- The notebook that prompted this went from 191 MB to about 35 MB.

### Added — smaller install

- **101 MB → 94 MB.** Chiefly a 1.6 MB icon font that Flutter's own desktop
  build never subsets (a quoting bug in the SDK, worked around here), 4 MB of
  web-only PDF machinery that desktop cannot execute, a compressed word list,
  and two font faces nothing asked for.

### Added — storage housekeeping

- **Reclaim space** compacts a notebook and hands back what it was holding —
  free database pages and the write-ahead log, which one notebook had grown
  larger than the database itself.
- **A duplicates finder** in the notebook manager: repeated imports of the same
  notebook are listed with their sizes so you can bin the extras. Nothing could
  have merged them automatically — each import correctly mints new ids.
- Stray `-wal`/`-shm` files whose database is gone are offered by the
  leftovers scan.

### Fixed — data safety

- **A restart could delete the other device's work.** If a second device's
  changes arrived while Openote was closed, the next thing you typed could undo
  them, on both machines. Openote now folds in what arrived before you can
  type, and refuses to record a change to a page it knows it has not caught up
  on. This applied to folder sync as well as git.

### Known — importing from OneNote

Some pages still lay out wrongly: a text box can be drawn over a diagram, two
boxes can land on top of each other, paragraphs can come in out of order, and
blank lines between bullets are dropped. The content itself is imported — it is
the positions that are wrong. Diagnosed in
`docs/planning/v0.11-size-and-speed-overhaul.md`.

### Fixed — passcodes now behave like passcodes

- **A lock survived closing Openote.** It did not before: the code that reloads
  which pages are protected was never called outside tests, so every restart
  began with the gate wide open — locked pages opened with no prompt, and their
  titles and contents came back in search. The passcode itself was never lost;
  nothing read it.
- **Locking a page now locks the sub-pages indented under it**, which is what
  was always promised. Sub-pages are not children in the file format — they sit
  in the same section with an indent level — and the lock was walking the
  wrong relationship.
- **Locked pages no longer leak through the tags panel, the planner agenda or
  the flashcard deck**, all of which read page text directly and none of which
  were checking.

### Added — sync a notebook with git

- **Notebook ▸ Sync ▸ "Sync with git"** keeps a notebook in a git repository
  and pushes it as you work — no button to remember. Give it a remote address
  (a GitHub repository, or anything git can push to) or leave it empty to keep
  a history on this computer only.
- **It syncs a minute after you stop typing**, and once more when you close
  Openote. Not on every keystroke: that would be a commit per sentence.
- **"Put this notebook on GitHub" creates the repository for you.** Name it,
  press the button, and Openote makes it on GitHub, points the notebook at it
  and pushes — without you visiting github.com to make one first.
- **It is private unless you say otherwise**, and the option says in as many
  words what making it public would mean.
- Connecting a GitHub account is one page, once. GitHub only issues tokens on
  its own site, so that step cannot move into the app; the button opens the
  right page with the right permission already ticked, and you paste the token
  back. Every notebook you own can be published after that without signing in
  again.
- **The token is never written into the notebook or its repository.** Not into
  `.git/config`, not into the remote address, and not onto a command line where
  other programs on your computer could read it. It is kept on this computer
  and sent only to GitHub.
- **If you have not connected an account, Openote never asks for your
  password.** It runs the git already on your computer and uses whatever
  sign-in you have set up for it. If a push needs credentials you have not
  configured it says so, rather than appearing to work.
- Your notes go into the repository; the working file Openote keeps on this
  computer does not. Two computers writing that file through a sync service is
  the one thing the notebook format is designed to avoid.
- **Notebooks ▸ Import ▸ "From a git address"** opens a notebook someone
  published — paste the address and it is copied here, opened, and kept in step
  from then on. Private repositories work when a GitHub account is connected.
  Joining one you already have opens it rather than making a second copy.
- Needs git installed. Without it the option explains that and offers nothing.

### Fixed — sync

- **A restart could delete the other device's work.** If a second device's
  changes arrived while Openote was closed, the next thing you typed could undo
  them — on both machines. The changes were read into memory at startup but
  never written to the notebook, so the save that followed treated them as
  deletions. Openote now folds in what arrived before you can type, and refuses
  to record any change to a page it knows it has not caught up on yet. This
  applies to folder sync as well as git.
- **Changes pulled from a git remote appear.** They were arriving on disk and
  being ignored until the next restart.
- **Pictures and videos reach the other machine.** A notebook kept only in git
  pushed its notes without their images — the text arrived and nothing else did.
- **Switching notebooks re-arms the change watcher.** It stayed pointed at
  whichever notebook was open when Openote launched, so every other notebook's
  incoming changes went unnoticed for the rest of the session.
- **A notebook pushed to git no longer reads as "on this computer only".** The
  sync dot, the status-bar chip and the storage figures all counted cloud
  folders and nothing else.
- **"Check now" is offered as soon as a notebook syncs**, rather than only once
  a second device has appeared — which was exactly backwards, since the moment
  you most want it is while setting the second machine up.

### Changed — the sync window

- **It fits on the screen.** Extra copies, git and the storage figures are now
  three headings that each answer their own question when closed, and open one
  at a time. It was eight sections stacked in one unbounded scroll.
- **It keeps up.** A sync finishing in the background now updates the window
  that is open, instead of showing whatever was true when you opened it.

### Fixed — PDF export

- **Code blocks appear at all.** They were dropped silently: the exporter read
  a key nothing in the app has ever written.
- **The exported page is the size the page says.** A paged A4 note now comes
  out as A4 rather than a canvas-width sheet with a guessed height, and Letter,
  Legal and landscape are their own shapes rather than everything being ISO.
- **The page's name and date are on the first sheet**, so a PDF you have shared
  or handed in says which note it is.
- Code keeps its monospaced face with the app's own font embedded, so symbols
  and accents inside a code block survive the trip.
- **Pictures inside a text box are exported.** They were being deleted: the
  exporter stripped every in-flow picture on the assumption that pictures are
  always their own block, which stopped being true when they became something
  you could put in the middle of a paragraph. Flashcards written into your
  notes come out too, with both sides showing — on paper there is nothing to
  flip, and a question with the answer withheld is not something you can revise
  from.
- **Writing that is not Latin survives the export.** Greek, Cyrillic, Arabic,
  Hebrew, Thai and the Indic scripts now come out as themselves rather than
  blanks, using a font borrowed from your computer. Chinese, Japanese and
  Korean still will not on Windows or macOS — the system fonts for them are in
  a format the PDF writer cannot read, and bundling one would add 16 MB to the
  download. Linux is fine if you have Noto installed.
- **Maths exports as maths.** Equations are drawn exactly as the app draws
  them and embedded as pictures — not selectable, which is the trade, but an
  equation is not something anyone searches a PDF for. If one cannot be drawn
  it falls back to its written form (`a/b`) rather than taking the export down.
- **If a PDF export goes wrong, you still get a PDF.** Rather than failing, it
  falls back to a picture of the page — unsearchable and larger, but a document
  you can hand in.
- Page mode's paper sizes were themselves slightly wrong — they were worked out
  at the wrong scale, so an "A4" sheet was about 80% of A4 on screen as well as
  in the export. Both are right now.

### Added — pages, as well as the endless canvas

- **A page can be a sheet of paper instead of open canvas.** The button is in
  the View row: A4, A5, A3, Letter, Legal or Tabloid, portrait or landscape,
  and you can change it whenever you like. Canvas is still the default and
  every existing page opens exactly as it did.
- **In page mode you just write.** The page starts as one full-width column —
  a plain text/Markdown editor rather than a spread of boxes — and grows a new
  sheet when you reach the bottom of the last one. Everything else still works
  inside it: pictures, cards, maths, tables.
- **It is per page, not per notebook**, so one notebook can hold the lecture
  you scribble on and the essay you have to hand in.
- A new page keeps the shape of the one you made it from.
- **Not done yet**: printing and PDF export still lay a paged page out as one
  continuous sheet rather than breaking where the page breaks. Switching a page
  that already has boxes on it keeps them where they are rather than reflowing
  them into the column.

### Changed — templates

- **A template lands under what is already on the page** instead of on top of
  the title and your writing, keeps its own arrangement, and no longer rewrites
  the page's background or grid unless the page was empty.
- **"Revision sheet" is new** — two flashcards ready to fill in, a definitions
  column and a "still shaky on" list. "Lecture notes" marks its questions
  column, so writing a question there turns it into a card.

### Fixed — templates

- **Insert ▸ Template does something.** Every built-in template failed on a
  parse error the moment you picked one, and had done since they were added.
  The failure was completely silent.
- Applying a template no longer discards data belonging to blocks a newer
  Openote wrote.

### Fixed — pictures and new pages

- **In-flow pictures sit flush against the left edge**, and one as wide as its
  box stays on its line instead of dropping below it.
- **Making a new page no longer takes the current page's sub-pages.** It is
  created beside the page you are on — from a sub-page you get another
  sub-page — and immediately after that page rather than at the bottom of the
  section.
- **Ctrl+N** makes a new page, **Ctrl+Shift+N** a sub-page of the one you are
  on.

### Added

- **Flashcards in the same box as your writing.** Put `?[question](answer)` on
  its own line inside any text box and it becomes a real card, sitting in the
  flow of the notes around it. Insert ▸ Flashcard always makes one of these —
  into the box you are editing, or into a new box if you are not editing
  anything. Use the pencil on the card to change what it says. It counts
  towards your revision exactly like any other card.
- **A flashcard you can put straight on the page** — Insert ▸ Flashcard. Write
  the question and the answer, tap to turn it over. It joins the same deck as
  tagged lines, so it counts towards your revision and your exam plan without
  anything extra. Tagging lines still works exactly as before.
- **Dragging a picture past the edge of its box now widens the box** instead of
  stopping. (Note: the box does not shrink back on its own afterwards — use its
  right-hand resize handle.)
- **Hold Ctrl while dragging a box to flip it out of the grid** — or into it, if
  the grid is off — for that one drag. Everything else stays as it was. Not Alt:
  Alt-dragging a text box already means "move it instead of selecting text".

## [0.4.2] — 2026-08-08

### Added — videos you keep, and watch, in your notes

- **Copy a video or recording into the notebook and play it in the page.**
  Insert ▸ Video or link… now offers "Use a file on this computer…" beside the
  link box. The file is copied in and kept, so it plays whether or not you are
  online and whether or not the original is still where you left it.
  - It genuinely does use the disk: a term of lectures is however many
    gigabytes those lectures are. The copy shows its progress and can be
    cancelled, and Notebook ▸ Sync now breaks the total out on its own line so
    you can see what the videos are costing you.
  - Recordings are stored as files beside the notes file rather than inside
    it, which is what lets playback start immediately on a two-hour recording
    instead of loading the whole thing first. They travel with the notebook
    when you move or duplicate it.
  - **Linux needs one package**: `mpv-libs` on Fedora, `libmpv2` on Ubuntu and
    Debian. The `.deb` and `.rpm` ask for it automatically. If you installed
    from the `.tar.gz` and it is missing, the card says so and which package
    to install, and "Open in your usual player" still works.
  - Links are unchanged and still open in your browser — a Panopto or YouTube
    page is a web application, not a file anything here can decode.

### Added — the picture is there while you are typing

- **In-flow images now show as pictures in edit mode**, not as their reference.
  Clicking into a box used to replace every picture with a line of
  `![](sha256:…)`; now the picture stays put and the writing flows around it
  exactly as it does when you are not editing.
- **Drag the corner to resize a picture.** The box width is the maximum and you
  can go as small as you like from there; the aspect ratio is kept.

### Added — passcodes on pages, sections and section groups

- **Right-click any page, section or section group ▸ "Lock with a passcode…".**
  Locked pages will not open, and will not turn up in search, until the
  passcode is entered. Choose how long an unlock lasts: every time, ten
  minutes, an hour, or until Openote closes.
- **It is a lock on Openote's doors, not on the file**, and the dialog says so
  before you set one: anyone with your notebook file can still read the page.
  Real encryption is a separate piece of work (ADR-0008) — this is the part
  that stops someone reading over your shoulder or picking up your laptop.
- A forgotten passcode cannot be recovered, but the notes are not lost either:
  they are still in the file.

### Changed — which Linux distros the packages run on

- **The Linux builds now require glibc 2.39 or newer.** In practice: Ubuntu
  24.04+, Fedora 40+, Debian 13, Mint 22, openSUSE. **Debian 12 and Ubuntu
  22.04 cannot run 0.4.2** and should stay on 0.4.1.
  - The reason is video. Openote's player links libmpv, so the version present
    on the machine that BUILDS the release is the version every user needs —
    and the older build host we used produced binaries asking for a libmpv no
    current distro ships. Left alone, the packages would have installed
    perfectly and then failed to start. Moving the build forward fixes that and
    costs the two older distros.
  - Getting both back means building inside a Debian 12 container; it is
    recorded as the next step rather than rushed into this release.

### Known gaps

- Exporting a notebook to Markdown does not carry copied-in videos yet.
- Space used by videos whose block you deleted is not reclaimed automatically.

## [0.4.1] — 2026-08-07

### Changed — Linux gets a real installer

- **`.deb` and `.rpm` packages replace the AppImage.** The AppImage was one
  file you had to mark executable and launch from a terminal, every time —
  AppImages deliberately touch nothing, so there was never a menu entry or an
  icon. Now you double-click the package your distro uses, Openote installs
  like any other program and appears in your applications menu.
  - `openote-*-linux-amd64.deb` — Ubuntu, Debian, Mint
  - `openote-*-linux-x86_64.rpm` — Fedora, RHEL, openSUSE
  - The `.tar.gz` stays for everything else: extract anywhere and run
    `./openote`. No install and no root, so dropping the AppImage costs
    convenience on those distros, not access.
  - `.onote` files are described and iconed correctly in the file manager, but
    double-clicking one does **not** open it yet — Openote cannot be handed a
    file on startup, so claiming the association would launch the app showing
    a different notebook. Declared honestly rather than half-wired.

## [0.4.0] — 2026-08-07

### Fixed — the move bar behaves like a move bar

- **The bar is reachable directly.** It only appeared once you had hovered the
  box itself, so moving a box meant putting the cursor inside it and then coming
  back out to the bar. Hovering the strip now works on its own.
- **Dragging the bar no longer puts a caret in the box.** A box that was not
  being edited stays that way through a move — which is the whole reason the bar
  exists. The same bug meant dragging a **resize handle** on a text box opened
  the editor too; both are fixed by the same change.

### Added — pictures where you are typing, and links to your lectures

- **Insert ▸ Image puts the picture in the box you are working in**, in the flow
  of the writing, instead of dropping a separate picture over the page. Pasting
  and dragging already did this; the menu — the route most people reach for —
  was the only one that could not. Text, images, maths and tables can now all
  live in one box together.
- **Insert ▸ Video or link…** adds a card that opens a recording in your
  browser. A link, not a copy: a lecture video is hundreds of megabytes, and
  copying one into the notebook would bloat every synced device. Openote checks
  the link is one it can actually open before adding it.

### Fixed — your notebooks survive being opened by an older Openote

- **An older version no longer destroys content it does not recognise.** Openote
  is supposed to hand back anything from a newer release untouched; instead, a
  block type it had never seen came back permanently renamed to "unknown". The
  content survived, but nothing could ever identify it again — and one save from
  an older copy was enough. **This matters most if you already run 0.3.1**,
  which still has the bug: the fix only protects notebooks opened by builds that
  have it, so the sooner everything is on 0.4.0, the smaller the window.

### Documentation

- [ADR-0008](docs/adr/ADR-0008-page-protection.md) settles how password
  protection will work: encryption at rest, not a dialog in front of the page.
  A dialog would be bypassed by Openote's own search box, which reads every
  page's content directly.

## [0.3.1] — 2026-08-07 · the first release you can actually download

<!--
0.3.1, not 0.3.0. The v0.3.0 tag was cut against a commit whose pubspec still
read 0.2.0, so the release workflow's version guard failed before any platform
job ran, and the tag shipped nothing — the release published under it has zero
assets, and openote.org served it for two days. Reusing the number would make
one version string mean two different things: a release with no downloads and a
release with five installers. Cheaper to spend a patch number than to overload
one. See docs/RELEASING.md.
-->

### Fixed — the app no longer freezes while it works (2026-08-06)

Four reports, one thread. Full reasoning and every measurement in
[the v0.10 plan](docs/planning/v0.10-responsiveness-and-storage.md).

- **Importing a notebook no longer locks the app up.** The whole import — read,
  parse, write — moved to a second isolate. Measured on a 200-page notebook:
  the number of interaction steps that complete *during* an import went from
  **50 to 2349**, and the median wait from **12.8 ms to 0.1 ms**.
- **Launching no longer freezes for the first few seconds.** Showing a
  notebook's sync status was replaying its entire change log on the UI thread —
  **489 ms** for the log a 2000-page import leaves behind, and worse on a real
  notebook. Status reads now cost a directory listing (0.24 ms) and the replay
  happens in the background. The same bug was why the app froze the moment an
  import announced its result.
- **Progress starts moving immediately.** The import used to lay out every page
  before writing any of them, sending the layout request across the isolate
  boundary as one uninterruptible copy. It is now four pages at a time,
  immediately before those pages are written — and the import got *faster*
  (11.0 s where it had been 13.4 s on the same synthetic notebook).
- **Cancelling an import removes the half-built notebook.** It could keep it, in
  a workspace that had no other notebooks, because the teardown went through the
  recycle bin and that refuses to delete your last notebook.
- **Imported notebooks are named `Uni Notes`, not `Uni Notes.onepkg`.**
- **Two more causes of the same freeze, both Windows-shaped.** Laying out an
  imported page's text is the one job that cannot leave the app's thread, and
  a real lecture page often has *one* enormous text box — a single indivisible
  measurement costing **216 ms at 2000 lines, 613 ms at 5000**. That is now
  measured in small chunks (verified to produce identical layout to the bit).
  And every chunk is followed by a genuinely idle pause, because Windows
  dispatches an app's own queued work ahead of mouse and keyboard: a loop that
  never goes idle starves input entirely while frames keep flowing, which is
  why the popup could keep updating while clicks queued up until the import
  finished.
- A box the OneNote parser could not place now falls back to the top of the
  content area rather than being written under the page title.

### Changed — notebooks take about half the disk space (2026-08-06)

- **Every image was stored twice**: once in the `.onote` container and again in
  the `.onotebook` folder beside it, so that syncing could copy the folder. That
  second copy is now written only for notebooks that are actually in a sync
  folder or mirrored. Measured on a synthetic 40-page notebook with 20 images:
  **17.4 MB → 9.6 MB**, a 2.23× overhead down to 1.23×.
- Nothing is lost by the change: the container still holds every byte, so the
  moment a notebook starts syncing its images are copied out. The rule, visible
  on screen: **a hollow ring on a notebook's backup dot means one copy on disk.**

### Added

- **A backup dot per notebook** in the notebook manager and the navigator
  header — green for a sync folder, amber for a mirror, a hollow ring for
  this-computer-only — with the answer spelled out in words on hover.

### Fixed — the release build itself (2026-08-07)

The first tag for 0.3.1 built all three platforms and then failed to package
two of them. Both causes were in steps that had never run before: every prior
release run died at the version guard within twenty seconds, so the packaging
half of the workflow reached its first real execution here.

- **The macOS app could not be signed.** `Release.entitlements` carried an
  explanatory comment naming the `codesign` flags in full, and XML forbids `--`
  inside a comment — so the entire plist was unparseable and `codesign` failed
  with `AMFIUnserializeXML: syntax error near line 21`. Local macOS builds had
  been silently dropping their entitlements for the same reason. The file now
  parses, and `release_assets_test.dart` fails in milliseconds if the sequence
  ever comes back.
- **The Windows installer was rejected by its own version check.** `ISCC.exe`
  reports no version at all — the numeric fields *and* the `ProductVersion` /
  `FileVersion` strings are all zeroed — so the guard asserting Inno Setup 6.3+
  read `0.0` and refused the perfectly capable 6.x that had just been
  installed. It took two attempts to accept that: reading a different field
  produced a confident, wrong `0.0` and failed the release a second time.

  The check no longer gates anything. ISCC itself rejects
  `ArchitecturesAllowed=x64compatible` when it is too old, and that is the
  authoritative answer; the guard only ever existed to turn ISCC's terse
  `Unknown value` into a sentence naming the cause, so it now runs *after* the
  compile, on the failure path, where being wrong costs nothing. Locating the
  compiler also stopped recursively scanning both Program Files trees —
  4m24s, spent after the build had already finished, now about a second.

---

## [0.2.0 · 0.3.0] — 2026-08-04 / 2026-08-05 · the first public release and the student release

Two tags four days apart, one set of notes: the work was written up as a single
pass and splitting it after the fact would invent a boundary that was never
there. `v0.2.0` was the first public release; `v0.3.0` added the student
features (planner, events and reminders, the UI revamp, installers) — though
neither tag ever produced a downloadable build; see the note under 0.3.1.

### Changed — the interface, made one thing (2026-08-05)
- **The app looked like two apps.** Openote had a colour palette and it had
  hand-built panels, and nothing in between — so every stock Flutter control
  came out looking like a phone app sitting next to them. Every message
  Openote showed you was a full-window-width bar; every dialog button was a
  lozenge; the date picker was a mobile calendar. All of it now matches the
  rest of the app.
- **Text is bigger and more consistent.** Seventeen slightly-different text
  sizes (some a half-pixel apart) became five, and eleven icon sizes became
  three. Nothing new is on screen — it just lines up now, which is most of
  what "looking finished" is.
- **Grey text was too faint to read**, and failed the accessibility contrast
  standard the project holds itself to. Every caption, hint and subtitle is
  now readable — in dark mode too, where the naive fix would have made it
  worse.
- **Dark mode has depth.** Panels used to sit on the same black as the page,
  so they merged into one rectangle. The page is now the darkest surface and
  everything else sits above it.
- **One side panel at a time.** Study, Planner, Tags, Outline and Links could
  all be open at once — over 1,300px of panels, which left no room for your
  notes on a laptop screen.
- **The toolbar no longer opens as a wall of grey.** With nothing selected it
  shows three group icons instead of twenty disabled ones; the full set is
  there the moment you click into a text box.
- **The status bar stops cutting itself off** mid-sentence, and the
  breadcrumb no longer spends a whole row repeating what the navigator is
  already showing.
- **Your to-dos read as words in the Planner and Tags panels** — a task
  written as a bullet used to show up as "- Finish tutorial 4", dash and all.
- **Notes can't hide under the page title any more.** Imported pages with
  content up there are moved down when you open them.

### Fixed — the sync button going grey (2026-08-05)
- **A notebook you put in your own sync folder now says so** — and keeps
  saying so after you restart. Openote was working out "is this syncing?" by
  guessing: it checked whether the notebook sat inside one of about fifteen
  well-known paths (`~/Dropbox`, `~/OneDrive`, Google Drive's usual drive
  letters…). So a self-hosted Nextcloud anywhere else, a moved OneDrive, or
  any folder you picked yourself was reported as "not syncing" even though it
  was — and the chip's tooltip invited you to set up the sync you already had.
- **It also stops flickering on startup.** Cloud clients mount their folders a
  few seconds after login, so the check could run before the folder existed
  and get a wrong answer that then sat there for the whole session. Openote
  now remembers the folder *you chose* instead of re-deriving it, and
  re-checks in the background so a change reaches the screen on its own.
- The chip now names the folder — "Nextcloud", "OneDrive (work)" — instead of
  a generic label.

### Fixed — a font bug found while doing the above (2026-08-05)
- **Every button in the app was using the wrong font.** Openote bundles Inter
  so it looks the same on Windows, macOS and Linux — but button labels were
  quietly falling back to the system default, so they never quite matched the
  text beside them.

### Added — the Planner: dates, reminders and your timetable (2026-08-05)
- **Every date you have, in one place.** Exam dates, to-dos you have given a
  deadline, reminders and your university timetable all appear in one panel,
  bucketed into Overdue / Today / Tomorrow / This week / Later. Open it from
  the command bar, or read the next three rows from the navigator's Home pane
  without opening anything.
- **Exam dates stop hiding.** They were set from two different context menus
  and were then visible only inside the study panel, on whichever section you
  happened to be looking at — there was no way to ask *"what dates do I have
  at all"*. Every date can now be set, moved or cleared from the planner, and
  an exam still carries its revision plan: *"40 to learn · 3 a day covers it"*.
- **To-dos can have a deadline.** Right-click any tagged line's row in the
  planner, or use Add a date ▸ Due date. The date lives on the tag inside the
  note, so it **syncs** — in a shared notebook the group's deadline is one
  deadline — and it follows the line when you edit around it.
- **Reminders that tell you the truth.** Set a nudge for a time ("in an hour",
  "this evening", or pick one) and Openote pops it up while it is open. If it
  was closed when the time came, the reminder is waiting on next open under
  *"3 reminders while you were away"* rather than being lost. Every reminder
  can be snoozed. This is deliberate rather than a limitation we hid: Linux
  has no notification-scheduling API at all and Windows would need MSIX
  packaging, so **Openote owns the schedule** and behaves identically on all
  three platforms. A student who trusts a reminder that never arrives is worse
  off than one who never set it.
- **Subscribe to your real timetable.** Paste the `.ics` address from your
  university, Google Calendar, Outlook or Apple Calendar and your lectures
  appear beside your notes. It is a plain download of a text file — no
  sign-in, no account, no access to anything but the calendar you pasted — and
  it is **read-only in both directions**: Openote never writes to your
  calendar, and calendar rows offer no edit they could not honour. Weekly
  lectures expand; anything more exotic is shown once and labelled rather than
  guessed at. A failed refresh keeps the copy you already had instead of
  blanking your timetable on a train.
- **A month view**, off by default — the agenda is what you read daily, and
  the grid is one click away when "when in the month is that?" is the question.

### Added — OneNote tags now import (2026-08-05)
- **Your OneNote tags come across.** To Do, Important, Question, Remember,
  Definition, Idea, Critical and Contact arrive as real Openote tags on the
  lines they marked — so an imported notebook's questions and definitions feed
  the flashcard deck on day one instead of needing to be re-tagged by hand. A
  tag we don't recognise (a custom one, or a notebook in another language)
  arrives as a custom tag keeping its own name rather than being dropped.
- The import summary counts them: *"Imported 324 pages, 372 images, 64,616 ink
  strokes and 811 tags"*.
- **Imported to-dos arrive unticked.** OneNote's completion flag is not decoded
  yet — the two candidate properties contradict each other on the file we have,
  and a wrongly-ticked to-do is worse than an unticked one.

### Changed — navigator polish + storage honesty (2026-08-05)
- **Sections inside a group are indented, with a guide rail** down their left
  edge, so where a group starts and ends is unambiguous.
- **Section colours can be set.** Right-click a section — the colour swatches
  are right there. The chip has always been drawn but only the OneNote
  importer ever wrote it, so on a notebook you started yourself it was a
  control that looked interactive and wasn't.
- **Notebooks ▸ Repair** heals every page in one pass. The automatic repair
  only runs when a page is opened, so a notebook imported before the importer
  was fixed keeps its junk on every page you have not happened to visit.
- **The sync dialog says where your notebook actually is** — both paths, both
  sizes, and which of them your cloud can see. It also finds notebook files
  nothing points at, and can delete the ones inside your own workspace.

### Fixed — data safety (2026-08-05)
- **Emptying the recycle bin no longer strands a notebook's sync log.** Purge
  deleted the notes file and left the `.onotebook` behind — logs and every
  image they held — invisible to the app and permanent. Shared logs another
  device still uses are never touched.
- **Re-joining a notebook you had deleted restores it** instead of copying it
  again under a new identity, which is how a workspace ends up holding several
  copies of one notebook.
- **A text box no longer grows sideways when you click into it**, and lines
  no longer wrap that shouldn't. Two causes: auto-width was measured only for
  the block being edited, so a box kept its creation width until first edit
  and then snapped; and the three paths that render or measure a box each
  inherited a different Material letter-spacing (read 0.25, edit 0.5, the
  measurement 0), so letters visibly spread on entering edit and the box was
  measured narrower than the field it had to hold.

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
