# Contributing to Openote

Thanks for your interest. Openote is an open-source cross-platform alternative to Microsoft OneNote, built so nobody is ever locked into their notes again.

There is a working desktop app: Flutter/Dart in [`app/`](app/README.md) plus a native Rust core in [`rust/onote_core/`](rust/onote_core/README.md). Start with [`app/README.md`](app/README.md) to build and run it, and read [`INTEGRATION.md`](rust/onote_core/INTEGRATION.md) — including its stale-DLL warning — before touching the core. Design critique on [`docs/`](docs/README.md) is welcome too.

## Before submitting code

`flutter analyze` clean of errors and warnings, `flutter test` and `cargo test` passing, `cargo clippy --all-targets` clean.

**Comments explain why, not what.** Lead with one line saying what the thing is for. Then the contract a caller needs and any invariant that is not obvious from the code. Put a comment about one edge case *at* that case, not at the top of the file.

What does **not** belong in a comment: measurements, a quote from a bug report, the history of what the code used to be, or an argument against an approach that was not taken. All four are worth recording — in the commit message, or in the planning document for the release. Keeping them next to the code means the same fact exists in two places that can disagree, and it is the code's copy that goes stale.

### Writing tests

**Never assert on wall-clock time.** `flutter test` runs files in parallel, so
a `Stopwatch` bar measures how much CPU the machine had spare. It passes
alone, fails in a full suite, and fails every time on a two-core CI runner.
This has taken CI down twice while the code under test was working perfectly.

Count the work instead, on the one path your change exists to alter.
`Repository.debugSharedPageReads`, `Repository.debugPageDecodes`,
`OpLogStore.debugDirectoryListings` and `ImportWriterHandle.debugMeasureRequests`
exist for this: a working cache adds zero and a broken one adds hundreds,
and neither answer moves with the weather. Product code that a widget test
drives needs the same treatment — the sidebar's double-click window takes an
injectable `sidebarNow`.

**Pair every `expect(count, 0)` with a test that makes the same counter move.**
A counter watching the wrong layer reads zero for the wrong reason, and the
guard is then worthless while looking strict.

**A timeout is a hang guard, not a performance bar**, so make it generous
enough for the slowest machine that will ever run it. The 30-second default
suits an ordinary unit test; a file that spawns real subprocesses — the git
suites run `init`, `config`, `clone`, `commit`, `push` — takes 20 s on an idle
sixteen-core machine and does not fit. Those carry
`@Timeout(Duration(minutes: 3))`. The failure this prevents is the nastiest
kind: intermittent, one platform, one test at a time, reported as
"TimeoutException after 0:00:30" with nothing in it about git.

**Never put a control character in a source file.** Ripgrep treats a file holding
one as binary and skips it, so the file becomes invisible to every code search —
which is how nine hundred lines of one widget hid from the audits looking for
defects in it. The trap is a backslash escape typed through a shell that
interprets it — `\frac` arrives as a form feed followed by `rac`, and
`\alpha` as a bell followed by `lpha`. Write `\u000c` if you genuinely need one.
`test/source_hygiene_test.dart` enforces this over `lib/` and `test/`.

**To reproduce a CI-only failure, constrain the cores rather than adding**
**load.** GitHub runners have about two. Burner threads on a sixteen-core box
do not emulate that — the suite passed sixteen burners deep and still failed
on CI. Pinning the test process to two cores
(`$p.ProcessorAffinity = [IntPtr]3` around `flutter test`) reproduced it on
the first run and turned one intermittent failure into six deterministic ones.

One invariant worth knowing before you add a dependency: **`onote_core` must
never gain a copyleft one.** It is Apache-2.0 so that any tool, including a
closed one, can read and write `.onote` files — see
[LICENSING.md](LICENSING.md).

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
- **Accessibility** on custom-drawn canvases — the editor's semantics tree is
  rejected by the Windows bridge today, which is the single worst defect we have

**3. Review the decisions.** The major technical decisions are recorded as
[Architecture Decision Records](docs/adr/README.md), each with the context, the
options weighed, and explicit revisit triggers. A reasoned challenge backed by
evidence is welcome — several of these are marked provisional precisely because
they should be reopened if the evidence changes.

**4. Run a build nobody has run.** The most useful thing anyone with a Mac or
a Linux machine can do: CI builds all three platforms on every push, and only
Windows has been used by a human. Launch it, import a PDF (pdfium is a
per-platform native binary and the likeliest thing to fail differently), draw
something, sync a notebook between two machines, and open an issue about
whatever went wrong. Same for ink on real stylus hardware — pressure, tilt,
palm rejection and the barrel button cannot be tested headlessly.

**5. Translate Openote.** This is the one job that needs no Dart at all. Copy `app/lib/l10n/app_en.arb` to `app/lib/l10n/app_<code>.arb`, translate the values, drop the `@` description entries (those belong to the English template), and run `flutter gen-l10n` from `app/`. Nothing else changes — the list of supported languages is generated from the files present, and any message you leave out falls back to English, so a partial translation is a useful contribution rather than a broken build.

Openote already ships in German, Spanish, French, Italian, Portuguese and
Simplified Chinese, and picks a language from the computer's own settings
without asking, so a new `.arb` is live for its speakers the moment it lands.

Two things to know before you start. The English `.arb` is still growing: the
welcome flow, the toolbars, the navigator, the insert catalogue and Settings
read their words from it, but several dialogs (sync, AI access, the planner and
study panels) are still Dart string literals — the order they are being
converted in is in [v0.24 §1](docs/planning/archive/v0.24-road-to-1.0.md). And every
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

## Branches

`master` is the released branch — it should always be what the latest published
release was cut from. Work does not land on it directly.

```
master                  ← releases only, tagged from here
  └── v1.0.2            ← one branch per patch/minor release
        ├── feature-a    ← one branch per piece of work
        └── feature-b
```

- **A release branch per version**, named for it: `v1.0.2`.
- **A branch per piece of work**, off the release branch, merged back into it.
- **The release branch merges into `master`** when the release is ready, and
  the tag is cut there — see [docs/RELEASING.md](docs/RELEASING.md), which
  assumes you are on `master` for good reasons it explains.

The default branch is `master`, not `main`. It is not being renamed: people
have the repository cloned now, and a rename breaks their remotes and any open
pull request for no benefit.

## Releasing

Full runbook: [docs/RELEASING.md](docs/RELEASING.md). The one rule that has
already broken two releases, stated here so it is findable:

**Bump `app/pubspec.yaml`, commit, and _push to master_ — then tag.** The
release workflow compares the tag against the pubspec version on the tagged
commit and refuses to build if they disagree. Tagging first, or committing the
bump on a feature branch, fails the run before any platform job starts.

---

*Openote is being built in the open, deliberately and carefully, so that it's worth trusting with your notes. Thanks for helping make that real.*
