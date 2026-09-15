// **Temporary instrument: who takes the caret out of a table cell?**
//
// Reported, and reproducible on the owner's machine every time: make a row
// with Enter, "it will create the new row, move my cursor into the box very
// briefly, then move it out of the box so if i tried to type it would be next
// to the table." Beside the table is `_leaveAtom`'s doing and nothing else's —
// it puts the caret at the end of the atom reference and gives the paragraph
// the keyboard — so the question is only ever WHO CALLED IT.
//
// Eight widget tests reproduce none of it, including ones that let the save
// debounce fire and ones whose table outgrows its box, so inference has run
// out of road. This prints the answer from the machine where it happens.
//
// Off unless asked for, and compiled out of a release build entirely:
//
//     flutter run --dart-define=ONOTE_FOCUS_DEBUG=true
//
// DELETE THIS FILE once the cause is found.

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Whether the focus instrument is armed. A `const` from the environment, so
/// an ordinary build drops every call below and the string never ships.
const bool kFocusDebug = bool.fromEnvironment('ONOTE_FOCUS_DEBUG');

/// One line, tagged so it can be grepped out of a noisy debug console.
void focusLog(String message) {
  if (kFocusDebug) debugPrint('[caret] $message');
}

/// The same, with the call stack — for the events where WHO is the question.
/// Trimmed to the frames that name our own code; the framework's own frames
/// below the callback boundary say nothing useful and bury the ones that do.
void focusLogWithStack(String message) {
  if (!kFocusDebug) return;
  final frames = StackTrace.current.toString().split('\n');
  final ours = [
    for (final f in frames.skip(1).take(24))
      if (f.contains('package:openote/')) f.trim()
  ];
  debugPrint('[caret] $message\n${ours.map((f) => '    $f').join('\n')}');
}

/// **Every change of primary focus, tagged.**
///
/// `debugFocusChanges` says the same thing and a great deal more, but it prints
/// untagged and in volume, which makes the one transition that matters hard to
/// find in a console a media player and a sync engine are also writing to.
/// This is the same answer in one grep-able line per change.
void armFocusWatch() {
  if (!kFocusDebug) return;
  FocusNode? last;
  FocusManager.instance.addListener(() {
    final now = FocusManager.instance.primaryFocus;
    if (identical(now, last)) return;
    focusLog('PRIMARY: ${last?.debugLabel ?? 'none'} '
        '-> ${now?.debugLabel ?? 'none'}');
    last = now;
  });
}
