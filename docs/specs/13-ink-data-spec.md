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
  strokes into new strokes with new ids covering the surviving segments.
  Lineage is not recorded: a `splitFrom` field was specified here and never
  built, because nothing has needed to trace a fragment back to what it came
  from.
- Strokes share one `ink` block when they were written **close together in
  both senses** — within a short gap (default 2 s) and near the block's own
  bounds (default about a line of handwriting). Time alone groups a note made
  at the top of a page with one made at the bottom, and a block is the unit of
  selection, so that reads as one object that cannot be taken apart. One block
  per page-sized drawing also destroys culling granularity; a writer SHOULD
  start a new block beyond 512 strokes.
- The **lasso** re-homes strokes into a block of their own, which is how a
  block that has grown gets split.

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
> The blob's bytes are specified in **§2.3**. Note the quantisation supersedes
> §2's old promise of 0.01 px in JSON. 1/16 px is 0.0625, which at the canvas's
> maximum 8× zoom is 0.0078 px on screen — finer than that promise in the only
> place it matters.

### 2.3 The blob format: OIS1 (normative)

Openote Ink Strokes, version 1. Everything below is little-endian in the sense
that varint groups run least-significant first; there are no multi-byte
integers other than varints.

**Two varint spellings** are used throughout:

- `uvar` — LEB128. Seven bits per byte, least-significant group first, high bit
  set means another byte follows. Counts, lengths and non-negative scalars.
- `svar` — zigzag, then LEB128. `encode(v) = (v << 1) ^ (v >> 63)`,
  `decode(u) = (u >>> 1) ^ -(u & 1)`. Deltas, which are as often negative as
  positive.

#### File

