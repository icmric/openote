import 'l10n/l10n.dart';
import 'dart:io' show Directory, exit;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'core/single_instance.dart';
import 'core/startup_args.dart';
import 'media/video_playback.dart';
import 'state/app_state.dart';
import 'store/repository.dart';
import 'theme/onote_theme.dart';
import 'ui/app_shell.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // The notebook we were launched to open: `openote Physics.onotebook`, or a
  // double-click in the file manager — on the notebook folder itself where the
  // shell will open one, and on the `Open this notebook.onotelink` inside it
  // everywhere else (v0.17 Step 8b). Parsed before anything else because the
  // single-instance hand-off below needs to know what to hand over, and it
  // hands over a path whether that path is a file or a directory. See
  // core/startup_args.dart, and core/open_target.dart for which of the two it
  // turned out to be.
  final requested = notebookPathFromArgs(args);

  // BEFORE runApp, and this ordering is the whole point: if another Openote is
  // already running on this workspace it takes the notebook and we exit
  // without ever painting. A window that appears and immediately vanishes
  // would be worse than either outcome.
  //
  // The cost is that the first frame now waits on resolving the workspace
  // folder and one file lock — a `mkdir` and an `open` — which is a few
  // milliseconds against the "the app takes ages to appear" work below. There
  // is no way to know whether this process is allowed to exist without asking.
  SingleInstance? instance;
  var handedOver = false;
  try {
    final dir = await Repository.resolveWorkspaceDir();
    instance = await SingleInstance.claim(dir, openPath: requested);
    handedOver = instance == null;
  } catch (_) {
    // The workspace folder could not even be resolved. Say nothing here and
    // carry on: `Repository.open()` is about to fail the same way, and it
    // fails into the in-window error screen below instead of into a process
    // that dies with no window at all.
    instance = null;
  }
  // Outside the try on purpose. A null `instance` means "we handed over, stop"
  // on one path and "carry on without a claim" on the other, so the decision
  // is spelled with its own flag rather than left for a reader to infer.
  if (handedOver) exit(0);

  // pdfrx wires its own statics (asset loader, and the cache directory pdfium
  // needs for its font cache) inside this call. Its *widgets* do it implicitly
  // in initState, but Openote drives the document API directly and never
  // builds one — so without this, opening a PDF throws
  // "Pdfrx.getCacheDirectory is not set" before pdfium is even touched.
  // Must run on the root isolate, before any PDF work.
  pdfrxFlutterInitialize();
  // Resolve libmpv once, here, rather than the first time a block tries to
  // play something: on a Linux box without it, `MediaKit.ensureInitialized`
  // throws, and a throw inside a widget build is a red screen where a "you
  // need to install mpv-libs" card belongs. See media/video_playback.dart.
  // Awaited: on Windows this also resolves whether the downloaded engine is
  // present, and a page that renders its video cards before that answer is
  // known shows "needs the video player" to somebody who already has it.
  await VideoPlayback.probe();
  // Paint a window IMMEDIATELY; open the workspace behind it. Blocking runApp
  // on Repository.open + init left the window invisible until SQLite and the
  // restored page were fully loaded ("the app takes ages to appear").
  runApp(OpenoteBoot(notebookPath: requested, instance: instance));
}

/// Boots the workspace behind a lightweight splash, then swaps in the app.
/// Never fails invisibly: a startup error renders in-window (PLAT-9 in
/// spirit) instead of leaving a ghost process.
class OpenoteBoot extends StatefulWidget {
  const OpenoteBoot({super.key, this.notebookPath, this.instance});

  /// The notebook named on the command line, absolute — or null.
  final String? notebookPath;

  /// Our claim on this workspace, when we got one. Held here so it lives as
  /// long as the app and is released on the way out.
  final SingleInstance? instance;

  @override
  State<OpenoteBoot> createState() => _OpenoteBootState();
}

