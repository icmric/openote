# The pre-release checklist

> Run this by hand on the packaged build before every release. Budget **about
> 35 minutes** for Pass 1. Passes 2 and 3 are conditional and usually add ten.

`flutter test` runs 2 700-odd tests, and they are worth having, but every one
of them runs in a headless test binding, in one process, on one machine, with
a fake clock and a fake file picker. That leaves a whole category of failure
they *cannot* see:

- anything the compositor decides — a frame that stutters, a widget that
  overflows at a real window size, a font that falls back to tofu;
- anything a second process does — the folder watcher, a sync client, another
  copy of Openote, an antivirus;
- anything the OS owns — file dialogs, printing, file associations, the
  stylus, the trackpad, the installer, the "unidentified developer" wall;
- anything that needs the network — the update check, the release notes;
- and whether the thing is actually *pleasant*, which no assertion has ever
  measured.

That is what this list is for. It is deliberately short enough to run every
time. If an item here starts failing often, that is a signal to write a real
test for it and delete the row.

## Before you start

1. **Build or install the artifact you are about to ship** — the installer or
   the archive, not `flutter run`. Half of Pass 3 only exists in a packaged
   build.
2. **Move your real workspace aside** so this is a genuine first run:
   rename `~/Documents/Openote` (Windows: `Documents\Openote`) to
   `Openote.bak`. Settings live in `workspace.json` inside it, so renaming the
   folder resets everything, and moving it back afterwards restores your notes
   exactly.
3. Have a **real-sized notebook** to hand for the two performance rows — a few
   dozen pages, some ink, some pictures. A three-page scratch notebook proves
   nothing about frame times.

Tick as you go. If a row fails, note it and keep going — the rest of the list
still tells you whether it is one bug or a bad build.

---

# Pass 1 — the core, every release

## A. It starts, and it is yours

| # | Action | Expected result |
|---|---|---|
| A1 | Launch the app on the renamed (empty) workspace | A window opens in a few seconds. The welcome flow appears, on its first step. |
| A2 | Walk the welcome flow to the end with **Next** | Three steps, each led by a drawing; the canvas step animates. Nothing overflows, no yellow-and-black stripes, the buttons stay on screen. |
| A3 | Pick **Start fresh** on the last step | A notebook exists, a page is open, and the page is empty. |
| A4 | Set your OS to a language Openote ships (de, es, fr, it, pt, zh), then relaunch on a fresh workspace | The app comes up **in that language**, without asking — menus, sidebar, status bar, welcome flow. Set the OS back afterwards. |
| A5 | Settings ▸ Appearance ▸ Language ▸ pick a different one | Every visible string changes immediately, no restart. Nothing is clipped or ellipsised mid-word in the toolbars. |
| A6 | Set Language back to **Same as my computer**, quit, relaunch | It follows the OS again, and the choice persisted across the restart. |
| A7 | Settings ▸ Help ▸ **Welcome tour** | The welcome flow reopens. |

## B. The canvas — the thing people came for

| # | Action | Expected result |
|---|---|---|
| B1 | Click on empty space on the page and type | A caret appears where you clicked, the words appear as you type, and a box grows around them. No lag between key and glyph. |
| B2 | Click elsewhere and type again | A second, independent box. The first is untouched. |
| B3 | Select a box, then drag it to another part of the page | It moves smoothly and stays where you drop it, and the align guides appear while you drag. |
| B4 | Drag the right edge of a box | It re-wraps as you drag; text does not jump or lose the caret. |
| B5 | Middle-drag, and two-finger scroll on a trackpad | Both pan the page in every direction, smoothly, without snapping back. A left-drag on empty page still marquees. |
| B6 | Ctrl+wheel | Zoom in and out around the pointer. The status-bar percentage tracks it. |
| B7 | Marquee-drag across two boxes with the mouse | Both highlight; move them together as one. |
| B8 | Ctrl+Z several times, then Ctrl+Y | Everything you just did undoes in order and redoes in order. |
| B9 | On the real-sized notebook: hold a key down in the middle of a paragraph | The text keeps up with the key repeat. No visible pause on the toolbars or the sidebar. |

## C. Text, and Markdown where you type it

| # | Action | Expected result |
|---|---|---|
| C1 | Type `# ` then a word | It becomes a heading in place. |
| C2 | Type `- ` then a word, Enter, another word | A bullet list that continues on Enter, and ends on a second Enter. |
| C3 | Type `- [ ] ` then a word | A checkbox you can tick, and ticking it survives a page switch. |
| C4 | Select a word, press Ctrl+B, then Ctrl+I | Bold, then bold-italic. The Home row's buttons show the state. |
| C5 | Paste a few paragraphs from a browser | The text arrives; formatting is either kept sensibly or dropped cleanly. It does not arrive as one unbroken line or as HTML source. |
| C6 | Right-click a word with spell check on | The OS spelling menu appears with suggestions. |

