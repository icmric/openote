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
// `penFlags` is never looked at anywhere in that embedder — no barrel, no
// eraser, no inverted — so a barrel press cannot reach Dart at all, whatever
// the app does with the button bits it is handed. That is the whole of the
// report that has now come back three times: *"the buttons on the pen still
// dont work for erasing and selecting."*
//
// Upstream has fixed it (flutter/flutter#183369, re-landed as #187629: pen
// events report a real button bitmap and an inverted pen reports itself), and
// it will arrive here with a Flutter upgrade. This is the same information,
// read in the one place that is ours until then: the runner's own window
// procedure sees every `WM_POINTER*` message before the engine does.
//
// It only ever OBSERVES. No message is consumed, nothing is synthesised, and
// if `GetPointerPenInfo` fails — not a pen, or an older Windows — it does
// nothing at all and the app behaves exactly as it does today.
class PenButtons {
 public:
  explicit PenButtons(flutter::BinaryMessenger* messenger);

  // Called for every window message. Sends to Dart only when the answer
  // changes, so a pen streaming a hundred moves a second costs one message.
  void OnMessage(UINT message, WPARAM wparam);

  // Mirrors `lib/core/pen_buttons.dart`.
  static constexpr int kBarrel = 1;    // a side button
  static constexpr int kInverted = 2;  // turned round
  static constexpr int kEraser = 4;    // the tail, which IS an eraser

 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  // -1 so the first answer is always sent, including a plain zero.
  int last_ = -1;
};

#endif  // RUNNER_PEN_BUTTONS_H_
