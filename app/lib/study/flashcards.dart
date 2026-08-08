/// Flashcards generated from your own notes (the study loop).
///
/// **The pitch:** tag a line Question or Definition while taking notes; the
/// week before the exam, Openote quizzes you on them. No second app, no
/// re-typing what you already wrote.
///
/// The on-ramp already existed — Question and Definition tags with a rollup
/// panel — so this is the small step from *finding* what you marked to
/// *studying* it. That step is the differentiator: no mainstream notes app
/// does it natively, and students maintain a painful second system by hand.
///
/// **Scope guard, revised.** This began as a pure *view* of the notes: tag a
/// line, get a card. That stayed true and stays true — but "Currently not
/// intuitive how to use them" was the verdict, because nothing about typing a
/// line of notes suggests that tagging it produces a card, and the tag chords
/// are invisible until you know them.
///
/// So there is now a second door: Insert ▸ Flashcard puts a real card on the
/// page, which you fill in and flip where it sits. Both doors lead to the same
/// deck — [cardsFromBlock] emits from either, so scheduling, the study panel,
/// the deck counts and the exam plan needed no changes at all. What is still
/// out of scope is a flashcard *app*: no shared decks, no card templates, no
/// separate authoring surface away from the notes.
library;

import '../model/models.dart';
import '../model/tags.dart';

/// Where a card came from, so review can jump back to the note.
class Flashcard {
  Flashcard({
    required this.pageId,
    required this.pageTitle,
    required this.blockId,
    required this.line,
    required this.front,
    required this.back,
    required this.kind,
  });

  final String pageId;
  final String pageTitle;
  final String blockId;
  final int line;
  final String front;
  final String back;
  final TagKind kind;

  /// Stable identity across sessions and devices: the scheduling state is
  /// stored under this, and it must survive the note being edited around the
  /// tagged line. Block id + line is as stable as the tag itself.
  String get id => '$blockId:$line';

  bool get isCloze => front.contains('[…]');
}

/// Strip our Markdown markers so a card reads as prose rather than source.
///
/// Deliberately not a full parse: cards are short, and the risk of a heavier
/// renderer here is showing a half-parsed mess on the one screen that has to
/// be readable at a glance.
String plainify(String s) {
  // `replaceAll` takes a literal replacement — `$1` there is the two
  // characters, not the capture group. Every inline marker therefore has to go
  // through `replaceAllMapped`.
  String unwrap(String input, RegExp re) =>
      input.replaceAllMapped(re, (m) => m.group(1) ?? '');

  var out = s;
  // Line prefixes first, so a bulleted checkbox line loses both.
  out = out.replaceFirst(RegExp(r'^\s*- \[[ xX]\]\s*'), '');
  out = out.replaceFirst(RegExp(r'^\s*(#{1,6}\s+|[-*]\s+|\d+\.\s+|>\s?)'), '');
  out = unwrap(out, RegExp(r'\*\*(.+?)\*\*'));
  out = unwrap(out, RegExp(r'(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)'));
  out = unwrap(out, RegExp(r'\+\+(.+?)\+\+'));
  out = unwrap(out, RegExp(r'~~(.+?)~~'));
  out = unwrap(out, RegExp(r'==(.+?)=='));
  out = unwrap(out, RegExp(r'`(.+?)`'));
  out = unwrap(out, RegExp(r'\{\{#[0-9A-Fa-f]{6,8} (.+?)\}\}'));
  out = unwrap(out, RegExp(r'\[\[([^\]|]+)(?:\|[^\]]+)?\]\]'));
  return out.trim();
}

/// The separators a definition line may use, most explicit first.
final _definitionSplits = [
  RegExp(r'\s+—\s+'), // em dash
  RegExp(r'\s+–\s+'), // en dash
  RegExp(r'\s+-\s+'), // hyphen with spaces (not a hyphenated-word)
  RegExp(r':\s+'),
  RegExp(r'\s+=\s+'),
];

