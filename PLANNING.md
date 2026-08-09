# Eric's notes — what I want next

> Raw asks, in my own words, **in priority order — top first**. Nothing here
> is a spec; the plans in [`docs/planning/`](docs/planning/) are where these
> turn into work. Done items are removed as they ship — CHANGELOG.md is the
> record of what landed and when.
>
> Removed as completed so far: page format, password protection, the
> storage/size overhaul, templates, git/GitHub sync with join-by-link, page
> linking + live page windows, finger-drag panning, boxes stopping at the
> screen edge, box background colour + transparency, CSV/TSV import into
> tables, **PDF as a real PDF** (stored once, pages rendered on demand, text
> selectable/copyable in the popup viewer — right-click a slide ▸ Open the
> PDF, or import "As a card" for the thumbnail-that-opens flow), and
> **inking** (pen proximity switches to the pen tool; the pen's tail and its
> barrel button erase — arbitrary per-button OS mappings never reach a
> cross-platform app, so barrel = erase is the half that exists).

PPTX Thumbnail
    (The PDF half of this shipped as the card import.) PPTX has no renderer
    here — a .pptx still lands as a plain attachment. Rendering it needs
    either a converter on import or exporting to PDF first.

Tables
    Excel like spreadsheet or SQL like table
    import data (xlxs), live data (via api)
    graphing
    → csv/tsv import shipped; xlsx needs a reader package, live data and
      graphing want a design pass (what refreshes, when, and what a chart
      block is) — worth doing together with the spreadsheet question.

Calander and tasks
    It works currently, however is very limited. This would need a fairly significant UI rework as it would probaly need to replace the page entirley, but having the ability to have a trello like task board would be incredibly helpful for both students and product managers

accesability
    i13n
    full keyboard control
    MCP
        read stuff but also write stuff, like asking to create flash cards, etc.
    → Three different sizes in one word: MCP is a self-contained server over
      the notebook model (and the most leveraged — every AI tool gets to read
      and write notes); full keyboard control is incremental work across every
      surface; i18n is a one-time wiring cost plus translations forever.

Local code
    Write and execute code like JS, SQL, etc
    Similar to juniper notebook
    → Needs a sandbox decision before anything else: executing note content
      is the one feature where "a shared notebook can contain anything a
      stranger wrote" stops being hypothetical.

Cloud storage and saving
    Currently no real way to share a file or page with someone else, would like to address that

boxes
    metadata

Maps
    OSM and maplibre
    interactive map on the page
    style JSON in settings
    drop pins, draw lines, select countries/states, leave notes, etc

Prezi like presentation

Live editing
    In time, live editing (including cursor positions) would be awesome, although that will be quite complex and is not worth the effort at the moment.
