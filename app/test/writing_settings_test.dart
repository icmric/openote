// The writing-help settings: their defaults, that they survive a restart, and
// what someone who switched spell check off before grammar existed should get.
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/core/onote_text.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());
  setUp(() => AppState.syncLogEnabled = false);
  tearDown(() => AppState.syncLogEnabled = true);

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('onote_writing_'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<(Repository, AppState)> launch() async {
    final repo = await Repository.openAt(dir);
    final app = AppState(repo);
    await app.init();
    return (repo, app);
  }

  Future<void> quit(Repository repo, AppState app) async {
    await app.flushSave();
    app.cancelPendingSave();
    await repo.flushWorkspace();
    app.dispose();
    repo.dispose();
  }

  test('a new install has everything on, following the computer', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app) = await launch();
    expect(app.spellCheckEnabled, isTrue);
    expect(app.grammarCheckEnabled, isTrue);
    expect(app.autoCorrectEnabled, isTrue);
    expect(app.autoCapitalizeEnabled, isTrue);
    expect(app.spellLanguage, 'system');
    app.systemLocale = () => const Locale('en', 'AU');
    expect(app.writingDialect, EnglishDialect.australian);
    await quit(repo, app);
  });

  test('each choice survives a restart', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    var (repo, app) = await launch();
    app.setGrammarCheck(false);
    app.setAutoCorrect(false);
    app.setAutoCapitalize(false);
    app.setSpellLanguage('en-GB');
    await quit(repo, app);

    (repo, app) = await launch();
    expect(app.grammarCheckEnabled, isFalse);
    expect(app.autoCorrectEnabled, isFalse);
    expect(app.autoCapitalizeEnabled, isFalse);
    expect(app.spellLanguage, 'en-GB');
    expect(app.spellCheckEnabled, isTrue, reason: 'the others did not move');
    await quit(repo, app);
  });

  test('a language this version does not know is ignored, not kept', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    var (repo, app) = await launch();
    app.setSpellLanguage('klingon'); // refused
    expect(app.spellLanguage, 'system');
    // …and a stored one from a newer build is not trusted either.
    repo.setSetting('spellLanguage', 'klingon');
    await quit(repo, app);
    (repo, app) = await launch();
    expect(app.spellLanguage, 'system');
    await quit(repo, app);
  });

  test('someone who turned spell check off does not get grammar switched on',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    var (repo, app) = await launch();
    app.setSpellCheck(false);
    // A setting from before grammar existed: no grammar choice stored.
    expect(repo.getSetting('grammarCheck'), isNull);
    await quit(repo, app);

    (repo, app) = await launch();
    expect(app.spellCheckEnabled, isFalse);
    expect(app.grammarCheckEnabled, isFalse,
        reason: 'they asked for no underlines; grammar is new and follows it');
    // Their own later choice wins over the inheritance.
    app.setGrammarCheck(true);
    await quit(repo, app);
    (repo, app) = await launch();
    expect(app.grammarCheckEnabled, isTrue);
    await quit(repo, app);
  });

  test('the language setting, not the computer, decides when it is set',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app) = await launch();
    app.systemLocale = () => const Locale('de', 'DE');
    expect(app.writingDialect, isNull, reason: 'German computer: no English');
    app.setSpellLanguage('en-AU');
    expect(app.writingDialect, EnglishDialect.australian);
    app.setSpellLanguage('other');
    app.systemLocale = () => const Locale('en', 'AU');
    expect(app.writingDialect, isNull, reason: 'told it is not English');
    await quit(repo, app);
  });
}
