<#
setup.ps1 - bootstrap a folder-per-class Canvas workspace.

Runs on Windows (Windows PowerShell 5.1) and macOS (PowerShell 7, pwsh).
Launch it with `powershell -ExecutionPolicy Bypass -File ./setup.ps1` on
Windows, or `pwsh -File ./setup.ps1` on macOS - -ExecutionPolicy does not
exist there and pwsh errors on it. Write paths with /, which both accept.

  ./setup.ps1 -Interview                     ask the questions, then do it
  ./setup.ps1 -Root <path>                   non-interactive, all three agents
  ./setup.ps1 -Root <path> -Agents claude    only Claude Code shims
  ./setup.ps1 -Root <synced path> -Reuse     adopt a workspace from another computer
  ./setup.ps1 -Root <path> -Every 4          refresh every 4 hours (default 1)
  ./setup.ps1 -Root <path> -NoSchedule       skip the recurring background job

Discovers your courses from Canvas, writes courses.json, creates one folder per
course with agent rules, takes a first snapshot, and schedules a read-only
watcher - Task Scheduler on Windows, a launchd agent on macOS. Safe to rerun:
new courses merge in, and your STATUS.md, hand-written rules, and edited
templates are never overwritten.
#>
param(
  [string]$Root,
  # A plain string, deliberately NOT [string[]] with [ValidateSet]: when this
  # script is launched as `powershell -File setup.ps1 -Agents claude,codex`
  # (the form the docs give), PowerShell hands the parameter over as the single
  # string "claude,codex", which a ValidateSet on a string[] rejects outright.
  # Parse and validate it here instead so the documented command works.
  [string]$Agents,
  [int]$Every = 1,
  # 24-hour HH:mm. When set, a daily standup task is registered as well.
  [string]$StandupAt,
  [switch]$NoSchedule,
  [switch]$Interview,
  [switch]$Reuse
)
$ErrorActionPreference = 'Stop'

# Validate -StandupAt HERE, before anything is created. Failing at the very last
# step - after the workspace, the folders and the watcher already exist - reads
# as "the whole install failed" when in fact only the trigger was rejected.
if ($StandupAt -and $StandupAt -notmatch '^([01]?\d|2[0-3]):[0-5]\d$') {
  Write-Error "-StandupAt must be a 24-hour time like 07:30 or 7:30 - got '$StandupAt'."
}

$VALID_AGENTS = @('claude', 'codex', 'antigravity')
$agentList = @()
if ($Agents) {
  $agentList = @($Agents -split '[,;\s]+' | Where-Object { $_ } | ForEach-Object { $_.Trim().ToLower() })
  $bad = @($agentList | Where-Object { $VALID_AGENTS -notcontains $_ })
  if ($bad) { Write-Error "Unknown agent(s): $($bad -join ', '). Valid values are: $($VALID_AGENTS -join ', ')." }
}

# Everything that differs between Windows and macOS lives in platform.ps1.
. (Join-Path $PSScriptRoot 'platform.ps1')

# On Windows a token set by a previous run lives in HKCU\Environment, which a
# process that was already running never sees - including the AI agent driving
# this script. Without this, an agent-run setup loops forever on "CANVAS_TOKEN
# is not set" even though the student set it correctly. On macOS the same call
# reads the login Keychain. The value is never displayed, and `&`-invoked child
# scripts inherit it from $env:.
if (-not $env:CANVAS_TOKEN) { $env:CANVAS_TOKEN = Get-CanvasToken }
if (-not $env:CANVAS_BASE)  { $env:CANVAS_BASE  = Get-CanvasBase }

function Find-GoogleDrive { Find-CanvasCloudDrive }
# Read-Host returns $null at end-of-input when there is no console - which is
# what happens if an AI agent or a scheduled task runs -Interview. Calling
# .Trim() on that throws "You cannot call a method on a null-valued expression",
# which means nothing to a student. Fail with an instruction instead.
function ReadLine($prompt) {
  $a = Read-Host $prompt
  if ($null -eq $a) {
    Write-Error ("-Interview needs a real terminal, and this session has no console to read answers from. " +
                 "If an AI assistant is running this, it should ask you the questions itself and pass " +
                 "the answers as flags instead, for example: -Root C:\Users\you\School -Agents claude -Every 4. " +
                 "See SKILL.md.")
  }
  return $a
}
function Ask($question, $default) {
  $suffix = if ($default) { " [$default]" } else { '' }
  $a = ReadLine "$question$suffix"
  if ([string]::IsNullOrWhiteSpace($a)) { return $default }
  return $a.Trim()
}
function AskYesNo($question, $defaultYes) {
  $d = if ($defaultYes) { 'Y/n' } else { 'y/N' }
  $a = (ReadLine "$question ($d)").Trim()
  if (-not $a) { return [bool]$defaultYes }
  return $a -match '^(y|yes)$'
}

