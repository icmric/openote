/// **An import that stopped before it finished, and how to pick it up.**
///
/// A cloud import can end early for reasons that are nobody's fault and not
/// permanent: Microsoft throttles the account, the wifi drops, the laptop is
/// shut. Everything already brought over is kept — that was fixed separately,
/// and it matters more than this does — but a notebook holding 152 of 332
/// pages with nothing on screen to say so is a quiet lie. Somebody will find
/// the gaps weeks later and conclude the import ate their notes.
///
/// So the fact is written down, per notebook, and survives closing the app.
///
/// ## What it deliberately does not do
///
/// **It never resumes an import somebody stopped on purpose.** Pressing Stop
/// is an instruction, not an interruption, and an app that quietly restarts
/// the thing you just stopped is worse than one that forgets. [stoppedByUser]
/// carries that distinction and nothing automatic ever looks past it.
///
/// **It never re-imports a page it already brought over.** Resuming skips
/// every page in [donePageIds], so a page somebody has since edited is not
/// overwritten by a fresh copy of its original — which would be the one way
/// this feature could destroy work rather than protect it.
library;

/// How long to wait before trying again on our own.
///
/// Microsoft does not publish the OneNote throttle window. What is documented
/// is that Graph throttling is per-app-per-user over a sliding window and that
/// `Retry-After` is authoritative for a single request; nothing states the
/// cooldown for an account that has been hammered. Measured here rather than
/// read: a run that exhausted the limit was still refused **minutes** later,
/// and an account probed hard through a working day was still slow after
/// roughly half an hour.
///
/// An hour is therefore chosen to be comfortably past anything observed, on
/// the reasoning that the cost of waiting too long is a notebook that finishes
/// later, and the cost of trying too early is another refusal and a longer
/// penalty. It is not a magic number and is not presented as one.
const Duration kUnfinishedRetryAfter = Duration(hours: 1);

/// Why an import stopped, in the only three flavours that change what happens
/// next.
enum UnfinishedReason {
  /// Microsoft asked us to slow down and kept asking. Worth retrying.
  throttled,

  /// The connection went, or something unexpected broke. Worth retrying.
  interrupted,

  /// Somebody pressed Stop. **Never** retried on its own.
  stopped,
}

/// The record kept against one notebook.
class UnfinishedImport {
  const UnfinishedImport({
    required this.graphNotebookId,
    required this.notebookName,
    required this.pagesDone,
    required this.pagesTotal,
    required this.donePageIds,
    required this.linkMap,
    required this.reason,
    required this.lastTryMs,
  });

  /// The OneNote notebook this came from, so resuming does not have to ask.
  final String graphNotebookId;
  final String notebookName;

  final int pagesDone;
  final int pagesTotal;

  /// Graph page ids already written. Resuming skips these.
  final List<String> donePageIds;

  /// OneNote page GUID to the Openote page written for it.
  ///
  /// Kept because cross-page links are rewritten from it, and a link on a page
  /// that arrives in the SECOND half often points at one from the first. Left
  /// behind, every such link would stay broken for ever after a resume.
  final Map<String, String> linkMap;

  final UnfinishedReason reason;
  final int lastTryMs;

  bool get stoppedByUser => reason == UnfinishedReason.stopped;

  int get pagesLeft {
    final left = pagesTotal - pagesDone;
    return left < 0 ? 0 : left;
  }

  /// When an automatic attempt becomes allowed. Never, if somebody stopped it.
  DateTime? get retryAfter => stoppedByUser
      ? null
      : DateTime.fromMillisecondsSinceEpoch(lastTryMs)
          .add(kUnfinishedRetryAfter);

  bool mayRetryAt(DateTime now) {
    final at = retryAfter;
    return at != null && !now.isBefore(at);
  }

  Map<String, dynamic> toJson() => {
        'graphNotebookId': graphNotebookId,
        'notebookName': notebookName,
        'pagesDone': pagesDone,
        'pagesTotal': pagesTotal,
        'donePageIds': donePageIds,
        'linkMap': linkMap,
        'reason': reason.name,
        'lastTryMs': lastTryMs,
      };

  /// Null for anything that is not a record we wrote.
  ///
  /// Tolerant on purpose: this comes off disk, may have been written by an
  /// older build, and a malformed one must read as "no unfinished import"
  /// rather than as a crash on startup.
  static UnfinishedImport? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final m = raw.cast<String, dynamic>();
    final id = m['graphNotebookId'];
    if (id is! String || id.isEmpty) return null;
    return UnfinishedImport(
      graphNotebookId: id,
      notebookName: m['notebookName'] as String? ?? 'Notebook',
      pagesDone: (m['pagesDone'] as num?)?.toInt() ?? 0,
      pagesTotal: (m['pagesTotal'] as num?)?.toInt() ?? 0,
      donePageIds: [
        for (final v in (m['donePageIds'] as List? ?? const []))
          if (v is String) v
      ],
      linkMap: {
        for (final e in (m['linkMap'] as Map? ?? const {}).entries)
          if (e.key is String && e.value is String)
            e.key as String: e.value as String
      },
      reason: UnfinishedReason.values.firstWhere(
        (r) => r.name == m['reason'],
        orElse: () => UnfinishedReason.interrupted,
      ),
      lastTryMs: (m['lastTryMs'] as num?)?.toInt() ?? 0,
    );
  }
}
