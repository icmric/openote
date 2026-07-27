import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import 'state/app_state.dart';
import 'store/repository.dart';
import 'theme/onote_theme.dart';
import 'ui/app_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Paint a window IMMEDIATELY; open the workspace behind it. Blocking runApp
  // on Repository.open + init left the window invisible until SQLite and the
  // restored page were fully loaded ("the app takes ages to appear").
  runApp(const OpenoteBoot());
}

/// Boots the workspace behind a lightweight splash, then swaps in the app.
/// Never fails invisibly: a startup error renders in-window (PLAT-9 in
/// spirit) instead of leaving a ghost process.
class OpenoteBoot extends StatefulWidget {
  const OpenoteBoot({super.key});

  @override
  State<OpenoteBoot> createState() => _OpenoteBootState();
}

class _OpenoteBootState extends State<OpenoteBoot> {
  AppState? _app;
  (Object, StackTrace)? _error;
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final repo = await Repository.open();
      final app = AppState(repo);
      await app.init();
      // Persist before the process goes away. Autosave is debounced, so without
      // this the last edits before a window close were silently lost — and the
      // SQLite handles never got a clean close (no WAL checkpoint).
      _lifecycle = AppLifecycleListener(
        onExitRequested: () async {
          await app.shutdown();
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
    _app?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final err = _error;
    if (err != null) return _StartupError(error: err.$1, stack: err.$2);
    final app = _app;
    if (app != null) return OpenoteApp(app: app);
    return MaterialApp(
      title: 'Openote',
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

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error, required this.stack});
  final Object error;
  final StackTrace stack;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Openote',
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
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
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
        if (_built != null && _builtMode == widget.app.themeMode) {
          return _built!;
        }
        _builtMode = widget.app.themeMode;
        return _built = MaterialApp(
          title: 'Openote',
          debugShowCheckedModeBanner: false,
          theme: onoteTheme(Brightness.light),
          darkTheme: onoteTheme(Brightness.dark),
          themeMode: widget.app.themeMode, // View tab: Auto / Light / Dark
          home: AppShell(app: widget.app),
        );
      },
    );
  }
}
