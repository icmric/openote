// Guards on the things that make the install big.
//
// Every saving in Phase 0 of the v0.11 plan is a build-time step or a pubspec
// line, and every one of them is the kind of thing that comes back silently: a
// package update restores its web assets, someone adds a font face "for
// completeness", the gzipped dictionary gets replaced with plain text because
// a stack trace was easier to read that way.
//
// These are cheap and they run in the ordinary suite. They deliberately assert
// on the SOURCE tree (pubspec, assets) rather than on a built bundle — `flutter
// test` runs on a fresh checkout where `build/` does not exist, and a test that
// silently skips is how the size crept up in the first place.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/spell/spell_checker.dart';

void main() {
  /// The app package root, whichever directory the runner started in.
  Directory appRoot() {
    var dir = Directory.current;
    for (var i = 0; i < 4; i++) {
      if (File('${dir.path}/pubspec.yaml').existsSync()) return dir;
      dir = dir.parent;
    }
    fail('could not find pubspec.yaml from ${Directory.current.path}');
  }

  late String pubspec;
  late Directory root;

  setUpAll(() {
    root = appRoot();
    pubspec = File('${root.path}/pubspec.yaml').readAsStringSync();
  });

  group('the spell dictionary stays compressed', () {
    test('the bundled asset is the gzip, and the plain text is gone', () {
      // 1.7 MB → 443 KB, on an asset that is already loaded off the UI thread
      // so the inflate costs nothing anyone waits for.
      expect(File('${root.path}/assets/dict/en_us.txt.gz').existsSync(), isTrue,
          reason: 'the compressed wordlist must be the one in the repo');
      expect(File('${root.path}/assets/dict/en_us.txt').existsSync(), isFalse,
          reason: 'shipping both would be worse than shipping neither');
      expect(pubspec, contains('assets/dict/en_us.txt.gz'));
      expect(pubspec, isNot(contains('- assets/dict/en_us.txt\n')),
          reason: 'the uncompressed asset must not be declared');
    });

    test('it is actually smaller than the text it replaced', () {
      final gz = File('${root.path}/assets/dict/en_us.txt.gz').lengthSync();
      // The plain file was 1,743,363 bytes. Anything near that means the gzip
      // was regenerated at a level that gave up, or is not a gzip at all.
      expect(gz, lessThan(700 * 1024),
          reason: 'the wordlist compresses to ~443 KB; got $gz bytes');
    });
  });

  // THE ASSET ACTUALLY LOADS.
  //
  // Nothing in the suite had ever loaded the real wordlist — every spell test
  // injects a tiny fixture through `installForTest`. So compressing it changed
  // a code path with no coverage at all, on an asset whose failure mode is
  // "spell check silently never works". Asserting on the pubspec would not
  // have caught a wrong gzip, a wrong path, or an inflate that throws.
  testWidgets('the compressed wordlist inflates and answers queries',
      (tester) async {
    // Real file I/O through the asset bundle, so it has to be runAsync.
    await tester.runAsync(() async {
      SpellChecker.installForTest(null); // ignore anything a sibling installed
      final checker = await SpellChecker.instance();
      expect(checker.dictionary.length, greaterThan(100000),
          reason: 'the whole wordlist must survive the round trip');
      expect(checker.isWordSpelled('notebook'), isTrue);
      expect(checker.isWordSpelled('physics'), isTrue);
      expect(checker.isWordSpelled('qwertyuiopasdf'), isFalse,
          reason: 'and it must still say no to something');
    });
    SpellChecker.installForTest(null);
  });

  group('fonts stay trimmed', () {
    test('only the two mono faces the app needs are declared', () {
      // Regular and Bold. The italics were 557 KB for a combination only
      // reachable by a user italicising a block they set to this family, where
      // the engine's synthesised oblique is indistinguishable at body size.
      expect(pubspec, contains('JetBrainsMono-Regular.ttf'));
      expect(pubspec, contains('JetBrainsMono-Bold.ttf'));
      expect(pubspec, isNot(contains('JetBrainsMono-Italic.ttf')));
      expect(pubspec, isNot(contains('JetBrainsMono-BoldItalic.ttf')));
    });

    test('and the files match the declaration', () {
      // A declared-but-absent font fails at runtime; a present-but-undeclared
      // one is dead weight in the repo. Either is worth catching here.
      final dir = Directory('${root.path}/assets/fonts/jetbrains-mono');
      final faces = dir
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.endsWith('.ttf'))
          .toList()
        ..sort();
      expect(faces, ['JetBrainsMono-Bold.ttf', 'JetBrainsMono-Regular.ttf']);
    });
  });

  group('the build-time trimming steps exist and are wired up', () {
    // The savings live in CI, not in the app, so what is testable is that the
    // steps are still called. A dropped line here is a 7 MB regression that
    // nothing else would notice until someone measured an installer.
    test('both tools are present', () {
      expect(File('${root.path}/tool/strip_web_assets.dart').existsSync(),
          isTrue);
      expect(File('${root.path}/tool/shake_icons.dart').existsSync(), isTrue);
    });

    test('CI runs all three trimming steps', () {
      final ci = File('${root.parent.path}/.github/workflows/ci.yml');
      expect(ci.existsSync(), isTrue, reason: 'expected ${ci.path}');
      final text = ci.readAsStringSync();
      expect(text, contains('pdfrx:remove_wasm_modules'));
      expect(text, contains('tool/strip_web_assets.dart'));
      expect(text, contains('tool/shake_icons.dart'));
    });

    test('every release build runs them too', () {
      // Three platforms, and the icon step is a deliberate no-op on macOS —
      // so two shake_icons calls, three of each of the others.
      final text =
          File('${root.parent.path}/.github/workflows/release.yml')
              .readAsStringSync();
      expect('pdfrx:remove_wasm_modules'.allMatches(text).length, 3,
          reason: 'windows, linux and macos');
      expect('tool/strip_web_assets.dart'.allMatches(text).length, 3);
      expect('tool/shake_icons.dart'.allMatches(text).length, 2,
          reason: 'macOS subsets correctly on its own');
    });
  });
}
