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

import '../export/import_status.dart';
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

/// **What the import card says, in the reader's language.**
///
/// [ImportJob] is a `ChangeNotifier` with no `BuildContext`, so it cannot
/// reach `L` and therefore could never say anything in anybody's language but
/// English — which is how the very first screen a switcher sees stayed English
/// in an app that ships in seven languages. It reports a stage and some
/// numbers now, and the wording happens here, where the language is.
///
/// Same split, and the same reason, as the enums above.
extension ImportStatusLabel on ImportStatus {
  String describe(L l) => switch (stage) {
        ImportStage.reading => l.importReading,
        ImportStage.signingIn => l.importSigningIn,
        ImportStage.lookingAround => l.importLookingAround,
        ImportStage.foundSections => l.importFoundSections(count),
        ImportStage.foundPages => l.importFoundPages(count),
        // Under a second reads as "in 0s", which looks like a stuck clock
        // rather than a short wait.
        ImportStage.throttled =>
          count < 1 ? l.importThrottledSoon : l.importThrottled(count),
        ImportStage.bringingIn => l.importBringingIn(name, count, total),
        ImportStage.stopping => l.importStopping,
        ImportStage.stoppedKept => l.importStoppedKept(count),
        ImportStage.cancelled => l.importCancelledLabel,
        ImportStage.emptyNotebook => l.importEmptyNotebook,
        ImportStage.imported => l.importDone(count),
        ImportStage.importedButLost => l.importDoneButLost(count, detail),
        ImportStage.partialThrottled => l.importPartialThrottled(detail, count),
        ImportStage.partialBroke => l.importPartialBroke(count),
        ImportStage.failed => l.importFailedGeneric,
        ImportStage.writingPages => l.importWritingPages(count),
        ImportStage.writingSection => l.importWritingSection(name),
      };
}
