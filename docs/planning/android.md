# Android (and tablets): where we are, and syncing with Google Drive

Written 17 November 2026, v1.0.3 branch. Android is **not** part of the v1.0.3 release; this is the
groundwork and the plan, so the next steps start from what is true.

## Where it stands

| Piece | State |
|---|---|
| Android project (`app/android/`) | Tracked in git. Gradle 8.14 and Android Gradle Plugin 8.11: AGP 9 needs Gradle 9, which the clipboard plugin's build step (`irondash_engine_context`, cargokit) cannot run on. `kotlin.jvm.target.validation.mode=warning` because `flutter_js` has mismatched Java and Kotlin targets |
| Rust libraries | `bash app/tool/build_android_libs.sh` builds `onote_core` and `onote_text` for arm64 (or `x86_64` for an emulator), with 16 KB page alignment (`-Wl,-z,max-page-size=16384`, checked: LOAD alignment 0x4000). Output goes to `android/app/src/main/jniLibs/<abi>/`, **not in git**: it must be run once on each machine that builds the app |
| Loading | `onote_core` already falls back to the bare library name, which Android resolves. `onote_text` gained an Android branch |
| Phone layout | `DeviceClass.phone` (`ui/device_class.dart`: on a touch device the SHORTER side under 600, so a phone held sideways is still a phone; on a computer the width). Slim top bar with a save mark (tick, arrows, or a pressable red warning) and the Review chip; the page filling the screen; the tools strip and four icon tabs at the foot (Write, Insert, Draw, Page: Insert and Page are sheets, Insert has an Export tile that opens the Export sheet); the navigator as a drawer (notebook with its sync dot, search or jump to, sections with page counts, Recent and favourites, recycle bin, settings; long-press a row for its menu); everything inside the safe area; sideways the bottom becomes one row with the four tabs as icons |
| Tablet layout | `DeviceClass.tablet`: the desktop layout drawn at 135% (`kTabletBoost`, in `UiScaleHost`, on top of the chosen size) so every target is finger-sized; held upright the navigator folds to a rail (`TabletRail`: menu, search, recent, bin) that opens the same drawer a phone has; Review writing becomes a sheet by the existing room rule |
| Touch | Long press with a finger is the right-click on blocks, pictures, board cards, portals and planner rows (`ui/touch_long_press.dart`; a mouse or a pen does not trigger it). A finger scrolls and a stylus draws already (`TouchDrawing.auto`) |
| Saving and exporting | Android has no Save dialog for an ordinary app, so every export, "Save a copy" of a picture or attachment, and the study-deck export go through the system's Save-as screen, which can save to Drive (`export/save_where.dart`, `saveFile` in `MainActivity.kt`; several files, such as a page with pictures or a whole notebook, are zipped). Not covered: saving a video (video is off on Android) and the Markdown-folder import (its folder picker returns an address, not a path) |
| Icon | Adaptive: the purple gradient behind, the ring and its dot in front inside the safe zone, plus a single-colour version for Android 13's themed icons (`res/mipmap-*/ic_launcher_{background,foreground,monochrome}.png`, `mipmap-anydpi-v26`). The old square PNG stays for Android 7 and 8 |
| Release build | `flutter build apk --release --target-platform android-arm64` works (about 104 MB), signed with the debug key, fine for sideloading to test |

## Drive sync: reading and writing, built (17 Nov), to be tried on a phone

