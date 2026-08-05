/// Fetching a subscribed calendar over HTTP — separated from `PlannerState` so
/// the retry ladder below can be tested against a fake server rather than only
/// against whatever the university's CDN happens to be doing today.
///
/// **Why this is more than one `HttpClient.getUrl`.** The first real timetable
/// this was pointed at (a `mytimetablecloud` feed behind an institutional WAF)
/// failed with `HttpException: Connection closed while receiving data` — a
/// mid-stream drop, not a refusal. A plain GET has three separate ways to hit
/// that against a hardened server, and Dart's defaults make two of them likely:
///
/// 1. **No `User-Agent`.** `dart:io` sends `Dart/3.x (dart:io)`, which several
///    WAF rule sets treat as a scraper and drop *after* the response line — so
///    the client sees a truncated body rather than a 403 it could report.
/// 2. **`Accept-Encoding: gzip`, added automatically.** If the response is
///    gzipped by an intermediary that then miscounts the length, `dart:io`'s
///    auto-inflate throws exactly the observed error. Asking for `identity`
///    costs a few hundred KB and removes the whole failure mode.
/// 3. **Connection reuse.** A keep-alive socket the server has already decided
///    to close races the next read.
///
/// None of these can be diagnosed from the client side, so this does not try
/// to: it **retries with progressively more conservative requests**, which is
/// cheap (a timetable is fetched a handful of times a day) and fixes all three
/// without knowing which one applied.
///
/// The other half of the job is decoding. The stream is collected to bytes and
/// decoded with `allowMalformed: true` rather than piped through `utf8.decoder`
/// — a single bad byte in a room name should not lose a whole semester's
/// timetable, and some university systems really do emit Latin-1 in a file
/// they label UTF-8.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// How many times to ask, counting the first attempt. Each retry is a
/// *different* request (see [_Attempt]), not the same one repeated — repeating
/// an identical request that a WAF has decided to drop just fails identically.
const int calendarFetchAttempts = 3;

/// Refuse a body larger than this outright. Guards memory before the string
/// exists, which the previous length check (after decoding) could not.
const int calendarFetchMaxBytes = 16 * 1024 * 1024;

/// Thrown for a failure that carries a message worth showing a student.
///
/// Every message is written to be *actionable by the person reading it* —
/// "the address needs a password" tells you to go and get the private link,
/// where `HttpException: Connection closed…` tells you nothing you can do.
class CalendarFetchException implements Exception {
  const CalendarFetchException(this.message, {this.status});

  final String message;

  /// The HTTP status, when the failure was a status rather than a transport
  /// problem. Kept so callers can distinguish "wrong link" from "no network".
  final int? status;

  @override
  String toString() => message;
}

/// One rung of the ladder. Attempt 0 is the ordinary request; each later one
/// gives up a convenience that could be what the server is objecting to.
class _Attempt {
  const _Attempt({
    required this.gzip,
    required this.keepAlive,
    required this.timeout,
  });

  final bool gzip;
  final bool keepAlive;
  final Duration timeout;

  static const ladder = <_Attempt>[
    _Attempt(gzip: true, keepAlive: true, timeout: Duration(seconds: 30)),
    // Identity encoding and a fresh connection per request: the two defaults
    // most likely to be the cause, dropped together because the goal is to
    // succeed, not to bisect someone else's proxy.
    _Attempt(gzip: false, keepAlive: false, timeout: Duration(seconds: 45)),
    _Attempt(gzip: false, keepAlive: false, timeout: Duration(seconds: 60)),
  ];
}

/// The User-Agent every request identifies itself with.
///
/// A real product name and a URL, because the alternative — pretending to be a
/// browser — is the thing that gets a client blocked once an administrator
/// notices, and because an institution that wants to talk to us should be able
/// to find out who we are from a log line.
const String calendarUserAgent =
    'Openote/1.0 (+https://openote.org; calendar subscription)';

/// Fetch [url] and return its body.
///
/// Accepts `http`, `https`, `webcal` (which is plain HTTPS with a scheme that
/// makes desktop calendar apps take the click) and a local filesystem path, so
/// "export the .ics and point at the file" keeps working offline.
///
/// [openClient] exists for tests; production passes nothing.
Future<String> fetchCalendar(
  String url, {
  HttpClient Function()? openClient,
  Future<void> Function(Duration)? sleep,
}) async {
  final target = url.trim();
  if (target.isEmpty) {
    throw const CalendarFetchException('No address given');
  }
  if (target.startsWith('webcal://')) {
    return fetchCalendar('https://${target.substring('webcal://'.length)}',
        openClient: openClient, sleep: sleep);
  }
  if (!target.startsWith('http://') && !target.startsWith('https://')) {
    // A path, not a URL. Read it and stop — there is nothing to retry.
    try {
      final bytes = await File(target).readAsBytes();
      return _decode(bytes);
    } on FileSystemException {
      throw const CalendarFetchException('Could not read that file');
    }
  }

  final Uri uri;
  try {
    uri = Uri.parse(target);
  } on FormatException {
    throw const CalendarFetchException('That address is not a valid URL');
  }

  Object? lastTransportError;
  for (var i = 0; i < calendarFetchAttempts; i++) {
    final attempt = _Attempt.ladder[i.clamp(0, _Attempt.ladder.length - 1)];
    try {
      return await _once(uri, attempt, openClient);
    } on CalendarFetchException {
      // A status the server chose is an answer, not a glitch. Retrying a 401
      // or a 404 two more times only makes the user wait three times as long
      // to read the same sentence.
      rethrow;
    } catch (e) {
      lastTransportError = e;
      if (i == calendarFetchAttempts - 1) break;
      // A short, growing pause. The failure this exists for is usually
      // immediate, so the wait is about letting a rate limiter forget us
      // rather than about giving a slow server time.
      final wait = Duration(milliseconds: 400 * (i + 1));
      await (sleep == null ? Future<void>.delayed(wait) : sleep(wait));
    }
  }
  throw CalendarFetchException(_transportMessage(lastTransportError));
}

