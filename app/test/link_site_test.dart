// **Where a link may go, and — mostly — where it may not.**
//
// The requirement, in the owner's words: *"ensure it can handle if the user is
// inserting inside a table, if they have selected an image (alone or in
// addition to text), inside a maths equation, etc. They dont nesesarily all
// have to be capable of handling links … but you MUST confirm that it will not
// corrupt anything or cause issues no matter where a user attempts to insert a
// link."*
//
// So most of this file is refusals, and that is the point. Splicing `[…](…)`
// into a paragraph is writing into somebody's note, and there are places in
// this format where a stray bracket costs more than a missing feature:
//
//  * A table's `![2x3 table](onote://atom/…)` and a picture's
//    `![](sha256:…)` are POINTERS. A bracket spliced into either stops it
//    matching, which strands the payload and spills forty characters of URL
//    into the sentence. Unrecoverable by the person it happened to.
//  * An equation's `[` and `]` are LaTeX, not a link.
//  * Neither renderer re-scans the inside of an inline run, so a link placed
//    inside bold would be correct Markdown that this editor draws as its own
//    source — a link that silently does not work, discovered later, in a note
//    somebody was relying on.
//
// The last test is the one that matters most: whatever this produces, the
// grammar has to read back as a link. Anything else is a note that has been
// quietly rewritten.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/live_markdown_controller.dart';
import 'package:openote/markdown/md_syntax.dart';
import 'package:openote/model/inline_atom.dart';

