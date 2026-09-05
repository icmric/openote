/// **Reading a OneNote notebook out of Microsoft Graph.**
///
/// The fetching half, kept apart from [readGraphPage]'s conversion half so
/// that everything expensive to get wrong stays testable without an account.
/// This file is deliberately thin: list, fetch, retry, paginate.
///
/// ## What it is careful about
///
///  * **Throttling.** The OneNote endpoints throttle harder than most of
///    Graph, and a five-year notebook is hundreds of requests. A 429 carries
///    `Retry-After`; honouring it is the difference between an import that
///    takes a few minutes and one that gets the account rate-limited.
///  * **Paging.** Graph returns at most a hundred pages per request and hands
///    back `@odata.nextLink`. Ignoring it silently imports the first hundred
///    pages of a section and nothing else, which is exactly the kind of quiet
///    partial success this project refuses.
///  * **Section groups.** They nest arbitrarily, so they are walked
///    recursively and flattened into the `/`-joined path the importer already
///    understands from `.one` files.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// One notebook, as the picker shows it.
class GraphNotebook {
  const GraphNotebook(
      {required this.id, required this.name, this.lastModified});
  final String id;
  final String name;
  final DateTime? lastModified;
}

/// A section, carrying the section-group path it was found under.
class GraphSectionRef {
  const GraphSectionRef(
      {required this.id, required this.name, this.groupPath = ''});
  final String id;
  final String name;

  /// `Y1/S2`, the way the `.one` parser spells a nested group. Empty at the
  /// notebook's top level.
  final String groupPath;
}

/// A page's metadata, before its content is fetched.
class GraphPageRef {
  const GraphPageRef({
    required this.id,
    required this.title,
    this.level = 0,
    this.createdIso,
    this.oneNoteId,
  });
  final String id;
  final String title;
  final int level;
  final String? createdIso;

  /// The GUID OneNote's own links use, taken from `links.oneNoteClientUrl`.
  ///
  /// Not the same thing as [id], which is Graph's. A page's own address inside
  /// a notebook — `onenote:…&page-id={C60353C1-…}` — is written with this one,
  /// so it is what a cross-reference has to be matched against.
  final String? oneNoteId;
}

/// The `page-id` in a OneNote URL, normalised.
///
/// The two places it appears disagree cosmetically: `links.oneNoteClientUrl`
/// writes it bare and lower-case, an `<a href>` inside a page writes it in
/// braces and upper-case. Both are the same GUID.
String? oneNotePageIdIn(String url) {
  final m = RegExp(r'page-id=\{?([0-9a-fA-F-]{36})\}?').firstMatch(url);
  return m == null ? null : m.group(1)!.toLowerCase();
}

/// Something went wrong talking to Graph. Always a sentence: these reach a
/// person.
class GraphException implements Exception {
  GraphException(this.message, {this.details});
  final String message;
  final String? details;
  @override
  String toString() => details == null ? message : '$message ($details)';
}

/// The import is stopping because the service will not let it get on.
///
/// Its own type so that it cannot be mistaken for one page failing. Every
/// other [GraphException] here is caught somewhere and turned into "skip this
/// page" — which is right for one bad page and catastrophic for this one,
/// where the answer would be a notebook of hundreds of empty pages, silently.
class GraphGaveUp extends GraphException {
  GraphGaveUp(super.message, {super.details});
}

/// The person pressed Stop.
///
/// Not a failure, and its own type so the import can tell it apart from one.
/// Before this existed the client had **no idea cancellation was a thing**:
/// Stop set a flag that was only read between batches, so once a request was
/// inside a throttle wait or a retry loop — which is exactly when somebody
/// reaches for Stop — nothing ever read it again. The card said "Stopping…"
/// and stayed there.
class GraphCancelled extends GraphException {
  GraphCancelled() : super('Stopped.');
}

/// How many requests are allowed to be in flight at once.
///
/// The import is almost entirely **waiting**: a page is one round trip, and
/// doing them one after another made a large notebook take about five seconds
/// per page. Six at a time is the whole speed-up, and the number is a
/// compromise rather than a maximum — the OneNote endpoints throttle freely,
/// and a wider pipe just converts latency into 429s, which cost more than they
/// save because every one of them is a wasted round trip AND a wait.
const int kGraphConcurrency = 6;

/// Run [jobs] with at most [limit] outstanding, keeping the order of results.
///
/// The limit is a **local** one. What actually bounds requests is the gate
/// inside [GraphClient], because these pools nest — a pool over pages whose
/// jobs each open a pool over that page's images multiplied six by six and
/// put thirty-six requests in flight, which OneNote answers with 429s. A 429
/// costs a round trip AND the wait after it, so the throttling was slower than
/// the sequential code it replaced.
Future<List<T>> graphPool<T>(List<Future<T> Function()> jobs,
    {int limit = kGraphConcurrency}) async {
  final results = List<T?>.filled(jobs.length, null);
  var next = 0;
  Future<void> worker() async {
    while (true) {
      final i = next++;
      if (i >= jobs.length) return;
      results[i] = await jobs[i]();
    }
  }

  final n = jobs.length < limit ? jobs.length : limit;
  await Future.wait([for (var i = 0; i < n; i++) worker()]);
  return results.cast<T>();
}

