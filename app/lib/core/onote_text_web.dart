/// The browser half of [OnoteText]: there is no native library, so the answer
/// is always "absent", which every caller already handles.
library;

import 'onote_text.dart';

class OnoteText {
  OnoteText._();

  static bool get available => false;
  static String? get libraryPath => null;

  static Future<List<TextFinding>> check(
          String text, EnglishDialect dialect, int want) async =>
      const [];

  static Future<List<String>> suggest(String word, EnglishDialect dialect,
          {int max = 5}) async =>
      const [];

  static Future<String?> autocorrect(String word, EnglishDialect dialect) async =>
      null;
}
