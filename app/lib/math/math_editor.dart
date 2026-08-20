/// The editing engine: where the caret is, and what each keystroke does to
/// the tree (plan: v0.18 §6).
///
/// Two rules run through everything here.
///
/// **Nothing the student typed is ever destroyed.** Backspace at the right
/// edge of a structure steps INSIDE it, at the end, and deletes from there —
/// the way every other equation editor works. It never removes a structure and
/// its contents in one keypress. That is the "the app ate my equation" moment
/// this editor exists to avoid.
///
/// This replaced an earlier rule where Backspace "unbuilt" a structure back
/// into the characters that produced it. That read well and was wrong three
/// ways, each measured: a script with an empty slot unbuilt to a bare `^`,
/// which is not drawable TeX at all, so the equation vanished into a grey box
/// of source; `x^(n+1)` unbuilt to characters TeX then re-read as a script
/// over the bracket alone; and one Backspace at the edge of a matrix flattened
/// a filled 2x2 grid to `1234`.
///
/// **Typing is never blocked.** Input that doesn't parse yet simply stays as
/// the characters that were typed until it does (Math Input Spec §3.3). There
/// is no error state while writing.
library;

import 'math_inventory.dart';
import 'linear_math.dart';
import 'math_parse.dart';
import 'math_tree.dart';
import 'math_view.dart';

class MathEditor {
  MathEditor._(this.root) {
    caretRow = root;
    caretIndex = root.length;
  }

  MathEditor.empty() : this._(MRow());

  /// Opens stored LaTeX for visual editing, or returns null when the source
  /// contains something the tree cannot hold — the caller then shows the
  /// LaTeX view instead of silently dropping it (v0.18 §6.6).
  static MathEditor? open(String latex) {
    if (latex.trim().isEmpty) return MathEditor.empty();
    final r = parseLatex(latex);
    if (!r.supported || r.root == null) return null;
    return MathEditor._(r.root!);
  }

  final MRow root;

  /// The row the caret sits in, and how many children precede it.
  late MRow caretRow;
  late int caretIndex;

  /// A `\text{…}` the student is currently filling. Words go into it instead
  /// of becoming maths atoms. Cleared by any caret movement, and by inserting
  /// anything from the palette — otherwise the next symbol pressed left the
  /// box armed and the typing after it landed inside the words instead of in
  /// the equation.
  MText? _openText;

  /// A space is a SPACE.
  ///
  /// It used to be swallowed whenever it did not trigger a build-up, so a
  /// student could never put one in — reported as "i can never have a space
  /// included". It is a real atom now, which also means two characters with a
  /// space between them are no longer adjacent, so `x < -3` cannot pair itself
  /// into `x ← 3` by accident.
  static const String spaceTex = r'\ ';

  bool get isEmpty => root.isEmpty;

  /// Replace this editor's contents with [other]'s tree, keeping THIS
  /// identity. The LaTeX view closing back into the visual editor needs it
  /// when the tree is owned by the host (the inline session): every reference
  /// to the editor must stay valid across the round-trip, so the tree moves
  /// rather than the editor being replaced.
  void adopt(MathEditor other) {
    root.children.clear();
    root.addAll(other.root.drain());
    caretRow = root;
    caretIndex = root.length;
    _openText = null;
    clearSelection();
  }

  /// Canonical LaTeX — what goes to storage, export and the PDF. Identical in
  /// shape to what the old string editor stored.
  String get latex => rowToTex(root, kStoreCtx);

  /// The same tree with the caret and the empty boxes drawn in.
  String renderTex(MathTexCtx style) => rowToTex(
        root,
        MathTexCtx(
          caretRow: caretRow,
          caretIndex: caretIndex,
          decorate: true,
          activeText: _openText,
          selectionRow: selectionRow,
          selectionStart: selectionStart,
          selectionEnd: selectionEnd,
          accent: style.accent,
          tint: style.tint,
          selectionTint: style.selectionTint,
          dim: style.dim,
          display: style.display,
        ),
      );

  /// The words box being filled, if any. Public so the field can tell whether
  /// a keystroke is going into words or into maths.
  MText? get openText => _openText;

  // ───────────────────────────────────────────────────────── selection
  //
  // **A selection is a contiguous run of siblings in ONE row.** Not a range
  // over the whole tree: a run that started in a numerator and ended outside
  // the fraction would have no meaning to copy, cut or replace, and every
  // operation on it would need a special case. Shift+arrow therefore steps
  // OVER a structure rather than into it — selecting a fraction selects the
  // whole fraction, which is what a student means by dragging across one.

