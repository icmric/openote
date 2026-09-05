# Contributing to Openote

Thank you for your interest in Openote — an open-source, cross-platform alternative to Microsoft OneNote, built so that no one is ever locked into their notes again.

> **Current phase: implementation.** There is a working desktop app — Flutter/Dart in [`app/`](app/README.md) plus a native Rust core in [`rust/onote_core/`](rust/onote_core/README.md). Start with [`app/README.md`](app/README.md) to build and run it, and read [`INTEGRATION.md`](rust/onote_core/INTEGRATION.md) (including its **stale-DLL warning**) before touching the core. Design critique on [`docs/`](docs/README.md) is still very welcome.
>
> **Before submitting code:** `flutter analyze` must be clean of errors and warnings, `flutter test` (1,071 tests) and `cargo test` (53 tests) must pass, and `cargo clippy --all-targets` must be clean. Match the surrounding comment density — this codebase explains *why*, not *what*.

> **Never assert on wall-clock time.** `flutter test` runs test files in
> parallel, so a `Stopwatch` bar measures how much CPU the machine had going
> spare — it passes alone, fails in a full suite, and fails *every* time on a
> two-core CI runner. This has taken CI down twice: once on a study-cache ratio,
> once on four per-keystroke bars and an import-progress ratio, each while the
> code under test was working perfectly.
>
> Count the work instead, on the one code path the change exists to alter:
> `Repository.debugSharedPageReads`, `Repository.debugPageDecodes`,
> `OpLogStore.debugDirectoryListings` and
> `ImportWriterHandle.debugMeasureRequests` all exist for this. A working cache
> adds zero and a broken one adds hundreds, and neither answer moves with the
> weather.
>
> **Pair every `expect(count, 0)` with a test that makes the same counter move.**
> A counter watching the wrong layer reads zero for the wrong reason, and the
> guard is then worthless while looking strict — which is exactly what happened
> the first time these were converted.
>
> Wall-clock is equally untestable in *product* code that a widget test drives:
> the sidebar's double-click window uses an injectable `sidebarNow` for the same
> reason.
>
> **A timeout is the one number that should be generous.** It is a hang guard,
> not a performance bar, so it must clear the slowest machine that will ever run
> it. The `test` package's 30-second default is chosen for an ordinary unit
> test; a case that spawns real subprocesses (the git suites run `init`,
> `config`, `clone`, `commit`, `push`) takes 20 s on an idle sixteen-core
> machine and simply does not fit. Those files carry
> `@Timeout(Duration(minutes: 3))`, and the failure it prevents is the nastiest
> kind: intermittent, one platform, one test at a time, reported as
> "TimeoutException after 0:00:30" with nothing in it about git.

> **Reproducing a CI-only failure: constrain the cores, don't add load.** GitHub
> runners have about two. Piling burner threads onto a sixteen-core box does not
> emulate that — the suite passed sixteen burners deep and still failed on CI.
> Pinning the test process to two cores reproduced it on the first run
> (`$p.ProcessorAffinity = [IntPtr]3` around `flutter test`), and turned one
> intermittent failure into six deterministic ones.

> **Licensing is ratified** ([ADR-0005](docs/adr/ADR-0005-licensing.md), 2026-07-27): **AGPL-3.0-or-later** for the app, **Apache-2.0** for `onote_core`, **CC0-1.0** for the format specs. Contributions are accepted under the licence of the directory they touch. See [LICENSING.md](LICENSING.md) — and note the invariant that **`onote_core` must never gain a copyleft dependency**.

## Ways to help right now

**1. Read and critique the plans.** The [documentation set](docs/README.md) — vision, teardown, PRD, technology evaluation, architecture, and style guide — is where the project is being shaped. Open an issue if you:
- disagree with a decision or spot a flaw in the reasoning,
- know of prior art (an app, a format, a library) we should learn from,
- have hands-on experience with one of the hard problems below.

**2. Bring domain expertise.** Openote sits at the intersection of several genuinely hard areas. If you have real experience with any of these, your input is especially wanted:
- **Flutter canvas & ink pipelines** (infinite-canvas performance, viewport culling, `perfect_freehand`-style stroke rendering)
- **Rich-text / block editing** on a canvas (ProseMirror/Lexical/BlockSuite, or native text engines)
- **CRDTs & local-first sync** (Yjs/`yrs`, Loro, Automerge; E2E-encrypted sync)
- **Math input & rendering** (UnicodeMath/LaTeX/MathML, KaTeX/MathJax/MathLive)
- **Open file-format design** and long-term data durability
- **Flutter, Qt, or the other candidate frameworks** — especially real ink/text experience
- **Accessibility** on custom-drawn canvases

