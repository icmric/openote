# Eric's notes — what I want next

> Raw asks, in my own words, **in priority order, top first.** Nothing here is a
> spec; the documents in [`docs/planning/`](docs/planning/) are where these turn
> into work, and [CHANGELOG.md](CHANGELOG.md) is the record of what landed.
>
> Items are deleted as they ship, so this list only gets shorter. A `→` note under
> one means part of it is done, or a decision has been taken that changes the
> rest of it.

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
    → CSV, TSV and XLSX import land as VALUES: a formula cell imports the
      number you saw. Keeping formulas live, conditional styling and charts is
      not an importer gap — the table block has no formula model, no cell
      styling and no chart to import INTO. So this is the spreadsheet-engine
      design pass: decide what a table block can hold first, then the importer
      fills it. Live data belongs to the same pass.

Calander and tasks
    It works currently, however is very limited.
    → The Trello board shipped as a BLOCK rather than a page mode: Insert ▸
      Board, or right-click ▸ Task board here. Stretched wide on an empty page
      it IS a board page, and it sits beside notes in a way a page mode could
      not. The wider calendar rework stays open.

accesability
    i13n
    full keyboard control
    → MCP shipped: a local server, off by default, token-guarded and
      loopback-only. AI tools read pages, search, create pages, append blocks
      and make flashcards, and every write is an ordinary synced, undoable
      edit. The durable contract is docs/specs/14-external-api-mcp.md, whose
      §2 rule — the file format IS the API — is what keeps future block types
      API-visible without anyone updating a schema.
    → Keyboard control shipped, all four phases: one map in code, Ctrl+/
      renders it, and the canvas, the board and the PDF reader all traverse.
    → i18n shipped: six languages, chosen from the computer's own settings.
      Several dialogs are still Dart string literals rather than messages —
      see the backlog.
    → **Accessibility is the one of the three that is NOT done.** Screen
      readers cannot read the editor at all, because the Windows accessibility
      bridge rejects the semantics tree this app produces. It is the worst
      defect in the project and it is §1 of docs/planning/v1.0.2.md.

Local code
    Write and execute code like JS, SQL, etc — similar to juniper notebook
    In time: other languages too, maybe ones the user already has installed
    on their system, if we can access that in a sandboxed way
    → SQL and JS cells shipped — Run, or Ctrl+Enter; page tables are
      queryable; output persists and syncs. What remains is in the backlog:
      page sessions and Run All, write-back behind a confirm, chart output,
      and system interpreters, which need real OS sandboxing per platform
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
    → Word count, character counts and reading time are on the page's own
      row. The count follows what the page READS: bold text is one word, a
      link is its label, an equation is one word wherever it sits, and bullets
      and heading marks are not words.
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
    → Version history shows per-block authors, edits and deletions, naming
      each device. Whether to keep that surface at all, or build rollback
      instead, is being decided — see docs/planning/v1.0.2.md.
    Creating flowcharts
        users: students creating IT flowcharts, students creating logic flowcharts, companies creating chain of command, problem resolution, etc
        Basic text in components as early version. In future be able to click to expand each box to see more information (sorta like how the pdf thumbnail thing works), or potentially attach flows and actions to buttons allowing code or things to be executed by clicking on them
        Viewing mode where it takes people through one step at a time (for logic flowcharts), shows answer history somewhere (not kept once leaving view mode) allowing backtracking
    PDF Viewer
        Inserted PDF (thumbnail) and it opened once but then failed to ever open again, i opened right after importing which may have caused a bug?
        Thumbnail PDF viewer should be able to be "detached" (or a better term) and had off to the side still within the app, but allowing me to edit the page while also viewing the PDF at the same time. 

Drawing
    tools such as basic shapes, lines/arrows, graphs
    drawing interpretation for flowcharts
    text interpretation, shape interpretation

Everything in one box
    "My dream is that we could have every data type in a single box. For some
    like images and videos it may not be plausible to have them inline in
    which case it can be split onto its own line, however if everything could
    be truly inlined that would be incredible."
    → Three things are already inline in a text box: pictures, flashcards and
      maths, all through ONE mechanism — a placeholder occupying exactly one
      code unit, so not a single caret offset moves. That is the existence
      proof. Whether one general syntax can carry every block type instead of
      a bespoke rule per kind is designed in
      docs/planning/v0.19-everything-in-one-box.md.