  MRow? _anchorRow;
  int _anchorIndex = -1;

  bool get hasSelection =>
      _anchorRow != null &&
      identical(_anchorRow, caretRow) &&
      _anchorIndex != caretIndex;

  MRow? get selectionRow => hasSelection ? caretRow : null;
  int get selectionStart =>
      hasSelection ? (_anchorIndex < caretIndex ? _anchorIndex : caretIndex) : -1;
  int get selectionEnd =>
      hasSelection ? (_anchorIndex < caretIndex ? caretIndex : _anchorIndex) : -1;

  /// Forget the highlight. Every plain movement does this — a selection that
  /// survives an arrow key is one the student has stopped seeing.
  void clearSelection() {
    _anchorRow = null;
    _anchorIndex = -1;
  }

  /// Shift+←/→. Steps over structures rather than into them, and stops at the
  /// row's own edges, which is what keeps the run contiguous by construction.
  bool extendBy(int delta) {
    _openText = null;
    if (_anchorRow == null || !identical(_anchorRow, caretRow)) {
      _anchorRow = caretRow;
      _anchorIndex = caretIndex;
    }
    final next = caretIndex + delta;
    if (next < 0 || next > caretRow.length) return false;
    caretIndex = next;
    return true;
  }

  /// Ctrl+A — everything in the row the caret is in, which for an equation
  /// with no structures is the whole equation.
  bool selectAll() {
    if (caretRow.isEmpty) return false;
    _openText = null;
    _anchorRow = caretRow;
    _anchorIndex = 0;
    caretIndex = caretRow.length;
    return true;
  }

  /// The highlighted run as canonical LaTeX — what goes on the clipboard.
  String get selectionLatex {
    if (!hasSelection) return '';
    final slice = MRow();
    for (var i = selectionStart; i < selectionEnd; i++) {
      slice.children.add(caretRow.children[i]);
    }
    final out = rowToTex(slice, kStoreCtx);
    slice.children.clear();
    return out;
  }

  /// Remove the highlighted run. Returns false when there was none.
  bool deleteSelection() {
    if (!hasSelection) return false;
    final start = selectionStart, end = selectionEnd;
    for (var i = end; i > start; i--) {
      caretRow.removeAt(i - 1);
    }
    caretIndex = start;
    clearSelection();
    _openText = null;
    return true;
  }

  // ───────────────────────────────────────────────────── pointer placement
  //
  // The mouse speaks in ROOT-ROW BOUNDARIES (MathHitTable): a click lands the
  // caret at the nearest gap between top-level atoms, a drag runs between two
  // of them. Boundaries keep every gesture's result contiguous by
  // construction — the same rule Shift+arrow follows.

  /// Put the caret at [index] in the root row. A click.
  void placeAt(int index) {
    caretRow = root;
    caretIndex = index < 0
        ? 0
        : (index > root.length ? root.length : index);
    _openText = null;
    clearSelection();
  }

  /// Extend (or start) a highlight from wherever the caret is to [index] in
  /// the root row. A drag, or Shift+click.
  void selectTo(int index) {
    _openText = null;
    final to = index < 0 ? 0 : (index > root.length ? root.length : index);
    if (_anchorRow == null ||
        !identical(_anchorRow, root) ||
        !identical(caretRow, root)) {
      _anchorRow = root;
      _anchorIndex = identical(caretRow, root) ? caretIndex : to;
    }
    caretRow = root;
    caretIndex = to;
  }

  /// Highlight exactly the root-row child at [child]. A double-click — which
  /// for a fraction selects the fraction, the whole thing a student means.
  bool selectChild(int child) {
    if (child < 0 || child >= root.length) return false;
    _openText = null;
    _anchorRow = root;
    _anchorIndex = child;
    caretRow = root;
    caretIndex = child + 1;
    return true;
  }

  // ───────────────────────────────────────────────────────── movement

  void placeAtEnd() {
    caretRow = root;
    caretIndex = root.length;
    _openText = null;
    clearSelection();
  }

  void placeAtStart() {
    caretRow = root;
    caretIndex = 0;
    _openText = null;
    clearSelection();
  }

