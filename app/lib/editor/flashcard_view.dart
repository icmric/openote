import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/onote_theme.dart';
import '../theme/tokens.dart';

/// The card itself: two faces and the turn between them.
///
/// Presentation only — it takes two strings and knows nothing about blocks,
/// Markdown or storage. That is what lets the same card appear in three
/// places: as a block on the page, as a line inside a paragraph in read mode,
/// and as a placeholder inside the live editor. A card that looked different
/// depending on which of those you were looking at would not read as one
/// object.
///
/// **The flip is the design.** A card that swaps its text is a label changing;
/// a card that turns over is an object you are holding. The rotation is about
/// the vertical axis with perspective set so it reads as a card rather than a
/// rectangle being squashed.
class FlipCard extends StatefulWidget {
  const FlipCard({
    super.key,
    required this.front,
    required this.back,
    this.trailing,
    this.compact = false,
  });

  final String front;
  final String back;

  /// An extra control on the face — the block form puts its edit button here.
  /// In flow there is nothing: you edit the card by editing the line.
  final Widget? trailing;

  /// The in-flow form, which sits among paragraphs and must not shout.
  final bool compact;

  @override
  State<FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<FlipCard>
    with SingleTickerProviderStateMixin {
  /// Created in [initState], NOT as a `late final` initialiser: a lazily
  /// created controller first touched in `dispose()` asserts, because the
  /// element is deactivated by then and the ticker looks up an ancestor.
  late final AnimationController _flip;

  @override
  void initState() {
    super.initState();
    _flip = AnimationController(vsync: this, duration: OnoteMotion.large);
  }

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  bool get _showingBack => _flip.value >= 0.5;

  void _toggle() {
    if (_flip.isCompleted || _flip.velocity > 0) {
      _flip.reverse();
    } else {
      _flip.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: _flip,
      builder: (context, _) {
        final angle = Curves.easeInOut.transform(_flip.value) * math.pi;
        return Transform(
          key: const ValueKey('flashcard-flip'),
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0015)
            ..rotateY(angle),
          child: _showingBack
              // Un-mirror the back: the rotation that brought it round would
              // otherwise lay it out reversed.
              ? Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(math.pi),
                  child: _face(dark, back: true),
                )
              : _face(dark, back: false),
        );
      },
    );
  }

  Widget _face(bool dark, {required bool back}) {
    final text = back ? widget.back : widget.front;
    final accent = back ? OnoteColors.ink300 : OnoteColors.brass400;
    final pad = widget.compact ? OnoteSpace.x4 : OnoteSpace.x6;
    return Container(
      decoration: BoxDecoration(
        color: dark ? OnoteColors.night100 : Colors.white,
        borderRadius: OnoteRadius.xlAll,
        border: Border.all(color: accent.withValues(alpha: .55), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .35 : .08),
            blurRadius: widget.compact ? 6 : 10,
            offset: Offset(0, widget.compact ? 2 : 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _toggle,
          child: Stack(
            children: [
              // The accent stripe is what answers "which side am I looking at"
              // without reading a word.
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(width: widget.compact ? 4 : 5, color: accent),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(pad + OnoteSpace.x4, pad, pad, pad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize:
                      widget.compact ? MainAxisSize.min : MainAxisSize.max,
                  children: [
                    Row(
                      children: [
                        Text(back ? 'ANSWER' : 'QUESTION',
                            style: OnoteType.overline.copyWith(color: accent)),
                        const Spacer(),
                        if (widget.trailing != null) widget.trailing!,
                      ],
                    ),
                    const SizedBox(height: OnoteSpace.x3),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Text(
                          text.trim().isEmpty
                              ? (back ? 'No answer yet' : 'No question yet')
                              : text,
                          style: OnoteType.ui.copyWith(
                            fontSize: widget.compact ? 14 : 16,
                            height: 1.4,
                            color: text.trim().isEmpty
                                ? OnoteColors.graphite400
                                : null,
                            fontStyle: text.trim().isEmpty
                                ? FontStyle.italic
                                : FontStyle.normal,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: OnoteSpace.x3),
                    Row(
                      children: [
                        const Icon(Icons.autorenew,
                            size: 12, color: OnoteColors.graphite400),
                        const SizedBox(width: OnoteSpace.x2),
                        Text(back ? 'Tap to go back' : 'Tap to reveal',
                            style: OnoteType.caption
                                .copyWith(color: OnoteColors.graphite400)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ask for a new front and back. Returns null when cancelled.
///
/// A dialog rather than fields on the card itself, and that is deliberate: an
/// in-flow card lives inside a `TextField`'s span tree, and putting editable
/// fields in there means two editors competing for focus and a caret that
/// belongs to neither. The block form can afford inline fields because it is a
/// block; this one cannot.
Future<({String front, String back})?> editCardDialog(
        BuildContext context, String front, String back) =>
    showDialog<({String front, String back})>(
      context: context,
      builder: (_) => _EditCardDialog(front: front, back: back),
    );

class _EditCardDialog extends StatefulWidget {
  const _EditCardDialog({required this.front, required this.back});
  final String front;
  final String back;

  @override
  State<_EditCardDialog> createState() => _EditCardDialogState();
}

class _EditCardDialogState extends State<_EditCardDialog> {
  late final _front = TextEditingController(text: widget.front);
  late final _back = TextEditingController(text: widget.back);

  @override
  void dispose() {
    _front.dispose();
    _back.dispose();
    super.dispose();
  }

  void _submit() =>
      Navigator.of(context).pop((front: _front.text, back: _back.text));

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Edit card'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('QUESTION',
                  style:
                      OnoteType.overline.copyWith(color: OnoteColors.brass400)),
              const SizedBox(height: OnoteSpace.x2),
              TextField(
                controller: _front,
                autofocus: true,
                maxLines: null,
                style: OnoteType.ui.copyWith(fontSize: 15),
                decoration: const InputDecoration(isDense: true),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: OnoteSpace.x5),
              Text('ANSWER',
                  style: OnoteType.overline.copyWith(color: OnoteColors.ink300)),
              const SizedBox(height: OnoteSpace.x2),
              TextField(
                controller: _back,
                maxLines: null,
                style: OnoteType.ui.copyWith(fontSize: 15),
                decoration: const InputDecoration(isDense: true),
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          FilledButton(onPressed: _submit, child: const Text('Done')),
        ],
      );
}