void main() {
  TextSelection at(int o) => TextSelection.collapsed(offset: o);
  TextSelection range(int a, int b) =>
      TextSelection(baseOffset: a, extentOffset: b);

  group('what the link attaches to', () {
    test('a selection, exactly as highlighted', () {
      final s = linkSiteAt('see the docs now', range(4, 12));
      expect(s.ok, isTrue);
      expect(s.label, 'the docs');
      expect(s.start, 4);
      expect(s.end, 12);
    });

    test('the word the caret is pressed against, from the right', () {
      final s = linkSiteAt('see docs now', at(8)); // just after "docs"
      expect(s.label, 'docs');
      expect(s.start, 4);
      expect(s.end, 8);
    });

    test('and from the left', () {
      final s = linkSiteAt('see docs now', at(4)); // just before "docs"
      expect(s.label, 'docs');
    });

    test('and from inside it', () {
      final s = linkSiteAt('see docs now', at(6));
      expect(s.label, 'docs');
    });

    test('but NOT across a gap — a space means there is nothing to label', () {
      // The owner's rule: *"if there is a space between the cursor and word
      // DONT fill it on there"*.
      final s = linkSiteAt('see  docs', at(4)); // between the two spaces
      expect(s.ok, isTrue);
      expect(s.label, isEmpty, reason: 'the dialog asks for display text');
      expect(s.start, 4);
      expect(s.end, 4);
    });

    test('an empty line gives an empty label rather than a refusal', () {
      final s = linkSiteAt('', at(0));
      expect(s.ok, isTrue);
      expect(s.label, isEmpty);
    });

    test('sentence punctuation belongs to the writer, not the address', () {
      final s = linkSiteAt('read docs.', at(10));
      expect(s.label, 'docs', reason: 'the full stop is the sentence, not the link');
      expect(s.end, 9);
    });

    test('a word at the very start and very end of the buffer', () {
      expect(linkSiteAt('docs', at(0)).label, 'docs');
      expect(linkSiteAt('docs', at(4)).label, 'docs');
    });
  });

  group('an existing link is edited, not nested', () {
    const text = 'see [the docs](https://x.test/a) now';

    test('the caret inside one finds the whole link and its address', () {
      final s = linkSiteAt(text, at(8));
      expect(s.ok, isTrue);
      expect(s.isEdit, isTrue);
      expect(s.label, 'the docs');
      expect(s.url, 'https://x.test/a');
      expect(s.start, 4);
      expect(s.end, text.indexOf(' now'));
    });

    test('so does a selection of just its words', () {
      final s = linkSiteAt(text, range(5, 13));
      expect(s.isEdit, isTrue, reason: 'inside the link, so it is that link');
      expect(s.url, 'https://x.test/a');
    });

    test('a wiki link is edited the same way', () {
      final s = linkSiteAt('see [[Chemistry|p7]] now', at(8));
      expect(s.isEdit, isTrue);
      expect(s.label, 'Chemistry');
      expect(s.url, 'p7');
    });

    test('but a selection only HALF covering one is refused', () {
      // Replacing half a link would leave the other half as literal brackets.
      final s = linkSiteAt(text, range(1, 8));
      expect(s.ok, isFalse);
      expect(s.blocked, LinkBlocked.nested);
    });
  });

  group('the refusals, which are the point', () {
    test('a selection that crosses a line', () {
      final s = linkSiteAt('one\ntwo', range(1, 6));
      expect(s.blocked, LinkBlocked.lines,
          reason: 'the grammar is scanned per line; it could never be drawn');
    });

    test('a picture in the sentence', () {
      final s = linkSiteAt('notes\n![](sha256:abc)\nmore', at(8));
      expect(s.blocked, LinkBlocked.object);
    });

    test('a flashcard line', () {
      final s = linkSiteAt('?[front](back)', at(3));
      expect(s.blocked, LinkBlocked.object);
    });

    test("a TABLE's reference — the pointer that must not be touched", () {
      const atom = InlineAtom(id: 't1', type: 'table', content: {
        'cells': [
          ['a', 'b']
        ]
      });
      final ref = atom.reference(TableData.referenceAlt);
      final text = 'before $ref after';
      // Selected on its own…
      expect(linkSiteAt(text, range(7, 7 + ref.length)).blocked,
          LinkBlocked.object);
      // …and selected together with the words beside it, which is the case
      // the owner asked about by name.
      expect(linkSiteAt(text, range(0, text.length)).blocked,
          LinkBlocked.object);
      // …and with the caret sitting inside it.
      expect(linkSiteAt(text, range(9, 12)).blocked, LinkBlocked.object);
    });

    test('inside an equation, where the brackets are LaTeX', () {
      final s = linkSiteAt(r'the value $\frac{1}{2}$ is', range(11, 16));
      expect(s.blocked, LinkBlocked.maths);
    });

    test('inside bold, which neither renderer would re-scan', () {
      final s = linkSiteAt('a **bold word** here', range(5, 9));
      expect(s.blocked, LinkBlocked.nested);
    });

    test('inside code, for the same reason', () {
      final s = linkSiteAt('run `the thing` now', range(6, 9));
      expect(s.blocked, LinkBlocked.nested);
    });

    test('over a bare URL, which is already a link', () {
      final s = linkSiteAt('see https://x.test now', range(4, 18));
      expect(s.blocked, LinkBlocked.nested);
    });

    test('words carrying a bracket the label cannot hold', () {
      final s = linkSiteAt('see [this] now', range(4, 10));
      expect(s.blocked, LinkBlocked.bracket);
    });

    test('and no caret at all', () {
      expect(linkSiteAt('anything', const TextSelection.collapsed(offset: -1))
          .blocked, LinkBlocked.noCaret);
    });
  });

  group('the address is written so the grammar can read it back', () {
    test('a bracket or a space in a URL is encoded, not refused', () {
      // Both are legal in a real address — Wikipedia is full of the first —
      // and `_link` reads `[^)\s]+`, so either would end the match early and
      // leave the tail of somebody's URL in their sentence as text.
      expect(encodeLinkTarget('https://x.test/a_(b)'),
          'https://x.test/a_%28b%29');
      expect(encodeLinkTarget('https://x.test/a b'), 'https://x.test/a%20b');
    });

    test('an existing percent sign is encoded first, so it round-trips', () {
      expect(encodeLinkTarget('https://x.test/100%'), 'https://x.test/100%25');
    });

    test('and nothing else is rewritten', () {
      const url = 'https://x.test/a/b?c=d&e=f#g';
      expect(encodeLinkTarget(url), url);
    });
  });

  group('what it writes really is a link', () {
    /// The whole safety story in one check: hand the output back to the
    /// grammar and insist it reads as a link covering exactly what was written.
    void readsBackAsALink(String text, String label) {
      final line = text.split('\n').first;
      final hit = mdInlineRe.allMatches(line).map(classifyInline).where((c) =>
          c.kind == MdInline.extLink || c.kind == MdInline.wikiLink);
      expect(hit, hasLength(1), reason: 'exactly one link in «$line»');
      expect(hit.first.label, label);
    }

    test('wrapping a selection', () {
      final site = linkSiteAt('see the docs now', range(4, 12));
      final out = applyLink('see the docs now', site,
          label: site.label, url: 'https://x.test');
      expect(out.text, 'see [the docs](https://x.test) now');
      readsBackAsALink(out.text, 'the docs');
      expect(out.selection.baseOffset, out.text.indexOf(' now'));
    });

    test('wrapping a word the caret abutted', () {
      const before = 'see docs now';
      final site = linkSiteAt(before, at(8));
      final out =
          applyLink(before, site, label: site.label, url: 'https://x.test');
      readsBackAsALink(out.text, 'docs');
    });

    test('inserting display text where there was none', () {
      const before = 'see  now';
      final site = linkSiteAt(before, at(4));
      final out =
          applyLink(before, site, label: 'the docs', url: 'https://x.test');
      readsBackAsALink(out.text, 'the docs');
    });

    test('a URL needing encoding still reads back whole', () {
      final site = linkSiteAt('docs', at(4));
      final out = applyLink('docs', site,
          label: 'docs', url: 'https://x.test/a (b)');
      readsBackAsALink(out.text, 'docs');
      expect(out.text, contains('%28b%29'),
          reason: 'the tail of the address is inside the link, not beside it');
    });

    test('editing one replaces it whole, leaving exactly one link', () {
      const before = 'see [the docs](https://old.test) now';
      final site = linkSiteAt(before, at(8));
      final out = applyLink(before, site,
          label: 'the docs', url: 'https://new.test');
      expect(out.text, 'see [the docs](https://new.test) now');
      readsBackAsALink(out.text, 'the docs');
    });

    test('and the result is findable as an edit, so Ctrl+K is repeatable', () {
      final site = linkSiteAt('see docs now', at(8));
      final out =
          applyLink('see docs now', site, label: 'docs', url: 'https://x.test');
      final again = linkSiteAt(out.text, at(site.start + 2));
      expect(again.isEdit, isTrue);
      expect(again.url, 'https://x.test');
    });

    test('removing one leaves the words and nothing else', () {
      const before = 'see [the docs](https://x.test) now';
      final site = linkSiteAt(before, at(8));
      final out = removeLink(before, site);
      expect(out.text, 'see the docs now');
      expect(mdInlineRe.allMatches(out.text).map(classifyInline).where((c) =>
          c.kind == MdInline.extLink), isEmpty);
    });
  });
}
