// Two properties of the SOURCE that nothing else in this suite can see.
//
// Both have already bitten, and neither can be caught by a test that runs the
// code: one is invisible in a debug build, and the other is invisible to the
// tools you would use to look.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every `.dart` file under [dir].
Iterable<File> _dartFiles(String dir) sync* {
  final d = Directory(dir);
  if (!d.existsSync()) return;
  for (final e in d.listSync(recursive: true)) {
    if (e is File && e.path.endsWith('.dart')) yield e;
  }
}

/// Shipped code.
Iterable<File> _libFiles() => _dartFiles('lib');

/// Shipped code AND the tests. The control-character check covers both, because
/// the first version of that check lived in a file that contained a NUL itself
/// and only ever looked at `lib/`.
Iterable<File> _allFiles() => [..._dartFiles('lib'), ..._dartFiles('test')];

void main() {
  test('no source file contains a control character', () {
    // Ripgrep treats a file containing one as BINARY and skips it. That is how
    // nine hundred lines of `text_block_view.dart` became invisible to every
    // code search in the repo, including the audits looking for defects in it:
    // it held five literal NULs as a cache-key separator.
    //
    // The same trap catches a LaTeX escape typed into a comment through a shell
    // that interpreted it. In two of the maths files `\frac` had become a form
    // feed plus "rac", and `\boxed` a backspace plus "oxed", and neither was
    // noticed for months. Write the escape.
    //
    // Tab, newline and carriage return are the only ones a source file may hold.
    final offenders = <String>[];
    for (final f in _allFiles()) {
      final bytes = f.readAsBytesSync();
      for (var i = 0; i < bytes.length; i++) {
        final b = bytes[i];
        if (b >= 0x20 || b == 0x09 || b == 0x0a || b == 0x0d) continue;
        var line = 1;
        for (var k = 0; k < i; k++) {
          if (bytes[k] == 0x0a) line++;
        }
        final hex = b.toRadixString(16).padLeft(2, '0');
        offenders.add('${f.path}:$line  byte 0x$hex');
        break;
      }
    }
    expect(offenders, isEmpty,
        reason: 'a control character makes the whole file unsearchable to '
            'ripgrep; write the escape instead. Offenders: $offenders');
  });

  test('shipped code never reads a debug-only API outside an assert', () {
    // `RenderObject.debugNeedsLayout` assigns its result INSIDE an assert, so
    // with asserts stripped it throws a LateInitializationError. Debug builds
    // — which is every build this suite ever runs — were fine; release and
    // profile builds broke the layout of any paragraph holding an open inline
    // equation, once per frame.
    //
    // There is no runtime test for this. A debug suite cannot observe what a
    // release build does, so the check is on the source.
    //
    // The first six were picked by hand. The rest are every `debug…` getter
    // in the pinned Flutter whose value is assigned only inside an assert —
    // found by reading the SDK (backlog §1.7, 17 November), because a list
    // remembered from one incident misses the next. In release each either
    // throws or answers null. The sweep that produced it found nothing in
    // lib/ reading any of them.
    const banned = [
      'debugNeedsLayout',
      'debugNeedsPaint',
      'debugDoingThisLayout',
      'debugDoingThisPaint',
      'debugDoingThisResize',
      'debugDisposed',
      'debugAnimation',
      'debugController',
      'debugGlobalRouteCount',
      'debugHandleCount',
      'debugLastPendingEventTimestamp',
      'debugLayer',
      'debugLayoutParent',
      'debugName',
      'debugNeedsCompositedLayerUpdate',
      'debugParentDataType',
    ];
    final offenders = <String>[];
    for (final f in _libFiles()) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final code = line.trimLeft();
        if (code.startsWith('//') || code.startsWith('///')) continue;
        for (final name in banned) {
          if (!RegExp('\\.$name\\b').hasMatch(line)) continue;
          if (line.contains('assert(')) continue;
          // dart:isolate's `Isolate.debugName` is a plain field, set in every
          // build; the banned one is `LogicalKeyboardKey.debugName`.
          if (name == 'debugName' && line.contains('Isolate.')) continue;
          offenders.add('${f.path}:${i + 1}  $code');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'these throw in release and profile builds: $offenders');
  });
}
