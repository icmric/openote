#include "pen_buttons.h"

#include <commctrl.h>
#include <flutter/standard_method_codec.h>

namespace {

// The signature Windows puts in `GetMessageExtraInfo` for input that came
// from a pen or a touchscreen, and the bit that tells the two apart. Taken
// from the engine's own `GetFlutterPointerDeviceKind`, which uses exactly
// this test to decide whether a mouse message is really a pen.
constexpr LPARAM kTouchOrPenSignature = 0xFF515700;
constexpr LPARAM kTouchBit = 0x80;
constexpr LPARAM kSignatureMask = 0xFFFFFF00;

// Any constant will do; it only has to be ours.
constexpr UINT_PTR kSubclassId = 0x0DEF7E11;

}  // namespace

PenButtons::PenButtons(flutter::BinaryMessenger* messenger)
    : channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "openote/pen_buttons",
          &flutter::StandardMethodCodec::GetInstance())) {
  // **Dart asks whether this is here.** "No buttons" has two causes with one
  // symptom — the hook is not in the build, or it is and the pen reports
  // nothing — and a diagnostic that cannot tell them apart costs a round trip
  // each time. Answering a call rather than announcing at startup, because
  // the Dart side registers its handler during `main` and a message sent
  // before that is simply dropped.
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "probe") {
          result->NotImplemented();
          return;
        }
        result->Success(flutter::EncodableValue(flutter::EncodableMap{
            {flutter::EncodableValue("attached"),
             flutter::EncodableValue(view_ != nullptr)},
            {flutter::EncodableValue("bits"),
             flutter::EncodableValue(last_ < 0 ? 0 : last_)},
        }));
      });
}

PenButtons::~PenButtons() {
  if (view_ != nullptr) {
    RemoveWindowSubclass(view_, Subclass, kSubclassId);
    view_ = nullptr;
  }
}

void PenButtons::Attach(HWND view) {
  if (view == nullptr) {
    return;
  }
  if (view_ != nullptr) {
    RemoveWindowSubclass(view_, Subclass, kSubclassId);
  }
  view_ = view;
  SetWindowSubclass(view, Subclass, kSubclassId,
                    reinterpret_cast<DWORD_PTR>(this));
}

LRESULT CALLBACK PenButtons::Subclass(HWND window, UINT message, WPARAM wparam,
                                      LPARAM lparam, UINT_PTR id,
                                      DWORD_PTR ref) {
  auto* self = reinterpret_cast<PenButtons*>(ref);
  if (self != nullptr) {
    self->OnMessage(message, wparam);
  }
  // Always passed on. This is an observer: consuming a pointer message here
  // would take the stroke away from the engine.
  return DefSubclassProc(window, message, wparam, lparam);
}

bool PenButtons::FromPenBySignature() {
  const LPARAM info = GetMessageExtraInfo();
  if ((info & kSignatureMask) != kTouchOrPenSignature) {
    return false;  // an ordinary mouse
  }
  return (info & kTouchBit) == 0;  // a pen rather than a finger
}

void PenButtons::Report(int bits) {
  if (bits == last_) {
    return;
  }
  last_ = bits;
  channel_->InvokeMethod("buttons",
                         std::make_unique<flutter::EncodableValue>(bits));
}

void PenButtons::OnMessage(UINT message, WPARAM wparam) {
  switch (message) {
    // Delivery path 2: the driver synthesised a mouse click from a pen. The
    // message carries no pen information of its own, only the signature, so
    // the down and the up have to be paired by hand.
    case WM_RBUTTONDOWN:
      if (FromPenBySignature()) {
        promoted_barrel_ = true;
        Report(kBarrel);
      }
      return;
    case WM_RBUTTONUP:
      if (promoted_barrel_) {
        promoted_barrel_ = false;
        Report(0);
      }
      return;

    // Delivery path 1: Windows Ink, where the flags are on the pointer.
    case WM_POINTERDOWN:
    case WM_POINTERUPDATE:
    case WM_POINTERUP:
    case WM_POINTERENTER:
    case WM_POINTERLEAVE:
      break;

    default:
      return;
  }

  // A pen carried out of range holds no buttons, by definition — and sends no
  // further event to say so, which is how a held button used to stick.
  if (message == WM_POINTERLEAVE) {
    Report(0);
    return;
  }

  const UINT32 id = GET_POINTERID_WPARAM(wparam);
  POINTER_INFO info{};
  if (!GetPointerInfo(id, &info)) {
    return;
  }
  if (info.pointerType != PT_PEN) {
    return;  // a finger or a mouse: not ours to report on
  }

  int bits = 0;
  POINTER_PEN_INFO pen{};
  if (GetPointerPenInfo(id, &pen)) {
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
  // **The fallback upstream's own patch keeps**, for a pen whose driver fills
  // in the generic pointer flags and leaves `penFlags` empty. Costs nothing
  // when both are set, because it is the same bit of meaning.
  if (info.pointerFlags & POINTER_FLAG_SECONDBUTTON) {
    bits |= kBarrel;
  }

  Report(bits);
}
