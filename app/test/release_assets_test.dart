// Guards on files that are only ever parsed by the release toolchain.
//
// Nothing here is exercised by running the app: macOS entitlements are read by
// AMFI at codesign time, on a runner, after the Rust and Flutter builds have
// already taken their twenty minutes. A typo in one of them is invisible until
// the release is most of an hour old — which is exactly what happened to
// v0.3.1, where a `--` inside an XML comment made the whole plist unparseable
// and `codesign` failed with `AMFIUnserializeXML: syntax error near line 21`.
//
// These tests run in milliseconds, on every platform, on every push.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The `app/` package root, wherever the runner happened to start.
Directory _packageRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    if (Directory('${dir.path}/macos/Runner').existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('could not locate the app package root from ${Directory.current.path}');
}

/// The body text of every `<!-- ... -->` comment in [xml].
///
/// Deliberately hand-rolled: the point is to read the file the way a strict
/// parser does, and pulling in an XML package to check that an XML package
/// would be happy defeats the exercise.
Iterable<String> _commentBodies(String xml) sync* {
  var i = 0;
  while (true) {
    final start = xml.indexOf('<!--', i);
    if (start < 0) return;
    final end = xml.indexOf('-->', start + 4);
    if (end < 0) fail('unterminated XML comment starting at offset $start');
    yield xml.substring(start + 4, end);
    i = end + 3;
  }
}

void main() {
  final root = _packageRoot();
  final entitlements = <String, File>{
    'Release': File('${root.path}/macos/Runner/Release.entitlements'),
    'DebugProfile': File('${root.path}/macos/Runner/DebugProfile.entitlements'),
  };

  group('macOS entitlements', () {
    for (final entry in entitlements.entries) {
      test('${entry.key}.entitlements has no double hyphen inside a comment',
          () {
        final file = entry.value;
        expect(file.existsSync(), isTrue, reason: '${file.path} is missing');

        final bodies = _commentBodies(file.readAsStringSync()).toList();
        for (final body in bodies) {
          expect(
            body.contains('--'),
            isFalse,
            reason: 'XML forbids "--" inside a comment, and AMFI enforces it. '
                'Rewrite the flag name bare (deep, not the dashed form) in:\n'
                '${body.trim()}',
          );
        }
      });
    }

    // The keys themselves, so a well-formed file that says the wrong thing is
    // caught too. Release is deliberately UNsandboxed and needs outbound
    // HTTPS — see the rationale in the file itself.
    test('Release.entitlements keeps the sandbox off and the network on', () {
      final text = entitlements['Release']!.readAsStringSync();
      // Strip comments first: the rationale in this file names both keys, so
      // matching against the raw text would pass on prose alone.
      var body = text;
      for (final comment in _commentBodies(text)) {
        body = body.replaceFirst('<!--$comment-->', '');
      }

      expect(
        RegExp(r'<key>com\.apple\.security\.app-sandbox</key>\s*<false\s*/>')
            .hasMatch(body),
        isTrue,
        reason: 'app-sandbox must be explicitly false, not inherited or true',
      );
      expect(
        RegExp(r'<key>com\.apple\.security\.network\.client</key>\s*<true\s*/>')
            .hasMatch(body),
        isTrue,
        reason: 'the subscribed .ics timetable needs outbound HTTPS',
      );
    });
  });
}
