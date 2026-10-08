# Planning

One document per release-sized piece of work. These are the **reasoning**: what
was reported, what was measured, which options were weighed, and what it cost.
[CHANGELOG.md](../../CHANGELOG.md) is what changed; these say why.

| | |
|---|---|
| [backlog.md](backlog.md) | What to do next, ranked — and what has been decided against. **Start here.** |
| [v1.0.2.md](v1.0.2.md) | The release being worked on now |
| [archive/](archive/) | Work that has shipped, kept for the reasoning |

## Open plans

Designed but not built. Each already contains the thinking, so read it before
starting the work.

| Document | State |
|---|---|
| [v0.19 — everything in one box](v0.19-everything-in-one-box.md) | One general inline-atom pipeline for every block type. Three things already inline through one mechanism, which is the existence proof |
| [v0.21 — outdo OneNote at maths](v0.21-outdo-onenote-maths.md) | Aligned derivations, units, chemistry, equation numbering, spoken maths, ranked |
| [v0.12 — making sync feel live](v0.12-sync-latency.md) | Where the latency goes, and what would make a two-device edit feel immediate |
| [v0.13 — op-log compaction](v0.13-op-log-compaction-review.md) | **Rejected as designed.** The disk cost is real; this fix was not safe. Do not implement without answering every objection in it |

## Reference

| Document | |
|---|---|
| [onenote-over-graph.md](onenote-over-graph.md) | What Microsoft Graph actually sends, measured against a real notebook rather than read out of the documentation |

## House style

The report in the owner's own words, then a measurement, then the options with
what each one cannot do, then the decision. Numbers in tables, not adjectives.

Three things to keep out: a progress log (the changelog has it), a status line
that has to be updated by hand, and anything struck through. If an item shipped,
delete it; if it moved to a later release, move it to that release's document.

**Numbers like `v0.19` are work items, not releases.** Releases are in the
changelog and the tags; several of these landed inside one release.