  /// Put the caret in the first box left to fill, or at the end if there
  /// isn't one. This is what makes inserting √ land you *under* the sign.
  void placeInFirstHole({MNode? within}) {
    final rows = within == null
        ? allRows(root).where((r) => r.owner != null)
        : _rowsOf(within);
    for (final r in rows) {
      if (r.isEmpty) {
        caretRow = r;
        caretIndex = 0;
        _openText = null;
        return;
      }
    }
    if (within != null) {
      final parent = within.parent;
      if (parent != null) {
        caretRow = parent;
        caretIndex = parent.children.indexOf(within) + 1;
        _openText = null;
        return;
      }
    }
    placeAtEnd();
  }

  Iterable<MRow> _rowsOf(MNode n) sync* {
    for (final s in n.slots) {
      yield s;
      for (final child in s.children) {
        yield* _rowsOf(child);
      }
    }
  }

  bool moveRight() {
    _openText = null;
    clearSelection();
    if (caretIndex < caretRow.length) {
      final n = caretRow.children[caretIndex];
      final slots = n.slots;
      if (slots.isNotEmpty) {
        caretRow = slots.first;
        caretIndex = 0;
        return true;
      }
      caretIndex++;
      return true;
    }
    return _exit(forward: true);
  }

  bool moveLeft() {
    _openText = null;
    clearSelection();
    if (caretIndex > 0) {
      final n = caretRow.children[caretIndex - 1];
      final slots = n.slots;
      if (slots.isNotEmpty) {
        caretRow = slots.last;
        caretIndex = caretRow.length;
        return true;
      }
      caretIndex--;
      return true;
    }
    return _exit(forward: false);
  }

  /// Off the end of a slot: into the next slot of the same structure, or out
  /// of the structure entirely. Returns false at the equation's own edge,
  /// which is the caller's cue to leave the equation.
  bool _exit({required bool forward}) {
    final owner = caretRow.owner;
    if (owner == null) return false;
    final slots = owner.slots;
    final k = slots.indexWhere((r) => identical(r, caretRow));
    if (forward && k >= 0 && k + 1 < slots.length) {
      caretRow = slots[k + 1];
      caretIndex = 0;
      return true;
    }
    if (!forward && k > 0) {
      caretRow = slots[k - 1];
      caretIndex = caretRow.length;
      return true;
    }
    final up = owner.parent;
    if (up == null) return false;
    final at = up.children.indexOf(owner);
    caretRow = up;
    caretIndex = forward ? at + 1 : at;
    return true;
  }

  /// Returns false at the top or bottom of the equation, which the caller
  /// reads as "leave" — the same contract [moveLeft] and [moveRight] use. It
  /// used to swallow the keystroke, so ↑ out of an equation in a sentence did
  /// nothing at all.
  bool moveUp() => _vertical(up: true);
  bool moveDown() => _vertical(up: false);

  bool _vertical({required bool up}) {
    _openText = null;
    clearSelection();
    var row = caretRow;
    // Climb until some ancestor offers a move in that direction — so ↑ from
    // deep inside a denominator still reaches the numerator.
    while (true) {
      final owner = row.owner;
      if (owner == null) return false;
      final target = _verticalTarget(owner, row, up);
      if (target != null) {
        caretRow = target;
        caretIndex = target.length;
        return true;
      }
      final parent = owner.parent;
      if (parent == null) return false;
      row = parent;
    }
  }

  MRow? _verticalTarget(MNode owner, MRow from, bool up) {
    if (owner is MFrac) {
      if (up && identical(from, owner.den)) return owner.num;
      if (!up && identical(from, owner.num)) return owner.den;
      return null;
    }
    if (owner is MScript) {
      // An n-ary has no navigable base, so up and down simply swap the two
      // limits — the owner's model: "if im on the bottom one id like to press
      // up and have it move me to the top one, and if i press it again
      // probably move me down to the bottom one".
      if (owner.fixedBase) {
        if (identical(from, owner.sub)) return owner.sup;
        if (identical(from, owner.sup)) return owner.sub;
        return null;
      }
      if (up) {
        if (identical(from, owner.base)) return owner.sup;
        if (owner.sub != null && identical(from, owner.sub)) return owner.base;
      } else {
        if (identical(from, owner.base)) return owner.sub;
        if (owner.sup != null && identical(from, owner.sup)) return owner.base;
      }
      return null;
    }
    if (owner is MSqrt) {
      if (up && identical(from, owner.radicand)) return owner.degree;
      if (!up && owner.degree != null && identical(from, owner.degree)) {
        return owner.radicand;
      }
      return null;
    }
    if (owner is MBinom) {
      if (up && identical(from, owner.bottom)) return owner.top;
      if (!up && identical(from, owner.top)) return owner.bottom;
      return null;
    }
    if (owner is MMatrix) {
      final at = owner.locate(from);
      if (at == null) return null;
      final (r, k) = at;
      final want = up ? r - 1 : r + 1;
      if (want >= 0 && want < owner.rowCount && k < owner.rows[want].length) {
        return owner.rows[want][k];
      }
    }
    return null;
  }

