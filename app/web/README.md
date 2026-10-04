# `web/` — the browser demo

Hand-written. **Do not run `flutter create --platforms=web` on this repo.**
A throwaway run of it while measuring §16 also removed `pdfium_flutter` from
all three desktop plugin registrants — a broken desktop build in exchange for
a folder you can write by hand in ten minutes. `app/.gitignore` carries the
same warning next to the `ios/`/`android/` lines.

## What the demo is

A try-before-you-download pad, not a cut-down port on the way to a web app.
Nothing is saved, and that is a property of the mechanism rather than a
promise: `store/sqlite_backend_web.dart` registers SQLite's
`InMemoryFileSystem` as the default VFS, so the container, the op log and the
FTS5 index are all real and all live in the tab's heap. Not OPFS, not
IndexedDB, not `localStorage`. A refresh is a new notebook.

The notebook it opens with is `../assets/demo/demo.onote` — a real container,
edited in Openote itself. See `assets/demo/README.md`; nothing in Dart needs
touching to change what the demo says.

Which features are offered and which are greyed out is not decided here. It
is derived from `core/capabilities.dart`, which asks each feature's own web
half the question that feature already had to answer in order to compile. See
`docs/planning/v1.0.2.md` §16.

## `sqlite3.wasm`

730 KB, committed on purpose: it is the matching build of a pinned direct
dependency, and a build step that fetches it would be a build that fails when
GitHub is unreachable.

It comes from the `sqlite3` package's own releases, tagged with the package
version in `pubspec.lock`:

    https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-<version>/sqlite3.wasm

Currently `sqlite3-2.9.4`. **Update it whenever `sqlite3` is upgraded in
`pubspec.lock`** — a mismatch is not a compile error, it is a runtime one.

This build carries **FTS5** and RTREE (and not FTS3/4), which matters: search
is FTS5 and the schema creates a virtual table at notebook-open, so a build
without it would fail on the first page rather than on the first search.

## Building

    flutter build web --release

Output lands in `build/web/`. It is a static site: any host that serves files
will do, and there is no server side to this at all.
