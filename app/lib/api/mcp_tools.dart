/// The MCP tool surface — External API Spec (docs/specs/14) §5.
///
/// **The file format is the API** (spec §2): every content noun here is the
/// page JSON of the format specs, serialised by `Block.toJson` and validated
/// by `Block.fromJson` — the same code every file and every synced op goes
/// through. That is why a block type added next year is readable and
/// writable through this API the day it exists, with no edit to this file.
/// What each known type keeps in `content` is written down once, beside the
/// model, in `model/block_schema.dart`; this file asks it, it does not own it.
///
/// Writes route through the app's ORDINARY write paths (spec §4.6): the open
/// page through the live editor (`pushUndo` + `addBlock` / `removeBlock` /
/// `updateBlock` — undoable, live on screen), any other page through
/// `importPage`, which is the importers' own container-write + op-record
/// pair — so an AI-created block syncs, undoes and materialises exactly like
/// a typed one. A write tool that cannot route this way must not ship.
library;

import 'dart:convert';
import 'dart:math' as math;

import '../core/ids.dart';
import '../editor/code_languages.dart';
import '../export/markdown_export.dart';
import '../markdown/md_blocks.dart';
import '../model/block_schema.dart';
import '../model/inline_atom.dart';
import '../model/models.dart';
import '../model/tags.dart' show NoteTag;
import '../model/table_conversion.dart';
import '../state/app_state.dart';
import '../state/page_protection.dart' show ProtectionTree;
import '../update/app_update.dart' show kAppVersion;

