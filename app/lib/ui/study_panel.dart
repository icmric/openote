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

import '../export/save_where.dart';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../l10n/labels.dart';
import '../l10n/study_words.dart';
import '../markdown/md_render.dart';
import '../model/models.dart';
import '../model/tags.dart';
import '../state/app_state.dart';
import '../study/flashcards.dart';
import '../study/study_stats.dart';
import '../theme/onote_theme.dart';
import 'exam_date.dart';
import 'side_panel.dart';
import '../theme/tokens.dart';
import 'onote_dialog.dart';
import 'toast.dart';

/// Which pages a session draws from. Pages ARE the deck structure — a lecture
/// page is a deck without anyone having to build one — so this is a view over
/// the notebook tree rather than a card-container entity of its own.
enum DeckScope {
  page,
  section,
  notebook;

  String label(L l) => switch (this) {
        DeckScope.page => l.deckThisPage,
        DeckScope.section => l.deckThisSection,
        DeckScope.notebook => l.deckWholeNotebook,
      };
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
    final path = await chooseSaveLocation(
      suggestedName: 'openote-cards.txt',
      acceptedTypeGroups: [
        XTypeGroup(
            label: L.of(context).studyAnkiText, extensions: const ['txt', 'tsv'])
      ],
    );
    if (path == null) return;
    final file = XFile.fromData(
      Uint8List.fromList(utf8.encode(cardsToAnkiTsv(cards))),
      mimeType: 'text/tab-separated-values',
    );
    await file.saveTo(path.path);
    if (await finishSave(path.path) == null) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showToast(
        SnackBar(content: Text(L.of(context).studyExported(cards.length))));
  }

  Future<void> _resetSchedule() async {
    final ok = await showOnoteDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(L.of(c).studyForgetTitle),
        content: Text(L.of(c).studyForgetBody(_scope.name)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(L.of(c).commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(L.of(c).studyForget)),
        ],
      ),
    );
    if (ok != true) return;
    final n = app.study.resetDeck(sectionId: _sectionId, pageId: _pageId);
    if (!mounted) return;
    _end();
    ScaffoldMessenger.of(context)
        .showToast(SnackBar(content: Text(L.of(context).studyResetCards(n))));
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
              child: Text(L.of(context).studyEnd,
                  style: const TextStyle(fontSize: 12)),
            )
          else
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz, size: 16),
              tooltip: L.of(context).studyDeckActions,
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
                final l = L.of(context);
                const menu = TextStyle(fontSize: 13);
                return [
                  PopupMenuItem(
                      value: 'export',
                      height: 36,
                      child: Text(l.studyExportAnki, style: menu)),
                  if (app.activeSectionId != null)
                    PopupMenuItem(
                        value: 'exam',
                        height: 36,
                        child: Text(
                            hasExam ? l.studyChangeExam : l.studySetExam,
                            style: menu)),
                  if (hasExam)
                    PopupMenuItem(
                        value: 'examclear',
                        height: 36,
                        child: Text(l.studyRemoveExam, style: menu)),
                  PopupMenuItem(
                      value: 'reset',
                      height: 36,
                      child: Text(l.studyForgetSchedule, style: menu)),
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
                    text: '  ${L.of(context).studyDue}',
                    style: TextStyle(
                        fontSize: 13, color: context.surfaces.textSecondary)),
              ])),
              const SizedBox(height: 2),
              Text(
                  L.of(context).studyCards(s.total) +
                      (s.unseen > 0
                          ? ' · ${L.of(context).studyNew(s.unseen)}'
                          : ''),
                  style: TextStyle(
                      fontSize: 12, color: context.surfaces.textSecondary)),
              const SizedBox(height: 14),
              if (s.due > 0)
                FilledButton.icon(
                  onPressed: () => _start(StudyMode.due),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: Text(L.of(context).studyReview('${s.due}')),
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
                            ? L.of(context).studyAllCaughtUp
                            : L.of(context).studyAllCaughtUpNext(delayIn(
                                L.of(context), s.nextDueAt! - nowMs())),
                        style: const TextStyle(fontSize: 12, height: 1.35),
                      ),
                    ),
                  ]),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _start(StudyMode.cram),
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(L.of(context).studyPracticeAll('${s.total}'),
                    style: const TextStyle(fontSize: 13)),
              ),
              const SizedBox(height: 4),
              Text(L.of(context).studyPracticeNote,
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
        trailing: countdownIn(L.of(context), next.plan.daysLeft),
        detail: L.of(context).studyThisSection,
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
    final l = L.of(context);
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
        title: l.studyExamWhen(countdownIn(l, plan.daysLeft)),
        trailing: shortDateIn(l, plan.date, DateTime.now()),
        detail: l.studyKeepSchedule,
        onClear: sectionId == null
            ? null
            : () => clearExamDate(context, app, sectionId),
      );
    }

    final detail = switch ((plan.isToday, plan.unseen)) {
      (true, 0) => l.studyExamGoodLuck,
      (true, final n) => l.studyExamUnseenToday(n),
      (false, 0) => l.studyAllSeen('${plan.total}'),
      (false, final n) => l.studyToLearn('$n', '${plan.newPerDay}'),
    };
    return _bannerBox(
      dark: dark,
      tint: OnoteColors.brass500,
      icon: Icons.flag_outlined,
      title: plan.isToday
          ? l.studyExamToday
          : l.studyExamWhen(shortDateIn(l, plan.date, DateTime.now())),
      trailing: countdownIn(l, plan.daysLeft),
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
          mouseCursor: WidgetStateMouseCursor.clickable,
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
                      tooltip: L.of(context).studyRemoveExam,
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
            child: Text(L.of(context).studySeen,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .6,
                    color: context.surfaces.textSecondary)),
          ),
          Text(L.of(context).studyNOfM('$seen', '${s.total}'),
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: s.total == 0 ? 0 : seen / s.total,
            minHeight: 4,
            backgroundColor: context.surfaces.border,
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
              child: Text(_streakLine(L.of(context), streak, today),
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
              label: Text(L.of(context).studyAddExam,
                  style: const TextStyle(fontSize: 12)),
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

  static String _streakLine(L l, int streak, int today) {
    if (streak <= 0) {
      return today > 0 ? l.studyReviewedToday(today) : l.studyNothingToday;
    }
    // The one line in this panel that is trying to change behaviour: a streak
    // is only motivating while it is still savable, and the day it is at risk
    // is the day worth saying so.
    if (today <= 0) return l.studyStreakAtRisk('$streak');
    return l.studyStreak('$streak', '$today');
  }

  /// Reviews per day for the last fortnight. Today is the full-strength bar,
  /// so "did I turn up?" is answerable at a glance rather than by counting
  /// from the left.
  Widget _activityStrip(List<int> bars, bool dark) {
    final peak = bars.fold<int>(0, (m, v) => v > m ? v : m);
    final idle = context.surfaces.border;
    final primary = Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: L.of(context).studyActivityTip('${bars.length}'),
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
                    borderRadius: BorderRadius.circular(4),
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
        Text(L.of(context).studyDeck,
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
                      return Text(
                          '${s.label(L.of(context))}  ·  ${st.due}/${st.total}',
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
          Text(L.of(context).studyNoCards,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          _recipe(TagKind.question, _chordQuestion,
              L.of(context).studyRecipeQuestion),
          _recipe(TagKind.definition, _chordDefinition,
              L.of(context).studyRecipeDefinition),
          _recipe(TagKind.remember, _chordCloze, L.of(context).studyRecipeCloze),
          const SizedBox(height: 12),
          Text(
            L.of(context).studyCardsAreNotes,
            style: TextStyle(
                fontSize: 12, height: 1.4, color: context.surfaces.textSecondary),
          ),
        ],
      );

  /// Keys and syntax, the same in every language.
  static const _chordQuestion = 'Ctrl+3';
  static const _chordDefinition = 'Ctrl+5';
  static const _chordCloze = '== ==';

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
    final l = L.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.task_alt,
                size: OnoteIcon.xl, color: OnoteColors.success),
            const SizedBox(height: 10),
            Text(l.studyReviewedCards(done),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              _missed.isEmpty
                  ? (stats.due > 0
                      ? l.studyStillDue('${stats.due}')
                      : stats.nextDueAt == null
                          ? l.studyNothingElseDue
                          : l.studyNextCardIn(
                              delayIn(l, stats.nextDueAt! - nowMs())))
                  : l.studyNeedAnotherLook(_missed.length),
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
                Text(
                    l.studyStreak('${app.study.studyStreakDays()}',
                        '${app.study.reviewsToday()}'),
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
                    ? l.studyExamTodayDot
                    : p.unseen > 0
                        ? l.studyUntilExamUnseen(
                            countdownIn(l, p.daysLeft), '${p.unseen}')
                        : l.studyUntilExam(countdownIn(l, p.daysLeft)),
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
                label: Text(l.studyReviewAgain(_missed.length)),
              )
            else if (stats.due > 0)
              FilledButton.icon(
                onPressed: () => _start(StudyMode.due),
                icon: const Icon(Icons.play_arrow, size: 18),
                label: Text(l.studyKeepGoing('${stats.due}')),
              ),
            const SizedBox(height: 8),
            OutlinedButton(
                onPressed: _end,
                child: Text(l.commonDone, style: const TextStyle(fontSize: 13))),
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
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : _index / total,
              minHeight: 3,
              backgroundColor:
                  context.surfaces.border,
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Text(L.of(context).studyNOfM('${_index + 1}', '$total'),
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
              Text(L.of(context).studyPracticeBadge,
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
                  child: Text('${L.of(context).studyShowAnswer}   ␣'),
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
    final l = L.of(context);
    final label =
        c.isCloze ? l.studyFillBlank : kind.label(l).toUpperCase();
    return Container(
      decoration: BoxDecoration(
        color: context.surfaces.raised,
        border: Border.all(
            color: context.surfaces.border),
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
                tooltip: L.of(context).studyOpenNote,
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
    // Through the shared inline renderer, never a bare string: a question
    // like `What is $\frac{d}{dx}x^2$?` used to show its raw backslashes on
    // the one screen built for remembering it (open finding, v0.18 §13.6).
    if (!c.isCloze) {
      return SelectableText.rich(
          TextSpan(children: inlineSpans(c.front, style, dark)),
          style: style);
    }
    final parts = c.front.split('[…]');
    return SelectableText.rich(TextSpan(children: [
      for (var i = 0; i < parts.length; i++) ...[
        TextSpan(children: inlineSpans(parts[i], style, dark)),
        if (i < parts.length - 1)
          TextSpan(
            // The revealed answer goes through the renderer too — a blanked
            // formula must drop back into the sentence as maths, not source.
            // The unrevealed blank keeps its literal en-spaces: only its
            // underline is meant to show.
            children: _revealed
                ? inlineSpans(c.back, style.copyWith(color: kind.color), dark)
                : const [
                    TextSpan(text: '      ')
                  ],
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
              color: (context.surfaces.border)),
        ),
        child: Text(L.of(context).studyAnswerHidden,
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
          Text(L.of(context).studyAnswer,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .7,
                  color: kind.color)),
          const SizedBox(height: 6),
          // The answer is where the maths usually lives — `$E=mc^2$` shown
          // as backslashes here is the flashcard defect this panel had.
          SelectableText.rich(
              TextSpan(
                  children: inlineSpans(
                      c.back,
                      const TextStyle(fontSize: 13, height: 1.45),
                      dark)),
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
        Text(g.labelIn(L.of(context)),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        Text(
          _mode == StudyMode.cram && g != Grade.again
              ? '—'
              : delayIn(L.of(context), previewDelayMs(state, g, now)),
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
