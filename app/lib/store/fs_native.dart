/// The desktop half of [fs]: the real filesystem, named exactly as before.
///
/// Deliberately a bare re-export rather than a wrapper. Anything else would be
/// a second implementation of the most consequential code in the app, and the
/// point of this seam is that the desktop build is untouched by it.
library;

export 'dart:io'
    show
        Directory,
        File,
        FileMode,
        FileStat,
        FileSystemEntity,
        FileSystemEntityType,
        FileSystemEvent,
        FileSystemException,
        FileSystemMoveEvent,
        OSError,
        RandomAccessFile;
