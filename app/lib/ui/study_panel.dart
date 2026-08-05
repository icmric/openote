/// The study panel: review the cards your own notes produced.
///
/// **The rule this panel is built around: never be a dead end.** The first
/// version had four of them. Nothing due disabled the only button and said
/// "Nothing due", which reads as *broken* rather than *finished*. A completed
/// session left the same screen with a banner. A card graded Again came back
/// tomorrow, so "let me try that one again" was impossible. And there was no
/// way to go over a topic before an exam, which is the single most common
/// thing a student wants from a review tool.
///
/// So: every state offers a next action, the schedule is previewed on the
/// buttons rather than hidden, and Practice is always available and never
/// touches the schedule.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/models.dart';
import '../model/tags.dart';
import '../state/app_state.dart';
import '../study/flashcards.dart';
import '../study/study_stats.dart';
import '../theme/onote_theme.dart';
import 'exam_date.dart';
import 'side_panel.dart';
import '../theme/tokens.dart';

/// Which pages a session draws from. Pages ARE the deck structure — a lecture
/// page is a deck without anyone having to build one — so this is a view over
/// the notebook tree rather than a card-container entity of its own.
enum DeckScope {
  page('This page'),
  section('This section'),
  notebook('Whole notebook');

  const DeckScope(this.label);
  final String label;
}

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
  StudyMode _mode = StudyMode.due;

  /// Cards graded Again this sitting — offered again from the summary, which
  /// is the whole point of getting one wrong.
  final List<Flashcard> _missed = [];

  DeckScope _scope = DeckScope.section;

  /// What the running session was built from. When the notebook moves under
  /// it — a page switch, an edit, a grade elsewhere — the session is stale and
  /// silently reviewing a vanished card would be worse than restarting.
  String? _sessionKey;

  final FocusNode _keys = FocusNode(debugLabel: 'study');

  String? get _sectionId =>
      _scope == DeckScope.notebook ? null : app.activeSectionId;
  String? get _pageId => _scope == DeckScope.page ? app.pageId : null;

  String get _scopeKey =>
      '${_scope.name}#${app.pageId}#${app.activeSectionId}#${app.notebookId}';

  @override
  void dispose() {
    _keys.dispose();
    super.dispose();
  }

  void _start(StudyMode mode) {
    final cards =
        app.study.sessionCards(sectionId: _sectionId, pageId: _pageId, mode: mode);
    if (cards.isEmpty) return; // nothing to enter; the overview stays put
    setState(() {
      _mode = mode;
      _session = cards;
      _sessionKey = _scopeKey;
      _missed.clear();
      _index = 0;
      _revealed = false;
    });
    _keys.requestFocus();
  }

  void _startWith(List<Flashcard> cards) {
    setState(() {
      _mode = StudyMode.cram;
      _session = [...cards];
      _sessionKey = _scopeKey;
      _missed.clear();
      _index = 0;
      _revealed = false;
    });
    _keys.requestFocus();
  }

  void _grade(Grade g) {
    final s = _session;
    if (s == null || _index >= s.length) return;
    final card = s[_index];
    app.study.gradeCard(card.id, g, schedule: _mode == StudyMode.due);
    if (g == Grade.again && !_missed.any((c) => c.id == card.id)) {
      _missed.add(card);
    }
    setState(() {
      _index++;
      _revealed = false;
      // Grading bumps studyRevision, which would otherwise read as "the deck
      // moved" on the next build and drop the session mid-sitting.
      _sessionKey = _scopeKey;
    });
  }

  void _end() => setState(() {
        _session = null;
        _missed.clear();
        _index = 0;
        _revealed = false;
      });

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent || _session == null) return KeyEventResult.ignored;
    // The muscle memory every spaced-repetition user already has.
    if (e.logicalKey == LogicalKeyboardKey.space) {
      _revealed ? _grade(Grade.good) : setState(() => _revealed = true);
      return KeyEventResult.handled;
    }
    if (!_revealed) return KeyEventResult.ignored;
    final g = switch (e.logicalKey) {
      LogicalKeyboardKey.digit1 => Grade.again,
      LogicalKeyboardKey.digit2 => Grade.hard,
      LogicalKeyboardKey.digit3 => Grade.good,
      LogicalKeyboardKey.digit4 => Grade.easy,
      _ => null,
    };
    if (g == null) return KeyEventResult.ignored;
    _grade(g);
    return KeyEventResult.handled;
  }

  Future<void> _export() async {
    final cards = app.study.deck(sectionId: _sectionId, pageId: _pageId);
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

  Future<void> _resetSchedule() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Forget this deck’s schedule?'),
        content: Text('Every card in ${_scope.label.toLowerCase()} becomes new '
            'again. Your notes are not touched.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Forget')),
        ],
      ),
    );
    if (ok != true) return;
    final n = app.study.resetDeck(sectionId: _sectionId, pageId: _pageId);
    if (!mounted) return;
    _end();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Reset $n cards')));
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // A session built against a different scope (or a deck that has since
    // changed) is stale. Drop it rather than review cards that may no longer
    // exist.
    if (_session != null && _sessionKey != _scopeKey) {
      _session = null;
      _missed.clear();
    }
    final stats = app.study.deckStats(sectionId: _sectionId, pageId: _pageId);
    final session = _session;
    final inSession = session != null && _index < session.length;

    return SidePanel(
      title: SidePanelKind.study.label,
      icon: Icons.school_outlined,
      onClose: app.closePanel,
      actions: _actions(inSession),
      child: Focus(
        focusNode: _keys,
        onKeyEvent: _onKey,
        child: inSession
            ? _card(session[_index], dark)
            : session != null
                ? _summary(dark)
                : _overview(stats, dark),
      ),
    );
  }

  /// Header actions. The panel supplies the title, icon and close button
  /// (style guide §7c); this is only what is specific to studying.
  List<Widget> _actions(bool inSession) => [
          if (inSession)
            TextButton(
              onPressed: _end,
              style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: const Text('End', style: TextStyle(fontSize: 12)),
            )
          else
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz, size: 16),
              tooltip: 'Deck actions',
              padding: EdgeInsets.zero,
              onSelected: (v) async {
                final sectionId = app.activeSectionId;
                switch (v) {
                  case 'export':
                    await _export();
                  case 'reset':
                    await _resetSchedule();
                  case 'exam':
                    if (sectionId != null &&
                        await pickExamDate(context, app, sectionId) &&
                        mounted) {
                      setState(() {});
                    }
                  case 'examclear':
                    if (sectionId != null && mounted) {
                      clearExamDate(context, app, sectionId);
                    }
                }
              },
              itemBuilder: (_) {
                final hasExam = app.study.examDate(app.activeSectionId) != null;
                return [
                  const PopupMenuItem(
                      value: 'export',
                      height: 36,
                      child: Text('Export to Anki…',
                          style: TextStyle(fontSize: 13))),
                  if (app.activeSectionId != null)
                    PopupMenuItem(
                        value: 'exam',
                        height: 36,
                        child: Text(hasExam ? 'Change exam date…' : 'Set exam date…',
                            style: const TextStyle(fontSize: 13))),
                  if (hasExam)
                    const PopupMenuItem(
                        value: 'examclear',
                        height: 36,
                        child: Text('Remove exam date',
                            style: TextStyle(fontSize: 13))),
                  const PopupMenuItem(
                      value: 'reset',
                      height: 36,
                      child: Text('Forget schedule…',
                          style: TextStyle(fontSize: 13))),
                ];
              },
            ),
      ];

  // ── Overview ──────────────────────────────────────────────────────────

  Widget _overview(
          ({int due, int total, int unseen, int? nextDueAt}) s, bool dark) =>
      SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _scopePicker(),
            const SizedBox(height: 14),
            if (s.total == 0)
              _emptyHelp(dark)
            else ...[
              if (_examBanner(dark, s) case final banner?) ...[
                banner,
                const SizedBox(height: 14),
              ],
              Text.rich(TextSpan(children: [
                TextSpan(
                    text: '${s.due}',
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w700)),
                TextSpan(
                    text: '  due',
                    style: TextStyle(
                        fontSize: 13, color: context.surfaces.textSecondary)),
              ])),
              const SizedBox(height: 2),
              Text(
                  '${s.total} card${s.total == 1 ? '' : 's'}'
                  '${s.unseen > 0 ? ' · ${s.unseen} new' : ''}',
                  style: TextStyle(
                      fontSize: 12, color: context.surfaces.textSecondary)),
              const SizedBox(height: 14),
              if (s.due > 0)
                FilledButton.icon(
                  onPressed: () => _start(StudyMode.due),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: Text('Review ${s.due}'),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  decoration: BoxDecoration(
                    color: OnoteColors.success.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    const Icon(Icons.check_circle_outline,
                        size: 16, color: OnoteColors.success),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s.nextDueAt == null
                            ? 'All caught up.'
                            : 'All caught up — next card in '
                                '${formatDelay(s.nextDueAt! - nowMs())}.',
                        style: const TextStyle(fontSize: 12, height: 1.35),
                      ),
                    ),
                  ]),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _start(StudyMode.cram),
                icon: const Icon(Icons.refresh, size: 16),
                label: Text('Practice all ${s.total}',
                    style: const TextStyle(fontSize: 13)),
              ),
              const SizedBox(height: 4),
              Text("Practice doesn't change your schedule.",
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 11, color: context.surfaces.textSecondary)),
              _progress(s, dark),
            ],
          ],
        ),
      );

  // ── The exam countdown ────────────────────────────────────────────────

  /// The banner above the counts, or null when there is no exam to show.
  ///
  /// Placed above the due count rather than below the buttons because it is
  /// the *reason* for the numbers underneath — "14 days" reframes "12 due"
  /// from a chore into a pace. It stays one compact strip: the primary action
  /// on this panel is still Review, and a countdown that pushed the button
  /// below the fold would be a worse feature than no countdown at all.
  ///
  /// Takes the caller's [s] rather than re-deriving it: the overview has
  /// already counted this deck, and `examPlanFor` would walk every card in it
  /// a second time for numbers that are sitting right there.
  Widget? _examBanner(
      bool dark, ({int due, int total, int unseen, int? nextDueAt}) s) {
    // A whole-notebook deck spans subjects, so there is no single revision
    // plan to state — three modules' cards are not "the exam's" cards. Show
    // the soonest exam as context, and offer the jump to the deck it means.
    if (_scope == DeckScope.notebook) {
      final next = app.study.nextExam();
      if (next == null) return null;
      return _bannerBox(
        dark: dark,
        tint: OnoteColors.brass500,
        icon: Icons.event_outlined,
        title: next.section.title,
        trailing: formatCountdown(next.plan.daysLeft),
        detail: 'Tap to study this section',
        onTap: () {
          app.activateSection(next.section.id);
          setState(() {
            _scope = DeckScope.section;
            _session = null;
          });
        },
      );
    }

    final sectionId = app.activeSectionId;
    final plan = examPlan(
      exam: app.study.examDate(sectionId),
      today: DateTime.now(),
      unseen: s.unseen,
      total: s.total,
    );
    if (plan == null) return null;

    if (plan.isPast) {
      // Kept visible rather than quietly dropped: a countdown that vanishes
      // reads as a bug, and the student is the only one who can say whether
      // the date was wrong or the exam is simply over.
      return _bannerBox(
        dark: dark,
        tint: context.surfaces.textSecondary,
        icon: Icons.event_available_outlined,
        title: 'Exam ${formatCountdown(plan.daysLeft)}',
        trailing: formatExamDate(plan.date, DateTime.now()),
        detail: 'These cards keep their schedule.',
        onClear: sectionId == null
            ? null
            : () => clearExamDate(context, app, sectionId),
      );
    }

    final detail = switch ((plan.isToday, plan.unseen)) {
      (true, 0) => 'Every card seen. Good luck.',
      (true, final n) => "$n you haven't seen yet.",
      (false, 0) => 'All ${plan.total} seen — keep the reviews up.',
      (false, final n) =>
        '$n to learn · ${plan.newPerDay} a day covers them by then',
    };
    return _bannerBox(
      dark: dark,
      tint: OnoteColors.brass500,
      icon: Icons.flag_outlined,
      title: plan.isToday
          ? 'Exam today'
          : 'Exam ${formatExamDate(plan.date, DateTime.now())}',
      trailing: formatCountdown(plan.daysLeft),
      detail: detail,
      onTap: sectionId == null
          ? null
          : () async {
              if (await pickExamDate(context, app, sectionId) && mounted) {
                setState(() {});
              }
            },
      onClear: sectionId == null
          ? null
          : () => clearExamDate(context, app, sectionId),
    );
  }

  Widget _bannerBox({
    required bool dark,
    required Color tint,
    required IconData icon,
    required String title,
    required String trailing,
    required String detail,
    VoidCallback? onTap,
    VoidCallback? onClear,
  }) =>
      Material(
        color: tint.withValues(alpha: dark ? .14 : .10),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: EdgeInsets.fromLTRB(10, 8, onClear == null ? 10 : 2, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(icon, size: 16, color: tint),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 6),
                  Text(trailing,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: tint)),
                  if (onClear != null)
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 26, minHeight: 22),
                      tooltip: 'Remove exam date',
                      color: context.surfaces.textSecondary,
                      onPressed: onClear,
                    ),
                ]),
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(detail,
                      style: TextStyle(
                          fontSize: 11,
                          height: 1.3,
                          color: context.surfaces.textSecondary)),
                ),
              ],
            ),
          ),
        ),
      );

  // ── Progress ──────────────────────────────────────────────────────────

  /// How far through the deck you are, and whether you turned up today.
  ///
  /// Below the actions on purpose: it is a reason to come back tomorrow, not a
  /// thing to read before starting. The two halves are scoped differently and
  /// labelled so — the deck's progress is this deck's, while the streak counts
  /// every notebook, because the habit is one habit.
  Widget _progress(
      ({int due, int total, int unseen, int? nextDueAt}) s, bool dark) {
    final seen = s.total - s.unseen;
    final today = app.study.reviewsToday();
    final streak = app.study.studyStreakDays();
    final sectionId = app.activeSectionId;
    final hasExam = app.study.examDate(sectionId) != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        const Divider(height: 1),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: Text('SEEN',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .6,
                    color: context.surfaces.textSecondary)),
          ),
          Text('$seen of ${s.total}',
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: s.total == 0 ? 0 : seen / s.total,
            minHeight: 4,
            backgroundColor: dark ? OnoteColors.night200 : OnoteColors.paper200,
          ),
        ),
        if (app.study.hasStudyHistory) ...[
          const SizedBox(height: 12),
          Row(children: [
            Icon(
              Icons.local_fire_department,
              size: 16,
              color: streak > 0 ? OnoteColors.brass500 : context.surfaces.textSecondary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(_streakLine(streak, today),
                  style: const TextStyle(fontSize: 12, height: 1.3)),
            ),
          ]),
          const SizedBox(height: 8),
          _activityStrip(app.study.studyActivity(), dark),
        ],
        // The only place an exam date can be added from the study side. Quiet
        // by design — it is an offer, not a demand, and a student with no exam
        // in sight should not be nagged about one.
        if (!hasExam && sectionId != null && _scope != DeckScope.notebook) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.event_outlined, size: 16),
              label: const Text('Add an exam date',
                  style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6)),
              onPressed: () async {
                if (await pickExamDate(context, app, sectionId) && mounted) {
                  setState(() {});
                }
              },
            ),
          ),
        ],
      ],
    );
  }

  static String _streakLine(int streak, int today) {
    if (streak <= 0) {
      return today > 0 ? '$today reviewed today' : 'Nothing reviewed today';
    }
    // The one line in this panel that is trying to change behaviour: a streak
    // is only motivating while it is still savable, and the day it is at risk
    // is the day worth saying so.
    if (today <= 0) return '$streak-day streak — keep it going today';
    return '$streak-day streak · $today today';
  }

  /// Reviews per day for the last fortnight. Today is the full-strength bar,
  /// so "did I turn up?" is answerable at a glance rather than by counting
  /// from the left.
  Widget _activityStrip(List<int> bars, bool dark) {
    final peak = bars.fold<int>(0, (m, v) => v > m ? v : m);
    final idle = dark ? OnoteColors.night200 : OnoteColors.paper200;
    final primary = Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: 'Reviews in the last ${bars.length} days',
      child: SizedBox(
        height: 20,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < bars.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Expanded(
                child: Container(
                  height: peak == 0 ? 2.0 : 2.0 + 18.0 * (bars[i] / peak),
                  decoration: BoxDecoration(
                    color: bars[i] == 0
                        ? idle
                        : primary.withValues(
                            alpha: i == bars.length - 1 ? 1.0 : 0.5),
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _scopePicker() => Row(children: [
        Text('Deck',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: .5,
                color: context.surfaces.textSecondary)),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<DeckScope>(
              value: _scope,
              isDense: true,
              isExpanded: true,
              style: const TextStyle(fontSize: 13),
              onChanged: (v) => setState(() {
                _scope = v ?? _scope;
                _session = null;
              }),
              items: [
                for (final s in DeckScope.values)
                  DropdownMenuItem(
                    value: s,
                    child: Builder(builder: (_) {
                      final st = app.study.deckStats(
                        sectionId:
                            s == DeckScope.notebook ? null : app.activeSectionId,
                        pageId: s == DeckScope.page ? app.pageId : null,
                      );
                      return Text('${s.label}  ·  ${st.due}/${st.total}',
                          style: DefaultTextStyle.of(context)
                              .style
                              .copyWith(fontSize: 13),
                          overflow: TextOverflow.ellipsis);
                    }),
                  ),
              ],
            ),
          ),
        ),
      ]);

  Widget _emptyHelp(bool dark) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('No cards here yet.',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          _recipe(TagKind.question, 'Ctrl+3',
              'Tag a question. The indented line below it is the answer.'),
          _recipe(TagKind.definition, 'Ctrl+5',
              'Tag a definition written as “term — meaning”.'),
          _recipe(TagKind.remember, '== ==',
              'Highlight part of a tagged line to blank it out instead.'),
          const SizedBox(height: 12),
          Text(
            'Cards are a view of your notes, so editing the note edits the '
            'card — there is nothing separate to maintain.',
            style: TextStyle(
                fontSize: 12, height: 1.4, color: context.surfaces.textSecondary),
          ),
        ],
      );

  Widget _recipe(TagKind kind, String chord, String what) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(kind.icon, size: 16, color: kind.color),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(
                  text: '$chord  ',
                  style: TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontFamilyFallback: onoteFontFallback,
                      fontSize: 11,
                      color: context.surfaces.textSecondary)),
              TextSpan(text: what),
            ]), style: const TextStyle(fontSize: 12, height: 1.4)),
          ),
        ]),
      );

  // ── Session summary ───────────────────────────────────────────────────

  Widget _summary(bool dark) {
    final done = _session?.length ?? 0;
    final stats = app.study.deckStats(sectionId: _sectionId, pageId: _pageId);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.task_alt, size: 34, color: OnoteColors.success),
            const SizedBox(height: 10),
            Text('Reviewed $done card${done == 1 ? '' : 's'}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              _missed.isEmpty
                  ? (stats.due > 0
                      ? '${stats.due} still due in this deck.'
                      : stats.nextDueAt == null
                          ? 'Nothing else due.'
                          : 'Next card in '
                              '${formatDelay(stats.nextDueAt! - nowMs())}.')
                  : '${_missed.length} need another look.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12, color: context.surfaces.textSecondary, height: 1.35),
            ),
            // The payoff. Finishing a sitting is the one moment a student is
            // certain to be looking at this panel, so it is where the streak
            // is worth stating — a number that only ever appears in a corner
            // of an overview screen is a number nobody notices going up.
            if (app.study.studyStreakDays() > 0) ...[
              const SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.local_fire_department,
                    size: 16, color: OnoteColors.brass500),
                const SizedBox(width: 5),
                Text('${app.study.studyStreakDays()}-day streak · '
                    '${app.study.reviewsToday()} today',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
            ],
            if (examPlan(
                  exam: app.study.examDate(app.activeSectionId),
                  today: DateTime.now(),
                  unseen: stats.unseen,
                  total: stats.total,
                ) case final p? when !p.isPast) ...[
              const SizedBox(height: 6),
              Text(
                p.isToday
                    ? 'Exam today.'
                    : '${formatCountdown(p.daysLeft)} until the exam'
                        '${p.unseen > 0 ? ' · ${p.unseen} still unseen' : ''}.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, color: context.surfaces.textSecondary),
              ),
            ],
            const SizedBox(height: 16),
            if (_missed.isNotEmpty)
              FilledButton.icon(
                onPressed: () => _startWith(_missed),
                icon: const Icon(Icons.replay, size: 16),
                label: Text('Review those ${_missed.length} again'),
              )
            else if (stats.due > 0)
              FilledButton.icon(
                onPressed: () => _start(StudyMode.due),
                icon: const Icon(Icons.play_arrow, size: 18),
                label: Text('Keep going — ${stats.due} due'),
              ),
            const SizedBox(height: 8),
            OutlinedButton(
                onPressed: _end,
                child: const Text('Done', style: TextStyle(fontSize: 13))),
          ],
        ),
      ),
    );
  }

  // ── One card ──────────────────────────────────────────────────────────

  Widget _card(Flashcard c, bool dark) {
    final total = _session!.length;
    final state = app.study.cardState(c.id);
    final now = nowMs();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : _index / total,
              minHeight: 3,
              backgroundColor:
                  dark ? OnoteColors.night200 : OnoteColors.paper200,
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Text('${_index + 1} of $total',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: context.surfaces.textSecondary)),
            const SizedBox(width: 6),
            Expanded(
              child: Text('· ${c.pageTitle}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11, color: context.surfaces.textSecondary)),
            ),
            if (_mode == StudyMode.cram)
              Text('PRACTICE',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .5,
                      color: context.surfaces.textSecondary)),
          ]),
          const SizedBox(height: 8),
          // Centred and height-capped: on a tall window the question used to
          // float at the top with the buttons pinned far below, so the card
          // stopped reading as one object.
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 460),
                child: _face(c, dark),
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (!_revealed)
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: FilledButton(
                  onPressed: () => setState(() => _revealed = true),
                  child: const Text('Show answer   ␣'),
                ),
              ),
            )
          else
            _grades(state, now),
        ],
      ),
    );
  }

  /// The card itself: a real surface with two sides, so the reveal reads as
  /// turning it over rather than as more text appearing underneath.
  Widget _face(Flashcard c, bool dark) {
    final kind = c.kind;
    final label = c.isCloze ? 'FILL IN THE BLANK' : kind.label.toUpperCase();
    return Container(
      decoration: BoxDecoration(
        color: dark ? OnoteColors.night50 : OnoteColors.paper0,
        border: Border.all(
            color: dark ? OnoteColors.night200 : OnoteColors.paper200),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .28 : .06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(kind.icon, size: 16, color: kind.color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .7,
                        color: kind.color)),
              ),
              // Demoted to an icon so it stops competing with the grades.
              IconButton(
                icon: const Icon(Icons.open_in_new, size: 16),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Open the note',
                color: context.surfaces.textSecondary,
                onPressed: () {
                  app.selectPage(c.pageId);
                  app.jumpToBlock(c.blockId);
                },
              ),
            ]),
            const SizedBox(height: 8),
            _front(c, kind, dark),
            const SizedBox(height: 12),
            AnimatedSize(
              duration: const Duration(milliseconds: 130),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: _revealed
                  ? _answer(c, kind, dark)
                  : _hiddenAnswer(dark),
            ),
          ],
        ),
      ),
    );
  }

  /// A cloze front reads as the sentence with a blank in it, and on reveal the
  /// answer drops INTO the blank — you read the finished sentence, which is
  /// the thing you're trying to remember.
  Widget _front(Flashcard c, TagKind kind, bool dark) {
    const style =
        TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.42);
    if (!c.isCloze) return SelectableText(c.front, style: style);
    final parts = c.front.split('[…]');
    return SelectableText.rich(TextSpan(children: [
      for (var i = 0; i < parts.length; i++) ...[
        TextSpan(text: parts[i]),
        if (i < parts.length - 1)
          TextSpan(
            text: _revealed ? c.back : '      ',
            style: TextStyle(
              color: _revealed ? kind.color : null,
              decoration: TextDecoration.underline,
              decorationColor: kind.color,
              decorationThickness: 2,
            ),
          ),
      ],
    ], style: style));
  }

  Widget _hiddenAnswer(bool dark) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: (dark ? OnoteColors.night200 : OnoteColors.paper200)),
        ),
        child: Text('Answer hidden',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: context.surfaces.textSecondary)),
      );

  Widget _answer(Flashcard c, TagKind kind, bool dark) {
    // A cloze already showed its answer in the blank; repeating it below is
    // noise.
    if (c.isCloze) return const SizedBox(width: double.infinity);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: kind.color.withValues(alpha: dark ? .16 : .08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ANSWER',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .7,
                  color: kind.color)),
          const SizedBox(height: 6),
          SelectableText(c.back,
              style: const TextStyle(fontSize: 13, height: 1.45)),
        ],
      ),
    );
  }

  /// Four grades, each showing what it will actually do. Hiding the schedule
  /// behind identical buttons is what made "Hard" and "Good" feel like a
  /// coin toss.
  Widget _grades(CardState state, int now) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final g in Grade.values) ...[
                if (g != Grade.again) const SizedBox(width: 6),
                Flexible(child: _gradeButton(g, state, now)),
              ],
            ],
          ),
        ),
      );

  Widget _gradeButton(Grade g, CardState state, int now) {
    final tint = switch (g) {
      Grade.again => OnoteColors.danger,
      Grade.easy => OnoteColors.success,
      _ => null,
    };
    final child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(g.label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        Text(
          _mode == StudyMode.cram && g != Grade.again
              ? '—'
              : previewInterval(state, g, now),
          style: TextStyle(fontSize: 11, color: context.surfaces.textSecondary),
        ),
      ],
    );
    const pad = EdgeInsets.symmetric(vertical: 6, horizontal: 2);
    // Good is the default answer, so it is the only filled button — the
    // hierarchy does the choosing when you're mid-flow.
    if (g == Grade.good) {
      return FilledButton(
        style: FilledButton.styleFrom(
            padding: pad, visualDensity: VisualDensity.compact),
        onPressed: () => _grade(g),
        child: child,
      );
    }
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        padding: pad,
        visualDensity: VisualDensity.compact,
        backgroundColor: tint?.withValues(alpha: .12),
        side: tint == null ? null : BorderSide(color: tint.withValues(alpha: .4)),
      ),
      onPressed: () => _grade(g),
      child: child,
    );
  }
}
