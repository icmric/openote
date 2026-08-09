import 'package:flutter/material.dart';

import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';

/// A trello-style task board on the page (PLANNING.md: "having the ability
/// to have a trello like task board would be incredibly helpful").
///
/// content: `{'columns': [{'title': 'To do', 'cards': ['…', …]}, …]}`
///
/// Deliberately a BLOCK, not a page mode: a board block stretched wide on an
/// empty page IS a board page, while a board beside lecture notes is a thing
/// a page mode could never give. Cards are plain strings — the unit of a
/// board is a sentence, and anything richer belongs on a page a card can
/// link to. Every mutation goes through the ordinary undo/save/sync path,
/// so Ctrl+Z, autosave and the op log all treat a board edit like any other
/// edit.
class BoardBlockView extends StatefulWidget {
  const BoardBlockView({super.key, required this.block, required this.app});
  final Block block;
  final AppState app;

  /// What a new board starts as.
  static Map<String, dynamic> starterContent() => {
        'columns': [
          {'title': 'To do', 'cards': <String>[]},
          {'title': 'Doing', 'cards': <String>[]},
          {'title': 'Done', 'cards': <String>[]},
        ],
      };

  @override
  State<BoardBlockView> createState() => _BoardBlockViewState();
}

/// A card's address while being dragged.
typedef _CardRef = ({int col, int card});

class _BoardBlockViewState extends State<BoardBlockView> {
  Block get b => widget.block;
  AppState get app => widget.app;

  /// Which card (or column title, or "new card in column N") owns the inline
  /// editor right now. One at a time, like everything else in the app.
  _CardRef? _editingCard;
  int? _editingTitle;
  int? _addingTo;
  final _editCtrl = TextEditingController();

