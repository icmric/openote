/// The Planner: one place where every date you have lives (v0.5 §3).
///
/// **The complaint this answers.** The exam countdown worked, but managing it
/// did not: a date was set from two different context menus and was then
/// visible only inside the study panel, on whichever section you had open.
/// There was no way to ask *"what dates do I have at all"*. So the fix is not
/// a better date picker — it is a surface where every dated thing is listed,
/// and where each one can be re-dated or cleared without hunting for the menu
/// that created it.
///
/// **Four streams, one list.** Exams, dated to-dos, reminders and a subscribed
/// timetable are stored in four different places for four good reasons (see
/// `planner_state.dart`), and a student does not care about any of them. They
/// arrive here flattened into rows that all behave the same way: click to go
/// there, right-click to re-date.
///
/// **Every state offers a next action** — the rule the study panel was rebuilt
/// around, and the same reasoning applies. "Nothing today" with no way to add
/// anything is a dead end that reads as broken.
library;

import 'package:flutter/material.dart';

import '../model/models.dart';
import '../planner/agenda.dart';
import '../state/app_state.dart';
import '../state/planner_state.dart';
import '../theme/onote_theme.dart';
import 'month_grid.dart';
import 'planner_format.dart';

class PlannerPanel extends StatefulWidget {
  const PlannerPanel({super.key, required this.app});
  final AppState app;

  @override
  State<PlannerPanel> createState() => _PlannerPanelState();
}

class _PlannerPanelState extends State<PlannerPanel> {
  AppState get app => widget.app;
  PlannerState get planner => app.planner;

  /// The month grid is **off by default** and remembered per session.
  ///
  /// v0.5 §4 is explicit that a grid is presentation and the agenda is what a
  /// student reads daily. Opening on the calendar would put the layout first
  /// and the answer second.
  bool _showMonth = false;

  /// Which day the grid has selected, if any. Null means "no day picked" and
  /// the agenda below shows everything.
  DateTime? _pickedDay;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final sections = planner.sections(now: now);

