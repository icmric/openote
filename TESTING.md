# What needs testing, and what I need from you

> Working document · last updated 2026-10-21 · **v1.0.2 is not tagged yet.**
> This pass decides whether it can ship.
>
> Everything below is **built and covered by automated tests**, and as far as
> I know has not been tried by a human on a real machine. Tests prove a
> mechanism; they cannot tell you a gesture feels wrong, that a colour is hard
> to read, or that something is technically correct and still not what you
> meant. That is what this list is for. If you already tried something while
> it was being built, delete the row.
>
> Only things you can do yourself, on your own machine, are in here. Anything
> the test suite already settles has been left out on purpose. The most
> likely to break come first.
>
> Tick as you go and tell me what breaks — what you did, what happened, what
> you expected. Confirmed rows get deleted, so this file stays the honest
> queue rather than a museum.
>
> Not to be confused with [the pre-release checklist](docs/pre-release-checklist.md),
> which is the *fixed* pass — the same rows run on the packaged build before
> every release. This file is the frontier.
>
> **The v1.0.1 queue that used to live here has been cleared out**, as the
> v0.7 one was before it: v1.0.1 shipped over it, three weeks of using it
> found what it found, and I have no record of which rows you confirmed. It
> is in git (`git show c66a0d9:TESTING.md`) — tables, links, pen shapes,
> pictures, your own SSH key, code-block colours, the navigator, the
> right-click menu. If something from it is still outstanding, say so and I
> will put it back.

---

## 1. Your pen, and the lasso

Hardware no test here can hold. Windows and Linux; macOS has no pen-button
support yet.

- [ ] **Press the pen's side button and draw a loop.** It lassoes — by default,
      as OneNote does. **Settings ▸ Writing and drawing ▸ Pen and touch**
      can make it Select, Eraser or nothing instead.
- [ ] **If your pen driver maps a button to the eraser**, that button erases,
      whatever the setting says. **The tail end of the pen erases** too.
- [ ] **Press and release the side button many times, quickly.** It should do
      the same thing every time. It used to be a coin toss, "most times but not
      every time".
- [ ] **What you lasso stays selected when you let go of the button**, and the
      pen then drags it — press inside the selection and move.
- [ ] **Press anywhere outside the selection with the pen**: the selection is
      put down and the pen draws, straight away, with nothing to switch back.
- [ ] **Hover the pen near the page with the eraser in hand.** A faint ring
      shows how far it reaches before it touches anything.
- [ ] **Lasso a box, a picture or a graph.** Each is caught once at least half
      of it is inside the loop. A slide from an imported PDF is never caught.
- [ ] **Lasso one stroke on its own** — a Delete appears for it.
- [ ] **Lasso a word, move it, then click away.** The strokes go back to being
      separate strokes. They used to stay welded together for good.

---

## 2. Writing on a PDF or a picture

GitHub #20 — *"some bugs that make it almost impossible to work with imported
PDFs or images."* Use a real lecture deck if you have one.

- [ ] **Middle-drag over a slide, a picture and a text box.** All three pan the
      page. Before, only empty page did.
- [ ] **Write on a slide, then click your writing.** The writing is selected,
      not the slide.
- [ ] **Annotate two corners of a slide quickly.** They stay two separate
      pieces of handwriting, not one the size of the slide.
- [ ] **Drag a selection box over your notes on a slide.** It selects the notes
      and leaves the slide alone; moving them leaves the slide where it is.
- [ ] **Brush the corner of a picture with a selection box.** It is not
      picked up; it wants about half of something.
- [ ] **Drag handwriting up into the title area, and past the right edge of a
      paper page, and let go.** It is pulled back onto the page — and the
      writing comes with its box. The box used to jump while the writing
      stayed behind.
- [ ] **Move, erase and recolour old handwriting, then reload the page.** It is
      where you left it.
- [ ] **Right-click a slide ▸ unlock every page of this PDF.** The whole deck
      unlocks at once.

---

## 3. Grouping

- [ ] **Select a few things of different kinds** — a box, some handwriting, a
      picture — **and group them**: Ctrl+G, right-click ▸ Group, or the button
      above the selection.
- [ ] **Click any one of them**: all of them are selected, and they move,
      copy, cut and delete together.
- [ ] **Click a grouped text box twice.** The first click takes the group; the
      second puts the caret in the box.