# ---------- token, checked BEFORE the interview ----------
# Asking every question and only then saying "now go make a token" wastes the
# student's answers and reads as a bait-and-switch. Check first.
if (-not $env:CANVAS_TOKEN) {
  $hintBase = if ($env:CANVAS_BASE) { $env:CANVAS_BASE.TrimEnd('/') } else { 'https://yourschool.instructure.com' }
  $steps = Get-CanvasTokenInstructions $hintBase
  $tail = Get-CanvasShellNote
  if (-not (Test-CanvasTokenStorable)) {
    Write-Warning "The 'security' command is missing, so the Keychain is unavailable. This is not a normal macOS setup."
  }
  Write-Host @"

Before anything else: this needs a Canvas token, and only YOU can make one.
It takes about a minute.

$steps
  3. Run this script again. No new terminal needed.

Picture guide: docs/image-prompt-canvas-token.md

$tail
Never paste the token into a chat, a file, or a screenshot. It is unscoped:
whoever has it has your entire Canvas account. Stuck? Ask your AI assistant.

"@
  exit 1
}

# ---------- the interview ----------
if ($Interview) {
  Write-Host ""
  Write-Host "Canvas workspace setup. Seven questions. Press Enter to take the default." -F Cyan
  Write-Host "Stuck on any of them? Ask your AI assistant - it can answer and rerun this." -F DarkGray
  Write-Host ""

  $drive = Find-GoogleDrive
  $already = AskYesNo "1. Have you already set this up on another computer?" $false
  if ($already) {
    Write-Host "   Then point me at the synced copy and I will adopt it, not rebuild it." -F DarkGray
    if ($drive) { Write-Host "   Google Drive is on this PC at: $drive" -F DarkGray }
    $Root = Ask "   Path to your existing workspace" $(if ($drive) { Join-Path $drive 'School' } else { Join-Path (Get-CanvasHome) 'School' })
    $Reuse = $true
  } else {
    if ($drive) {
      Write-Host "2. Google Drive is installed here: $drive" -F DarkGray
      $useDrive = AskYesNo "   Keep the workspace in Google Drive so it follows you between computers?" $true
      $default = if ($useDrive) { Join-Path $drive 'School' } else { Join-Path (Get-CanvasHome) 'School' }
    } else {
      Write-Host "2. Google Drive is not installed on this computer." -F DarkGray
      Write-Host "   I cannot install it for you. If you want your workspace to follow you" -F DarkGray
      Write-Host "   between computers, install Drive first from google.com/drive/download," -F DarkGray
      Write-Host "   then rerun this. Otherwise a local folder is completely fine." -F DarkGray
      if (AskYesNo "   Stop here so you can install Google Drive first?" $false) {
        Write-Host "Nothing changed. Rerun this script after installing Drive." -F Yellow
        exit 0
      }
      $default = Join-Path (Get-CanvasHome) 'School'
    }
    $Root = Ask "3. Where should the workspace live?" $default
  }

  # Not on the reuse path: the workspace already records an agent choice, and
  # the defaults here (Claude yes, others no) would silently delete the other
  # agents' shims across the synced workspace for anyone pressing Enter through.
  if ($Reuse -and -not $agentList) {
    Write-Host ""
    Write-Host "4. Keeping the AI tools this workspace already records." -F DarkGray
    Write-Host "   To change them, rerun later with -Agents claude,codex" -F DarkGray
  }
  if ((-not $agentList) -and (-not $Reuse)) {
    Write-Host ""
    Write-Host "4. Which AI coding tools do you actually use? Each one needs its own" -F DarkGray
    Write-Host "   instructions file in every class folder; unused ones are just clutter." -F DarkGray
    $sel = @()
    if (AskYesNo "   Claude Code?"           $true)  { $sel += 'claude' }
    if (AskYesNo "   Codex?"                 $false) { $sel += 'codex' }
    if (AskYesNo "   Antigravity (Gemini)?"  $false) { $sel += 'antigravity' }
    if (-not $sel) {
      Write-Host "   None selected - defaulting to Claude Code so the folders are usable." -F Yellow
      $sel = @('claude')
    }
    $agentList = $sel
  }

  $schoolHost = Ask "5. Your Canvas address" $(if ($env:CANVAS_BASE) { $env:CANVAS_BASE } else { 'https://byu.instructure.com' })
  # Persist it. Process scope dies with this run, and the next run would fall
  # back to the BYU default and send a non-BYU student's full-account token to
  # a school they have no relationship with. Set-CanvasBase writes the User env
  # scope on Windows and ~/.config on macOS, where that scope does nothing.
  Set-CanvasBase $schoolHost

  $Every = [int](Ask "6. Refresh how often, in hours?" '1')

  if (-not $StandupAt) {
    Write-Host ""
    Write-Host "7. A daily standup rewrites STANDUP.md each morning: due today, coming up," -F DarkGray
    Write-Host "   past due. You can also run .\standup.ps1 by hand any time." -F DarkGray
    if (AskYesNo "   Schedule a daily standup?" $true) {
      $StandupAt = Ask "   What time? (24-hour, e.g. 07:30)" '07:30'
      if ($StandupAt -notmatch '^([01]?\d|2[0-3]):[0-5]\d$') {
        Write-Host "   '$StandupAt' is not a 24-hour time. Skipping the daily standup;" -F Yellow
        Write-Host "   add it later with -StandupAt 07:30" -F Yellow
        $StandupAt = $null
      }
    }
  }
  Write-Host ""
}

