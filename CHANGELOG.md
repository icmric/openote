# Changelog

All notable changes to Openote. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [SemVer](https://semver.org/) with the caveat that **the file format has its own versioning** (File Format Spec §2) and format compatibility is the promise that matters most here.

## [Unreleased]

### Added — bring your notes over from OneNote without exporting anything

- **Sign in to Microsoft, pick a notebook, and it arrives.** No exporting, no
  files, no leaving the app. On a Mac or on Linux this is not merely the easier
  way, it is the **only** way: OneNote for Mac cannot export a notebook at all,
  and there is no OneNote for Linux.
- **Your notebook fills in while you watch.** Each section is written as it
  arrives, so you can open and read the parts already in while the rest is
  still coming, and keep typing the whole time. It says how far through it is.
- **Handwriting comes too.** So do equations, pictures, tables, lists, your
  to-do ticks, and **attachments** — which the file import has never managed.
- **Your notebook's own links work.** A contents page that pointed at other
  pages still points at them, now inside Openote. A link to something you did
  not import still opens OneNote, exactly as before.
- **Openote learns nothing about you.** It asks to read your notebooks and
  nothing else — no name, no email, no address book, no files, no calendar —
  and it cannot change anything in OneNote even if it wanted to. There is no
  Openote server, so your notes go from Microsoft to your own machine and
  nowhere else.
- **You do not have to sign in at all.** The exported-file route is still there
  on the same screen, described side by side, because not wanting to sign in to
  a Microsoft account is a perfectly good reason not to.

  One honest limit: **subpages arrive as ordinary pages.** Microsoft does not
  send how pages were nested, so there is nothing to read. If that matters to
  you, the exported-file route still keeps them.

### Fixed

- **Handwriting is no longer lost** when bringing a notebook over the internet.
- **Equations arrive as equations**, not as one letter per line.
- **Blank lines between paragraphs survive.** They were being dropped, so
  paragraphs ran together however many returns you had typed.
- **Bold and italic survive.** OneNote does not use the tags anyone would
  expect, so all of it was being quietly discarded.
- **Tables fit where they were.** They were coming in far too wide and
  overlapping whatever sat beside them, with every column the same width
  however much was in it.
- **Pictures you had moved stay where you put them** instead of jumping back
  into the middle of a paragraph.
- **A big notebook imports in about two minutes** rather than the ten or more
  it used to take, and when Microsoft asks Openote to slow down it says so and
  waits, instead of going quiet or giving up.
- **An import that goes wrong keeps the pages it already brought you.** If
  something failed halfway, Openote used to delete the whole notebook — every
  page you had just watched arrive. Now it stops, keeps them, and tells you how
  many are in.
- **If Microsoft will not let Openote read for several minutes together, it
  says so and stops** rather than sitting there apparently working. One run
  spent forty minutes to bring in a single page.
- **One stalled connection no longer stops the whole import.** A request that
  never came back used to hold its place for ever; six of those and a notebook
  stopped halfway with nothing on screen to say why.
- **Pictures are no longer lost when Microsoft asks Openote to slow down.**
  Bringing a five-year notebook over, four pictures went missing and nothing
  else did: a "come back shortly" on a picture was being read as "this picture
  does not exist". It waits and asks again now.
- **The wait before the first page now says what it is doing.** Finding out
  what is in a big notebook takes half a minute or so before anything can
  appear, and the card sat on "Signing in to OneNote…" for all of it. It now
  tells you how many sections and pages it found, and **Stop works during it**
  instead of waiting until the first section had already been brought over.

## [0.9.0] — 2026-09-03

### Added — Openote speaks six more languages, and picks one without asking (2026-09-03)

- **German, Spanish, French, Italian, Portuguese and Simplified Chinese**, all
  complete. Nothing to configure: Openote reads the language list your computer
  already has and comes up in the first one it can speak, so somebody whose
  machine is set to Chinese sees Chinese on the very first run, welcome flow
  included. If it guesses wrong, or you'd rather read the app in something
  else, Settings ▸ Appearance ▸ Language changes it there and then, no restart.
- **Chinese, Japanese and Korean text now has fonts to fall back on.** The
  fallback list was Latin and maths families only, so a machine without a CJK
  default drew empty boxes.
- Adding the *seventh* language still needs no Dart at all — one `.arb` file
  and a codegen run. [CONTRIBUTING §5](CONTRIBUTING.md#ways-to-help-right-now)
  is the whole procedure.

### Fixed — an unfamiliar language fell back to German, not English (2026-09-03)

- **A computer set to a language Openote does not speak got German**, because
  Flutter's default resolution falls back to the first supported locale and
  the locale list is built from the `.arb` files in alphabetical order. It
  falls back to English now.
- **The language your computer prefers is read as a list, not a single
  answer.** `localeResolutionCallback` hands over one locale at a time, so a
  machine set to Chinese-then-English could resolve on the wrong end of its own
  preference order. It uses `localeListResolutionCallback` now.

### Fixed — turning sync off did not wait for the work already running (2026-09-03)

- **`setAutoSync(false)` returned before the watcher had actually stopped.**
  The stop was started and its result thrown away, so for a moment afterwards
  a notebook you had just told Openote to stop watching could still be written
  to — which on Windows also means an open handle on a folder you may be about
  to move, rename or delete. It now waits, and everything that turns the
  watcher off waits with it.
- **And stopping the watcher was only half of it.** Noticing another device's
  change starts a catch-up, and that catch-up is the thing that actually
  writes — it folds the other device's edits in and records how far it got,
  both inside the folder. Stopping the watcher stopped it noticing anything
  new; a catch-up already under way carried on regardless, and nothing in the
  app could wait for it. So "everything has finished" was answered wrongly on
  the two occasions that ask it precisely because they are about to touch that
  folder: moving a notebook, and deleting one for good. Both wait properly
  now.
- Both showed up as one CI run failing on Windows while the same commit passed
  everywhere else. The flake was the bug reporting itself.

### Fixed — Openote refused to start (2026-09-04)

- **A notebook Openote could not read stopped the whole app from opening**, on
  a screen with nothing on it but an error. Reported from a real build: it
  never got as far as a window. Three separate things had to be wrong for that,
  and all three are fixed.
- **Tidying the recycle bin is no longer allowed to stop the launch.** Openote
  clears out anything past thirty days when it starts. That is housekeeping —
  skipping it costs nothing, because the next launch does it — and it was
  taking the entire app down with it.
- **One unreadable notebook no longer means no Openote.** If the notebook you
  had open last will not open — a drive that is not plugged in, a file another
  program is holding, a disk that is full — Openote now opens one that works
  and tells you what happened to the other, instead of refusing to start. Even
  if *every* notebook is unreadable, the window opens and says why.
- **And it says it in words.** "SqliteException(1546): disk I/O error" is not
  something anybody can act on. It now names the notebook, gives the handful of
  things that actually cause this on a desktop, and says the thing that matters
  most: nothing has been lost. Your writing is in the notebook folder, not in
  that file, and the file can be rebuilt from it.
- **Opening a notebook no longer asks SQLite for a setting it could not
  apply.** Every open ran `PRAGMA auto_vacuum=INCREMENTAL`, which reads like a
  preference but takes a write transaction — and on a notebook that already has
  content the setting cannot change anyway, so every notebook you own paid for
  it and none of them got anything. It now runs only when a notebook is being
  created, which is the only time it does anything.

### Added — a pre-release checklist a human can actually run (2026-09-03)

- **[docs/pre-release-checklist.md](docs/pre-release-checklist.md)**: the
  manual pass, action and expected result, run on the packaged build before
  every release. The automated suite is nearly 2,800 tests, but all of them run
  headless in one process with a fake clock and a fake file picker — it cannot
  see a stuttering frame, a real file dialog, an installer, a stylus, or the
  update path. About 35 minutes, deliberately short enough to run every time.


### Added — a screen reader can hear an equation (2026-09-02)

- **Equations announce themselves.** Maths is drawn as glyph boxes, which say
  nothing at all, so an equation was silence in the middle of a page whose
  prose reads perfectly well. It now carries what you typed. That is not
  spoken maths — "x squared over two" is a separate, planned job — but it
  beats a blank.
- The rest of the app came out of the same check better than expected, and
  the review has been corrected: every icon-only button in Openote already
  carries a tooltip, and a tooltip is what a screen reader reads out, so the
  toolbars and the navigator name themselves. The words on a page reach a
  screen reader too. What is still missing is a way to jump straight to the
  navigator, the toolbar or the page instead of walking through everything.


### Changed — typing no longer rebuilds the toolbars (2026-09-02)

- **The command bar and the object row are no longer rebuilt for a keystroke
  that cannot change them.** Every character marks the page dirty — it has to,
  because that is what makes a box grow as you type — and the whole window was
  being rebuilt from the top for it. Measured on a page of forty blocks in a
  ninety-page notebook: the toolbars were 47 ms of a 63 ms frame, and neither
  can look any different because a character was typed in the middle of a
  paragraph. That frame is now 19 ms. The parts that really do change while
  you type — the word count, the study and planner badges — keep themselves up
  to date on their own.

### Added — the toolbars and the navigator can be translated (2026-09-02)

- **The chrome that is on screen all session now reads its words from the
  translation file**, joining the welcome flow. Around 200 messages, and six
  of them are things that were being assembled by hand in a way no other
  language would accept: "1 card" against "5 cards", reminders waiting, days
  left in the recycle bin, and the word count, badge numbers and zoom
  percentage, which are now grouped and shaped the way each language does it.
  This was the groundwork; the six languages above are what it enabled.


### Added — the welcome flow teaches the app, and other languages have somewhere to go (2026-09-02)

- **The first thing you see now says what Openote IS.** The welcome dialog
  offered three ways to get notes *in* — sync, OneNote import, start fresh —
  and never mentioned the canvas. That is the discoverable half: both of
  those live in the notebook manager and in Settings. The canvas is not.
  Nothing on an empty page tells you that clicking anywhere and typing is the
  whole interaction, and someone arriving from OneNote who does not learn
  that in the first ten seconds concludes the page is broken. It is now three
  short steps, each led by a drawing rather than a paragraph: the canvas
  (animated, because the thing it teaches is an order of events — pointer,
  click, caret, words, and only then a box), maths and ink, and where your
  notes live. Every starting point the old dialog had is kept, as the last
  step.
- **The welcome flow can be reopened.** It ran once, ever, on a first run
  that had already been stamped by the time you decided you wanted it —
  skipping it was permanent, and being the second person to use the machine
  meant never seeing it. Settings ▸ Help now has a door back in.
- **Openote can be translated.** The foundation is in: the localisation
  delegates, an English `.arb` template that is now the source of truth for
  the welcome flow's words, and a generated strings class checked into the
  repository. Adding a language is a single `.arb` file and a codegen run —
  no code to change — which is exactly how the six languages above arrived a
  day later. The rest of the migration is tracked in
  [v0.24 — the road to 1.0](docs/planning/v0.24-road-to-1.0.md).

### Fixed — layout and consistency in the dialogs (2026-09-02)

- **The welcome flow's starting-point cards overflowed by 25 pixels**, on the
  one step someone switching from OneNote actually has to read. The existing
  smoke test never caught it because it only ever opened the first step.
- **Three confirmation dialogs in Sync appeared without the fade-and-scale
  every other dialog in the app uses**, because they opened through Flutter's
  own `showDialog` rather than Openote's.


### Fixed — a picture Openote couldn't find could be self-healed, and wasn't (2026-09-01)

- **A blob file missing from `blobs/` — but still sitting safely in the
  notebook's own container — is now recovered automatically, the same way
  a corrupted one already was.** The proof step re-hashes every picture and
  drawing and repairs a wrong-bytes file from the container, but a file
  that was simply ABSENT skipped that same chance and went straight to
  "missing" — correct only in the instant right after the notebook's own
  backfill had just run, and permanently stale for a file deleted (an
  antivirus quarantine, a cloud client eviction, a folder tidied by hand)
  any time after. It now gets the identical repair a corrupted file
  already got.
- **"The pictures are still fine on this computer" was wrong for exactly
  the case it was said about.** By the time a hash reaches that report,
  the notebook's own container has already been asked for good bytes and
  could not supply them either — so the picture is not fine on this
  computer, it is the one place its bytes are actually gone. The message
  now says so.

### Changed — a consistency pass over the chrome (2026-09-01)

- **Insert's ribbon compacts instead of scrolling once its thirteen
  buttons run past the window** — the same fold the trailing cluster
  below already got. Home and Draw still scroll: both mix dividers, split
  buttons and a live text field with no single "this control folds into a
  menu item" shape the way Insert's uniform row of commands does.
- **The command bar's trailing icons (Study, Planner, tags, outline, links,
  find, export, settings) now compact instead of scrolling.** A narrow
  window used to hide whichever of them didn't fit off the edge of a
  horizontal scrollbar, reachable only by scrolling first and invisible
  otherwise. They now fold into one "More" menu the moment they stop
  fitting — the same controls, doing the same thing, just reachable one tap
  further in — and unfold again the moment there's room. Built as a
  reusable `CompactingToolbar` component rather than a one-off fix.
- **Every on/off setting now shows its state as a highlighted segment, not
  a toggle switch** — Spell check and "pen near the page switches to
  inking" in Settings, AI access in the AI access dialog, and the Draw
  row's own pen-proximity control, which now matches every other tool
  button on that row (Bold, Italic, the drawing tools) instead of being the
  one `Switch` among them.
- **"Click to…", "Tap to…" and "Insert" trimmed from labels and tooltips**
  where the surrounding UI already says as much: a flashcard's "Tap to
  reveal" is now "Reveal", a tappable status dot's tooltip no longer opens
  with "Click to", and the page-window dialog is titled "Page window", not
  "Insert a page window".

### Added — plug a value into an equation and see the result (2026-09-01)

- **`⋯ ▸ Evaluate at a value…`** puts a small block beside the equation: the
  equation, a box for whatever the variable is, and the answer, updated as
  you type. It works the same whether the equation is in a box of its own
  or in the middle of a sentence — the same rule Draw the graph already
  follows — and the value you type can be an expression too (`2+3`, `pi`),
  not just a bare number. It is a graph's sibling for one point rather than
  a curve: its own copy of the equation, tied to the original the same way,
  so editing `y = 3x+10` into `y = 2x+6` updates the answer as you type.

### Fixed — a graph that had opinions of its own (2026-09-01)

- **The window now refits itself when the equation changes**, not just when
  the graph is first drawn. Rewriting `y = 3x+10` as `y = \sin x` used to
  leave the old window in place, often showing nothing recognisable at all.
  Panning or zooming by hand still holds — the refit only happens on an
  actual edit.
- **Scrolling or pinching inside a graph no longer also scrolls or zooms the
  page underneath it.** Trackpad pan and pinch are a separate stream of
  events from an ordinary mouse wheel, and the page was never told to leave
  them alone.
- **A small reset button appears in a graph's corner once it has been moved**,
  and goes away again once the window is back to its default — a visible way
  back that does not require knowing double-click is the shortcut.
- **Hovering the curve shows the point's value.** The number shown is
  snapped to the same spacing as the gridlines, one digit finer, so it never
  shows a value with no meaningful precision behind it.
- **A trackpad pinch zoomed a little and slid the window a lot.** Two
  separate bugs, both in the same gesture: the graph's own pan/zoom
  handling was applying a pinch's noisy, incidental pan literally, on top
  of the zoom; and a leftover pan-gesture recognizer meant for Alt+drag was
  quietly running a SECOND, competing pan from the same physical gesture,
  which is also what made a touchscreen pinch feel jagged. Pinching now
  only zooms, about wherever the fingers are.

### Fixed — five from real use, each root-caused rather than patched over (2026-09-01)

- **A graph's border only ever lit up in one of the two directions the link
  is supposed to work.** Clicking the equation correctly tinted it, but the
  graph's own border re-checked "is the GRAPH itself selected" on top of
  the already-correct answer `graphLinkHighlight` gave it — so clicking the
  equation could never light up its graph, only the reverse. One redundant
  condition, removed.
- **Backspace at the front of a plain exponent or subscript did nothing
  visible.** It silently stepped the caret into the base and stopped,
  leaving the box exactly as it was. It now takes the whole `^{}` away and
  hands the exponent's own characters back as ordinary text, landing the
  caret exactly on the boundary it was already sitting on. Chasing this
  down turned up a second, older bug in the same neighbourhood: backspacing
  off the front of `\lim`'s only limit (or `\sum`'s lower one) quietly
  turned the sign itself into a plain, editable symbol — `\sum_{n}^{}`
  became `\sum n` — which the existing test for exactly that never caught,
  because `\sum n` still *contains* the substring `\sum`. Both are fixed
  together.
