<#
standup.ps1 - a one-screen standup of everything outstanding, from the local
Canvas mirror. Also exports the same deadlines as a calendar file you can import
into Google Calendar, Outlook or Apple Calendar.

  .\standup.ps1                 print it, write STANDUP.md and the .ics
  .\standup.ps1 -Refresh        refresh the Canvas mirror first (needs the token)
  .\standup.ps1 -Days 14        change the look-ahead window (default 7)
  .\standup.ps1 -Quiet          write the files, print nothing

Reads only what canvas-watch.ps1 already mirrored, so it needs no token, no
network and no Canvas call. It never submits, grades or messages anything.
#>
param([switch]$Refresh, [int]$Days = 7, [switch]$Quiet)
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$cfgPath = Join-Path $Root 'courses.json'
if (-not (Test-Path $cfgPath)) { Write-Error "No courses.json here. Run setup.ps1 first." }

if ($Refresh) {
  # Prefer whichever watcher this workspace actually schedules. A workspace that
  # grew its own multi-class canvas-watch-all.ps1 must not be refreshed by a
  # different script than the hourly job uses, or the two disagree about layout
  # and the standup reads one while the other writes the other.
  $watcher = @('canvas-watch-all.ps1', 'canvas-watch.ps1') |
             ForEach-Object { Join-Path $Root $_ } |
             Where-Object { Test-Path $_ } |
             Select-Object -First 1
  if (-not $watcher) { Write-Error "-Refresh needs canvas-watch.ps1 (or canvas-watch-all.ps1) next to this script, and neither is here." }
  & $watcher | Out-Null
}

