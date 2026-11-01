/// The Win32 half of [WindowFocus], behind a conditional import.
///
/// `dart:ffi` does not exist on the web and importing it is a hard compile
/// error, so the FFI lives here and `window_focus_web.dart` answers the other
/// side. See `free_space_native.dart` for the first of these pairs and
/// `window_focus.dart` for the class that chooses.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// The class the Flutter Windows runner registers for its top-level window
/// (`windows/runner/win32_window.cpp`), and the title `wWinMain` gives it
/// (`windows/runner/main.cpp`). Matched together: the class alone would find
/// ANY Flutter desktop app's window, and raising somebody else's app is a
/// worse bug than not raising ours.
const _windowClass = 'FLUTTER_RUNNER_WIN32_WINDOW';
const _windowTitles = ['openote', 'Openote'];

const int _swRestore = 9;

/// `ASFW_ANY` — `(DWORD)-1`.
const int _asfwAny = 0xFFFFFFFF;

/// Windows refuses `SetForegroundWindow` from a process that did not recently
/// receive user input — the anti-focus-stealing rule. A process the user just
/// launched by double-clicking a file DOES have that right, and this is the
/// documented way to pass it on. Without it the running Openote switches
/// notebooks correctly and its taskbar button merely blinks, which reads
/// exactly like nothing happening.
bool platformAllowForegroundHandover() {
  if (!Platform.isWindows) return false;
  try {
    return _allowSetForegroundWindow(_asfwAny) != 0;
  } catch (_) {
    return false;
  }
}

/// Un-minimise the running Openote and bring it forward.
bool platformRaiseSelf() {
  if (!Platform.isWindows) return false;
  try {
    final hwnd = _findOpenoteWindow();
    if (hwnd == 0) return false;
    if (_isIconic(hwnd) != 0) _showWindow(hwnd, _swRestore);
    return _setForegroundWindow(hwnd) != 0;
  } catch (_) {
    // A missing user32 export or a hostile window manager must never take the
    // app down; the notebook has already been switched by this point.
    return false;
  }
}

int _findOpenoteWindow() {
  final cls = _windowClass.toNativeUtf16();
  try {
    for (final title in _windowTitles) {
      final name = title.toNativeUtf16();
      try {
        final hwnd = _findWindowW(cls, name);
        if (hwnd != 0) return hwnd;
      } finally {
        calloc.free(name);
      }
    }
    return 0;
  } finally {
    calloc.free(cls);
  }
}

// Resolved lazily, exactly as `PlatformOpen` resolves shell32: a top-level
// `DynamicLibrary.open('user32.dll')` would run on Linux the moment anything
// in this library is touched.
DynamicLibrary get _user32 => DynamicLibrary.open('user32.dll');

final _findWindowW = _user32.lookupFunction<
    IntPtr Function(Pointer<Utf16>, Pointer<Utf16>),
    int Function(Pointer<Utf16>, Pointer<Utf16>)>('FindWindowW');

final _setForegroundWindow = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'SetForegroundWindow');

final _showWindow = _user32.lookupFunction<Int32 Function(IntPtr, Int32),
    int Function(int, int)>('ShowWindow');

final _isIconic = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('IsIconic');

final _allowSetForegroundWindow = _user32
    .lookupFunction<Int32 Function(Uint32), int Function(int)>(
        'AllowSetForegroundWindow');