- **`sin-1` now becomes sin⁻¹**, the calculator-keypad shorthand, the moment
  the `1` lands — the same idea as `sin(` going upright without a backslash,
  one unambiguous character earlier. The undo is staged on purpose: one
  Backspace gives back `\sin` followed by a plain `-1` (identical to typing
  `sin(-1)` by hand), and only a second Backspace, now landing on `\sin`
  itself, hands back the three raw letters.
- **Typing `(` right before existing content auto-inserted an empty pair
  and stranded whatever followed it on the far side of the `)` — never
  wrapping it, just sitting in front of it unasked.** A `(` typed anywhere
  but the true end of a row is now one character, exactly as typed; typing
  it at the end still opens a real, auto-sized grower, so `\sin(` and
  `(x+1)` work exactly as they always have.
- **Ctrl+←/→ inside an equation did nothing at all.** A blanket "everything
  else with Ctrl belongs to the app" rule was swallowing the chord before
  it ever reached the equation's own arrow handling. It now jumps a whole
  run — every digit of a number, every letter of a name, a run of operator
  characters, or one entire structure (a fraction, a root, a grower) in a
  single hop, never entered. Ctrl+Shift+←/→ highlights the same run.

### Added — how much have I written?

- **A word count on the page's own row.** Every essay has a limit on it, and
  the only way to find out used to be exporting the page and pasting it
  somewhere else. One click gives characters, characters without spaces, and
  reading time.
