<#
doctor.ps1 - check the course setup requirements and say exactly what is missing.

  .\doctor.ps1                 check this workspace
  .\doctor.ps1 -Fast           skip the live agent calls (no quota used)

Checks the things a syllabus actually asks for: two AI agents installed AND
authenticated, the shared-rules files wired up and PROVEN to load, and the
folder layout. Read-only: it installs nothing, signs in to nothing, and
changes no files.

Exit code 0 only when every required check passes.
#>
param([switch]$Fast)
$ErrorActionPreference = 'Continue'
$Root = $PSScriptRoot
$fail = 0; $warn = 0

function Say($status, $text, $detail) {
  $c = switch ($status) { 'OK' { 'Green' } 'FAIL' { 'Red' } 'WARN' { 'Yellow' } default { 'Gray' } }
  Write-Host ("  [{0,-4}] {1}" -f $status, $text) -F $c
  if ($detail) { Write-Host ("         {0}" -f $detail) -F DarkGray }
  if ($status -eq 'FAIL') { $script:fail++ }
  if ($status -eq 'WARN') { $script:warn++ }
}
function HasCmd($n) { [bool](Get-Command $n -EA SilentlyContinue) }

Write-Host ""
Write-Host "COURSE SETUP CHECK" -F Cyan
Write-Host "  workspace: $Root"
Write-Host ""

# ---------------- 1. agents installed ----------------
Write-Host "1. AI agents installed (the course needs TWO working locally)" -F Cyan
$agents = @()
foreach ($a in @(
  @{ Name='Claude Code'; Cmd='claude';  Probe='claude --version' },
  @{ Name='Codex';       Cmd='codex';   Probe='codex --version' },
  @{ Name='Gemini CLI';  Cmd='gemini';  Probe='gemini --version' }
)) {
  if (HasCmd $a.Cmd) {
    $v = (& $a.Cmd --version 2>&1 | Select-Object -First 1)
    Say 'OK' "$($a.Name) installed" "version $v"
    $agents += $a.Name
  } else {
    Say 'INFO' "$($a.Name) not installed" "optional if you have two others working"
  }
}
# Antigravity ships its own binary and is not always on PATH.
$agyPath = Join-Path $env:LOCALAPPDATA 'agy\bin\agy.exe'
$agy = if (HasCmd 'agy') { 'agy' } elseif (Test-Path $agyPath) { $agyPath } else { $null }
if ($agy) {
  Say 'OK' "Antigravity CLI installed" "version $(& $agy --version 2>&1 | Select-Object -First 1)"
  $agents += 'Antigravity'
} else {
  Say 'INFO' "Antigravity CLI not installed" "Google's replacement for Gemini CLI on individual accounts"
}
if ($agents.Count -ge 2) { Say 'OK' "$($agents.Count) agents installed" ($agents -join ', ') }
else { Say 'FAIL' "only $($agents.Count) agent(s) installed" "the course requires two working locally" }
Write-Host ""

# ---------------- 2. authentication ----------------
# A version number proves installation, NOT sign-in. These are separate failures
# and a setup check that conflates them is worse than none.
Write-Host "2. Authentication (a version number does not prove sign-in)" -F Cyan
if ($Fast) {
  Say 'INFO' 'skipped (-Fast)' 'live calls use your account allowance'
} else {
  if (HasCmd 'gemini') {
    $g = (& gemini -p "reply OK" 2>&1 | Out-String)
    if ($g -match 'IneligibleTierError|UNSUPPORTED_CLIENT|no longer supported') {
      Say 'WARN' 'Gemini CLI installed but BLOCKED by Google' 'individual accounts are migrated to Antigravity - see docs\gemini-vs-antigravity.md'
    } elseif ($g -match 'Error authenticating|not authenticated') {
      Say 'WARN' 'Gemini CLI not signed in' 'run: gemini'
    } else {
      Say 'OK' 'Gemini CLI answered a prompt'
    }
  }
  if ($agy) {
    $o = ("reply OK" | & $agy 2>&1 | Out-String)
    if ($o -match 'not logged in|sign in|unauthori') { Say 'WARN' 'Antigravity not signed in' 'launch: agy' }
    else { Say 'OK' 'Antigravity answered a prompt' }
  }
  Say 'INFO' 'Claude Code and Codex not auto-probed' 'start each one and ask it to read a file in this folder'
}
Write-Host ""

