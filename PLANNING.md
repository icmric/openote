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
> PDF, or import "As a card" for the thumbnail-that-opens flow),
> **inking** (pen proximity switches to the pen tool; the pen's tail and its
> barrel button erase — arbitrary per-button OS mappings never reach a
> cross-platform app, so barrel = erase is the half that exists), the page
> scroll bar, **AI access** (local MCP server + one-click Connect buttons
> for Claude Code and Gemini CLI; spec 14 is the durable contract), and
> **update through app** (v0.7.0: launch check, an Update button when a
> newer release exists, save-everything → silent install → relaunch on
> Windows; other platforms get the download page).

PPTX Thumbnail
    (The PDF half of this shipped as the card import.) PPTX has no renderer
    here — a .pptx still lands as a plain attachment. Rendering it needs
    either a converter on import or exporting to PDF first.

Tables
    Excel like spreadsheet or SQL like table
    live data (via api)
    graphs/charts based on table
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
      Keyboard control phases 1+2 SHIPPED (docs/planning/v0.16): one
      keyboard map in code, Ctrl+/ renders it, and the canvas traverses —
      Tab/arrows/Enter/Escape, Ctrl+arrows nudge. Remaining: phase 3 (F6
      region cycling + dialog Enter/Escape audit) and phase 4 (board/panel
      internals). i18n follows, pending the which-languages decision.

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

Maps
    OSM and maplibre
    interactive map on the page
    style JSON in settings
    drop pins, draw lines, select countries/states, leave notes, etc

Prezi like presentation

Live editing
    In time, live editing (including cursor positions) would be awesome, although that will be quite complex and is not worth the effort at the moment.

Page info/tools
    Word counter, char count, estimated reading time.
    Citation tool similar to google docs
        select media type, provide link and it attempts to autofill as much info as possible. 
        Store list of all citations, button to insert in text citation and button to include all references (maybe this is live updated?) 
    Academic writing mode (maybe the default for page mode?)
        Regular page format rather than canvas
        More like a traditional text editor (one single continuous box for text, ability to still insert images, equations, etc either in line or as seperate boxes) 
        In app warning for unused references (where no in text citation was inserted) that is clear and maybe a warning before exporting, however no warnings are present in the export
    Improved spell check, grammar check
    Comments/notes
    Embed website inside page?
        Online only (i.e. basically use an iframe?) or allow it to donwload an offline copy too?
    Version history and user/computer tagging in metadata with creations, edits, and deletions
    Creating flowcharts
        users: students creating IT flowcharts, students creating logic flowcharts, companies creating chain of command, problem resolution, etc
        Basic text in components as early version. In future be able to click to expand each box to see more information (sorta like how the pdf thumbnail thing works), or potentially attach flows and actions to buttons allowing code or things to be executed by clicking on them
        Viewing mode where it takes people through one step at a time (for logic flowcharts), shows answer history somewhere (not kept once leaving view mode) allowing backtracking

Drawing
    tools such as basic shapes, lines/arrows, graphs
    drawing interpretation for flowcharts
    text interpretation, shape interpretation

Consistency/UX
    Ensure all blocks are consistent in their behaviours, being able to be copy and pasted, consistent navigation, formatting etc. Most objects should be able to share a box with each other, however for stuff like code blocks could stick with being their own thing if its not practical to mix them in.
    → v0.7.1 took the concrete half: code blocks now respect click
      position and are text-selectable without editing (same pointer
      behaviour as text boxes); copy/paste clones every block through the
      open-format round-trip, so nothing — including block types from
      newer versions — loses anything in transit. The follow-up round
      fixed the editor-key leaks (arrows jumped boxes, Enter was eaten —
      canvas traversal now stands down whenever an editor holds focus)
      and added TYPE-THROUGH: a letter on a selected text/code box starts
      writing at its end. The blocks-sharing-a-box model is the remaining
      design question.
    Simple unobtrusive animations consistently would be nice. A little bounce when a popup appears, the PDF viewer looking like it opens from the thumbnail, animation switching between menus, stuff like that
    → All three shipped: one shared dialog transition (quick fade +
      slight bounce), toolbar tab switches fade/slide in the same motion
      register, and the PDF viewer grows out of its thumbnail card.
    Centeralised settings page (including stuff like syncing, defaults for styles etc, and other information)
    → Shipped v0.7.1 (the gear, top bar): theme, spell check, pen
      behaviour, doors to Sync / AI access / shortcuts, About + update
      check. Style DEFAULTS still live only per-feature — they join the
      page when the styles system grows defaults at all.
