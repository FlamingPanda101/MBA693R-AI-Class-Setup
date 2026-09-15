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

if ($Refresh) { & (Join-Path $Root 'canvas-watch.ps1') | Out-Null }

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

$cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
$now = Get-Date
$items = @()
$oldest = $null

foreach ($c in @($cfg.courses)) {
  if ($c.enabled -eq $false) { continue }
  $sub = if ($c.folder -and (Test-Path (Join-Path $Root (Join-Path $c.folder 'sources\canvas\assignments.json')))) { 'sources\canvas' } else { 'canvas' }
  $f = Join-Path $Root (Join-Path $c.folder (Join-Path $sub 'assignments.json'))
  if (-not (Test-Path $f)) { continue }
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

$today   = @($items | Where-Object { $_.Due.Date -eq $now.Date -and $_.Due -ge $now } | Sort-Object Due)
$overdue = @($items | Where-Object { $_.Due -lt $now } | Sort-Object Due -Descending)
$window  = @($items | Where-Object { $_.Due -gt $now -and $_.Due.Date -ne $now.Date -and $_.Due -le $now.AddDays($Days) } | Sort-Object Due)
$graded  = @($window | Where-Object { $_.Pts -gt 0 })

# ---------------- STANDUP.md ----------------
$age = if ($oldest) { [int]($now - $oldest).TotalHours } else { -1 }
$md = @()
$md += "# Standup - $($now.ToString('dddd, MMMM d, yyyy h:mm tt'))"
$md += ""
$md += "_Canvas mirror is $(if ($age -lt 0) { 'missing' } else { "$age h old" }). Confirm anything time-critical in Canvas itself._"
$md += ""
$md += "**$($overdue.Count) past due - $($today.Count) due today - $($window.Count) in the next $Days days ($($graded.Count) worth points)**"
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
  (([string]$t) -replace '\\', '\\\\' -replace ';', '\;' -replace ',', '\,' -replace "`r`n", '\n' -replace "`n", '\n')
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
  $utc   = $x.Due.ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
  $start = $x.Due.AddMinutes(-30).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
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
  if ($age -gt 5) { Write-Warning "Canvas mirror is $age h old. Run with -Refresh for current data." }
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
  Write-Host "Written: STANDUP.md and canvas-deadlines.ics" -F DarkGray
}
