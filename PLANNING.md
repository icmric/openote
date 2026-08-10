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
    live data (via api)
    graphing
    Excel import should keep formulas as formulas, styling rules, charts —
    "it seems to have imported it just as a plain text table"
    → csv/tsv/xlsx import shipped as VALUES (a formula cell imports the
      number you saw). Keeping formulas live, conditional styling and charts
      is not an importer gap — the table block has no formula model, no cell
      styling and no chart to import INTO, so this is the spreadsheet-engine
      design pass: decide what a table block can hold first, then the
      importer fills it. Live data belongs to the same pass.

Calander and tasks
    It works currently, however is very limited.
    → The trello board shipped as a BLOCK (Insert ▸ Board, or right-click ▸
      Task board here): columns, draggable cards, inline editing — stretched
      wide on an empty page it IS a board page, and it sits beside notes in
      a way a page mode couldn't. The wider calendar rework stays open.

accesability
    i13n
    full keyboard control
    → MCP SHIPPED (View tab ▸ AI access): a local MCP server, off by
      default, token-guarded, loopback-only — AI tools read pages, search,
      create pages, append blocks, make flashcards, and every write is an
      ordinary synced, undoable edit. The durable contract is
      docs/specs/14-external-api-mcp.md, whose §2 rule ("the file format IS
      the API") is what keeps future block types API-visible automatically —
      consult §7's checklist in any PR that touches the model.
      Keyboard control is PLANNED at docs/planning/v0.16-keyboard-control.md
      (one keyboard map in code, a Ctrl+/ reference rendered from it, then
      the block-traversal sweep); i18n follows it, pending the
      which-languages decision.

Local code
    Write and execute code like JS, SQL, etc — similar to juniper notebook
    In time: other languages too, maybe ones the user already has installed
    on their system, if we can access that in a sandboxed way
    → SQL and JS cells SHIPPED (Run button / Ctrl+Enter; page tables are
      queryable; output persists and syncs). Remaining, staged in
      docs/planning/v0.14-local-code.md: page sessions + Run All,
      write-back behind a confirm, chart output (shared with the Tables
      graphing design), and system interpreters — which need REAL OS
      sandboxing per platform (AppContainer / bubblewrap / sandbox-exec),
      because a prompt is not a sandbox.

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

Update through app
    App should search for new version of the app (maybe each launch?) and if it finds a new version a little update buttons appears. If the user clicks it it should make a popup to stop them interacting further, save everything then if they confirm download do the download, however prevent them from using the app during the process. It should automatically apply the update and relaunch the app