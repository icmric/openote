// End-to-end: a tagged .one, through the REAL native parser and the REAL
// import path, arrives as real Openote tags on the right lines.
//
// Skips when the core library or a fixture isn't present, matching
// onenote_import_e2e_test.dart — the sample files are the user's own notes and
// are deliberately not committed. Point it at one with:
//   ONOTE_TAGGED_ONE=/path/to/Tagged.one flutter test test/onenote_tag_import_e2e_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/core/onote_ffi.dart';
import 'package:openote/export/onenote_import.dart';
import 'package:openote/model/models.dart';
import 'package:openote/model/tags.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  test('a tagged .one imports its tags onto the right lines', () async {
    // A skipped test is RECORDED AS A SUCCESS, so a quiet skip would make this
    // file green in CI having asserted nothing — and note-tag import is exactly
    // the path where a property-walk change once silently ate a tagged
    // paragraph's text. Every gate below names what was missing, loudly.
    void notVerified(String why) {
      // ignore: avoid_print
      print('!!! NOT VERIFIED: onenote_tag_import_e2e_test asserted NOTHING — '
          '$why. Whether a tagged .one arrives with its tags on the right '
          'lines is unchecked in this run. To check it, run: '
          'ONOTE_TAGGED_ONE=/path/to/Tagged.one flutter test '
          'test/onenote_tag_import_e2e_test.dart');
      markTestSkipped('$why — see the NOT VERIFIED line above');
    }

    if (!haveSqlite) return notVerified('sqlite is unavailable');
    final core = OnoteCore.instance;
    if (core == null) return notVerified('the native core is not built');
    final path = Platform.environment['ONOTE_TAGGED_ONE'];
    // Empty counts as unset: a CI that exports the variable without a value
    // would otherwise get "names , which does not exist".
    if (path == null || path.isEmpty) {
      return notVerified('ONOTE_TAGGED_ONE is not set');
    }
    if (!File(path).existsSync()) {
      return notVerified('ONOTE_TAGGED_ONE names $path, which does not exist');
    }

    final tmp = Directory.systemTemp.createTempSync('onote_tag_e2e_');
    final repo = await Repository.openAt(tmp);
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final nb = await repo.createNotebook('Tagged');
    final app = AppState(repo)..notebookId = nb.id;
    app.reloadNodes();

    final json = jsonDecode(core.importOne(File(path).readAsBytesSync()))
        as Map<String, dynamic>;
    expect(json['ok'], isTrue, reason: 'the parser rejected the file');
    final (pages, _) = importParsedSection(
        app, nb.id, 'Tagged', (json['pages'] as List?) ?? const []);
    expect(pages, greaterThan(0), reason: 'nothing imported');
    app.reloadNodes();

    // Every tag found across the imported notebook, with the text it marks.
    final marked = <String, TagKind>{};
    for (final n in app.nodes.where((n) => n.kind == NodeKind.page)) {
      for (final b in app.readPage(n.id).blocks) {
        if (b.type != BlockType.text) continue;
        final lines = (b.content['text'] as String? ?? '').split('\n');
        for (final t in NoteTag.listFrom(b.content)) {
          if (t.line < 0 || t.line >= lines.length) {
            fail('tag on line ${t.line} of a ${lines.length}-line block');
          }
          marked[lines[t.line].trim()] = t.kind;
        }
      }
    }

    expect(marked, isNotEmpty, reason: 'the file is tagged but nothing arrived');
    marked.forEach((line, kind) => expect(line, isNotEmpty,
        reason: 'a tag landed on a blank line — the index drifted'));
  });
}
