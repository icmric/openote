/// What Openote was asked to open when the process started.
///
/// Two doors lead here and only one of them matters to the audience:
///
/// * **Double-clicking a notebook in the file manager.** Windows Explorer runs
///   `openote.exe "C:\...\Physics.onotebook\Open this notebook.onotelink"`,
///   and a Linux desktop runs `/opt/openote/openote /home/.../Physics.onotebook`
///   (the `%f` in `packaging/linux/org.openote.openote.desktop`). Both arrive
///   as an ordinary argument. This is the path a year-10 student actually uses.
/// * **`openote path/to/notebook.onotebook`** from a terminal, for people who
///   live there.
///
/// Both end up in the same one-element list, so there is one parser.
///
/// **A directory is an ordinary argument, and that is the point.** From v0.17
/// the notebook IS the `.onotebook` directory (plan Step 8b, decision 2), so
/// what arrives here is often a folder path. Every rule below — switches,
/// `--`, `file://` URLs, relative paths — applies to it unchanged, which is
/// why this file needed no new case. What the path turns out to be is
/// `core/open_target.dart`'s question, asked after this one is answered.
///
/// **Why this is a separate, dependency-free file.** `main()` receives raw
/// argv, and every interesting case in it — a relative path, a path with
/// spaces, an engine flag that is not a path at all, a `file://` URL from a
/// desktop portal — is decidable without touching the disk, a Repository or a
/// widget. Keeping it here is what lets `test/startup_args_test.dart` exercise
/// the real function instead of reasoning about it.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// The notebook named on the command line, as an absolute path — or null when
/// the app was simply launched.
///
/// [workingDirectory] defaults to the process's, and exists so a test can pin
/// one instead of mutating `Directory.current` for every other test in the
/// same isolate.
///
/// Rules, and the reason for each:
///
/// * **Anything starting with `-` is skipped.** The engine and the tooling put
///   their own switches on this command line, and macOS's Finder adds a
///   `-psn_0_12345` process serial number to every double-click launch. A
///   switch is never the notebook. (The cost: a file whose name genuinely
///   starts with a hyphen has to be given as `./-notes.onote`. That is the
///   same deal every Unix program offers, and `--` below is the escape hatch.)
/// * **`--` ends the switches.** Everything after it is taken literally.
/// * **The FIRST remaining argument wins.** Opening two notebooks at once has
///   no meaning in an app with one workspace window; the rest are ignored
///   rather than silently opening the last one.
/// * **Spaces need no handling at all, and that is worth saying out loud.**
///   Windows splits the command line with `CommandLineToArgvW`
///   (`app/windows/runner/utils.cpp`) and Linux never joins it, so
///   `C:\My Notes\Term 1.onote` arrives as one argument with its quotes
///   already stripped. Re-stripping quotes here would corrupt the (legal on
///   Linux) filename that contains one.
/// * **`file://` URLs are accepted.** `%f` in the desktop entry asks for a
///   path, but some launchers and portals hand over a URL regardless, and
///   `file:///home/e/My%20Notes.onote` is not a filename.
/// * **Relative paths are resolved here**, against the working directory the
///   process was started in — `openote notes/physics.onote` from a terminal.
///   Nothing downstream should have to wonder whether its path is absolute.
String? notebookPathFromArgs(List<String> args, {String? workingDirectory}) {
  var literal = false;
  for (final raw in args) {
    if (!literal && raw == '--') {
      literal = true;
      continue;
    }
    if (!literal && raw.startsWith('-')) continue;
    final arg = raw.trim();
    if (arg.isEmpty) continue;
    final path = _fromUrlOrPath(arg);
    if (path == null || path.isEmpty) continue;
    final cwd = workingDirectory ?? Directory.current.path;
    return p.normalize(p.isAbsolute(path) ? path : p.join(cwd, path));
  }
  return null;
}

/// A `file:` URL as a local path, or [arg] unchanged when it is already one.
///
/// Only `file:` — a launcher that hands over `https://…` is not naming a
/// notebook on this machine, and following it would be a fetch nobody asked
/// for. Returns null for those so the caller keeps looking.
String? _fromUrlOrPath(String arg) {
  // Cheap reject before parsing: a Windows path like `C:\x` parses as a URI
  // with scheme "c", and `Uri.parse` is not free on every argument.
  if (!arg.contains('://')) return arg;
  final uri = Uri.tryParse(arg);
  if (uri == null || !uri.hasScheme) return arg;
  if (uri.scheme.toLowerCase() != 'file') return null;
  try {
    return uri.toFilePath(windows: Platform.isWindows);
  } catch (_) {
    // A file: URL this platform cannot express as a path (a UNC host we do not
    // understand, say). Better to look at the next argument than to throw out
    // of main().
    return null;
  }
}
