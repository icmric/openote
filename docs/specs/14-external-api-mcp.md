# 14 · External API & MCP Spec

> **Purpose:** The contract between Openote and programs that read or write a
> user's notes — AI assistants over MCP first, anything JSON-RPC-shaped in
> principle. This document is normative for the tool surface, the wire
> format, the security posture, and — most importantly — **the rule that
> keeps the API consistent as the app grows** (§2). A feature PR that adds
> or changes a block type, a page property, or a notebook operation should
> need NO change here to remain API-correct; if it does need one, that is a
> design smell to stop on.
>
> Status: v1 shipped 2026-08-10 (app-hosted server, tools in §5).
> v1.1 2026-10-09: edit/insert/delete and tree tools, native Markdown
> import, content checking, layout feedback (§5.1–§5.4). One breaking
> change, called out in §5.5.
> Additive changes ride minor revisions; removing or renaming a tool or
> field is a breaking change and needs a deprecation cycle.

## 1. What this is

Openote hosts a local **MCP server** while the app runs: AI tools the user
already uses (Claude, editors, agents) connect to it and can read pages,
search, create pages, append content, and make flashcards — "read stuff but
also write stuff" (PLANNING.md). It is a *user-facing feature with a
security surface*, and both halves are specified here.

## 2. The consistency rule: THE FILE FORMAT IS THE API

The single load-bearing decision. Tools do not define their own schemas for
notebook content; they speak **the page JSON of the File Format Spec (§10)
and Data Model Spec (§11)** — the same `{blocks: [...], page: {...}}` the
container mirrors, the exporter writes, and every build round-trips.

What this buys, permanently:

- **New block types are API-visible the day they exist.** `read_page`
  returns whatever the page holds — a `board`, an `embed`, next year's
  type — because it serialises through `Block.toJson`, which carries
  unknown types by `rawType` and unknown fields verbatim. Nobody updates
  the API when they add a feature; the API was never a second schema.
- **Writes are validated by the same code that reads files.** An
  `append_blocks` payload goes through `Block.fromJson` — the exact parser
  a synced page goes through — so a malformed block is rejected identically
  everywhere, and a well-formed one cannot desync the mirror, the op log,
  or another device.
- **The API documentation is the format documentation.** A client that
  wants to write a table block reads Data Model Spec §5, not a parallel
  API reference that would drift.

**Knowing a type's keys is not a second schema.** v1 accepted any `content`
map, and a code block sent as `{"code": …}` parsed, synced and drew as an
empty box — `CodeBlockView` reads `source`. What each known type keeps in
`content` is now written down ONCE, beside the model, in
`model/block_schema.dart`: the API checks writes against it and
`describe_block_types` serves it. It is the format's documentation, not
the API's. A type with no entry there is not checked at all, and an
unknown key is a warning, never a refusal (the unknown-field rule, Data
Model Spec §3) — so a new block type still works through the API the day
it exists. Adding a type should add its entry there; forgetting to only
costs the check.

The corollary rule for FUTURE WORK: **a new capability is exposed by
generalising an existing tool over the format, never by a bespoke tool
schema.** A "create board" need is `append_blocks` with a board block. Only
genuinely new *operations* (a new verb, not a new noun) justify new tools.

## 3. Transport & lifecycle

- **Streamable HTTP** (MCP revision 2025-03-26+): JSON-RPC 2.0 over
  `POST /mcp`, JSON responses. Stateless — no session ids required — which
  every current client handles and which keeps the server ~free of state
  that could desync from the app.
- Served by the running app on **127.0.0.1 only**, on a port chosen at
  enable-time and shown in the settings UI. If the app is closed, the API
  is down: the server has no life of its own, holds no data of its own,
  and every request executes against the live `AppState` on the UI isolate
  (requests are small; §6 caps them).
- Methods: `initialize`, `notifications/initialized`, `ping`,
  `tools/list`, `tools/call`. Everything else answers method-not-found.
  Unsupported protocol revisions negotiate down to `2025-03-26`.

## 4. Security posture (normative)

1. **Off by default.** Enabling is an explicit user action in settings.
2. **Bearer token**, generated at enable, stored in the workspace,
   shown once in the UI as part of the ready-to-paste client config.
   Requests without `Authorization: Bearer <token>` are 401.
3. **Origin validation**: any request carrying an `Origin` header that is
   not a localhost origin is rejected (DNS-rebinding defence, per the MCP
   spec). Non-browser clients send no Origin and pass. "Localhost" is the
   parsed host, exactly `localhost` or `127.0.0.1` over `http` — never a
   prefix of the string, which `http://localhost.evil.com` would pass.
