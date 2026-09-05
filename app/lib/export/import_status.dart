/// **What an import is doing, as data rather than as an English sentence.**
///
/// The import card was the last surface in the app speaking only English. Six
/// languages shipped deliberately, and a German student picking their notebook
/// out of OneNote — the very first thing they do — watched it arrive in
/// English the whole way.
///
/// The reason was structural rather than an oversight. [ImportJob] is a
/// `ChangeNotifier`: it has no `BuildContext`, so it cannot reach `L`, so
/// every sentence it wanted to say had to be built where it had no way to say
/// it in anybody's language. Translating in place was impossible; the fix is
/// to stop writing sentences there at all.
///
/// So the job reports a **stage and some numbers**, and the card — which does
/// have a context — turns that into words. Same split as `l10n/labels.dart`
/// uses for the model's enums, and for the same reason: the data layer should
/// not know about words, and the word layer should not know about the data's
/// internals.
///
/// [ImportJob.message] survives alongside this as the English rendering, for
/// tests and for anything without a context to ask.
library;

/// Where an import has got to.
enum ImportStage {
  /// Reading a `.onepkg` off disk.
  reading,

  /// Getting a token before anything can be fetched.
  signingIn,

  /// Before any page can arrive: listing sections, then their page lists.
  lookingAround,

  /// Sections counted, their contents not yet.
  foundSections,

  /// The page total is known and writing is about to start.
  foundPages,

  /// Microsoft has asked us to slow down. Counts down.
  throttled,

  /// Writing a section's pages.
  bringingIn,

  /// Stop pressed, not yet finished stopping.
  stopping,

  /// Stopped on purpose, with pages kept.
  stoppedKept,

  /// Stopped and nothing kept.
  cancelled,

  /// The notebook had nothing in it.
  emptyNotebook,

  /// Finished, everything came over.
  imported,

  /// Finished, but something specific did not come.
  importedButLost,

  /// Gave up under throttling, with pages kept.
  partialThrottled,

  /// Something unexpected broke, with pages kept.
  partialBroke,

  /// Nothing came over at all.
  failed,

  /// The `.onepkg` writer, mid-run.
  writingPages,

  /// The `.onepkg` writer, naming a section.
  writingSection,
}

/// One reading of the import's state: a stage, plus whatever numbers that
/// stage needs.
///
/// Deliberately one flat class rather than a sealed hierarchy of nineteen. The
/// fields are few, the stages are many, and a switch in one place reads better
/// than nineteen tiny types — this is a progress label, not a domain model.
class ImportStatus {
  const ImportStatus(
    this.stage, {
    this.count = 0,
    this.total = 0,
    this.name = '',
    this.detail = '',
  });

  final ImportStage stage;

  /// Pages, sections or seconds, depending on [stage].
  final int count;

  /// The denominator when there is one.
  final int total;

  /// A section or notebook name, when the stage names one.
  final String name;

  /// Already-worded detail that has nowhere better to live — the list of
  /// things a partial import could not bring, and the service's own
  /// explanation of why it stopped.
  ///
  /// **The one thing here that is not translated**, and knowingly so: it is
  /// assembled from counts of pictures and attachments, and from Microsoft's
  /// own message. Leaving it in English is honest about where it came from;
  /// pretending otherwise would mean inventing a translation for a sentence
  /// this app did not write.
  final String detail;
}