- [ ] **Copy a group and paste it.** The copy is a group of its own — dragging
      the original leaves the copy where it is.
- [ ] **Ctrl+Shift+G takes it apart**, and Ctrl+Z puts it back.

---

## 4. Styles on top of styles, and highlighting

GitHub #17. The rule is that any style works inside any other, in either
order.

- [ ] **Bold a word, then colour it** — and the other way round. Then add
      italic, a highlight, strike-through. Every one shows, and no `*`, `~`
      or `{{` is left on the page.
- [ ] **Open an old note** where you tried this before and it showed symbols.
      It should now show what you meant, with nothing to redo.
- [ ] **Italicise the last word of a bold phrase.** No stray asterisk.
- [ ] **Take the colour off a bold red word** with the toolbar. It loses the
      colour; it does not gain a second one.
- [ ] **Backspace at the end of a bold red word** deletes the last letter and
      nothing else.
- [ ] **Highlight a word, then open the arrow beside the highlighter and pick
      a colour.** The word is highlighted in it, and the button's bar shows
      which colour it will use next time.
- [ ] **Press the highlighter again on that word.** The highlight comes off.
- [ ] **Colour a word AND highlight it.** Both show, and taking one off leaves
      the other.
- [ ] **In dark mode**, is a highlight colour still readable with text on top?
      This one is a judgement call and yours is the one that counts.
- [ ] **Export a page with a coloured highlight to Markdown.** The highlight
      is there as `==text==`; the colour is not, which is the most Markdown
      can carry.

---

## 5. Flashcards keep their own history

v1.0.2 bug 16. Quick to check, and it is your revision record.

- [ ] **Review two cards written in a box** (the `?[question](answer)` kind)
      until they are scheduled for different days.
- [ ] **Press Enter above them, or type a new line above them.** Each keeps its
      own next-review date. Before, the first took the second's.
- [ ] **Now press Ctrl+Z.** The dates follow the cards back up.
- [ ] **Drop a picture into that box, above the cards.** The dates still hold,
      and a dated to-do below the picture keeps its date.

---

## 6. Pictures and pasting

- [ ] **Drop an SVG on the page**, and use Insert ▸ Image for another. Both are
      drawings, sharp at any zoom, and still sharp in a PDF export.
- [ ] **Drop a picture onto empty page.** It arrives in a box you can type in
      under it, and you can cut and paste it like text.
- [ ] **Your existing pictures** open, move and export as they always did.
- [ ] **Click a picture inside a box.** It is selected — Ctrl+C, Ctrl+X and
      Delete all act on the whole picture.
- [ ] **Put the caret just after a picture and press Backspace.** The whole
      picture goes, not part of its reference. Same for Delete just before one.
- [ ] **Type right after a picture, and right before one.** What you type ends
      up on its own line; the picture stays a picture.
- [ ] **Copy a picture and paste it into the middle of a sentence.** It gets a
      line of its own rather than breaking.
- [ ] **Cut a whole box, click into another box, and paste.** Its writing
      arrives at the caret. Try one with a table in it, and one with a
      picture.
- [ ] **Cut some handwriting and try the same.** Nothing is pasted into the
      box, and it still pastes on the canvas.

---

## 7. Pages

- [ ] **Click a page title.** One click, and you are typing in the title.
- [ ] **Right-click a page, a section and a section group.** Each has Rename.
- [ ] **Right-click a page ▸ Duplicate.** The copy sits right under it with its
      name ready to type over.
- [ ] **Make a page next to a graph-paper page.** The new one is graph paper
      too, with the same width and paper.
- [ ] **Switch notebooks and come back.** You are on the page you left, in
      each.
- [ ] **Templates are gone from the menus**, and nothing you saved went with
      them.

---

## 8. Settings, one group at a time

- [ ] **Open Settings.** Groups down the left, one group's settings on the
      right.
- [ ] **Look for three settings you know.** Did you find each where you
      expected? Is anything now missing a word it needed?

---

## 9. AI helpers

Needs Claude, ChatGPT, Claude Code or Gemini CLI connected from **Settings ▸
Connections ▸ AI access**.

- [ ] **Ask it to tidy a page**: fix a typo in a box, move things, rename the
      page. Each change is a normal edit, and Ctrl+Z undoes it.
- [ ] **Ask it to add a table and some code.** They arrive as a real table and
      a code box, not symbols.