  /// Tab: the next box still waiting to be filled — and, when there are none
  /// left, OUT of the structure the caret is in.
  ///
  /// That second half is the difference between a working integral and the one
  /// the owner photographed. Insert ∫, fill the lower limit, Tab, fill the
  /// upper limit — and then there is nowhere to go. Tab used to do nothing, so
  /// the next thing typed went into the exponent and the integrand ended up
  /// stacked above the sign. A structure you cannot leave by the key that got
  /// you into it is a trap.
  bool tab({bool backwards = false}) {
    _openText = null;
    final rows = allRows(root).where((r) => r.owner != null).toList();
    final holes = [
      for (var i = 0; i < rows.length; i++)
        if (rows[i].isEmpty) i
    ];
    if (holes.isEmpty) return backwards ? false : _tabOut();
    final here = rows.indexWhere((r) => identical(r, caretRow));
    int target;
    if (backwards) {
      target = holes.lastWhere((i) => i < here, orElse: () => holes.last);
    } else {
      target = holes.firstWhere((i) => i > here, orElse: () => holes.first);
    }
    caretRow = rows[target];
    caretIndex = 0;
    return true;
  }

  /// Leave the structure the caret is in, landing just after it — where the
  /// integrand of a filled-in integral belongs. Climbs out of nesting one
  /// level at a time, and reports false only when the caret is already in the
  /// equation's own top row with nothing left to leave.
  bool _tabOut() {
    final owner = caretRow.owner;
    if (owner == null) return false;
    final parent = owner.parent;
    if (parent == null) return false;
    caretRow = parent;
    caretIndex = parent.children.indexOf(owner) + 1;
    return true;
  }

  // ───────────────────────────────────────────────────────── insertion

  /// Empty the equation — what Ctrl+X leaves behind once it has taken a copy.
  void clear() {
    root.drain();
    caretRow = root;
    caretIndex = 0;
    _openText = null;
  }

  /// Drop pasted source in at the caret.
  ///
  /// LaTeX first, then the linear grammar (`1/2`, `\sum_(n=1)^oo`) so maths
  /// copied out of a message still arrives as maths, and finally the plain
  /// characters — pasting must never be refused outright, because the student
  /// can always see what they pasted and fix it.
  InsertOutcome insertSource(String source) {
    bool place(MathParseResult r) {
      if (!r.supported || r.root == null) return false;
      // Pasting REPLACES the highlight, exactly as insertChar and insertItem
      // do — it used to append after it instead, leaving the highlight
      // spanning old and pasted content so the next keystroke's
      // deleteSelection wiped the whole equation.
      deleteSelection();
      final nodes = r.root!.drain();
      caretRow.insertAll(caretIndex, nodes);
      caretIndex += nodes.length;
      _openText = null;
      return true;
    }

    // Delimiters come off first, whichever flavour: `$…$`, `$$…$$`, and the
    // `\(…\)` / `\[…\]` that ChatGPT and every LaTeX editor hand you. All
    // four were understood by the renderer and by neither paste path, so the
    // student saw backslashes at both ends of their own equation.
    source = MathClipboard.unwrap(source);

    // The LINEAR reading goes first, but only when it actually says something
    // different. `1/2` is perfectly valid LaTeX — three ordinary atoms — so a
    // LaTeX-first order pasted it as the characters `1/2` rather than as the
    // fraction the sender meant. Where the linear grammar leaves the text
    // alone, nothing is preferred and the LaTeX path takes it.
    final linear = linearToLatex(source);
    if (linear != source && place(parseLatex(linear))) {
      return InsertOutcome.placed;
    }
    if (place(parseLatex(source))) return InsertOutcome.placed;
    // LaTeX the tree cannot hold is REFUSED, untouched (v0.20 D.2). The old
    // fallback escaped it character by character, and the escaping layer
    // turned every backslash into `\backslash` — TYPESET backslashes that
    // re-parse cleanly, so the student's own clipboard content was silently
    // rewritten into something no undo could recover the meaning of.
    // Measured: 22 of 79 realistic constructs landed there.
    if (source.contains('\\')) return InsertOutcome.refused;
    // Plain text goes in as the characters it is — visible, fixable.
    deleteSelection();
    for (final ch in source.split('')) {
      insertChar(ch);
    }
    return InsertOutcome.chars;
  }

