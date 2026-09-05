// The release body: the text GitHub hands the app, and what the update
// dialog does with it.
//
// Two failures, both reported after 0.8.0 shipped.
//
//  1. The dialog printed the body as plain text, so a student saw
//     `**like this**` instead of bold, and `## What's new` instead of a
//     heading. It renders through the note renderer now.
//  2. Only the first few lines of the body are ever read, because that is
//     what fits in the dialog — so the body must OPEN with the best of the
//     release, short. That is a property of the workflow file, so the test
//     for it reads the workflow file.
//
// The body used here is not a copy: it is extracted from
// `.github/workflows/release.yml` itself, so these tests exercise the real
// text that will ship and cannot drift away from it.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/l10n/l10n.dart';
import 'package:openote/ui/update_dialog.dart';
import 'package:openote/update/app_update.dart';

/// The `body: |` block scalar from the release workflow, dedented — i.e.
/// exactly the Markdown GitHub will store as the release body.
String releaseBodyTemplate() {
  final f = File('../.github/workflows/release.yml');
  expect(f.existsSync(), isTrue,
      reason: 'tests run from app/, so the workflow is one level up');
  final lines = f.readAsStringSync().replaceAll('\r\n', '\n').split('\n');
  final start = lines.indexWhere((l) => RegExp(r'^\s*body: \|\s*$').hasMatch(l));
  expect(start, greaterThan(-1), reason: 'release.yml still has a `body: |`');
  final body = <String>[];
  int? indent;
  for (final line in lines.skip(start + 1)) {
    if (line.trim().isEmpty) {
      body.add('');
      continue;
    }
    final lead = line.length - line.trimLeft().length;
    indent ??= lead;
    if (lead < indent) break; // the block scalar ended
    body.add(line.substring(indent));
  }
  return body.join('\n').trim();
}

/// Every string the widget tree actually draws.
String visibleText(WidgetTester tester) {
  final buf = StringBuffer();
  for (final t in tester.widgetList<Text>(find.byType(Text))) {
    if (t.data != null) buf.writeln(t.data);
    final span = t.textSpan;
    if (span != null) {
      buf.writeln(span.toPlainText(
          includeSemanticsLabels: false, includePlaceholders: false));
    }
  }
  return buf.toString();
}

/// True when anything on screen is drawn bold.
bool hasBoldRun(WidgetTester tester) {
  var bold = false;
  for (final t in tester.widgetList<Text>(find.byType(Text))) {
    t.textSpan?.visitChildren((span) {
      if (span is TextSpan && span.style?.fontWeight == FontWeight.w600) {
        bold = true;
      }
      return !bold;
    });
  }
  return bold;
}

Widget host(Widget child) => MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      home: Scaffold(body: Center(child: SizedBox(width: 440, child: child))),
    );

