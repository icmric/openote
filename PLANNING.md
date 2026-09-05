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
      Keyboard control SHIPPED, all four phases (docs/planning/v0.16): one
      keyboard map in code, Ctrl+/ renders it, the canvas traverses —
      Tab/arrows/Enter/Escape, Ctrl+arrows nudge — F6/Shift+F6 jumps
      between the sidebar, toolbar, page and open panel with a ring showing
      where you are, the task board walks and moves its cards on the
      arrows, the PDF reader turns pages, find goes backwards on
      Shift+Enter, and every dialog that can be confirmed or cancelled now
      has an Enter or an Escape that does it. i18n is the last of the trio,
      pending the which-languages decision.

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
    → v0.24: a word count sits at the end of the page's own row; one click
      gives characters, characters without spaces, and reading time at 200
      words a minute. It counts the page as it READS — `**bold**` is one
      word, a link is its label, an equation is one word wherever it sits,
      and bullets and heading hashes are not words — through the same
      classifier both renderers use, so a syntax added to the app is counted
      correctly in the same commit.  DONE
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
    → v0.22 delivered this: `Version history…` on a page shows per-block
      authors, edits and deletions, naming each device by its label and
      saying "another computer" when it cannot.  DONE
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
    → Three things already inline inside a text box today: pictures
      (![](sha256:…)), flashcards, and — since v0.18 — maths ($…$). All three
      go through ONE mechanism in editor/live_markdown_controller.dart: a
      placeholder that occupies exactly one code unit, so not a single caret
      offset moves. That is the existence proof; the open question is whether
      one general inline-atom syntax can carry every block type instead of a
      bespoke regex per kind. Designed in docs/planning/v0.18-visual-maths.md.

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
      writing at its end.
    → v0.23 was the big one here: an 86-agent sweep against the five
      principles found 37 confirmed defects and fixed every one, and
      principle 4 became MECHANICAL rather than a promise — the equation
      face takes an editor and primitives only, so a maths box and one in a
      sentence cannot be told apart by anything downstream. A later
      adversarial round found and fixed 22 more.
    The blocks-sharing-a-box model is the remaining design question.
    Simple unobtrusive animations consistently would be nice. A little bounce when a popup appears, the PDF viewer looking like it opens from the thumbnail, animation switching between menus, stuff like that
    → All three shipped: one shared dialog transition (quick fade +
      slight bounce), toolbar tab switches fade/slide in the same motion
      register, and the PDF viewer grows out of its thumbnail card.
    Centeralised settings page (including stuff like syncing, defaults for styles etc, and other information)
    → Shipped v0.7.1 (the gear, top bar): theme, spell check, pen
      behaviour, doors to Sync / AI access / shortcuts, About + update
      check. Style DEFAULTS still live only per-feature — they join the
      page when the styles system grows defaults at all.
    Pressing 'Del' when clicking on a page or group doesnt delete it - only way to delete is right click and press delete
    → v0.24: Del and Backspace both work on the row you clicked — page,
      section or group — and the sidebar became keyboard-navigable getting
      there. No confirmation, because it is a soft delete with thirty days
      of retention and the menu does not ask either, but a snackbar names
      what went and where to get it back. A locked node is refused and told
      why. It also closed a hazard nobody had reported: the shell's own
      Delete handler runs BEFORE focus dispatch, so with a block selected
      one Del used to destroy the block and the section.  DONE
    Hovering over a box makes its background solid, this makes aligning with other objects more difficult and is different to how it will be rendered
    → v0.24: hover no longer fills. The border already said "this one",
      which is what hover is for.  DONE
    Poor feedback given when selecting a cloud folder to sync with. Options to grey out however as the process can soemtimes take some time for larger notebooks a spinner icon where the select button was (or somewhere intuitive) would be great
    → v0.24: a spinner takes the place of the button's label while the move
      runs, and the button does not change size doing it — the label still
      measures, only its painting is swapped. Keyed to the button you
      PRESSED, because three different actions in that dialog raise the same
      busy flag and a spinner on the wrong one is worse than none.  DONE
      Still silent: "Move the working file out of <folder>", which
      checkpoints a WAL, copies and compares hashes with nothing on screen.

