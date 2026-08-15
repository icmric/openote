# Cutting a release

> How a commit on `master` becomes something a stranger can download and
> install. Last updated 2026-08-05.
>
> **Everything here is automated except the four things marked ⚠️.** Those four
> are manual on purpose — a release that can publish itself is a release that
> can publish itself by accident.

## The short version

```bash
# 0. BE ON MASTER. Every step below assumes it, and the failure is silent:
#    committing the bump on a feature branch makes step 1's push print
#    "Everything up-to-date" and exit 0, after which step 2 tags a commit
#    whose pubspec was never bumped — which is exactly how 0.3.0 died.
git checkout master && git pull

# 1. OPTIONAL BUT RECOMMENDED — a dry run, no tag involved.
#    Actions ▸ Release ▸ Run workflow ▸ Branch: master ▸ version = 0.3.1
#    Builds and packages all three platforms and uploads the artifacts to the
#    run page. It creates NO release — and note that it therefore does NOT
#    exercise the release job at all (see §"What the dry run cannot tell you").
#    The version guard still applies, so do this AFTER step 2's push.

# 2. bump the version (must match the tag exactly), commit, PUSH
#    app/pubspec.yaml:  version: 0.3.1+4
#    CHANGELOG.md:      heading says 0.3.1
git commit -am "Release 0.3.1"
git push origin master

# 3. tag it — only once the bump is actually on the remote
git tag v0.3.1
git push origin v0.3.1

# 4. wait ~15 min, then REVIEW and publish the draft on GitHub
```

That is it. Everything below is what those commands set off, and what to do
when one of them does not work.

### Re-tagging after a failed attempt

A tag deleted on GitHub is **still in your local clone**, and `git push origin
v0.3.0` will happily push the stale copy straight back. A plain `git fetch
--prune` does not remove it either — tags need `--prune-tags`. So delete it in
both places, explicitly:

```bash
git push --delete origin v0.3.0     # remote
git tag -d v0.3.0                   # local  ← the one that gets forgotten
git fetch --prune --prune-tags origin

git checkout master && git pull
git log --oneline -1                # note this SHA
git tag v0.3.0
git rev-parse v0.3.0                # must equal the SHA above
git push origin v0.3.0
```

**Delete the release for the failed tag FIRST — this is a numbered step, not a
tidy-up.** It does not "sit beside" the new draft; there is no second release.
`softprops/action-gh-release` finds the release by tag and, on that update
path, passes `draft: existingRelease.draft` straight through. Only the *create*
path honours `draft: true`. So re-tagging into an existing **published** release
attaches every installer to it live, overwrites its title and body with the
draft text, and never pauses for review.

The `version` job now refuses outright when a release already exists for the
tag, so this cannot happen silently any more — but the refusal is the backstop,
not the plan.

```bash
# Releases ▸ the old release ▸ ⋯ ▸ Delete release   (deleting a release does
#                                                    NOT delete its tag)
git push --delete origin v0.3.1
git tag -d v0.3.1
```

**Or just ship the next patch number.** One line in `pubspec.yaml` against four
coupled destructive steps that each have to happen in the right order. That is
what 0.3.0 → 0.3.1 was.

---

## 0. Before you tag

| Check | Why |
|---|---|
| CI is green on `master` | The release workflow **does not run tests**. It builds and packages. A red master produces a broken release quite happily. |
| `app/pubspec.yaml` version matches the tag | The workflow fails fast if they disagree. `version: 0.3.0+3` ↔ tag `v0.3.0` — only `M.m.p` is compared, the `+build` is ignored. |
| The version is bumped **and pushed** before the tag | Tagging a commit whose pubspec still says the old version fails the `derive version` job in about eight seconds. |
| You are on `master`, not a feature branch | The bump has to be on the commit the tag points at. Committing it elsewhere makes `git push origin master` a silent no-op. |
| `CHANGELOG.md` names this version | Nothing checks it, and the auto-generated notes are a list of merged PRs — not a description of what changed for a user. |
| No release already exists for the tag | The `version` job now refuses if one does, because publishing into an existing release bypasses the draft review entirely. |

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
| Windows | `openote-X.Y.Z-windows-x64-setup.exe` | Runs it. Wizard, Start-menu entry, uninstaller, and `.onote` files start opening in Openote. **No administrator password** — it installs per-user into `%LOCALAPPDATA%`. |
| Windows | `openote-X.Y.Z-windows-x64.zip` | Unzips it, runs `openote.exe`. Kept for locked-down machines, USB sticks, and people who want to look inside first. **No file association** — that lives in the installer's registry entries, so double-clicking a `.onote` does nothing here. |
| Linux | `openote-X.Y.Z-linux-amd64.deb` | Double-click on Ubuntu/Debian/Mint. Installs to `/opt`, adds a menu entry and the `.onote` association. |
| Linux | `openote-X.Y.Z-linux-x86_64.rpm` | Same, for Fedora/RHEL/openSUSE. |
| Linux | `openote-X.Y.Z-linux-x64.tar.gz` | Extracts, runs `openote`. The fallback for distros that use neither package format. No desktop entry, so no association either. |
| macOS | `openote-X.Y.Z-macos-universal.dmg` | Opens, drags to Applications. Universal — one file for Intel and Apple Silicon. **No `.onote` association yet** — macOS delivers files through `application(_:open:)` rather than as an argument, which needs `Runner/Info.plist` and `AppDelegate.swift` work that belongs with the macOS packaging item. |

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

