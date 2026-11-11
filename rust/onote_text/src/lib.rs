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

use harper_core::linting::{LintGroup, LintKind, Linter};
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
        let dict = guard
            .as_ref()
            .map(|e| e.dict.clone())
            .unwrap_or_else(FstDictionary::curated);
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
    // Opinions, not mistakes. The Oxford comma is the clear one: Harper asks
    // for it, and Australian and British writing mostly does not use it.
    group.config.set_rule_enabled("OxfordComma", false);
    group.config.set_rule_enabled("NoOxfordComma", false);
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
        Agreement | BoundaryError | Capitalization | Eggcorn | Grammar | Malapropism
        | Miscellaneous | Nonstandard | Punctuation | Regionalism | Repetition | Usage
        | WordChoice => Some(WANT_GRAMMAR),
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

/// Check `text` and return the findings as JSON:
/// `[{"s":0,"e":4,"k":"spelling","m":"…","r":["fix","fix"]}]`.
///
/// `text` is expected to be *prose already*: the caller blanks out anything
/// that is not (code, links, markers) with spaces of the same length, which
/// keeps every offset valid.
pub fn check(text: &str, dialect: Dialect, want: u32) -> Value {
    let offsets = utf16_offsets(text);
    let lints = with_engine(dialect, |e| {
        let doc = Document::new_markdown_default(text, &*e.dict);
        e.group.lint(&doc)
    });
    let mut out = Vec::new();
    for l in lints {
        let Some(bucket) = classify(l.lint_kind) else {
            continue;
        };
        if want & bucket == 0 {
            continue;
        }
        let (s, e) = (l.span.start, l.span.end);
        if e > offsets.len() - 1 || s >= e {
            continue;
        }
        let word: String = text.chars().skip(s).take(e - s).collect();
        let fixes: Vec<String> = l
            .suggestions
            .iter()
            .take(5)
            .map(|sug| sug.to_string())
            .collect();
        out.push(json!({
            "s": offsets[s],
            "e": offsets[e],
            "k": kind_name(l.lint_kind),
            "m": l.message,
            "w": word,
            "r": fixes,
        }));
    }
    Value::Array(out)
}

/// Up to `max` spelling suggestions for a single word, best first.
pub fn suggest(word: &str, dialect: Dialect, max: usize) -> Vec<String> {
    with_engine(dialect, |e| {
        harper_core::spell::suggest_correct_spelling_str(word, max, 2, &*e.dict)
    })
}

/// Is this a word in the dialect's dictionary?
pub fn is_word(word: &str, dialect: Dialect) -> bool {
    with_engine(dialect, |e| e.dict.contains_word_str(word))
}

/// The one correction we are sure enough of to make without asking, or `None`.
///
/// Deliberately timid, because a wrong silent change is worse than a typo left
/// for the person to see:
///   * the word must not be in the dictionary (so `form` is never touched);
///   * it must be 3 to 20 letters, all letters, not an ALL-CAPS acronym;
///   * exactly **one** dictionary word may lie one edit away, and it must
///     start with the same letter (typos rarely change the first one), so a
///     choice between `were` and `we` for `wer` is no correction at all;
///   * the capital shape is kept (`Teh` → `The`).
pub fn autocorrect(word: &str, dialect: Dialect) -> Option<String> {
    let n = word.chars().count();
    if !(3..=20).contains(&n) || !word.chars().all(|c| c.is_alphabetic()) {
        return None;
    }
    if n > 1 && word.chars().all(|c| c.is_uppercase()) {
        return None;
    }
    with_engine(dialect, |e| {
        let chars: Vec<char> = word.chars().collect();
        if e.dict.contains_word(&chars) {
            return None;
        }
        let lower: Vec<char> = word.to_lowercase().chars().collect();
        // Harper's distance counts a swapped pair as two edits, but a swapped
        // pair is the commonest typo there is (`teh`), so ask for up to two and
        // do our own counting below, where a swap is one edit.
        let mut near: Vec<String> = e
            .dict
            .fuzzy_match(&lower, 2, 40)
            .into_iter()
            .map(|m| m.word.iter().collect::<String>().to_lowercase())
            .filter(|w| {
                let w: Vec<char> = w.chars().collect();
                w.first() == lower.first() && one_edit_away(&lower, &w)
            })
            .collect();
        // The same word can appear in more than one case (`it`, `IT`).
        near.sort();
        near.dedup();
        // A swap of two neighbouring letters is rarely a different real word,
        // so when exactly one candidate is a swap it wins even if a
        // substitution also exists (`teh` is `the`, not `tea`).
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
        assert!(first("recieve").contains("receive"));
        assert!(first("lecure").contains("lecture"));
        assert!(first("definately").contains("definitely"));
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
