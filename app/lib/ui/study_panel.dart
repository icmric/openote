/// The study panel: review the cards your own notes produced.
///
/// Kept deliberately plain — a card, an answer, four buttons. The whole value
/// is that it takes zero setup, so anything that looks like deck management
/// would be working against the point.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../study/flashcards.dart';
import '../theme/onote_theme.dart';

class StudyPanel extends StatefulWidget {
  const StudyPanel({super.key, required this.app});
  final AppState app;

  @override
  State<StudyPanel> createState() => _StudyPanelState();
}

class _StudyPanelState extends State<StudyPanel> {
  AppState get app => widget.app;

  List<Flashcard>? _session;
  int _index = 0;
  bool _revealed = false;

  /// Limit to the section being worked on, which is what "revise this topic"
  /// means in practice.
  bool _sectionOnly = true;

  String? get _scope => _sectionOnly ? app.activeSectionId : null;

  void _start() {
    setState(() {
      _session = app.dueCards(sectionId: _scope);
      _index = 0;
      _revealed = false;
    });
  }

  void _grade(Grade g) {
    final s = _session;
    if (s == null || _index >= s.length) return;
    app.gradeCard(s[_index].id, g);
    setState(() {
      _index++;
      _revealed = false;
    });
  }

  Future<void> _export() async {
    final cards = app.deck(sectionId: _scope);
    if (cards.isEmpty) return;
    final path = await getSaveLocation(
      suggestedName: 'openote-cards.txt',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Anki text', extensions: ['txt', 'tsv'])
      ],
    );
    if (path == null) return;
    final file = XFile.fromData(
      Uint8List.fromList(utf8.encode(cardsToAnkiTsv(cards))),
      mimeType: 'text/tab-separated-values',
    );
    await file.saveTo(path.path);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Exported ${cards.length} cards — '
            'import into Anki with File ▸ Import')));
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (due, total) = app.deckCounts(sectionId: _scope);
    return Container(
      width: 300,
      color: dark ? OnoteColors.night0 : OnoteColors.paper50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
            child: Row(children: [
              const Icon(Icons.school_outlined,
                  size: 14, color: OnoteColors.graphite400),
              const SizedBox(width: 6),
              const Text('STUDY',
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .6,
                      color: OnoteColors.graphite400)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 15),
                visualDensity: VisualDensity.compact,
                tooltip: 'Close study',
                onPressed: app.toggleStudyPanel,
              ),
            ]),
          ),
          Expanded(
            child: _session == null || _index >= (_session?.length ?? 0)
                ? _overview(due, total)
                : _card(_session![_index], dark),
          ),
        ],
      ),
    );
  }

  Widget _overview(int due, int total) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_session != null && _index >= _session!.length) ...[
              const Text('Session complete.',
                  style:
                      TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
            ],
            if (total == 0)
              const Text(
                'No cards yet.\n\nTag a line as Question or Definition '
                '(Ctrl+3 / Ctrl+5) and it becomes a card. Highlight part of a '
                'tagged line to turn it into a fill-in-the-blank.',
                style: TextStyle(fontSize: 12.5, height: 1.45),
              )
            else ...[
              Text('$due due · $total card${total == 1 ? '' : 's'}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: due == 0 ? null : _start,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: Text(due == 0 ? 'Nothing due' : 'Review $due'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _export,
                icon: const Icon(Icons.ios_share, size: 16),
                label:
                    const Text('Export to Anki', style: TextStyle(fontSize: 12)),
              ),
            ],
            const Divider(height: 24),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _sectionOnly,
              onChanged: (v) => setState(() {
                _sectionOnly = v;
                _session = null;
              }),
              title: const Text('This section only',
                  style: TextStyle(fontSize: 12.5)),
            ),
          ],
        ),
      );

  Widget _card(Flashcard c, bool dark) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${_index + 1} of ${_session!.length} · ${c.pageTitle}',
                style: const TextStyle(
                    fontSize: 11, color: OnoteColors.graphite400)),
            const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.front,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600, height: 1.4)),
                    if (_revealed) ...[
                      const Divider(height: 22),
                      SelectableText(c.back,
                          style: const TextStyle(fontSize: 14, height: 1.45)),
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: () {
                          app.selectPage(c.pageId);
                          app.jumpToBlock(c.blockId);
                        },
                        icon: const Icon(Icons.open_in_new, size: 14),
                        label: const Text('Open the note',
                            style: TextStyle(fontSize: 11.5)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (!_revealed)
              FilledButton(
                onPressed: () => setState(() => _revealed = true),
                child: const Text('Show answer'),
              )
            else
              // Four grades, not SM-2's six: more choices mid-review is more
              // introspection than anyone wants.
              Row(
                children: [
                  for (final g in Grade.values)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () => _grade(g),
                          child: Text(g.label,
                              style: const TextStyle(fontSize: 11)),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      );
}
