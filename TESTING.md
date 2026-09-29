# What needs testing, and what I need from you

> Working document · last updated 2026-09-29 · **v1.0.1 is not cut yet** —
> this is the pass that decides whether it can be.
>
> **§7 is new**, and is the twelve things you reported part-way through this
> pass. None of it has been near a human.
>
> Everything below is **built, covered by automated tests, and never touched
> by a human**. Tests prove a mechanism; they cannot tell you a gesture feels
> wrong, that a colour is hard to read, or that something is technically
> correct and still not what you meant. That is what this list is for.
>
> Only things you can do yourself, on your own machine, are in here. Anything
> the test suite already settles has been left out on purpose.
>
> Tick as you go and tell me what breaks — what you did, what happened, what
> you expected. Confirmed rows get deleted, so this file stays the honest
> queue rather than a museum.
>
> Not to be confused with [the pre-release checklist](docs/pre-release-checklist.md),
> which is the *fixed* pass — the same forty-odd rows run on the packaged
> build before every release. This file is the frontier.
>
> **The v0.7-era queue that used to live here has been cleared out.** Three
> releases have shipped over it and I have no record of what you confirmed.
> If something from it is still outstanding — the pen's proximity switching,
> the tail eraser, the barrel button, finger-drag panning, board cards on
> touch — say so and I will put it back.

---

## 1. Tables in your writing

The largest change in this release, and the one with the longest history of
me fixing something and you finding it still broken. Please be unkind to it.

### 1.1 Making one, and filling it in

- [ ] **Type a word and press Tab.** The word becomes the first cell of a
      table and the caret lands in the second.
- [ ] **Tab again** (still on the top row). This adds a **column**, not a row
      — the top row is where you name things — and the caret goes into it.
- [ ] **Press Enter.** This starts a body row, and the caret lands in the
      **same column** you pressed Enter in. Type: it must go into that cell.
- [ ] **Keep going: type, Tab, type, Tab** down a body row. Tab at the end of
      a body row makes the next row.
- [ ] **On an empty line, Tab indents twice** and never makes a table.

> The caret leaving the table is the bug you have hit four times. If it
> happens again, tell me **which key**, **which cell you were in**, and
> whether the row or column was still created.

### 1.2 Getting in and out

- [ ] **Click a cell** — the caret goes in it, and stays there.
- [ ] **Click the sentence** beside or below the table — the caret comes out.
- [ ] **Arrow keys walk in.** With the caret just after the table, press ←:
      it should step into the last cell. Just before it, → steps into the
      first.
- [ ] **Escape** puts the caret back in the paragraph, and the table stays.
- [ ] **Arrow down from the last row** leaves the table downwards.

### 1.3 The thing that must never happen

- [ ] **Put the caret right at the table's edge and type.** Space, letters,
      anything. The table must stay a table. If it ever turns into
      `![… ](onote://atom/…)`, stop and tell me — that is a note losing its
      table, and it is the one failure here I care about more than any other.
- [ ] **Select from inside the table out into the sentence and type over it.**
      The table should go completely, or not at all — never half.
- [ ] **Backspace just after a table** deletes the whole table.
- [ ] **Undo brings it back.**

### 1.4 Editing in a cell

- [ ] **Ctrl+C, Ctrl+X, Ctrl+V and Ctrl+A** inside a cell.
- [ ] **Ctrl+Backspace and Ctrl+Delete** delete a whole word.
- [ ] **Ctrl+Shift+←/→** selects by word, inside the cell only.
- [ ] **Bold, italic and an equation inside a cell** stay themselves as you
      type them.
- [ ] **Ctrl+K in a cell** opens the link dialog, and the caret comes back to
      the cell when you close it.

### 1.5 Shape and size

- [ ] **The column widens as you type**, from the first character — not after
      a pause, and no stacking letters. It stops widening at a sensible width
      and wraps after that.
- [ ] **The box grows to fit the table**, and a sentence next to a table gets
      room for both rather than being pushed onto the next line.
- [ ] **Drag a column border** to resize it; the width sticks.
- [ ] **Right-click a cell**: insert row above/below, column left/right,
      delete row, delete column — all relative to the cell you clicked. The
      caret should stay in the table after each.
- [ ] **The last row and the last column cannot be deleted.**

### 1.6 Your existing tables

- [ ] **Open a notebook with old tables in it.** They convert to the new kind
      as you open the page, and the rest of the notebook follows quietly. You
      should not be able to tell, except that they now sit in the writing.
- [ ] **Nothing is lost.** Check a table you care about, cell by cell, against
      what you remember — and check the page still opens after a restart.
- [ ] **On a second device**, if you have one syncing: a table made here
      should arrive there intact.

---

## 2. Links

- [ ] **Click into a link.** It stays its words — it must not unfold into
      `[words](https://…)` and re-wrap the line.
- [ ] **Select some words and press Ctrl+K.** The link goes on them.
- [ ] **Put the caret against a word and press Ctrl+K** with nothing selected.
      The link goes on that word — and **not** across the space before it.
- [ ] **A full stop at the end of a sentence stays out of the link.**
- [ ] **Ctrl+K inside an existing link** edits it, and so does **right-click →
      Edit link…**
- [ ] **Insert ▸ Link** opens the same dialog, with the page picker in it.
- [ ] **The link still works** when you click it in the finished note.

---

## 3. Shapes for the pen

- [ ] **Draw tab → pick Line, Arrow, Rectangle, Ellipse or Triangle**, then
      drag on the page. The stroke comes out straight.
- [ ] **Pick it again to turn it off** and go back to freehand.
- [ ] **A shape takes the colour, size and opacity** you have chosen,
      including the highlighter.
