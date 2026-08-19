/// The editing engine: where the caret is, and what each keystroke does to
/// the tree (plan: v0.18 §6).
///
/// Two rules run through everything here.
///
/// **Nothing the student typed is ever destroyed.** Backspace on a built
/// structure unbuilds or unwraps it — a fraction becomes `1/2` again, a square
/// root hands back what was under it — but it never removes a structure and
/// its contents in one keypress. That is the "the app ate my equation" moment
/// this editor exists to avoid.
///
/// **Typing is never blocked.** Input that doesn't parse yet simply stays as
/// the characters that were typed until it does (Math Input Spec §3.3). There
/// is no error state while writing.
library;

import 'math_inventory.dart';
import 'math_parse.dart';
import 'math_tree.dart';

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
  /// of becoming maths atoms. Cleared by any caret movement, so leaving is
  /// just pressing an arrow — no mode to get stuck in.
  MText? _openText;

  bool get isEmpty => root.isEmpty;

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
          accent: style.accent,
          tint: style.tint,
          dim: style.dim,
        ),
      );

  // ───────────────────────────────────────────────────────── movement

  void placeAtEnd() {
    caretRow = root;
    caretIndex = root.length;
    _openText = null;
  }

  void placeAtStart() {
    caretRow = root;
    caretIndex = 0;
    _openText = null;
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

  bool moveUp() => _vertical(up: true);
  bool moveDown() => _vertical(up: false);

  bool _vertical({required bool up}) {
    _openText = null;
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

  /// A palette press. Fresh nodes every time — see [MathItem.build].
  void insertItem(MathItem item) {
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

    if (_openText != null && ch != '\n') {
      // Inside `\text{…}`: letters, spaces and punctuation are words, not
      // maths. Any arrow key ends this — see [_openText].
      _openText!.text += ch;
      return true;
    }

    switch (ch) {
      case ' ':
        return _buildControlWord() || _buildFunctionName();
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

    // `<=`, `->`, `!=` … complete the moment their last character lands.
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

  /// The letters immediately before the caret that the student typed as
  /// letters — never symbols autocorrect already placed.
  (int, String) _wordBefore() {
    var k = caretIndex;
    final buf = StringBuffer();
    while (k > 0) {
      final n = caretRow.children[k - 1];
      if (n is! MSym || n.cls != MClass.letter || n.tex.length != 1) break;
      buf.write(n.tex);
      k--;
    }
    final word = String.fromCharCodes(buf.toString().codeUnits.reversed);
    return (k, word);
  }

  bool _buildControlWord() {
    final (start, word) = _wordBefore();
    if (word.isEmpty) return false;
    final item = mathControlWords[word];
    if (item == null) return false;
    for (var i = caretIndex; i > start; i--) {
      caretRow.removeAt(i - 1);
    }
    caretIndex = start;
    _insertRemembering(item, word);
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

  /// `sin` typed in front of a bracket goes upright, the way every textbook
  /// sets it — without the student knowing the rule exists.
  bool _buildFunctionName() {
    final (start, word) = _wordBefore();
    if (word.length < 2) return false;
    final item = mathItemsById['fn-$word'];
    if (item == null) return false;
    for (var i = caretIndex; i > start; i--) {
      caretRow.removeAt(i - 1);
    }
    caretIndex = start;
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
      default:
        return end; // an operator is not an operand — leave the box empty
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
    final owner = caretRow.owner;
    if (owner is MScript && caretIndex == caretRow.length) {
      final leavingSub = identical(caretRow, owner.sub);
      final leavingSup = identical(caretRow, owner.sup);
      if (sup && leavingSub && owner.sup == null) {
        caretRow = owner.ensureSup();
        caretIndex = 0;
        return;
      }
      if (!sup && leavingSup && owner.sub == null) {
        caretRow = owner.ensureSub();
        caretIndex = 0;
        return;
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
  /// structure's edge it unbuilds (fraction, script — back to the linear
  /// characters that rebuild it) or unwraps (everything else — contents kept,
  /// wrapper gone). Returns false only at the very start of the equation,
  /// which the caller reads as "leave".
  bool backspace() {
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

      _dissolve(n, caretIndex - 1);
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
    _dissolve(owner, parent.children.indexOf(owner), inRow: parent);
    return true;
  }

  /// Replace a structure with its linear form, or with its contents.
  void _dissolve(MNode n, int at, {MRow? inRow}) {
    final row = inRow ?? caretRow;
    if (at < 0) return;
    final replacement = n.unbuild() ??
        [for (final s in n.slots) ...s.drain()];
    row.removeAt(at);
    row.insertAll(at, replacement);
    caretRow = row;
    caretIndex = at + replacement.length;
    _openText = null;
  }

  /// Delete forward. Symmetric with [backspace] but takes the node ahead —
  /// and leaves the caret where it was, in front of what is now there.
  bool delete() {
    if (caretIndex >= caretRow.length) return false;
    final n = caretRow.children[caretIndex];
    if (n is MSym || n is MText) {
      caretRow.removeAt(caretIndex);
      return true;
    }
    final at = caretIndex;
    _dissolve(n, at);
    caretIndex = at;
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
