/// Setting the exam date — and, optionally, the time — on a section (P1).
///
/// One helper rather than a copy in each caller, because the two entry points
/// are deliberately far apart: the **navigator**, where a student thinks in
/// subjects ("Discrete Maths has an exam"), and the **study panel**, where they
/// think in decks. Both must open the same picker with the same defaults, or
/// the date silently becomes two different features.
///
/// **Why a small dialog rather than the bare `showDatePicker`.** The date alone
/// was what shipped, and the report back was "being able to also set a time
/// would be awesome" — which is true, and the obvious implementation (chain a
/// `showTimePicker` after the date picker) is the wrong one. Cancelling the
/// second picker is ambiguous: it could mean "no time", or "I changed my mind,
/// keep what was there", and whichever it is chosen to mean is wrong half the
/// time. A single dialog with the time as a visible optional field has no
/// ambiguous gesture in it: the time is either shown or it is not, and there is
/// a button for each direction.
///
/// **The time is presentation and alerting only.** The countdown and the
/// revision plan still work in whole days — see `StudyState.examAt` for why
/// that separation is enforced by having two methods rather than one.
library;

import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../study/study_stats.dart';
import '../theme/tokens.dart';
import 'onote_dialog.dart';

/// How far out a new date lands when there isn't one yet. Two weeks is the
/// horizon at which revision starts feeling real — far enough that a plan has
/// days to spread over, near enough that it isn't an abstraction.
const _defaultLeadDays = 14;

/// Ask for a section's exam day (and time) and store it. Returns true if
/// anything changed.
Future<bool> pickExamDate(
    BuildContext context, AppState app, String sectionId) async {
  final today = DateTime.now();
  final start = DateTime(today.year, today.month, today.day);
  final existing = app.study.examDate(sectionId);
  // An exam that has already been and gone can't be the picker's opening date
  // — `showDatePicker` asserts when the initial date precedes the first one.
  final initialDay = (existing != null && !existing.isBefore(start))
      ? existing
      : DateTime(start.year, start.month, start.day + _defaultLeadDays);
  final section = app.nodes.where((n) => n.id == sectionId).firstOrNull;

  final result = await showOnoteDialog<_ExamWhen>(
    context: context,
    builder: (ctx) => _ExamWhenDialog(
      title: section == null || section.title.isEmpty
          ? 'Exam date'
          : 'Exam — ${section.title}',
      day: initialDay,
      minuteOfDay: app.study.examMinuteOfDay(sectionId),
      firstDate: start,
    ),
  );
  if (result == null) return false;
  app.study.setExamDate(sectionId, result.day);
  // Order matters: `setExamTime` refuses to store a time for a section with no
  // date, so the date has to land first.
  app.study.setExamTime(sectionId, result.minuteOfDay);
  return true;
}

/// Clear a section's exam day, telling the user what was removed.
///
/// The confirmation is a snackbar rather than a dialog: nothing is destroyed —
/// the cards, the schedule and the notes are all untouched — so asking "are you
/// sure?" would be theatre. Saying what happened is enough.
void clearExamDate(BuildContext context, AppState app, String sectionId) {
  final had = app.study.examDate(sectionId);
  app.study.setExamDate(sectionId, null);
  if (had == null || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Exam date removed '
          '(${formatExamDate(had, DateTime.now())}). Your cards are unchanged.')));
}

/// `'HH:mm'` for a minute-of-day, in the local 24-hour form the settings use.
/// Display goes through [TimeOfDay.format] so it follows the locale instead.
String examTimeLabel(BuildContext context, int minuteOfDay) =>
    TimeOfDay(hour: minuteOfDay ~/ 60, minute: minuteOfDay % 60).format(context);

class _ExamWhen {
  const _ExamWhen(this.day, this.minuteOfDay);
  final DateTime day;
  final int? minuteOfDay;
}

class _ExamWhenDialog extends StatefulWidget {
  const _ExamWhenDialog({
    required this.title,
    required this.day,
    required this.minuteOfDay,
    required this.firstDate,
  });

  final String title;
  final DateTime day;
  final int? minuteOfDay;
  final DateTime firstDate;

  @override
  State<_ExamWhenDialog> createState() => _ExamWhenDialogState();
}

class _ExamWhenDialogState extends State<_ExamWhenDialog> {
  late DateTime _day = widget.day;
  late int? _minute = widget.minuteOfDay;

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: widget.firstDate,
      lastDate: DateTime(
          widget.firstDate.year + 3, widget.firstDate.month, widget.firstDate.day),
      helpText: 'Exam date',
      confirmText: 'Use this date',
    );
    if (picked != null) setState(() => _day = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _minute == null
          ? const TimeOfDay(hour: 9, minute: 0)
          : TimeOfDay(hour: _minute! ~/ 60, minute: _minute! % 60),
      helpText: 'What time does it start?',
    );
    if (picked != null) {
      setState(() => _minute = picked.hour * 60 + picked.minute);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    return AlertDialog(
      title: Text(widget.title, style: OnoteType.title),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Field(
              label: 'Date',
              value: formatExamDate(_day, DateTime.now()),
              onTap: _pickDay,
            ),
            const SizedBox(height: OnoteSpace.x4),
            if (_minute == null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.schedule, size: OnoteIcon.sm),
                  label: const Text('Add a start time'),
                  onPressed: _pickTime,
                ),
              )
            else
              Row(children: [
                Expanded(
                  child: _Field(
                    label: 'Starts',
                    value: examTimeLabel(context, _minute!),
                    onTap: _pickTime,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: OnoteIcon.sm),
                  tooltip: 'No particular time',
                  onPressed: () => setState(() => _minute = null),
                ),
              ]),
            const SizedBox(height: OnoteSpace.x4),
            Text(
              _minute == null
                  ? 'The countdown and the revision plan work in whole days, '
                      'so a time is optional.'
                  : 'Shown on the day. The countdown still works in whole days.',
              style: OnoteType.caption.copyWith(color: s.textSecondary),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          // The only dialog in the app with no text field to carry Enter:
          // every control here is a picker, so without a default button
          // Enter did nothing and "Set" was mouse-only (phase-3 audit).
          // Autofocus is safe on this one — it confirms a date you can see
          // and change again, it does not delete anything.
          autofocus: true,
          onPressed: () => Navigator.pop(context, _ExamWhen(_day, _minute)),
          child: const Text('Set'),
        ),
      ],
    );
  }
}

/// A labelled, tappable value — the shape the sync and template dialogs already
/// use, so the three read as the same app.
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value, required this.onTap});

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    return InkWell(
      borderRadius: OnoteRadius.mdAll,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: OnoteSpace.x5, vertical: OnoteSpace.x4),
        decoration: BoxDecoration(
          borderRadius: OnoteRadius.mdAll,
          border: Border.all(color: s.border),
        ),
        child: Row(children: [
          Text(label, style: OnoteType.small.copyWith(color: s.textSecondary)),
          const SizedBox(width: OnoteSpace.x5),
          Expanded(
            child: Text(value,
                style: OnoteType.uiStrong.copyWith(color: s.textPrimary)),
          ),
          Icon(Icons.edit_calendar_outlined,
              size: OnoteIcon.sm, color: s.textSecondary),
        ]),
      ),
    );
  }
}