- [ ] **Put a passcode on a section, then ask it what is in that section.** It
      cannot see it, says something is withheld, and cannot open it — even
      after you unlock the section in Openote.
- [ ] **The AI page says when a helper last used Openote**, and says "set up"
      rather than "connected".

---

## 10. Equations

- [ ] **Evaluate `F = m·a`, `v = u + at` or `c = √(a² + b²)`.** It asks for
      each letter, in order, and answers by name: `v = 14`.
- [ ] **Evaluate is a button beside Graph** on the equation toolbar.
- [ ] **Highlight part of an equation and press `(`.** It wraps what you
      highlighted rather than replacing it.
- [ ] **On a narrow window**, the equation toolbar folds into More rather than
      running off the edge.

---

## 11. Sync

- [ ] **"N devices"** counts the devices you actually use.
- [ ] **With two Google accounts signed in**, the folder picker names each
      one, with its drive letter.

---

## 12. Touch, on a tablet

The two parts that were fixed are deterministic and tested; whether the
result *feels* right is not something a test can say, and that is most of
what is wanted here.

- [ ] **Drag a finger across a text box.** The page scrolls. It used to select
      the box's words, which on a tablet left almost nowhere to scroll from.
- [ ] **Tap a box.** It still opens for typing — a short scroll that ends on a
      box must not open it, and a tap must.
- [ ] **With the caret in a box, drag a finger across its words.** They are
      selected: that is how you select without a keyboard.
- [ ] **Pinch out, then pinch back to where your fingers started.** The page
      comes back to the zoom it began at. Then pinch out past the furthest
      zoom, hold, and come back — still the same.
- [ ] **Is the zoom smooth now?** It compounded its own rounding before. This
      is a feel question and yours is the answer.
- [ ] **Drag boxes around at several zoom levels** — right out, right in. You
      remembered this being "definitely funky"; I could not reproduce it (every
      drag path divides by the zoom), so if it is still wrong I need to know
      what you see: does the box lag the finger, overshoot it, or jump?
- [ ] **One finger on empty page scrolls**, two fingers pan and zoom, and a
      pen still draws.

---

## 13. Page windows and passcodes

- [ ] **Put a passcode on a section**, then drag one of its pages onto another
      page. You are asked for the passcode before any window is made, and
      Cancel makes nothing.
- [ ] **Insert ▸ Page window** on that locked page: asked before the page is
      drawn to pick an area from, and locked pages show a padlock in the list.
- [ ] **Leave the page the window is on and come back.** The window asks
      again.
- [ ] **Unlock the section in the navigator**, then look at the window. It
      still asks — the two are separate doors, deliberately.
- [ ] **A window onto a page with no passcode** is not asked about at all.

---

## 14. Things I already know about

Not for you to test — recorded here so you are not surprised by them.

- **The demo notebook's handwriting is missing.** Its Maths page has eight
  pieces of ink whose strokes were never copied into it, so the page opens
  and draws nothing there. You are redoing it; the steps are in
  [app/assets/demo/README.md](app/assets/demo/README.md).
- **A flashcard's history can still slip if its line is edited on another
  device.** Schedules are kept on each device under the card's line number,
  so a line added above a card elsewhere arrives without the schedule
  moving. So can splitting a card's own line with Enter. The v1.0.3 card
  rebuild gives every card a permanent identity and ends both.
- **Opening a notebook from a cloud folder that is not "Available offline"
  freezes the app.** Minutes, with no explanation, and it may not recover. Set
  the notebook's folder to be available offline on every device and it does
  not happen. Written up in
  [docs/planning/v1.0.2.md](docs/planning/v1.0.2.md) §5.
- **The formatting buttons are grey inside a table cell.** Typing Markdown
  into the cell works and is the way to format one today. v1.0.2 bug 2.
- **The console prints accessibility errors constantly** —
  `Failed to update ui::AXTree` — and screen readers cannot read the editor.
  The check that fails is in the engine. v1.0.2 bug 1, §1.
- **The caret may blink out of a table cell and straight back in.** If you can
  carry on typing, that is this. If it leaves and **stays** out, that is a new
  bug — tell me.
- **Four tests can fail when the machine is busy**, all asserting something
  about *time* rather than behaviour: `graph_plot_test`, `cloud_sync_test`,
  `code_runner_test`, `import_writer_test`. If they go red, look at how long
  the run took before you look at the code.
