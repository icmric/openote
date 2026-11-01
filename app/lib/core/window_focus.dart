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
///   merely flashing the taskbar button. Both halves are in
///   `window_focus_native.dart`.
/// * **Linux** cannot be done from Dart. Raising a window is `gtk_window_present`
///   on a `GtkWindow` this code has no handle on, and on Wayland it is the
///   compositor's decision anyway. Doing it properly means teaching
///   `linux/runner/my_application.cc` to be a unique `GApplication` — noted in
///   the report, not bodged here.
/// * **macOS** does not reach this code at all: files arrive through
///   `application(_:open:)`, not argv (backlog #42).
/// * **The web** has no second instance to raise, and no argv to be launched
///   with. `window_focus_web.dart` answers false, which is the same answer
///   Linux already gets.
///
/// Everywhere except Windows both calls are no-ops that return false, so
/// callers need no platform check of their own.
///
/// **Not verified by running it.** Nothing in this file can be exercised by
/// `flutter test` beyond "does not throw and does nothing off Windows" — the
/// real proof is two Openotes on a desktop, which this change has not had.
library;

// The Win32 calls live in the native half; the web half answers false, which
// is already this class's documented answer off Windows.
import 'window_focus_native.dart'
    if (dart.library.js_interop) 'window_focus_web.dart';

abstract final class WindowFocus {
  /// Called by the process that is about to hand its work to the running
  /// Openote and exit.
  static bool allowForegroundHandover() => platformAllowForegroundHandover();

  /// Called by the running Openote when a request arrives: un-minimise and
  /// come forward.
  static bool raiseSelf() => platformRaiseSelf();
}
