# What needs testing, and what I need from you

> Working document · last updated 2026-08-06 · branch `claude/performance`
>
> Everything below is either **built but never seen by a human**, or **blocked
> on something only you can do**. Tick things off as you go; tell me what breaks.
>
> **Changes since the last round** — found the import stall that survived your
> release-exe test: a page whose text is one enormous box was being measured in
> one indivisible 200–600 ms call on the app's thread, several times per real
> notebook. Now measured in small chunks with a frame between each (§1.0).
> Launch you've confirmed clean ✅. The import is the one to re-test.

---

## 1. Built but unverified — please try these

### 1.0 The import rework (v0.9 + v0.10) — NEW, and the one to try first

The whole flow changed shape: importing a `.onepkg` now runs in the
**background** with a floating progress card, and the app stays fully usable
while it works.

**What changed in v0.10, over three rounds.** You first wrote: *"Visually it
updates with the popup, however interactions with the page aren't completed
until the import is finished."* That was one bug wearing a disguise — painting
and interacting have different appetites. The import gave the app just enough
time between batches to draw a frame (so it *looked* alive) and nowhere near
enough for a click, which is a whole conversation of steps rather than one
event. So the import moved off the app's thread entirely: a second process
reads the file, parses it and writes the notebook.

Then you wrote: *"still locks up when it starts displaying all the pages in the
popup"* — and later added that the app is **locked up for the first few seconds
after launching**. The launch clue cracked it: both freezes were the same bug,
and it wasn't the import itself. To show sync status, the app was reading and
replaying the notebook's **entire change log** — every op the import wrote, one
per block — synchronously, before it would draw anything. At launch that ran
for the open notebook; at the end of an import it ran the moment the new
notebook's backup dot first painted, which is exactly when the popup shows the
result. Half a second for a synthetic 2000-page notebook on fast hardware;
seconds for a real one on Windows.

Now status reads cost a directory listing (~3 ms), and the log replay happens
on a background thread, started at launch and at import completion — so the
first edit finds it already done.

Then, with the release exe, you confirmed launch was clean but *"the stall
during import though was still very much there."* Found it, by measuring what
none of my synthetic notebooks had: a page whose text is **one enormous box**.
Laying out imported text happens on the app's thread (nothing else can measure
text), and one box was measured in one indivisible call — **216 ms for a
2000-line box, 613 ms for 5000**, several times per real lecture notebook. It
is now measured in 64-line chunks with a frame given back between chunks —
worst pause ~14 ms regardless of box size, verified identical layout to the
bit.

- [ ] Fresh-start test: delete your workspace folder (or use a VM), launch,
      and pick **Bring my notes over from OneNote** in the welcome dialog.
      The dialog should STAY OPEN with a progress row, and a card should
      appear bottom-left with live page counts.
- [ ] **Type, scroll, draw AND click into text boxes while it imports.** This
      is the headline claim, and the clicking is the part that was broken:
      switching pages, opening panels, selecting a box — the things that need a
      round trip to the database, not just a repaint. They should feel exactly
      as they do when nothing is importing. If you feel a stutter, note what
      the card said at that moment.
- [x] **Launch.** You confirmed the release exe launches with no stall — and
      that the stall you saw was debug-only. (The background-replay fix stands
      regardless: debug is where development happens.)
- [ ] **The moment the import finishes.** The popup announcing the result used
      to be exactly when the app locked up (the new notebook's backup dot
      triggered the same replay). It should now stay smooth straight through
      the "Imported N pages" card, and clicking into the imported notebook
      right away should work without a pause.
- [ ] The counts should start moving **immediately** after the total appears
      (the earlier one-giant-message layout bug, also fixed). If anything still
      hitches, tell me what the card said and roughly how big the notebook is.
- [ ] The progress popup that had vanished is back (as the card). Watch for
      the counts moving — "118 of 324 pages".
- [ ] **Cancel** mid-import. It should stop within a moment and the
      half-imported notebook should be gone from the manager — *and* not sitting
      in the recycle bin. Try this once in a workspace with **no other
      notebooks**: that case used to keep it, silently.
