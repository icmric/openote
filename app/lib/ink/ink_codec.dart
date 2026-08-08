/// Handwriting as bytes instead of as decimal text.
///
/// **The measurement that motivated this.** A real imported notebook's op log
/// was 67.7 MB, and 63.1 MB of it was 113 ink blocks: 64,616 strokes,
/// 1,828,431 points, at **36.2 bytes per point** — because a point was
/// `[123.45678901234567,456.78901234567890]` in JSON, and the same JSON was
/// stored a second time in the container's page mirror. Two thirds of the
/// notebook was somebody's handwriting written out as ASCII decimal floats,
/// twice.
///
/// The same content through this codec is **1.86 bytes per point** deflated —
/// a 19.4× reduction, against 3.6× for simply gzipping the JSON. Three choices
/// account for it, and each was measured rather than assumed:
///
/// * **Quantise to 1/16 px.** A stroke is drawn as a path in a space the
///   canvas already treats as integers, and the maximum zoom is 8×, so 1/16 px
///   is a quarter of a device pixel at full magnification — below anything a
///   screen can show. Storing 17 significant digits of a coordinate that came
///   off a digitiser with 3 was the single biggest waste.
/// * **Delta between consecutive points.** Adjacent samples of one stroke are
///   a pixel or two apart, so a delta is one varint byte where an absolute
///   value is two or three.
/// * **Column-major, not point-major.** All the x deltas, then all the y
///   deltas, then pressure. Same bytes, but like values sit together and
///   deflate finds far more to work with: measured 3.68 MB against 4.06 MB for
///   the interleaved form, for free.
///
/// A float32 alternative was measured too, at 3.7× raw and 5.3× deflated, and
/// is not offered — it is four times the size for no simplicity worth having.
///
/// **No Flutter imports**, so this runs inside `Isolate.run` for the migration
/// and the importer. Encoding is deterministic: the same strokes always produce
/// the same bytes, which is what makes the blobs content-addressable and the
/// round-trip testable byte-for-byte.
library;

import 'dart:convert';
import 'dart:io' show ZLibCodec;
import 'dart:math' as math;
import 'dart:typed_data';

import '../model/models.dart';

/// The mime type these blobs are stored under, beside the container's images.
const String inkMimeType = 'application/x-onote-ink+binary';

/// `OIS1` — Openote Ink Strokes, version 1.
const int _magic0 = 0x4F, _magic1 = 0x49, _magic2 = 0x53, _magic3 = 0x31;

/// Quantisation units per page pixel.
///
/// 16 gives 0.0625 px, which at the canvas's maximum 8× zoom is 0.0078 px on
/// screen. The Ink Data Spec previously promised 0.01 px in JSON; this is finer
/// than that in the only place it matters (on screen at full zoom) while being
/// dramatically smaller.
const int kInkScale = 16;

/// Pressure is stored as a byte. A digitiser reports 0–1 with far less than
/// 8 bits of real resolution, and 1/255 is invisible in stroke width.
const int _pressureSteps = 255;

/// Tilt in 1/64 of whatever unit the source used, round-tripped rather than
/// interpreted — see [Stroke.tx].
const int _tiltScale = 64;

class _Writer {
  // `copy: true` (the default), and `addByte` rather than `add` of a reused
  // one-byte buffer. With `copy: false` the builder retains a REFERENCE to
  // whatever list it is handed, so a reused scratch buffer makes every byte
  // written so far read back as the last one — the encoder produced a
  // 6-byte-magic header of four identical bytes and nothing decoded at all.
  final BytesBuilder _b = BytesBuilder();

  void u8(int v) => _b.addByte(v & 0xFF);

  /// LEB128. Sizes, counts and non-negative scalars.
  void uvar(int v) {
    assert(v >= 0, 'uvar cannot encode $v');
    var x = v;
    while (x >= 0x80) {
      u8((x & 0x7F) | 0x80);
      x >>= 7;
    }
    u8(x);
  }