/// How many pages one `\$batch` carries. Twenty is Microsoft's maximum.
const int kGraphBatchRequests = 20;

/// Talks to Graph on behalf of a signed-in student.
class GraphClient {
  GraphClient({required this.token, HttpClient? client})
      : _client = client ?? HttpClient() {
    // Dart pools connections per host, but only six by default. Every request
    // here goes to one host, so six is also the ceiling on how much good
    // [kGraphConcurrency] can do — and a seventh request would queue behind a
    // finished one rather than opening its own.
    _client.maxConnectionsPerHost = kGraphConcurrency + 2;
    // Long enough that a whole notebook reuses the same handful of sockets
    // rather than paying a TLS handshake every few pages.
    _client.idleTimeout = const Duration(seconds: 60);
    _client.connectionTimeout = const Duration(seconds: 30);
  }

  /// **Asked before every wait and before every retry.**
  ///
  /// Cancellation has to reach in this far. Checking it only between batches
  /// means it is never checked during the one situation people actually
  /// cancel in: a long throttle wait.
  bool Function()? isCancelled;

  void _stopIfAsked() {
    if (isCancelled?.call() ?? false) throw GraphCancelled();
  }

  /// How the client gets a live access token. A callback rather than a string
  /// because an import can outlast the one-hour token, and asking for it per
  /// request is what makes the refresh invisible.
  final Future<String> Function() token;

  final HttpClient _client;

  /// **The one gate every request passes through.**
  ///
  /// Counts requests actually in flight, wherever they were started from, so
  /// nesting a pool inside a pool cannot exceed it. Without this the limit was
  /// per call site and multiplied.
  int _inFlight = 0;
  final List<Completer<void>> _waiting = [];

  /// **How many requests to have in flight, adjusted as the service answers.**
  ///
  /// A fixed number cannot be right, because the limit is OneNote's and it is
  /// not published. Too low wastes the whole import waiting; too high spends
  /// it collecting 429s, and a 429 costs a round trip AND the wait after it —
  /// so being too fast is slower than being too slow.
  ///
  /// Measured on a real notebook: a burst of six ran at about 350 ms a page,
  /// and a sustained run of the same six was throttled inside seven minutes
  /// and stayed throttled. Neither number is the sustainable rate; the
  /// sustainable rate is what this looks for.
  ///
  /// Halve on a refusal, add one after a run of successes. That is TCP's
  /// congestion control and it is the same problem: find the fastest rate a
  /// shared resource will accept without being told what it is.
  int _limit = kGraphConcurrency;
  int _goodRun = 0;

  /// After this many clean replies, try one more at a time.
  static const int _speedUpAfter = 24;

  void _sawRefusal() {
    _goodRun = 0;
    _refusedSince ??= DateTime.now();
    final next = _limit ~/ 2;
    _limit = next < 1 ? 1 : next;
  }

  /// Throw when the service has been refusing for longer than anyone should
  /// be asked to wait. Checked where a refusal is recorded, so it cannot be
  /// reached by a request that is merely slow.
  void _stopIfHopeless() {
    if (_refusedSince == null) return;
    if (refusedFor < giveUpAfterThrottledFor) return;
    // Two sentences, and neither of them mentions what was kept — the job
    // adds that, because only the job knows the number. Saying it in both
    // places produced "…has been kept — try again… (152 pages so far.)".
    throw GraphGaveUp(
        'Microsoft is limiting how fast Openote can read this account, and '
        'has been for several minutes. Try again in a little while.',
        details: 'throttled continuously for ${refusedFor.inSeconds}s');
  }

  void _sawSuccess() {
    _refusedSince = null;
    if (_limit >= kGraphConcurrency) return;
    if (++_goodRun < _speedUpAfter) return;
    _goodRun = 0;
    _limit++;
    // Wake one waiter, since there is now room for it.
    if (_waiting.isNotEmpty && _inFlight < _limit) {
      _waiting.removeAt(0).complete();
    }
  }

  /// What the gate is currently allowing, for tests and for the log.
  @visibleForTesting
  int get concurrencyLimit => _limit;

  Future<void> _acquire() async {
    _stopIfAsked();
    if (_inFlight < _limit) {
      _inFlight++;
      return;
    }
    final c = Completer<void>();
    _waiting.add(c);
    await c.future;
    // Checked again on the way out: a request can sit in this queue for the
    // whole of a long throttle wait, and the answer may have changed while it
    // was there.
    if (isCancelled?.call() ?? false) {
      _wakeNext();
      throw GraphCancelled();
    }
    _inFlight++;
  }

  /// Let the next queued request through. Used when one leaves without ever
  /// taking its slot.
  void _wakeNext() {
    if (_waiting.isNotEmpty && _inFlight < _limit) {
      _waiting.removeAt(0).complete();
    }
  }

  void _release() {
    _inFlight--;
    if (_waiting.isNotEmpty && _inFlight < _limit) {
      _waiting.removeAt(0).complete();
    }
  }

  static const String _root = 'https://graph.microsoft.com/v1.0';
  static const String _base = '$_root/me/onenote';

  /// Test seam: answers requests without a network.
  @visibleForTesting
  static Future<(int, String, Map<String, String>)> Function(String url)?
      debugFetch;