/// A tool-level failure the calling model is meant to read and recover from.
class McpToolError implements Exception {
  McpToolError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Every block type with a documented shape, one clause each, for the
/// `append_blocks` description — generated from the block schema so it
/// cannot drift from what the checks enforce (v1.0.2 plan §20, fix 1).
final String _typeList = [
  for (final s in blockSchemas) '${s.type} (${_firstClause(s.summary)})'
].join(', ');

String _firstClause(String s) {
  final end = s.indexOf(RegExp(r'[.:,]'));
  return (end < 0 ? s : s.substring(0, end)).toLowerCase();
}

/// Space left between blocks the API stacks, and between the page's existing
/// content and the first appended block.
const double _kGap = 16;
const double _kGapAfterExisting = 24;

/// Caps (spec §6).
const int _kMaxBlocks = 100;
const int _kMaxPages = 50;
const int _kMaxText = 256 * 1024;

const Map<String, Object> _pageIdProp = {
  'type': 'string',
  'description': 'A page id from list_pages, search or create_page.',
};
const Map<String, Object> _blocksProp = {
  'type': 'array',
  'items': {'type': 'object'},
  'description': 'Page-JSON blocks: {"type", "content", optional x/y/w/h}. '
      'describe_block_types lists each type\'s content keys.',
};
const Map<String, Object> _markdownProp = {
  'type': 'string',
  'description': 'Markdown. Fenced code becomes code blocks, GFM pipe tables '
      'become real tables, the rest becomes text blocks.',
};

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
    'description': 'The sections and pages of a notebook, in sidebar order, '
        'paginated. Big notebooks: first call with kind="section" to find a '
        'section, then with sectionId to list its pages. Defaults to the open '
        'notebook. Returns {total, items, nextOffset?}; pass nextOffset as '
        'offset for the next page of results. Anything with a passcode is '
        'left out, and cannot be opened from here.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'notebookId': {'type': 'string'},
        'sectionId': {
          'type': 'string',
          'description': 'Only the pages of this section.'
        },
        'kind': {
          'type': 'string',
          'enum': ['section', 'page', 'sectionGroup'],
        },
        'query': {
          'type': 'string',
          'description': 'Only titles containing this (case-insensitive).'
        },
        'maxLevel': {
          'type': 'integer',
          'description': 'Only pages at most this deep (0 = top-level pages, '
              'no subpages).'
        },
        'offset': {'type': 'integer'},
        'limit': {'type': 'integer', 'description': 'Default 100, max 1000.'},
      },
    },
  },
  {
    'name': 'read_page',
    'description': 'One page. format "json" (default) returns the open '
        'page-JSON format — blocks with types, positions and content, the '
        'same shape append_blocks accepts. format "markdown" returns a '
        'flattened reading-order projection. format "layout" returns just '
        'each block\'s id, type and bounding box plus any overlaps — use it '
        'to check how a page is laid out after writing.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'pageId': _pageIdProp,
        'format': {
          'type': 'string',
          'enum': ['json', 'markdown', 'layout']
        },
      },
      'required': ['pageId'],
    },
  },
  {
    'name': 'search',
    'description': 'Full-text search over a notebook\'s pages. Returns page '
        'ids, titles and a snippet around the first hit. Pages with a '
        'passcode are never searched.',
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
    'name': 'describe_block_types',
    'description': 'The content keys of every block type (text, code, math, '
        'flashcard, …), the valid code language ids, how tables are stored, '
        'and the page layout constants. Read this before writing blocks by '
        'hand with append_blocks / insert_blocks / update_block.',
    'inputSchema': {'type': 'object', 'properties': <String, Object>{}},
  },
  {
    'name': 'create_page',
    'description': 'A new page, optionally filled in the same call from '
        'markdown and/or blocks. Lands at the end of the given section (or '
        'the notebook\'s first section), or right after afterPageId.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'title': {'type': 'string'},
        'sectionId': {'type': 'string'},
        'notebookId': {'type': 'string'},
        'afterPageId': {'type': 'string'},
        'level': {
          'type': 'integer',
          'description': '0 = page, 1-2 = subpage of the page above.'
        },
        'markdown': _markdownProp,
        'blocks': _blocksProp,
      },
      'required': ['title'],
    },
  },
  {
    'name': 'create_pages',
    'description': 'Several new pages in one call, in order, at the end of '
        'one section. Each is {title, markdown?, blocks?, level?}. At most '
        '50 pages. Nothing is created unless every page is valid.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'sectionId': {'type': 'string'},
        'notebookId': {'type': 'string'},
        'pages': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'title': {'type': 'string'},
              'markdown': {'type': 'string'},
              'blocks': {
                'type': 'array',
                'items': {'type': 'object'}
              },
              'level': {'type': 'integer'},
            },
            'required': ['title'],
          },
        },
      },
      'required': ['pages'],
    },
  },
  {
    'name': 'append_blocks',
    'description': 'Add blocks to a page, below its existing content. '
        'Blocks are page-JSON block objects — the same shape read_page '
        'returns, e.g. {"type": "text", "content": {"text": "…"}} or '
        '{"type": "code", "content": {"source": "…", "language": "python"}}. '
        'Prefer a real code block or table over Markdown that only renders as '
        'text. Types: $_typeList. '
        'describe_block_types lists every type\'s keys; a block with a '
        'missing or misspelt required key is refused. Positions (x, y) are '
        'optional; omitted blocks are stacked down the page. Returns each '
        'block\'s id and placed box. At most 100 blocks per call.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'pageId': _pageIdProp,
        'blocks': _blocksProp,
      },
      'required': ['pageId', 'blocks'],
    },
  },
  {
    'name': 'append_markdown',
    'description': 'Add Markdown to the bottom of a page as Openote\'s own '
        'objects: prose becomes text blocks (headings, lists, checkboxes, '
        'bold, links, \$math\$ all render), ```lang fences become code '
        'blocks, and GFM pipe tables become real editable tables. Set '
        'literal to keep it as one text block exactly as written instead. '
        'Returns each block\'s id and placed box.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'pageId': _pageIdProp,
        'markdown': _markdownProp,
        'literal': {
          'type': 'boolean',
          'description': 'true: one text block, fences and pipes left as '
              'literal Markdown (for showing Markdown itself).'
        },
      },
      'required': ['pageId', 'markdown'],
    },
  },
  {
    'name': 'insert_blocks',
    'description': 'Insert blocks or markdown in the middle of a page: '
        'directly below afterBlockId, or at y. Everything below the '
        'insertion point moves down to make room. Give blocks or markdown, '
        'and afterBlockId or y.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'pageId': _pageIdProp,
        'afterBlockId': {'type': 'string'},
        'y': {'type': 'number'},
        'blocks': _blocksProp,
        'markdown': _markdownProp,
      },
      'required': ['pageId'],
    },
  },
  {
    'name': 'update_block',
    'description': 'Change one block: its content and/or position and size. '
        'content is MERGED key by key (a key set to null is removed) unless '
        'replaceContent is true. The result is checked like a new block. '
        'Undoable in the app.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'pageId': _pageIdProp,
        'blockId': {'type': 'string'},
        'content': {'type': 'object'},
        'replaceContent': {'type': 'boolean'},
        'x': {'type': 'number'},
        'y': {'type': 'number'},
        'w': {'type': 'number'},
        'h': {
          'type': 'number',
          'description': 'Fixed height. Send null to go back to automatic.'
        },
      },
      'required': ['pageId', 'blockId'],
    },
  },
  {
    'name': 'delete_blocks',
    'description': 'Remove blocks from a page. Undoable in the app.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'pageId': _pageIdProp,
        'blockIds': {
          'type': 'array',
          'items': {'type': 'string'}
        },
      },
      'required': ['pageId', 'blockIds'],
    },
  },
  {
    'name': 'move_blocks',
    'description': 'Move blocks by (dx, dy) logical px. Positive dy is down. '
        'Undoable in the app.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'pageId': _pageIdProp,
        'blockIds': {
          'type': 'array',
          'items': {'type': 'string'}
        },
        'dx': {'type': 'number'},
        'dy': {'type': 'number'},
      },
      'required': ['pageId', 'blockIds'],
    },
  },
  {
    'name': 'rename_page',
    'description': 'Give a page (or a section) a new title.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'pageId': _pageIdProp,
        'title': {'type': 'string'},
      },
      'required': ['pageId', 'title'],
    },
  },
  {
    'name': 'move_page',
    'description': 'Move a page, with its subpages, to the end of another '
        'section or to just after afterPageId, within the same notebook. '
        'level sets its indent (0-2).',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'pageId': _pageIdProp,
        'sectionId': {'type': 'string'},
        'afterPageId': {'type': 'string'},
        'level': {'type': 'integer'},
      },
      'required': ['pageId'],
    },
  },
  {
    'name': 'delete_page',
    'description': 'Delete a page. It goes to the notebook\'s recycle bin, '
        'where the user can restore it. Its subpages are kept.',
    'inputSchema': {
      'type': 'object',
      'properties': {'pageId': _pageIdProp},
      'required': ['pageId'],
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
        'pageId': _pageIdProp,
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
      return jsonEncode(_listPages(app, args));

    case 'read_page':
      final (nb, pageId) = _pageOf(app, args);
      final data = _readPage(app, nb, pageId);
      final title = _titleOf(app, nb, pageId);
      switch (args['format']) {
        case 'markdown':
          return pageMarkdownOf(app, title, data.blocks,
              withheld: (id) => _coveredAnywhere(app, id));
        case 'layout':
          final pw = _PageWrite.read(app, nb, pageId);
          final sorted = [...pw.blocks]..sort((a, b) => a.y.compareTo(b.y));
          return jsonEncode({
            'pageId': pageId,
            'title': title,
            'pageWidth': pw.props.pageWidth,
            'blocks': [
              for (final b in sorted) {...pw.bounds(b), 'preview': _preview(b)}
            ],
            'overlaps': pw.overlaps(),
          });
      }
      return jsonEncode({
        'pageId': pageId,
        'title': title,
        'page': data.props.toJson(),
        'blocks': [for (final b in data.blocks) b.toJson()],
      });

    case 'search':
      final nb = _notebookOf(app, args);
      final q = '${args['query'] ?? ''}';
      if (q.trim().isEmpty) throw McpToolError('query is empty');
      final gate = _Gate(app, nb);
      final hits = [
        for (final h in app.searchPagesOf(nb, q))
          if (!gate.covers(h.pageId)) h
      ];
      return jsonEncode([
        for (final h in hits)
          {
            'pageId': h.pageId,
            'title': _titleOf(app, nb, h.pageId),
            'snippet': h.snippet,
          },
      ]);

    case 'describe_block_types':
      return jsonEncode(_describe());

    case 'create_page':
      final (nb, sectionId) = _sectionOf(app, args);
      final title = _titleArg(args['title']);
      final warnings = <String>[];
      final blocks = _contentArgs(args, warnings, required: false);
      _refuseLockedWindows(app, blocks);
      final level = _levelArg(args['level']);
      final afterPageId = args['afterPageId'] as String?;
      final node = _createPages(app, nb, sectionId,
          [(title: title, level: level)], afterPageId: afterPageId).single;
      final placed = _fillNewPage(app, nb, node.id, blocks);
      _refreshTree(app, nb);
      return jsonEncode({
        'pageId': node.id,
        if (blocks.isNotEmpty) 'added': blocks.length,
        if (placed.isNotEmpty) 'blocks': placed,
        if (warnings.isNotEmpty) 'warnings': warnings,
      });

    case 'create_pages':
      final (nb, sectionId) = _sectionOf(app, args);
      final raw = args['pages'];
      if (raw is! List || raw.isEmpty) {
        throw McpToolError('pages must be a non-empty array of {title, ...}');
      }
      if (raw.length > _kMaxPages) {
        throw McpToolError('at most $_kMaxPages pages per call');
      }
      // Everything is parsed before anything is written: a batch that fails
      // on page 7 must not leave pages 1-6 behind for somebody to clean up.
      final warnings = <String>[];
      final specs = <({String title, int level, List<Block> blocks})>[];
      for (var i = 0; i < raw.length; i++) {
        final p = raw[i];
        if (p is! Map) throw McpToolError('pages[$i] is not an object');
        final args = p.cast<String, Object?>();
        final pageWarnings = <String>[];
        try {
          specs.add((
            title: _titleArg(args['title']),
            level: _levelArg(args['level']),
            blocks: _contentArgs(args, pageWarnings, required: false),
          ));
        } on McpToolError catch (e) {
          throw McpToolError('pages[$i]: ${e.message}');
        }
        warnings.addAll([for (final w in pageWarnings) 'pages[$i]: $w']);
      }
      for (final s in specs) {
        _refuseLockedWindows(app, s.blocks);
      }
      final nodes = _createPages(app, nb, sectionId,
          [for (final s in specs) (title: s.title, level: s.level)]);
      final out = <Map<String, Object?>>[];
      for (var i = 0; i < nodes.length; i++) {
        _fillNewPage(app, nb, nodes[i].id, specs[i].blocks);
        out.add({
          'pageId': nodes[i].id,
          'title': specs[i].title,
          'added': specs[i].blocks.length,
        });
      }
      _refreshTree(app, nb);
      return jsonEncode({
        'pages': out,
        if (warnings.isNotEmpty) 'warnings': warnings,
      });

    case 'append_blocks':
      final (nb, pageId) = _pageOf(app, args, pageOnly: true);
      final warnings = <String>[];
      final pw = _PageWrite.open(app, nb, pageId);
      final blocks = _parseBlocks(args['blocks'], warnings);
      _refuseLockedWindows(app, blocks);
      return jsonEncode(_append(pw, blocks, warnings));

    case 'append_markdown':
      final (nb, pageId) = _pageOf(app, args, pageOnly: true);
      final blocks =
          _markdownArg(args['markdown'], literal: args['literal'] == true)!;
      return jsonEncode(
          _append(_PageWrite.open(app, nb, pageId), blocks, <String>[]));

    case 'insert_blocks':
      final (nb, pageId) = _pageOf(app, args, pageOnly: true);
      final pw = _PageWrite.open(app, nb, pageId);
      final warnings = <String>[];
      final blocks = _contentArgs(args, warnings);
      _refuseLockedWindows(app, blocks);
      return jsonEncode(_insert(pw, blocks, warnings,
          afterBlockId: args['afterBlockId'] as String?,
          atY: (args['y'] as num?)?.toDouble()));

    case 'update_block':
      final (nb, pageId) = _pageOf(app, args, pageOnly: true);
      return jsonEncode(_update(_PageWrite.open(app, nb, pageId), args));

    case 'delete_blocks':
      final (nb, pageId) = _pageOf(app, args, pageOnly: true);
      final pw = _PageWrite.open(app, nb, pageId);
      final targets = pw.find(args['blockIds']);
      pw.begin();
      final gone = {for (final b in targets) b.id};
      if (pw.onScreen) {
        for (final id in gone) {
          app.removeBlock(id, recordUndo: false);
        }
      } else {
        pw.blocks.removeWhere((b) => gone.contains(b.id));
      }
      pw.commit();
      return jsonEncode({'deleted': gone.length});

    case 'move_blocks':
      final (nb, pageId) = _pageOf(app, args, pageOnly: true);
      final pw = _PageWrite.open(app, nb, pageId);
      final targets = pw.find(args['blockIds']);
      final dx = (args['dx'] as num?)?.toDouble() ?? 0;
      final dy = (args['dy'] as num?)?.toDouble() ?? 0;
      if (dx == 0 && dy == 0) throw McpToolError('give dx and/or dy');
      pw.begin();
      for (final b in targets) {
        _shift(b, dx, dy);
      }
      pw.commit(changed: targets);
      return jsonEncode({
        'blocks': [for (final b in targets) pw.bounds(b)],
        ..._warningsOf(pw.overlaps(only: {for (final b in targets) b.id})),
      });

    case 'rename_page':
      final (nb, id) = _pageOf(app, args);
      final title = _titleArg(args['title']);
      _guardWritable(app, nb);
      final n = _nodesOf(app, nb).firstWhere((n) => n.id == id);
      n.title = title;
      app.importNode(nb, n);
      _refreshTree(app, nb);
      return jsonEncode({'pageId': id, 'title': title});

    case 'move_page':
      final (nb, id) = _pageOf(app, args, pageOnly: true);
      _guardWritable(app, nb);
      _movePage(app, nb, id, args);
      _refreshTree(app, nb);
      final n = _nodesOf(app, nb).firstWhere((n) => n.id == id);
      return jsonEncode(
          {'pageId': id, 'sectionId': n.parentId, 'level': n.level});

    case 'delete_page':
      final (nb, id) = _pageOf(app, args, pageOnly: true);
      _guardWritable(app, nb);
      // A subpage of the page going is NOT deleted with it, and slides up to
      // whatever page is above — which can be one with a passcode.
      final gate = _Gate(app, nb);
      gate.refuseCoverageChange([for (final n in gate.nodes) if (n.id != id) n]);
      await app.deleteNodeIn(nb, id);
      _refreshTree(app, nb);
      return jsonEncode({'deleted': id, 'restorable': 'recycle bin'});

    case 'create_flashcards':
      final (nb, pageId) = _pageOf(app, args, pageOnly: true);
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
      final r = _append(_PageWrite.open(app, nb, pageId), [
        Block(type: BlockType.text, x: 0, y: 0, w: 460, content: {
          'text': '${lines.join('\n')}\n',
          'autoWidth': false,
        })
      ], <String>[]);
      return jsonEncode({...r, 'added': cards.length});

    default:
      throw McpToolError('no such tool: $name');
  }
}

