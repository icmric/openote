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
complete, self-contained database at a consistent point. Closing Openote first
and then copying also works.

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
