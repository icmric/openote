/// The popup — what a reminder actually *does* when it comes due (v0.8 §3).
///
/// **What was wrong.** Reminders fired correctly, and then the only sign of it
/// was a coloured dot on a toolbar button. If the planner panel happened to be
/// closed — which it is, most of the time — a reminder set for 2pm produced no
/// visible event at 2pm at all. A nudge you have to go looking for is not a
/// nudge; it is a list.
///
/// **Why an in-app overlay rather than an OS notification.** The same reasoning
/// that made Openote own the schedule (v0.5 §1) applies to the display: there is
/// no scheduling API on Linux, and Windows toasts need an MSIX package identity
/// the portable build does not have. An overlay works identically on all three
/// desktops today, with no new dependency and no packaging constraint. It has a
/// real limitation and the plan says so out loud — it cannot reach you when
/// Openote is behind another window — and the catch-up list is what covers that
/// gap. An OS toast, when it can be had, is a *second* channel to add later,
/// never a replacement for this one.
///
/// **Placement and behaviour.** Bottom-right, above everything, over the canvas
/// rather than pushing it — a reminder must not reflow the page you are writing
/// on. It does not steal focus and it does not block: every alert is dismissible
/// in one click, and ignoring it entirely leaves it in the panel and on the
/// badge. Nothing here ever auto-dismisses; a nudge that vanished while you were
/// looking at the other monitor is the failure this whole feature exists to
/// prevent.
library;

import 'package:flutter/material.dart';

import '../core/platform_open.dart';
import '../planner/alerts.dart';
import '../planner/event_kinds.dart';
import '../planner/agenda.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';

/// How many cards are shown before the rest collapse into a count.
///
/// Three, because the stack is an interruption and an interruption that fills
/// the window is a modal dialog wearing a disguise. Everything beyond three is
/// still there — in the panel, on the badge, and in "and 4 more".
const int alertStackMax = 3;

/// The floating alert stack. Sits in a `Stack` above the shell.
class AlertPopup extends StatelessWidget {
  const AlertPopup({super.key, required this.app, this.regionFocus});

  final AppState app;

  /// Marks the card stack as an F6 region (v0.16 phase 3).
  ///
  /// This was the one popup in the app with NO keyboard route of any kind:
  /// it is not a route, so nothing in the framework dismissed it, and it is
  /// not in the Tab order of anything you can get to. So a reminder sat in
  /// the corner until a mouse arrived. Attached here, below the `Positioned`
  /// — a `Positioned` has to be a direct child of its `Stack`, so the shell
  /// cannot wrap this widget the way it wraps the other regions.
  final FocusNode? regionFocus;

  @override
  Widget build(BuildContext context) {
    final alerts = app.planner.pendingAlerts;
    if (alerts.isEmpty) return const SizedBox.shrink();
    final shown = alerts.length <= alertStackMax
        ? alerts
        : alerts.sublist(alerts.length - alertStackMax);
    final hidden = alerts.length - shown.length;

    return Positioned(
      right: OnoteSpace.x6,
      // Clear of the status bar rather than on top of it. The stack covers the
      // whole shell, so a plain 16px inset parked the card over the save/sync
      // state — hiding the one strip whose entire job is telling you the app
      // is fine while something new demands attention.
      bottom: OnoteSize.statusBar + OnoteSpace.x4,
      child: _region(ConstrainedBox(
        // Wide enough for a lecture title and a room, narrow enough that it
        // never reads as a panel. Matches the snackbar width set in the theme,
        // so the two floating surfaces agree with each other.
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (hidden > 0 || alerts.length > 1)
              _StackHeader(
                app: app,
                total: alerts.length,
                hidden: hidden,
                wereMissed: app.planner.alertsWereMissed,
              ),
            for (final a in shown)
              Padding(
                padding: const EdgeInsets.only(top: OnoteSpace.x3),
                child: _AlertCard(app: app, alert: a),
              ),
          ],
        ),
      )),
    );
  }

  /// `skipTraversal`: the marker is where F6 ARRIVES, not a Tab stop of its
  /// own — Tab should land on Done, not on an invisible wrapper first.
  Widget _region(Widget child) {
    final node = regionFocus;
    return node == null
        ? child
        : Focus(focusNode: node, skipTraversal: true, child: child);
  }
}

class _StackHeader extends StatelessWidget {
  const _StackHeader({
    required this.app,
    required this.total,
    required this.hidden,
    required this.wereMissed,
  });

