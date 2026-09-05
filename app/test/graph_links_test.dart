// A notebook's own cross-references, pointed at the imported pages.
//
// PLANNING has asked for this since the importer existed, and a real notebook
// carries 142 `onenote:` links in sixty pages — a contents page is nothing but
// these, so leaving them all pointing back at OneNote makes the imported copy
// a shell that keeps sending the student somewhere else.
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/onenote/graph_client.dart';
import 'package:openote/onenote/graph_links.dart';

/// A link exactly as OneNote writes one, braces and upper case included.
const onenoteLink =
    r'[Formulas](onenote:Maths\Misc.one#Formulas&section-id={C72C868F-AFA6-4B32-8DBE-3E70E0902BAC}&page-id={C60353C1-082C-49F5-AEC1-CAB80682DEC6}&end&base-path=https://d.docs.live.net/x)';

void main() {
  group('finding the page id', () {
    test('the two spellings are the same GUID', () {
      // `links.oneNoteClientUrl` writes it bare and lower-case; an `<a href>`
      // inside a page writes it in braces and upper-case.
      const fromLinks = 'onenote:https://d.docs.live.net/x/Misc.one'
          '#&section-id=857cef1e-3b77-40b8-b189-22fa9df111f5'
          '&page-id=59ad797e-5ee9-4689-bbe2-299d8f09d963&end';
      const fromHref = r'onenote:Maths\Misc.one#Formulas'
          '&page-id={59AD797E-5EE9-4689-BBE2-299D8F09D963}&end';
      expect(oneNotePageIdIn(fromLinks), oneNotePageIdIn(fromHref));
      expect(oneNotePageIdIn(fromLinks),
          '59ad797e-5ee9-4689-bbe2-299d8f09d963');
    });

    test('a URL with no page id is nobody', () {
      expect(oneNotePageIdIn('onenote:Maths\Misc.one#&section-id=abc'),
          isNull);
    });
  });

  group('rewriting', () {
    test('a link to an imported page becomes a real page link', () {
      final out = relinkMarkdown(onenoteLink, {
        'c60353c1-082c-49f5-aec1-cab80682dec6': 'PAGE7',
      });
      expect(out, '[Formulas](onote://page/PAGE7)');
    });

    test('a link to a page that was NOT imported is left exactly alone', () {
      // The owner's instruction, and the better behaviour: the `onenote:`
      // scheme opens OneNote, so an unresolved link still goes where it was
      // meant to, whereas a rewritten-but-broken one goes nowhere.
      final out = relinkMarkdown(onenoteLink, {'some-other-guid': 'PAGE7'});
      expect(out, onenoteLink);
    });

    test('ordinary links are untouched', () {
      const md = '[a](https://example.com) and [b](onote://page/X)';
      expect(relinkMarkdown(md, {'x': 'Y'}), md);
    });

    test('several links on one line each resolve on their own', () {
      final md = '$onenoteLink and $onenoteLink';
      final out = relinkMarkdown(md, {
        'c60353c1-082c-49f5-aec1-cab80682dec6': 'P1',
      });
      expect('(onote://page/P1)'.allMatches(out).length, 2);
    });

    test('an empty map changes nothing and costs nothing', () {
      expect(relinkMarkdown(onenoteLink, const {}), onenoteLink);
    });

    test('the label survives, whatever it is', () {
      final md = onenoteLink.replaceFirst('[Formulas]', '[Week 3: **notes**]');
      final out = relinkMarkdown(md, {
        'c60353c1-082c-49f5-aec1-cab80682dec6': 'P1',
      });
      expect(out, '[Week 3: **notes**](onote://page/P1)');
    });

    test('text with no onenote link is recognised cheaply', () {
      expect(hasOneNoteLink('nothing here'), isFalse);
      expect(hasOneNoteLink(onenoteLink), isTrue);
    });
  });
}