4. **Loopback bind only**, never `0.0.0.0`. Remote access is out of scope
   until it can be designed as its own feature.
5. Request bodies over **1 MB** are rejected; tool inputs inherit the
   app's own caps (block counts, text sizes) by construction of §2.
6. Writes are **real edits**: they go through the same paths as typing —
   undoable when the page is open, recorded into the op log always, synced
   like anything else. There is no side door that mutates storage without
   the recorder seeing it. (This is also a consistency rule for future
   tools: a write tool that cannot route through the ordinary write path
   must not ship.)
7. **Anything a passcode covers is closed**, in every notebook, whether or
   not it is unlocked in the app: a section group, section or page with a
   passcode, and everything the app counts as beneath it, subpages
   included. It is not listed (a listing says, once and without a count,
   that something was withheld), not searched, not read, and not changed.
   No tool takes a passcode, so there is nothing to guess at. No write may
   change what a passcode covers either — re-indenting, moving, adding or
   deleting a page is refused if any page would come out from under one,
   or go in under one — and no block may be a page window onto a covered
   page. Like the gate itself, this closes Openote's door and makes no
   claim about the file: a tool that can read the disk can read the
   container (`state/page_protection.dart`), and the AI dialog says so.
   (Consistency rule for future tools: resolve every node and page id
   through the same gate, and check a tree change against its result.)

## 5. Tools (v1)

Content nouns are page JSON (§2). Ids are the stable UUIDs of OPEN-12.

