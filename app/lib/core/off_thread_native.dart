/// The desktop half of [offThread]: a real isolate.
library;

import 'dart:isolate';

Future<T> platformOffThread<T>(T Function() work) => Isolate.run(work);

/// `main` on the UI isolate, `_RemoteRunner._remoteExecute` inside an
/// `Isolate.run`. Read from within the work to prove it was sent.
String get platformOffThreadName => Isolate.current.debugName ?? '?';
