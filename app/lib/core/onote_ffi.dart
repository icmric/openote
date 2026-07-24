import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

/// Dart bindings for the Rust core (`rust/onote_core`) over `dart:ffi`.
///
/// Loading is **optional and forgiving**: [instance] returns null if the native
/// library can't be found or opened, and every caller is expected to fall back
/// to the pure-Dart path. This means linking the Rust core can never break the
/// app — with the library present it's used (and shown in the status bar); with
/// it absent the app behaves exactly as the Dart-only build did.
///
/// The C ABI is defined in `rust/onote_core/src/ffi.rs`. Every string the
/// native side returns is owned by us and freed via `onote_core_string_free`.

typedef _VersionNative = Pointer<Utf8> Function();
typedef _MergeNative = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _HashNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _ImportOneNative = Pointer<Utf8> Function(Pointer<Uint8>, IntPtr);
typedef _ImportOne = Pointer<Utf8> Function(Pointer<Uint8>, int);
typedef _FreeNative = Void Function(Pointer<Utf8>);
typedef _Free = void Function(Pointer<Utf8>);

class OnoteCore {
  // The library handle isn't retained: once opened, the OS keeps it mapped for
  // the process lifetime, so the looked-up function pointers stay valid.
  OnoteCore._(DynamicLibrary lib)
      : _version =
            lib.lookupFunction<_VersionNative, _VersionNative>('onote_core_version'),
        _merge =
            lib.lookupFunction<_MergeNative, _MergeNative>('onote_core_merge'),
        _hash = lib.lookupFunction<_HashNative, _HashNative>('onote_core_page_hash'),
        _importOne =
            lib.lookupFunction<_ImportOneNative, _ImportOne>('onote_core_import_one'),
        _free = lib.lookupFunction<_FreeNative, _Free>('onote_core_string_free');

  final _VersionNative _version;
  final _MergeNative _merge;
  final _HashNative _hash;
  final _ImportOne _importOne;
  final _Free _free;

  static bool _tried = false;
  static OnoteCore? _instance;

  /// The loaded core, or null if the native library isn't available. Loading
  /// is attempted once; failures are cached so we don't retry every call.
  static OnoteCore? get instance {
    if (!_tried) {
      _tried = true;
      _instance = _tryLoad();
    }
    return _instance;
  }

  /// True when the Rust core is linked and usable.
  static bool get available => instance != null;

  static OnoteCore? _tryLoad() {
    for (final candidate in _candidatePaths()) {
      try {
        final lib = DynamicLibrary.open(candidate);
        final core = OnoteCore._(lib);
        // Prove the symbols resolve and a call round-trips before committing.
        if (core.version().isNotEmpty) return core;
      } catch (_) {
        // Try the next location.
      }
    }
    return null;
  }

  static String get _libName {
    if (Platform.isWindows) return 'onote_core.dll';
    if (Platform.isMacOS) return 'libonote_core.dylib';
    return 'libonote_core.so';
  }

  /// Where to look for the library, most-specific first:
  /// 1. next to the executable (where a packaged build bundles it),
  /// 2. the crate's release build output (developer convenience from `app/`),
  /// 3. the bare name (lets the OS loader search its default paths).
  static List<String> _candidatePaths() {
    final name = _libName;
    final paths = <String>[];
    try {
      final exeDir = p.dirname(Platform.resolvedExecutable);
      paths.add(p.join(exeDir, name));
    } catch (_) {}
    paths
      ..add(p.join('..', 'rust', 'onote_core', 'target', 'release', name))
      ..add(p.join('rust', 'onote_core', 'target', 'release', name))
      ..add(name);
    return paths;
  }

  /// Core version string (e.g. "0.1.0").
  String version() {
    final ptr = _version();
    return _takeString(ptr);
  }

  /// Conflict-free merge of two page-mirror JSON documents.
  String mergeMirrors(String local, String remote) {
    final lp = local.toNativeUtf8();
    final rp = remote.toNativeUtf8();
    try {
      return _takeString(_merge(lp, rp));
    } finally {
      malloc
        ..free(lp)
        ..free(rp);
    }
  }

  /// Stable content hash of a page mirror (empty on malformed input).
  String pageHash(String mirrorJson) {
    final mp = mirrorJson.toNativeUtf8();
    try {
      return _takeString(_hash(mp));
    } finally {
      malloc.free(mp);
    }
  }

  /// Import a OneNote `.one` section file. Returns the parser's JSON string
  /// (`{ok, error?, pages:[...]}`); see the Rust `onenote` module.
  String importOne(List<int> bytes) {
    final ptr = malloc.allocate<Uint8>(bytes.length);
    try {
      ptr.asTypedList(bytes.length).setAll(0, bytes);
      return _takeString(_importOne(ptr, bytes.length));
    } finally {
      malloc.free(ptr);
    }
  }

  /// Copy a native string into Dart and free the native allocation.
  String _takeString(Pointer<Utf8> ptr) {
    if (ptr == nullptr) return '';
    try {
      return ptr.toDartString();
    } finally {
      _free(ptr);
    }
  }
}