    return Container(
      width: 320,
      color: dark ? OnoteColors.night0 : OnoteColors.paper50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context, now),
          if (planner.pendingAlerts.isNotEmpty) _alerts(context),
          if (_showMonth) ...[
            MonthGrid(
              planner: planner,
              now: now,
              selected: _pickedDay,
              onPick: (d) => setState(() => _pickedDay =
                  _pickedDay != null && daysEqual(_pickedDay!, d) ? null : d),
            ),
            const Divider(height: 1),
          ],
          Expanded(
            child: _pickedDay != null
                ? _dayList(context, _pickedDay!, now)
                : _agendaList(context, sections, now),
          ),
          const Divider(height: 1),
          _footer(context, now),
        ],
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────

  Widget _header(BuildContext context, DateTime now) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
        child: Row(children: [
          const Icon(Icons.event_note_outlined,
              size: 14, color: OnoteColors.graphite400),
          const SizedBox(width: 6),
          const Text('PLANNER',
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .6,
                  color: OnoteColors.graphite400)),
          const Spacer(),
          IconButton(
            icon: Icon(
                _showMonth
                    ? Icons.calendar_view_day_outlined
                    : Icons.calendar_month_outlined,
                size: 15),
            visualDensity: VisualDensity.compact,
            tooltip: _showMonth ? 'Show the list' : 'Show the month',
            onPressed: () => setState(() {
              _showMonth = !_showMonth;
              if (!_showMonth) _pickedDay = null;
            }),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 15),
            visualDensity: VisualDensity.compact,
            tooltip: 'Close planner',
            onPressed: app.togglePlannerPanel,
          ),
        ]),
      );

  // ── The catch-up list (v0.5 §1) ──────────────────────────────────────
  //
  // A desktop app that is not running cannot interrupt you. Pretending
  // otherwise is the worst outcome — a student who trusts a reminder that never
  // arrives is worse off than one who never set it — so a reminder that came
  // due while Openote was closed is a first-class state, said out loud.

  Widget _alerts(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final alerts = planner.pendingAlerts;
    final away = planner.alertsWereMissed;
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: scheme.primary.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.notifications_active_outlined,
                size: 14, color: scheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                away
                    ? '${alerts.length} reminder${alerts.length == 1 ? '' : 's'} '
                        'while you were away'
                    : alerts.length == 1
                        ? 'Reminder'
                        : '${alerts.length} reminders',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.done, size: 15),
              visualDensity: VisualDensity.compact,
              tooltip: 'Dismiss',
              onPressed: planner.clearAlerts,
            ),
          ]),
          for (final r in alerts)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text('${r.text}  ·  ${formatClock(r.at)}',
                      style: const TextStyle(fontSize: 12, height: 1.35)),
                ),
                _SnoozeButton(
                  // Measured from now, not from the reminder's own time —
                  // snoozing something that came due yesterday "by ten
                  // minutes" must land ten minutes from now, or it fires again
                  // on the next tick and the Snooze button appears broken.
                  onSnooze: (d) =>
                      planner.reminders.snooze(r.id, d, DateTime.now()),
                ),
              ]),
            ),
        ],
      ),
    );
  }

  // ── The agenda ───────────────────────────────────────────────────────

  Widget _agendaList(
      BuildContext context, List<AgendaSection> sections, DateTime now) {
    if (sections.isEmpty) return _empty(context, now);
    return ListView(
      padding: const EdgeInsets.only(bottom: 10),
      children: [
        for (final s in sections) ...[
          _sectionHeader(s.bucket, now),
          for (final it in s.items) _row(context, it, now),
        ],
        if (planner.calendar?.lastError case final err?)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Text('Timetable: $err. Showing the last copy.',
                style: const TextStyle(
                    fontSize: 10.5, color: OnoteColors.graphite400)),
          ),
        // Surfaced rather than buried in a menu. A lecture shown at the wrong
        // hour, or a monthly seminar appearing once, is the kind of thing a
        // student would otherwise conclude was a bug in Openote — and the
        // parser already knows exactly what it could not read.
        if (planner.calendarWarnings.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: InkWell(
              onTap: _showWarnings,
              child: Text(
                  '${planner.calendarWarnings.length} note'
                  '${planner.calendarWarnings.length == 1 ? '' : 's'} about '
                  'this calendar',
                  style: TextStyle(
                      fontSize: 10.5,
                      color: Theme.of(context).colorScheme.primary)),
            ),
          ),
      ],
    );
  }

  Widget _dayList(BuildContext context, DateTime day, DateTime now) {
    final items = planner.itemsOn(day, now: now);
    return ListView(
      padding: const EdgeInsets.only(bottom: 10),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
          child: Row(children: [
            Text(formatDayFull(day),
                style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .6,
                    color: OnoteColors.graphite400)),
            const Spacer(),
            InkWell(
              onTap: () => setState(() => _pickedDay = null),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text('Show all',
                    style: TextStyle(fontSize: 10.5, color: OnoteColors.graphite400)),
              ),
            ),
          ]),
        ),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Text('Nothing on this day.',
                style: TextStyle(fontSize: 11.5, color: OnoteColors.graphite400)),
          )
        else
          for (final it in items) _row(context, it, now),
      ],
    );
  }

  Widget _sectionHeader(AgendaBucket bucket, DateTime now) {
    final isToday = bucket == AgendaBucket.today;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 3),
      child: Row(children: [
        Text(bucket.title.toUpperCase(),
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: .6,
                color: bucket == AgendaBucket.overdue
                    ? OnoteColors.danger
                    : OnoteColors.graphite400)),
        // The date, once, beside TODAY — the one heading where knowing the
        // actual date is worth the pixels.
        if (isToday) ...[
          const Spacer(),
          Text(formatDayFull(now),
              style: const TextStyle(
                  fontSize: 10.5, color: OnoteColors.graphite400)),
        ],
      ]),
    );
  }

  Widget _row(BuildContext context, DatedItem it, DateTime now) {
    final scheme = Theme.of(context).colorScheme;
    final overdue = bucketFor(it, now) == AgendaBucket.overdue;
    return InkWell(
      onTap: () => _open(it),
      onSecondaryTapDown: (d) => _rowMenu(it, d.globalPosition, now),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 5, 10, 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _leading(it),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(it.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.3,
                        decoration:
                            it.done ? TextDecoration.lineThrough : null,
                        color: it.done ? OnoteColors.graphite400 : null)),
                if (it.subtitle case final s?)
                  Text(s,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 10.5, color: OnoteColors.graphite400)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(plannerWhen(it, now),
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: overdue ? FontWeight.w700 : FontWeight.w400,
                    color: overdue ? OnoteColors.danger : scheme.primary)),
          ),
        ]),
      ),
    );
  }

  /// The leading control: a real checkbox for a task (ticking it here must tick
  /// it in the note — the agenda is a lens, so there is only one truth), an
  /// icon for everything else.
  Widget _leading(DatedItem it) {
    if (it.kind == DatedKind.task) {
      return SizedBox(
        width: 16,
        height: 18,
        child: Checkbox(
          value: it.done,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          // Ticks in place, on whatever page the task lives on. Navigating
          // there first would yank the reader away for a checkbox — and worse,
          // `selectPage` reloads the block list, so the tick made in the same
          // turn was discarded by the load that followed it.
          onChanged: (v) {
            if (it.pageId == null || it.blockId == null || it.line == null) {
              return;
            }
            app.setTagCheckedOn(
                it.pageId!, it.blockId!, it.line!, v ?? false);
          },
        ),
      );
    }
    final (icon, colour) = switch (it.kind) {
      DatedKind.exam => (Icons.flag_outlined, OnoteColors.brass500),
      DatedKind.reminder => (Icons.notifications_none, OnoteColors.ink500),
      DatedKind.event => (Icons.schedule, OnoteColors.graphite400),
      DatedKind.task => (Icons.check_box_outline_blank, OnoteColors.graphite400),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 1),
      child: Icon(icon, size: 14, color: colour),
    );
  }

  Widget _empty(BuildContext context, DateTime now) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Nothing dated yet.',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text(
              'Everything with a date shows up here — exam dates, to-dos you '
              'give a deadline, reminders, and your timetable if you subscribe '
              'to one.',
              style: TextStyle(fontSize: 11.5, height: 1.45),
            ),
            const SizedBox(height: 12),
            _link(context, Icons.flag_outlined, 'Set an exam date', _addExam),
            _link(context, Icons.notifications_none, 'Add a reminder',
                () => _addReminder(now)),
            _link(context, Icons.calendar_month_outlined,
                'Subscribe to a timetable', _subscribe),
          ],
        ),
      );

  Widget _link(
          BuildContext context, IconData icon, String label, VoidCallback tap) =>
      InkWell(
        onTap: tap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Icon(icon, size: 14, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 7),
            // Expanded, not bare: 'Subscribe to a timetable' overflows a 320px
            // panel by 23px otherwise, and an unconstrained Text in a Row is
            // the exact shape of the two layout bugs that shipped in the
            // command bar.
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary)),
            ),
          ]),
        ),
      );

  // ── Footer ───────────────────────────────────────────────────────────

  Widget _footer(BuildContext context, DateTime now) {
    final sub = planner.calendar;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
      child: Row(children: [
        // A PopupMenuButton rather than a bare `showMenu`: it anchors to its
        // own render box, where a hand-rolled position computed from the
        // panel's context would drop the menu at the panel's corner instead.
        PopupMenuButton<String>(
          tooltip: 'Add a date',
          position: PopupMenuPosition.over,
          onSelected: (v) => _onAdd(v, now),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'reminder', child: Text('Reminder…')),
            PopupMenuItem(value: 'exam', child: Text('Exam date…')),
            PopupMenuItem(value: 'task', child: Text('Due date on this page…')),
            PopupMenuDivider(),
            PopupMenuItem(value: 'ics', child: Text('Subscribe to a timetable…')),
          ],
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.add, size: 15),
              SizedBox(width: 5),
              Text('Add a date…', style: TextStyle(fontSize: 12)),
            ]),
          ),
        ),
        const Spacer(),
        if (sub != null)
          IconButton(
            icon: planner.isRefreshingCalendar
                ? const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 1.8))
                : const Icon(Icons.sync, size: 15),
            visualDensity: VisualDensity.compact,
            tooltip: _calendarTooltip(sub, now),
            onPressed:
                planner.isRefreshingCalendar ? null : planner.refreshCalendar,
          ),
        PopupMenuButton<String>(
          tooltip: 'Planner settings',
          icon: const Icon(Icons.tune, size: 15),
          iconSize: 15,
          position: PopupMenuPosition.over,
          onSelected: _onSettings,
          itemBuilder: (_) => [
            PopupMenuItem(
                value: 'ics',
                child: Text(planner.calendar == null
                    ? 'Subscribe to a timetable…'
                    : 'Change the timetable…')),
            if (planner.calendar != null)
              const PopupMenuItem(
                  value: 'unsub', child: Text('Remove the timetable')),
            if (planner.calendarWarnings.isNotEmpty)
              const PopupMenuItem(
                  value: 'warnings',
                  child: Text('Notes about this calendar…')),
          ],
        ),
      ]),
    );
  }

  String _calendarTooltip(CalendarSubscription sub, DateTime now) {
    final name = sub.name.isEmpty ? 'Timetable' : sub.name;
    if (sub.lastError != null) return '$name — ${sub.lastError}. Refresh';
    final at = sub.fetchedAt;
    if (at == null) return 'Refresh $name';
    return 'Refresh $name (updated ${relativeWhen(DatedItem(
      id: '',
      kind: DatedKind.event,
      title: '',
      when: at,
      allDay: false,
    ), now)})';
  }

  // ── Actions ──────────────────────────────────────────────────────────

  void _open(DatedItem it) {
    if (it.pageId != null) {
      app.selectPage(it.pageId!);
      return;
    }
    final section = PlannerState.examSectionOf(it);
    if (section != null) app.activateSection(section);
  }

  /// The row's context menu. Anchored on the tap point, so it opens where the
  /// pointer is rather than where the panel is.
  ///
  /// Uses the State's own `context` throughout — paired with `mounted`, which
  /// is the State's flag. Passing a captured `BuildContext` across the await
  /// and then checking `mounted` checks the wrong thing.
  Future<void> _rowMenu(DatedItem it, Offset at, DateTime now) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
          at & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        if (it.pageId != null)
          const PopupMenuItem(value: 'open', child: Text('Go to the note')),
        if (planner.canRedate(it)) ...[
          const PopupMenuItem(value: 'today', child: Text('Move to today')),
          const PopupMenuItem(
              value: 'tomorrow', child: Text('Move to tomorrow')),
          const PopupMenuItem(value: 'week', child: Text('Move on a week')),
          const PopupMenuItem(value: 'pick', child: Text('Pick a date…')),
          const PopupMenuDivider(),
          PopupMenuItem(
              value: 'clear',
              child: Text(it.kind == DatedKind.reminder
                  ? 'Delete reminder'
                  : 'Clear the date')),
        ] else
          // Said, not hidden. A calendar row with no menu at all reads as a
          // bug; a menu that explains why it cannot be edited is the answer to
          // "Openote never writes to anyone's calendar".
          const PopupMenuItem(
            enabled: false,
            child: Text('From your calendar — read-only',
                style: TextStyle(fontSize: 11.5)),
          ),
      ],
    );
    if (choice == null || !mounted) return;
    final today = DateTime(now.year, now.month, now.day);
    switch (choice) {
      case 'open':
        _open(it);
      case 'today':
        planner.redate(it, today);
      case 'tomorrow':
        planner.redate(it, DateTime(today.year, today.month, today.day + 1));
      case 'week':
        // A week from where it IS, not from today: "move on a week" about
        // something due next Friday means the Friday after.
        planner.redate(
            it, DateTime(it.when.year, it.when.month, it.when.day + 7));
      case 'pick':
        final d = await _pickDay(initial: it.when, now: now);
        if (d != null) planner.redate(it, d);
      case 'clear':
        planner.redate(it, null);
    }
  }

  Future<void> _onAdd(String choice, DateTime now) async {
    switch (choice) {
      case 'reminder':
        await _addReminder(now);
      case 'exam':
        await _addExam();
      case 'task':
        await _dateATask(now);
      case 'ics':
        await _subscribe();
    }
  }

  Future<void> _onSettings(String choice) async {
    switch (choice) {
      case 'ics':
        await _subscribe();
      case 'unsub':
        planner.unsubscribeCalendar();
      case 'warnings':
        await _showWarnings();
    }
  }

  Future<void> _addExam() async {
    final sections = [
      for (final n in app.nodes)
        if (n.kind == NodeKind.section) n
    ];
    if (sections.isEmpty) return;
    final chosen = sections.length == 1
        ? sections.single
        : await _pickSection(sections);
    if (chosen == null || !mounted) return;
    final now = DateTime.now();
    final d = await _pickDay(
        initial: app.study.examDate(chosen.id) ??
            DateTime(now.year, now.month, now.day + 14),
        now: now,
        help: 'Exam date — ${chosen.title}');
    if (d == null) return;
    app.study.setExamDate(chosen.id, d);
  }

  Future<TreeNode?> _pickSection(List<TreeNode> sections) =>
      showDialog<TreeNode>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Which section?', style: TextStyle(fontSize: 15)),
          children: [
            for (final s in sections)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, s),
                child: Row(children: [
                  Expanded(
                      child: Text(s.title.isEmpty ? 'Untitled' : s.title,
                          style: const TextStyle(fontSize: 13))),
                  if (app.study.examDate(s.id) != null)
                    const Icon(Icons.flag_outlined,
                        size: 13, color: OnoteColors.brass500),
                ]),
              ),
          ],
        ),
      );

  /// Put a due date on a to-do that is already on the open page.
  ///
  /// Deliberately does **not** create a task. v0.5 §6: no task that isn't in
  /// your notes — a dated item is a view of something you wrote. This offers
  /// the lines you have already tagged and dates one of them.
  Future<void> _dateATask(DateTime now) async {
    final candidates = [
      for (final t in app.allTags())
        if (t.pageId == app.pageId && t.tag.due == null) t
    ];
    if (candidates.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Tag a line on this page first — then it can have a '
              'due date.')));
      return;
    }
    final chosen = await showDialog<TaggedLine>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Give which line a deadline?',
            style: TextStyle(fontSize: 15)),
        children: [
          for (final t in candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, t),
              child: Row(children: [
                Icon(t.tag.kind.icon, size: 13, color: t.tag.kind.color),
                const SizedBox(width: 7),
                Expanded(
                    child: Text(t.text.isEmpty ? '(empty line)' : t.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13))),
              ]),
            ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;
    final d = await _pickDay(
        initial: DateTime(now.year, now.month, now.day + 7),
        now: now,
        help: 'Due date');
    if (d == null) return;
    app.setTagDue(chosen.blockId, chosen.tag.line, chosen.tag.kind, d,
        pageId: chosen.pageId);
  }

  Future<void> _addReminder(DateTime now) async {
    final r = await showDialog<({String text, DateTime at})>(
      context: context,
      builder: (ctx) => _ReminderDialog(now: now),
    );
    if (r == null || !mounted) return;
    final page = app.nodes.where((n) => n.id == app.pageId).firstOrNull;
    // Attached to the open page when there is one, free-standing when there
    // isn't. v0.5 §7 left that an open decision; allowing it is the resolution,
    // because "call the tutor at 3" belongs to no page and refusing it means
    // the student simply loses the reminder rather than filing it better.
    planner.reminders.add(
      text: r.text,
      at: r.at,
      notebookId: app.notebookId,
      pageId: page?.id,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Reminder set for ${formatClock(r.at)} '
            '${relativeWhen(DatedItem(id: '', kind: DatedKind.reminder, title: '', when: r.at, allDay: true), now)}. '
            'Openote will nudge you if it is open — and tell you if it wasn’t.')));
  }

  Future<void> _subscribe() async {
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => _CalendarDialog(existing: planner.calendar?.url),
    );
    if (url == null || !mounted) return;
    await planner.subscribeCalendar(url);
    if (!mounted) return;
    final err = planner.calendar?.lastError;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err == null
            ? 'Timetable added. It refreshes when Openote opens.'
            : 'Could not load that calendar: $err')));
  }

  Future<void> _showWarnings() => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('About this calendar',
              style: TextStyle(fontSize: 15)),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                      'Openote reads the common parts of a calendar file. '
                      'Anything it could not read — or could not read exactly '
                      '— is listed here rather than dropped silently. Times '
                      'are shown in your computer’s time zone.',
                      style: TextStyle(fontSize: 12, height: 1.45)),
                  const SizedBox(height: 10),
                  for (final w in planner.calendarWarnings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text('· $w',
                          style: const TextStyle(fontSize: 11.5, height: 1.4)),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ],
        ),
      );

  Future<DateTime?> _pickDay(
      {required DateTime initial, required DateTime now, String? help}) {
    // A date already past cannot be the picker's opening date — `showDatePicker`
    // asserts when the initial date precedes the first one — but the planner
    // must be able to re-date something overdue, so the FIRST date reaches back
    // rather than the initial one jumping forward.
    final first = DateTime(now.year, now.month, now.day - 365);
    return showDatePicker(
      context: context,
      initialDate: initial.isBefore(first) ? first : initial,
      firstDate: first,
      lastDate: DateTime(now.year + 5, now.month, now.day),
      helpText: help ?? 'Pick a date',
      confirmText: 'Set',
    );
  }
}

