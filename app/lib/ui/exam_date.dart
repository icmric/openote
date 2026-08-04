/// Setting the exam date on a section (P1).
///
/// One helper rather than a copy in each caller, because the two entry points
/// are deliberately far apart: the **navigator**, where a student thinks in
/// subjects ("Discrete Maths has an exam"), and the **study panel**, where they
/// think in decks. Both must open the same picker with the same defaults, or
/// the date silently becomes two different features.
library;

import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../study/study_stats.dart';

/// How far out a new date lands when there isn't one yet. Two weeks is the
/// horizon at which revision starts feeling real — far enough that a plan has
/// days to spread over, near enough that it isn't an abstraction.
const _defaultLeadDays = 14;

/// Ask for a section's exam day and store it. Returns true if it changed.
///
/// Deliberately the OS-standard date picker rather than something bespoke: it
/// is keyboard-enterable, localised, and already knows what a month looks like
/// here. Style guide §7a.3 — dialogs are for choices too rich for a menu, and
/// this is exactly one of those.
Future<bool> pickExamDate(
    BuildContext context, AppState app, String sectionId) async {
  final today = DateTime.now();
  final start = DateTime(today.year, today.month, today.day);
  final existing = app.study.examDate(sectionId);
  // An exam that has already been and gone can't be the picker's opening date
  // — `showDatePicker` asserts when the initial date precedes the first one.
  final initial = (existing != null && !existing.isBefore(start))
      ? existing
      : DateTime(start.year, start.month, start.day + _defaultLeadDays);
  final section = app.nodes.where((n) => n.id == sectionId).firstOrNull;

  final picked = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: start,
    lastDate: DateTime(start.year + 3, start.month, start.day),
    helpText: section == null ? 'Exam date' : 'Exam date — ${section.title}',
    confirmText: 'Set',
  );
  if (picked == null) return false;
  app.study.setExamDate(sectionId, picked);
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