  /// Zigzag then LEB128. Deltas, which are as often negative as positive.
  void svar(int v) => uvar((v << 1) ^ (v >> 63));

  void bytes(List<int> v) => _b.add(v);

  Uint8List take() => _b.takeBytes();
  int get length => _b.length;
}

class _Reader {
  _Reader(this.d) : _i = 0;
  final Uint8List d;
  int _i;

  bool get done => _i >= d.length;
  int get offset => _i;

  int u8() {
    if (_i >= d.length) throw const FormatException('ink: truncated');
    return d[_i++];
  }

  int uvar() {
    var result = 0, shift = 0;
    while (true) {
      final b = u8();
      result |= (b & 0x7F) << shift;
      if (b < 0x80) return result;
      shift += 7;
      if (shift > 63) throw const FormatException('ink: varint too long');
    }
  }

  int svar() {
    final u = uvar();
    return (u >>> 1) ^ -(u & 1);
  }
}

/// What a blob says about itself without decoding its point columns.
///
/// Enough for layout and for the box-fitting the canvas does on selection,
/// which is why those paths never have to inflate megabytes of geometry.
class InkHeader {
  const InkHeader({
    required this.strokeCount,
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
  });

  final int strokeCount;

  /// Blob-local bounds, in page pixels relative to the blob's origin.
  final double minX, minY, maxX, maxY;

  double get width => maxX - minX;
  double get height => maxY - minY;
}

abstract final class InkCodec {
  /// Deflate anything above this. Below it the zlib header costs more than it
  /// saves, and a single erased fragment is genuinely tiny.
  static const int _deflateAbove = 256;

  static final ZLibCodec _zlib = ZLibCodec(level: 9);

  /// True when [bytes] look like this format at all.
  static bool looksLikeInk(Uint8List bytes) =>
      bytes.length >= 6 &&
      bytes[0] == _magic0 &&
      bytes[1] == _magic1 &&
      bytes[2] == _magic2 &&
      bytes[3] == _magic3;

