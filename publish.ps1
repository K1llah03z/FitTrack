<#
  publish.ps1  -  upload FitTrack to GitHub (GitHub Pages serves this folder).

  Every run:
    - sets the version in BOTH index.html (APP_VERSION) and sw.js (VERSION),
      cookbook style: year.month.DDNN (2026.11.2601, 2026.11.2602, ...)
    - commits everything and pushes to GitHub

  Usage (from this folder):
      .\publish.ps1
      .\publish.ps1 -Message "Fixed the fasting ring"
#>
param(
  [string]$Message = "",
  [switch]$Minor,   # no longer used (kept so old commands still run)
  [switch]$Major    # no longer used
)

$ErrorActionPreference = "Continue"
Set-Location -LiteralPath $PSScriptRoot
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Say($text, $color = "Cyan") { Write-Host ""; Write-Host "==> $text" -ForegroundColor $color }
function Fail($text) { Write-Host ""; Write-Host "STOPPED: $text" -ForegroundColor Red; exit 1 }

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail "Git is not installed (winget install --id Git.Git -e), then reopen PowerShell." }
if (-not (Test-Path "index.html") -or -not (Test-Path "sw.js")) { Fail "Run this from the FitTrack folder (the one with index.html and sw.js)." }

# ---- first run: connect this folder to the GitHub repo without losing anything on either side
if (-not (Test-Path ".git")) {
  Say "First run: connecting this folder to GitHub"
  $remote = Read-Host "Repository address (press Enter for https://github.com/K1llah03z/FitTrack.git)"
  if (-not $remote) { $remote = "https://github.com/K1llah03z/FitTrack.git" }
  & git init | Out-Null
  & git symbolic-ref HEAD refs/heads/main
  & git remote add origin $remote
  & git fetch origin
  if ($LASTEXITCODE -eq 0) {
    & git reset origin/main | Out-Null
    # bring back files that exist on GitHub but not in this folder (README etc.)
    $missing = & git ls-files --deleted
    foreach ($f in $missing) { & git checkout -- "$f" }
  }
  if (-not (& git config user.name))  { & git config user.name  (Read-Host "Your name for GitHub commits") }
  if (-not (& git config user.email)) { & git config user.email (Read-Host "Your GitHub email (or the no-reply address from GitHub settings)") }
}
$branch = (& git rev-parse --abbrev-ref HEAD 2>$null)
if (-not $branch -or $branch -eq "HEAD") { $branch = "main" }

# ---- bump the version in index.html and sw.js together
# Version = year.month.DDNN  (day of the month + that day's build number, e.g. 2026.11.2601, 2026.11.2602)
$htmlPath = Join-Path $PSScriptRoot "index.html"
$swPath   = Join-Path $PSScriptRoot "sw.js"
$html = [IO.File]::ReadAllText($htmlPath)
$sw   = [IO.File]::ReadAllText($swPath)
$old = [regex]::Match($html, 'const APP_VERSION = "([^"]*)";').Groups[1].Value
if (-not $old) { Fail "Couldn't find APP_VERSION in index.html." }
# If an update zip carried an older number, continue from the last version that was actually published.
function VerKey($v) { $mm = [regex]::Match($v, '^(\d{4})\.(\d{1,2})\.(\d{1,2})(\d{2})$'); if (-not $mm.Success) { return 0 }
  return [int64]$mm.Groups[1].Value * 100000000 + [int64]$mm.Groups[2].Value * 1000000 + [int64]$mm.Groups[3].Value * 1000 + [int64]$mm.Groups[4].Value }
$published = [regex]::Match((& git show HEAD:index.html 2>$null | Out-String), 'const APP_VERSION = "([^"]*)";').Groups[1].Value
if ($published -and (VerKey $published) -gt (VerKey $old)) { $old = $published }
$now = Get-Date
$prefix = "{0}.{1}.{2}" -f $now.Year, $now.Month, $now.Day
$n = 1
$m = [regex]::Match($old, '^' + [regex]::Escape($prefix) + '(\d{2})$')
if ($m.Success) { $n = [int]$m.Groups[1].Value + 1 }
$ver = $prefix + $n.ToString("00")
$html = [regex]::Replace($html, 'const APP_VERSION = "[^"]*";', "const APP_VERSION = `"$ver`";")
$sw = [regex]::Replace($sw, 'const VERSION = "[^"]*";', "const VERSION = `"$ver`";")
[IO.File]::WriteAllText($htmlPath, $html, $utf8)
[IO.File]::WriteAllText($swPath, $sw, $utf8)
Say "FitTrack version $ver  (was $old)"

# ---- commit and push
if (-not $Message) { $Message = "FitTrack $ver" }
& git add -A
& git commit -m $Message | Out-Host
Say "Uploading to GitHub..."
& git push -u origin $branch
if ($LASTEXITCODE -ne 0) {
  Write-Host "GitHub has changes this folder doesn't. Combining them..." -ForegroundColor Yellow
  & git pull --rebase origin $branch
  if ($LASTEXITCODE -ne 0) { Fail "Couldn't combine automatically. Run 'git status' to see what's different." }
  & git push -u origin $branch
  if ($LASTEXITCODE -ne 0) { Fail "Push failed. If GitHub asked you to sign in, finish that and run this again." }
}
Say "Uploaded!" "Green"
Write-Host "Live in about a minute: https://k1llah03z.github.io/FitTrack/"
