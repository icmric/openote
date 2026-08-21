/// The menu an answer carries: how it is written, and what to do with it.
///
/// The owner: *"Would also like to be able to right click on an answer and
/// choose number of significant figures, dec/frac mode, all those little
/// things."*
///
/// **It shows rather than tells.** The two form rows are the answer itself,
/// drawn as a decimal and drawn as a fraction, with a tick against the one on
/// the page — no words like "decimal" or "improper fraction" for a student to
/// have to map back onto the number in front of them. The figures row is the
/// same idea compressed: press 3 and read `0.707`. That is the owner's rule
/// for instructions, applied to a menu: *"rely as much on mapping, icons, and
/// alike for instructions rather than text."*
///
/// Only the three verbs at the bottom carry words, because there is no way to
/// draw "work it out again".
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import 'evaluate.dart';
import 'math_editor.dart';
import 'math_tree.dart';
import 'math_view.dart';

/// The figures a student is ever likely to want, and the one that means
/// "however many the number needs".
///
/// Three to six is the range every school and first-year lab report asks for;
/// ten is what the calculator on the desk shows, and is this app's own
/// default. Nothing above ten, because past that the digits are the floating
/// point talking rather than the maths.
const List<int?> kAnswerFigureChoices = [null, 3, 4, 5, 6, 10];

/// Show the menu for [answer]. [at] is in global coordinates.
///
/// Returns true when something changed and the host should commit.
Future<bool> showAnswerMenu(
  BuildContext context, {
  required Offset at,
  required MathEditor editor,
  required MAnswer answer,
}) async {
  final overlay =
      Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlay == null) return false;
  final surfaces = context.surfaces;
  final scheme = Theme.of(context).colorScheme;

  final decimal = editor.answerFormTex(answer, fraction: false);
  final fraction = editor.answerFormTex(answer, fraction: true);
  final isFraction = editor.answerIsFraction(answer);
  final figures = editor.answerSigFigs(answer);
  final angleBound = editor.answerDependsOnAngleMode(answer);

  Widget maths(String tex) => OnoteMath(
        tex,
        compact: true,
        textStyle: TextStyle(fontSize: 15, color: surfaces.textPrimary),
      );

  PopupMenuItem<String> form({
    required String value,
    required String tex,
    required bool on,
    required String semantics,
  }) =>
      PopupMenuItem<String>(
        key: ValueKey('answer-$value'),
        value: value,
        height: 34,
        child: Semantics(
          label: semantics,
          selected: on,
          child: Row(children: [
            SizedBox(
              width: 22,
              child: on
                  ? Icon(Icons.check, size: OnoteIcon.sm, color: scheme.primary)
                  : null,
            ),
            Flexible(child: maths(tex)),
          ]),
        ),
      );

  final items = <PopupMenuEntry<String>>[
    if (decimal != null)
      form(
        value: 'decimal',
        tex: decimal,
        on: !isFraction,
        semantics: 'as a decimal',
      ),
    if (fraction != null)
      form(
        value: 'fraction',
        tex: fraction,
        on: isFraction,
        semantics: 'as a fraction',
      ),
    if (!isFraction) ...[
      const PopupMenuDivider(height: 9),
      _FiguresRow(
        editor: editor,
        answer: answer,
        current: figures,
        surfaces: surfaces,
        accent: scheme.primary,
      ),
    ],
    const PopupMenuDivider(height: 9),
    PopupMenuItem<String>(
      value: 'again',
      height: 34,
      child: Row(children: [
        Icon(Icons.refresh, size: OnoteIcon.sm, color: surfaces.textSecondary),
        const SizedBox(width: 8),
        Text('Work it out again', style: OnoteType.ui),
        if (angleBound) ...[
          const Spacer(),
          // The one place the mode is named. It is here and not on the page
          // because an answer only ever depends on it SOMETIMES, and a label
          // that is usually meaningless is worse than none: this row is the
          // moment it means something.
          _Tag(
            text: mathAngleMode == AngleMode.degrees ? 'DEG' : 'RAD',
            surfaces: surfaces,
          ),
        ],
      ]),
    ),
    PopupMenuItem<String>(
      value: 'copy',
      height: 34,
      child: Row(children: [
        Icon(Icons.copy_outlined,
            size: OnoteIcon.sm, color: surfaces.textSecondary),
        const SizedBox(width: 8),
        Text('Copy', style: OnoteType.ui),
      ]),
    ),
    PopupMenuItem<String>(
      value: 'remove',
      height: 34,
      child: Row(children: [
        Icon(Icons.close,
            size: OnoteIcon.sm, color: surfaces.textSecondary),
        const SizedBox(width: 8),
        Text('Remove', style: OnoteType.ui),
      ]),
    ),
  ];

  final picked = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(at & Size.zero, Offset.zero & overlay.size),
    // Wide enough for the figures row, which is the widest thing here by a
    // long way. Without it the menu sizes to the maths rows — which are a
    // couple of digits — and the chips overflow off the right-hand edge,
    // where they cannot be seen OR pressed.
    constraints: const BoxConstraints(minWidth: 336, maxWidth: 380),
    items: items,
  );
  switch (picked) {
    case 'decimal':
      return editor.setAnswerForm(answer, fraction: false);
    case 'fraction':
      return editor.setAnswerForm(answer, fraction: true);
    case 'again':
      return editor.recalculateAnswer(answer);
    case 'copy':
      await Clipboard.setData(
          ClipboardData(text: editor.answerPlainText(answer)));
      return false;
    case 'remove':
      return editor.removeAnswer(answer);
  }
  // A figures chip closes the menu carrying its own choice, so that every
  // change this menu can make still happens in exactly one place.
  if (picked != null && picked.startsWith('sf:')) {
    final rest = picked.substring(3);
    return editor.setAnswerSigFigs(answer, rest == 'auto' ? null : int.parse(rest));
  }
  return false;
}

