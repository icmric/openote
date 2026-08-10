/// The MCP tool surface — External API Spec (docs/specs/14) §5.
///
/// **The file format is the API** (spec §2): every content noun here is the
/// page JSON of the format specs, serialised by `Block.toJson` and validated
/// by `Block.fromJson` — the same code every file and every synced op goes
/// through. That is why a block type added next year is readable and
/// writable through this API the day it exists, with no edit to this file.
///
/// Writes route through the app's ORDINARY write paths (spec §4.6): the open
/// page through `addBlock` (undoable, live on screen), any other page
/// through `importPage`, which is the importers' own container-write +
/// op-record pair — so an AI-created block syncs, undoes and materialises
/// exactly like a typed one. A write tool that cannot route this way must
/// not ship.
library;

import 'dart:convert';

import '../core/ids.dart';
import '../export/markdown_export.dart';
import '../model/models.dart';
import '../state/app_state.dart';

/// A tool-level failure the calling model is meant to read and recover from.
class McpToolError implements Exception {
  McpToolError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Tool definitions for `tools/list` — names, descriptions, input schemas.
/// Descriptions are written for the MODEL reading them: say what the tool
/// is for and what the shapes mean, briefly.
final List<Map<String, Object>> mcpToolDefinitions = [
  {
    'name': 'list_notebooks',
    'description': 'Every notebook in this Openote workspace. The one with '
        'open=true is on screen right now.',
    'inputSchema': {'type': 'object', 'properties': <String, Object>{}},
  },
  {
    'name': 'list_pages',
    'description': 'The sections and pages of a notebook, in sidebar order. '
        'Defaults to the open notebook.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'notebookId': {'type': 'string'},
      },
    },
  },
  {
    'name': 'read_page',
    'description': 'One page. format "json" (default) returns the open '
        'page-JSON format — blocks with types, positions and content, the '
        'same shape append_blocks accepts. format "markdown" returns a '
        'flattened reading-order projection.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'pageId': {'type': 'string'},
        'format': {
          'type': 'string',
          'enum': ['json', 'markdown']
        },
      },
      'required': ['pageId'],
    },
  },
  {
    'name': 'search',
    'description': 'Full-text search over a notebook\'s pages. Returns page '
        'ids, titles and a snippet around the first hit.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'query': {'type': 'string'},
        'notebookId': {'type': 'string'},
      },
      'required': ['query'],
    },
  },
  {
    'name': 'create_page',
    'description': 'A new, empty page. Lands in the given section, or the '
        'notebook\'s first section.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'title': {'type': 'string'},
        'sectionId': {'type': 'string'},
        'notebookId': {'type': 'string'},
      },
      'required': ['title'],
    },
  },
  {
    'name': 'append_blocks',
    'description': 'Append blocks to a page, below its existing content. '
        'Blocks are page-JSON block objects — the same shape read_page '
        'returns: {"type": "text", "content": {"text": "…"}} and every other '
        'documented type. Positions (x, y) are optional; omitted blocks are '
        'laid out down the page. At most 100 blocks per call.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'pageId': {'type': 'string'},
        'blocks': {
          'type': 'array',
          'items': {'type': 'object'},
        },
      },
      'required': ['pageId', 'blocks'],
    },
  },
  {
    'name': 'append_markdown',
    'description': 'Append prose to a page as one text block. Openote text '
        'blocks render Markdown, so headings, lists, checkboxes, bold and '
        'links all work.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'pageId': {'type': 'string'},
        'markdown': {'type': 'string'},
      },
      'required': ['pageId', 'markdown'],
    },
  },
  {
    'name': 'create_flashcards',
    'description': 'Add study flashcards to a page. Each card is '
        '{front, back}. They are written in the page\'s own card form, so '
        'Openote\'s spaced-repetition deck picks them up immediately.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'pageId': {'type': 'string'},
        'cards': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'front': {'type': 'string'},
              'back': {'type': 'string'},
            },
            'required': ['front', 'back'],
          },
        },
      },
      'required': ['pageId', 'cards'],
    },
  },
];

