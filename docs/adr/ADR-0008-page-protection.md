# ADR-0008: Password-protecting a page, section or section group

> **Status:** Proposed — design only, no protection code written yet · 2026-08-07
> **Related:** [ADR-0003](ADR-0003-storage-container.md) (SQLite `.onote`) · [ADR-0006](ADR-0006-sync-transport-and-text-model.md) (op log, §6a.4 reserves `Op.encryption`) · [Data Model](../specs/11-data-model-spec.md) · [File Format Spec](../specs/10-file-format-spec.md)

## Why this exists now

The ask, verbatim: *"Would like the ability to password protect a page (which
includes sub pages if applicable), a section, or a section group. Also being
able to configure if the password is required for every time its opened, if it
lasts for 10 minutes, 1 hour, or until app is closed."*

It is written here rather than built directly because this is the one feature in
the backlog where a half-implementation is **worse than nothing**. Everything
else ships degraded and the user can see the degradation. This one ships a
padlock, and if the padlock is decorative the user finds out only when it
matters.

---

## 1. The decision: this is encryption, not a locked door

A "locked page" could mean two very different things, and the cheap one is a
lie.

**UI gating** — put a dialog in front of the page and refuse to render it — is
about a day's work and would be **security theatre**. The notes would stay in
plaintext in a documented, open SQLite file that any SQLite browser opens in
seconds, and, worse, in the op log that syncs to the user's Google Drive folder.

That is not a theoretical objection. Page content is read by full-table scans
that never go near the page view. Verified in the current tree:

| Reader | Where | What it sees |
|---|---|---|
| Notebook search | `repository.dart:922` — `SELECT page_id FROM page_mirror WHERE json LIKE ?` | every page's full JSON |
| Content scan | `repository.dart:937` — `SELECT json FROM page_mirror` | every page |
| Blob-reference scan | `repository.dart:987` — `SELECT page_id, json FROM page_mirror` | every page |
| Version history | `page_versions.snapshot` (`database.dart:93`) | past copies of the page |
| The op log | `.onotebook/ops/<device>.oplog` | every `block.set` payload, **synced to the cloud** |

So a student who protects a page and then types a word from it into the search
box gets it straight back. **A dialog is bypassed by the app's own search.**

**Decision: content is encrypted at rest, or the feature is not offered.**

---

## 2. Threat model — stated plainly, and shown to the user

What this protects against:

- Someone with your unlocked laptop opening Openote and reading the page.
- Someone who obtains the `.onote` file, or the synced `.onotebook` folder from
  your cloud storage, and opens it with any tool.
- A person you share a notebook folder with reading a section you did not intend
  to share.

What it does **not** protect against, and the UI must say so:

- **Malware or another program running as you while the page is unlocked.** The
  key is in Openote's memory during the unlock window.
- **A forgotten passphrase.** There is no recovery. This is a property of doing
  it properly, not an oversight — see §7.
- **Metadata.** Titles, structure, page count and modification times stay
  readable. See §4.
- **Anything already exported.** A PDF or Markdown export made before locking is
  a plain file on disk and this feature cannot reach it.

---

## 3. Scope: nodes, not blocks

Protection attaches to a **node** — a page, a section, or a section group —
because that is what the ask names and what the navigator shows.

A correction worth recording, because the obvious-looking field is the wrong
one: `Block.access` (`models.dart:180`, "reserved (SYNC-9)") is **not** for
this. SYNC-9 is multi-user block ownership and edit-locking for classroom
collaboration — a write-permission field with no secret in it, on the wrong
entity. Using it would collide with a planned feature and put a per-subtree
secret on a per-block record.

**Inheritance.** Protecting a section protects every page in it, including pages
added later, and every sub-page. Protecting a section group protects everything
beneath. A node inherits protection from its nearest protected ancestor; there
is exactly one key per protected subtree, and nesting a protected node inside
another protected node is refused rather than layered — two passphrases to reach
one page is a worse experience than one, and doubles the ways to lose access.

---

## 4. What is encrypted, and what deliberately is not

**Encrypted:** the page's content — every block, which is the text, the ink
strokes, the maths, the tables and the references to images.

**Not encrypted, on purpose:**

- **Node titles.** The navigator has to draw the tree, and a tree of
  indistinguishable locked boxes is unusable. OneNote makes the same call.
- **Structure and timestamps.** Same reason.
- **Blob bytes.** An image referenced by a protected page keeps its bytes in the
  content-addressed store. Encrypting blobs per-subtree would break the property
  that makes them cheap — the same picture in two notebooks is one file — and
  the reference to the image is inside the encrypted content, so an attacker
  gets an unattributed pile of images rather than "the diagram on the page about
  X". **This is a real, disclosed limitation, not a hidden one**, and it is the
  one most likely to matter to a student who protects a page of photographed
  worksheets. Revisit if it turns out to matter more than blob de-duplication.

---

## 5. Cryptography

- **Key derivation:** Argon2id from the passphrase, per-subtree random salt,
  parameters stored beside the salt so they can be raised later without
  invalidating existing notebooks.
