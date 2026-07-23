# ADR-0001: Application framework — Flutter/Dart UI with a Rust core

> **Status:** Accepted (provisional) · 2026-07-22
> **Deciders:** Eric (stakeholder) via priority direction; analysis in [Technology Evaluation](../03-technology-evaluation.md)

## Context

Openote needs one codebase producing native-feeling apps for Windows/macOS/Linux (first) and tablets (close second), with an infinite canvas, free-floating rich text, math, ink, and CRDT sync. The v0.1 Technology Evaluation mapped an irreducible tension: content-richness favors web rendering; canvas/ink control favors native-drawn rendering — and left the decision open, hinging on how hard the ink-latency requirement was.

The stakeholder then clarified the priority order: **(1) startup speed, (2) cross-platform consistency, (3) rich feature set — with near-native pen latency explicitly acceptable to trade away.** The stakeholder also has existing Flutter/Dart experience.

## Decision

**Flutter/Dart for the entire UI layer; a Rust core library (via `flutter_rust_bridge` v2) for CRDT, sync, and other engine-grade concerns.** No per-platform native ink overlays; Flutter's standard pointer → compositor pipeline is the accepted ink baseline.

## Rationale

- **Wins the top two priorities outright.** AOT-compiled Flutter desktop apps cold-start well under 1 s with ~5–8× smaller binaries than Electron equivalents (measured comparisons in the research record); one bundled renderer (Skia/Impeller) makes rendering pixel-identical across all targets — the definition of consistency. Tauri fails consistency structurally (three webview engines, WebKitGTK-on-Linux fragility per Tauri's own docs); Electron fails startup/footprint and has no tablet path.
- **The demoted axis is where Flutter was weakest relative to Qt.** Qt's native-tier pen stack was its decisive advantage; with latency demoted, Qt's remaining case (mature `QTextDocument`) doesn't outweigh C++ velocity costs, LGPL/static-linking friction on tablets, and zero team familiarity.
- **The historical weak spot has narrowed.** Flutter rich text is no longer a green field: two production-proven engines exist (super_editor — Superlist; appflowy_editor — AppFlowy), each demonstrably supporting block editing, live Markdown, and inline widgets ([ADR-0004](ADR-0004-editor-engine.md) picks between them by spike).
- **Ecosystem proof points map 1:1 onto our subsystems:** Saber (Flutter ink app on all six platforms, GPL), AppFlowy (Flutter + Rust + yrs CRDT at scale), `perfect_freehand`, `flutter_math_fork`, `drift`/`sqlite3` with FTS5.
- **Team familiarity** converts directly into velocity for a small open-source team — priority (3).
- **Why a Rust core at all:** every viable CRDT is a Rust library with no published Dart binding; sync, format migration, and (later) an importer benefit from a portable, testable, UI-independent engine — and it keeps the document engine reusable beyond Flutter (tenet 4, Architecture §1).

## Consequences

- We own a first-party canvas (~2–4 weeks core), the editor bake-off, and a small permanent CRDT FFI surface (≈20 functions).
- Desktop IME/CJK and screen-reader depth are Flutter's known desktop soft spots → PLAT-5/6 get early, explicit test passes; multi-window is not architected for in v1 (still flag-gated upstream).
- Web builds are deprioritized (Flutter web is the weakest Flutter target; PLAT-3 already places web last).
- Ink feel targets "Saber-quality," validated by a feel-check spike on real tablet hardware — a validation, not a decision gate.

## Revisit triggers

1. The [ADR-0004](ADR-0004-editor-engine.md) bake-off fails on **both** engines against its acceptance criteria (would reopen posture B / hybrid).
2. The ink feel-check spike is judged unacceptable by the stakeholder on target hardware (would reopen the native-overlay question — not the framework).
3. Flutter desktop loses first-party support or Linux regression-breaks for two consecutive stable releases.
