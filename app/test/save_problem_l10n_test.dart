// §1.14: what Openote says when a save goes wrong, in the reader's language.
//
// The words are built in AppState, which has no BuildContext, so they used to
// be English everywhere. A problem now carries its kind; the status bar and the
// dialog say it with `shortIn` / `messageIn`, and `short` / `message` stay the
// English for logs and the tests that read them.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/l10n/gen/app_localizations.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/ui/save_problem_dialog.dart';

void main() {
  SaveProblem of(SaveProblemKind k) => k == SaveProblemKind.listLocked
      ? SaveProblem.of(k, message: 'The lock says this.')
      : SaveProblem.of(k, count: 3);

  test('every kind has words in every language', () {
    for (final locale in kOnoteLocales) {
      final l = lookupL(locale);
      for (final k in SaveProblemKind.values) {
        final p = of(k);
        expect(p.shortIn(l).trim(), isNotEmpty, reason: '$locale $k');
        expect(p.messageIn(l).trim(), isNotEmpty, reason: '$locale $k');
        // The chip on the status bar has room for a few words.
        expect(p.shortIn(l).length, lessThanOrEqualTo(40),
            reason: '$locale $k: "${p.shortIn(l)}"');
        if (locale.languageCode != 'en') {
          expect(p.shortIn(l), isNot(p.short), reason: '$locale $k');
        }
      }
    }
  });

  test('the English is what the logs and older tests read', () {
    const p = SaveProblem.of(SaveProblemKind.picturesMissing, count: 2);
    expect(p.message, contains('For 2 of them'));
    expect('$p', p.message);
    expect(p.short, 'Some pictures may be missing');
  });

  test("the lock's own sentence is said as given", () {
    final p = of(SaveProblemKind.listLocked);
    expect(p.messageIn(lookupL(const Locale('de'))), 'The lock says this.');
    expect(p.shortIn(lookupL(const Locale('de'))),
        isNot('Your notebook list is locked'));
  });

  testWidgets('the dialog speaks the reader\'s language', (tester) async {
    const p = SaveProblem.of(SaveProblemKind.pageNotSaved, details: 'errno 13');
    final de = lookupL(const Locale('de'));
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showSaveProblemDialog(context, p),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text(de.saveProblemPageShort), findsOneWidget);
    expect(find.text(de.saveProblemPage), findsOneWidget);
    expect(find.text(de.commonDetailsAdvanced), findsOneWidget);
    expect(find.text(p.short), findsNothing, reason: 'no English left over');
  });
}