if (-not $Root) {
  Write-Error "No workspace path. Run './setup.ps1 -Interview' to be asked, or pass -Root <path>."
}

# Fall back to the base this workspace already recorded before assuming BYU -
# the same fallback canvas-watch.ps1 has. Without it, a workspace copied to a
# second machine would send its owner's token to the wrong school.
$recordedBase = $null
$earlyMap = Join-Path $Root 'courses.json'
if (Test-Path $earlyMap) {
  try { $recordedBase = (Get-Content $earlyMap -Raw -Encoding UTF8 | ConvertFrom-Json).base } catch { }
}
$Base = if ($env:CANVAS_BASE) { $env:CANVAS_BASE.TrimEnd('/') }
        elseif ($recordedBase) { ([string]$recordedBase).TrimEnd('/') }
        else { 'https://byu.instructure.com' }
# The Bearer header carrying an unscoped, full-account token goes to whatever
# this says. A typo'd "http://" would put it on the wire in cleartext, and
# Canvas's redirect to HTTPS happens only after the header has already been sent.
if ($Base -notmatch '^https://[A-Za-z0-9.-]+$') {
  Write-Error "Canvas address must be https:// and a plain host, e.g. https://yourschool.instructure.com - got '$Base'."
}
$Api  = "$Base/api/v1"

# The workspace must not be the tool folder. Otherwise this folder's CLAUDE.md /
# GEMINI.md / AGENTS.md sit above every class folder and each class session
# inherits the *installer* instructions instead of that class's rules.
# Resolve WITHOUT creating, so a refused path is not left behind as an empty folder.
$rootFull = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Root)
if ((Test-Path (Join-Path $PSScriptRoot 'SKILL.md')) -and ($rootFull -eq (Resolve-Path $PSScriptRoot).Path)) {
  Write-Error "Pass -Root <workspace path>, e.g. ./setup.ps1 -Root <your workspace path>. The tool folder cannot also be the workspace: its CLAUDE.md/AGENTS.md/GEMINI.md would load in every class session."
}

# ---------- prove the token works ----------
try   { $me = Invoke-CanvasApi "$Api/users/self" }
catch {
  $fixBase   = Get-CanvasBaseFixInstructions
  $shellNote = Get-CanvasShellNote
  Write-Error (
    "Canvas at $Base rejected the token. Two usual causes, most likely first:`n" +
    "  1. Wrong school. If $Base is not yours, set the right one:`n" +
    "$fixBase`n" +
    "  2. Expired or deleted token. Make a new one at $Base/profile/settings, copy it, then:`n" +
    (Get-CanvasTokenInstructions $Base) + "`n" +
    "$shellNote`n" +
    "Underlying error: $($_.Exception.Message)")
}
Write-Host "Canvas says hello, $($me.name)." -F Green

