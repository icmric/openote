import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../markdown/md_render.dart' show inlineSpans;
import '../model/inline_atom.dart';
import '../theme/onote_theme.dart';
import 'focus_debug.dart';
import 'live_markdown_controller.dart';

/// Where a table's data lives, and how a change to it is saved.
class TableBinding {
  const TableBinding({
    required this.read,
    required this.write,
    this.onNeedWidth,
  });

  /// The table as it stands. Called on every build and on every external
  /// change, never cached: an undo, a sync pull or the same note open twice
  /// can change it underneath us.
  final TableData Function() read;

  /// Save [next]. [pushUndo] is false for the keystrokes after the first in
  /// one burst of typing, so a sentence typed into a cell is ONE undo step
  /// rather than forty.
  final void Function(TableData next, {required bool pushUndo}) write;

  /// The table wants [total] logical pixels of width. The host grows the box
  /// if it can; if it cannot, the columns are scaled to fit instead.
  final void Function(double total)? onNeedWidth;
}

/// **How wide a column gets before somebody says otherwise.**
///
/// The owner: *"ensure it still obeys a max width so we dont end up with crazy
/// long cells by default, although if i drag the cell out there is no reason it
/// should stop at that max width"*. So this caps the AUTOMATIC width only. A
/// width somebody dragged, or one OneNote sent, is used exactly.
const double kTableColumnCap = 320;

/// The narrowest a column can be dragged. Below this the text is unreadable
/// and the handle itself becomes hard to grab back.
const double kTableColumnMin = 36;

/// Padding inside a cell. Named because the measured width of a column is
/// this plus its widest text, and the two must agree or a column is drawn
/// narrower than the thing it was measured to hold.
const EdgeInsets kTableCellPad =
    EdgeInsets.symmetric(horizontal: 8, vertical: 5);

/// The floor under a row's height, whatever the font. Shorter than this and a
/// row is hard to hit with a pointer, and a table of empty cells reads as a
/// rule rather than a table.
const double kTableRowMin = 24;

/// **The height a line with no TEXT on it takes, which is not the height a
/// line of text takes.**
///
/// Measured, because it is not guessable, and it is the whole of why a cell
/// used to grow when you clicked into it. With the non-forced strut this
/// editor needs everywhere — a forced one clamps every line to the base
/// height, so an equation in a cell would be drawn outside it — a paragraph
/// carrying no glyphs of its own lays out at the strut's full box (22px for
/// 13px Inter) while one character of text lays out at 18. An empty cell is
/// one such paragraph. So is a cell holding nothing but an equation.
///
/// So a row's MINIMUM height is this number rather than a constant: at that
/// floor, both halves of every short cell land on exactly the same height,
/// and a cell decides its own height only once it is tall enough that the two
/// agree anyway. `inline_table_test.dart` measures the pair.
///
/// [style] must be RESOLVED — merged with the ambient [DefaultTextStyle] — or
/// the answer is computed against a different font from the one that will be
/// drawn, which is a different number.
double emptyLineHeight(TextStyle style) {
  final tp = TextPainter(
    text: TextSpan(children: const [], style: style),
    strutStyle: StrutStyle.fromTextStyle(style, forceStrutHeight: false),
    textDirection: TextDirection.ltr,
  )..layout();
  final h = tp.height;
  tp.dispose();
  return h;
}

/// **The one table widget, wherever the table is kept.**
///
/// A table used to be a block of its own with its own view, so a table inside
/// a sentence would have been a second implementation of the same grid: two
/// sets of column arithmetic, two menus, two answers to what Tab does. There
/// is one widget instead, bound to its data through [TableBinding] — a
/// block's `content`, or an atom's payload inside a paragraph. The two look
/// identical because they are the same widget.
///
/// **Reading and editing are the same shape**, which is the requirement:
/// *"i want to be able to just click in a cell and start editing it in place
/// with nothing moving or changing"*. A cell being read is a `Text.rich`
/// through the shared inline renderer; a cell being written is a [TextField]
/// over a [LiveMarkdownController]. Two widgets, one geometry — both sit
/// inside the same [kTableCellPad] and the same minimum height, and both
/// render the same Markdown the same way. The equality is not argued, it is
/// measured: `inline_table_test.dart` builds the identical table in both
/// modes and holds the two to the same pixel.
///
/// Two widgets rather than one `readOnly` field, deliberately. A [TextField]
/// exposes its RAW SOURCE as its value, so a note being read would say
/// "asterisk asterisk bold asterisk asterisk" to a screen reader, and a page
/// of tables would carry an `EditableText`, a focus node and a gesture
/// detector per cell for nobody to type into.
class InlineTable extends StatefulWidget {
  const InlineTable({
    super.key,
    required this.binding,
    required this.editable,
    required this.style,
    required this.dark,
    this.revision,
    this.maxWidth,
    this.onKeyboard,
    this.onExit,
    this.onOpen,
    this.rememberCell,
    this.takeInitialCell,
  });

  final TableBinding binding;

  /// Whether a cell accepts typing. False on every read surface, and false
  /// while the note is read-only.
  final bool editable;

  /// The paragraph's own style. A table in a sentence is written in the
  /// sentence's font, not in one of its own.
  final TextStyle style;
  final bool dark;

  /// Notifies when something outside this widget may have changed the table —
  /// an undo, a sync pull, a second view of the same note. In the app that is
  /// every keystroke anywhere, so the handler compares before it does
  /// anything, and never writes over a cell somebody is typing in.
  final Listenable? revision;

  /// The room the table has. Columns are scaled down to fit when the host
  /// cannot grow; null means unconstrained.
  final double? maxWidth;

  /// A cell took or gave up the keyboard. The host editor stands its own key
  /// handling, caret and context menu down while this is true — the same one
  /// flag an inline equation already sets.
  final void Function(bool holding)? onKeyboard;

  /// Escape, or a Tab off the end: give the keyboard back to whoever had it.
  final VoidCallback? onExit;

  /// A cell was clicked while the table was being read. The host opens itself
  /// for editing and hands the cell straight back as [initialCell], so one
  /// click lands the caret where the pointer was.
  final void Function(int row, int col)? onOpen;

  /// Where the caret was, said as this table is torn down, so that a table
  /// rebuilt in its place the same frame can put it back. See
  /// `InlineAtomHost.rememberCell`.
  final void Function(int row, int col)? rememberCell;

  /// The cell to put the caret in, asked for ONCE as this table mounts —
  /// by a click on a cell while the table was being read, or by the Tab that
  /// made the table in the first place.
  ///
  /// A callback rather than a value because the answer is consumed when it is
  /// asked for: a widget that is built and then discarded must not be able to
  /// take the request with it.
  final ({int row, int col})? Function()? takeInitialCell;

  @override
  State<InlineTable> createState() => _InlineTableState();
}

class _CellMove extends Intent {
  const _CellMove(this.dr, this.dc,
      {this.caretAware = false, this.wrap = false});
  final int dr, dc;
  final bool caretAware;
  final bool wrap;
}

