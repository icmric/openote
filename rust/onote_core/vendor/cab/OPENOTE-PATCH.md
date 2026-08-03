# Openote's patch to `cab`

This directory is a **vendored copy of the `cab` crate** (upstream:
<https://github.com/mdsteele/rust-cab>, crates.io `cab 0.6.0`), MIT-licensed.
Upstream's `LICENSE` is retained unchanged.

Openote adds **two public methods and nothing else**. A byte-for-byte diff
against the crates.io release shows no other changes. This file exists so that
the delta is discoverable without performing that diff.

## Why

A `.onepkg` OneNote package is a Microsoft Cabinet containing every section
`.one` file, almost always as a **single LZX-compressed folder**. LZX is a
continuous stream: to read the bytes of file *N* you must decompress everything
before it.

Upstream's `Cabinet::read_file` starts from the beginning of the folder every
time it is called. Over a 27-file package that is quadratic — the folder prefix
is decompressed 27 times. Measured on a real 48 MB / 324-page notebook, this
accounted for roughly **35 s of a ~41 s import**.

The fix is to decompress the folder **once** and have the caller slice it
per-file, which requires knowing where each file starts in the uncompressed
stream — information the crate parsed but did not expose.

## The two additions

| Symbol | File | What it does |
|---|---|---|
| `FileEntry::uncompressed_offset() -> u32` | `src/file.rs` | Exposes the already-parsed offset of this file's data within its folder's uncompressed stream. Pure accessor; no logic. |
| `Cabinet::read_folder_data(index, limit) -> io::Result<Vec<u8>>` | `src/cabinet.rs` | Decompresses a whole folder in one pass, capped at `limit` bytes. |

Both are marked `(Openote patch.)` in their doc comments.

### One deliberate behavioural choice in `read_folder_data`

It **keeps whatever decompressed successfully** rather than propagating a
decompression error:

```rust
let _ = reader.take(limit).read_to_end(&mut out);
Ok(out)
```

This is intentional and was a bug fix (review finding C-5). Because a folder is
one continuous stream, a single corrupt data block would otherwise abort the
whole read — and in a `.onepkg` the folder *is* the entire notebook, so one bad
block lost every section. Returning the recovered prefix lets the caller import
every section that decompressed and skip only those that fall beyond it.

The `limit` argument is the zip-bomb guard: the caller
(`src/onepkg.rs`) derives an expected size from attacker-controlled header
fields, so the cap must be applied here rather than trusted upstream.

## Invariant this patch depends on

> Slicing the folder buffer at `entry.uncompressed_offset()` for
> `entry.uncompressed_size()` bytes yields exactly what `read_file(entry.name())`
> would have returned.

If a dependency bump ever bypasses this vendored copy, that invariant silently
stops being tested and the import silently gets ~4× slower — or worse, wrong.
`Cargo.toml`'s `[patch.crates-io]` section is what keeps the vendored copy in
force; do not remove it without re-measuring import time.

## Updating from upstream

1. Diff the new upstream release against this directory to confirm the only
   differences are the two additions above.
2. Re-apply both methods.
3. Re-run `cargo test` — including the tests that pin the invariant above.
4. Re-measure a whole-notebook import; a regression to ~4× slower means the
   patch is not in force.
