//! Openote's writing checker.
//!
//! **What this is for.** The app's own spell checker is one American word list
//! with no grammar and no idea which English the person writes. This crate wraps
//! [Harper](https://github.com/Automattic/harper) (Apache-2.0, offline) so the
//! app can underline spelling *and* grammar in the person's own dialect —
//! Australian, British, Canadian, Indian or American — and make the small
//! automatic corrections people expect (`teh` → `the`).
//!
//! **What it does not do.** English only. Harper has no other language. The
//! caller decides which language is being written and does not call in for any
//! other; nothing here guesses.
//!
//! **Offsets.** Harper counts Unicode scalar values; Dart counts UTF-16 code
//! units. Every offset that leaves this crate has been converted to UTF-16, so
//! the Dart side can use it on its own strings without thinking about it (an
//! emoji is two units in Dart and one here, and an unconverted offset
//! underlines the wrong word for the rest of the line).
//!
//! **Text in, JSON out.** The same shape as `onote_core`'s FFI: UTF-8 in, a
//! JSON string out, freed with [`onote_text_free`].

use std::ffi::{c_char, CStr, CString};
use std::sync::{Arc, Mutex, OnceLock};

use harper_core::linting::{LintGroup, LintKind, Linter, Suggestion};
use harper_core::spell::{Dictionary, FstDictionary};
use harper_core::{Dialect, Document};
use serde_json::{json, Value};

/// What to report. Bit flags, so the app's four switches map straight on.
pub const WANT_SPELLING: u32 = 1;
pub const WANT_GRAMMAR: u32 = 2;

/// The dialect codes the Dart side sends. Kept as plain integers so the FFI
/// stays plain: this is the one list both sides must agree on.
pub fn dialect_from_code(code: i32) -> Dialect {
    match code {
        1 => Dialect::Canadian,
        2 => Dialect::Australian,
        3 => Dialect::British,
        4 => Dialect::Indian,
        _ => Dialect::American,
    }
}

/// One engine for the process: loading the dictionary costs about a second and
/// the grammar rules are built per dialect, so both are kept and reused.
struct Engine {
    dict: Arc<FstDictionary>,
    dialect: Dialect,
    group: LintGroup,
}

static ENGINE: OnceLock<Mutex<Option<Engine>>> = OnceLock::new();

/// The dictionary on its own, shared and read-only. Autocorrect and the word
/// queries use only this, so they never wait for the engine's lock: a long
/// check running on a worker thread must not make a keystroke on the UI thread
/// stall (the dictionary is immutable, so there is nothing to protect).
static DICT: OnceLock<Arc<FstDictionary>> = OnceLock::new();

fn dictionary() -> Arc<FstDictionary> {
    DICT.get_or_init(FstDictionary::curated).clone()
}

/// Is `word` a word in this dialect? A spelling that only another English uses
/// (`organisation` for an American, `organization` for an Australian) is in the
/// dictionary but is not a word *here*: the dialect tags on the entry say so.
fn is_word_in(dict: &FstDictionary, word: &str, dialect: Dialect) -> bool {
    if !dict.contains_word_str(word) {
        return false;
    }
    match dict.get_word_metadata_str(word) {
        Some(m) => m.dialects.is_dialect_enabled(dialect),
        None => true,
    }
}

fn with_engine<T>(dialect: Dialect, f: impl FnOnce(&mut Engine) -> T) -> T {
    let cell = ENGINE.get_or_init(|| Mutex::new(None));
    // A panic inside Harper must not leave the lock poisoned forever: the
    // engine is rebuilt from scratch, which is the safe thing to do.
    let mut guard = cell.lock().unwrap_or_else(|e| e.into_inner());
    let rebuild = match guard.as_ref() {
        Some(e) => e.dialect != dialect,
        None => true,
    };
    if rebuild {
        let dict = dictionary();
        let group = new_group(dict.clone(), dialect);
        *guard = Some(Engine {
            dict,
            dialect,
            group,
        });
    }
    f(guard.as_mut().expect("engine was just built"))
}