- It counts what you WROTE, the way a marker would: `**bold**` is one word, a
  link is the words you can see and not its address, an equation is one word
  wherever it sits, and the dash in front of a bullet is not a word at all.

### Changed — after using it

- **Insert is one row of thirteen again**, each with its word, in the order it
  has always been. Text box, Flashcard and Template are back. The right-click
  menu keeps its three short columns — that shape suits a menu — and the two
  still read from one list, so neither can quietly gain something the other
  has not got.
- **Graph is a button on the equation's row**, not a line inside the `...`
  fold. A command that makes something is not an advanced setting.
- **Clicking at the end of a line that ends in an equation now puts you in
  it.** The arrow keys always did; the click did not, so clicking the obvious
  place did nothing at all. Words after the equation still take a caret, as
  they must.
- **An empty equation you are inside looks like one.** The caret was drawn
  BESIDE the empty box rather than in it, so starting an equation looked
  almost exactly like not starting one. It is one box with the caret inside,
  the same as a half-filled fraction.
- **Hovering over a box no longer fills its background.** It hid the gridline
  and the box beside it just as you were lining them up, and it was a shape
  the page would never print.
- **Del deletes the page or section you clicked on** in the list down the
  side, and so does Backspace. It was right-click ▸ Delete or nothing. There
  is no "are you sure" — deleting a page keeps it for thirty days and the
  menu never asked either — but it now says what went and where to find it.
  Getting there made the whole list keyboard-navigable.
