# Architecture Decision Records

Each ADR captures one significant, hard-to-reverse decision: the context, the options weighed, the decision, its consequences, and — because good decisions age — explicit **revisit triggers**. Statuses: **Accepted (provisional)** = the decision the specs and code build on, with documented triggers that would reopen it · **Open** = decision pending a defined process · **Proposed** = needs stakeholder ratification.

| ADR | Decision | Status |
|-----|----------|--------|
| [0001](ADR-0001-application-framework.md) | Application framework: **Flutter/Dart UI + Rust core** | Accepted (provisional) |
| [0002](ADR-0002-crdt-library.md) | CRDT: **Loro**, behind our own Rust API; `yrs` fallback | Accepted (provisional) |
| [0003](ADR-0003-storage-container.md) | Storage: **SQLite `.onote` container** + open-folder export | Accepted (provisional) |
| [0004](ADR-0004-editor-engine.md) | Rich-text engine: **super_editor vs appflowy_editor bake-off** | Open (spike-gated) |
| [0005](ADR-0005-licensing.md) | Licensing: **AGPL-3.0 app / Apache-2.0 libs / CC0-MIT spec** | Proposed |

Convention: new ADRs are numbered sequentially, never edited destructively — a superseding ADR links back and flips the old one to *Superseded*.