/// Build cards from one text block's tagged lines.
///
/// Rules, chosen so that ordinary note-taking produces good cards without the
/// student thinking about card design:
/// - **Question** tag → that line is the front; the following *more-indented*
///   lines (or the next line) are the back.
/// - **Definition** tag → split on `term — meaning`; term is the front.
/// - A `==highlight==` inside a tagged line becomes a **cloze** blank, which
///   beats a whole-line recall for a fact buried in a sentence.
List<Flashcard> cardsFromBlock(
    Block block, String pageId, String pageTitle) {
  // A card the user placed on the page directly (Insert > Flashcard). It is
  // ONE card and it needs no parsing — the front and back are already the two
  // things they typed. Emitting it here rather than anywhere else is what
  // makes it appear in the study panel, the deck counts, the exam plan and the
  // scheduler with no further plumbing: everything downstream consumes this
  // function, and it does not care where a card came from.
  if (block.type == BlockType.flashcard) {
    final front = (block.content['front'] as String? ?? '').trim();
    final back = (block.content['back'] as String? ?? '').trim();
    // A half-written card is not a card. Reviewing a blank front teaches
    // nothing and cannot be graded honestly.
    if (front.isEmpty || back.isEmpty) return const [];
    return [
      Flashcard(
        pageId: pageId,
        pageTitle: pageTitle,
        blockId: block.id,
        // Line 0: a block card has no line to move, so its id is stable for
        // the block's whole life. `Flashcard.id` is `blockId:line`, and the
        // scheduling state is stored under it.
        line: 0,
        front: front,
        back: back,
        kind: TagKind.question,
      )
    ];
  }
  if (block.type != BlockType.text) return const [];
  final tags = NoteTag.listFrom(block.content);
  if (tags.isEmpty) return const [];
  final lines = (block.content['text'] as String? ?? '').split('\n');
  final out = <Flashcard>[];

  for (final tag in tags) {
    if (tag.kind != TagKind.question && tag.kind != TagKind.definition) {
      continue;
    }
    if (tag.line < 0 || tag.line >= lines.length) continue;
    final raw = lines[tag.line];
    final text = plainify(raw);
    if (text.isEmpty) continue;

    // Cloze: the highlighted span is what you're recalling.
    final cloze = RegExp(r'==(.+?)==').firstMatch(raw);
    if (cloze != null) {
      final answer = plainify(cloze.group(1)!);
      final blanked = plainify(raw.replaceRange(
          cloze.start, cloze.end, '[…]'));
      if (answer.isNotEmpty) {
        out.add(Flashcard(
          pageId: pageId,
          pageTitle: pageTitle,
          blockId: block.id,
          line: tag.line,
          front: blanked,
          back: answer,
          kind: tag.kind,
        ));
        continue;
      }
    }

    if (tag.kind == TagKind.definition) {
      for (final sep in _definitionSplits) {
        final m = sep.firstMatch(text);
        if (m == null) continue;
        final term = text.substring(0, m.start).trim();
        final meaning = text.substring(m.end).trim();
        if (term.isEmpty || meaning.isEmpty) continue;
        out.add(Flashcard(
          pageId: pageId,
          pageTitle: pageTitle,
          blockId: block.id,
          line: tag.line,
          front: term,
          back: meaning,
          kind: tag.kind,
        ));
        break;
      }
      continue;
    }

    // Question: the answer is what follows, indented or not.
    final back = _answerFollowing(lines, tag.line);
    if (back.isEmpty) continue;
    out.add(Flashcard(
      pageId: pageId,
      pageTitle: pageTitle,
      blockId: block.id,
      line: tag.line,
      front: text,
      back: back,
      kind: tag.kind,
    ));
  }
  return out;
}

/// The answer body following a question line: every deeper-indented line, or
/// failing that the single next non-empty line.
String _answerFollowing(List<String> lines, int at) {
  final indentOf = (String l) => l.length - l.trimLeft().length;
  final base = indentOf(lines[at]);
  final deeper = <String>[];
  for (var i = at + 1; i < lines.length; i++) {
    if (lines[i].trim().isEmpty) break;
    if (indentOf(lines[i]) <= base) break;
    deeper.add(plainify(lines[i]));
  }
  if (deeper.isNotEmpty) return deeper.join('\n');
  for (var i = at + 1; i < lines.length; i++) {
    final t = plainify(lines[i]);
    if (t.isNotEmpty) return t;
  }
  return '';
}

// ── Scheduling (SM-2) ───────────────────────────────────────────────────────

/// What a review session should contain.
enum StudyMode {
  /// The real schedule: what spaced repetition says you should see today.
  due,

  /// Everything in scope, shuffled, schedule untouched. "Go over this again"
  /// is the most common thing a student wants the night before an exam.
  cram,
}

/// How well a card was recalled.
enum Grade {
  again(0, 'Again'),
  hard(3, 'Hard'),
  good(4, 'Good'),
  easy(5, 'Easy');

  const Grade(this.quality, this.label);

  /// SM-2's 0-5 quality scale, collapsed to the four buttons every modern
  /// spaced-repetition UI uses — six choices is more introspection than anyone
  /// wants mid-review.
  final int quality;
  final String label;
}

/// Per-card scheduling state. Small and JSON-shaped: it persists in workspace
/// settings, not in the notebook, because *when you should review* is personal
/// and shouldn't travel to everyone in a shared notebook.
class CardState {
  CardState({
    this.repetitions = 0,
    this.intervalDays = 0,
    this.ease = 2.5,
    this.dueAt = 0,
    this.lapses = 0,
  });

  int repetitions;
  int intervalDays;
  double ease;
  int dueAt; // epoch ms; 0 = never reviewed, i.e. due now
  int lapses;

  bool isDue(int now) => dueAt <= now;

  CardState copy() => CardState(
        repetitions: repetitions,
        intervalDays: intervalDays,
        ease: ease,
        dueAt: dueAt,
        lapses: lapses,
      );

  Map<String, dynamic> toJson() => {
        'n': repetitions,
        'i': intervalDays,
        'e': ease,
        'due': dueAt,
        'lapses': lapses,
      };

