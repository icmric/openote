// Stop shipping the video engine inside the Windows installer.
//
// **The problem.** `media_kit_libs_windows_video` bundles seven native DLLs
// next to `openote.exe` — libmpv plus the whole ANGLE set. Measured on the
// v0.7.1 Release bundle they are 48,580,342 B of 97,831,741 B (49.7%), and
// they are dead weight for every user who never puts a lecture in a notebook.
// Nothing in them touches a byte of anybody's notes.
//
// **Why this cannot be done by deleting files after the build.** The linker
// records `libmpv-2.dll`, `libEGL.dll` and `libGLESv2.dll` as ordinary imports
// of `media_kit_video_plugin.dll`, and `openote.exe` imports that plugin the
// same way. Windows resolves both before a single line of Dart runs, so a
// bundle with the DLLs merely removed does not start Openote without video —
// it does not start Openote at all, with a loader message naming a DLL, and
// every notebook on the machine is unreachable. That is strictly worse than
// the problem being solved. (Verified with a PE import-table dump of the
// shipped 0.7.1 bundle; `flutter_windows.dll` imports none of the seven, which
// is what makes removing them safe for the rest of the app.)
//
// **The mechanism.** Two edits inside the pub cache, the same approach
// `strip_web_assets.dart` already uses and for the same reason — the
// alternative is repeating the work in every packaging path instead of once
// before the build:
//
//  1. `media_kit_video/windows/CMakeLists.txt` — link the three engine
//     libraries with `/DELAYLOAD`, so the plugin DLL loads with them absent
//     and the loader only goes looking when a video is actually played.
//     Registration is safe: `MediaKitVideoPlugin`'s constructor creates a
//     method channel and a thread pool and calls nothing in mpv or ANGLE.
//  2. `media_kit_libs_windows_video/windows/CMakeLists.txt` — empty its
//     `bundled_libraries` list, so `flutter build windows` stops copying the
//     seven DLLs into the Release directory. They stay where CMake downloaded
//     them (`build/windows/x64/{libmpv,ANGLE}`), which is where
//     `pack_video_engine.dart` picks them up to build the download.
//
// Idempotent, reversible (`--revert`), and it fails LOUDLY when the upstream
// text has moved rather than quietly saving nothing — a silent no-op here
// ships an installer that is 48 MB bigger than the release notes claim, or,
// far worse, one that has the DLLs stripped and the delay-load not applied.
//
// Windows only. Linux gets libmpv from the distribution (`mpv-libs`,
// `libmpv2`) and already has exactly this behaviour; macOS bundles an
// xcframework by a different mechanism and is untouched.
import 'dart:convert';
import 'dart:io';

/// The `target_link_libraries` block as `media_kit_video` 2.0.1 writes it. The
/// whole block is matched, not a fragment: a version that reorders or renames
/// these libraries needs a human to re-check that delay-loading is still the
/// right list, and a partial match would hide that.
const _linkAnchor = '''
  target_link_libraries(
    \${PLUGIN_NAME} PRIVATE
    flutter
    flutter_wrapper_plugin

    # Link to libmpv & ANGLE.
    "\${LIBMPV_SRC}/libmpv.dll.a"
    "\${ANGLE_SRC}/lib/libEGL.dll.lib"
    "\${ANGLE_SRC}/lib/libGLESv2.dll.lib"
  )''';

/// What replaces it. `delayimp.lib` is the MSVC helper that performs the
/// deferred `LoadLibrary`; without it the `/DELAYLOAD` flags are a link error,
/// not a silent no-op, which is the failure mode we want.
///
/// The libmpv import library is rebuilt rather than used as shipped, and that
/// is not gold-plating — it is the difference between this working and not.
/// mpv ships `libmpv.dll.a`, a GNU-format import library. MSVC links it by
/// resolving `__imp_` symbols directly, so as far as the linker is concerned
/// there are no *imports from libmpv-2.dll* to defer: it answers
/// `LNK4199: /DELAYLOAD:libmpv-2.dll ignored; no imports found`, emits an
/// ordinary load-time import anyway, and the app still refuses to start
/// without the DLL. Measured, on this exact tree, before the .def was added.
const _linkPatch = r'''
  # --- openote: video engine on demand (tool/split_video_engine.dart) ---
  # An MSVC import library for the seven mpv entry points this plugin uses,
  # built from a .def so the linker records them as imports OF libmpv-2.dll
  # and /DELAYLOAD below can actually defer them. A missing name here is a
  # link error naming the symbol, which is the right way to find out that
  # media_kit started calling something new.
  file(
    WRITE "${CMAKE_BINARY_DIR}/openote-libmpv-2.def"
    "LIBRARY libmpv-2.dll\nEXPORTS\n"
    "mpv_free_node_contents\n"
    "mpv_get_property\n"
    "mpv_render_context_create\n"
    "mpv_render_context_free\n"
    "mpv_render_context_render\n"
    "mpv_render_context_set_update_callback\n"
    "mpv_set_option_string\n"
  )
  set(OPENOTE_LIB_TOOL "${CMAKE_AR}")
  if(NOT OPENOTE_LIB_TOOL)
    set(OPENOTE_LIB_TOOL "lib")
  endif()
  execute_process(
    COMMAND
    "${OPENOTE_LIB_TOOL}" /NOLOGO
    "/DEF:${CMAKE_BINARY_DIR}/openote-libmpv-2.def"
    /MACHINE:X64
    "/OUT:${CMAKE_BINARY_DIR}/openote-libmpv-2.lib"
    RESULT_VARIABLE OPENOTE_MPV_LIB_RESULT
    OUTPUT_QUIET
  )
  if(NOT OPENOTE_MPV_LIB_RESULT EQUAL 0)
    message(
      FATAL_ERROR
      "openote: could not build the libmpv import library with "
      "${OPENOTE_LIB_TOOL}. Without it libmpv-2.dll stays a load-time "
      "dependency and the shipped app will not start at all."
    )
  endif()

  target_link_libraries(
    ${PLUGIN_NAME} PRIVATE
    flutter
    flutter_wrapper_plugin

    # Link to libmpv & ANGLE. Deferred, not removed: resolved at load time
    # these three make the whole app refuse to start when the engine is not
    # installed. Deferred, the loader only looks when the first video is
    # played, by which point media/video_engine.dart has put the downloaded
    # DLLs on the search path.
    delayimp.lib
    "${CMAKE_BINARY_DIR}/openote-libmpv-2.lib"
    "${ANGLE_SRC}/lib/libEGL.dll.lib"
    "${ANGLE_SRC}/lib/libGLESv2.dll.lib"
  )
  target_link_options(
    ${PLUGIN_NAME} PRIVATE
    "/DELAYLOAD:libmpv-2.dll"
    "/DELAYLOAD:libEGL.dll"
    "/DELAYLOAD:libGLESv2.dll"
  )
  # --- end openote ---''';

