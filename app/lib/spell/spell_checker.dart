/// Spell checking (TEXT-11) — a pure-Dart wordlist checker.
///
/// **Why not the platform, as the PRD's wording suggests?** Because on desktop
/// there is no platform to ask. Flutter's `DefaultSpellCheckService` is
/// documented and implemented for Android and iOS only, and `EditableText`
/// disables spell check on desktop unless a custom service is supplied.
///
/// **Why not Flutter's `spellCheckConfiguration` even with a custom service?**
/// Because when spell results exist, `EditableText` builds its span tree via
/// `buildTextSpanWithSpellCheckSuggestions` *instead of* the controller's
/// `buildTextSpan` — which would throw away every bit of live-Markdown
/// styling. So misspellings are merged inside our own controller, and this
/// class only answers "which ranges are wrong".
library;

import 'dart:convert';
import 'dart:io' show gzip;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show TextRange;

/// Where the bundled list lives. English only for now — a deliberate v0.2
/// scope cut, with the upgrade path (hunspell dictionaries via the Rust core)
/// recorded in the release plan rather than half-built here.
/// **Gzipped in the bundle**, and inflated on the isolate that already parses
/// it. The wordlist is 1.7 MB of plain text and compresses to 443 KB — a 1.3 MB
/// saving on every install, for a decompression the user never waits for
/// because this whole path is already off the UI thread.
///
/// It also fixes a smaller waste: `rootBundle.loadString` caches the decoded
/// string forever in `CachingAssetBundle._stringCache`, so the 1.7 MB sat in
/// memory for the life of the process ON TOP of the parsed dictionary. Loading
/// bytes and inflating them skips that cache entirely.
const String kDictionaryAsset = 'assets/dict/en_us.txt.gz';

/// Words the user taught us ("Add to dictionary").
///
/// Workspace-scoped and persisted (see [loadLearnedWords] / [onLearnedChanged]).
/// Deliberately NOT synced: a personal dictionary is about the words *this
/// person* uses, and pushing it through the op log would make one device's
/// jargon everyone's — including on a shared group notebook.
final Set<String> learnedWords = <String>{};

/// Called whenever [learnedWords] changes, so the host can persist it. Set once
/// at startup; null in tests.
void Function(List<String> words)? onLearnedChanged;

/// Teach the checker a word and persist it.
void learnWord(String word) {
  final w = word.trim().toLowerCase();
  if (w.isEmpty || !learnedWords.add(w)) return;
  onLearnedChanged?.call(learnedWords.toList()..sort());
}

/// Restore the persisted set at startup.
void loadLearnedWords(Iterable<String> words) {
  for (final w in words) {
    final t = w.trim().toLowerCase();
    if (t.isNotEmpty) learnedWords.add(t);
  }
}

/// A loaded, queryable dictionary.
class SpellDictionary {
  SpellDictionary(this._sorted);

  /// Lowercased and sorted, queried by binary search. A `Set` would be faster
  /// per lookup but costs several times the memory for 170k strings, and a
  /// block's worth of text is only a few hundred lookups.
  final List<String> _sorted;

  int get length => _sorted.length;

  /// Build from raw newline-separated text. Public so tests can inject a tiny
  /// list instead of loading the 1.7 MB asset.
  factory SpellDictionary.fromLines(Iterable<String> lines) {
    final words = <String>[];
    for (final l in lines) {
      final w = l.trim().toLowerCase();
      if (w.isNotEmpty) words.add(w);
    }
    words.sort();
    return SpellDictionary(words);
  }

  bool contains(String lowercase) {
    var lo = 0, hi = _sorted.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final c = _sorted[mid].compareTo(lowercase);
      if (c == 0) return true;
      if (c < 0) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return false;
  }
}

/// Loads the dictionary once, off the UI isolate, and answers spelling
/// queries over the app's Markdown text.
class SpellChecker {
  SpellChecker(this.dictionary);

