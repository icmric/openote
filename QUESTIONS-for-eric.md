# For Eric, at the end

## Needs your decision

1. **Subpage nesting is impossible over Graph — accept, or keep the file route
   as the "full fidelity" option?** Settled from the wire, not guessed:
   `$select=id,title,level` returns `[id, title]` with `level` silently
   dropped, and the default page object carries neither `level` nor `order`.
   Right now the dialog says so and points at the file route. If you'd rather,
   I could flatten *deliberately* differently — e.g. prefix a subpage's title
   with an indent marker so the structure is at least visible — but that is a
   guess about what you'd prefer, so I have not.

2. **Should the sign-in route become the default on Windows too?** Today the
   two are presented side by side and the file route wins on nesting. On
   Windows a `.onepkg` keeps subpage nesting AND real table column widths; the
   internet route wins on attachments, needing no export, and internal links.
   Genuinely a toss-up and it is your product call.

3. **Publisher verification.** Users currently see "unverified publisher" on
   the Microsoft consent screen. Clearing it needs a Microsoft Partner Network
   ID (free to create, some paperwork). Worth doing before you tell people
   about this, or leave it?

4. **How long should a hopelessly throttled import wait before it stops?** I
   set four minutes. Context: a real run of your notebook spent **forty
   minutes to import one page**, all of it backoff, because there was no
   number at which the client gave up. Four minutes of being refused with
   nothing whatsoever getting through now ends it with "keep what arrived, try
   again in a little while". Any success resets the clock, so an ordinary
   large import that is throttled on and off never trips it. Longer is more
   patient and more like a hang; shorter gives up on a slow day.

5. **The import progress card is English only, in a seven-language app.**
   Not something I introduced — every message in `import_job.dart` is a
   hardcoded English string, and has been since the `.onepkg` import: "Reading
   the notebook…", "Imported 42 pages", all of it. A German or Chinese student
   gets the whole import in English. I have not fixed it because it is a real
   design change rather than a translation pass: the job is a `ChangeNotifier`
   with no `BuildContext`, so it cannot reach `AppLocalizations` as written —
   it would have to report a *state* and let the card do the wording. Worth
   doing before release, or after? I'd do it before, given you shipped seven
   languages deliberately, but it is a day's work and not a small diff.

## Needs you to check (I cannot)

6. **Look at an imported notebook and tell me what still reads wrong.** I have
   verified structure — 301 ink strokes, bold surviving, tables fitted — but
   not whether a page *looks* like the original. Tables especially: OneNote
   sends no column widths at all, so I share the outline's width out by how
   much text each column holds. That is a guess and it may look wrong.

7. **Ink placement.** Strokes convert from himetric at 2540 units/inch against
   the canvas's 120 dpi. The arithmetic is right; whether handwriting lands
   where it did in OneNote, relative to the typed text, needs eyes.

8. **Equations.** MathML → LaTeX covers fractions, powers, roots, subscripts,
   fences, matrices and Greek. Anything unusual will come through as its
   plain characters rather than as maths. Send me one that looks wrong and I
   will add the case.

## Things I chose, that you might want changed

9. **Colour and font are deliberately dropped** from imported text. The app's
   `{{#hex text}}` colour syntax is private and PLANNING already marks it for
   replacement, and a per-run font has nowhere to live in a Markdown box — so
   importing either would bake a decision you are reversing into every page.
   Say the word and I will keep them anyway.

10. **Black ink becomes the theme's default rather than a hard black**, so
   imported handwriting stays legible on a dark page. A colour you actually
   chose is kept exactly.

11. **A cancelled cloud import keeps what already arrived** (the file import
   tears down instead). You have been watching pages appear, so deleting them
   because you pressed stop seemed the wrong reading of "stop".

## What a real import actually does now

Your whole notebook, end to end, twice:

```
time            189s          per page   571 ms
pages           332 (332 nodes)
sections        25, groups 6
text boxes      1004    tables 32    images 46    attachments 2
ink blocks      109 (64,060 strokes)
inline maths    548
lost: ink pages 0, images 0, attachments 0
```

Five years of notes in about three minutes, with sixty-four thousand ink
strokes and five hundred equations. **Nothing lost.**

Two caveats on the numbers, so you are not surprised later:

- The first two runs today were made while your account was in a throttle
  penalty my own probing had earned it. That has worn off. If an import is
  ever slow, that is what it will be, and it now says so on screen rather than
  going quiet.
- 133 s and 189 s are the two clean runs. Treat "about half a second a page"
  as the shape of it rather than a promise — it is one notebook on one
  connection, and Microsoft's throttling is the thing that actually decides.

## Known gaps, deliberately not built

- **Superscript and subscript** keep their text and lose their position; seen
  in your own notes as `[b]<sub>d</sub>`.
- **`list-style-type` and ordered-list `value`** are ignored, so a list that
  restarted at 7 restarts at 1.
- **The `.onepkg` route still cannot convert internal links** — its mapping
  would have to come out of the binary format rather than out of Graph's
  `links.oneNoteClientUrl`.