/// The bundle list as `media_kit_libs_windows_video` 1.0.11 writes it.
const _bundleAnchor = '''
set(
  media_kit_libs_windows_video_bundled_libraries
  "\${LIBMPV_SRC}/libmpv-2.dll"
  "\${ANGLE_SRC}/d3dcompiler_47.dll"
  "\${ANGLE_SRC}/libEGL.dll"
  "\${ANGLE_SRC}/libGLESv2.dll"
  "\${ANGLE_SRC}/vk_swiftshader.dll"
  "\${ANGLE_SRC}/vulkan-1.dll"
  "\${ANGLE_SRC}/zlib.dll"
  PARENT_SCOPE
)''';

const _bundlePatched = '''
# --- openote: video engine on demand (tool/split_video_engine.dart) ---
# Emptied, not deleted: the download and extract steps above still run, so the
# DLLs are on disk at build/windows/x64/{libmpv,ANGLE} for pack_video_engine
# to archive. They simply stop being copied next to openote.exe.
set(
  media_kit_libs_windows_video_bundled_libraries
  ""
  PARENT_SCOPE
)
# --- end openote ---''';

/// The seven files this removes from the bundle, relative to
/// `build/windows/x64/`. The order is the order they are loaded in.
const engineFiles = <String>[
  'libmpv/libmpv-2.dll',
  'ANGLE/d3dcompiler_47.dll',
  'ANGLE/libEGL.dll',
  'ANGLE/libGLESv2.dll',
  'ANGLE/vk_swiftshader.dll',
  'ANGLE/vulkan-1.dll',
  'ANGLE/zlib.dll',
];

void main(List<String> args) {
  final revert = args.contains('--revert');
  final config = File('.dart_tool/package_config.json');
  if (!config.existsSync()) {
    stderr.writeln('split_video_engine: no .dart_tool/package_config.json — '
        'run `flutter pub get` first.');
    exit(1);
  }
  final packages = (jsonDecode(config.readAsStringSync())
      as Map<String, dynamic>)['packages'] as List;

  Directory? rootOf(String name) {
    final pkg = packages
        .cast<Map<String, dynamic>>()
        .where((p) => p['name'] == name)
        .firstOrNull;
    if (pkg == null) return null;
    // rootUri is relative to .dart_tool/ and is a file: URI.
    return Directory.fromUri(
        config.parent.uri.resolve(pkg['rootUri'] as String));
  }

  var changed = 0;
  for (final job in [
    ('media_kit_video', _linkAnchor, _linkPatch),
    ('media_kit_libs_windows_video', _bundleAnchor, _bundlePatched),
  ]) {
    final (name, before, after) = job;
    final root = rootOf(name);
    if (root == null) {
      stdout.writeln('split_video_engine: $name not in this project — '
          'skipped.');
      continue;
    }
    final file = File('${root.path}/windows/CMakeLists.txt');
    if (!file.existsSync()) {
      stderr.writeln('split_video_engine: no windows/CMakeLists.txt in $name');
      exit(2);
    }
    final text = file.readAsStringSync();
    final want = revert ? after : before;
    final give = revert ? before : after;
    if (text.contains(give) && !text.contains(want)) {
      stdout.writeln('split_video_engine: $name already '
          '${revert ? 'restored' : 'split'}.');
      continue;
    }
    if (!text.contains(want)) {
      // Loud, not silent. Getting this wrong in either direction ships a
      // broken installer: un-split means the release notes lie about the
      // download size, half-split means Openote will not launch at all.
      stderr.writeln('split_video_engine: $name no longer contains the text '
          'this tool rewrites. The package changed. Re-check by hand that '
          'delay-loading is still correct before trusting the bundle size.');
      exit(2);
    }
    file.writeAsStringSync(text.replaceFirst(want, give));
    stdout.writeln(
        'split_video_engine: ${revert ? 'restored' : 'split'} $name');
    changed++;
  }
  stdout.writeln('split_video_engine: $changed package(s) '
      '${revert ? 'restored' : 'split'}.');
}
