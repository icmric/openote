# Openote Math Input & Storage Specification

> **Document status:** Draft v0.1 · Last updated 2026-07-22
> **Purpose:** Defines the OneNote-style **linear math input** experience — type a linear string, watch it build into 2-D notation as you go — and the storage/rendering pipeline behind it. This is the spec for MATH-1…7.
> **Related:** [Data Model Spec §5.4](11-data-model-spec.md) · [Architecture §6](../04-architecture-overview.md)
> **Prior art:** UnicodeMath (Unicode Technical Note #28, v3.2 — the format behind OneNote/Word's equation editor), LaTeX, AsciiMath; reference implementation UnicodeMathML (MIT-adjacent, mineable for the buildup grammar).

---

## 1. Design position

- **Storage is canonical LaTeX** (`math` block / inline chip: `{"latex": "..."}`). LaTeX is the most portable, best-tooled semantic form; MathML is derived at export time for interchange/accessibility. Rendered output is never stored.
- **Input is multi-syntax, normalized on commit.** Users may type the **Openote linear syntax** (§3 — UnicodeMath-flavored, the OneNote experience), raw **LaTeX**, or (later) AsciiMath; all normalize to canonical LaTeX when a construct **builds up**.
- **Build-as-you-type.** Inside a math region, the editor continuously parses the linear buffer and replaces completed constructs with their 2-D rendering *in place* (the math analogue of TEXT-2's inline Markdown). The not-yet-committed tail stays visible as linear text at the caret.
- **Rendering** is native (`flutter_math_fork`, KaTeX-subset) so math is a first-class canvas citizen at any zoom. Coverage gaps vs. full LaTeX are tracked; constructs outside the renderer's subset fall back to a source-styled chip (never silent loss).
- **Non-goal:** solving, CAS, graphing (Vision §9).

## 2. Entering & leaving math

| Trigger | Result |
|---|---|
| `$…$` typed in text, or **Ctrl/⌘+=**, or toolbar Σ | inline math chip at caret |
| `$$` on its own line, or "Insert equation" | display `math` block |
| `Esc` / caret exits right edge | commit region, normalize to LaTeX |
| Backspace into a rendered construct | **de-builds** it back to linear form for editing (round-trip guarantee: every built construct de-builds to a linear string that rebuilds identically) |

## 3. The linear grammar (normative core)

Notation: `⟨op⟩` = operand — a single token, or a group in `(…)`/`{…}`. Parentheses render and auto-size; **braces group invisibly** (`1/{n+1}` → fraction with `n+1` denominator, no visible braces).

### 3.1 Tokens & autocorrect
- Control words autocorrect to Unicode/structures after a delimiter: `\alpha`→α, `\infty`→∞, `\times`→×, `\cdot`→⋅, `\sum`→∑, `\int`→∫, `\prod`→∏, `\sqrt`→√, `\to`→→, `\leq`→≤, `\geq`→≥, `\neq`→≠, `\pm`→±, `\in`→∈, `\subset`→⊂, `\cup`→∪, `\cap`→∩, `\forall`→∀, `\exists`→∃, `\partial`→∂, `\nabla`→∇, `\hbar`→ℏ, `\deg`→°, plus the full Greek set and blackboard/script/fraktur via `\bbR`/`\scrL`/`\frakg` style names. The autocorrect table ships as data (JSON) so users can extend it (MATH-4's palette is generated from the same table).
- **Space and operator characters are the build triggers** (UnicodeMath's load-bearing insight): a space after a complete construct builds it; operators (`+ − = < >` …) build the preceding construct.

### 3.2 Structures

| Input | Builds to (LaTeX canonical) |
|---|---|
| `⟨a⟩/⟨b⟩` | `\frac{a}{b}` (stacked fraction) |
| `⟨a⟩\atop⟨b⟩` | `\binom`-style stack without bar |
| `x^⟨e⟩`, `x_⟨i⟩`, `x_⟨i⟩^⟨e⟩` | `x^{e}`, `x_{i}`, `x_{i}^{e}` |
| `√⟨x⟩`, `√(n&x)` | `\sqrt{x}`, `\sqrt[n]{x}` |
| `∑_⟨lo⟩^⟨hi⟩ ⟨body⟩` | `\sum_{lo}^{hi} body` — **limits render above/below in display context** (the "characters around the sides like proper notation" requirement); same for `∏ ∫ ∬ ⋃ ⋂ ⋁ ⋀ lim` |
| `∫_0^1 f(x) \dx` | `\int_0^1 f(x)\,\mathrm{d}x` (`\dx`,`\dy`,`\dt` sugar) |
| `■(a&b@c&d)` or `\matrix(a&b@c&d)` | `\begin{pmatrix}a&b\\c&d\end{pmatrix}` — **`&` = column, `@` = row** |
| `\cases(x&x>0@-x&x≤0)` | `\begin{cases}…\end{cases}` |
| `⟨x⟩\bar`, `⟨x⟩\hat`, `⟨x⟩\vec`, `⟨x⟩\dot` | `\bar{x}` `\hat{x}` `\vec{x}` `\dot{x}` (postfix accents) |
| `\abs(x)`, `\norm(x)`, `\floor(x)`, `\ceil(x)` | `\lvert x\rvert`, `\lVert x\rVert`, `\lfloor x\rfloor`, `\lceil x\rceil` |
| `(…)` around tall content | `\left(…\right)` (stretchy, automatic) |
| `\(`,`\{`, `\_`, `\^`, `\/` | literal escapes (no build) |

**Scope-ending rule:** a trailing **space** ends the innermost open scope (e.g. after `∑_(n=1)^∞` a space begins the summand; a second space after the summand ends the n-ary scope). This matches UnicodeMath and is what makes linear entry feel like "it just knows."

### 3.3 Precedence & ambiguity (normative)
`^ _` bind tighter than `/`; `/` tighter than juxtaposition; explicit `{…}` always wins. `a/b/c` parses left-associative (`\frac{\frac{a}{b}}{c}`) but the builder SHOULD hint (dim underline) when a chained `/` builds, nudging users toward braces. Unparseable input **never blocks typing** — it stays linear until it parses; commit of an unparseable region stores it as `\text{…}`-wrapped source flagged for attention.

## 4. The palette & keyboard (MATH-4)
The symbol/structure palette is generated from the autocorrect + structure tables: **Structures** (fraction, script, radical, integral, n-ary, matrix, cases, accent, delimiter) insert linear **templates with placeholder slots** (`\frac` inserts `⟨□⟩/⟨□⟩` with the caret in the first slot; Tab cycles slots); **Symbols** tabs (Greek, operators, relations, arrows, sets/logic, misc) insert characters. Every palette entry shows its linear form as a learn-by-hover tooltip — the palette teaches the syntax.

## 5. Editing model
- Built constructs are **atoms** for cursor motion (←/→ steps over; ↓ enters slot-wise), Backspace de-builds (§2).
- Selection inside math is slot-aware; copy yields linear form (plain-text targets) or LaTeX (rich targets, configurable).
- **Nesting is unlimited**; rendering guarantees correct layout per the KaTeX box model (subset caveat §1).

## 6. Export & interchange
- Markdown export: `$latex$` / `$$latex$$` verbatim.
- **MathML export** derived from canonical LaTeX at export time (library-based; correctness over speed — it runs only on export). Accessibility surfaces (screen readers) use the same derivation.
- Import: `$…$`/`$$…$$` LaTeX recognized from Markdown/paste; OneNote import maps its native math (UnicodeMath-flavored) through the §3 grammar — the deliberate side-effect of choosing a UnicodeMath-compatible core.

## 7. Conformance test seed *(informative)*
`(x^2+4)/(x-3)` · `e^{-x^2/2}` · `∑_(n=1)^∞ 1/n^2 = π^2/6` · `∫_0^1 x^2 \dx = 1/3` · `lim_(x\to 0) (sin x)/x = 1` · `■(1&2@3&4)` · `\cases(x&x>0@-x&x≤0)` · `√(2&x+1)` · `\abs(x)\leq\norm(v)` — each MUST build, de-build, and round-trip byte-identically to its canonical LaTeX.

---

*The grammar above is the v1 core, chosen to cover the stakeholder's explicit bar (large equations, n-ary operators with proper limit placement, operator shortcuts) while staying implementable over `flutter_math_fork`. Extensions (chemistry, units, theorem environments) ride later minor revisions.*
