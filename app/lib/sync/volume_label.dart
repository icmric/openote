/// The volume label for a drive letter, where the platform has one.
///
/// `dart:ffi` is a hard compile error on the web, so the halves are split the
/// way `free_space.dart` established and nothing imports them directly.
library;

export 'volume_label_native.dart'
    if (dart.library.js_interop) 'volume_label_web.dart';
