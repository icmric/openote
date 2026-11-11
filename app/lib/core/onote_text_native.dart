/// The `dart:ffi` half of [OnoteText]. See `onote_text.dart`.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import 'off_thread.dart';
import 'onote_text.dart';

typedef _CheckNative = Pointer<Utf8> Function(Pointer<Utf8>, Int32, Uint32);
typedef _Check = Pointer<Utf8> Function(Pointer<Utf8>, int, int);
typedef _SuggestNative = Pointer<Utf8> Function(Pointer<Utf8>, Int32, Int32);
typedef _Suggest = Pointer<Utf8> Function(Pointer<Utf8>, int, int);
typedef _AutoNative = Pointer<Utf8> Function(Pointer<Utf8>, Int32);
typedef _Auto = Pointer<Utf8> Function(Pointer<Utf8>, int);
typedef _FreeNative = Void Function(Pointer<Utf8>);
typedef _Free = void Function(Pointer<Utf8>);

/// Everything one call needs, looked up from an already-open library. Built
/// inside whichever isolate makes the call (a handle is cheap to look up and
/// cannot be sent between isolates).
class _Fns {
  _Fns(DynamicLibrary lib)
      : check = lib.lookupFunction<_CheckNative, _Check>('onote_text_check'),
        suggest =
            lib.lookupFunction<_SuggestNative, _Suggest>('onote_text_suggest'),
        autocorrect =
            lib.lookupFunction<_AutoNative, _Auto>('onote_text_autocorrect'),
        free = lib.lookupFunction<_FreeNative, _Free>('onote_text_free');

  final _Check check;
  final _Suggest suggest;
  final _Auto autocorrect;
  final _Free free;

  /// Call a native function that takes one string and returns an owned one,
  /// copying the result out and freeing it, so no pointer escapes.
  String _str(String arg, Pointer<Utf8> Function(Pointer<Utf8>) call) {
    final a = arg.toNativeUtf8();
    try {
      final r = call(a);
      if (r == nullptr) return '';
      try {
        return r.toDartString();
      } finally {
        free(r);
      }
    } finally {
      malloc.free(a);
    }
  }
}

class OnoteText {
  OnoteText._();

  static bool _resolved = false;
  static String? _path;

  /// The library that will be used, found once; null when there is none. The
  /// path (not a handle) is what crosses to the worker isolates.
  static String? get libraryPath {
    if (!_resolved) {
      _resolved = true;
      _path = _find();
    }
    return _path;
  }

  static bool get available => libraryPath != null;

  /// A path for tests to force (a library built outside the usual places).
  static String? overridePath;

  static String get _libName {
    if (Platform.isWindows) return 'onote_text.dll';
    if (Platform.isMacOS) return 'libonote_text.dylib';
    return 'libonote_text.so';
  }

  static String? _find() {
    final forced = overridePath ?? Platform.environment['ONOTE_TEXT_LIB'];
    final candidates = <String>[
      if (forced != null) forced,
      // Where a packaged build bundles it.
      p.join(p.dirname(Platform.resolvedExecutable), _libName),
      // A developer build, run from `app/` or from the repository root.
      p.join('..', 'rust', 'onote_text', 'target', 'release', _libName),
      p.join('rust', 'onote_text', 'target', 'release', _libName),
    ];
    // The newest wins, so a rebuild is picked up without a copy (the same
    // stale-library trap onote_core's loader documents).
    final existing = [
      for (final c in candidates)
        if (File(c).existsSync()) File(c)
    ]..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    for (final f in existing) {
      try {
        final fns = _Fns(DynamicLibrary.open(f.path));
        // Prove it answers before trusting it.
        fns._str('', (a) => fns.check(a, 0, 0));
        return f.path;
      } catch (_) {
        // Try the next.
      }
    }
    return null;
  }

  /// Findings for [text], computed off the UI thread (the first call loads a
  /// dictionary and takes about a second).
  ///
  /// [text] must already have everything that is not prose blanked to spaces
  /// of the same length (see `WritingChecker.proseOnly`).
  static Future<List<TextFinding>> check(
      String text, EnglishDialect dialect, int want) async {
    final path = libraryPath;
    if (path == null || want == 0 || text.trim().isEmpty) return const [];
    final code = dialect.code;
    try {
      final json = await offThread(() {
        final fns = _Fns(DynamicLibrary.open(path));
        final r = fns._str(text, (a) => fns.check(a, code, want));
        return r;
      });
      final list = jsonDecode(json) as List;
      return [
        for (final j in list) TextFinding.fromJson(j as Map<String, dynamic>)
      ];
    } catch (_) {
      return const []; // a broken checker stays quiet
    }
  }

  static bool _warm = false;
  static _Fns? _uiFns;

  /// Load the dictionary and grammar rules in the background so that the first
  /// real use does not stall. The native engine is one per process, so once
  /// this finishes, [autocorrectNow] is a microsecond lookup on any thread.
  static Future<void> warmUp(EnglishDialect dialect) async {
    if (_warm) return;
    final path = libraryPath;
    if (path == null) return;
    final code = dialect.code;
    try {
      await offThread(() {
        final fns = _Fns(DynamicLibrary.open(path));
        fns._str('warm up', (a) => fns.check(a, code, kWantSpelling));
        // `autocorrect` builds nothing extra, but touching it proves the
        // symbol resolves before the editor depends on it.
        fns._str('teh', (a) => fns.autocorrect(a, code));
        return 0;
      });
      _warm = true;
    } catch (_) {
      // Stay cold: autocorrectNow keeps answering null.
    }
  }

  /// The sure correction for [word], answered at once on the calling isolate,
  /// or null. **Only once [warmUp] has finished**: the first call into the
  /// engine takes about a second, and a keystroke must never wait for that.
  static String? autocorrectNow(String word, EnglishDialect dialect) {
    final path = libraryPath;
    if (!_warm || path == null || word.isEmpty) return null;
    try {
      final fns = _uiFns ??= _Fns(DynamicLibrary.open(path));
      final r = fns._str(word, (a) => fns.autocorrect(a, dialect.code));
      return r.isEmpty ? null : r;
    } catch (_) {
      return null;
    }
  }

  static Future<List<String>> suggest(String word, EnglishDialect dialect,
      {int max = 5}) async {
    final path = libraryPath;
    if (path == null || word.isEmpty) return const [];
    final code = dialect.code;
    try {
      final json = await offThread(() {
        final fns = _Fns(DynamicLibrary.open(path));
        return fns._str(word, (a) => fns.suggest(a, code, max));
      });
      return [for (final s in jsonDecode(json) as List) s as String];
    } catch (_) {
      return const [];
    }
  }

  /// The correction to make silently for [word], or null to leave it.
  static Future<String?> autocorrect(String word, EnglishDialect dialect) async {
    final path = libraryPath;
    if (path == null || word.isEmpty) return null;
    final code = dialect.code;
    try {
      final r = await offThread(() {
        final fns = _Fns(DynamicLibrary.open(path));
        return fns._str(word, (a) => fns.autocorrect(a, code));
      });
      return r.isEmpty ? null : r;
    } catch (_) {
      return null;
    }
  }
}
