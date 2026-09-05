# Importing OneNote over Microsoft Graph

> What the service actually sends, measured against a real notebook rather than
> read out of the documentation. Written because three fixes in a row were built
> on an assumption about the markup and three in a row were wrong.
>
> The probes that produced all of this live in `app/test/manual/`. Each is
> skipped unless an environment variable names somewhere to write, so they cost
> the suite nothing, and each reuses the app's own sign-in — running one cannot
> invalidate the credential the app is using.

## Why this route exists

Openote could only take a notebook a human had exported by hand. On two of the
three platforms that is not friction, it is a wall: **OneNote for Mac cannot
export a notebook at all** — no `.one`, no `.onepkg`, only a page at a time as
PDF — and there is no OneNote for Linux. The usual workaround does not exist
either: checked on a real machine, the whole OneDrive tree held one stray
`.one` and zero `.onetoc2`, because a modern notebook lives in OneNote's cloud
store and is never synced to disk as files.

## What the wire actually looks like

Counted over sixty real pages unless stated otherwise.

| Thing | What OneNote sends |
|---|---|
| Text formatting | **Span styles only.** 375 `font-weight`, 173 `color`, 124 `font-style`, 90 `font-family` — and **not one** `<b>`, `<i>`, `<strong>` or `<em>` in the entire sample. |
| Layout | One absolutely-positioned `<div>` per outline, with `left`, `top` and `width` in CSS px. Paragraphs carry only `margin-top`/`margin-bottom`. |
| Blank lines | 332 `<br>` against 4 genuinely empty `<p>`. A gap is usually a paragraph holding a single `<br>`. |
| Tables | **No widths at all.** Every one of 42 `<td>` carried exactly one style property: `border`. The `<table>` carries `border` and `border-collapse`. |
| Equations | MathML, on 6 pages in 60. **One `<mi>` per letter** — `sin` is three elements. Invisible operators (U+2061 and friends) sprinkled through. Variables in Mathematical Italic (theta is U+1D703, not U+03B8). Uses `<mfenced>`, removed from MathML 4. |
| Images | 11 pages in 60. `width`/`height` attributes, `src` and `data-fullres-src`. **Some carry `style="position:absolute;left:…;top:…"` and some carry none** — the positioned ones are floating, the rest flow. |
| Attachments | `<object data-attachment="name.pdf" type="application/pdf" data="…/resources/…/$value" />`. One page in 60. |
| Handwriting | **Available**, but only with `includeinkML=true`, which changes the response into MIME multipart with an `application/inkml+xml` part. |
| Page nesting | **Not available at all.** See below. |
| Internal links | 142 `<a href="onenote:…">` with `page-id` and `section-id`. Converted to real page links after the import. |

### Ink, in detail

```xml
<inkml:trace contextRef="#ctxCoordinatesWithPressure" brushRef="#{…}{106}"
>2069 8152 15199, 2069 9773 15199</inkml:trace>
```

- Points comma-separated, values space-separated, in the channel order the
  referenced `<inkml:context>` declares — `X Y` or `X Y F`.
- Coordinates are **himetric**: hundredths of a millimetre, so 2540 to the inch
  against the canvas's 120 px.
- Pressure is an integer against the channel's declared `max`, 32767.
- Brushes are declared once and referenced, carrying width (himetric), colour
  and transparency.
- **Every page carries `<inkml:traceGroup />` whether or not anything was ever
  drawn**, so the part's presence proves nothing; only its contents decide.

Measured: 301 traces on one page, 292 KB against the 6 KB a typical page weighs.

## The hierarchy cannot be imported

This is settled, not pending. The default page object is:

```
id, self, createdDateTime, title, createdByAppId, contentUrl,
lastModifiedDateTime, links, parentSection
```

No `level`, no `order`. Asking for them by name does not help — `$select=id,
title,level` comes back as `[id, title]`, with `level` silently dropped.
`$orderby=order` *works*, so the field exists server-side for sorting, but its
value is never returned.

So **subpages arrive as ordinary pages** over this route, and the `.onepkg`
route remains the only way to keep their nesting. The dialog says so, in all
seven languages, beside the file route which keeps them.

## Throttling is the normal weather