# ---------- install the tool into $Root ----------
New-Item -ItemType Directory -Force -Path $Root | Out-Null
$Root = (Resolve-Path $Root).Path
if ($Root -ne $PSScriptRoot) {
  # Scripts are overwritten - that is how you take an update.
  foreach ($f in 'setup.ps1', 'canvas-watch.ps1', 'scaffold-class.ps1', 'standup.ps1', 'doctor.ps1', 'platform.ps1') { Copy-Item (Join-Path $PSScriptRoot $f) $Root -Force }
  New-Item -ItemType Directory -Force -Path (Join-Path $Root 'docs') | Out-Null
  Copy-Item (Join-Path (Join-Path $PSScriptRoot 'docs') '*') (Join-Path $Root 'docs') -Force
  # Templates are NOT: shared-rules.md is yours to edit, and the docs say so.
  # Copying it back every rerun would silently revert your rules into every class.
  if (-not (Test-Path (Join-Path $Root (Join-Path 'templates' 'shared-rules.md')))) {
    Copy-Item (Join-Path $PSScriptRoot 'templates') $Root -Recurse -Force
    Write-Host "Installed tool files and templates into $Root"
  } else {
    Write-Host "Updated scripts in $Root (kept your templates/shared-rules.md)"
  }
}

# ---------- discover courses, merge into courses.json ----------
# "MBA 693R-007: Special Topics" -> "MBA 693R-007 - Special Topics" (Windows-safe)
function SafeName($s) { ((($s -replace ':', ' -') -replace '[\\/:*?"<>|]', '') -replace '\s+', ' ').Trim() }

$mapPath = Join-Path $Root 'courses.json'
$existed = Test-Path $mapPath
if ($existed) {
  $cfg = Get-Content $mapPath -Raw -Encoding UTF8 | ConvertFrom-Json
  Write-Host "Found an existing workspace here ($(@($cfg.courses).Count) courses) - adopting it, not rebuilding."
} else {
  if ($Reuse) { Write-Host "No courses.json here, so there is nothing to adopt. Setting up fresh." -F Yellow }
  $cfg = [pscustomobject]@{ owner = $me.name; base = $Base; tokenExpires = $null; agents = @(); courses = @() }
}
foreach ($p in 'owner', 'base', 'tokenExpires', 'agents', 'courses') {
  if (-not ($cfg.PSObject.Properties.Name -contains $p)) { $cfg | Add-Member -NotePropertyName $p -NotePropertyValue $null }
}
$cfg.courses = @($cfg.courses)
$cfg.base    = $Base

# Agent choice: this run's -Agents wins; else what the workspace already recorded;
# else all three, so a plain non-interactive install stays fully capable.
if ($agentList)                 { $cfg.agents = @($agentList) }
elseif (-not @($cfg.agents))    { $cfg.agents = @('claude', 'codex', 'antigravity') }
else                            { $cfg.agents = @($cfg.agents) }