# ---------------- 3. folder layout ----------------
Write-Host "3. Folder layout" -F Cyan
$cfgPath = Join-Path $Root 'courses.json'
if (-not (Test-Path $cfgPath)) {
  Say 'FAIL' 'courses.json missing' 'run setup.ps1 first'
} else {
  $cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $classes = @($cfg.courses | Where-Object { $_.enabled -ne $false })
  Say 'OK' "$($classes.Count) classes configured"
  $missing = @()
  foreach ($c in $classes) {
    $d = Join-Path $Root $c.folder
    foreach ($sub in 'sources', 'work', 'submissions', 'skills') {
      if (-not (Test-Path (Join-Path $d $sub))) { $missing += "$($c.folder)\$sub" }
    }
    foreach ($f in 'AGENTS.md', 'STATUS.md') {
      if (-not (Test-Path (Join-Path $d $f))) { $missing += "$($c.folder)\$f" }
    }
  }
  if ($missing.Count) { Say 'FAIL' "$($missing.Count) required folder(s)/file(s) missing" (($missing | Select-Object -First 4) -join ', ') }
  else { Say 'OK' 'every class has sources, work, submissions, skills, AGENTS.md, STATUS.md' }
}
Write-Host ""

# ---------------- 4. rules actually load ----------------
# The syllabus asks you to TEST that CLAUDE.md / GEMINI.md reach the agent, not
# merely to create them. This asks for a fact that exists ONLY in the shared
# block, so a wrong answer means the rules did not arrive.
Write-Host "4. Do the shared rules actually reach an agent?" -F Cyan
if (-not (Test-Path $cfgPath)) {
  Say 'INFO' 'skipped' 'no workspace yet'
} else {
  $cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $first = @($cfg.courses | Where-Object { $_.enabled -ne $false })[0]
  $dir = Join-Path $Root $first.folder
  foreach ($f in 'CLAUDE.md', 'GEMINI.md') {
    $p = Join-Path $dir $f
    if (Test-Path $p) {
      if ((Get-Content $p -Raw -Encoding UTF8) -match '(?m)^@AGENTS\.md\s*$') {
        Say 'OK' "$f imports AGENTS.md" 'a markdown link does NOT import; it must be @AGENTS.md on its own line'
      } else {
        Say 'FAIL' "$f does not import AGENTS.md" 'needs a bare @AGENTS.md line'
      }
    }
  }
  if ($Fast) {
    Say 'INFO' 'live load test skipped (-Fast)' "run without -Fast, or ask an agent in $($first.folder) for this course's Canvas id"
  } else {
    Say 'INFO' 'live load test' "launch an agent in '$($first.folder)' and ask: what is this course's Canvas id, and what does rule 4 say about secrets?"
    Say 'INFO' 'expected' "$($first.id), and that tokens never go in a file or a chat"
  }
}
Write-Host ""

# ---------------- 5. Canvas mirror ----------------
Write-Host "5. Canvas mirror and schedule" -F Cyan
if (Test-Path (Join-Path $Root 'DUE.md')) {
  $age = [int]((Get-Date) - (Get-Item (Join-Path $Root 'DUE.md')).LastWriteTime).TotalHours
  if ($age -le 12) { Say 'OK' "DUE.md refreshed $age h ago" } else { Say 'WARN' "DUE.md is $age h old" 'run canvas-watch.ps1, or check the scheduled task' }
} else { Say 'FAIL' 'DUE.md missing' 'run canvas-watch.ps1' }
$task = Get-ScheduledTask | Where-Object { $_.TaskName -like '*Canvas*' } | Select-Object -First 1
if ($task) {
  $i = Get-ScheduledTaskInfo -TaskName $task.TaskName
  if ($i.LastTaskResult -eq 0) { Say 'OK' "scheduled task '$($task.TaskName)' healthy" "next run $($i.NextRunTime)" }
  else { Say 'WARN' "scheduled task last exited $($i.LastTaskResult)" $task.TaskName }
} else { Say 'WARN' 'no Canvas scheduled task found' 'rerun setup.ps1 without -NoSchedule' }
Write-Host ""

# ---------------- what this does NOT check ----------------
Write-Host "NOT checked here - still yours to do:" -F Yellow
Write-Host "  - buying and enrolling in the course book" -F DarkGray
Write-Host "  - the cold benchmark and the two surveys (do these yourself, not with AI)" -F DarkGray
Write-Host "  - mobile agent access (Claude Dispatch / Remote Control, Codex Remote)" -F DarkGray
Write-Host "  - saving your authentic conversation into <class>\submissions\" -F DarkGray
Write-Host "  - running the bounded cross-agent review (see AGENTS.md)" -F DarkGray
Write-Host ""

if ($fail) { Write-Host "$fail required check(s) FAILED, $warn warning(s)." -F Red; exit 1 }
Write-Host "All required checks passed ($warn warning(s))." -F Green
exit 0