- **One Del deletes one thing.** With a box selected on the page and a section
  clicked in the list, pressing Del destroyed both.
- **Choosing a cloud folder to sync with shows that it is working.** For a
  large notebook this takes seconds, and a greyed-out button with nothing
  moving is indistinguishable from a frozen app. The button does not change
  size doing it.

### Added — graphs

- **Write an equation, then draw it.** With an equation open, `⋯ ▸ Draw the
  graph` puts a graph beside it. Move it wherever you like; it stays tied to
  the equation, so changing `y = 3x+10` to `y = 2x+6` redraws the curve as you
  type. Click either one and both light up in the same colour, so you can see
  at a glance which graph belongs to which equation — and only while one of
  them is picked out, never the rest of the time.
- It works the same whether the equation is in a box of its own or in the
  middle of a sentence.
- Drag the graph to move around it, scroll to zoom, double-click to fit the
  curve back in the window. It prints and exports as a real graph, not a
  picture of one.
- Curves are cut where they should be cut: `1/x` and `tan x` break at their
  asymptotes instead of drawing a line straight through, `√x` simply stops
  where it runs out of values, and one spike cannot flatten everything else.
- **`y = sin x` opens on a whole wave.** Ten each way is twenty degrees, which
  drew the most likely graph in the app as a straight diagonal line.
- **`2y = 6x + 4` is rearranged for you** rather than drawn as `y = 6x + 4`,
  which is a line with twice the gradient and no warning. Anything that
  cannot be rearranged says so instead of drawing something else.

### Added — the maths that was missing

- **Roots you can type.** `\rt` gives you a root with an empty index box,
  `\cbrt` a cube root, and `\2rt`, `\3rt`, `\7rt`… fill the number in for
  you. Emptying an index turns it back into an ordinary square root.
- **Functions that take two numbers**, with the shape already filled in:
  `\gcd` gives you `gcd(□,□)` with the cursor in the first box. Also `\lcm`,
  `\max`, `\min`, `\nCr` and `\nPr` — everything a school calculator has.
- **`mod` works.** Write `17 mod 5` the way a textbook does and you get 2.
- **`log₂ 8`** works out, and so does any other base.

### Changed — one row for what you are working on

- **Nothing moves you any more.** Starting an equation used to switch the
  whole top bar to a Maths tab you never asked for. There is now a row under
  the toolbar that belongs to whatever you are working on: the page's own
  controls when nothing is picked, the symbol palette while you write an
  equation. The tabs above it never change, and nothing on the page shifts by
  a pixel.
- **Insert is tidier**: ten things in three groups instead of thirteen in a
  row. Text box is gone (a click on the page already makes one), Flashcard is
  gone (the button on Home reads the line you are on), and Apply a template
  moved to the page's own menu, beside Save as template.
- **Right-click on the page** now offers the same ten things as Insert, in
  three short columns — about half the height it was. "Here" is gone from
  every line, because right-clicking already means here.
- **Shift+F10 or the Menu key** opens that menu from the keyboard, which
  nothing did before.

### Changed — answers

- **Right-click an answer** for its choices: decimal or fraction, drawn rather
  than named; how many figures (3, 4, 5, 6, 10 or as many as it needs); work
  it out again; copy; remove.
- **An angle answer wears a degree sign.** `sin⁻¹(0.5)` is `30°`.
- **Answers are ten significant figures**, like the calculator on your desk.
  `cos 45` was showing twelve, which is enough to leak the floating point.
- **Switching between degrees and radians works the page out again**, so an
  answer can never quietly disagree with the button above it.

### Fixed

- **An equation in the middle of a sentence could not be edited at all** in
  the built app. It worked while being developed and broke in the version
  people download, which is the worst way for anything to break.
