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
   spec). Non-browser clients send no Origin and pass.
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

## 5. Tools (v1)

Content nouns are page JSON (§2). Ids are the stable UUIDs of OPEN-12.

| Tool | Input | Output | Notes |
|---|---|---|---|
| `list_notebooks` | — | `[{id, title, open}]` | `open` marks the one loaded in the UI |
| `list_pages` | `notebookId?` | `[{id, title, kind, parentId, level}]` in tree order | defaults to the open notebook |
| `read_page` | `pageId`, `format?: "json"\|"markdown"` | page JSON, or the Markdown projection | markdown uses the exporter's flattening (§10's projection caveats apply) |
| `search` | `query`, `notebookId?` | `[{pageId, title, snippet}]` | the app's own brute-force search |
| `create_page` | `title`, `sectionId?` | `{pageId}` | lands in the given (or first) section |
| `append_blocks` | `pageId`, `blocks: [BlockJSON]` | `{added}` | validated by `Block.fromJson`; placed below existing content |
| `append_markdown` | `pageId`, `markdown` | `{added}` | convenience: one text block; casual clients need no format knowledge |
| `create_flashcards` | `pageId`, `cards: [{front, back}]` | `{added}` | writes `?[front](back)` lines — the study system's own on-page form, so decks/scheduling pick them up with no new machinery |

Errors are JSON-RPC tool errors with human-readable messages (unknown ids
name the notebook searched; malformed blocks quote the parser's reason).

## 6. Constraints

- `append_blocks` accepts at most **100 blocks** per call; text payloads
  cap at **256 KB** per call. Big imports belong in the app's importers.
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

- **The visible path is a switch and one button.** "Connect Claude Code"
  writes the connection itself: Openote merges an `openote` entry into
  `~/.claude.json` (`mcpServers`, user scope) — exactly what
  `claude mcp add --scope user` would do, minus the terminal.
  Implementation and its safety rules: `api/mcp_connect.dart`.
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
