// The "Open Notebook" format's own projections of a graph and a substitute
// block — a SEPARATE, differently-worded switch from the file exporter's
// `pageMarkdownOf` (markdown_export.dart), so covering one does not cover
// the other. Neither type had a test here before today, for either the
// Markdown or the JSON Canvas projection.
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/export/open_export.dart';
import 'package:openote/model/models.dart';

void main() {
  group('the open-format Markdown projection', () {
    test('a graph carries its equation', () {
      final md = openPageMarkdownOf('Curves', [
        Block(type: BlockType.graph, x: 0, y: 0, w: 300, h: 200,
            content: {'latex': 'y=3x+10'}),
      ]);
      expect(md, contains('y=3x+10'));
      expect(md, contains('Graph of'));
    });

    test('an empty graph writes nothing for itself', () {
      final md = openPageMarkdownOf('Curves', [
        Block(type: BlockType.graph, x: 0, y: 0, w: 300, h: 200,
            content: {'latex': ''}),
      ]);
      expect(md, isNot(contains('Graph of')));
    });

    test('a substitute block carries the equation and the result', () {
      final md = openPageMarkdownOf('Numbers', [
        Block(type: BlockType.substitute, x: 0, y: 0, w: 260,
            content: {'latex': 'y=3x+10', 'value': '2'}),
      ]);
      expect(md, contains('y=3x+10'));
      expect(md, contains('x = 2'));
      expect(md, contains('16'));
    });

    test('a substitute block with nothing typed carries only the equation',
        () {
      final md = openPageMarkdownOf('Numbers', [
        Block(type: BlockType.substitute, x: 0, y: 0, w: 260,
            content: {'latex': 'y=3x+10', 'value': ''}),
      ]);
      expect(md, contains('y=3x+10'));
      expect(md, contains('Evaluate'));
      expect(md, isNot(contains('16')));
    });

    test('an empty substitute block writes nothing for itself', () {
      final md = openPageMarkdownOf('Numbers', [
        Block(type: BlockType.substitute, x: 0, y: 0, w: 260,
            content: {'latex': '', 'value': ''}),
      ]);
      expect(md, isNot(contains('Evaluate')));
    });
  });

  group('the JSON Canvas projection', () {
    test('a graph becomes a text node carrying its equation', () {
      final canvas = openJsonCanvasOf([
        Block(id: 'g1', type: BlockType.graph, x: 10, y: 20, w: 300, h: 200,
            content: {'latex': 'y=3x+10'}),
      ]);
      final nodes = canvas['nodes'] as List;
      expect(nodes, hasLength(1));
      final node = nodes.single as Map;
      expect(node['type'], 'text');
      expect(node['text'], contains('y=3x+10'));
      expect(node['x'], 10);
      expect(node['y'], 20);
    });

    test('a substitute block becomes a text node with the worked-out result',
        () {
      final canvas = openJsonCanvasOf([
        Block(id: 's1', type: BlockType.substitute, x: 0, y: 0, w: 260,
            content: {'latex': 'y=3x+10', 'value': '2'}),
      ]);
      final node = (canvas['nodes'] as List).single as Map;
      expect(node['type'], 'text');
      expect(node['text'], contains('y=3x+10'));
      expect(node['text'], contains('x = 2'));
    });

    test('every node keeps its own id, so an edge could still name it', () {
      final canvas = openJsonCanvasOf([
        Block(id: 'g1', type: BlockType.graph, x: 0, y: 0, w: 300, h: 200,
            content: {'latex': 'y=x'}),
        Block(id: 's1', type: BlockType.substitute, x: 0, y: 300, w: 260,
            content: {'latex': 'y=x', 'value': '1'}),
      ]);
      final ids = (canvas['nodes'] as List)
          .map((n) => (n as Map)['id'])
          .toSet();
      expect(ids, {'g1', 's1'});
    });
  });
}