- **`sin⁻¹(0.5) = 30°`, then `+10 =`, answered 10.52 instead of 40.** Carrying
  an answer into the next line is the ordinary next thing to do, and a degree
  sign was being read as "convert this" a second time. Pressing the degrees
  button and working something out gave no answer at all.
- **Typing in one equation could steal another one's graph** when the two
  briefly read the same, and nothing brought it back.
- **Copying an equation together with its graph** gave you a copy that
  followed the ORIGINAL: changing the new numbers moved nothing, and changing
  the old ones quietly rewrote the new graph as well. Cutting an equation and
  pasting it back unlinked its graph for good.
- **A graph of something very large, like `y = x¹³`, drew an empty box** —
  no curve, no message, and the graph was left off the printed page.
- **The mouse wheel over a graph scrolled the page out from under it** while
  it zoomed; a sideways flick on a trackpad zoomed it in.
- **Scrolling around a page counted as editing it** if there was a graph on
  it: a timestamp, a save and a backup for a change nobody made.
- **Pressing DEG or RAD threw away the number of figures you had chosen**, and
  left every other equation in the same sentence showing the old mode's
  answer.
- **An answer written `30°` or `1.27×10³⁰` lost its chosen number of figures**
  the next time you typed anything.
- **Asking for an angle as a fraction dropped the degree sign**, which made it
  a different number.
- **An equation ending in a space could not be reopened** — it came back as
  raw LaTeX, and typing a backslash into the LaTeX box broke it outright.
- **A root written inside another root's index came back as a different
  equation**, silently.
- **Tab could trap you in an empty box**, with no way out but the mouse.
- **Right-clicking the page and choosing Picture put it in the paragraph you
  were writing**, several inches from where you clicked. The menu also got
  back the "Table from a file (CSV, Excel)" it had lost.
- **Alt-drag now moves a graph**, like every other box.
- **Pressing DEG or RAD threw you out of the equation you were writing** — and
  in a sentence, took the equation with it.
- **Maths is one size everywhere.** An equation in a sentence was smaller than
  the same equation in a box.
- **An equation no longer jumps when you click into it.**
- **Ctrl+Z in a paragraph took back the whole visit**, both sentences and all,
  because one mistyped character in an equation was the same undo step as
  everything you had written since clicking in. It takes back one burst of
  typing now, exactly as it does in a maths box.
- **Right-clicking inside an equation in a sentence** opened the paragraph's
  cut/copy menu over the top of the answer's own.
- **The LaTeX view could quietly throw work away.** Typing something by hand,
  going back to the buttons, writing more, then reopening the LaTeX view
  showed the old text — and pressing "Back to the buttons" rebuilt the
  equation from it.
- **"Back to the buttons" did nothing at all**, with no message, for anything
  the buttons cannot draw. It says which bit now.
- **Drawing near the top of a page dragged every box on it downwards** the
  next time you opened that page — saved, synced, and out of reach of Ctrl+Z.
- **Ctrl+1 to tag a line threw the cursor to the end of the paragraph.**
- **Exports failed in silence.** A full disk or a read-only stick meant the
  menu closed and nothing happened; you believed the file was there.
- **A backup that had never once worked still said "Backed up."** The list
  now says which copies could not be reached, and "Run now" tells you what
  happened.
- **A change history that could not be read said "Nothing recorded"** — the
  one thing it must never say wrongly, including for a page you just deleted
  and came back to restore.
- **Importing a folder of Markdown froze the app** with nothing on screen.
- **Saving a copy of a recording** showed no progress for its whole gigabyte,
  and said nothing if it failed halfway; **saving a copy of an attachment**
  that had not synced yet did nothing at all.
- **Dropping something the app cannot take** (a folder) now says so.
- **Exporting a PDF threw away what you had selected**, and printing a page
  from the navigator left you sitting on that page.
- **Connect GitHub moved you on to "paste your token"** even when no browser
  had opened.
- Wording: "Background colour…" opened a window headed "Text colour"; the
  multiplication dot was called a dot product; a right-angle button inserted a
  perpendicular sign; the tips line taught three keystrokes that do nothing;
  "Materialize notebook to folder…"; "Version history…" opening "Recent
  changes"; "Type here" in the box you are already typing in; a raw error
  message on the very first screen; and the shortcut list promising Alt+=
  finishes an equation, which it does not.


### Fixed — sin 30 is a half

- **Sine, cosine and tangent were working in radians**, so `sin(30)` came
  back as −0.988. Angles are in degrees now, the way a school calculator
  does it — and if you want radians, put π in the angle: `sin(π/6)` is a
  half too. A degree sign works as well: `sin(30°)`.
- **`sin⁻¹` and its friends did not work at all** — they were being read as
  "one over sin". `sin⁻¹(0.5)` is 30 now, and the inverses give you degrees
  back because degrees go in.
- **The degree symbol was ignored**, so `30°` could not be worked out.
- `sin(180)` showed `1.22464679915e-16`. It shows `0`.
- **The answer's box is a soft grey panel** instead of an outline.

### Fixed — three wrong answers, and the answer you can click

- **`sin(x)²` was working out as `sin(x²)`.** Typing `sin(2)^2` gave you
  sin of 4. It gives you the square of sin 2, like every calculator and
  every textbook. (`sin x²` with no brackets still means sin of x squared,
  because that is what it means in school notation.)
- **The cube root of a negative number said `undefined`.** `(-8)^(1/3)` is
  -2 now, so curves like x^(1/3) work either side of zero.
- **Two symbols side by side were read as one made-up name.** Typing π then
  e gave `unknown "pie"`; it multiplies them. `2πr` now tells you `r` is
  the unknown instead of inventing `pir`.
- **Answers the app works out are boxed, and you can click them.** The box
  says this was calculated rather than typed, and shows you where to click.
  Clicking switches between a decimal and a fraction — and if you were
  working in fractions you get a fraction to start with. Whole numbers and
  untidy decimals do not offer a switch, because they have nothing to
  switch to.

### Changed — maths in a sentence is full size again, and the answer comes to you