  @override
  void dispose() {
    _editCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _cols() {
    final raw = b.content['columns'];
    if (raw is! List) return [];
    return [
      for (final c in raw)
        if (c is Map) c.cast<String, dynamic>()
    ];
  }

  List<String> _cards(Map<String, dynamic> col) =>
      [for (final c in (col['cards'] as List? ?? const [])) '$c'];

  /// One undoable, saved, synced step. Everything the board does funnels
  /// through here so no gesture can mutate without the full paper trail.
  void _mutate(void Function(List<Map<String, dynamic>> cols) fn) {
    final cols = _cols();
    app.pushUndo();
    fn(cols);
    b.content['columns'] = cols;
    app.updateBlock(b);
    setState(() {});
  }

  void _commitEditor() {
    final text = _editCtrl.text.trim();
    final editing = _editingCard;
    final title = _editingTitle;
    final adding = _addingTo;
    setState(() {
      _editingCard = null;
      _editingTitle = null;
      _addingTo = null;
    });
    if (editing != null) {
      _mutate((cols) {
        final cards = _cards(cols[editing.col]);
        if (text.isEmpty) {
          cards.removeAt(editing.card); // emptied = deleted, like a text box
        } else {
          cards[editing.card] = text;
        }
        cols[editing.col]['cards'] = cards;
      });
    } else if (title != null && text.isNotEmpty) {
      _mutate((cols) => cols[title]['title'] = text);
    } else if (adding != null && text.isNotEmpty) {
      _mutate((cols) {
        cols[adding]['cards'] = [..._cards(cols[adding]), text];
      });
    }
  }

  void _moveCard(_CardRef from, int toCol, int toIndex) {
    if (from.col == toCol && (from.card == toIndex || from.card == toIndex - 1)) {
      return; // dropped where it already is
    }
    _mutate((cols) {
      final source = _cards(cols[from.col]);
      final text = source.removeAt(from.card);
      cols[from.col]['cards'] = source;
      final dest = _cards(cols[toCol]);
      var at = toIndex;
      if (from.col == toCol && from.card < toIndex) at--;
      dest.insert(at.clamp(0, dest.length), text);
      cols[toCol]['cards'] = dest;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cols = _cols();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < cols.length; i++) ...[
              _column(context, i, cols[i], dark),
              const SizedBox(width: 8),
            ],
            // Small on purpose: adding a column is rare after week one.
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Tooltip(
                message: 'Add a column',
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => _mutate((cols) =>
                      cols.add({'title': 'New column', 'cards': <String>[]})),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child:
                        Icon(Icons.add, size: 16, color: OnoteColors.graphite400),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _column(
      BuildContext context, int i, Map<String, dynamic> col, bool dark) {
    final cards = _cards(col);
    final title = '${col['title'] ?? ''}';
    return Container(
      width: 210,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: dark ? OnoteColors.night100 : OnoteColors.paper100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Expanded(
              child: _editingTitle == i
                  ? _inlineEditor()
                  : InkWell(
                      onTap: () {
                        _commitEditor();
                        setState(() {
                          _editingTitle = i;
                          _editCtrl.text = title;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        child: Text(
                          '$title  ·  ${cards.length}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
            ),
            if (cards.isEmpty && _editingTitle != i)
              Tooltip(
                // Only an EMPTY column offers deletion: the cost of a slip
                // is somebody's task list, and emptying it first is one drag
                // per card.
                message: 'Remove this empty column',
                child: InkWell(
                  onTap: () => _mutate((cols) => cols.removeAt(i)),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.close,
                        size: 12, color: OnoteColors.graphite400),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 4),
          for (var j = 0; j < cards.length; j++)
            _dropZone(
              i,
              j,
              child: _editingCard == (col: i, card: j)
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _inlineEditor(),
                    )
                  : _card(context, i, j, cards[j], dark),
            ),
          // The column's tail catches drops below the last card — and IS the
          // whole surface of an empty column.
          _dropZone(i, cards.length,
              child: _addingTo == i
                  ? _inlineEditor()
                  : InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () {
                        _commitEditor();
                        setState(() {
                          _addingTo = i;
                          _editCtrl.clear();
                        });
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          SizedBox(width: 4),
                          Icon(Icons.add,
                              size: 13, color: OnoteColors.graphite400),
                          SizedBox(width: 4),
                          Text('Add a card',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: OnoteColors.graphite400)),
                        ]),
                      ),
                    )),
        ],
      ),
    );
  }

  /// A target that inserts an incoming card at [index] of column [col],
  /// glowing while a drag hovers so the drop point is never a guess.
  Widget _dropZone(int col, int index, {required Widget child}) {
    return DragTarget<_CardRef>(
      onWillAcceptWithDetails: (d) =>
          !(d.data.col == col && d.data.card == index),
      onAcceptWithDetails: (d) => _moveCard(d.data, col, index),
      builder: (context, candidates, _) => Container(
        decoration: candidates.isEmpty
            ? null
            : BoxDecoration(
                border: Border(
                    top: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2)),
              ),
        child: child,
      ),
    );
  }

  Widget _card(BuildContext context, int col, int idx, String text, bool dark) {
    final card = Material(
      color: dark ? OnoteColors.night0 : OnoteColors.paper0,
      borderRadius: BorderRadius.circular(6),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () {
          _commitEditor();
          setState(() {
            _editingCard = (col: col, card: idx);
            _editCtrl.text = text;
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Text(text, style: const TextStyle(fontSize: 12, height: 1.3)),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Draggable<_CardRef>(
        data: (col: col, card: idx),
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: 198,
            child: Opacity(opacity: .9, child: card),
          ),
        ),
        childWhenDragging: Opacity(opacity: .35, child: card),
        child: card,
      ),
    );
  }

  Widget _inlineEditor() => TextField(
        controller: _editCtrl,
        autofocus: true,
        maxLines: null,
        style: const TextStyle(fontSize: 12),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _commitEditor(),
        onTapOutside: (_) => _commitEditor(),
      );
}
