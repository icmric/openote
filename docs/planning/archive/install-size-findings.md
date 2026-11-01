# Where the install size actually goes

> Scoping only. Measured 2026-08-08 against the v0.4.2 tree; nothing here has
> been acted on. The ask was "do a brief investigation into this now, but we
> will revisit this later when we look more into notebook file sizes too".

## The headline

**The installed app is 101.4 MB on Windows**, across 71 files. The "20–50 MB"
figure is the *download* — the installer and the zip are compressed, and the
`.dmg`/`.deb`/`.rpm` likewise. So the gap between expectation and reality is
roughly a factor of two on top of a number that was already higher than wanted.

Measured from `app/build/windows/x64/runner/Release`.

| Size | File | Ours? |
|---:|---|---|
| 28.4 MB | `libmpv-2.dll` | **yes — a choice** |
| 20.3 MB | `flutter_windows.dll` | no, the engine |
| 12.0 MB | `data/app.so` | ours: all compiled Dart |
| 7.1 MB | `libGLESv2.dll` | no, ANGLE |
| 5.5 MB | `pdfium.dll` | ours: PDF import |
| 4.7 MB | `d3dcompiler_47.dll` | no |
| 4.6 MB | `vk_swiftshader.dll` | no, software Vulkan fallback |
| 3.8 MB | `pdfrx/assets/pdfium.wasm` | **ours, and dead weight** |
| 1.7 MB | `assets/dict/en_us.txt` | ours: spell check |
| 1.6 MB | `MaterialIcons-Regular.otf` | Flutter's icon font |
| 1.5 MB | `sqlite3.dll` | ours: the container |
| 0.8 MB | `onote_core.dll` | ours: the Rust core |

Bundled type is 4.4 MB in total: Inter in **eight** static instances
(~410 KB each = 3.3 MB) and JetBrains Mono in four (~270 KB each = 1.1 MB).
KaTeX adds ~400 KB across twenty small faces.

## What is worth doing, cheapest first

1. **`pdfium.wasm` — 3.8 MB, free.** It is the *web* build of pdfium, shipped
   inside a desktop bundle by `pdfrx`'s asset declaration. Nothing on Windows,
   macOS or Linux can execute it. Excluding it is a build-time change with no
   product cost whatsoever. Start here.

2. **Inter as a variable font — ~2.5 MB.** Eight static instances cover
   400/500/600/700 × upright/italic. One variable Inter (plus its italic) is
   roughly 800 KB for the same range and better interpolation. The risk is that
   variable-font rendering differs subtly; `edit_view_metrics_test.dart` and
   `font_fallback_test.dart` would tell us quickly.

3. **The wordlist — ~1.4 MB.** `en_us.txt` is plain uncompressed text. It is
   loaded once onto a background isolate, so it can be anything: gzip in the
   bundle, or a packed trie, which would also make the load faster.

4. **JetBrains Mono weights — ~800 KB.** Code spans use Regular almost
   exclusively; Bold and both italics are there for completeness rather than
   because anything asks for them. Worth checking usage before cutting.

Items 1–4 together are **~8.5 MB, about 8%**, with no feature lost.

## The big one, and the honest problem with it

`libmpv-2.dll` is **28% of the install on its own** — more than the Flutter
engine. It arrived in v0.4.2 with in-app video, and it is paid by every user
whether or not they ever put a video in a notebook.

Note the asymmetry already present: **the Linux packages do not contain it at
all.** They declare `libmpv2` / `mpv-libs` as a dependency and use the system
copy, so a Linux install is ~28 MB smaller than a Windows one for the same
features. Windows and macOS bundle it because there is no system package
manager to ask.

Three options, none free:

- **Download it on first use.** The honest version of "optional": ship without
  it, fetch it the first time someone inserts a video. But Openote never talks
  to a server by design, and this would be the first thing that does. That is a
  real change to what the product promises, not just a build tweak.
- **Two Windows installers**, with and without video. Doubles the release
  matrix and asks a question at download time that most people cannot answer.
- **Accept it.** 28 MB for "watch your lectures inside your notes" may simply
  be the price.

I do not think this should be decided as a size question. It is a question
about whether video is core, and that is worth answering deliberately —
alongside the notebook file-size work, which is where the storage that actually
grows without bound lives.

## What is not worth chasing

`flutter_windows.dll`, ANGLE, the D3D compiler and SwiftShader (37 MB
together) are the engine and its graphics fallbacks. They are not ours to trim,
and removing the software fallbacks would mean the app failing to start on
machines with poor drivers rather than running slowly.

`data/app.so` at 12 MB is all of our own Dart, AOT-compiled. It is large
because the app is large. Nothing here suggests a quick win in it.
