# Openote Maths Input & Storage Specification

> **Normative for maths input, storage and export.** Covers MATH-1…8.
>
> The experience this defines is OneNote's: you type a linear string and watch it
> build into two-dimensional notation as you go. §3 is the grammar, §5 is what
> the caret does, and §8 covers the two blocks that are derived from an equation
> rather than being one.
>
> **Related:** [Data model §5.4](11-data-model-spec.md) · [File format](10-file-format-spec.md) · [Architecture §6](../04-architecture-overview.md)
>
> **Prior art:** UnicodeMath (Unicode Technical Note #28 v3.2, the format behind
> OneNote and Word's equation editor), LaTeX and AsciiMath. UnicodeMathML is
> MIT-adjacent and worth mining for build-up behaviour.

---

## 1. Design position

**Storage is canonical LaTeX**, in `{"latex": "…"}`. LaTeX is the most portable
and best-tooled semantic form. MathML is derived at export time for interchange
and accessibility, and **rendered output is never stored.**

**Input is multi-syntax, normalised on commit.** The Openote linear syntax of §3
is UnicodeMath-flavoured and is the OneNote experience; raw LaTeX is accepted
too, and AsciiMath may be later. All of them normalise to canonical LaTeX when a
construct builds up.

**Build-as-you-type.** Inside a maths region the editor parses the linear buffer
continuously and replaces completed constructs with their rendered form in place —
the maths analogue of rendering Markdown where it is typed. The tail that has not
yet committed stays visible as linear text at the caret.

**Rendering is native**, through `flutter_math_fork`, a KaTeX subset, so an
equation is a first-class canvas citizen at any zoom. A construct outside that
subset falls back to a source-styled chip rather than being lost silently.

### What is in and what is out

**Evaluation is in.** An expression works out to a number, a formula takes a
value for each variable it names, and `f(x)` plots as a curve (§8). Everything
here is arithmetic over a compiled expression: nothing is rearranged and nothing
is solved for an unknown.

**A CAS is out, and so is step-by-step working.** Showing how an answer was
reached is the part a student would most want to be right, and getting it wrong
is worse than not offering it. See the [vision's non-goals](../00-product-vision.md).

## 2. Entering and leaving maths

| | |
|---|---|
| `$…$` typed in a sentence, **Alt+=**, or the toolbar's Σ | an equation at the caret, inside the sentence |
| `$$` on its own line, or **Alt+Shift+=** | an equation on a line of its own |
| `Esc`, or the caret leaving the right edge | commit, and normalise to LaTeX |
| `Tab` / `Shift+Tab` | the next or previous box left to fill |
| `Backspace` at a construct's right edge | steps **inside** it — §5 |

Inside an equation, **`Ctrl+=` and `Ctrl+Shift+=` are a subscript and a
superscript**, which is worth stating because they are easily confused with the
`Alt+=` that starts one.

An equation left empty is swept when it is committed, so nothing is left behind
but the sentence.

## 3. The linear grammar (normative core)

In the tables below, `⟨op⟩` is an **operand**: one token, or a group in `(…)` or
`{…}`. Parentheses render and stretch to fit. **Braces group invisibly**, so
`1/{n+1}` is a fraction with `n+1` underneath and no braces on screen.

### 3.1 Tokens and autocorrect

**A control word autocorrects once a delimiter follows it**: `\alpha` → α,
`\infty` → ∞, `\times` → ×, `\cdot` → ⋅, `\sum` → ∑, `\int` → ∫, `\prod` → ∏,
`\sqrt` → √, `\to` → →, `\leq` → ≤, `\geq` → ≥, `\neq` → ≠, `\pm` → ±, `\in` → ∈,
`\subset` → ⊂, `\cup` → ∪, `\cap` → ∩, `\forall` → ∀, `\exists` → ∃,
`\partial` → ∂, `\nabla` → ∇, `\hbar` → ℏ, `\deg` → °, the whole Greek set, and
blackboard, script and fraktur letters through names like `\bbR`, `\scrL` and
`\frakg`.

Without the backslash the letters stay letters, so ordinary words survive being
typed inside an equation.

**The table ships as data**, so it can be extended without touching code — and
§4's palette is generated from the same table, which is what keeps the two in
step.

**Space and operator characters are the build triggers.** This is UnicodeMath's
load-bearing insight: a space after a complete construct builds it, and an
operator — `+ − = < >` and the rest — builds whatever precedes it.

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

**A trailing space ends the innermost open scope.** After `∑_(n=1)^∞`, a space
begins the summand; a second space, after the summand, closes the n-ary operator.
This matches UnicodeMath, and it is what makes linear entry feel like it knows
what you meant.

### 3.3 Precedence and ambiguity (normative)

`^` and `_` bind tighter than `/`, which binds tighter than juxtaposition.
An explicit group always wins.

`a/b/c` parses left-associative, as a fraction over `c`, but a chained `/`
SHOULD be hinted with a dim underline — to nudge towards grouping rather than
leaving the reading to chance.

**Unparseable input never blocks typing.** It stays linear until it parses.
Committing a region that still does not parse stores it as wrapped source text,
flagged for attention rather than silently mangled.

## 4. The palette and the keyboard (MATH-4)

**The palette is generated from the same tables as the grammar** — the autocorrect
table of §3.1 and the structures of §3.2. That is a hard rule, enforced by a
generated test, and it is what stops the palette and the syntax from drifting
apart.

*Structures* — fraction, script, radical, integral, n-ary, matrix, cases, accent,
delimiter — insert a linear **template with placeholder slots**, with the caret in
the first one and `Tab` cycling through the rest. *Symbols*, grouped into Greek,
operators, relations, arrows, sets and logic, and miscellaneous, insert a
character.

**Every entry shows its linear form on hover**, so the palette teaches the syntax
rather than replacing it.

## 5. Editing model

**A built construct is an atom to the caret.** `←` and `→` step into a fraction or
a root rather than over it; `↑` and `↓` move between the halves — numerator and
denominator, a power and an index, the rows of a matrix.

**Backspace at a construct's right edge steps inside it** and deletes from there.
It never removes a filled structure whole, and it never leaves undrawable TeX
behind. This supersedes an earlier "de-build back to linear form" rule, which was
measured wrong in three separate ways.

**Selection is a contiguous run of siblings in one row.** A fraction is taken
whole, never half. Make one with `Shift`+arrows, `Shift+Home`/`End`, `Ctrl+A`, or
the pointer: a click places the caret at the nearest atom boundary, a drag
highlights, `Shift`+click extends, and a double-click takes the atom underneath.
Copy and cut act on the highlight when there is one and on the whole equation when
there is not, and **copy always wraps in `$…$`** so that what lands on the
clipboard round-trips as maths — into Word, Overleaf or a message.

**An equation inside a sentence is edited in place**, by the same editor that
handles one on its own line. The caret crosses it in one step from outside; at its
edge, `←`/`→`, Backspace at the right and Delete at the left all step inside.
`Esc` or `Enter` finishes.

**Nesting is unlimited.** Layout follows the KaTeX box model, with the subset
caveat in §1.

### Angles are in degrees unless the angle says otherwise

`sin(30)` is a half. Radians are asked for by putting π in the angle, so
`sin(π/6)` is also a half, or by writing `rad`; a degree sign forces degrees. The
inverses — `sin⁻¹` and friends, which is how this app writes them — give an angle
back in degrees, so `sin⁻¹(0.5)` is 30 and `sin⁻¹(sin(30))` comes home.

There is no mode to set and nothing to remember: the angle itself says which it
is.

### An answer the app worked out is an object, not digits

Typing `=` then a space works out the run since the last `=` and writes the answer
down, boxed. It serialises as `\boxed{…}`, which is real LaTeX, so it exports and
round-trips — and the box is what distinguishes an answer the app computed from
one somebody typed. It is atomic to the caret.

Clicking it switches between a decimal and a fraction. The fraction is offered
when the *working* was fractional, and refused when there is nothing to switch to:
a whole number, or a decimal no tidy fraction reproduces.

## 6. Export and interchange

**Markdown** carries the LaTeX verbatim, as `$latex$` or `$$latex$$`.

**Import** recognises `$…$` and `$$…$$` from Markdown and from a paste. OneNote's
own maths arrives as MathML and is converted to LaTeX through the §3 grammar,
which is the deliberate dividend of choosing a UnicodeMath-compatible core.

**MathML export is specified and not built.** Deriving it from the stored LaTeX at
export time is the intended route — correctness over speed, since it runs only on
export — and the same derivation should feed screen readers. Today an equation
exports as LaTeX only, so a tool that wants MathML has to convert it itself.
Tracked in [the backlog](../planning/backlog.md).

## 7. Conformance test seed *(informative)*

Each of these MUST build, and MUST round-trip byte-identically to its canonical
LaTeX. They are the smallest set that exercises every structure in §3.2.

```
(x^2+4)/(x-3)                 ∑_(n=1)^∞ 1/n^2 = π^2/6     ■(1&2@3&4)
e^{-x^2/2}                    ∫_0^1 x^2 \dx = 1/3         √(2&x+1)
lim_(x\to 0) (sin x)/x = 1    \cases(x&x>0@-x&x≤0)        \abs(x)\leq\norm(v)
```

## 8. Blocks derived from an equation

Two block types hold an equation and something worked out from it. Both are
additive, so a reader that does not know them MUST round-trip them untouched;
their `content` shapes are in [data model §4](11-data-model-spec.md#4-block-types).

### 8.1 A plotted curve — the `graph` block

`latex` is plotted as `f(x)`, sampled across the window and drawn. `view` is that
window in graph coordinates, and it is **stored rather than derived** so that
panning and zooming are undoable and travel between devices. `fitY` true means
the vertical range is chosen to fit the curve; it goes false the moment somebody
moves the view by hand.

The evaluator is the one §1 already describes, compiled once into a closure over
the variable rather than re-parsed per sample. That is what makes a curve
affordable to redraw while it is being dragged.

**Angles follow §5's rule**, so a plot of `sin(x)` is in degrees unless the
expression says otherwise. One period therefore fits a window of 360, not 2π,
which is what a student plotting from a textbook expects.

### 8.2 An equation with values in it — the `substitute` block

`latex` holds the formula; `values` holds one typed value per variable the formula
names, keyed by variable name. The result is **named** — `v = 14`, not a bare
`= 14` — because a formula of several variables has no single obvious subject.

Variables are the free names in the expression, in the order they are written, and
they keep the case they were written in: `V = I·R` asks for `I` and `R`.

`value` is the pre-v1.0.2 spelling, a single string with no name attached. The
[file format spec's changelog](10-file-format-spec.md#changelog) says which to
read and when each is written; the short version is that `values` wins, and
`value` is kept up to date only while there is exactly one variable, so an older
release still shows a number rather than an empty field.

### 8.3 What neither of these does

Neither solves for an unknown. A `substitute` block binds values and evaluates; a
`graph` samples and draws. An equation with no value for one of its variables says
which variables it is waiting for, rather than guessing or rearranging.

---

*The grammar above is the v1 core: large equations, n-ary operators with their
limits in the right place, and operator shortcuts, all implementable over
`flutter_math_fork`. Chemistry, units and theorem environments ride later minor
revisions — ranked in [v0.21](../planning/v0.21-outdo-onenote-maths.md).*
