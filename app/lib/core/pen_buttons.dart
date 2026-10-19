/// **What the pen's buttons are doing**, from the one place that can tell us.
///
/// Flutter's Windows embedder reads a pen's pressure and rotation out of
/// `POINTER_PEN_INFO` and never looks at `penFlags`, and reports every pen
/// contact as the left mouse button. So a barrel press does not reach Dart as
/// a button bit at all, and no arrangement of `kPrimaryStylusButton` /
/// `kSecondaryStylusButton` / `kSecondaryButton` in the ink layer could have
/// found it — which is the whole of a report that came back three times:
///
/// > *"The buttons on the pen still dont work for erasing and selecting, which
/// > is what they are set to as a computer level on my device … Really want
/// > this working as its currently one of the most significant downaides when
/// > compared to onenote."*
///
/// Upstream has fixed it — flutter/flutter#183369, re-landed as #187629, after
/// which pen events carry a real button bitmap — and it arrives here with a
/// Flutter upgrade. Until then `windows/runner/pen_buttons.cpp` reads the same
/// flags out of the window messages on their way past and sends them here.
///
/// **One side button, not two.** Windows has a single `PEN_FLAG_BARREL`: a pen
/// with two side buttons reports both through it, so they cannot be told
/// apart by anybody, us included. The tail is separate (`PEN_FLAG_ERASER` /
/// `PEN_FLAG_INVERTED`) because that end of a pen *is* an eraser.
///
/// **The three desktops, which answer differently** — read out of the engine
/// source that ships inside the SDK, at
/// `<flutter>/engine/src/flutter/shell/platform/`:
///
///  * **Windows** (`windows/flutter_window.cc`) reads `pressure` and
///    `rotation` from the pen and hard-codes `WM_LBUTTONDOWN`. Nothing else.
///    Hence this file and the runner hook; both go when the engine is new
///    enough, and `ink_ops.dart` reads the bits it was always written for.
///  * **Linux** (`linux/fl_view.cc`) maps `GDK_SOURCE_PEN` and
///    `GDK_SOURCE_ERASER` to a stylus and passes the real GDK button number
///    to `fl_pointer_manager_handle_button_press`. So a barrel press already
///    arrives as a secondary button on a stylus and is handled by
///    `penGestureHoldsButton` — which is why that function exists separately
///    from what a press MEANS. This channel stays at zero there, and must.
///  * **macOS** (`darwin/macos/.../FlutterViewController.mm`) has no stylus
///    device kind at all: `deviceKind` is only ever `mouse` or `trackpad`. A
///    pen's barrel press therefore arrives as an ordinary right-click and
///    **cannot be told from one**, because `NSEvent.pointingDeviceType` and
///    `subtype == NSEventSubtypeTabletPoint` — the only things that could —
///    are dropped before Dart sees them. Doing this properly there needs the
///    same shape of hook in `macos/Runner/MainFlutterWindow.swift`, reading
///    `NSEvent` and posting to this channel. Not written: nobody here has a
///    Mac with a tablet to confirm it against, and a guess in a second
///    language is how this took three rounds in the first.
///
/// **Mobile, for when it comes.** Android reports a stylus kind and real
/// button state (`MotionEvent.BUTTON_STYLUS_PRIMARY`), which Flutter forwards,
/// so the `penGestureHoldsButton` route should serve it unchanged. iPadOS has
/// no barrel button on any Apple Pencil; the double-tap and squeeze gestures
/// are `UIPencilInteraction`, which is not a pointer event at all and would
/// need its own channel. Neither is wired up, and neither should be guessed.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bits, mirroring `windows/runner/pen_buttons.h`.
abstract final class PenButton {
  /// A side button — the barrel. One bit for however many the pen has.
  static const int barrel = 1;

  /// The pen is being held the other way round.
  static const int inverted = 2;

  /// The tail, which the digitiser reports as an eraser in its own right.
  static const int eraser = 4;
}

/// The live button state, and the channel that keeps it live.
abstract final class PenButtons {
  static const MethodChannel channel = MethodChannel('openote/pen_buttons');

  /// The bits currently held. Listened to by the canvas, so a press changes
  /// the cursor and the tool indicator before it changes any ink.
  static final ValueNotifier<int> bits = ValueNotifier<int>(0);

  /// **Whether the runner has ever reported anything.**
  ///
  /// The one fact that tells "the native hook is not in this build" apart
  /// from "it is, and this pen sends nothing" — which are the same symptom
  /// and completely different problems. Read by the pen test dialog, because
  /// a diagnostic that cannot say which of the two it is saves nobody a
  /// round trip.
  static bool heard = false;

  /// Start listening. Called once from `main`; harmless to call twice.
  static void listen() {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'buttons') {
        final v = call.arguments;
        if (v is int) {
          heard = true;
          bits.value = v;
        }
      }
      return null;
    });
  }

  /// Whether what is held should erase, given what the side button is for.
  ///
  /// The tail always erases: it is an eraser. The side button does what it has
  /// been set to do, and nothing is the honest third option for a pen whose
  /// buttons the OS has already claimed.
  static bool erases(int bits, PenButtonAction side) =>
      (bits & (PenButton.eraser | PenButton.inverted)) != 0 ||
      ((bits & PenButton.barrel) != 0 && side == PenButtonAction.eraser);

  /// Whether what is held should select.
  static bool selects(int bits, PenButtonAction side) =>
      (bits & PenButton.barrel) != 0 && side == PenButtonAction.select;

  /// **Whether a secondary press should be swallowed rather than open a menu.**
  ///
  /// With Windows Ink off, a vendor driver synthesises the mouse itself and a
  /// barrel press arrives as a real right-click — so the runner reports the
  /// button AND Flutter delivers a context-menu gesture at the same place. One
  /// of the two has to give, and it is the menu, because the student has said
  /// what that button is for.
  ///
  /// Unless they said "nothing", in which case the menu is the most useful
  /// thing a barrel press can do and is what Windows itself would have done.
  ///
  /// The ordering this rests on: the runner reads the message BEFORE handing
  /// it to the engine, and both the channel message and the pointer packet go
  /// to the same task runner, so the button arrives first. If a menu ever does
  /// flash, the fallback is for the runner to consume the message — at the
  /// cost of the "nothing" case above.
  static bool suppressesMenu(PenButtonAction side) =>
      (bits.value & PenButton.barrel) != 0 && side != PenButtonAction.nothing;
}

/// What a press of the pen's side button does.
///
/// Settable because the OS mapping is not readable: Windows hands over "a
/// barrel button is down" and nothing about what the student told their pen
/// driver it was for. The default is the eraser, which is what the button did
/// before this was a choice and what OneNote does with it.
enum PenButtonAction {
  eraser,
  select,
  nothing;

  // The names live in `lib/l10n/labels.dart` beside the other enum labels, so
  // the Draw row is not three English words in an otherwise translated app.
}
