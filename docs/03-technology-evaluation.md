# Technology & Framework Evaluation

> **Document status:** v1.0 · **Decision made and validated in code** · Last updated 2026-07-22, reviewed 2026-08-05
> The Flutter + Rust choice (ADR-0001) has now been exercised on the hard cases
> this evaluation worried about — rich text on a zoomable canvas, ink latency,
> a reverse-engineered binary importer in Rust over FFI — and held. The one
> prediction that came true as written: "cross-platform frameworks give you
> consistency but you must build the design system yourself." Flutter's stock
> Material is *mobile* Material; leaving it unthemed is what the 2026-08 UI
> review found. See [v0.6](planning/v0.6-ui-revamp.md).
> **Purpose:** A balanced, evidence-based evaluation of cross-platform application frameworks and enabling technologies for Openote — the trade-off map behind the decision.
> **Related:** [PRD](02-product-requirements.md) · [Architecture Overview](04-architecture-overview.md) · [ADR-0001](adr/ADR-0001-application-framework.md)
> **Decision status:** **DECIDED (provisional) — Flutter/Dart UI with a Rust core**, ratified in [ADR-0001](adr/ADR-0001-application-framework.md). v0.1 of this document was deliberately balanced and left the call open, hinging on whether near-native ink latency was a hard requirement. The stakeholder has since clarified priorities — **startup speed, cross-platform consistency, and feature richness rank above pen latency; a slight ink delay is acceptable** — which resolves the central tension (§1) decisively. The v0.1 analysis is preserved below with §6–§9 revised to reflect the decision and the concrete stack that follows from it.

---

## 1. The decision that dominates everything

Before comparing frameworks, understand the one tension that decides the project. Openote's hard requirements pull in **opposite directions**, and no framework wins both ends:

- **Content richness — rich text, inline Markdown, math, sync/collaboration — pulls toward *web* rendering.** The most mature rich-text technology in existence is the web editor ecosystem (ProseMirror, Lexical, TipTap, BlockSuite, CodeMirror 6). Math (KaTeX/MathJax/MathLive) and CRDT collaboration (Yjs with ready-made editor bindings) are effectively *solved* there.
- **Canvas control and low-latency ink pull toward *native-drawn* rendering.** A custom infinite canvas and a pen that feels like a pen want direct control of the render pipeline, which webviews structurally cannot give.

Making this harder: in Openote, **text objects live *on* the zoomable canvas** (free-floating containers), not in a scrolling document. That rules out the usual comfortable compromise — a native shell with an embedded web editor *pane* — because you cannot practically put one webview per floating text box on a pannable canvas, nor freely transform a webview with the scene.

So the framework question is really a **strategic posture** question. Three coherent postures exist; §6 lays them out. Everything else is detail in service of that choice.

> **How the tension resolved (v0.2).** The stakeholder's clarified priorities changed the weights, not the facts. With near-native pen latency demoted from "must" to "nice" — ink remains a required *feature*, but a modest input delay is acceptable — the strongest argument for the heavier native-ink postures (per-platform front-buffer overlays, Qt's tablet stack) loses its force. Meanwhile the newly elevated priorities cut hard against the web postures: **startup speed** penalizes Electron (1.5–3 s cold starts and 100–200 MB bundles for nontrivial apps, vs. sub-second AOT Flutter — see §7), and **consistency** penalizes Tauri (three different webview engines across our own target platforms, with WebKitGTK on Linux the documented weak link). Flutter — one bundled renderer, pixel-identical everywhere, fast AOT startup, team familiarity, and proof (Saber) that its standard pipeline delivers acceptable ink — is left as the posture-A candidate that *also* wins on the new top priorities. That is the decision in [ADR-0001](adr/ADR-0001-application-framework.md).

---

## 2. Two structural facts to internalize first

### 2.1 Low-latency ink is a rendering-architecture problem, not a checkbox

Native "pen-on-glass" feel (~9–20 ms) comes from three OS-level techniques, **none of which cross-platform UI toolkits provide by default:**

