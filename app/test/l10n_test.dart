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

import 'package:path/path.dart' as p;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/l10n/l10n.dart';
import 'package:openote/state/app_state.dart';

import 'support/app.dart';

/// Files whose user-facing words have been moved into the .arb. Add a file
/// here the moment you convert it — that is what arms (c) for it.
const _converted = [
  'lib/ui/onboarding.dart',
  'lib/ui/object_row.dart',
  'lib/ui/command_bar.dart',
  'lib/ui/sidebar.dart',
  'lib/ui/settings_dialog.dart',
  'lib/ui/notebook_manager.dart',
  'lib/ui/insert_catalog.dart',
  'lib/ui/app_shell.dart',
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
    // Where a literal reaches the screen.
    final patterns = <RegExp>[
      RegExp(r'''\bText\(\s*('[^']*'|"[^"]*")'''),
      RegExp(r'''\b(?:label|title|hintText|tooltip|helperText|semanticLabel)\s*:\s*('[^']*'|"[^"]*")'''),
    ];

    /// Is there a WORD in this literal, once the interpolations are taken
    /// out? `Text('  ›  ')` between breadcrumbs and `Text('\${pages.length}')`
    /// on a badge have nothing to translate; demanding a message for either
    /// buys a worse app, not a better one.
    bool hasWords(String literal) => literal
        .replaceAll(RegExp(r'\$\{[^}]*\}'), '')
        .replaceAll(RegExp(r'\$\w+'), '')
        .contains(RegExp('[A-Za-z]'));
    final offenders = <String>[];
    for (final path in _converted) {
      final lines = File(path).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.startsWith('//') || line.startsWith('///')) continue;
        for (final p in patterns) {
          final m = p.firstMatch(line);
          if (m != null && hasWords(m.group(1)!)) {
            offenders.add('$path:${i + 1}  $line');
            break;
          }
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
      // English, rather than throwing on the first lookup. (It was French
      // when this was written. French shipped, which is a nice way for a test
      // to go stale; Icelandic is the stand-in now.)
      locale: const Locale('is'),
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

  group('the languages themselves', () {
    /// Every `app_*.arb` beside the template.
    List<File> translations() => Directory('lib/l10n')
        .listSync()
        .whereType<File>()
        .where((f) =>
            f.path.endsWith('.arb') && !f.path.endsWith('app_en.arb'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    Map<String, String> messages(File f) {
      final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      return {
        for (final e in j.entries)
          if (!e.key.startsWith('@')) e.key: e.value as String
      };
    }

    test('there are some, and each one is complete', () {
      final en = messages(File('lib/l10n/app_en.arb'));
      expect(translations(), isNotEmpty,
          reason: 'the whole point of the .arb machinery is other languages');
      for (final f in translations()) {
        final them = messages(f);
        final missing = en.keys.where((k) => !them.containsKey(k)).toList()
          ..sort();
        // A missing message falls back to English rather than crashing, so
        // this is a quality bar, not a safety one — but a half-translated
        // language reads worse than an untranslated one, and the person who
        // added the message is better placed to notice than the person who
        // meets it in the wild.
        expect(missing, isEmpty,
            reason: '${p.basename(f.path)} is missing $missing');
        final extra = them.keys.where((k) => !en.containsKey(k)).toList()
          ..sort();
        expect(extra, isEmpty,
            reason: '${p.basename(f.path)} has messages the template does '
                'not: $extra — a renamed key leaves these behind');
      }
    });

    test('every translation keeps every placeholder', () {
      // THE ONE THAT BREAKS AT RUNTIME. `{count}` dropped from a translation
      // is a message that renders without its number; `{coutn}` is worse.
      // Codegen catches a missing placeholder in the ARB's metadata, not a
      // sentence that simply forgot to use one.
      final en = messages(File('lib/l10n/app_en.arb'));
      final holes = RegExp(r'\{(\w+)[,}]');
      for (final f in translations()) {
        messages(f).forEach((key, value) {
          final want = holes
              .allMatches(en[key] ?? '')
              .map((m) => m.group(1)!)
              .where((n) => n != 'plural')
              .toSet();
          final got = holes
              .allMatches(value)
              .map((m) => m.group(1)!)
              .where((n) => n != 'plural')
              .toSet();
          expect(got, containsAll(want),
              reason: '${p.basename(f.path)} · $key drops ${want.difference(got)}');
        });
      }
    });

    testWidgets('a Chinese computer gets a Chinese app, with no setup',
        (tester) async {
      // The owner's own example: "if I run through the setup of it and my
      // computer's language is in Chinese, it should set it up automatically
      // in Chinese, not English". No locale is passed to `testApp` here —
      // exactly as `main.dart` passes none while `AppState.uiLocale` is null
      // — and the PLATFORM locale is what resolution sees.
      tester.platformDispatcher.localesTestValue = const [Locale('zh', 'CN')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      late L l;
      await tester.pumpWidget(testApp(Builder(builder: (context) {
        l = L.of(context);
        return Text(l.settingsTitle);
      })));
      await tester.pumpAndSettle();
      expect(l.localeName, startsWith('zh'));
      expect(find.text('设置'), findsOneWidget);
    });

    testWidgets('a language Openote does not have falls back to English',
        (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('is')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(testApp(Builder(
          builder: (context) => Text(L.of(context).settingsTitle))));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('the Settings override beats the computer', (tester) async {
      // A Spanish machine, a student who wants the app in French.
      tester.platformDispatcher.localesTestValue = const [Locale('es')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(testApp(
        Builder(builder: (context) => Text(L.of(context).settingsTitle)),
        locale: const Locale('fr'),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Réglages'), findsOneWidget);
    });

    test('a stored language tag reads back, and a broken one means "follow '
        'the computer"', () {
      expect(AppState.parseLocale('fr'), const Locale('fr'));
      expect(AppState.parseLocale('pt-BR'), const Locale('pt', 'BR'));
      expect(AppState.parseLocale('zh_Hant')?.scriptCode, 'Hant');
      // Null is the important one: it means follow the OS, and anything we
      // cannot read must land there rather than pinning the app to English.
      expect(AppState.parseLocale(null), isNull);
      expect(AppState.parseLocale(''), isNull);
    });

    test('every supported language has a name written in that language', () {
      for (final loc in kOnoteLocales) {
        final name = languageNameOf(loc);
        expect(name, isNotEmpty);
        expect(name, isNot(loc.toLanguageTag()),
            reason: 'add ${loc.toLanguageTag()} to kLanguageNames — a row '
                'reading "${loc.toLanguageTag()}" helps nobody find their '
                'own language');
      }
    });
  });
}
