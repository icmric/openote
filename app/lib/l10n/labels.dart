/// Names for things the MODEL defines and a screen shows.
///
/// A tag kind, a touch-drawing mode and the rest are enums in `lib/model` and
/// `lib/state`, and their names were `const` strings on the enum itself. That
/// is the right shape for data and the wrong shape for words: a `const` cannot
/// take a `BuildContext`, so those names stayed English inside an app that had
/// otherwise been translated — and they are not obscure corners, they are the
/// tag menu and the Draw row.
///
/// The fix is here rather than in the model, deliberately: `lib/model` knows
/// nothing about widgets or translations and should keep it that way. An
/// extension puts the word beside the language and leaves the data alone.
///
/// The old `label` getters are gone rather than deprecated. A getter that
/// silently returns English is exactly the thing `test/l10n_test.dart` cannot
/// see, so leaving one available is leaving the trap armed.
library;

import '../model/tags.dart';
import '../state/app_state.dart' show TouchDrawing;
import 'l10n.dart';

extension TagKindLabel on TagKind {
  String label(L l) => switch (this) {
        TagKind.todo => l.tagTodo,
        TagKind.important => l.tagImportant,
        TagKind.question => l.tagQuestion,
        TagKind.remember => l.tagRemember,
        TagKind.definition => l.tagDefinition,
        TagKind.idea => l.tagIdea,
        TagKind.critical => l.tagCritical,
        TagKind.contact => l.tagContact,
        TagKind.custom => l.tagCustom,
      };
}

extension TouchDrawingLabel on TouchDrawing {
  String label(L l) => switch (this) {
        TouchDrawing.auto => l.touchDrawAuto,
        TouchDrawing.always => l.touchDrawAlways,
        TouchDrawing.never => l.touchDrawNever,
      };
}