- **Inline maths is no longer shrunk.** A fraction is the same size in a
  sentence as in a box of its own, and the line makes room for it.
- **It sits on the line properly.** Clicking into an equation inside a
  sentence used to nudge the maths up and the words down, so the equation
  looked like a superscript. Nothing moves now.
- **Type `=` then a space and the answer appears** — `2+3= ` becomes
  `2+3=5`, right where you are typing. The live answer that used to sit at
  the top of the window is gone; it works out only what you wrote since
  the last `=`, and if it can't be worked out you simply get a space.
- Symbol tooltips read `name (\x)` instead of `name — type \x`.

### Fixed — the calculator answers real maths, and equations show up everywhere

- **The live "= answer" works for fractions, powers and roots now.** It only
  ever answered flat sums like 1+2 — anything actually built with the editor
  was silently ignored. The answer button also used to type the literal
  characters `=$value`; it types the answer.
- **Maths shows in tables, on flashcards and in study review.** All three
  drew raw backslashes before — a formula revision table or a maths
  flashcard simply didn't work.
- **`$$…$$` display maths no longer falls apart when you click into the
  text**, and pressing the equation shortcut twice on a word now steps it up
  from inline to display maths.
- **A matrix can grow columns, not just rows**: press `&` inside it — the
  same key adds a column in a 3-vector, a 2×3 grid, an augmented matrix.
- **Typing `sin(` sets it upright like a textbook**, no backslash needed.
- **Pasting maths onto the page makes an equation**, and maths the editor
  can't read is left on your clipboard with a plain message instead of
  being silently rewritten into typeset backslashes.
- **Cut a block, paste it back — you get the block**, not older clipboard
  text its own copy had left behind.
- Two equations in one paragraph behave; undo works inside an equation and
  can no longer scramble a sentence from under one; arrowing around an
  equation no longer wipes your redo; a half-filled fraction saved and
  reopened shows its empty box instead of a bar over nothing.
- **An import-repair step could silently delete dollar signs between two
  equations in one block** (merging them, or eating the second one's
  markers) every time a page was opened. Fixed at the source; takes effect
  after the next app build.

### Changed — equations in a sentence are edited in the sentence

- **The little card is gone.** Click an equation inside your text (or press
  Alt+=) and you now type straight into it, right where it sits — same
  editor, same Maths tab, same calculator as an equation box. Backspace at
  its edge steps inside it, the arrow keys walk in and out, Escape finishes,
  and an equation you abandon empty disappears instead of leaving `$$`
  behind.
- **Typing no longer scatters.** The old card and the paragraph fought over
  the keyboard after every keystroke, so characters could land in your
  sentence in the wrong order. Editing in place ends the fight for good —
  there is nothing left to fight with.
- Both places now share literally the same editor code, so a fix in one is a
  fix in the other. The inline editor gained the live calculator in the
  bargain.

### Added — highlight maths with the mouse

- **Drag across an equation and it highlights.** Click puts the cursor where
  you clicked (it used to jump to the end, always). Shift+click extends.
  Double-click grabs the whole piece under the pointer — for a fraction, the
  fraction. Cut, copy and delete act on the highlight, as everywhere else.
- **You can see the highlight now.** It was drawn in a tint measured at
  1.34:1 contrast against the page — invisible in practice. It uses a proper
  selection colour, the equation no longer changes size while selected, and a
  selected fraction no longer shrinks.
- An equation being written inside a sentence can no longer overflow it: the
  box asks the paragraph to widen, and scrolls if it truly cannot.
- The calculator's "use answer" button typed the literal characters
  `=$value` instead of the answer. Fixed, with the test it never had.

### Added — write maths by seeing it, not by learning LaTeX

- **Equations are now built visually.** Press Alt+= and type `1/2`: the moment
  you hit space it *becomes* a fraction, right where you were typing. Insert a
  square root and you get a √ with a small dotted box under it, with your
  cursor already in the box. Tab hops to the next box. There is no longer a
  panel of backslashes with a preview underneath — you write the equation by
  looking at the equation.
- **A Maths tab appears in the toolbar while you write an equation**, and
  goes away when you finish — the same place OneNote puts it. A fixed row of
  shapes
  (fraction, powers, roots, Σ, ∫, lim, brackets, piecewise, matrix, choose,
  accents), then a drop-down of symbols per category — Greek, comparisons and
  arrows, sets and logic, stats, geometry, science, functions — and a search
  box that speaks plain English: type "square root", "not equal", "choose" or
  "theta" and press Enter.
- **Symbols by name as you type.** `sqrt`, `sum`, `theta`, `pi`, `sin` and the
  rest turn into their symbol when you press space, and `<=` `>=` `!=` `->`
  turn into ≤ ≥ ≠ → as you type them. Every button's tooltip tells you its
  keyboard route, so the palette teaches you the shortcuts.
- **Nothing you typed is ever eaten.** Backspace at the edge of a fraction
  takes it apart back into `1/2` rather than deleting the whole thing. That
  holds for every shape: the wrapper goes, what you wrote stays.
- **Maths in a sentence stays maths while you write.** Clicking a paragraph
  that has an equation in it used to show `$\frac{1}{2}$` where the fraction
  had been. Now the equation stays drawn, the arrow keys step over it in one
  press, and one click on it opens it for editing.
- **Function names go upright by themselves** — `sin(x)` sets the way your
  textbook does, without you knowing there is a rule.
- The LaTeX view is still there for anyone who wants it: one `LaTeX` button on
  the bar. It is also where an imported equation opens if it uses something
  the buttons cannot show yet, so nothing is ever silently reshaped.

### Fixed — equations that quietly stopped drawing, and an integral that lost its limits

- **Integral and sum limits sit on the sign again**, above and below, instead
  of sliding off to the right of the whole expression. And after you fill the
  two limits, Tab now takes you to where the rest of the equation goes — it
  used to do nothing, so what you typed next ended up as a tiny exponent.
