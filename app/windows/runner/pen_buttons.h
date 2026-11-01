#ifndef RUNNER_PEN_BUTTONS_H_
#define RUNNER_PEN_BUTTONS_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>

// **What the pen's buttons are doing, which Flutter does not tell us.**
//
// Flutter 3.44's Windows embedder reads a pen's PRESSURE and ROTATION out of
// `POINTER_PEN_INFO` and nothing else, and reports every pen contact as the
// left mouse button:
//
//     if (pointerInfo.pointerType == PT_PEN) {
//       POINTER_PEN_INFO penInfo;
//       if (windows_proc_table_->GetPointerPenInfo(pointerId, &penInfo)) {
//         pressure = penInfo.pressure;
//         rotation = penInfo.rotation;
//       }
//     }
//     ... OnPointerDown(x, y, device_kind, touch_id, WM_LBUTTONDOWN, ...)
//
// `penFlags` is never looked at anywhere in that embedder, so a barrel press
// cannot reach Dart as a button bit, whatever the app does with the bits it is
// handed. Upstream fixed it in flutter/flutter#183369 (re-landed as #187629)
// and it arrives here with a Flutter upgrade; this reads the same flags until
// then.
//
// **It has to be hooked onto the VIEW'S window, not the runner's.** The first
// attempt watched `FlutterWindow::MessageHandler`, which is the top-level
// window's procedure — and saw nothing, for a reason the engine's own source
// states plainly: *"The view owns the child window"*
// (`flutter_windows_view.cc`). Win32 sends pointer messages to the window
// under the cursor, which is that child, and Win32 does not bubble input to
// parents. So the messages were never going past the place that was watching.
// A diagnostic session's whole readout said `runner: nothing yet` with
// `button bits seen: 0x1` — the contact bit and nothing else, ever.
//
// [Attach] therefore subclasses the view's window. `SetWindowSubclass` rather
// than `SetWindowLongPtr`, because it is the documented way to chain onto a
// window somebody else owns and it cannot lose a procedure installed after
// ours.
//
// **Windows has two ways of delivering a pen, and this watches both**, because
// which one a machine uses is a driver setting rather than a fact:
//
//  1. **Windows Ink on** — the pen arrives as `WM_POINTER*`, and the buttons
//     are in `POINTER_PEN_INFO::penFlags`, with
//     `POINTER_INFO::pointerFlags & POINTER_FLAG_SECONDBUTTON` as the fallback
//     upstream's own patch uses when `GetPointerPenInfo` fails. The
//     diagnostic above showed this machine on this path: its pen events carry
//     a real pressure, and only this path reads one.
//  2. **Windows Ink off, or a vendor driver in mouse mode** — the driver
//     synthesises the mouse itself and the barrel arrives as a real
//     `WM_RBUTTONDOWN`. It is still identifiable: `GetMessageExtraInfo`
//     carries the pen signature, which is the same test the engine itself
//     uses in `GetFlutterPointerDeviceKind`.
//
// Deliberately NOT gated on `POINTER_FLAG_INCONTACT`, which is where this
// parts company with upstream: a button pressed while the pen hovers is how
// people actually use it — press, then touch down — and the app has supported
// that since the first report about it.
//
// It only ever OBSERVES. Every message is passed on untouched, nothing is
// synthesised, and where the pen cannot be identified it does nothing at all
// and the app behaves exactly as it did before this existed.
//
// **Other platforms.** Linux needs none of this: GTK reports a pen as
// `GDK_SOURCE_PEN` and passes the real GDK button number through, so a barrel
// press reaches Dart as a secondary button on a stylus. macOS needs its own
// version of this file: that embedder has no stylus device kind at all (it
// reports `mouse` or `trackpad`), so a pen's barrel arrives as a plain
// right-click and `NSEvent`'s `pointingDeviceType` — the only thing that could
// tell the two apart — is dropped before Dart sees it.
class PenButtons {
 public:
  explicit PenButtons(flutter::BinaryMessenger* messenger);
  ~PenButtons();

  // Subclass [view] — the window `FlutterViewController::view()->
  // GetNativeWindow()` returns — so pointer messages are seen on their way
  // past. Safe to call once; a second call replaces the first.
  void Attach(HWND view);

  // Mirrors `lib/core/pen_buttons.dart`.
  static constexpr int kBarrel = 1;    // a side button
  static constexpr int kInverted = 2;  // turned round
  static constexpr int kEraser = 4;    // the tail, which IS an eraser

 private:
  // Called for every message the view receives.
  void OnMessage(UINT message, WPARAM wparam);

  // Sends `bits` if they are not what was sent last.
  void Report(int bits);

  // Whether the message being handled came from a pen, for the messages that
  // do not carry a pointer id. Mirrors the engine's own signature test.
  static bool FromPenBySignature();

  static LRESULT CALLBACK Subclass(HWND window, UINT message, WPARAM wparam,
                                   LPARAM lparam, UINT_PTR id,
                                   DWORD_PTR ref);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  HWND view_ = nullptr;

  // -1 so the first answer is always sent, including a plain zero.
  int last_ = -1;

  // True while a pen-promoted right-click is down (delivery path 2), which
  // has no flags of its own to read on the way back up.
  bool promoted_barrel_ = false;
};

#endif  // RUNNER_PEN_BUTTONS_H_
