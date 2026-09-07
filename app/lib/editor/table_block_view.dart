import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../markdown/md_render.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import '../theme/tokens.dart';
import 'wrap_selection.dart';

/// **How wide a column gets before somebody says otherwise.**
///
/// The owner: *"ensure it still obeys a max width so we dont end up with crazy
/// long cells by default, although if i drag the cell out there is no reason it
/// should stop at that max width, its like the boxes where they have a default
/// max width they will grow to, but it can be overriden manually."*
///
/// So this caps the AUTOMATIC width only. A width somebody dragged, or one
/// OneNote sent, is used exactly and is not clamped by this at all.
///
/// 320 is a little under half the usual page width: wide enough for a sentence
/// of prose without wrapping every few words, narrow enough that one long cell
/// cannot push the rest of the table off the page.
const double kTableColumnCap = 320;

/// The narrowest a column can be dragged. Below this the text is unreadable
/// and the handle itself becomes hard to grab back.
const double kTableColumnMin = 36;

/// Table block (MEDIA-3). content: { cells: [[String,…],…] }.
/// In edit mode each cell is a field with spreadsheet-style navigation:
/// Tab/Shift+Tab move between cells, arrows move (caret-aware on left/right),
/// Enter adds/moves to the row below, Ctrl+Enter inserts a line break.
class TableBlockView extends StatefulWidget {
  const TableBlockView({super.key, required this.block, required this.app});
  final Block block;
  final AppState app;

  @override
  State<TableBlockView> createState() => _TableBlockViewState();
}

class _CellMove extends Intent {
  const _CellMove(this.dr, this.dc, {this.caretAware = false, this.wrap = false});
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

class _TableBlockViewState extends State<TableBlockView> {
  List<List<TextEditingController>> _ctls = [];
  List<List<FocusNode>> _nodes = [];
  int _rows = 0, _cols = 0;

  bool get editing => widget.app.editingBlockId == widget.block.id;

  List<List<String>> get _cells {
    final raw = widget.block.content['cells'];
    if (raw is List && raw.isNotEmpty) {
      final grid = [
        for (final row in raw)
          [for (final c in (row as List)) c?.toString() ?? '']
      ];
      // Normalize to a rectangle. Flutter's Table and our per-cell controllers
      // require a uniform column count; an imported or hand-edited table can be
      // jagged, and a short row would otherwise crash cellWidget with a
      // RangeError. Pad short rows to the widest one.
      final cols = grid.fold(0, (m, r) => r.length > m ? r.length : m);
      for (final r in grid) {
        while (r.length < cols) {
          r.add('');
        }
      }
      return grid;
    }
    return [
      ['', ''],
      ['', ''],
    ];
  }

  /// True once this editing session has pushed an undo snapshot, so a burst of
  /// cell edits collapses into ONE undo step (matching the text/code/math
  /// editors) instead of none. Reset when editing ends.
  bool _undoPushed = false;

  void _write(List<List<String>> cells, {bool structural = false}) {
    // Regression: table writes used to call `markDirty()` without `pushUndo()`,
    // so Ctrl+Z jumped past every table edit to whatever preceded the table.
    // Structural changes (add/remove row or column) always get their own step.
    if (structural || !_undoPushed) {
      widget.app.pushUndo();
      _undoPushed = true;
    }
    widget.block.content['cells'] = cells;
    widget.block.updatedAt = nowMs();
    widget.app.markDirty();
  }

