import 'inline_atom.dart';
import 'models.dart';

/// **What each block type keeps in `content`, written down once.**
///
/// `Block.fromJson` accepts any map as `content` — that is the format's
/// forward-compatibility contract, and it is why a block type added next year
/// round-trips through an old build. But it also means a block whose content
/// uses the WRONG key parses perfectly and draws empty: a code block sent as
/// `{"code": "…"}` is stored, synced and shown as a blank box, because
/// `CodeBlockView` reads `source`. Nothing anywhere said the key was wrong.
///
/// This table is the answer to "what does a well-formed X look like", used by
/// the external API (spec 14) both to check what a client wrote and to tell a
/// client what to write (`describe_block_types`). It lives beside the model
/// rather than in the API layer so it is the FORMAT's documentation, not a
/// second schema of the API's own — and a type with no entry here is simply
/// not checked, so a new block type still works through the API the day it
/// exists (spec 14 §2).
///
/// Unknown keys are WARNED about, never refused: the unknown-field rule
/// (Data Model Spec §3) says readers preserve fields they do not understand,
/// and a newer build may well have added one.
class ContentKey {
  const ContentKey(this.name, this.kind, this.description,
      {this.required = false});

  final String name;

  /// `string`, `number`, `bool`, `list`, `map` or `any`.
  final String kind;
  final String description;
  final bool required;

  Map<String, Object> toJson() => {
        'key': name,
        'type': kind,
        if (required) 'required': true,
        'description': description,
      };
}

class BlockSchema {
  const BlockSchema({
    required this.type,
    required this.summary,
    required this.keys,
    this.mistakes = const {},
    this.example = const {},
    this.oneOf = const [],
  });

  final String type;
  final String summary;
  final List<ContentKey> keys;

  /// Keys clients reach for that this type spells differently, wrong → right.
  final Map<String, String> mistakes;

  /// A minimal well-formed `content` for this type.
  final Map<String, Object> example;

  /// Keys of which at least one must be present — for a type with two
  /// shapes, like an image that is either a picture or a page of a PDF.
  final List<String> oneOf;

  Map<String, Object> toJson() => {
        'type': type,
        'summary': summary,
        'content': [for (final k in keys) k.toJson()],
        'example': {'type': type, 'content': example},
      };
}

