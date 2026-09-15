<#
setup.ps1 - one-command bootstrap for a folder-per-class Canvas workspace.

  .\setup.ps1                      workspace = this folder
  .\setup.ps1 -Root C:\School      install the tool there and bootstrap it
  .\setup.ps1 -Every 6             refresh every 6 hours (default 4)
  .\setup.ps1 -NoSchedule          skip the Windows scheduled task

Discovers your enrolled courses from Canvas, writes courses.json, creates one
folder per course with agent rules, takes a first Canvas snapshot, and
schedules the read-only watcher. Safe to rerun: newly enrolled courses are
merged in, and your STATUS.md and hand-written rules are never overwritten.
#>
param([string]$Root = $PSScriptRoot, [int]$Every = 4, [switch]$NoSchedule)
$ErrorActionPreference = 'Stop'

# setx writes HKCU\Environment, which a process that was already running never
# sees - including the AI agent that is driving this script. Without this, an
# agent-run setup loops forever on "CANVAS_TOKEN is not set" even though the
# student set it correctly. Read the User scope directly; the value is never
# displayed, and `&`-invoked child scripts inherit it from $env:.
if (-not $env:CANVAS_TOKEN) { $env:CANVAS_TOKEN = [Environment]::GetEnvironmentVariable('CANVAS_TOKEN', 'User') }
if (-not $env:CANVAS_BASE)  { $env:CANVAS_BASE  = [Environment]::GetEnvironmentVariable('CANVAS_BASE',  'User') }

$Base = if ($env:CANVAS_BASE) { $env:CANVAS_BASE.TrimEnd('/') } else { 'https://byu.instructure.com' }
$Api  = "$Base/api/v1"

# The workspace must not be the tool folder. Otherwise this folder's CLAUDE.md /
# GEMINI.md / AGENTS.md sit above every class folder and each class session
# inherits the *installer* instructions instead of that class's rules.
if ($Root -eq $PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'SKILL.md'))) {
  Write-Error "Pass -Root <workspace path>, e.g. .\setup.ps1 -Root C:\Users\you\School. The tool folder cannot also be the workspace: its CLAUDE.md/AGENTS.md/GEMINI.md would load in every class session."
}

# ---------- 1. token (the one thing no script or agent should touch) ----------
if (-not $env:CANVAS_TOKEN) {
  Write-Host @"

CANVAS_TOKEN is not set. Three steps, done by YOU - not by an AI agent:

  1. Open  $Base/profile/settings  and click  + New Access Token
     Purpose: canvas-watcher.  Expires: end of semester is sensible.
  2. Copy the token. In a PowerShell window run exactly:
       setx CANVAS_TOKEN (Get-Clipboard); Set-Clipboard -Value 'cleared'
     That reads it from the clipboard so it never appears on screen or in
     your shell history, then wipes the clipboard so a stray Ctrl+V cannot
     paste your token into a chat. If you use Win+V clipboard history, also
     clear it: Settings > System > Clipboard > Clear clipboard data.
  3. Open a NEW PowerShell window and run this script again.

Never paste the token into a chat, a file, or a screenshot. It is unscoped:
whoever has it has your entire Canvas account.

"@
  exit 1
}
$H = @{ Authorization = "Bearer $env:CANVAS_TOKEN" }
try   { $me = Invoke-RestMethod "$Api/users/self" -Headers $H }
catch { Write-Error "Canvas at $Base rejected the token ($($_.Exception.Message)). Regenerate it and setx again. Wrong school? setx CANVAS_BASE https://yourschool.instructure.com" }
Write-Host "Canvas says hello, $($me.name)." -F Green

# ---------- 2. install the tool into $Root ----------
New-Item -ItemType Directory -Force -Path $Root | Out-Null
$Root = (Resolve-Path $Root).Path
if ($Root -ne $PSScriptRoot) {
  # Scripts are overwritten - that is how you take an update.
  foreach ($f in 'setup.ps1', 'canvas-watch.ps1', 'scaffold-class.ps1') { Copy-Item (Join-Path $PSScriptRoot $f) $Root -Force }
  # Templates are NOT: shared-rules.md is yours to edit, and the docs tell you to.
  # Copying it back every rerun would silently revert your rules into every class.
  if (-not (Test-Path (Join-Path $Root 'templates\shared-rules.md'))) {
    Copy-Item (Join-Path $PSScriptRoot 'templates') $Root -Recurse -Force
    Write-Host "Installed tool files and templates into $Root"
  } else {
    Write-Host "Updated scripts in $Root (kept your templates\shared-rules.md)"
  }
}

# ---------- 3. discover courses, merge into courses.json ----------
# "MBA 693R-007: Special Topics" -> "MBA 693R-007 - Special Topics" (Windows-safe)
function SafeName($s) { ((($s -replace ':', ' -') -replace '[\\/:*?"<>|]', '') -replace '\s+', ' ').Trim() }

$mapPath = Join-Path $Root 'courses.json'
if (Test-Path $mapPath) { $cfg = Get-Content $mapPath -Raw -Encoding UTF8 | ConvertFrom-Json }
else { $cfg = [pscustomobject]@{ owner = $me.name; base = $Base; tokenExpires = $null; courses = @() } }
$cfg.courses = @($cfg.courses)

$known = @{}; foreach ($c in $cfg.courses) { $known[[string]$c.id] = $true }
$live  = Invoke-RestMethod "$Api/courses?enrollment_state=active&per_page=100&include[]=term" -Headers $H
$added = 0
foreach ($c in @($live)) {
  if ($known.ContainsKey([string]$c.id)) { continue }
  $name  = SafeName $c.name
  # Short label for DUE.md: the course code, or the part of the name before " - "
  # when the code is something unhelpful like "Class of 2028 - Fall 2026".
  $short = if ($c.course_code -and $c.course_code.Length -le 16) { $c.course_code }
           else { $lead = ($name -split ' - ')[0]; $lead.Substring(0, [Math]::Min(16, $lead.Length)) }
  $cfg.courses += [pscustomobject]@{ id = $c.id; folder = $name; short = $short; term = $c.term.name; enabled = $true }
  $added++
}
ConvertTo-Json -InputObject $cfg -Depth 5 | Set-Content $mapPath -Encoding UTF8
Write-Host "courses.json: $($cfg.courses.Count) courses ($added new). Set ""enabled"": false on any you want skipped, then rerun."

# ---------- 4. folders + rules, 5. first snapshot ----------
& (Join-Path $Root 'scaffold-class.ps1')
& (Join-Path $Root 'canvas-watch.ps1')

# ---------- 6. schedule ----------
if (-not $NoSchedule) {
  $taskName = "Canvas Watch - $(Split-Path $Root -Leaf)"
  $action   = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Root\canvas-watch.ps1`""
  $trigger  = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) -RepetitionInterval (New-TimeSpan -Hours $Every) -RepetitionDuration (New-TimeSpan -Days 3650)
  $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 15)
  Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description 'Read-only Canvas mirror. Never submits, grades, or messages.' -Force | Out-Null
  Write-Host "Scheduled '$taskName' every $Every h. Check: Get-ScheduledTaskInfo -TaskName '$taskName'"
}
Write-Host "`nDone. Open $Root\DUE.md. Per-class detail is in <class>\canvas\." -F Green
