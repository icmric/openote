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
import '../core/platform_open.dart';
import '../planner/agenda.dart';
import '../planner/alerts.dart';
import '../planner/event_kinds.dart';
import '../planner/ics.dart';
import '../state/app_state.dart';
import '../state/planner_state.dart';
import '../theme/onote_theme.dart';
import 'event_alert_dialog.dart';
import 'exam_date.dart';
import 'month_grid.dart';
import 'side_panel.dart';
import 'planner_format.dart';
import '../theme/tokens.dart';
import 'onote_dialog.dart';

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
    final now = DateTime.now();
    final sections = planner.sections(now: now);

    return SidePanel(
      title: SidePanelKind.planner.label,
      icon: Icons.event_note_outlined,
      onClose: app.closePanel,
      actions: [
        IconButton(
          icon: Icon(
              _showMonth
                  ? Icons.calendar_view_day_outlined
                  : Icons.calendar_month_outlined,
              size: OnoteIcon.sm),
          visualDensity: VisualDensity.compact,
          tooltip: _showMonth ? 'Show the list' : 'Show the month',
          onPressed: () => setState(() {
            _showMonth = !_showMonth;
            if (!_showMonth) _pickedDay = null;
          }),
        ),
      ],
      // The alerts sit in the banner slot, above the scroll region, because a
      // reminder you have to scroll to find has not reminded you.
      banner: planner.pendingAlerts.isNotEmpty ? _alerts(context) : null,
      footer: _footer(context, now),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // "What have I got on" answered before the list is read, which is
          // the whole point of subscribing to a timetable. Costs nothing when
          // there is no subscription — it renders nothing.
          _UpNext(app: app, now: now),
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
        ],
      ),
    );
  }

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
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.primary.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.notifications_active_outlined,
                size: 16, color: scheme.primary),
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
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.done_all, size: 16),
              visualDensity: VisualDensity.compact,
              tooltip: 'Done with all of these',
              // **Dismisses, rather than merely hiding.** This button used to
              // call `clearAlerts`, which emptied the on-screen list and left
              // every reminder live — so the badge stayed lit, the row stayed
              // in the agenda below, and the button read as broken.
              onPressed: planner.dismissAllAlerts,
            ),
          ]),
          for (final r in alerts)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 4),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text('${r.title}  ·  ${formatClock(r.at)}',
                      style: const TextStyle(fontSize: 12, height: 1.35)),
                ),
                if (r.source == AlertSource.reminder)
                  _SnoozeButton(
                    // Measured from now, not from the reminder's own time —
                    // snoozing something that came due yesterday "by ten
                    // minutes" must land ten minutes from now, or it fires
                    // again on the next tick and Snooze appears broken.
                    onSnooze: (d) => planner.snoozeAlert(r.id, d),
                  ),
                IconButton(
                  icon: const Icon(Icons.done, size: 16),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                      minWidth: OnoteSize.hitTarget,
                      minHeight: OnoteSize.hitTarget),
                  tooltip: 'Done',
                  onPressed: () => planner.dismissAlert(r.id),
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
                style: TextStyle(
                    fontSize: 11, color: context.surfaces.textSecondary)),
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
                      fontSize: 11,
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
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .6,
                    color: context.surfaces.textSecondary)),
            const Spacer(),
            InkWell(
              onTap: () => setState(() => _pickedDay = null),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text('Show all',
                    style: TextStyle(fontSize: 11, color: context.surfaces.textSecondary)),
              ),
            ),
          ]),
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Text('Nothing on this day.',
                style: TextStyle(fontSize: 12, color: context.surfaces.textSecondary)),
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
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: .6,
                color: bucket == AgendaBucket.overdue
                    ? OnoteColors.danger
                    : context.surfaces.textSecondary)),
        // The date, once, beside TODAY — the one heading where knowing the
        // actual date is worth the pixels.
        if (isToday) ...[
          const Spacer(),
          Text(formatDayFull(now),
              style: TextStyle(
                  fontSize: 11, color: context.surfaces.textSecondary)),
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
                        fontSize: 13,
                        height: 1.3,
                        decoration:
                            it.done ? TextDecoration.lineThrough : null,
                        color: it.done ? context.surfaces.textSecondary : null)),
                if (it.subtitle case final s?)
                  Text(s,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, color: context.surfaces.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(plannerWhen(it, now),
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: overdue ? FontWeight.w700 : FontWeight.w400,
                    color: overdue ? OnoteColors.danger : scheme.primary)),
          ),
          // A visible way to be finished with a reminder.
          //
          // Delete has always been on the right-click menu, and that was not
          // enough: nobody right-clicks a list they have just been shown, so
          // the honest report was "there is no way to dismiss one". A task has
          // its checkbox and an exam has a date you can clear from the section
          // it belongs to; a reminder had neither, which made it the one row
          // type you could not get rid of without knowing a secret.
          if (it.kind == DatedKind.reminder)
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: IconButton(
                icon: const Icon(Icons.check, size: OnoteIcon.sm),
                tooltip: 'Done with this reminder',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                    minWidth: OnoteSize.hitTarget,
                    minHeight: OnoteSize.hitTarget),
                onPressed: () {
                  final id = PlannerState.reminderIdOf(it);
                  if (id != null) planner.reminders.dismiss(id);
                },
              ),
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
      DatedKind.event => (Icons.schedule, context.surfaces.textSecondary),
      DatedKind.task => (Icons.check_box_outline_blank, context.surfaces.textSecondary),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 1),
      child: Icon(icon, size: 16, color: colour),
    );
  }

  Widget _empty(BuildContext context, DateTime now) => PanelEmpty(
        headline: 'Nothing dated yet.',
        body: 'Everything with a date shows up here — exam dates, to-dos you '
            'give a deadline, reminders, and your timetable if you subscribe '
            'to one.',
        actions: [
          PanelAction(
              icon: Icons.flag_outlined,
              label: 'Set an exam date',
              onTap: _addExam),
          PanelAction(
              icon: Icons.notifications_none,
              label: 'Add a reminder',
              onTap: () => _addReminder(now)),
          PanelAction(
              icon: Icons.calendar_month_outlined,
              label: 'Subscribe to a timetable',
              onTap: _subscribe),
        ],
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
              Icon(Icons.add, size: 16),
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
                : const Icon(Icons.sync, size: 16),
            visualDensity: VisualDensity.compact,
            tooltip: _calendarTooltip(sub, now),
            onPressed:
                planner.isRefreshingCalendar ? null : planner.refreshCalendar,
          ),
        PopupMenuButton<String>(
          tooltip: 'Planner settings',
          icon: const Icon(Icons.tune, size: 16),
          iconSize: 15,
          position: PopupMenuPosition.over,
          onSelected: _onSettings,
          itemBuilder: (_) => [
            PopupMenuItem(
                value: 'ics',
                child: Text(planner.calendar == null
                    ? 'Subscribe to a timetable…'
                    : 'Change the timetable…')),
            if (planner.calendar != null) ...[
              const PopupMenuItem(
                  value: 'alerts', child: Text('Alerts before classes…')),
              const PopupMenuItem(
                  value: 'unsub', child: Text('Remove the timetable')),
            ],
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
                style: TextStyle(fontSize: 12)),
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
      case 'alerts':
        await showEventAlertDialog(context, app);
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
    // The shared picker, so the planner, the navigator and the study panel all
    // offer the same thing — including the optional start time, which the
    // hand-rolled `_pickDay` here could not.
    await pickExamDate(context, app, chosen.id);
  }

  Future<TreeNode?> _pickSection(List<TreeNode> sections) =>
      showOnoteDialog<TreeNode>(
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
                        size: 16, color: OnoteColors.brass500),
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
    final chosen = await showOnoteDialog<TaggedLine>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Give which line a deadline?',
            style: TextStyle(fontSize: 15)),
        children: [
          for (final t in candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, t),
              child: Row(children: [
                Icon(t.tag.kind.icon, size: 16, color: t.tag.kind.color),
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
    final r = await showOnoteDialog<({String text, DateTime at})>(
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
    final url = await showOnoteDialog<String>(
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

  Future<void> _showWarnings() => showOnoteDialog<void>(
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
                          style: const TextStyle(fontSize: 12, height: 1.4)),
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
        icon: const Icon(Icons.snooze, size: 16),
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
    // Enter in the field IS the "Remind me" button. The field is
    // autofocused, so typing the reminder and pressing Enter is what anyone
    // will try first; without this it did nothing at all and the only way
    // out was to find the button with the mouse (phase-3 audit). Empty text
    // does nothing, the same rule that greys the button out.
    void submit() {
      final t = _text.text.trim();
      if (t.isEmpty) return;
      Navigator.pop(context, (text: t, at: _at));
    }

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
              onSubmitted: (_) => submit(),
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
                icon: const Icon(Icons.event, size: 16),
                label: Text(relativeWhen(when, widget.now),
                    style: const TextStyle(fontSize: 12)),
                onPressed: _pickDate,
              ),
              TextButton.icon(
                icon: const Icon(Icons.schedule, size: 16),
                label: Text(formatClock(_at),
                    style: const TextStyle(fontSize: 12)),
                onPressed: _pickTime,
              ),
            ]),
            const SizedBox(height: 4),
            // Said plainly rather than buried in a help page: a reminder a
            // student wrongly believes will interrupt them is worse than no
            // reminder at all (v0.5 §1).
            Text(
              'Openote nudges you while it is open. If it was closed when the '
              'time came, the reminder is waiting when you next open it.',
              style: TextStyle(fontSize: 11, height: 1.4,
                  color: context.surfaces.textSecondary),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _text.text.trim().isEmpty ? null : submit,
          child: const Text('Remind me'),
        ),
      ],
    );
  }

  Widget _chip(String label, VoidCallback tap) => ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
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
                style: const TextStyle(fontSize: 13),
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
              Text(
                'Read-only, one direction: Openote shows your timetable beside '
                'your notes and never writes anything back to it.',
                style: TextStyle(
                    fontSize: 11, height: 1.4, color: context.surfaces.textSecondary),
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

/// The "up next" strip (v0.8 §2).
///
/// **Why this earns the top of the panel.** The agenda answers "what have I
/// got on"; it does not answer *"what do I do in the next ten minutes"*, which
/// is the question a timetable is actually subscribed to for. That answer is one
/// row long and it changes every hour, so it belongs pinned above the list
/// rather than found by scrolling to today.
///
/// Renders nothing at all without a subscription — a permanent empty box saying
/// "no upcoming events" would be chrome charging rent.
class _UpNext extends StatelessWidget {
  const _UpNext({required this.app, required this.now});

  final AppState app;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final planner = app.planner;
    if (planner.calendar == null) return const SizedBox.shrink();
    final current = planner.currentEvent(now: now);
    final next = planner.nextEvent(now: now);
    if (current == null && next == null) return const SizedBox.shrink();

    final s = context.surfaces;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
          OnoteSpace.x5, OnoteSpace.x4, OnoteSpace.x4, OnoteSpace.x4),
      decoration: BoxDecoration(
        color: s.chrome2,
        border: Border(bottom: BorderSide(color: s.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (current != null)
            _EventLine(label: 'Now', event: current, now: now, emphasis: true),
          if (current != null && next != null)
            const SizedBox(height: OnoteSpace.x3),
          if (next != null)
            _EventLine(
                label: current == null ? 'Next' : 'Then',
                event: next,
                now: now,
                emphasis: current == null),
        ],
      ),
    );
  }
}