class _OpenoteBootState extends State<OpenoteBoot> {
  AppState? _app;
  (Object, StackTrace)? _error;
  _WorkspaceBlocked? _blocked;
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      // **Before opening anything.** A workspace inside a folder Windows
      // Defender guards is readable but not writable, so every check that asks
      // "is it there?" passes and the first save fails — which used to surface
      // as a SQLite error about a notebook that could not be read. Ask the
      // question that actually matters, once, and answer it in words.
      final dir = await Repository.resolveWorkspaceDir();
      final problem = Repository.workspaceWriteProblem(dir);
      if (problem != null) {
        final safer = await Repository.saferWorkspaceDir(dir);
        if (mounted) {
          setState(() => _blocked =
              _WorkspaceBlocked(dir: dir, safer: safer, problem: problem));
        }
        return;
      }
      final repo = await Repository.open();
      final app = AppState(repo);
      await app.init(notebookPath: widget.notebookPath);
      // Every LATER double-click arrives here, as a request file the new
      // process left behind before exiting. See core/single_instance.dart.
      widget.instance?.listen(app.openNotebookFile);
      // Persist before the process goes away. Autosave is debounced, so without
      // this the last edits before a window close were silently lost — and the
      // SQLite handles never got a clean close (no WAL checkpoint).
      _lifecycle = AppLifecycleListener(
        onExitRequested: () async {
          await app.shutdown();
          await widget.instance?.dispose();
          return AppExitResponse.exit;
        },
      );
      if (mounted) setState(() => _app = app);
    } catch (e, st) {
      if (mounted) setState(() => _error = (e, st));
    }
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    // Stops the request poll. The lock itself is released by the OS when the
    // process goes, so this is about not leaving a timer behind in a hot
    // reload rather than about correctness on exit.
    widget.instance?.dispose();
    _app?.dispose();
    super.dispose();
  }

  /// Copy the workspace somewhere writable, then carry on into the app.
  Future<String?> _moveWorkspace(_WorkspaceBlocked blocked) async {
    try {
      await Repository.copyWorkspaceTo(blocked.dir, blocked.safer!);
      if (mounted) setState(() => _blocked = null);
      await _open();
      return null;
    } catch (e) {
      return '$e';
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocked = _blocked;
    if (blocked != null) {
      return _BlockedWorkspace(blocked: blocked, onMove: _moveWorkspace);
    }
    final err = _error;
    if (err != null) return _StartupError(error: err.$1, stack: err.$2);
    final app = _app;
    if (app != null) return OpenoteApp(app: app);
    return MaterialApp(
      title: 'Openote',
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      localeListResolutionCallback: onoteResolveLocale,
      debugShowCheckedModeBanner: false,
      theme: onoteTheme(Brightness.light),
      darkTheme: onoteTheme(Brightness.dark),
      home: const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_book_outlined, size: 42),
              SizedBox(height: 14),
              SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.4)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A workspace Openote can read but not write, and where it could go instead.
class _WorkspaceBlocked {
  const _WorkspaceBlocked(
      {required this.dir, required this.safer, required this.problem});

  /// Where the notebooks are now.
  final Directory dir;

  /// Somewhere nothing guards, or null when there is nowhere better.
  final Directory? safer;

  /// What went wrong, already in plain words.
  final String problem;
}

/// **"Openote cannot save here"**, and one button that fixes it.
///
/// This screen exists because of what the old one said instead. A student
/// whose Documents folder is guarded by Windows Defender got a SQLite
/// exception and a stack trace about a notebook that could not be read — which
/// names neither the cause (an antivirus setting), the place (one folder), nor
/// anything they could do. The fix was two clicks away in Windows Security and
/// there was no way to know that from the screen.
///
/// So: say what is blocking, say where, and offer to move the notebooks
/// somewhere it does not apply. The manual route is spelled out underneath for
/// anyone who would rather keep their notes in Documents and allow Openote —
/// both are legitimate and the student picks.
class _BlockedWorkspace extends StatefulWidget {
  const _BlockedWorkspace({required this.blocked, required this.onMove});

  final _WorkspaceBlocked blocked;

  /// Returns null on success, or the failure in words.
  final Future<String?> Function(_WorkspaceBlocked) onMove;

  @override
  State<_BlockedWorkspace> createState() => _BlockedWorkspaceState();
}

class _BlockedWorkspaceState extends State<_BlockedWorkspace> {
  bool _moving = false;
  String? _failed;

  @override
  Widget build(BuildContext context) {
    final b = widget.blocked;
    return MaterialApp(
      title: 'Openote',
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      localeListResolutionCallback: onoteResolveLocale,
      debugShowCheckedModeBanner: false,
      theme: onoteTheme(Brightness.light),
      darkTheme: onoteTheme(Brightness.dark),
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Openote cannot save to this folder',
                      style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  Text(b.problem),
                  const SizedBox(height: 10),
                  // Named plainly, because the next paragraph asks them to
                  // approve moving what is in it.
                  Text('Your notebooks are in:\n${b.dir.path}',
                      style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 10),
                  const Text(
                      'Nothing has been lost and nothing has been changed — '
                      'Openote can read your notes, it just cannot save into '
                      'this folder.'),
                  const SizedBox(height: 18),
                  if (b.safer != null) ...[
                    FilledButton.icon(
                      onPressed: _moving
                          ? null
                          : () async {
                              setState(() {
                                _moving = true;
                                _failed = null;
                              });
                              final err = await widget.onMove(b);
                              if (mounted && err != null) {
                                setState(() {
                                  _moving = false;
                                  _failed = err;
                                });
                              }
                            },
                      icon: _moving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.drive_file_move_outlined,
                              size: 18),
                      label: Text(_moving
                          ? 'Copying your notebooks…'
                          : 'Copy my notebooks somewhere Openote can save'),
                    ),
                    const SizedBox(height: 6),
                    // Said before they press it, not after: a copy that leaves
                    // the original behind is the safe choice here, and it is
                    // also the only one available — removing anything from a
                    // guarded folder is itself blocked.
                    Text(
                        'Copies them to ${b.safer!.path}. The originals stay '
                        'exactly where they are.',
                        style: const TextStyle(fontSize: 12)),
                  ],
                  if (_failed != null) ...[
                    const SizedBox(height: 12),
                    SelectableText('That did not work: $_failed',
                        style: const TextStyle(fontSize: 12)),
                  ],
                  const SizedBox(height: 22),
                  const Text('Or allow Openote to save where it is',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  const Text(
                      '1. Open Windows Security, then Virus & threat '
                      'protection.\n'
                      '2. Under Ransomware protection, choose Manage '
                      'ransomware protection.\n'
                      '3. Choose Allow an app through Controlled folder '
                      'access, then Add an allowed app, and pick Openote.\n'
                      '4. Start Openote again.',
                      style: TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error, required this.stack});
  final Object error;
  final StackTrace stack;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Openote',
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      localeListResolutionCallback: onoteResolveLocale,
      theme: onoteTheme(Brightness.light),
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Openote couldn't start",
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  const Text(
                      'Something failed while opening your workspace. Your notes '
                      'are not affected. Details below — please report this.'),
                  const SizedBox(height: 16),
                  SelectableText('$error\n\n$stack',
                      style: const TextStyle(fontFamily: 'JetBrains Mono', fontFamilyFallback: onoteFontFallback, fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OpenoteApp extends StatefulWidget {
  const OpenoteApp({super.key, required this.app});
  final AppState app;

  @override
  State<OpenoteApp> createState() => _OpenoteAppState();
}

class _OpenoteAppState extends State<OpenoteApp> {
  ThemeMode? _builtMode;
  Locale? _builtLocale;
  Widget? _built;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.app,
      builder: (context, _) {
        // Rebuild the root MaterialApp ONLY when the theme mode changes.
        // Content updates ride AppShell's own listener — rebuilding the whole
        // tree from the root on every notify (each keystroke, drag frame)
        // doubled per-frame build work.
        if (_built != null &&
            _builtMode == widget.app.themeMode &&
            _builtLocale == widget.app.uiLocale) {
          return _built!;
        }
        _builtMode = widget.app.themeMode;
        _builtLocale = widget.app.uiLocale;
        return _built = MaterialApp(
          title: 'Openote',
          localizationsDelegates: kOnoteLocalizations,
          supportedLocales: kOnoteLocales,
      localeListResolutionCallback: onoteResolveLocale,
          // **Null means follow the computer**, and null is the default.
          // Flutter then resolves against the OS's preferred-language list —
          // exact match, then language, then script — so Openote installed on
          // a Chinese machine opens in Chinese with nothing to set up, and
          // falls back to English only when it has nothing closer. A locale
          // is set here only when the student has picked one in Settings.
          locale: widget.app.uiLocale,
          debugShowCheckedModeBanner: false,
          theme: onoteTheme(Brightness.light),
          darkTheme: onoteTheme(Brightness.dark),
          themeMode: widget.app.themeMode, // Settings: Auto / Light / Dark
          home: AppShell(app: widget.app),
        );
      },
    );
  }
}
