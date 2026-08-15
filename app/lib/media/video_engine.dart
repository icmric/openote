/// The video engine, fetched when it is first needed rather than shipped.
///
/// **Why.** Measured on the v0.7.1 Windows Release bundle, libmpv and ANGLE
/// are 48,580,342 B of 97,831,741 B — half the download, carried by every
/// student whether or not they ever put a lecture in a notebook. They touch no
/// byte of anybody's notes: a video lives in `<notebook>.onotebook/media/` as
/// an ordinary file (see store/media_store.dart) and this is only the code
/// that decodes it. So the bytes stay on the student's disk and the *player*
/// becomes a download. See tool/split_video_engine.dart for the build half.
///
/// **What must never happen.** A student on a train with no signal opens a
/// notebook with a lecture on page 4. The notebook opens, the page renders,
/// the card is there with its name and its size, "Open in your usual player"
/// and "Save a copy…" both work, and the only thing missing is the button
/// that plays it *in the page*. Nothing here may make a video look lost, and
/// nothing here touches `media/` — the reclamation sweep in
/// store/media_gc.dart reads page content and op logs, neither of which this
/// file can reach.
///
/// **Integrity is a hash, not a length.** Every file is pinned by its
/// SHA-256. A truncated download and a corrupted one have the same length far
/// too often for a length to be a check — commit 435b2bd replaced exactly that
/// mistake in the notebook mover, and an engine DLL that half-arrived is a
/// crash inside a decoder rather than an error anyone can read.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';

import '../store/notebook_writer.dart' show sha256Hex;
import '../update/app_update.dart' show kAppVersion;

/// One file of the engine, pinned by content.
class EngineFile {
  const EngineFile(this.name, this.bytes, this.sha256);

  /// The file name as it must land on disk. Windows resolves an engine
  /// library by this exact name, so it is not cosmetic.
  final String name;
  final int bytes;
  final String sha256;
}

/// What went wrong, in the two halves the UI needs: a sentence for the card
/// and a technical line for **Details (advanced)**.
class EngineInstallFailure implements Exception {
  const EngineInstallFailure(this.message, this.details);

  /// Plain words. No DLL name, no URL, no exception class.
  final String message;

  /// The line behind the fold.
  final String details;

  @override
  String toString() => '$message ($details)';
}

/// Progress of a download-and-check, 0.0 → 1.0.
typedef EngineProgress = void Function(double fraction, String what);

abstract final class VideoEngine {
  /// The identity of this exact set of libraries. It is part of the directory
  /// name, so upgrading media_kit installs beside the old engine instead of
  /// half-overwriting it — a mixed set of ANGLE DLLs is a crash with no
  /// message, and there is no way to tell one from a whole set by looking.
  static const id = 'windows-x64-mpv-20230924-angle-1.0.1';

  /// Whether this platform's engine is split out at all.
  ///
  /// Windows only. Linux gets libmpv from the distribution — `mpv-libs` on
  /// Fedora, `libmpv2` on Debian — which is the same "on demand" property
  /// arrived at through the package manager, and the .deb and .rpm already
  /// declare it. macOS bundles an xcframework by a mechanism this does not
  /// touch, so there the engine is present exactly as before.
  static bool get splitOnThisPlatform => Platform.isWindows;

  /// The seven files, in load order: each one's dependencies come before it.
  ///
  /// Sizes and hashes were taken from the 0.7.1 Release bundle, which is the
  /// same set `media_kit_libs_windows_video` 1.0.11 pins by MD5 in its own
  /// CMakeLists — so this list is stable for as long as that version is.
  static List<EngineFile> get files => _debugFiles ?? pinnedFiles;
  static List<EngineFile>? _debugFiles;

  static const pinnedFiles = <EngineFile>[
    EngineFile('zlib.dll', 203264,
        '82d5bf175cf882ac9afc1558b416e674606d055966bc09529076b28a498fc0e4'),
    EngineFile('d3dcompiler_47.dll', 4891080,
        '5653bc7b0e2701561464ef36602ff6171c96bffe96e4c3597359cd7addcba88a'),
    EngineFile('vulkan-1.dll', 872776,
        '3be9a95dd9019aa1aca47ade26f5c1c7c0047f3cf6f633d586c9ec0d3b459566'),
    EngineFile('vk_swiftshader.dll', 4808008,
        '4f33eea716491972cb1ad123a78acef485f852581130d3f3a98a1981009004f2'),
    EngineFile('libGLESv2.dll', 7414088,
        '620bb6e38d7ed6c760a0cf4a8eb6a8f64b259b96ff286551cd32cefc6c35ca39'),
    EngineFile('libEGL.dll', 472904,
        'b2590bd0692f0381fc45c20bf1c7f7f713c9ea19c7ea6bab62efdd1fadc4eaac'),
    EngineFile('libmpv-2.dll', 29764622,
        'd5f0694b08c124e785d858d00082f3e3b158dd9138bfc48c0382bf1eb443a5fc'),
  ];

