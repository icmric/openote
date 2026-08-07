// Passcode gating: a lock on the app's doors, not on the file.
//
// The honesty of this feature is the feature. These tests pin the two things
// that decide whether it is coherent — inheritance (so a page added to a
// locked section later is still locked) and search exclusion (so the gate
// cannot be walked around inside the app that offers it) — and one thing that
// decides whether it is defensible: the passcode is never written down.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/state/page_protection.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  group('the record itself', () {
    test('a passcode is never stored, only a salted digest', () {
      // Someone who opens workspace.json must not find a passcode there. It
      // buys nothing against an attacker with the .onote — they never see the
      // prompt — but people reuse passcodes, and leaking a reused one would be
      // a real harm this feature has no business causing.
      final rec = newProtection('correct horse battery staple', UnlockPolicy.oneHour);
      final json = rec.toJson().toString();
      expect(json, isNot(contains('correct horse')));
      expect(json, contains(rec.hash));
      expect(rec.hash.length, 64, reason: 'sha-256 hex');
    });

    test('the same passcode twice gives different digests', () {
      // Per-record salt: otherwise one precomputed table covers every user,
      // and two people with the same passcode are visibly identified as such.
      final a = newProtection('hunter2', UnlockPolicy.session);
      final b = newProtection('hunter2', UnlockPolicy.session);
      expect(a.salt, isNot(b.salt));
      expect(a.hash, isNot(b.hash));
      expect(a.matches('hunter2'), isTrue);
      expect(b.matches('hunter2'), isTrue);
      expect(a.matches('hunter3'), isFalse);
    });

    test('it survives a round trip through settings JSON', () {
      final rec = newProtection('pw', UnlockPolicy.tenMinutes);
      final back = ProtectionRecord.fromJson(rec.toJson())!;
      expect(back.matches('pw'), isTrue);
      expect(back.policy, UnlockPolicy.tenMinutes);
    });

    test('a malformed record is refused rather than trusted', () {
      expect(ProtectionRecord.fromJson(null), isNull);
      expect(ProtectionRecord.fromJson('nonsense'), isNull);
      expect(ProtectionRecord.fromJson({'salt': 'x'}), isNull);
    });
  });

  group('gating a tree', () {
    late Repository repo;
    late Directory tmp;
    late AppState app;
    late TreeNode group, section, page, otherSection, otherPage;

    setUp(() async {
      if (!haveSqlite) return;
      tmp = Directory.systemTemp.createTempSync('onote_protect_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Protected');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();

      group = app.importNode(nb.id,
          TreeNode(kind: NodeKind.sectionGroup, title: 'Year 2', position: 'b0'));
      section = app.importNode(
          nb.id,
          TreeNode(
              kind: NodeKind.section, parentId: group.id, title: 'Private', position: 'b1'));
      page = app.importNode(
          nb.id,
          TreeNode(
              kind: NodeKind.page, parentId: section.id, title: 'Diary', position: 'b2'));
      otherSection = app.importNode(nb.id,
          TreeNode(kind: NodeKind.section, title: 'Open', position: 'c0'));
      otherPage = app.importNode(
          nb.id,
          TreeNode(
              kind: NodeKind.page, parentId: otherSection.id, title: 'Lectures', position: 'c1'));
      app.reloadNodes();
      app.reloadProtection();
    });

    tearDown(() {
      if (!haveSqlite) return;
      app.cancelPendingSave();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('nothing is locked until something is protected', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      expect(app.isLocked(page.id), isFalse);
      expect(app.governingNode(page.id), isNull);
    });

    test('protecting a section locks the pages inside it', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.protectNode(section.id, 'pw', UnlockPolicy.session);
      expect(app.isLocked(page.id), isTrue);
      expect(app.governingNode(page.id), section.id);
      // And leaves everything else alone.
      expect(app.isLocked(otherPage.id), isFalse);
    });

    test('a page added to a locked section LATER is locked too', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // The reason protection is resolved by walking UP from the page rather
      // than by marking descendants when it is set: no bookkeeping to forget.
      app.protectNode(section.id, 'pw', UnlockPolicy.session);
      final added = app.importNode(
          app.notebookId!,
          TreeNode(
              kind: NodeKind.page, parentId: section.id, title: 'New', position: 'b9'));
      app.reloadNodes();
      expect(app.isLocked(added.id), isTrue);
    });

    test('protecting a group reaches through the section to the page', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.protectNode(group.id, 'pw', UnlockPolicy.session);
      expect(app.governingNode(page.id), group.id);
      expect(app.isLocked(page.id), isTrue);
    });

    test('the wrong passcode changes nothing', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.protectNode(section.id, 'pw', UnlockPolicy.session);
      expect(app.unlockNode(page.id, 'not-it'), isFalse);
      expect(app.isLocked(page.id), isTrue, reason: 'still locked');
    });

    test('the right passcode unlocks the whole subtree', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.protectNode(section.id, 'pw', UnlockPolicy.session);
      expect(app.unlockNode(page.id, 'pw'), isTrue);
      expect(app.isLocked(page.id), isFalse);
      expect(app.isLocked(section.id), isFalse);
    });

    test('"every time" never caches the unlock', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.protectNode(section.id, 'pw', UnlockPolicy.always);
      expect(app.unlockNode(page.id, 'pw'), isTrue);
      // The caller got its yes for THIS open, and the next one asks again.
      expect(app.isLocked(page.id), isTrue);
    });

    test('Lock now forgets every unlock', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.protectNode(section.id, 'pw', UnlockPolicy.session);
      app.unlockNode(page.id, 'pw');
      expect(app.isLocked(page.id), isFalse);
      app.lockAll();
      expect(app.isLocked(page.id), isTrue);
    });

    test('removing protection needs the passcode', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.protectNode(section.id, 'pw', UnlockPolicy.session);
      expect(app.unprotectNode(section.id, 'wrong'), isFalse);
      expect(app.isLocked(page.id), isTrue);
      expect(app.unprotectNode(section.id, 'pw'), isTrue);
      expect(app.isLocked(page.id), isFalse);
      expect(app.protectionFor(section.id), isNull);
    });

    test('protection survives reopening the notebook', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.protectNode(section.id, 'pw', UnlockPolicy.session);
      // A fresh AppState over the same repository, as a restart would give.
      final fresh = AppState(repo)..notebookId = app.notebookId;
      fresh.reloadNodes();
      fresh.reloadProtection();
      addTearDown(fresh.cancelPendingSave);
      expect(fresh.isLocked(page.id), isTrue,
          reason: 'a restart must not drop the gate');
      expect(fresh.unlockNode(page.id, 'pw'), isTrue);
    });

    test('reloadProtection sees what a previous session set', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // The gate is only as good as its rehydration: a restart that forgot
      // which nodes were protected would open every locked page.
      app.protectNode(section.id, 'pw', UnlockPolicy.session);
      app.reloadProtection();
      expect(app.protectionFor(section.id), isNotNull);
      expect(app.isLocked(page.id), isTrue);
    });

    test('a locked page is not findable by searching its own words', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // The gate makes no claim about the FILE, but it has to be coherent
      // inside the app: if search returns the content, the prompt is theatre
      // even on its own terms.
      await app.selectPage(page.id);
      app.blocks = [
        Block(type: BlockType.text, x: 0, y: 0, content: {'text': 'pumpernickel'})
      ];
      app.markDirty();
      await app.flushSave();

      expect(app.searchContent('pumpernickel').map((h) => h.pageId),
          contains(page.id),
          reason: 'precondition: findable while unprotected');

      app.protectNode(section.id, 'pw', UnlockPolicy.session);
      expect(app.searchContent('pumpernickel'), isEmpty,
          reason: 'a locked page must not surface through search');

      app.unlockNode(page.id, 'pw');
      expect(app.searchContent('pumpernickel').map((h) => h.pageId),
          contains(page.id), reason: 'and comes back once unlocked');
    });
  });
}
