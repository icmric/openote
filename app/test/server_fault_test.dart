// A server that breaks, versus a server that asks for room.
//
// Reported: an import that failed almost instantly, saying "Microsoft is
// having trouble at the moment" — a 5xx.
//
// The 5xx was genuinely Microsoft's. Giving up on the first one was ours, in
// two separate places:
//
//   1. **Only 429 and 503 were retried.** 500, 502 and 504 fell straight
//      through to a thrown exception with no second attempt at all, which is
//      why it failed *quickly*. Those codes mean the service broke on this one
//      request, and a transient server fault is the most retryable thing there
//      is.
//   2. **One section's page list taking the whole notebook with it.** The
//      twenty-five listing requests go out together, so any one of them
//      throwing ended the import before a single page had been written.
//
// The distinction that matters and is easy to get wrong: 429 and 503 mean
// *too much, wait* — they carry `Retry-After` and the right answer is to
// narrow the pipe. 500/502/504 mean *I broke* — retrying is right, narrowing
// is not, and treating an apology as an instruction would punish the whole
// import for one bad response.

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/onenote/graph_client.dart';

void main() {
  tearDown(() => GraphClient.debugFetch = null);

  const page = '<html><body><p>hi</p></body></html>';

  group('a server fault is retried', () {
    for (final code in [500, 502, 504]) {
      test('$code is tried again rather than thrown on sight', () async {
        var n = 0;
        GraphClient.debugFetch = (url) async {
          n++;
          if (n == 1) return (code, '', <String, String>{});
          return (200, page, <String, String>{});
        };
        final c = GraphClient(token: () async => 't');

        expect(await c.pageHtml('p1'), contains('hi'));
        expect(n, 2, reason: 'a $code used to end the import outright');
      });
    }

    test('but not for ever — a service that is really down says so', () async {
      var n = 0;
      GraphClient.debugFetch = (url) async {
        n++;
        return (500, '', <String, String>{});
      };
      final c = GraphClient(token: () async => 't');

      await expectLater(c.pageHtml('p1'), throwsA(isA<GraphException>()));
      expect(n, lessThanOrEqualTo(5),
          reason: 'a few quick tries, not the ten a throttle gets');
    });

    test('and it does NOT narrow the pipe', () async {
      // The distinction. A 500 is not the service asking for room, so
      // halving concurrency for it would punish every other page for one bad
      // response.
      var n = 0;
      GraphClient.debugFetch = (url) async {
        n++;
        if (n == 1) return (500, '', <String, String>{});
        return (200, page, <String, String>{});
      };
      final c = GraphClient(token: () async => 't');
      final before = c.concurrencyLimit;

      await c.pageHtml('p1');
      expect(c.concurrencyLimit, before);
      expect(c.refusedFor, Duration.zero,
          reason: 'a fault is not a refusal, so it starts no give-up clock');
    });

    test('a throttle still DOES narrow it', () async {
      // The other half of the same decision, so the two cannot be conflated
      // by a later change.
      var n = 0;
      GraphClient.debugFetch = (url) async {
        n++;
        if (n == 1) {
          return (429, '', <String, String>{'retry-after': '0'});
        }
        return (200, page, <String, String>{});
      };
      final c = GraphClient(token: () async => 't');
      final before = c.concurrencyLimit;

      await c.pageHtml('p1');
      expect(c.concurrencyLimit, lessThan(before));
    });
  });

  group('what is NOT a transient fault', () {
    test('a 404 is answered at once, not retried', () async {
      // Also through a listing call, for the same reason.
      // Retrying something that will never work spends the budget for
      // something that might.
      var n = 0;
      GraphClient.debugFetch = (url) async {
        n++;
        return (404, '', <String, String>{});
      };
      final c = GraphClient(token: () async => 't');

      await expectLater(c.pages('s1'), throwsA(isA<GraphException>()));
      expect(n, 1);
    });

    test('a 401 says the sign-in expired, once', () async {
      // Through a LISTING call: reading one page has its own wording, and the
      // status-to-sentence mapping being tested here is the listing path's.
      var n = 0;
      GraphClient.debugFetch = (url) async {
        n++;
        return (401, '', <String, String>{});
      };
      final c = GraphClient(token: () async => 't');

      await expectLater(
        c.pages('s1'),
        throwsA(isA<GraphException>()
            .having((e) => e.message, 'message', contains('sign-in'))),
      );
      expect(n, 1);
    });
  });

  group('the friendly wording still matches the code', () {
    test('a 5xx reads as trouble at their end, not yours', () async {
      GraphClient.debugFetch =
          (url) async => (500, '', <String, String>{});
      final c = GraphClient(token: () async => 't');

      await expectLater(
        c.pages('s1'),
        throwsA(isA<GraphException>().having((e) => e.message, 'message',
            allOf(contains('Microsoft is having trouble'),
                contains('nothing already imported has been lost')))),
      );
    });
  });
}