  /// Encode [strokes] with coordinates stored relative to
  /// ([originX], [originY]).
  ///
  /// **Blob-local coordinates are the point.** Storing page-absolute positions
  /// would mean that dragging an ink block changed every byte of its blob, so a
  /// move would write a new multi-hundred-kilobyte object; and a
  /// content-addressed store would keep the old one too. Relative to an origin
  /// the block carries, a drag is two numbers on the block and zero new bytes.
  ///
  /// It also keeps the deltas small in absolute terms, which matters: the real
  /// notebook contains an imported block whose page coordinates reach
  /// x = 1,312,485.
  static Uint8List encode(
    List<Stroke> strokes, {
    required double originX,
    required double originY,
    int scale = kInkScale,
    bool deflate = true,
  }) {
    final w = _Writer();

    // Brushes are deduplicated: a page of handwriting is usually one pen, and
    // repeating tool/colour/size/opacity per stroke was ~40 bytes each.
    final brushKeys = <String>[];
    final brushIx = <String, int>{};
    for (final s in strokes) {
      final k = '${s.tool}|${s.colorHex}|${s.size}|${s.opacity}';
      if (brushIx.containsKey(k)) continue;
      brushIx[k] = brushKeys.length;
      brushKeys.add(k);
    }

    var anyPressure = false, anyTime = false, anyTilt = false;
    for (final s in strokes) {
      if (s.p.isNotEmpty) anyPressure = true;
      if (s.t.isNotEmpty) anyTime = true;
      if (s.tx.isNotEmpty || s.ty.isNotEmpty) anyTilt = true;
    }

    // Bounds, in quantised units, computed here so a reader never has to
    // decode points to lay out a block.
    var minQx = 0, minQy = 0, maxQx = 0, maxQy = 0;
    var first = true;
    int qx(double v) => ((v - originX) * scale).round();
    int qy(double v) => ((v - originY) * scale).round();
    for (final s in strokes) {
      for (var i = 0; i < s.x.length; i++) {
        final a = qx(s.x[i]);
        final b = i < s.y.length ? qy(s.y[i]) : 0;
        if (first) {
          minQx = maxQx = a;
          minQy = maxQy = b;
          first = false;
        } else {
          if (a < minQx) minQx = a;
          if (a > maxQx) maxQx = a;
          if (b < minQy) minQy = b;
          if (b > maxQy) maxQy = b;
        }
      }
    }

    // The base time is subtracted from every stroke's start, so a notebook
    // written in 2026 does not pay 13 digits of epoch per stroke.
    var baseTime = 0;
    if (strokes.isNotEmpty) {
      baseTime = strokes.first.strokeStart;
      for (final s in strokes) {
        if (s.strokeStart < baseTime) baseTime = s.strokeStart;
      }
      if (baseTime < 0) baseTime = 0;
    }

    w
      ..u8(_magic0)
      ..u8(_magic1)
      ..u8(_magic2)
      ..u8(_magic3)
      ..u8(1) // version
      ..u8(0); // method, patched below if deflated

    final body = _Writer()
      ..u8((anyPressure ? 1 : 0) | (anyTime ? 2 : 0) | (anyTilt ? 4 : 0))
      ..uvar(scale)
      ..uvar(strokes.length)
      ..svar(minQx)
      ..svar(minQy)
      ..svar(maxQx)
      ..svar(maxQy)
      ..uvar(brushKeys.length);

    for (final k in brushKeys) {
      final parts = k.split('|');
      body.u8(parts[0] == 'highlighter' ? 1 : 0);
      final hex = parts[1];
      // A colour outside `#RRGGBB` is round-tripped as a string rather than
      // dropped: the format spec's rule is that unknown data survives, and
      // `Stroke.colorHex` is whatever the file said.
      if (hex.length == 7 && hex.startsWith('#')) {
        body.u8(1);
        body.u8(int.parse(hex.substring(1, 3), radix: 16));
        body.u8(int.parse(hex.substring(3, 5), radix: 16));
        body.u8(int.parse(hex.substring(5, 7), radix: 16));
      } else {
        final raw = utf8.encode(hex);
        body
          ..u8(2)
          ..uvar(raw.length)
          ..bytes(raw);
      }
      body
        ..uvar((double.parse(parts[2]) * 64).round().clamp(0, 1 << 30))
        ..u8((double.parse(parts[3]) * 255).round().clamp(0, 255));
    }
    body.uvar(baseTime);

    // Stroke table: everything but the point columns.
    for (final s in strokes) {
      final hasP = s.p.isNotEmpty;
      final hasT = s.t.isNotEmpty;
      final hasTilt = s.tx.isNotEmpty || s.ty.isNotEmpty;
      body
        ..u8((hasP ? 1 : 0) | (hasT ? 2 : 0) | (hasTilt ? 4 : 0))
        ..uvar(brushIx['${s.tool}|${s.colorHex}|${s.size}|${s.opacity}']!)
        ..uvar(math.max(0, s.strokeStart - baseTime))
        ..uvar(s.x.length);
    }

    // Columns. The running value resets at each stroke boundary, so a stroke's
    // first point is an absolute (quantised) coordinate and the rest are steps.
    for (final s in strokes) {
      var prev = 0;
      for (final v in s.x) {
        final q = qx(v);
        body.svar(q - prev);
        prev = q;
      }
    }
    for (final s in strokes) {
      var prev = 0;
      for (final v in s.y) {
        final q = qy(v);
        body.svar(q - prev);
        prev = q;
      }
    }
    if (anyPressure) {
      for (final s in strokes) {
        if (s.p.isEmpty) continue;
        var prev = 0;
        for (final v in s.p) {
          final q = (v * _pressureSteps).round().clamp(0, _pressureSteps);
          body.svar(q - prev);
          prev = q;
        }
      }
    }
    if (anyTime) {
      for (final s in strokes) {
        if (s.t.isEmpty) continue;
        var prev = 0;
        for (final v in s.t) {
          body.svar(v - prev);
          prev = v;
        }
      }
    }
    if (anyTilt) {
      for (final s in strokes) {
        if (s.tx.isEmpty && s.ty.isEmpty) continue;
        // Lengths are the point count, so a device that reported tilt for some
        // samples and not others round-trips as zeros rather than as a
        // different-length list.
        for (final list in [s.tx, s.ty]) {
          var prev = 0;
          for (var i = 0; i < s.x.length; i++) {
            final q =
                i < list.length ? (list[i] * _tiltScale).round() : prev;
            body.svar(q - prev);
            prev = q;
          }
        }
      }
    }

    final payload = body.take();
    final out = w.take();
    if (deflate && payload.length > _deflateAbove) {
      final z = Uint8List.fromList(_zlib.encode(payload));
      if (z.length < payload.length) {
        out[5] = 1;
        return Uint8List.fromList([...out, ...z]);
      }
    }
    return Uint8List.fromList([...out, ...payload]);
  }

