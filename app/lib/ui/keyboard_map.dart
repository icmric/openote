/// THE keyboard map — docs/planning/v0.16-keyboard-control.md §1.
///
/// Every shortcut in the app, as data. Two consumers keep it honest: the
/// Ctrl+/ reference overlay renders this table (so the documentation cannot
/// drift from what's listed), and keyboard_map_test.dart pins the table's
/// invariants and its canonical rows. The rule for future work: a PR that
/// adds an interactive surface adds its rows here, or it isn't done. A
/// binding that exists in code but not here is a bug — file it like one.
library;

/// One binding: the keys as the user reads them, and what they do.
class KeyBinding {
  const KeyBinding(this.keys, this.action);

  /// Display form, e.g. `Ctrl+Shift+N`. Alternatives joined with ` / `.
  final String keys;

  /// What happens, in the user's language — verb first, no jargon.
  final String action;
}

/// A group of bindings that share a context (where the keys work).
class KeySection {
  const KeySection(this.title, this.bindings);
  final String title;
  final List<KeyBinding> bindings;
}

/// The whole map, in the order the overlay shows it: the always-available
/// chords first, then per-surface groups roughly by how often they're used.
const List<KeySection> keyboardMap = [
  KeySection('Anywhere', [
    KeyBinding('Ctrl+/', 'This list'),
    KeyBinding('Ctrl+PgDn / Ctrl+PgUp', 'Next / previous page'),
    KeyBinding('Ctrl+Tab / Ctrl+Shift+Tab', 'Next / previous section'),
    KeyBinding('Ctrl+N', 'New page after this one'),
    KeyBinding('Ctrl+Shift+N', 'New sub-page of this one'),
    KeyBinding('Ctrl+\\', 'Hide or show the sidebar'),
    KeyBinding('Esc',
        'One step back per press: close find, stop editing, clear selection'),
  ]),
  KeySection('While writing', [
    KeyBinding('Ctrl+B / Ctrl+I / Ctrl+U', 'Bold / italic / underline'),
    KeyBinding('Ctrl+Shift+C',
        'Colour the selection (last used colour; again to remove)'),
    KeyBinding('Ctrl+1 … Ctrl+5',
        'Tag the line: to-do, important, question, remember, definition'),
    KeyBinding('Ctrl+V',
        'Paste — a copied image lands on the page as a picture'),
    KeyBinding('Alt+X', 'Character ↔ its U+ code, either direction'),
    KeyBinding('( " * … with text selected',
        'Wraps the selection instead of replacing it'),
  ]),
  KeySection('On the page (nothing focused)', [
    KeyBinding('V / T / P / H / E',
        'Tool: Select, Text, Pen, Highlighter, Eraser'),
    KeyBinding('Ctrl+C / Ctrl+X / Ctrl+V', 'Copy / cut / paste blocks'),
    KeyBinding('Ctrl+D', 'Duplicate the selected block'),
    KeyBinding('Del', 'Delete the selection'),
    KeyBinding('Ctrl+Z', 'Undo'),
    KeyBinding('Ctrl+Y / Ctrl+Shift+Z', 'Redo'),
    KeyBinding('Ctrl+F', 'Find on this page'),
    KeyBinding('Ctrl+P', 'Print the page'),
    KeyBinding('Ctrl+= / Ctrl+-', 'Zoom in / out'),
    KeyBinding('Ctrl+0', 'Reset zoom and scroll'),
  ]),
  KeySection('In a table', [
    KeyBinding('Tab / Shift+Tab', 'Next / previous cell'),
    KeyBinding('↑ ↓ ← →',
        'Move between cells (left/right from the text\'s edge)'),
    KeyBinding('Enter', 'The cell below — a new row from the last one'),
    KeyBinding('Ctrl+Enter', 'Line break inside the cell'),
  ]),
  KeySection('In a code cell', [
    KeyBinding('Ctrl+Enter', 'Run'),
    KeyBinding('Tab', 'Indent (two spaces)'),
  ]),
  KeySection('Studying flashcards', [
    KeyBinding('Space', 'Reveal the answer; again marks it Good'),
    KeyBinding('1 / 2 / 3 / 4', 'Grade: Again, Hard, Good, Easy'),
  ]),
];
