// Two failures that a real import found, and neither of which was a bug in
// reading OneNote's markup.
//
// A 332-page notebook was imported against the live service and produced
// **one page in forty minutes** — every other line of the log a throttle wait.
// Two separate faults sat behind that, and both are the kind that only show up
// when something goes wrong far from the code that has to cope with it:
//
//   1. The client would wait to be let in for ever. There was no number of
//      minutes after which it stopped and said so.
//   2. If it had stopped, the job would have DELETED the notebook — pages the
//      student had already watched arrive included — because the count of what
//      had been imported was only written down after a successful return.
//
// The second is much the worse of the two: a slow import is a nuisance, an
// import that eats what it already gave you is a reason not to trust the app
// with a five-year notebook.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/export/import_job.dart';
import 'package:openote/export/onenote_import.dart';
import 'package:openote/model/models.dart';
import 'package:openote/onenote/graph_client.dart';
import 'package:openote/onenote/graph_import.dart';
import 'package:openote/onenote/graph_pages.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

Map<String, dynamic> page(String title) => {
      'title': title,
      'boxes': [
        {
          'kind': 'text',
          'markdown': 'Body of $title',
          'x': 60.0,
          'y': 120.0,
          'w': 480.0,
          'flow': 0,
        }
      ],
      'images': const [],
      'ink': const [],
    };