  /// A palette press. Fresh nodes every time — see [MathItem.build].
  void insertItem(MathItem item) {
    // Pressing a symbol ENDS the words box. Leaving it armed meant the letters
    // typed after a π landed inside the preceding \text{…} instead of in the
    // equation, which looks like the keyboard has stopped working.
    _openText = null;
    deleteSelection();
    final nodes = item.build();
    caretRow.insertAll(caretIndex, nodes);
    caretIndex += nodes.length;
    final structure = nodes.firstWhere(
      (n) => n.slots.isNotEmpty,
      orElse: () => nodes.last,
    );
    if (structure.slots.isNotEmpty) {
      placeInFirstHole(within: structure);
    } else if (nodes.length == 1 && nodes.first is MText) {
      _openText = nodes.first as MText;
    }
  }

  /// One typed character. Returns false only when nothing at all happened.
  bool insertChar(String ch) {
    if (ch.isEmpty) return false;
    // Typing over a highlight replaces it, the way it does in every editor.
    deleteSelection();

    if (_openText != null && ch != '\n') {
      // Inside `\text{…}`: letters, spaces and punctuation are words, not
      // maths. Any arrow key ends this — see [_openText].
      _openText!.text += ch;
      return true;
    }

    switch (ch) {
      case ' ':
        // A space either FINISHES a `\command` or is a space. Not both: doing
        // both put the space inside the box the command had just opened, so
        // `\sqrt` came out as a root with a space already under it.
        if (_buildControlWord()) return true;
        caretRow.insert(caretIndex, MSym(spaceTex));
        caretIndex++;
        return true;
      case '/':
        _buildFraction();
        return true;
      case '^':
        _buildScript(sup: true);
        return true;
      case '_':
        _buildScript(sup: false);
        return true;
      case '(':
        _buildControlWord();
        _buildFunctionName();
        final d = MDelim(left: '(', right: ')');
        caretRow.insert(caretIndex, d);
        caretIndex++;
        caretRow = d.body;
        caretIndex = 0;
        return true;
      case ')':
        // Closing a grower from inside finishes it, which is what typing the
        // bracket means; anywhere else it's an ordinary character.
        if (caretRow.owner is MDelim && caretIndex == caretRow.length) {
          return _exit(forward: true);
        }
    }

    // `<=`, `->`, `!=` … complete the moment their last character lands. A
    // space between them is a real atom now, so it separates them by itself.
    if (_buildOperatorRun(ch)) return true;

    // An operator ends a control word: `pi+1` should have π before the +.
    final cls = classOf(ch);
    if (cls == MClass.op || cls == MClass.rel || cls == MClass.close) {
      _buildControlWord();
    }

    caretRow.insert(caretIndex, MSym(ch, cls: cls));
    caretIndex++;
    return true;
  }

  /// The letters immediately before the caret, and the index of the BACKSLASH
  /// that starts them — or `-1` when there isn't one.
  ///
  /// **Only a `\command` converts.** The editor used to translate any word it
  /// recognised the moment a space or an operator arrived, which is the "super
  /// greedy always convert everything we see" the owner asked to be rid of —
  /// and it was worse than untidy. `in`, `cap`, `div`, `to`, `dot`, `hat`,
  /// `text`, `deg` and every Greek letter are ordinary English words and
  /// ordinary variable names, so writing any of them turned into a symbol
  /// nobody asked for. Requiring the backslash is the LaTeX convention, it is
  /// unambiguous, and a student who wants the letters simply types the letters.
  (int, String) _commandBefore() {
    var k = caretIndex;
    final buf = StringBuffer();
    while (k > 0) {
      final n = caretRow.children[k - 1];
      if (n is! MSym || n.cls != MClass.letter || n.tex.length != 1) break;
      buf.write(n.tex);
      k--;
    }
    if (buf.isEmpty || k == 0) return (-1, '');
    final lead = caretRow.children[k - 1];
    // `'\\'` and not `r'\'`: a Dart raw string cannot end in a backslash, and
    // the form that does compile does not hold the character we are after.
    if (lead is! MSym || lead.tex != '\\') return (-1, '');
    final word = String.fromCharCodes(buf.toString().codeUnits.reversed);
    return (k - 1, word);
  }

