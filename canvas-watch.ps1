# canvas-watch.ps1 - read-only Canvas mirror for every class in courses.json.
# Writes <class>\canvas\{syllabus,assignments}.md + assignments.json, and one
# combined DUE.md and CHANGES.md at the root. Never submits, grades, or messages.
#
# Needs $env:CANVAS_TOKEN (never written to disk). courses.json comes from
# setup.ps1. Optional $env:CANVAS_BASE overrides the Canvas host.
$ErrorActionPreference = 'Stop'
$Root    = $PSScriptRoot
$MapPath = Join-Path $Root 'courses.json'
$Snap    = Join-Path $Root '.canvas-snapshot.json'
$Log     = Join-Path $Root 'CHANGES.md'
$DuePath = Join-Path $Root 'DUE.md'   # not $Due: PowerShell vars are case-insensitive
$Horizon = 14                          # days shown in full detail in DUE.md

# setx writes HKCU\Environment, invisible to an already-running process (the AI
# agent driving this, or a scheduled task started before the value was set).
# Read the User scope directly. The value is never displayed.
if (-not $env:CANVAS_TOKEN) { $env:CANVAS_TOKEN = [Environment]::GetEnvironmentVariable('CANVAS_TOKEN', 'User') }
if (-not $env:CANVAS_BASE)  { $env:CANVAS_BASE  = [Environment]::GetEnvironmentVariable('CANVAS_BASE',  'User') }
if (-not $env:CANVAS_TOKEN) { Write-Error 'CANVAS_TOKEN is not set. Run setup.ps1 for the three-step fix.' }
if (-not (Test-Path $MapPath)) { Write-Error 'courses.json not found. Run setup.ps1 first.' }
$cfg  = Get-Content $MapPath -Raw -Encoding UTF8 | ConvertFrom-Json
$Base = if ($env:CANVAS_BASE) { $env:CANVAS_BASE.TrimEnd('/') } elseif ($cfg.base) { $cfg.base } else { 'https://byu.instructure.com' }
# The Bearer header carries an unscoped, full-account token to whatever this says.
# A plain-http value would put it on the wire in cleartext.
if ($Base -notmatch '^https://[A-Za-z0-9.-]+$') {
  Write-Error "Canvas address must be https:// and a plain host, e.g. https://yourschool.instructure.com - got '$Base'."
}
$Api  = "$Base/api/v1"

if ($cfg.tokenExpires) {
  $days = ([datetime]$cfg.tokenExpires - (Get-Date)).Days
  if ($days -lt 0)      { Write-Warning ("CANVAS_TOKEN expired $($cfg.tokenExpires). Make a new one, copy it, then run this in Windows PowerShell (not Command Prompt): " +
                                         "[Environment]::SetEnvironmentVariable('CANVAS_TOKEN', (Get-Clipboard), 'User'); Set-Clipboard -Value 'cleared'  -  then update tokenExpires in courses.json.") }
  elseif ($days -le 14) { Write-Warning "CANVAS_TOKEN expires in $days day(s), on $($cfg.tokenExpires)." }
}

$H = @{ Authorization = "Bearer $env:CANVAS_TOKEN" }

# Always returns a real array. Do NOT write @(SomeFunction ...) in this file:
# wrapping a function call in @() nests the returned array as a single element.
function AsArray($x) { if ($null -eq $x) { ,@() } else { ,@($x) } }

# Follows Canvas "Link: <...>; rel=next" pagination so >100 items still arrive.
function Get-CanvasAll($path) {
  $url = "$Api/$path"; $out = @()
  while ($url) {
    $r = Invoke-WebRequest -Uri $url -Headers $H -Method Get -UseBasicParsing
    $out += AsArray ($r.Content | ConvertFrom-Json)
    $url = $null
    $link = $r.Headers['Link']
    if ($link -and $link -match '<([^>]+)>;\s*rel="next"') { $url = $Matches[1] }
  }
  ,$out
}
function Get-Canvas($path) { Invoke-RestMethod -Uri "$Api/$path" -Headers $H -Method Get }

function Clean($html) {
  if (-not $html) { return '' }
  [System.Net.WebUtility]::HtmlDecode(($html -replace '<[^>]+>', '')) -replace '(\r?\n\s*){3,}', "`n`n"
}
# Assignment names contain "|" which would split a markdown table into bogus columns.
function MdCell($t) { ([string]$t) -replace '\|', '\|' }

# Canvas returns UTC. 05:59:59Z is 11:59pm the PREVIOUS day in Mountain Time.
# Converting is the difference between the right date and being a day off.
function LocalDue($v) {
  if (-not $v) { return $null }
  if ($v -is [datetime]) { return $v.ToLocalTime() }
  $dt = [datetimeoffset]::MinValue
  if ([datetimeoffset]::TryParse([string]$v, [ref]$dt)) { return $dt.LocalDateTime }
  Write-Warning "unparseable due date: '$v'"
  return $null
}

