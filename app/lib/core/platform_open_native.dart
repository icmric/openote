/// The desktop half of [PlatformOpen], behind a conditional import.
///
/// `dart:ffi` does not exist on the web and importing it is a hard compile
/// error, so `ShellExecuteW` lives here. See `platform_open_web.dart` for the
/// other side and `platform_open.dart` for the class that chooses — including
/// the security property this file exists to preserve: the target is always
/// **one parameter to a program**, never a fragment of a command line that
/// something else will re-parse.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

bool platformFileExists(String path) => File(path).existsSync();

bool platformDirectoryExists(String path) => Directory(path).existsSync();

Future<bool> platformHandOff(String target) async {
  try {
    if (Platform.isWindows) return _shellExecute(target);
    // `Process.start` with an argument LIST goes straight to execve — the
    // target is argv[1] and no shell ever sees it, so metacharacters in a
    // note's link are inert.
    await Process.start(Platform.isMacOS ? 'open' : 'xdg-open', [target]);
    return true;
  } catch (_) {
    return false; // no handler registered, or the launcher is missing
  }
}

/// Windows: `ShellExecuteW`, **not** `cmd /c start`.
///
/// This replaced `Process.start('cmd', ['/c', 'start', '', target])`, and the
/// reason is worth keeping. `cmd.exe` does not parse its command line the way
/// the C runtime does: it applies its own metacharacter handling — `&`, `|`,
/// `^`, `<`, `>` — to whatever it receives, *after* the ordinary argument
/// quoting has been applied. Ordinary quoting therefore does not neutralise
/// them. And `&` is perfectly legal in a URL (it separates query parameters),
/// so the scheme allow-list does not help either: a link in an imported or
/// shared notebook could carry one.
///
/// I have not demonstrated an exploit — that needs a Windows box this
/// development environment does not have — and the claim here is deliberately
/// the weaker one: **we were handing attacker-controlled text to a command
/// interpreter, and there is no reason to.** `ShellExecuteW` is the actual
/// Win32 API for "open this with its default handler". It takes the target as
/// a single wide-string parameter, so there is no command line and nothing to
/// parse. It is also what every other implementation of this function uses.
///
/// Returns false on any failure code. `ShellExecuteW` reports success as an
/// HINSTANCE greater than 32, which is a historical quirk rather than a typo.
bool _shellExecute(String target) {
  final op = 'open'.toNativeUtf16();
  final file = target.toNativeUtf16();
  try {
    final r = _shellExecuteW(0, op, file, nullptr, nullptr, _swShowNormal);
    return r > 32;
  } finally {
    calloc
      ..free(op)
      ..free(file);
  }
}

const int _swShowNormal = 1;

final _shellExecuteW = DynamicLibrary.open('shell32.dll').lookupFunction<
    IntPtr Function(IntPtr hwnd, Pointer<Utf16> operation, Pointer<Utf16> file,
        Pointer<Utf16> params, Pointer<Utf16> directory, Int32 showCmd),
    int Function(int hwnd, Pointer<Utf16> operation, Pointer<Utf16> file,
        Pointer<Utf16> params, Pointer<Utf16> directory,
        int showCmd)>('ShellExecuteW');