fn new_group(dict: Arc<FstDictionary>, dialect: Dialect) -> LintGroup {
    let mut group = LintGroup::new_curated(dict, dialect);
    // Opinions and habits, not mistakes. A student's notes are shorthand, in
    // bullets, with lower-case list items and informal words, and none of this
    // should be underlined as if it were an error:
    //   * the Oxford comma (Harper asks for it; Australian and British writing
    //     mostly does not use one);
    //   * a capital on every sentence and list item, and Title Case headings
    //     (the app's own, switchable, capitalisation handles the first word);
    //   * expanding abbreviations and initialisms ("idk" -> "I don't know");
    //   * contractions, swearing, long sentences, spelled-out numbers.
    // Matched by name AND by family prefix, so a rule added in a later Harper
    // of the same kind is quiet by default instead of arriving as new noise.
    const OFF: &[&str] = &[
        "OxfordComma",
        "NoOxfordComma",
        "SentenceCapitalization",
        "UseTitleCase",
        "DotInitialisms",
        "AvoidContractions",
        "AvoidCurses",
        "LongSentences",
        "SpelledNumbers",
        "NoFrenchSpaces",
        // "idk" -> "I don't know": expanding shorthand is a style choice.
        "IDontKnow",
    ];
    const OFF_PREFIXES: &[&str] = &["Expand", "Avoid"];
    let keys: Vec<String> = group.iter_keys().map(str::to_string).collect();
    for k in keys {
        if OFF.contains(&k.as_str()) || OFF_PREFIXES.iter().any(|p| k.starts_with(p)) {
            group.config.set_rule_enabled(&k, false);
        }
    }
    group
}

/// Which of Harper's lint kinds are *mistakes* the person would want to know
/// about, and which are the spelling ones. Everything else (style,
/// readability, "enhancement", redundancy) is advice, and a student's notes do
/// not need advice underlined as if it were an error.
fn classify(kind: LintKind) -> Option<u32> {
    use LintKind::*;
    match kind {
        Spelling | Typo => Some(WANT_SPELLING),
        // `Nonstandard` is left out on purpose: "gonna" and "ain't" are informal,
        // not wrong, and notes are informal.
        Agreement | BoundaryError | Capitalization | Eggcorn | Grammar | Malapropism
        | Miscellaneous | Punctuation | Regionalism | Repetition | Usage | WordChoice => {
            Some(WANT_GRAMMAR)
        }
        _ => None,
    }
}

fn kind_name(kind: LintKind) -> &'static str {
    use LintKind::*;
    match kind {
        Spelling | Typo => "spelling",
        Capitalization => "capital",
        Punctuation => "punctuation",
        Repetition => "repeat",
        Regionalism => "dialect",
        _ => "grammar",
    }
}

/// Character index → UTF-16 offset, for every position in `text` (and one past
/// the end).
fn utf16_offsets(text: &str) -> Vec<usize> {
    let mut out = Vec::with_capacity(text.len() + 1);
    let mut n = 0usize;
    for c in text.chars() {
        out.push(n);
        n += c.len_utf16();
    }
    out.push(n);
    out
}

/// Keep Markdown from reading blanked-out text as a code block.
///
/// The app blanks `[[a link]]`, `code` and equations to spaces of the same
/// length so every offset survives. A line that *begins* with one is then
/// indented, and Markdown treats four or more leading spaces as an indented
/// code block, which would switch checking off for the rest of that line
/// without a word. So leading spaces past the third become U+2007 (a figure
/// space: still whitespace, still one character, and not a space to Markdown).
///
/// A nested list item (`    - item`) is left alone, because there the indent
/// means something.
fn soften_indent(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for (i, line) in text.split('\n').enumerate() {
        if i > 0 {
            out.push('\n');
        }
        let lead = line.chars().take_while(|c| *c == ' ').count();
        let rest: String = line.chars().skip(lead).collect();
        let is_list = {
            let mut cs = rest.chars();
            match cs.next() {
                Some('-') | Some('*') | Some('+') => cs.next() == Some(' '),
                Some(d) if d.is_ascii_digit() => {
                    let tail: String = rest.chars().skip_while(|c| c.is_ascii_digit()).collect();
                    tail.starts_with(". ") || tail.starts_with(") ")
                }
                _ => false,
            }
        };
        if lead >= 4 && !is_list {
            out.extend(std::iter::repeat(' ').take(3));
            out.extend(std::iter::repeat('\u{2007}').take(lead - 3));
        } else {
            out.extend(std::iter::repeat(' ').take(lead));
        }
        out.push_str(&rest);
    }
    out
}