## D. Ink

| # | Action | Expected result |
|---|---|---|
| D1 | Press **P**, draw with the mouse | A stroke follows the pointer with no perceptible delay and no gaps. |
| D2 | Press **H**, draw across some text | A translucent highlight *behind* the text, not over it. |
| D3 | Press **E**, drag over a stroke | The stroke goes. Ctrl+Z brings it back. |
| D4 | Press **V**, lasso some ink, move it | The ink moves as a group and keeps its shape. |
| D5 | *With a stylus, if you have one:* write a line | Pressure varies the width; the app switches to inking on pen proximity if that setting is on; your palm does not draw. |

## E. Maths

| # | Action | Expected result |
|---|---|---|
| E1 | Insert ▸ Equation, type `1/2 + x^2` | It builds into real 2-D notation as you type — a stacked fraction, a raised exponent. |
| E2 | Type `sum_(n=1)^10 n` | A summation with both limits in place. |
| E3 | Arrow-key left and right through the finished equation | The caret walks into and out of the fraction and the exponent; it never disappears. |
| E4 | Graph an equation from the maths row, then pan and zoom the graph | The curve redraws at the new scale, and the *page* does not pan while you are inside the graph. |
| E5 | Evaluate the equation at a value (the more menu) | A number comes back, and it is right. |
| E6 | *If you have a screen reader:* focus the equation | It reads out what you typed rather than saying nothing. |

## F. Finding things again

| # | Action | Expected result |
|---|---|---|
| F1 | Make a second section and a third page | They appear in the sidebar immediately and in the right order. |
| F2 | Type a word from another page into the search box | The page is listed; Enter opens it at the right place. |
| F3 | Tag a block, then open the tags panel | The tag is listed with its block; clicking it jumps there. |
| F4 | Open the outline panel on a page with headings | The headings are listed in order; clicking one scrolls to it. |
| F5 | Link one page to another, then open the links panel on the target | The source page is listed as a backlink and opens on click. |
| F6 | Rename a page, then a section | Both rename in place, and the tab/title updates. |

## G. Bringing things in

| # | Action | Expected result |
|---|---|---|
| G1 | Insert ▸ Picture, pick a file | The real OS file dialog opens; the picture lands on the page at a sensible size. |
| G2 | Drag an image file from the desktop onto the page | Same result, no crash. |
| G3 | Insert ▸ Table | A table you can type in and tab between cells. |
| G4 | Export ▸ Markdown | A real `.md` file is written where you chose, and it opens in a text editor with your content in it. |
| G5 | Export ▸ PDF | A PDF is written and opens, with the page's content on it — text, ink and pictures. |

## H. Your notes survive

| # | Action | Expected result |
|---|---|---|
| H1 | Type something, then watch the status bar | It says saving, then settles on "Saved on this device" within a couple of seconds. |
| H2 | Quit the app normally and relaunch | Everything is there, on the page you were on. |
| H3 | Type something, then **kill the process** (Task Manager / `kill -9`) and relaunch | You lose at most the last few seconds. The notebook opens; nothing is corrupt; no error dialog. |
| H4 | Open the notebook folder in a file manager | It is `Name.onotebook`, with **Open this notebook** inside it, and the files have plausible names and sizes. |
| H5 | Delete a page, check the recycle bin, restore it | It comes back with its content, and the bin shows the days remaining. |
| H6 | Open page history and step back a version | You see an earlier state and can return to the current one. |

## I. Sync

Do this with two folders on the same machine — a second workspace is enough
to prove the machinery; a real cloud folder is Pass 3.

| # | Action | Expected result |
|---|---|---|
| I1 | Settings ▸ Sync, point a notebook at a synced folder | The sync dot goes green (or amber-then-green), and the folder fills with files. |
| I2 | Edit a page and wait | The dot shows the write and settles. The files on disk change timestamp. |
| I3 | Turn auto-sync **off**, then immediately move or rename the notebook folder | It moves. No "file in use" error, no ghost writes into the old path afterwards. |
| I4 | Turn auto-sync back on and change a file outside the app | Openote notices within a few seconds and shows the change. |

## J. The window itself

| # | Action | Expected result |
|---|---|---|
| J1 | Drag the window down to about 800 px wide | The toolbars **fold into a More menu** rather than scrolling off the edge. Everything is still reachable. |
| J2 | Widen it again | They unfold. |
| J3 | Settings ▸ Theme ▸ Dark | Everything is dark, including dialogs, panels and the maths. No white flash, no unreadable grey-on-grey. |
| J4 | Move the window to a second monitor with a different scale factor | Text stays crisp and the layout stays correct. |
| J5 | Tab through the window from the top | Focus moves visibly and in a sensible order, and never gets stuck somewhere invisible. |