class _CellEnter extends Intent {
  const _CellEnter();
}

class _CellBreak extends Intent {
  const _CellBreak();
}

class _CellEscape extends Intent {
  const _CellEscape();
}

/// **A cell's own editing keys stay the cell's.**
///
/// `EditableText` publishes most of its editing actions through
/// `Action.overridable`, so that a widget ABOVE a field can change what a key
/// does inside it. A cell is a field inside another field, which turns that
/// courtesy into a hijacking: the paragraph is an ancestor, so it is found as
/// the override, and its action runs against the PARAGRAPH's text and then
/// posts the result at the cell. The owner found both halves of it —
///
///   * *"i am unable to backspace words"*. Ctrl+Backspace resolved to the
///     paragraph's delete action, which is disabled while a cell holds the
///     keyboard (the paragraph is read-only then, which is how it stops
///     taking the keystrokes in the first place), so the key did nothing at
///     all.
///   * *"attempting to highlight text by pressing ctrl + arrow keys caused it
///     to bug out and say to update openote to view the table"*. Ctrl+Shift+←
///     resolved to the paragraph's word-selection action, which measured the
///     word boundary in the paragraph and handed the cell the PARAGRAPH's
///     whole value — reference and all. The cell then held the table's own
///     reference as text, and a cell has no atom host to draw it with, so all
///     it could show was the alt text: "update Openote to see it".
///
/// Registering this for the same intent above the cell makes the cell's own
/// action the one that is found first. It then hands straight back to the
/// action it displaced: `callingAction` is the real default — the framework
/// sets it before every call — so nothing is reimplemented here, and a cell
/// gets exactly the behaviour any other text field gets.
class _CellsOwnAction<T extends Intent> extends ContextAction<T> {
  @override
  Object? invoke(T intent, [BuildContext? context]) {
    final a = callingAction;
    if (a == null) return null;
    return a is ContextAction<T> ? a.invoke(intent, context) : a.invoke(intent);
  }

  /// Null means this was not reached as an override, and there is nothing to
  /// hand back to. Disabled, so the key goes on to whoever else wants it
  /// rather than being swallowed here.
  @override
  bool get isActionEnabled => callingAction?.isActionEnabled ?? false;

  @override
  bool consumesKey(T intent) => callingAction?.consumesKey(intent) ?? false;
}

/// Every editing intent `EditableText` makes overridable, claimed for the
/// cell. The list is exactly its `_makeOverridable` entries: the others are
/// registered plainly, so the nearest field — the cell — already wins them.
final Map<Type, Action<Intent>> _cellsOwnKeys = <Type, Action<Intent>>{
  DeleteCharacterIntent: _CellsOwnAction<DeleteCharacterIntent>(),
  DeleteToNextWordBoundaryIntent:
      _CellsOwnAction<DeleteToNextWordBoundaryIntent>(),
  DeleteToLineBreakIntent: _CellsOwnAction<DeleteToLineBreakIntent>(),
  ExtendSelectionByCharacterIntent:
      _CellsOwnAction<ExtendSelectionByCharacterIntent>(),
  ExtendSelectionToNextWordBoundaryIntent:
      _CellsOwnAction<ExtendSelectionToNextWordBoundaryIntent>(),
  ExtendSelectionToNextWordBoundaryOrCaretLocationIntent:
      _CellsOwnAction<ExtendSelectionToNextWordBoundaryOrCaretLocationIntent>(),
  ExtendSelectionToNextParagraphBoundaryIntent:
      _CellsOwnAction<ExtendSelectionToNextParagraphBoundaryIntent>(),
  ExtendSelectionToNextParagraphBoundaryOrCaretLocationIntent:
      _CellsOwnAction<
          ExtendSelectionToNextParagraphBoundaryOrCaretLocationIntent>(),
  ExtendSelectionToLineBreakIntent:
      _CellsOwnAction<ExtendSelectionToLineBreakIntent>(),
  ExtendSelectionToDocumentBoundaryIntent:
      _CellsOwnAction<ExtendSelectionToDocumentBoundaryIntent>(),
  ExtendSelectionVerticallyToAdjacentLineIntent:
      _CellsOwnAction<ExtendSelectionVerticallyToAdjacentLineIntent>(),
  ExtendSelectionVerticallyToAdjacentPageIntent:
      _CellsOwnAction<ExtendSelectionVerticallyToAdjacentPageIntent>(),
  ExpandSelectionToLineBreakIntent:
      _CellsOwnAction<ExpandSelectionToLineBreakIntent>(),
  ExpandSelectionToDocumentBoundaryIntent:
      _CellsOwnAction<ExpandSelectionToDocumentBoundaryIntent>(),
  ScrollToDocumentBoundaryIntent:
      _CellsOwnAction<ScrollToDocumentBoundaryIntent>(),
  TransposeCharactersIntent: _CellsOwnAction<TransposeCharactersIntent>(),
  // **Cut, copy, paste and select-all**, which are overridable like the rest
  // and were being answered by the paragraph in the two ways it can get this
  // wrong. Copy read the PARAGRAPH's selection, which is collapsed while a
  // cell has the keyboard, so there was nothing to copy and Ctrl+C and Ctrl+X
  // did nothing. Paste is disabled on a read-only field, and the paragraph is
  // read-only exactly while a cell holds the keyboard, so Ctrl+V did nothing
  // either. The owner: *"cut, copy, and paste shortcuts dont work inside the
  // box"*. Cut has no intent of its own — it is a copy that collapses the
  // selection — so this one entry is both.
  SelectAllTextIntent: _CellsOwnAction<SelectAllTextIntent>(),
  CopySelectionTextIntent: _CellsOwnAction<CopySelectionTextIntent>(),
  PasteTextIntent: _CellsOwnAction<PasteTextIntent>(),
  // Deliberately NOT the two tap-outside intents. They decide what a click
  // somewhere else does to this field's focus, which is a question the
  // paragraph is better placed to answer than a cell is — and focus around
  // this table has been settled twice already without them.
};

class _InlineTableState extends State<InlineTable> {
  late TableData _data;
  List<List<LiveMarkdownController>> _ctls = const [];
  List<List<FocusNode>> _nodes = const [];

