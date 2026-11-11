/// Which English the person writes — or that they are not writing English.
///
/// The checker (`rust/onote_text`) knows English only, so the whole question
/// reduces to: *is this English, and which?* Everything that checks, corrects or
/// capitalises asks this first, and does nothing when the answer is null. That
/// is how "none of it touches other languages" is kept: there is one gate, not
/// a check scattered through each feature.
///
/// The language is never guessed from the text. A note that mixes two languages
/// is a known limit; a per-section language is the later answer.
library;

import 'dart:ui' show Locale;

import '../core/onote_text.dart';

/// The values stored in the `spellLanguage` setting.
///
/// `system` is the default and follows the computer. `other` means "I write in
/// a language Openote cannot check yet", so nothing is checked or changed.
const List<String> kSpellLanguages = [
  'system',
  'en-AU',
  'en-GB',
  'en-US',
  'en-CA',
  'en-IN',
  'other',
];

/// The dialect for a setting value on a computer set to [system], or null when
/// the person is not writing English (so nothing should run).
EnglishDialect? resolveWritingDialect(String setting, Locale system) {
  switch (setting) {
    case 'en-AU':
      return EnglishDialect.australian;
    case 'en-GB':
      return EnglishDialect.british;
    case 'en-US':
      return EnglishDialect.american;
    case 'en-CA':
      return EnglishDialect.canadian;
    case 'en-IN':
      return EnglishDialect.indian;
    case 'other':
      return null;
    default:
      return dialectOfLocale(system);
  }
}

/// What the computer's own language and region say.
///
/// Harper has five Englishes. The regions that write the way Britain does but
/// have no entry of their own (Ireland, New Zealand, South Africa) take British,
/// the closest; every other English takes American, which is also what a bare
/// `en` means.
EnglishDialect? dialectOfLocale(Locale l) {
  if (l.languageCode != 'en') return null;
  switch (l.countryCode) {
    case 'AU':
      return EnglishDialect.australian;
    case 'GB':
    case 'IE':
    case 'NZ':
    case 'ZA':
      return EnglishDialect.british;
    case 'CA':
      return EnglishDialect.canadian;
    case 'IN':
      return EnglishDialect.indian;
    default:
      return EnglishDialect.american;
  }
}
