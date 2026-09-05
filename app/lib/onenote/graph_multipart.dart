/// **Splitting the two halves of a page.**
///
/// Asked for with `includeinkML=true`, a page comes back as a MIME multipart
/// body rather than as HTML: one part `text/html`, one part
/// `application/inkml+xml`. Both are needed — the HTML has everything typed
/// and the InkML has everything written by hand — and neither is optional if
/// this route is to match what a `.onepkg` import produces.
///
/// The boundary is read **from the body** rather than from the response's
/// `Content-Type` header, and that is deliberate: the same body arrives two
/// ways. A plain request carries the header; a `$batch` sub-response carries
/// its headers inside JSON and, depending on how the body was encoded, the
/// header may not survive to the point of parsing. The first line of a
/// multipart body is always its own boundary, so reading it from there works
/// for both and cannot disagree with itself.
library;

/// A page as Graph sent it.
class GraphPageBody {
  const GraphPageBody({required this.html, this.inkml});

  final String html;

  /// The InkML part, when there was one. Present but empty on most pages:
  /// every page carries an `<inkml:traceGroup />` whether or not anything was
  /// ever drawn on it, so its presence proves nothing and its contents decide.
  final String? inkml;
}

/// Read a page body, whether or not it turned out to be multipart.
///
/// A body that is not multipart is the whole HTML, which is what a request
/// without `includeinkML` returns and what an older server might return
/// anyway. Being tolerant of both means the ink request can be made
/// unconditionally.
GraphPageBody readPageBody(String body) {
  final boundary = _boundaryOf(body);
  if (boundary == null) return GraphPageBody(html: body);

  String? html;
  String? inkml;
  for (final part in _parts(body, boundary)) {
    final split = _headersAndBody(part);
    if (split == null) continue;
    final (headers, content) = split;
    final type = headers['content-type'] ?? '';
    if (type.contains('inkml')) {
      inkml = content;
    } else if (type.contains('html') || html == null) {
      // The `html == null` arm is the tolerant one: a part with a type this
      // does not recognise is more likely to be the page than to be nothing,
      // and a page that imports without its ink beats one that imports as
      // nothing at all.
      html = content;
    }
  }
  return GraphPageBody(html: html ?? body, inkml: inkml);
}

/// The boundary this body uses, from its own first line.
String? _boundaryOf(String body) {
  final firstBreak = body.indexOf('\n');
  if (firstBreak <= 0) return null;
  final first = body.substring(0, firstBreak).trim();
  // At least one character after the two dashes. The bound used to be four,
  // which quietly refused a short boundary and returned the whole body as
  // HTML — the ink silently gone, with nothing raised anywhere. Real
  // boundaries are GUIDs so it never bit in practice, but "never in practice"
  // is not a reason to keep an arbitrary limit that fails silently.
  if (!first.startsWith('--') || first.length < 3) return null;
  // A closing delimiter has a trailing `--`; the opening one does not, and it
  // is the opening one that names the boundary.
  final name = first.substring(2);
  return name.endsWith('--') ? name.substring(0, name.length - 2) : name;
}

Iterable<String> _parts(String body, String boundary) sync* {
  final delimiter = '--$boundary';
  var at = body.indexOf(delimiter);
  if (at < 0) return;
  at += delimiter.length;
  while (at < body.length) {
    final next = body.indexOf(delimiter, at);
    final end = next < 0 ? body.length : next;
    final chunk = body.substring(at, end);
    if (chunk.trimLeft().startsWith('--')) return; // the closing delimiter
    yield chunk;
    if (next < 0) return;
    at = next + delimiter.length;
  }
}

/// One part's headers and its content, or null when it has no blank-line
/// separator and is therefore not a part at all.
(Map<String, String>, String)? _headersAndBody(String part) {
  final trimmed = part.replaceFirst(RegExp(r'^\r?\n'), '');
  // The blank line between headers and content, in either line ending.
  var split = trimmed.indexOf('\r\n\r\n');
  var skip = 4;
  if (split < 0) {
    split = trimmed.indexOf('\n\n');
    skip = 2;
  }
  if (split < 0) return null;
  final headers = <String, String>{};
  for (final line in trimmed.substring(0, split).split(RegExp(r'\r?\n'))) {
    final colon = line.indexOf(':');
    if (colon <= 0) continue;
    headers[line.substring(0, colon).trim().toLowerCase()] =
        line.substring(colon + 1).trim().toLowerCase();
  }
  return (headers, trimmed.substring(split + skip));
}