/// Every type with a documented content shape, in the order a writer is most
/// likely to want them. Types not listed (ink, frame, embed, …) are carried
/// verbatim and not checked.
const List<BlockSchema> blockSchemas = [
  BlockSchema(
    type: 'text',
    summary: 'Rich text. The text is Markdown: headings (#, ##, ###), lists, '
        'checkboxes, **bold**, links, `code`, \$inline math\$, fenced code. '
        'Tables live INSIDE a text block as inline atoms (see "atoms").',
    keys: [
      ContentKey('text', 'string', 'The Markdown source.', required: true),
      ContentKey('fontSize', 'number', 'Base font size in px (default 15).'),
      ContentKey('lineHeight', 'number', 'Line-height multiplier (default 1.5).'),
      ContentKey('font', 'string', 'Font family name.'),
      ContentKey('autoWidth', 'bool',
          'true: the box grows sideways with its longest line. Write false '
              'for a fixed-width box that wraps at w.'),
      ContentKey('inset', 'number', 'Inner padding in px.'),
      ContentKey(
          'atoms',
          'map',
          'Inline objects, keyed by id. Each is {id, type, content}; a table '
              'is {type: "table", content: {cells: [["a","b"],["1","2"]]}}. '
              'Each atom must be referenced from text, on its own line, as '
              '![update Openote to see the table](onote://atom/<id>).'),
    ],
    mistakes: {
      'markdown': 'text',
      'content': 'text',
      'body': 'text',
      'value': 'text',
      'size': 'fontSize',
    },
    example: {'text': '## Heading\nA paragraph.', 'autoWidth': false},
  ),
  BlockSchema(
    type: 'code',
    summary: 'A code cell with syntax highlighting. Never executed by the API.',
    keys: [
      ContentKey('source', 'string', 'The code.', required: true),
      ContentKey('language', 'string',
          'A language id or alias from codeLanguages (default "text").'),
      ContentKey('output', 'map', 'Last run output — written by the app.'),
      ContentKey('ranAt', 'number', 'When it last ran — written by the app.'),
    ],
    mistakes: {
      'code': 'source',
      'text': 'source',
      'content': 'source',
      'body': 'source',
      'lang': 'language',
    },
    example: {'source': 'print("hi")', 'language': 'python'},
  ),
  BlockSchema(
    type: 'math',
    summary: 'A display equation.',
    keys: [
      ContentKey('latex', 'string', 'The equation as LaTeX.', required: true),
      ContentKey('linearSource', 'string',
          'The same equation as typed linear input, if any.'),
      ContentKey('display', 'bool', 'Display (centred) style.'),
    ],
    mistakes: {
      'tex': 'latex',
      'equation': 'latex',
      'formula': 'latex',
      'text': 'latex',
    },
    example: {'latex': r'E = mc^2'},
  ),
  BlockSchema(
    type: 'table',
    summary: 'A table as a block of its own. Prefer an inline table atom in a '
        'text block (see text.atoms): the app converts table blocks to that '
        'form, and this API does it for you on write.',
    keys: [
      ContentKey('cells', 'list', 'Rows of cell strings, header row first.',
          required: true),
      ContentKey('colWidths', 'list',
          'Widths somebody chose, per column, in px; 0 = auto. Used exactly.'),
      ContentKey('impliedColWidths', 'list',
          'Starting widths nobody chose (written by conversion); a column '
              'grows past them.'),
    ],
    mistakes: {'rows': 'cells', 'data': 'cells', 'table': 'cells'},
    example: {
      'cells': [
        ['Term', 'Meaning'],
        ['ATP', 'energy currency'],
      ]
    },
  ),
  BlockSchema(
    type: 'flashcard',
    summary: 'A study card. (For many cards, create_flashcards is simpler.)',
    keys: [
      ContentKey('front', 'string', 'The question side.', required: true),
      ContentKey('back', 'string', 'The answer side.', required: true),
    ],
    mistakes: {'question': 'front', 'answer': 'back', 'q': 'front', 'a': 'back'},
    example: {'front': 'What is osmosis?', 'back': 'Diffusion of water'},
  ),
  BlockSchema(
    type: 'board',
    summary: 'A task board: columns of cards.',
    keys: [
      ContentKey('columns', 'list',
          'Each column is {title, cards: [string, …]}.',
          required: true),
    ],
    mistakes: {'lists': 'columns', 'lanes': 'columns'},
    example: {
      'columns': [
        {
          'title': 'To do',
          'cards': ['write notes']
        },
        {'title': 'Done', 'cards': <String>[]},
      ]
    },
  ),
  BlockSchema(
    type: 'graph',
    summary: 'A plotted curve.',
    keys: [
      ContentKey('latex', 'string', 'The equation to plot, e.g. y = x^2.',
          required: true),
      ContentKey('view', 'map', 'The visible window.'),
      ContentKey('fitY', 'bool', 'Fit the y range to the curve.'),
    ],
    mistakes: {'equation': 'latex', 'function': 'latex', 'tex': 'latex'},
    example: {'latex': 'y = x^2'},
  ),
  BlockSchema(
    type: 'substitute',
    summary: 'An equation with values plugged in, and the result.',
    keys: [
      ContentKey('latex', 'string', 'The equation.', required: true),
      ContentKey('values', 'map',
          'What is plugged in, keyed by variable name: {"x": "3"}.'),
      ContentKey('value', 'string',
          'Pre-v1.0.2 spelling: one value, no name. Write values instead; '
              'with exactly one variable, write the same number here too so '
              'older releases still show it.'),
    ],
    mistakes: {'equation': 'latex', 'vars': 'values', 'variables': 'values'},
    example: {
      'latex': 'y = 2x + 1',
      'values': {'x': '3'},
      'value': '3'
    },
  ),
  BlockSchema(
    type: 'image',
    summary: 'A picture, or one page of a stored PDF. Needs a blob already in '
        'the notebook — the API cannot upload bytes yet, so only round-trip '
        'images read_page returned. Size is the block envelope w/h.',
    keys: [
      ContentKey('blob', 'string', 'sha256:<hash> of the stored picture.'),
      ContentKey('pdf', 'string', 'sha256:<hash> of a stored PDF, instead.'),
      ContentKey('page', 'number', 'Which page of pdf (0-based).'),
      ContentKey('mime', 'string', 'Media type of the stored bytes.'),
      ContentKey('naturalW', 'number', 'Width of the source itself.'),
      ContentKey('naturalH', 'number', 'Height of the source itself.'),
      ContentKey('locked', 'bool', 'Not movable by hand (PDF pages).'),
      ContentKey('background', 'bool', 'Drawn under everything else.'),
    ],
    oneOf: ['blob', 'pdf'],
  ),
];

