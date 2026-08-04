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
        _importOnepkg = lib.lookupFunction<_ImportOneNative, _ImportOne>(
            'onote_core_import_onepkg'),
        _repairFields = lib.lookupFunction<_HashNative, _HashNative>(
            'onote_core_repair_field_codes'),
        _free = lib.lookupFunction<_FreeNative, _Free>('onote_core_string_free');

  final _VersionNative _version;
  final _MergeNative _merge;
  final _HashNative _hash;
  final _ImportOne _importOne;
  final _ImportOne _importOnepkg;
  final _HashNative _repairFields;
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

  /// Absolute path of the library that actually loaded (diagnostics / staleness
  /// checks). Null until a successful load.
  static String? loadedFrom;

  static OnoteCore? _tryLoad() {
    // Prefer the NEWEST existing candidate by mtime. In development the app
    // runs an old copy next to the exe while `cargo build` refreshes
    // target/release; picking the newest means a rebuild is picked up without a
    // manual copy — the recurring "tested a stale DLL" trap. In a shipped build
    // only the exe-dir library exists, so this is a no-op there.
    final existing = _candidatePaths()
        .map((c) => File(c))
        .where((f) => f.existsSync())
        .toList()
      ..sort((a, b) =>
          b.statSync().modified.compareTo(a.statSync().modified));
    // Fall back to the bare name last (lets the OS loader search its paths).
    final ordered = [...existing.map((f) => f.path), _libName];
    for (final candidate in ordered) {
      try {
        final lib = DynamicLibrary.open(candidate);
        final core = OnoteCore._(lib);
        // Prove the symbols resolve and a call round-trips before committing.
        if (core.version().isNotEmpty) {
          loadedFrom = candidate;
          return core;
        }
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

  /// Locations to look for the library:
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
      ..add(p.join('rust', 'onote_core', 'target', 'release', name));
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

  /// Turn Word/OneNote `HYPERLINK` field codes in already-imported text into
  /// `[label](url)`, stripping every leftover field marker.
  ///
  /// Fixing the importer does nothing for notes imported before the fix — by
  /// then the `﷟HYPERLINK "…"` junk is stored user data. Callers should check
  /// [textNeedsFieldRepair] first: it is a substring test on text already in
  /// memory, so clean pages pay nothing.
  String repairFieldCodes(String text) {
    final tp = text.toNativeUtf8();
    try {
      return _takeString(_repairFields(tp));
    } finally {
      malloc.free(tp);
    }
  }

  /// Import a OneNote `.one` section file. Returns the parser's JSON string
  /// (`{ok, error?, pages:[...]}`); see the Rust `onenote` module.
  String importOne(List<int> bytes) => _importBytes(_importOne, bytes);

  /// Import a OneNote `.onepkg` notebook package (a cabinet of `.one`
  /// sections). Returns `{ok, error?, sections:[{name, group?, section}]}`;
  /// see the Rust `onepkg` module.
  String importOnepkg(List<int> bytes) => _importBytes(_importOnepkg, bytes);

  String _importBytes(_ImportOne f, List<int> bytes) {
    final ptr = malloc.allocate<Uint8>(bytes.length);
    try {
      ptr.asTypedList(bytes.length).setAll(0, bytes);
      return _takeString(f(ptr, bytes.length));
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
bool textNeedsFieldRepair(String s) =>
    s.contains('\uFDDF') ||
    s.contains('\uFDDE') ||
    s.contains('\u0013') ||
    s.contains('\u0014') ||
    s.contains('\u0015') ||
    s.contains('\$');