  /// What the student is told the download costs. The compressed archive is
  /// smaller than the sum below; this is deliberately the *honest* number for
  /// what lands on their disk, because that is what they will see if they go
  /// looking for it later.
  static int get installedBytes =>
      files.fold(0, (sum, f) => sum + f.bytes);

  /// Where a downloaded engine lives, once [prepare] has resolved it.
  ///
  /// Application support, NOT the workspace and NOT any notebook. Anything
  /// under the workspace root is in reach of the leftovers scan
  /// (`AppState.findOrphanFiles`) and of every backup and sync mechanism the
  /// app has; a redownloadable cache belongs in none of them.
  static Directory? _root;

  static Directory get _dir => Directory('${_root!.path}/video-engine/$id');

  /// The file written LAST, after every hash has been checked. Its presence is
  /// the record that verification happened, which is why a second launch does
  /// not re-read 48 MB to find out what it already knows.
  static File get _stamp => File('${_dir.path}/installed');

  /// Resolve the cache location. Safe to call more than once; never throws —
  /// a machine whose support directory cannot be created simply has no engine
  /// available, which is a card, not a crash.
  static Future<void> prepare() async {
    if (_root != null) return;
    try {
      _root = await getApplicationSupportDirectory();
    } catch (_) {
      _root = null;
    }
  }

  /// True when a complete, previously verified engine is on this machine.
  ///
  /// Presence of every file is re-checked because a user can delete one by
  /// hand and the stamp would still be there; the hashes are not, because
  /// re-hashing 48 MB on every launch would cost more than the whole startup
  /// budget to answer a question the stamp already answers.
  static bool get isInstalled {
    if (_root == null) return false;
    if (!_stamp.existsSync()) return false;
    for (final f in files) {
      final file = File('${_dir.path}/${f.name}');
      if (!file.existsSync()) return false;
    }
    return true;
  }

