# Publish the CurseForge instance's current mods and configs to this packwiz repo.
# Usage: update-pack.bat [-DryRun] [-Yes] [-NoWait] [-InstanceDir <path>]
# Windows PowerShell 5.1 compatible. Needs node and git on PATH.
param(
  [string]$InstanceDir = 'C:\Users\kbouk\curseforge\minecraft\Instances\All of Create Aeronautics',
  [switch]$DryRun,  # show what would change, then put the repo back exactly as it was
  [switch]$Yes,     # publish without asking
  [switch]$NoWait   # don't wait for GitHub's raw cache to serve the new files
)
$ErrorActionPreference = 'Continue'   # native-command exit codes are checked explicitly
$Tools    = $PSScriptRoot
$Repo     = Split-Path -Parent $Tools
$ListFile = Join-Path $Tools 'client-only.txt'
$Folders  = 'config','defaultconfigs','configureddefaults','resourcepacks','shaderpacks','fancymenu_data','datapacks'
$PackPaths = @('mods','pack.toml','index.toml') + $Folders
$RawBase  = 'https://raw.githubusercontent.com/kbouk2003-ctrl/aoc-aeronautics-pack/main'
$CoAuthor = 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'
$Utf8     = New-Object System.Text.UTF8Encoding($false)

function Fail($msg) { throw $msg }
function RunGit { $out = & git -C $Repo @args; if ($LASTEXITCODE -ne 0) { Fail "git $($args -join ' ') failed" }; $out }
function Present { $tracked = @(& git -C $Repo ls-tree --name-only HEAD)
  $PackPaths | Where-Object { (Test-Path (Join-Path $Repo $_)) -or ($tracked -contains $_) } }
