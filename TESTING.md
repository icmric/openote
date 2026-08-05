# What needs testing, and what I need from you

> Working document · last updated 2026-08-05 · branch `claude/tag-import-and-storage`
>
> Everything below is either **built but never seen by a human**, or **blocked
> on something only you can do**. Nothing here has been verified on real
> hardware by anyone. Tick things off as you go; tell me what breaks.

---

## 1. Built but unverified — please try these

Four substantial changes are stacked on the branch, in this order. If something
is wrong, the earlier ones are the more likely culprits.

### 1.1 The Planner (v0.5) — biggest surface, least tested

Open it from the command bar (calendar icon beside Study), or read the
"Coming up" summary in the navigator's Home pane.

- [ ] **Exam dates** — set, move and clear one *from the planner* rather than
      from the study panel's menu. This is the fix for "the exam countdown is
      not that easy to use", so it is the thing to judge hardest.
- [ ] **Due dates on to-dos** — tag a line, then tag menu ▸ *Due date…*. The
      deadline should render in the note's own gutter ("Fri", "12 Aug", red
      once overdue) **and** appear in the planner.
- [ ] Press Enter on the line *above* a dated task. The deadline must not move
      or vanish. (This one had a real bug; it is fixed and tested, but it is
      the kind of thing worth confirming by hand.)
- [ ] **Reminders** — set one for two minutes out, leave the app open, check it
      pops. Then set one for two minutes out, **close the app**, reopen after
      it passes: it should be waiting under *"1 reminder while you were away"*.
      That second case is the whole design; if it fails, the feature is a lie.
- [ ] **Snooze** a fired reminder. It must not immediately re-fire.
- [ ] **Timetable** — see §3.2, I need a real `.ics` from you.
- [ ] **Month view** (calendar icon in the panel header) — dots on days that
      have something, click a day to filter.
- [ ] Ticking a task in the planner ticks it in the note, **without** yanking
      you to that page.

### 1.2 The UI revamp (v0.6) — judge the feel, not the features

Nothing new appeared; a lot was made consistent. What I want to know is
whether it still "feels a bit off", and if so, where.

- [ ] Does it look like one app now? Particularly: dialogs, the date picker,
      the little confirmation messages (they were full-window-width bars).
- [ ] **Dark mode** — panels should sit visibly *above* the page rather than
      merging into one black rectangle.
- [ ] Is the text still too small anywhere? It all moved up ~1px onto a fixed
      ramp; I would rather know if it should go up again.
- [ ] The toolbar with nothing selected shows three grey group icons instead
      of twenty. Does that read as calm, or as missing?
- [ ] **Only one right-hand panel opens at a time now.** If you find a real
      workflow that needs two, tell me — that decision is reversible.
- [ ] The breadcrumb row (notebook ▸ section) now only appears when the
      navigator is collapsed. Do you miss it?

### 1.3 The sync chip going grey — the bug you reported

- [ ] Put a notebook in your sync folder, close the app, reopen. The chip
      should be green and should **name the folder**.
- [ ] Try it with a folder that is *not* a standard provider path (any folder
      you pick yourself). That case never worked before.
- ⚠️ **Known gap:** a notebook you moved into a custom folder *before* this
      change has no remembered root yet. It should go green the first time you
      open the sync dialog and confirm the folder. If you would rather it
      healed itself silently on open, say so — I left that as your call
      because it is a guess of a different kind.

### 1.4 Images between devices — **needs two machines**

This is the one I most want tested, because it is the one I could not test
properly. I found that a shared notebook containing an image would **break
syncing entirely** on the second device (a foreign-key violation took down the
whole pull, not just the image). It is fixed and covered by four tests, but
those tests simulate the second device.

- [ ] Device A: put an image in a shared notebook. Device B: pull. The image
      should appear, and everything else in that batch should sync too.
- [ ] Same again but let device B pull *before* the image file has finished
      copying (start the pull immediately). The page should arrive without the
      picture and sync should keep working; the image should appear on a later
      pull.

---

## 2. Older verification debt — still outstanding

Carried from the v0.2 release plan and never cleared.

- [ ] **macOS and Linux** have never been run by a human. Windows is the only
      platform with real use behind it. The Linux **print dialog** in
      particular you flagged as "works but looks really old" — that is the
      stock GTK dialog and mostly not ours, but I would like to know whether
      the parts we own look wrong too.
- [ ] **Rebuild-from-log as a real join path.** It exists in shadow mode with a
      test and has never been the user-facing way to join a notebook. This one
      is load-bearing: it **blocks** the container demotion, which in turn
      blocks the biggest disk-space win (see §4).

---

## 3. Things I need from you

### 3.1 A `.one` file with a **ticked** to-do

The OneNote importer brings tags across but every imported to-do arrives
unticked, because the two candidate properties in the file we have contradict
each other and a wrongly-ticked to-do is worse than an unticked one. One
notebook containing a to-do you have actually checked off would settle it.

### 3.2 A real university `.ics` URL

The calendar parser is thorough — 54 tests, adversarially reviewed, handles
recurrence, overrides, malformed feeds — but it has only ever met fixtures I
wrote. A genuine timetable feed is the obvious next verification. If you would
rather not share the URL, a downloaded `.ics` file is just as good.

### 3.3 Decisions I have parked for you

| # | Question | My recommendation |
|---|---|---|
| 1 | Should a notebook already in a custom sync folder heal itself on open, or wait for you to confirm in the dialog? | Wait — silent inference is how you get a *wrong* green chip |
| 2 | Custom window title bar (merging the breadcrumb into it)? | Not yet — platform-fiddly, and the breadcrumb question above may make it moot |
| 3 | Swap Material icons for a Lucide-style set? | Decide after you have lived with the revamp; the token layer makes it cheap now |
| 4 | Packaging — see `docs/planning/v0.7-packaging.md` | Answer the three questions at the end of that document |

---

## 4. What I would do next, once you have tested

In the order I would take them:

1. **The tag gutter / edit-view parity fix.** The only item that is a bug
   *you already reported* — "the dotpoints render differently when I'm editing
   compared to when I'm not". I attempted it during the revamp and backed it
   out: the gutter exists only in the read renderer, so fixing one side alone
   makes the jumping worse. The real fix changes both renderers together, with
   `edit_view_metrics_test` driving it.
2. **Disk space (E1/E2, ADR-0007).** A 60-slide deck costs ~240 MB because
   every image is stored twice and nothing is ever deleted. Garbage collection
   is unblocked and I can build it; the *de-duplication* half may or may not be
   blocked by the join path in §2 — I want to prove which with a two-device
   test rather than argue it from the ADR.
3. **Accessibility (PLAT-5).** Keyboard traversal between blocks, focus order,
   screen-reader labels on the canvas, reduce-motion. The contrast half is
   done; this is what is left of the promise.
4. **Finish the `AppState` split.** `SyncCoordinator` and `TagOps` remain.
   Worth doing before the next big feature rather than after.

---

## 5. Previously reported — believed fixed, worth confirming

| You said | State |
|---|---|
| "Some symbols end up with `$x$` around them" | **Fixed** — needed the Rust core rebuilt; check your build stamp in the status bar if it recurs |
| "I don't love the notebook selection method" | **Rebuilt** — two resizable columns plus a 44px rail (Ctrl+\\), the OneNote shape |
| "I'd like to add a notebook from inside the sync button" | **Done** — *Add a notebook…* in the sync dialog |
| "The print dialog looks really old" | **Partly ours** — see §2 |
| "The dotpoints render differently when editing" | **Still open** — see §4 item 1 |
