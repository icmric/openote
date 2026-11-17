# Android (and tablets): where we are, and syncing with Google Drive

Written 17 November 2026, v1.0.3 branch. Android is **not** part of the v1.0.3 release; this is the
groundwork and the plan, so the next steps start from what is true.

## Where it stands

| Piece | State |
|---|---|
| Android project (`app/android/`) | Tracked in git. Gradle 8.14 and Android Gradle Plugin 8.11: AGP 9 needs Gradle 9, which the clipboard plugin's build step (`irondash_engine_context`, cargokit) cannot run on. `kotlin.jvm.target.validation.mode=warning` because `flutter_js` has mismatched Java and Kotlin targets |
| Rust libraries | `bash app/tool/build_android_libs.sh` builds `onote_core` and `onote_text` for arm64 (or `x86_64` for an emulator), with 16 KB page alignment (`-Wl,-z,max-page-size=16384`, checked: LOAD alignment 0x4000). Output goes to `android/app/src/main/jniLibs/<abi>/`, **not in git**: it must be run once on each machine that builds the app |
| Loading | `onote_core` already falls back to the bare library name, which Android resolves. `onote_text` gained an Android branch |
| Phone layout | Below 600 px wide (`isPhoneWidth`, `ui/phone_shell.dart`): slim top bar, the page filling the screen, the tools strip and four icon tabs at the foot (`CommandBar._phoneBar`), the navigator as a drawer (notebook, section, page), everything inside the safe area. Wider windows and tablets keep the desktop layout |
| Icon | The Openote icon is generated for Android, but as the square icon on white. **Open:** an adaptive icon, purple background with the ring as foreground |
| Release build | `flutter build apk --release --target-platform android-arm64` works (about 104 MB), signed with the debug key, fine for sideloading to test |

## Open, before anyone but the owner uses it

- **Application id** is still `com.example.openote`. Make it `org.openote.openote` (as Linux and macOS use) before any release: it cannot be changed after one, and it means moving `MainActivity`.
- **Plugins not yet audited on a device:** `media_kit` (video), `super_clipboard`, `printing`, `desktop_drop`, `pdfrx`. Anything that does not work is to be greyed with "Not yet", as the browser demo does, not hidden. The design canvas shows Video and Print greyed in the phone's Insert sheet; **the app does not do this yet**.
- **Missing on the phone:** Recent (the drawer has no Home view), the Export menu (the desktop has it in the trailing toolbar, which the phone bar drops), search across notebooks, long-press as right-click on every context menu, and finger-versus-pen behaviour as designed (finger scrolls, stylus draws).
- **Debug-build warning** "not 16 KB-compatible" can still name plugin libraries; ours are aligned.
- **Tablet** layout is designed (`Tablet.dc.html` on the canvas) and not built: larger targets, two toolbar bands, portrait folding to a rail and a sheet.

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