  bool _buildControlWord() {
    final (start, word) = _commandBefore();
    if (start < 0 || word.isEmpty) return false;
    // Function names live under `fn-<name>`; everything else is a control word.
    final item = mathControlWords[word] ?? mathItemsById['fn-$word'];
    if (item == null) return false;
    for (var i = caretIndex; i > start; i--) {
      caretRow.removeAt(i - 1);
    }
    caretIndex = start;
    _insertRemembering(item, '\\$word');
    return true;
  }

  /// Insert an item, tagging a plain symbol with the word it replaced. That
  /// tag is what lets Backspace hand `alpha` back instead of eating both the
  /// symbol and the six letters that produced it.
  void _insertRemembering(MathItem item, String typed) {
    final nodes = item.build();
    if (nodes.length == 1 && nodes.first is MSym) {
      final s = nodes.first as MSym;
      caretRow.insert(caretIndex, MSym(s.tex, cls: s.cls, typed: typed));
      caretIndex++;
      return;
    }
    insertItem(item);
  }

  /// `sin(` goes upright, the way every textbook sets it — WITHOUT needing
  /// the backslash. The `(` is what makes the intent unambiguous, so this
  /// does not violate the no-greedy-conversion rule ("alpha doesnt convert,
  /// \alpha does"): a bare word converts only when it is a known FUNCTION
  /// name and the student has just opened its argument. Backspace hands the
  /// letters back, as for every remembered conversion.
  ///
  /// (It used to alias [_buildControlWord], which requires the backslash —
  /// so the `(` handler called the same function twice and plain `sin(`
  /// never went upright at all.)
  bool _buildFunctionName() {
    var k = caretIndex;
    final buf = StringBuffer();
    while (k > 0) {
      final n = caretRow.children[k - 1];
      if (n is! MSym || n.cls != MClass.letter || n.tex.length != 1) break;
      buf.write(n.tex);
      k--;
    }
    if (buf.isEmpty) return false;
    final word = String.fromCharCodes(buf.toString().codeUnits.reversed);
    final item = mathItemsById['fn-${word}'];
    if (item == null) return false;
    for (var i = caretIndex; i > k; i--) {
      caretRow.removeAt(i - 1);
    }
    caretIndex = k;
    _insertRemembering(item, word);
    return true;
  }

  bool _buildOperatorRun(String ch) {
    for (final (run, item) in mathOperatorRuns) {
      if (!run.endsWith(ch)) continue;
      final head = run.substring(0, run.length - 1);
      if (head.isEmpty) continue;
      if (caretIndex < head.length) continue;
      var matches = true;
      for (var i = 0; i < head.length; i++) {
        final n = caretRow.children[caretIndex - head.length + i];
        if (n is! MSym || n.tex != head[i]) {
          matches = false;
          break;
        }
      }
      if (!matches) continue;
      for (var i = 0; i < head.length; i++) {
        caretRow.removeAt(caretIndex - 1);
        caretIndex--;
      }
      insertItem(item);
      return true;
    }
    return false;
  }

  /// Where the operand before the caret starts: a run of digits, one letter,
  /// one complete structure, or a bracketed group. `12/5` takes the twelve.
  int _operandStart() {
    final end = caretIndex;
    if (end <= 0) return end;
    final n = caretRow.children[end - 1];
    if (n is! MSym) return end - 1; // a whole structure
    switch (n.cls) {
      case MClass.close:
        var depth = 0;
        for (var k = end - 1; k >= 0; k--) {
          final m = caretRow.children[k];
          if (m is MSym && m.cls == MClass.close) depth++;
          if (m is MSym && m.cls == MClass.open) {
            depth--;
            if (depth == 0) return k;
          }
        }
        return end - 1;
      case MClass.digit:
        var k = end - 1;
        while (k > 0) {
          final m = caretRow.children[k - 1];
          if (m is MSym && (m.cls == MClass.digit || m.tex == '.')) {
            k--;
          } else {
            break;
          }
        }
        return k;
      case MClass.letter || MClass.func:
        return end - 1;
      case MClass.op:
        // Most operators are not operands — `1+^2` should leave the box empty.
        // A BIG operator is the exception: `\iint` then `^` has to put the
        // limit on the sign, and treating it like a plus left the base empty
        // so the limits sat beside an invisible atom.
        return kBigOperators.contains(n.tex) ? end - 1 : end;
      default:
        return end;
    }
  }