/// Execute [name] with [args] against the live app. Returns the tool result
/// as a JSON string (models parse it fine, and it keeps the transport dumb).
Future<String> callMcpTool(
    AppState app, String name, Map<String, Object?> args) async {
  switch (name) {
    case 'list_notebooks':
      return jsonEncode([
        for (final n in app.notebooks)
          {'id': n.id, 'title': n.title, 'open': n.id == app.notebookId},
      ]);

    case 'list_pages':
      final nb = _notebookOf(app, args);
      final nodes = nb == app.notebookId
          ? app.nodes
          : app.readNodesOf(nb);
      return jsonEncode([
        for (final n in nodes)
          {
            'id': n.id,
            'title': n.title,
            'kind': n.kind.name,
            if (n.parentId != null) 'parentId': n.parentId,
            'level': n.level,
          },
      ]);

    case 'read_page':
      final (nb, pageId) = _pageOf(app, args);
      final data = _readPage(app, nb, pageId);
      if (args['format'] == 'markdown') {
        final title = _titleOf(app, nb, pageId);
        return pageMarkdownOf(app, title, data.blocks);
      }
      return jsonEncode({
        'pageId': pageId,
        'title': _titleOf(app, nb, pageId),
        'page': data.props.toJson(),
        'blocks': [for (final b in data.blocks) b.toJson()],
      });

    case 'search':
      final nb = _notebookOf(app, args);
      final q = '${args['query'] ?? ''}';
      if (q.trim().isEmpty) throw McpToolError('query is empty');
      final hits = app.searchPagesOf(nb, q);
      return jsonEncode([
        for (final h in hits)
          {
            'pageId': h.pageId,
            'title': _titleOf(app, nb, h.pageId),
            'snippet': h.snippet,
          },
      ]);

    case 'create_page':
      final nb = _notebookOf(app, args);
      final title = '${args['title'] ?? ''}'.trim();
      if (title.isEmpty) throw McpToolError('title is empty');
      final nodes = nb == app.notebookId ? app.nodes : app.readNodesOf(nb);
      final sectionId = args['sectionId'] as String? ??
          nodes
              .where((n) => n.kind == NodeKind.section)
              .firstOrNull
              ?.id;
      if (sectionId == null) {
        throw McpToolError('that notebook has no sections');
      }
      if (!nodes.any((n) => n.id == sectionId)) {
        throw McpToolError('no section $sectionId in that notebook');
      }
      final node = app.importNode(
          nb,
          TreeNode(
            kind: NodeKind.page,
            parentId: sectionId,
            title: title,
            position: 'a${nowMs().toString().padLeft(15, '0')}',
          ));
      if (nb == app.notebookId) app.reloadNodes();
      return jsonEncode({'pageId': node.id});

    case 'append_blocks':
      final (nb, pageId) = _pageOf(app, args);
      final raw = args['blocks'];
      if (raw is! List || raw.isEmpty) {
        throw McpToolError('blocks must be a non-empty array');
      }
      if (raw.length > 100) {
        throw McpToolError('at most 100 blocks per call');
      }
      // THE consistency moment: parse through the format's own reader, so a
      // malformed block fails here with the parser's reason, and a valid one
      // — of any type, including types newer than this document — round-trips.
      final blocks = <Block>[];
      for (var i = 0; i < raw.length; i++) {
        final m = raw[i];
        if (m is! Map) throw McpToolError('blocks[$i] is not an object');
        try {
          final json =
              (jsonDecode(jsonEncode(m)) as Map).cast<String, dynamic>();
          // Files always carry ids; API clients should not have to mint
          // UUIDs to append a paragraph. Minted here, stable thereafter.
          json['id'] ??= newId();
          blocks.add(Block.fromJson(json));
        } catch (e) {
          throw McpToolError('blocks[$i] did not parse: $e');
        }
      }
      _appendBlocks(app, nb, pageId, blocks);
      return jsonEncode({'added': blocks.length});

    case 'append_markdown':
      final (nb, pageId) = _pageOf(app, args);
      final md = '${args['markdown'] ?? ''}';
      if (md.trim().isEmpty) throw McpToolError('markdown is empty');
      if (md.length > 256 * 1024) throw McpToolError('over 256 KB');
      _appendBlocks(app, nb, pageId, [
        Block(type: BlockType.text, x: 0, y: 0, w: 480, content: {
          'text': md,
          'autoWidth': false,
        })
      ]);
      return jsonEncode({'added': 1});

    case 'create_flashcards':
      final (nb, pageId) = _pageOf(app, args);
      final cards = args['cards'];
      if (cards is! List || cards.isEmpty) {
        throw McpToolError('cards must be a non-empty array of {front, back}');
      }
      final lines = <String>[];
      for (final c in cards) {
        if (c is! Map) throw McpToolError('each card must be {front, back}');
        final front = '${c['front'] ?? ''}'.trim().replaceAll('\n', ' ');
        final back = '${c['back'] ?? ''}'.trim().replaceAll('\n', ' ');
        if (front.isEmpty || back.isEmpty) {
          throw McpToolError('cards need a non-empty front and back');
        }
        // The page's own card form (`?[front](back)`) — the study system
        // derives deck entries and schedules from these lines directly, so
        // nothing else needs to know these cards came from outside.
        lines.add('?[${front.replaceAll('[', '(').replaceAll(']', ')')}]'
            '(${back.replaceAll('(', '[').replaceAll(')', ']')})');
      }
      _appendBlocks(app, nb, pageId, [
        Block(type: BlockType.text, x: 0, y: 0, w: 460, content: {
          'text': '${lines.join('\n')}\n',
          'autoWidth': false,
        })
      ]);
      return jsonEncode({'added': cards.length});

    default:
      throw McpToolError('no such tool: $name');
  }
}