  /// **How long any one request may take before it is abandoned.**
  ///
  /// Found by importing a real notebook twice: both runs stopped at exactly
  /// page 152 of 332 and then sat there for over ten minutes. Not throttling —
  /// throttling is not deterministic, and the second run had the whole
  /// adaptive rate control the first did not. It was a request that never came
  /// back.
  ///
  /// Every request holds one of [kGraphConcurrency] slots while it runs, and
  /// with no deadline it holds one **for ever**. Six of those and the import
  /// is stopped permanently, with no error, no progress and nothing to say why
  /// — the exact shape of what was seen.
  ///
  /// Ninety seconds is generous on purpose: a page carrying three hundred ink
  /// strokes was 292 KB, and an attachment can be far larger. This is the
  /// deadline for a request that has *stopped*, not a budget for a slow one.
  /// Not `const`: a test cannot wait ninety seconds to prove a deadline
  /// works, and this is exactly the property worth proving.
  @visibleForTesting
  static Duration kRequestTimeout = const Duration(seconds: 90);

  /// A request that ran out of time. Not a real HTTP status — 408 is the
  /// nearest thing — and deliberately distinguished from throttling, because a
  /// stalled connection is not the service asking anyone to slow down.
  static const int _timedOut = 408;

  /// **A server fault, which is not the same as being told to slow down.**
  ///
  /// 429 and 503 mean *too much, wait* — they carry `Retry-After`, they are
  /// the account's own limit, and the right answer is to narrow the pipe. 500,
  /// 502 and 504 mean the service broke on this one request. Retrying is right
  /// and narrowing is not: nothing has asked us to go slower, and punishing
  /// the whole import for one bad response would be reading an apology as an
  /// instruction.
  ///
  /// Only 429 and 503 were retried before. So a single 500 on any one of
  /// twenty-five section requests ended the whole import at once, with nothing
  /// kept — reported as an import that failed almost instantly saying
  /// "Microsoft is having trouble at the moment". The trouble was real; giving
  /// up on the first one was ours.
  static bool _serverFault(int s) => s == 500 || s == 502 || s == 504;

  /// The network was not there at all. Not a real HTTP status either.
  static const int _noNetwork = 499;

  /// **How many times a vanished network is retried before believing it.**
  ///
  /// Watched happen: a confirmation import died at seven minutes on
  /// `Failed host lookup: 'graph.microsoft.com'`, and the same lookup
  /// succeeded from the same machine seconds later. A momentary DNS drop — a
  /// laptop changing wifi, a router blinking — was ending a two-minute import
  /// outright, on the first blip, with no second try.
  ///
  /// Three quick attempts covers a blip in about three seconds. Deliberately
  /// no more than that: if the connection is genuinely gone, saying so
  /// promptly is more useful than a long silence, and the student is told
  /// plainly that nothing already brought over was lost.
  static const int _networkRetries = 3;

  /// The last real socket failure, kept so the honest message can carry it.
  String? _lastNetworkError;

  /// How many times a throttled request is retried before giving up.
  ///
  /// Raised from five after a measured run: reading three pages from each of
  /// sixty sections got a 429 after six and a half minutes, and a **second
  /// attempt minutes later was throttled on its first request**. OneNote's
  /// cooldown is long, so five quick retries covering fifteen seconds gave up
  /// while the wait had barely started, and the import failed rather than
  /// waited.
  static const int _maxRetries = 10;

  /// The longest a single backoff will wait before trying again.
  static const Duration _maxBackoff = Duration(minutes: 2);

  /// **How long the client will go on being refused before it stops.**
  ///
  /// Measured on a genuinely rate-limited account: forty minutes, one page
  /// imported, and every line of the log a throttle wait. Retrying for ever is
  /// not persistence, it is a hang with a progress message — and the student
  /// is sitting in front of a notebook that is never going to finish.
  ///
  /// Four minutes of being refused with nothing getting through is enough to
  /// say so and stop, keeping every page that did arrive. Trying again later
  /// is a real answer; waiting out an hour is not.
  static Duration giveUpAfterThrottledFor = const Duration(minutes: 4);

  /// When the current unbroken run of refusals began, or null if the last
  /// request got through.
  DateTime? _refusedSince;

  /// How long the service has been refusing without a single success.
  Duration get refusedFor => _refusedSince == null
      ? Duration.zero
      : DateTime.now().difference(_refusedSince!);

  /// Nothing is sent before this moment.
  ///
  /// **Shared across every request, not per request.** A 429 means the whole
  /// application has been asked to slow down; letting the other five in-flight
  /// requests carry on regardless is what turns one 429 into six, each costing
  /// a round trip AND its own wait. When one request is told to back off, all
  /// of them do.
  DateTime _quietUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// Set when the client is waiting out a throttle, so the import can say so
  /// rather than looking frozen.
  Duration? get throttledFor {
    final left = _quietUntil.difference(DateTime.now());
    return left.isNegative ? null : left;
  }

  /// Called when a throttle starts or ends, for the progress line.
  void Function(Duration? waiting)? onThrottle;

  void close() => _client.close(force: true);

