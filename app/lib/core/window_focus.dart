/// Bringing the already-running Openote to the front.
///
/// Only half of "one Openote per workspace" is safety (see
/// [SingleInstance] — two processes on one WAL container is the corruption
/// case ADR-0006 §3 designs against). The other half is that the user
/// double-clicked a notebook and expects to *see* it. An instance that
/// silently switches notebooks behind another window is a silent no-op as far
/// as the person is concerned.
///
/// Windows only, deliberately and honestly:
///
/// * **Windows** has a documented handshake for this and no plugin is needed —
///   the launching process calls [allowForegroundHandover], which is what
///   makes the running process's `SetForegroundWindow` succeed instead of
///   merely flashing the taskbar button. Both halves are in this file.
/// * **Linux** cannot be done from Dart. Raising a window is `gtk_window_present`
///   on a `GtkWindow` this code has no handle on, and on Wayland it is the
///   compositor's decision anyway. Doing it properly means teaching
///   `linux/runner/my_application.cc` to be a unique `GApplication` — noted in
///   the report, not bodged here.
/// * **macOS** does not reach this code at all: files arrive through
///   `application(_:open:)`, not argv (backlog #42).
///
/// Everywhere except Windows both calls are no-ops that return false, so
/// callers need no platform check of their own.
///
/// **Not verified by running it.** Nothing in this file can be exercised by
/// `flutter test` beyond "does not throw and does nothing off Windows" — the
/// real proof is two Openotes on a desktop, which this change has not had.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

abstract final class WindowFocus {
  /// The class the Flutter Windows runner registers for its top-level window
  /// (`windows/runner/win32_window.cpp`), and the title `wWinMain` gives it
  /// (`windows/runner/main.cpp`). Matched together: the class alone would find
  /// ANY Flutter desktop app's window, and raising somebody else's app is a
  /// worse bug than not raising ours.
  static const _windowClass = 'FLUTTER_RUNNER_WIN32_WINDOW';
  static const _windowTitles = ['openote', 'Openote'];

  static const int _swRestore = 9;

  /// `ASFW_ANY` — `(DWORD)-1`.
  static const int _asfwAny = 0xFFFFFFFF;

  /// Called by the process that is about to hand its work to the running
  /// Openote and exit.
  ///
  /// Windows refuses `SetForegroundWindow` from a process that did not
  /// recently receive user input — the anti-focus-stealing rule. A process the
  /// user just launched by double-clicking a file DOES have that right, and
  /// this is the documented way to pass it on. Without it the running Openote
  /// switches notebooks correctly and its taskbar button merely blinks, which
  /// reads exactly like nothing happening.
  static bool allowForegroundHandover() {
    if (!Platform.isWindows) return false;
    try {
      return _allowSetForegroundWindow(_asfwAny) != 0;
    } catch (_) {
      return false;
    }
  }

  /// Called by the running Openote when a request arrives: un-minimise and
  /// come forward.
  static bool raiseSelf() {
    if (!Platform.isWindows) return false;
    try {
      final hwnd = _findOpenoteWindow();
      if (hwnd == 0) return false;
      if (_isIconic(hwnd) != 0) _showWindow(hwnd, _swRestore);
      return _setForegroundWindow(hwnd) != 0;
    } catch (_) {
      // A missing user32 export or a hostile window manager must never take
      // the app down; the notebook has already been switched by this point.
      return false;
    }
  }

  static int _findOpenoteWindow() {
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
  static DynamicLibrary get _user32 => DynamicLibrary.open('user32.dll');

  static final _findWindowW = _user32.lookupFunction<
      IntPtr Function(Pointer<Utf16>, Pointer<Utf16>),
      int Function(Pointer<Utf16>, Pointer<Utf16>)>('FindWindowW');

  static final _setForegroundWindow = _user32.lookupFunction<
      Int32 Function(IntPtr), int Function(int)>('SetForegroundWindow');

  static final _showWindow = _user32.lookupFunction<Int32 Function(IntPtr, Int32),
      int Function(int, int)>('ShowWindow');

  static final _isIconic = _user32
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>('IsIconic');

  static final _allowSetForegroundWindow = _user32.lookupFunction<
      Int32 Function(Uint32), int Function(int)>('AllowSetForegroundWindow');
}
