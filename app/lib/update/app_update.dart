/// Update through the app (PLANNING.md, shipped v0.7.0).
///
/// The shape: a silent check against GitHub's latest-release API on every
/// launch; when something newer exists, a button appears in the command
/// bar. Clicking it opens a dialog that saves everything, downloads the
/// Windows installer with a progress bar behind a modal barrier, then runs
/// it silently and exits — the installer replaces the files and relaunches
/// Openote itself (the .iss has a silent-mode relaunch entry). Platforms
/// without an installer artifact get an "open the download page" button
/// instead of a pretend-automatic flow.
///
/// Every network path here fails SILENT and NULL: an update check must
/// never cost a user who is offline, rate-limited, or behind a captive
/// portal anything at all.
library;

import 'dart:convert';
import 'dart:io';

import '../markdown/md_syntax.dart';

/// The running app's version. pubspec.yaml is the source of truth;
/// app_update_test.dart fails the build the moment the two drift.
const kAppVersion = '0.8.0';

const _kLatestReleaseApi =
    'https://api.github.com/repos/icmric/openote/releases/latest';

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.pageUrl,
    this.notes,
    this.windowsSetupUrl,
  });

  final String version;

  /// The human release page — the fallback for every platform.
  final String pageUrl;
  final String? notes;

  /// The `-setup.exe` asset, when the release has one.
  final String? windowsSetupUrl;
}

/// Numeric dotted-version compare. Tolerates a leading `v`, a `+build`
/// suffix and unequal segment counts; 0.10.0 beats 0.9.9.
int compareVersions(String a, String b) {
  List<int> parts(String v) {
    var s = v.trim();
    if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
    final plus = s.indexOf('+');
    if (plus >= 0) s = s.substring(0, plus);
    final dash = s.indexOf('-');
    if (dash >= 0) s = s.substring(0, dash);
    return [for (final p in s.split('.')) int.tryParse(p) ?? 0];
  }

  final pa = parts(a), pb = parts(b);
  for (var i = 0; i < (pa.length > pb.length ? pa.length : pb.length); i++) {
    final va = i < pa.length ? pa[i] : 0;
    final vb = i < pb.length ? pb[i] : 0;
    if (va != vb) return va - vb;
  }
  return 0;
}

/// Pure half of the check, so tests can feed it release JSON directly.
/// Returns null when there is nothing newer to offer.
UpdateInfo? parseLatestRelease(
    {required String current, required Map<String, dynamic> json}) {
  if (json['draft'] == true || json['prerelease'] == true) return null;
  final tag = '${json['tag_name'] ?? ''}';
  final version = tag.startsWith('v') ? tag.substring(1) : tag;
  if (version.isEmpty || compareVersions(version, current) <= 0) return null;

  String? setup;
  final assets = json['assets'];
  if (assets is List) {
    for (final a in assets.whereType<Map>()) {
      if ('${a['name']}'.endsWith('-setup.exe')) {
        setup = a['browser_download_url'] as String?;
      }
    }
  }
  return UpdateInfo(
    version: version,
    notes: json['body'] as String?,
    windowsSetupUrl: setup,
    pageUrl: json['html_url'] as String? ??
        'https://github.com/icmric/openote/releases',
  );
}

/// The launch-time check. Null on ANY failure, by design.
Future<UpdateInfo?> fetchLatestUpdate({String current = kAppVersion}) async {
  try {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(_kLatestReleaseApi));
      req.headers.set(HttpHeaders.userAgentHeader, 'openote/$current');
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final json = jsonDecode(await utf8.decodeStream(res));
      if (json is! Map<String, dynamic>) return null;
      return parseLatestRelease(current: current, json: json);
    } finally {
      client.close();
    }
  } catch (_) {
    return null;
  }
}

// ── The release body, made fit to show ────────────────────────────────────
//
// The dialog renders the GitHub release body with the SAME Markdown renderer
// notes use (markdown/md_render.dart), so `**bold**` finally arrives as bold
// rather than as four visible asterisks. That renderer reads a note, though,
// and a note is not a GitHub release body. Three concrete differences bite,
// and this is where each is dealt with — before any widget sees the text.

/// `<!-- … -->`, across lines. GitHub hides comments; our renderer has no
/// idea what one is and would print it.
final _reHtmlComment = RegExp(r'<!--.*?-->', dotAll: true);

/// Four or more leading spaces: a code block in Markdown, so its line breaks
/// are content and must survive the reflow below.
final _reIndentedCode = RegExp(r'^ {4,}\S');

/// A heading at any level. Wider than the renderer's own 1–3 on purpose: a
/// `#### x` it will not style is still a line that must not be swallowed by
/// the paragraph above it.
final _reAnyHeading = RegExp(r'^#{1,6}[ \t]');

/// A pipe-table row. `md_table` parses a table as a run of consecutive lines,
/// so folding the first row into the paragraph above destroys the whole table.
final _reTableRow = RegExp(r'^\s*\|');

/// An image line, and a raw HTML block. Neither is prose to be joined.
final _reImageLine = RegExp(r'^\s*!\[');
final _reHtmlBlock = RegExp(r'^\s*<');