// ── Passcodes ────────────────────────────────────────────────────────────
//
// **Anything a passcode covers is closed to AI helpers**: not listed, not
// searched, not read, not changed — not even while it is unlocked in the app
// — and no tool takes a passcode. The owner: *"I don't even want them to be
// able to enter a passcode as it could allow it to just be brute forced
// easily, they should just not be able to access locked pages."*
//
// Not "while it is locked". An unlock is for the person at the keyboard, who
// opened that page to read it; an agent running beside them for the rest of
// the session is not who it was opened for. And "a passcode keeps it from AI
// helpers" is one sentence that is always true, where "until you unlock it"
// would mean an unlock at nine still exposing the page to an agent at three.
//
// The same honesty as the gate itself (`state/page_protection.dart`): this
// closes OPENOTE's door. An AI tool that can read files on this computer can
// read the notebook's container as anyone can, and the AI dialog says so.

/// What the passcodes in one notebook cover, for one tool call.
///
/// Built per notebook, never from the app's own [AppState.isLocked]: that
/// knows only the OPEN notebook, and this door reaches all of them.
class _Gate {
  _Gate(AppState app, String nb)
      : this._(app.protectedNodeIdsOf(nb), _nodesOf(app, nb));

  _Gate._(this._protected, this.nodes)
      : _tree = ProtectionTree(nodes, _protected.contains);

  final Set<String> _protected;

  /// The notebook's nodes in navigator order — all of them, covered or not.
  final List<TreeNode> nodes;
  final ProtectionTree _tree;

  /// The node whose passcode covers [id], or null when none does.
  String? over(String id) => _protected.isEmpty ? null : _tree.governing(id);

  bool covers(String id) => over(id) != null;

  /// Whether anything in this notebook is covered at all.
  bool get coversAny =>
      _protected.isNotEmpty && nodes.any((n) => covers(n.id));