  final AppState app;
  final int total;
  final int hidden;
  final bool wereMissed;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    return Container(
      padding: const EdgeInsets.fromLTRB(
          OnoteSpace.x5, OnoteSpace.x2, OnoteSpace.x2, OnoteSpace.x2),
      decoration: BoxDecoration(
        color: s.chrome2,
        borderRadius: OnoteRadius.mdAll,
        border: Border.all(color: s.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(
          hidden > 0
              ? '$total waiting · $hidden more below'
              : wereMissed
                  ? '$total while you were away'
                  : '$total waiting',
          style: OnoteType.small.copyWith(color: s.textSecondary),
        ),
        const SizedBox(width: OnoteSpace.x4),
        TextButton(
          onPressed: app.planner.dismissAllAlerts,
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: OnoteSpace.x4),
            minimumSize: const Size(0, OnoteSize.buttonCompact),
          ),
          child: const Text('Dismiss all'),
        ),
      ]),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.app, required this.alert});

  final AppState app;
  final PlannerAlert alert;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    return Material(
      color: s.raised,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: .28),
      borderRadius: OnoteRadius.lgAll,
      child: Container(
        padding: const EdgeInsets.all(OnoteSpace.x5),
        decoration: BoxDecoration(
          borderRadius: OnoteRadius.lgAll,
          border: Border.all(color: s.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(_icon(alert), size: OnoteIcon.md, color: scheme.primary),
              const SizedBox(width: OnoteSpace.x4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(alert.title,
                        style: OnoteType.uiStrong
                            .copyWith(color: s.textPrimary),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: OnoteSpace.x1),
                    Text(_when(alert, now),
                        style:
                            OnoteType.small.copyWith(color: s.textSecondary)),
                    if (alert.subtitle case final sub?
                        when sub.isNotEmpty) ...[
                      const SizedBox(height: OnoteSpace.x1),
                      Text(sub,
                          style: OnoteType.small
                              .copyWith(color: s.textSecondary),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
              // Close is the *quiet* dismissal, and it is deliberately in the
              // corner where a close button always is. "Done" below is the
              // same action said loudly; having both is not redundancy, it is
              // the difference between swatting a popup and finishing a task.
              IconButton(
                icon: const Icon(Icons.close, size: OnoteIcon.sm),
                tooltip: 'Dismiss',
                visualDensity: VisualDensity.compact,
                onPressed: () => app.planner.dismissAlert(alert.id),
              ),
            ]),
            const SizedBox(height: OnoteSpace.x3),
            Row(children: [
              if (alert.join case final join?)
                Padding(
                  padding: const EdgeInsets.only(right: OnoteSpace.x3),
                  child: FilledButton.icon(
                    icon: const Icon(Icons.videocam_outlined,
                        size: OnoteIcon.sm),
                    label: Text('Join ${join.provider}'),
                    onPressed: () => _join(context, join),
                  ),
                ),
              if (alert.hasTarget)
                Padding(
                  padding: const EdgeInsets.only(right: OnoteSpace.x3),
                  child: TextButton(
                    onPressed: () {
                      app.selectPage(alert.pageId!);
                      app.planner.dismissAlert(alert.id);
                    },
                    child: const Text('Go to the note'),
                  ),
                ),
              const Spacer(),
              if (alert.source == AlertSource.reminder)
                _SnoozeMenu(
                  onSnooze: (d) => app.planner.snoozeAlert(alert.id, d),
                ),
              const SizedBox(width: OnoteSpace.x2),
              TextButton(
                onPressed: () => app.planner.dismissAlert(alert.id),
                child: const Text('Done'),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _join(BuildContext context, JoinLink join) async {
    final ok = await PlatformOpen.url(join.url);
    if (!context.mounted) return;
    if (ok) {
      app.planner.dismissAlert(alert.id);
    } else {
      // Never silently do nothing. A Join button that appears to work and
      // does not is worse than no Join button, because you find out at 9:02.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Couldn't open that link: ${join.url}")));
    }
  }

  static IconData _icon(PlannerAlert a) {
    if (a.source == AlertSource.reminder) return Icons.notifications_active;
    return switch (a.kind) {
      EventKind.exam => Icons.assignment_outlined,
      EventKind.lab => Icons.science_outlined,
      EventKind.tutorial || EventKind.workshop => Icons.groups_outlined,
      EventKind.lecture || EventKind.seminar => Icons.co_present_outlined,
      EventKind.meeting => Icons.event_available_outlined,
      _ => Icons.event_outlined,
    };
  }

  /// The line under the title.
  ///
  /// For an event this leads with **how long you have**, because that is the
  /// only number being read: "in 10 minutes" is the answer, "09:00" is a fact
  /// you have to subtract from. For a reminder it leads with the time it was
  /// set for, since a reminder that fired late needs to say when it was due.
  static String _when(PlannerAlert a, DateTime now) {
    if (a.source == AlertSource.event) {
      final mins = a.at.difference(now).inMinutes;
      final lead = mins <= 0
          ? 'starting now'
          : mins == 1
              ? 'in 1 minute'
              : mins < 60
                  ? 'in $mins minutes'
                  : 'at ${formatClock(a.at)}';
      final kind = a.kind == null || a.kind == EventKind.other
          ? ''
          : '${a.kind!.label} · ';
      return '$kind$lead · ${formatClock(a.at)}';
    }
    if (now.difference(a.at).inMinutes >= 2) {
      return 'Was due at ${formatClock(a.at)}';
    }
    return formatClock(a.at);
  }
}

/// Snooze, offered on the alert itself.
///
/// A nudge you cannot postpone is one you dismiss and forget, which is the
/// failure mode that makes people turn reminders off entirely.
class _SnoozeMenu extends StatelessWidget {
  const _SnoozeMenu({required this.onSnooze});

  final void Function(Duration) onSnooze;

  @override
  Widget build(BuildContext context) => MenuAnchor(
        builder: (context, controller, _) => TextButton.icon(
          icon: const Icon(Icons.snooze, size: OnoteIcon.sm),
          label: const Text('Snooze'),
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
        ),
        menuChildren: [
          for (final (label, minutes) in const [
            ('10 minutes', 10),
            ('An hour', 60),
            ('This evening (3 hours)', 180),
            ('Tomorrow', 60 * 24),
          ])
            MenuItemButton(
              onPressed: () => onSnooze(Duration(minutes: minutes)),
              child: Text(label),
            ),
        ],
      );
}
