/// The web half of [offThread]: the same isolate, one event-loop turn later.
///
/// `Future(work)` rather than calling [work] directly, so the caller still
/// yields to the frame before the work starts and an `await offThread(...)`
/// behaves the way it does everywhere else. What it cannot do is run the work
/// *during* a frame, which is the whole point on a desktop.
library;

Future<T> platformOffThread<T>(T Function() work) => Future(work);

const String platformOffThreadName = 'main';
