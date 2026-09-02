// Translation: the plumbing, and a guard that stops it silently rotting.
//
// Openote ships in English only today. What landed is the FOUNDATION — the
// delegates, the .arb template, the generated `L` class, and one converted
// surface (the welcome flow) proving the pattern end to end. Adding a
// language is then `lib/l10n/app_<code>.arb` plus `flutter gen-l10n`, with no
// Dart to change; see docs/planning/v0.24-road-to-1.0.md §Languages.
//
// Three things are asserted, and each of them is something that broke a real
// part-translated app somewhere:
//
//  (a) the delegates are actually installed, and an UNSUPPORTED locale falls
//      back to English rather than throwing — the failure mode of a
//      `supportedLocales` list that lists a language with no strings behind
//      it;
//  (b) a message with a placeholder really interpolates, because a
//      translator's job is to move that placeholder around the sentence and
//      a string that only ever concatenated would not let them;
//  (c) every message in the template carries an @-description, and no
//      already-converted file has grown a NEW hardcoded string. A migration
//      done file-by-file rots the moment someone adds `Text('…')` back into a
//      file that had been finished, and nothing else in the build notices.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/l10n/l10n.dart';

import 'support/app.dart';

/// Files whose user-facing words have been moved into the .arb. Add a file
/// here the moment you convert it — that is what arms (c) for it.
const _converted = [
  'lib/ui/onboarding.dart',
  'lib/ui/object_row.dart',
  'lib/ui/command_bar.dart',
  'lib/ui/sidebar.dart',
];

void main() {
  test('the template gives every message a description for the translator',
      () {
    final arb = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
        as Map<String, dynamic>;
    final missing = <String>[];
    for (final key in arb.keys) {
      if (key.startsWith('@')) continue;
      final meta = arb['@$key'];
      if (meta is! Map || (meta['description'] as String?)?.isNotEmpty != true) {
        missing.add(key);
      }
    }
    expect(missing, isEmpty,
        reason: 'a translator sees the string and nothing else: these have no '
            '@description saying where they appear — $missing');
  });

  test('every placeholder is declared', () {
    final arb = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
        as Map<String, dynamic>;
    final undeclared = <String>[];
    for (final entry in arb.entries) {
      if (entry.key.startsWith('@')) continue;
      final used = RegExp(r'\{(\w+)\}')
          .allMatches(entry.value as String)
          .map((m) => m.group(1)!)
          .toSet();
      if (used.isEmpty) continue;
      final meta = arb['@${entry.key}'];
      final declared =
          ((meta as Map?)?['placeholders'] as Map?)?.keys.toSet() ?? {};
      for (final u in used) {
        if (!declared.contains(u)) undeclared.add('${entry.key}.$u');
      }
    }
    expect(undeclared, isEmpty,
        reason: 'an undeclared placeholder becomes literal braces on screen');
  });

  test('the converted surfaces hold no hardcoded user-facing strings', () {
    // Only the shapes that actually reach the screen, and only when they
    // carry an actual word: a comment, a debug string, a semantic key or the
    // empty string a `PopupMenuButton` takes to suppress its own tooltip is
    // not what this is looking for.
    final patterns = <RegExp>[
      RegExp(r'''\bText\(\s*(?:'[^']|"[^"])'''),
      RegExp(r'''\b(?:label|title|hintText|tooltip|helperText|semanticLabel)\s*:\s*(?:'[^']|"[^"])'''),
    ];
    final offenders = <String>[];
    for (final path in _converted) {
      final lines = File(path).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.startsWith('//') || line.startsWith('///')) continue;
        if (patterns.any((p) => p.hasMatch(line))) {
          offenders.add('$path:${i + 1}  $line');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'these files were converted to the .arb and have grown a new '
            'literal — move it into lib/l10n/app_en.arb:\n'
            '${offenders.join('\n')}');
  });

  testWidgets('the delegates are installed and an unknown language falls back',
      (tester) async {
    late L l;
    await tester.pumpWidget(testApp(
      Builder(builder: (context) {
        l = L.of(context);
        return Text(l.onboardingStep1Title);
      }),
      // Not a language Openote has strings for — the app must still open, in
      // English, rather than throwing on the first lookup.
      locale: const Locale('fr'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('The page is a canvas'), findsOneWidget);
    expect(kOnoteLocales, contains(const Locale('en')));
    // The placeholder really is one, not a fragment glued on the end.
    expect(l.onboardingImportingFile('School 2026.onepkg'),
        'Importing School 2026.onepkg');
    expect(l.onboardingReadFailed('no such file'),
        contains('no such file'));
  });
}
