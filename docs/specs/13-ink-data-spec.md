# Openote Ink Data Model Specification

> **Document status:** Draft v0.1 · Last updated 2026-07-22
> **Purpose:** The concrete stroke data model — capture, storage, rendering, and InkML interchange — for INK-1…11. Written against the decided pipeline: Flutter pointer events → `perfect_freehand` outlines → `CustomPainter`, per [ADR-0001](../adr/ADR-0001-application-framework.md) and the Saber reference architecture.
> **Priority note:** per stakeholder direction, ink is a required feature but **near-native latency is a non-goal** — this spec optimizes for lossless storage, natural rendering, and openness, not for front-buffer tricks.

---

## 1. Capture (normative)

- Input source: Flutter `PointerEvent`s, **including coalesced events** where the platform delivers them (pens sample at 240–400 Hz vs 60–120 Hz frames; discarding coalesced points visibly corners fast strokes).
- Per point, capture: position (page-space, after inverse canvas transform), `pressure` (normalized 0–1; devices without pressure report the platform default → §4 velocity fallback), `tiltX`/`tiltY` degrees where available, timestamp ms.
- **Palm rejection** (INK-4): while a stylus pointer is active, touch pointers are ignored for drawing (two-finger gestures still pan/zoom).
- Raw captured points are stored **unsmoothed** — smoothing/outline generation is a render-time concern (§4), so future renderers can do better with the same data (the lossless principle, INK-11).

## 2. Storage model

An `ink` block ([Data Model Spec §4](11-data-model-spec.md)) contains a stroke set. Strokes use **parallel arrays** (compact, cache-friendly, CRDT-friendly — a stroke is written once, immutable thereafter; erasure and transforms are separate ops):

```jsonc
"content": {
  "strokes": [
    {
      "id": "0198f3c2-…",           // UUIDv7 (lasso ops & sync address strokes)
      "brush": {
        "tool": "pen",              // "pen" | "highlighter" | "pencil" (P2)
        "color": "#211F1B",          // content-ink token or hex
        "size": 2.5,                 // base width, logical px
        "opacity": 1.0               // highlighter ≈ 0.4
      },
      "x": [120.5, 121.2, …],        // page-space, float
      "y": [96.0, 96.8, …],
      "p": [0.42, 0.47, …],          // pressure 0–1; omitted → no pressure data
      "tx": [], "ty": [],            // tilt degrees; empty → not captured
      "t": [0, 8, 17, …],            // ms offsets from strokeStart
      "strokeStart": 1753142400000   // epoch ms
    }
  ]
}
```

- **In the CRDT** (File Format Spec §5.2): each stroke is one immutable value in the block's stroke list — no per-point CRDT ops. In the mirror/Page JSON, arrays appear as above; number precision: positions to 0.01 px, pressure to 0.001 (quantization is allowed at write time and documented so hashes are stable).
- **Erase by stroke** removes the stroke value; **erase by area** (INK-6) splits affected strokes into new strokes (new IDs) covering the surviving segments — the original's ID goes to the longest survivor's `absorbedIds`-equivalent (`splitFrom` field) for lasso-history continuity.
- **Grouping:** consecutive strokes within a short gap (default 2 s, config) share an `ink` block; the lasso can regroup. One block per page-sized drawing is an anti-pattern (kills culling granularity); the writer SHOULD start a new ink block beyond 512 strokes.

## 3. Coordinate & transform rules

Stroke coordinates are **page-space absolute** (not block-relative): the ink block's envelope `x/y/w/h` is the strokes' bounding box, recomputed on change. Moving ink (lasso/drag) rewrites stroke coordinates in one op — keeping coordinates absolute makes cross-block operations (erase across blocks, region embeds of ink) coordinate-math-free.

## 4. Rendering (normative behavior, informative technique)

- Strokes render as **variable-width filled outlines** via the `perfect-freehand` algorithm (Dart: `perfect_freehand`): width tracks pressure; when `p` is absent, width tracks inverse velocity (computed from `t`), giving mouse/trackpad strokes a natural taper (INK-5).
- The **wet stroke** (in-progress) draws on a dedicated top layer repainted per frame; **committed strokes** rasterize into cached layers per ink block (`RepaintBoundary` + image cache), re-rasterized on zoom-level change buckets. This is the Saber-proven pipeline — smoothness through caching, not OS tricks.
- Highlighter renders beneath text marks of overlapping text blocks (paint order exception, z within page still respected among ink).

## 5. Tools (v1)

| Tool | Behavior |
|------|----------|
| Pen | pressure-width outline, opaque |
| Highlighter | flat width ×3 base, opacity 0.4, blend `multiply` |
| Eraser | stroke-erase (default) / area-erase (toggle), diameter configurable |
| Lasso (P2) | freehand region → select strokes (≥50% contained), move/scale/recolor/delete |

## 6. InkML interchange (OPEN-5, P2)

- **Export:** each ink block emits an InkML `<ink>` with `<traceFormat>` declaring channels `X Y F T` (+ `OTx OTy` when tilt present), `<brush>` per Openote brush, one `<trace>` per stroke using first-difference (`'`) encoding. Page-space px map to InkML units with an explicit `<mapping>`; timestamps via `T` channel ms.
- **Import:** InkML traces map back; unsupported channels are preserved as opaque extension data on the stroke (`"x-inkml": {…}`) per the unknown-field rule.
- InkML is interchange only — never the hot-path storage (XML per-point cost is documented as the reason; this mirrors the compact-internal/open-interchange split the research recommends).

## 7. Recognition hooks (P3, design-only)

The model is recognition-ready without committing to a recognizer: strokes carry the exact shape ML Kit Digital Ink consumes (points + t), and recognition results, when they arrive, attach as **derived annotations** (`"recognized": {"text": "…", "confidence": 0.87, "engine": "mlkit@x.y"}`) — never replacing stroke data (INK-11). Ink-to-math feeds the [Math Input Spec](12-math-input-spec.md) grammar with the recognized linear string, reusing the entire build pipeline.

## 8. Invariants (testable)

1. Stroke arrays are equal length (`x,y,t` mandatory; `p,tx,ty` each either empty or full length).
2. A stroke, once written, is never mutated — only replaced (split/erase) or transformed (coordinate rewrite in one op).
3. Round-trip Page JSON → import → Page JSON is byte-stable after quantization.
4. Rendering never reads more than the viewport's culled block set (perf invariant, CANVAS-9).

---

*This spec plus `perfect_freehand`'s published parameters is sufficient to render Openote ink pixel-faithfully outside Openote — the test of openness for the ink layer.*
