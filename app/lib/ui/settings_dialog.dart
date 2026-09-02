import 'package:flutter/material.dart';

import '../core/platform_open.dart';
import '../l10n/l10n.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import '../update/app_update.dart';
import 'mcp_dialog.dart';
import 'onboarding.dart';
import 'onote_dialog.dart';
import 'shortcut_overlay.dart';
import 'sync_dialog.dart';
import 'update_dialog.dart';

/// The centralised settings page (PLANNING "Consistency/UX"): one place
/// holding every app-wide preference and door — previously each lived only
/// wherever its feature happened to put a control. The per-feature controls
/// stay where they are (a toggle you use while drawing belongs in Draw);
/// this page is where you LOOK for one you can't find.
Future<void> showSettingsDialog(BuildContext context, AppState app) {
  return showOnoteDialog<void>(
    context: context,
    builder: (_) => _SettingsDialog(app: app),
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.app});
  final AppState app;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  AppState get app => widget.app;

  bool _checking = false;
  String? _updateNote;

  Future<void> _checkNow() async {
    setState(() {
      _checking = true;
      _updateNote = null;
    });
    await app.checkForAppUpdate();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _updateNote = app.updateAvailable == null
          ? L.of(context).settingsUpToDate(kAppVersion)
          : null;
    });
    if (app.updateAvailable != null && mounted) {
      await showUpdateDialog(context, app);
    }
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: Text(title,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary)),
      );

  Widget _row(String label, Widget control) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          control,
        ]),
      );

  /// An on/off preference, shown the same way as the Theme row above it — a
  /// highlighted segment, not a switch. One visual language for "this is
  /// currently set to X" throughout the dialog, not two.
  Widget _toggle(bool value, ValueChanged<bool> onChanged) =>
      SegmentedButton<bool>(
        showSelectedIcon: false,
        style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11))),
        segments: [
          ButtonSegment(
              value: false, label: Text(L.of(context).commonOff)),
          ButtonSegment(value: true, label: Text(L.of(context).commonOn)),
        ],
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.first),
      );

  Widget _door(IconData icon, String label, String hint, VoidCallback open) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 13)),
              Text(hint,
                  style: const TextStyle(
                      fontSize: 11, color: OnoteColors.graphite400)),
            ]),
          ),
          TextButton.icon(
            icon: Icon(icon, size: 15),
            label: Text(L.of(context).commonOpenEllipsis,
                style: const TextStyle(fontSize: 12)),
            onPressed: open,
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final l = L.of(context);
        return AlertDialog(
        title: Text(l.settingsTitle),
        content: SizedBox(
          width: 460,
          child: ListView(
            shrinkWrap: true,
            children: [
              _section(l.settingsAppearance),
              _row(
                l.settingsTheme,
                SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      textStyle:
                          WidgetStatePropertyAll(TextStyle(fontSize: 11))),
                  segments: [
                    ButtonSegment(
                        value: ThemeMode.system,
                        label: Text(l.settingsThemeSystem)),
                    ButtonSegment(
                        value: ThemeMode.light,
                        label: Text(l.settingsThemeLight)),
                    ButtonSegment(
                        value: ThemeMode.dark, label: Text(l.settingsThemeDark)),
                  ],
                  selected: {app.themeMode},
                  onSelectionChanged: (s) => app.setThemeMode(s.first),
                ),
              ),
              _section(l.settingsWriting),
              _row(l.settingsSpellCheck,
                  _toggle(app.spellCheckEnabled, app.setSpellCheck)),
              _row(l.settingsPenProximity,
                  _toggle(app.penProximitySwitch, app.setPenProximitySwitch)),
              _section(l.settingsConnections),
              _door(Icons.sync, l.settingsSync, l.settingsSyncHint,
                  () => showSyncDialog(context, app)),
              _door(
                  Icons.smart_toy_outlined,
                  l.settingsAi,
                  app.mcpEnabled ? l.settingsAiOn : l.settingsAiOff,
                  () => showMcpDialog(context, app)),
              _section(l.settingsHelp),
              // The welcome flow is the only place that teaches the canvas
              // itself, and it used to be shown exactly once, ever: skip it
              // on the first run — or be the second person to use the
              // machine — and there was no way back to it. A door here is
              // what makes "Skip" a fair offer.
              _door(Icons.school_outlined, l.settingsWelcomeTour,
                  l.settingsWelcomeTourHint,
                  () => showOnboarding(context, app)),
              _door(Icons.keyboard_outlined, l.settingsShortcuts,
                  l.settingsShortcutsHint,
                  () => showShortcutOverlay(context)),
              _section(l.settingsAbout),
              _row(
                l.settingsVersion(kAppVersion),
                _checking
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : TextButton(
                        onPressed: _checkNow,
                        child: Text(l.settingsCheckUpdates,
                            style: const TextStyle(fontSize: 12)),
                      ),
              ),
              if (_updateNote != null)
                Text(_updateNote!,
                    style: const TextStyle(
                        fontSize: 11.5, color: OnoteColors.graphite400)),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => PlatformOpen.url(
                      'https://github.com/icmric/openote/releases'),
                  child: Text(l.settingsWhatsNew,
                      style: const TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.commonClose)),
        ],
      );
      },
    );
  }
}