/// The longest text checked in one go, in characters. A paragraph is a few
/// hundred; this is a book chapter pasted into one box. Past it the box is left
/// unchecked rather than holding the checker for seconds.
pub const MAX_CHARS: usize = 60_000;

/// A finding before it leaves this crate.
struct Found {
    start: usize,
    end: usize,
    bucket: u32,
    kind: &'static str,
    message: String,
    word: String,
    fixes: Vec<String>,
    priority: u8,
}

/// Check `text` and return the findings as JSON:
/// `[{"s":0,"e":4,"k":"spelling","m":"…","w":"word","r":["fix","fix"]}]`.
///
/// `text` is expected to be *prose already*: the caller blanks out anything
/// that is not (code, links, markers) with spaces of the same length, which
/// keeps every offset valid.
///
/// What is dropped here, and why (each was seen on real notes, not guessed):
///   * a "misspelling" with a digit in it (`H2O`, `CO2`) or in capitals (`UNSW`,
///     `NASA`) — formulas and acronyms, which the old checker never flagged;
///   * advice rather than mistakes (see [`classify`] and [`new_group`]);
///   * duplicates: one mistake often trips two or three rules on the same
///     words (`that that` came back three times), and the person should see one
///     underline with every fix on it.
pub fn check(text: &str, dialect: Dialect, want: u32) -> Value {
    if text.chars().count() > MAX_CHARS {
        return Value::Array(vec![]);
    }
    let offsets = utf16_offsets(text);
    let lints = with_engine(dialect, |e| {
        let soft = soften_indent(text);
        let doc = Document::new_markdown_default(&soft, &*e.dict);
        e.group.lint(&doc)
    });
    let chars: Vec<char> = text.chars().collect();
    let mut found: Vec<Found> = Vec::new();
    for l in lints {
        let Some(bucket) = classify(l.lint_kind) else {
            continue;
        };
        if want & bucket == 0 {
            continue;
        }
        let (s, e) = (l.span.start, l.span.end);
        if e > offsets.len() - 1 || e > chars.len() || s >= e {
            continue;
        }
        let word: String = chars[s..e].iter().collect();
        if bucket == WANT_SPELLING {
            let letters: Vec<char> = word.chars().filter(|c| c.is_alphabetic()).collect();
            if word.chars().any(|c| c.is_ascii_digit())
                || (letters.len() > 1 && letters.iter().all(|c| c.is_uppercase()))
            {
                continue;
            }
        }
        // What the flagged text should BECOME, not Harper's display sentence
        // ("Replace with: “x”"): the app puts this straight into the note.
        let fixes: Vec<String> = l
            .suggestions
            .iter()
            .take(5)
            .map(|sug| match sug {
                Suggestion::ReplaceWith(cs) => cs.iter().collect::<String>(),
                Suggestion::InsertAfter(cs) => {
                    format!("{}{}", word, cs.iter().collect::<String>())
                }
                Suggestion::Remove => String::new(),
            })
            .collect();
        found.push(Found {
            start: offsets[s],
            end: offsets[e],
            bucket,
            kind: kind_name(l.lint_kind),
            message: l.message,
            word,
            fixes,
            priority: l.priority,
        });
    }

    // One underline per span: spelling first (it is the thing to fix first),
    // then the most important rule; the others' fixes are folded in.
    found.sort_by(|a, b| {
        (a.start, a.end, (a.bucket != WANT_SPELLING) as u8, a.priority).cmp(&(
            b.start,
            b.end,
            (b.bucket != WANT_SPELLING) as u8,
            b.priority,
        ))
    });
    let mut merged: Vec<Found> = Vec::new();
    for f in found {
        match merged.last_mut() {
            Some(m) if m.start == f.start && m.end == f.end => {
                for fix in f.fixes {
                    if !m.fixes.contains(&fix) {
                        m.fixes.push(fix);
                    }
                }
            }
            _ => merged.push(f),
        }
    }
    Value::Array(
        merged
            .into_iter()
            .map(|f| {
                json!({
                    "s": f.start,
                    "e": f.end,
                    "k": f.kind,
                    "m": f.message,
                    "w": f.word,
                    "r": f.fixes.into_iter().take(5).collect::<Vec<_>>(),
                })
            })
            .collect(),
    )
}

