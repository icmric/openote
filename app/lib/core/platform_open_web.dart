/// The web half of [PlatformOpen].
///
/// **URLs work here; local paths do not, and that asymmetry is the point.**
/// A link in note text is the common case and the browser is better at it than
/// any desktop shell — so [platformHandOff] opens it in a new tab. A file or a
/// folder on the user's disk is not something a page may reach, so the two
/// existence checks answer false and [PlatformOpen.file] / `.folder` return
/// false, which is the answer they already document for "no handler".
///
/// The existence checks are here rather than left to `dart:io` on purpose.
/// `dart:io` compiles on the web but its `File` and `Directory` throw when
/// called, so `File(path).existsSync()` in the shared facade would turn a
/// documented false into an uncaught exception.
library;

import 'package:web/web.dart' as web;

bool platformFileExists(String path) => false;

bool platformDirectoryExists(String path) => false;

Future<bool> platformHandOff(String target) async {
  // `noopener` because the opened page must not get a handle on this one.
  // Reached from note text, and note text is untrusted — the same reason
  // `platform_open.dart` keeps a scheme allow-list in front of this call.
  final opened = web.window.open(target, '_blank', 'noopener,noreferrer');
  // A popup blocker answers null. Returning false says "it did not open",
  // which is what the caller surfaces, rather than claiming success.
  // ignore: unnecessary_null_comparison
  return opened != null;
}