// ── Shared plumbing ──────────────────────────────────────────────────────

String _notebookOf(AppState app, Map<String, Object?> args) {
  final asked = args['notebookId'] as String?;
  if (asked == null) {
    final open = app.notebookId;
    if (open == null) throw McpToolError('no notebook is open — pass notebookId');
    return open;
  }
  if (!app.notebooks.any((n) => n.id == asked)) {
    throw McpToolError('no notebook $asked. Known: '
        '${app.notebooks.map((n) => '${n.title} (${n.id})').join(', ')}');
  }
  return asked;
}

/// Resolve a pageId to its notebook by looking, so callers never have to
/// pass both. Searches the open notebook first, then the rest.
(String, String) _pageOf(AppState app, Map<String, Object?> args) {
  final pageId = args['pageId'] as String?;
  if (pageId == null || pageId.isEmpty) throw McpToolError('pageId missing');
  final open = app.notebookId;
  if (open != null && app.nodes.any((n) => n.id == pageId)) {
    return (open, pageId);
  }
  for (final n in app.notebooks) {
    if (n.id == open) continue;
    if (app.readNodesOf(n.id).any((x) => x.id == pageId)) return (n.id, pageId);
  }
  throw McpToolError('no page $pageId in any notebook — list_pages shows '
      'what exists');
}

PageData _readPage(AppState app, String nb, String pageId) =>
    nb == app.notebookId && pageId == app.pageId
        // The OPEN page reads from the live editor, not the last save — an
        // assistant must see what the user sees.
        ? PageData(app.blocks, app.pageProps)
        : app.readPageOf(nb, pageId);

String _titleOf(AppState app, String nb, String pageId) {
  final nodes = nb == app.notebookId ? app.nodes : app.readNodesOf(nb);
  return nodes.where((n) => n.id == pageId).firstOrNull?.title ?? '';
}

/// Below existing content, through the ordinary write paths (spec §4.6).
void _appendBlocks(AppState app, String nb, String pageId, List<Block> blocks) {
  final onScreen = nb == app.notebookId && pageId == app.pageId;
  final existing = onScreen ? app.blocks : app.readPageOf(nb, pageId).blocks;
  var y = AppState.contentTop;
  for (final b in existing) {
    final bottom = b.y + (b.h ?? app.estimatedHeight(b));
    if (bottom > y) y = bottom;
  }
  y += 24;
  for (final b in blocks) {
    // Only place blocks the caller did not place: an explicit (x, y) — from
    // a client round-tripping read_page output — is honoured as given.
    if (b.x == 0 && b.y == 0) {
      b.x = AppState.pageLeftMargin;
      b.y = y;
      y += (b.h ?? app.estimatedHeight(b)) + 16;
    }
  }
  if (onScreen) {
    app.pushUndo();
    for (final b in blocks) {
      app.addBlock(b, recordUndo: false);
    }
  } else {
    final data = app.readPageOf(nb, pageId);
    app.importPage(nb, pageId, [...data.blocks, ...blocks], data.props);
    if (nb == app.notebookId) app.bumpNodes();
  }
}