/// Snooze, offered on the alert itself.
///
/// A nudge you cannot postpone is one you dismiss and forget, which is the
/// failure mode that makes people turn reminders off.
class _SnoozeButton extends StatelessWidget {
  const _SnoozeButton({required this.onSnooze});
  final void Function(Duration) onSnooze;

  @override
  Widget build(BuildContext context) => PopupMenuButton<int>(
        tooltip: 'Snooze',
        padding: EdgeInsets.zero,
        iconSize: 14,
        icon: const Icon(Icons.snooze, size: 14),
        onSelected: (m) => onSnooze(Duration(minutes: m)),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 10, child: Text('10 minutes')),
          PopupMenuItem(value: 60, child: Text('An hour')),
          PopupMenuItem(value: 60 * 3, child: Text('This evening (3 hours)')),
          PopupMenuItem(value: 60 * 24, child: Text('Tomorrow')),
        ],
      );
}

/// Setting a reminder: what, and when.
///
/// **Relative buttons first, an exact time second.** "In an hour" is what a
/// student actually means when they think "come back to this", and making them
/// compute 15:40 from 14:40 is the friction that stops the thought being
/// captured at all.
class _ReminderDialog extends StatefulWidget {
  const _ReminderDialog({required this.now});
  final DateTime now;

  @override
  State<_ReminderDialog> createState() => _ReminderDialogState();
}