- [ ] Let one finish: the card should say what arrived ("324 pages, 372
      images…") and offer **Open notebook** — and it must NOT yank you there
      by itself.
- [ ] Import from the notebook manager too (Import ▸ OneNote notebook) — same
      card, plus a snackbar saying it runs in the background.
- [ ] **Time it.** The wall-clock should be *better* than before, not merely
      similar: half the disk writes are gone (see §1.0d) and the writes no
      longer wait for frames. But the app being alive is still the point.
- [ ] Check the notebook's **name**: importing `Uni Notes.onepkg` should give
      you a notebook called "Uni Notes", not "Uni Notes.onepkg".

### 1.0a The import entry points — the bug you just hit

The `.onepkg` import from the **notebook manager** was completely dead: the
file picker opened, you chose a notebook, and the very next line returned
without doing anything. My fault, introduced with the background-job rework.

- [ ] Notebook manager ▸ **Import** ▸ *OneNote notebook (.onepkg)*. A snackbar
      should say it is importing in the background, and the card should appear
      bottom-left.
- [ ] The same from the **welcome dialog** (that path was already working, but
      it now shares the fix).
- [ ] Notebook manager ▸ **Get started** — this had the identical bug one line
      above and should now open the welcome dialog properly.
- [ ] Start an import, then try to start a second one: it should refuse with
      "an import is already running", not queue or interleave.
- [ ] Cancel the file picker: nothing at all should happen, no error.

### 1.0b The study tab on your big notebook

- [ ] Open the flashcards/study tab on the imported notebook. This was your
      "opening the tab is very slow" report — it should now be instant, since
      only tagged pages are read.
- [ ] The tags rollup and the planner should feel the same.
- [ ] Check the deck contents are unchanged: same cards as before the update.


### 1.0c The backup dot — NEW

- [ ] Open the notebook manager: every notebook row now has a dot after its
      icon. **Green** = in a sync folder, **amber** = backed up by a mirror but
      not syncing, **hollow ring** = this computer only.
- [ ] Hover each one — the tooltip says it in words, and names the folder.
- [ ] The navigator header (above the search box) shows the same thing for the
      open notebook, with the folder name spelled out.
- [ ] Move a notebook into a sync folder and check both surfaces turn green.

### 1.0d The disk-space diet — NEW, and the dot now means something on disk

Openote was storing every image **twice**: once inside the `.onote` file and
once again in the `.onotebook` folder beside it, so that syncing could copy the
folder. That second copy is now written only for notebooks that actually go
somewhere. Measured on a synthetic 40-page notebook with 20 images: **17.4 MB →
9.6 MB**.

The rule, in one line: **a hollow ring on the dot means one copy on disk.**

- [ ] Right-click a **local-only** notebook ▸ *Storage* (or find its files).
      The `.onotebook` folder should have `ops/` and `manifest.json` but **no
      `blobs/` folder at all**. Your big imported notebook is the one to check —
      it should be roughly half the size it was.
- [ ] **The important one.** Now move that notebook into a sync folder. Within a
      few seconds `blobs/` should appear and fill with the images that were
      already in it. Nothing should be missing — the images are still all in the
      `.onote`, and this copies them out.
- [ ] Same again with a **mirror/backup** target instead of a sync folder
      (notebook manager ▸ backup icon). Then look inside the mirror: it must
      contain the images. A backup with no pictures in it is the failure this
      needs to not have.
- [ ] Sanity: open a synced notebook, paste a new image, and check it lands in
      `blobs/` straight away rather than waiting for anything.

### 1.1 The Planner (v0.5) — biggest surface, least tested

Open it from the command bar (calendar icon beside Study), or read the
"Coming up" summary in the navigator's Home pane.

- [ ] **Exam dates** — set, move and clear one *from the planner* rather than
      from the study panel's menu. This is the fix for "the exam countdown is
      not that easy to use", so it is the thing to judge hardest.
- [ ] **Exam *times*** — new. The picker now has a **Add a start time** button.
      Setting one should make the planner row read `9:30 am` instead of sitting
      with the all-day items, and the countdown ("in 12 days") should be
      unchanged. Clearing the date and setting it again must **not** bring the
      old time back.
- [ ] **Due dates on to-dos** — tag a line, then tag menu ▸ *Due date…*. The
      deadline should render in the note's own gutter ("Fri", "12 Aug", red
      once overdue) **and** appear in the planner.
- [ ] Press Enter on the line *above* a dated task. The deadline must not move
      or vanish. (This had a real bug; fixed and tested, but worth confirming.)
- [ ] **Month view** (calendar icon in the panel header) — dots on days that
      have something, click a day to filter.
- [ ] Ticking a task in the planner ticks it in the note, **without** yanking
      you to that page.

### 1.2 The UI revamp (v0.6) — judge the feel, not the features

- [ ] Does it look like one app now? Particularly: dialogs, the date picker,
      the little confirmation messages.
- [ ] **Dark mode** — panels should sit visibly *above* the page rather than
      merging into one black rectangle.
- [ ] Is the text still too small anywhere? I would rather know if it should go
      up again.
- [ ] **Only one right-hand panel opens at a time now.** If you find a real
      workflow that needs two, tell me — that decision is reversible.
- [ ] The breadcrumb row (notebook ▸ section) now only appears when the
      navigator is collapsed. Do you miss it?

### 1.3 Images between devices — **needs two machines**

