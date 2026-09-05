// The ADR-0004 editor-engine seam.
//
// ADR-0004 commits to wrapping the editor behind `OnoteTextEditor` "from day
// one … so the loser remains a swap candidate and the format never depends on
// engine internals". These tests are what makes that claim checkable:
//
//  * the seam is real — a substitute engine renders, so nothing above it
//    reaches into the shipped engine's internals;
//  * criterion 1 (the multi-instance pattern) holds — a 20-container page opens
//    exactly one editing session and nineteen read-only renders;
//  * a session is created on entry and disposed on exit, so the cheap path
//    really is cheap;
//  * the storage contract round-trips.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/live_markdown_engine.dart';
import 'package:openote/editor/onote_text_editor.dart';
import 'package:openote/editor/text_block_view.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

/// A minimal engine that shares no code with the shipped one. If the host still
/// works with this installed, the host is genuinely engine-agnostic.
class _ProbeEngine extends OnoteTextEditor {
  _ProbeEngine();

  int sessionsOpened = 0;
  int sessionsDisposed = 0;
  int readOnlyBuilds = 0;

  @override
  String get id => 'probe';

  @override
  Widget buildReadOnly(BuildContext context, TextSurface s) {
    readOnlyBuilds++;
    return Text('ro:${deserialize(s.block.content)}',
        textDirection: TextDirection.ltr);
  }

  @override
  OnoteEditSession openSession({
    required Block block,
    required AppState app,
    required ValueChanged<String> onChanged,
  }) {
    sessionsOpened++;
    return _ProbeSession(this, deserialize(block.content));
  }

  @override
  double measureIntrinsicWidth(String text, TextStyle style) =>
      text.length * 7.0;
}

class _ProbeSession extends OnoteEditSession {
  _ProbeSession(this._engine, this._text);
  final _ProbeEngine _engine;
  String _text;

  @override
  Widget build(BuildContext context, TextSurface s) =>
      Text('live:$_text', textDirection: TextDirection.ltr);

  @override
  String get text => _text;

  @override
  set text(String value) => _text = value;

  /// No Flutter controller — exercises the "engine owns its own selection
  /// model" path, where command-bar formatting must stay disabled rather than
  /// act on the wrong target.
  @override
  TextEditingController? get commandController => null;

  @override
  void dispose() => _engine.sessionsDisposed++;
}

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());
  tearDown(OnoteEditors.useDefault);

  /// An AppState on a real repository — `TextBlockView` reaches the blob store
  /// through it for in-flow images.
  Future<AppState> newApp(WidgetTester tester) async {
    late AppState app;
    final tmp = Directory.systemTemp.createTempSync('onote_engine_');
    late Repository repo;
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    await tester.runAsync(() async {
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Engine');
      app = AppState(repo)..notebookId = nb.id;
    });
    return app;
  }

  Block textBlock(String id, String text) => Block(
        id: id,
        type: BlockType.text,
        x: 0,
        y: 0,
        w: 300,
        content: {'text': text, 'autoWidth': false},
      );

  Widget host(AppState app, List<Block> blocks) => MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: Column(
            children: [
              for (final b in blocks)
                SizedBox(
                    width: 300, child: TextBlockView(block: b, app: app)),
            ],
          ),
        ),
      );

  testWidgets('a substitute engine renders — the seam carries no engine internals',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final probe = _ProbeEngine();
    OnoteEditors.use(probe);
    final app = await newApp(tester);
    final b = textBlock('b1', 'hello');

    await tester.pumpWidget(host(app, [b]));
    expect(find.text('ro:hello'), findsOneWidget);
    expect(probe.sessionsOpened, 0, reason: 'unfocused blocks open no session');

    app.editingBlockId = 'b1';
    await tester.pumpWidget(host(app, [b]));
    expect(find.text('live:hello'), findsOneWidget);
    expect(probe.sessionsOpened, 1);
    // No controller reported → formatting target stays unset.
    expect(app.activeEditor, isNull);
  });

  testWidgets('20 containers: one live session, nineteen read-only',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final probe = _ProbeEngine();
    OnoteEditors.use(probe);
    final app = await newApp(tester);
    final blocks = [
      for (var i = 0; i < 20; i++) textBlock('b$i', 'container $i'),
    ];
    app.editingBlockId = 'b7';

    await tester.pumpWidget(host(app, blocks));

    expect(probe.sessionsOpened, 1, reason: 'ADR-0004 criterion 1');
    expect(find.text('live:container 7'), findsOneWidget);
    expect(find.textContaining('ro:'), findsNWidgets(19));
  });

  testWidgets('the session is disposed when editing ends', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final probe = _ProbeEngine();
    OnoteEditors.use(probe);
    final app = await newApp(tester);
    final b = textBlock('b1', 'kept');
    app.editingBlockId = 'b1';

    await tester.pumpWidget(host(app, [b]));
    expect(probe.sessionsOpened, 1);
    expect(probe.sessionsDisposed, 0);

    app.editingBlockId = null;
    await tester.pumpWidget(host(app, [b]));
    await tester.pump(); // the post-frame empty-block check
    expect(probe.sessionsDisposed, 1,
        reason: 'leaving edit must free the engine state, not just hide it');
  });

  testWidgets('the shipped engine registers a formatting target',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(tester);
    final b = textBlock('b1', '# Heading');
    app.editingBlockId = 'b1';

    await tester.pumpWidget(host(app, [b]));

    expect(find.byType(TextField), findsOneWidget);
    expect(app.activeEditor, isNotNull);
    expect(app.activeEditor!.controller.text, '# Heading');
    expect(app.activeEditor!.contentKey, OnoteEditors.active.textStorageKey);
  });

  test('the storage contract round-trips', () {
    const engine = LiveMarkdownEngine();
    const src = '# Title\n\n- [ ] task with \$x^2\$ and [[Page]]\n';
    final content = <String, dynamic>{};
    engine.serialize(content, src);
    expect(content[engine.textStorageKey], src);
    expect(engine.deserialize(content), src);
    // A block written by another engine degrades to empty, never throws.
    expect(engine.deserialize(<String, dynamic>{'nodes': []}), '');
  });
}