  /// Refuse [n] when a passcode covers it.
  void refuse(TreeNode n) {
    if (covers(n.id)) throw McpToolError(_lockedMessage(n));
  }

  /// **Refuse a change to the tree that would change what a passcode
  /// covers.** [after] is this notebook's nodes as the change would leave
  /// them, in order, and [made] the pages it creates, which must come out
  /// covered by nothing.
  ///
  /// Asked of the result rather than written as a list of cases, because the
  /// cases are not obvious: re-indenting a run of pages can flatten a subpage
  /// out from under its locked parent — the levels clamp at 2 — and a
  /// subpage appended to a section lands under whatever page is last in it.
  /// The same walk before and after catches every one of them, including any
  /// nobody has thought of yet.
  void refuseCoverageChange(List<TreeNode> after,
      {Set<String> made = const {}}) {
    if (_protected.isEmpty) return;
    final next = _Gate._(_protected, after);
    for (final n in after) {
      final isNew = made.contains(n.id);
      if (next.over(n.id) == (isNew ? null : over(n.id))) continue;
      throw McpToolError(isNew
          ? 'a new page there would sit under a page with a passcode — '
              'choose another place. $_kNotHere'
          : 'that would change which pages a passcode covers, so nothing '
              'was changed. $_kNotHere');
    }
  }
}

const _kNotHere = 'Openote never lets an AI helper into anything with a '
    'passcode, even while it is unlocked in the app, and there is no way to '
    'unlock it from here.';

String _lockedMessage(TreeNode n) {
  final what = switch (n.kind) {
    NodeKind.page => 'That page',
    NodeKind.section => 'That section',
    NodeKind.sectionGroup => 'That section group',
  };
  return '$what has a passcode, or is inside something that does. '
      '$_kNotHere Nothing was read or changed.';
}

/// Whether a passcode covers page [id], in whichever notebook holds it.
bool _coveredAnywhere(AppState app, String id) {
  final found = _findNode(app, id);
  return found != null && _Gate(app, found.$1).covers(id);
}

/// **Refuse a page window onto anything a passcode covers.** A window shows
/// its source live, so writing one would put what is behind the passcode on a
/// page that has none.
void _refuseLockedWindows(AppState app, Iterable<Block> blocks) {
  for (final b in blocks) {
    if (b.type != BlockType.embed) continue;
    final ref = b.content['ref'];
    final target = ref is Map ? ref['pageId'] : null;
    if (target is String && _coveredAnywhere(app, target)) {
      throw McpToolError('a page window cannot show a page with a passcode. '
          '$_kNotHere Nothing was changed.');
    }
  }
}

// ── Reading the tree ─────────────────────────────────────────────────────

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

List<TreeNode> _nodesOf(AppState app, String nb) =>
    nb == app.notebookId ? app.nodes : app.readNodesOf(nb);

/// Find [id] in the open notebook first, then the rest, so callers never
/// have to pass both a notebook and an id.
(String, TreeNode)? _findNode(AppState app, String id) {
  final open = app.notebookId;
  if (open != null) {
    final n = app.nodes.where((n) => n.id == id).firstOrNull;
    if (n != null) return (open, n);
  }
  for (final nb in app.notebooks) {
    if (nb.id == open) continue;
    final n = app.readNodesOf(nb.id).where((x) => x.id == id).firstOrNull;
    if (n != null) return (nb.id, n);
  }
  return null;
}

/// Resolve a pageId to its notebook by looking. [pageOnly] refuses a
/// section id where only a page makes sense.
(String, String) _pageOf(AppState app, Map<String, Object?> args,
    {bool pageOnly = false}) {
  final pageId = args['pageId'] as String?;
  if (pageId == null || pageId.isEmpty) throw McpToolError('pageId missing');
  final found = _findNode(app, pageId);
  if (found == null) {
    throw McpToolError('no page $pageId in any notebook — list_pages shows '
        'what exists');
  }
  // Before anything else is said about it, its kind included.
  _Gate(app, found.$1).refuse(found.$2);
  if (pageOnly && found.$2.kind != NodeKind.page) {
    throw McpToolError('$pageId is a ${found.$2.kind.name}, not a page');
  }
  return (found.$1, pageId);
}

/// The section a new page goes into: the one asked for (in whichever
/// notebook holds it), or the first section of the notebook asked for.
(String, String) _sectionOf(AppState app, Map<String, Object?> args) {
  final asked = args['sectionId'] as String?;
  if (asked == null) {
    final nb = _notebookOf(app, args);
    final gate = _Gate(app, nb);
    // The first one an AI helper may use: defaulting into a section with a
    // passcode would refuse a call that never named it.
    final first = gate.nodes
        .where((n) => n.kind == NodeKind.section && !gate.covers(n.id))
        .firstOrNull;
    if (first == null) {
      throw McpToolError(gate.coversAny
          ? 'every section in that notebook has a passcode. $_kNotHere'
          : 'that notebook has no sections');
    }
    return (nb, first.id);
  }
  final found = _findNode(app, asked);
  if (found != null) _Gate(app, found.$1).refuse(found.$2);
  if (found == null || found.$2.kind != NodeKind.section) {
    throw McpToolError('no section $asked — list_pages with kind="section" '
        'shows the sections');
  }
  if (args['notebookId'] != null && args['notebookId'] != found.$1) {
    throw McpToolError('section $asked is not in notebook '
        '${args['notebookId']}');
  }
  return (found.$1, asked);
}

Map<String, Object?> _listPages(AppState app, Map<String, Object?> args) {
  final nb = _notebookOf(app, args);
  final gate = _Gate(app, nb);
  // Filtered FIRST, so no filter below — a title query above all — can be
  // used to learn anything about what a passcode covers.
  Iterable<TreeNode> nodes = [
    for (final n in gate.nodes)
      if (!gate.covers(n.id)) n
  ];
  final sectionId = args['sectionId'] as String?;
  if (sectionId != null) {
    final asked = gate.nodes.where((n) => n.id == sectionId).firstOrNull;
    if (asked != null) gate.refuse(asked);
    if (!nodes.any((n) => n.id == sectionId && n.kind == NodeKind.section)) {
      throw McpToolError('no section $sectionId in that notebook — '
          'list_pages with kind="section" shows the sections');
    }
    nodes = nodes.where((n) => n.parentId == sectionId);
  }
  final kind = args['kind'] as String?;
  if (kind != null) {
    final k = NodeKind.values.where((k) => k.name == kind).firstOrNull;
    if (k == null) throw McpToolError('kind must be section, page or sectionGroup');
    nodes = nodes.where((n) => n.kind == k);
  }
  final query = (args['query'] as String?)?.trim().toLowerCase();
  if (query != null && query.isNotEmpty) {
    nodes = nodes.where((n) => n.title.toLowerCase().contains(query));
  }
  final maxLevel = (args['maxLevel'] as num?)?.toInt();
  if (maxLevel != null) {
    nodes = nodes.where((n) => n.kind != NodeKind.page || n.level <= maxLevel);
  }
  final all = nodes.toList();
  final offset = ((args['offset'] as num?)?.toInt() ?? 0).clamp(0, all.length);
  final limit = ((args['limit'] as num?)?.toInt() ?? 100).clamp(1, 1000);
  final end = math.min(all.length, offset + limit);
  return {
    'total': all.length,
    'offset': offset,
    if (end < all.length) 'nextOffset': end,
    'items': [
      for (final n in all.sublist(offset, end))
        {
          'id': n.id,
          'title': n.title,
          'kind': n.kind.name,
          if (n.parentId != null) 'parentId': n.parentId,
          if (n.kind == NodeKind.page) 'level': n.level,
        },
    ],
    // Said once, with no count, and whatever was asked — so it tells the
    // model why it may not see something it was asked about, and nothing
    // about what that something is.
    if (gate.coversAny)
      'withheld': 'Some sections or pages have a passcode, so they are not '
          'listed. $_kNotHere',
  };
}