Still the one I most want tested, and the one I could not test properly. A
shared notebook containing an image used to **break syncing entirely** on the
second device — a foreign-key violation took down the whole pull, not just the
image. Fixed, with four tests, but those tests simulate the second device.

- [ ] Device A: put an image in a shared notebook. Device B: pull. The image
      should appear, and everything else in that batch should sync too.
- [ ] Same again but let device B pull *before* the image file has finished
      copying (start the pull immediately). The page should arrive without the
      picture and sync should keep working; the image should appear on a later
      pull.

### 1.4 Sync — partly confirmed, one case left

You confirmed the chip survives closing and reopening the app. ✅ Removed.

- [ ] The remaining case is §1.3 above: two computers, actually syncing.

### 1.5 The three things you reported — fixed, please re-break them

**Reminders now pop up.** A card appears bottom-right when one comes due,
wherever you are in the app, over the page rather than pushing it.

- [ ] Set a reminder two minutes out, leave the app open, keep typing. A card
      should appear without moving the line you are on.
- [ ] Set one two minutes out, **close the app**, reopen after it passes. It
      should be waiting, headed *"1 while you were away"*. That second case is
      the whole design; if it fails, the feature is a lie.
- [ ] **Done actually dismisses now.** Click Done. The reminder must leave the
      badge *and* the agenda list below — that was the bug. The ✕ in the card's
      corner does the same thing quietly.
- [ ] Every reminder row in the planner now has a **tick** on the right. That
      is the second way to be finished with one, since right-click ▸ *Delete
      reminder* was not discoverable.
- [ ] **Snooze** a fired reminder. It must not immediately re-fire, and it must
      land relative to *now*, not to when it was originally due.

**Your timetable should load now.** See §2.1 — this is the thing I most want
you to try, because I could not reach that host from here.

**The toolbar stops jumping.** Clicking into a text box no longer makes fifteen
buttons appear and shove everything sideways. Every command holds its position
and greys out instead.

- [ ] Click in and out of a text box repeatedly. Nothing on the Home row should
      move.
- [ ] **Insert tab** — the options are ink-coloured now instead of blue, so all
      four tabs match. Does it read as consistent, or as flat?
- [ ] The toolbar and status bar now run to the edges. Check nothing is
      clipped, especially with a right-hand panel open and a narrow window.

### 1.6 The timetable, made useful (v0.8) — all new

Once a calendar is subscribed (§2.1):

- [ ] **"Up next"** appears pinned at the top of the planner: what is on now,
      and what is next with how long you have.
- [ ] Planner ▸ ⚙ (tune icon) ▸ **Alerts before classes…**. Openote guesses
      what each event is from its name — check the guesses are sane for your
      units. Press *Remind me 10 minutes before classes*.
- [ ] Turning alerts on must **not** immediately fire for a class already in
      progress. If it does, that is a bug and I want to know.
- [ ] With a lecture ~10 minutes away, a card should appear. If your feed
      carries a Zoom/Teams/Echo360 link, there should be a **Join** button on
      it — and on the "up next" row.
- [ ] Anything mis-classified? The fix is a keyword, so tell me the exact
      event title.

---

## 2. Things I need from you

### 2.1 Your timetable URL — **the top ask**

The failure you hit (`connection was closed while receiving data`) is a
mid-stream drop, and the host is blocked from where I work, so I could not
reproduce it directly. I fixed it from first principles instead — Openote now
identifies itself properly, retries with compression and connection reuse
turned off, accepts any content type, and tolerates a bad byte. That is tested
against a local server that reproduces the exact hangup, but **not against UTS**.

- [ ] Paste the same URL in again. If it works, we are done.
- [ ] If it still fails, tell me the **exact** message now shown — the errors
      are rewritten to say which of the failure modes it was, so the new
      wording is the diagnostic.
- [ ] Fallback if it is stubborn: open the URL in a browser, save the file, and
      choose the file instead of a URL. That path does not touch any of this.

Two notes on things you were right to wonder about:

- **The extension does not matter.** Openote never looked at it — it sniffs
  `BEGIN:VCALENDAR` in the body. Your URL *is* iCalendar; that was not the
  problem.
- **Google Calendar being private** is a different fix: use **Settings ▸ the
  calendar ▸ "Secret address in iCal format"**, not the public URL. Openote now
  says this in the error when a server answers 401/403.

### 2.2 A `.one` file with a **ticked** to-do

The OneNote importer brings tags across but every imported to-do arrives
unticked, because the two candidate properties in the file we have contradict
each other, and a wrongly-ticked to-do is worse than an unticked one. One
notebook containing a to-do you have actually checked off would settle it.

### 2.3 Decisions I have parked for you

