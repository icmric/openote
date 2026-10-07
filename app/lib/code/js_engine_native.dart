/// The flutter_js half of [JsSession].
///
/// macOS and iOS use the system JavaScriptCore; everything else the bundled
/// QuickJS. Constructed directly rather than through `getJavascriptRuntime()`
/// — see the library comment in `code_runner.dart` for why.
library;

import 'dart:io';

import 'package:flutter_js/javascript_runtime.dart';
import 'package:flutter_js/javascriptcore/jscore_runtime.dart';
import 'package:flutter_js/quickjs/quickjs_runtime2.dart';

import 'js_session.dart';

/// Whether this build has a JavaScript engine at all.
///
/// A `const` and not a probe. Asking by *constructing* a runtime was the first
/// shape of this and it was wrong twice over: it loads a native library to
/// answer a question about the build, and it did so from
/// `Capabilities.has(codeBlocks)` — which the Insert catalogue asks on every
/// toolbar build, and which `flutter test` cannot satisfy at all because the
/// QuickJS library is not loaded in the harness.
const bool platformCanRunJs = true;

/// Never null on a desktop build: both engines ship with the app.
JsSession? platformStartJs() => _FlutterJsSession(
    (Platform.isMacOS || Platform.isIOS)
        ? JavascriptCoreRuntime()
        : QuickJsRuntime2());

class _FlutterJsSession implements JsSession {
  _FlutterJsSession(this._rt);

  final JavascriptRuntime _rt;

  @override
  JsResult eval(String source) {
    final r = _rt.evaluate(source);
    return (isError: r.isError, text: r.stringResult);
  }

  @override
  void dispose() => _rt.dispose();
}