Consistency/UX
    Ensure all blocks are consistent in their behaviours, being able to be copy and pasted, consistent navigation, formatting etc. Most objects should be able to share a box with each other, however for stuff like code blocks could stick with being their own thing if its not practical to mix them in.
    → Copy and paste clones every block through the open-format round-trip, so
      nothing — including a block type from a newer version — loses anything in
      transit. Code blocks respect click position and are selectable without
      editing, and a letter typed on a selected box starts writing at its end.
    → An 86-agent sweep against the five consistency principles found 37
      defects and fixed them all; a later adversarial round found 22 more.
      Principle 4 became MECHANICAL rather than a promise: the equation face
      takes an editor and primitives only, so a maths box and one in a sentence
      cannot be told apart by anything downstream.
    The blocks-sharing-a-box model is the remaining design question.
    Simple unobtrusive animations consistently would be nice. A little bounce when a popup appears, the PDF viewer looking like it opens from the thumbnail, animation switching between menus, stuff like that
    → All three shipped: one shared dialog transition, toolbar tabs in the
      same motion register, and the PDF viewer growing out of its thumbnail.
    Centeralised settings page (including stuff like syncing, defaults for styles etc, and other information)
    → Shipped (the gear, top bar): theme, spell check, pen behaviour, doors to
      Sync, AI access and shortcuts, and the update check. Style DEFAULTS still
      live per feature; they join this page when the styles system grows
      defaults at all.
    Pressing 'Del' when clicking on a page or group doesnt delete it - only way to delete is right click and press delete
    → Del and Backspace both work on the row you clicked — page, section or
      group — and the sidebar became keyboard-navigable getting there. No
      confirmation, because it is a soft delete with thirty days of retention,
      but a snackbar names what went and where to get it back. A locked node is
      refused and told why.
    Hovering over a box makes its background solid, this makes aligning with other objects more difficult and is different to how it will be rendered
    → Hover no longer fills. The border already said "this one", which is what
      hover is for.
    Poor feedback given when selecting a cloud folder to sync with. Options to grey out however as the process can soemtimes take some time for larger notebooks a spinner icon where the select button was (or somewhere intuitive) would be great
    → A spinner takes the place of the button's label while the move runs, and
      the button does not change size doing it. Keyed to the button you
      PRESSED, because three actions in that dialog raise the same busy flag
      and a spinner on the wrong one is worse than none.
      Still silent: "Move the working file out of <folder>", which checkpoints
      a WAL, copies, and compares hashes with nothing on screen.

Code editor
    Remaining: HTML tag auto-closing, and string/comment awareness in the
    pairing rules (typing a quote inside a comment still pairs).
    Should follow VS or VScode styling where possible. i.e. comments in C# should be green. Maybe we offer the option to pick styles? Dont want to bog down the app with storing several styles for each language (assuming each style ends up language specific), if all styles are <5-10MB total then have them all preloaded, otherwise we should figure out a way to download them or compress them. 
        Basic linting for each language would be nice. Dont have to do anything complex on most languages (basic syntax errors would be helpful even), slightly more complex linting for JS and SQL would be very helpful as they can be run locally, however again if its going to add lots of 

General text editing
    → All five shipped. The lasting change is that there is now ONE grammar
      (markdown/md_syntax.dart) and ONE list engine (editor/list_editing.dart)
      instead of five files each with their own idea of what a bullet is —
      which is what let reading and writing disagree in the first place.
    → Wrapped list lines now hang under their own text, and `$$math$$` has a
      live preview.
    Remaining in this area, deliberately deferred: live preview for tables,
    fences and links, recursive inline nesting (**==x==**), rich paste that
    keeps structure from Word or a web page, and replacing the private
    {{#hex text}} colour syntax with portable HTML.
    Ontenote page links arent imported correctly. Start with onenote:https://ONEDRIVELINK, would be nice if we could attempt to convert this link to a page link within openote - Given page name (which may not be unique), section ID, and page ID. If a matching page cannot be found (as it could be linking to a notebook that hasnt been imported, a deleted page, etc) please allow it to continue linking to onenote (which the onenote: prefix automatically allows AFAIK)
    → Done for the Graph route: a notebook's own cross-references become real
      page links once every page has landed — after the import, not during it,
      because a link on the first page routinely points at the last one. A link
      whose target was not imported keeps its `onenote:` address exactly, as
      asked. Counted on a real notebook: 142 of them in sixty pages. The
      `.onepkg` route does not do this yet; the mapping there would have to
      come out of the binary format rather than out of `links.oneNoteClientUrl`.

Bringing a notebook over from OneNote
    → There is now a route that needs no export at all: sign in, pick a
      notebook, and it arrives — the ONLY route on macOS and Linux, since
      OneNote for Mac cannot export and there is no OneNote for Linux. It
      brings text and formatting, positioned outlines, lists, to-do tags,
      tables, images, equations, ATTACHMENTS (which the `.onepkg` route has
      never imported) and — the piece thought impossible — HANDWRITING.
    → **Page nesting cannot be done over Graph**, and this is settled rather
      than pending: Graph's page object carries neither `level` nor `order`,
      and asking for them by name returns neither. Subpages arrive as ordinary
      pages, so the `.onepkg` route stays the only way to keep them. The dialog
      says so beside the file route, in every language. What the wire actually
      looks like — nothing like the documentation suggests — is in
      docs/planning/onenote-over-graph.md.