OneNote throttles by **request count**, so `$batch` cuts round trips and not
throttling. Measured: reading three pages from each of sixty sections drew a
429 after six and a half minutes, and a second attempt *minutes later* was
throttled on its first request. The cooldown is long.

Consequences, all now built in:

- A 429 quiets the **whole client**, not the one request that got it. Letting
  the other five in flight carry on is what turns one 429 into six, each
  costing a round trip and its own wait.
- Ten retries, up to two minutes each. Five quick ones covering fifteen seconds
  gave up while the wait had barely started.
- The wait is **reported**. A card that sits silent for two minutes cannot be
  told from one that has hung, and the student's next move would be to kill the
  app halfway through their own notebook.

## Speed

| | |
|---|---|
| Where it started | ~5 s per page |
| One `$batch` of 20 pages, carrying ink | 1,151,526 bytes in **7.1 s** — about 350 ms a page |
| A real 332-page notebook, end to end | **152 pages in 72 s**, of which the first 40 s is startup — so about **210 ms a page** once running |

A warning about measuring it: the notebook's `.onote` is a WAL database, so
**watching the file size is not watching progress**. An import that looked
stalled at seven megabytes for eleven minutes was in fact running normally the
whole time — the log said 152 of 332 pages at 72 seconds. Read the progress
callback, not the disk.

The 40 s before the first page appears is the startup cost: listing the
sections, walking the section groups, and fetching every section's page list.
It buys the page total, which is what lets the card show how far through it is,
and it is paid once.

**It also used to be forty seconds of nothing.** No progress is reported until
a section has been written, so for that whole stretch the card read *"Signing
in to OneNote…"* — finished long before, and indistinguishable from a freeze on
the one screen where a student is most likely to conclude the app has died and
kill it. That stretch now reports as it goes ("looking through your notebook",
then the section count, then the page total), and `shouldCancel` is checked
before the first write, because Stop is on screen for all forty seconds and was
doing nothing for all forty seconds.

What got it there, in order of how much each was worth:

1. **`$batch`** — twenty pages in one round trip instead of twenty.
2. **One shared request gate.** The pools were nested — a pool over pages whose
   jobs each opened a pool over that page's images multiplied six by six and
   put thirty-six requests in flight, which OneNote answers with 429s. The
   throttling was slower than the sequential code it replaced.
3. **Every section's page list up front**, together, rather than one round trip
   at each section boundary.
4. **Sections read ahead of the one being written** (two of them). Fetching can
   be parallel; writing cannot, because the sink is a transaction on one
   isolate and every node carries a position, so two sections interleaving
   their writes would shuffle the notebook.

## The bug only a real import could find

Both of the first two full-notebook runs stopped at **exactly page 152 of 332**
and then sat there for over ten minutes.

It looked like throttling and was not: throttling is not deterministic and does
not stop at the same page twice, and the second run had the whole adaptive rate
control the first did not. It was a request that never came back.

**There was no timeout anywhere in the client.** Every request holds one of the
concurrency slots while it runs, and with no deadline it holds one for ever.
Six of those and the import is stopped permanently — no error, no progress, and
nothing to tell it from a very slow notebook. I killed the first run believing
it was throttled; only the second stopping at the same page said otherwise.

Two lessons worth keeping:

- **Every request needs a deadline**, and it belongs at the request level as
  well as inside the transport, so the property is testable rather than only
  observable on somebody's real notebook.
- **A stalled connection is not throttling.** Treating it as such would narrow
  the pipe and punish the whole import for one bad socket.

## The second real import: forty minutes, one page

With deadlines in place the same notebook was run again, and the result was
worse than either run before it:

```
  1/332 — General  (33570 ms)
  waiting 0s … waiting 1s … waiting 2s … waiting 4s … waiting 8s … waiting 16s …
  [26 throttle waits over 40 minutes]
```

**One page, and the rest was backoff.** Two things to separate out.

*The caveat first:* a day of probing against one account earns a sustained
throttle penalty, and this run was made from inside it. It is not a
measurement of what a student's first import looks like — the 210 ms a page
above was measured on the same code against the same notebook. Both numbers
are real; they are measurements of different weather.

*The faults it exposed are real regardless*, and neither is about speed.