  final SpellDictionary dictionary;

  static SpellChecker? _instance;
  static Future<SpellChecker>? _loading;

  /// The shared checker, loading the bundled asset on first use.
  ///
  /// Lazy on purpose: 170k words cost ~150 ms to parse and a few MB resident,
  /// which is fine the first time someone edits text and wasteful at startup
  /// for a session that only draws.
  static Future<SpellChecker> instance() {
    if (_instance != null) return Future.value(_instance);
    return _loading ??= _load();
  }

  /// The checker if it is already loaded, else null — for synchronous paths
  /// that must not wait (a build method).
  static SpellChecker? get loaded => _instance;

  static Future<SpellChecker> _load() async {
    final raw = await rootBundle.load(kDictionaryAsset);
    // Inflate AND parse on the background isolate, in one hop. Doing the
    // inflate here would put 1.7 MB of decompression on the UI thread for no
    // reason, and would then have to ship the result across the isolate
    // boundary anyway.
    final dict = await compute(_parse, raw.buffer.asUint8List());
    final checker = SpellChecker(dict);
    _instance = checker;
    return checker;
  }

  static SpellDictionary _parse(Uint8List gzipped) => SpellDictionary.fromLines(
      const LineSplitter().convert(utf8.decode(gzip.decode(gzipped))));

  /// Inject a dictionary (tests, and a future language switch).
  @visibleForTesting
  static void installForTest(SpellChecker? c) {
    _instance = c;
    _loading = null;
  }

  bool isWordSpelled(String word) {
    final lower = word.toLowerCase();
    return dictionary.contains(lower) ||
        learnedWords.contains(lower) ||
        // An ALL-CAPS token is usually an acronym, and flagging every one of
        // them makes technical notes unusable.
        (word.length > 1 && word == word.toUpperCase());
  }

  /// The misspelled word range containing [offset], or null.
  ///
  /// Used by the right-click menu: a suggestion list is only useful if we can
  /// find which word was clicked, and the caret lands *inside* the word rather
  /// than on its boundary.
  TextRange? misspelledAt(String text, int offset) {
    for (final r in check(text)) {
      if (offset >= r.start && offset <= r.end) return r;
    }
    return null;
  }

  /// Misspelled ranges in [text], as offsets into the RAW string.
  ///
  /// Raw offsets matter: the live editor styles the unmodified buffer
  /// (markers included), so anything computed against a rendered projection
  /// would underline the wrong characters.
  List<TextRange> check(String text) {
    final out = <TextRange>[];
    for (final (start, end) in _wordSpans(text)) {
      final word = text.substring(start, end);
      if (!isWordSpelled(word)) out.add(TextRange(start: start, end: end));
    }
    return out;
  }

  /// Up to [max] corrections, by edit distance 1 (insert/delete/substitute/
  /// transpose) filtered through the dictionary.
  ///
  /// Distance 1 covers the overwhelming majority of real typos, and generating
  /// distance-2 candidates for a 10-letter word is ~250k strings — the wrong
  /// trade for a right-click menu.
  List<String> suggest(String word, {int max = 5}) {
    final lower = word.toLowerCase();
    if (lower.isEmpty || isWordSpelled(word)) return const [];
    const alphabet = 'abcdefghijklmnopqrstuvwxyz';
    final seen = <String>{};
    final hits = <String>[];

    void tryWord(String c) {
      if (c.isEmpty || !seen.add(c)) return;
      if (hits.length < max && dictionary.contains(c)) hits.add(c);
    }

    for (var i = 0; i < lower.length; i++) {
      tryWord(lower.substring(0, i) + lower.substring(i + 1)); // delete
      if (i + 1 < lower.length) {
        tryWord(lower.substring(0, i) +
            lower[i + 1] +
            lower[i] +
            lower.substring(i + 2)); // transpose
      }
      for (var a = 0; a < alphabet.length; a++) {
        final ch = alphabet[a];
        tryWord(lower.substring(0, i) + ch + lower.substring(i + 1)); // sub
        tryWord(lower.substring(0, i) + ch + lower.substring(i)); // insert
      }
    }
    for (var a = 0; a < alphabet.length; a++) {
      tryWord(lower + alphabet[a]);
    }

    // Restore the original capitalisation shape so replacing "Teh" offers
    // "The", not "the".
    if (word.isNotEmpty && word[0] == word[0].toUpperCase()) {
      return [
        for (final h in hits)
          h.isEmpty ? h : h[0].toUpperCase() + h.substring(1)
      ];
    }
    return hits;
  }