  /// Pull the operand out of the row, dropping the brackets a group carried:
  /// `(n+1)/2` builds the same fraction `n+1` would.
  List<MNode> _takeOperand() {
    final start = _operandStart();
    final taken = <MNode>[];
    for (var i = start; i < caretIndex; i++) {
      taken.add(caretRow.children[start]);
      caretRow.removeAt(start);
    }
    caretIndex = start;
    if (taken.length >= 2) {
      final first = taken.first;
      final last = taken.last;
      if (first is MSym &&
          first.cls == MClass.open &&
          last is MSym &&
          last.cls == MClass.close) {
        taken.removeLast();
        taken.removeAt(0);
      }
    }
    return taken;
  }

  void _buildFraction() {
    var num = _takeOperand();
    // `(a+b)/c` builds the fraction WITHOUT the brackets — the bar already
    // does the grouping, and carrying them through is the thing that makes a
    // typed fraction look wrong next to a palette one. OneNote drops them
    // here too. Scripts deliberately don't: `(x+1)^2` needs its brackets.
    if (num.length == 1 && num.first is MDelim) {
      final d = num.first as MDelim;
      if (d.left == '(' && d.right == ')') num = d.body.drain();
    }
    final f = MFrac(num: MRow(num));
    caretRow.insert(caretIndex, f);
    caretIndex++;
    caretRow = f.den;
    caretIndex = 0;
  }

  void _buildScript({required bool sup}) {
    // `x_i^2` — the caret is sitting at the end of the INDEX when `^` arrives.
    // The power belongs to the x, not to the i. Without this, a student typing
    // the most ordinary thing in algebra gets a power nested inside their own
    // subscript.
    //
    // The same rule carries the n-ary case, which is the one that actually
    // bit: type `sum`, fill the lower limit, press `^`. The upper limit is
    // right there and empty, and pressing the key for it should GO there —
    // before this, it built a second script inside the lower limit and left
    // the upper one visibly empty.
    final owner = caretRow.owner;
    if (owner is MScript) {
      final inSub = identical(caretRow, owner.sub);
      final inSup = identical(caretRow, owner.sup);
      final wanted = sup ? owner.sup : owner.sub;
      if ((sup && inSub) || (!sup && inSup)) {
        if (wanted == null || wanted.isEmpty) {
          caretRow = sup ? owner.ensureSup() : owner.ensureSub();
          caretIndex = 0;
          return;
        }
      }
    }

    // `x^2^3` shouldn't stack two scripts on one base, and `x_i^2` must reuse
    // the script already there rather than nesting one inside another.
    if (caretIndex > 0) {
      final prev = caretRow.children[caretIndex - 1];
      if (prev is MScript && (sup ? prev.sup == null : prev.sub == null)) {
        caretRow = sup ? prev.ensureSup() : prev.ensureSub();
        caretIndex = 0;
        return;
      }
    }
    _buildControlWord();
    final base = _takeOperand();
    final s = MScript(base: MRow(base));
    caretRow.insert(caretIndex, s);
    caretIndex++;
    caretRow = sup ? s.ensureSup() : s.ensureSub();
    caretIndex = 0;
  }

  // ───────────────────────────────────────────────────────── deletion

