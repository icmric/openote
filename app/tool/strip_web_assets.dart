// Stop shipping web-only assets inside desktop builds.
//
// **The problem.** A Flutter package declares its assets once, for every
// platform. Several of ours ship browser payloads that no desktop build can
// execute and that nothing on desktop ever loads, and they are not small:
//
//   media_kit/assets/web/hls1.4.10.js   374,690 B   HLS streaming, browsers only
//   wakelock_plus/assets/no_sleep.js     13,669 B   a browser wake-lock shim
//
// pdfrx has the same problem at 4 MB and ships its own remover
// (`dart run pdfrx:remove_wasm_modules`) — run that too; this deliberately
// does not duplicate it.
//
// **The mechanism**, which is pdfrx's own: comment out the `assets:` entry in
// the package's pubspec inside the pub cache, so the asset never enters
// `AssetManifest.bin`. Mutating the cache is not elegant, but the alternative
// — deleting from the built bundle afterwards — leaves the manifest pointing
// at a file that is not there, and it has to be repeated for every packaging
// path rather than once before the build.
//
// Idempotent, reversible (`--revert`), and safe to run when a package is
// absent. `flutter pub get` does NOT undo it, so run it once after `pub get`
// and before `flutter build`.
import 'dart:convert';
import 'dart:io';

/// Package → the exact asset line to comment out, as it appears in that
/// package's pubspec. Matched literally: a package that changes its
/// declaration should fail loudly (reported as "not found") rather than
/// silently stop saving anything.
const _targets = <String, String>{
  'media_kit': '- assets/web/',
  'wakelock_plus': '- packages/wakelock_plus/assets/no_sleep.js',
};

void main(List<String> args) {
  final revert = args.contains('--revert');
  final config = File('.dart_tool/package_config.json');
  if (!config.existsSync()) {
    stderr.writeln('strip_web_assets: no .dart_tool/package_config.json — '
        'run `flutter pub get` first.');
    exit(1);
  }
  final packages = (jsonDecode(config.readAsStringSync())
      as Map<String, dynamic>)['packages'] as List;

  var changed = 0;
  for (final entry in _targets.entries) {
    final pkg = packages.cast<Map<String, dynamic>>().where(
        (p) => p['name'] == entry.key).firstOrNull;
    if (pkg == null) {
      stdout.writeln('strip_web_assets: ${entry.key} not in this project — '
          'skipped.');
      continue;
    }
    // rootUri is relative to .dart_tool/ and is a file: URI.
    final root = Directory.fromUri(
        config.parent.uri.resolve(pkg['rootUri'] as String));
    final pubspec = File('${root.path}/pubspec.yaml');
    if (!pubspec.existsSync()) {
      stderr.writeln('strip_web_assets: no pubspec at ${pubspec.path}');
      continue;
    }

    final text = pubspec.readAsStringSync();
    final live = '    ${entry.value}';
    final commented = '    # ${entry.value}';
    final String next;
    if (revert) {
      if (!text.contains(commented)) {
        stdout.writeln('strip_web_assets: ${entry.key} already restored.');
        continue;
      }
      next = text.replaceAll(commented, live);
    } else {
      if (text.contains(commented)) {
        stdout.writeln('strip_web_assets: ${entry.key} already stripped.');
        continue;
      }
      if (!text.contains(live)) {
        // Loud, not silent: the package changed its layout and this script is
        // now saving nothing while appearing to work.
        stderr.writeln('strip_web_assets: ${entry.key} no longer declares '
            '"${entry.value}" — the asset list changed. Re-check what it '
            'ships before trusting the bundle size.');
        exit(2);
      }
      next = text.replaceAll(live, commented);
    }
    pubspec.writeAsStringSync(next);
    stdout.writeln('strip_web_assets: ${revert ? 'restored' : 'stripped'} '
        '${entry.key}');
    changed++;
  }
  stdout.writeln('strip_web_assets: $changed package(s) '
      '${revert ? 'restored' : 'stripped'}.');
}
