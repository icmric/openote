/// **What the pen, the finger and the buttons actually report.**
///
/// The pen-buttons report has come back three times now, from two different
/// people, on hardware nobody working on this owns:
///
/// > *"Pressing the button on my pen i have defined to be the eraser does not
/// > change it … pressing one of them does cause a circle to come around the
/// > pointer on screen but this may be a windows thing."*
///
/// > *"The buttons on the pen still dont work for erasing and selecting, which
/// > is what they are set to as a computer level on my device."*
///
/// Each time it has been answered by reasoning about what Windows *probably*
/// sends — three button bits are accepted, and the kind is widened to `mouse`
/// because a barrel press is often promoted to a right-click. That is a guess
/// with a test around it, which is the worst kind: it looks settled.
///
/// This is the instrument instead. It shows every pointer event the app
/// receives, with its kind, its button bits and its pressure, and says what
/// the ink layer would conclude from it — so the next report can be *"here is
/// what my pen sends"* rather than *"it does not work"*.
///
/// Deliberately not localised below the title: the readout is evidence meant
/// to be pasted into an issue, and translating hex into seven languages would
/// make it harder to read, not easier.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../canvas/ink_ops.dart';
import '../core/pen_buttons.dart';
import '../l10n/l10n.dart';
import '../theme/onote_theme.dart';
import '../theme/tokens.dart';
import 'onote_dialog.dart';

Future<void> showPenTestDialog(BuildContext context) => showOnoteDialog<void>(
      context: context,
      builder: (_) => const _PenTestDialog(),
    );

/// One line of the readout.
class _Seen {
  _Seen(this.phase, PointerEvent e)
      : kind = e.kind,
        buttons = e.buttons,
        pressure = e.pressure,
        pressureMax = e.pressureMax,
        tilt = e.tilt,
        distance = e.distance,
        device = e.device,
        synthesized = e.synthesized;

  final String phase;
  final PointerDeviceKind kind;
  final int buttons;
  final double pressure;
  final double pressureMax;
  final double tilt;
  final double distance;
  final int device;
  final bool synthesized;

  /// The bits, named. `kPrimaryStylusButton` shares its value with
  /// `kSecondaryButton` and `kSecondaryStylusButton` with `kTertiaryButton`,
  /// which is exactly the ambiguity this dialog exists to resolve, so both
  /// names are printed.
  String get bits {
    if (buttons == 0) return 'none';
    final out = <String>[];
    if (buttons & kPrimaryButton != 0) out.add('primary/contact');
    if (buttons & kSecondaryButton != 0) out.add('secondary/barrel');
    if (buttons & kTertiaryButton != 0) out.add('tertiary/stylus2');
    final rest = buttons & ~(kPrimaryButton | kSecondaryButton | kTertiaryButton);
    if (rest != 0) out.add('other 0x${rest.toRadixString(16)}');
    return out.join(' + ');
  }

  @override
  String toString() => '${phase.padRight(6)} ${kind.name.padRight(14)} '
      'buttons=0x${buttons.toRadixString(16)} ($bits) '
      // **Out of what**: Windows reports a pen's pressure as 0..1024 and the
      // engine passes the range through beside it, so a bare "674" reads as
      // a bug when it is a perfectly ordinary two-thirds.
      'p=${pressure.toStringAsFixed(0)}/${pressureMax.toStringAsFixed(0)} '
      'tilt=${tilt.toStringAsFixed(2)} '
      'dist=${distance.toStringAsFixed(2)} dev=$device'
      '${synthesized ? ' synthesized' : ''}';
}

class _PenTestDialog extends StatefulWidget {
  const _PenTestDialog();

  @override
  State<_PenTestDialog> createState() => _PenTestDialogState();
}

class _PenTestDialogState extends State<_PenTestDialog> {
  @override
  void initState() {
    super.initState();
    // The runner's report is not a pointer event, so nothing else would
    // rebuild this when a button is pressed while the pen hovers — which is
    // exactly the case somebody opens this dialog to look at.
    PenButtons.bits.addListener(_refresh);
    // Ask the native side whether it is there at all, which is the first
    // thing anybody opening this needs to know.
    PenButtons.probe().then((_) => _refresh());
  }

