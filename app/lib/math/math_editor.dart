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

import 'evaluate.dart';
import 'math_inventory.dart';
import 'math_linear_projection.dart';
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
    // While the working and its answers still agree, ask each answer how many
    // figures it is showing. This is the one moment that question has an
    // exact answer; a keystroke later the working has moved on.
    return MathEditor._(r.root!)..recoverAnswerPrecision();
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
  void insertItem(MathItem item) => insertNodes(item.build());

  /// Drop built nodes at the caret and land it in the first empty box.
  ///
  /// The body [insertItem] used to be. Split out because the root family
  /// (`\4rt`, `\12rt`) is a PATTERN rather than a palette entry — there is no
  /// end to the numbers — and it must still arrive exactly the way a palette
  /// press does, boxes and all.
  void insertNodes(List<MNode> nodes) {
    // Pressing a symbol ENDS the words box. Leaving it armed meant the letters
    // typed after a π landed inside the preceding \text{…} instead of in the
    // equation, which looks like the keyboard has stopped working.
    _openText = null;
    deleteSelection();
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
        // `2+3=` and a space writes `5` — the calculator where the student is
        // already looking. It used to live as a readout at the top of the
        // window, which the owner found unintuitive: an answer belongs in the
        // equation, at the moment you ask for it.
        if (answerAfterEquals()) return true;
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
        // **A template brings its own brackets.** `gcd(` used to insert the
        // template AND then a second, empty pair after it; the function that
        // built the template says so, and the `(` that asked for it has
        // already been served.
        if (_buildFunctionName()) return true;
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
      // Digits as well as letters, for `\2rt`. Safe because the leading `\`
      // is still required below: a digit used to abort the walk, so nothing
      // that converted before stops converting, and a bare `2rt` is still
      // just three characters.
      if (n is! MSym ||
          (n.cls != MClass.letter && n.cls != MClass.digit) ||
          n.tex.length != 1) {
        break;
      }
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
    // **The root family.** `\4rt` is a fourth root with the four already in
    // its index, `\12rt` a twelfth. Written as a pattern rather than twenty
    // palette entries because there is no end to the numbers, and a student
    // who has met `\3rt` should not have to wonder whether `\7rt` was one of
    // the ones we thought of.
    final root = RegExp(r'^([0-9]+)rt$').firstMatch(word);
    if (root != null) {
      final digits = root.group(1)!;
      for (var i = caretIndex; i > start; i--) {
        caretRow.removeAt(i - 1);
      }
      caretIndex = start;
      insertNodes([
        MSqrt(
          degree: MRow([
            for (final d in digits.split('')) MSym(d, cls: MClass.digit),
          ]),
        ),
      ]);
      return true;
    }
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

  /// Typing `=` then a space: work out what is in front of it and write the
  /// answer down (owner, v0.21).
  ///
  /// Deliberately narrow, because a wrong number is far worse than no number:
  ///
  ///  * only the run since the LAST `=` is evaluated, so `x=2+3=` answers 5
  ///    rather than choking on the unknown x;
  ///  * the run is read through [rowToLinear], the same projection the
  ///    calculator uses, which REFUSES anything without a numeric meaning —
  ///    a matrix, a subscripted name, a words box;
  ///  * an expression with a letter in it does not evaluate, so `y=mx+c=`
  ///    simply leaves you a space, exactly as before.
  ///
  /// Returns false whenever any of that fails, and the space is then just a
  /// space — the student never has to know the feature was considered.
  bool answerAfterEquals() {
    // **Only at the top level of the equation.** An answer is the end of a
    // line of working, and inside a structure it is nonsense: typing `1/2=`
    // and a space without stepping out of the denominator first produced
    // `rac{1}{2=2}` — the answer buried in the bottom of the fraction. A
    // student who does that gets a plain space, which is the same quiet
    // refusal every other unanswerable case gets.
    if (!identical(caretRow, root)) return false;
    if (caretIndex < 2) return false;
    final eq = caretRow.children[caretIndex - 1];
    if (eq is! MSym || eq.tex != '=') return false;

    // Back to the previous `=`, or the start of the row.
    var from = 0;
    for (var i = caretIndex - 2; i >= 0; i--) {
      final n = caretRow.children[i];
      if (n is MSym && n.tex == '=') {
        from = i + 1;
        break;
      }
    }
    if (caretIndex - 1 - from <= 0) return false;

    // Borrowed by LIST manipulation, never re-parented: the probe row must
    // not touch the tree it is reading (the same trick [selectionLatex] uses).
    final slice = MRow();
    for (var i = from; i < caretIndex - 1; i++) {
      slice.children.add(caretRow.children[i]);
    }
    // **A lone LETTER is a name, not a sum.** `e` is Euler's number to the
    // evaluator and names are lowercased, so a physics student typing `E`,
    // `=`, space — the ordinary way to start `E = mc^2` — had
    // 2.71828182846 written into their page. Same for `e`, and `E` is what
    // both the expected-value and capital-epsilon palette buttons insert.
    //
    // A lone letter is what a student is DEFINING. `\pi` is not a letter
    // they typed but a symbol they chose, and nobody defines pi, so it
    // still answers — as does a lone root or fraction, which is one NODE
    // but not one letter.
    final lone = slice.children.length == 1 ? slice.children.first : null;
    final onlySymbol = lone is MSym &&
        lone.tex.length == 1 &&
        RegExp('[A-Za-z]').hasMatch(lone.tex);
    final linear = rowToLinear(slice).trim();
    slice.children.clear();
    if (linear.isEmpty || onlySymbol) return false;

    final r = evaluateLinear(linear);
    if (!r.isOk) return false;
    final answer = r.display;
    // `undefined`, `∞` and the like are honest readings but not maths a
    // student can go on typing with.
    if (answer.isEmpty || !_isPlainNumber(answer)) {
      return false;
    }
    // **A fraction in, a fraction out.** The owner: *"if the equation is a
    // fraction it should ideally give a fractional answer (if its a clean
    // fraction, otherwise decimal)"*. So the question asked of the working is
    // not "is the answer tidy" but "was the student thinking in fractions" —
    // and only then whether it lands on a tidy one.
    final wantsFraction = _looksLikeFractionWork(from, caretIndex - 1);
    caretRow.insert(
        caretIndex,
        MAnswer(content: _writeAnswer(r, fraction: wantsFraction)));
    caretIndex++;
    _openText = null;
    clearSelection();
    return true;
  }

  /// **The one place an answer is written down.**
  ///
  /// Creation, the re-work after an edit, the fraction toggle and every choice
  /// in the answer's own menu all come through here, because they had each
  /// grown their own copy of "turn this value into nodes" and the copies had
  /// already started to differ.
  ///
  /// [fraction] asks for the fraction form and is ignored when the value has
  /// no tidy one. [sigFigs] is null for "as many figures as the number needs".
  /// The unit rides on [r] — see [_unitNodes].
  static MRow _writeAnswer(EvalResult r,
      {required bool fraction, int? sigFigs}) {
    if (fraction) {
      final rat = _tidyFraction(r);
      if (rat != null) return _fractionRow(rat);
    }
    final row =
        _digits(sigFigs == null ? r.display : r.displayAt(sigFigs));
    for (final n in _unitNodes(r.unit)) {
      row.add(n);
    }
    return row;
  }

  /// The unit an answer wears, when it can only be one thing.
  ///
  /// **A degree sign in degrees, and nothing at all in radians.** That is not
  /// an omission: a bare number IS radians, in every textbook and on every
  /// calculator, and the presence or absence of the ring is exactly what says
  /// which mode worked the answer out. It also composes — `sin` of an answer
  /// written `30` with a ring on it is still a half, whichever mode the
  /// student is in by then, because the ring travels with the number.
  ///
  /// The same symbol the palette's own degrees button writes, so there is one
  /// degree sign in the app rather than two that must be kept in step.
  static List<MNode> _unitNodes(EvalUnit unit) => switch (unit) {
        EvalUnit.degrees =>
          mathItemsById['degree']?.build() ?? const <MNode>[],
        EvalUnit.radians || EvalUnit.none => const <MNode>[],
      };

  /// How many significant figures a written-out number is carrying.
  ///
  /// Leading zeros never count; trailing zeros after a decimal point always
  /// do, which is the whole point — `0.500` is three figures and `0.5` is one.
  /// For a whole number the trailing zeros are dropped, because `1230` at
  /// three figures and 1230 exactly are written identically and the modest
  /// reading is the safe one.
  static int sigFigsOf(String text) {
    var t = text.replaceAll('-', '').replaceAll('−', '');
    final hasPoint = t.contains('.');
    t = t.replaceAll('.', '');
    var a = 0;
    while (a < t.length - 1 && t[a] == '0') {
      a++;
    }
    t = t.substring(a);
    if (!hasPoint) {
      var b = t.length;
      while (b > 1 && t[b - 1] == '0') {
        b--;
      }
      t = t.substring(0, b);
    }
    return t.isEmpty ? 1 : t.length;
  }

  /// The digits an answer is showing, or null when it is not a plain number
  /// (a fraction, or a value written with a power of ten).
  static String? _writtenDigits(MRow content) {
    final b = StringBuffer();
    for (final n in content.children) {
      if (n is MSym && (RegExp(r'^[0-9.]$').hasMatch(n.tex) || n.tex == '-')) {
        b.write(n.tex);
        continue;
      }
      if (_isUnitNode(n)) continue;
      return null;
    }
    final t = b.toString();
    return t.isEmpty ? null : t;
  }

  /// A unit worn by an answer rather than part of its number. Both the shape
  /// the palette builds and the one the parser rebuilds it as.
  static bool _isUnitNode(MNode n) {
    if (n is MSym) return n.tex == r'{}^{\circ}' || n.tex == r'\circ';
    if (n is MScript) {
      final sup = n.sup;
      return n.base.children.isEmpty &&
          sup != null &&
          sup.children.length == 1 &&
          sup.children.first is MSym &&
          (sup.children.first as MSym).tex == r'\circ';
    }
    return false;
  }

  /// The precision an existing answer is written at.
  ///
  /// The node remembers within a session. For an answer that has no memory —
  /// one just read off the page — [recoverAnswerPrecision] has already asked
  /// the working, which is exact; this is only the last resort for an orphan
  /// answer with no working to ask.
  static int? _precisionOf(MAnswer a) {
    if (a.sigFigs != null) return a.sigFigs;
    final text = _writtenDigits(a.content);
    if (text == null) return null;
    final self = double.tryParse(text);
    if (self == null) return null;
    if (EvalResult.ok(self).display == text) return null; // nothing special
    return sigFigsOf(text);
  }

  /// **Ask the working how many figures each answer is showing.**
  ///
  /// Run once, when an equation is read off the page, while the working and
  /// the answer still agree. `0.707` is three figures of cos 45 and it is
  /// also just a number — the digits cannot tell you which, and guessing
  /// "just a number" threw the student's choice away on their next keystroke.
  /// The working can tell you exactly: round it to one figure, then two, and
  /// see which rounding the page is showing.
  ///
  /// Silent when the working no longer evaluates, when the answer is a
  /// fraction, or when the digits are simply what the number needs — all of
  /// which mean there is no choice to remember.
  void recoverAnswerPrecision() {
    for (var i = 0; i < root.length; i++) {
      final a = root.children[i];
      if (a is! MAnswer) continue;
      final text = _writtenDigits(a.content);
      if (text == null) continue;
      if (i == 0 || !_isEquals(root.children[i - 1])) continue;
      final w = _workingBefore(i - 1);
      if (w == null) continue;
      final r = evaluateLinear(w);
      if (!r.isOk) continue;
      if (r.display == text) continue; // the ordinary rendering
      for (var f = 1; f <= 15; f++) {
        if (r.displayAt(f) == text) {
          a.sigFigs = f;
          break;
        }
      }
    }
  }

  /// Was the working written with fractions in it? Looks at what the student
  /// actually wrote, not at the answer — `1/4 + 1/4` deserves `1/2` even
  /// though `0.5` is perfectly tidy.
  bool _looksLikeFractionWork(int from, int to) {
    for (var i = from; i < to; i++) {
      final n = caretRow.children[i];
      if (n is MFrac) return true;
      if (n is MSym && n.tex == '/') return true;
      // A fraction the student already toggled counts too, so `1/2 = 0.5`
      // switched to a fraction does not flip back on the next line.
      if (n is MAnswer && n.content.children.any((c) => c is MFrac)) return true;
    }
    return false;
  }

  /// The answer, written the way it should be read.
  ///
  /// A plain run of digits for an ordinary number — and `6.02 × 10²³` for one
  /// that needs an exponent, because `6.02000000000e+23` is programmer
  /// notation and a student reads straight past it. Big answers were being
  /// REFUSED outright before this (the digits-only test threw them away), so
  /// `20!` and `2^100` produced no answer at all.
  static MRow _digits(String text) {
    final e = RegExp(r'^(-?[0-9.]+)e([+-]?)([0-9]+)$').firstMatch(text);
    if (e == null) {
      return MRow([for (final ch in text.split('')) MSym(ch, cls: classOf(ch))]);
    }
    var mantissa = e.group(1)!;
    if (mantissa.contains('.')) {
      mantissa = mantissa.replaceFirst(RegExp(r'0+$'), '');
      if (mantissa.endsWith('.')) {
        mantissa = mantissa.substring(0, mantissa.length - 1);
      }
    }
    final neg = e.group(2) == '-';
    final exp = e.group(3)!;
    return MRow([
      for (final ch in mantissa.split('')) MSym(ch, cls: classOf(ch)),
      MSym(r'\times', cls: MClass.op),
      MScript(
        base: MRow([MSym('1'), MSym('0')]),
        sup: MRow([
          if (neg) MSym('-', cls: MClass.op),
          for (final ch in exp.split('')) MSym(ch, cls: classOf(ch)),
        ]),
      ),
    ]);
  }

  static MRow _fractionRow(({int num, int den}) r) {
    final neg = r.num < 0;
    return MRow([
      if (neg) MSym('-', cls: MClass.op),
      MFrac(num: _digits('${r.num.abs()}'), den: _digits('${r.den}')),
    ]);
  }

  /// Switch an answer between a decimal and a fraction — the click the box
  /// around it advertises.
  ///
  /// Returns false when there is nothing to switch TO: a whole number has no
  /// fraction worth showing, and a decimal that is not a tidy fraction (π,
  /// √2, a long division) has none either. The caller leaves the answer alone
  /// rather than offering a toggle that would do nothing, which is why
  /// [rationalOf] returns null for a whole number by design.
  bool toggleAnswer(MAnswer a) =>
      setAnswerForm(a, fraction: !answerIsFraction(a));

  /// Is this answer showing a fraction right now?
  bool answerIsFraction(MAnswer a) =>
      a.content.children.any((c) => c is MFrac);

  /// Is there a fraction this answer could be shown as? False for a whole
  /// number and for a decimal no tidy fraction says exactly.
  bool answerHasFraction(MAnswer a) {
    final v = _valueOf(a);
    return v.isOk && _tidyFraction(v) != null;
  }

  /// Write this answer as a fraction, or as a decimal. Returns false when
  /// there is nothing to change — no fraction to switch to, or already so.
  bool setAnswerForm(MAnswer a, {required bool fraction}) {
    if (fraction == answerIsFraction(a)) return false;
    final v = _valueOf(a);
    if (!v.isOk) return false;
    if (fraction && _tidyFraction(v) == null) return false;
    // A click is a click: it ends any highlight, exactly as clicking
    // anywhere else in the equation does. Leaving one alive meant the next
    // keystroke ran `deleteSelection` and took the student's working with
    // it — the click LOOKED like it had only changed a fraction to a
    // decimal.
    clearSelection();
    _rewrite(a, v, fraction: fraction, sigFigs: fraction ? null : a.sigFigs);
    return true;
  }

  /// Show this answer to [figures] significant figures, or to as many as the
  /// number needs when [figures] is null.
  bool setAnswerSigFigs(MAnswer a, int? figures) {
    final v = _valueOf(a);
    if (!v.isOk) return false;
    clearSelection();
    a.sigFigs = figures;
    _rewrite(a, v, fraction: false, sigFigs: figures);
    return true;
  }

  /// Work this answer out again from the working in front of it — what to
  /// press after switching between degrees and radians, or after any change
  /// the app decided not to make on the student's behalf.
  bool recalculateAnswer(MAnswer a) {
    final v = _valueOf(a);
    if (!v.isOk) return false;
    final before = rowToTex(a.content, kStoreCtx);
    _rewrite(a,
        v, fraction: answerIsFraction(a), sigFigs: _precisionOf(a));
    return rowToTex(a.content, kStoreCtx) != before;
  }

  /// Take the answer away, leaving the working exactly as it was.
  bool removeAnswer(MAnswer a) {
    final i = root.children.indexOf(a);
    if (i < 0) return false;
    clearSelection();
    root.removeAt(i);
    if (caretIndex > i && identical(caretRow, root)) caretIndex--;
    return true;
  }

  void _rewrite(MAnswer a, EvalResult v,
      {required bool fraction, int? sigFigs}) {
    final next = _writeAnswer(v, fraction: fraction, sigFigs: sigFigs);
    a.content.children.clear();
    a.content.addAll(next.drain());
  }

  /// The precision this answer is currently showing, for a menu that has to
  /// tick one of its own choices. Null means "as many figures as it needs".
  int? answerSigFigs(MAnswer a) => _precisionOf(a);

  /// This answer written as a decimal, and as a fraction — so a menu can SHOW
  /// the two choices instead of naming them. Null when that form does not
  /// exist, which is also the answer to "should this row be there at all".
  String? answerFormTex(MAnswer a, {required bool fraction}) {
    final v = _valueOf(a);
    if (!v.isOk) return null;
    if (fraction && _tidyFraction(v) == null) return null;
    return rowToTex(
        _writeAnswer(v,
            fraction: fraction, sigFigs: fraction ? null : _precisionOf(a)),
        kStoreCtx);
  }

  /// This answer written to [figures] significant figures, for the same
  /// reason: the menu shows what you would get.
  String? answerAtFiguresTex(MAnswer a, int? figures) {
    final v = _valueOf(a);
    if (!v.isOk) return null;
    return rowToTex(
        _writeAnswer(v, fraction: false, sigFigs: figures), kStoreCtx);
  }

  /// The digits themselves, for the clipboard. What you would paste into a
  /// calculator, a spreadsheet or a message — not LaTeX.
  String answerPlainText(MAnswer a) =>
      _writtenDigits(a.content) ?? rowToLinear(a.content).trim();

  /// **Would this answer be a different number in the other angle mode?**
  ///
  /// Asked rather than guessed: the working is evaluated both ways and the
  /// two readings compared. No list of function names to keep in step, and it
  /// is right for the awkward cases on its own — `sin(30°)` carries its own
  /// unit and so does not depend on the mode, while `sin(30)` does.
  bool answerDependsOnAngleMode(MAnswer a) {
    final i = root.children.indexOf(a);
    if (i <= 0 || !_isEquals(root.children[i - 1])) return false;
    final w = _workingBefore(i - 1);
    if (w == null) return false;
    final saved = mathAngleMode;
    try {
      mathAngleMode = AngleMode.degrees;
      final inDeg = evaluateLinear(w);
      mathAngleMode = AngleMode.radians;
      final inRad = evaluateLinear(w);
      if (!inDeg.isOk || !inRad.isOk) return false;
      return inDeg.display != inRad.display;
    } finally {
      mathAngleMode = saved;
    }
  }

  /// **The exact value an answer stands for.**
  ///
  /// Re-worked from the working in front of it whenever there is one, and only
  /// read back off the digits when there is not (an answer that arrived by
  /// paste). Reading the digits is not good enough on its own: an answer shown
  /// to three figures says `0.333`, and turning THAT into a fraction gives
  /// 333/1000 rather than a third.
  EvalResult _valueOf(MAnswer a) {
    final i = root.children.indexOf(a);
    if (i > 0 && _isEquals(root.children[i - 1])) {
      final w = _workingBefore(i - 1);
      if (w != null) {
        final r = evaluateLinear(w);
        if (r.isOk) return r;
      }
    }
    // No working: read the number as written, without its unit — a degree
    // sign means "in radians" to the evaluator, and an answer is not working.
    final digits = _writtenDigits(a.content);
    if (digits != null) {
      final d = double.tryParse(digits);
      if (d != null) return EvalResult.ok(d);
    }
    return evaluateLinear(rowToLinear(a.content));
  }

  /// Re-work every answer in the equation, because the working changed.
  ///
  /// The owner: *"Please make it update the value when i update the equation,
  /// but debounce it so its not doing lots of unnesesary updates."* The
  /// debounce lives in the field (which knows about keystrokes); this is the
  /// pass itself, and it is cheap — a projection and an evaluation per
  /// answer, over a row that is a few dozen atoms at most.
  ///
  /// Left to right, because answers feed each other: in `2+3=[5]+1=[6]` the
  /// second answer's working contains the first, so the first has to be
  /// right before the second is asked.
  ///
  /// **An answer whose working no longer works out is REMOVED**, not left
  /// standing. The box means "the app worked this out", so an answer the app
  /// can no longer stand behind is a lie — and one that would be believed,
  /// because it looks exactly like a true one. Typing `= ` brings it back.
  ///
  /// How it is WRITTEN is preserved: an answer the student switched to a
  /// fraction stays a fraction if the new value has one.
  /// Whether this equation holds an answer at all — checked before arming
  /// the refresh timer, so an equation with no maths worked out in it never
  /// schedules a wakeup.
  bool get hasAnswers => root.children.any((n) => n is MAnswer);

  bool refreshAnswers() {
    var changed = false;
    for (var i = 0; i < root.length; i++) {
      final a = root.children[i];
      if (a is! MAnswer) continue;
      // The `=` immediately before it is what makes it an answer to
      // something. Without one it is an orphan — a paste, or an edit that
      // took the `=` away — and there is no working to re-read.
      if (i == 0 || !_isEquals(root.children[i - 1])) continue;
      final working = _workingBefore(i - 1);
      if (working == null) continue;
      final r = evaluateLinear(working);
      if (!r.isOk || !_isPlainNumber(r.display)) {
        root.removeAt(i);
        if (caretIndex > i) caretIndex--;
        i--;
        changed = true;
        continue;
      }
      final next = _writeAnswer(r,
          fraction: a.content.children.any((c) => c is MFrac),
          sigFigs: _precisionOf(a));
      if (rowToTex(next, kStoreCtx) == rowToTex(a.content, kStoreCtx)) {
        continue; // already right — touch nothing
      }
      a.content.children.clear();
      a.content.addAll(next.drain());
      changed = true;
    }
    if (changed) clearSelection();
    return changed;
  }

  static bool _isEquals(MNode n) => n is MSym && n.tex == '=';

  static bool _isPlainNumber(String s) =>
      s.isNotEmpty && RegExp(r'^-?[0-9.]+(e[+-]?[0-9]+)?$').hasMatch(s);

  /// The linear form of the run that ENDS at [endExclusive] (the index of the
  /// `=`), reaching back to the previous `=` or the start of the row. Null
  /// when there is nothing there, or nothing a number could come of.
  String? _workingBefore(int endExclusive) {
    var from = 0;
    for (var i = endExclusive - 1; i >= 0; i--) {
      if (_isEquals(root.children[i])) {
        from = i + 1;
        break;
      }
    }
    if (endExclusive - from <= 0) return null;
    final slice = MRow();
    for (var i = from; i < endExclusive; i++) {
      slice.children.add(root.children[i]);
    }
    final lone = slice.children.length == 1 ? slice.children.first : null;
    final onlyLetter = lone is MSym &&
        lone.tex.length == 1 &&
        RegExp('[A-Za-z]').hasMatch(lone.tex);
    final linear = rowToLinear(slice).trim();
    slice.children.clear();
    return linear.isEmpty || onlyLetter ? null : linear;
  }

  /// The fraction for a value, but only when it is the SAME number.
  ///
  /// [rationalOf] accepts anything within 1e-9, which is right for asking
  /// "is there an odd root here" and wrong for rewriting a student's answer:
  /// a decimal they typed as `0.6666666667` became `2/3`, and clicking back
  /// gave `0.666666666667` — a different number, and no way to get the first
  /// one back. The promise is a change of FORM, never of value, so the
  /// fraction has to read back as the very same decimal.
  static ({int num, int den})? _tidyFraction(EvalResult value) {
    final rat = rationalOf(value.value);
    if (rat == null) return null;
    final back = EvalResult.ok(rat.num / rat.den);
    return back.display == value.display ? rat : null;
  }

  /// The answer at [index] in the ROOT row, if that child is one.
  ///
  /// The root, NOT the caret's row: the field's hit table is measured over
  /// `root` (`MathHitTable.prefixTexes(_e.root)`), so an index from a click
  /// only means anything there. Reading `caretRow` instead made the two
  /// agree only while the caret happened to be in the root row — and the
  /// moment it was inside a fraction or a script, a click on one glyph
  /// silently rewrote a DIFFERENT answer somewhere else in the equation,
  /// committed it, and placed no caret. Probe-proven.
  ///
  /// The consequence, taken deliberately: an answer nested inside a slot
  /// cannot be clicked. There is no geometry for it — the hit table measures
  /// root children only — so there is no honest target, and an answer is
  /// only ever CREATED at the top level anyway.
  MAnswer? answerAt(int index) {
    if (index < 0 || index >= root.length) return null;
    final n = root.children[index];
    return n is MAnswer ? n : null;
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
    // A template already has its brackets and its boxes; a plain function
    // name does not, and the `(` the student typed still has work to do.
    return item.build().first is MCall;
  }

  bool _buildOperatorRun(String ch) {
    for (final (run, item) in mathOperatorRuns) {
      if (!run.endsWith(ch)) continue;
      final head = run.substring(0, run.length - 1);
      if (head.isEmpty) continue;
      if (caretIndex < head.length) continue;
      // **`20!=` is a factorial, not a not-equals.** The `!=` run consumed
      // the `!` the student had just typed and left `20≠` — their factorial
      // deleted, and no answer, on the one shape every factorial line has.
      // After a number or a closing bracket, `!` is an operator that has
      // already been applied to something; ≠ never follows one.
      if (run == '!=' && caretIndex >= 2) {
        final before = caretRow.children[caretIndex - 2];
        if (before is MSym &&
            (RegExp(r'^[0-9]$').hasMatch(before.tex) ||
                before.tex == ')')) {
          continue;
        }
      }
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
    // **An empty index deletes itself**, leaving an ordinary square root.
    // Without this, taking the 3 out of a cube root left `\sqrt[]{x}` — a
    // root printing an empty box for ever, with no way back to a plain
    // radical short of deleting the whole thing and starting again. A bare
    // radical already MEANS two, so this is the same root either way.
    if (owner is MSqrt &&
        owner.degree != null &&
        identical(caretRow, owner.degree) &&
        caretRow.isEmpty) {
      owner.degree = null;
      caretRow = owner.radicand;
      caretIndex = 0;
      _openText = null;
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
  /// `&` inside a matrix: a new column, with the caret in it — the same
  /// character LaTeX itself uses to separate columns, so the one group who
  /// already know a way to say "next column" keep it, and Enter-for-row /
  /// &-for-column make a full grid reachable from the keyboard. Outside a
  /// matrix, `&` stays the character it is.
  ///
  /// This closes "the palette only makes 2x2" (open since v0.18 s13.6): a
  /// 3-vector, a 2x3 grid or an augmented matrix needed the LaTeX view,
  /// which defeats the year-10 bar for the whole linear-algebra topic.
  bool addMatrixColumn() {
    var row = caretRow;
    while (true) {
      final owner = row.owner;
      if (owner == null) return false;
      if (owner is MMatrix) {
        final at = owner.locate(row);
        if (at == null) return false;
        owner.addColumnAfter(at.$2);
        caretRow = owner.rows[at.$1][at.$2 + 1];
        caretIndex = 0;
        _openText = null;
        clearSelection();
        return true;
      }
      final parent = owner.parent;
      if (parent == null) return false;
      row = parent;
    }
  }

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
