# Architecture Decision Records

One ADR per decision that is hard to reverse: the context, the options weighed,
the decision, its consequences, and — because good decisions age — explicit
**revisit triggers**.

ADRs are not edited destructively. A decision that is overtaken gets a note at
the top saying what changed and what to believe instead; a decision that is
replaced outright gets a new ADR that links back, and this one is marked
*Superseded*.

| ADR | Decision | Where it stands |
|-----|----------|-----------------|
| [0001](ADR-0001-application-framework.md) | **Flutter/Dart UI + Rust core** | Built. Reached by hand-written `dart:ffi`, not `flutter_rust_bridge`, and the core does no sync |
| [0002](ADR-0002-crdt-library.md) | CRDT: **Loro**, behind our own Rust API | **Never integrated.** Its scope has narrowed to the text sequence; re-argue before building |
| [0003](ADR-0003-storage-container.md) | **One SQLite `.onote` per notebook** + open-folder export | Built. The container holds no CRDT and no blob bytes |
| [0004](ADR-0004-editor-engine.md) | **Keep the editor we own**, behind the `OnoteTextEditor` seam | Built. The bake-off was deliberately not run |
| [0005](ADR-0005-licensing.md) | **AGPL-3.0 app / Apache-2.0 libs / CC0 spec** | Ratified |
| [0006](ADR-0006-sync-transport-and-text-model.md) | Sync: **append-only per-device op log** in a `.onotebook` directory | Transport built. **The text model it asks for is not** |
| [0007](ADR-0007-blob-lifecycle.md) | Blob collection: **a grace period, not a handshake** | Designed. **Nothing has ever deleted a blob** |
| [0008](ADR-0008-page-protection.md) | Page protection: **encryption, not a locked door** | Designed. A passcode gate ships instead, and says so |

The two worth reading before touching storage are **0006** (where the durable
bytes live) and **0007** (why nothing deletes them yet).