/// How much of a release body the dialog will show. The renderer builds one
/// widget per line into a plain `Column` — nothing is lazy — so a body that
/// arrives with hundreds of generated pull-request lines would build
/// thousands of widgets before the dialog could paint. GitHub's own limit on
/// a release body is 125 000 characters.
const int kReleaseNotesMaxChars = 20000;

/// True when [line] opens a new block, so it can never be a continuation of
/// the line before it.
bool _startsBlock(String line) {
  final l = line.trimLeft();
  return _reAnyHeading.hasMatch(l) ||
      mdBulletRe.hasMatch(line) ||
      mdNumberedRe.hasMatch(line) ||
      mdCheckboxRe.hasMatch(line) ||
      mdQuoteRe.hasMatch(l) ||
      mdDividerRe.hasMatch(line) ||
      _reTableRow.hasMatch(line) ||
      _reImageLine.hasMatch(line) ||
      _reHtmlBlock.hasMatch(line);
}

/// True when [line] is a block that prose may be appended to — a paragraph, a
/// list item or a quote. A heading, rule, table row or image is not.
bool _acceptsContinuation(String line) {
  if (line.trim().isEmpty) return false;
  // An indented code line. Prose that follows one at column 0 ENDS the code
  // block, so appending it would move that sentence inside the command.
  if (_reIndentedCode.hasMatch(line)) return false;
  final l = line.trimLeft();
  // A fence marker, in particular the CLOSING one: appending the next
  // paragraph to it would put that paragraph inside the code block.
  if (l.startsWith('```')) return false;
  return !(_reAnyHeading.hasMatch(l) ||
      mdDividerRe.hasMatch(line) ||
      _reTableRow.hasMatch(line) ||
      _reImageLine.hasMatch(line) ||
      _reHtmlBlock.hasMatch(line));
}

/// Fold soft-wrapped lines back into the block they belong to.
///
/// A release body is hard-wrapped in the workflow file at about seventy
/// columns, because it lives inside YAML. Markdown — and therefore GitHub,
/// where these notes are also read — joins those lines into one paragraph.
/// Our renderer is line-based and would instead draw each wrapped fragment as
/// its own paragraph at zero indent, so a bullet's second line fell out from
/// under its bullet and the whole panel came out ragged. Folding here makes
/// the dialog show what GitHub shows.
List<String> _reflow(List<String> lines) {
  final out = <String>[];
  var inFence = false;
  for (final line in lines) {
    if (line.trimLeft().startsWith('```')) {
      inFence = !inFence;
      out.add(line);
      continue;
    }
    // Inside a fence every line break is content.
    if (inFence || line.trim().isEmpty) {
      out.add(line);
      continue;
    }
    // Note there is no test for an indented line HERE. Markdown does not let
    // an indented code block interrupt a paragraph either — `Some prose:` /
    // `    code` with no blank line between them is one paragraph on GitHub
    // too — so refusing to fold it would have made us differ from the page
    // this text is also read on. The guard that matters is the one in
    // [_acceptsContinuation]: nothing gets appended to a code line.
    if (out.isNotEmpty && _acceptsContinuation(out.last) && !_startsBlock(line)) {
      out[out.length - 1] = '${out.last.trimRight()} ${line.trim()}';
    } else {
      out.add(line);
    }
  }
  return out;
}

/// A GitHub release body, ready for the note renderer.
///
/// Never throws and never returns something unshowable: this text is the only
/// description a user gets of an update they are being asked to install, and
/// a tidying step must not be the reason the offer fails to appear. Anything
/// unexpected falls back to the body as it arrived, which is exactly what the
/// dialog used to show.
String tidyReleaseNotes(String raw, {int maxChars = kReleaseNotesMaxChars}) {
  try {
    // GitHub returns CRLF. A stray `\r` rides along at the end of every line
    // into whatever the renderer measures and draws.
    var s = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    s = s.replaceAll(_reHtmlComment, '');
    var text = _reflow(s.split('\n')).join('\n').trim();
    // Stripping a comment leaves the blank lines that surrounded it.
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    if (text.length > maxChars) {
      // Cut at a line boundary — half a sentence looks like a bug.
      final nl = text.lastIndexOf('\n', maxChars);
      text = '${text.substring(0, nl > 0 ? nl : maxChars).trimRight()}\n\n'
          'There is more to read on the download page.';
    }
    return text;
  } catch (_) {
    return raw.trim();
  }
}

/// Stream a release asset to [toPath]. GitHub asset URLs redirect to a
/// CDN; HttpClient follows redirects on GET by itself. Null on failure.
Future<File?> downloadUpdate(String url, String toPath,
    {void Function(int received, int total)? onProgress}) async {
  try {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader, 'openote/$kAppVersion');
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final total = res.contentLength;
      final file = File(toPath);
      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final chunk in res) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        await sink.close();
      }
      // A truncated download must not be handed to the OS as an installer.
      if (total > 0 && received != total) {
        try {
          file.deleteSync();
        } catch (_) {}
        return null;
      }
      return file;
    } finally {
      client.close();
    }
  } catch (_) {
    return null;
  }
}