/// Up to `max` spelling suggestions for a single word, best first, and only
/// words that are words in this dialect (an Australian is not offered
/// `organization`).
pub fn suggest(word: &str, dialect: Dialect, max: usize) -> Vec<String> {
    let dict = dictionary();
    harper_core::spell::suggest_correct_spelling_str(word, max.saturating_mul(3), 2, &*dict)
        .into_iter()
        .filter(|w| is_word_in(&dict, w, dialect))
        .take(max)
        .collect()
}

/// Is this a word in the dialect?
pub fn is_word(word: &str, dialect: Dialect) -> bool {
    is_word_in(&dictionary(), word, dialect)
}

/// The one correction we are sure enough of to make without asking, or `None`.
///
/// Deliberately timid, because a wrong silent change is worse than a typo left
/// for the person to see:
///   * the word must not be a word (so `form` is never touched);
///   * it must be 3 to 20 letters, all letters, not an ALL-CAPS acronym;
///   * exactly **one** word of the person's own dialect may lie one edit away,
///     and it must start with the same letter (typos rarely change the first
///     one), so a choice between `were` and `we` for `wer` is no correction at
///     all, and an Australian typing `organizaton` is not "corrected" into the
///     American spelling;
///   * the capital shape is kept (`Teh` → `The`).
///
/// Uses only the dictionary, never the engine's lock, so it can be called from
/// the UI thread between keystrokes without ever waiting on a running check.
pub fn autocorrect(word: &str, dialect: Dialect) -> Option<String> {
    let n = word.chars().count();
    if !(3..=20).contains(&n) || !word.chars().all(|c| c.is_alphabetic()) {
        return None;
    }
    if n > 1 && word.chars().all(|c| c.is_uppercase()) {
        return None;
    }
    let dict = dictionary();
    let chars: Vec<char> = word.chars().collect();
    if dict.contains_word(&chars) {
        return None;
    }
    let lower: Vec<char> = word.to_lowercase().chars().collect();
    // Harper's distance counts a swapped pair as two edits, but a swapped pair
    // is the commonest typo there is (`teh`), so ask for up to two and do our
    // own counting below, where a swap is one edit.
    let mut near: Vec<String> = dict
        .fuzzy_match(&lower, 2, 40)
        .into_iter()
        .filter(|m| m.metadata.dialects.is_dialect_enabled(dialect))
        .map(|m| m.word.iter().collect::<String>().to_lowercase())
        .filter(|w| {
            let w: Vec<char> = w.chars().collect();
            w.first() == lower.first() && one_edit_away(&lower, &w)
        })
        .collect();
    // The same word can appear in more than one case (`it`, `IT`).
    near.sort();
    near.dedup();
    // A swap of two neighbouring letters is rarely a different real word, so
    // when exactly one candidate is a swap it wins even if a substitution also
    // exists (`teh` is `the`, not `tea`).
    let swaps: Vec<&String> = near
        .iter()
        .filter(|w| is_swap(&lower, &w.chars().collect::<Vec<_>>()))
        .collect();
    let mut uniq: Vec<String> = if swaps.len() == 1 {
        vec![swaps[0].clone()]
    } else {
        near.clone()
    };
    if uniq.len() != 1 {
        return None;
    }
    let fix = uniq.remove(0);
    if fix == word.to_lowercase() {
        return None;
    }
    let first_upper = word.chars().next().map_or(false, |c| c.is_uppercase());
    Some(if first_upper {
        let mut cs = fix.chars();
        cs.next()
            .map(|c| c.to_uppercase().collect::<String>() + cs.as_str())
            .unwrap_or(fix)
    } else {
        fix
    })
}