# OneDrive / Google Drive hold a file handle briefly after syncing it. Retry
# instead of dying, or a scheduled run fails silently and looks like "no changes".
function Save($text, $path, [switch]$Append) {
  $dir = Split-Path -Parent $path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  # UTF-8 WITHOUT a BOM. PS 5.1's "-Encoding UTF8" emits a BOM, and a BOM makes
  # JSON.parse in Node and json.load in Python fail outright on courses.json and
  # assignments.json - files this tool exists to hand to other programs.
  $enc  = New-Object System.Text.UTF8Encoding($false)
  $body = if ($text -is [array]) { $text -join "`r`n" } else { [string]$text }
  foreach ($i in 1..6) {
    try {
      if ($Append) { [System.IO.File]::AppendAllText($path, $body + "`r`n", $enc) }
      else         { [System.IO.File]::WriteAllText($path,  $body + "`r`n", $enc) }
      return
    } catch { Start-Sleep -Milliseconds (250 * $i) }
  }
  Write-Warning "could not write $path after 6 tries (locked by a sync client?)"
}

# ---------- pull every enabled course ----------
$now = Get-Date; $state = @{}; $all = @(); $seen = @()
foreach ($c in (AsArray $cfg.courses)) {
  if ($c.enabled -eq $false) { continue }
  $seen += [int]$c.id
  $outDir = Join-Path (Join-Path $Root $c.folder) 'canvas'
  try {
    $info = Get-Canvas "courses/$($c.id)`?include[]=syllabus_body"
    $asgs = Get-CanvasAll "courses/$($c.id)/assignments?per_page=100&include[]=submission"
  } catch {
    Write-Warning "$($c.short): fetch failed - $($_.Exception.Message.Split([Environment]::NewLine)[0])"
    continue
  }

  Save (Clean $info.syllabus_body) (Join-Path $outDir 'syllabus.md')
  Save (($asgs | Sort-Object due_at | ForEach-Object {
    $ld = LocalDue $_.due_at
    $d  = if ($ld) { $ld.ToString('yyyy-MM-dd HH:mm') } else { 'none' }
    "## $($_.name)`n- due: $d`n- points: $($_.points_possible)`n- submit via: $($_.submission_types -join ', ')`n- state: $($_.submission.workflow_state)`n- url: $($_.html_url)`n`n$(Clean $_.description)`n"
  }) -join "`n") (Join-Path $outDir 'assignments.md')
  Save (ConvertTo-Json -InputObject $asgs -Depth 10) (Join-Path $outDir 'assignments.json')

  foreach ($a in $asgs) {
    $state["$($c.id):$($a.id)"] = "$($c.short)|$($a.name)|due=$($a.due_at)|pts=$($a.points_possible)"
    $dueLocal = LocalDue $a.due_at
    if ($dueLocal) {
      $all += [pscustomobject]@{
        Due = $dueLocal; Course = $c.short; Name = $a.name; Pts = $a.points_possible
        Sub = $a.submission.workflow_state; Paper = ($a.submission_types -contains 'on_paper'); Url = $a.html_url
      }
    }
  }
  Write-Host ("{0,-18} {1,3} assignments" -f $c.short, $asgs.Count)
}

# New enrollment not in courses.json? Say so, so next semester is one rerun of setup.
try {
  foreach ($l in (AsArray (Get-Canvas 'courses?enrollment_state=active&per_page=100'))) {
    if ($seen -notcontains [int]$l.id -and -not ((AsArray $cfg.courses) | Where-Object { [int]$_.id -eq [int]$l.id })) {
      Write-Warning "Enrolled but not in courses.json: $($l.id) - $($l.name). Rerun setup.ps1 to add it."
    }
  }
} catch { }

# If the fetch collapsed to a fraction of last time (a network blip, or some
# courses erroring), do NOT rewrite DUE.md or the snapshot - that would log mass
# REMOVED now and mass NEW next run. Keep the last good state and bail.
if (Test-Path $Snap) {
  $prev = Get-Content $Snap -Raw -Encoding UTF8 -EA SilentlyContinue
  $prevCount = if ($prev) { @((ConvertFrom-Json $prev).PSObject.Properties).Count } else { 0 }
  if ($prevCount -ge 20 -and $state.Count -lt ($prevCount * 0.6)) {
    Write-Warning "fetched $($state.Count) assignments vs $prevCount last run - likely a partial fetch. Left DUE.md and the snapshot untouched."
    exit 1
  }
}

# ---------- DUE.md ----------
$open    = $all | Where-Object { $_.Sub -notin @('graded', 'submitted') }
$soon    = @($open | Where-Object { $_.Due -gt $now -and $_.Due -le $now.AddDays($Horizon) } | Sort-Object Due)
$later   = @($open | Where-Object { $_.Due -gt $now.AddDays($Horizon) } | Sort-Object Due)
$overdue = @($open | Where-Object { $_.Due -le $now } | Sort-Object Due)