PageData _readPage(AppState app, String nb, String pageId) =>
    nb == app.notebookId && pageId == app.pageId
        // The OPEN page reads from the live editor, not the last save — an
        // assistant must see what the user sees.
        ? PageData(app.blocks, app.pageProps)
        : app.readPageOf(nb, pageId);

String _titleOf(AppState app, String nb, String pageId) =>
    _nodesOf(app, nb).where((n) => n.id == pageId).firstOrNull?.title ?? '';

String _preview(Block b) {
  final s = switch (b.type) {
    BlockType.text => b.content['text'],
    BlockType.code => b.content['source'],
    BlockType.math => b.content['latex'],
    BlockType.flashcard => b.content['front'],
    _ => null,
  };
  if (s is! String) return '';
  final one = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return one.length <= 60 ? one : '${one.substring(0, 60)}…';
}

Map<String, Object?> _describe() => {
      'layout': {
        'units': 'logical px in page space; x grows right, y grows down',
        'pageLeftMargin': AppState.pageLeftMargin,
        'contentTop': AppState.contentTop,
        'pageWidth': PageProps().pageWidth,
        'defaultTextWidth': kMarkdownTextWidth,
        'gapBetweenBlocks': _kGap,
        'grid': PageProps().gridSize,
        'notes': 'Blocks without x/y are stacked down the left margin for '
            'you; append and insert return each block\'s placed box. h is '
            'normally omitted (automatic height).',
      },
      'tables': 'A table lives INSIDE a text block as an inline atom: put '
          '"![${TableData.referenceAlt}](onote://atom/<id>)" on its own line '
          'of content.text and {"<id>": {"id": "<id>", "type": "table", '
          '"content": {"cells": [["h1","h2"],["a","b"]]}}} in content.atoms. '
          'append_markdown does this for you from a GFM pipe table.',
      'blockTypes': [for (final s in blockSchemas) s.toJson()],
      'codeLanguages': [
        for (final l in codeLanguages)
          {
            'id': l.id,
            'name': l.name,
            if (l.aliases.isNotEmpty) 'aliases': l.aliases,
          }
      ],
      'otherTypes': 'Types not listed (ink, frame, embed, file, video, …) '
          'round-trip verbatim: copy what read_page returns.',
    };

// ── Arguments ────────────────────────────────────────────────────────────

String _titleArg(Object? raw) {
  final title = '${raw ?? ''}'.trim();
  if (title.isEmpty) throw McpToolError('title is empty');
  return title;
}

int _levelArg(Object? raw) {
  if (raw == null) return 0;
  if (raw is! num || raw < 0 || raw > 2) {
    throw McpToolError('level must be 0, 1 or 2');
  }
  return raw.toInt();
}

List<Block>? _markdownArg(Object? raw, {bool literal = false}) {
  if (raw == null) return null;
  final md = '$raw';
  if (md.trim().isEmpty) throw McpToolError('markdown is empty');
  if (md.length > _kMaxText) throw McpToolError('markdown is over 256 KB');
  // Converting is the right default, but it must not surprise somebody who
  // genuinely wanted the Markdown itself on the page (v1.0.2 plan §20).
  if (literal) {
    return [
      Block(type: BlockType.text, x: 0, y: 0, w: kMarkdownTextWidth, content: {
        'text': md,
        'autoWidth': false,
      })
    ];
  }
  return markdownToBlocks(md, madeIn: kAppVersion);
}

/// The blocks a call carries, from `markdown` and/or `blocks` (markdown
/// first). [required] refuses a call with neither.
List<Block> _contentArgs(Map<String, Object?> args, List<String> warnings,
    {bool required = true}) {
  final fromMd = _markdownArg(args['markdown']) ?? const <Block>[];
  final fromJson = args['blocks'] == null
      ? const <Block>[]
      : _parseBlocks(args['blocks'], warnings);
  final all = [...fromMd, ...fromJson];
  if (required && all.isEmpty) throw McpToolError('give blocks or markdown');
  if (all.length > _kMaxBlocks) {
    throw McpToolError('at most $_kMaxBlocks blocks per call');
  }
  return all;
}

/// Blocks whose x / y the caller left out, for the layout to fill in.
final Expando<bool> _autoX = Expando(), _autoY = Expando();

List<Block> _parseBlocks(Object? raw, List<String> warnings) {
  if (raw is! List || raw.isEmpty) {
    throw McpToolError('blocks must be a non-empty array');
  }
  if (raw.length > _kMaxBlocks) {
    throw McpToolError('at most $_kMaxBlocks blocks per call');
  }
  // THE consistency moment: parse through the format's own reader, so a
  // malformed block fails here with the parser's reason, and a valid one
  // — of any type, including types newer than this document — round-trips.
  final blocks = <Block>[];
  for (var i = 0; i < raw.length; i++) {
    final m = raw[i];
    if (m is! Map) throw McpToolError('blocks[$i] is not an object');
    Block b;
    try {
      final json = (jsonDecode(jsonEncode(m)) as Map).cast<String, dynamic>();
      // **Always a fresh id**, whatever the caller sent. Writing a block is
      // an import, and an import mints (Data Model Spec §2 rule 3): a block
      // copied from read_page of another page would otherwise carry that
      // block's id, and ids must be unique across the notebook (§8.1) —
      // which no check of THIS page could ever have caught. The id the
      // block got is in the result.
      json['id'] = newId();
      b = Block.fromJson(json);
      if (!json.containsKey('x')) _autoX[b] = true;
      if (!json.containsKey('y')) _autoY[b] = true;
    } catch (e) {
      throw McpToolError('blocks[$i] did not parse: $e');
    }
    // A block that parses can still be one nothing will draw — a code block
    // whose text is under `code` rather than `source` is stored, synced and
    // shown as an empty box. Say so now, while the caller can fix it.
    final check = checkBlockContent(b);
    final type = b.rawType ?? b.type.name;
    if (check.errors.isNotEmpty) {
      throw McpToolError('blocks[$i] ($type): ${check.errors.join('; ')}. '
          'describe_block_types lists every type\'s keys');
    }
    warnings.addAll([for (final w in check.warnings) 'blocks[$i]: $w']);
    final lang = b.type == BlockType.code ? b.content['language'] : null;
    if (lang is String && !_isKnownLanguage(lang)) {
      warnings.add('blocks[$i]: language "$lang" is not one Openote knows, '
          'so it will show as plain text — describe_block_types lists the ids');
    }
    // The app converts every table BLOCK it opens into a paragraph carrying
    // the table (model/table_conversion.dart). Writing the converted form
    // now saves that round trip and gives the client back the shape the
    // page will actually hold.
    if (b.type == BlockType.table) {
      final converted = tableBlockAsText(b, madeIn: kAppVersion);
      if (converted != null) {
        _autoX[converted] = _autoX[b];
        _autoY[converted] = _autoY[b];
        b = converted;
      }
    }
    blocks.add(b);
  }
  return blocks;
}