  /// Put the installed engine on the loader's path and pull it in.
  ///
  /// Returns false rather than throwing: every caller's answer to "the engine
  /// did not load" is the same card, and a throw on a build path would be a
  /// red screen where that card belongs.
  ///
  /// The plugin's imports of these libraries are delay-loaded (see
  /// tool/split_video_engine.dart), so the loader has not looked for them
  /// before now. Loading each by ABSOLUTE path registers it under its base
  /// name, which is what the deferred `LoadLibrary("libmpv-2.dll")` inside the
  /// plugin then finds.
  static bool load() {
    if (!isInstalled) return false;
    try {
      _addToDllSearchPath(_dir.path);
      for (final f in files) {
        DynamicLibrary.open('${_dir.path}/${f.name}');
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// `SetDllDirectoryW`. Belt and braces beside the explicit opens above: a
  /// library that loads a *sibling* we have not named — ANGLE picks its
  /// backend at run time — has to be able to find it too.
  static void _addToDllSearchPath(String dir) {
    if (!Platform.isWindows) return;
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final setDllDirectory = kernel32.lookupFunction<
        Int32 Function(Pointer<Utf16>),
        int Function(Pointer<Utf16>)>('SetDllDirectoryW');
    final p = dir.toNativeUtf16();
    try {
      setDllDirectory(p);
    } finally {
      calloc.free(p);
    }
  }

  /// Where the archive comes from. A release asset of the running version, so
  /// an old build keeps working against the release it shipped with.
  ///
  /// The name deliberately does NOT end in `-setup.exe`: the in-app updater
  /// picks the Windows installer out of a release by exactly that suffix
  /// (`app_update.dart`), and an extra asset that matched would hand a student
  /// an engine archive to run as an installer.
  static String get downloadUrl =>
      'https://github.com/icmric/openote/releases/download/v$kAppVersion/'
      '$assetName';

  /// Kept separate from [id]: the id names the exact library set and lands in
  /// a directory name, while this is what a human sees in a release's asset
  /// list. `.github/workflows/release.yml` builds a file of exactly this name.
  static String get assetName =>
      'openote-$kAppVersion-video-engine-windows-x64.zip';

  /// Fetch, check and install. Throws [EngineInstallFailure] and nothing else.
  ///
  /// [fetch] is the download, injected so the whole of this can be tested
  /// without a network: it reports bytes as they arrive and completes with the
  /// archive.
  static Future<void> install({
    required Future<Uint8List> Function(EngineProgress onProgress) fetch,
    EngineProgress? onProgress,
  }) async {
    await prepare();
    if (_root == null) {
      throw const EngineInstallFailure(
        'Openote could not find anywhere on this computer to keep the video '
        'player.',
        'application support directory unavailable',
      );
    }
    void report(double f, String what) => onProgress?.call(f, what);

    // Everything lands here first. A download interrupted at 90% must leave
    // NOTHING that a later launch could mistake for an engine — half an
    // ANGLE set is a crash inside a driver, with no message and no clue.
    final partial = Directory('${_dir.path}.partial');
    _deleteQuietly(partial);

    final Uint8List archive;
    try {
      archive = await fetch((f, what) => report(f * 0.8, what));
    } catch (e) {
      throw EngineInstallFailure(
        'The video player did not finish downloading. Check your connection '
        'and try again — nothing on this computer was changed.',
        'download failed: $e',
      );
    }

    try {
      partial.createSync(recursive: true);
      report(0.85, 'Checking the download');
      final zip = ZipDecoder().decodeBytes(archive);
      for (final want in files) {
        final entry = zip.files.where((f) => _baseName(f.name) == want.name);
        if (entry.isEmpty) {
          throw EngineInstallFailure(
            'The video player that arrived is not the one Openote expected. '
            'Nothing on this computer was changed.',
            'archive is missing ${want.name}',
          );
        }
        final bytes = Uint8List.fromList(
            entry.first.content as List<int>);
        // The hash, not the length. Two different 4,891,080-byte files are
        // exactly the case a length check waves through.
        final got = sha256Hex(bytes);
        if (got != want.sha256) {
          throw EngineInstallFailure(
            'The video player that arrived did not check out, so Openote has '
            'not installed it. Nothing on this computer was changed.',
            'sha-256 mismatch on ${want.name}: expected ${want.sha256}, '
                'got $got',
          );
        }
        File('${partial.path}/${want.name}').writeAsBytesSync(bytes);
      }

      report(0.98, 'Finishing');
      // The stamp goes in BEFORE the rename, so the directory either appears
      // complete-and-verified or does not appear at all. There is no moment
      // at which a crash leaves a directory that `isInstalled` believes.
      File('${partial.path}/installed').writeAsStringSync(id);
      _deleteQuietly(_dir);
      partial.renameSync(_dir.path);
      report(1.0, 'Done');
    } on EngineInstallFailure {
      _deleteQuietly(partial);
      rethrow;
    } catch (e) {
      _deleteQuietly(partial);
      throw EngineInstallFailure(
        'Openote could not save the video player. There may not be enough '
        'room on this computer. Nothing else was changed.',
        'install failed: $e',
      );
    }
  }

  /// The real download. Separated from [install] so every check above can be
  /// tested without a network, and so this stays the only place a URL is
  /// opened.
  static Future<Uint8List> networkFetch(EngineProgress onProgress) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.getUrl(Uri.parse(downloadUrl));
      req.headers.set(HttpHeaders.userAgentHeader, 'openote/$kAppVersion');
      final res = await req.close();
      if (res.statusCode != 200) {
        throw 'the download server answered ${res.statusCode} for $assetName';
      }
      final total = res.contentLength;
      final out = BytesBuilder(copy: false);
      await for (final chunk in res) {
        out.add(chunk);
        if (total > 0) {
          onProgress(out.length / total, 'Getting the video player');
        }
      }
      // Every file is hashed after this anyway, so this check is not the
      // integrity check — it is what lets the message say "your connection"
      // instead of "the file was wrong", which are different problems with
      // different answers.
      if (total > 0 && out.length != total) {
        throw 'the connection ended after ${out.length} of $total bytes';
      }
      return out.takeBytes();
    } finally {
      client.close();
    }
  }

  static String _baseName(String path) =>
      path.split(RegExp(r'[\\/]')).last;

  static void _deleteQuietly(Directory d) {
    try {
      if (d.existsSync()) d.deleteSync(recursive: true);
    } catch (_) {}
  }

  /// Point the cache at a temporary directory, for tests. Also the hook the
  /// negative-control test uses to assert a page with a video still opens with
  /// no engine anywhere on the machine.
  static void debugSetRoot(Directory? root) => _root = root;

  /// Stand in a small manifest, for tests. The real one names 46 MB of DLLs
  /// that are deliberately not in the repo, so without this the only paths a
  /// test could reach are the refusals — and the path that matters most is
  /// the one where a download arrives whole and is accepted.
  static void debugSetFiles(List<EngineFile>? files) => _debugFiles = files;
}