| # | Question | My recommendation |
|---|---|---|
| 1 | Should a notebook already in a custom sync folder heal itself on open, or wait for you to confirm in the dialog? | Wait — silent inference is how you get a *wrong* green chip |
| 2 | Custom window title bar (merging the breadcrumb into it)? | Not yet — platform-fiddly, and the breadcrumb question in §1.2 may make it moot |
| 3 | Swap Material icons for a Lucide-style set? | Decide after you have lived with the revamp; the token layer makes it cheap now |
| 4 | Windows code-signing certificate (~$200–400/yr)? | Not yet — see `docs/planning/v0.7-packaging.md` §4 |
| 5 | Apple Developer account ($99/yr)? | Not yet — same section. Neither is needed to build or share |

---

## 3. Older verification debt — still outstanding

- [ ] **macOS and Linux** have never been run by a human. Windows is the only
      platform with real use behind it. The Linux **print dialog** you flagged
      as "works but looks really old" is the stock GTK dialog and mostly not
      ours, but I would like to know whether the parts we own look wrong too.
- [ ] **Rebuild-from-log as a real join path.** It exists in shadow mode with a
      test and has never been the user-facing way to join a notebook. It is
      load-bearing: it **blocks** the container demotion, which in turn blocks
      the biggest disk-space win.
- [ ] **Neither the Windows installer nor the website has ever run.** Both
      fire for the first time on the next tagged release / push to master. See
      §5 of my reply and `docs/planning/v0.7-packaging.md`.

---

## 4. What I would do next, once you have tested

1. **The tag gutter / edit-view parity fix.** The only item that is a bug *you
   already reported* — "the dotpoints render differently when I'm editing
   compared to when I'm not". I attempted it during the revamp and backed it
   out: the gutter exists only in the read renderer, so fixing one side alone
   makes the jumping worse. The real fix changes both renderers together, with
   `edit_view_metrics_test` driving it.
2. **Disk space, part two.** The double-store half is **done** (§1.0d above:
   2.23× → 1.23× for local-only notebooks). What is left is the bigger absolute
   win: a 60-slide deck still costs ~240 MB because every PDF page is stored as
   a full-page raster image. Storing the PDF once and rendering pages on demand
   fixes that *and* gives you selectable text in imported PDFs *and* the
   thumbnail element — three of your asks, one change. Then blob garbage
   collection (ADR-0007), which is designed and unbuilt.
3. **Notes attached to a timetable event** — "open my notes for this lecture".
   The obvious next step for v0.8, deliberately parked until the two-machine
   sync testing is done, because it is per-workspace state of exactly the kind
   that has bitten before.
4. **Accessibility (PLAT-5).** Keyboard traversal between blocks, focus order,
   screen-reader labels on the canvas, reduce-motion. The contrast half is
   done; this is what is left of the promise.
5. **Finish the `AppState` split.** `SyncCoordinator` and `TagOps` remain.

---

## 5. Previously reported — state

| You said | State |
|---|---|
| "Some symbols end up with `$x$` around them" | **Fixed** — needed the Rust core rebuilt; check your build stamp in the status bar if it recurs |
| "I don't love the notebook selection method" | **Rebuilt** — two resizable columns plus a 44px rail (Ctrl+\\), the OneNote shape |
| "I'd like to add a notebook from inside the sync button" | **Done** — *Add a notebook…* in the sync dialog |
| "The print dialog looks really old" | **Partly ours** — see §3 |
| "The dotpoints render differently when editing" | **Still open** — see §4 item 1 |
| "The sync button goes grey after restart" | **Fixed and confirmed by you** ✅ |
| "There's no popup when a reminder happens" | **Fixed** — re-test at §1.5 |
| "Done doesn't dismiss the reminder" | **Fixed** — it called the wrong method; re-test at §1.5 |
| "No way to fully dismiss or delete a reminder" | **Fixed** — tick on every row; delete still on right-click |
| "Timetable import: connection closed while receiving data" | **Fixed blind** — needs your URL, §2.1 |
| "Events feel clunky and like an afterthought" | **Reworked** — `docs/planning/v0.8-events.md`; try §1.6 |
| "Insert tab options are a different colour" | **Fixed** — §1.5 |
| "The UI doesn't fully extend to the edges" | **Fixed** — §1.5 |
| "Lots of layout shift on the Home tab" | **Fixed** — §1.5. This reverses a decision you were asked to judge last round; the question is withdrawn |
| "Being able to set a time for an exam would be awesome" | **Built** — §1.1 |
| "The app locks up during import / imports are slow" | **Reworked** — background job, §1.0 |
| "We lost the popup when importing" | **Found and fixed** — a context bug ate it; it's a card now, §1.0 |
| "Opening the flashcards tab is very slow" | **Fixed** — SQL prefilter + page cache, §1.0b |
| "Notebook import doesn't work — no popup, never appears" | **Fixed** — my regression; the entry point was handed a dead dialog context, §1.0a |
| "A dot showing which notebooks are backed up" | **Built** — §1.0c |
