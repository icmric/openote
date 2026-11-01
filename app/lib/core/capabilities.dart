/// What this build can actually do, asked once and answered in one place.
///
/// **A feature declares the dependency it needs, not whether it is available.**
/// Most features depend on nothing platform-specific: they say nothing, they work
/// everywhere, and nobody has to think about them. One that needs something
/// native names the [Capability] it needs — and it has to anyway, because it
/// cannot compile for the web without a conditional import, and that seam is
/// where the answer comes from. The compiler is the reminder, which is stronger
/// than a convention.
///
/// [Capabilities.has] is a `switch` with no default arm, so adding a capability
/// without answering it is a compile error rather than a silent `false`.
///
/// **Every arm delegates to the check the production code already makes**, so the
/// value that greys out a button is the same value that drives the fallback
/// behind it. They cannot drift apart, because there is only one of them.
///
/// **What this does not catch:** a feature that quietly calls `dart:io` three
/// layers down. `dart:io` compiles on the web and throws when called, so that
/// failure is found by running the thing, not by reading it. The fail-soft
/// fallbacks are the backstop, and this is not a substitute for them.
library;

import '../code/js_engine_native.dart'
    if (dart.library.js_interop) '../code/js_engine_web.dart';
import '../media/video_engine_native.dart'
    if (dart.library.js_interop) '../media/video_engine_web.dart';
import '../store/workspace_fs.dart';
import 'onote_ffi.dart';

/// Something a feature needs from the platform underneath it.
///
/// Named for the dependency rather than for the feature, so that two features
/// needing the same thing cannot disagree about whether they have it.
enum Capability {
  /// A real filesystem: attaching a file, saving an export, opening an
  /// attachment in another application, pointing at a sync folder.
  ///
  /// The broadest one. A browser build keeps its whole workspace in memory, so
  /// everything that reaches the disk is off at once.
  localFiles,

  /// Watching a folder for another device's writes — `Directory.watch`, which
  /// has no web equivalent at all.
  ///
  /// Separate from [localFiles] because a browser can, on some engines, be
  /// handed a file to read and write. What it cannot be handed is a folder that
  /// tells you when it changed, and sync is built on exactly that.
  folderSync,

  /// Importing a OneNote `.one` / `.onepkg` section.
  onenoteImport,

  /// Decoding and playing a video file.
  video,

  /// **Running** the contents of a code block — not having one.
  ///
  /// The distinction matters: a code block is pure Dart, so writing one, picking
  /// its language and highlighting it all work in a browser. Only execution needs
  /// an engine. Do not gate the block itself on this.
  runCode,
}

abstract final class Capabilities {
  /// Can this build do [c]?
  ///
  /// A `switch` with no default arm on purpose — see the library comment.
  static bool has(Capability c) => switch (c) {
        Capability.localFiles => workspaceIsOnDisk,
        Capability.folderSync => workspaceCanWatchFolders,
        // The OneNote parser is the Rust core, and the core is a shared
        // library. `onote_ffi.dart` has always allowed it to be absent and
        // every caller already falls back; on the web it is absent for good.
        Capability.onenoteImport => OnoteCore.available,
        Capability.video => platformCanLoadEngine,
        // `js_engine_web.dart` explains why the browser's own engine is
        // declined rather than used.
        Capability.runCode => platformCanRunJs,
      };

  /// True on an ordinary desktop build, so a caller can skip assembling an
  /// explanation nobody will read.
  static bool get allPresent => Capability.values.every(has);
}
