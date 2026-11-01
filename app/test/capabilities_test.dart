// What this suite is for: the browser demo greys out the features a tab
// cannot do, and the owner's requirement was that this keeps working *without
// anyone maintaining it* — "if i add new features in the future it should add
// them in if it works, but grey it out if it doesnt, without me having to go
// in and manually do stuff to set this."
//
// Three mechanisms carry that, and only the third is a test:
//
//   1. **The compiler.** `Capabilities.has` is a `switch` over every
//      `Capability` with no default arm, so a new capability that nobody
//      answered will not compile. And a feature that needs native code cannot
//      compile for the web at all without a conditional import — which is
//      where its answer comes from.
//   2. **One fact, used twice.** Every arm delegates to the check the
//      production fallback already makes, so the value that greys a button is
//      the value behind the button. There is no second list to drift.
//   3. **This file**, for the parts neither of those can see: that the thing
//      the UI asks is the thing `Capabilities` answers, and that nothing
//      declares a dependency on a capability that does not exist.
//
// What none of them can catch is a feature that quietly calls `dart:io` three
// layers down — `dart:io` compiles on the web and throws when called, so that
// one is found by running the demo. The grey box the navigator showed for a
// while (`cloud_folders.dart`, `Platform.environment`) was exactly that.

import 'package:flutter_test/flutter_test.dart';
import 'package:openote/core/capabilities.dart';
import 'package:openote/ui/insert_catalog.dart';

void main() {
  group('capabilities', () {
    test('a desktop build can do everything', () {
      // The native half of every seam answers yes. If this fails, a web half
      // has been wired into a desktop build — which would quietly disable a
      // feature for every user of the app.
      for (final c in Capability.values) {
        expect(Capabilities.has(c), isTrue, reason: c.name);
      }
      expect(Capabilities.allPresent, isTrue);
    });

    test('every capability is one some feature actually asks for', () {
      // An orphan capability is a dead branch: something that can be false
      // with nothing downstream of it. Either a feature should name it or it
      // should go.
      //
      // Two are gated outside this catalogue, and are listed here rather than
      // left to look like oversights: `folderSync` gates the sync UI, and
      // `onenoteImport` gates the three OneNote routes on the notebook
      // manager's import row. Neither is a thing you insert onto a page.
      const gatedElsewhere = {
        Capability.folderSync,
        Capability.onenoteImport,
        // Gated inside the code block rather than on the insert item, because
        // the block itself works everywhere — only the Run button, Ctrl+Enter
        // and the "Run" badge go, and all three ask `isRunnableLanguage`.
        Capability.runCode,
      };

      final named = {
        for (final i in kInsertItemsAndExtras)
          if (i.needs != null) i.needs!,
      };
      for (final c in Capability.values) {
        if (gatedElsewhere.contains(c)) continue;
        expect(named, contains(c),
            reason: 'Capability.${c.name} is declared but nothing needs it — '
                'either an item should name it, or it should be removed.');
      }
    });
  });

  group('the insert catalogue', () {
    test('everything is available on a desktop build', () {
      for (final i in kInsertItemsAndExtras) {
        expect(i.available, isTrue, reason: i.id);
      }
    });

    test('an item that reaches outside Dart has said so', () {
      // The classification itself, pinned by id. Not a second source of truth
      // — the field in the catalogue is that — but a statement of which items
      // were looked at and what was concluded, so that a change to one is a
      // change to this list and gets read.
      //
      // Everything NOT here needs nothing: it is pure Dart, it works in a
      // browser, and it stays out of this test precisely so that adding one
      // costs nothing.
      const expected = {
        'image': Capability.localFiles,
        'pdf': Capability.localFiles,
        'pdf-here': Capability.localFiles,
        'pdf-pages': Capability.localFiles,
        'pdf-card': Capability.localFiles,
        'file': Capability.localFiles,
        'table-file': Capability.localFiles,
        'video': Capability.video,
      };

      final actual = {
        for (final i in kInsertItemsAndExtras)
          if (i.needs != null) i.id: i.needs!,
      };
      expect(actual, expected);
    });

    test('availability is asked, not assumed', () {
      // `available` must consult `Capabilities`, not a stored flag. Proved by
      // the one case where the two could differ: an item with no declared
      // need is available even if every capability were false.
      final plain = kInsertItems.firstWhere((i) => i.id == 'equation');
      expect(plain.needs, isNull);
      expect(plain.available, isTrue);

      final gated = kInsertItemsAndExtras.firstWhere((i) => i.id == 'video');
      expect(gated.needs, Capability.video);
      expect(gated.available, Capabilities.has(Capability.video));
    });
  });
}