/// A row of significant-figure chips, each showing what you would get.
class _FiguresRow extends PopupMenuEntry<String> {
  const _FiguresRow({
    required this.editor,
    required this.answer,
    required this.current,
    required this.surfaces,
    required this.accent,
  });

  final MathEditor editor;
  final MAnswer answer;
  final int? current;
  final OnoteSurfaces surfaces;
  final Color accent;

  @override
  double get height => 38;

  @override
  bool represents(String? value) => false;

  @override
  State<_FiguresRow> createState() => _FiguresRowState();
}

class _FiguresRowState extends State<_FiguresRow> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 8, 2),
      child: Row(children: [
        Text('Figures',
            style: OnoteType.small.copyWith(color: widget.surfaces.textSecondary)),
        const SizedBox(width: 8),
        for (final f in kAnswerFigureChoices)
          _Chip(
            label: f == null ? 'Auto' : '$f',
            on: f == widget.current,
            preview: widget.editor.answerAtFiguresTex(widget.answer, f),
            surfaces: widget.surfaces,
            accent: widget.accent,
            onTap: () =>
                Navigator.of(context).pop('sf:${f == null ? 'auto' : f}'),
          ),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.on,
    required this.preview,
    required this.surfaces,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool on;
  final String? preview;
  final OnoteSurfaces surfaces;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chip = Padding(
      padding: const EdgeInsets.only(right: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(OnoteRadius.sm),
        onTap: onTap,
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? accent.withValues(alpha: 0.12) : null,
            borderRadius: BorderRadius.circular(OnoteRadius.sm),
            border:
                Border.all(color: on ? accent : surfaces.border),
          ),
          child: Text(label,
              style: OnoteType.small.copyWith(
                fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                color: on ? accent : surfaces.textPrimary,
              )),
        ),
      ),
    );
    final p = preview;
    if (p == null) return chip;
    // The tooltip is the number itself, so pressing is never a guess.
    return Tooltip(
      richMessage: WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: OnoteMath(p,
            compact: true,
            textStyle: TextStyle(fontSize: 13, color: surfaces.textPrimary)),
      ),
      child: chip,
    );
  }
}

/// A small upright label, for a mode that is only sometimes worth naming.
class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.surfaces});
  final String text;
  final OnoteSurfaces surfaces;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: surfaces.chrome2,
          borderRadius: BorderRadius.circular(OnoteRadius.sm),
        ),
        child: Text(text,
            style: OnoteType.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: surfaces.textSecondary,
            )),
      );
}