# UTF-8 without a BOM: JSON.parse and json.load both reject a leading BOM, and a
# BOM in an .ics file makes some calendar importers reject the whole file.
function WriteUtf8($path, $text) {
  [System.IO.File]::WriteAllText($path, ([string]$text) + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
}
function LocalDue($v) {
  if (-not $v) { return $null }
  if ($v -is [datetime]) { return $v.ToLocalTime() }
  $dt = [datetimeoffset]::MinValue
  if ([datetimeoffset]::TryParse([string]$v, [ref]$dt)) { return $dt.LocalDateTime }
  return $null
}
function MdCell($t) { ([string]$t) -replace '\|', '\|' }

# The watcher refreshes hourly, so three missed hours is a stopped watcher, not
# a slow one. Raise this if you deliberately set -Every higher than 1.
$STALE_H = 3

$cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
$now = Get-Date
$items = @()
$oldest = $null
$missing = @()   # classes whose mirror is absent, so they appear nowhere below

foreach ($c in @($cfg.courses)) {
  if ($c.enabled -eq $false) { continue }
  # Join-Path rather than a literal 'sources\canvas'. On macOS a backslash is a
  # legal filename character, not a separator, so the literal form would not
  # error - it would quietly match nothing and report every class as empty.
  $srcSub = Join-Path 'sources' 'canvas'
  $sub = if ($c.folder -and (Test-Path (Join-Path $Root (Join-Path $c.folder (Join-Path $srcSub 'assignments.json'))))) { $srcSub } else { 'canvas' }
  $f = Join-Path $Root (Join-Path $c.folder (Join-Path $sub 'assignments.json'))
  # Missing mirror means this whole class is invisible below. Silently skipping
  # it let a student read a confident standup with an entire course absent while
  # the freshness line still said "0 h old". Count it and say so.
  if (-not (Test-Path $f)) { $missing += $c.short; continue }
  $stamp = (Get-Item $f).LastWriteTime
  if (-not $oldest -or $stamp -lt $oldest) { $oldest = $stamp }
  # A course with no assignments leaves an empty file, and ConvertFrom-Json
  # throws on whitespace rather than returning nothing.
  $raw = Get-Content $f -Raw -Encoding UTF8
  if ([string]::IsNullOrWhiteSpace($raw)) { continue }
  try { $a = $raw | ConvertFrom-Json } catch { Write-Warning "skipping $($c.folder): assignments.json is not valid JSON"; continue }
  if ($null -eq $a) { continue }
  foreach ($x in @($a)) {
    $due = LocalDue $x.due_at
    if (-not $due) { continue }
    if ($x.submission.workflow_state -in @('graded', 'submitted')) { continue }
    $items += [pscustomobject]@{
      Due = $due; Course = $c.short; Name = $x.name
      Pts = [double]$x.points_possible
      Paper = (@($x.submission_types) -contains 'on_paper')
      Url = $x.html_url; CourseId = $c.id; Id = $x.id
    }
  }
}

# ---------------- what changed since the last standup ----------------
# Its own seen-state, independent of the watcher's snapshot: the watcher records
# what Canvas looked like, this records what YOU were last told. An instructor
# posting eleven new assignments at 7pm should be the first line you read.
$seenPath = Join-Path $Root '.standup-seen.json'
$seen = @{}
if (Test-Path $seenPath) {
  $rawSeen = Get-Content $seenPath -Raw -Encoding UTF8 -EA SilentlyContinue
  if (-not [string]::IsNullOrWhiteSpace($rawSeen)) {
    # Say so when it is unreadable. Swallowing this silently makes a corrupt
    # file look like a first run, so that cycle's NEW and MOVED items - the only
    # reason this feature exists - are dropped and never mentioned again.
    try { (ConvertFrom-Json $rawSeen).PSObject.Properties | ForEach-Object { $seen[$_.Name] = $_.Value } }
    catch { Write-Warning "$seenPath is unreadable, so changes since the last standup cannot be shown this once. It will be rebuilt now and work normally from the next run." }
  }
}
$firstRun = ($seen.Count -eq 0)
$nowSeen = @{}
$newItems = @(); $movedItems = @()
foreach ($x in $items) {
  $k = "$($x.CourseId):$($x.Id)"
  $stamp = "$($x.Due.ToString('yyyy-MM-ddTHH:mm'))|$($x.Pts)"
  $nowSeen[$k] = $stamp
  if (-not $firstRun) {
    if (-not $seen.ContainsKey($k)) { $newItems += $x }
    elseif ($seen[$k] -ne $stamp) {
      # Compare the DUE part only. The stamp also carries points, so an
      # instructor re-weighting an assignment used to be reported as MOVED with
      # an identical before and after date - which reads as a bug in the report.
      $wasDue = ($seen[$k] -split '\|')[0]
      if ($wasDue -ne $x.Due.ToString('yyyy-MM-ddTHH:mm')) {
        $movedItems += [pscustomobject]@{ Item = $x; Was = $wasDue }
      }
    }
  }
}

$today   = @($items | Where-Object { $_.Due.Date -eq $now.Date -and $_.Due -ge $now } | Sort-Object Due)
$overdue = @($items | Where-Object { $_.Due -lt $now } | Sort-Object Due -Descending)
$window  = @($items | Where-Object { $_.Due -gt $now -and $_.Due.Date -ne $now.Date -and $_.Due -le $now.AddDays($Days) } | Sort-Object Due)
$graded  = @($window | Where-Object { $_.Pts -gt 0 })

# ---------------- STANDUP.md ----------------
$age = if ($oldest) { [int]($now - $oldest).TotalHours } else { -1 }
$md = @()
$md += "# Standup - $($now.ToString('dddd, MMMM d, yyyy h:mm tt'))"
$md += ""
if ($age -lt 0) {
  $md += "> **The Canvas mirror is missing.** Nothing below is trustworthy. Run ``.\canvas-watch.ps1`` first."
} elseif ($age -gt $STALE_H) {
  $md += "> **The Canvas mirror is $age h old** - the hourly watcher has missed about $age runs, so anything added or moved since then is not shown here. Run ``.\doctor.ps1`` to find out why, or ``.\standup.ps1 -Refresh`` to update now."
} else {
  $md += "_Canvas mirror is $age h old. Confirm anything time-critical in Canvas itself._"
}
if ($missing.Count) {
  # A class with no mirror contributes nothing below, and the freshness line
  # above would still read "0 h old" - a confident report with a course silently
  # absent. Name them.
  $md += ""
  $md += "> **$($missing.Count) class(es) are missing from this report** - $($missing -join ', ') - because their Canvas mirror has not been written yet. Nothing from them is counted below. Refresh the watcher, or run ``.\doctor.ps1`` if it keeps happening."
}
$md += ""
$md += "**$($overdue.Count) past due - $($today.Count) due today - $($window.Count) in the next $Days days ($($graded.Count) worth points)**"
$md += ""

$md += "## Since your last standup"
$md += ""
if ($firstRun) {
  $md += "- First run, so nothing to compare against yet. From now on this section lists"
  $md += "  anything newly posted or rescheduled."
} elseif (-not $newItems.Count -and -not $movedItems.Count) {
  $md += "- Nothing new or rescheduled."
} else {
  foreach ($x in ($newItems | Sort-Object Due)) {
    $p = if ($x.Pts -gt 0) { " **($($x.Pts) pts)**" } else { "" }
    $md += "- **NEW** $(MdCell $x.Course) - [$(MdCell $x.Name)]($($x.Url)) - due $($x.Due.ToString('ddd MMM dd, h:mm tt'))$p"
  }
  foreach ($m in ($movedItems | Sort-Object { $_.Item.Due })) {
    $x = $m.Item
    $md += "- **MOVED** $(MdCell $x.Course) - [$(MdCell $x.Name)]($($x.Url)) - was $($m.Was), now $($x.Due.ToString('ddd MMM dd, h:mm tt'))"
  }
  $newPts = ($newItems | Measure-Object Pts -Sum).Sum
  if ($newPts -gt 0) { $md += ""; $md += "_$($newItems.Count) new item(s) worth $newPts points._" }
}
$md += ""

$md += "## Due today"
$md += ""
if ($today.Count) {
  foreach ($x in $today) {
    $p = if ($x.Pts -gt 0) { " **($($x.Pts) pts)**" } else { "" }
    $t = if ($x.Paper) { " _(hand in on paper)_" } else { "" }
    $md += "- **$($x.Due.ToString('h:mm tt'))** - $(MdCell $x.Course) - [$(MdCell $x.Name)]($($x.Url))$p$t"
  }
} else { $md += "- Nothing due today." }
$md += ""

$md += "## Next $Days days"
$md += ""
if ($window.Count) {
  $lastDay = ''
  foreach ($x in $window) {
    $d = $x.Due.ToString('ddd MMM dd')
    if ($d -ne $lastDay) { $md += ""; $md += "**$d**"; $lastDay = $d }
    $p = if ($x.Pts -gt 0) { " **($($x.Pts) pts)**" } else { "" }
    $t = if ($x.Paper) { " _(paper)_" } else { "" }
    $md += "- $($x.Due.ToString('h:mm tt')) - $(MdCell $x.Course) - [$(MdCell $x.Name)]($($x.Url))$p$t"
  }
} else { $md += "- Nothing in the next $Days days." }
$md += ""

$md += "## Past due, still unsubmitted"
$md += ""
if ($overdue.Count) {
  foreach ($x in ($overdue | Select-Object -First 10)) {
    $p = if ($x.Pts -gt 0) { " **($($x.Pts) pts)**" } else { "" }
    $t = if ($x.Paper) { " _(paper - Canvas never marks these submitted)_" } else { "" }
    $md += "- $($x.Due.ToString('MMM dd')) ($([int]($now - $x.Due).TotalDays)d ago) - $(MdCell $x.Course) - [$(MdCell $x.Name)]($($x.Url))$p$t"
  }
  if ($overdue.Count -gt 10) { $md += "- _...and $($overdue.Count - 10) older._" }
} else { $md += "- Nothing outstanding." }
$md += ""
$md += "---"
$md += "_Zero-point rows are usually readings or attendance. Rows marked paper are"
$md += "handed in physically, so Canvas never shows them submitted._"

WriteUtf8 (Join-Path $Root 'STANDUP.md') ($md -join "`n")

# ---------------- calendar export ----------------
# RFC 5545. Escape TEXT values and fold lines at 75 octets, or strict importers
# (Outlook especially) reject the file.
function IcsText($t) {
  # .Replace for the backslash, NOT -replace. A -replace REPLACEMENT string is
  # handed to .NET Regex.Replace, where a backslash is literal - so '\\\\' emits
  # FOUR backslashes, not the two RFC 5545 asks for, and every path in a
  # description rendered doubled. .Replace has no regex semantics either side.
  # It must run first, or it would escape the backslashes the later rules add.
  (([string]$t).Replace('\', '\\') -replace ';', '\;' -replace ',', '\,' -replace "`r`n", '\n' -replace "`n", '\n')
}
function IcsFold($line) {
  $bytes = [Text.Encoding]::UTF8.GetBytes($line)
  if ($bytes.Length -le 75) { return $line }
  $out = New-Object Text.StringBuilder
  $cur = 0
  foreach ($ch in $line.ToCharArray()) {
    $w = [Text.Encoding]::UTF8.GetByteCount([string]$ch)
    if ($cur + $w -gt 74) { [void]$out.Append("`r`n "); $cur = 1 }
    [void]$out.Append($ch); $cur += $w
  }
  return $out.ToString()
}
$stampUtc = $now.ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$ics = @()
$ics += 'BEGIN:VCALENDAR'
$ics += 'VERSION:2.0'
$ics += 'PRODID:-//mba-canvas-workspace//Canvas deadlines//EN'
$ics += 'CALSCALE:GREGORIAN'
$ics += 'METHOD:PUBLISH'
$ics += 'X-WR-CALNAME:Canvas deadlines'
foreach ($x in ($items | Sort-Object Due)) {
  # A zero-duration event (DTSTART == DTEND) renders as a bare dot in Google and
  # is easy to miss entirely. Give it a visible 30-minute block that ENDS at the
  # deadline, so the event still sits on the correct day and hour.
  # Subtract in UTC, never in local time. A local subtraction can land inside a
  # DST spring-forward gap - an hour that does not exist - and converting that
  # back yields a DTSTART AFTER its DTEND, which strict importers reject.
  # Measured: a 03:15 deadline on 2027-03-14 Mountain gave DTSTART 09:45Z with
  # DTEND 09:15Z. UTC has no gaps, so 30 minutes is always 30 minutes.
  $dueUtc = $x.Due.ToUniversalTime()
  $utc    = $dueUtc.ToString('yyyyMMddTHHmmssZ')
  $start  = $dueUtc.AddMinutes(-30).ToString('yyyyMMddTHHmmssZ')
  $ics += 'BEGIN:VEVENT'
  $ics += "UID:canvas-$($x.CourseId)-$($x.Id)@mba-canvas-workspace"
  $ics += "DTSTAMP:$stampUtc"
  $ics += "DTSTART:$start"
  $ics += "DTEND:$utc"
  $ics += IcsFold ("SUMMARY:" + (IcsText "$($x.Course): $($x.Name)"))
  $desc = "Due $($x.Due.ToString('ddd MMM dd, h:mm tt')). " +
          $(if ($x.Pts -gt 0) { "$($x.Pts) points. " } else { "Not graded. " }) +
          $(if ($x.Paper) { "Handed in on paper. " } else { "" }) + $x.Url
  $ics += IcsFold ("DESCRIPTION:" + (IcsText $desc))
  $ics += IcsFold ("URL:" + $x.Url)
  $ics += 'END:VEVENT'
}
$ics += 'END:VCALENDAR'
WriteUtf8 (Join-Path $Root 'canvas-deadlines.ics') ($ics -join "`r`n")

# ---------------- console ----------------
if (-not $Quiet) {
  Write-Host ""
  Write-Host "STANDUP  $($now.ToString('ddd MMM dd, h:mm tt'))" -F Cyan
  Write-Host ("  {0} past due | {1} due today | {2} in {3} days ({4} graded)" -f $overdue.Count, $today.Count, $window.Count, $Days, $graded.Count)
  if ($missing.Count) { Write-Warning "$($missing.Count) class(es) have no Canvas mirror yet and are NOT in this report: $($missing -join ', ')." }
  if ($age -gt $STALE_H) { Write-Warning "Canvas mirror is $age h old - the hourly watcher has missed about $age runs. Check it with doctor.ps1, or refresh now with -Refresh." }
  Write-Host ""
  if ($today.Count) {
    Write-Host "TODAY" -F Yellow
    foreach ($x in $today) { "  {0,-8} {1,-12} {2}{3}" -f $x.Due.ToString('h:mm tt'), $x.Course, $x.Name, $(if ($x.Pts -gt 0) { " ($($x.Pts) pts)" } else { '' }) }
    Write-Host ""
  }
  if ($window.Count) {
    Write-Host "NEXT $Days DAYS" -F Yellow
    foreach ($x in ($window | Select-Object -First 12)) { "  {0,-13} {1,-12} {2}{3}" -f $x.Due.ToString('ddd MMM dd'), $x.Course, $x.Name, $(if ($x.Pts -gt 0) { " ($($x.Pts) pts)" } else { '' }) }
    if ($window.Count -gt 12) { "  ...and $($window.Count - 12) more" }
    Write-Host ""
  }
  if ($overdue.Count) {
    Write-Host "PAST DUE ($($overdue.Count))" -F Red
    foreach ($x in ($overdue | Select-Object -First 5)) { "  {0,-13} {1,-12} {2}" -f $x.Due.ToString('MMM dd'), $x.Course, $x.Name }
    Write-Host ""
  }
  if ($newItems.Count -or $movedItems.Count) {
    Write-Host "SINCE LAST STANDUP" -F Magenta
    foreach ($x in ($newItems | Sort-Object Due | Select-Object -First 8)) {
      "  NEW    {0,-12} {1}{2}" -f $x.Course, $x.Name, $(if ($x.Pts -gt 0) { " ($($x.Pts) pts)" } else { '' })
    }
    if ($newItems.Count -gt 8) { "  ...and $($newItems.Count - 8) more new" }
    foreach ($m in ($movedItems | Select-Object -First 5)) {
      "  MOVED  {0,-12} {1}  (was {2})" -f $m.Item.Course, $m.Item.Name, $m.Was
    }
    Write-Host ""
  }
  Write-Host "Written: STANDUP.md and canvas-deadlines.ics" -F DarkGray
}

# Record what the owner has now been told. Written LAST, so a crash before this
# point leaves the old state and the same changes are reported again rather than
# being silently swallowed.
WriteUtf8 $seenPath (ConvertTo-Json -InputObject $nowSeen -Depth 3)
