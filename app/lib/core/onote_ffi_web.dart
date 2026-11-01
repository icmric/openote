/// The web half of [OnoteCore]: the core is absent, permanently.
///
/// `onote_ffi.dart` promises that [OnoteCore.instance] may be null and that
/// *"every caller is expected to fall back to the pure-Dart path"*. On the web
/// that is not a degraded mode, it is the only mode — there is no shared
/// library to load — so this file says null once and the whole app takes the
/// path it already takes on any desktop built without the Rust core.
///
/// The instance methods exist to satisfy the type checker and nothing more.
/// Every one of them is unreachable: the only way to hold an [OnoteCore] is
/// [OnoteCore.instance], which is null here. They throw rather than returning
/// a plausible-looking empty string, because a silent wrong answer from a
/// merge or a content hash is the one failure this class must not invent.
library;

class OnoteCore {
  OnoteCore._();

  /// Always null on the web. See the library comment.
  static OnoteCore? get instance => null;

  /// Always false on the web, which is what the status bar reports.
  static bool get available => false;

  /// Never set, because nothing ever loads.
  static String? loadedFrom;

  ({DateTime built, String commit})? get buildId => null;

  String version() => throw _absent;
  String mergeMirrors(String local, String remote) => throw _absent;
  String pageHash(String mirrorJson) => throw _absent;
  String repairFieldCodes(String text) => throw _absent;
  String importOne(List<int> bytes) => throw _absent;
  String importOnepkg(List<int> bytes) => throw _absent;

  static UnsupportedError get _absent => UnsupportedError(
      'The Rust core is not available in a web build; callers must check '
      'OnoteCore.instance for null and use the pure-Dart path.');
}