Code editor
    Remaining: HTML tag auto-closing, and string/comment awareness in the
    pairing rules (typing a quote inside a comment still pairs).
    Should follow VS or VScode styling where possible. i.e. comments in C# should be green. Maybe we offer the option to pick styles? Dont want to bog down the app with storing several styles for each language (assuming each style ends up language specific), if all styles are <5-10MB total then have them all preloaded, otherwise we should figure out a way to download them or compress them. 
        Basic linting for each language would be nice. Dont have to do anything complex on most languages (basic syntax errors would be helpful even), slightly more complex linting for JS and SQL would be very helpful as they can be run locally, however again if its going to add lots of 

General text editing
    → ALL FIVE SHIPPED. The lasting change is that there is now ONE grammar
      (markdown/md_syntax.dart) and ONE list engine (editor/list_editing.dart)
      instead of five files each with their own idea of what a bullet or a
      marker is — which is what let reading and writing disagree in the first
      place.
      · Dot points no longer move: the editor hangs the marker in the same
        22px gutter the reader uses, so the body text starts at the same x at
        every nesting level (edit_view_metrics_test now pins it horizontally,
        which is why this went unnoticed — only height was pinned before).
      · Ctrl+B with no selection formats the WORD the caret is in instead of
        writing a bare **** into the note, toggling off works from inside a
        run, and the toolbar buttons light up for whatever is on at the caret.
      · ***bold italic*** now parses as one run. The importer was already
        emitting it correctly; both Dart parsers lacked the branch, so it
        degraded to bold plus a stray asterisk — reachable without importing
        by pressing Ctrl+B then Ctrl+I.
      · Blank lines survive the import (an empty paragraph pushed no Line at
        all, so the gap was gone before Dart saw it).
      · `* ` and `+ ` are real bullets everywhere. No preference was added —
        Enter continues with whichever marker that line already uses, which
        removes the decision rather than adding a setting.
      Also, because the same investigation turned them up: Enter continues a
      list and exits an empty one, Tab/Shift+Tab nest, Backspace unwraps an
      item, ordered lists renumber themselves, and the list buttons stopped
      crashing at offset 0, destroying checkboxes and eating indentation.
    → v0.22 finished two of these: WRAPPED list lines now hang under their
      own text (a custom paragraph, `_hangWrappedListLines`, pinned by
      `app/test/hanging_indent_test.dart`), which is also the answer to the
      "lot of movement with dotpoints" note that sat beside it; and
      `$$math$$` has live preview.
    Remaining in this area, deliberately deferred: live preview for tables,
    fences and links, recursive inline nesting (**==x==**), rich paste that
    keeps structure from Word or a web page, and replacing the private
    {{#hex text}} colour syntax with portable HTML.
    Ontenote page links arent imported correctly. Start with onenote:https://ONEDRIVELINK, would be nice if we could attempt to convert this link to a page link within openote - Given page name (which may not be unique), section ID, and page ID. If a matching page cannot be found (as it could be linking to a notebook that hasnt been imported, a deleted page, etc) please allow it to continue linking to onenote (which the onenote: prefix automatically allows AFAIK)
    → DONE for the over-the-internet import. A notebook's own
      cross-references are rewritten to real page links once every page has
      landed — after the import, not during it, because a link on the first
      page routinely points at the last one. A link whose target was not
      imported keeps its `onenote:` address exactly, as asked, which still
      opens OneNote. Counted on a real notebook: 142 of them in sixty pages.
      The `.onepkg` route does not do this yet; the mapping there would have
      to come out of the binary format rather than out of `links
      .oneNoteClientUrl`.

Bringing a notebook over from OneNote
    → The whole of this changed. There is now a route that needs no export at
      all: sign in, pick a notebook, and it arrives — which is the ONLY route
      on macOS and Linux, since OneNote for Mac cannot export a notebook and
      there is no OneNote for Linux.

      It imports text and formatting, positioned outlines, lists and OneNote's
      to-do tags, tables, images (floating and in-flow), equations, ATTACHMENTS
      (which the `.onepkg` route has never imported at all), and — the piece
      thought impossible — HANDWRITING, via `includeinkML=true`, which returns
      the ink in a second part of a multipart body.

      One thing it cannot do, and this is settled rather than pending:
      **page nesting**. Graph's page object carries neither `level` nor
      `order`, and asking for them by name returns neither — `$select=id,title,
      level` comes back as `[id,title]`. So subpages arrive as ordinary pages,
      and the `.onepkg` route stays the only way to keep them. The dialog says
      so beside the file route, in all seven languages.

      What the wire actually looks like — and it is nothing like the
      documentation suggests — is written down in
      docs/planning/onenote-over-graph.md, with the measurements behind every
      decision.