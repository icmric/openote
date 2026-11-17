/// **A test page, not a feature.** It answers the one question that cannot be
/// settled from a desk: does a Google Drive folder, reached through Android's
/// folder picker, behave well enough to sync a notebook through? Pick a folder,
/// list it, write a file, replace it, read it back, and time a read of
/// everything in it. See `docs/planning/android.md`.
///
/// Reached from the top bar's menu on Android only, and in English only on
/// purpose: it is to be deleted once the real thing is built.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FolderSpikePage extends StatefulWidget {
  const FolderSpikePage({super.key});

  @override
  State<FolderSpikePage> createState() => _FolderSpikePageState();
}

class _FolderSpikePageState extends State<FolderSpikePage> {
  static const _ch = MethodChannel('org.openote/saf');
  static const _testName = 'openote-spike.txt';

  String? _tree;
  final List<String> _log = [];
  bool _busy = false;

  void _say(String s) => setState(() => _log.insert(0, s));

  Future<T?> _timed<T>(String what, Future<T> Function() f) async {
    final sw = Stopwatch()..start();
    setState(() => _busy = true);
    try {
      final r = await f();
      _say('$what: ${sw.elapsedMilliseconds} ms');
      return r;
    } on PlatformException catch (e) {
      _say('$what FAILED after ${sw.elapsedMilliseconds} ms: ${e.message}');
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<List<Map<String, Object?>>> _list() async {
    final r = await _ch.invokeMethod<List<Object?>>('list', {'tree': _tree});
    return [for (final e in r ?? const []) Map<String, Object?>.from(e as Map)];
  }

  Future<void> _pick() async {
    final t = await _ch.invokeMethod<String>('pickTree');
    if (t == null) return _say('No folder chosen.');
    setState(() => _tree = t);
    _say('Chosen: ${Uri.decodeFull(t)}');
  }

  Future<void> _listIt() async {
    final items = await _timed('List', _list);
    if (items == null) return;
    _say('${items.length} items: ${items.take(12).map((e) => '${e['dir'] == true ? '[dir] ' : ''}${e['name']} (${e['size']})').join(', ')}');
  }

  Future<String?> _write(String text) async => _ch.invokeMethod<String>('write', {
        'tree': _tree,
        'parent': null,
        'name': _testName,
        'bytes': Uint8List.fromList(utf8.encode(text)),
      });

  Future<void> _writeIt() async {
    final id = await _timed('Write new', () => _write('first write ${DateTime.now()}'));
    if (id != null) _say('Wrote $_testName');
  }

  Future<void> _replaceIt() async {
    // A SHORTER text than the first write: a leftover tail would show up here.
    final id = await _timed('Replace', () => _write('second ${DateTime.now().second}'));
    if (id != null) _say('Replaced $_testName');
  }

  Future<void> _readIt() async {
    final items = await _list();
    final f = items.where((e) => e['name'] == _testName).firstOrNull;
    if (f == null) return _say('$_testName is not there.');
    final bytes = await _timed(
        'Read back',
        () => _ch.invokeMethod<Uint8List>(
            'read', {'tree': _tree, 'doc': f['id']}));
    if (bytes != null) _say('Read ${bytes.length} bytes: "${utf8.decode(bytes)}"');
  }

  Future<void> _pullAll() async {
    final sw = Stopwatch()..start();
    setState(() => _busy = true);
    try {
      var files = 0, bytes = 0;
      Future<void> walk(String? doc, int depth) async {
        final r = await _ch.invokeMethod<List<Object?>>(
            'list', {'tree': _tree, 'doc': doc});
        for (final e in r ?? const []) {
          final m = Map<String, Object?>.from(e as Map);
          if (m['dir'] == true) {
            if (depth < 4) await walk(m['id'] as String, depth + 1);
          } else if ((m['size'] as int) < 8 * 1024 * 1024) {
            final b = await _ch.invokeMethod<Uint8List>(
                'read', {'tree': _tree, 'doc': m['id']});
            files++;
            bytes += b?.length ?? 0;
          }
        }
      }

      await walk(null, 0);
      _say('Pulled $files files, ${(bytes / 1024).round()} KB in ${sw.elapsedMilliseconds} ms');
    } on PlatformException catch (e) {
      _say('Pull FAILED after ${sw.elapsedMilliseconds} ms: ${e.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final has = _tree != null;
    Widget b(String label, VoidCallback? f) =>
        FilledButton.tonal(onPressed: _busy ? null : f, child: Text(label));
    return Scaffold(
      appBar: AppBar(title: const Text('Folder test (temporary)')),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              b('1 · Choose a folder', _pick),
              b('2 · List it', has ? _listIt : null),
              b('3 · Write a test file', has ? _writeIt : null),
              b('4 · Replace it', has ? _replaceIt : null),
              b('5 · Read it back', has ? _readIt : null),
              b('6 · Time a read of everything', has ? _pullAll : null),
            ]),
          ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: ListView(padding: const EdgeInsets.all(12), children: [
              for (final l in _log)
                Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: SelectableText(l, style: const TextStyle(fontSize: 13))),
            ]),
          ),
        ]),
      ),
    );
  }
}
