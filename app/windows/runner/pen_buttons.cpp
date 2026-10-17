#include "pen_buttons.h"

#include <flutter/standard_method_codec.h>

PenButtons::PenButtons(flutter::BinaryMessenger* messenger)
    : channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "openote/pen_buttons",
          &flutter::StandardMethodCodec::GetInstance())) {}

void PenButtons::OnMessage(UINT message, WPARAM wparam) {
  switch (message) {
    case WM_POINTERDOWN:
    case WM_POINTERUPDATE:
    case WM_POINTERUP:
    case WM_POINTERENTER:
    case WM_POINTERLEAVE:
      break;
    default:
      return;
  }

  int bits = 0;
  // A pen carried out of range has no buttons held, by definition — and no
  // event afterwards to say so, which is how a held button used to stick.
  if (message != WM_POINTERLEAVE) {
    POINTER_PEN_INFO pen{};
    if (!GetPointerPenInfo(GET_POINTERID_WPARAM(wparam), &pen)) {
      return;  // a finger, a mouse, or a Windows too old to be asked
    }
    if (pen.penFlags & PEN_FLAG_BARREL) {
      bits |= kBarrel;
    }
    if (pen.penFlags & PEN_FLAG_INVERTED) {
      bits |= kInverted;
    }
    if (pen.penFlags & PEN_FLAG_ERASER) {
      bits |= kEraser;
    }
  }

  if (bits == last_) {
    return;
  }
  last_ = bits;
  channel_->InvokeMethod("buttons",
                         std::make_unique<flutter::EncodableValue>(bits));
}
