/// The web half of [JsSession]: no JavaScript engine, on purpose.
///
/// There is an obvious one right there — the browser's own — and this
/// deliberately does not reach for it. A code block's source is note content,
/// and note content is untrusted: an imported OneNote page or a shared
/// notebook can carry anything a stranger wrote. On a desktop that snippet
/// runs inside a separate QuickJS interpreter in a spawned isolate with a
/// five-second budget and no DOM. `eval` in the page would run it in the app's
/// own origin, with access to everything the app can reach. That is not the
/// same feature with a different engine behind it; it is a different and much
/// worse one.
///
/// So the honest answer is no, and the demo greys the Code block out — see
/// `core/capabilities.dart`, which asks this file.
library;

import 'js_session.dart';

JsSession? platformStartJs() => null;
