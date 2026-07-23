import 'dart:io';
import 'dart:typed_data';

/// System font enumeration. Flutter renders any installed family by name but
/// offers no listing API, so we read the platform font directories and parse
/// each font's 'name' table (family, nameID 1) — TTF/OTF and TTC supported.
/// Everything is failure-guarded per file; the result is cached for the
/// session. Returns sorted unique family names.
class SystemFonts {
  static List<String>? _cache;

  static Future<List<String>> families() async {
    final cached = _cache;
    if (cached != null) return cached;
    final out = <String>{};
    for (final dir in _fontDirs()) {
      final d = Directory(dir);
      if (!d.existsSync()) continue;
      try {
        await for (final f in d.list(recursive: true, followLinks: false)) {
          if (f is! File) continue;
          final lower = f.path.toLowerCase();
          if (!(lower.endsWith('.ttf') ||
              lower.endsWith('.otf') ||
              lower.endsWith('.ttc'))) {
            continue;
          }
          try {
            final names = _familiesFromFont(await f.readAsBytes());
            out.addAll(names);
          } catch (_) {/* skip unparseable font */}
        }
      } catch (_) {/* skip unreadable dir */}
    }
    final list = out.where((n) => n.trim().isNotEmpty).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    _cache = list;
    return list;
  }

  static List<String> _fontDirs() {
    if (Platform.isWindows) {
      final windir = Platform.environment['WINDIR'] ?? r'C:\Windows';
      final local = Platform.environment['LOCALAPPDATA'];
      return [
        '$windir\\Fonts',
        if (local != null) '$local\\Microsoft\\Windows\\Fonts',
      ];
    }
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      return [
        '/System/Library/Fonts',
        '/Library/Fonts',
        if (home != null) '$home/Library/Fonts',
      ];
    }
    final home = Platform.environment['HOME'];
    return [
      '/usr/share/fonts',
      '/usr/local/share/fonts',
      if (home != null) '$home/.fonts',
      if (home != null) '$home/.local/share/fonts',
    ];
  }

  static List<String> _familiesFromFont(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final tag = data.getUint32(0);
    if (tag == 0x74746366) {
      // 'ttcf' — collection: parse each face
      final n = data.getUint32(8);
      final out = <String>[];
      for (var i = 0; i < n && i < 20; i++) {
        final off = data.getUint32(12 + i * 4);
        final name = _familyFromFace(data, off);
        if (name != null) out.add(name);
      }
      return out;
    }
    final name = _familyFromFace(data, 0);
    return name == null ? const [] : [name];
  }

  /// Parses one face's table directory → 'name' table → family (nameID 1;
  /// prefers 16 "typographic family" when present).
  static String? _familyFromFace(ByteData data, int faceOff) {
    final numTables = data.getUint16(faceOff + 4);
    int? nameOff;
    for (var i = 0; i < numTables; i++) {
      final rec = faceOff + 12 + i * 16;
      if (data.getUint32(rec) == 0x6E616D65) {
        nameOff = data.getUint32(rec + 8);
        break;
      }
    }
    if (nameOff == null) return null;
    final count = data.getUint16(nameOff + 2);
    final stringOff = nameOff + data.getUint16(nameOff + 4);
    String? family, typographic;
    for (var i = 0; i < count; i++) {
      final rec = nameOff + 6 + i * 12;
      final platform = data.getUint16(rec);
      final nameId = data.getUint16(rec + 6);
      if (nameId != 1 && nameId != 16) continue;
      final len = data.getUint16(rec + 8);
      final off = stringOff + data.getUint16(rec + 10);
      if (off + len > data.lengthInBytes) continue;
      String value;
      if (platform == 3 || platform == 0) {
        // UTF-16BE
        final units = <int>[];
        for (var j = 0; j + 1 < len; j += 2) {
          units.add(data.getUint16(off + j));
        }
        value = String.fromCharCodes(units);
      } else {
        value = String.fromCharCodes(
            [for (var j = 0; j < len; j++) data.getUint8(off + j)]);
      }
      if (nameId == 16) {
        typographic ??= value;
      } else {
        family ??= value;
      }
    }
    return typographic ?? family;
  }
}