  /// Every notebook the signed-in account can read.
  Future<List<GraphNotebook>> notebooks() async {
    final rows = await _all('$_base/notebooks?\$select=id,displayName,'
        'lastModifiedDateTime&\$orderby=lastModifiedDateTime%20desc');
    return [
      for (final r in rows)
        GraphNotebook(
          id: r['id'] as String,
          name: (r['displayName'] as String?)?.trim().isNotEmpty == true
              ? (r['displayName'] as String).trim()
              : 'Untitled notebook',
          lastModified: DateTime.tryParse(
              (r['lastModifiedDateTime'] as String?) ?? ''),
        ),
    ];
  }

  /// Every section in a notebook, including those inside section groups.
  ///
  /// Flattened, because the importer takes a `/`-joined group path per section
  /// rather than a tree — the same shape the `.one` parser produces from a
  /// folder hierarchy.
  Future<List<GraphSectionRef>> sections(String notebookId) async {
    // Both arms at once. A notebook organised by year and semester has a dozen
    // groups, each needing its own request, and walking them in sequence was
    // most of the wait between choosing a notebook and seeing anything.
    //
    // **Fetched in parallel, assembled in order.** Appending to one shared
    // list as the replies arrived would have put the student's sections in
    // whatever order the network happened to answer in — a different order
    // every import, and never OneNote's. So each call returns its own list and
    // the results are concatenated afterwards, which is deterministic no
    // matter who answers first.
    final results = await Future.wait([
      _sectionsAt('$_base/notebooks/$notebookId/sections', ''),
      _groupsAt('$_base/notebooks/$notebookId/sectionGroups', ''),
    ]);
    return [for (final list in results) ...list];
  }

  Future<List<GraphSectionRef>> _sectionsAt(
      String url, String groupPath) async {
    final rows = await _all('$url?\$select=id,displayName');
    return [
      for (final r in rows)
        GraphSectionRef(
          id: r['id'] as String,
          name: (r['displayName'] as String?)?.trim().isNotEmpty == true
              ? (r['displayName'] as String).trim()
              : 'Untitled section',
          groupPath: groupPath,
        ),
    ];
  }

  /// Section groups nest, so this recurses and joins the names with `/`.
  Future<List<GraphSectionRef>> _groupsAt(
      String url, String parentPath) async {
    final groups = await _all('$url?\$select=id,displayName');
    final perGroup = await Future.wait([
      for (final g in groups)
        () async {
          final id = g['id'] as String;
          final name = (g['displayName'] as String?)?.trim() ?? '';
          final path = parentPath.isEmpty ? name : '$parentPath/$name';
          final inner = await Future.wait([
            _sectionsAt('$_base/sectionGroups/$id/sections', path),
            _groupsAt('$_base/sectionGroups/$id/sectionGroups', path),
          ]);
          return [for (final list in inner) ...list];
        }(),
    ]);
    return [for (final list in perGroup) ...list];
  }

  /// A section's pages, oldest first so the imported order matches OneNote's.
  /// **How deep each page is nested, by asking the question backwards.**
  ///
  /// `level` is never returned. `$select=id,title,level` comes back as
  /// `[id,title]` with the field silently dropped, on v1.0 and on beta, on a
  /// collection and on a single page — all four checked against the live
  /// service. For a long time this was written down here as settled: subpages
  /// cannot be nested over Graph, and the `.onepkg` route is the only one that
  /// keeps them.
  ///
  /// That was wrong, and the clue was sitting in the same paragraph.
  /// `$orderby=order` **works**, which means the fields exist server-side and
  /// are merely never projected into the response. A field the server can sort
  /// by is a field it may also FILTER by — and a filter turns *"tell me this
  /// page's level"* into *"tell me which pages have this level"*. Same
  /// information, asked the other way round, and no guessing from anybody's
  /// title.
  ///
  /// It works. Measured on a real section of 80 pages:
  ///
  /// ```
  /// $filter=level eq 0  -> Week 12, Week 11: Power Series, Week 10: …
  /// $filter=level eq 1  -> Test Notes, Taylor Series, Maclaurin Series, …
  /// $filter=level eq 2  -> none
  /// $filter=level eq 99 -> none        <- the control
  /// ```
  ///
  /// The control is the part that makes it evidence rather than coincidence:
  /// a filter that is being IGNORED returns everything, so an impossible value
  /// returning nothing proves the server is really applying it.
  ///
  /// Costs one extra request per level per section, so [maxLevel] stops at
  /// OneNote's own limit — its UI offers two levels of indent and no more.
  /// Only `id` is asked for, because the levels are joined back onto the page
  /// list by id and nothing else is needed.
  Future<Map<String, int>> pageLevels(String sectionId,
      {int maxLevel = 2}) async {
    final out = <String, int>{};
    for (var level = 1; level <= maxLevel; level++) {
      final rows = await _all('$_base/sections/$sectionId/pages'
          '?\$filter=level%20eq%20$level&\$select=id&\$top=100');
      // An empty level means there is nothing deeper either: OneNote cannot
      // make a sub-subpage without a subpage above it.
      if (rows.isEmpty) break;
      for (final r in rows) {
        final id = r['id'] as String?;
        if (id == null) continue;
        // **A page cannot be at two depths at once.**
        //
        // The whole method rests on the service actually applying a filter it
        // never echoes back, and the failure mode if it ever stopped is nasty
        // and silent: every query returns every page, and the notebook comes
        // in with all of its pages indented to the deepest level asked for.
        //
        // An overlap is proof that happened, costs nothing to check, and the
        // safe answer is the one that was true before any of this — flat.
        // Better a notebook with no nesting than one with invented nesting.
        if (out.containsKey(id)) return const {};
        out[id] = level;
      }
    }
    return out;
  }