- **Typing a percentage no longer erases the rest of your equation.** `20%`
  drew as `20`, and `30%+2` drew as `30`, with nothing at all to tell you the
  rest had gone. Same story for `{`, `}`, `$`, `#` and `&`, which turned the
  whole equation into a grey box of code. A set written `{1,2,3}` now shows
  its braces instead of silently losing them.
- **Words boxes take any words.** "50% off", "costs $5", "where {n} is odd" —
  all of these used to break the equation they were in. An empty words box is
  also visible now; before, pressing the button did nothing you could see.
- **Backspace never destroys what you wrote.** At the edge of a fraction, a
  root or a matrix it now steps *inside* so you can delete from there. One
  press used to flatten a filled grid to a run of loose numbers, and on an
  empty power it left behind something no renderer could draw.
- **`x < -3` stays an inequality** instead of turning into `x ← 3`.
- **A degree sign or a prime after a power no longer breaks the equation**, and
  `30°C` works.
- **Undo takes back what you just typed, not the whole equation.** Ctrl+Z after
  a typo used to delete the equation and its box.

### Fixed — starting an equation in a sentence no longer shows `$$`

- Press Alt+= in a paragraph and you get **the same empty box you already see
  inside a half-filled fraction**, right where the caret was. Before, two
  dollar signs appeared in the middle of your sentence.
- **Pasting maths into a paragraph no longer pastes it twice.**

### Added — highlight part of an equation, and a lot more symbols

- **You can highlight inside an equation now** — Shift with the arrow keys,
  Shift+Home/End, or Ctrl+A — and **cut or copy just that part** instead of the
  whole thing. Dragging across a fraction takes the whole fraction, because
  half of one is not an equation.
- **The whole Greek alphabet**, capitals included. Only eleven capitals have a
  LaTeX name, which is why the rest were missing; they are all there now.
- **The "nots"**: ≮ ≯ ≰ ≱ ≁ ≇ ≢ ∦ ⊈ ⊅ ⊉ ∄ ↛ ⇏ ⇎ — and about forty other
  symbols besides, from ∓ ∘ ⊗ ⊙ ⋯ ⋮ to ⊨ ⊢ ⊇ ∋ ℵ ↪ ↗ ∡.
- Every symbol is now reachable by **browsing** as well as searching. Forty-four
  of them could previously only be found if you already knew to search for it.

### Fixed — pasted maths turns into maths

- **Copying an equation now says it is an equation.** Pasted into a sentence it
  used to stay as plain LaTeX for ever — nothing could tell it was maths.
- **`\(…\)` and `\[…\]` are understood** — what ChatGPT and most LaTeX
  editors give you — as well as `$…$` and `$$…$$`.
- **Pasting maths into a paragraph turns it into an equation** rather than
  leaving backslashes in your sentence. Ordinary writing and file paths are
  left alone.
- An equation ending in a typed space no longer breaks and prints its own
  source.

### Fixed — equations in a sentence, a summation you can navigate, and a box that grows

- **Alt+= in a paragraph now makes an equation right there**, in the sentence,
  and opens it for editing. Before, it dropped a separate equation below your
  paragraph — there was no way to ask for an inline one unless you knew to
  type two dollar signs.
- **The summation sign can no longer be walked into, typed over, or deleted by
  accident.** Its own row was an ordinary box: typing in it threw the limits
  off the sign for good, and two backspaces deleted the ∑ with nothing to show
  it had gone. Up and down now simply swap the two limits.
- **The equation box grows with what you write**, and scrolls when it reaches
  its limit. It used to be pinned to its width, so anything longer was clipped
  off the edge — worst on a summation, whose limits sit above the sign and make
  it much wider than it looks.
- **`\infty` works.** So does every other symbol's proper name — the shortcuts
  were the only thing being listened for.

### Changed — the maths bar has a button per kind of thing

- **Shapes · ∑∫ · Operators · Compare · Greek · Sets · Functions · Subjects**,
  each with a drop-down arrow so it reads as a menu, and clicking a second one
  while another is open now opens it on the first click. The menus are quicker
  to appear, too.
- Absolute value, piecewise and matrix had no button at all and could only be
  found by searching. Set operations (∪ ∩ ∖) moved in with the rest of the set
  work, `sin⁻¹` sits beside `sin`, and the determinant has its matrix next to
  it.

### Fixed — two ways an equation could still lose your work

- **Ctrl+X no longer deletes the whole box.** Pressed while writing an
  equation it cut the block out from under you. Copy, cut and paste now belong
  to the equation while you are in it, and it travels as LaTeX so it pastes
  into Word, Overleaf or a message — and a `1/2` pasted from a message comes
  back as a fraction.
- **Clearing an equation in a sentence no longer eats the words after it.**
  Emptying it and typing again used to overwrite the next few characters of
  your paragraph.
- **Tapping an equation in a sentence no longer errors on a narrow window.**

### Changed

- **Alt+= with words selected turns them into maths where they are**, in the
  sentence, instead of cutting them out and dropping a separate equation
  below. **Alt+Shift+=** does the old thing — an equation on its own line.

### Fixed — you can type in an equation

- **A new equation takes the keyboard straight away.** Nothing you typed
  registered until you happened to click a button on the bar.
- **A space is a space.** There was no way to put one in at all.
- **Only `\commands` turn into symbols now.** Typing `lpha` then a space
  gives you α; typing `alpha` gives you the word alpha. Before, the editor
  converted any word it recognised — so writing "a in b", "sin x" or "cap" in
  your own sentence turned into symbols you never asked for. An unrecognised
  command just stays as the letters you typed.

### Changed — a bar button for each kind of thing

- The Maths tab now has a door per kind — **Shapes, Big, Operators, Compare,
  Greek, Sets, Functions, More** — instead of one "Symbols" button you had to
  guess your way into, plus five shapes on the bar itself and a search button.

### Changed — the maths buttons are a tidier bar now

