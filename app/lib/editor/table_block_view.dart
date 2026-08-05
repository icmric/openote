import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import '../theme/tokens.dart';

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
        return Container(
          constraints: const BoxConstraints(minHeight: 30),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          color: r == 0 ? headerFill : null,
          child: Text(cells[r][c].isEmpty ? ' ' : cells[r][c], style: style),
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

    // Imported tables carry OneNote's own per-column widths; honour them
    // exactly. A flex share each (the default) made every column equal, so an
    // imported table was the wrong shape and ran into its neighbours.
    final stored = widget.block.content['colWidths'];
    final colWidths = <int, TableColumnWidth>{
      if (stored is List && stored.length == cols)
        for (var c = 0; c < cols; c++)
          if ((stored[c] as num?) != null && (stored[c] as num) > 1)
            c: FixedColumnWidth((stored[c] as num).toDouble()),
    };
    final table = Table(
      border: TableBorder.all(color: border, width: 1),
      columnWidths: colWidths.isEmpty ? null : colWidths,
      defaultColumnWidth: const FlexColumnWidth(),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        for (var r = 0; r < rows; r++)
          TableRow(children: [for (var c = 0; c < cols; c++) cellWidget(r, c)]),
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
