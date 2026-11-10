/// Put copied or cut blocks on the system clipboard, so they paste into Word,
/// Google Docs, a Markdown file or a message.
///
/// Two flavours go on together: `text/plain` as Markdown, which anything that
/// reads Markdown can interpret, and `text/html` with the formatting, which
/// is what word processors take. Pictures ride in the HTML as data URIs and
/// are left out of the plain text; handwriting, graphs, boards and
/// attachments have no text form and are left out of both.
///
/// Openote's own paste does not read this back. It keeps the blocks themselves
/// (`AppState.pasteBlocks`), so a paste inside Openote is a copy of the real
/// thing, not a round trip through text.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:super_clipboard/super_clipboard.dart';

import '../markdown/md_to_html.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import 'markdown_export.dart' show pageMarkdownOf;

/// Largest picture embedded in the HTML flavour. A clipboard carrying tens of
/// megabytes of base64 stalls the app that pastes it.
const int kClipboardImageMax = 3 << 20;

/// The Markdown and HTML for [blocks], or null when they have no text form.
({String plain, String html})? blocksAsClipboardText(
    AppState app, List<Block> blocks) {
  final assets = <String, String>{};
  var md = pageMarkdownOf(app, '', blocks, assetsOut: assets);
  md = md.replaceFirst(RegExp(r'^# \n\n'), '');
  md = md.replaceAll(RegExp(r'^> _This page also contains .*$', multiLine: true), '');

  final plain = md
      .replaceAll(RegExp(r'^!\[[^\]]*\]\([^)]*\)\s*$', multiLine: true), '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
  if (plain.isEmpty && assets.isEmpty) return null;

  final byPath = {for (final e in assets.entries) e.value: e.key};
  final html = markdownToHtml(md, imageSrc: (path) {
    final hash = byPath[path];
    if (hash == null) return null;
    final bytes = app.blob(hash);
    if (bytes == null || bytes.length > kClipboardImageMax) return null;
    final ext = path.split('.').last.toLowerCase();
    final mime = switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'svg' => 'image/svg+xml',
      _ => 'image/png',
    };
    return 'data:$mime;base64,${base64Encode(bytes)}';
  });
  return (plain: plain, html: html);
}

/// Write [blocks] to the system clipboard. Returns the plain text that was
/// written, or null when nothing was (no text form, no clipboard, or the
/// write failed). Never throws: copying must not fail because another program
/// is holding the clipboard.
Future<String?> writeBlocksToSystemClipboard(
    AppState app, List<Block> blocks) async {
  try {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return null;
    final text = blocksAsClipboardText(app, blocks);
    if (text == null) return null;
    final item = DataWriterItem();
    if (text.plain.isNotEmpty) item.add(Formats.plainText(text.plain));
    item.add(Formats.htmlText(text.html));
    await clipboard.write([item]);
    return text.plain.isEmpty ? null : text.plain;
  } catch (e) {
    debugPrint('[openote/clipboard] could not write blocks: $e');
    return null;
  }
}