bool _isKnownLanguage(String lang) {
  final l = lang.trim().toLowerCase();
  return l.isEmpty ||
      languageFor(l).id != kDefaultLanguageId ||
      languageFor(kDefaultLanguageId).aliases.contains(l) ||
      l == kDefaultLanguageId;
}

// ── Writing a page ───────────────────────────────────────────────────────

/// One page, read for a write — the live editor's blocks when it is on
/// screen, the stored ones otherwise — and written back through the matching
/// ordinary path (spec §4.6).
class _PageWrite {
  _PageWrite._(this.app, this.nb, this.pageId)
      : onScreen = nb == app.notebookId && pageId == app.pageId {
    if (onScreen) {
      blocks = app.blocks;
      props = app.pageProps;
    } else {
      final d = app.readPageOf(nb, pageId);
      blocks = [...d.blocks];
      props = d.props;
    }
  }

  factory _PageWrite.read(AppState app, String nb, String pageId) =>
      _PageWrite._(app, nb, pageId);

  factory _PageWrite.open(AppState app, String nb, String pageId) {
    _guardWritable(app, nb);
    return _PageWrite._(app, nb, pageId);
  }

  final AppState app;
  final String nb, pageId;
  final bool onScreen;
  late final List<Block> blocks;
  late final PageProps props;
  final List<Block> _added = [];
  bool _began = false;

  /// Where a block's height comes from, best first: a stored height, what
  /// the canvas measured when it drew it, then an estimate.
  (double, String) heightOf(Block b) {
    if (b.h != null) return (b.h!, 'stored');
    final measured = onScreen ? app.renderSizes[b.id]?.height : null;
    if (measured != null) return (measured, 'measured');
    return (app.estimatedHeight(b), 'estimated');
  }

  double bottomOf(Block b) => b.y + heightOf(b).$1;

  Map<String, Object?> bounds(Block b) {
    final (h, from) = heightOf(b);
    return {
      'id': b.id,
      'type': b.rawType ?? b.type.name,
      'x': b.x,
      'y': b.y,
      'w': b.w,
      'h': h.roundToDouble(),
      'heightIs': from,
    };
  }

  /// The blocks named by [raw], all of them or an error naming the missing.
  List<Block> find(Object? raw) {
    if (raw is! List || raw.isEmpty) {
      throw McpToolError('blockIds must be a non-empty array of block ids');
    }
    final byId = {for (final b in blocks) b.id: b};
    final missing = [for (final id in raw) if (!byId.containsKey(id)) '$id'];
    if (missing.isNotEmpty) {
      throw McpToolError('not on this page: ${missing.join(', ')} — '
          'read_page with format "layout" lists its blocks');
    }
    return [for (final id in raw.toSet()) byId[id]!];
  }

  /// Round a stacking position up onto the grid the live editor snaps to,
  /// so the snap in `addBlock` cannot pull a box up into the one above.
  double gridUp(double y) {
    if (!onScreen || !app.effectiveSnap) return y;
    final g = app.gridSize;
    return g <= 0 ? y : (y / g).ceil() * g;
  }

  /// Before the first change. On screen this is the ONE undo step the whole
  /// call becomes.
  void begin() {
    if (_began) return;
    _began = true;
    if (onScreen) app.pushUndo();
  }

  void add(List<Block> bs) {
    // Each tool checks before it writes anything; this is the backstop, so a
    // tool added later cannot forget.
    _refuseLockedWindows(app, bs);
    begin();
    _added.addAll(bs);
  }

  void commit({List<Block> changed = const [], bool contentChanged = false}) {
    begin();
    if (onScreen) {
      for (final b in _added) {
        app.addBlock(b, recordUndo: false);
      }
      // Every block widget is keyed by `docRevision`; a content change made
      // from outside the editor reaches a live text box only by rebuilding it.
      if (contentChanged) app.docRevision++;
      for (final b in changed) {
        app.updateBlock(b);
      }
      app.markDirty();
    } else {
      final now = nowMs();
      for (final b in changed) {
        b.updatedAt = now;
      }
      app.importPage(nb, pageId, [...blocks, ..._added], props);
      if (nb == app.notebookId) app.bumpNodes();
    }
  }

  /// Boxes that overlap, as human-readable warnings. Ink is left out: a
  /// drawing over text is what ink is for. [only] limits it to pairs that
  /// involve one of those blocks.
  List<String> overlaps({Set<String>? only}) {
    final all = [
      for (final b in [...blocks, ..._added])
        if (b.type != BlockType.ink && b.type != BlockType.frame) b
    ];
    final out = <String>[];
    for (var i = 0; i < all.length; i++) {
      for (var j = i + 1; j < all.length; j++) {
        final a = all[i], c = all[j];
        if (only != null && !only.contains(a.id) && !only.contains(c.id)) {
          continue;
        }
        final ox = math.min(a.x + a.w, c.x + c.w) - math.max(a.x, c.x);
        final oy = math.min(bottomOf(a), bottomOf(c)) - math.max(a.y, c.y);
        if (ox > 2 && oy > 2) {
          out.add('block ${a.id} overlaps block ${c.id} by '
              '${ox.round()}x${oy.round()} px');
        }
      }
    }
    return out;
  }
}

void _guardWritable(AppState app, String nb) {
  if (app.notebookIsReadOnly(nb)) {
    throw McpToolError('that notebook was written by a newer Openote and is '
        'read-only here — nothing was changed');
  }
}

Map<String, Object?> _warningsOf(List<String> w) =>
    w.isEmpty ? const {} : {'warnings': w};

/// Stack the blocks the caller did not place, from [top] down, at [x].
/// Returns the y just below the last one, gap included.
double _stack(_PageWrite pw, List<Block> blocks, double top, double x) {
  var y = pw.gridUp(top);
  for (final b in blocks) {
    // Only place what the caller did not: an explicit position — from a
    // client round-tripping read_page output — is honoured as given.
    final autoX = _autoX[b] ?? (b.x == 0 && b.y == 0);
    final autoY = _autoY[b] ?? (b.x == 0 && b.y == 0);
    if (autoX) b.x = x;
    if (!autoY) continue;
    b.y = y;
    y = pw.gridUp(y + pw.heightOf(b).$1 + _kGap);
  }
  return y;
}

Map<String, Object?> _placed(
    _PageWrite pw, List<Block> blocks, List<String> warnings) {
  final ids = {for (final b in blocks) b.id};
  return {
    'added': blocks.length,
    'blocks': [for (final b in blocks) pw.bounds(b)],
    ..._warningsOf([...warnings, ...pw.overlaps(only: ids)]),
  };
}

