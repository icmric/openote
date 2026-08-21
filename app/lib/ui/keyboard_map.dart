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
    KeyBinding('Alt+=',
        'Start a maths equation — with words selected, they become one '
        'right where they are, in the sentence'),
    KeyBinding('Alt+Shift+=',
        'The same, but as an equation on a line of its own'),
    KeyBinding(
        'F6 / Shift+F6',
        'Jump between the sidebar, the toolbar, the row of controls for what '
        'you are writing, the page, the open panel and a reminder that has '
        'popped up'),
    KeyBinding('Shift+F10  /  Menu key',
        'The menu of things you can add, where you are \u2014 or, with a box '
        'selected, that box\'s own menu'),
    KeyBinding(
        'Esc',
        'One step back per press: close find, stop editing, clear selection, '
        'dismiss a reminder'),
  ]),
  KeySection('While writing', [
    KeyBinding('Ctrl+B / Ctrl+I / Ctrl+U', 'Bold / italic / underline'),
    KeyBinding('Ctrl+*',
        'Put the word you are on in italics; press it again for bold, again '
        'for both, and a fourth press does nothing'),
    KeyBinding('Ctrl+` / Ctrl+~ / Ctrl+^ / Ctrl+_ / Ctrl+\$',
        'The same with the other Markdown characters: code / small below the '
        'line, then crossed out / small above it / italic then bold / maths'),
    KeyBinding('Ctrl+= / Ctrl+Shift+=',
        'Small text below the line / above it — H₂O, x²'),
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
    KeyBinding('Tab / Shift+Tab',
        'Select the next / previous box, in reading order'),
    KeyBinding('↑ ↓ ← →', 'Select the nearest box in that direction'),
    KeyBinding('Enter', 'Edit the selected box (Esc climbs back out)'),
    KeyBinding('Just start typing',
        'A letter on a selected text or code box starts writing at its end'),
    KeyBinding('Ctrl+↑↓←→',
        'Move the selected box (one grid step; add Shift for 1 px)'),
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
  KeySection('Writing an equation', [
    KeyBinding('Alt+=', 'Start one'),
    KeyBinding('Esc', 'Finish, and carry on with the sentence'),
    KeyBinding('Tab / Shift+Tab', 'The next / previous box left to fill'),
    KeyBinding('← →', 'Step through — INTO a fraction or a root, not over it'),
    KeyBinding('↑ ↓',
        'Between the halves: top and bottom of a fraction, a power and an '
        'index, rows of a matrix'),
    KeyBinding('A backslash, a name, then Space',
        r'Symbols by name: \alpha, \sqrt, \sum, \sin. WITHOUT the '
        r'backslash the letters stay letters, so ordinary words survive'),
    KeyBinding('/ then a number', 'A fraction — try 1/2, or (n+1)/2'),
    KeyBinding('<= >= != ->', 'Become ≤ ≥ ≠ → as you type them'),
    KeyBinding('Space',
        'A space — or finishes the backslash name in front of it'),
    KeyBinding('Backspace',
        'Steps INSIDE a fraction, root or grid rather than deleting it, so '
        'one press can never take the whole thing'),
    KeyBinding('Ctrl+= / Ctrl+Shift+=', 'A small index / a power'),
    KeyBinding('Ctrl+C / Ctrl+X / Ctrl+V',
        'Copy, cut or paste the equation — it goes on the clipboard as '
        'LaTeX, so it pastes into Word, Overleaf or a message'),
    KeyBinding('Enter', 'Another row of a piecewise or a matrix'),
    KeyBinding('&', 'Another column of a matrix'),
    KeyBinding('= then space',
        'Works out what you have written and puts the answer in'),
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
  KeySection('On a task board', [
    KeyBinding('Enter', 'Step into the board — then Enter again edits a card'),
    KeyBinding('↑ ↓ ← →', 'Move between cards and columns'),
    KeyBinding('Ctrl+↑↓←→',
        'Take the card with you — up or down the list, or to the next column'),
    KeyBinding('Enter on “Add a card”', 'Write a new card at the foot'),
    KeyBinding('Del', 'Remove the card you are on (Ctrl+Z brings it back)'),
    KeyBinding('Esc', 'Leave the board'),
  ]),
  KeySection('Studying flashcards', [
    KeyBinding('Space', 'Reveal the answer; again marks it Good'),
    KeyBinding('1 / 2 / 3 / 4', 'Grade: Again, Hard, Good, Easy'),
    KeyBinding('Ctrl+Enter', 'Save the card you are writing'),
  ]),
  KeySection('Reading a PDF', [
    KeyBinding('PgUp / PgDn / Space', 'Previous / next page'),
    KeyBinding('Home / End', 'First / last page'),
    KeyBinding('↑ ↓ ← →', 'Scroll around the page'),
    KeyBinding('Ctrl+= / Ctrl+-', 'Zoom in / out'),
    KeyBinding('Ctrl+A / Ctrl+C', 'Select all the text / copy it'),
    KeyBinding('Esc', 'Close the reader'),
  ]),
  KeySection('Finding text on the page', [
    KeyBinding('Ctrl+F', 'Open the find bar'),
    KeyBinding('Enter / Shift+Enter', 'Next / previous match'),
    KeyBinding('Esc', 'Close it'),
  ]),
];
