import 'dart:io';

import 'package:flutter/material.dart';

import '../core/platform_open.dart';
import '../l10n/l10n.dart';
import '../markdown/md_render.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import '../update/app_update.dart';
import 'onote_dialog.dart';

/// The update flow (PLANNING.md: "make a popup to stop them interacting
/// further, save everything, … prevent them from using the app during the
/// process … automatically apply the update and relaunch").
///
/// Windows gets the full ride: flush every save, download the installer
/// behind an undismissable barrier, run it silently and exit — the
/// installer's silent-mode Run entry starts the new Openote. Platforms
/// whose artifact is a package (.deb/.rpm/tar.gz) get the download page:
/// pretending that is automatic would just fail confusingly later.
Future<void> showUpdateDialog(BuildContext context, AppState app) {
  final info = app.updateAvailable;
  if (info == null) return Future.value();
  return showOnoteDialog<void>(
    context: context,
    // Dismissible, with the `PopScope` below doing the real gating. It was
    // `false`, which switches OFF the framework's Escape handling entirely
    // (`_DismissModalAction.isEnabled` IS `route.barrierDismissible`) — so an
    // update notice that appears on startup could not be waved away by
    // keyboard at all, even before anything was downloading. `maybePop`
    // honours `canPop`, so the barrier is still solid mid-download, which is
    // the only moment it needed to be.
    builder: (_) => _UpdateDialog(app: app, info: info),
  );
}

/// What's new in the update, drawn the way it was written.
///
/// The release body arrives as Markdown, and this used to be a plain [Text] —
/// so a student was shown `**The download is about half the size**`,
/// asterisks and all, with `##` in front of every heading. Eric, 2026-08-17:
/// "it shows words **like this** rather than bolded which is not the best
/// look."
///
/// It renders through [MarkdownView], the renderer the notes themselves use,
/// so the dialect can never drift from the one the rest of the app reads.
/// Three deliberate choices, because a release body is REMOTE text rather
/// than the user's own notes:
///
///  * **No image resolver.** Without one an `![…](…)` line renders as its
///    literal Markdown, which means the dialog cannot be made to fetch a
///    remote picture by whatever the release body happens to contain.
///  * **No wiki-link handler**, so `[[…]]` draws as an inert chip: there is
///    no page in a notebook for a release note to point at.
///  * **Links open in the browser** through the same `PlatformOpen`
///    allow-list note links use — http/https/mailto only, handed to the OS as
///    one parameter and never through a shell.
///
/// It scrolls, and it opens out: a release body is arbitrarily long, and the
/// dialog is where most people read one.
class ReleaseNotesView extends StatefulWidget {
  const ReleaseNotesView({super.key, required this.notes});

  final String notes;

  /// Height of the panel when folded. About eight lines — enough for the
  /// compact overview the body is required to open with (docs/RELEASING.md).
  static const double collapsedHeight = 200;

  /// Longer than this and the panel offers to open out.
  static const int foldAfterLines = 10;

  @override
  State<ReleaseNotesView> createState() => _ReleaseNotesViewState();
}