$md = @()
$md += "# What's due - all classes"
$md += ""
$md += "_Generated $($now.ToString('yyyy-MM-dd HH:mm')) local. Read-only mirror; Canvas is the source of truth._"
$md += "_Items marked (paper) are handed in physically - Canvas never shows them as submitted._"
$md += ""
if ($overdue.Count) {
  $md += "## Past due, still unsubmitted ($($overdue.Count))"; $md += ""
  $md += "| Due | Age | Class | Assignment | Pts |"; $md += "|---|---|---|---|---|"
  foreach ($x in ($overdue | Select-Object -Last 15)) {
    $tag = if ($x.Paper) { ' (paper)' } else { '' }
    $md += "| $($x.Due.ToString('ddd MMM dd')) | $([int]($now - $x.Due).TotalDays)d | $(MdCell $x.Course) | [$(MdCell $x.Name)]($($x.Url))$tag | $($x.Pts) |"
  }
  if ($overdue.Count -gt 15) { $md += ""; $md += "_...and $($overdue.Count - 15) older, not listed._" }
  $md += ""
}
$md += "## Next $Horizon days ($($soon.Count))"; $md += ""
if ($soon.Count) {
  $md += "| Due | In | Class | Assignment | Pts |"; $md += "|---|---|---|---|---|"
  foreach ($x in $soon) {
    $d = [int][Math]::Ceiling(($x.Due - $now).TotalDays)
    $tag = if ($x.Paper) { ' (paper)' } else { '' }
    $md += "| $($x.Due.ToString('ddd MMM dd, h:mm tt')) | ${d}d | $(MdCell $x.Course) | [$(MdCell $x.Name)]($($x.Url))$tag | $($x.Pts) |"
  }
} else { $md += "_Nothing due in the next $Horizon days._" }
$md += ""
$md += "## Later ($($later.Count))"; $md += ""
if ($later.Count) {
  $md += "| Class | Remaining | Next one |"; $md += "|---|---|---|"
  foreach ($g in ($later | Group-Object Course | Sort-Object { ($_.Group | Sort-Object Due)[0].Due })) {
    $n = ($g.Group | Sort-Object Due)[0]
    $md += "| $(MdCell $g.Name) | $($g.Count) | $($n.Due.ToString('MMM dd')) - $(MdCell $n.Name) |"
  }
}
Save ($md -join "`n") $DuePath

# ---------- change log ----------
$stamp = $now.ToString('yyyy-MM-dd HH:mm')
if (-not (Test-Path $Snap)) {
  Save "# Canvas change log`n`n- $stamp - baseline captured ($($state.Count) assignments)." $Log
  Write-Host "`n$stamp - baseline captured ($($state.Count) assignments)."
} else {
  # A cloud-synced snapshot can read back empty while OneDrive / Drive is still
  # hydrating it. Diffing against nothing would log every assignment as NEW
  # (seen 2026-09-14 on the first run after a move to Google Drive). Re-baseline
  # quietly instead; the next run diffs normally.
  $old = @{}
  $rawSnap = Get-Content $Snap -Raw -Encoding UTF8 -EA SilentlyContinue
  if ($rawSnap) { (ConvertFrom-Json $rawSnap).PSObject.Properties | ForEach-Object { $old[$_.Name] = $_.Value } }
  if ($old.Count -eq 0) {
    Write-Warning "snapshot exists but read back empty (still syncing?). Re-baselined; no changes logged this run."
    Save (,"- $stamp - snapshot unreadable, re-baselined ($($state.Count) assignments)") $Log -Append
    Save (ConvertTo-Json -InputObject $state -Depth 5) $Snap
    Write-Host "DUE.md: $($overdue.Count) past due, $($soon.Count) in $Horizon days, $($later.Count) later"
    exit 0
  }
  $lines = @()
  foreach ($k in $state.Keys) {
    if (-not $old.ContainsKey($k))   { $lines += "  - NEW     $($state[$k])" }
    elseif ($old[$k] -ne $state[$k]) { $lines += "  - CHANGED`n      was: $($old[$k])`n      now: $($state[$k])" }
  }
  foreach ($k in $old.Keys) { if (-not $state.ContainsKey($k)) { $lines += "  - REMOVED $($old[$k])" } }
  if ($lines) { Save (,"- $stamp" + $lines) $Log -Append; Write-Host "`n$stamp - $($lines.Count) change(s) - see CHANGES.md" }
  else        { Write-Host "`n$stamp - no changes" }
}
Save (ConvertTo-Json -InputObject $state -Depth 5) $Snap
Write-Host "DUE.md: $($overdue.Count) past due, $($soon.Count) in $Horizon days, $($later.Count) later"
