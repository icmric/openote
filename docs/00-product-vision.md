# Openote — Product Vision

> **Document status:** v1.0 · **Implementation phase** · Last updated 2026-08-05
> **Still accurate.** This document has needed no correction as the app was
> built — the problem statement, the six principles and the non-goals all held.
> The only note worth adding: principle §5.6 ("the interface is calm… we favor a
> clean surface over a crowded ribbon") is the one the 2026-08 UI review found
> the *implementation* falling short of, not through clutter but through
> inconsistency. See [v0.6 — the UI revamp](planning/v0.6-ui-revamp.md).
> **Owner:** Eric · **Audience:** Core team, contributors, prospective collaborators
> **Related documents:** [OneNote Teardown & Gap Analysis](01-onenote-teardown.md) · [Product Requirements](02-product-requirements.md) · [Technology Evaluation](03-technology-evaluation.md) · [Architecture Overview](04-architecture-overview.md) · [Style Guide](05-style-guide.md)

---

## 1. The one-sentence version

**Openote is a free, open-source, natively cross-platform notebook application that gives you OneNote's freeform canvas, handwriting, and math — without locking your notes inside a proprietary format or a single vendor's cloud.**

---

## 2. Why we are building this

Microsoft OneNote is, for a large class of users, the best freeform note-taking tool ever made. Its infinite canvas, its notebook/section/page hierarchy, its handwriting and its math input remain genuinely unmatched — no competitor with a serious organizational model has replicated the experience of clicking anywhere on an unbounded page, dropping a text box, and dragging it wherever it belongs, while a pen writes equations in the margin.

And yet OneNote carries structural problems that Microsoft has shown little interest in fixing, because they are not bugs — they are the business model:

- **Your notes are trapped.** The `.one` / `.onepkg` format is a binary revision store that, in practice, only OneNote can read. On the free tier you cannot even keep a purely local copy; your data lives on OneDrive by default. Getting notes *out* — cleanly, losslessly, with ink and tags intact — ranges from painful to impossible.
- **It is tethered to one ecosystem.** There is no native Linux client. Feature parity across Windows, Mac, iPad, Android and web is uneven — page templates, find-and-replace, password protection and local notebooks each go missing on some platform.
- **Key capabilities are paywalled.** Solving and step-by-step math require an Enterprise or Education Microsoft 365 subscription. Creating local notebooks requires a paid Office license. AI features require a Copilot license.
- **The things people ask for never arrive.** Native Markdown, an open file format, backlinks, syntax-highlighted code, a Linux client — these are perennial, well-documented requests that Microsoft has repeatedly declined.

The result is a market with a clear, persistent gap. There are excellent open note apps (Joplin, Logseq, Standard Notes), excellent open canvases (Excalidraw, tldraw), and excellent open ink apps (Xournal++, Saber) — but **no open, cross-platform application combines all four of: a freeform infinite canvas, first-class pen/handwriting and math, a real notebook hierarchy, and an open, durable file format.** That intersection is exactly where OneNote lives, and exactly where it is most vulnerable.

Openote exists to occupy that intersection — and to do it in the open, so that no future user is ever locked in again.

---

## 3. Vision statement

> A world where your handwritten notes, diagrams, equations and ideas are yours — readable a decade from now, editable on any device and any operating system, in a format anyone is free to build on. Openote aims to be the notebook that earns its place not by locking you in, but by being good enough that you never want to leave — and open enough that you always could.

---

## 4. Mission

Build a professional-grade, natively cross-platform notebook application that:

1. **Matches OneNote's core experience** — freeform canvas, notebook/section/page organization, rich text, pen, and math.
2. **Fixes OneNote's structural failings** — an open, documented file format; true local-first ownership; optional (not mandatory) cloud sync; and genuine platform parity, Linux included.
3. **Adds what power users have always wanted** — inline-rendered Markdown, backlinks, **live page embeds** (render part of one page inside another, always up to date — where OneNote offers only a bare navigation link), proper code blocks, clean import/export.
4. **Stays open by construction** — an open-source license, a publicly specified file format, and an architecture others can extend.

---

## 5. Design principles

These principles are the tie-breakers. When two features conflict, or a shortcut tempts us, these decide.

### 5.1 Your data is yours
The file format is open, documented, and versioned from day one. Notes are stored locally by default. Nothing about the format requires Openote, our servers, or our continued existence to read. If the project disappeared tomorrow, your notes would still open. **Openness is not a feature we add later; it is a constraint we design under.**

### 5.2 Local-first, cloud-optional
The application is fully functional offline, on a single device, with no account. Sync is something you turn *on*, not something you must escape. When you do sync, you choose where — our optional service, your own server, or a folder in a cloud drive you already pay for.

### 5.3 The canvas is sacred
OneNote's signature is the freeform page: click anywhere, place anything, drag it where it belongs. This is the hardest thing to get right and the easiest thing to compromise. We protect it. Panning, zooming, fast startup, and responsive ink are first-class performance requirements, not afterthoughts — though we deliberately rank *startup speed, consistency, and feature richness* above chasing the last few milliseconds of pen latency (see §10).

### 5.4 Interpret, don't interrupt
Formatting should happen where you type it. Markdown renders in place as you write it; math builds up from linear input as you complete it; the tool gets out of the way. No mode-switching between a "source" view and a "rendered" view for everyday writing.

### 5.5 Native feel on every platform
We are cross-platform, but not lowest-common-denominator. The pen must feel like a pen. Desktop keyboard shortcuts must feel native. Text input, accessibility, and platform conventions are respected, not bridged reluctantly.

### 5.6 Professional, quiet, and out of the way
The interface is calm. The chrome recedes so the page can be the focus. Power is available but not thrust in your face. We favor a clean surface over a crowded ribbon.

### 5.7 Extensible by design
An open format invites an ecosystem. We design the data model, the import/export paths, and (eventually) a plugin surface so that others can build importers, exporters, renderers, and integrations we never thought of.

---

## 6. Who this is for

**Primary personas (v1 focus):**

- **The switcher.** A long-time OneNote user — a student, researcher, engineer, or knowledge worker — who loves the freeform canvas but is frustrated by lock-in, sync problems, or the lack of a Linux client. They need a migration path and a familiar mental model.
- **The open-source native.** Someone who already lives in Obsidian, Logseq, or Joplin and owns their files, but misses a true freeform canvas and real pen/math support. They value the open format above almost everything.
- **The pen-and-math thinker.** A STEM student, mathematician, or engineer who thinks in equations and diagrams, works on a tablet or convertible (iPad, Surface, Android tablet), and wants OneNote-grade ink and equation entry without the subscription gates.

**Secondary personas (post-v1):**

- Small teams who want to collaborate on shared notebooks without handing their data to a third party.
- Educators and institutions wanting a notebook tool they can self-host and that runs on Linux lab machines.

**Explicitly not our first audience:** enterprise deployments requiring Microsoft 365 governance, users who want a task manager or a full project-management suite, and users who primarily want a linear document editor (Word/Google Docs territory).

---

## 7. Positioning

|                        | **Openote** | OneNote | Obsidian | AFFiNE | Joplin | Xournal++ |
|------------------------|:-----------:|:-------:|:--------:|:------:|:------:|:---------:|
| Freeform infinite canvas | ✅ | ✅ | Plugin | ✅ | ❌ | Page-based |
| Notebook/section/page hierarchy | ✅ | ✅ | Folders | Workspace | Notebooks | Files |
| First-class pen/handwriting | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ |
| Math entry & rendering | ✅ | ✅ (paywalled solve) | LaTeX | LaTeX | LaTeX | LaTeX tool |
| Inline-rendered Markdown | ✅ | ❌ | ✅ | Blocks | ✅ | ❌ |
| **Open, documented format** | ✅ | ⚠️ documented, impractical | ✅ (MD) | ⚠️ open-core | ✅ (MD) | ✅ (XML) |
| Local-first, cloud-optional | ✅ | ❌ (cloud-default) | ✅ | ✅ | ✅ | ✅ |
| Native Linux client | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ |
| Fully open-source app | ✅ | ❌ | ❌ (freeware) | ⚠️ open-core | ✅ | ✅ |
| Cost of full features | Free | Subscription tiers | Freemium | Freemium | Free | Free |

> Legend: ✅ yes / first-class · ⚠️ partial or caveated · ❌ no. See the [Teardown](01-onenote-teardown.md) for the detail behind each OneNote cell and [Landscape notes](01-onenote-teardown.md#8-competitive-landscape) for competitors.

**Our position in one line:** *OneNote's experience, Obsidian's openness, on every platform.*

The competitive insight is that our two nearest rivals each concede half the field. OneNote owns the experience but not the openness. Obsidian (and the FOSS Markdown crowd) own the openness but not the canvas-and-ink experience. AFFiNE comes closest architecturally — a unified docs-plus-canvas model — but has no real handwriting, an open-*core* (not fully open) server, and a reputation for instability. Nobody is standing where we intend to stand.

---

## 8. What success looks like

Success is not "beat Microsoft." Microsoft has 500M+ installs and infinite runway. Success is **being the obvious answer to a specific, currently-unanswerable question**: *"What do I use instead of OneNote if I want to own my notes and run on Linux?"* Today there is no clean answer. Openote intends to be it.

Concretely, over the horizons below:

- **Near term (MVP):** a OneNote user can install Openote on Windows, macOS or Linux, create a notebook, write and draw freely on an infinite canvas, type math, and know their notes live in an open file on their own disk.
- **Medium term:** they can sync those notes across their own devices, import their existing OneNote content without losing ink or structure, and use a stylus on a tablet with near-native latency.
- **Long term:** small teams collaborate in real time on shared notebooks; a community builds importers, exporters, and plugins around a published, stable file-format specification; and "Openote format" becomes a recognized, safe place to keep notes for the long haul.

*(Detailed, phased scope and prioritization live in the [Roadmap](../ROADMAP.md) and [PRD](02-product-requirements.md). This document deliberately stays at the level of intent.)*

---

## 9. Non-goals

Saying no is how the canvas stays sacred and the schedule stays real. For the foreseeable future, Openote is **not**:

- **A OneNote clone down to the pixel.** We copy what is excellent (the freeform model, the hierarchy, ink, math) and deliberately improve or drop what is not (the cluttered ribbon, the cloud tether, the format).
- **A math *solver* or CAS.** Like OneNote's underlying editor, we make it easy to *write* complex equations beautifully. We do not commit to *solving* them in v1. (This keeps us out of a very deep well and focuses effort on the entry/rendering experience users actually asked for.)
- **A full office suite, task manager, or PM tool.** We are a notebook. Integrations can come later; scope creep into project management will not.
- **A cloud service you must use.** Sync is optional infrastructure, never the product's center of gravity.
- **An AI product.** We are not chasing an AI-first positioning. AI-assisted features, if any, come far later and remain optional.
- **A handwriting-recognition research project.** v1 stores ink losslessly and renders it beautifully; recognition (ink-to-text, ink-to-math) is a later, optional layer, not a launch blocker. There is, honestly, no mature fully-open cross-platform online handwriting recognizer today — we will not architect as though one exists.

---

## 10. Guiding constraints and known hard problems

We enter this with eyes open. Three problems are genuinely hard and will shape every downstream decision:

1. **Rich text on a freeform canvas.** Cross-platform UI frameworks have famously weak rich-text/editing stories, and our text lives *on* a zoomable canvas rather than in a scrolling document — which rules out the easy "embed a web editor" shortcut. This is our single biggest technical risk. See the [Technology Evaluation](03-technology-evaluation.md).
2. **Craft under constraint.** The stakeholder's priorities are explicit: fast startup, cross-platform consistency, and a rich feature set come first; ink must feel good, but we do not trade any of those for marginal pen-latency gains (near-native "pen-on-glass" latency is a stated non-goal). The discipline is holding that line — refusing per-platform complexity that buys little.
3. **An open format that survives collaboration.** Real-time collaboration pushes toward opaque CRDT binaries; openness pushes toward inspectable, documented files. Reconciling the two — a CRDT-native document that also exports to a clean, published, open format — is a central design problem, not a detail. (Live cross-page embeds add a second wrinkle: stable identity and cross-document references must be designed in from the first byte. See the [Data Model Spec](specs/11-data-model-spec.md).)

None of these is a reason not to build. All three are reasons to plan carefully before we write a line of application code — which is exactly what this documentation set is for.

---

## 11. The name

**Openote** = **Open** + **note**. It says the two things that matter most in one word: it is *open*, and it is for *notes*. Read another way — "Open Note" — it is also an instruction and an invitation. Brand direction, wordmark, and voice are specified in the [Style Guide](05-style-guide.md).

---

*This is a living document. As research turns into decisions and decisions into code, the vision should be revisited — but its core commitments (open format, local-first, freeform canvas, cross-platform parity) are the fixed points the rest of the project is measured against.*