Future<String> _once(
  Uri uri,
  _Attempt attempt,
  HttpClient Function()? openClient,
) async {
  final client = (openClient?.call() ?? HttpClient())
    ..connectionTimeout = const Duration(seconds: 20)
    ..idleTimeout = const Duration(seconds: 5)
    ..userAgent = calendarUserAgent
    // Institutional feeds redirect a lot: http→https, then a load balancer,
    // then a per-region host. Five is Dart's default and is plenty; the point
    // of naming it is that a redirect chain must not be mistaken for success.
    ..maxConnectionsPerHost = 2;
  try {
    final req = await client.getUrl(uri);
    req.followRedirects = true;
    req.maxRedirects = 5;
    // `*/*` at the end matters: a server that serves the feed as
    // `application/octet-stream` — which several university systems do,
    // because the URL has no `.ics` extension — will 406 a strict Accept.
    req.headers.set(HttpHeaders.acceptHeader,
        'text/calendar, text/plain;q=0.9, */*;q=0.8');
    if (!attempt.gzip) {
      req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    }
    if (!attempt.keepAlive) {
      req.persistentConnection = false;
      req.headers.set(HttpHeaders.connectionHeader, 'close');
    }
    final res = await req.close().timeout(attempt.timeout);

    if (res.statusCode != 200) {
      throw CalendarFetchException(_statusMessage(res.statusCode),
          status: res.statusCode);
    }
    final declared = res.headers.contentLength;
    if (declared > calendarFetchMaxBytes) {
      throw CalendarFetchException(
          'That calendar is larger than '
          '${calendarFetchMaxBytes ~/ (1024 * 1024)} MB',
          status: res.statusCode);
    }
    final bytes = await _collect(res, attempt.timeout);
    return _decode(bytes);
  } finally {
    client.close(force: true);
  }
}

/// Read the whole body into memory, bounded.
///
/// Bounded *while reading* rather than after: a feed that is accidentally a
/// 2 GB error log should not be fully downloaded before being rejected.
Future<Uint8List> _collect(Stream<List<int>> body, Duration timeout) async {
  final sink = BytesBuilder(copy: false);
  await for (final chunk in body.timeout(timeout)) {
    sink.add(chunk);
    if (sink.length > calendarFetchMaxBytes) {
      throw const CalendarFetchException('That calendar is larger than '
          '${calendarFetchMaxBytes ~/ (1024 * 1024)} MB');
    }
  }
  return sink.takeBytes();
}

/// Bytes → text, forgivingly.
///
/// A UTF-8 BOM is stripped because it would otherwise sit in front of
/// `BEGIN:VCALENDAR` and defeat both the sanity check and the parser's first
/// content line — an invisible three bytes that reads to the user as "Openote
/// says my timetable is not a calendar".
String _decode(List<int> bytes) {
  var data = bytes;
  if (data.length >= 3 &&
      data[0] == 0xEF &&
      data[1] == 0xBB &&
      data[2] == 0xBF) {
    data = data.sublist(3);
  }
  return utf8.decode(data, allowMalformed: true);
}

/// What a status code means to someone trying to see their timetable.
String _statusMessage(int status) => switch (status) {
      401 || 403 =>
        'That calendar needs a password. Most calendars have a separate '
            'private link that does not — in Google Calendar it is Settings ▸ '
            'the calendar ▸ "Secret address in iCal format".',
      404 => 'There is nothing at that address (404). Check the link, and that '
          'it has not expired.',
      429 => 'The calendar server asked us to slow down. Try again in a few '
          'minutes.',
      >= 500 => 'The calendar server had a problem ($status). That is at their '
          'end — try again later.',
      _ => 'The server answered $status',
    };

/// What a *transport* failure means, after the ladder has already been tried.
///
/// The messages name the retry explicitly. A student who is told "we tried
/// three times" stops wondering whether clicking Refresh again would help.
String _transportMessage(Object? e) {
  if (e is SocketException) {
    return 'Could not reach that address — check the link and your connection';
  }
  if (e is HandshakeException) {
    return 'Could not establish a secure connection to that server';
  }
  if (e is TimeoutException) {
    return 'The server took too long to answer (tried $calendarFetchAttempts '
        'times)';
  }
  if (e is HttpException) {
    // The observed failure. Said in full, because the useful half of the
    // message is what to do next.
    return 'The server closed the connection before sending the whole '
        'calendar (tried $calendarFetchAttempts times). If the link works in '
        'a browser, the calendar server may be blocking non-browser apps — '
        'downloading the .ics file and choosing it here will work.';
  }
  if (e is FormatException) return 'That address is not a valid URL';
  final s = e?.toString() ?? 'Unknown error';
  return s.startsWith('Exception: ') ? s.substring(11) : s;
}
