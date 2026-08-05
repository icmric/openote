// Importing OneNote's tags (P9 — the last importer gap).
//
// Unblocked by the property-walk fix: a paragraph's tag reference is an
// `ArrayOfPropertyValues`, and until its length was computed properly every
// property after it — including the paragraph's own text — was read from the
// wrong offset. With that fixed, the chain decodes: 0x3489 → 0x3488 → a tag
// definition carrying its label.
//
// These cover the Dart half: the label mapping, and that an unmapped tag
// survives rather than being dropped.

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/tags.dart';

void main() {
  group('OneNote label mapping', () {
    test('maps the built-ins a student actually uses', () {
      const cases = {
        'To Do': TagKind.todo,
        'Important': TagKind.important,
        'Question': TagKind.question,
        'Remember for later': TagKind.remember,
        'Definition': TagKind.definition,
        'Idea': TagKind.idea,
        'Critical': TagKind.critical,
        'Contact': TagKind.contact,
      };
      cases.forEach((label, kind) {
        expect(TagKind.fromOneNoteLabel(label), kind, reason: label);
      });
    });

    test('OneNote’s priority variants are still to-dos', () {
      expect(TagKind.fromOneNoteLabel('To Do priority 1'), TagKind.todo);
      expect(TagKind.fromOneNoteLabel('To Do priority 2'), TagKind.todo);
    });

    test('matching ignores case and surrounding space', () {
      expect(TagKind.fromOneNoteLabel('  question  '), TagKind.question);
      expect(TagKind.fromOneNoteLabel('IMPORTANT'), TagKind.important);
    });

    // The rule that matters for a switcher: an unrecognised tag must arrive.
    // A German notebook says "Aufgabe", and matching on the English label
    // cannot know that — but dropping it would lose the user's organising
    // information silently, which is the one outcome that is not allowed.
    test('an unknown label becomes a custom tag rather than vanishing', () {
      for (final label in ['Aufgabe', 'Project A', 'Send in email', 'Ω']) {
        expect(TagKind.fromOneNoteLabel(label), TagKind.custom, reason: label);
      }
    });
  });

  group('a tag written into a block', () {
    test('round-trips through the block envelope, keeping its custom name', () {
      final content = <String, dynamic>{'text': 'a\nb\nc'};
      NoteTag.writeInto(content, [
        NoteTag(kind: TagKind.question, line: 0),
        NoteTag(kind: TagKind.todo, line: 1, checked: false),
        NoteTag(kind: TagKind.custom, line: 2, label: 'Project A'),
      ]);

      final back = NoteTag.listFrom(content);
      expect(back.length, 3);
      expect(back[0].kind, TagKind.question);
      expect(back[0].line, 0);
      expect(back[1].kind, TagKind.todo);
      expect(back[1].checked, isFalse,
          reason: 'an imported to-do arrives unticked — OneNote’s '
              'completion flag is deliberately not guessed at');
      expect(back[2].kind, TagKind.custom);
      expect(back[2].label, 'Project A');
    });
  });
}