void main() {
  group('tidyReleaseNotes', () {
    test('hides the draft-review comment the workflow leaves in the body', () {
      const raw = '<!-- Draft: review — written with the\n'
          '     tag, from CHANGELOG.md — then publish. -->\n'
          '\n'
          '## What\'s new\n';
      final out = tidyReleaseNotes(raw);
      expect(out, isNot(contains('<!--')));
      expect(out, isNot(contains('Draft: review')));
      expect(out, startsWith("## What's new"));
    });

    test('folds a wrapped bullet back into its bullet', () {
      const raw = '- **Half the download** — about 50 MB now,\n'
          '  instead of 100 MB.\n'
          '- The next bullet stays its own bullet.\n';
      final out = tidyReleaseNotes(raw).split('\n');
      expect(out, hasLength(2));
      expect(out.first,
          '- **Half the download** — about 50 MB now, instead of 100 MB.');
      expect(out.last, '- The next bullet stays its own bullet.');
    });

    test('a blank line still separates two paragraphs', () {
      final out = tidyReleaseNotes('One paragraph.\n\nAnother one.').split('\n');
      expect(out, ['One paragraph.', '', 'Another one.']);
    });

    test('headings, rules and table rows are never folded into prose', () {
      const raw = 'Some prose.\n'
          '## A heading\n'
          'Its first line.\n'
          '---\n'
          '| a | b |\n'
          '| - | - |\n';
      final out = tidyReleaseNotes(raw).split('\n');
      expect(out, [
        'Some prose.',
        '## A heading',
        'Its first line.',
        '---',
        '| a | b |',
        '| - | - |',
      ]);
    });

    test('an indented code block keeps its own lines', () {
      // The `xattr` line in the real body. Nothing may be appended to it —
      // the sentence after it would end up inside the command.
      const raw = 'After copying to Applications, clear the flag once:\n'
          '\n'
          '    xattr -cr /Applications/openote.app\n'
          'Your notes never leave your machine either way.\n';
      final out = tidyReleaseNotes(raw).split('\n');
      expect(out, [
        'After copying to Applications, clear the flag once:',
        '',
        '    xattr -cr /Applications/openote.app',
        'Your notes never leave your machine either way.',
      ]);
    });

    test('a fenced block keeps every line break it has', () {
      const raw = '```\none\ntwo\n```\nprose after';
      expect(tidyReleaseNotes(raw).split('\n'),
          ['```', 'one', 'two', '```', 'prose after']);
    });

    test('CRLF from the GitHub API leaves no carriage returns behind', () {
      expect(tidyReleaseNotes('## Heading\r\n\r\n- one\r\n'), isNot(contains('\r')));
    });

    test('a runaway body is cut at a line boundary, with a pointer to the rest',
        () {
      final raw = List.filled(4000, '- a generated pull-request line').join('\n');
      final out = tidyReleaseNotes(raw);
      expect(out.length, lessThan(kReleaseNotesMaxChars + 200));
      expect(out, endsWith('There is more to read on the download page.'));
      expect(out, contains('- a generated pull-request line'));
    });

    test('hostile bodies come back as text rather than as an exception', () {
      final nasty = [
        '',
        '   ',
        '**',
        '***unclosed',
        '`',
        '<!-- never closed',
        '\$\$',
        '{{#ZZZZZZ nope}}',
        '[label](javascript:alert(1))',
        '![img](https://evil.test/x.png)',
        '|',
        '#'.padRight(200, '#'),
        '\x00\x07 control characters',
        '- [ ] a checkbox with no body',
      ];
      for (final n in nasty) {
        expect(() => tidyReleaseNotes(n), returnsNormally, reason: n);
        expect(tidyReleaseNotes(n), isA<String>());
      }
    });
  });

  group('ReleaseNotesView', () {
    testWidgets('renders the shipping body as Markdown, not as markers',
        (tester) async {
      final body = releaseBodyTemplate();
      // Guard the fixture itself: if the extraction ever silently returns
      // nothing, the assertions below would all pass on an empty string.
      expect(body, contains('**'));
      expect(body, contains("## What's new"));

      // The lead bullet's bold phrase, taken from the body rather than
      // written here: this test used to assert a literal from 0.8.0's notes
      // ('Half the download'), which meant every release had to remember to
      // edit a test that is not about any one release. What is being checked
      // is that the FIRST thing a reader sees survives the render — whatever
      // this release chose to lead with.
      final lead = RegExp(r'^- \*\*(.+?)\*\*', multiLine: true)
          .firstMatch(body.substring(body.indexOf("## What's new")))
          ?.group(1);
      expect(lead, isNotNull,
          reason: 'the overview opens with a bolded bullet');

      await tester.pumpWidget(host(ReleaseNotesView(notes: body)));
      await tester.pumpAndSettle();

      final shown = visibleText(tester);
      expect(shown, isNot(contains('**')),
          reason: 'bold markers must be bold, not asterisks');
      expect(shown, isNot(contains('## ')),
          reason: 'a heading must be a heading, not two hashes');
      expect(shown, isNot(contains('<!--')),
          reason: 'the draft comment is for the person publishing, not the user');
      expect(shown, contains(lead!),
          reason: 'the lead bullet is what most readers ever see');
      expect(hasBoldRun(tester), isTrue,
          reason: 'something on screen is actually drawn bold');
      expect(tester.takeException(), isNull);
    });

    testWidgets('scrolls, and opens out for the rest of the notes',
        (tester) async {
      await tester.pumpWidget(host(ReleaseNotesView(notes: releaseBodyTemplate())));
      await tester.pumpAndSettle();

      expect(find.byType(Scrollbar), findsOneWidget);
      final folded = tester.getSize(find.byType(Scrollbar)).height;
      expect(folded, lessThanOrEqualTo(ReleaseNotesView.collapsedHeight));

      expect(find.text('Show more'), findsOneWidget);
      await tester.tap(find.text('Show more'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(Scrollbar)).height, greaterThan(folded));
      expect(find.text('Show less'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('short notes get no fold, and nothing overflows on a small '
        'window', (tester) async {
      tester.view.physicalSize = const Size(420, 320);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(ReleaseNotesView(notes: releaseBodyTemplate())));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(host(const ReleaseNotesView(notes: 'One line.')));
      await tester.pumpAndSettle();
      expect(find.text('Show more'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a hostile body renders without throwing', (tester) async {
      const nasty = '***unclosed **bold `code\n'
          '<!-- open comment\n'
          '| broken | table\n'
          '\$\$\\frac{1}{}\$\$\n'
          '![picture](https://evil.test/x.png)\n'
          '[link](javascript:alert(1))\n'
          '{{#ZZZZZZ not a colour}}\n'
          '#######\n';
      await tester.pumpWidget(host(const ReleaseNotesView(notes: nasty)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // A remote picture is never FETCHED. With no image resolver the line
      // never reaches the image branch of the renderer, so nothing in a
      // release body can make the dialog pull bytes off the network — the
      // address survives only as a link, which goes through PlatformOpen's
      // http/https/mailto allow-list when tapped.
      expect(find.byType(Image), findsNothing);
      expect(visibleText(tester), contains('picture'));
    });
  });

  group('the release body opens with the compact overview', () {
    // Eric, 2026-08-17: "we only show the first few lines in the app which is
    // where most people will see it. We want to keep the overview compact and
    // have the most important/exciting changes for a user right at the top
    // every time." The rule is written down in docs/RELEASING.md; this is
    // what stops the next release quietly breaking it.
    test('the first section is a handful of one-line bullets', () {
      final lines = releaseBodyTemplate().split('\n');
      final first = lines.indexWhere((l) => l.startsWith('## '));
      expect(first, greaterThan(-1));
      expect(lines[first], "## What's new");

      final second = lines.indexWhere((l) => l.startsWith('## '), first + 1);
      expect(second, greaterThan(first), reason: 'the detail follows below');

      final opening = [
        for (final l in lines.sublist(first + 1, second))
          if (l.trim().isNotEmpty) l
      ];
      expect(opening.length, inInclusiveRange(3, 7),
          reason: 'a handful of lines, not a wall of them');
      for (final l in opening) {
        expect(l, startsWith('- '),
            reason: 'every opening line is its own bullet: "$l"');
        expect(l.length, lessThanOrEqualTo(90),
            reason: 'an opening bullet is one short line: "$l"');
      }
    });

    test('downloads and boilerplate come last', () {
      final body = releaseBodyTemplate();
      final overview = body.indexOf("## What's new");
      final detail = body.indexOf('\n## ', overview + 1);
      final downloads = body.indexOf('## Downloads');
      expect(overview, lessThan(detail));
      expect(detail, lessThan(downloads));
      expect(downloads, lessThan(body.indexOf('not code-signed')));
    });
  });
}
