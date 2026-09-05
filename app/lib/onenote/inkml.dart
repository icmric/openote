/// **Handwriting, out of InkML and into the shape the importer already takes.**
///
/// The owner wanted this route to match the `.onepkg` one: *"it also imports
/// inking, maths, images, its going to be the easier (or only) option for most
/// users, so i belive we need to make it as close to if not exactly parody if
/// possible."* Ink was the piece thought to be impossible, because a page's
/// HTML has no representation of a stroke.
///
/// It is not impossible. Asking for a page with `includeinkML=true` returns a
/// multipart body whose second part is `application/inkml+xml` — verified on a
/// real notebook, 301 traces on one page.
///
/// ## What OneNote's InkML looks like
///
/// Read off the wire, not out of the specification:
///
/// ```xml
/// <inkml:trace contextRef="#ctxCoordinatesWithPressure"
///              brushRef="#{…}{106}">2069 8152 15199, 2069 9773 15199</inkml:trace>
/// ```
///
///  * Points are comma-separated, values space-separated, in the channel order
///    the referenced context declares — `X Y` or `X Y F`.
///  * Coordinates are **himetric**: hundredths of a millimetre.
///  * Pressure is an integer against the channel's `max`, usually 32767.
///  * Brushes are declared once and referenced, carrying width, colour and
///    transparency.
///
/// ## What it produces
///
/// Exactly the `page['ink']` list the Rust parser produces for a `.one` file —
/// `{x, y, p, color, size, opacity}` in page pixels — so
/// `importOneParsedPage` turns it into an ink block with all the same code.
/// Nothing downstream can tell the two routes apart, which is the whole point.
library;

import 'package:xml/xml.dart';

/// Hundredths of a millimetre into the canvas's 120-dpi pixels.
///
/// One inch is 25.4 mm, so 2540 himetric; the canvas draws 120 px to the inch.
const double kHimetricToCanvas = 120.0 / 2540.0;

/// A stroke, in the shape `importOneParsedPage` already reads.
typedef InkStroke = Map<String, dynamic>;

/// Every stroke in an InkML document, in page pixels.
///
/// Returns an empty list for the common case: a page that was never drawn on
/// still carries an `<inkml:traceGroup />`, so the presence of the part proves
/// nothing and only its contents decide.
List<InkStroke> strokesFromInkML(String inkmlSource) {
  if (inkmlSource.trim().isEmpty) return const [];
  late XmlDocument doc;
  try {
    doc = XmlDocument.parse(inkmlSource);
  } on XmlException {
    // Handwriting that cannot be read costs the handwriting, never the page.
    return const [];
  }

  final contexts = _readContexts(doc);
  final brushes = _readBrushes(doc);
  final out = <InkStroke>[];

  for (final trace in _named(doc, 'trace')) {
    final channels =
        contexts[_ref(_attr(trace, 'contextRef'))] ?? const ['X', 'Y'];
    final brush = brushes[_ref(_attr(trace, 'brushRef'))];
    final points = _points(trace.innerText, channels);
    if (points.$1.length < 2) continue;
    out.add({
      'x': points.$1,
      'y': points.$2,
      'p': points.$3,
      if (brush?.color != null) 'color': brush!.color,
      'size': brush?.size ?? 2.0,
      'opacity': brush?.opacity ?? 1.0,
    });
  }
  return out;
}

/// Elements by LOCAL name, wherever they are.
///
/// OneNote writes everything prefixed — `<inkml:trace>`, `<inkml:brush>` — and
/// `findAllElements` matches the qualified name, so asking for `trace` found
/// nothing at all. Matching the local name works whether or not a prefix is
/// used, which also covers InkML written by anything else.
Iterable<XmlElement> _named(XmlDocument doc, String local) =>
    doc.descendants.whereType<XmlElement>().where((e) => e.name.local == local);

Iterable<XmlElement> _namedIn(XmlElement el, String local) =>
    el.descendants.whereType<XmlElement>().where((e) => e.name.local == local);

/// An attribute by local name, so `xml:id` and `id` are the same question.
String? _attr(XmlElement el, String local) {
  for (final a in el.attributes) {
    if (a.name.local == local) return a.value;
  }
  return null;
}

/// `#{id}` to `{id}`.
String _ref(String? raw) =>
    raw == null ? '' : (raw.startsWith('#') ? raw.substring(1) : raw);

/// Which channels each context declares, in order.
Map<String, List<String>> _readContexts(XmlDocument doc) {
  final out = <String, List<String>>{};
  for (final context in _named(doc, 'context')) {
    final id = _attr(context, 'id');
    if (id == null) continue;
    final names = <String>[
      for (final ch in _namedIn(context, 'channel')) _attr(ch, 'name') ?? '?',
    ];
    if (names.isNotEmpty) out[id] = names;
  }
  return out;
}

class _Brush {
  const _Brush({this.color, required this.size, required this.opacity});
  final String? color;
  final double size;
  final double opacity;
}

Map<String, _Brush> _readBrushes(XmlDocument doc) {
  final out = <String, _Brush>{};
  for (final brush in _named(doc, 'brush')) {
    final id = _attr(brush, 'id');
    if (id == null) continue;
    String? color;
    double? width;
    var transparency = 0.0;
    for (final p in _namedIn(brush, 'brushProperty')) {
      final name = _attr(p, 'name');
      final value = _attr(p, 'value') ?? '';
      switch (name) {
        case 'color':
          color = value.trim().isEmpty ? null : value.trim();
        case 'width':
          width = double.tryParse(value);
        case 'transparency':
          // 0–255 in OneNote's own writing, though it emits 0 almost always.
          transparency = (double.tryParse(value) ?? 0) / 255.0;
      }
    }
    out[id] = _Brush(
      // Black is what OneNote writes when the student never chose a colour,
      // and `auto` is the app's word for "whatever suits the theme" — which
      // is what keeps imported ink legible on a dark page. An explicit colour
      // is kept exactly.
      color: (color == null || color.toLowerCase() == '#000000') ? null : color,
      // The width is himetric too. Clamped to the same range the `.one`
      // importer clamps to, so a pen cannot arrive invisible or enormous.
      size: ((width ?? 25) * kHimetricToCanvas).clamp(0.6, 24.0),
      opacity: (1.0 - transparency).clamp(0.05, 1.0),
    );
  }
  return out;
}

/// `x`, `y` and pressure lists from one trace's text.
(List<double>, List<double>, List<double>) _points(
    String data, List<String> channels) {
  final xs = <double>[];
  final ys = <double>[];
  final ps = <double>[];
  final xAt = channels.indexOf('X');
  final yAt = channels.indexOf('Y');
  final fAt = channels.indexOf('F');
  if (xAt < 0 || yAt < 0) return (xs, ys, ps);

  for (final point in data.split(',')) {
    final parts = point.trim().split(RegExp(r'\s+'));
    if (parts.length <= (xAt > yAt ? xAt : yAt)) continue;
    final x = double.tryParse(parts[xAt]);
    final y = double.tryParse(parts[yAt]);
    if (x == null || y == null) continue;
    xs.add(x * kHimetricToCanvas);
    ys.add(y * kHimetricToCanvas);
    if (fAt >= 0 && parts.length > fAt) {
      final f = double.tryParse(parts[fAt]);
      // Against the channel's declared maximum, which OneNote sets to 32767.
      ps.add(f == null ? 1.0 : (f / 32767.0).clamp(0.0, 1.0));
    } else {
      ps.add(1.0);
    }
  }
  return (xs, ys, ps);
}