  /// **How wide a column wants to be, measured from what is in it.**
  ///
  /// `IntrinsicColumnWidth` is the obvious answer and it does not work here:
  /// a cell holds a rich-text renderer in read mode and a `TextField` in edit
  /// mode, neither of which reports a usable intrinsic width, and the table
  /// fails to lay out at all — `RenderTable was not laid out`. Measuring the
  /// text is also the cheaper answer, since intrinsics cost extra layout
  /// passes over every cell.
  ///
  /// Approximate on purpose. It measures the raw cell source, so a `**bold**`
  /// column is reckoned a few pixels wider than it renders and a `$x^2$` one
  /// wider still. That is the right kind of wrong for a DEFAULT: a column
  /// slightly too wide is readable, and anybody who minds can drag it.
  double _autoWidth(List<List<String>> cells, int col, bool dark) {
    var widest = 0.0;
    for (var r = 0; r < cells.length; r++) {
      if (col >= cells[r].length) continue;
      final text = cells[r][col];
      if (text.isEmpty) continue;
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: 13,
            // The header row is bold, so it measures wider — using one style
            // for the whole column would let the header clip.
            fontWeight: r == 0 ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();
      if (tp.width > widest) widest = tp.width;
    }
    // The cell's own horizontal padding, both sides, plus the border.
    const chrome = 8.0 * 2 + 2;
    return (widest + chrome).clamp(kTableColumnMin, kTableColumnCap);
  }

  /// The per-column widths somebody has set, `null` where they have not.
  ///
  /// Tolerant of a stored list that no longer matches the table: a column
  /// added since is simply unset, which is right — nobody chose a width for a
  /// column that did not exist.
  List<double?> _storedWidths(int cols) {
    final raw = widget.block.content['colWidths'];
    final out = List<double?>.filled(cols, null);
    if (raw is! List) return out;
    for (var c = 0; c < cols && c < raw.length; c++) {
      final v = raw[c];
      if (v is num && v > 1) out[c] = v.toDouble();
    }
    return out;
  }

  /// Remember one column's width.
  ///
  /// Written as a full list rather than a sparse map because that is the shape
  /// the `.one` importer already writes and every exporter already reads;
  /// inventing a second representation for the same fact would mean four
  /// places to keep in step. Columns nobody has sized are stored as 0, which
  /// [_storedWidths] reads back as "unset".
  void _setColumnWidth(int col, double width, int cols) {
    final w = _storedWidths(cols);
    w[col] = width.clamp(kTableColumnMin, 4000).toDouble();
    widget.app.pushUndo();
    widget.block.content['colWidths'] = [for (final v in w) v ?? 0];
    widget.block.updatedAt = nowMs();
    widget.app.markDirty();
    setState(() {});
  }

  /// The rendered width of a cell, for the moment a drag begins on a column
  /// that has never been sized.
  final Map<int, GlobalKey> _headerKeys = {};

  /// The width being dragged towards, kept across pointer samples.
  ///
  /// Accumulated from the drag's own deltas rather than re-read from the block
  /// each frame: a column whose width is clamped at the minimum would
  /// otherwise stop tracking the pointer, and dragging back out would do
  /// nothing until the mouse had returned to the edge.
  double? _dragFrom;

  double? _measuredWidth(int col) {
    final box =
        _headerKeys[col]?.currentContext?.findRenderObject() as RenderBox?;
    return box?.hasSize == true ? box!.size.width : null;
  }

  void _disposeGrid() {
    for (final row in _ctls) {
      for (final c in row) {
        c.dispose();
      }
    }
    for (final row in _nodes) {
      for (final n in row) {
        n.dispose();
      }
    }
    _ctls = [];
    _nodes = [];
  }