- [ ] **Both erasers rub it out**, the lasso picks it up, and undo undoes it.
- [ ] **It survives a save and reopen**, and appears in a PDF export.
- [ ] **Drawing with a trackpad** — the case this was built for. Is it
      actually usable?

---

## 4. Pictures

- [ ] **A picture that is still arriving** (syncing from your server) should
      appear on its own when the bytes land — without a restart and without
      waiting for the next sync cycle.
- [ ] **Right-click a picture → Save a copy.** Both kinds: one dropped onto
      empty page, and one pasted into a paragraph. The saved file should open
      in an image viewer and have a proper extension.
- [ ] **A slide from an imported PDF** saves out too.
- [ ] **A picture your cloud client renamed** is found and put back.

---

## 5. Your own SSH key

- [ ] **In the sync dialog** for a notebook, "Use another key…" lets you
      choose a private key file. Sync to a server that needs it while the rest
      of the machine keeps its default key.
- [ ] **A path with spaces in it** works (this is the part most likely to be
      wrong).

---

## 6. Code blocks — new colours

- [ ] **Comments are green and italic**, strings are a warm red, in a code
      block in **both** light and dark themes.
- [ ] **Is it actually more readable?** This one is a judgement call and
      yours is the one that counts. I moved strings off green so that
      comments in green would stand out; if you would rather have the old
      green strings back and a different comment colour, say so.

---

## 7. The twelve from your testing pass

Everything in this section is new since you started testing and none of it
has been near a human. The first two are the ones I would break first.

### 7.1 Styled text (the one that matters)

- [ ] **Bold a word, press space, keep typing.** The asterisks must never
      appear, and the bold must carry on to the next word, and the word after
      that. Same for italic.
- [ ] **Select a bold word and delete it.** All of it goes — no `**` left
      behind at either end. Try it three ways: dragging left-to-right,
      dragging right-to-left, and selecting just the letters you can see.
- [ ] **Type over a selected bold word.** What you type should still be bold.
- [ ] **Ctrl+Z inside a table cell** takes back what you typed in the cell.
      It must not take the table away.

### 7.2 The navigator

- [ ] **Fold the sections away** with the chevron in the notebook header. The
      navigator should get narrower — that is the point — and the page list
      stays.
- [ ] **Close some groups and some pages, quit, reopen.** They should still
      be closed.
- [ ] **Drag a page into the empty space below the list.** It goes to the
      bottom. Same for a section.
- [ ] **Drag a subpage down there** — it should become a top-level page, not
      an indented one under nothing.
- [ ] **Dropping onto the middle of a page row still makes a subpage.**

### 7.3 Page windows

- [ ] **Drag a page from the navigator onto the open page.** You get a window
      onto it.
- [ ] **Right-click that window → Change to a page link.** It becomes a link
      in a text box, in the same spot, and the link works.

### 7.4 Writing and inserting

- [ ] **Click out of a box onto the page.** A new box opens straight away —
      it should not take two clicks.
- [ ] **Click about the page a few times without typing.** You should not be
      collecting invisible empty boxes; check by dragging a marquee over the
      area afterwards.
- [ ] **Enter from the page title** makes the same bare box a click makes —
      no border, no `heading (#), list (-)` hint.
- [ ] **Insert something while writing.** It should land under the box you
      were in, not in the middle of the screen. **This now applies to every
      Insert item, not just the code box** — tell me if you want it narrowed
      back to code only.
- [ ] **Insert ▸ Code twice**, setting the language on the first. The second
      should open in that language.
- [ ] **Insert no longer offers "Text box".**

### 7.5 The Draw toolbar

- [ ] **Four thickness dots instead of the slider.** Is picking one actually
      easier than aiming the slider was?
- [ ] **The ⚙ beside them** opens the old slider for anything in between.
- [ ] **Two mixed colours on the row now, not four**, and the palette button
      opens the full picker.
- [ ] **"Mix your own colour" in the picker** — is it clear now what that row
      does?

---

## 8. Editor odds and ends

- [ ] **Ctrl+B then type** — the new words come out bold, and stop when you
      press it again. It should not reach back and bold the word behind you.
      Same for Ctrl+I and Ctrl+U and the toolbar buttons.
- [ ] **Press Enter in a completely empty text block.** This used to crash;
      it should simply make a new line.
- [ ] **Delete a page** — you should land on the page next door, in the same
      section.
- [ ] **Delete a section, then Ctrl+Z.** It comes back.
- [ ] **Type down a long page** — the view follows the caret smoothly, and
      scrolling or zooming yourself stops it dead rather than fighting you.

---

## 9. Two things I already know about

Not for you to test — recorded here so you are not surprised by them.

- **`graph_plot_test` can fail under load.** It asserts that ten frames of a
  curve redraw inside 160ms, which is a fair thing to want and an unfair
  thing to promise on a runner doing six other things. It passes alone and
  fails when the machine is busy. `tool_follows_device_test` had the same
  shape and is now fixed properly — its correctness never depended on the
  clock, so the clock came out. This one's whole point IS the clock, so the
  choice is between not gating on it (the repo already has perf probes that
  print their numbers instead of asserting them) or widening the budget until
  it only catches a real regression. Your call; I have not touched it.
- **A caret parked on a table's scope.** If a cell were to take and drop the
  caret four times inside one frame, the caret would sit on the table itself
  with nothing typeable until you click. I could not make it happen, and the
  obvious fix risks a worse problem, so it is written down rather than
  changed. If you ever get a table that swallows the keyboard and only a
  click gets you out, this is what you found.
