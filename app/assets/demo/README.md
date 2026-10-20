# The demo notebook

`demo.onote` is the notebook the browser demo opens with. It is an **ordinary
Openote container** — the same format as any notebook on your disk, not a
special export — so you edit it in Openote.

## To change what the demo says

1. **Copy `demo.onote` into your workspace folder** (`Documents\Openote`),
   with whatever name you like, and open it from the notebook list. Never
   open it where it sits — see below.
2. **Edit it like any other notebook.** Handwriting, section groups and
   subpages all travel (step 5).
3. **Look in its recycle bin** and *Delete forever* anything you would rather
   visitors did not find. Whatever is in there ships with the demo, and
   anyone can open the bin.
4. **Close Openote**, so every save is folded into the file.
5. **Pack it**, from `app/`:

   ```bash
   flutter test test/pack_demo_notebook_test.dart --dart-define=DEMO_FROM="C:\Users\you\Documents\Openote\Openote demo.onote"
   ```

   That writes `app/assets/demo/demo.onote`, with every drawing and picture
   the pages use **inside** it, and lists what is in the recycle bin if
   anything is. If the notebook's folder is not beside the file — you moved
   it to a cloud drive — add `--dart-define=DEMO_FOLDER="<that folder>"`;
   *Sync ▸ Open folder* shows where it is.
6. **Rebuild the web demo** (`flutter build web --release`) and open it. The
   handwriting should be on the page.

**If step 5 refuses**, a page refers to a drawing or picture whose bytes are
not in the folder, and it names them. Nothing is written when that happens:
a demo that looks complete and is not is exactly what this is for stopping.
On the current asset it refuses eight times — the eight drawings on the
Maths page lost their bytes long ago and draw nothing. Delete those eight
blank drawings, redraw, and it packs.

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
with it. See `docs/planning/v1.0.2.md` §12.

`.gitignore` now catches the files, but it cannot catch the data loss, so:
copy, then open.

## Why step 5 exists

**Ink and pictures are stored in `blobs/<sha256>` beside the notebook's log
directory, not inside the `.onote`** (v0.17 Step 6). So a container copied on
its own — by hand, or by *Back up this notebook*, which copies the container
and the folder separately — arrives with references that resolve to
nothing, and the handwriting is simply absent. That is how this asset ended
up with eight drawings whose bytes were nowhere.

The browser demo has no folder: it reads a blob from the container's own
`blobs` table when there is no file for it (`Repository.getBlob`). The packer
(`test/support/pack_notebook.dart`) puts those rows back — the same operation
as `Repository.refillContainerBlobs`, done to a copy, so the notebook in your
workspace keeps its blobs in its folder where they belong — and then checks
that every reference resolves before it writes anything.

## Things worth knowing

- **Keep it small.** It is downloaded by everyone who opens the demo. The
  first version was 94 KB. Since step 5 packs every drawing and picture the
  pages use, a photo costs its full size in that download — handwriting is
  small, a phone picture is not.
- **The title is in two places.** The sidebar shows the name from
  `kDemoNotebookTitle` in `lib/store/demo_notebook.dart`, which is also the
  filename the container is registered under. The container carries its own
  title in `notebook_meta`. Rename in one and the other will disagree where it
  is shown.
- **Nothing a visitor does to it survives.** The whole workspace is in the
  tab's memory and a refresh starts again from this file, so there is no way
  for the demo to be left in a state somebody else has to clean up.
