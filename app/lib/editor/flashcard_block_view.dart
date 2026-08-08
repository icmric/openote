import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import '../theme/tokens.dart';

/// A flashcard living on the page, written and revised where it sits.
///
/// content: `{ front, back }`
///
/// **Why this exists.** Cards were derived from tags only: mark a line
/// Question or Definition and one appears in the study tab. That is a lovely
/// trick and nobody found it — "Currently not intuitive how to use them" —
/// because nothing about typing notes suggests a tag makes a card, and the
/// chords are invisible until told. A thing you can insert, see, and flip is
/// self-explanatory in a way a keyboard chord never is.
///
/// It does not replace the tag route; both produce cards through
/// `cardsFromBlock`, so this card is in the deck, the counts and the exam plan
/// the moment its two halves are filled in.
///
/// **The flip is the whole design.** A card that just swaps its text is a
/// label changing; a card that turns over is an object you are holding. For a
/// fifteen-year-old deciding whether revision is worth the effort, that
/// difference is most of the argument — so the flip is a real rotation about
/// the vertical axis, with the perspective set so it reads as a card rather
/// than a shrinking rectangle.
class FlashcardBlockView extends StatefulWidget {
  const FlashcardBlockView({super.key, required this.block, required this.app});
  final Block block;
  final AppState app;

  @override
  State<FlashcardBlockView> createState() => _FlashcardBlockViewState();
}

