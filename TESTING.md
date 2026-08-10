# What needs testing, and what I need from you

> Working document · last updated 2026-08-10 · **test from master** (no
> release is cut yet, on your instruction — Linux items wait for the next
> one; everything else runs from source on Windows).
>
> Everything below is either **built but never touched by a human**, or
> **half-verified** — you confirmed part and deferred the rest. Tick things
> off as you go; tell me what breaks. Confirmed things get deleted, so this
> file stays the honest queue rather than a museum.

---

## 1. Deferred by you, waiting on hardware

### 1.1 Touch — needs the tablet / touch screen

- [ ] **Finger drag pans the page** (not marquee). A finger *tap* should
      still do everything a click does — create a text box on empty page,
      select a block. Pen and mouse drags still marquee.
- [ ] **Board cards on touch.** Dragging a card between columns uses an
      immediate drag; the block itself moves by long-press. Flagged when the
      board shipped: these two may fight on touch — if a card drag keeps
      picking up the whole block (or vice versa), describe which gesture you
      made and what moved.

### 1.2 The pen — needs the stylus

- [ ] **Proximity switches to inking.** With Select active, bring the pen
      NEAR the page (don't touch): the tool should flip to Pen. Pick Select
      again while the pen hovers — it must stick until the pen leaves and
      comes back. The toggle for the whole behaviour is in the Draw tab.
- [ ] **The tail erases.** Flip the pen; strokes under it should erase with
      no tool change.
- [ ] **The barrel button erases** while held during a stroke. (Whatever
      your pen's button is mapped to in the OS, the signal that reaches apps
      is the barrel flag; if pressing it does something OTHER than erase,
      tell me what.)

---

## 2. Built this round, untested or partly tested

### 2.1 PDF-as-PDF — the deep change; you confirmed the viewer, the rest needs eyes

The importer no longer rasterises pages into stored images: the PDF is
stored once, slides are drawn from it on demand.

- [ ] **A fresh printout import looks IDENTICAL to the old kind** — same
      sharpness, same layout, annotate with the pen as before. This is the
      claim the whole change hangs on.
- [ ] **Import speed**: a big deck should import in seconds now (the
      per-page rendering is gone from the import path).
- [ ] **Notebook size**: import a deck you've imported before and compare
      the notebook's size — it should now cost roughly the PDF, once.
- [x] The popup viewer opens, text selects and copies. *(Confirmed; sizing
      and scrolling fixed on your feedback — recheck the wheel distance and
      the page-numbered thumb if you get a chance.)*
- [ ] **The card**: import ▸ arrow ▸ *As a card*, or drop a .pdf onto the
      page — one thumbnail block, click opens the viewer.
- [ ] **Scroll a long printout fast** — slides render as they arrive
      (brief spinner placeholder is expected; blank holes or wrong pages are
      not).
- [ ] Note: **old imports keep their old raster storage** — only new
      imports get the stored-once form. If you want existing decks
      converted, say so and I'll build the migration (same shape as the ink
      one, housekeeping would run it).

### 2.2 The page scroll bar — NEW, from your report

- [ ] A vertical bar on the right edge of the page whenever the page is
      taller than the window: drag it, click the track to jump. Wheel and
      panning unchanged.

### 2.3 Code cells — NEW, and the JS half is untestable by machine

SQL cells are fully covered by tests; the JS engine only exists in a real
build (QuickJS arrives with the Flutter build, not the test VM), so **every
JS item below is machine-unverified**:

- [ ] Make a code block, set its language to `sql`, put a table on the same
      page (drop a CSV), and run `SELECT * FROM t1` — the Run button, or
      Ctrl+Enter while editing. Output should appear under the source as a
      real table and SURVIVE a restart.
- [ ] The error for a wrong table name should list the tables that do
      exist on the page.
- [ ] Set language `js`: `console.log("hi"); 1 + 2` — output shows both.
      `tables.<name>` should hold your page table's rows.