| Tool | Input | Output | Notes |
|---|---|---|---|
| `list_notebooks` | — | `[{id, title, open}]` | `open` marks the one loaded in the UI |
| `list_pages` | `notebookId?`, `sectionId?`, `kind?`, `query?`, `maxLevel?`, `offset?`, `limit?` | `{total, offset, nextOffset?, items: [{id, title, kind, parentId, level}]}` in tree order | defaults to the open notebook; `limit` defaults to 100 (max 1000). See §5.5 |
| `read_page` | `pageId`, `format?: "json"\|"markdown"\|"layout"` | page JSON, the Markdown projection, or each block's box plus overlaps | markdown uses the exporter's flattening (§10's projection caveats apply); layout is the cheap "did that land where I meant" check |
| `search` | `query`, `notebookId?` | `[{pageId, title, snippet}]` | the app's own brute-force search |
| `describe_block_types` | — | per-type content keys, code language ids, table form, layout constants | served from `model/block_schema.dart` (§2) |
| `create_page` | `title`, `sectionId?`, `notebookId?`, `afterPageId?`, `level?`, `markdown?`, `blocks?` | `{pageId, added?, blocks?}` | end of the given (or first) section, or after `afterPageId` and its subpages; filled in the same call |
| `create_pages` | `pages: [{title, markdown?, blocks?, level?}]`, `sectionId?`, `notebookId?` | `{pages: [{pageId, title, added}]}` | ≤ 50; every page is parsed before any is written — all or nothing |
| `append_blocks` | `pageId`, `blocks: [BlockJSON]` | `{added, blocks: [box]}` | parsed by `Block.fromJson`, checked by the block schema; placed below existing content |
| `append_markdown` | `pageId`, `markdown`, `literal?` | `{added, blocks: [box]}` | native objects, §5.1; `literal` keeps one text block as written |
| `insert_blocks` | `pageId`, `afterBlockId`\|`y`, `blocks?`, `markdown?` | `{added, blocks, shifted}` | everything at or below the insertion line moves down by the room taken |
| `update_block` | `pageId`, `blockId`, `content?`, `replaceContent?`, `x?`, `y?`, `w?`, `h?` | `{block: box}` | `content` merges by key (`null` removes); the result is checked like a new block, and refused whole |
| `delete_blocks` | `pageId`, `blockIds` | `{deleted}` | all ids must exist, or nothing happens |
| `move_blocks` | `pageId`, `blockIds`, `dx?`, `dy?` | `{blocks: [box]}` | ink moves with its box (strokes are page-absolute) |
| `rename_page` | `pageId`, `title` | `{pageId, title}` | also takes a section id |
| `move_page` | `pageId`, `sectionId?`, `afterPageId?`, `level?` | `{pageId, sectionId, level}` | carries its subpages; same notebook only |
| `delete_page` | `pageId` | `{deleted}` | soft delete — the recycle bin, undoable on the open notebook |
| `create_flashcards` | `pageId`, `cards: [{front, back}]` | `{added}` | writes `?[front](back)` lines — the study system's own on-page form, so decks/scheduling pick them up with no new machinery |

Errors are JSON-RPC tool errors with human-readable messages (unknown ids
name the notebook searched; malformed blocks quote the parser's reason, and
a misspelt key names the right one). Every write that places blocks returns
each block's **box** — `{id, type, x, y, w, h, heightIs}` — and a `warnings`
list for anything worth fixing that was not worth refusing: an undocumented
key, an unknown code language, an overlap.

### 5.1 Markdown becomes native objects

`append_markdown`, `insert_blocks`, `create_page` and `create_pages` take
Markdown and split it the way the app holds it (`markdown/md_blocks.dart`):
fenced code → `code` blocks, language resolved through the picker's alias
table (`languageFor`; unknown → `text`); GFM pipe tables → inline table atoms
inside the surrounding text block (the shape Insert → Table writes); the
rest → text blocks, one per run of prose between code. v1 wrote one 480px
text block holding raw pipes and fences — rendered, but not editable as
tables or runnable as code. `atomizePipeTables` is the reusable half, meant
also for the editor's "convert pipe tables when leaving edit mode".

Converting is the default because an agent that writes Markdown almost always
meant the thing, not the syntax (the [v1.0.2 plan](../planning/v1.0.2.md)
§20, fix 3). `append_markdown` takes `literal: true` for the other case: one
text block, exactly as written, as v1 did.

`append_blocks`'s description names every type in `model/block_schema.dart`,
generated from it, so an agent sees that `code` and `table` exist without
calling `describe_block_types` first (§20, fix 1).

A `table` BLOCK written through `append_blocks` is stored already converted
to that inline form (`tableBlockAsText`), since the app converts every table
block it opens anyway.

### 5.2 Layout

Blocks without `x`/`y` are stacked down the left margin
(`pageLeftMargin` 44, from `contentTop` 92), 16px apart, 24px below
existing content, rounded onto the grid when the live editor snaps. Heights
come from, best first: a stored `h`, the canvas's measured `renderSizes`
(only for the page on screen), then `estimateBlockHeight`
(`model/block_metrics.dart`) — code from its line count at CodeBlockView's
19px lines + 60px chrome, tables from their rows, a paragraph's inline
tables from their own size, headings at their own sizes. The estimate errs
high: a gap is a nit, an overlap hides writing. It replaced a flat 60px for
every non-text block, which stacked a 30-line code block as if it were one
line tall. `AppState.estimatedHeight` delegates to it, so page growth and
the PDF paths got the same fix.

A rendered PNG (`render_page`) was considered and deferred: the canvas
cannot be built off screen cheaply, and `read_page` `format: "layout"`
answers the question clients actually had — where did everything land, and
does anything overlap.

### 5.3 Edits and undo

On the open page every write tool is ONE `pushUndo` step, then the live
editor's own `addBlock` / `removeBlock` / `updateBlock`; content changes bump
`docRevision` so a live text box rebuilds with the new text. Other pages go
through `importPage`. Tree writes go through `importNode` (the recorder
sees them); `delete_page` is `deleteNodeIn`, which is `deleteNode` itself
for the open notebook. Writes to a notebook this build may only read
(`notebookIsReadOnly`) are refused.

### 5.4 Ids

Every block written gets a **fresh id**, whatever `id` the caller sent, and
the result says which. Writing a block is an import, and an import mints
(Data Model Spec §2 rule 3): a block copied out of `read_page` of one page
and appended to another would otherwise carry its id across, and ids must be
unique in the notebook (§8.1) — which no check of the target page alone can
see. To change an existing block, use `update_block`.

### 5.5 The one break: `list_pages` output

v1 returned a bare array of every node. On a real notebook that was 56k
characters on one line, past a client's token limit. v1.1 returns
`{total, offset, nextOffset?, items}`, 100 items by default, with filters.
This is a field-shape change, which the status note says needs a
deprecation cycle; it was taken anyway because the v1 shape was unusable at
exactly the size it mattered, and the only consumers are models that read
`tools/list` at connect time. Do not repeat the exception for anything with
code clients.

## 6. Constraints

- Block-writing tools accept at most **100 blocks** per call (Markdown
  counts after splitting); Markdown caps at **256 KB** per call;
  `create_pages` at **50 pages**. Big imports belong in the app's importers.
- `read_page` of a page holding binary-backed blocks (images, ink refs,
  PDFs) returns the REFERENCES (hashes), not bytes — blob transfer is a
  future, deliberate addition (it changes the size profile entirely).
- Tools never execute anything: a code cell arrives and leaves as text.
  (An AI asking to RUN a cell would be a new verb — designed, not slipped
  in, because §4.6 of the local-code plan applies doubly to remote
  callers.)

## 7. The future-additions checklist

For any PR that touches the model or adds a feature, the API questions are:

1. Does the new content flow through `Block.toJson`/`fromJson`? Then the
   API already carries it — done.
2. Is it a new *operation* (not representable as read/append of format
   JSON)? Then it needs a tool here, a row in §5, and the §4 checklist
   applied to it.
3. Does it change what a write can do (new side effects)? Re-check §4.6:
   still routed through the ordinary write path? Still recorded?
4. Never: a tool-specific schema for content that has a format
   representation. That is how APIs drift; §2 exists to forbid it.

## 8. Connecting a client: the no-jargon rule

The audience for the AI-access dialog is a year-10 student who does not
know what MCP is and has never opened a terminal (Eric, 2026-08-10: "I
want to dejargon this as much as possible, and make it as simple as
possible"). Field-tested the hard way: v1 of the dialog handed over a
config JSON with no destination, and the first real user landed in a
terminal error.

Normative for this dialog and any future connection surface:

- **The visible path is a switch and per-tool Connect buttons.** Openote
  writes each connection itself into the tool's own settings file —
  exactly what that tool's `mcp add` command would do, minus the
  terminal. Implementation and its safety rules: `api/mcp_connect.dart`.
  The client landscape as of 2026-08:

  | Tool | Status | Why |
  |---|---|---|
  | Claude Code | ✅ button | user-scope `mcpServers` in `~/.claude.json` |
  | Claude app (chat) | ✅ button | `mcpServers` in `claude_desktop_config.json` — `%APPDATA%/Claude` on Windows, `~/Library/Application Support/Claude` on macOS, `~/.config/Claude` elsewhere. Takes `url` + `headers`, so this server needs no changes |
  | Gemini CLI | ✅ button | `mcpServers` (`httpUrl`) in `~/.gemini/settings.json` |
  | ChatGPT **desktop** app | ✅ button | `[mcp_servers.openote]` in `~/.codex/config.toml` — the same path on every platform, shared with the Codex CLI and the IDE extension. TOML, so it is edited by the line rather than re-emitted, to keep the user's comments |
  | ChatGPT **website** | ❌ impossible | its connectors run on OpenAI's servers, which cannot reach `127.0.0.1` on the user's machine |
  | Gemini app | ❌ impossible today | same: cloud-side connectors cannot see a local server |
  | Anything else MCP-capable | Advanced fold | generic config JSON + CLI one-liner |

  > **Table revised 2026-10-01.** The Claude *app* was never in it and is how
  > most people use Claude; it is now a button. ChatGPT's desktop app is a
  > button too: OpenAI's documentation gives a config FILE,
  > `~/.codex/config.toml`, shared with the Codex CLI and the IDE extension,
  > accepting a Streamable HTTP URL with static `http_headers` — so §4's
  > bearer token is carried and nothing on the server changed. The website's
  > row is unchanged and always will be while connectors run server-side.
  >
  > `http_headers` and not `bearer_token_env_var`: the latter names an
  > environment variable, which Openote cannot set inside another app's
  > process. The token is therefore in the file in clear, as it already is in
  > the JSON configs — hence the dialog calling it a password.
  >
  > Not yet confirmed by a human: that the desktop app picks the entry up.

  The dialog states the ❌ rows in plain words rather than hiding them —
  "can't yet, their connectors run on the company's servers" — so nobody
  hunts for a setting that does not exist. Revisit if either vendor ships
  a desktop-side MCP client; the button pattern is ready for it.
- **Never destroy another app's config.** Merge, don't overwrite; a file
  that doesn't parse is refused, not clobbered; the first write of a
  pre-existing file leaves a one-time `.openote-backup` beside it.
- **Honest status.** "Connected" only when Claude Code shows signs of
  being installed; otherwise say plainly what to install and that the
  connection will work once it is.
- **Self-healing.** Whenever the server starts, an entry the user
  previously made is refreshed (ports move); an entry they never made is
  never created uninvited.
- **Jargon lives behind the Advanced fold.** MCP, ports, tokens, config
  JSON and the CLI one-liner exist for other tools' users — below an
  expander, never in the primary path. A future "connect X" for another
  client follows the same shape: one button that does the work, or it
  isn't simple enough to ship.