  /// The header alone. Cheap: it inflates the payload but stops reading after
  /// the bounds.
  static InkHeader decodeHeader(Uint8List bytes) {
    final (payload, _) = _payloadOf(bytes);
    final r = _Reader(payload);
    r.u8(); // flags
    final scale = r.uvar();
    final count = r.uvar();
    final minQx = r.svar(), minQy = r.svar(), maxQx = r.svar(), maxQy = r.svar();
    return InkHeader(
      strokeCount: count,
      minX: minQx / scale,
      minY: minQy / scale,
      maxX: maxQx / scale,
      maxY: maxQy / scale,
    );
  }

  static (Uint8List, int) _payloadOf(Uint8List bytes) {
    if (!looksLikeInk(bytes)) {
      throw const FormatException('ink: not an OIS1 blob');
    }
    final version = bytes[4];
    if (version != 1) {
      throw FormatException('ink: version $version is newer than this build');
    }
    final method = bytes[5];
    final rest = Uint8List.sublistView(bytes, 6);
    return switch (method) {
      0 => (rest, version),
      1 => (Uint8List.fromList(_zlib.decode(rest)), version),
      _ => throw FormatException('ink: unknown compression $method'),
    };
  }

  /// Decode to strokes with PAGE-ABSOLUTE coordinates.
  ///
  /// [originX]/[originY] and [scaleX]/[scaleY] come from the block, so every
  /// existing consumer — the painter, hit testing, the exporters — sees exactly
  /// the geometry it sees today and needs no idea that a blob was involved.
  ///
  /// [idPrefix] seeds the synthesised stroke ids. Ids are NOT stored: they were
  /// 16 bytes each (19% of the payload on the real notebook) and nothing
  /// persists a cross-reference to one. Deriving them from the blob hash keeps
  /// them stable across decodes, which is what lets a rebuild be compared
  /// byte-for-byte against a container.
  static List<Stroke> decode(
    Uint8List bytes, {
    required double originX,
    required double originY,
    double scaleX = 1,
    double scaleY = 1,
    String idPrefix = 'ink',
  }) {
    final (payload, _) = _payloadOf(bytes);
    final r = _Reader(payload);
    final flags = r.u8();
    final anyPressure = flags & 1 != 0;
    final anyTime = flags & 2 != 0;
    final anyTilt = flags & 4 != 0;
    final scale = r.uvar();
    final count = r.uvar();
    r..svar()..svar()..svar()..svar(); // bounds — see decodeHeader

    final brushCount = r.uvar();
    final tools = <String>[];
    final colors = <String>[];
    final sizes = <double>[];
    final opacities = <double>[];
    for (var i = 0; i < brushCount; i++) {
      tools.add(r.u8() == 1 ? 'highlighter' : 'pen');
      final kind = r.u8();
      if (kind == 1) {
        final rr = r.u8(), gg = r.u8(), bb = r.u8();
        colors.add('#'
            '${rr.toRadixString(16).padLeft(2, '0')}'
            '${gg.toRadixString(16).padLeft(2, '0')}'
            '${bb.toRadixString(16).padLeft(2, '0')}'
            .toUpperCase()
            .replaceFirst('#', '#'));
      } else if (kind == 2) {
        final n = r.uvar();
        final raw = Uint8List(n);
        for (var k = 0; k < n; k++) {
          raw[k] = r.u8();
        }
        colors.add(utf8.decode(raw));
      } else {
        colors.add('#211F1B');
      }
      sizes.add(r.uvar() / 64);
      opacities.add(r.u8() / 255);
    }
    final baseTime = r.uvar();

    final brushOf = List<int>.filled(count, 0);
    final starts = List<int>.filled(count, 0);
    final lengths = List<int>.filled(count, 0);
    final sflags = List<int>.filled(count, 0);
    for (var i = 0; i < count; i++) {
      sflags[i] = r.u8();
      brushOf[i] = r.uvar();
      starts[i] = baseTime + r.uvar();
      lengths[i] = r.uvar();
    }

    List<List<double>> readColumn(double unit, double origin, double mul) {
      final out = <List<double>>[];
      for (var i = 0; i < count; i++) {
        final n = lengths[i];
        final col = List<double>.filled(n, 0);
        var prev = 0;
        for (var k = 0; k < n; k++) {
          prev += r.svar();
          col[k] = origin + (prev / unit) * mul;
        }
        out.add(col);
      }
      return out;
    }

    final xs = readColumn(scale.toDouble(), originX, scaleX);
    final ys = readColumn(scale.toDouble(), originY, scaleY);

    final ps = <List<double>>[];
    for (var i = 0; i < count; i++) {
      if (!anyPressure || sflags[i] & 1 == 0) {
        ps.add(const []);
        continue;
      }
      final n = lengths[i];
      final col = List<double>.filled(n, 0);
      var prev = 0;
      for (var k = 0; k < n; k++) {
        prev += r.svar();
        col[k] = prev / _pressureSteps;
      }
      ps.add(col);
    }

    final ts = <List<int>>[];
    for (var i = 0; i < count; i++) {
      if (!anyTime || sflags[i] & 2 == 0) {
        ts.add(const []);
        continue;
      }
      final n = lengths[i];
      final col = List<int>.filled(n, 0);
      var prev = 0;
      for (var k = 0; k < n; k++) {
        prev += r.svar();
        col[k] = prev;
      }
      ts.add(col);
    }

    final txs = <List<double>>[];
    final tys = <List<double>>[];
    for (var i = 0; i < count; i++) {
      if (!anyTilt || sflags[i] & 4 == 0) {
        txs.add(const []);
        tys.add(const []);
        continue;
      }
      for (final target in [txs, tys]) {
        final n = lengths[i];
        final col = List<double>.filled(n, 0);
        var prev = 0;
        for (var k = 0; k < n; k++) {
          prev += r.svar();
          col[k] = prev / _tiltScale;
        }
        target.add(col);
      }
    }

    return [
      for (var i = 0; i < count; i++)
        Stroke(
          id: '$idPrefix:$i',
          tool: tools[brushOf[i]],
          colorHex: colors[brushOf[i]],
          size: sizes[brushOf[i]],
          opacity: opacities[brushOf[i]],
          x: xs[i],
          y: ys[i],
          p: ps[i],
          tx: txs[i],
          ty: tys[i],
          t: ts[i],
          strokeStart: starts[i],
        )
    ];
  }
}
