# scaffold-class.ps1 - give every enabled class in courses.json the same agent setup.
# Creates sources\ work\ submissions\, AGENTS.md, CLAUDE.md, GEMINI.md, STATUS.md.
# Never overwrites STATUS.md or hand-written text in AGENTS.md: it refreshes only
# the block between the SHARED RULES markers. Rerun any time.
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$cfg  = Get-Content (Join-Path $Root 'courses.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$tpl  = Get-Content (Join-Path $Root 'templates\shared-rules.md') -Raw -Encoding UTF8
$shared = $tpl -replace '\{\{OWNER\}\}', [string]$cfg.owner

# Why materialise instead of "@../shared-rules.md"? Claude Code refuses to read
# a parent of the folder it was launched in, so a parent import silently loads
# nothing. Tested 2026-09-14. Copies between markers are refreshable and work
# for Claude Code, Codex and Antigravity alike.
$BEGIN = '<!-- BEGIN SHARED RULES - generated from templates\shared-rules.md by scaffold-class.ps1. Edit the template, not this block. -->'
$END   = '<!-- END SHARED RULES -->'
$sharedBlock = "$BEGIN`n`n$shared`n$END"
$stamp = Get-Date -Format 'yyyy-MM-dd'

foreach ($c in @($cfg.courses)) {
  if ($c.enabled -eq $false) { continue }
  $dir = Join-Path $Root $c.folder
  foreach ($sub in 'sources', 'work', 'submissions') { New-Item -ItemType Directory -Force -Path (Join-Path $dir $sub) | Out-Null }

  $courseBlock = @"
## This course
| | |
|---|---|
| Canvas course id | $($c.id) |
| Canvas URL | $($cfg.base)/courses/$($c.id) |
| Canvas mirror | ``canvas/`` - regenerated every run, do not hand-edit |

## Course AI policy
**Not yet recorded.** Shared rule 8 applies until it is. Replace this section
once you have checked the syllabus or asked the instructor.
"@

  $agentsPath = Join-Path $dir 'AGENTS.md'
  if (Test-Path $agentsPath) {
    $cur = Get-Content $agentsPath -Raw -Encoding UTF8
    $i = $cur.IndexOf($BEGIN); $j = $cur.IndexOf($END)
    if ($i -ge 0 -and $j -gt $i) {
      Set-Content $agentsPath ($cur.Substring(0, $i) + $sharedBlock + $cur.Substring($j + $END.Length)) -Encoding UTF8
      $msg = 'shared rules refreshed'
    } else {
      Set-Content $agentsPath "$sharedBlock`n`n$cur" -Encoding UTF8
      $msg = 'shared rules inserted; existing text kept'
    }
  } else {
    Set-Content $agentsPath "# AGENTS.md - $($c.folder)`n`n$sharedBlock`n`n$courseBlock" -Encoding UTF8
    $msg = 'created'
  }

  foreach ($shim in 'CLAUDE.md', 'GEMINI.md') {
    $p = Join-Path $dir $shim
    if (-not (Test-Path $p)) {
      Set-Content $p "# $shim`n`nThe rules for this folder live in AGENTS.md and are imported below.`nRead STATUS.md before working and update it after.`n`n@AGENTS.md`n@STATUS.md" -Encoding UTF8
    }
  }

  $statusPath = Join-Path $dir 'STATUS.md'
  if (-not (Test-Path $statusPath)) {
    Set-Content $statusPath @"
# STATUS - $($c.folder)

Last updated: $stamp (scaffolded)

Deadlines: ``canvas\assignments.md`` here, ``..\DUE.md`` for every class. Both
refresh on a schedule and can be hours behind. Confirm in Canvas (shared rule 6).

## Next step
Nothing recorded yet. Replace this line with the actual next action.

## Open questions
- What is this course's AI policy? Until answered, shared rule 8 applies.

## Log
- $stamp - Folder scaffolded.
"@ -Encoding UTF8
  }
  Write-Host ("{0,-50} {1}" -f $c.folder, $msg)
}
