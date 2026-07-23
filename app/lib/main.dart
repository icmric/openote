import 'package:flutter/material.dart';

import 'state/app_state.dart';
import 'store/repository.dart';
import 'theme/onote_theme.dart';
import 'ui/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Never fail invisibly: if startup throws, show the error in a window
  // instead of leaving a ghost process (PLAT-9 in spirit).
  try {
    final repo = await Repository.open();
    final app = AppState(repo);
    await app.init();
    runApp(OpenoteApp(app: app));
  } catch (e, st) {
    runApp(_StartupError(error: e, stack: st));
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

class OpenoteApp extends StatelessWidget {
  const OpenoteApp({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => MaterialApp(
        title: 'Openote',
        debugShowCheckedModeBanner: false,
        theme: onoteTheme(Brightness.light),
        darkTheme: onoteTheme(Brightness.dark),
        themeMode: app.themeMode, // View tab: Auto / Light / Dark
        home: AppShell(app: app),
      ),
    );
  }
}