  static CardState fromJson(Object? j) {
    if (j is! Map) return CardState();
    return CardState(
      repetitions: (j['n'] as num?)?.toInt() ?? 0,
      intervalDays: (j['i'] as num?)?.toInt() ?? 0,
      ease: (j['e'] as num?)?.toDouble() ?? 2.5,
      dueAt: (j['due'] as num?)?.toInt() ?? 0,
      lapses: (j['lapses'] as num?)?.toInt() ?? 0,
    );
  }
}

const _dayMs = 86400000;

/// How soon a card you just got wrong comes back. Ten minutes, not tomorrow.
const _relearnMs = 600000;

/// Apply a grade, returning the updated state (SM-2).
///
/// Two deliberate deviations from the classic algorithm:
///
/// 1. **Ease has a floor.** SM-2's unbounded ease decay punishes a genuinely
///    hard card into daily repetition forever — which is how students end up
///    hating their own deck.
/// 2. **Sub-day learning steps.** Textbook SM-2 has a one-day minimum, so
///    pressing Again meant the card vanished until tomorrow and there was no
///    way to have another go at the thing you just failed. That is the opposite
///    of how anyone actually revises. A lapse, and a brand-new card's first
///    correct answer, come back in ten minutes — inside the same sitting — and
///    only then graduate to days.
CardState applyGrade(CardState s, Grade g, int now) {
  final q = g.quality;
  if (q < 3) {
    s
      ..repetitions = 0
      ..intervalDays = 0
      ..lapses += 1
      ..ease = (s.ease - 0.20).clamp(1.3, 3.0)
      ..dueAt = now + _relearnMs;
    return s;
  }
  s.ease = (s.ease + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02))).clamp(1.3, 3.0);
  s.repetitions += 1;
  // The learning step. A card met for the first time (or just failed) comes
  // back in minutes, and only the NEXT correct answer graduates it to days —
  // so you can actually learn it in the sitting you met it in. `Easy` skips
  // the step; that is what the button is for.
  if (s.intervalDays == 0 && s.repetitions == 1 && g != Grade.easy) {
    s.dueAt = now + _relearnMs;
    return s;
  }
  // Driven by the interval rather than the repetition count, so a card
  // restored from an older schedule keeps its place in the ladder.
  s.intervalDays = switch (s.intervalDays) {
    0 => 1,
    1 => 6,
    _ => (s.intervalDays * s.ease).round().clamp(1, 3650),
  };
  if (g == Grade.easy) s.intervalDays = (s.intervalDays * 1.3).round();
  s.dueAt = now + s.intervalDays * _dayMs;
  return s;
}

/// What each button would do, for the label under it.
///
/// Runs the real scheduler on a copy — a preview that drifts from the algorithm
/// is worse than no preview, because the student plans around it.
String previewInterval(CardState s, Grade g, int now) =>
    formatDelay(applyGrade(s.copy(), g, now).dueAt - now);

/// A duration as a student would say it: `10m`, `3d`, `2mo`.
String formatDelay(int ms) {
  if (ms <= 0) return 'now';
  final mins = ms ~/ 60000;
  if (mins < 60) return '${mins.clamp(1, 59)}m';
  final hours = ms ~/ 3600000;
  if (hours < 36) return '${hours}h';
  final days = (ms / _dayMs).round();
  if (days < 31) return '${days}d';
  if (days < 365) return '${(days / 30).round()}mo';
  final years = days / 365;
  return years < 10 ? '${years.toStringAsFixed(1)}y' : '${years.round()}y';
}

// ── Anki export ─────────────────────────────────────────────────────────────

/// Cards as an Anki-importable TSV.
///
/// TSV rather than `.apkg` on purpose: `.apkg` is a zip of a SQLite database
/// with a schema that changes between Anki versions, so a generated one can
/// break on upgrade in ways the student can't diagnose. Anki's plain-text
/// import is stable, documented, and takes two clicks — and this way the export
/// is also readable by Quizlet, Mnemosyne, and a spreadsheet.
///
/// Escaping: Anki's TSV import splits on tabs and treats newlines as record
/// separators unless the field is quoted, so both are neutralised.
String cardsToAnkiTsv(List<Flashcard> cards) {
  String field(String s) => s
      .replaceAll('\t', '    ')
      .replaceAll('\r\n', '<br>')
      .replaceAll('\n', '<br>');
  final b = StringBuffer()
    // Anki reads these header directives; they make the import dialog
    // pre-select the right separator and enable the HTML we emit for newlines.
    ..writeln('#separator:tab')
    ..writeln('#html:true')
    ..writeln('#tags column:3');
  for (final c in cards) {
    b.writeln('${field(c.front)}\t${field(c.back)}\t'
        '${c.kind.key} ${_ankiTag(c.pageTitle)}');
  }
  return b.toString();
}

/// Anki tags can't contain spaces.
String _ankiTag(String pageTitle) =>
    pageTitle.trim().replaceAll(RegExp(r'\s+'), '-');
