# ------------------------------------------------------------------
#  How many people have downloaded a release.
#
#  GitHub counts this and then does not show it: the release page has
#  no download figures anywhere in the web interface, and the numbers
#  exist only on the REST API. That is the whole reason this file is
#  here - the question "did the 1.0.0 announcement do anything" is not
#  answerable by clicking around.
#
#  PowerShell rather than a shell one-liner because the one-liner is a
#  quoting trap: a `python -c` pipeline needs bash escaping, breaks in
#  PowerShell with a parser error, and is too long to retype anyway.
#
#  ASCII only, deliberately. Windows PowerShell 5.1 - the one that
#  ships with Windows - reads a .ps1 as the system codepage unless the
#  file carries a UTF-8 BOM, so an em dash in a comment becomes
#  mojibake and takes the parser down with it. An encoding this file
#  cannot control is not worth a nicer dash.
#
#  Usage:
#    .\tools\downloads.ps1              # the latest release, per file
#    .\tools\downloads.ps1 -All         # every release, one line each
#    .\tools\downloads.ps1 -Tag v1.0.0  # one named release
#
#  No authentication, so it works from anywhere - at the cost of two
#  things worth knowing. Unauthenticated calls are limited to 60 an
#  hour per IP, and DRAFT releases are invisible: a release you have
#  staged but not published will not appear here at all, which reads
#  exactly like "not released yet".
# ------------------------------------------------------------------

[CmdletBinding()]
param(
  # Every release instead of just the current one.
  [switch]$All,

  # A specific release, e.g. v1.0.0. Beats -All.
  [string]$Tag,

  # Here so a fork can point it somewhere else without editing the file.
  [string]$Repo = 'icmric/openote'
)

$ErrorActionPreference = 'Stop'

# **The add-on is not an install.** `video-engine` is the optional media
# component an existing user fetches to play video; counting it inflates
# "how many people downloaded Openote" by the number of people who were
# already running it. Every total below is reported both ways so the
# difference is visible rather than hidden in a choice we made for you.
$addOn = '*video-engine*'

function Get-Json($url) {
  try {
    Invoke-RestMethod -Uri $url -Headers @{ 'Accept' = 'application/vnd.github+json' }
  } catch {
    # The failure that actually happens is the rate limit, and its
    # message does not say so. Name it rather than printing a 403.
    throw ("GitHub API request failed: " + $_.Exception.Message + "`n" +
           "If this is a 403, it is almost certainly the 60-per-hour " +
           "unauthenticated limit: wait, or use 'gh api' with a token.")
  }
}

function Show-Release($r) {
  $app   = ($r.assets | Where-Object { $_.name -notlike $addOn } |
            Measure-Object download_count -Sum).Sum
  $total = ($r.assets | Measure-Object download_count -Sum).Sum
  $when  = if ($r.published_at) {
             ([datetime]$r.published_at).ToString('yyyy-MM-dd')
           } else { 'unpublished' }

  ''
  "$($r.tag_name)  published $when"
  $r.assets |
    Sort-Object download_count -Descending |
    Select-Object @{n = 'downloads'; e = { $_.download_count }},
                  @{n = 'MB'; e = { [math]::Round($_.size / 1MB, 1) }},
                  name |
    Format-Table -AutoSize

  "  app downloads: $app   (all assets: $total)"
  ''
}

$base = "https://api.github.com/repos/$Repo/releases"

if ($Tag) {
  Show-Release (Get-Json "$base/tags/$Tag")
} elseif ($All) {
  # **Assigned, then iterated with `foreach`.** Piping the result of
  # Invoke-RestMethod straight into ForEach-Object does not enumerate
  # the array in PowerShell 5.1 - `$_` arrives as the whole collection
  # and every column comes out as `{v1.0.1, v1.0.0, ...}`. Windows
  # PowerShell is what ships with Windows, so it is the one that has to
  # work.
  $releases = Get-Json "$base`?per_page=100"
  $rows = foreach ($r in $releases) {
    [pscustomobject]@{
      tag       = $r.tag_name
      published = if ($r.published_at) {
                    ([datetime]$r.published_at).ToString('yyyy-MM-dd')
                  } else { '-' }
      app       = ($r.assets | Where-Object { $_.name -notlike $addOn } |
                   Measure-Object download_count -Sum).Sum
      total     = ($r.assets | Measure-Object download_count -Sum).Sum
    }
  }
  $rows | Format-Table -AutoSize
  $a = ($rows | Measure-Object app -Sum).Sum
  $t = ($rows | Measure-Object total -Sum).Sum
  "ALL RELEASES: app=$a  total=$t"
  ''
} else {
  # `/releases/latest` is the newest NON-draft, NON-prerelease release,
  # ordered by creation date rather than by version - so a patch
  # backported to an older line after the fact would win.
  Show-Release (Get-Json "$base/latest")
}

# **What these numbers are not**, because they are easy to over-read:
#
#  * Requests, not people. A resumed or retried download counts again,
#    and .deb/.rpm attract mirror and indexing bots.
#  * Updates are in there. The in-app updater fetches the same installer
#    as a new user does, and nothing here can separate the two.
#  * Source archives are not counted at all. GitHub's auto-generated
#    zip/tar.gz never appear in `download_count` - only uploaded assets.
#
# So treat the app figure as an upper bound on installs and a lower
# bound on interest.
