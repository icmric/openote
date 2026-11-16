/// **"I changed that word", with a way back.**
///
/// When the app corrects a word by itself (a typo, a missing apostrophe, a
/// capital), the word is marked with a quiet dotted line and a small marker
/// appears under it showing what was typed, with a back arrow: one click puts
/// the original back, and the app remembers not to change that word again. The
/// marker goes once a few more words have been written, or the caret leaves, so
/// it never piles up. Icon first and the person's own word after it, so it needs
/// no translation. Backspace and Ctrl+Z straight after a fix still do the same
/// (see `auto_writing.dart`); this is for the person who did not see it happen.
library;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/tokens.dart';

/// How many further words are written before the marker goes. Long enough to
/// notice and decide, short enough that it is never still there when the
/// person has moved on to the next sentence.
const int kFixNoticeWords = 3;

/// One automatic fix that can still be taken back.
class FixNotice {
  FixNotice({
    required this.start,
    required this.typed,
    required this.put,
    required this.keepKey,
    required String textAtFix,
  })  : end = start + put.length,
        head = textAtFix.substring(0, start + put.length),
        _wordsAtFix =
            wordsAfter(textAtFix.substring(start + put.length));

  /// Where the fixed word starts, and ends, in the text now.
  final int start;
  final int end;

  /// What the person typed, and what it became.
  final String typed;
  final String put;

  /// What to remember so the word is not fixed again once it is put back.
  final String keepKey;

  /// The text up to the end of the fixed word, as it was when it was fixed. If
  /// anything in it changes, the range above no longer means the same letters
  /// and the marker has to go.
  final String head;
  final int _wordsAtFix;

  static final RegExp _word =
      RegExp(r"[\p{L}\p{N}][\p{L}\p{N}'’]*[\s.,;:!?]", unicode: true);

  /// Finished words in [tail]: a word and the character that ended it.
  static int wordsAfter(String tail) => _word.allMatches(tail).length;

  /// Whether the marker should still be showing for [text] and [sel].
  bool stillWanted(String text, TextSelection sel) {
    if (text.length < end || !text.startsWith(head)) return false;
    if (!sel.isValid || !sel.isCollapsed || sel.baseOffset < start) return false;
    return wordsAfter(text.substring(end)) - _wordsAtFix < kFixNoticeWords;
  }
}

/// The marker: a back arrow and the word as it was typed.
class FixNoticeChip extends StatelessWidget {
  const FixNoticeChip({super.key, required this.typed, required this.onTap});
  final String typed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final scheme = Theme.of(context).colorScheme;
    final l = L.of(context);
    // Taps here are inside the text box as far as focus goes: the caret must
    // stay where it is.
    return TextFieldTapRegion(
      child: Semantics(
        label: l.fixNoticeRevert(typed),
        button: true,
        excludeSemantics: true,
        child: Material(
          color: s.chrome,
          elevation: 1.5,
          shadowColor: const Color(0x33000000),
          shape: StadiumBorder(side: BorderSide(color: s.border)),
          child: InkWell(
            key: const ValueKey('fix-notice'),
            canRequestFocus: false,
            mouseCursor: WidgetStateMouseCursor.clickable,
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.undo, size: 13, color: scheme.primary),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(typed,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11.5,
                            color: s.textSecondary,
                            decoration: TextDecoration.none)),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
