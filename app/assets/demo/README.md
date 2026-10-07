# The demo notebook

`demo.onote` is the notebook the browser demo opens with. It is an **ordinary
Openote container** — the same format as any notebook on your disk, not a
special export — so you edit it in Openote.

## To change what the demo says

1. Open `demo.onote` in the desktop app. Either double-click it, or copy it
   into your workspace folder and open it from the notebook list.
2. Edit it like any other notebook: move boxes, retype the words, add a page.
3. Copy the container back over `app/assets/demo/demo.onote`, and rebuild
   (`flutter build web --release`).

For step 3, prefer **Back up this notebook** (or any route that writes a copy)
over dragging the file out of your workspace. The container is open in WAL
mode while the app is running, so the `.onote` on its own can be missing the
last few saves; the backup goes through `VACUUM INTO`, which asks SQLite for a
complete database at a consistent point. Closing Openote first and then
copying also works.

## ⚠ Do not open this file where it sits

**Copy it into your workspace first, and open it from there.**

Opening a `.onote` makes the folder it is in that notebook's **live log
directory**: from then on Openote writes that notebook's ops and blobs beside
it. Opening this asset in place therefore points a real notebook at this
repository, and it starts filling `assets/demo/` with working files.

That is not hypothetical. It is how it went the first time (2026-10-05), and
it did real damage: one of the two demo notebooks ended up logging into
`build/web/assets/assets/demo/demo.onotebook/`, which `flutter clean` and the
next `flutter build web` deleted — taking that notebook's handwriting blobs
with it. See `docs/planning/v1.0.2.md` §19f.

`.gitignore` now catches the files, but it cannot catch the data loss, so:
copy, then open.

## ⚠ Handwriting does not travel in the container

**Ink and pictures are stored in `blobs/<sha256>` beside the log directory,
not inside the `.onote`** (v0.17 Step 6). So a container copied on its own —
however you copy it — arrives with references that resolve to nothing, and the
ink is simply absent. An earlier version of this file recommended copying the
container without saying so, and that is how the demo notebook ended up with
eight ink blocks whose blobs were nowhere: see `docs/planning/v1.0.2.md`
§18c, and §17 for the grey page it used to cause.

Until a self-contained export exists (`refillContainerBlobs` is the operation
that would do it — §18c), **do not put handwriting in the demo notebook.**
Everything else — text, maths, graphs, tables, flashcards, code — lives in the
container and travels fine.

## Things worth knowing

- **Keep it small.** It is downloaded by everyone who opens the demo. The
  first version was 94 KB. Pictures and PDFs are stored outside the container
  (ADR-0007), so they will not travel with it — which is moot in the demo,
  where those features are greyed out anyway.
- **The title is in two places.** The sidebar shows the name from
  `kDemoNotebookTitle` in `lib/store/demo_notebook.dart`, which is also the
  filename the container is registered under. The container carries its own
  title in `notebook_meta`. Rename in one and the other will disagree where it
  is shown.
- **Nothing a visitor does to it survives.** The whole workspace is in the
  tab's memory and a refresh starts again from this file, so there is no way
  for the demo to be left in a state somebody else has to clean up.