  /// **The table's own focus scope — where the caret goes when a cell lets go
  /// of it, instead of out of the table altogether.**
  ///
  /// This is the fix for *"it creates the new row, puts my cursor in there,
  /// and then kicks it out of the table"*, and it works by changing WHERE a
  /// released caret lands rather than by trying to stop it being released.
  ///
  /// A `FocusNode` that stops being focusable — detached because the widget
  /// holding it was rebuilt from above, disposed, told `canRequestFocus =
  /// false`, or simply `unfocus()`ed by `EditableText` itself — does not leave
  /// the caret nowhere. Flutter hands it to the nearest enclosing
  /// `FocusScope`. Without this widget that scope is the PAGE's, which is
  /// outside the paragraph entirely: the paragraph's own node stops reporting
  /// `hasFocus`, its post-build hook sees a block being edited with nothing
  /// focused inside it, and claims the keyboard — caret beside the table, and
  /// the next letters typed into the sentence. That is the exact sequence the
  /// owner's log shows, ending in `post-build claim: the paragraph takes the
  /// keyboard`.
  ///
  /// With a scope of our own the same release lands INSIDE the table: on the
  /// cell that had the caret a moment ago, or on this scope itself. Either
  /// way the paragraph's node still reports `hasFocus`, so
  /// `inlineChildFocused` stays true, the paragraph keeps its caret and its
  /// text-input connection stood down, and [_scopeChanged] puts the caret
  /// back in the cell we asked for — in the same microtask, before a frame is
  /// painted. Nothing is visible, and nothing is typed anywhere it should not
  /// be.
  ///
  /// **Why a row and not a column.** The heading row's cells are wrapped in a
  /// `KeyedSubtree` carrying a `GlobalKey` (they are measured for the column
  /// drag handles), and a GlobalKey'd element survives a rebuild from above
  /// intact — focus node and all. No other row has one. So the identical code
  /// path, reached by the identical keystroke, loses the caret when it lands
  /// in the BODY and keeps it when it lands in the HEADING, which is precisely
  /// what was reported: *"I can create a column with no issues, just rows."*
  ///
  /// Owned by the State rather than by the `FocusScope` widget, so it survives
  /// any rebuild of this table's subtree — a scope that is itself thrown away
  /// cannot catch anything.
  final FocusScopeNode _scope = FocusScopeNode(debugLabel: 'inlineTable');

  /// True once this burst of editing has pushed an undo step, so a sentence
  /// typed into a cell collapses into one. Cleared when the keyboard leaves.
  bool _undoPushed = false;
  bool _holdingKeyboard = false;
  bool _placedInitial = false;

  int get _rows => _data.rows;
  int get _cols => _data.cols;

