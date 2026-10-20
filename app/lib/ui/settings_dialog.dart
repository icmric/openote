import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/platform_open.dart';
import '../core/pen_buttons.dart';
import '../l10n/l10n.dart';
import '../l10n/labels.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import '../theme/tokens.dart';
import '../update/app_update.dart';
import 'mcp_dialog.dart';
import 'onboarding.dart';
import 'onote_dialog.dart';
import 'pen_test_dialog.dart';
import 'shortcut_overlay.dart';
import 'sync_dialog.dart';
import 'update_dialog.dart';

/// The centralised settings page (PLANNING "Consistency/UX"): one place
/// holding every app-wide preference and door — previously each lived only
/// wherever its feature happened to put a control. The per-feature controls
/// stay where they are (a toggle you use while drawing belongs in Draw);
/// this page is where you LOOK for one you can't find.
///
/// **A rail of groups down the left, one group at a time on the right.** It
/// was one long scroll with headings in it, which worked until it grew: the
/// owner, *"The settings menu is looking pretty messy though at the moment.
/// Like its alright but its a bit hard to find things and navigate. I wonder
/// if we go for a more standard 'tab' style … rather than one long page we
/// instead have a series of groups along the left."*
///
/// Quite so, and the headings were already doing half of it — they named the
/// groups but you still had to scroll past every one of them to read the
/// names. The rail says all five at once, and a page is then short enough to
/// take in whole, which is the thing a long scroll can never be.
///
/// **Where the things that are coming go**, since the point of a rail is
/// having somewhere to put them: the size of the interface's text and icons
/// under [_Group.appearance]; custom keybindings in a Keyboard group split out
/// of [_Group.help], which is where the shortcut list already is; dictionaries
/// and automatic capitalisation under [_Group.writing] (see
/// `docs/planning/backlog.md` §1.16).
Future<void> showSettingsDialog(BuildContext context, AppState app) {
  return showOnoteDialog<void>(
    context: context,
    builder: (_) => _SettingsDialog(app: app),
  );
}

/// The dialog's size, stated here rather than per child (style guide §7h).
/// Wide enough for the rail and a row of label-plus-control beside it; tall
/// enough that no group has to scroll on an ordinary window.
const double _kWidth = 620;
const double _kHeight = 380;

