import 'package:flutter_test/flutter_test.dart';
import 'package:openote/spell/autocorrect_table.dart';

void main() {
  test('missing apostrophes', () {
    expect(autocorrectFor('dont'), "don't");
    expect(autocorrectFor('doesnt'), "doesn't");
    expect(autocorrectFor('cant'), "can't");
    expect(autocorrectFor('im'), "I'm");
    expect(autocorrectFor('ive'), "I've");
    expect(autocorrectFor('youre'), "you're");
    expect(autocorrectFor('thats'), "that's");
  });

  test('classic typos', () {
    expect(autocorrectFor('teh'), 'the');
    expect(autocorrectFor('recieve'), 'receive');
    expect(autocorrectFor('definately'), 'definitely');
    expect(autocorrectFor('seperate'), 'separate');
    expect(autocorrectFor('alot'), 'a lot');
    expect(autocorrectFor('realy'), 'really');
  });

  test('case follows the typed word', () {
    expect(autocorrectFor('Dont'), "Don't");
    expect(autocorrectFor('Teh'), 'The');
    expect(autocorrectFor('Im'), "I'm");
    expect(autocorrectFor('DONT'), isNull, reason: 'shouting or an acronym');
    expect(autocorrectFor('dOnt'), isNull);
  });

  test('words that are real words, or could be, are never touched', () {
    for (final w in [
      'its', 'lets', 'were', 'well', 'ill', 'id', 'hell', 'shell', 'whos?',
      'form', 'from', 'alto', 'inst', 'relay', 'docent', 'the', 'hello',
      // Spellings that differ between Englishes are not ours to pick.
      'colour', 'color', 'organise', 'organize',
    ]) {
      expect(autocorrectFor(w), isNull, reason: w);
    }
  });

  test('no entry corrects to itself or to something that needs correcting',
      () {
    // Every answer is a spelling this list would not change again, so one
    // keystroke can never start a chain.
    for (final w in [
      'dont', 'im', 'cant', 'teh', 'alot', 'realy', 'wendsday', 'thier'
    ]) {
      final r = autocorrectFor(w)!;
      expect(autocorrectFor(r), isNull, reason: '$w -> $r');
      expect(r, isNot(w));
    }
  });
}