class _ReminderDialogState extends State<_ReminderDialog> {
  final _text = TextEditingController();
  late DateTime _at = _round(widget.now.add(const Duration(hours: 1)));

  /// Snapped to the next five minutes. A reminder at 15:43 is a time nobody
  /// chose; it is an artefact of when the dialog happened to open.
  static DateTime _round(DateTime d) {
    final m = ((d.minute + 4) ~/ 5) * 5;
    return DateTime(d.year, d.month, d.day, d.hour, 0).add(Duration(minutes: m));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _shift(Duration d) => setState(() => _at = _round(widget.now.add(d)));

  /// A preset time of day, rolled to tomorrow when today's has already gone.
  ///
  /// Without the roll, tapping "This evening" at 9pm sets 7pm *today* — a
  /// reminder in the past, which fires the instant you save it. A preset button
  /// promising a time it cannot deliver is worse than not offering it.
  void _setTimeOfDay(int hour, int minute, {int dayOffset = 0}) {
    final d = widget.now;
    var at = DateTime(d.year, d.month, d.day + dayOffset, hour, minute);
    if (!at.isAfter(widget.now)) {
      at = DateTime(at.year, at.month, at.day + 1, hour, minute);
    }
    setState(() => _at = at);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_at));
    if (t == null || !mounted) return;
    setState(() => _at = DateTime(_at.year, _at.month, _at.day, t.hour, t.minute));
  }

  Future<void> _pickDate() async {
    final today = DateTime(widget.now.year, widget.now.month, widget.now.day);
    final d = await showDatePicker(
      context: context,
      initialDate: _at.isBefore(today) ? today : _at,
      firstDate: today,
      lastDate: DateTime(today.year + 5, today.month, today.day),
    );
    if (d == null || !mounted) return;
    setState(() => _at = DateTime(d.year, d.month, d.day, _at.hour, _at.minute));
  }

  @override
  Widget build(BuildContext context) {
    final when = DatedItem(
        id: '',
        kind: DatedKind.reminder,
        title: '',
        when: _at,
        allDay: true);
    return AlertDialog(
      title: const Text('Remind me', style: TextStyle(fontSize: 15)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _text,
              autofocus: true,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Come back to the proof of 2.7',
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 6, runSpacing: 6, children: [
              _chip('In 30 min', () => _shift(const Duration(minutes: 30))),
              _chip('In an hour', () => _shift(const Duration(hours: 1))),
              _chip('This evening', () => _setTimeOfDay(19, 0)),
              _chip('Tomorrow morning',
                  () => _setTimeOfDay(9, 0, dayOffset: 1)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              TextButton.icon(
                icon: const Icon(Icons.event, size: 15),
                label: Text(relativeWhen(when, widget.now),
                    style: const TextStyle(fontSize: 12)),
                onPressed: _pickDate,
              ),
              TextButton.icon(
                icon: const Icon(Icons.schedule, size: 15),
                label: Text(formatClock(_at),
                    style: const TextStyle(fontSize: 12)),
                onPressed: _pickTime,
              ),
            ]),
            const SizedBox(height: 4),
            // Said plainly rather than buried in a help page: a reminder a
            // student wrongly believes will interrupt them is worse than no
            // reminder at all (v0.5 §1).
            const Text(
              'Openote nudges you while it is open. If it was closed when the '
              'time came, the reminder is waiting when you next open it.',
              style: TextStyle(fontSize: 11, height: 1.4,
                  color: OnoteColors.graphite400),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _text.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, (text: _text.text.trim(), at: _at)),
          child: const Text('Remind me'),
        ),
      ],
    );
  }

  Widget _chip(String label, VoidCallback tap) => ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 11.5)),
        visualDensity: VisualDensity.compact,
        onPressed: tap,
      );
}

