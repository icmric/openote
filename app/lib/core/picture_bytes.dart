/// **One place that decides what a picture's bytes are**, and one widget that
/// draws them whichever they are.
///
/// A picture in a note is a reference to a blob — `![](sha256:…)` — and the
/// reference says nothing about the format, deliberately: it is a hash, and a
/// hash of a PNG looks exactly like a hash of an SVG. So the bytes are asked.
///
/// Two renderers draw in-flow pictures, the editing one and the read-only one,
/// and the PDF exporter draws them a third way. They have to agree about what
/// a blob is, or a drawing that appears while you type vanishes when you click
/// away — which is the shape of bug after bug in this file's history. Hence
/// one sniff and one widget, used by both of the Flutter two.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Whether these bytes are an SVG document.
///
/// **Sniffed rather than taken from the blob's recorded MIME type**, because
/// the reference in the text carries no MIME type at all and the store's copy
/// is one indirection away from the thing being drawn. The bytes are the
/// thing. A raster's magic number is unambiguous and none of them can begin
/// with an angle bracket, so a positive test for the markup is safe.
///
/// Only the start is read — an SVG may legally open with an XML declaration, a
/// doctype, a comment or a byte-order mark before the `<svg` element, and a
/// kilobyte is far more than any of those need.
bool looksLikeSvg(Uint8List bytes) {
  final n = bytes.length < 1024 ? bytes.length : 1024;
  // The ASCII bytes of "<svg", which is all that is being looked for: an SVG
  // is UTF-8 (or UTF-16 with a BOM, where the element name still appears as
  // these bytes interleaved with nulls — hence the second pass).
  const needle = [0x3C, 0x73, 0x76, 0x67]; // '<' 's' 'v' 'g'
  bool at(int i, int step) {
    for (var k = 0; k < needle.length; k++) {
      final j = i + k * step;
      if (j >= n || (bytes[j] | 0x20) != (needle[k] | 0x20)) return false;
    }
    return true;
  }

  for (var i = 0; i < n; i++) {
    if (at(i, 1)) return true;
    if (at(i, 2)) return true; // UTF-16LE
  }
  return false;
}

/// A picture from [bytes], raster or vector.
///
/// The arguments are the ones both call sites already passed to
/// `Image.memory`: a null [width] or [height] means "natural size, capped by
/// whatever the parent allows", which is what a picture with no stored
/// `=WxH` has always done.
///
/// [onUndecodable] is called after the frame when a raster cannot be decoded,
/// so the caller can show the reference instead of a blank gap. An SVG that
/// cannot be parsed takes the same route through `SvgPicture`'s own error
/// handling.
Widget pictureFromBytes(
  Uint8List bytes, {
  Key? key,
  double? width,
  double? height,
  BoxFit fit = BoxFit.contain,
  Alignment alignment = Alignment.topLeft,
  VoidCallback? onUndecodable,
}) {
  if (looksLikeSvg(bytes)) {
    return SvgPicture.memory(
      bytes,
      key: key,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      // A drawing that fails to parse is reported the same way a raster that
      // fails to decode is, so a broken file looks the same whichever it is.
      errorBuilder: (_, __, ___) {
        if (onUndecodable != null) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => onUndecodable());
        }
        return const SizedBox.shrink();
      },
    );
  }
  return Image.memory(
    bytes,
    key: key,
    width: width,
    height: height,
    fit: fit,
    alignment: alignment,
    gaplessPlayback: true,
    errorBuilder: (_, __, ___) {
      if (onUndecodable != null) {
        // The decode fails asynchronously, so the swap has to wait for the
        // frame that is already building.
        WidgetsBinding.instance.addPostFrameCallback((_) => onUndecodable());
      }
      return const SizedBox.shrink();
    },
  );
}