Map<String, dynamic> section(String name, List<Map<String, dynamic>> pages) => {
      'name': name,
      'section': {'pages': pages},
    };

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  group('the client stops asking eventually', () {
    final wasGiveUp = GraphClient.giveUpAfterThrottledFor;
    tearDown(() {
      GraphClient.giveUpAfterThrottledFor = wasGiveUp;
      GraphClient.debugFetch = null;
    });

    test('a service that only ever refuses ends the import, it does not hang',
        () async {
      GraphClient.giveUpAfterThrottledFor = Duration.zero;
      var asked = 0;
      GraphClient.debugFetch = (url) async {
        asked++;
        return (429, '', <String, String>{'retry-after': '1'});
      };
      final c = GraphClient(token: () async => 't');

      await expectLater(
        c.pageHtml('p1'),
        throwsA(isA<GraphGaveUp>().having((e) => e.message, 'message',
            allOf(contains('limiting'), contains('Try again')))),
      );
      // The point is that it gave up, not that it gave up quickly — but ten
      // retries at up to two minutes each is over twenty minutes of silence,
      // and that is what this stops.
      expect(asked, lessThan(3));
    });

    test('a refusal followed by a success starts the clock again', () async {
      // Otherwise a long import that is throttled now and then — which is
      // every large notebook — would give up on the strength of trouble it had
      // already recovered from.
      GraphClient.giveUpAfterThrottledFor = const Duration(hours: 1);
      var n = 0;
      GraphClient.debugFetch = (url) async {
        n++;
        if (n == 1) return (429, '', <String, String>{'retry-after': '0'});
        return (200, '<html><body></body></html>', <String, String>{});
      };
      final c = GraphClient(token: () async => 't');

      await c.pageHtml('p1');
      expect(c.refusedFor, Duration.zero,
          reason: 'the run of refusals ended when one request got through');
    });

    test('a picture refused with 429 is asked for again, not thrown away',
        () async {
      // Found by importing a real notebook: 46 pictures arrived and 4 were
      // lost, with nothing else lost at all. `resource` was the one request
      // path that ignored throttling — it never waited out the shared quiet
      // period, and it read a 429 ("come back shortly") as "this picture does
      // not exist".
      GraphClient.giveUpAfterThrottledFor = const Duration(hours: 1);
      var n = 0;
      GraphClient.debugResource = (url) async {
        n++;
        if (n <= 2) {
          return (429, null, <String, String>{'retry-after': '0'});
        }
        return (200, Uint8List.fromList([1, 2, 3]), <String, String>{});
      };
      addTearDown(() => GraphClient.debugResource = null);
      final c = GraphClient(token: () async => 't');

      expect(await c.resource('https://example/pic'), [1, 2, 3]);
      expect(n, 3, reason: 'refused twice, then asked a third time');
    });

    test('a picture that really is not there is not retried for ever',
        () async {
      // Null still has to mean null. Retrying a 404 ten times would spend the
      // backoff budget on something that is never going to arrive.
      var n = 0;
      GraphClient.debugResource = (url) async {
        n++;
        return (404, null, <String, String>{});
      };
      addTearDown(() => GraphClient.debugResource = null);
      final c = GraphClient(token: () async => 't');

      expect(await c.resource('https://example/gone'), isNull);
      expect(n, 1);
    });

    test('a moment of bad wifi does not end the whole import', () async {
      // Watched happen: a confirmation import died at seven minutes on
      // "Failed host lookup: graph.microsoft.com", and the same lookup
      // succeeded from the same machine seconds later. One blink of DNS was
      // ending a two-minute import on the first failure, with no second try.
      var n = 0;
      GraphClient.debugFetch = (url) async {
        n++;
        if (n == 1) throw const SocketException('Failed host lookup');
        return (200, '<html><body></body></html>', <String, String>{});
      };
      final c = GraphClient(token: () async => 't');

      await c.pageHtml('p1');
      expect(n, 2, reason: 'it asked again once the blip had passed');
    });

    test('a connection that is really gone is reported, not retried for ever',
        () async {
      // The other half of the same decision. If the wifi is off, saying so
      // promptly is more useful than a long silence — and the sentence has to
      // tell them their imported pages are safe, because that is the thing
      // they will worry about.
      var n = 0;
      // Written out with its return type rather than as a closure: an `async`
      // closure whose body only ever throws is inferred as `Future<Never>`,
      // which `.timeout()` will not accept — a quirk of the stub, not of the
      // code under test.
      Future<(int, String, Map<String, String>)> gone(String url) async {
        n++;
        throw const SocketException('Failed host lookup');
      }

      GraphClient.debugFetch = gone;
      final c = GraphClient(token: () async => 't');

      await expectLater(
        c.pageHtml('p1'),
        throwsA(isA<GraphException>().having((e) => e.message, 'message',
            allOf(contains('lost its connection'), contains('nothing already '
                'imported has been lost')))),
      );
      expect(n, lessThanOrEqualTo(5),
          reason: 'a few quick tries, not a long silence');
      // Not the give-up type: this is the network, not Microsoft refusing.
      await expectLater(c.pageHtml('p2'), throwsA(isNot(isA<GraphGaveUp>())));
    });

    test('a blip does not narrow the pipe', () async {
      // A missing network is not the service asking anyone to slow down.
      // Halving concurrency for it would punish the whole import for one
      // blink of the router.
      var n = 0;
      GraphClient.debugFetch = (url) async {
        n++;
        if (n == 1) throw const SocketException('Failed host lookup');
        return (200, '<html><body></body></html>', <String, String>{});
      };
      final c = GraphClient(token: () async => 't');
      final before = c.concurrencyLimit;

      await c.pageHtml('p1');
      expect(c.concurrencyLimit, before);
      expect(c.refusedFor, Duration.zero,
          reason: 'a blip is not a refusal, so it starts no give-up clock');
    });

    test('Stop is honoured inside a throttle wait, not only between batches',
        () async {
      // What a real user hit: throttled on the second page, the card said
      // "carrying on in 1s", they pressed Cancel, it said "Stopping…" — and
      // stayed there. The flag was only read between batches, and the import
      // was never going to reach one. The client did not know cancellation
      // existed.
      var stop = false;
      GraphClient.debugFetch = (url) async =>
          (429, '', <String, String>{'retry-after': '120'});
      final c = GraphClient(token: () async => 't')..isCancelled = () => stop;

      final f = c.pageHtml('p1');
      // Let it get into the wait, then press Stop.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      stop = true;
      await expectLater(f, throwsA(isA<GraphCancelled>()));
    });

    test('the wait counts down instead of sitting on one number', () async {
      // It was announced only when it got LONGER, so a run of one-second
      // backoffs showed "1s" and then never changed — which reads as a freeze
      // rather than as waiting.
      final seen = <Duration>[];
      void note(Duration? d) {
        if (d != null) seen.add(d);
      }

      GraphClient.debugFetch = (url) async =>
          (429, '', <String, String>{'retry-after': '3'});
      final c = GraphClient(token: () async => 't')
        ..onThrottle = note
        ..isCancelled = () => seen.length >= 4;

      await expectLater(c.pageHtml('p1'), throwsA(isA<GraphCancelled>()));
      expect(seen.length, greaterThanOrEqualTo(3));
      // First against last, not consecutive pairs: the backoff is announced
      // and the wait's first slice measured in the same clock tick, so those
      // two can legitimately be equal. What must not happen is the number
      // staying put across the whole wait.
      expect(seen.last, lessThan(seen.first),
          reason: 'the number has to get smaller as the wait passes');
    });

    test('giving up is not mistaken for one bad page', () {
      // `pageHtmlMany` answers a page it cannot read with null and carries on,
      // which is right for one page and catastrophic here: swallowed, a
      // give-up would produce a notebook of hundreds of empty pages and call
      // it a success.
      expect(GraphGaveUp('x'), isA<GraphException>());
    });
  });

  group('a failed import keeps what it already brought', () {
    tearDown(() => ImportJob.current = null);

    Future<(Repository, AppState)> fixture(String name) async {
      final tmp = Directory.systemTemp.createTempSync(name);
      final repo = await Repository.openAt(tmp);
      addTearDown(() async {
        await repo.flushWorkspace();
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      return (repo, AppState(repo));
    }

    Future<void> settle(ImportJob job) async {
      for (var i = 0; i < 2000 && !job.isFinished; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(job.isFinished, isTrue);
    }

    test('pages already on screen survive a give-up partway through', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app) = await fixture('onote_giveup_keep_');

      final job = ImportJob.startFromCloud(app, 'Computing Science',
          (sink, onProgress, shouldCancel) async {
        // Two pages land and the student sees them…
        final r = await writePackageInBatches(sink, [
          section('Week 1', [page('Mon'), page('Tue')]),
        ]);
        onProgress(GraphImportProgress(
          sectionName: 'Week 1',
          pagesDone: r.pages,
          pagesTotal: 40,
          sectionsDone: 1,
          sectionsTotal: 6,
        ));
        // …and then the service stops letting anything through.
        throw GraphGaveUp('Microsoft is limiting how fast Openote can read '
            'this account. Everything brought in so far has been kept.');
      });
      expect(job, isNotNull);
      await settle(job!);

      final nb = repo.notebooks.firstWhere(
          (n) => n.title == 'Computing Science',
          orElse: () => throw StateError('the notebook was deleted'));
      expect(repo.loadNodes(nb.id).where((n) => n.kind == NodeKind.page),
          hasLength(2),
          reason: 'the two pages the student watched arrive are still there');
      expect(job.importedPages, 2);
      // Not `failed`: a notebook with real pages in it that is called a
      // failure invites the student to delete it and start over, which is the
      // one action that would actually lose the work.
      expect(job.state, ImportJobState.done);
      expect(job.message, contains('2 pages already brought over are here'));
    });

    test('an unexpected fault keeps them too', () async {
      // The rule is about what is on screen, not about which exception type
      // happened to reach the handler.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app) = await fixture('onote_giveup_odd_');

      final job = ImportJob.startFromCloud(app, 'Odd Failure',
          (sink, onProgress, shouldCancel) async {
        final r = await writePackageInBatches(sink, [
          section('Week 1', [page('Mon')]),
        ]);
        onProgress(GraphImportProgress(
          sectionName: 'Week 1',
          pagesDone: r.pages,
          pagesTotal: 9,
          sectionsDone: 1,
          sectionsTotal: 3,
        ));
        throw StateError('something nobody predicted');
      });
      await settle(job!);

      final nb = repo.notebooks.firstWhere((n) => n.title == 'Odd Failure',
          orElse: () => throw StateError('the notebook was deleted'));
      expect(repo.loadNodes(nb.id).where((n) => n.kind == NodeKind.page),
          hasLength(1));
      expect(job.state, ImportJobState.done);
      expect(job.message, contains('1 page'));
    });

    test('the long wait before the first page says something', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (_, app) = await fixture('onote_preparing_');

      // Listing the sections and every section's page list took **33 seconds**
      // on a real notebook, and for all of it the card read "Signing in to
      // OneNote…" — finished minutes earlier, and impossible to tell from a
      // freeze.
      final said = <String>[];
      final job = ImportJob.startFromCloud(app, 'Slow Start',
          (sink, onProgress, shouldCancel) async {
        void tick(int sections, int pages) {
          onProgress(GraphImportProgress(
            sectionName: '',
            pagesDone: 0,
            pagesTotal: pages,
            sectionsDone: 0,
            sectionsTotal: sections,
            preparing: true,
          ));
          said.add(ImportJob.current!.message);
        }

        tick(0, 0); // before anything is known
        tick(12, 0); // sections listed
        tick(12, 332); // page lists in, total known
        return GraphImportResult(
            pages: 0, sections: 0, loss: GraphPageLoss(), firstPageId: null);
      });
      await settle(job!);

      expect(said[0], 'Looking through your notebook…');
      expect(said[1], contains('12 sections'));
      expect(said[2], contains('332 pages'));
      for (final m in said) {
        expect(m, isNot(contains('Signing in')),
            reason: 'sign-in finished long before any of this');
      }
      // The bar has a denominator before the first page rather than appearing
      // partway through.
      expect(job.pagesTotal, 332);
    });

    test('a notebook that got nothing at all is still cleaned up', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app) = await fixture('onote_giveup_empty_');
      final before = repo.notebooks.length;

      final job = ImportJob.startFromCloud(app, 'Nothing Doing',
          (sink, onProgress, shouldCancel) async {
        throw GraphGaveUp('refused from the first request');
      });
      await settle(job!);

      expect(job.state, ImportJobState.failed);
      expect(repo.notebooks.length, before,
          reason: 'an empty shell left behind is just litter');
    });
  });
}
