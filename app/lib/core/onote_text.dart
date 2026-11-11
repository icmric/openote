/// Dart bindings for the writing checker (`rust/onote_text`) over `dart:ffi`.
///
/// Optional and forgiving, exactly like [OnoteCore]: when the native library is
/// absent (a build without Rust, or a browser) [OnoteText.available] is false
/// and the editor falls back to the old word list. Nothing that calls in here
/// may assume it is there.
///
/// The library does English only. It is the caller's job (`spell/writing_checker.dart`)
/// never to send it any other language.
library;

export 'onote_text_native.dart'
    if (dart.library.js_interop) 'onote_text_web.dart';

/// One thing the checker found: where, what kind, why, and what to do.
///
/// [start] and [end] are UTF-16 offsets into the string that was checked, so
/// they can be used on a Dart string directly.
class TextFinding {
  const TextFinding({
    required this.start,
    required this.end,
    required this.kind,
    required this.message,
    required this.word,
    required this.fixes,
  });

  final int start;
  final int end;

  /// `spelling`, `grammar`, `capital`, `punctuation`, `repeat` or `dialect`.
  final String kind;
  final String message;

  /// The text the finding covers, as it was found.
  final String word;
  final List<String> fixes;

  bool get isSpelling => kind == 'spelling';

  factory TextFinding.fromJson(Map<String, dynamic> j) => TextFinding(
        start: (j['s'] as num).toInt(),
        end: (j['e'] as num).toInt(),
        kind: j['k'] as String? ?? 'grammar',
        message: j['m'] as String? ?? '',
        word: j['w'] as String? ?? '',
        fixes: [for (final f in (j['r'] as List? ?? const [])) f as String],
      );
}

/// The English the person writes, as the checker names it. The integers are the
/// ones `rust/onote_text` expects (`dialect_from_code`); keep the two in step.
enum EnglishDialect {
  american(0),
  canadian(1),
  australian(2),
  british(3),
  indian(4);

  const EnglishDialect(this.code);
  final int code;
}

/// What to report; bit flags matching `WANT_SPELLING` / `WANT_GRAMMAR`.
const int kWantSpelling = 1;
const int kWantGrammar = 2;