  void _ensure(List<List<String>> cells) {
    final rows = cells.length;
    final cols = cells.isEmpty ? 0 : cells[0].length;
    if (rows == _rows && cols == _cols && _ctls.isNotEmpty) {
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
          if (!_nodes[r][c].hasFocus && _ctls[r][c].text != cells[r][c]) {
            _ctls[r][c].text = cells[r][c];
          }
        }
      }
      return;
    }
    _disposeGrid();
    _ctls = [
      for (final row in cells) [for (final c in row) TextEditingController(text: c)]
    ];
    _nodes = [
      for (final row in cells) [for (final _ in row) FocusNode()]
    ];
    _rows = rows;
    _cols = cols;
  }

  @override
  void dispose() {
    _disposeGrid();
    super.dispose();
  }

  void _focusCell(int r, int c, {bool atEnd = true}) {
    if (r < 0 || c < 0 || r >= _rows || c >= _cols) return;
    _nodes[r][c].requestFocus();
    final ctl = _ctls[r][c];
    ctl.selection = TextSelection.collapsed(offset: atEnd ? ctl.text.length : 0);
  }

  Object? _onMove(int r, int c, _CellMove m) {
    final ctl = _ctls[r][c];
    // Caret-aware horizontal: move within the cell until the edge.
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
    _focusCell(nr, nc, atEnd: m.dc <= 0);
    return null;
  }

  Object? _onEnter(int r, int c) {
    if (r == _rows - 1) {
      final cells = _cells..add(List.filled(_cols, '', growable: true));
      _write(cells);
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusCell(r + 1, c));
    } else {
      _focusCell(r + 1, c);
    }
    return null;
  }

  Object? _onBreak(int r, int c) {
    final ctl = _ctls[r][c];
    final sel = ctl.selection;
    final at = sel.isValid ? sel.start : ctl.text.length;
    final end = sel.isValid ? sel.end : ctl.text.length;
    ctl.text = ctl.text.replaceRange(at, end, '\n');
    ctl.selection = TextSelection.collapsed(offset: at + 1);
    final cells = _cells;
    cells[r][c] = ctl.text;
    _write(cells);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cells = _cells;
    final rows = cells.length;
    final cols = cells.isEmpty ? 0 : cells[0].length;
    final border = dark ? OnoteColors.night300 : OnoteColors.paper300;
    // Handles appear when the table is being worked on — edited, or selected
    // on the canvas — and never while it is merely being read.
    final interactive =
        editing || widget.app.selectedIds.contains(widget.block.id);
    final headerFill = dark ? OnoteColors.night100 : OnoteColors.paper100;

    if (editing) {
      _ensure(cells);
    } else if (_undoPushed) {
      // Editing ended: the next session starts a new undo step.
      _undoPushed = false;
    }

    Widget cellWidget(int r, int c) {
      final style = TextStyle(
          fontSize: 13,
          fontWeight: r == 0 ? FontWeight.w600 : FontWeight.w400,
          color: dark ? OnoteColors.moon100 : OnoteColors.graphite700);
      if (!editing) {
        // Through the shared inline renderer, not a bare Text (open finding
        // since v0.18 §13.6): a formula table's $x^2$ used to show its dollar
        // signs and backslashes literally when read, and **bold** kept its
        // asterisks — table cells were the one read view that skipped the
        // Markdown grammar every text block already renders. The raw source
        // still shows while the cell is being edited, same as text blocks.
        return Container(
          constraints: const BoxConstraints(minHeight: 30),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          color: r == 0 ? headerFill : null,
          child: Text.rich(
            TextSpan(
                children: inlineSpans(
                    cells[r][c].isEmpty ? ' ' : cells[r][c], style, dark)),
            style: style,
          ),
        );
      }
      return Container(
        color: r == 0 ? headerFill : null,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Shortcuts(
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
          },
          child: Actions(
            actions: {
              _CellMove: CallbackAction<_CellMove>(
                  onInvoke: (i) => _onMove(r, c, i)),
              _CellEnter:
                  CallbackAction<_CellEnter>(onInvoke: (_) => _onEnter(r, c)),
              _CellBreak:
                  CallbackAction<_CellBreak>(onInvoke: (_) => _onBreak(r, c)),
            },
            child: TextField(
              controller: _ctls[r][c],
              focusNode: _nodes[r][c],
              style: style,
              maxLines: null,
              // Wrap-on-selection, same as every other content field.
              inputFormatters: const [
                WrapSelectionFormatter(
                    pairs: WrapSelectionFormatter.bracketPairs,
                    autoCloseFences: false)
              ],
              decoration: OnoteInput.bare.copyWith(
                  contentPadding: const EdgeInsets.symmetric(vertical: 6)),
              onChanged: (v) {
                final cur = _cells;
                cur[r][c] = v;
                _write(cur);
              },
            ),
          ),
        ),
      );
    }

    // **What decides a column's width**, in the order the rules apply.
    //
    // 1. A width somebody SET — dragged here, or carried in from OneNote's own
    //    `col_w` — is used exactly, with no cap. If you drag a column out to
    //    six hundred pixels you meant it, and an app that springs it back is
    //    arguing with you.
    // 2. Otherwise the column is as wide as its contents need, up to
    //    [kTableColumnCap]. That is the behaviour asked for: fit the content,
    //    but do not let one long sentence turn a table into a ribbon.
    //
    // Every column used to get an equal flex share, which is why they "all
    // default to larger when they should be smaller" — a two-character column
    // took the same room as a paragraph.
    final stored = _storedWidths(cols);
    final colWidths = <int, TableColumnWidth>{
      for (var c = 0; c < cols; c++)
        c: FixedColumnWidth(
            stored[c] ?? _autoWidth(cells, c, dark)),
    };
    // **The handle sits on the column's right edge, on the top row.**
    //
    // Reported: *"there isnt any way for me to manually resize the cells, at
    // least by dragging which is how it should be done"*. Quite so — there was
    // no way at all, which is also part of why the widths looked wrong: when
    // the automatic answer is off there was nothing to do about it.
    //
    // On the top row only, because a table has one width per column and
    // offering the same handle on every row would suggest otherwise. Six
    // pixels wide with a resize cursor, drawn only faintly and only when the
    // block is in play, so a table being read is a table and not a control
    // panel.
    Widget withHandle(int c, Widget cell) {
      if (!interactive || c >= cols) return cell;
      return Stack(clipBehavior: Clip.none, children: [
        cell,
        Positioned(
          top: 0,
          bottom: 0,
          right: -3,
          width: 6,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) {
                _dragFrom = _storedWidths(cols)[c] ?? _measuredWidth(c);
              },
              onHorizontalDragUpdate: (d) {
                final from = _dragFrom;
                if (from == null) return;
                _dragFrom = from + d.delta.dx;
                // No cap here on purpose: the cap is for the width nobody
                // chose. This one is chosen.
                _setColumnWidth(c, _dragFrom!, cols);
              },
              onHorizontalDragEnd: (_) => _dragFrom = null,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ]);
    }

    final table = Table(
      border: TableBorder.all(color: border, width: 1),
      columnWidths: colWidths,
      defaultColumnWidth: const FlexColumnWidth(),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        for (var r = 0; r < rows; r++)
          TableRow(children: [
            for (var c = 0; c < cols; c++)
              r == 0
                  ? KeyedSubtree(
                      key: _headerKeys.putIfAbsent(c, GlobalKey.new),
                      child: withHandle(c, cellWidget(r, c)))
                  : cellWidget(r, c)
          ]),
      ],
    );

    if (!editing) return table;

    Widget ctlBtn(IconData icon, String tip, VoidCallback fn) => IconButton(
          icon: Icon(icon, size: 16),
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          onPressed: fn,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        table,
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(children: [
            ctlBtn(Icons.add, 'Add row', () {
              _write(_cells..add(List.filled(cols, '', growable: true)), structural: true);
              setState(() {});
            }),
            ctlBtn(Icons.remove, 'Remove row', () {
              if (rows <= 1) return;
              _write(_cells..removeLast(), structural: true);
              setState(() {});
            }),
            const SizedBox(width: 8),
            ctlBtn(Icons.view_column_outlined, 'Add column', () {
              _write([for (final row in _cells) row..add('')], structural: true);
              setState(() {});
            }),
            ctlBtn(Icons.view_column, 'Remove column', () {
              if (cols <= 1) return;
              _write([for (final row in _cells) row..removeLast()], structural: true);
              setState(() {});
            }),
          ]),
        ),
      ],
    );
  }
}
