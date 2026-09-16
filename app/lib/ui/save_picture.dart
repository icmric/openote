/// **Writing a picture out of a note — one definition, two menus.**
///
/// A picture reaches a page in two shapes, and only one of them is a block.
/// Dropping a file onto empty canvas makes a `BlockType.image`; Ctrl+V at the
/// caret, a drop onto an existing text box, and Insert ▸ Image all splice
/// `![](sha256:…)` into a paragraph's own Markdown instead. Three routes of
/// four produce the second shape, so it is the common one.
///
/// The first version of "Save image as…" asked `pictureIn(Block)`, which can
/// only see the first shape — so the owner tried it on a pasted picture,
/// found nothing in either menu, and reported the feature as missing. It was
/// not missing; it was answering a question about blocks while the picture was
/// characters in a sentence.
///
/// This file exists so that cannot happen again: the block menu and the
/// paragraph's own menu call the same function, and the question "where is the
/// picture" is answered next to each menu rather than once, in the wrong
/// place. See `pictureRefAt` in `live_markdown_controller.dart` for the in-flow
/// half, and `pictureIn` in `context_menus.dart` for the block half.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../store/repository.dart';

/// The extension for [mime], defaulting to `png`.
///
/// Neither shape of picture records a filename — not a drop, not a paste, not
/// the Insert menu — so the suggested name is built rather than remembered.
/// Getting the extension right is the part that matters: it is what decides
/// whether the saved file opens by double-click.
@visibleForTesting
String extForMime(String? mime) => switch (mime) {
      'image/jpeg' => 'jpg',
      'image/gif' => 'gif',
      'image/webp' => 'webp',
      'image/bmp' => 'bmp',
      'image/svg+xml' => 'svg',
      _ => 'png',
    };

/// The name to suggest for [bytes], from what the caller knows and, failing
/// that, from the bytes themselves.
///
/// An in-flow reference carries no mime — it is `![](sha256:…)` and nothing
/// else — so there is nothing to pass. Sniffing is not a fallback so much as
/// the more honest answer: it describes what is actually about to be written,
/// where a recorded mime only describes what something once claimed.
@visibleForTesting
String suggestedPictureName(Uint8List bytes, {String? mime, String base = 'image'}) =>
    '$base.${extForMime(mime ?? Repository.sniffMime(bytes))}';

/// **Write a picture out under a name the person chooses.**
///
/// [notHereYet] is said when there are no bytes to write. Deliberately not
/// "missing": the two halves of a picture travel separately, so a reference
/// whose blob has not landed yet is *expected*, not lost — the same wait the
/// placeholder on the canvas is already describing.
Future<void> savePictureBytes(
  BuildContext context,
  Uint8List? bytes, {
  String? mime,
  String base = 'image',
  required String notHereYet,
}) async {
  void say(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  if (bytes == null) {
    say(notHereYet);
    return;
  }
  final loc = await getSaveLocation(
      suggestedName: suggestedPictureName(bytes, mime: mime, base: base));
  if (loc == null) return;
  try {
    await File(loc.path).writeAsBytes(bytes);
  } catch (e) {
    if (context.mounted) say("That copy didn't save: $e");
    return;
  }
  if (context.mounted) say('Saved to ${loc.path}');
}
