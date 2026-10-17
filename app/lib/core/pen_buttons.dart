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
/// Every other platform leaves this at zero, which is exactly the behaviour
/// the app had before it existed.
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

  /// Start listening. Called once from `main`; harmless to call twice.
  static void listen() {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'buttons') {
        final v = call.arguments;
        if (v is int) bits.value = v;
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