**3. Review the decisions.** The major technical decisions are recorded as [Architecture Decision Records](docs/adr/README.md) — framework (Flutter + Rust core), CRDT (Loro), storage container (SQLite `.onote`), editor engine (keep the engine we own, behind a swappable seam), licensing (proposed), and the sync storage layout (proposed). Each documents its revisit triggers; reasoned challenges backed by evidence are welcome.

**4. Prototype a spike.** The remaining open work is spike-shaped: the editor-engine bake-off ([ADR-0004](docs/adr/ADR-0004-editor-engine.md)), the first-party canvas core, the Saber-style ink pipeline feel-check, and the Loro-via-FFI round-trip benchmark. If you want to build one, say so in an issue — spike evidence settles arguments here.

**5. Translate Openote.** This is the one job that needs no Dart at all. Copy `app/lib/l10n/app_en.arb` to `app/lib/l10n/app_<code>.arb`, translate the values, drop the `@` description entries (those belong to the English template), and run `flutter gen-l10n` from `app/`. Nothing else changes — the list of supported languages is generated from the files present, and any message you leave out falls back to English, so a partial translation is a useful contribution rather than a broken build.

Openote already ships in German, Spanish, French, Italian, Portuguese and
Simplified Chinese, and picks a language from the computer's own settings
without asking, so a new `.arb` is live for its speakers the moment it lands.

Two things to know before you start. The English `.arb` is still growing: the
welcome flow, the toolbars, the navigator, the insert catalogue and Settings
read their words from it, but several dialogs (sync, AI access, the planner and
study panels) are still Dart string literals — the order they are being
converted in is in [v0.24 §1](docs/planning/v0.24-road-to-1.0.md). And every
message carries an `@` entry describing where it appears and what any
placeholder holds; read it, because it is the only context you get, and it is
where "this is a Windows menu path", "this is a file extension, leave it alone"
and "keep this under 31 characters or it falls off the edge of the toolbar" are
written down.

## Principles contributions are held to

Every contribution is weighed against the project's [design principles](docs/00-product-vision.md#5-design-principles) and [non-goals](docs/00-product-vision.md#9-non-goals). In short:

- **Openness is non-negotiable.** No feature may compromise the open, documented, local-first format or lock users in.
- **The canvas is sacred.** Freeform placement, fast startup, and responsive ink come first — and we deliberately don't trade startup speed or consistency for micro-latency ink tricks.
- **We don't overreach.** Openote is a notebook, not an office suite, task manager, or AI product. Scope discipline is a feature.
- **Accuracy matters.** We describe competitors and technical trade-offs precisely, even when a looser claim would be more flattering.

## How to propose changes

1. **Open an issue** describing the idea/problem before large work — it saves everyone effort and invites discussion.
2. For **documentation edits**, small corrections can go straight to a pull request; larger structural changes should start as an issue.
3. Keep discussion **respectful and constructive.** We assume good faith and expect the same.
4. When code begins, this guide will add: dev environment setup, coding standards, testing requirements, commit/PR conventions, and a code of conduct.

## Communication

- **Issues** — proposals, bugs (later), and design discussion.
- **Discussions** (when enabled) — open-ended questions and ideas.
- A **Code of Conduct** will be adopted alongside the first code contributions.

## Licensing of contributions

**Inbound = outbound**, with a [Developer Certificate of Origin](https://developercertificate.org/) sign-off rather than a CLA. Sign your commits:

```bash
git commit -s -m "your message"
```

That adds a `Signed-off-by:` line certifying you have the right to submit the work under the project's licence — AGPL-3.0-or-later for the app, Apache-2.0 for `onote_core`, CC0-1.0 for `docs/specs/` ([ADR-0005](docs/adr/ADR-0005-licensing.md), [LICENSING.md](LICENSING.md)). There is deliberately no CLA: it would buy the project an option to relicense that we are not preserving. Contributors will be credited.

## Releasing

Full runbook: [docs/RELEASING.md](docs/RELEASING.md). The one rule that has
already broken two releases, stated here so it is findable:

**Bump `app/pubspec.yaml`, commit, and _push to master_ — then tag.** The
release workflow compares the tag against the pubspec version on the tagged
commit and refuses to build if they disagree. Tagging first, or committing the
bump on a feature branch, fails the run before any platform job starts.

---

*Openote is being built in the open, deliberately and carefully, so that it's worth trusting with your notes. Thanks for helping make that real.*
