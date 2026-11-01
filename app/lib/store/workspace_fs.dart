/// Whether there is a disk under the workspace, and whether a folder on it
/// can be watched.
///
/// Two facts rather than one, because they fail apart. A browser *can*, on
/// some engines, be handed a file to read and write — so "no filesystem" is
/// too strong a thing to say in general. What no browser can do is tell you
/// that a folder changed, and `sync/folder_watch.dart` is built on exactly
/// that:
///
/// ```dart
/// _sub = opsDir.watch(recursive: false).listen(_onEvent, …);
/// ```
///
/// which is why the sync model does not port even where file access would.
/// Keeping the two apart means a later build that gains real file handles can
/// flip one without claiming the other.
library;

import 'workspace_fs_native.dart'
    if (dart.library.js_interop) 'workspace_fs_web.dart';

/// True when `Directory` and `File` reach a real filesystem.
///
/// False in the browser demo, where the whole workspace lives in SQLite's
/// in-memory VFS and nothing is written anywhere a browser could keep it.
bool get workspaceIsOnDisk => platformWorkspaceIsOnDisk;

/// True when a directory can be watched for changes made by something else.
bool get workspaceCanWatchFolders => platformWorkspaceCanWatchFolders;