/// The groups in the rail, in rail order.
///
/// Deliberately the same five names the headings already used. The owner,
/// proposing the rail: *"Dont have to be the same as the existing headings,
/// and ideally shouldnt be"* — but the complaint was about finding things in
/// one long page, which is the layout rather than the words, and renaming five
/// groups costs seven translations each to say the same thing. Language stays
/// under Appearance for the reason the row itself gives.
enum _Group { appearance, writing, connections, help, about }

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.app});
  final AppState app;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  AppState get app => widget.app;

  _Group _group = _Group.appearance;

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

  /// One setting: what it is, what it does if that is not obvious, and the
  /// control.
  ///
  /// **The hint is optional and most rows do not want one.** The owner, of the
  /// first version of this dialog: *"the items within it now feel quite messy
  /// due to the length and redundancy in some situations of the descriptions,
  /// many of them are long and add nearly nothing."* Quite so, and the test a
  /// line has to pass to be here is that it says something the label and the
  /// control between them do not. "Spell check / On" needs no sentence under
  /// it; "Draw with your finger / Auto (pen takes over)" does, because two
  /// fingers mean something else again and nothing on the row says so.
  Widget _row(String label, Widget control, {String? hint}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 13)),
                if (hint != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, right: 8),
                    child: Text(hint,
                        style: const TextStyle(
                            fontSize: 11, color: OnoteColors.graphite400)),
                  ),
              ],
            ),
          ),
          control,
        ]),
      );

  /// A group within a group, for the settings that are related to each other
  /// and not to the rest of the page: *"We can also have sub headings in each
  /// menu within settings if there are multiple related but distinct
  /// groups."*
  ///
  /// Quieter than the rail's own entries — it is a label inside the page, not
  /// a place you can go.
  Widget _subhead(String text) => _Subhead(text);

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

  /// A settings row's dropdown. One shape for all of them, so a page of
  /// preferences does not have three ways of offering a choice.
  Widget _choice<T>(List<T> values, T current, void Function(T) set,
          String Function(T) label) =>
      DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: current,
          isDense: true,
          style: TextStyle(
              fontSize: 12, color: Theme.of(context).colorScheme.onSurface),
          items: [
            for (final v in values)
              DropdownMenuItem(value: v, child: Text(label(v))),
          ],
          onChanged: (v) => v == null ? null : set(v),
        ),
      );

  /// A settings row that opens something else.
  ///
  /// **The whole row is the button.** It used to be a label and a hint sitting
  /// beside a small "Open…" button, which made the hit target a fraction of
  /// the row it belonged to and gave every one of these entries two visual
  /// weights to read — the owner: *"the link buttons arent exactly the
  /// clearest things, given they are all to open things i dont see any reason
  /// why we shouldnt just turn that whole block into a button"*.
  ///
  /// Quite so. The words already say what pressing does, so the word "Open"
  /// beside them was saying it twice. What is left is the title, the sentence
  /// under it, and a chevron — the shape everybody already reads as "this
  /// leads somewhere".
  Widget _door(IconData icon, String label, String hint, VoidCallback open) =>
      InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        onTap: open,
        borderRadius: OnoteRadius.smAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: Row(children: [
            Icon(icon, size: 16, color: context.surfaces.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(fontSize: 13)),
                    Text(hint,
                        style: const TextStyle(
                            fontSize: 11, color: OnoteColors.graphite400)),
                  ]),
            ),
            Icon(Icons.chevron_right,
                size: 18, color: context.surfaces.textSecondary),
          ]),
        ),
      );

  /// A link out of the app, left-aligned under its group.
  Widget _link(String label, String url) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () => PlatformOpen.url(url),
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
      );

  String _label(_Group g, L l) => switch (g) {
        _Group.appearance => l.settingsAppearance,
        _Group.writing => l.settingsWriting,
        _Group.connections => l.settingsConnections,
        _Group.help => l.settingsHelp,
        _Group.about => l.settingsAbout,
      };

  IconData _icon(_Group g) => switch (g) {
        _Group.appearance => Icons.palette_outlined,
        _Group.writing => Icons.edit_outlined,
        _Group.connections => Icons.cloud_outlined,
        _Group.help => Icons.help_outline,
        _Group.about => Icons.info_outline,
      };

  /// One entry in the rail. No heading is repeated on the page beside it: the
  /// highlighted entry already says which group is open, and saying it twice
  /// in one dialog is how a page of preferences starts reading like a form.
  Widget _railEntry(_Group g, L l) {
    final on = g == _group;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: OnoteRadius.smAll,
        onTap: () => setState(() => _group = g),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: OnoteRadius.smAll,
            color: on ? scheme.primary.withValues(alpha: .12) : null,
          ),
          child: Row(children: [
            Icon(_icon(g),
                size: 16,
                color: on ? scheme.primary : context.surfaces.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _label(g, l),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                  color: on ? scheme.primary : null,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// **A hairline between one setting and the next**, which is the other half
  /// of the mess: *"Please also make it a bit clearer where one setting ends
  /// and the next starts."* A row with a sentence under it and a row with no
  /// sentence read as one run of text otherwise, and the control on the right
  /// is no help in saying which line it belongs to.
  ///
  /// Not around a subheading, which is already a boundary — two of them
  /// together would be a line under a line.
  List<Widget> _ruled(List<Widget> items) {
    final out = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0 && items[i] is! _Subhead && items[i - 1] is! _Subhead) {
        out.add(Divider(
            height: 1, thickness: 1, color: context.surfaces.border));
      }
      out.add(items[i]);
    }
    return out;
  }

  List<Widget> _page(_Group g, L l) => switch (g) {
        _Group.appearance => [
            _row(
              l.settingsTheme,
              SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11))),
                segments: [
                  ButtonSegment(
                      value: ThemeMode.system,
                      label: Text(l.settingsThemeSystem)),
                  ButtonSegment(
                      value: ThemeMode.light, label: Text(l.settingsThemeLight)),
                  ButtonSegment(
                      value: ThemeMode.dark, label: Text(l.settingsThemeDark)),
                ],
                selected: {app.themeMode},
                onSelectionChanged: (s) => app.setThemeMode(s.first),
              ),
            ),
            // **Language sits under Appearance, not behind a "Region" page
            // nobody opens.** It is the first thing somebody whose computer
            // is not in English needs, and by then they are reading a dialog
            // they cannot read.
            _row(
              l.settingsLanguage,
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: app.uiLocale?.toLanguageTag() ?? '',
                  isDense: true,
                  style: const TextStyle(fontSize: 12),
                  items: [
                    DropdownMenuItem(
                        value: '',
                        child: Text(l.settingsLanguageAuto,
                            style: const TextStyle(fontSize: 12))),
                    for (final loc in kOnoteLocalesInOrder)
                      DropdownMenuItem(
                          value: loc.toLanguageTag(),
                          child: Text(languageNameOf(loc),
                              style: const TextStyle(fontSize: 12))),
                  ],
                  onChanged: (v) => app
                      .setUiLocale(v == null || v.isEmpty ? null : Locale(v)),
                ),
              ),
            ),
            // No sentence about who translates Openote: the link under it is
            // that sentence, and said it second.
            _link(l.settingsLanguageContribute,
                'https://github.com/icmric/openote/blob/master/CONTRIBUTING.md#ways-to-help-right-now'),
          ],
        _Group.writing => [
            _row(l.settingsSpellCheck,
                _toggle(app.spellCheckEnabled, app.setSpellCheck)),
            // **Moved off the Draw tab, and under a heading of their own.**
            // The owner: *"i think that option should be in settings rather
            // than that bar."* Both are hardware preferences somebody sets
            // once and never looks at again, which is what this page is for —
            // and they are about the pen and the screen rather than about
            // writing, which is what the subhead is for.
            _subhead(l.settingsPenAndTouch),
            _row(
                l.settingsPenButton,
                _choice<PenButtonAction>(
                  PenButtonAction.values,
                  app.penButton,
                  app.setPenButton,
                  (v) => v.label(l),
                ),
                hint: l.settingsPenButtonHint),
            _row(
                l.settingsTouchDrawing,
                _choice<TouchDrawing>(
                  TouchDrawing.values,
                  app.touchDrawing,
                  app.setTouchDrawing,
                  (v) => v.label(l),
                ),
                hint: l.settingsTouchDrawingHint),
          ],
        _Group.connections => [
            _door(Icons.sync, l.settingsSync, l.settingsSyncHint,
                () => showSyncDialog(context, app)),
            _door(
                Icons.smart_toy_outlined,
                l.settingsAi,
                app.mcpEnabled ? l.settingsAiOn : l.settingsAiOff,
                () => showMcpDialog(context, app)),
          ],
        _Group.help => [
            // The welcome flow is the only place that teaches the canvas
            // itself, and it used to be shown exactly once, ever: skip it on
            // the first run — or be the second person to use the machine —
            // and there was no way back to it. A door here is what makes
            // "Skip" a fair offer.
            _door(Icons.school_outlined, l.settingsWelcomeTour,
                l.settingsWelcomeTourHint, () => showOnboarding(context, app)),
            _door(Icons.keyboard_outlined, l.settingsShortcuts,
                l.settingsShortcutsHint, () => showShortcutOverlay(context)),
            // **The instrument for the pen-buttons report.** It has come back
            // three times from two people on hardware nobody here owns, and
            // each answer has been a guess about what Windows sends. In
            // Settings rather than on the Draw tab because it is for the one
            // conversation where it is needed, not for the toolbar — and
            // under its own heading because it is not something to read.
            _subhead(l.settingsDiagnostics),
            _door(Icons.draw_outlined, l.settingsPenTest, l.settingsPenTestHint,
                () => showPenTestDialog(context)),
          ],
        _Group.about => [
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
            _link(l.settingsWhatsNew,
                'https://github.com/icmric/openote/releases'),
          ],
      };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final l = L.of(context);
        return AlertDialog(
          title: Text(l.settingsTitle),
          content: SizedBox(
            // **Both fixed, and that is what keeps the dialog still.** A page
            // of three rows and a page of three doors are different heights,
            // and a dialog that resized as you moved down the rail would be a
            // dialog whose rail moved under the pointer. A `SizedBox` takes
            // the smaller of this and what the window leaves, so a small
            // window gets a smaller dialog rather than an overflow — and the
            // height is held to the style guide's §7h ceiling of 60% of the
            // window, which on a short window is less than this asks for.
            width: _kWidth,
            height: math.min(
                _kHeight, MediaQuery.sizeOf(context).height * 0.6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 152,
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      for (final g in _Group.values) _railEntry(g, l),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const VerticalDivider(width: 1, thickness: 1),
                const SizedBox(width: 8),
                Expanded(
                  child: ListView(
                    // Keyed by the group, so moving down the rail starts the
                    // new page at the top rather than at the old one's scroll
                    // offset.
                    key: ValueKey(_group),
                    padding: EdgeInsets.zero,
                    children: _ruled(_page(_group, l)),
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

/// A heading for a run of settings inside one group. Its own type, so
/// [_SettingsDialogState._ruled] can tell it from a setting and not draw a
/// line against it.
class _Subhead extends StatelessWidget {
  const _Subhead(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 2),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: .4,
            color: context.surfaces.textSecondary,
          ),
        ),
      );
}