  @override
  void dispose() {
    PenButtons.bits.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  final _seen = <_Seen>[];
  final _kinds = <PointerDeviceKind>{};
  var _buttonBits = 0;
  var _penSeen = false;

  static const _keep = 60;

  /// **Events that carried a button, kept where they cannot scroll away.**
  ///
  /// The first real readout from a pen lost its button presses to the
  /// sixty-event cap — the cumulative summary survived and said `0x1`, which
  /// is what made the session useful, but the detail of the one moment
  /// anybody opens this for was gone. So that moment gets a list of its own.
  final _pressed = <_Seen>[];

  void _note(String phase, PointerEvent e) {
    setState(() {
      final seen = _Seen(phase, e);
      if (e.buttons & ~kPrimaryButton != 0 && _pressed.length < 20) {
        _pressed.insert(0, seen);
      }
      _seen.insert(0, seen);
      if (_seen.length > _keep) _seen.removeLast();
      _kinds.add(e.kind);
      _buttonBits |= e.buttons;
      if (e.kind == PointerDeviceKind.stylus ||
          e.kind == PointerDeviceKind.invertedStylus) {
        _penSeen = true;
      }
    });
  }

  /// What the ink layer would make of the newest event — the actual question,
  /// answered by the same function the canvas asks.
  String get _verdict {
    if (_seen.isEmpty) return 'nothing yet';
    final e = _seen.first;
    if (penGestureErases(
        kind: e.kind, buttons: e.buttons, penInRange: _penSeen)) {
      return 'ERASE — a pen button the app understands';
    }
    if (e.kind == PointerDeviceKind.stylus ||
        e.kind == PointerDeviceKind.invertedStylus) {
      return 'draw — a plain pen contact';
    }
    if (e.kind == PointerDeviceKind.touch) {
      return 'touch — navigate, unless touch drawing is set to Always';
    }
    return 'mouse — whatever the current tool does';
  }

  /// **The first thing to establish**, because "no buttons" has two
  /// completely different causes with one symptom: the native hook is not in
  /// this build, or it is and the pen reports nothing through it. A
  /// diagnostic that cannot tell those apart saves nobody a round trip.
  String get _runnerLine {
    final where = switch (PenButtons.attached) {
      true => 'hooked onto the view',
      false => 'NOT IN THIS BUILD — rebuild the Windows runner',
      null => 'no hook on this platform (only Windows needs one)',
    };
    final heard = PenButtons.heard
        ? 'reporting 0x${PenButtons.bits.value.toRadixString(16)}'
        : 'has not reported a button yet';
    return 'runner: $where, $heard';
  }

  String get _report => [
        'Openote pen & touch test',
        _runnerLine,
        'kinds seen: ${_kinds.map((k) => k.name).join(', ')}',
        'button bits seen: 0x${_buttonBits.toRadixString(16)}',
        'last event would: $_verdict',
        '',
        if (_pressed.isNotEmpty) ...[
          'WITH A BUTTON (kept, never scrolled off):',
          ..._pressed.map((s) => s.toString()),
          '',
        ],
        ..._seen.map((s) => s.toString()),
      ].join('\n');

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final mono = TextStyle(
      fontFamily: 'JetBrains Mono',
      fontFamilyFallback: onoteFontFallback,
      fontSize: 11,
      color: context.surfaces.textSecondary,
    );
    return AlertDialog(
      title: Text(l.settingsPenTest),
      content: SizedBox(
        width: 560,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            'Draw in the box with your pen, hover it, and press each of its '
            'buttons — then copy this and paste it into the issue. Every line '
            'is one event the app was handed.',
            style: TextStyle(fontSize: 12, color: context.surfaces.textSecondary),
          ),
          const SizedBox(height: 8),
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) => _note('down', e),
            onPointerMove: (e) => _note('move', e),
            onPointerUp: (e) => _note('up', e),
            onPointerHover: (e) => _note('hover', e),
            onPointerCancel: (e) => _note('cancel', e),
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.surfaces.border),
                color: context.surfaces.canvas,
              ),
              alignment: Alignment.center,
              child: Text('press, draw and hover here',
                  style: TextStyle(
                      fontSize: 12, color: context.surfaces.textSecondary)),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '$_runnerLine\n'
              'kinds: ${_kinds.isEmpty ? '—' : _kinds.map((k) => k.name).join(', ')}'
              '    buttons: 0x${_buttonBits.toRadixString(16)}'
              '\nthe last event would: $_verdict',
              style: mono.copyWith(color: null),
            ),
          ),
          const SizedBox(height: 6),
          // **Flexible, not a fixed height.** A dialog gets whatever the
          // window leaves it, and three fixed heights plus two paragraphs
          // overflowed a 600x800 window by sixteen pixels — which the test
          // below caught before anybody with a small screen did.
          Flexible(
              child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: context.surfaces.chrome2,
            ),
            child: ListView.builder(
              itemCount: _seen.length,
              itemBuilder: (_, i) => Text(_seen[i].toString(), style: mono),
            ),
          )),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: _report));
            if (context.mounted) Navigator.pop(context);
          },
          child: Text(l.commonCopy),
        ),
        FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.commonClose)),
      ],
    );
  }
}