/// Below existing content, through the ordinary write paths (spec §4.6).
Map<String, Object?> _append(
    _PageWrite pw, List<Block> blocks, List<String> warnings) {
  var top = AppState.contentTop;
  for (final b in pw.blocks) {
    final bottom = pw.bottomOf(b);
    if (bottom > top) top = bottom;
  }
  if (pw.blocks.isNotEmpty) top += _kGapAfterExisting;
  _stack(pw, blocks, top, AppState.pageLeftMargin);
  pw.add(blocks);
  pw.commit();
  return _placed(pw, blocks, warnings);
}

/// Into the middle of the page, pushing what is below down by exactly the
/// room the new blocks take.
Map<String, Object?> _insert(_PageWrite pw, List<Block> blocks,
    List<String> warnings,
    {String? afterBlockId, double? atY}) {
  if ((afterBlockId == null) == (atY == null)) {
    throw McpToolError('give exactly one of afterBlockId or y');
  }
  double top, x, below;
  Block? anchor;
  if (afterBlockId != null) {
    anchor = pw.find([afterBlockId]).single;
    below = pw.bottomOf(anchor);
    top = below + _kGap;
    x = anchor.x;
  } else {
    top = math.max(atY!, AppState.contentTop);
    below = top;
    x = AppState.pageLeftMargin;
  }
  final end = _stack(pw, blocks, top, x);
  // What sat below keeps the gap it had to whatever was above it — now the
  // last inserted block. Inserting at a bare y has no gap above to reuse, so
  // the stacking gap goes in instead.
  final room = end - below - (anchor != null ? _kGap : 0);
  pw.begin();
  // Everything that starts at or below the insertion line moves; a box
  // BESIDE the anchor (starting above its bottom edge) stays put.
  final moved = <Block>[];
  for (final b in pw.blocks) {
    if (identical(b, anchor) || b.y < below - 1) continue;
    _shift(b, 0, room);
    moved.add(b);
  }
  pw.add(blocks);
  pw.commit(changed: moved);
  return {..._placed(pw, blocks, warnings), 'shifted': moved.length};
}

Map<String, Object?> _update(_PageWrite pw, Map<String, Object?> args) {
  final b = pw.find([args['blockId']]).single;
  final warnings = <String>[];
  final patch = args['content'];
  if (patch != null && patch is! Map) {
    throw McpToolError('content must be an object');
  }
  final geometry = ['x', 'y', 'w', 'h'].where(args.containsKey).toList();
  if (patch == null && geometry.isEmpty) {
    throw McpToolError('nothing to change — give content and/or x, y, w, h');
  }
  for (final k in geometry) {
    final v = args[k];
    if (!(v is num || (k == 'h' && v == null))) {
      throw McpToolError('$k must be a number');
    }
  }
  Map<String, dynamic>? content;
  if (patch is Map) {
    final copy = (jsonDecode(jsonEncode(patch)) as Map).cast<String, dynamic>();
    if (args['replaceContent'] == true) {
      content = copy;
    } else {
      content = (jsonDecode(jsonEncode(b.content)) as Map)
          .cast<String, dynamic>();
      for (final e in copy.entries) {
        if (e.value == null) {
          content.remove(e.key);
        } else {
          content[e.key] = e.value;
        }
      }
    }
    // Checked as the block it would become, before anything is touched.
    final candidate = Block.fromJson(b.toJson()..['content'] = content);
    _refuseLockedWindows(pw.app, [candidate]);
    final check = checkBlockContent(candidate);
    if (check.errors.isNotEmpty) {
      throw McpToolError('${check.errors.join('; ')} — nothing was changed');
    }
    warnings.addAll(check.warnings);
  }
  pw.begin();
  if (content != null) {
    // A change of text is an edit like a typed one (spec §4.6), so tags and
    // flashcard schedules follow their lines the way they do when typing —
    // unless the caller sent tags of its own, which are then the truth.
    if (b.type == BlockType.text && !(patch as Map).containsKey('tags')) {
      final before = b.content['text'] as String? ?? '';
      final after = content['text'] as String? ?? '';
      NoteTag.rebase(content, before, after);
      pw.app.study.remapCardStates(b.id, NoteTag.lineMoves(before, after));
    }
    b.content = content;
  }
  final dx = args.containsKey('x') ? (args['x'] as num).toDouble() - b.x : 0.0;
  final dy = args.containsKey('y') ? (args['y'] as num).toDouble() - b.y : 0.0;
  if (dx != 0 || dy != 0) _shift(b, dx, dy);
  if (args.containsKey('w')) b.w = (args['w'] as num).toDouble();
  if (args.containsKey('h')) b.h = (args['h'] as num?)?.toDouble();
  pw.commit(changed: [b], contentChanged: content != null);
  return {
    'block': pw.bounds(b),
    ..._warningsOf([...warnings, ...pw.overlaps(only: {b.id})]),
  };
}

/// Move a block, and its ink with it: stroke points are page-absolute (Ink
/// Spec §3), so moving the box alone would leave the drawing behind. Working
/// form carries the points; the stored form carries an origin they are
/// relative to (`ink_storage.dart`).
void _shift(Block b, double dx, double dy) {
  b
    ..x += dx
    ..y += dy;
  if (b.type != BlockType.ink) return;
  final strokes = b.content['strokes'];
  if (strokes is List) {
    for (final sj in strokes) {
      if (sj is! Map) continue;
      for (final (key, d) in [('x', dx), ('y', dy)]) {
        final vs = sj[key];
        if (d != 0 && vs is List) sj[key] = [for (final v in vs) (v as num) + d];
      }
    }
  }
  final ink = b.content['ink'];
  if (ink is Map) {
    final o = ink['o'];
    final ox = o is List && o.isNotEmpty ? (o[0] as num).toDouble() : 0.0;
    final oy = o is List && o.length > 1 ? (o[1] as num).toDouble() : 0.0;
    ink['o'] = [ox + dx, oy + dy];
  }
  b.updatedAt = nowMs();
}

// ── Writing the tree ─────────────────────────────────────────────────────

void _refreshTree(AppState app, String nb) {
  if (nb != app.notebookId) return;
  app.reloadNodes();
  app.bumpNodes();
  app.refresh();
}

/// A position key strictly after [after] (or after now, whichever is later).
/// Keys are `'a' + 15-digit ms` and sort as strings.
String _positionAfter(String? after) {
  final now = 'a${nowMs().toString().padLeft(15, '0')}';
  if (after == null || now.compareTo(after) > 0) return now;
  final n = int.tryParse(after.substring(1));
  if (after.length == 16 && n != null) {
    return 'a${(n + 1).toString().padLeft(15, '0')}';
  }
  return '${after}1';
}

/// The pages of [sectionId], each with the subpages that hang under it —
/// the unit the navigator moves, because hierarchy is contiguous runs.
List<List<TreeNode>> _groupsOf(List<TreeNode> nodes, String sectionId) {
  final groups = <List<TreeNode>>[];
  for (final p in nodes) {
    if (p.kind != NodeKind.page || p.parentId != sectionId) continue;
    if (p.level == 0 || groups.isEmpty) {
      groups.add([p]);
    } else {
      groups.last.add(p);
    }
  }
  return groups;
}

