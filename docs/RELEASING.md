# Cutting a release

> How a commit on `master` becomes something a stranger can download and
> install. Last updated 2026-08-05.
>
> **Everything here is automated except the four things marked ⚠️.** Those four
> are manual on purpose — a release that can publish itself is a release that
> can publish itself by accident.

## The short version

```bash
# 1. bump the version (must match the tag exactly)
#    app/pubspec.yaml:  version: 0.3.0+3
git commit -am "Release 0.3.0"
git push origin master

# 2. tag it
git tag v0.3.0
git push origin v0.3.0

# 3. wait ~15 min, then publish the draft on GitHub
```

That is it. Everything below is what those three commands set off, and what to
do when one of them does not work.

---

## 0. Before you tag

| Check | Why |
|---|---|
| CI is green on `master` | The release workflow **does not run tests**. It builds and packages. A red master produces a broken release quite happily. |
| `app/pubspec.yaml` version matches the tag | The workflow fails fast if they disagree. `version: 0.3.0+3` ↔ tag `v0.3.0` — only `M.m.p` is compared, the `+build` is ignored. |
| The version is bumped **and pushed** before the tag | Tagging a commit whose pubspec still says the old version fails the `derive version` job in about eight seconds. |

**Version numbers.** `M.m.p` on both sides; increment the `+build` counter too,
because some platforms care about it even though this workflow does not.

---

## 1. What the tag triggers

Pushing `v*` runs [`.github/workflows/release.yml`](../.github/workflows/release.yml):
four parallel jobs, then a fifth that collects them.

```
derive version ──┬── windows x64 ──────┐
                 ├── linux x64  ───────┼── draft release
                 └── macos universal ──┘
```

Each platform job builds the Rust core first, then the Flutter app, then
packages. Roughly 12–18 minutes end to end, most of it macOS.

### What comes out

| Platform | File | What the user does |
|---|---|---|
| Windows | `openote-X.Y.Z-windows-x64-setup.exe` | Runs it. Wizard, Start-menu entry, uninstaller. **No administrator password** — it installs per-user into `%LOCALAPPDATA%`. |
| Windows | `openote-X.Y.Z-windows-x64.zip` | Unzips it, runs `openote.exe`. Kept for locked-down machines, USB sticks, and people who want to look inside first. |
| Linux | `openote-X.Y.Z-linux-x86_64.AppImage` | `chmod +x`, double-click. |
| Linux | `openote-X.Y.Z-linux-x64.tar.gz` | Extracts, runs `openote`. Fallback for anywhere AppImage does not suit. |
| macOS | `openote-X.Y.Z-macos-universal.dmg` | Opens, drags to Applications. Universal — one file for Intel and Apple Silicon. |

### ⚠️ 1a. Publishing the draft — manual

The workflow creates the release as a **draft**. Nothing is public until a
person presses Publish, which is the point: it is the last place to notice that
the macOS job silently produced a 4 MB dmg.

1. GitHub ▸ **Releases** ▸ the draft ▸ **Edit**
2. Check five files are attached and none is suspiciously small
3. Edit the notes if you want — the body is pre-filled with the download table
   and the warning explanations, and `generate_release_notes: true` appends the
   merged PRs since the last tag
4. **Publish release**

The website picks it up on its next page load; nothing needs republishing.

---

## 2. Making it downloadable

Two surfaces, and only one of them is a link you would send to a person.

### 2.1 GitHub Releases

Automatic, permanent, and where the files actually live:
`https://github.com/icmric/openote/releases/latest`

Fine for a developer. Not fine for the friend testing on a Mac, who has to
scroll past the source-code tarballs and pick the right one of five files.

### 2.2 The website — `site/` on Cloudflare Workers

One static HTML file plus a Worker with a single route. Deployed by
[`.github/workflows/site.yml`](../.github/workflows/site.yml) on any push to
`master` touching `site/` or `wrangler.jsonc`.

The page detects the visitor's OS and moves that card to the front, so a single
link lands each person on the file they want. **A newly published release
appears on the site with no deploy** — the version and the download links are
read at request time, not baked in.

#### Why a Worker rather than plain static hosting

Exactly one route justifies it: `/api/latest`. The page needs the newest
release, and asking GitHub from the *browser* — which is what shipped first —
costs two real things. The unauthenticated GitHub API allows 60 requests an
hour **per IP**, so a lecture theatre behind one NAT can exhaust it between
them; and every visitor pays a cross-origin round trip before the buttons
resolve. Fetching it in the Worker gives one cached origin request shared by
everyone, served from the edge, trimmed from ~50 KB to under 500 bytes.

`site/index.html` still falls back to calling GitHub directly if `/api/latest`
is unavailable, so the file works opened from disk or served from anywhere. A
hosting choice must not be able to break the page.

#### ⚠️ 2a. Two repository secrets — manual, once ever

Settings ▸ Secrets and variables ▸ Actions ▸ **New repository secret**:

| Secret | Where it comes from |
|---|---|
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare dashboard ▸ Workers & Pages ▸ right-hand sidebar |
| `CLOUDFLARE_API_TOKEN` | My Profile ▸ API Tokens ▸ Create Token ▸ **Edit Cloudflare Workers** template |

Scope the token to this account and nothing else. It needs two permissions —
**Workers Scripts: Edit** and **Account Settings: Read** — and no zone access
at all unless you let wrangler manage the DNS route for you, which the config
here deliberately does not.