class _EventLine extends StatelessWidget {
  const _EventLine({
    required this.label,
    required this.event,
    required this.now,
    required this.emphasis,
  });

  final String label;
  final IcsEvent event;
  final DateTime now;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final scheme = Theme.of(context).colorScheme;
    final kind = classifyEvent(event);
    final join = joinLink(event);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 34,
        child: Text(label,
            style: OnoteType.overline.copyWith(
                color: emphasis ? scheme.primary : s.textSecondary)),
      ),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              event.summary.isEmpty ? '(untitled event)' : event.summary,
              style: (emphasis ? OnoteType.uiStrong : OnoteType.ui)
                  .copyWith(color: s.textPrimary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Text(_detail(kind),
                style: OnoteType.caption.copyWith(color: s.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
      // The Join button is the payoff. A lecture row that tells you the link
      // exists but makes you hunt for it in the description has done the hard
      // half of the job and skipped the useful half.
      if (join != null)
        Padding(
          padding: const EdgeInsets.only(left: OnoteSpace.x3),
          child: Tooltip(
            message: join.url,
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding:
                    const EdgeInsets.symmetric(horizontal: OnoteSpace.x4),
                minimumSize: const Size(0, OnoteSize.buttonCompact),
                textStyle: OnoteType.small,
              ),
              onPressed: () => _join(context, join),
              child: Text('Join ${join.provider}'),
            ),
          ),
        ),
    ]);
  }

  String _detail(EventKind kind) {
    final parts = <String>[];
    final mins = event.start.difference(now).inMinutes;
    if (mins > 0) {
      parts.add(mins < 60
          ? 'in $mins min'
          : 'at ${formatClock(event.start)}');
    } else if (event.end != null) {
      parts.add('until ${formatClock(event.end!)}');
    } else {
      parts.add(formatClock(event.start));
    }
    if (kind != EventKind.other) parts.add(kind.label);
    if (event.location.isNotEmpty) parts.add(event.location);
    return parts.join(' · ');
  }

  Future<void> _join(BuildContext context, JoinLink join) async {
    final ok = await PlatformOpen.url(join.url);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't open that link: ${join.url}")));
    }
  }
}
