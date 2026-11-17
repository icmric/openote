/// "Tell me before my classes" — the settings behind event alerts (v0.8 §2).
///
/// **Why per-kind rather than one switch.** A semester's timetable is thirty-odd
/// events a week. One switch means either silence or thirty-four interruptions,
/// and thirty-four interruptions is silence a week later once they have been
/// turned off. The useful configuration is narrow: *lectures, ten minutes, so I
/// can find the link* — which is one row of this dialog, and is exactly what the
/// preset button sets.
///
/// **Why a dialog rather than inline rows in the panel.** The panel is read
/// daily; this is set once a semester. Style guide §7a.3 — a choice too rich
/// for a menu and too rare for the surface goes in a dialog.
library;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../planner/event_kinds.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import 'onote_dialog.dart';

/// Show the alert-rules dialog. Returns when it closes; changes are applied as
/// they are made, so there is no Save button to forget to press.
Future<void> showEventAlertDialog(BuildContext context, AppState app) =>
    showOnoteDialog<void>(
      context: context,
      builder: (ctx) => _EventAlertDialog(app: app),
    );

class _EventAlertDialog extends StatefulWidget {
  const _EventAlertDialog({required this.app});
  final AppState app;

  @override
  State<_EventAlertDialog> createState() => _EventAlertDialogState();
}

class _EventAlertDialogState extends State<_EventAlertDialog> {
  AppState get app => widget.app;

  void _set(EventKind kind, int? minutes) => setState(
      () => app.planner.eventAlerts =
          app.planner.eventAlerts.withLead(kind, minutes));

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final rules = app.planner.eventAlerts;
    final l = L.of(context);
    return AlertDialog(
      title: Text(l.alertsTitle, style: OnoteType.title),
      content: SizedBox(
        width: 470,
        child: DialogScrollBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l.alertsIntro,
                style:
                    OnoteType.small.copyWith(color: s.textSecondary, height: 1.5),
              ),
              const SizedBox(height: OnoteSpace.x4),
              Row(children: [
                TextButton.icon(
                  icon: const Icon(Icons.bolt_outlined, size: OnoteIcon.sm),
                  label: Text(l.alertsPreset),
                  onPressed: () => setState(() =>
                      app.planner.eventAlerts = EventAlertRules.beforeClasses),
                ),
                const Spacer(),
                if (!rules.isEmpty)
                  TextButton(
                    onPressed: () => setState(
                        () => app.planner.eventAlerts = EventAlertRules.none),
                    child: Text(l.alertsAllOff),
                  ),
              ]),
              const Divider(height: OnoteSpace.x7),
              for (final kind in EventKind.values)
                _KindRow(
                  kind: kind,
                  lead: rules.leadFor(kind),
                  onChanged: (m) => _set(kind, m),
                ),
              const SizedBox(height: OnoteSpace.x5),
              // The limitation, said out loud rather than discovered. An alert
              // that silently cannot reach you is worse than one you know the
              // rules for.
              Container(
                padding: const EdgeInsets.all(OnoteSpace.x4),
                decoration: BoxDecoration(
                  color: s.chrome2,
                  borderRadius: OnoteRadius.mdAll,
                ),
                child: Text(
                  l.alertsWhileRunning,
                  style: OnoteType.small
                      .copyWith(color: s.textSecondary, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(l.commonDone)),
      ],
    );
  }
}

class _KindRow extends StatelessWidget {
  const _KindRow({
    required this.kind,
    required this.lead,
    required this.onChanged,
  });

  final EventKind kind;
  final int? lead;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final l = L.of(context);
    final on = lead != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: OnoteSpace.x1),
      child: Row(children: [
        SizedBox(
          width: 150,
          child: Text(eventKindLabel(l, kind),
              style: OnoteType.ui.copyWith(
                  color: on ? s.textPrimary : s.textSecondary)),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: WidgetStatePropertyAll(OnoteType.caption),
              ),
              segments: [
                ButtonSegment(value: -1, label: Text(l.commonOff)),
                for (final m in eventAlertLeadChoices)
                  ButtonSegment(
                      value: m,
                      label: Text(
                          m == 0 ? l.alertsAtStart : l.alertsMinutes(m))),
              ],
              selected: {lead ?? -1},
              onSelectionChanged: (sel) {
                final v = sel.first;
                onChanged(v < 0 ? null : v);
              },
            ),
          ),
        ),
      ]),
    );
  }
}

/// [kind]'s name in the person's language. [EventKind.label] stays the English
/// name the code knows it by; the planner panel still shows that one until it
/// is translated as a whole.
String eventKindLabel(L l, EventKind kind) => switch (kind) {
      EventKind.lecture => l.eventKindLecture,
      EventKind.tutorial => l.eventKindTutorial,
      EventKind.lab => l.eventKindLab,
      EventKind.workshop => l.eventKindWorkshop,
      EventKind.seminar => l.eventKindSeminar,
      EventKind.exam => l.eventKindExam,
      EventKind.meeting => l.eventKindMeeting,
      EventKind.other => l.eventKindOther,
    };