  Future<List<GraphPageRef>> pages(String sectionId) async {
    // **No `\$select`.** It used to ask for `level` by name and OneNote's
    // pages endpoint did not reliably return it, so every page arrived at
    // level 0 and a notebook's subpages all became top-level pages — the
    // hierarchy the `.onepkg` route keeps. Asking for the whole object costs
    // a few hundred bytes per page and cannot lose a field.
    final rows = await _all('$_base/sections/$sectionId/pages'
        '?\$orderby=order&\$top=100');
    return [
      for (final r in rows)
        GraphPageRef(
          id: r['id'] as String,
          title: (r['title'] as String?)?.trim().isNotEmpty == true
              ? (r['title'] as String).trim()
              : 'Untitled page',
          // Filled in from [pageLevels]; the field is never in the row.
          level: (r['level'] as num?)?.toInt() ?? 0,
          createdIso: r['createdDateTime'] as String?,
          oneNoteId: oneNotePageIdIn(
              (((r['links'] as Map?)?['oneNoteClientUrl'] as Map?)?['href']
                      as String?) ??
                  ''),
        ),
    ];
  }

  /// One page's content: HTML, and the InkML beside it.
  ///
  /// `includeIDs` is asked for because it also turns on the absolute-position
  /// styles the converter reads to place boxes; without it a page comes back
  /// as one undifferentiated flow and every outline lands on top of the next.
  ///
  /// `includeinkML` is what makes handwriting reachable at all — the HTML has
  /// no representation of a stroke. It changes the response into a MIME
  /// multipart body, which `readPageBody` unpicks. The cost is a few hundred
  /// bytes on a page nobody drew on (an empty `<inkml:traceGroup />` arrives
  /// either way) and real weight only where there is real ink: measured at
  /// 292 KB for a page carrying 301 traces, against 6 KB for a typical one.
  Future<String> pageHtml(String pageId) async {
    final (status, body, _) = await _fetch(
        '$_base/pages/$pageId/content?includeIDs=true&includeinkML=true');
    if (status != 200) {
      throw GraphException('A page could not be read from OneNote.',
          details: 'HTTP $status');
    }
    return body;
  }

  /// Several pages' HTML at once, in the order asked for.
  ///
  /// **The difference between minutes and tens of minutes.** A page is one
  /// round trip, and a notebook is hundreds of pages; even six at a time, a
  /// three-hundred-page notebook is fifty waves of network latency. Graph's
  /// `\$batch` carries twenty requests in a single round trip, so the same
  /// notebook is fifteen.
  ///
  /// Falls back to individual requests whenever the batch does not work — a
  /// bad status, a malformed envelope, an exception. `\$batch` has more ways to
  /// disappoint than a plain GET and none of them are worth failing an import
  /// over, so this is an optimisation that can always be skipped.
  Future<List<String?>> pageHtmlMany(List<String> pageIds) async {
    if (pageIds.isEmpty) return const [];
    final out = List<String?>.filled(pageIds.length, null);
    var allFailed = true;
    for (var start = 0; start < pageIds.length; start += kGraphBatchRequests) {
      final end = (start + kGraphBatchRequests).clamp(0, pageIds.length);
      final slice = pageIds.sublist(start, end);
      final got = await _batchPageHtml(slice);
      if (got == null) continue;
      allFailed = false;
      for (var i = 0; i < slice.length; i++) {
        out[start + i] = got[i];
      }
    }
    // Anything the batch could not supply — a failed envelope, or one entry
    // inside a good one — is fetched the ordinary way rather than lost.
    final missing = <int>[
      for (var i = 0; i < pageIds.length; i++)
        if (out[i] == null) i
    ];
    if (missing.isNotEmpty) {
      final fetched = await graphPool<String?>([
        for (final i in missing)
          () async {
            try {
              return await pageHtml(pageIds[i]);
            } on GraphGaveUp {
              rethrow;
            } on GraphCancelled {
              rethrow;
            } on GraphException {
              return null;
            }
          },
      ]);
      for (var k = 0; k < missing.length; k++) {
        out[missing[k]] = fetched[k];
      }
    }
    if (allFailed && pageIds.length > 1) {
      // Worth knowing in a debug run: the fast path is off and everything is
      // going one at a time.
      debugPrint('[openote/onenote] \$batch unavailable; fetching singly');
    }
    return out;
  }

  /// One `\$batch` POST, or null when it could not be used at all.
  ///
  /// Null means *this endpoint is no good* — a malformed envelope, an
  /// exception, a status that is not going to improve — and the caller then
  /// fetches the pages one at a time. Throttling is NOT that: it is handled
  /// here, by waiting and asking again, for the reason in the loop below.
  Future<List<String?>?> _batchPageHtml(List<String> ids) async {
    final body = jsonEncode({
      'requests': [
        for (var i = 0; i < ids.length; i++)
          {
            'id': '$i',
            'method': 'GET',
            'url': '/me/onenote/pages/${ids[i]}/content'
                '?includeIDs=true&includeinkML=true',
          }
      ]
    });
    for (var attempt = 0;; attempt++) {
      final got = await _batchOnce(body, ids, attempt);
      if (got != _retryBatch) return got;
    }
  }