class _FlashcardBlockViewState extends State<FlashcardBlockView>
    with SingleTickerProviderStateMixin {
  /// Created in [initState], NOT as a `late final` initialiser.
  ///
  /// A card inserted from the menu opens straight into the editor and its
  /// build never touches this — so with lazy initialisation the controller was
  /// first constructed inside `dispose()`, where the element is already
  /// deactivated and the ticker's ancestor lookup asserts. Every newly created
  /// card threw on the way out.
  late final AnimationController _flip;

  bool _editing = false;
  TextEditingController? _front;
  TextEditingController? _back;

  String get _frontText => widget.block.content['front'] as String? ?? '';
  String get _backText => widget.block.content['back'] as String? ?? '';
  bool get _blank => _frontText.trim().isEmpty && _backText.trim().isEmpty;

  /// Past the halfway point the back is the face you are looking at.
  bool get _showingBack => _flip.value >= 0.5;

  @override
  void initState() {
    super.initState();
    _flip = AnimationController(vsync: this, duration: OnoteMotion.large);
    // A card dropped on the page has nothing on it, so it opens ready to be
    // written rather than as an empty rectangle you have to work out how to
    // fill. Through _openEditor, NOT by setting the flag: the editor's fields
    // are driven by controllers this state owns, and flipping the flag alone
    // gave each TextField an internal controller of its own — so everything
    // typed into a brand new card went into an object nothing ever read, and
    // Done saved two empty strings. The primary flow, broken.
    if (_blank) _openEditor();
  }

  @override
  void dispose() {
    _flip.dispose();
    _front?.dispose();
    _back?.dispose();
    super.dispose();
  }

  void _toggleFlip() {
    if (_editing) return;
    if (_flip.isCompleted || _flip.velocity > 0) {
      _flip.reverse();
    } else {
      _flip.forward();
    }
  }

  /// Open the editor. The one place `_editing` becomes true, so the fields can
  /// never exist without the controllers behind them.
  void _openEditor() {
    _front?.dispose();
    _back?.dispose();
    _front = TextEditingController(text: _frontText);
    _back = TextEditingController(text: _backText);
    _editing = true;
  }

  void _startEditing() {
    setState(_openEditor);
    // Editing a card you had turned over is confusing — both halves are shown
    // side by side, so the flip state means nothing while it is open.
    _flip.value = 0;
  }

  void _commit() {
    final f = _front?.text ?? '';
    final b = _back?.text ?? '';
    if (f != _frontText || b != _backText) {
      widget.app.pushUndo();
      widget.block.content['front'] = f;
      widget.block.content['back'] = b;
      widget.block.updatedAt = nowMs();
      // Through the normal funnel, so the op log records it and the card
      // reaches the study deck on the next rebuild.
      widget.app.updateBlock(widget.block);
      widget.app.markDirty();
    }
    _front?.dispose();
    _back?.dispose();
    _front = null;
    _back = null;
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (_editing) return _editor(dark);
    return AnimatedBuilder(
      animation: _flip,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_flip.value);
        final angle = t * math.pi;
        return Transform(
          key: const ValueKey('flashcard-flip'),
          alignment: Alignment.center,
          // A little perspective, or the card reads as a rectangle being
          // squashed rather than something turning over.
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0015)
            ..rotateY(angle),
          child: _showingBack
              // The back would be laid out mirrored by the rotation that
              // brought it round; flipping it again puts it the right way up.
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
    final text = back ? _backText : _frontText;
    final accent = back ? OnoteColors.ink300 : OnoteColors.brass400;
    return Container(
      decoration: BoxDecoration(
        color: dark ? OnoteColors.night100 : Colors.white,
        borderRadius: OnoteRadius.xlAll,
        border: Border.all(color: accent.withValues(alpha: .55), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .35 : .08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _toggleFlip,
          child: Stack(
            children: [
              // The accent stripe is the only thing that differs at a glance
              // between the two faces, which is what makes "which side am I
              // looking at" answerable without reading.
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(width: 5, color: accent),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    OnoteSpace.x7, OnoteSpace.x6, OnoteSpace.x6, OnoteSpace.x6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Text(back ? 'ANSWER' : 'QUESTION',
                            style: OnoteType.overline.copyWith(color: accent)),
                        const Spacer(),
                        _iconButton(Icons.edit_outlined, 'Edit this card',
                            _startEditing),
                      ],
                    ),
                    const SizedBox(height: OnoteSpace.x4),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Text(
                          text.trim().isEmpty
                              ? (back ? 'No answer yet' : 'No question yet')
                              : text,
                          style: OnoteType.ui.copyWith(
                            fontSize: 16,
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
                    const SizedBox(height: OnoteSpace.x4),
                    Row(
                      children: [
                        const Icon(Icons.autorenew,
                            size: 13, color: OnoteColors.graphite400),
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

  Widget _iconButton(IconData icon, String tooltip, VoidCallback onTap) =>
      IconButton(
        icon: Icon(icon, size: 15),
        color: OnoteColors.graphite400,
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
        onPressed: onTap,
      );

  /// Both halves at once. A card is a pair, and editing one side at a time
  /// behind a flip means never seeing whether the answer actually answers the
  /// question.
  Widget _editor(bool dark) => Container(
        decoration: BoxDecoration(
          color: dark ? OnoteColors.night100 : Colors.white,
          borderRadius: OnoteRadius.xlAll,
          border:
              Border.all(color: OnoteColors.brass400.withValues(alpha: .8), width: 1.5),
        ),
        padding: const EdgeInsets.all(OnoteSpace.x5),
        // Scrollable, because the editor is genuinely taller than the face it
        // replaces — two fields, two labels and a button where there was one
        // paragraph — and a card is a fixed-height block. Without this it
        // overflows its own box the moment you open it on a default-sized
        // card, which is a yellow-and-black bar across the thing you are
        // trying to type into.
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
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
                decoration: const InputDecoration(
                    isDense: true, hintText: 'What are you learning?'),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: OnoteSpace.x5),
              Text('ANSWER',
                  style:
                      OnoteType.overline.copyWith(color: OnoteColors.ink300)),
              const SizedBox(height: OnoteSpace.x2),
              TextField(
                controller: _back,
                maxLines: null,
                style: OnoteType.ui.copyWith(fontSize: 15),
                decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'The answer you want to recall'),
              ),
              const SizedBox(height: OnoteSpace.x5),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton(onPressed: _commit, child: const Text('Done')),
                ],
              ),
            ],
          ),
        ),
      );
}
