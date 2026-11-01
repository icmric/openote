/// The browser answers: no to both, and the second is the permanent one.
///
/// `dart:io` compiles in a web build and throws when called, so these are not
/// "we chose not to" — a `Directory` here is a thrown `UnsupportedError`.
///
/// Folder watching is the one that will still be false if that ever changes.
/// The File System Access API can hand a page a real read/write handle to a
/// file or directory the user picks, and the handle can be kept in IndexedDB
/// and re-acquired later. What it cannot do, on any engine, is notify a page
/// that a folder changed underneath it — and that is the whole mechanism
/// Openote's sync is built on.
library;

const bool platformWorkspaceIsOnDisk = false;

const bool platformWorkspaceCanWatchFolders = false;
