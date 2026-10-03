/// Dart bindings for the Rust core (`rust/onote_core`) over `dart:ffi`.
///
/// Loading is **optional and forgiving**: [OnoteCore.instance] returns null if
/// the native library can't be found or opened, and every caller is expected to
/// fall back to the pure-Dart path. This means linking the Rust core can never
/// break the app — with the library present it's used (and shown in the status
/// bar); with it absent the app behaves exactly as the Dart-only build did.
///
/// The C ABI is defined in `rust/onote_core/src/ffi.rs`. Every string the
/// native side returns is owned by us and freed via `onote_core_string_free`.
///
/// **The web gets "absent" for free, and that is why this split is cheap.**
/// `dart:ffi` is a hard compile error in a browser build, so the bindings live
/// in `onote_ffi_native.dart` and `onote_ffi_web.dart` answers null from
/// [OnoteCore.instance] — the state the paragraph above already promises every
/// caller handles. No caller learns a new case.
library;

export 'onote_ffi_native.dart'
    if (dart.library.js_interop) 'onote_ffi_web.dart';

/// Does this text carry anything the import repair can fix?
///
/// A cheap substring test, so the repair path costs nothing on the 99.9% of
/// blocks that were never near a `.one` file. U+FDDF is what OneNote writes;
/// U+0013..U+0015 are Word's classic field begin/separator/end, which survive a
/// paste from Word.
///
/// `\$` is here for the second repair: a symbol from OneNote's palette was
/// imported wrapped in `\$…\$`, which reads correctly until you click into the
/// box. A page containing no dollar at all — almost all of them — still costs
/// one substring scan and nothing else, and the repair itself leaves real
/// equations alone.
///
/// Pure Dart, so it stays in the shared file: the test for "does this page
/// need repairing" is worth having on every platform even where the repair
/// itself cannot run.
bool textNeedsFieldRepair(String s) =>
    s.contains('﷟') ||
    s.contains('﷞') ||
    s.contains('\u0013') ||
    s.contains('\u0014') ||
    s.contains('\u0015') ||
    s.contains('\$');