1. **Front-buffer / direct-to-screen rendering** — the wet stroke is drawn straight to the framebuffer, bypassing the compositor, then committed on pen-up. (Android `GLFrontBufferedRenderer`; Apple PencilKit; Windows DirectInk.) Only valid for small dirty regions — never for panning/zooming.
2. **Motion prediction** — a predictor synthesizes 1–2 future points so the stroke tip "reaches ahead" of the pen. (Android `MotionEventPredictor`; Apple `predictedTouches`; web `PointerEvent.getPredictedEvents()`.)
3. **Unbuffered high-rate input** — pens sample at 240–400 Hz while displays refresh at 60–120 Hz; you must consume coalesced events to draw smooth curves.

**Consequences:**
- **Own-canvas toolkits** (Flutter, Compose, Qt, Avalonia) render ink through their own compositor at vsync → ~1–2 frames of latency *unless* you special-case a native front-buffer overlay. **Qt gets closest to native out of the box** (this is how Krita achieves pro-grade pen feel).
- **Webview toolkits** (Tauri, Electron) are structurally furthest from native — pointer events cross the browser event loop and compositor, with no front-buffer access. Chromium (Electron; Tauri on Windows/Android) has predicted/coalesced events; **WebKit (macOS/iOS/Linux WebKitGTK) support is weaker and inconsistent.**
- **The escape hatch for any framework:** embed the *platform's own* ink surface (PencilKit / Windows Ink / Android low-latency layer) as a native overlay, and use the framework for everything else. Doable in Flutter/Compose/Qt/Tauri — but it is **per-platform work you build and maintain**, and blending it with a zoomable canvas (the pen surface must transform with the scene) is genuinely fiddly.

> ⚠️ **Honesty flag:** Per-framework ink-latency numbers are essentially unpublished. The native-vs-webview ordering above is *architectural reasoning, not benchmarks*.
>
> **Status note (v0.2):** this section is retained for the record, but its stakes have dropped. Per stakeholder direction, near-native pen latency is a **non-goal**: Flutter's ordinary pointer-event → compositor pipeline (the Saber approach) is the accepted baseline, and none of the OS-level techniques above are planned. The ink spike is now a *validation* exercise (confirm Saber-quality feel on our canvas), not a decision gate.

### 2.2 Rich text on a canvas is the known hard spot — and why "just embed a web editor" fights this product

- **Every own-canvas framework has an immature rich-text/block editor.** You will build (or heavily assemble) a text engine on your canvas, or accept limits. Details per framework in §5.
- **The web editor ecosystem is the mature option** — but the tempting hybrid (native shell + embedded web editor) works well only when text is a *document pane*, not a free-floating canvas object. For our canvas, the hybrid's benefit largely evaporates. This pushes you to a fork:
  - **All-web rendering** (Electron/Tauri): canvas *and* text both in the webview, one coordinate system — the **AFFiNE / BlockSuite** model (edgeless canvas + rich blocks + Yjs collaboration, all web). You inherit the webview ink ceiling.
  - **All-native rendering** (Flutter/Compose/Qt/Avalonia): you own the hard text/IME/rich-text problem, but get full ink and canvas control.

**BlockSuite is the closest existing reference architecture to Openote** (infinite/edgeless canvas + block rich text + Yjs collaboration in one model) — strong evidence the web stack can do the *content* side coherently, at the price of committing to web rendering and its ink ceiling.

---

## 3. How we score (the axes that matter for Openote)

Axes are listed in **priority order (v0.2, per stakeholder direction)** — the reordering relative to v0.1 (ink demoted; startup and consistency promoted) is what tips the decision.

| Axis | Why it matters here |
|------|--------------------|
| **Startup speed** | Top-ranked stakeholder priority (PLAT-4): cold start ≤ 2 s to an editable page. |
| **Cross-platform consistency** | Second-ranked: identical behavior/rendering on Win/macOS/Linux; no per-platform surprises. |
| **Feature richness & velocity** | Third-ranked: rich text, math, embeds, canvas — features over micro-latency. |
| Infinite-canvas control | Requirement zero (CANVAS-*). |
| Rich text + inline Markdown | Known hard spot (TEXT-*). |
| Math rendering/editing | MATH-*; web ecosystem is far ahead. |
| Sync/collab (CRDT) readiness | SYNC-*; editor bindings save enormous work. |
| **Linux desktop story** | First-class target and a wedge (PLAT-1). |
| Tablet/pen story | Close-second platform priority (PLAT-2). |
| Comfortable ink | Required feature (INK-1–6) — but near-native latency is a non-goal (INK-3). |
| Text/IME/accessibility | PLAT-5/6; weak in some own-canvas toolkits. |
| Ecosystem, language, license | Velocity, hiring, and open-source fit. |
| Team familiarity | Stakeholder knows Flutter — real velocity. |

