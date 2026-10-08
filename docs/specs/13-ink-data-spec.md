# Openote Ink Data Model Specification

> **Normative for stroke capture, storage and interchange.** Covers INK-1…11.
> **Purpose:** The concrete stroke data model — capture, storage, rendering, and InkML interchange — for INK-1…11. Written against the decided pipeline: Flutter pointer events → `perfect_freehand` outlines → `CustomPainter`, per [ADR-0001](../adr/ADR-0001-application-framework.md) and the Saber reference architecture.
> **Priority note:** per stakeholder direction, ink is a required feature but **near-native latency is a non-goal** — this spec optimizes for lossless storage, natural rendering, and openness, not for front-buffer tricks.

---

## 1. Capture (normative)

- Input source: Flutter `PointerEvent`s, **including coalesced events** where the platform delivers them (pens sample at 240–400 Hz vs 60–120 Hz frames; discarding coalesced points visibly corners fast strokes).
- Per point, capture: position (page-space, after inverse canvas transform), `pressure` (normalized 0–1; devices without pressure report the platform default → §4 velocity fallback), `tiltX`/`tiltY` degrees where available, timestamp ms.
- **Palm rejection** (INK-4): while a stylus pointer is active, touch pointers are ignored for drawing (two-finger gestures still pan/zoom).
- Raw captured points are stored **unsmoothed** — smoothing/outline generation is a render-time concern (§4), so future renderers can do better with the same data (the lossless principle, INK-11).

## 2. Storage model

A stroke is the shape below. **It is the working shape, not the stored one** —
see §2.2, which is what actually goes on disk.

```jsonc
{
  "id": "0198f3c2-…",           // UUIDv7 (lasso ops and sync address strokes)
  "brush": {
    "tool": "pen",              // "pen" | "highlighter" | "pencil"
    "color": "#211F1B",         // content-ink token or hex
    "size": 2.5,                // base width, logical px
    "opacity": 1.0              // highlighter is about 0.4
  },
  "x": [120.5, 121.2, …],       // page-space, float
  "y": [96.0, 96.8, …],
  "p": [0.42, 0.47, …],         // pressure 0-1; omitted means no pressure data
  "tx": [], "ty": [],           // tilt; empty means not captured
  "t": [0, 8, 17, …],           // ms offsets from strokeStart
  "strokeStart": 1753142400000  // epoch ms
}
```

Parallel arrays rather than a list of points: compact, cache-friendly, and a
stroke is written once and immutable thereafter, so erasure and transforms are
separate operations rather than edits.

**`strokeStart` is data, never a clock reading.** It is the origin the `t`
offsets are measured from, and it is hashed into the content-addressed blob. A
writer with no start time for a stroke MUST write `0`. Stamping the current time
makes byte-identical handwriting hash differently on every write, so a re-import
stores the whole ink payload again — in the container *and* in the append-only op
log. The OneNote importer did exactly that: two sections re-imported wrote 82
further blobs and 2.9 MB for handwriting already on disk. OneNote's own ink
carries no timing, so `0` and an empty `t` is what an import states.

### 2.1 Grouping, erasing, splitting

- **Erase by stroke** removes the stroke. **Erase by area** splits affected
  strokes into new strokes with new ids covering the surviving segments; the
  original's id goes to the longest survivor's `splitFrom`, for lasso-history
  continuity.
- Consecutive strokes within a short gap (default 2 s) share one `ink` block, and
  the lasso can regroup. One block per page-sized drawing is an anti-pattern
  because it destroys culling granularity; a writer SHOULD start a new block
  beyond 512 strokes.

### 2.2 What is actually stored: a blob reference

> **⚠ Changed in v0.11.** An `ink` block's `content` does **not** hold the array
> above. It holds a reference to a binary blob:
>
> ```jsonc
> "content": {"ink": {
>   "v": 1,
>   "base": "sha256:…",   // the strokes
>   "add": [],            // reserved: erase/append overlays
>   "gone": "",           // reserved: run-length removed indices
>   "n": 612,             // stroke count, so counting never opens a blob
>   "o": [minX, minY]     // the origin the blob's coordinates are relative to
> }}
> ```
>
> The reason was measured: a real imported notebook's op log was 67.7 MB, and
> 63.1 MB of it was 113 ink blocks — 1,828,431 points at **36.2 bytes per point**,
> because a point was `[123.45678901234567,456.78901234567890]` in JSON, stored
> twice. The same content as bytes is **1.86 bytes per point**, a 19.4×
> reduction against 3.6× for simply gzipping the JSON.
>
> `add` and `gone` are read on the way in and preserved on the way out, so an
> incremental-overlay scheme can land later without a second migration of
> everyone's handwriting.
>
> **The legacy inline form is read for ever.** A reader MUST handle both: an
> `ink` key means the reference form, a `strokes` key means the array above.
>
> **This document does not yet specify the blob's bytes**, which means an
> independent implementation cannot render Openote ink today — the one place this
> project's openness guarantee is currently unmet. The format is deterministic
> and documented in `app/lib/ink/ink_codec.dart`: a magic `OIS1`, coordinates
> quantised to **1/16 px**, delta-encoded between consecutive points, written
> column-major (all x deltas, then all y, then pressure) with LEB128 varints and
> zigzag for signed deltas, then deflated. Pressure is one byte; tilt is 1/64 of
> whatever unit the source used, round-tripped rather than interpreted.
> **Writing that out properly here is outstanding work**, tracked in
> [the backlog](../planning/backlog.md).
>
> Note the quantisation supersedes §2's old promise of 0.01 px in JSON. 1/16 px
> is 0.0625, which at the canvas's maximum 8× zoom is 0.0078 px on screen —
> finer than that promise in the only place it matters.

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

*The test of openness for the ink layer is that this document plus
`perfect_freehand`'s published parameters is enough to render Openote ink
faithfully outside Openote. **It is not, yet** — §2.2 says what is missing.*