| Bytes | Field | |
|---|---|---|
| 0–3 | magic | `OIS1` — `4F 49 53 31` |
| 4 | version | `1`. A reader MUST refuse a higher one rather than guess |
| 5 | method | `0` the payload follows verbatim; `1` it is zlib-compressed ([RFC 1950](https://www.rfc-editor.org/rfc/rfc1950), header and Adler-32 included) |
| 6… | payload | |

A writer chooses whether to compress and on what grounds — Openote deflates
above 256 bytes and only when the result is smaller. A reader MUST accept
either method at any size.

#### Payload

| Field | Type | |
|---|---|---|
| flags | `u8` | bit 0: some stroke carries pressure · bit 1: some carries timing · bit 2: some carries tilt. The corresponding column is absent when its bit is clear |
| scale | `uvar` | quantisation units per page pixel. Openote writes 16; a reader MUST use the stored value |
| count | `uvar` | strokes |
| minX, minY, maxX, maxY | `svar` ×4 | the bounding box in quantised units, **relative to the blob's origin**, so a reader can lay a block out without decoding any points. All four are `0` when there are no points |
| brushCount | `uvar` | distinct brushes |
| brushes | | `brushCount` of the record below |
| baseTime | `uvar` | epoch ms, subtracted from every stroke's start |
| strokes | | `count` of the record below |
| columns | | in the order given under *Columns* |

Brushes are deduplicated because a page of handwriting is usually one pen, and
repeating the four fields per stroke cost about forty bytes each.

**Brush record**

| Field | Type | |
|---|---|---|
| tool | `u8` | `0` pen, `1` highlighter |
| colourKind | `u8` | `1` three bytes follow; `2` a string follows; anything else means the reader substitutes `#211F1B` |
| colour | 3 × `u8`, or `uvar` length then UTF-8 | `#RRGGBB` as R, G, B when kind is `1`. Kind `2` carries the colour as written, verbatim — a value outside `#RRGGBB` is round-tripped rather than dropped, per the format spec's unknown-data rule |
| size | `uvar` | base width in 1/64 px |
| opacity | `u8` | `0`–`255` for 0.0–1.0 |

**Stroke record**

| Field | Type | |
|---|---|---|
| flags | `u8` | bit 0: this stroke has a pressure column · bit 1: timing · bit 2: tilt |
| brush | `uvar` | index into the brush table |
| start | `uvar` | ms after `baseTime` — the stroke's `strokeStart` |
| points | `uvar` | samples in this stroke |

**Columns**, in this order and each covering every stroke before the next
begins: `x`, `y`, then `pressure` if the payload flags say so, then `time`,
then `tilt`. Column-major rather than point-major because like values sit
together and deflate finds far more to work with — 3.68 MB against 4.06 MB on
the real notebook, for nothing.

Every column is a run of `svar` deltas, and **the running value resets to zero
at each stroke boundary**, so a stroke's first entry is its absolute value and
the rest are steps.

| Column | Entries | Units |
|---|---|---|
| `x`, `y` | `points` per stroke, every stroke | quantised units relative to the origin. A page coordinate is `origin + value / scale` |
| `pressure` | `points`, only for strokes whose flag bit 0 is set | `0`–`255` for 0.0–1.0 |
| `time` | `points`, only for strokes whose flag bit 1 is set | ms offsets from that stroke's own `start` |
| `tilt` | two runs of `points` back to back — all of `tx`, then all of `ty` — only for strokes whose flag bit 2 is set | 1/64 of whatever unit the source used, round-tripped rather than interpreted |

A device that reported tilt for only some samples is padded by repeating the
last value, so both runs are always `points` long.

**What the blob does not hold.** Stroke ids: they were sixteen bytes each, 19%
of the payload on the real notebook, and nothing persists a cross-reference to
one. A reader synthesises them; Openote derives them from the blob hash so they
are stable across decodes, which is what lets a rebuilt container be compared
byte-for-byte against the original.

#### A worked example

Two strokes — a pen and a highlighter — with the block's origin at
`(100, 49)`, uncompressed. 69 bytes:

```
4f 49 53 31 01 00  03 10 02  00 10 c0 1b e0 02  02
00 01 21 1f 1b 80 01 ff   01 01 ff d4 00 80 06 66
80 d0 95 ff bc 31
03 00 00 03   02 01 f4 03 02
00 20 30   80 19 c0 02
20 00 0f   e0 02 00
fe 03 65 65
00 10 12   00 12
```

| Bytes | Reading |
|---|---|
| `4f 49 53 31 01 00` | `OIS1`, version 1, uncompressed |
| `03` | some stroke has pressure, some has timing, none has tilt |
| `10 02` | scale 16, two strokes |
| `00 10 c0 1b e0 02` | bounds `(0, 0.5)`–`(110, 11)` in page px once divided by 16 |
| `02` | two brushes |
| `00 01 21 1f 1b 80 01 ff` | pen, `#211F1B`, size 128/64 = 2, opacity 255/255 = 1 |
| `01 01 ff d4 00 80 06 66` | highlighter, `#FFD400`, size 768/64 = 12, opacity 102/255 ≈ 0.4 |
| `80 d0 95 ff bc 31` | base time 1 700 000 000 000 |
| `03 00 00 03` | stroke 0: pressure and timing, brush 0, at the base time, 3 points |
| `02 01 f4 03 02` | stroke 1: timing only, brush 1, 500 ms later, 2 points |
| `00 20 30` | x of stroke 0: 0, +16, +24 → 0, 16, 40 → page x 100, 101, 102.5 |
| `80 19 c0 02` | x of stroke 1: 1600, +160 → page x 200, 210 |
| `20 00 0f` | y of stroke 0: 16, 0, −8 → page y 50, 50, 49.5 |
| `e0 02 00` | y of stroke 1: 176, 0 → page y 60, 60 |
| `fe 03 65 65` | pressure, stroke 0 only: 255, −51, −51 → 1.0, 0.8, 0.6 |
| `00 10 12` + `00 12` | timing: 0, +8, +9 → 0, 8, 17 ms; and 0, +9 → 0, 9 ms |

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
faithfully outside Openote. §2.3 is the byte layout, with a worked example to
check an implementation against.*