  /// Backspace. Never removes a structure together with its contents: at a
  /// structure's right edge it steps INSIDE, at the end, so the next press
  /// deletes the last thing in it. A structure already emptied is removed
  /// outright; one deleted into from the FRONT unwraps, keeping its contents.
  /// Returns false only at the very start of the equation, which the caller
  /// reads as "leave".
  bool backspace() {
    if (deleteSelection()) return true;
    if (_openText != null && _openText!.text.isNotEmpty) {
      final t = _openText!;
      t.text = t.text.substring(0, t.text.length - 1);
      if (t.text.isEmpty) {
        final at = caretRow.children.indexOf(t);
        if (at >= 0) {
          caretRow.removeAt(at);
          caretIndex = at;
        }
        _openText = null;
      }
      return true;
    }

    if (caretIndex > 0) {
      final n = caretRow.children[caretIndex - 1];

      if (n is MText) {
        if (n.text.isEmpty) {
          caretRow.removeAt(caretIndex - 1);
          caretIndex--;
        } else {
          n.text = n.text.substring(0, n.text.length - 1);
          _openText = n;
        }
        return true;
      }

      if (n is MSym) {
        caretRow.removeAt(caretIndex - 1);
        caretIndex--;
        // Autocorrect gave the student a symbol for a word they typed; taking
        // it away should give the word back, not swallow both.
        final typed = n.typed;
        if (typed != null && typed.isNotEmpty) {
          final chars = [
            for (final c in typed.split('')) MSym(c, cls: classOf(c))
          ];
          caretRow.insertAll(caretIndex, chars);
          caretIndex += chars.length;
        }
        return true;
      }

      // A structure. Step INSIDE it, at the end, rather than taking it apart —
      // unless it is already empty, in which case there is nothing to lose.
      if (n.isBlank) {
        caretRow.removeAt(caretIndex - 1);
        caretIndex--;
        return true;
      }
      final last = n.slots.last;
      caretRow = last;
      caretIndex = last.length;
      _openText = null;
      return true;
    }

    // At the start of a slot.
    final owner = caretRow.owner;
    if (owner == null) return false;
    final slots = owner.slots;
    final k = slots.indexWhere((r) => identical(r, caretRow));
    if (k > 0) {
      caretRow = slots[k - 1];
      caretIndex = caretRow.length;
      return true;
    }
    final parent = owner.parent;
    if (parent == null) return false;
    final at = parent.children.indexOf(owner);
    if (owner.isBlank) {
      parent.removeAt(at);
      caretRow = parent;
      caretIndex = at;
      _openText = null;
    } else {
      _unwrap(owner, at, parent);
    }
    return true;
  }

  /// Take a structure's wrapper away and leave its contents in its place, in
  /// order. Used when the student deletes off the FRONT of a structure that
  /// still holds work: the frame goes, every character they typed stays.
  void _unwrap(MNode n, int at, MRow row) {
    if (at < 0) return;
    // contentSlots, not slots: an n-ary's operator sign lives in a row the
    // caret cannot reach, and unwrapping must not throw it away.
    final contents = [for (final s in n.contentSlots) ...s.drain()];
    row.removeAt(at);
    row.insertAll(at, contents);
    caretRow = row;
    caretIndex = at;
    _openText = null;
  }

  /// Delete forward. Symmetric with [backspace] but takes the node ahead —
  /// and leaves the caret where it was, in front of what is now there.
  bool delete() {
    if (deleteSelection()) return true;
    if (caretIndex >= caretRow.length) return false;
    final n = caretRow.children[caretIndex];
    if (n is MText) {
      // ONE character, matching Backspace. Delete used to take the whole words
      // box — and everything written in it — on a single keypress.
      if (n.text.length > 1) {
        n.text = n.text.substring(1);
        return true;
      }
      caretRow.removeAt(caretIndex);
      return true;
    }
    if (n is MSym || n.isBlank) {
      caretRow.removeAt(caretIndex);
      return true;
    }
    // Mirror of Backspace: step inside, at the start.
    final first = n.slots.first;
    caretRow = first;
    caretIndex = 0;
    _openText = null;
    return true;
  }

  /// Add a row to the piecewise/matrix the caret is in — the Enter key in a
  /// display equation. False when the caret isn't inside one.
  bool addMatrixRow() {
    var row = caretRow;
    while (true) {
      final owner = row.owner;
      if (owner == null) return false;
      if (owner is MMatrix) {
        owner.addRow();
        final last = owner.rows.last;
        caretRow = last.first;
        caretIndex = 0;
        _openText = null;
        return true;
      }
      final parent = owner.parent;
      if (parent == null) return false;
      row = parent;
    }
  }
}

/// What [MathEditor.insertSource] did with the clipboard. `refused` means the
/// text was LaTeX the tree cannot hold and NOTHING changed — the caller tells
/// the student it is still on their clipboard, because a paste that silently
/// rewrites what was pasted is worse than one that declines.
enum InsertOutcome { placed, chars, refused }