---

## 4. At-a-glance comparison

Ratings are **relative to Openote's specific needs**, not general quality. ●●● strong · ●●○ adequate · ●○○ weak. Read alongside the per-framework detail in §5 — a single ●○○ on a load-bearing axis can be disqualifying.

| Framework | Canvas | Native ink | Rich text | Math | CRDT/collab | **Linux** | Tablet/pen | IME/a11y | Lang / License |
|-----------|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--|
| **Flutter** | ●●● | ●●○ | ●○○ | ●●○ | ●●○ | ●●● | ●●○ | ●●○ | Dart / BSD-3 |
| **Compose MP** | ●●● | ●●○ | ●○○ | ●○○ | ●●○ | ●●○ | ●●○ | ●●○ | Kotlin / Apache-2 |
| **Tauri** | ●●○ | ●○○ | ●●● | ●●● | ●●● | ●○○ | ●●○ | ●●○ | Rust+JS / MIT-Apache |
| **Electron** | ●●○ | ●○○ | ●●● | ●●● | ●●● | ●●● | ●○○ | ●●● | JS/TS / MIT |
| **Avalonia** (.NET) | ●●● | ●●○ | ●○○ | ●○○ | ●●○ | ●●● | ●●○ | ●●○ | C# / MIT |
| **.NET MAUI** | ●●○ | ●●○ | ●○○ | ●○○ | ●●○ | ●○○* | ●●○ | ●●○ | C# / MIT |
| **Qt/QML** | ●●● | ●●● | ●●○ | ●●○ | ●●○ | ●●● | ●●● | ●●● | C++/QML / GPL-LGPL-comm. |
| **React Native** | ●●○ | ●●○ | ●○○ | ●○○ | ●●○ | ●○○ | ●●○ | ●●○ | JS/TS / MIT |

\* .NET MAUI has **no official Linux desktop** (community-only) — close to disqualifying given our Linux priority.

---

## 5. Per-framework detail

