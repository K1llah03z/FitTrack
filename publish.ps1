<#
  publish.ps1  -  upload FitTrack to GitHub (GitHub Pages serves this folder).

  Every run:
    - bumps the version in BOTH index.html (APP_VERSION) and sw.js (VERSION),
      so installed phones show "Version x.y.z is ready"
    - commits everything and pushes to GitHub

  Usage (from this folder):
      .\publish.ps1                 bug fix      1.3.0 -> 1.3.1
      .\publish.ps1 -Minor          new feature  1.3.1 -> 1.4.0
      .\publish.ps1 -Major          big rework   1.4.0 -> 2.0.0
      .\publish.ps1 -Message "Fixed the fasting ring"
#>
param(
  [string]$Message = "",
  [switch]$Minor,
  [switch]$Major
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
$htmlPath = Join-Path $PSScriptRoot "index.html"
$swPath   = Join-Path $PSScriptRoot "sw.js"
$html = [IO.File]::ReadAllText($htmlPath)
$sw   = [IO.File]::ReadAllText($swPath)
$cur = [regex]::Match($html, 'const APP_VERSION = "(\d+)\.(\d+)\.(\d+)";')
if (-not $cur.Success) { Fail "Couldn't find APP_VERSION in index.html." }
$ma = [int]$cur.Groups[1].Value; $mi = [int]$cur.Groups[2].Value; $pa = [int]$cur.Groups[3].Value
$old = "$ma.$mi.$pa"
if ($Major) { $ma++; $mi = 0; $pa = 0 } elseif ($Minor) { $mi++; $pa = 0 } else { $pa++ }
$ver = "$ma.$mi.$pa"
$html = [regex]::Replace($html, 'const APP_VERSION = "[^"]*";', "const APP_VERSION = `"$ver`";")
if ($sw -match 'const VERSION = "[^"]*";') {
  $sw = [regex]::Replace($sw, 'const VERSION = "[^"]*";', "const VERSION = `"$ver`";")
} else {
  $sw = [regex]::Replace($sw, 'const CACHE = "FitTrack-v[^"]*";', "const CACHE = `"FitTrack-v$ver`";")
}
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
