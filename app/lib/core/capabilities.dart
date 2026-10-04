/// What this build can actually do, asked once and answered in one place.
///
/// ## The problem this solves
///
/// The browser demo shows the whole app, including the parts that do not work
/// there — the owner's requirement being that a prospective user *"can see,
/// for example, that it can take in videos and play them back, however the web
/// version itself can have the video button greyed out"*. That means the UI
/// has to know which features are real here.
///
/// The hard half of the requirement is the next sentence: *"I dont want this
/// to be too seperate of a thing either, like if i add new features in the
/// future it should add them in if it works, but grey it out if it doesnt,
/// without me having to go in and manually do stuff to set this."*
///
/// Neither obvious default satisfies that:
///
/// * **Default available** and a new feature appears enabled in the demo and
///   breaks when pressed — the worst outcome, in the one build whose whole job
///   is to make a good first impression.
/// * **Default unavailable** is safe but means every new feature needs a
///   manual classification, which is exactly the manual step being refused.
///
/// ## So this declares the dependency, not the availability
///
/// Most features depend on nothing platform-specific. They say nothing, they
/// work everywhere, and nobody has to think about them — that is the common
/// case and it costs zero. A feature that needs something native names the
/// [Capability] it needs, and it has to anyway: **it cannot compile for the
/// web without a conditional import, and that seam is where the answer comes
/// from.** The compiler is the reminder, which is stronger than a convention
/// and much stronger than remembering.
///
/// [has] is a `switch` over every [Capability] with no default arm, so adding
/// a capability without answering it is a compile error rather than a silent
/// `false`.
///
/// ## One fact, used twice
///
/// Every arm below delegates to the check the *production* code already makes
/// — `platformCanLoadEngine`, `platformStartJs`, `OnoteCore.available`. The
/// value that greys a button is therefore the same value that drives the
/// fallback behind it. They cannot drift apart, because there is only one of
/// them. A separate "is this on the web" list would be a second source of
/// truth and would be wrong within two releases.
///
/// ## What this cannot do
///
/// It catches features that *know* they need something. It will not catch one
/// that quietly calls `dart:io` three layers down: `dart:io` compiles to stubs
/// that throw when called, so that failure is found by running the thing, not
/// by reading it. The fail-soft fallbacks are the backstop for that, and this
/// is not a substitute for them.
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
  /// A real filesystem: picking a file to attach, saving an export, opening
  /// an attachment in another application, pointing at a sync folder.
  ///
  /// The single most load-bearing one. The browser demo keeps its whole
  /// workspace in memory, so everything that reaches the disk is off.
  localFiles,

  /// Watching a folder for another device's writes — `Directory.watch`, which
  /// has no web equivalent at all.
  ///
  /// Separate from [localFiles] because the distinction is the honest one: a
  /// browser could, on some engines, be handed a file to read and write. What
  /// it cannot be handed is a folder that tells you when it changed, and
  /// Openote's sync is built on exactly that.
  folderSync,

  /// Importing a OneNote `.one` / `.onepkg` section.
  onenoteImport,

  /// Decoding and playing a video file.
  video,

  /// Running the contents of a code block.
  codeBlocks,
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
        Capability.codeBlocks => platformCanRunJs,
      };

  /// True when every capability is present — i.e. an ordinary desktop build.
  /// Lets a caller skip assembling an explanation nobody will read.
  static bool get allPresent =>
      Capability.values.every(has);

}
