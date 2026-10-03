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