### 5.1 Flutter / Dart — *own-canvas, great for the canvas, taxed on text (and the team knows it)*
- **Rendering:** draws every pixel via **Impeller** (mobile) / **Skia** (desktop, mid-2026). Excellent for a custom canvas.
- **Canvas:** ★ strongest argument — `CustomPainter` + transforms give full control of a pannable/zoomable scene, with proven prior art.
- **Ink:** `PointerEvent` exposes pressure/tilt; Apple Pencil, Surface, Wacom work. No built-in front-buffer/prediction path → good-but-not-native without a native overlay. **Saber** (open-source Flutter handwriting app across all platforms incl. Linux) proves high-quality ink is achievable here.
- **Rich text:** the weak spot. `TextField` is single-field; block/rich editing is DIY. Best options: **super_editor** (most serious, still evolving), **flutter_quill**, **Fleather**. **AppFlowy** (Flutter + Rust Notion alternative) proves a block editor is possible — but it is a lot of work.
- **Math:** `flutter_math_fork` renders a KaTeX subset **natively, no WebView** — the most direct fit for in-canvas math. Interactive editing (MathLive-style) would need a WebView.
- **CRDT:** no native editor binding, but **AppFlowy builds its collaborative layer on `yrs` (Yjs's Rust port) inside a Flutter app** — a live proof point that Yjs-family CRDTs ship in Flutter via Rust FFI; a `y_dart` binding is maturing.
- **Linux:** officially supported (GTK embedder), Flatpak/Snap; one of the better Linux stories among own-canvas toolkits.
- **IME/a11y:** because Flutter draws its own text, desktop CJK IME has historically been rough and desktop screen-reader support is weaker than mobile — a real concern for a text-heavy app.
- **Verdict:** best *canvas* fit, first-class Linux, team velocity — offset by the rich-text/IME/desktop-a11y tax and no free native-ink path. **Strong candidate for the "native, ink-first" posture.**

### 5.2 JetBrains Compose Multiplatform / Kotlin — *own-canvas via Skia; desktop+Android solid, iOS now stable, text thin*
- Own UI via Skia (Skiko); good canvas control, slightly less canvas prior-art than Flutter.
- **Ink:** on Android you can reach the full native stylus stack (pressure/tilt, prediction, front-buffer) around Compose's drawing; **desktop (JVM) pen support is weaker**, iOS pen less proven. *Verify with a spike.*
- **Rich text:** also immature, with a *smaller* editor ecosystem than Flutter.
- **Math/CRDT:** thin native math; CRDT via Rust FFI as with Flutter.
- **Linux:** runs on the JVM — works, but a larger runtime and less battle-tested than Win/Mac.
- **Verdict:** viable native alternative to Flutter, especially for a Kotlin team; weaker desktop/iPad pen and smaller ecosystem make it a second choice to Flutter for *this* product.

### 5.3 Tauri (Rust + system webview) — *lean, web-editor superpowers, WebKitGTK is the Linux landmine*
- Renders in the **system webview** — WebView2 (Win), WKWebView (mac/iOS), **WebKitGTK (Linux)**, Android System WebView. Rust backend, tiny bundles.
- **Canvas + rich text + math + CRDT:** best-in-class via the web ecosystem (this is how tldraw/Excalidraw/BlockSuite work).
- **Ink:** weakest tier — webview-compositor latency, no front-buffer; predicted/coalesced events strong on Chromium but weak on WebKit/WebKitGTK → **inconsistent ink across your own targets**.
- **Linux — the big problem:** WebKitGTK varies dramatically by distro and lags Chromium; Tauri's own docs concede it's hard to get accurate info across distros. **This directly conflicts with our Linux-first + low-latency-ink priorities.**
- **Verdict:** superb for content, but the WebKitGTK-on-Linux fragility plus the webview ink ceiling are serious strikes against *our* specific priorities.

### 5.4 Electron — *the heavyweight web baseline; most consistent Linux, no tablet*
- Ships its **own Chromium + Node** → **identical engine on every desktop OS** (the decisive edge over Tauri). Proven infinite canvases (Obsidian Canvas, Notion, and **AFFiNE ships Electron desktop**).
- **Content:** best-in-class rich text/math/CRDT, consistent IME/a11y **including Linux**.
- **Ink:** webview ceiling, but Chromium's best-in-web pointer stack, consistent on every OS. Still not native latency.
- **Linux:** arguably the most reliable "same behavior on Linux" of any option (VS Code, Obsidian, Slack).
- **Tablet — the real gap:** **no first-class iPad/Android from Electron.** Given tablet is a close-second priority, you'd need a separate mobile stack sharing the web editor. Plus ~100–200 MB bundles and high RAM.
- **Verdict:** the safest path for *content-first* on desktop incl. Linux — but the tablet gap and heaviness are the price. Underpins the "all-web" posture if desktop leads and tablet follows via a separate shell.

### 5.5 .NET: Avalonia / Uno / MAUI (C#) — *only two of the three fit*
- **.NET MAUI:** native widgets, SkiaSharp canvas, Windows InkCanvas — but **no official Linux desktop.** For a Linux-first product, near-disqualifying as the primary.
- **Avalonia:** **draws its own UI via Skia** (like Flutter, in C#/XAML), **first-class Linux/Win/mac + iOS/Android + WASM, MIT.** Pointer API exposes pressure/tilt/twist. **Best Linux story in .NET.** Rich text is basic (`AvaloniaEdit` is a *code* editor, not WYSIWYG) — same native rich-text gap as peers.
- **Uno:** WinUI/XAML model, Skia across desktop incl. Linux; similar rich-text thinness.
- **Verdict:** if C# is desired, **Avalonia is the one to prototype** (MIT, real Linux, own-canvas). Immature rich text and a smaller stylus ecosystem keep it behind Flutter/Qt for this product.

### 5.6 Qt / QML (C++ / Python) — *the most mature pen + graphics; licensing is friction, not a wall*
- Mature own scene-graph; very capable custom canvases.
- **Ink:** **best native-tier pen of any cross-platform option** — `QTabletEvent` (pressure/tilt/rotation), Windows Ink/Wacom, drop-to-GL for low-latency strokes. **Krita** proves pro-grade feel on desktop *and* tablets.
- **Rich text:** `QTextDocument`/`QTextEdit` is one of the more mature *native* rich-text engines — a genuine edge over Flutter/Compose/Avalonia — though a modern block/Markdown editor on it is still substantial work.
- **Linux:** best-in-class (Qt *is* the KDE toolkit). IME/a11y among the best native stories.
- **Licensing — the real nuance:** GPL / LGPLv3 / commercial. **For an open-source project this is *not* a deal-breaker** (LGPLv3 dynamic-link or GPL is free; PySide6 is LGPL). Friction is real but bounded: static linking (common for mobile/app-store builds) needs GPL or commercial; LGPL relink-compliance on iOS/Android stores is awkward; a *future closed/commercial* fork gets complicated.
- **Verdict:** the strongest *technical* fit for the ink-and-canvas core, and it softens the rich-text gap — at the cost of C++ complexity, a smaller modern-app talent pool, and licensing friction on static/mobile builds. **The serious alternative to Flutter for the "native, ink-first" posture.**

### 5.7 React Native — *weak fit; noted for completeness*
Native widgets via JSI; **not desktop-first** (community `-windows`/`-macos`, no real Linux) — which alone disqualifies it here despite good mobile Skia canvas support.

---

## 6. The three postures — and why Posture A won

Because content-richness and canvas/ink pull apart, the choice was always a **posture** first, a framework second. The v0.1 descriptions are kept; verdicts added.

### Posture A — "Own the canvas" (native-drawn) — ✅ CHOSEN
**Flutter** (team knows it, best own-canvas prior art, Saber proves ink, first-class Linux, fastest startup of the candidates, one renderer everywhere) with a **Rust core** for CRDT/sync. Qt was the runner-up (best native pen, `QTextDocument`, best Linux) — but its pen advantage is exactly the axis the stakeholder demoted, and C++ velocity + licensing friction + zero team familiarity are all real costs with no compensating win left.
- **We accept:** building/assembling the rich-text + math layer in Flutter (the ecosystem has matured — see §7.2) and hand-rolling a thin CRDT FFI.
- **We decline:** per-platform native ink overlays. Standard Flutter pointer pipeline is the accepted ink baseline.

### Posture B — "Content-first, all-web" (webview-drawn) — ❌ rejected
The web editors remain superb, but the posture fails the two newly-elevated priorities: **Electron** fails startup (1.5–3 s cold starts, 100–200 MB bundles, high RAM) and has no tablet story at all; **Tauri** fails consistency (three webview engines across our own targets; WebKitGTK-on-Linux fragility is documented by Tauri themselves). Adopting BlockSuite would also have meant our canvas, text, and file format all inherit a large third-party web framework — a heavy dependency for an "open by construction" project.

### Posture C — hybrid — ❌ rejected
Unchanged from v0.1: free-floating text on a zoomable canvas makes embedded web editor panes structurally awkward. Complexity without the payoff.

---

## 7. The concrete Flutter stack (what the decision buys, package by package)

With the framework decided, the evaluation moves down a level. Findings from a dedicated stack-research pass (mid-2026 state; maturity ratings are honest, sources in the research record). Full rationale in [ADR-0001](adr/ADR-0001-application-framework.md)–[ADR-0004](adr/ADR-0004-editor-engine.md); integration details in the [Architecture Overview](04-architecture-overview.md).

### 7.1 Startup & consistency evidence (the new top priorities)
Published desktop comparisons: hello-world memory ~38 MB (Flutter) vs ~100 MB (Electron), heavy-scene ~170 MB vs ~2.2 GB; binaries 5–8× smaller (23–41 MB vs 184–259 MB); Flutter AOT cold starts typically well under 1 s vs 1.5–3 s for nontrivial Electron apps. And Flutter's single bundled renderer (Skia today on Windows/Linux; Impeller default on mobile, opt-in on desktop) means pixel-identical output on every OS — the structural consistency win. Watch-items: desktop multi-window is only now landing behind a flag (don't architect v1 around it) and desktop IME/CJK remains the area to test earliest (PLAT-6).

### 7.2 Rich text — a two-way bake-off that we ended up not running

> **Outcome (2026-07-27):** neither engine was adopted. [ADR-0004](adr/ADR-0004-editor-engine.md) is **Accepted: keep the engine we own**, behind an `OnoteTextEditor` seam. The comparison below still stands on its facts and is kept as the record of what was weighed — but it framed the choice as two-way, which assumed there was no third option. By the time the criteria were written there was one: the incumbent already met the spike's criteria 1–2 in shipped code. The deciding factor was a shape mismatch rather than capability — **both candidates own their own document layout**, and Openote's text containers are absolutely-positioned canvas boxes whose geometry must match the OneNote importer to fractions of a millimetre. An engine that owns layout is a liability at that seam.

The v0.1 "weak spot" assessment stands but has narrowed to two serious engines, each with real production evidence:

| | **super_editor** (0.3.0-dev line) | **appflowy_editor** (v6.x) |
|---|---|---|
| Model | `Document`/`Editor`/attributions — a build-your-own-editor toolkit | Block tree + per-block Delta — a shipped block editor |
| Inline Markdown as-you-type | Primitives provided; assemble it | **Built in, shipping in AppFlowy today** |
| Inline widgets (math chips) | First-class (inline placeholders, custom nodes) | Custom block components (AppFlowy ships a math block) |
| Markdown I/O | `super_editor_markdown` | Built-in MD/JSON/Delta import-export |
| Production proof | Superlist + client apps — **on dev releases** | AppFlowy itself (60k★ product) |
| Risk profile | API churn on the perpetual dev line | Roadmap tracks AppFlowy's needs, not ours |

**Decision path as proposed:** a 1–2 week spike on each — "math inline widget + live Markdown + read-only instance in a canvas box". The five acceptance criteria remain the right bar for the text engine and [ADR-0004](adr/ADR-0004-editor-engine.md) scores the incumbent against them (criteria 1–2 met; 3–5 explicitly *not* claimed). Multi-instance strategy, which held regardless of engine and is now shipped: **read-only/rasterized renderings for every box, one live editor mounted on the focused box** — the proven canvas-app pattern.

### 7.3 The rest of the stack (low-controversy picks)

| Concern | Choice | Maturity |
|---------|--------|----------|
| Rust interop | `flutter_rust_bridge` v2 (Flutter Favorite; async, streams, all six platforms) | Production-ready |
| CRDT | **Loro** behind our own thin Rust crate (no pub.dev binding exists for any CRDT — we own a small FFI surface either way); `yrs` documented fallback | Usable-with-effort — [ADR-0002](adr/ADR-0002-crdt-library.md) |
| Storage | `drift` over bundled `sqlite3` (FTS5 + JSON1 included; SQLCipher drop-in for optional encryption) | Production-ready — [ADR-0003](adr/ADR-0003-storage-container.md) |
| Full-text search | SQLite **FTS5** shadow tables (`unicode61` + `trigram` for CJK) | Production-ready |
| Ink | `perfect_freehand` (maintained by Saber's author) + Saber-style stroke pipeline on `CustomPainter` | Production-ready |
| Math render | `flutter_math_fork` (pure-Dart KaTeX subset — the only real native option; budget upstream contributions) | Usable-with-effort |
| Markdown parse | Dart team's `markdown` package (CommonMark+GFM); `flutter_markdown_plus` for read-only surfaces (Google discontinued `flutter_markdown`) | Production-ready |
| Syntax highlighting | `re_highlight` | Production-ready |
| Canvas | **First-party** (own transform matrix, viewport culling, `RepaintBoundary` per block, raster caching) — community packages are stalled 0.0.x reference material, not dependencies | Build-it-ourselves, ~2–4 weeks for the core |

### 7.4 Honest top risks
1. ~~**The editor bake-off** (§7.2)~~ — **closed** ([ADR-0004](adr/ADR-0004-editor-engine.md)). The live risk it leaves behind is the **structured-`nodes` migration**: storage is still an interim Markdown string, which cannot represent a sub-block edit and therefore cannot merge — see [ADR-0006](adr/ADR-0006-sync-transport-and-text-model.md).
2. **The CRDT FFI surface is ours to build and maintain** — small (≈20 functions) but permanent.
3. **Desktop IME/CJK** and the not-yet-stable multi-window story — schedule items, not blockers.

---

## 8. Enabling-technology choices (mostly framework-independent)

These decisions matter regardless of posture and are detailed in the [Architecture Overview](04-architecture-overview.md); summarized here with the leading options.

- **Math:** store **canonical LaTeX**, export **MathML** (W3C interchange, good for accessibility; MathML Core is now supported across all browser engines but not pixel-identical). Render with **KaTeX** (fast, MIT) or **MathJax** (broadest LaTeX, Apache-2) on web; **`flutter_math_fork`** natively in Flutter. Offer **UnicodeMath-style linear input** (the OneNote experience) — reuse **UnicodeMathML** as the UnicodeMath↔LaTeX/MathML bridge; **MathLive** (MIT) is the closest off-the-shelf WYSIWYG equation field.
- **Ink:** capture full channels (x/y/pressure/tilt/time) as compact typed arrays; render natural variable-width strokes with **`perfect-freehand`** (Dart port `perfect_freehand` exists). Use **InkML** (W3C) as an open import/export interchange, not the hot-path storage. **Defer recognition;** later, **ML Kit Digital Ink** (on-device, offline, 300+ languages, but a Google binary) or **MyScript** (commercial, best-in-class) — noting **no mature fully-open cross-platform online recognizer exists.**
- **Sync/CRDT:** decided provisionally in [ADR-0002](adr/ADR-0002-crdt-library.md): **Loro** behind our own Rust crate (movable tree fits the notebook hierarchy; rich-text CRDT; snapshot/time-travel gives version history nearly free; a production Dart-via-FRB report exists), with **`yrs`** the documented fallback if Yjs wire-compatibility ever becomes a requirement. A note-shaped benchmark (long text + many ink strokes + math) remains a Phase-0 validation task — published CRDT numbers conflict and are workload-dependent.
- **Local-first & E2E:** anchor on the Ink & Switch *local-first* principles; if E2E encryption is in scope, design for a **blind-relay** sync server now (model on `secsync`) — retrofitting E2E later is much harder.

---

## 9. Summary

The framework choice was always "**which end of the content-vs-ink tension do we optimize for.**" The stakeholder's clarified priorities — startup speed, consistency, and feature richness above pen latency — answered it: **Flutter/Dart UI with a Rust core** ([ADR-0001](adr/ADR-0001-application-framework.md)). Flutter wins the newly-top-ranked axes outright (sub-second AOT startup, one renderer everywhere, first-class Linux), carries the team's existing velocity, and its historical weak spot — rich text — has narrowed to a two-way bake-off between production-proven engines (§7.2). The editor engine is since decided (ADR-0004 — keep the engine we own, behind a swappable seam), leaving **license ratification (ADR-0005) as the only open Phase 0 gate**, plus the newly-raised sync storage layout (ADR-0006, proposed). Everything else is specified and ready to build against: see the [File Format Spec](specs/10-file-format-spec.md), [Data Model Spec](specs/11-data-model-spec.md), [Math Input Spec](specs/12-math-input-spec.md), and [Ink Data Spec](specs/13-ink-data-spec.md).

---

*Comparative claims derive from mid-2026 research. "Provisional" in ADR-0001 means: revisit triggers are documented, but absent a trigger, this is the decision the specs and code build on. ADR-0001's trigger 1 (the editor bake-off failing on both engines) is moot — the bake-off was not run and ADR-0004 resolved without it.*
