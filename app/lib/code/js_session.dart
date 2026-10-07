/// One JavaScript evaluation context, with the engine behind it unnamed.
///
/// Exists so `code_runner.dart` can hold a JS engine without naming
/// `flutter_js`, which has no web build and was 2,681 of the 8,284 errors a
/// web build reported. `js_engine_native.dart` implements this over
/// flutter_js; `js_engine_web.dart` declines to implement it at all.
library;

/// The result of evaluating a snippet: whether it threw, and the text to show.
///
/// A record rather than flutter_js's own `JsEvalResult`, because that type is
/// the thing being hidden.
typedef JsResult = ({bool isError, String text});

abstract class JsSession {
  JsResult eval(String source);

  void dispose();
}