  @override
  void initState() {
    super.initState();
    focusLog('TABLE BUILT (a teardown immediately above this line means the '
        'widget was REPLACED, not closed)');
    _data = widget.binding.read();
    if (widget.editable) _build(_data);
    widget.revision?.addListener(_external);
    _scope.addListener(_scopeChanged);
    // **And once more at the end of this frame.** A table that is replacing
    // one torn down in the same frame mounts BEFORE the old one is disposed —
    // Flutter inflates the new element and unmounts the old when the build is
    // finished — so the note saying where the caret was does not exist yet
    // when [build] first looks for it. See `InlineAtomHost.rememberCell`.
    if (widget.editable) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final at = widget.takeInitialCell?.call();
        if (at != null) _askForCell(at.row, at.col);
      });
    }
  }

  @override
  void didUpdateWidget(InlineTable old) {
    super.didUpdateWidget(old);
    if (!identical(old.revision, widget.revision)) {
      old.revision?.removeListener(_external);
      widget.revision?.addListener(_external);
    }
    if (!identical(old.binding, widget.binding)) _external();
  }

  @override
  void dispose() {
    focusLog('TABLE TORN DOWN (holding=$_holdingKeyboard want=$_wantCell)');
    widget.revision?.removeListener(_external);
    // **Hand the keyboard back on the way out.** The host stands its own key
    // handling, caret and text-input connection down while a cell holds the
    // keyboard; a table torn down while one did — the block closing, a row
    // rebuilt underneath it — would otherwise leave that true for ever, and
    // a paragraph that cannot be typed into is a far worse bug than the one
    // the flag exists to fix. Post-frame because this runs during a build.
    // **Leave a note saying where the caret was**, before the nodes that know
    // are thrown away. If this teardown is really a rebuild — the block's
    // subtree is replaced whole whenever its key changes — the table that
    // mounts in its place picks the note up and the caret never moves. If it
    // is a real close, nobody picks it up and the host drops it at the end of
    // the frame.
    final remember = widget.rememberCell;
    final was = _lastFocused;
    if (remember != null && was != null && _holdingKeyboard) {
      remember(was.row, was.col);
    }
    final tell = widget.onKeyboard;
    if (_holdingKeyboard && tell != null) {
      _holdingKeyboard = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => tell(false));
    }
    _retireGrid();
    _drainRetired();
    _scope
      ..removeListener(_scopeChanged)
      ..dispose();
    super.dispose();
  }

  /// **Let go of the grid now; dispose it when the frame is over.**
  ///
  /// The grid is torn down from inside `build` — a table leaving edit mode
  /// hands its cells back, a row inserted rebuilds them all — and disposing a
  /// `FocusNode` that still HAS the focus asks the focus manager to find the
  /// next one, mid-build. Detaching is synchronous (nothing reads `_ctls`
  /// while the table is not editable), and the disposal waits for the frame
  /// it would otherwise have reached into.
  void _retireGrid() {
    for (final row in _ctls) {
      _retired.addAll(row);
    }
    for (final row in _nodes) {
      _retired.addAll(row);
    }
    _ctls = const [];
    _nodes = const [];
    if (_retired.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _drainRetired());
  }

  final List<Object> _retired = [];

  void _drainRetired() {
    if (_retired.isNotEmpty) {
      final focused =
          _retired.whereType<FocusNode>().where((n) => n.hasFocus).length;
      focusLog('drainRetired: disposing ${_retired.length} '
          '($focused of them STILL HAVE FOCUS)');
      // **Move the caret off it deliberately, rather than letting the
      // disposal do it.** Detaching a focused `FocusNode` hands the caret to
      // the enclosing scope, and while [_scope] now catches that, a cell we
      // can name is a better destination than the scope itself — it keeps a
      // real text field under the keyboard for the whole of the handover
      // instead of for all but one microtask of it.
      if (focused > 0 && mounted) _sendCaretHome();
    }
    for (final o in _retired) {
      if (o is TextEditingController) o.dispose();
      if (o is FocusNode) {
        o
          ..removeListener(_focusChanged)
          ..dispose();
      }
    }
    _retired.clear();
  }

  /// The controllers and focus nodes, one per cell — built only while the
  /// table is EDITABLE. A page of tables being read would otherwise carry a
  /// text controller and a focus node per cell for nobody to type into.
  ///
  /// **A cell that still exists keeps the objects it had.** This used to
  /// throw the whole grid away and build a new one for any change of shape,
  /// and that is what put the caret outside the table: adding a row disposed
  /// the focus node the person was typing into, and a `FocusNode` that is
  /// detached while it holds the focus hands it to the enclosing SCOPE, which
  /// gives it to the paragraph. The caret was then put back post-frame — a
  /// race against a teardown already in flight, and the frame it lost, the
  /// keystrokes went into the sentence beside the table.
  ///
  /// Growing the grid instead means the node being typed into is never
  /// touched at all: `insertRow` at the end adds cells and disturbs nothing,
  /// which is the gesture this table is built around (type, Tab, type, Tab).
  /// Only cells that genuinely disappear are retired.
  void _build(TableData d) {
    final ctls = <List<LiveMarkdownController>>[];
    final nodes = <List<FocusNode>>[];
    for (var r = 0; r < d.rows; r++) {
      final row = <LiveMarkdownController>[];
      final keys = <FocusNode>[];
      for (var c = 0; c < d.cols; c++) {
        if (r < _ctls.length && c < _ctls[r].length) {
          final ctl = _ctls[r][c];
          // Positions shift under an insert in the MIDDLE, so what this cell
          // holds may now be its neighbour's text. Assigning moves the
          // caret to the end of it, which is why the callers that insert
          // ask for a cell explicitly afterwards.
          if (ctl.text != d.cells[r][c]) ctl.text = d.cells[r][c];
          row.add(ctl);
          keys.add(_nodes[r][c]);
        } else {
          row.add(LiveMarkdownController(text: d.cells[r][c], dark: widget.dark));
          keys.add(FocusNode(debugLabel: 'tableCell')..addListener(_focusChanged));
        }
      }
      ctls.add(row);
      nodes.add(keys);
    }
    for (var r = 0; r < _ctls.length; r++) {
      for (var c = 0; c < _ctls[r].length; c++) {
        if (r < d.rows && c < d.cols) continue;
        _retired
          ..add(_ctls[r][c])
          ..add(_nodes[r][c]);
      }
    }
    _ctls = ctls;
    _nodes = nodes;
    if (_retired.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _drainRetired());
    }
  }

  /// Something outside this widget may have changed the table.
  ///
  /// Cheap on purpose, and does nothing at all in the overwhelming case where
  /// the table is unchanged: it is called for every notification of a shared
  /// [Listenable], which in this app is every keystroke anywhere.
  void _external() {
    if (!mounted) return;
    // **Somebody outside asking for a cell.** An arrow key pressed in the
    // paragraph at the table's edge leaves the request where the Tab that
    // makes a table leaves it, and for the same reason: this widget is built
    // once per id and then kept, so there is nothing to pass it to. Polled
    // here because this already runs on every notification the app makes.
    if (widget.editable) {
      final asked = widget.takeInitialCell?.call();
      if (asked != null) _askForCell(asked.row, asked.col);
    }
    final next = widget.binding.read();
    if (next.rows != _rows || next.cols != _cols) {
      setState(() {
        _data = next;
        // Only while somebody can type in it: a shape change on a table being
        // READ (an undo, or a second view of the same note) has no cells to
        // rebuild, and building them would only have them retired again on
        // the very next build.
        if (widget.editable) _build(next);
      });
      return;
    }
    var textChanged = false;
    final typed = _ctls.isNotEmpty;
    for (var r = 0; r < next.rows; r++) {
      for (var c = 0; c < next.cols; c++) {
        if (next.cells[r][c] == _data.cells[r][c]) continue;
        textChanged = true;
        // Never over the top of somebody's typing. The controller they are
        // in is ahead of the saved value by definition.
        if (!typed || _nodes[r][c].hasFocus) continue;
        _ctls[r][c].text = next.cells[r][c];
      }
    }
    if (!textChanged && _sameWidths(next.colWidths, _data.colWidths)) return;
    setState(() => _data = next);
  }

  static bool _sameWidths(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// **Does this table hold the keyboard?**
  ///
  /// [_scope] first, and that is the load-bearing half: it answers true while
  /// the scope ITSELF holds the caret, which is the state a cell leaves
  /// behind when it is rebuilt or disposed out from under the person. Asking
  /// only the cells said "nobody" there, the host was told the keyboard was
  /// free, and the paragraph took it — see the note on [_scope]. The grid is
  /// still asked as well, for the frames before the scope is attached.
  bool get _anyFocused {
    if (_scope.hasFocus) return true;
    for (final row in _nodes) {
      for (final n in row) {
        if (n.hasFocus) return true;
      }
    }
    return false;
  }

  /// The cell the caret is actually IN, or null — including "in this table
  /// but not in any cell", which is null here and true for [_anyFocused].
  ({int row, int col})? get _focusedCell {
    for (var r = 0; r < _nodes.length; r++) {
      for (var c = 0; c < _nodes[r].length; c++) {
        if (_nodes[r][c].hasPrimaryFocus) return (row: r, col: c);
      }
    }
    return null;
  }

  /// The caret has landed on the scope rather than in a cell: a cell let go
  /// of it without another taking it. Put it back where it was going.
  ///
  /// Called from the scope's own notification, so the request is made in the
  /// same microtask the release was applied in and the next frame is drawn
  /// with the caret already in the cell. Nothing is painted in between.
  void _scopeChanged() {
    if (!mounted) return;
    if (_scope.hasPrimaryFocus) {
      focusLog('scope holds the caret — a cell let go of it');
      _sendCaretHome();
    }
    _settleKeyboard();
  }

  /// Put the caret in the cell it is owed: the one being pursued, else the
  /// one that had it last, else the first.
  ///
  /// Never invents a destination outside the grid, and does nothing at all on
  /// a table with no cells to type into — a read-only table must not trap the
  /// keyboard it was never given.
  void _sendCaretHome() {
    if (!widget.editable || _ctls.isEmpty || _rows == 0 || _cols == 0) return;
    // **Bounded within a frame.** A focus change is applied in a microtask,
    // so a cell that took the caret and dropped it again in the same breath
    // would bounce between here and the scope for ever without a frame ever
    // being drawn — a hang rather than a misplaced caret, which is worse than
    // the bug. Four goes, then leave the caret on the scope: the table still
    // holds the keyboard there ([_anyFocused] says so), so the paragraph
    // cannot take it, and the next frame starts the count again.
    if (_homeTries >= 4) {
      focusLog('sendCaretHome: four goes in one frame, leaving it on the '
          'scope rather than spinning');
      return;
    }
    _homeTries++;
    WidgetsBinding.instance
      ..ensureVisualUpdate()
      ..addPostFrameCallback((_) => _homeTries = 0);
    final home = _wantCell ?? _lastFocused ?? (row: 0, col: 0);
    _focusCell(home.row.clamp(0, _rows - 1), home.col.clamp(0, _cols - 1));
  }

  int _homeTries = 0;

  /// The last cell that held the caret, kept after it has let go.
  ///
  /// Read in [dispose], where the nodes can no longer answer: a widget's
  /// children are unmounted before it is, so by the time this State is
  /// disposed every cell's `Focus` has already detached and unfocused itself.
  /// Asking then always says "nobody", which is how the note about where the
  /// caret was came to be blank.
  ({int row, int col})? _lastFocused;

  void _focusChanged() {
    ({int row, int col})? has;
    for (var r = 0; r < _nodes.length; r++) {
      for (var c = 0; c < _nodes[r].length; c++) {
        if (_nodes[r][c].hasFocus) {
          has = (row: r, col: c);
          _lastFocused = has;
        }
      }
    }
    focusLog('focusChanged: cell=$has grid=${_rows}x$_cols want=$_wantCell');
    _settleKeyboard();
  }

  /// Tell the host, once the frame has settled, whether this table has the
  /// keyboard.
  ///
  /// Settled because focus moving from one cell to the next passes through
  /// "nobody": without the delay every Tab would say the keyboard had gone
  /// back and then come again, and the host redraws its caret on that signal.
  ///
  /// **A cell being ASKED for counts as holding it.** Rebuilding a table's
  /// grid puts a gap between the cell that had the caret and the cell that is
  /// about to, and in that gap nothing in the table is focused. Saying so
  /// hands the paragraph its keyboard back mid-move — and the paragraph, on
  /// its next frame, claims the caret it has just been told is free. That is
  /// the window behind *"it created the new row below me, but put my cursor
  /// out of the table"*, and why it happens only sometimes: it is a race
  /// between two post-frame callbacks and a focus change that lands in a
  /// microtask between them.
  void _settleKeyboard() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final holding = _anyFocused || _wantCell != null;
      focusLog('settleKeyboard: holding=$holding was=$_holdingKeyboard '
          'anyFocused=$_anyFocused want=$_wantCell');
      if (holding == _holdingKeyboard) return;
      _holdingKeyboard = holding;
      if (!holding) _undoPushed = false;
      widget.onKeyboard?.call(holding);
    });
  }

  void _write(TableData next, {bool structural = false}) {
    final push = structural || !_undoPushed;
    if (push) _undoPushed = true;
    // **Draw the table again**, because its shape on screen is measured from
    // exactly this. A column is as wide as the longest thing in it and a row
    // is as tall as it has to be, and both of those were being computed from
    // a `_data` that had been updated without anything asking for a new
    // frame. The cell being typed into kept its own text — it has its own
    // controller — so the letters appeared, in a column that never widened:
    // sixteen characters in a 21px column is sixteen lines of one letter.
    // The owner: *"when i start typing it will take a second or two to start
    // expanding horizontally (so letters get stacked), but it will catch up"*.
    // It caught up when something ELSE happened to rebuild the table — the
    // box around it changing width, which is a frame or three later and
    // sometimes not at all.
    //
    // This is not the "built once" property: that one is about a keystroke in
    // the SENTENCE not rebuilding the table, and it is kept by the atom
    // cache, which hands back the same widget. Rebuilding this State is what
    // any field does when what it draws changes, and the cells keep their
    // controllers and their focus nodes across it.
    setState(() => _data = next);
    widget.binding.write(next, pushUndo: push);
  }

  /// Rewrite the grid AND the cells, for a change of shape: the controllers
  /// have to be rebuilt around the new size, and the focus put back where the
  /// person was looking.
  void _restructure(TableData next, {({int row, int col})? focus}) {
    _write(next, structural: true);
    setState(() => _build(next));
    if (focus != null) _askForCell(focus.row, focus.col);
  }

  /// The cell the caret is being sent to, until it actually gets there.
  ///
  /// A single post-frame `requestFocus` is one throw of the dice: the frame it
  /// is made in may be the frame the grid is rebuilt in, or the one the block
  /// is re-laid-out in, and if the request does not land the caret is left in
  /// the paragraph with nothing to put it right. The owner saw the last of
  /// those: *"sometimes when hitting enter to create a new row, it does push
  /// the cursor out of the table"* — sometimes, because it is a race.
  ///
  /// So the request is kept and re-made until the cell has the caret, for at
  /// most a few frames. Bounded because a request that can never be satisfied
  /// must not fight the person for the keyboard for ever.
  ({int row, int col})? _wantCell;
  int _wantTries = 0;

  /// The cell the caret was in when [_wantCell] was asked for.
  ///
  /// The pursuit gives up when it finds ANOTHER cell holding the caret, on
  /// the reasoning that somebody clicked there and their choice beats ours.
  /// The cell we are moving AWAY from is the one exception: finding the caret
  /// still sitting there means the request has not landed yet, which is the
  /// ordinary state of the first frame or two and the opposite of a reason to
  /// stop. Without this the pursuit could stand itself down on the very frame
  /// it was made and leave the caret in the row above the new one.
  ({int row, int col})? _wantFrom;

  void _askForCell(int r, int c) {
    focusLog('askForCell($r,$c)');
    _wantFrom = _focusedCell ?? _lastFocused;
    _wantCell = (row: r, col: c);
    _wantTries = 0;
    // Said BEFORE the caret has moved, not after: from here until it lands,
    // this table has the keyboard and the paragraph must not take it.
    _settleKeyboard();
    _pursueCell();
  }

  void _pursueCell() {
    // **And make sure a frame actually happens.** A post-frame callback runs
    // at the end of the NEXT frame, and if nothing is dirty there is no next
    // frame: the request sat in the queue until something else woke the tree
    // up, which in a running app is the caret blinking and in a test is never.
    WidgetsBinding.instance.ensureVisualUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final want = _wantCell;
      if (!mounted || want == null) return;
      void stop() {
        _wantCell = null;
        _wantFrom = null;
        // The answer to "does this table have the keyboard" has just changed
        // shape, and if the pursuit failed nobody else will say so.
        _settleKeyboard();
      }

      // A grid that is momentarily the wrong size is a frame to wait for, not
      // a reason to give up: the cell being asked for may not have been built
      // yet. Dropping the request here is how it was lost.
      final built =
          want.row < _nodes.length && want.col < _nodes[want.row].length;
      final holder = _focusedCell;
      focusLog('pursue try=$_wantTries want=$want built=$built '
          'holder=$holder scope=${_scope.hasPrimaryFocus} '
          'primary=${WidgetsBinding.instance.focusManager.primaryFocus?.debugLabel}');
      if (built && holder == want) {
        focusLog('pursue STOP: the wanted cell has the caret');
        return stop();
      }
      // Somebody chose another cell in the meantime — a click. Theirs wins.
      // The cell we are coming FROM does not count: the caret has simply not
      // moved yet. Nor does the scope holding it, which means a cell let go
      // and [_scopeChanged] is putting it back — the pursuit's own business.
      if (built && holder != null && holder != _wantFrom && _wantTries > 0) {
        focusLog('pursue STOP: assumed a click — ANOTHER cell has it '
            '(holder=$holder, from=$_wantFrom, wanted=$want)');
        return stop();
      }
      if (_wantTries++ >= 8) {
        focusLog('pursue STOP: gave up after 8 frames, wanted=$want');
        return stop();
      }
      if (built) _focusCell(want.row, want.col);
      _pursueCell();
    });
  }

  void _focusCell(int r, int c, {bool atEnd = true}) {
    if (!widget.editable || _ctls.isEmpty) return;
    if (r < 0 || c < 0 || r >= _rows || c >= _cols) return;
    if (r >= _ctls.length || c >= _ctls[r].length) return;
    _nodes[r][c].requestFocus();
    final ctl = _ctls[r][c];
    ctl.selection =
        TextSelection.collapsed(offset: atEnd ? ctl.text.length : 0);
  }

  Object? _onMove(int r, int c, _CellMove m) {
    final ctl = _ctls[r][c];
    // Caret-aware horizontal: move within the cell until its edge.
    if (m.caretAware) {
      final off = ctl.selection.baseOffset;
      if (m.dc < 0 && off > 0) {
        ctl.selection = TextSelection.collapsed(offset: off - 1);
        return null;
      }
      if (m.dc > 0 && off < ctl.text.length) {
        ctl.selection = TextSelection.collapsed(offset: off + 1);
        return null;
      }
    }
    var nr = r + m.dr, nc = c + m.dc;
    // **Tab off the end of the FIRST row adds a column, not a row.**
    //
    // The owner: *"on the first row pressing tab should add a new column
    // rather than return me"*. The top row is where a table's shape is
    // decided — you are naming the columns, not filling anything in — so the
    // gesture that extends it should extend it SIDEWAYS. Every row after it
    // behaves as it does in Word and every spreadsheet, where Tab at the end
    // makes a row.
    //
    // A table is born one row old with the caret in its second cell, so this
    // is the rule that governs the whole of building a new one: type, Tab,
    // type, Tab lays out the headings, and Enter starts the body.
    if (m.wrap && r == 0 && m.dc > 0 && nc >= _cols) {
      _restructure(_data.insertColumn(_cols), focus: (row: 0, col: _cols));
      return null;
    }
    if (m.wrap) {
      if (nc >= _cols) {
        nc = 0;
        nr = r + 1;
      } else if (nc < 0) {
        nc = _cols - 1;
        nr = r - 1;
      }
    }
    if (nr >= _rows) {
      // **Tab in the last cell makes a new row**, as it does in OneNote, in
      // Word and in every spreadsheet — it is how a table gets filled in:
      // type, Tab, type, Tab. Only for Tab (`wrap`); an arrow pressed off
      // the bottom is somebody LEAVING, and gets to.
      if (m.wrap) {
        _restructure(_data.insertRow(_rows), focus: (row: _rows, col: 0));
        return null;
      }
      widget.onExit?.call();
      return null;
    }
    if (nr < 0) {
      // Off the top, or Shift+Tab out of the first cell: the keyboard goes
      // back to the paragraph the table sits in, rather than nowhere.
      widget.onExit?.call();
      return null;
    }
    _focusCell(nr, nc, atEnd: m.dc <= 0);
    return null;
  }

  Object? _onEnter(int r, int c) {
    if (r == _rows - 1) {
      _restructure(_data.insertRow(_rows), focus: (row: r + 1, col: c));
    } else {
      // Through the same door as every other move between cells, so that a
      // frame going wrong here cannot leave the caret in the paragraph either.
      _askForCell(r + 1, c);
    }
    return null;
  }

  /// Ctrl+Enter: a line break inside the cell rather than the next row.
  Object? _onBreak(int r, int c) {
    final ctl = _ctls[r][c];
    final sel = ctl.selection;
    final at = sel.isValid ? sel.start : ctl.text.length;
    final end = sel.isValid ? sel.end : ctl.text.length;
    ctl.value = TextEditingValue(
      text: ctl.text.replaceRange(at, end, '\n'),
      selection: TextSelection.collapsed(offset: at + 1),
    );
    _write(_data.withCell(r, c, ctl.text));
    return null;
  }

  // ── Column widths ────────────────────────────────────────────────────────

  /// How wide a column wants to be, measured from what is in it.
  ///
  /// `IntrinsicColumnWidth` is the obvious answer and it does not work here: a
  /// cell holds a `TextField`, which reports no usable intrinsic width, and
  /// the table then fails to lay out at all — `RenderTable was not laid out`.
  /// Measuring the text is also the cheaper answer, since intrinsics cost
  /// extra layout passes over every cell.
  ///
  /// Approximate on purpose: it measures the raw source, so a `**bold**`
  /// column is reckoned wider than it draws. That is the right kind of wrong
  /// for a DEFAULT — slightly too wide is readable, and anybody who minds can
  /// drag it.
  /// Every column's width: the one somebody dragged, else the one the
  /// contents ask for.
  List<double> _widths() => tableColumnWidths(_data, _cellStyle(0));

  void _setColumnWidth(int col, double width) {
    final w = [
      for (var c = 0; c < _cols; c++)
        c < _data.colWidths.length ? _data.colWidths[c] : 0.0
    ];
    w[col] = width.clamp(kTableColumnMin, 4000).toDouble();
    // One undo step for a whole drag, not one per pointer sample: an undo
    // entry is the encoded page, and a hundred a second of them is the
    // freeze-then-crash this had before the flag existed.
    _write(TableData(cells: _data.cells, colWidths: w),
        structural: !_dragging);
    setState(() {});
  }

  bool _dragging = false;

  /// Accumulated from the drag's own deltas rather than re-read each frame: a
  /// column clamped at the minimum would otherwise stop tracking the pointer.
  double? _dragFrom;
  final Map<int, GlobalKey> _headerKeys = {};

  double? _measuredWidth(int col) {
    final box =
        _headerKeys[col]?.currentContext?.findRenderObject() as RenderBox?;
    return box?.hasSize == true ? box!.size.width : null;
  }

  // ── The menu ─────────────────────────────────────────────────────────────

  /// **Right-click in a cell: everything a table can become, relative to the
  /// cell the pointer is in.**
  ///
  /// This replaces the row of buttons that used to sit under every open table
  /// — the owner: *"we can remove the menu that was persistantly there on the
  /// current one in favour of a right click menu, allowing me to insert a
  /// row/colum above/below the cell i clicked in, like in a standard advanced
  /// text editor"*. Those buttons could only add and remove at the END, which
  /// is why inserting a row in the middle meant retyping everything below it.
  ///
  /// Built as the cell field's OWN context menu rather than as a separate
  /// right-click gesture, and that is not a detail: a gesture on a parent
  /// loses the arena to the field's own secondary-tap recognizer, so the
  /// table menu never opened and the text one did. Going through
  /// `contextMenuBuilder` also means there is exactly one menu, carrying the
  /// table's actions above the cell's own cut/copy/paste, instead of two
  /// stacked on top of each other — the same defect an inline equation's menu
  /// had, and the same fix.
  Widget _cellMenu(
      BuildContext context, EditableTextState field, int r, int c) {
    final l = L.of(context);
    ContextMenuButtonItem item(String label, bool enabled, VoidCallback act) =>
        ContextMenuButtonItem(
          label: label,
          onPressed: !enabled
              ? null
              : () {
                  field.hideToolbar();
                  act();
                },
        );
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: field.contextMenuAnchors,
      buttonItems: [
        item(l.tableRowAbove, true,
            () => _restructure(_data.insertRow(r), focus: (row: r, col: c))),
        item(
            l.tableRowBelow,
            true,
            () => _restructure(_data.insertRow(r + 1),
                focus: (row: r + 1, col: c))),
        item(l.tableColumnLeft, true,
            () => _restructure(_data.insertColumn(c), focus: (row: r, col: c))),
        item(
            l.tableColumnRight,
            true,
            () => _restructure(_data.insertColumn(c + 1),
                focus: (row: r, col: c + 1))),
        // The last row and the last column stay: a table with neither cannot
        // be typed into, so removing them would be a one-way door.
        item(
            l.tableDeleteRow,
            _rows > 1,
            () => _restructure(_data.removeRow(r),
                focus: (row: r >= _rows - 1 ? _rows - 2 : r, col: c))),
        item(
            l.tableDeleteColumn,
            _cols > 1,
            () => _restructure(_data.removeColumn(c),
                focus: (row: r, col: c >= _cols - 1 ? _cols - 2 : c))),
        ...field.contextMenuButtonItems,
      ],
    );
  }

  // ── Drawing ──────────────────────────────────────────────────────────────

  TextStyle _cellStyle(int r) => widget.style.copyWith(
        fontWeight: r == 0 ? FontWeight.w600 : FontWeight.w400,
        color: widget.dark ? OnoteColors.moon100 : OnoteColors.graphite700,
        height: widget.style.height ?? 1.35,
      );

  @override
  Widget build(BuildContext context) {
    // A shape change from outside arrives through [_external]; one that
    // arrives with a rebuilt widget is caught here. Re-reading on every build
    // is what keeps a CACHED atom widget honest — it is handed back
    // unchanged for as long as its id is unchanged, so it cannot rely on
    // being reconstructed to notice anything.
    final live = widget.binding.read();
    final shapeChanged = live.rows != _rows || live.cols != _cols;
    if (shapeChanged) _data = live;
    if (widget.editable && (shapeChanged || _ctls.isEmpty)) {
      _build(_data);
    } else if (!widget.editable && _ctls.isNotEmpty) {
      _retireGrid();
    }

    if (widget.editable && !_placedInitial) {
      _placedInitial = true;
      final at = widget.takeInitialCell?.call();
      if (at != null) _askForCell(at.row, at.col);
    }

    final border = widget.dark ? OnoteColors.night300 : OnoteColors.paper300;
    final headerFill =
        widget.dark ? OnoteColors.night100 : OnoteColors.paper100;

    var widths = _widths();
    var total = widths.fold(0.0, (a, b) => a + b) + 2;
    final room = widget.maxWidth;
    if (room != null && total > room) {
      // Ask for the room, and fit meanwhile. A table that overflows its box
      // paints a debug stripe across the note and clips its last column,
      // which is worse than columns a few pixels narrower than they asked.
      final need = widget.binding.onNeedWidth;
      if (need != null) {
        final wanted = total;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) need(wanted);
        });
      }
      final scale = ((room - 2) / (total - 2)).clamp(0.05, 1.0);
      widths = [for (final w in widths) w * scale];
      total = widths.fold(0.0, (a, b) => a + b) + 2;
    }

    // One floor for every row, from whichever of the two cell styles wants
    // the most room. See [emptyLineHeight]: this is what holds a cell the
    // same height before and after you click into it.
    final ambient = DefaultTextStyle.of(context).style;
    double floor(TextStyle s) =>
        emptyLineHeight(s.inherit ? ambient.merge(s) : s);
    final rowMin = math.max(
        kTableRowMin,
        math.max(floor(_cellStyle(0)), floor(_cellStyle(1))) +
            kTableCellPad.vertical);

    final table = Table(
      border: TableBorder.all(color: border, width: 1),
      columnWidths: {
        for (var c = 0; c < _cols; c++) c: FixedColumnWidth(widths[c])
      },
      defaultColumnWidth: const FlexColumnWidth(),
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        for (var r = 0; r < _rows; r++)
          TableRow(
            decoration: r == 0 ? BoxDecoration(color: headerFill) : null,
            children: [
              for (var c = 0; c < _cols; c++)
                r == 0
                    ? KeyedSubtree(
                        key: _headerKeys.putIfAbsent(c, GlobalKey.new),
                        child: _withHandle(c, _cell(r, c, rowMin)))
                    : _cell(r, c, rowMin)
            ],
          ),
      ],
    );
    // SIZED, and nothing around it. A `Table` stretches to its constraints,
    // so a two-column table would otherwise be drawn across the whole page —
    // and an `Align` around it is worse still: inside a paragraph the
    // placeholder would then take the whole line, pushing the sentence off
    // it and putting the table's own hit box over the words.
    final sized = SizedBox(width: total, child: table);
    if (!widget.editable) return sized;
    // **A tap on the table belongs to the table**, including the parts of it
    // that are not a cell: the borders, the gap between two columns, the
    // strip a column is dragged by. Those fell straight through to the
    // paragraph underneath, whose own tap handler then put the caret at the
    // nearest offset it could find — which is inside the reference, because
    // every offset from the object's first character to the end of it is
    // drawn in the same place. The owner saw the visible half of that: *"if i
    // click into the last box it will put my cursor in it, but then kick it
    // out to after the table"*.
    //
    // The cells are deeper than this, so a tap that lands on one still goes
    // to that cell and this never sees it. What arrives here is only what
    // would otherwise have left the table altogether.
    //
    // **Inside the table's own focus scope**, which is what keeps a released
    // caret in the table instead of handing it to the page — see [_scope].
    // Only on the editable side: a table being read holds no keyboard and
    // must not be able to catch one.
    return FocusScope(
      node: _scope,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => _focusNearestCell(d.globalPosition),
        child: sized,
      ),
    );
  }

  /// The cell closest to a point, for a tap that landed between them.
  ///
  /// By distance to the cell's BOX rather than to its centre, so the answer
  /// for a tap on a border is the cell it is touching rather than whichever
  /// one happens to be smallest.
  void _focusNearestCell(Offset global) {
    var best = (row: -1, col: -1);
    var nearest = double.infinity;
    for (var r = 0; r < _nodes.length; r++) {
      for (var c = 0; c < _nodes[r].length; c++) {
        final box = _nodes[r][c].context?.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) continue;
        final rect = box.localToGlobal(Offset.zero) & box.size;
        final dx = global.dx < rect.left
            ? rect.left - global.dx
            : (global.dx > rect.right ? global.dx - rect.right : 0.0);
        final dy = global.dy < rect.top
            ? rect.top - global.dy
            : (global.dy > rect.bottom ? global.dy - rect.bottom : 0.0);
        final d = dx * dx + dy * dy;
        if (d < nearest) {
          nearest = d;
          best = (row: r, col: c);
        }
      }
    }
    if (best.row >= 0) _focusCell(best.row, best.col);
  }

  Widget _cell(int r, int c, double rowMin) {
    final style = _cellStyle(r);
    final field = ConstrainedBox(
      constraints: BoxConstraints(minHeight: rowMin),
      child: Padding(
        padding: kTableCellPad,
        child: widget.editable ? _editable(r, c, style) : _reading(r, c, style),
      ),
    );

    Widget out = field;
    if (widget.editable) {
      out = Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.tab): _CellMove(0, 1, wrap: true),
          SingleActivator(LogicalKeyboardKey.tab, shift: true):
              _CellMove(0, -1, wrap: true),
          SingleActivator(LogicalKeyboardKey.arrowUp): _CellMove(-1, 0),
          SingleActivator(LogicalKeyboardKey.arrowDown): _CellMove(1, 0),
          SingleActivator(LogicalKeyboardKey.arrowLeft):
              _CellMove(0, -1, caretAware: true),
          SingleActivator(LogicalKeyboardKey.arrowRight):
              _CellMove(0, 1, caretAware: true),
          SingleActivator(LogicalKeyboardKey.enter): _CellEnter(),
          SingleActivator(LogicalKeyboardKey.enter, control: true):
              _CellBreak(),
          SingleActivator(LogicalKeyboardKey.escape): _CellEscape(),
        },
        child: Actions(
          actions: {
            // Before this table's own keys, and for the same reason they are
            // here: a cell is a field inside a field, and without this the
            // paragraph answers for it. See [_CellsOwnAction].
            ..._cellsOwnKeys,
            _CellMove:
                CallbackAction<_CellMove>(onInvoke: (i) => _onMove(r, c, i)),
            _CellEnter:
                CallbackAction<_CellEnter>(onInvoke: (_) => _onEnter(r, c)),
            _CellBreak:
                CallbackAction<_CellBreak>(onInvoke: (_) => _onBreak(r, c)),
            _CellEscape: CallbackAction<_CellEscape>(onInvoke: (_) {
              widget.onExit?.call();
              return null;
            }),
          },
          child: field,
        ),
      );
    }

    if (widget.editable) return out;
    // Reading: one click asks the host to open AND says which cell was
    // clicked, so the caret lands where the pointer is instead of the table
    // opening and waiting to be clicked a second time.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onOpen?.call(r, c),
      child: out,
    );
  }

  /// A cell being read: through the SAME inline renderer the paragraph
  /// around the table uses, so an equation in a cell is an equation and bold
  /// is bold. A table used to be the one read surface that skipped the
  /// grammar and showed its dollar signs and asterisks.
  Widget _reading(int r, int c, TextStyle style) {
    final text = _data.cells[r][c];
    return Text.rich(
      TextSpan(
          children:
              inlineSpans(text.isEmpty ? ' ' : text, style, widget.dark)),
      style: style,
    );
  }

  /// A cell being written. Over a [LiveMarkdownController], so bold stays
  /// bold and an equation stays an equation while it is typed — the same
  /// change of character the paragraph itself made, and the other half of why
  /// clicking into a cell moves nothing.
  Widget _editable(int r, int c, TextStyle style) => TextField(
        // **Keyed on the focus node, not the position.** A row removed from
        // the middle slides every cell below it up, so the field at (r, c) can
        // be handed a different controller and a different focus node than it
        // had last frame — and `EditableText` does not reconsider its platform
        // text-input connection when its focus node is swapped underneath it.
        // It would go on being the field the keyboard was wired to while the
        // caret was somewhere else entirely. A key makes that a new field.
        key: ObjectKey(_nodes[r][c]),
        controller: _ctls[r][c],
        focusNode: _nodes[r][c],
        maxLines: null,
        style: style,
        contextMenuBuilder: (context, field) => _cellMenu(context, field, r, c),
        // Non-forced, like the host paragraph's: a cell holding a taller span
        // grows its own line instead of having the extra height measured and
        // then discarded.
        strutStyle: StrutStyle.fromTextStyle(style, forceStrutHeight: false),
        // Type a bracket over a selection and it WRAPS the selection, as in
        // every other content field in the app. Fences are off: a cell is one
        // line of prose, not a place to open a code block.
        inputFormatters: const [
          WrapSelectionFormatter(
              pairs: WrapSelectionFormatter.bracketPairs,
              autoCloseFences: false)
        ],
        // Collapsed and unpadded, because the cell's own padding IS the
        // padding. An InputDecorator's dense default would add 8px the read
        // half does not have, and every row would grow on click-in.
        decoration: const InputDecoration(
          isDense: true,
          isCollapsed: true,
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
        ),
        onChanged: (v) => _write(_data.withCell(r, c, v)),
      );

  Widget _withHandle(int c, Widget cell) => Stack(
        clipBehavior: Clip.none,
        children: [
          cell,
          // Wholly INSIDE the cell: a `RenderBox` rejects a hit outside its
          // own bounds before it ever reaches its children, so a strip
          // centred on the border would be dead on its outer half.
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: 8,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (_) {
                  _dragFrom =
                      (c < _data.colWidths.length && _data.colWidths[c] > 1)
                          ? _data.colWidths[c]
                          : _measuredWidth(c);
                  _dragging = false;
                },
                onHorizontalDragUpdate: (d) {
                  final from = _dragFrom;
                  if (from == null) return;
                  _dragFrom = from + d.delta.dx;
                  // No cap here on purpose: the cap is for the width nobody
                  // chose. This one is chosen.
                  _setColumnWidth(c, _dragFrom!);
                  _dragging = true;
                },
                onHorizontalDragEnd: (_) {
                  _dragFrom = null;
                  _dragging = false;
                },
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      );
}

