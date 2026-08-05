/// The month view (v0.5 stage 5) — presentation over the same agenda model.
///
/// **Deliberately second, and deliberately small.** The v0.5 plan is explicit
/// that a grid is a lot of layout before any of the model is exercised, and
/// that an agenda is what a student actually reads daily. So this is not a
/// calendar application: it is a compact month strip that answers "when in the
/// month is that?" and hands the day back to the list below it.
///
/// It therefore shows **dots, not text**. A 320px panel gives each day cell
/// about 40px; a title in that space is two illegible characters. A dot per
/// kind says "something on the 12th, one of them an exam" at a glance, which is
/// the only question a grid this size can honestly answer — and clicking
/// through to the day's real rows answers the rest.
library;

import 'package:flutter/material.dart';

import '../planner/agenda.dart';
import '../state/planner_state.dart';
import '../theme/onote_theme.dart';
import 'planner_format.dart';

class MonthGrid extends StatefulWidget {
  const MonthGrid({
    super.key,
    required this.planner,
    required this.now,
    required this.onPick,
    this.selected,
  });

  final PlannerState planner;

  /// Today. Passed in rather than read from the clock so the grid can be tested
  /// on any date — the same rule the whole planner is built on.
  final DateTime now;

  final DateTime? selected;
  final void Function(DateTime day) onPick;

  @override
  State<MonthGrid> createState() => _MonthGridState();
}

class _MonthGridState extends State<MonthGrid> {
  /// The first of the month being shown. Starts on today's month; moving it
  /// does not move the selection, so paging ahead to check a date does not
  /// clear what you were looking at.
  late DateTime _month = DateTime(widget.now.year, widget.now.month);

  void _step(int months) => setState(
      () => _month = DateTime(_month.year, _month.month + months));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cells = _cells(_month);
    // One agenda read for the whole grid rather than one per cell: the agenda
    // is cached, but 42 lookups through it every rebuild is still 42 walks of
    // the list, and this rebuilds with the panel.
    final marks = _marks(cells.first, cells.last);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Column(children: [
        Row(children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 16),
            visualDensity: VisualDensity.compact,
            tooltip: 'Previous month',
            onPressed: () => _step(-1),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() =>
                  _month = DateTime(widget.now.year, widget.now.month)),
              child: Text(
                '${monthName(_month.month)} ${_month.year}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 16),
            visualDensity: VisualDensity.compact,
            tooltip: 'Next month',
            onPressed: () => _step(1),
          ),
        ]),
        Row(
          children: [
            for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              Expanded(
                child: Center(
                  child: Text(d,
                      style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: OnoteColors.graphite400)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        for (var week = 0; week * 7 < cells.length; week++)
          Row(
            children: [
              for (var i = week * 7; i < week * 7 + 7 && i < cells.length; i++)
                Expanded(child: _cell(context, cells[i], marks, scheme)),
            ],
          ),
      ]),
    );
  }

  Widget _cell(BuildContext context, DateTime day,
      Map<String, Set<DatedKind>> marks, ColorScheme scheme) {
    final inMonth = day.month == _month.month;
    final isToday = daysEqual(day, widget.now);
    final isPicked =
        widget.selected != null && daysEqual(day, widget.selected!);
    final kinds = marks[_key(day)] ?? const <DatedKind>{};

    return InkWell(
      onTap: () => widget.onPick(day),
      borderRadius: BorderRadius.circular(5),
      child: Container(
        height: 32,
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          color: isPicked ? scheme.primary.withValues(alpha: .16) : null,
          border: isToday
              ? Border.all(color: scheme.primary.withValues(alpha: .7))
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${day.day}',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                    // Days from the neighbouring months stay visible but
                    // recede: hiding them leaves ragged holes, and giving them
                    // full weight makes the month's own boundary invisible.
                    color: inMonth
                        ? null
                        : OnoteColors.graphite400.withValues(alpha: .65))),
            const SizedBox(height: 2),
            SizedBox(
              height: 4,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Ordered by DatedKind so the dots never reshuffle between
                  // rebuilds of the same day.
                  for (final k in DatedKind.values)
                    if (kinds.contains(k))
                      Container(
                        width: 4,
                        height: 4,
                        margin: const EdgeInsets.symmetric(horizontal: .8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _dotColour(k, scheme),
                        ),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Color _dotColour(DatedKind k, ColorScheme scheme) => switch (k) {
        DatedKind.exam => OnoteColors.brass500,
        DatedKind.task => scheme.primary,
        DatedKind.reminder => OnoteColors.ink400,
        DatedKind.event => OnoteColors.graphite400,
      };

  /// Which kinds fall on each day in the visible range, keyed by `y-m-d`.
  Map<String, Set<DatedKind>> _marks(DateTime from, DateTime to) {
    final out = <String, Set<DatedKind>>{};
    for (final it in widget.planner.agenda(now: widget.now)) {
      if (it.done) continue; // a ticked-off task is not a thing still to do
      if (it.when.isBefore(from) || it.when.isAfter(to)) continue;
      out.putIfAbsent(_key(it.when), () => <DatedKind>{}).add(it.kind);
    }
    return out;
  }

  static String _key(DateTime d) => '${d.year}-${d.month}-${d.day}';

  /// Every cell of the grid: the month, padded out to whole Monday-start weeks.
  ///
  /// Built by day arithmetic on `DateTime(y, m, d)` rather than by adding
  /// `Duration(days: 1)`, which lands on the same calendar day when the clocks
  /// go back and would silently duplicate a day in the grid.
  static List<DateTime> _cells(DateTime month) {
    final first = DateTime(month.year, month.month);
    final lead = (first.weekday - DateTime.monday) % 7;
    final start = DateTime(first.year, first.month, 1 - lead);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final total = ((lead + daysInMonth) / 7).ceil() * 7;
    return [
      for (var i = 0; i < total; i++)
        DateTime(start.year, start.month, start.day + i)
    ];
  }
}
