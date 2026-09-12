import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../markdown/md_render.dart' show inlineSpans;
import '../model/inline_atom.dart';
import '../theme/onote_theme.dart';
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
    this.initialCell,
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

  /// Focus this cell once, on the first editable build.
  final ({int row, int col})? initialCell;

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

class _InlineTableState extends State<InlineTable> {
  late TableData _data;
  List<List<LiveMarkdownController>> _ctls = const [];
  List<List<FocusNode>> _nodes = const [];

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
    _data = widget.binding.read();
    if (widget.editable) _build(_data);
    widget.revision?.addListener(_external);
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
    widget.revision?.removeListener(_external);
    _disposeGrid();
    super.dispose();
  }

  void _disposeGrid() {
    for (final row in _ctls) {
      for (final c in row) {
        c.dispose();
      }
    }
    for (final row in _nodes) {
      for (final n in row) {
        n
          ..removeListener(_focusChanged)
          ..dispose();
      }
    }
    _ctls = const [];
    _nodes = const [];
  }

  /// The controllers and focus nodes, one per cell — built only while the
  /// table is EDITABLE. A page of tables being read would otherwise carry a
  /// text controller and a focus node per cell for nobody to type into.
  void _build(TableData d) {
    _disposeGrid();
    _ctls = [
      for (final row in d.cells)
        [
          for (final c in row)
            LiveMarkdownController(text: c, dark: widget.dark)
        ]
    ];
    _nodes = [
      for (final row in d.cells)
        [
          for (final _ in row)
            FocusNode(debugLabel: 'tableCell')..addListener(_focusChanged)
        ]
    ];
  }

  /// Something outside this widget may have changed the table.
  ///
  /// Cheap on purpose, and does nothing at all in the overwhelming case where
  /// the table is unchanged: it is called for every notification of a shared
  /// [Listenable], which in this app is every keystroke anywhere.
  void _external() {
    if (!mounted) return;
    final next = widget.binding.read();
    if (next.rows != _rows || next.cols != _cols) {
      setState(() {
        _data = next;
        _build(next);
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

  bool get _anyFocused {
    for (final row in _nodes) {
      for (final n in row) {
        if (n.hasFocus) return true;
      }
    }
    return false;
  }

  void _focusChanged() {
    // Focus moving from one cell to the next passes through "nobody", so the
    // answer is only true once the frame has settled. Without this every Tab
    // would tell the host it had the keyboard back and then lost it again,
    // and the host redraws its caret on that signal.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final holding = _anyFocused;
      if (holding == _holdingKeyboard) return;
      _holdingKeyboard = holding;
      if (!holding) _undoPushed = false;
      widget.onKeyboard?.call(holding);
    });
  }

  void _write(TableData next, {bool structural = false}) {
    final push = structural || !_undoPushed;
    if (push) _undoPushed = true;
    _data = next;
    widget.binding.write(next, pushUndo: push);
  }

  /// Rewrite the grid AND the cells, for a change of shape: the controllers
  /// have to be rebuilt around the new size, and the focus put back where the
  /// person was looking.
  void _restructure(TableData next, {({int row, int col})? focus}) {
    _write(next, structural: true);
    setState(() => _build(next));
    if (focus == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusCell(focus.row, focus.col);
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
    if (m.wrap) {
      if (nc >= _cols) {
        nc = 0;
        nr = r + 1;
      } else if (nc < 0) {
        nc = _cols - 1;
        nr = r - 1;
      }
    }
    // Off the end of the table: the keyboard goes back to the paragraph the
    // table sits in. Tab out of the last cell is how most people leave a
    // table, and a table you cannot Tab out of is a trap.
    if (nr < 0 || nr >= _rows) {
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
      _focusCell(r + 1, c);
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
      _disposeGrid();
    }

    if (widget.editable && !_placedInitial) {
      _placedInitial = true;
      final at = widget.initialCell;
      if (at != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focusCell(at.row, at.col);
        });
      }
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
    return SizedBox(width: total, child: table);
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
        controller: _ctls[r][c],
        focusNode: _nodes[r][c],
        maxLines: null,
        style: style,
        contextMenuBuilder: (context, field) => _cellMenu(context, field, r, c),
        // Non-forced, like the host paragraph's: a cell holding a taller span
        // grows its own line instead of having the extra height measured and
        // then discarded.
        strutStyle: StrutStyle.fromTextStyle(style, forceStrutHeight: false),
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