function Field($text, $key) { if ($text -match "(?m)^$key = `"(.*)`"") { $Matches[1] } }
function Revert {
  Write-Host 'Reverting working tree...'
  $tracked = @(& git -C $Repo ls-tree --name-only HEAD)
  $p = @(Present)
  & git -C $Repo reset -q HEAD -- $p 'tools/client-only.txt'
  & git -C $Repo checkout -q HEAD -- ($p | Where-Object { $tracked -contains $_ })
  & git -C $Repo clean -fdq -- $p
  [IO.File]::WriteAllBytes($ListFile, $script:ListBackup)
}

if (-not (Test-Path (Join-Path $InstanceDir 'minecraftinstance.json'))) { Write-Error "Not a CurseForge instance: $InstanceDir"; exit 1 }
foreach ($c in 'git','node') { if (-not (Get-Command $c -ErrorAction SilentlyContinue)) { Write-Error "$c not found on PATH"; exit 1 } }
& git -C $Repo config core.autocrlf false
$dirty = & git -C $Repo status --porcelain -- (Present)
if ($dirty) { Write-Error "Pack files have uncommitted changes. Commit or discard them first:`n$($dirty -join "`n")"; exit 1 }

$script:ListBackup = [IO.File]::ReadAllBytes($ListFile)
$committed = $false
$exit = 0
try {
  # a. mods: regenerate mods/*.pw.toml from the instance's jars
  Write-Host "== Syncing mods from $InstanceDir"
  & node (Join-Path $Tools 'build_packwiz.js') $InstanceDir $Repo $ListFile
  if ($LASTEXITCODE -ne 0) { Fail 'Mod sync failed (see above). Nothing was published.' }

  # b. mirror content folders, honouring .packwizignore
  Write-Host '== Mirroring content folders'
  $ignore = Get-Content (Join-Path $Repo '.packwizignore') | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') }
  foreach ($f in $Folders) {
    $src = Join-Path $InstanceDir $f
    if (-not (Test-Path $src)) { Write-Warning "  $f not in instance, left unchanged"; continue }
    $xd = @(); $xf = @()
    foreach ($p in $ignore) {
      $full = Join-Path $InstanceDir ($p.TrimEnd('/') -replace '/', '\')
      if ($p.EndsWith('/')) { if ($p.StartsWith("$f/")) { $xd += $full } }
      elseif ($p.Contains('/')) { if ($p.StartsWith("$f/")) { $xf += $full } }
      else { $xf += $p }
    }
    $rc = @('/MIR','/NJH','/NJS','/NFL','/NDL','/NP','/R:1','/W:1')
    if ($xd) { $rc += '/XD'; $rc += $xd }
    if ($xf) { $rc += '/XF'; $rc += $xf }
    & robocopy $src (Join-Path $Repo $f) @rc | Out-Null
    if ($LASTEXITCODE -ge 8) { Fail "robocopy failed for $f (exit $LASTEXITCODE)" }
  }

  # c. personal-data scan of everything that will be published
  Write-Host '== Personal-data scan'
  $hits = & git -C $Repo grep -l -i -a --untracked -e 'kbouk' -e 'xTheAncientOne' -e '9ea37e5f' -e '@gmail' -- (Present | Where-Object { $_ -notin 'pack.toml','index.toml' })
  if ($LASTEXITCODE -eq 0) { Fail "Personal data found, aborting. Remove it from the instance (or add the path to .packwizignore):`n  $($hits -join "`n  ")" }
  if ($LASTEXITCODE -gt 1) { Fail 'personal-data scan failed' }

  # d. bump pack version (patch + 1)
  $packFile = Join-Path $Repo 'pack.toml'
  $pack = [IO.File]::ReadAllText($packFile)
  if ($pack -notmatch '(?m)^version = "(\d+)\.(\d+)\.(\d+)"') { Fail 'pack.toml version not in x.y.z form' }
  $oldVer = "$($Matches[1]).$($Matches[2]).$($Matches[3])"
  $newVer = "$($Matches[1]).$($Matches[2]).$([int]$Matches[3] + 1)"
  [IO.File]::WriteAllText($packFile, ($pack -replace '(?m)^version = "[^"]*"', "version = `"$newVer`""), $Utf8)

  # e. packwiz refresh
  Push-Location $Repo
  & (Join-Path $Tools 'packwiz.exe') refresh | Out-Null
  $rc = $LASTEXITCODE; Pop-Location
  if ($rc -ne 0) { Fail 'packwiz refresh failed' }
  if (Select-String -Path (Join-Path $Repo 'index.toml') -Pattern '^file = "(tools/|update-pack\.bat|UPDATING\.md)' -Quiet) { Fail 'index.toml lists repo tooling; check .packwizignore' }

  # f. summary vs HEAD
  RunGit add -A -- (Present) | Out-Null
  RunGit add -- 'tools/client-only.txt' | Out-Null
  $added = @(); $removed = @(); $updated = @(); $cfg = @()
  foreach ($line in (RunGit diff --cached --no-renames --name-status HEAD -- (Present))) {
    $st, $path = $line -split "`t", 2
    if ($path -in 'pack.toml','index.toml') { continue }
    if ($path -like 'mods/*.pw.toml') {
      $new = if ($st -ne 'D') { [IO.File]::ReadAllText((Join-Path $Repo $path)) }
      $old = if ($st -ne 'A') { (& git -C $Repo show "HEAD:$path") -join "`n" }
      switch ($st) {
        'A' { $added   += "$(Field $new 'name') ($(Field $new 'filename'))" }
        'D' { $removed += "$(Field $old 'name') ($(Field $old 'filename'))" }
        default {
          $of = Field $old 'filename'; $nf = Field $new 'filename'
          $what = if ($of -ne $nf) { "$of -> $nf" } else { "side $(Field $old 'side') -> $(Field $new 'side')" }
          $updated += "$(Field $new 'name'): $what"
        }
      }
    } else { $cfg += "$st $path" }
  }
  Write-Host ''
  Write-Host "== Pack $oldVer -> $newVer"
  Write-Host "Mods added:   $($added.Count)";   $added   | ForEach-Object { Write-Host "  + $_" }
  Write-Host "Mods removed: $($removed.Count)"; $removed | ForEach-Object { Write-Host "  - $_" }
  Write-Host "Mods updated: $($updated.Count)"; $updated | ForEach-Object { Write-Host "  ~ $_" }
  Write-Host "Config/content files changed: $($cfg.Count)"
  $cfg | Select-Object -First 40 | ForEach-Object { Write-Host "  $_" }
  if ($cfg.Count -gt 40) { Write-Host "  ...and $($cfg.Count - 40) more" }
  Write-Host ''

  $go = $false
  if ($added.Count + $removed.Count + $updated.Count + $cfg.Count -eq 0) { Write-Host 'Nothing to publish.' }
  elseif ($DryRun) { Write-Host 'Dry run: nothing committed or pushed.' }
  elseif (-not $Yes -and (Read-Host 'Publish? (y/n)') -notmatch '^y') { Write-Host 'Not published.' }
  else { $go = $true }
  if ($go) {

  # g. commit, verify blob bytes, push
  $msg = @("Pack update $newVer", '')
  if ($added)   { $msg += 'Added:';   $msg += $added   | ForEach-Object { "- $_" }; $msg += '' }
  if ($removed) { $msg += 'Removed:'; $msg += $removed | ForEach-Object { "- $_" }; $msg += '' }
  if ($updated) { $msg += 'Updated:'; $msg += $updated | ForEach-Object { "- $_" }; $msg += '' }
  if ($cfg)     { $msg += "Config/content files changed: $($cfg.Count)"; $msg += '' }
  $msg += $CoAuthor
  $msgFile = [IO.Path]::GetTempFileName()
  [IO.File]::WriteAllText($msgFile, ($msg -join "`n") + "`n", $Utf8)
  RunGit commit -q -F $msgFile | Out-Null
  Remove-Item $msgFile
  $committed = $true

  # Committed blobs must be byte-identical to the files packwiz hashed (no line-ending conversion).
  $check = @('pack.toml','index.toml') + @($cfg | ForEach-Object { ($_ -split ' ', 2)[1] } | Where-Object { Test-Path (Join-Path $Repo $_) } | Select-Object -First 50)
  $work = @(RunGit hash-object --no-filters -- $check)
  $blob = @(RunGit rev-parse ($check | ForEach-Object { "HEAD:$_" }))
  for ($i = 0; $i -lt $check.Count; $i++) {
    if ($work[$i] -ne $blob[$i]) {
      & git -C $Repo reset -q --soft HEAD~1; $committed = $false
      Fail "Committed bytes differ from working file $($check[$i]) (line-ending conversion?). Commit undone."
    }
  }

  & git -C $Repo push -q origin main
  if ($LASTEXITCODE -ne 0) { Fail 'git push failed. The commit is saved locally; fix the problem and run: git push origin main' }
  Write-Host "Published $newVer ($((RunGit rev-parse --short HEAD)))."
  Write-Host 'Published. Wait 5 minutes before restarting the server or launching, so GitHub''s cache serves the new files.'

  if (-not $NoWait) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $want = @{}; foreach ($f in 'pack.toml','index.toml') { $want[$f] = (Get-FileHash (Join-Path $Repo $f) -Algorithm SHA256).Hash }
    $deadline = (Get-Date).AddMinutes(6)
    Write-Host 'Waiting for raw.githubusercontent.com to serve the new pack (up to 6 minutes, Ctrl+C to skip)...'
    while ((Get-Date) -lt $deadline) {
      $live = $true
      foreach ($f in $want.Keys) {
        try {
          $r = Invoke-WebRequest "$RawBase/$f" -UseBasicParsing -TimeoutSec 30
          if ((Get-FileHash -InputStream $r.RawContentStream -Algorithm SHA256).Hash -ne $want[$f]) { $live = $false }
        } catch { $live = $false }
      }
      if ($live) { Write-Host 'Live now.'; break }
      Start-Sleep -Seconds 20
    }
    if (-not $live) { Write-Host 'Still cached after 6 minutes; give it a few more minutes before launching.' }
  }
  }
}
catch { Write-Host "ERROR: $_" -ForegroundColor Red; $exit = 1 }
finally { if (-not $committed) { Revert } }
exit $exit
