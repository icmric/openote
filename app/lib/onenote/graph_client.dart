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
    final next = _limit ~/ 2;
    _limit = next < 1 ? 1 : next;
  }

  void _sawSuccess() {
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
    if (_inFlight < _limit) {
      _inFlight++;
      return;
    }
    final c = Completer<void>();
    _waiting.add(c);
    await c.future;
    _inFlight++;
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
          final res = await req.close();
          text = await res.transform(utf8.decoder).join();
          status = res.statusCode;
        } finally {
          _release();
        }
      }
      if (status == 429 || status == 503) {
        // Falling straight through to twenty individual requests would be
        // twenty more 429s. Back off first, then let the caller retry them
        // one at a time through the same gate.
        _sawRefusal();
        _holdEveryoneBack(batchThrottleHold);
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
  Future<Uint8List?> resource(String url) async {
    await _acquire();
    try {
      final t = await token();
      final req = await _client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $t');
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final chunks = <int>[];
      await for (final c in res) {
        chunks.addAll(c);
      }
      return Uint8List.fromList(chunks);
    } catch (_) {
      return null;
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
      await _waitOutThrottle();
      final (status, body, headers) = fake != null
          ? await fake(url)
          : await _realFetch(url);
      // 429 is throttling and 503 is "busy, come back"; both carry
      // Retry-After, and both are normal on a large notebook rather than
      // exceptional. A five-year notebook is hundreds of requests and OneNote
      // throttles by request COUNT, so batching reduces round trips but not
      // this — being asked to slow down is the expected path, not a failure.
      if (status == 200) _sawSuccess();
      if ((status == 429 || status == 503) && attempt < _maxRetries) {
        _sawRefusal();
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
      final left = _quietUntil.difference(DateTime.now());
      if (left.isNegative || left.inMilliseconds == 0) return;
      // In slices, so a cancelled import is not stuck behind a two-minute
      // sleep it can no longer do anything with.
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
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final headers = <String, String>{};
      res.headers.forEach((k, v) => headers[k.toLowerCase()] = v.join(','));
      return (res.statusCode, body, headers);
    } on SocketException catch (e) {
      throw GraphException(
          'Openote lost its connection to Microsoft. Check your internet and '
          'try again — nothing already imported has been lost.',
          details: '$e');
    } finally {
      _release();
    }
  }

  static String _friendly(int status) => switch (status) {
        401 => 'Your Microsoft sign-in has expired. Sign in again to carry on.',
        403 => 'Microsoft would not allow Openote to read that notebook.',
        404 => 'That notebook is no longer in OneNote.',
        429 => 'Microsoft is asking Openote to slow down. Try again shortly.',
        >= 500 => 'Microsoft is having trouble at the moment. Try again '
            'shortly — nothing already imported has been lost.',
        _ => 'OneNote could not be read just now.',
      };
}