**"Open from a Drive folder"** is in the notebook list on Android. It picks a folder with the system picker, copies the other devices' logs and the manifest into this device's own sync directory (`sync/folder_bridge.dart`, `sync/saf_folder.dart`, `MainActivity.kt`), and opens the notebook through the same adopt-and-replay path a git join uses (`AppState.joinNotebookFromFolder`). The text and outline are there at once; **pictures are fetched on demand**, in the background, three at a time, and kept only if their bytes are their hash. A real notebook (the owner's Honours one) is 11 MB of logs in 7 files and 93 MB of pictures in 625, which is why the pictures wait.

**Sending changes back** (`FolderBridge.push`, `AppState.pushFolderNow`): eight seconds after the writing stops, every half minute while the notebook is open, when the app is left (`onInactive`), and the other way round when it comes back (`onResume` pulls). Its rules are held tightly, and each has a test (`test/folder_join_test.dart`):

- It writes exactly two kinds of file: this device's own log (`ops/<this device>.oplog`, replaced whole, only when it has grown) and pictures the folder does not have (`blobs/<hash>.blob`, only if their bytes are their name).
- It never replaces or removes anything that is not this device's own log: not `manifest.json`, not another device's log, not a picture that is there. It never deletes. A test compares every file in the folder before and after.
- It refuses to replace the folder's copy of this device's log with a SHORTER one (this phone would be behind its own history: a restored backup, a copied install). That throws, and shows as "Not on Drive yet".
- A folder that cannot be reached keeps the edit on the phone (the log is local first), shows a quiet "Not on Drive yet" in the save mark, and sends when it can.
- A block type this build does not know, on a page that is edited and sent, comes through untouched to a second device (tested end to end).

The notebook shows as synced (`SyncStatus.driveFolder`, "Google Drive"), not "this computer only".

**Found by the first real try (17 Nov evening), and fixed:**

- **A page opened before its notebook was read in was an OLD page, and it was written back.** The join selected the notebook first and let the fold run in the background; the page loaded half-folded, its tables were still in the importer's shape, the open-time repair converted them and wrote them with a newer clock than the real, later edits, so nine tables went back to their import positions and overlapped their neighbours. (The tell, in the phone's own log: nine `block.set` ops with atoms re-keyed, `placement` back to `free` and the original x/y.) Now the whole history is folded in BEFORE the notebook is shown, a Drive-folder notebook records that it has been (`folded` in its `folderSync:` setting), and until it has, `selectPage` waits (the page area says "Opening this notebook…") and nothing is sent. A notebook joined by an earlier build has no mark and gets it at its next open.
- **"No sections", then sections.** The same cause; an empty outline now shows a progress mark and "Opening this notebook…" in the drawer, the page area and the desktop navigator, and a thin bar while it is read in.
- **The page followed the phone's "font size" setting**, which makes text in fixed-width boxes and tables wider than the room measured for it. The page draws its text unscaled (pinch is its zoom); the chrome still follows the setting.
- **Opening an existing notebook was only possible from the first-run screen.** "Open" is now a button in the notebook list on every device: on a computer it lists notebooks already in Google Drive, OneDrive and the like (up to three folders down) and lets you choose a folder; on a phone it says what to choose, opens the folder picker, then finds the notebooks inside whatever was chosen and asks which. No `.onote` container is needed beside the folder.
- **A notebook taken off the phone and opened again** gets its own earlier history back from the folder (a longer local log is still never replaced), instead of being stuck behind a refusal to push.

**Not built:** putting a notebook that exists only on the phone into a Drive folder (that needs the manifest written, which is the one file the rule above forbids it to touch, so it wants its own design), and the desktop Sync dialog's chooser on Android (the phone has no status bar to reach it from).

**Test copy:** `Openote test copy/Honours (copy).onotebook` on the owner's personal Drive: logs, pictures and manifest copied from the real notebook, which was only read. **Try writing on the copy first, never on the real notebook.**

## Open, before anyone but the owner uses it

- **Application id** is still `com.example.openote`. Make it `org.openote.openote` (as Linux and macOS use) before any release: it cannot be changed after one, and it means moving `MainActivity`.
- **Plugins not yet audited on a device:** `super_clipboard`, `printing`, `desktop_drop`, `pdfrx`. Anything that does not work is to be greyed with "Not yet", as the browser demo does, not hidden. **Video is greyed on Android** (`platformCanLoadEngine` is false there: the engine is desktop libraries) with "Not yet" under it; Print is left available, because the plugin supports Android, until a phone says otherwise.
- **Missing on the phone:** search across notebooks (the drawer searches the open one), long-press on the page's own text (the text editor's own selection menu covers that), and the Markdown-folder import.
- **Debug-build warning** "not 16 KB-compatible" can still name plugin libraries; ours are aligned.
- **Tablet** is built from the board, with one difference: larger targets come from drawing everything at 135% rather than from a second set of sizes. Not yet measured on a real tablet.

## Syncing with Google Drive on Android

**Feasible without OAuth, and it works with notebooks that already exist.** The reasoning:

1. **Why not the Drive API.** The app registration is the small part. The real limit is scope: the only Drive scope that needs no security assessment is `drive.file`, which sees only files the app itself created or the user opened through Google's own picker. Notebooks made by the desktop through the Drive client are not that, so **existing notebooks would be invisible**. The full `drive` scope is "restricted" and needs a paid security assessment. So the API is the wrong tool for this app.
2. **What does work: Android's folder picker (Storage Access Framework).** The Drive app registers a document provider, which is why Drive appears under "Other storage" in the Files app. A "Choose a folder" screen (`ACTION_OPEN_DOCUMENT_TREE`) can be pointed at a Drive folder, the person approves it once (a system screen, no passwords, no app registration), and the grant persists. This is the same idea as the desktop's "the Drive client presents a folder": no tokens held by the app.
3. **What it cannot do.** The files are not ordinary files: `dart:io` cannot open them, there is no append, and listing and writing go through the provider (slower, some caching). A small plugin, or about 150 lines of Kotlin behind a method channel, supplies list, read and write by URI.

### Design: a local copy, and a bridge

The sync format already suits this ([ADR-0006](../adr/ADR-0006-sync-transport-and-text-model.md)): each device **only ever writes its own** `ops/<device>.oplog`, blobs are content-addressed and never change, and the manifest is rewritten whole. So:

- On Android the notebook's op-log folder lives **locally**, in app storage, exactly as a notebook with a local sync folder does today. All the existing code (recorder, materializer, `OpLogStore`) runs unchanged against it.
- A **bridge** moves files between that local folder and the chosen Drive folder:
  - **Pull:** download other devices' logs and any blobs not held locally; verify each blob's hash and discard a mismatch; a log with a torn last line costs that line (JSON Lines).
  - **Push:** upload this device's own log (whole-file replace, only when it has changed since the last push) and new blobs. **Never overwrite or delete anything that is not this device's own file.**
  - Runs when the app opens, after a pause in writing, and on a manual "Sync now".
- **Joining an existing notebook** reuses the second-device path that already builds a notebook from a sync folder's logs: pull the Drive folder into a local temp directory, then run the same join.

### Fail safe, as it stands

Checked in the code on 17 November, and the reason none of the above needs a new rule:

- **Unknown op kinds** are kept, in order, and written back unchanged (`OpKind.unknown`, `rawTag`).
- **A newer envelope** (`v: 2` or later) makes the notebook **read-only** on a build that cannot read it (`SyncRecorder.logIsAhead`): it will not write on top of a history it has only half read.
- **Unknown block types and fields** are kept (`Block.rawType`, `Block.unknownFields`), survive copy and paste, and are drawn as a quiet "Unsupported block" note, not a crash. The owner would rather such a thing were hidden than shown as a note: a one-line change if so.
- Android runs the same Dart data model, so a feature the phone cannot show (video, say) is only missing from the **screen**; its data is carried through untouched.

**Not yet covered by a test:** an unknown block type on a page that is opened, edited elsewhere and saved (the paste test covers copy and paste only). Worth adding before the bridge exists.

### Plan, smallest first

1. **Spike (a day, needs the owner's phone):** a hidden screen that picks a folder, lists it, reads a file, writes a file and replaces it, on a real Drive folder. This settles the two things that cannot be known from here: how the Drive provider behaves on whole-file replacement, and how long a pull of a real notebook takes.
2. **Pull and join** an existing notebook into local storage (read only, so it cannot hurt anything).
3. **Push** this device's own log and blobs.
4. **Sync dialog:** "Choose a Drive folder" in the Sync dialog's words, with the grant explained in one line.
5. Periodic and on-open sync; show the state in the same place the desktop does.

**What the owner needs to do:** try the spike on the phone, and say which Drive account and folder to use (the desktop sees two accounts, one personal and one work).

## Risks

- The Drive provider is not a file system: slow listing and delayed writes are likely. The design copes (a local copy, whole-file writes), but how slow is only known after the spike.
- Two devices writing at the same moment is safe by construction (each owns its file). Two phones with the **same** device identity would not be: a restored backup must get a new device id (check `sync/device_identity.dart` before the bridge exists).
- If the provider proves unusable, the fallback is the folder sync the app already has through GitHub (`sync/git_sync.dart`), which needs no folder access at all.