The website picks it up within about ten minutes; nothing needs republishing.
Not on the next page load — `worker/index.js` caches for 600 s, and Cloudflare's
Browser Cache TTL can override that on cache hits (measured: `max-age=14400`
unless the zone is set to *Respect Existing Headers*). To see it immediately:
Cloudflare ▸ Caching ▸ Purge, `https://openote.org/api/latest`.

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
- **Linux.** No equivalent — neither package is signed, and neither format
  warns about it. `dpkg`/`rpm` will note the package is not from a configured
  repository, which is expected.

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
`libonote_core.so` / inside `Contents/MacOS/`). All three platforms now do this
for you: CMake on Windows and Linux, and on macOS a Run Script build phase on
the Runner target (`app/macos/build_onote_core.sh`) that builds one Rust target
per architecture in `$ARCHS` and `lipo`s them together, so a universal Release
app gets a universal dylib.

The macOS hook has **not been run on a Mac** — see the checklist in
[`app/README.md`](../app/README.md). Until someone confirms it, the manual
fallback is still the documented one: `cargo build --release`, copy the dylib
into `Contents/MacOS/`, then **re-sign ad-hoc** — inserting a file into an
already-signed bundle breaks its seal and the app is killed on launch. That is
also exactly what the release workflow does, and it is deliberately left in
place: the workflow's own `cargo`/`lipo`/re-sign steps run whether or not the
build phase works, so a tag cannot ship a coreless dmg because of an untested
script.

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
| The site says "no release yet" | No **published** release: `/releases/latest` excludes drafts | Publish the draft |
| The site shows "Not in this release" on a platform | That platform's build job failed, so its installer is genuinely not attached | Check the run; re-cut with the next patch number once fixed |

**Deleting a tag** is safe before the release is published, and the usual fix
for everything above:

```bash
git tag -d vX.Y.Z
git push --delete origin vX.Y.Z
```

---

## 6. Not yet true

Stated plainly, because this is where the surprises come from.

**The three platform jobs have never run to completion.** Two tag attempts both
stopped at the version guard, so everything after it was skipped. An audit of
that never-executed path found two independent faults in the Windows job, both
now fixed, and neither of which any amount of reading had caught before:

- `"$env:ProgramFiles(x86)\..."` expands to `C:\Program Files(x86)\...` —
  without the space. PowerShell ends an unbraced variable name at `(`, so the
  braced `${env:ProgramFiles(x86)}` is required. Confirmed by running the exact
  expression under pwsh.
- The Inno Setup pin was 6.2.2 while `openote.iss` uses
  `ArchitecturesAllowed=x64compatible`, which needs 6.3+. A pin that cannot
  compile the script it is pinned for is not caution. The install is now
  unpinned and the step **asserts** the floor with a message saying what to do.

**Still unchecked from a Linux machine:** whether ISCC accepts `app_icon.ico`,
whose entries are all PNG-compressed rather than BMP. The `workflow_dispatch`
dry run settles this — that is what it is for. If ISCC rejects it, regenerate
the icon with BMP entries at 16/32/48.

### What the dry run cannot tell you

The `release` job is gated `if: github.event_name == 'push'`, so a
`workflow_dispatch` run **skips it entirely**. The dry run proves the three
platform jobs — roughly 90% of the runner time and 100% of the packaging code —
and nothing about:

- `actions/download-artifact` with `merge-multiple: true`, and whether
  `files: dist/*` resolves to all five artifacts
- `generate_release_notes: true`
- **`contents: write`** — the top level of this workflow is `contents: read` and
  only the release job elevates. No workflow in this repository has ever asked
  for write. If **Settings ▸ Actions ▸ General ▸ Workflow permissions** is set
  to read-only, that is a ceiling the job cannot raise, and it 403s at the end
  of an otherwise perfect forty-minute build. Check the setting; the dry run
  will never tell you.

If you want the release job proven too, tag a prerelease: set the version to
something like `0.3.1-rc1`, tag `v0.3.1-rc1`, push. The guard captures
`[^+ ]*`, so it matches; the full chain runs; the output is a draft, invisible
to `/releases/latest`, which you inspect and then delete.

**macOS has never been run by a human at all**, and the audit found a
consequence worth knowing about. `Release.entitlements` enabled the App Sandbox
with neither network nor file-access keys — and Openote fetches an `.ics` feed
over HTTPS and opens notebooks at remembered arbitrary paths, so a
locally-built macOS app most likely could do neither. The shipped `.dmg`
escaped it only because `codesign --deep` silently stripped the entitlements.
That is now an explicit decision rather than an accident (see the comment in
`app/macos/Runner/Release.entitlements`), but it is reasoned, not measured.
**Someone still has to run the dmg.**

**The Linux job builds in a container, not on the runner.** A Linux binary
inherits its build host's glibc floor, so the host is a shipping decision, not
an implementation detail — and a runner label made it GitHub's decision on
GitHub's schedule. The job now runs in `debian:12` (bookworm), which pairs
**glibc 2.36** with **libmpv 0.35.1 → libmpv.so.2**; nothing else does, which
is why that tag and not another. Bullseye would drop the floor to 2.31 but
regress the mpv soname to `.so.1`, and the app would not launch at all.

Practical effect: **glibc 2.36 or newer** — Debian 12/13, Ubuntu 24.04+,
Mint 22+, Fedora 37+, RHEL 10, openSUSE Leap 15.6+, Arch. Ubuntu 22.04 and
Mint 21 remain out, on the mpv soname rather than on glibc. The release job
measures the real floor (`Verify the glibc floor`) instead of trusting the
image tag, so this paragraph cannot quietly go stale.

This also retires the runner-pin expiry that used to live here: the label is
now only a Docker host, so the `ubuntu-22.04` deprecation on **2026-09-17**,
and every image deprecation after it, no longer touches what ships.
