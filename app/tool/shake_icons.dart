// Subset the Material icon font that Flutter's own build forgets to subset.
//
// **This is a workaround for an SDK bug, not for anything in this app.**
//
// `MaterialIcons-Regular.otf` is 1,645,184 bytes and ships whole in every
// Windows and Linux release. The app uses a few dozen glyphs; subsetting takes
// it to ~24 KB, a 98.5% reduction, and Flutter is supposed to do it
// automatically.
//
// It does not, and the reason is one pair of quotation marks. In
// `packages/flutter_tools/bin/tool_backend.dart` — the shim CMake calls to run
// the Dart half of a desktop build — the define is written
//
//     '-dTreeShakeIcons="$treeShakeIcons"',
//
// while every sibling define on the surrounding lines is unquoted. The literal
// quotes survive into `flutter assemble`, so the value arrives as `"true"`
// rather than `true`, and `IconTreeShaker` gates on `== 'true'` and stays off.
// The subsetter is never invoked, and the build prints nothing to say so —
// which is why this looked like a dependency defeating tree-shaking rather
// than a build that never attempted it. macOS goes through
// `bin/xcode_backend.dart`, which passes the same define unquoted, so macOS
// releases have always been subsetted correctly.
//
// So: re-run the asset bundling ourselves with the define spelled properly,
// and copy the one font it produces into the built bundle. Everything else in
// the bundle is already correct — this replaces a single file.
//
// Run AFTER `flutter build <platform> --release`. A no-op on macOS.
import 'dart:io';

/// Where the built bundle keeps its assets, per platform.
const _bundleAssets = <String, String>{
  'windows': 'build/windows/x64/runner/Release/data/flutter_assets',
  'linux': 'build/linux/x64/release/bundle/data/flutter_assets',
};

/// The `flutter assemble` target that produces the asset bundle.
const _assembleTarget = <String, String>{
  'windows': 'release_bundle_windows-x64_assets',
  'linux': 'release_bundle_linux-x64_assets',
};

const _targetPlatform = <String, String>{
  'windows': 'windows-x64',
  'linux': 'linux-x64',
};

Future<void> main(List<String> args) async {
  final platform = args.isNotEmpty
      ? args.first
      : Platform.isWindows
          ? 'windows'
          : Platform.isLinux
              ? 'linux'
              : 'macos';

  if (platform == 'macos') {
    stdout.writeln('shake_icons: macOS subsets correctly already — nothing '
        'to do.');
    return;
  }
  final bundleDir = _bundleAssets[platform];
  if (bundleDir == null) {
    stderr.writeln('shake_icons: unknown platform "$platform".');
    exit(2);
  }

  final shipped = File('$bundleDir/fonts/MaterialIcons-Regular.otf');
  if (!shipped.existsSync()) {
    stderr.writeln('shake_icons: no built bundle at ${shipped.path} — run '
        '`flutter build $platform --release` first.');
    exit(1);
  }
  final before = shipped.lengthSync();

  // The stamp is what makes `assemble` skip work it thinks it has already
  // done. Since the previous run produced an UNSHAKEN font with the same
  // inputs, leaving the stamp would make this silently do nothing.
  final stamp = File('build/${_assembleTarget[platform]}.stamp');
  if (stamp.existsSync()) stamp.deleteSync();

  final flutter = Platform.isWindows ? 'flutter.bat' : 'flutter';
  final r = await Process.run(flutter, [
    'assemble',
    '--no-version-check',
    '--output=build',
    '-dTargetPlatform=${_targetPlatform[platform]}',
    '-dBuildMode=release',
    '-dTargetFile=lib/main.dart',
    // The whole point. Unquoted.
    '-dTreeShakeIcons=true',
    '-dTrackWidgetCreation=false',
    '-dDartObfuscation=false',
    _assembleTarget[platform]!,
  ]);
  if (r.exitCode != 0) {
    stderr.writeln('shake_icons: assemble failed:\n${r.stdout}\n${r.stderr}');
    exit(r.exitCode);
  }

  final subset = File('build/flutter_assets/fonts/MaterialIcons-Regular.otf');
  if (!subset.existsSync()) {
    stderr.writeln('shake_icons: assemble produced no font at ${subset.path}.');
    exit(1);
  }
  final after = subset.lengthSync();
  if (after >= before) {
    // Refuse to "fix" anything if the subsetter did not actually run — a
    // same-size copy would look like success in the log and change nothing,
    // which is exactly the failure mode this script exists to end.
    stderr.writeln('shake_icons: the font did not shrink ($before → $after). '
        'The subsetter did not run; the bundle is unchanged.');
    exit(3);
  }
  subset.copySync(shipped.path);
  final saved = before - after;
  stdout.writeln('shake_icons: MaterialIcons-Regular.otf $before → $after '
      'bytes (${(saved / 1024).toStringAsFixed(0)} KB saved).');
}