class _ReleaseNotesViewState extends State<ReleaseNotesView> {
  final _scroll = ScrollController();
  bool _expanded = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = tidyReleaseNotes(widget.notes);
    if (text.isEmpty) return const SizedBox.shrink();
    final long = '\n'.allMatches(text).length + 1 >
        ReleaseNotesView.foldAfterLines;
    // Opened out, the panel follows the window rather than a fixed number:
    // the same 460px that is comfortable on a laptop is taller than the whole
    // dialog on a small screen.
    final maxHeight = _expanded
        ? (MediaQuery.of(context).size.height * 0.45).clamp(160.0, 460.0)
        : ReleaseNotesView.collapsedHeight;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            // A visible thumb, because the first few lines are all most
            // people see — without it there is nothing to say the rest of the
            // notes exist.
            child: Scrollbar(
              controller: _scroll,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.only(right: 12),
                child: MarkdownView(
                  text: text,
                  baseStyle: const TextStyle(fontSize: 12.5, height: 1.35),
                ),
              ),
            ),
          ),
        ),
        if (long)
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              minimumSize: const Size(0, 30),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(_expanded ? 'Show less' : 'Show more',
                style: const TextStyle(fontSize: 12)),
          ),
      ],
    );
  }
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.app, required this.info});
  final AppState app;
  final UpdateInfo info;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _busy = false;
  double? _progress; // null = indeterminate
  String? _error;

  UpdateInfo get info => widget.info;

  /// **Openote installs its own update on Windows, and nowhere else.**
  ///
  /// Not an unfinished branch — a decision, and a different one on each
  /// platform:
  ///
  ///  * **Windows** ships an Inno Setup `-setup.exe`. It takes `/SILENT`,
  ///    replaces the files and relaunches Openote itself, so the whole
  ///    update is one `Process.start` and the installer handles its own
  ///    elevation. That is the only platform where the artefact we already
  ///    publish can do the job.
  ///  * **Linux** ships `.deb`, `.rpm` and `.tar.gz`. Both packages need
  ///    root, and an app that silently elevates to install a package is
  ///    something a user is right to distrust — worse, it would be reaching
  ///    around the package manager that owns those files. Somebody who
  ///    installed the `.rpm` should be updated by `dnf`, not by us. The
  ///    tarball COULD replace itself (unlinking a running binary is fine on
  ///    Linux; the inode survives), but nothing records which of the three
  ///    they used or where they put it, and guessing wrong breaks an install.
  ///  * **macOS** ships a `.dmg`, so updating means mounting it and copying
  ///    over `/Applications` while running from there. That is what Sparkle
  ///    exists for, and it carries a code-signing story this app does not
  ///    have yet: an unsigned bundle replacing itself lands in Gatekeeper
  ///    quarantine.
  ///
  /// So everywhere else the button sends them to the download page and the
  /// dialog says, in one line, that they install it themselves.
  bool get _canAutoUpdate =>
      Platform.isWindows && info.windowsSetupUrl != null;

  /// **Where the button goes when Openote cannot install it itself.**
  ///
  /// The site rather than the GitHub release: openote.org detects the
  /// visitor's OS and puts the matching download first, which is the whole
  /// reason it exists — where the release page is seven assets and a wall of
  /// notes to scroll past, and a Linux user has to know whether they want the
  /// `.deb`, the `.rpm` or the `.tar.gz`. The page reads the newest release
  /// at request time, so it needs nothing from us to stay current.
  static const _downloadPage = 'https://openote.org';

  Future<void> _update() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    // Save EVERYTHING first — the app is about to be replaced under us.
    await widget.app.flushSave();
    final to =
        '${Directory.systemTemp.path}${Platform.pathSeparator}openote-${info.version}-setup.exe';
    final file = await downloadUpdate(info.windowsSetupUrl!, to,
        onProgress: (got, total) {
      if (!mounted) return;
      setState(() => _progress = total > 0 ? got / total : null);
    });
    if (!mounted) return;
    if (file == null) {
      setState(() {
        _busy = false;
        _progress = null;
        _error = "The download didn't finish. Check your internet "
            'connection and try again — nothing has been changed.';
      });
      return;
    }
    try {
      // Silent install: replaces the files and relaunches Openote itself.
      // This process must be gone before the installer touches the exe.
      await Process.start(file.path, ['/SILENT', '/NOCANCEL'],
          mode: ProcessStartMode.detached);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = "Couldn't start the installer: $e";
      });
      return;
    }
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final notes = (info.notes ?? '').trim();
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(l.updateAvailable(info.version)),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.updateYouHave(kAppVersion),
                  style: const TextStyle(fontSize: 12.5)),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                // Flexible, not a bare child: the notes panel asks for up to
                // 460px when opened out, and a `Column` hands a non-flexible
                // child unbounded height — on a short window that is a yellow
                // overflow stripe across the dialog.
                Flexible(child: ReleaseNotesView(notes: notes)),
              ],
              const SizedBox(height: 10),
              if (_busy) ...[
                Text(
                    _progress == null
                        ? l.updateDownloading
                        : l.updateDownloadingPercent(
                            (_progress! * 100).round()),
                    style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 6),
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: 6),
                Text(l.updateSavedClosing,
                    style: const TextStyle(
                        fontSize: 11.5, color: OnoteColors.graphite400)),
              ] else if (_canAutoUpdate)
                Text(l.updateWillRestart,
                    style: const TextStyle(fontSize: 12, height: 1.4))
              else
                // **The one thing a reader must not miss.** The old wording
                // explained the mechanism — *"the update installs from a
                // downloaded package"* — and buried the instruction, so the
                // browser opened and people thought the button had failed.
                // This says what THEY do, in one short sentence, and the
                // button's own icon says it leaves the app.
                Text(l.updateInstallYourself,
                    style: const TextStyle(fontSize: 12, height: 1.4)),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!,
                      style: const TextStyle(
                          fontSize: 12, color: OnoteColors.danger)),
                ),
            ],
          ),
        ),
        actions: _busy
            ? const []
            : [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l.updateNotNow)),
                if (_canAutoUpdate)
                  FilledButton(
                      onPressed: _update, child: Text(l.updateNow))
                else
                  FilledButton.icon(
                      onPressed: () {
                        PlatformOpen.url(_downloadPage);
                        Navigator.of(context).pop();
                      },
                      // The icon carries half the message: this one leaves
                      // Openote. One word and a glyph, rather than a sentence
                      // on the button.
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: Text(l.updateDownload)),
              ],
      ),
    );
  }
}