/// Two neighbouring letters exchanged: `teh` / `the`.
fn is_swap(a: &[char], b: &[char]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let diff: Vec<usize> = (0..a.len()).filter(|&i| a[i] != b[i]).collect();
    diff.len() == 2 && diff[1] == diff[0] + 1 && a[diff[0]] == b[diff[1]] && a[diff[1]] == b[diff[0]]
}

/// One insertion, deletion, substitution or neighbour swap apart.
fn one_edit_away(a: &[char], b: &[char]) -> bool {
    if a == b {
        return false;
    }
    if is_swap(a, b) {
        return true;
    }
    let (long, short) = if a.len() >= b.len() { (a, b) } else { (b, a) };
    if long.len() - short.len() > 1 {
        return false;
    }
    if long.len() == short.len() {
        return a.iter().zip(b).filter(|(x, y)| x != y).count() == 1;
    }
    // One deletion from the longer word gives the shorter.
    (0..long.len()).any(|i| {
        long.iter()
            .enumerate()
            .filter(|(j, _)| *j != i)
            .map(|(_, c)| c)
            .eq(short.iter())
    })
}

// ── C ABI ────────────────────────────────────────────────────────────────────

fn to_c(s: String) -> *mut c_char {
    // JSON and our own strings never contain NUL; if one somehow does, return
    // an empty array rather than a null the caller must special-case.
    CString::new(s)
        .unwrap_or_else(|_| CString::new("[]").unwrap())
        .into_raw()
}

unsafe fn from_c<'a>(p: *const c_char) -> Option<&'a str> {
    if p.is_null() {
        return None;
    }
    CStr::from_ptr(p).to_str().ok()
}

/// Run `f`, turning a panic inside Harper into "no answer" instead of letting
/// it unwind across the FFI boundary, which is undefined behaviour.
fn guarded<T>(f: impl FnOnce() -> T + std::panic::UnwindSafe) -> Option<T> {
    std::panic::catch_unwind(f).ok()
}

/// The crate version, as a string to free with [`onote_text_free`].
#[no_mangle]
pub extern "C" fn onote_text_version() -> *mut c_char {
    to_c(format!("onote_text {}", env!("CARGO_PKG_VERSION")))
}

/// Findings for `text`. `dialect` is the code in [`dialect_from_code`]; `want`
/// is [`WANT_SPELLING`] | [`WANT_GRAMMAR`]. Always returns a JSON array.
///
/// # Safety
/// `text` must be null or a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn onote_text_check(
    text: *const c_char,
    dialect: i32,
    want: u32,
) -> *mut c_char {
    let Some(t) = from_c(text) else {
        return to_c("[]".into());
    };
    let v = guarded(|| check(t, dialect_from_code(dialect), want)).unwrap_or(Value::Array(vec![]));
    to_c(v.to_string())
}

/// Suggestions for one word, as a JSON array of strings.
///
/// # Safety
/// `word` must be null or a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn onote_text_suggest(
    word: *const c_char,
    dialect: i32,
    max: i32,
) -> *mut c_char {
    let Some(w) = from_c(word) else {
        return to_c("[]".into());
    };
    let v = guarded(|| suggest(w, dialect_from_code(dialect), max.clamp(1, 10) as usize))
        .unwrap_or_default();
    to_c(json!(v).to_string())
}

/// The sure correction for `word`, or an empty string for "leave it".
///
/// # Safety
/// `word` must be null or a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn onote_text_autocorrect(word: *const c_char, dialect: i32) -> *mut c_char {
    let Some(w) = from_c(word) else {
        return to_c(String::new());
    };
    let fix = guarded(|| autocorrect(w, dialect_from_code(dialect))).flatten();
    to_c(fix.unwrap_or_default())
}

/// 1 if `word` is in the dialect's dictionary, else 0.
///
/// # Safety
/// `word` must be null or a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn onote_text_is_word(word: *const c_char, dialect: i32) -> i32 {
    let Some(w) = from_c(word) else {
        return 1;
    };
    // On any failure say "yes, it's a word": a broken checker must stay quiet.
    guarded(|| is_word(w, dialect_from_code(dialect)) as i32).unwrap_or(1)
}

