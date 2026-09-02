// The "Embed a video or link" dialog — which shipped broken in v0.5.0.
//
// Its actions row used a Spacer to push the file button left. AlertDialog
// lays actions out in an OverflowBar, which is not a Flex, and a Spacer is an
// Expanded whose ParentData contract only a Flex satisfies — so the dialog
// failed to build. On a release build a failed subtree paints as a grey box:
// reported from Linux as "the popup was taking up the whole screen, was just
// grey". Nothing could have caught it, because the dialog was private behind
// a menu and a picker, and no test ever built it. Now one does.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/l10n/l10n.dart';

import 'package:openote/ui/media_link_dialog.dart' show MediaLinkDialog;

void main() {
  testWidgets('THE DIALOG BUILDS — no Spacer-in-OverflowBar layout error',
      (t) async {
    await t.pumpWidget(const MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      home: Scaffold(body: MediaLinkDialog()),
    ));
    await t.pump();

    expect(t.takeException(), isNull,
        reason: 'a ParentDataWidget violation here is the whole-screen grey '
            'box reported on Linux');
    expect(find.text('Embed a video or link'), findsOneWidget);
    expect(find.text('Add link'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Use a file on this computer…'), findsOneWidget,
        reason: 'all three actions must survive the layout change');
  });

  testWidgets('an empty link is refused with a reason, not submitted',
      (t) async {
    await t.pumpWidget(const MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      home: Scaffold(body: MediaLinkDialog()),
    ));
    await t.pump();

    await t.tap(find.text('Add link'));
    await t.pump();
    expect(find.text('That needs to be an http or https link.'),
        findsOneWidget);
  });
}