#### ⚠️ 2b. Point the domain — manual, once ever

Add `openote.org` to Cloudflare as a zone (this changes the nameservers at your
registrar), then in the dashboard: **Workers & Pages ▸ openote-site ▸ Settings
▸ Domains & Routes ▸ Add ▸ Custom domain** → `openote.org`, and again for
`www.openote.org` if you want it.

A custom domain creates the DNS record and the certificate itself; there is no
CNAME file and no A records to add by hand. The old `site/CNAME` was a GitHub
Pages artefact and has been deleted.

Until the domain is attached, the Worker is live at
`openote-site.<your-subdomain>.workers.dev`, which is enough to test with.

#### Deploying by hand

```bash
npx wrangler@4 deploy        # from the repo root; reads wrangler.jsonc
npx wrangler@4 dev           # serves site/ on localhost:8787, Worker and all
npx wrangler@4 tail          # live logs, for when /api/latest starts 503ing
```

**Say `@4`, or pin it.** Wrangler 3 cannot read `wrangler.jsonc` at all (JSONC
config landed in 3.91) and does not support static assets, so it reports
`Missing entry-point` — pointing at a file it is silently ignoring. That is
exactly how the first CI deploy failed: `cloudflare/wrangler-action@v3` installs
wrangler **3.90** by default. The workflow now calls a pinned wrangler 4
directly instead.

## 3. The warnings, and what to tell people

Openote is **not code-signed**, on either platform. This is a deliberate,
revisitable decision — see [v0.7 §4](planning/v0.7-packaging.md#4-the-honest-part-code-signing).
The release notes already explain both warnings; the short version:

- **Windows — "Windows protected your PC".** More info → Run anyway.
  SmartScreen shows this for any installer it has not seen often enough to have
  an opinion about. A brand-new certificate would not clear it either;
  reputation accrues per certificate over downloads and time.
- **macOS — "openote is damaged and can't be opened".** It is not damaged;
  Gatekeeper quarantines unsigned downloads. Once, after copying to
  Applications: `xattr -cr /Applications/openote.app`. Or **System Settings ▸
  Privacy & Security ▸ Open Anyway** — note the old right-click ▸ Open trick
  was removed in macOS 15, so most advice online is stale.
- **Linux.** No equivalent. AppImage just runs.

**Tell people about the warning before they see it.** A user who was warned
treats it as expected; a user who was not treats it as malware.

---

## 4. Building locally

You do not need CI to get a build, and **you do not need to pay anyone** to
build for any platform — including macOS, where the free Xcode is sufficient
and a locally-built app is not quarantined at all.

```bash
# the Rust core first — the app falls back to pure Dart without it, but then
# the status bar will say so
cd rust/onote_core && cargo build --release

cd ../../app
flutter pub get
flutter build windows --release   # or: linux / macos
```

Output lands in `app/build/<platform>/…`. The one rule that matters: **the
native library must sit next to the executable** (`onote_core.dll` /
`libonote_core.so` / inside `Contents/MacOS/`). The CMake hook does this on
Windows and Linux; macOS has no hook, so the workflow copies it manually and
then **re-signs ad-hoc** — inserting a file breaks Flutter's signature seal and
the app is killed on launch otherwise.

To build the Windows installer locally you need [Inno Setup](https://jrsoftware.org/isdl.php) 6:

```powershell
iscc /DAppVersion=0.3.0 /DStageDir=<path to the Release folder> packaging\windows\openote.iss
```

---

## 5. When it goes wrong

| Symptom | Cause | Fix |
|---|---|---|
| `derive version` fails in seconds | Tag and pubspec disagree | Bump `app/pubspec.yaml`, commit, delete the tag (`git push --delete origin vX.Y.Z`), re-tag |
| A platform job fails but others pass | No draft is created — the release job needs all three | Fix, delete the tag, re-tag. Re-running the single job also works |
| The dmg is tiny | The macOS build produced no app bundle | Check the *Build app* step; it usually fails loudly earlier |
| Windows app starts and the status bar says "pure-Dart engine" | `onote_core.dll` is not beside the exe | Check the *Package zip* step copied it |
| Site deploy fails with an auth error | §2a not done, or the token is scoped to the wrong account | Recreate the token from the **Edit Cloudflare Workers** template |
| Site deploy says `Missing entry-point` | Wrangler 3 is being used; it ignores `wrangler.jsonc` entirely | Use wrangler 4 — the workflow pins it, so this only bites a hand-run `npx wrangler` |
| `/api/latest` returns 503 | GitHub had no published release, or was unreachable | Expected with no release; the page falls back to calling GitHub directly |
| The site says "no release yet" | No **published** release — a draft is invisible to the API | Publish the draft |

**Deleting a tag** is safe before the release is published, and the usual fix
for everything above:

```bash
git tag -d vX.Y.Z
git push --delete origin vX.Y.Z
```

---

## 6. Not yet true

Stated plainly because it is the most likely source of a surprise: **neither
the Windows installer nor the Pages workflow has ever executed.** Both were
added on 2026-08-05 and fire for the first time on the next tag / next push to
`master`. They have been read carefully and the Inno Setup script is
conventional, but reviewed is not the same as ran. Expect the first tag to
shake out something dull, most likely a path.
