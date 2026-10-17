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
        tilt = e.tilt,
        distance = e.distance,
        device = e.device,
        synthesized = e.synthesized;

  final String phase;
  final PointerDeviceKind kind;
  final int buttons;
  final double pressure;
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
      'p=${pressure.toStringAsFixed(2)} tilt=${tilt.toStringAsFixed(2)} '
      'dist=${distance.toStringAsFixed(2)} dev=$device'
      '${synthesized ? ' synthesized' : ''}';
}

class _PenTestDialog extends StatefulWidget {
  const _PenTestDialog();

  @override
  State<_PenTestDialog> createState() => _PenTestDialogState();
}

class _PenTestDialogState extends State<_PenTestDialog> {
  final _seen = <_Seen>[];
  final _kinds = <PointerDeviceKind>{};
  var _buttonBits = 0;
  var _penSeen = false;

  static const _keep = 60;

  void _note(String phase, PointerEvent e) {
    setState(() {
      _seen.insert(0, _Seen(phase, e));
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

  String get _report => [
        'Openote pen & touch test',
        'kinds seen: ${_kinds.map((k) => k.name).join(', ')}',
        'button bits seen: 0x${_buttonBits.toRadixString(16)}',
        'last event would: $_verdict',
        '',
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