**1. There was no number of minutes after which the client stopped.** Ten
retries at up to two minutes each, per request, with the shared quiet-until
pushed forward every time — the arithmetic allows for an hour of silence, and
forty minutes of it is what came out. Waiting for ever is not persistence; it
is a hang with a progress message. `giveUpAfterThrottledFor` (four minutes of
being refused with **nothing at all** getting through) ends it with a sentence
a student can act on: try again in a little while.

The clock is reset by any success, so a long import that is throttled now and
then — which is every large notebook — never trips it. Only an account that is
genuinely locked out does.

**2. Giving up would have deleted the notebook.** The far worse of the two,
and it was sitting in the job the whole time:

```dart
importedPages = result.pages;                                 // after run()
…
} on GraphException catch (e) {
  if (nb.isNotEmpty && importedPages == 0) await _teardown();  // still 0
```

`importedPages` was only assigned once the import **returned**. Anything thrown
partway left it at zero, so the teardown — written to clear up an empty shell —
would instead have deleted a notebook with pages in it, the same pages the
student had just spent ten minutes watching arrive. Progressive import is what
made this reachable: before it, nothing was on screen to lose.

It is counted from the progress callback now, as the pages land. And an import
that brought *something* finishes as **done**, not failed, with a count in the
message. Calling it a failure is an invitation to delete it and start again,
which is the one action that would actually lose the work.

A note on the shape of the fix: giving up is `GraphGaveUp`, its own type, not a
`GraphException` with a distinctive message. Every other `GraphException` on
this path is caught somewhere and turned into *skip this page* — right for one
bad page, catastrophic here, where the result would be several hundred empty
pages reported as a success. The type is what stops it being swallowed.

## The third real import: the whole notebook

Once the account's penalty had worn off, the same notebook went through end to
end:

```
time            133s          per page   403 ms
pages           332 (332 nodes)
sections        25, groups 6
text boxes      1004    tables 32    images 46    attachments 2
ink blocks      109 (64,060 strokes)
inline maths    548
lost: ink pages 0, images 4, attachments 0
```

Five years of notes in **two minutes and thirteen seconds**, with sixty-four
thousand ink strokes and five hundred equations intact. The 45 s of that spent
"looking around" is the section and page-list phase, and it is now reported
rather than silent.

**Four pictures were lost, and nothing else was** — which is what made the
cause findable. `resource`, the path that fetches pictures and attachments, was
the one request path in the client that ignored throttling completely:

- it never waited out the shared quiet period, so pictures barged through
  backoff every other request was respecting — losing the picture *and*
  deepening the throttling for everything else;
- `statusCode != 200` returned null, so a 429 (*come back shortly*) was read as
  *this picture does not exist*;
- and there was no retry, so there was no shortly to come back in.

It backs off and asks again now, like everything else. Null still means a real
failure — a 404, a body that stopped arriving, an exhausted retry.

The general lesson is worth more than the fix: **a partial loss of one kind of
thing, with no loss of any other kind, points at the code path unique to that
kind.** The pages, ink, maths and attachments all shared the throttle-aware
path. The pictures did not.

## Parity with the `.onepkg` route

| | `.onepkg` | Over Graph |
|---|---|---|
| Text, formatting, lists, headings | yes | yes |
| Tables | with real column widths (`col_w`, from `0x1D66`) | fitted to the outline, columns shared by content length |
| Images | yes | yes, floating and in-flow |
| Equations | yes (OMML → LaTeX in the Rust core) | yes (MathML → LaTeX) |
| Handwriting | yes | yes |
| **Attachments** | **no — never implemented** | **yes** |
| **Internal page links** | **no** | **yes, rewritten after the import** |
| Page nesting | yes | **no, and cannot be** |
| Works on macOS or Linux | no | yes |

Both routes produce the same intermediate shape and go through
`importOneParsedPage`, so everything downstream — box geometry, in-flow image
rewriting, restacking, tags, ink blocks — is one piece of code rather than two
that must be kept in step.

## Still open

- **Superscript and subscript** (`<sup>`, `<sub>`) keep their text and lose
  their position. Seen in real content — `[b]<sub>d</sub>`.
- **`list-style-type`** on `<li>` and `value` on ordered items are ignored, so
  a list restarting at 7 restarts at 1.
- **A cold-account first import has now been measured once** (133 s for 332
  pages) but only once, and only on one notebook. Treat 400 ms a page as the
  shape of it rather than as a promise.
