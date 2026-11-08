# Import a OneNote notebook from a share link

[#36](https://github.com/icmric/openote/issues/36), investigated on 6–8 November 2026 against the
owner's own old notebook. **Status: open. A way exists; the route is not chosen.** Nothing here is
built, and nothing is promised for a release — the owner's call on 8 November was to settle the
v1.0.3 scope first and work out the route afterwards.

## The ask

> Import from OneNote share link — *Aloxite1, 5 November.* A student has a OneNote notebook that
> was shared with them as a link and wants it in Openote without exporting anything.

The reply on 6 November said it should be doable and hoped to ship it "with the next update". That
is owed a correction whichever way this goes: it is not in the proposed v1.0.3 scope.

The design rule the owner set for it: **the person pastes a link and that is all** — no export
step, nothing technical to know, and as few sign-ins as can be got away with. Every route below is
judged first on how far it is from that.

## What a share link actually is

Measured with the owner's read-only link (`1drv.ms/o/c/<id>/<token>?e=…`), 6 November.

| Step | What happens |
|---|---|
| 1 | `1drv.ms/o/c/…` redirects (301) to `onedrive.live.com/:o:/g/personal/<CID>/…` |
| 2 | That redirects (302) to `…/personal/<cid>/_layouts/15/Doc.aspx?sourcedoc=…&redeem=…` — **OneNote Online** — and sets two cookies, `FedAuth` and `ScaleCompatibilityDeviceId`. This is an **anonymous guest session**: no sign-in |
| 3 | On the same host, `…/personal/<cid>/_api/v2.0/drive/items/<id>/children` lists the notebook as a **folder of real `.one` and `.onetoc2` files** (the item says `package: oneNote`). The owner's: **35 files, 184 MB** |
| 4 | Each file carries `@content.downloadUrl` and `@content.downloadUrlNoAuth` |

The owner confirmed the human side in an incognito window: the link opens with nobody signed in, a
sign-in popup appears, **Cancel** dismisses it, and it never asks again. So for an "Anyone with the
link" share, **no account is needed by anyone** — the whole difficulty is the app's access, not the
person's.

The notebook is the files the importer already reads (`rust/onote_core/src/onenote.rs`, the `.one`
and `.onepkg` path). The unsolved part is only *fetching* them.

## What does not work

| Attempt | Result |
|---|---|
| `api.onedrive.com/v1.0/shares/u!<base64 url>/…` with no auth | 401 |
| `graph.microsoft.com/v1.0/shares/…` with no auth | 401 |
| The `_api/v2.0` endpoint from a plain client that says what it is (`Openote/…`) | **403**. The same call from a browser-style client, with the guest cookie, is 200 |
| Pretending to be a browser (a Chrome user-agent string) so the 403 goes away | **Ruled out.** It would work, and it is exactly what the site's check exists to refuse, so an app should not do it. One comparison request was made before that was settled; nothing was downloaded. Do not build on it, do not retry it |
| Building on the OneNote Online page itself | Not an option: it talks to Microsoft's private Office endpoints (`onenote.officeapps.live.com`), which are not a contract |

## The routes

### A. Microsoft Graph, signed in with any Microsoft account

`GET /shares/{encoded link}/driveItem`, then walk the children and download. This is the
**documented** route for an "Anyone" link. The importer already signs in
([`graph_auth.dart`](../../app/lib/onenote/graph_auth.dart): authority `common`, so a personal
account works, scope `Notes.Read`, a remembered refresh token), so the person pastes a link and, the
first time only, signs in with *any* Microsoft account — not the one the notebook belongs to.

- **Cannot do:** be sign-in-free. A student with only a school account has to make a free personal
  one; a school can also switch "Anyone" links off, in which case no route works.
- **Unknown:** the permission it needs. Probably `Files.Read.All`, which is a broader consent screen
  than `Notes.Read` and may be refused by a school that already blocks the current one.
- **Unknown:** whether it works with an account unrelated to the notebook. Documented, not tested.

### B. An embedded browser inside the app

A real browser engine, so no impersonation: WebView2 on Windows, WKWebView on macOS, webkit2gtk on
Linux. It would do what the owner's incognito window did — open the link, take the guest session,
list the files — with no sign-in at all.

- **Cannot do:** be light. The app has **no webview dependency today** (`pubspec.yaml`, `app/linux/`
  and the packaging were checked); Linux would add webkit2gtk to the `.deb` and `.rpm`.
- **Cannot do:** be stable. It leans on SharePoint web endpoints that are not a public contract, so
  a Microsoft change could break it without warning.
- **Unknown:** whether the file download URLs work from ordinary app code once the browser has
  opened the session. If they do, the browser is only needed to list the files and the 184 MB comes
  down through a normal download.

### C. Ask the person to download it themselves — untested idea

OneDrive's own **Download** on a shared folder may hand over a zip of the `.one` files, which an
"import a folder of `.one` files" step could take. It would be sign-in-free and risk-free, and costs
the person three steps instead of one. **Nothing has been checked** — not whether OneNote notebooks
offer it, nor whether the zip comes out in a shape the importer reads.

## What to investigate, in order

Each is a yes/no that decides the route.

1. **Do the `downloadUrlNoAuth` URLs work from a plain Dart HTTP client, after a real browser has
   opened the session?** Answers whether B needs a browser for the whole import or only for the
   listing. This was the next test when the permission system stopped the run.
2. **Do the `.one` files that come back from a share import through the existing Rust importer?**
   Fetch two small ones (`General.one`, `Open Notebook.onetoc2`) by hand in a browser, put them in
   their own empty folder, and run the importer. The files are the owner's, and are untrusted data
   like any download: parse only, never open or run.
3. **Does Graph `/shares` accept an unrelated Microsoft account, and what permission does it ask
   for?** Needs a second account (a free personal one is enough). Decides whether A is real.
4. **Does OneDrive's Download on the shared notebook give a usable zip?** Decides whether C is a
   fallback worth writing.
5. **Which webview package covers all three platforms, and what does Linux cost in package size and
   install steps?** Only if B survives 1.
6. **Ask the reporter what kind of link theirs is** — *Anyone with the link*, *People in my
   organisation*, or *Specific people*. The last two need an account that has been given access,
   whatever the route, and the reporter's school may block "Anyone" altogether. This is a reply on
   the issue, for the owner to post.

## Decision

Not made. The shape that keeps the most options open: answer 2 first (cheap, and fatal to every
route if it fails), then 1 and 3 side by side, then choose between A and B — with A as the fallback
if the browser route fails or Linux cannot carry it.

## Things to keep true whichever route wins

- A share link is a **credential** for read access to someone's notebook. It is never written to a
  log, a crash report or an issue, and it is not stored after the import finishes.
- The import runs as a **background job** with progress, like `.onepkg` ([`ImportJob`](../../app/lib/export/import_job.dart)):
  184 MB is a long download.
- Failure messages are specific and in plain words — *"This link needs you to be signed in"*, *"Your
  school has turned off sharing by link"*, *"This link has expired"* — never a status code.
