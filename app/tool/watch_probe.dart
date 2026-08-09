// What does Directory.watch actually report when a cloud client writes?
//
// The receiving device never notices another machine's edits. OpFolderWatcher
// filters events on `path.endsWith('.oplog')`, while its own doc comment says
// "a cloud client … often renames a temp file over it" — and a temp file does
// not end in `.oplog`. Worse, Dart's FileSystemMoveEvent.path is the SOURCE
// (the temp name); the target is in `.destination`, which nothing reads.
//
// That is a theory. This measures it. Point it at a real synced ops directory,
// edit the notebook on the OTHER machine, and read what comes out.
//
//   dart run tool/watch_probe.dart "<...>/Notebook.onotebook/ops"
//
// Strictly read-only.
import 'dart:async';
import 'dart:io';

String _kind(FileSystemEvent e) => switch (e.type) {
      FileSystemEvent.create => 'CREATE',
      FileSystemEvent.modify => 'MODIFY',
      FileSystemEvent.delete => 'DELETE',
      FileSystemEvent.move => 'MOVE  ',
      _ => 'OTHER ',
    };

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/watch_probe.dart <ops directory>');
    exit(2);
  }
  final dir = Directory(args[0]);
  if (!dir.existsSync()) {
    stderr.writeln('no such directory: ${args[0]}');
    exit(1);
  }

  stdout.writeln('watching ${dir.path}');
  stdout.writeln('files now:');
  for (final f in dir.listSync().whereType<File>()) {
    stdout.writeln('  ${f.lengthSync().toString().padLeft(9)}  '
        '${f.statSync().modified.toIso8601String()}  '
        '${f.uri.pathSegments.last}');
  }
  stdout.writeln('\nnow edit the notebook on the OTHER machine. Ctrl+C to stop.\n');

  // Everything, unfiltered — the point is to see what the filter would drop.
  dir.watch(recursive: false).listen((e) {
    final dest = e is FileSystemMoveEvent ? ' -> ${e.destination}' : '';
    final wouldPass = e.path.endsWith('.oplog');
    stdout.writeln('${DateTime.now().toIso8601String().substring(11, 23)} '
        '${_kind(e)} ${e.path}$dest'
        '${wouldPass ? '' : '   <-- TODAY\'S FILTER DROPS THIS'}');
  }, onError: (Object err) {
    stdout.writeln('WATCH ERROR: $err  '
        '(a filesystem that cannot watch is itself the answer)');
  });

  // A poll beside it, so we can tell "no events" from "no changes".
  final seen = <String, DateTime>{};
  for (final f in dir.listSync().whereType<File>()) {
    seen[f.path] = f.statSync().modified;
  }
  Timer.periodic(const Duration(seconds: 5), (_) {
    for (final f in dir.listSync().whereType<File>()) {
      final m = f.statSync().modified;
      if (seen[f.path] != m) {
        seen[f.path] = m;
        stdout.writeln('${DateTime.now().toIso8601String().substring(11, 23)} '
            'POLL   ${f.uri.pathSegments.last} changed '
            '(mtime ${m.toIso8601String()})   <-- a poll WOULD have caught it');
      }
    }
  });
}
