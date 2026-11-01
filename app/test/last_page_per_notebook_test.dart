// Each notebook opens where you left it.
//
// v1.0.2 #14: *"The last open page is not remembered when switching
// notebooks, though it survives closing the app."* There was one `lastPage`
// for the whole workspace. Startup read it; a switch never did — it opened the
// first page — and that first page was then saved over it. So leaving a
// notebook forgot where you were in it, and only the notebook open at shutdown
// was ever remembered.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
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
  setUp(() => dir = Directory.systemTemp.createTempSync('onote_lastpage_'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Open the workspace the way the app does at launch.
  Future<(Repository, AppState)> launch() async {
    final repo = await Repository.openAt(dir);
    final app = AppState(repo);
    await app.init();
    return (repo, app);
  }

  /// Close it the way the app does, so whatever it owes the disk is written.
  Future<void> quit(Repository repo, AppState app) async {
    await app.flushSave();
    app.cancelPendingSave();
    await repo.flushWorkspace();
    app.dispose();
    repo.dispose();
  }

  /// A page called [title] at the end of [nb]'s first section.
  TreeNode addPage(AppState app, String nb, String title, String position) {
    final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section);
    final n = app.importNode(
        nb,
        TreeNode(
            kind: NodeKind.page,
            parentId: section.id,
            title: title,
            position: position));
    app.reloadNodes();
    return n;
  }

  String titleOfOpenPage(AppState app) => app.node(app.pageId!)!.title;

  test('THE REPORTED ONE: switching away and back keeps your place', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final seed = await Repository.openAt(dir);
    final a = (await seed.createNotebook('Biology')).id;
    final b = (await seed.createNotebook('Chemistry')).id;
    seed.dispose();

    final (repo, app) = await launch();
    await app.selectNotebook(a);
    addPage(app, a, 'Osmosis', 'y0');
    final osmosis = addPage(app, a, 'Diffusion', 'z0');
    await app.selectPage(osmosis.id);

    await app.selectNotebook(b);
    final bonds = addPage(app, b, 'Ionic bonds', 'z0');
    await app.selectPage(bonds.id);

    await app.selectNotebook(a);
    expect(titleOfOpenPage(app), 'Diffusion',
        reason: 'back on the page you left Biology on, not its first page');

    await app.selectNotebook(b);
    expect(titleOfOpenPage(app), 'Ionic bonds',
        reason: 'and Chemistry kept its own place while you were away');
    await quit(repo, app);
  });

  test('and every notebook keeps its place across closing the app', () async {
    // The half that "survived closing the app" before survived only for the
    // notebook that happened to be open at the time.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final seed = await Repository.openAt(dir);
    final a = (await seed.createNotebook('Biology')).id;
    final b = (await seed.createNotebook('Chemistry')).id;
    seed.dispose();

    var (repo, app) = await launch();
    await app.selectNotebook(a);
    final diffusion = addPage(app, a, 'Diffusion', 'z0');
    await app.selectPage(diffusion.id);
    await app.selectNotebook(b);
    final bonds = addPage(app, b, 'Ionic bonds', 'z0');
    await app.selectPage(bonds.id);
    await quit(repo, app);

    (repo, app) = await launch();
    expect(app.notebookId, b, reason: 'reopens the notebook you closed on');
    expect(titleOfOpenPage(app), 'Ionic bonds');
    await app.selectNotebook(a);
    expect(titleOfOpenPage(app), 'Diffusion',
        reason: 'and the one you were in before it is where you left it too');
    await quit(repo, app);
  });

  test('a remembered page that has since gone opens the notebook at the top',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final seed = await Repository.openAt(dir);
    final a = (await seed.createNotebook('Biology')).id;
    final b = (await seed.createNotebook('Chemistry')).id;
    seed.dispose();

    final (repo, app) = await launch();
    await app.selectNotebook(a);
    final first =
        app.nodes.firstWhere((n) => n.kind == NodeKind.page).title;
    final doomed = addPage(app, a, 'Diffusion', 'z0');
    await app.selectPage(doomed.id);
    await app.selectNotebook(b);

    // Deleted from elsewhere — the MCP API, or another device.
    await app.deleteNodeIn(a, doomed.id);

    await app.selectNotebook(a);
    expect(app.pageId, isNotNull, reason: 'opens on SOMETHING');
    expect(titleOfOpenPage(app), first,
        reason: 'the first page, rather than a page that is not there');
    await quit(repo, app);
  });

  test('a brand-new notebook opens on its own first page', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app) = await launch();
    final before = app.pageId;
    await app.createNotebook('Physics');
    expect(app.pageId, isNot(before),
        reason: "not the previous notebook's page id carried across");
    expect(app.nodes.any((n) => n.id == app.pageId), isTrue,
        reason: 'a page that belongs to the new notebook');
    await quit(repo, app);
  });
}
