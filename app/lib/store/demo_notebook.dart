/// The notebook the browser demo opens with.
///
/// A visitor arriving at an empty page learns nothing: the canvas looks like a
/// blank rectangle and every feature worth seeing is behind a menu they have
/// no reason to open. So the demo starts with something already on the page,
/// chosen to answer "what is this, and what can it do" in the ten seconds
/// before somebody closes the tab.
///
/// **Content only, no new machinery.** Every block here is made with the same
/// `Block(type:…, content:…)` the editor itself makes, written through the
/// same `Repository.writePage`. If a shape in this file renders wrongly, the
/// app renders it wrongly — which is the point of showing the real editor
/// rather than a mock-up of one.
///
/// Flashcards and checklists are markdown inside a text block rather than
/// block types of their own, which is how the app makes them too
/// (`AppState.insertFlashcard` writes `?[Question](Answer)` into a text
/// block).
library;

import '../model/models.dart';
import 'repository.dart';

/// Create the demo notebook in [repo] and return it.
///
/// Called in place of the empty "My Notebook" that a fresh desktop workspace
/// gets. Deliberately not conditional on anything inside itself — the caller
/// decides, so this file stays readable as plain content.
Future<NotebookRef> seedDemoNotebook(Repository repo) async {
  final ref = await repo.createNotebook('Welcome to Openote');
  final id = ref.id;

  // `createNotebook` has already seeded "Section 1" and one page. Rename them
  // and add the rest rather than starting a second section beside them.
  final nodes = repo.loadNodes(id);
  final section = nodes.firstWhere((n) => n.kind == NodeKind.section);
  repo.upsertNode(id, section..title = 'Have a look round');

  final first = nodes.firstWhere((n) => n.kind == NodeKind.page);
  repo.upsertNode(id, first..title = 'Start here');
  _writeStartHere(repo, id, first.id);

  final maths = repo.upsertNode(
      id,
      TreeNode(
          kind: NodeKind.page,
          parentId: section.id,
          title: 'Maths',
          position: 'b0'));
  _writeMaths(repo, id, maths.id);

  final revision = repo.upsertNode(
      id,
      TreeNode(
          kind: NodeKind.page,
          parentId: section.id,
          title: 'Revision',
          position: 'c0'));
  _writeRevision(repo, id, revision.id);

  return ref;
}

/// A text block. Width is given rather than measured because nothing has been
/// laid out yet — there is no frame in which to ask how wide the words are.
/// A text block of a stated width.
///
/// `autoWidth: false` matters here and is not boilerplate. A text box
/// normally measures its own words and widens to fit — fine when you are
/// typing into it, wrong for a page laid out in advance, where two boxes side
/// by side would grow into each other. `AppState.insertFlashcard` sets the
/// same flag for the same reason.
Block _text(String body,
        {required double x, required double y, double w = 420}) =>
    Block(
        type: BlockType.text,
        x: x,
        y: y,
        w: w,
        content: {'text': body, 'autoWidth': false});

void _writeStartHere(Repository repo, String notebookId, String pageId) {
  repo.writePage(notebookId, pageId, [
    _text(
      '# Openote\n'
      'A notebook that keeps your notes in **files you own** — on your disk, '
      'in a format you can read, synced through a folder you already have.\n\n'
      'This is the demo. Have a poke around; nothing here is saved.',
      x: 80,
      y: 80,
      w: 460,
    ),
    _text(
      '## The page is a canvas\n'
      'Click anywhere and start typing — a box appears where you clicked. '
      'Drag one by the bar along its top. Nothing is locked to a line.\n\n'
      '- [ ] Click an empty patch and type something\n'
      '- [ ] Drag this box somewhere else\n'
      '- [ ] Try the Draw tab and scribble\n',
      x: 80,
      y: 280,
      w: 420,
    ),
    _text(
      '## It does maths properly\n'
      'Not a picture of an equation — one you can type into, solve and plot. '
      'The Maths page has more.',
      x: 570,
      y: 280,
      w: 360,
    ),
    Block(
      type: BlockType.math,
      x: 570,
      y: 400,
      w: 330,
      content: {'latex': r'\frac{-b \pm \sqrt{b^2-4ac}}{2a}', 'display': true},
    ),
    _text(
      '## Tables, without leaving the page',
      x: 80,
      y: 500,
      w: 420,
    ),
    Block(
      type: BlockType.table,
      x: 80,
      y: 560,
      w: 430,
      content: {
        'cells': [
          ['Planet', 'Day (hours)', 'Moons'],
          ['Mercury', '1408', '0'],
          ['Earth', '24', '1'],
          ['Jupiter', '10', '95'],
        ],
        'colWidths': [150.0, 150.0, 130.0],
      },
    ),
  ], PageProps(background: 'grid'));
}

void _writeMaths(Repository repo, String notebookId, String pageId) {
  repo.writePage(notebookId, pageId, [
    _text(
      '# Maths\n'
      'Type `/` or use the Insert tab to add an equation. Inside one, '
      r'`\frac`, `\sqrt`, `\sum` and friends turn into the real thing as you '
      'type, and so do shortcuts like `\\pi` and `\\infty`.',
      x: 80,
      y: 80,
      w: 460,
    ),
    Block(
      type: BlockType.math,
      x: 80,
      y: 230,
      w: 380,
      content: {
        'latex': r'\int_{0}^{\pi} \sin(x)\,dx = 2',
        'display': true,
      },
    ),
    Block(
      type: BlockType.math,
      x: 80,
      y: 330,
      w: 380,
      content: {
        'latex': r'\sum_{n=1}^{\infty} \frac{1}{n^2} = \frac{\pi^2}{6}',
        'display': true,
      },
    ),
    _text(
      '## Plot it\n'
      'Any equation can become a curve. This one came from `y = x^2 - 3`.',
      x: 540,
      y: 230,
      w: 360,
    ),
    Block(
      type: BlockType.graph,
      x: 540,
      y: 330,
      w: 360,
      h: 260,
      content: {'latex': 'x^2 - 3', 'fitY': true},
    ),
    _text(
      '## Or put a number in it\n'
      'The solver takes an equation and a value and shows the answer. '
      'Click the box and type a number for `r`.',
      x: 80,
      y: 450,
      w: 380,
    ),
    Block(
      type: BlockType.substitute,
      x: 80,
      y: 580,
      w: 300,
      content: {'latex': r'\pi r^2', 'value': '3'},
    ),
  ], PageProps(background: 'grid'));
}

void _writeRevision(Repository repo, String notebookId, String pageId) {
  repo.writePage(notebookId, pageId, [
    _text(
      '# Revision\n'
      'Write `?[question](answer)` on a line and it becomes a card you can '
      'turn over. They are ordinary text in the file, so nothing is trapped '
      'in a format only this app can read.',
      x: 80,
      y: 80,
      w: 460,
    ),
    _text(
      '?[What keeps a satellite in orbit?](Gravity — it is falling, and '
      'missing the Earth.)\n',
      x: 80,
      y: 240,
      w: 460,
    ),
    _text(
      '?[Mitochondria do what?](Release energy from glucose — respiration.)\n',
      x: 80,
      y: 400,
      w: 460,
    ),
    _text(
      '## Everything else\n'
      'Pictures, PDFs, video, audio, code blocks, task boards, handwriting '
      'with a pen.\n\n'
      'Some of those are greyed out here — a browser tab cannot reach your '
      'files or run a video engine. They all work in the app.',
      x: 600,
      y: 240,
      w: 340,
    ),
  ], PageProps(background: 'blank'));
}