/// Rewrite the order of a section's pages. Positions are rebuilt for the
/// whole run, as `reorderNode` does: there is no guaranteed gap between two
/// adjacent keys to insert into.
void _writeOrder(AppState app, String nb, List<TreeNode> ordered) {
  var seq = nowMs();
  for (final p in ordered) {
    p.position = 'a${(seq++).toString().padLeft(15, '0')}';
    app.importNode(nb, p);
  }
}

List<TreeNode> _createPages(AppState app, String nb, String sectionId,
    List<({String title, int level})> specs,
    {String? afterPageId}) {
  _guardWritable(app, nb);
  final gate = _Gate(app, nb);
  final nodes = gate.nodes;
  final siblings = [
    for (final n in nodes)
      if (n.kind == NodeKind.page && n.parentId == sectionId) n
  ];
  final made = [
    for (final s in specs)
      TreeNode(
          kind: NodeKind.page,
          parentId: sectionId,
          title: s.title,
          level: s.level)
  ];
  final ids = {for (final n in made) n.id};
  if (afterPageId != null) {
    final anchor = nodes.where((n) => n.id == afterPageId).firstOrNull;
    if (anchor != null) gate.refuse(anchor);
    final groups = _groupsOf(nodes, sectionId);
    final at = groups.indexWhere((g) => g.any((n) => n.id == afterPageId));
    if (at < 0) {
      throw McpToolError('afterPageId $afterPageId is not a page of that '
          'section');
    }
    // After the anchor's subpages too, or they would become the new page's.
    final ordered = [
      for (final g in groups.take(at + 1)) ...g,
      ...made,
      for (final g in groups.skip(at + 1)) ...g,
    ];
    gate.refuseCoverageChange([
      for (final n in nodes)
        if (n.kind != NodeKind.page || n.parentId != sectionId) n,
      ...ordered,
    ], made: ids);
    _writeOrder(app, nb, ordered);
  } else {
    var last = siblings.isEmpty
        ? null
        : siblings.map((n) => n.position).reduce((a, b) => a.compareTo(b) > 0 ? a : b);
    for (final n in made) {
      n.position = last = _positionAfter(last);
    }
    // Positions first, so the check sees the pages where they will land —
    // last in the section, under whatever page is last there now.
    gate.refuseCoverageChange([...nodes, ...made], made: ids);
    for (final n in made) {
      app.importNode(nb, n);
    }
  }
  return made;
}

/// Lay [blocks] out on a page nobody has opened yet and write them.
List<Map<String, Object?>> _fillNewPage(
    AppState app, String nb, String pageId, List<Block> blocks) {
  if (blocks.isEmpty) return const [];
  final pw = _PageWrite.open(app, nb, pageId);
  _stack(pw, blocks, AppState.contentTop, AppState.pageLeftMargin);
  pw.add(blocks);
  pw.commit();
  return [for (final b in blocks) pw.bounds(b)];
}

void _movePage(AppState app, String nb, String id, Map<String, Object?> args) {
  final gate = _Gate(app, nb);
  final nodes = gate.nodes;
  final page = nodes.firstWhere((n) => n.id == id);
  final afterPageId = args['afterPageId'] as String?;
  final askedSection = args['sectionId'] as String?;
  if (afterPageId == id) throw McpToolError('a page cannot go after itself');
  TreeNode? after;
  if (afterPageId != null) {
    final anchor = nodes.where((n) => n.id == afterPageId).firstOrNull;
    if (anchor != null) gate.refuse(anchor);
    after = nodes
        .where((n) => n.id == afterPageId && n.kind == NodeKind.page)
        .firstOrNull;
    if (after == null) {
      throw McpToolError('afterPageId $afterPageId is not a page in the same '
          'notebook — moving between notebooks is not supported');
    }
  }
  final target = askedSection ?? after?.parentId ?? page.parentId!;
  final targetNode = nodes.where((n) => n.id == target).firstOrNull;
  if (targetNode != null) gate.refuse(targetNode);
  if (!nodes.any((n) => n.id == target && n.kind == NodeKind.section)) {
    throw McpToolError('no section $target in the same notebook — moving '
        'between notebooks is not supported');
  }
  if (after != null && after.parentId != target) {
    throw McpToolError('afterPageId is not in section $target');
  }
  if (args['level'] == null && askedSection == null && after == null) {
    throw McpToolError('give sectionId, afterPageId and/or level');
  }

  // The page travels with its subpages: the run of deeper pages below it.
  final section = [
    for (final n in nodes)
      if (n.kind == NodeKind.page && n.parentId == page.parentId) n
  ];
  final run = <TreeNode>[page];
  for (final n in section.skip(section.indexOf(page) + 1)) {
    if (n.level <= page.level) break;
    run.add(n);
  }
  if (after != null && run.any((n) => n.id == after!.id)) {
    throw McpToolError('a page cannot go after its own subpage');
  }
  // A subpage with a passcode of its own would travel with the run.
  if (run.any((n) => gate.covers(n.id))) {
    throw McpToolError('a subpage under that page has a passcode, and would '
        'move with it. $_kNotHere Nothing was changed.');
  }
  // Worked out, not yet applied: [page] and its run are live nodes, and
  // nothing may change until the result has been checked.
  final level = {for (final n in run) n.id: n.level};
  if (args['level'] != null) {
    final delta = _levelArg(args['level']) - page.level;
    for (final n in run) {
      level[n.id] = (n.level + delta).clamp(0, 2);
    }
  }
  final moving = {for (final n in run) n.id};
  final rest = [
    for (final n in nodes)
      if (n.kind == NodeKind.page &&
          n.parentId == target &&
          !moving.contains(n.id))
        n
  ];
  var at = rest.length;
  if (after != null) {
    at = rest.indexWhere((n) => n.id == after!.id) + 1;
    // Past the anchor's own subpages.
    while (at < rest.length && rest[at].level > after.level) {
      at++;
    }
  } else if (askedSection == null || askedSection == page.parentId) {
    // Only the level changed: stay where it is.
    final i = rest.indexWhere((n) => nodes.indexOf(n) > nodes.indexOf(page));
    at = i < 0 ? rest.length : i;
  }
  final ordered = [...rest.take(at), ...run, ...rest.skip(at)];
  TreeNode moved(TreeNode n) => TreeNode(
      id: n.id,
      kind: n.kind,
      parentId: target,
      title: n.title,
      position: n.position,
      color: n.color,
      level: level[n.id]!,
      createdAt: n.createdAt);
  gate.refuseCoverageChange([
    for (final n in nodes)
      if (n.kind != NodeKind.page ||
          (n.parentId != target && !moving.contains(n.id)))
        n,
    for (final n in ordered) moving.contains(n.id) ? moved(n) : n,
  ]);
  for (final n in run) {
    n
      ..level = level[n.id]!
      ..parentId = target;
  }
  _writeOrder(app, nb, ordered);
}