- **Content encryption:** an AEAD — XChaCha20-Poly1305 preferred for its
  nonce size, AES-256-GCM acceptable. Random nonce per encryption, never reused.
- **Two-level keys.** The passphrase unwraps a random per-subtree *content key*;
  the content key encrypts pages. Changing the passphrase then rewraps one key
  instead of re-encrypting every page, and a passphrase change does not have to
  touch the op log.
- **Verifier.** A small known-plaintext AEAD blob, so a wrong passphrase is
  reported as wrong instead of surfacing as corrupt pages.
- **No custom constructions.** Only library primitives, in the combinations
  their documentation describes.

**Library choice is open** and is the first implementation decision, not a
detail: there is currently no crypto dependency in either `app/pubspec.yaml` or
`rust/onote_core/Cargo.toml`. Dart (`cryptography`) keeps the build simple and
adds no FFI; Rust (RustCrypto) is faster and is where heavy work already lives,
at the cost of widening the FFI surface and the macOS build gap (task #42).
Decide with a spike, not in this document.

---

## 6. The op log is the hard half

A protected page's `block.set` ops must carry ciphertext, or the whole exercise
fails at the point the notebook syncs — which is exactly where it matters most.

ADR-0006 §6a.4 already reserved `Op.encryption` (currently always `'none'`) for
this, and the envelope stays readable: device, seq, lamport and op kind remain
plaintext so ordering, the fork check and compaction all keep working on a log
they cannot read. Only the payload is sealed.

Consequences that must be designed for, not discovered:

- **Replay without the key.** `Materializer` must carry an undecryptable op
  forward untouched rather than dropping it, exactly as it does for
  `OpKind.unknown`. A device that has the notebook but not the passphrase must
  still relay history correctly — otherwise unlocking on device B loses whatever
  device A wrote while locked.
- **The rebuild-equals-container invariant** (`sync_shadow_test.dart`) has to
  hold *with* the key and be skipped honestly *without* it.
- **Search must exclude locked pages** rather than scanning ciphertext and
  finding nothing — the difference between "no results" and "not searched" is
  the difference between a user trusting the result and being misled.

---

## 7. No recovery, and saying so before it matters

There is no backdoor, no recovery key escrowed anywhere, and no reset. A
forgotten passphrase means the content is gone.

The alternative — a recovery mechanism the app can use — is a second way in, and
a second way in that the app can walk through is one an attacker with the file
can walk through too. Given the audience is students protecting their own notes
on their own machines, the honest trade is: no recovery, and **say so at the
moment the passphrase is set**, in the dialog, before the first page is locked.

---

## 8. Session policy

The ask names the options directly: every time it is opened, 10 minutes, 1 hour,
or until the app closes. Stored per protected subtree.

The unlocked *content key* lives in memory only, and is dropped when the window
expires, when the app exits, and on an explicit "Lock now". It is never written
to disk, never to `workspace.json`, and never to the op log.

---

## 9. Format impact — additive only

Format v1 is frozen with a compatibility promise, and nothing here breaks it:

- `nodes` gains nullable columns for the protection record (salt, wrapped key,
  KDF parameters, verifier, policy). `_ensureSchema` already adds columns
  idempotently on every open.
- A protected page's `page_mirror.json` holds an encryption envelope object
  instead of the plain page object — same column, same type, different content.
- A new `node.protect` op kind. Older builds fold it to `OpKind.unknown` and —
  since `Op.rawTag` — round-trip it correctly.

**What an older build does with a protected notebook** must be settled before
implementation, and is the one place this could still go wrong: it will not
recognise the envelope, and the failure has to be a clear "this page is
protected; update Openote to open it" rather than a crash or, far worse, an
empty page that then gets saved back over the ciphertext. That is a data-loss
path and the implementation must close it explicitly.

---

## 10. Alternatives rejected

- **UI gating only.** §1. Would be dishonest.
- **Whole-notebook encryption.** Simpler, but the ask is per-section, and
  encrypting everything defeats search across the notes a student did not feel
  the need to protect.
- **OS keychain instead of a passphrase.** Convenient, but it protects against
  nobody who has the file, which is the main case in §2.
- **Encrypting titles as well.** Considered; makes the navigator unusable for a
  gain that §2 already discloses.

---

## 11. Implementation order

Each step is shippable and leaves the tree honest:

1. **Choose the crypto library** with a spike measuring key derivation on the
   slowest target machine.
2. **Envelope + key management**, with tests: derive, wrap, unwrap, wrong
   passphrase, tamper detection. No UI, no format changes.
3. **Encrypt page content at rest** in the container, plus the search exclusion.
   Behind a flag; not yet reachable from the UI.
4. **Encrypt the op log payloads**, plus undecryptable-op passthrough in the
   materializer, plus the old-build guard from §9.
5. **UI**: protect, unlock, session policy, the "no recovery" warning, and the
   disclosure from §2.

Nothing before step 5 is user-visible, and no step leaves plaintext where the
previous step promised ciphertext.