final Map<String, BlockSchema> _byType = {
  for (final s in blockSchemas) s.type: s
};

BlockSchema? blockSchemaFor(String type) => _byType[type];

/// What is wrong with [b]'s content, by [blockSchemas].
///
/// `errors` make the block useless as written (a required key missing or of
/// the wrong kind) and the caller should refuse it; `warnings` are worth
/// telling the writer but not worth refusing. A type with no schema returns
/// neither.
({List<String> errors, List<String> warnings}) checkBlockContent(Block b) {
  final type = b.rawType ?? b.type.name;
  final schema = _byType[type];
  final errors = <String>[], warnings = <String>[];
  if (schema == null) return (errors: errors, warnings: warnings);
  final c = b.content;
  final known = {for (final k in schema.keys) k.name: k};

  for (final k in schema.keys) {
    final v = c[k.name];
    if (v == null) {
      if (!k.required) continue;
      final wrong = [
        for (final e in schema.mistakes.entries)
          if (e.value == k.name && c.containsKey(e.key)) e.key
      ];
      errors.add(wrong.isEmpty
          ? '$type blocks need content.${k.name} (${k.description})'
          : '$type blocks keep this in content.${k.name}, not '
              'content.${wrong.first} — rename the key');
      continue;
    }
    if (!_isKind(v, k.kind)) {
      final msg = 'content.${k.name} must be a ${k.kind}, got '
          '${_kindOf(v)}';
      (k.required ? errors : warnings).add(msg);
    }
  }
  if (schema.oneOf.isNotEmpty && !schema.oneOf.any((k) => c[k] != null)) {
    errors.add('$type blocks need one of '
        '${schema.oneOf.map((k) => 'content.$k').join(' or ')}');
  }
  for (final key in c.keys) {
    if (known.containsKey(key) || key == 'madeIn') continue;
    final right = schema.mistakes[key];
    warnings.add(right != null
        ? 'content.$key is not read by $type blocks — did you mean '
            'content.$right?'
        : 'content.$key is not a documented $type key; kept as given');
  }
  if (type == 'text') _checkAtoms(c, errors, warnings);
  return (errors: errors, warnings: warnings);
}

void _checkAtoms(
    Map<String, dynamic> c, List<String> errors, List<String> warnings) {
  final text = c['text'];
  if (text is! String) return;
  final held = InlineAtom.allIn(c);
  final raw = c['atoms'];
  if (raw is Map && raw.length != held.length) {
    errors.add('content.atoms entries must each be {id, type, content} with '
        'the id matching its key');
  }
  final referenced = InlineAtom.idsIn(text);
  for (final id in referenced) {
    if (!held.containsKey(id)) {
      errors.add('text references onote://atom/$id but content.atoms has no '
          'entry for it');
    }
  }
  for (final e in held.entries) {
    if (!referenced.contains(e.key)) {
      warnings.add('atom ${e.key} is never referenced from text, so it will '
          'not show — add ![${TableData.referenceAlt}]'
          '(onote://atom/${e.key}) on its own line');
    }
    final a = e.value;
    if (a.type == 'table' && a.content['cells'] is! List) {
      errors.add('table atom ${e.key} needs content.cells, a list of rows');
    }
  }
}

bool _isKind(Object v, String kind) => switch (kind) {
      'string' => v is String,
      'number' => v is num,
      'bool' => v is bool,
      'list' => v is List,
      'map' => v is Map,
      _ => true,
    };

String _kindOf(Object v) => switch (v) {
      String() => 'a string',
      num() => 'a number',
      bool() => 'a bool',
      List() => 'a list',
      Map() => 'an object',
      _ => v.runtimeType.toString(),
    };