  /// The sentinel [_batchPageHtml] loops on. A distinct object rather than
  /// null, because null already means something else here.
  static final List<String?> _retryBatch = List<String?>.unmodifiable(const []);

  Future<List<String?>?> _batchOnce(
      String body, List<String> ids, int attempt) async {
    final fake = debugBatch;
    // A test that stubs the ordinary fetch but not the batch must not reach
    // the real internet to discover the batch is unavailable.
    if (fake == null && debugFetch != null) return null;
    late int status;
    late String text;
    try {
      if (fake != null) {
        (status, text) = await fake(body);
      } else {
        await _waitOutThrottle();
        await _acquire();
        try {
          final t = await token();
          final req = await _client.postUrl(Uri.parse('$_root/\$batch'));
          req.headers
            ..set(HttpHeaders.authorizationHeader, 'Bearer $t')
            ..contentType = ContentType.json;
          req.write(body);
          final res = await req.close().timeout(kRequestTimeout);
          text = await res
              .transform(utf8.decoder)
              .join()
              .timeout(kRequestTimeout);
          status = res.statusCode;
        } finally {
          _release();
        }
      }
      if (_serverFault(status) && attempt < 3) {
        // Same distinction as in [_fetch]: the service broke, it did not ask
        // for room. Retried without holding everyone else back.
        await Future<void>.delayed(
            Duration(milliseconds: 400 * (1 << attempt)));
        return _retryBatch;
      }
      if (status == 429 || status == 503) {
        // **Backed off and retried as a batch, never split up.**
        //
        // The obvious thing is to give up on the batch and fetch the twenty
        // pages individually. That is precisely wrong: throttling counts
        // REQUESTS, so falling back turns one refusal into twenty more at the
        // exact moment the service has said it is overloaded — and each of
        // those carries its own wait. Retrying the batch keeps the cost at
        // twenty requests per attempt instead of forty.
        _sawRefusal();
        _stopIfHopeless();
        _holdEveryoneBack(batchThrottleHold);
        if (attempt < _maxRetries) return _retryBatch;
        return null;
      }
      if (status == 200) _sawSuccess();
      if (status != 200) return null;
      final json = jsonDecode(text) as Map<String, dynamic>;
      final responses = json['responses'] as List?;
      if (responses == null) return null;
      final out = List<String?>.filled(ids.length, null);
      for (final r in responses) {
        final m = (r as Map).cast<String, dynamic>();
        final at = int.tryParse('${m['id']}');
        if (at == null || at < 0 || at >= ids.length) continue;
        if ((m['status'] as num?)?.toInt() != 200) continue;
        out[at] = _decodeBatchBody(m['body']);
      }
      return out;
    } on GraphCancelled {
      // Same reasoning as below: stopping is a decision about the import, not
      // a verdict on this endpoint.
      rethrow;
    } on GraphGaveUp {
      // Giving up on a hopelessly throttled account is a decision about the
      // whole import, not a verdict on this endpoint. Swallowed here it would
      // read as "\$batch is no good", and the caller would answer by asking
      // for the same twenty pages one at a time — twenty more requests at the
      // exact moment the service has run out of patience.
      rethrow;
    } catch (_) {
      return null;
    }
  }

  /// A `\$batch` entry's body as text.
  ///
  /// Graph returns a JSON body as an object and anything else — HTML included
  /// — as a base64 string, so both spellings are accepted and a string that
  /// is not base64 is taken at face value rather than thrown away.
  static String? _decodeBatchBody(Object? body) {
    if (body == null) return null;
    if (body is Map || body is List) return jsonEncode(body);
    final text = '$body';
    if (text.startsWith('<')) return text;
    try {
      return utf8.decode(base64.decode(text));
    } catch (_) {
      return text;
    }
  }

  /// How long a throttled batch quiets the whole client for.
  ///
  /// A guess, because a `\$batch` envelope carries no `Retry-After` of its
  /// own — twenty seconds is short enough not to strand an import and long
  /// enough to be worth more than an immediate retry. Overridable so tests do
  /// not pay it in wall-clock time.
  @visibleForTesting
  static Duration batchThrottleHold = const Duration(seconds: 20);

  /// Test seam for the batch endpoint. Returns `(status, body)`.
  @visibleForTesting
  static Future<(int, String)> Function(String requestBody)? debugBatch;

  /// The raw JSON at [url], for looking at what Graph actually sends.
  ///
  /// Used by `tool/graph_probe.dart`. Three fixes in a row were built on an
  /// assumption about the real markup and three in a row were wrong, so the
  /// wire is worth being able to read directly.
  Future<String> debugRawJson(String url) async {
    final (status, body, _) = await _fetch(url);
    if (status != 200) {
      throw GraphException(_friendly(status), details: 'HTTP $status');
    }
    return body;
  }

  /// The raw body at [url] whatever its type, for looking at the wire.
  Future<String> debugRawText(String url) async {
    final (_, body, __) = await _fetch(url);
    return body;
  }