- The Maths tab was too wide for a normal window, so the search box and some
  buttons were off the edge with no way to scroll to them. It is about half
  the width now: eight shapes you use daily stay on the bar, everything else
  is behind **More shapes** and **Symbols**.
- **One Symbols button** with the search inside it, instead of eight
  category menus — and the lists are proper grids rather than one symbol per
  row.
- **Searching works the way you'd expect.** Typing a symbol's name now finds
  that symbol rather than something else with a similar nickname, and longer
  phrases like "greater than or equal to" find it too.
- **Every shape can be typed as well as clicked** — `matrix`, `root`, `abs`,
  `choose`, `cases` and the rest, then Space.
- **Recently used symbols** sit at the top of the Symbols panel.
- **The answer is clickable**: `= 0.5` writes itself into your equation. It
  also stays in one place now instead of shoving the buttons sideways as you
  type.
- The whole toolbar scrolls and takes a mouse wheel, on every tab.

### Fixed

- **Prices in a sentence are no longer turned into an equation.** "coffee is
  $5 and lunch is $10 today" was being read as maths from the first `$` to the
  second, setting half the sentence in italics as an equation. Two dollar
  signs now only mean maths when what is between them looks like maths.


### Fixed — three ways the OneNote import flattened your maths pages

- **Text you set as subscript or superscript now comes across.** OneNote lets
  you make ordinary text small-and-low or small-and-high with the x₂ and x²
  buttons, without writing an equation — and the importer threw that away, so
  a set written `{a₁, a₂, … , aₘ}` arrived as `{a1, a2, … ,am}`. It now
  survives, along with every `Aᶜ`, `ℝ⁺`, `O(n²)` and `qᵢ` on the pages around
  it.
- **A table cell holding just a symbol is no longer imported empty.** A
  character you picked from OneNote's symbol palette — ℕ, ℤ, an arrow, a 0 —
  is marked inside the file as maths, and a cell holding nothing else was
  dropped on the floor, so whole columns of a table came in blank. Those
  cells import now, and a cell holding a real equation shows the equation
  instead of nothing.
- **Equations keep their shape.** A definition split over two lines with a big
  curly brace used to be mashed into a fraction — and so did matrices, roots,
  and sums and integrals, which also lost the limits above and below them.
  Every one of those now imports looking like it did in OneNote.
- Pages you have already imported are not rewritten; re-import to pick these
  up.

## [0.8.0] — 2026-08-17

### Fixed — opening, moving and copying notebooks all keep their promises now

- **Double-clicking a notebook now works even when Openote is closed.** Opening
  a notebook's folder — or the "Open this notebook" file inside it — used to
  say *"That file isn't an Openote notebook"* if Openote wasn't already
  running, about your own notebook. Now a double-click opens the same notebook
  whether the app was running or not, and double-clicking the notebook you
  already have open simply brings the window to the front.
- **Moving a notebook — or sharing it into a sync folder — can no longer lose
  it if the app is interrupted at the wrong moment.** Openote used to delete
  the old copy first and write down the new home second; if it was closed or
  the computer lost power in between, the notebook could vanish from the list —
  and in one case the surviving copy was even offered up as safe to delete. Now
  the new home is written down before anything old is removed, so an
  interruption costs at worst a leftover file, never the notebook.
- **Duplicating a notebook now keeps its pictures.** A duplicate used to come
  out with every pasted picture blank, because the picture files that live
  beside the notebook were not carried along. They travel with the copy now,
  and each file is checked on the way over.
- **Tidying up videos now always respects the recently-deleted list.** The
  clean-up sweep could run before Openote had read which removed videos you can
  still put back, and offer one of those for deletion. It reads that list first
  now — and if the list cannot be read, it says so and removes nothing.

### Fixed — a shared notebook's pictures can no longer be lost when one computer's copy goes bad

- **When one computer's copy of a picture turns out to be wrong, Openote now
  sets that copy aside and heals it instead of deleting it.** Deleting it was
  how it used to work, and in a shared notebook a delete travels — one bad copy
  on one computer could take the good copies on every other computer with it.
  Now the bad copy is simply not used until a good one arrives, from another
  computer or from the notebook itself, and the moment it is right again it is
  back in use. A copy Openote merely could not read — a file another program
  had open, say — is left alone entirely.
- **A picture that arrives while you are looking at the page is checked before
  it is shown**, and one unreadable picture shows its own placeholder instead
  of stopping the pictures around it from loading.
- **A paste that cannot be saved now says so instead of doing nothing.** If
  your disk is full or the notebook's folder cannot be written to, pasting or
  dropping a picture used to quietly leave you with nothing — or worse, with a
  picture on the page whose file was never saved. Now nothing is added to the
  page and Openote tells you plainly what went wrong, with the technical
  details behind the Advanced fold.

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

### Fixed — four more ways the OneNote import let you down

- **Imported pages no longer look cut off.** The importer had the whole
  page all along — it was being cut off when the page opened.
- **Erased ink stays erased.** Handwriting you had rubbed out in OneNote
  used to come back on import.
- **Titles land on the right pages.** Pages could come in wearing each
  other's titles, and one title could be duplicated into every page.
- **Paragraphs no longer come in twice**, with the second copy in the
  wrong place — a nested group was being counted as page-level content.
- As with the blank-lines fix, pages you have already imported are not
  rewritten; re-import to pick these up.

### Added — full keyboard control, phases 3 and 4

- **F6 (Shift+F6 backwards) moves between the areas of the app** — sidebar,
  toolbar, page, an open panel, a showing reminder — with a visible focus
  ring, and it works mid-sentence. Ctrl+/ still shows every shortcut.
- **The surfaces that were mouse-only now answer the keyboard**: arrows
  walk a board's cards and columns and Ctrl+arrows carry a card, Enter
  edits and Delete removes (undoably); the find bar's Enter finds the next
  match instead of doing nothing; the PDF reader's full key set is
  reachable without a click; and Escape behaves consistently everywhere,
  including dialogs where it was silently switched off.

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
