// Fetching a subscribed calendar, against a real local server.
//
// **Why a real `HttpServer` and not a mock.** The bug being fixed here is a
// transport bug: a university feed answered `HttpException: Connection closed
// while receiving data`. A mocked client cannot express "sends a Content-Length
// and then hangs up early" — that is precisely the behaviour under test, and it
// only exists at the socket. Each server below is a few lines and binds to
// 127.0.0.1 on an ephemeral port, so the suite stays hermetic.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openote/planner/calendar_fetch.dart';

const _ics = 'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:x\r\nSUMMARY:Lecture\r\n'
    'DTSTART:20260805T090000\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n';

void main() {
  late HttpServer server;
  late String url;

  /// Start a server whose handler is [handle]. Returns its base URL.
  Future<void> serve(FutureOr<void> Function(HttpRequest) handle) async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    url = 'http://127.0.0.1:${server.port}/cal';
    unawaited(server.forEach((req) async {
      try {
        await handle(req);
      } catch (_) {
        // A handler that deliberately hangs up throws on the next write.
      }
    }));
  }

  tearDown(() async => server.close(force: true));

  test('an ordinary feed comes back whole', () async {
    await serve((req) async {
      req.response.headers.contentType = ContentType('text', 'calendar');
      req.response.write(_ics);
      await req.response.close();
    });
    expect(await fetchCalendar(url), _ics);
  });

  test('it identifies itself, and asks for something a picky server will send',
      () async {
    String? agent;
    String? accept;
    await serve((req) async {
      agent = req.headers.value(HttpHeaders.userAgentHeader);
      accept = req.headers.value(HttpHeaders.acceptHeader);
      req.response.write(_ics);
      await req.response.close();
    });
    await fetchCalendar(url);
    // A default `Dart/3.x (dart:io)` is what several institutional WAFs drop.
    expect(agent, contains('Openote'));
    // `*/*` matters: a feed served as application/octet-stream — which several
    // university systems do, because the URL has no .ics extension — 406s
    // against a strict Accept.
    expect(accept, contains('*/*'));
  });

  test('a mid-stream hangup is retried without gzip, and then succeeds',
      () async {
    // This IS the reported failure. The first request is answered with a
    // truncated body and a forced close; the retry drops `Accept-Encoding:
    // gzip` and a server that only misbehaves for compressed responses answers
    // properly.
    var attempts = 0;
    final encodings = <String?>[];
    await serve((req) async {
      attempts++;
      encodings.add(req.headers.value(HttpHeaders.acceptEncodingHeader));
      if (attempts == 1) {
        req.response.headers.contentLength = _ics.length;
        req.response.write(_ics.substring(0, 20));
        await req.response.close();
        return;
      }
      req.response.write(_ics);
      await req.response.close();
    });

    expect(await fetchCalendar(url, sleep: (_) async {}), _ics);
    expect(attempts, 2);
    expect(encodings[1], 'identity');
  });

  test('a status the server chose is reported, not retried', () async {
    var attempts = 0;
    await serve((req) async {
      attempts++;
      req.response.statusCode = 403;
      await req.response.close();
    });

    await expectLater(
      fetchCalendar(url, sleep: (_) async {}),
      throwsA(isA<CalendarFetchException>()
          .having((e) => e.status, 'status', 403)
          // The message has to be actionable: a 403 on a calendar feed is
          // almost always "you used the public URL, you need the private one".
          .having((e) => e.message, 'message', contains('Secret address'))),
    );
    expect(attempts, 1, reason: 'retrying a 403 only makes the user wait');
  });

  test('a 404 says the link is wrong rather than showing a number', () async {
    await serve((req) async {
      req.response.statusCode = 404;
      await req.response.close();
    });
    await expectLater(
      fetchCalendar(url, sleep: (_) async {}),
      throwsA(isA<CalendarFetchException>()
          .having((e) => e.message, 'message', contains('nothing at that'))),
    );
  });

  test('a persistent hangup gives a message that says what to do next',
      () async {
    await serve((req) async {
      req.response.headers.contentLength = _ics.length;
      req.response.write(_ics.substring(0, 10));
      await req.response.close();
    });
    await expectLater(
      fetchCalendar(url, sleep: (_) async {}),
      throwsA(isA<CalendarFetchException>().having(
          (e) => e.message,
          'message',
          allOf(contains('closed the connection'),
              contains('downloading the .ics file')))),
    );
  });

  test('a redirect is followed', () async {
    await serve((req) async {
      if (req.uri.path == '/cal') {
        await req.response.redirect(
            Uri.parse('http://127.0.0.1:${server.port}/real'),
            status: 302);
        return;
      }
      req.response.write(_ics);
      await req.response.close();
    });
    expect(await fetchCalendar(url), _ics);
  });

  test('a UTF-8 BOM does not defeat the "is this a calendar" check', () async {
    // Three invisible bytes in front of BEGIN:VCALENDAR used to read to the
    // user as "Openote says my timetable is not a calendar".
    await serve((req) async {
      req.response.add([0xEF, 0xBB, 0xBF]);
      req.response.write(_ics);
      await req.response.close();
    });
    expect(await fetchCalendar(url), startsWith('BEGIN:VCALENDAR'));
  });

  test('a stray bad byte costs one character, not the semester', () async {
    await serve((req) async {
      req.response.add('BEGIN:VCALENDAR\r\nX-WR-CALNAME:Caf'.codeUnits);
      req.response.add([0xE9]); // Latin-1 é in a file labelled UTF-8
      req.response.add('\r\nEND:VCALENDAR\r\n'.codeUnits);
      await req.response.close();
    });
    final body = await fetchCalendar(url);
    expect(body, startsWith('BEGIN:VCALENDAR'));
    expect(body, contains('END:VCALENDAR'));
  });

  test('a local file path is read rather than fetched', () async {
    await serve((req) async => req.response.close());
    final tmp = Directory.systemTemp.createTempSync('onote_cal_');
    // Guarded, like every other temp-dir teardown in this suite: Windows
    // refuses to remove a directory holding a handle anything still owns, and
    // a cleanup that throws fails an otherwise passing test.
    addTearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final f = File('${tmp.path}/t.ics')..writeAsStringSync(_ics);
    expect(await fetchCalendar(f.path), _ics);
  });

  test('a missing file says so in words', () async {
    await serve((req) async => req.response.close());
    await expectLater(
      fetchCalendar('/definitely/not/here.ics'),
      throwsA(isA<CalendarFetchException>()
          .having((e) => e.message, 'message', contains('Could not read'))),
    );
  });

  test('webcal:// is treated as https', () async {
    await serve((req) async => req.response.close());
    // Nothing is listening on https here, so this only pins the rewrite: it
    // must fail as a *network* problem, not as "that is not a valid URL".
    await expectLater(
      fetchCalendar('webcal://127.0.0.1:1/x', sleep: (_) async {}),
      throwsA(isA<CalendarFetchException>()
          .having((e) => e.message, 'message', isNot(contains('valid URL')))),
    );
  });
}