  /// Word spans worth checking, skipping everything that isn't prose.
  ///
  /// The text is Markdown in our own dialect, so a naive tokenizer would flag
  /// URLs, hashes, wiki-link targets and code — the exact content people write
  /// most and least want underlined.
  static Iterable<(int, int)> _wordSpans(String text) sync* {
    var i = 0;
    while (i < text.length) {
      // Skip regions wholesale.
      final skipTo = _skipRegionEnd(text, i);
      if (skipTo > i) {
        i = skipTo;
        continue;
      }
      if (!_isWordChar(text.codeUnitAt(i))) {
        i++;
        continue;
      }
      final start = i;
      while (i < text.length && _isWordChar(text.codeUnitAt(i))) {
        i++;
      }
      var end = i;
      // Trim edge apostrophes: "don't" is a word, "'quoted'" is not two.
      var s = start;
      while (s < end && _isApostrophe(text.codeUnitAt(s))) {
        s++;
      }
      while (end > s && _isApostrophe(text.codeUnitAt(end - 1))) {
        end--;
      }
      if (end - s < 2) continue; // single letters are never misspelled
      final word = text.substring(s, end);
      // Digits anywhere → an identifier, a measurement, a version.
      if (word.codeUnits.any((c) => c >= 0x30 && c <= 0x39)) continue;
      yield (s, end);
    }
  }

  /// If a non-prose region starts at [i], the offset just past it.
  static int _skipRegionEnd(String text, int i) {
    // `inline code`
    if (text[i] == '`') {
      final close = text.indexOf('`', i + 1);
      return close < 0 ? text.length : close + 1;
    }
    // [[wiki links]] and {{markers}} — both are targets/metadata, not prose.
    if (text.startsWith('[[', i)) {
      final close = text.indexOf(']]', i + 2);
      return close < 0 ? text.length : close + 2;
    }
    if (text.startsWith('{{', i)) {
      final close = text.indexOf('}}', i + 2);
      return close < 0 ? text.length : close + 2;
    }
    // Bare URLs and scheme-ish tokens (http://…, sha256:…, mailto:…).
    if (_isWordChar(text.codeUnitAt(i)) &&
        (i == 0 || !_isWordChar(text.codeUnitAt(i - 1)))) {
      var j = i;
      while (j < text.length && _isWordChar(text.codeUnitAt(j))) {
        j++;
      }
      if (j < text.length && text[j] == ':') {
        // Consume to whitespace — the whole token is machine-readable.
        var k = j;
        while (k < text.length && !_isSpace(text.codeUnitAt(k))) {
          k++;
        }
        return k;
      }
    }
    return i;
  }

  static bool _isWordChar(int c) =>
      (c >= 0x41 && c <= 0x5A) || // A-Z
      (c >= 0x61 && c <= 0x7A) || // a-z
      (c >= 0x30 && c <= 0x39) || // 0-9 (kept, then whole word rejected)
      c == 0x27 ||
      c == 0x2019 || // ' and ’
      c > 0x7F; // any non-ASCII letter (accented, Greek, …)

  static bool _isApostrophe(int c) => c == 0x27 || c == 0x2019;
  static bool _isSpace(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;
}