- [ ] `typeof fetch` in a js cell must print `undefined` — if it prints
      `function`, stop and tell me immediately, that is a sandbox hole.
- [ ] A `while(true){}` js cell: the spinner should give way to a
      "Stopped" error after ~5 s and the app stay responsive. (Known,
      documented: the stuck engine thread keeps burning a core until app
      close — the UI recovering is the claim to check.)
- [ ] The scroll bar again after this build: drag it — the page should
      move and NO selection box should appear behind it (that was the
      pointer-claim fix).

### 2.4 AI access (MCP) — NEW

The protocol and tools are machine-tested over real HTTP; what needs a
human is the end-to-end with a real client:

- [ ] View tab ▸ the robot icon ▸ turn it on ▸ press **Connect Claude
      Code** — no terminal, no copying; Openote writes the connection
      itself and the message tells you it worked. Then in a fresh Claude
      Code session, ask it to list your notebooks, read a page, search.
      (The old JSON/command routes still exist under "Other AI tools
      (advanced)" for any non-Claude tool.)
- [ ] Ask it to CREATE something — "make me 5 flashcards about X on page Y"
      is the canonical test. The cards should appear on the page, be
      undoable with Ctrl+Z, and show up in the study deck.
- [ ] Restart Openote: the server should come back by itself (the toggle
      stays on), and the same pasted config should still work.
- [ ] Sanity: with the toggle OFF, the same client must fail to connect.

### 2.5 Small recent things

- [ ] **Ctrl+/** — the keyboard shortcut reference, from anywhere including
      mid-typing. Same chord or Esc closes it; View tab has a button too.
      Everything it lists should be true — a listed chord that doesn't work
      is a bug worth reporting.
- [ ] **Keyboard-only canvas**: click an empty part of the page once, then
      put the mouse down. Tab / Shift+Tab should walk the boxes in reading
      order, plain arrows jump to the nearest box in that direction, Enter
      drops into the box's editor, Esc climbs back out, Ctrl+arrows move
      the selected box (add Shift for 1 px), Del deletes. Arrow keys inside
      a text box must still move the CARET (the box only moves with Ctrl).

- [ ] **Selected-box priority on text**: select a box whose end runs under
      another, then try SELECTING TEXT in the overlapped part (you confirmed
      resize; text selection through the overlap is the other half).
- [ ] **Box tint through a page window**: tint a box, then look at it
      through a portal on another page — the tint should show there too.
- [ ] **Markdown export of a board** — each column a heading with its list.

---

## 3. Linux — waits for the next release

- [ ] **Insert ▸ Image.** If it still does nothing, there is now an error
      message with the actual reason — quote it at me. (The silent-failure
      path is gone either way.)
- [ ] **Git sync retest**: the fresh-machine identity fix shipped in 0.6.1
      but your broken notebook may still be sitting there — press sync once
      on it, then check the repo on GitHub has `ops/` and `blobs/` in it.
- [ ] **Portal video** — the card has its shape back; play should work
      in-place (needs libmpv, which the .deb/.rpm install).
- [ ] CSV/xlsx drop, the board, PDF-as-PDF — all also worth one pass on
      Linux since none has run there.

## 4. Things you reported that are DESIGN work, not bugs (parked, visibly)

| You said | Where it stands |
|---|---|
| Excel import "imported it just as a plain text table" — no formulas, styling rules, charts | Correct and currently by design: a formula cell imports the number you saw. Keeping formulas live needs the table block to HAVE a formula/styling/chart model first — that's the spreadsheet-engine design pass, top of the Tables item in PLANNING.md, and the importer grows with it. |
| Dead links inside a page window | Could not reproduce through the full widget stack with mouse or touch — my standing suspicion is links inside TABLE blocks (inert by policy) vs text (live). Next time you hit one: table or plain text, page link or web link? |

## 5. Older verification debt — still true

- [ ] **macOS has never been run by a human.**
- [ ] Two-machine image sync (§ the old 1.3): device B pulling while the
      image file is still copying should get the page now, picture later.