/// **How wide each column wants to be**: the width somebody dragged, else the
/// width its contents ask for, capped at [kTableColumnCap].
///
/// A free function rather than a method because the BOX around a table has to
/// know this before there is a table to ask. `TextBlockView.autoWidth`
/// measures a paragraph to decide how wide its block should be, and a
/// paragraph containing a table has to be at least as wide as the table or it
/// is drawn squeezed. See the note on [tableNaturalWidth].
List<double> tableColumnWidths(TableData d, TextStyle headerStyle) => [
      for (var c = 0; c < d.cols; c++)
        (c < d.colWidths.length && d.colWidths[c] > 1)
            ? d.colWidths[c]
            : _measuredColumn(d, c, headerStyle)
    ];

/// One column's width, measured from what is in it.
///
/// `IntrinsicColumnWidth` is the obvious answer and it does not work here: a
/// cell holds a `TextField`, which reports no usable intrinsic width, and the
/// table then fails to lay out at all — `RenderTable was not laid out`.
/// Measuring the text is also the cheaper answer, since intrinsics cost extra
/// layout passes over every cell.
///
/// Approximate on purpose: it measures the raw source, so a `**bold**` column
/// is reckoned a few pixels wider than it draws. That is the right kind of
/// wrong for a DEFAULT — slightly too wide is readable, and anybody who minds
/// can drag it.
double _measuredColumn(TableData d, int col, TextStyle headerStyle) {
  var widest = 0.0;
  for (var r = 0; r < d.rows; r++) {
    final text = d.cells[r][col];
    if (text.isEmpty) continue;
    final tp = TextPainter(
      // At the HEADER's weight for every row: a bold header measured as body
      // text clips its own last word.
      text: TextSpan(text: text, style: headerStyle),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    final w = tp.width;
    tp.dispose();
    if (w > widest) widest = w;
  }
  return (widest + kTableCellPad.horizontal + 2)
      .clamp(kTableColumnMin, kTableColumnCap);
}

/// How wide the whole table wants to be, borders included.
double tableNaturalWidth(TableData d, TextStyle headerStyle) =>
    tableColumnWidths(d, headerStyle).fold(2.0, (a, b) => a + b);
