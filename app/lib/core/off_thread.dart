/// Run a piece of work somewhere that is not the frame.
///
/// `Isolate.run` is the desktop answer and the right one: hashing 488 blobs is
/// 2.8 seconds of CPU with a 164 ms single file in it, and no per-file yield
/// can divide that. A browser has no isolates — `Isolate.run` fails with
/// *"Unsupported operation: new RawReceivePort"*, which is how the demo's op
/// log announced itself with a red "Saved, but not recorded" banner on the
/// first frame.
///
/// So the web runs the same closure on the main isolate, after a turn of the
/// event loop. **That is a real cost and is stated rather than hidden**: a
/// long task will stutter the demo where it would not stutter the app. It is
/// acceptable here and nowhere else, because the demo's notebooks are the ones
/// a visitor typed in the last two minutes — there is no 488-blob workspace in
/// a tab that is wiped on refresh.
///
/// The closure must be isolate-safe either way: written so it captures only
/// what it names, since on a desktop it really is sent. Keeping one signature
/// for both is what stops that discipline quietly lapsing in a web-only path.
library;

import 'off_thread_native.dart'
    if (dart.library.js_interop) 'off_thread_web.dart';

/// Run [work] off the UI thread where there is one, and off the current frame
/// where there is not.
Future<T> offThread<T>(T Function() work) => platformOffThread(work);

/// Where [offThread] put the last piece of work, for a test that needs to
/// prove it moved at all. `main` means it did not.
String get offThreadName => platformOffThreadName;