/// Subscribing to a calendar: one URL, no account.
class _CalendarDialog extends StatefulWidget {
  const _CalendarDialog({this.existing});
  final String? existing;

  @override
  State<_CalendarDialog> createState() => _CalendarDialogState();
}

class _CalendarDialogState extends State<_CalendarDialog> {
  late final _url = TextEditingController(text: widget.existing ?? '');

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Subscribe to a calendar',
            style: TextStyle(fontSize: 15)),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Paste the calendar address from your university timetable, '
                'Google Calendar, Outlook or Apple Calendar. It usually ends '
                'in .ics, and it is the only thing Openote ever sees — there '
                'is no sign-in and no access to your account.',
                style: TextStyle(fontSize: 12, height: 1.45),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _url,
                autofocus: true,
                style: const TextStyle(fontSize: 12.5),
                decoration: const InputDecoration(
                  hintText: 'https://…/timetable.ics',
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (v) => v.trim().isEmpty
                    ? null
                    : Navigator.pop(context, v.trim()),
              ),
              const SizedBox(height: 10),
              const Text(
                'Read-only, one direction: Openote shows your timetable beside '
                'your notes and never writes anything back to it.',
                style: TextStyle(
                    fontSize: 11, height: 1.4, color: OnoteColors.graphite400),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: _url.text.trim().isEmpty
                ? null
                : () => Navigator.pop(context, _url.text.trim()),
            child: const Text('Subscribe'),
          ),
        ],
      );
}
