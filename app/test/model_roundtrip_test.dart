import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openote/model/models.dart';

void main() {
  group('Block JSON round-trip (Data Model Spec §8 invariant 6)', () {
    test('envelope + content survive, unknown fields preserved', () {
      final src = {
        'id': '0198f3c2-7b1e-7cc3-9f10-3d2a8c41e977',
        'type': 'text',
        'x': 120.0, 'y': 96.0, 'w': 340.0, 'h': null,
        // Deliberately NON-default: `rotation: 0` used to mask a real bug —
        // `toJson` hard-coded 0 while `_known` claimed the key, so a non-zero
        // rotation was destroyed on every load→save cycle.
        'rotation': 15.0, 'z': 3,
        'placement': 'snapped',
        'frameId': null,
        'absorbedIds': ['0198f3c2-0000-7000-8000-000000000001'],
        'access': null,
        'createdAt': 1753142400000,
        'updatedAt': 1753142400001,
        'content': {'text': 'hello'},
        'x-future-field': {'anything': true}, // unknown-field rule
      };
      final b = Block.fromJson(src);
      final out = b.toJson();
      expect(out['id'], src['id']);
      expect(out['placement'], 'snapped');
      expect(out['absorbedIds'], src['absorbedIds']);
      expect(out['x-future-field'], src['x-future-field']);
      expect(out['content'], src['content']);
      // Full JSON-level stability modulo nothing (same timestamps preserved):
      expect(jsonDecode(jsonEncode(out)), jsonDecode(jsonEncode(src)));
    });

    test('stroke arrays are parallel and round-trip', () {
      final s = Stroke(tool: 'pen', colorHex: '#211F1B', size: 2.5)
        ..x.addAll([1.0, 2.0])
        ..y.addAll([3.0, 4.0])
        ..p.addAll([0.5, 0.6])
        ..t.addAll([0, 8]);
      final j = s.toJson();
      final back = Stroke.fromJson(j.cast<String, dynamic>());
      expect(back.x, s.x);
      expect(back.p, s.p);
      expect(back.t, s.t);
      expect(back.id, s.id);
      // Invariant 1: parallel lengths
      expect(back.x.length, back.y.length);
      expect(back.p.length, anyOf(0, back.x.length));
    });

    test('stroke tilt channels survive a round-trip', () {
      // Regression: tx/ty were written as `const []` and never read back, so
      // tilt recorded by another tool was destroyed by opening and saving.
      final j = {
        'id': '0198f3c2-0000-7000-8000-00000000abcd',
        'brush': {'tool': 'pen', 'color': '#211F1B', 'size': 2.5, 'opacity': 1.0},
        'x': [1.0, 2.0],
        'y': [3.0, 4.0],
        'p': [0.5, 0.6],
        'tx': [0.1, 0.2],
        'ty': [-0.3, -0.4],
        't': [0, 8],
        'strokeStart': 1753142400000,
      };
      final back = Stroke.fromJson(j.cast<String, dynamic>());
      expect(back.tx, [0.1, 0.2]);
      expect(back.ty, [-0.3, -0.4]);
      expect(jsonDecode(jsonEncode(back.toJson())), jsonDecode(jsonEncode(j)));
    });

    test('page props preserve unknown future fields', () {
      final src = {
        'background': 'grid',
        'gridSize': 32.0,
        'pageWidth': 1200.0,
        'x-future-page-prop': {'nested': [1, 2]},
      };
      final out = PageProps.fromJson(src).toJson();
      expect(out['background'], 'grid');
      expect(out['x-future-page-prop'], src['x-future-page-prop']);
      expect(jsonDecode(jsonEncode(out)), jsonDecode(jsonEncode(src)));
    });
  });
}
