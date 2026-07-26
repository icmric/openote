/// Data model per docs/specs/11-data-model-spec.md. Field names match the
/// Page JSON schema exactly, so `toJson` output IS the mirror format.
library;

import '../core/ids.dart';

int nowMs() => DateTime.now().millisecondsSinceEpoch;

// ── Hierarchy ────────────────────────────────────────────────────────────

enum NodeKind { sectionGroup, section, page }

class TreeNode {
  TreeNode({
    String? id,
    required this.kind,
    this.parentId,
    this.title = '',
    this.position = 'a0',
    this.color,
    this.level = 0,
    int? createdAt,
  })  : id = id ?? newId(),
        createdAt = createdAt ?? nowMs(),
        updatedAt = createdAt ?? nowMs();

  final String id;
  final NodeKind kind;
  String? parentId;
  String title;
  String position; // fractional index, sorts lexicographically
  String? color;
  int level; // subpage indent for pages (0..2)
  final int createdAt;
  int updatedAt;
}

class NotebookRef {
  NotebookRef(
      {required this.id, required this.file, required this.title, this.deletedAt});
  final String id;
  final String file; // absolute path to the .onote
  String title;
  int? deletedAt; // set while the notebook sits in the recycle bin (ORG-7)
}

// ── Page properties (Data Model Spec §3 page-level; CANVAS-11) ───────────

class PageProps {
  PageProps({this.background = 'blank', this.gridSize = 24, this.pageWidth = 1100});
  String background; // blank | grid | dotted | ruled
  double gridSize;
  double pageWidth; // presented page-surface width (CANVAS-1 v0.3)

  Map<String, dynamic> toJson() =>
      {'background': background, 'gridSize': gridSize, 'pageWidth': pageWidth};
  factory PageProps.fromJson(Map<String, dynamic>? j) => PageProps(
        background: j?['background'] as String? ?? 'blank',
        gridSize: (j?['gridSize'] as num?)?.toDouble() ?? 24,
        pageWidth: (j?['pageWidth'] as num?)?.toDouble() ?? 1100,
      );
}

class PageData {
  PageData(this.blocks, this.props);
  final List<Block> blocks;
  final PageProps props;
}

// ── Blocks ───────────────────────────────────────────────────────────────

enum BlockType { text, ink, math, image, code, file, table, frame, embed, unknown }

BlockType blockTypeFrom(String s) =>
    BlockType.values.asNameMap()[s] ?? BlockType.unknown;

class Block {
  Block({
    String? id,
    required this.type,
    required this.x,
    required this.y,
    this.w = 320,
    this.h,
    this.z = 0,
    this.placement = 'free',
    this.frameId,
    Map<String, dynamic>? content,
    List<String>? absorbedIds,
    this.access,
    Map<String, dynamic>? unknownFields,
    int? createdAt,
  })  : id = id ?? newId(),
        content = content ?? {},
        absorbedIds = absorbedIds ?? [],
        unknownFields = unknownFields ?? {},
        createdAt = createdAt ?? nowMs(),
        updatedAt = createdAt ?? nowMs();

  final String id;
  final BlockType type;
  double x, y;
  double w;
  double? h; // null = auto-height
  int z;
  String placement; // 'free' | 'snapped'
  String? frameId;
  Map<String, dynamic> content;
  final List<String> absorbedIds;
  Map<String, dynamic>? access; // reserved (SYNC-9); v1 writes null
  final Map<String, dynamic> unknownFields; // forward-compat round-trip
  final int createdAt;
  int updatedAt;

  static const _known = {
    'id', 'type', 'x', 'y', 'w', 'h', 'rotation', 'z', 'placement', 'frameId',
    'absorbedIds', 'access', 'createdAt', 'updatedAt', 'content',
  };

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'x': x, 'y': y, 'w': w, 'h': h,
        'rotation': 0,
        'z': z,
        'placement': placement,
        'frameId': frameId,
        'absorbedIds': absorbedIds,
        'access': access,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'content': content,
        ...unknownFields,
      };

  factory Block.fromJson(Map<String, dynamic> j) => Block(
        id: j['id'] as String,
        type: blockTypeFrom(j['type'] as String? ?? 'unknown'),
        x: (j['x'] as num?)?.toDouble() ?? 0,
        y: (j['y'] as num?)?.toDouble() ?? 0,
        w: (j['w'] as num?)?.toDouble() ?? 320,
        h: (j['h'] as num?)?.toDouble(),
        z: (j['z'] as num?)?.toInt() ?? 0,
        placement: j['placement'] as String? ?? 'free',
        frameId: j['frameId'] as String?,
        content: (j['content'] as Map?)?.cast<String, dynamic>() ?? {},
        absorbedIds: (j['absorbedIds'] as List?)?.cast<String>() ?? [],
        access: (j['access'] as Map?)?.cast<String, dynamic>(),
        createdAt: (j['createdAt'] as num?)?.toInt(),
        unknownFields: {
          for (final e in j.entries)
            if (!_known.contains(e.key)) e.key: e.value,
        },
      )..updatedAt = (j['updatedAt'] as num?)?.toInt() ?? nowMs();
}

// ── Ink (Ink Data Spec §2: parallel arrays, immutable strokes) ───────────

class Stroke {
  Stroke({
    String? id,
    required this.tool,
    required this.colorHex,
    required this.size,
    this.opacity = 1.0,
    List<double>? x,
    List<double>? y,
    List<double>? p,
    List<int>? t,
    int? strokeStart,
  })  : id = id ?? newId(),
        x = x ?? [],
        y = y ?? [],
        p = p ?? [],
        t = t ?? [],
        strokeStart = strokeStart ?? nowMs();

  final String id;
  final String tool; // pen | highlighter
  final String colorHex; // "#RRGGBB"
  final double size;
  final double opacity;
  final List<double> x, y, p;
  final List<int> t;
  final int strokeStart;

  Map<String, dynamic> toJson() => {
        'id': id,
        'brush': {'tool': tool, 'color': colorHex, 'size': size, 'opacity': opacity},
        'x': x, 'y': y, 'p': p, 'tx': const [], 'ty': const [],
        't': t, 'strokeStart': strokeStart,
      };

  factory Stroke.fromJson(Map<String, dynamic> j) {
    final b = (j['brush'] as Map).cast<String, dynamic>();
    return Stroke(
      id: j['id'] as String,
      tool: b['tool'] as String? ?? 'pen',
      colorHex: b['color'] as String? ?? '#211F1B',
      size: (b['size'] as num?)?.toDouble() ?? 2.5,
      opacity: (b['opacity'] as num?)?.toDouble() ?? 1.0,
      x: (j['x'] as List).map((e) => (e as num).toDouble()).toList(),
      y: (j['y'] as List).map((e) => (e as num).toDouble()).toList(),
      p: ((j['p'] as List?) ?? const []).map((e) => (e as num).toDouble()).toList(),
      t: ((j['t'] as List?) ?? const []).map((e) => (e as num).toInt()).toList(),
      strokeStart: (j['strokeStart'] as num?)?.toInt(),
    );
  }

  ({double minX, double minY, double maxX, double maxY}) bounds() {
    var mnx = double.infinity, mny = double.infinity;
    var mxx = -double.infinity, mxy = -double.infinity;
    for (var i = 0; i < x.length; i++) {
      if (x[i] < mnx) mnx = x[i];
      if (x[i] > mxx) mxx = x[i];
      if (y[i] < mny) mny = y[i];
      if (y[i] > mxy) mxy = y[i];
    }
    return (minX: mnx, minY: mny, maxX: mxx, maxY: mxy);
  }
}