/// Free a string returned by any function above.
///
/// # Safety
/// `p` must come from this library and not have been freed.
#[no_mangle]
pub unsafe extern "C" fn onote_text_free(p: *mut c_char) {
    if !p.is_null() {
        drop(CString::from_raw(p));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const ALL: u32 = WANT_SPELLING | WANT_GRAMMAR;

    fn words(v: &Value) -> Vec<String> {
        v.as_array()
            .unwrap()
            .iter()
            .map(|x| x["w"].as_str().unwrap().to_string())
            .collect()
    }

    #[test]
    fn everyday_words_are_not_flagged() {
        // The reason this crate exists: the old list underlined all of these.
        let t = "On Monday in January I flew to Australia with my laptop. I don't think it's \
                 the website's dataset. Email Dr Smith about the mitochondria.";
        let v = check(t, Dialect::Australian, ALL);
        assert!(words(&v).is_empty(), "flagged: {:?}", words(&v));
    }

    #[test]
    fn the_dialect_decides_what_colour_is() {
        let t = "The organisation chose a colour for the favourite.";
        assert!(words(&check(t, Dialect::Australian, ALL)).is_empty());
        assert!(words(&check(t, Dialect::British, ALL)).is_empty());
        let us = words(&check(t, Dialect::American, ALL));
        assert!(us.contains(&"colour".to_string()), "{us:?}");
        assert!(us.contains(&"organisation".to_string()), "{us:?}");
    }

    #[test]
    fn typos_get_the_right_first_suggestion() {
        let v = check("I recieve the lecure definately.", Dialect::Australian, ALL);
        let arr = v.as_array().unwrap();
        let first = |w: &str| {
            arr.iter()
                .find(|x| x["w"] == w)
                .and_then(|x| x["r"][0].as_str())
                .unwrap_or("")
                .to_string()
        };
        // The replacement text itself, not a sentence about it.
        assert_eq!(first("recieve"), "receive");
        assert_eq!(first("lecure"), "lecture");
        assert_eq!(first("definately"), "definitely");
    }

    #[test]
    fn the_switches_choose_what_is_reported() {
        let t = "Their going to recieve it.";
        let spell = check(t, Dialect::Australian, WANT_SPELLING);
        let gram = check(t, Dialect::Australian, WANT_GRAMMAR);
        let sk: Vec<_> = spell.as_array().unwrap().iter().map(|x| x["k"].clone()).collect();
        assert!(sk.iter().all(|k| k == "spelling"), "{sk:?}");
        assert!(!spell.as_array().unwrap().is_empty());
        assert!(gram.as_array().unwrap().iter().all(|x| x["k"] != "spelling"));
        assert!(!gram.as_array().unwrap().is_empty());
        assert!(check(t, Dialect::Australian, 0).as_array().unwrap().is_empty());
    }

    #[test]
    fn the_oxford_comma_is_nobodys_business() {
        let v = check("We bought an apple, a pear and a plum.", Dialect::Australian, ALL);
        assert!(words(&v).is_empty(), "{:?}", words(&v));
    }

    #[test]
    fn offsets_are_utf16_so_dart_can_use_them() {
        // 😀 is one scalar value here and two UTF-16 units in Dart.
        let t = "😀 I recieve it";
        let v = check(t, Dialect::Australian, WANT_SPELLING);
        let hit = &v.as_array().unwrap()[0];
        let (s, e) = (hit["s"].as_u64().unwrap() as usize, hit["e"].as_u64().unwrap() as usize);
        let units: Vec<u16> = t.encode_utf16().collect();
        assert_eq!(String::from_utf16(&units[s..e]).unwrap(), "recieve");
    }

    #[test]
    fn blanked_out_regions_keep_every_offset() {
        // What the app sends: code, links and markers replaced by spaces.
        let t = "I recieve it            and teh end";
        let v = check(t, Dialect::Australian, WANT_SPELLING);
        let ws = words(&v);
        assert!(ws.contains(&"recieve".to_string()) && ws.contains(&"teh".to_string()), "{ws:?}");
    }

    #[test]
    fn autocorrect_fixes_only_the_sure_cases() {
        for (typo, fix) in [("teh", "the"), ("adn", "and"), ("taht", "that"), ("recieve", "receive"), ("Teh", "The")] {
            assert_eq!(autocorrect(typo, Dialect::Australian).as_deref(), Some(fix), "{typo}");
        }
    }

    #[test]
    fn autocorrect_leaves_real_words_names_and_acronyms_alone() {
        for w in ["form", "Monday", "Australia", "NASA", "mitochondria", "colour", "ok"] {
            assert_eq!(autocorrect(w, Dialect::Australian), None, "{w}");
        }
        // American does not accept colour, but it must not be silently
        // "corrected" without being asked: that is the underline's job.
        assert_eq!(autocorrect("zzzzzz", Dialect::Australian), None);
        assert_eq!(autocorrect("a1b2", Dialect::Australian), None);
    }

    #[test]
    fn autocorrect_refuses_when_there_is_a_choice() {
        // `wer` could be `we`, `were`, `war`, `her`…: no single answer.
        assert_eq!(autocorrect("wer", Dialect::Australian), None);
    }

    // ── Found by running real notes through it (see examples/probe.rs) ──────────

    #[test]
    fn formulas_and_acronyms_are_not_misspellings() {
        let t = "H2O and CO2 react; NaCl is 5kg. NASA and UNSW agree.";
        let v = check(t, Dialect::Australian, WANT_SPELLING);
        let ws = words(&v);
        // `NaCl` has no digit and is not all capitals, so it may be flagged:
        // that is a word the person can add. The rest must not be.
        for bad in ["H2O", "CO2", "NASA", "UNSW", "5kg"] {
            assert!(!ws.contains(&bad.to_string()), "{bad} flagged: {ws:?}");
        }
    }

    #[test]
    fn notes_are_not_marked_down_for_being_notes() {
        // Lower-case bullets, informal words, a heading in sentence case,
        // abbreviations: shorthand, not errors.
        let t = "# Week 4 notes\n\n- read ch. 4\n- email Sarah re the assignment\n\nidk, gonna finish this tonight.";
        let v = check(t, Dialect::Australian, WANT_GRAMMAR);
        assert!(words(&v).is_empty(), "grammar noise: {:?}", words(&v));
    }

    #[test]
    fn one_mistake_is_one_underline_with_every_fix_on_it() {
        let v = check("I think that that is it.", Dialect::Australian, WANT_GRAMMAR);
        let arr = v.as_array().unwrap();
        let spans: Vec<_> = arr.iter().map(|x| (x["s"].clone(), x["e"].clone())).collect();
        let mut dedup = spans.clone();
        dedup.dedup();
        assert_eq!(spans, dedup, "two underlines on the same words: {arr:?}");
        assert_eq!(arr.len(), 1, "{arr:?}");
    }

    #[test]
    fn spelling_wins_when_both_apply_to_the_same_words() {
        // `alot` is a misspelling AND a boundary error; it must be one finding,
        // and it must be the spelling one (the thing to fix first).
        let v = check("There are alot of them.", Dialect::Australian, ALL);
        let arr: Vec<_> = v
            .as_array()
            .unwrap()
            .iter()
            .filter(|x| x["w"] == "alot")
            .collect();
        assert_eq!(arr.len(), 1);
        assert_eq!(arr[0]["k"], "spelling");
        assert!(arr[0]["r"].as_array().unwrap().iter().any(|f| f == "a lot"));
    }

    #[test]
    fn a_huge_box_is_left_alone_rather_than_holding_the_checker() {
        let t = "recieve ".repeat(MAX_CHARS / 8 + 10);
        assert!(check(&t, Dialect::Australian, ALL).as_array().unwrap().is_empty());
    }

    // ── Dialects, in the places that are not the underline ──────────────────────

    #[test]
    fn autocorrect_never_swaps_in_another_englishs_spelling() {
        // `colur` is one letter from both `color` and `colour`. Each person
        // gets the one that is a word in THEIR English, never the other's: an
        // Australian silently turned into an American (or the reverse) is a bug.
        assert_eq!(autocorrect("colur", Dialect::Australian).as_deref(), Some("colour"));
        assert_eq!(autocorrect("colur", Dialect::British).as_deref(), Some("colour"));
        assert_eq!(autocorrect("colur", Dialect::American).as_deref(), Some("color"));
    }

    #[test]
    fn suggestions_are_words_in_the_persons_dialect() {
        let au = suggest("colur", Dialect::Australian, 5);
        assert!(au.iter().any(|w| w == "colour"), "{au:?}");
        assert!(!au.iter().any(|w| w == "color"), "{au:?}");
        let us = suggest("colur", Dialect::American, 5);
        assert!(us.iter().any(|w| w == "color"), "{us:?}");
        assert!(!us.iter().any(|w| w == "colour"), "{us:?}");
    }

    #[test]
    fn a_word_is_a_word_only_in_the_dialects_that_use_it() {
        assert!(is_word("colour", Dialect::Australian));
        assert!(!is_word("colour", Dialect::American));
        assert!(is_word("color", Dialect::American));
        assert!(is_word("Monday", Dialect::American));
    }

    // ── It must never make the keyboard wait ────────────────────────────────────

    #[test]
    fn autocorrect_does_not_wait_for_a_running_check() {
        // Hold the engine lock the way a long check does, and ask for a
        // correction from another thread. It must answer, not block.
        let _ = autocorrect("teh", Dialect::Australian); // load the dictionary
        let cell = ENGINE.get_or_init(|| Mutex::new(None));
        let guard = cell.lock().unwrap_or_else(|e| e.into_inner());
        let (tx, rx) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
            tx.send(autocorrect("teh", Dialect::Australian)).ok();
        });
        let got = rx
            .recv_timeout(std::time::Duration::from_secs(5))
            .expect("autocorrect blocked on the engine lock");
        drop(guard);
        assert_eq!(got.as_deref(), Some("the"));
    }

    #[test]
    fn several_threads_can_check_at_once() {
        let handles: Vec<_> = (0..4)
            .map(|_| {
                std::thread::spawn(|| {
                    let v = check("I recieve it.", Dialect::Australian, ALL);
                    words(&v)
                })
            })
            .collect();
        for h in handles {
            assert_eq!(h.join().unwrap(), vec!["recieve".to_string()]);
        }
    }

    #[test]
    fn switching_dialect_back_and_forth_is_safe() {
        for d in [Dialect::American, Dialect::Australian, Dialect::British, Dialect::American] {
            let v = check("The colour.", d, WANT_SPELLING);
            let flagged = !words(&v).is_empty();
            assert_eq!(flagged, d == Dialect::American, "{d:?}");
        }
    }

    #[test]
    fn a_line_that_starts_with_a_blanked_region_is_still_checked() {
        // The app blanks `[[a link]]` and `code` to spaces. A line that begins
        // with one is then indented by that many spaces, and Markdown reads
        // four or more leading spaces as a code block, which would silently
        // switch the checker off for the rest of the line.
        let t = "            and I recieve it\n\n        and I recieve it too";
        let ws = words(&check(t, Dialect::Australian, WANT_SPELLING));
        assert_eq!(ws, vec!["recieve".to_string(), "recieve".to_string()], "{ws:?}");
    }

    #[test]
    fn the_ffi_round_trips_and_survives_bad_input() {
        unsafe {
            let t = CString::new("I recieve it").unwrap();
            let p = onote_text_check(t.as_ptr(), 2, 3);
            let s = CStr::from_ptr(p).to_str().unwrap().to_string();
            onote_text_free(p);
            assert!(s.contains("recieve"), "{s}");
            let p = onote_text_check(std::ptr::null(), 2, 3);
            assert_eq!(CStr::from_ptr(p).to_str().unwrap(), "[]");
            onote_text_free(p);
            assert_eq!(onote_text_is_word(std::ptr::null(), 0), 1);
        }
    }
}