## K. The update path

| # | Action | Expected result |
|---|---|---|
| K1 | Settings ▸ About ▸ **Check for updates** on the *previous* release | It finds the new version and offers it. |
| K2 | Read the notes in that dialog | Markdown is *rendered* — bold is bold, headings are headings. No stray `##` or `**`. The first screen is the overview bullets, not the download table. |
| K3 | Let it update | It downloads, installs, and relaunches on the new version. Settings and notebooks are intact. |

---

# Pass 2 — only if this release touched it

Skip the whole row if the release did not go near it.

| Area | Action | Expected result |
|---|---|---|
| OneNote import | Import a real `.one`/notebook export | Progress is honest and the window stays responsive throughout. Pages, sections and ink arrive; nothing is silently dropped. |
| Notebook lock | Protect a notebook, quit, reopen | The lock screen appears; the right password opens it, a wrong one does not; the files on disk are unreadable without it. |
| Study | Make flashcards from a page, run a session | Cards come from your own notes; the badge count matches; answers reveal and grade. |
| Planner | Add a reminder and an exam date | It shows on the month grid, the badge counts it, and the alert fires. |
| PDF | Insert a PDF as slides and as a printout | Pages render, scroll, and stay sharp when zoomed. |
| Code cells | Run a JavaScript cell | It executes, prints output, and a bad script errors instead of hanging the app. |
| Page windows / portals | Embed a region of another page | It renders live, is read-only, and click-through goes to the source. |
| Templates | Apply a template to a new page | The layout arrives and is editable. |
| AI access (MCP) | Turn it on and connect a client | It connects, and turning it off actually stops it. |
| Git sync | Join an existing repo | It clones, opens, and a subsequent edit pushes. |

---

# Pass 3 — per platform

Everything above should be run on **the platform you develop on**. These rows
are the ones that only exist on a real, packaged install, and they are why a
release still needs a human on each OS.

## Windows

| # | Action | Expected result |
|---|---|---|
| W1 | Run the `.exe` installer as a normal user | No administrator prompt. It installs for the current user. |
| W2 | "Windows protected your PC" ▸ More info ▸ Run anyway | It runs. (Expected until we sign — just confirm the escape hatch is there.) |
| W3 | Double-click **Open this notebook** in a notebook folder | It opens, in the copy of Openote already running if there is one — not a second window. |
| W4 | Put a notebook in a OneDrive folder and edit it | It syncs, and Openote does not fight the client over open handles. |

## macOS

| # | Action | Expected result |
|---|---|---|
| M1 | Open the `.dmg`, drag to Applications, launch | The "damaged and can't be opened" wall appears; `xattr -cr /Applications/openote.app` clears it and it launches. |
| M2 | Trackpad: two-finger scroll, pinch | The page pans and zooms the way every other Mac app does. |
| M3 | Cmd-based shortcuts | Cmd+Z, Cmd+C, Cmd+V, Cmd+S do what a Mac user expects — not Ctrl. |
| M4 | Menu bar and full-screen | The app has a sensible menu bar and behaves in full screen. |

## Linux

| # | Action | Expected result |
|---|---|---|
| L1 | Install the `.deb` or `.rpm` | Installs cleanly, appears in the applications menu with its icon. |
| L2 | Double-click a `.onotebook` folder from the file manager | It opens in Openote (works on some desktops only — note which). |
| L3 | `openote path/to/X.onotebook` from a terminal | Opens that notebook. |
| L4 | Check the status bar | It names the Rust core version. If it says the core is missing, the package is wrong. |
| L5 | Run under both X11 and Wayland if you can | Window decorations, cursor and ink all behave. |

---

## When something fails

- **Write down what you did, not what you concluded.** "Clicked the third
  page while the import was still running" is a bug report; "the sidebar is
  broken" is not.
- **Decide whether it blocks.** Data loss, a crash on launch, a broken update
  path and a broken installer block a release. Almost nothing else does — this
  project ships often, and a known rough edge in the notes beats a release
  that never happens.
- **Anything that fails twice in two releases should become a real test.**
  Add it to `app/test/`, then delete its row here.

## What this list still cannot tell you

Long-run behaviour. A memory leak over eight hours, a notebook that grows for
a month, a sync conflict that needs two people and bad timing. Those are found
by using the app, which is what [TESTING.md](../TESTING.md) tracks — the
rolling list of what has and has not been touched by a human. This file is the
floor; that one is the frontier.