$known = @{}; foreach ($c in $cfg.courses) { $known[[string]$c.id] = $true }
$live  = Invoke-CanvasApi "$Api/courses?enrollment_state=active&per_page=100&include[]=term"
$added = 0
foreach ($c in @($live)) {
  if ($known.ContainsKey([string]$c.id)) { continue }
  $name = SafeName $c.name
  # Short label for DUE.md: the course code, or the part of the name before " - "
  # when the code is something unhelpful like "Class of 2028 - Fall 2026".
  $short = if ($c.course_code -and $c.course_code.Length -le 16) { $c.course_code }
           else { $lead = ($name -split ' - ')[0]; $lead.Substring(0, [Math]::Min(16, $lead.Length)) }
  $cfg.courses += [pscustomobject]@{ id = $c.id; folder = $name; short = $short; term = $c.term.name; enabled = $true }
  $added++
}
# UTF-8 without a BOM: PS 5.1's -Encoding UTF8 adds one, and JSON.parse in Node
# (and json.load in Python) rejects a leading BOM. courses.json is read by other
# programs, not just PowerShell.
[System.IO.File]::WriteAllText($mapPath, (ConvertTo-Json -InputObject $cfg -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "courses.json: $(@($cfg.courses).Count) courses ($added new), agents: $($cfg.agents -join ', ')."
Write-Host 'Set "enabled": false on any course you want skipped, then rerun.'

# Codex refuses any folder that is not a git repo. git is not preinstalled on
# Windows, so without this the student gets a clean-looking run and then a
# "Not inside a trusted directory" error with no connection to anything said here.
if (($cfg.agents -contains 'codex') -and -not (Get-Command git -EA SilentlyContinue)) {
  Write-Warning ("You chose Codex, but Git is not installed. The class folders will be created, " +
                 "but Codex will refuse to open them until you install Git for Windows " +
                 "(winget install Git.Git, or git-scm.com) and rerun this script.")
}

# The workspace holds the student's name, course list and Canvas grades, and the
# per-class git repos below would happily stage all of it. Protect it at the root
# before anything can be committed.
$wsIgnore = Join-Path $Root '.gitignore'
$wantIgnore = @(
  'courses.json', 'DUE.md', 'CHANGES.md', 'STANDUP.md', 'canvas-deadlines.ics',
  '.canvas-snapshot.json', '.standup-seen.json',
  '*/canvas/', '*/sources/', '*/work/', '*/submissions/',
  '*/STATUS.md', '*/AGENTS.md', '*/CLAUDE.md', '*/GEMINI.md'
)
# APPEND what is missing rather than skipping an existing file: a workspace
# created by an older version would otherwise never receive a new exclusion,
# and every future addition would silently miss everyone who already installed.
$haveIgnore = if (Test-Path $wsIgnore) { @(Get-Content $wsIgnore -Encoding UTF8) } else { @() }
$addIgnore  = @($wantIgnore | Where-Object { $haveIgnore -notcontains $_ })
if ($addIgnore) {
  $header = if ($haveIgnore) { @() } else { @('# Personal. Your Canvas mirror, notes and coursework are not for publication.') }
  $body = (@($haveIgnore) + $header + $addIgnore | Where-Object { $_ -ne $null }) -join "`r`n"
  [System.IO.File]::WriteAllText($wsIgnore, $body + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
}

# ---------- folders, rules, first snapshot ----------
& (Join-Path $Root 'scaffold-class.ps1')
& (Join-Path $Root 'canvas-watch.ps1')

# ---------- schedule ----------
# Task Scheduler on Windows, a launchd agent on macOS. Register-CanvasSchedule
# picks; it returns rather than throws when a platform cannot schedule, because
# a workspace that built fine should not report as a failed install just because
# the recurring job could not be registered.
if (-not $NoSchedule) {
  $r = Register-CanvasSchedule -Name "Canvas Watch - $(Split-Path $Root -Leaf)" `
         -ScriptPath (Join-Path $Root 'canvas-watch.ps1') -EveryHours $Every
  if ($r.Ok) { Write-Host "$($r.Detail) Refreshing every $Every h." }
  else       { Write-Warning "Could not schedule the watcher: $($r.Detail). Run canvas-watch.ps1 yourself when you want an update." }
}
# ---------- standup ----------
& (Join-Path $Root 'standup.ps1') -Quiet
if (-not $NoSchedule -and $StandupAt) {
  $s = Register-CanvasSchedule -Name "Canvas Standup - $(Split-Path $Root -Leaf)" `
         -ScriptPath (Join-Path $Root 'standup.ps1') -ExtraArgs @('-Refresh', '-Quiet') `
         -DailyAt $StandupAt -EveryHours 24 `
         -Description 'Refreshes the Canvas mirror and rewrites STANDUP.md. Read-only.'
  if ($s.Ok) { Write-Host "$($s.Detail) Daily at $StandupAt." }
  else       { Write-Warning "Could not schedule the standup: $($s.Detail). Run standup.ps1 yourself any time." }
}

$dueHint     = Join-Path $Root 'DUE.md'
$standupHint = Join-Path $Root 'STANDUP.md'
$icsHint     = Join-Path $Root 'canvas-deadlines.ics'
Write-Host ""
Write-Host "Done. Open $dueHint for everything, or $standupHint for today." -F Green
Write-Host "Calendar file: $icsHint - import it into Google, Outlook or Apple Calendar." -F DarkGray
Write-Host "Anything unclear? Ask your AI assistant - it has the full instructions in SKILL.md." -F DarkGray