  /// An image or attachment's bytes, or null when it cannot be had.
  ///
  /// Null rather than throwing: one unreadable picture must cost that picture
  /// and nothing else, and the page around it is still worth importing.
  /// A picture or attachment, or null if it genuinely could not be had.
  ///
  /// **This was the one request path that ignored throttling entirely**, and a
  /// real 332-page import showed exactly what that costs: 46 pictures arrived
  /// and **4 were lost**, with nothing else lost at all. Three separate
  /// mistakes, all in the same few lines:
  ///
  ///   - It never waited out the shared quiet period, so pictures barged
  ///     through backoff that every other request was respecting — which both
  ///     loses the picture and deepens the throttling for everything else.
  ///   - `statusCode != 200` returned null, so a 429 — *come back shortly* —
  ///     was treated as *this picture does not exist*.
  ///   - There was no retry, so there was no shortly to come back in.
  ///
  /// Now it backs off and asks again like everything else. Null still means a
  /// real failure: a 404, a body that stopped arriving, an exhausted retry.
  Future<Uint8List?> resource(String url) async {
    for (var attempt = 0;; attempt++) {
      _stopIfAsked();
      await _waitOutThrottle();
      final (status, bytes, headers) = await _resourceOnce(url);
      if (status == 200 && bytes != null) {
        _sawSuccess();
        return bytes;
      }
      if (status == _noNetwork && attempt < _networkRetries) {
        await Future<void>.delayed(
            Duration(milliseconds: 400 * (1 << attempt)));
        continue;
      }
      // Anything that is not the service asking us to wait is a real failure:
      // a 404, a body that stopped arriving, a token that will not mint.
      if (status != 429 && status != 503) return null;
      if (attempt >= _maxRetries) return null;
      _sawRefusal();
      _stopIfHopeless();
      final after = int.tryParse(headers['retry-after'] ?? '') ?? 0;
      final wait = after > 0
          ? Duration(seconds: after)
          : Duration(milliseconds: 500 * (1 << attempt));
      _holdEveryoneBack(wait > _maxBackoff ? _maxBackoff : wait);
    }
  }

  /// Test seam for [resource]: answers with bytes and a status, no network.
  ///
  /// Separate from [debugFetch] because this path carries bytes rather than
  /// text, and because the retry policy above is the part worth testing —
  /// four real pictures were lost to its absence.
  @visibleForTesting
  static Future<(int, Uint8List?, Map<String, String>)> Function(String url)?
      debugResource;

  /// One attempt at fetching bytes. Never throws; a failure is a status.
  Future<(int, Uint8List?, Map<String, String>)> _resourceOnce(
      String url) async {
    final fake = debugResource;
    await _acquire();
    try {
      if (fake != null) return await fake(url).timeout(kRequestTimeout);
      final t = await token();
      final req = await _client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $t');
      final res = await req.close().timeout(kRequestTimeout);
      final headers = <String, String>{};
      res.headers.forEach((k, v) => headers[k.toLowerCase()] = v.join(','));
      if (res.statusCode != 200) return (res.statusCode, null, headers);
      // Bounded by the same deadline as everything else. A picture that stops
      // arriving halfway costs that picture; before this it cost the import,
      // by holding a slot until the process was killed.
      final bytes = await res
          .fold<List<int>>(<int>[], (a, c) => a..addAll(c))
          .timeout(kRequestTimeout);
      return (200, Uint8List.fromList(bytes), headers);
    } on SocketException catch (e) {
      // Same blip, same answer: retried a few times, then believed.
      _lastNetworkError = '$e';
      return (_noNetwork, null, const <String, String>{});
    } catch (_) {
      // Deliberately not 429: a broken socket is not the service asking for
      // patience, and retrying it as though it were would spend the whole
      // backoff budget on a connection that is simply gone.
      return (0, null, const <String, String>{});
    } finally {
      _release();
    }
  }

  /// Follow `@odata.nextLink` until Graph stops offering one.
  Future<List<Map<String, dynamic>>> _all(String url) async {
    final out = <Map<String, dynamic>>[];
    var next = url;
    // A notebook with more pages than this is not a notebook any more, and an
    // unbounded loop over a server-supplied link is not something to ship.
    for (var guard = 0; guard < 200; guard++) {
      final (status, body, _) = await _fetch(next);
      if (status != 200) {
        throw GraphException(_friendly(status), details: 'HTTP $status');
      }
      final json = jsonDecode(body) as Map<String, dynamic>;
      for (final v in (json['value'] as List? ?? const [])) {
        out.add((v as Map).cast<String, dynamic>());
      }
      final link = json['@odata.nextLink'] as String?;
      if (link == null || link.isEmpty) return out;
      next = link;
    }
    return out;
  }

