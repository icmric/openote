import 'package:flutter/material.dart';

import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import 'wrap_selection.dart';
import 'flashcard_view.dart';
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

class _FlashcardBlockViewState extends State<FlashcardBlockView> {
  bool _editing = false;
  TextEditingController? _front;
  TextEditingController? _back;

  String get _frontText => widget.block.content['front'] as String? ?? '';
  String get _backText => widget.block.content['back'] as String? ?? '';
  bool get _blank => _frontText.trim().isEmpty && _backText.trim().isEmpty;

  @override
  void initState() {
    super.initState();
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
    _front?.dispose();
    _back?.dispose();
    super.dispose();
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

  void _startEditing() => setState(_openEditor);

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
    // The SAME card the in-flow form draws (editor/flashcard_view.dart). One
    // widget, so a card is one object whether it is a block on the page or a
    // line inside a paragraph — two that merely looked alike would drift.
    return FlipCard(
      front: _frontText,
      back: _backText,
      trailing: _iconButton(Icons.edit_outlined, 'Edit this card', _startEditing),
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
                inputFormatters: const [
                  WrapSelectionFormatter(
                      pairs: WrapSelectionFormatter.bracketPairs,
                      autoCloseFences: false)
                ],
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
                inputFormatters: const [
                  WrapSelectionFormatter(
                      pairs: WrapSelectionFormatter.bracketPairs,
                      autoCloseFences: false)
                ],
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