  /// One request, with the throttling retry Graph's OneNote endpoints need.
  Future<(int, String, Map<String, String>)> _fetch(String url) async {
    final fake = debugFetch;
    for (var attempt = 0;; attempt++) {
      _stopIfAsked();
      await _waitOutThrottle();
      // The deadline sits HERE as well as inside the transport, so it holds
      // for the test transport too — and the property being defended (one
      // dead request must not wedge the whole import) is one that has to be
      // testable, having already cost two full import runs to find.
      // The SocketException handling sits HERE as well as inside the real
      // transport, for the same reason the deadline above does: the property
      // being defended — one blink of the network must not end an import —
      // has to hold whatever the transport is, and has to be testable without
      // unplugging a router.
      int status;
      String body;
      Map<String, String> headers;
      try {
        (status, body, headers) = await (fake != null
                ? fake(url)
                : _realFetch(url))
            .timeout(kRequestTimeout,
                onTimeout: () => (_timedOut, '', <String, String>{}));
      } on SocketException catch (e) {
        _lastNetworkError = '$e';
        status = _noNetwork;
        body = '';
        headers = const <String, String>{};
      }
      // 429 is throttling and 503 is "busy, come back"; both carry
      // Retry-After, and both are normal on a large notebook rather than
      // exceptional. A five-year notebook is hundreds of requests and OneNote
      // throttles by request COUNT, so batching reduces round trips but not
      // this — being asked to slow down is the expected path, not a failure.
      if (status == 200) _sawSuccess();
      // A request that ran out of time is retried, but WITHOUT narrowing the
      // pipe: nothing has asked us to slow down, one connection simply
      // stopped answering, and treating that as throttling would punish the
      // whole import for it.
      if (status == _timedOut && attempt < 2) continue;
      // A server fault is retried like a timeout — a few times, quickly, and
      // WITHOUT narrowing the pipe.
      if (_serverFault(status) && attempt < 3) {
        await Future<void>.delayed(
            Duration(milliseconds: 400 * (1 << attempt)));
        continue;
      }
      if (status == _noNetwork) {
        // Retried, but the pipe is NOT narrowed and nobody else is held back:
        // a missing network is not the service asking anyone to slow down,
        // and punishing the whole import for one blink would be the wrong
        // lesson to draw from it.
        if (attempt < _networkRetries) {
          await Future<void>.delayed(
              Duration(milliseconds: 400 * (1 << attempt)));
          continue;
        }
        throw GraphException(
            'Openote lost its connection to Microsoft. Check your internet '
            'and try again — nothing already imported has been lost.',
            details: _lastNetworkError);
      }
      if ((status == 429 || status == 503) && attempt < _maxRetries) {
        _sawRefusal();
        _stopIfHopeless();
        final after = int.tryParse(headers['retry-after'] ?? '') ?? 0;
        // Exponential backoff when the server did not say, because hammering
        // a throttled endpoint is how an account gets a longer ban.
        final wait = after > 0
            ? Duration(seconds: after)
            : Duration(milliseconds: 500 * (1 << attempt));
        _holdEveryoneBack(wait > _maxBackoff ? _maxBackoff : wait);
        continue;
      }
      return (status, body, headers);
    }
  }

  /// Push the shared quiet-until forward, never backward.
  void _holdEveryoneBack(Duration wait) {
    final until = DateTime.now().add(wait);
    if (until.isAfter(_quietUntil)) {
      _quietUntil = until;
      onThrottle?.call(wait);
    }
  }

  /// Sleep until the shared quiet period is over.
  Future<void> _waitOutThrottle() async {
    while (true) {
      _stopIfAsked();
      final left = _quietUntil.difference(DateTime.now());
      if (left.isNegative || left.inMilliseconds == 0) return;
      // **Reported every second, not once at the start.** The wait used to be
      // announced only when it got LONGER, so a run of one-second backoffs
      // showed "carrying on in 1s" and then sat there unchanged for as long as
      // the throttling lasted — a frozen number is worse than no number,
      // because it looks like the app has stopped rather than that it is
      // waiting.
      onThrottle?.call(left);
      // In slices, so a cancelled import is not stuck behind a two-minute
      // sleep it can no longer do anything with — and so the countdown above
      // actually counts down.
      final slice = left > const Duration(seconds: 1)
          ? const Duration(seconds: 1)
          : left;
      await Future<void>.delayed(slice);
    }
  }

  Future<(int, String, Map<String, String>)> _realFetch(String url) async {
    await _acquire();
    try {
      final t = await token();
      final req = await _client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $t');
      final res = await req.close().timeout(kRequestTimeout);
      final body =
          await res.transform(utf8.decoder).join().timeout(kRequestTimeout);
      final headers = <String, String>{};
      res.headers.forEach((k, v) => headers[k.toLowerCase()] = v.join(','));
      return (res.statusCode, body, headers);
    } on TimeoutException {
      return (_timedOut, '', <String, String>{});
    } on SocketException catch (e) {
      // NOT thrown from here any more. Throwing on the first failed lookup
      // ended a whole import for a drop that had already healed by the time
      // anybody read the message. [_fetch] decides whether to believe it.
      _lastNetworkError = '$e';
      return (_noNetwork, '', <String, String>{});
    } finally {
      _release();
    }
  }

  static String _friendly(int status) => switch (status) {
        _timedOut => 'Microsoft stopped responding partway through. Check your '
            'internet and try again — nothing already imported has been lost.',
        401 => 'Your Microsoft sign-in has expired. Sign in again to carry on.',
        403 => 'Microsoft would not allow Openote to read that notebook.',
        404 => 'That notebook is no longer in OneNote.',
        429 => 'Microsoft is asking Openote to slow down. Try again shortly.',
        >= 500 => 'Microsoft is having trouble at the moment. Try again '
            'shortly — nothing already imported has been lost.',
        _ => 'OneNote could not be read just now.',
      };
}
