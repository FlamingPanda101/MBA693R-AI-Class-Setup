<#
platform.ps1 - the only file that knows which operating system this is.

Dot-source it, do not run it:

    . (Join-Path $PSScriptRoot 'platform.ps1')

Everything else in this tool is written once and stays platform-neutral. The
four things that genuinely differ - where a secret lives, how a recurring job
is registered, how the clipboard is read, and where cloud storage mounts - are
answered here and nowhere else.

Windows PowerShell 5.1 has no $IsWindows, and 5.1 only ever runs on Windows, so
its absence is itself the answer. On macOS and Linux the shell is PowerShell 7
(pwsh), where $IsWindows / $IsMacOS are automatic variables.

Set CANVAS_FORCE_PLATFORM to exercise another platform's DECISIONS on this one.
It changes which branch is chosen and what gets generated; it cannot conjure
launchctl or security onto a Windows box, and the functions that shell out to
them say so rather than pretending.
#>

function Get-CanvasPlatform {
  if ($env:CANVAS_FORCE_PLATFORM) {
    $f = $env:CANVAS_FORCE_PLATFORM.ToLower()
    if ($f -in @('windows', 'macos', 'linux')) { return $f }
    Write-Warning "CANVAS_FORCE_PLATFORM='$f' is not one of windows, macos, linux. Ignoring it."
  }
  if ($null -eq $IsWindows) { return 'windows' }   # PS 5.1, therefore Windows
  if ($IsWindows) { return 'windows' }
  if ($IsMacOS)   { return 'macos' }
  return 'linux'
}

function Test-CanvasReal {
  # True when the chosen platform is the one actually underfoot. Anything that
  # shells out to an OS binary must check this first, or a forced-branch test
  # run turns into a confusing "command not found" instead of a clear skip.
  $p = Get-CanvasPlatform
  if ($null -eq $IsWindows) { return $p -eq 'windows' }
  if ($IsWindows) { return $p -eq 'windows' }
  if ($IsMacOS)   { return $p -eq 'macos' }
  return $p -eq 'linux'
}

function Get-CanvasHome {
  if ((Get-CanvasPlatform) -eq 'windows') {
    if ($env:USERPROFILE) { return $env:USERPROFILE }
    return [Environment]::GetFolderPath('UserProfile')
  }
  if ($env:HOME) { return $env:HOME }
  return [Environment]::GetFolderPath('UserProfile')
}

function Get-CanvasTemp {
  if ((Get-CanvasPlatform) -eq 'windows') {
    if ($env:TEMP) { return $env:TEMP }
  } elseif ($env:TMPDIR) {
    return $env:TMPDIR.TrimEnd('/')
  }
  return [System.IO.Path]::GetTempPath().TrimEnd([System.IO.Path]::DirectorySeparatorChar)
}

function Get-CanvasShellExe {
  # What a scheduled job must invoke to run one of these scripts.
  if ((Get-CanvasPlatform) -eq 'windows') { return 'powershell.exe' }
  $c = Get-Command pwsh -EA SilentlyContinue
  if ($c) { return $c.Source }
  # Resolve at registration time; launchd needs an absolute path and does not
  # search PATH the way a login shell does.
  foreach ($p in '/opt/homebrew/bin/pwsh', '/usr/local/bin/pwsh', '/usr/bin/pwsh') {
    if (Test-Path $p) { return $p }
  }
  return 'pwsh'
}

function Get-CanvasRunCommand($scriptPath, $extra) {
  # The exact command line to run one of these scripts ON THIS MACHINE, ready to
  # paste. Printed rather than described so nobody has to translate a
  # "<pwsh> -File ..." placeholder into whatever their platform wants.
  $tail = if ($extra) { ' ' + (@($extra) -join ' ') } else { '' }
  if ((Get-CanvasPlatform) -eq 'windows') {
    return "powershell -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"$tail"
  }
  return "pwsh -NoProfile -File `"$scriptPath`"$tail"
}

function Get-CanvasShellArgs($scriptPath) {
  # -ExecutionPolicy does not exist outside Windows and pwsh errors on it.
  if ((Get-CanvasPlatform) -eq 'windows') {
    return @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $scriptPath)
  }
  return @('-NoProfile', '-File', $scriptPath)
}

# ---------------------------------------------------------------- the secret
# The Canvas token is unscoped: whoever holds it holds the whole account. It
# never goes in a file on either platform.
#
# Windows: HKCU\Environment via the User scope, which is also what makes it
# visible to later shells as $env:CANVAS_TOKEN.
# macOS:   the login Keychain. [Environment]::SetEnvironmentVariable with the
#          'User' scope is a SILENT NO-OP on Unix - it neither stores nor
#          throws - so using it there would look like success and lose the
#          token every time.

$script:KEYCHAIN_SERVICE = 'canvas-workspace-token'

function Get-CanvasToken {
  <#
    -Fresh skips the process environment and re-reads the durable store.

    Why that matters: when you regenerate a Canvas token, every process that
    was already running keeps the old one in its environment - a long-lived
    shell, an AI agent driving these scripts, a scheduled job started earlier.
    The stored value is correct and the process copy is revoked, so Canvas
    answers 401 and the obvious reading ("my new token is broken") is exactly
    wrong. Callers retry with -Fresh on a 401 before blaming anything else.
  #>
  param([switch]$Fresh)
  if ($env:CANVAS_TOKEN -and -not $Fresh) { return $env:CANVAS_TOKEN }
  if ((Get-CanvasPlatform) -eq 'windows') {
    return [Environment]::GetEnvironmentVariable('CANVAS_TOKEN', 'User')
  }
  if (-not (Test-CanvasReal)) { return $null }
  if ((Get-CanvasPlatform) -eq 'linux') {
    # Linux has no single built-in store. libsecret is the closest common one;
    # if it is absent there is nothing to read and the caller prompts.
    if (-not (Get-Command secret-tool -EA SilentlyContinue)) { return $null }
    $v = & secret-tool lookup service $script:KEYCHAIN_SERVICE 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($v)) { return $null }
    return ([string]$v).Trim()
  }
  if (-not (Get-Command security -EA SilentlyContinue)) { return $null }
  # 2>$null: "item not found" is an ordinary answer here, not a failure.
  $v = & security find-generic-password -a $env:USER -s $script:KEYCHAIN_SERVICE -w 2>$null
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($v)) { return $null }
  return ([string]$v).Trim()
}

function Invoke-CanvasApi {
  <#
    One place that talks to Canvas, so the stale-token retry exists once rather
    than in every caller. On a 401 it re-reads the durable store and retries a
    single time; if the fresh value is identical, the token really is bad and
    the original error stands.
  #>
  param([Parameter(Mandatory)][string]$Uri, [hashtable]$Extra = @{})
  $tok = if ($env:CANVAS_TOKEN) { $env:CANVAS_TOKEN } else { Get-CanvasToken }
  try {
    return Invoke-RestMethod $Uri -Headers (@{ Authorization = "Bearer $tok" } + $Extra)
  } catch {
    $code = $null
    if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
    if ($code -ne 401) { throw }
    $fresh = Get-CanvasToken -Fresh
    if (-not $fresh -or $fresh -eq $tok) { throw }
    # The stored token differs from the one this process started with, so it was
    # regenerated after this process began. Adopt it and carry on.
    Write-Warning 'The Canvas token changed since this process started - picked up the new one.'
    $env:CANVAS_TOKEN = $fresh
    return Invoke-RestMethod $Uri -Headers (@{ Authorization = "Bearer $fresh" } + $Extra)
  }
}

function Get-CanvasTokenInstructions($hintBase) {
  # Returned as text so the caller decides how to present it, and so a test can
  # assert on it without a terminal.
  if ((Get-CanvasPlatform) -eq 'windows') {
    return @"
  1. Open  $hintBase/profile/settings  and click  + New Access Token
  2. Copy it. Then in >>> Windows PowerShell <<< - not Command Prompt - run:

       [Environment]::SetEnvironmentVariable('CANVAS_TOKEN', (Get-Clipboard), 'User'); Set-Clipboard -Value 'cleared'

     It takes the token from your clipboard, stores it for your Windows
     account, and wipes the clipboard. Nothing is printed, and unlike setx the
     token never appears on a command line where auditing would record it.
"@
  }
  if ((Get-CanvasPlatform) -eq 'linux') {
    return @"
  1. Open  $hintBase/profile/settings  and click  + New Access Token
  2. Copy it. Then in a terminal, if you have libsecret (most desktop distros):

       secret-tool store --label='Canvas' service $($script:KEYCHAIN_SERVICE)

     It prompts for the token and reads it silently. Paste it, press Return.

     No secret-tool? Linux has no single built-in store, so the honest fallback
     is your shell profile - but understand the trade: this DOES put an
     unscoped, full-account token in a plaintext file.

       printf 'export CANVAS_TOKEN=%s\n' '<paste>' >> ~/.bashrc && chmod 600 ~/.bashrc

     Prefer installing libsecret (apt install libsecret-tools) over that.
"@
  }
  return @"
  1. Open  $hintBase/profile/settings  and click  + New Access Token
  2. Copy it. Then in Terminal run exactly this - note the bare -w at the end:

       security add-generic-password -a "`$USER" -s $($script:KEYCHAIN_SERVICE) -U -w

     It will prompt you for the token and read it silently. Paste it and press
     Return. The bare -w matters: writing -w "<your token>" would put the token
     on the command line, where ps and your shell history would both keep it.
  3. Then clear your clipboard:  pbcopy < /dev/null
"@
}

function Get-CanvasBaseFixInstructions {
  # How to correct a wrong Canvas host. Lives here, not in the caller, so that
  # "only platform.ps1 knows the difference" stays literally true - a Windows
  # command embedded in setup.ps1's error text would be wrong half the time.
  if ((Get-CanvasPlatform) -eq 'windows') {
    return "       [Environment]::SetEnvironmentVariable('CANVAS_BASE','https://yourschool.instructure.com','User')"
  }
  return "       mkdir -p ~/.config/canvas-workspace && echo 'https://yourschool.instructure.com' > ~/.config/canvas-workspace/base"
}

function Get-CanvasShellNote {
  if ((Get-CanvasPlatform) -eq 'windows') {
    return 'Use Windows PowerShell, not Command Prompt - the clipboard cmdlet does not exist there and fails silently.'
  }
  return 'Run these in Terminal. The bare -w is deliberate: it prompts for the token instead of putting it on the command line.'
}

function Test-CanvasTokenStorable {
  # Can this machine store the token the way this tool expects?
  if ((Get-CanvasPlatform) -eq 'windows') { return $true }
  if (-not (Test-CanvasReal)) { return $true }
  return [bool](Get-Command security -EA SilentlyContinue)
}

# ------------------------------------------------------------- non-secrets
# CANVAS_BASE is a school hostname, not a credential, so a config file is fine
# where a persistent env scope does not exist.

function Get-CanvasConfigDir {
  if ((Get-CanvasPlatform) -eq 'windows') {
    return Join-Path $env:APPDATA 'canvas-workspace'
  }
  return Join-Path (Join-Path (Get-CanvasHome) '.config') 'canvas-workspace'
}

function Set-CanvasBase($value) {
  $v = ([string]$value).TrimEnd('/')
  $env:CANVAS_BASE = $v
  if ((Get-CanvasPlatform) -eq 'windows') {
    [Environment]::SetEnvironmentVariable('CANVAS_BASE', $v, 'User')
    return
  }
  $dir = Get-CanvasConfigDir
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $dir 'base'), $v, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-CanvasBase {
  if ($env:CANVAS_BASE) { return $env:CANVAS_BASE.TrimEnd('/') }
  if ((Get-CanvasPlatform) -eq 'windows') {
    return [Environment]::GetEnvironmentVariable('CANVAS_BASE', 'User')
  }
  $f = Join-Path (Get-CanvasConfigDir) 'base'
  if (Test-Path $f) { return (Get-Content $f -Raw -Encoding UTF8).Trim() }
  return $null
}

# ---------------------------------------------------------------- clipboard
function Read-CanvasClipboard {
  if ((Get-CanvasPlatform) -eq 'windows') {
    if (Get-Command Get-Clipboard -EA SilentlyContinue) { return (Get-Clipboard) }
    return $null
  }
  if (-not (Test-CanvasReal)) { return $null }
  if (-not (Get-Command pbpaste -EA SilentlyContinue)) { return $null }
  return (& pbpaste)
}

# ------------------------------------------------------------- cloud storage
function Find-CanvasCloudDrive {
  if ((Get-CanvasPlatform) -eq 'windows') {
    foreach ($d in (Get-PSDrive -PSProvider FileSystem -EA SilentlyContinue)) {
      $p = Join-Path $d.Root 'My Drive'
      if (Test-Path $p) { return $p }
    }
    return $null
  }
  if (-not (Test-CanvasReal)) { return $null }
  # Modern Google Drive for Desktop mounts per-account under CloudStorage.
  $cs = Join-Path (Join-Path (Get-CanvasHome) 'Library') 'CloudStorage'
  if (Test-Path $cs) {
    $hit = @(Get-ChildItem $cs -Directory -EA SilentlyContinue |
             Where-Object { $_.Name -like 'GoogleDrive-*' } |
             ForEach-Object { Join-Path $_.FullName 'My Drive' } |
             Where-Object { Test-Path $_ })
    if ($hit.Count) { return $hit[0] }
  }
  foreach ($p in @((Join-Path '/Volumes/GoogleDrive' 'My Drive'),
                   (Join-Path (Get-CanvasHome) 'Google Drive/My Drive'))) {
    if (Test-Path $p) { return $p }
  }
  return $null
}

# ---------------------------------------------------------------- scheduling
$script:LAUNCHD_PREFIX = 'com.canvas-workspace'

function Get-CanvasLaunchAgentDir {
  Join-Path (Join-Path (Get-CanvasHome) 'Library') 'LaunchAgents'
}

function New-CanvasLaunchPlist {
  <#
    Returns the plist XML as a string. Kept separate from writing and loading so
    the generated artefact can be validated without touching launchd.
    IntervalSeconds and AtHour/AtMinute are mutually exclusive: launchd takes
    StartInterval for "every N seconds" and StartCalendarInterval for "daily at".
  #>
  param(
    [Parameter(Mandatory)][string]$Label,
    [Parameter(Mandatory)][string]$ShellExe,
    [Parameter(Mandatory)][string[]]$ScriptArgs,
    [int]$IntervalSeconds,
    [int]$AtHour = -1,
    [int]$AtMinute = -1,
    [string]$WorkingDirectory
  )
  $esc = { param($s) ([string]$s).Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;') }
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
  [void]$sb.AppendLine('<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">')
  [void]$sb.AppendLine('<plist version="1.0">')
  [void]$sb.AppendLine('<dict>')
  [void]$sb.AppendLine("  <key>Label</key><string>$(& $esc $Label)</string>")
  [void]$sb.AppendLine('  <key>ProgramArguments</key>')
  [void]$sb.AppendLine('  <array>')
  [void]$sb.AppendLine("    <string>$(& $esc $ShellExe)</string>")
  foreach ($a in $ScriptArgs) { [void]$sb.AppendLine("    <string>$(& $esc $a)</string>") }
  [void]$sb.AppendLine('  </array>')
  if ($AtHour -ge 0 -and $AtMinute -ge 0) {
    [void]$sb.AppendLine('  <key>StartCalendarInterval</key>')
    [void]$sb.AppendLine('  <dict>')
    [void]$sb.AppendLine("    <key>Hour</key><integer>$AtHour</integer>")
    [void]$sb.AppendLine("    <key>Minute</key><integer>$AtMinute</integer>")
    [void]$sb.AppendLine('  </dict>')
  } else {
    [void]$sb.AppendLine("  <key>StartInterval</key><integer>$IntervalSeconds</integer>")
  }
  if ($WorkingDirectory) {
    [void]$sb.AppendLine("  <key>WorkingDirectory</key><string>$(& $esc $WorkingDirectory)</string>")
  }
  # RunAtLoad false: installing the schedule should not also fire a run. setup
  # takes its own first snapshot explicitly, and a duplicate would race it.
  [void]$sb.AppendLine('  <key>RunAtLoad</key><false/>')
  # launchd skips a StartInterval that comes due while asleep. This makes it run
  # once on wake instead, which is the whole point of an hourly watcher.
  [void]$sb.AppendLine('  <key>ProcessType</key><string>Background</string>')
  [void]$sb.AppendLine('</dict>')
  [void]$sb.AppendLine('</plist>')
  return $sb.ToString()
}

function Register-CanvasSchedule {
  <#
    Registers a recurring run of $ScriptPath. Returns a hashtable:
      Ok       - whether it was actually registered
      Name     - task name or launchd label
      Detail   - one line for the user
    Never throws for "this platform cannot do it"; the caller decides how loud
    that should be.
  #>
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$ScriptPath,
    [string[]]$ExtraArgs = @(),
    [int]$EveryHours,
    [string]$DailyAt,
    [string]$Description = 'Read-only Canvas mirror. Never submits, grades, or messages.'
  )
  $plat = Get-CanvasPlatform
  $exe  = Get-CanvasShellExe
  $sargs = @(Get-CanvasShellArgs $ScriptPath) + $ExtraArgs

  # This function promises never to throw, and the caller relies on that: by the
  # time it runs, the workspace, every class folder and the whole Canvas mirror
  # already exist. An escaping error - Access Denied on a managed school laptop,
  # Task Scheduler disabled, a same-named task owned by another account, or an
  # unwritable ~/Library/LaunchAgents - would abort setup before the standup is
  # written and before the closing "here is what you got" is printed, so a
  # student whose install succeeded in every way that matters sees only red text.
  # One try/catch around the whole body keeps that promise on both platforms.
  try {

  if ($plat -eq 'windows') {
    if (-not (Get-Command Register-ScheduledTask -EA SilentlyContinue)) {
      return @{ Ok = $false; Name = $Name; Detail = 'the ScheduledTasks module is unavailable' }
    }
    $argLine = ($sargs | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) -join ' '
    $action  = New-ScheduledTaskAction -Execute $exe -Argument $argLine
    if ($DailyAt) {
      $at = [datetime]::ParseExact($DailyAt, 'H:mm', [Globalization.CultureInfo]::InvariantCulture)
      $trigger = New-ScheduledTaskTrigger -Daily -At $at
    } else {
      $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) `
                   -RepetitionInterval (New-TimeSpan -Hours $EveryHours) `
                   -RepetitionDuration (New-TimeSpan -Days 3650)
    }
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries `
                  -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 15)
    Register-ScheduledTask -TaskName $Name -Action $action -Trigger $trigger -Settings $settings `
      -Description $Description -Force | Out-Null
    return @{ Ok = $true; Name = $Name; Detail = "Scheduled '$Name'." }
  }

  if ($plat -ne 'macos') {
    return @{ Ok = $false; Name = $Name; Detail = "scheduling is not implemented for $plat - run the script yourself, or add a cron entry" }
  }

  $label = "$($script:LAUNCHD_PREFIX).$($Name -replace '[^A-Za-z0-9]+', '-')".ToLower().Trim('-')
  $hour = -1; $minute = -1
  if ($DailyAt) { $parts = $DailyAt -split ':'; $hour = [int]$parts[0]; $minute = [int]$parts[1] }
  $xml = New-CanvasLaunchPlist -Label $label -ShellExe $exe -ScriptArgs $sargs `
           -IntervalSeconds ([Math]::Max(60, $EveryHours * 3600)) -AtHour $hour -AtMinute $minute `
           -WorkingDirectory (Split-Path $ScriptPath -Parent)

  if (-not (Test-CanvasReal)) {
    return @{ Ok = $false; Name = $label; Detail = 'forced macos branch on a non-mac host: plist generated, not installed'; Plist = $xml }
  }

  $dir = Get-CanvasLaunchAgentDir
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $plistPath = Join-Path $dir "$label.plist"
  [System.IO.File]::WriteAllText($plistPath, $xml, (New-Object System.Text.UTF8Encoding($false)))

  $uid = (& id -u).Trim()
  # bootout first so a rerun replaces rather than collides. Failure is normal
  # the first time - the job is not loaded yet - so its output is discarded.
  & launchctl bootout "gui/$uid/$label" 2>$null | Out-Null
  & launchctl bootstrap "gui/$uid" $plistPath 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) {
    # Older macOS, or a sandboxed context: load -w is the pre-bootstrap verb.
    & launchctl load -w $plistPath 2>$null | Out-Null
  }
  $loaded = (& launchctl list 2>$null | Select-String -SimpleMatch $label -Quiet)
  if ($loaded) {
    return @{ Ok = $true; Name = $label; Detail = "Loaded launchd agent '$label'. Check: launchctl list | grep $label"; Plist = $xml; Path = $plistPath }
  }
  return @{ Ok = $false; Name = $label; Detail = "wrote $plistPath but launchctl did not load it - run: launchctl bootstrap gui/$uid `"$plistPath`""; Plist = $xml; Path = $plistPath }

  } catch {
    # Report, never throw. The caller turns this into a warning and carries on,
    # so an unschedulable machine still finishes with a complete workspace.
    return @{ Ok = $false; Name = $Name; Detail = "could not register the recurring job: $($_.Exception.Message)" }
  }
}

function Get-CanvasScheduleState {
  <#
    Reports the health of the registered job. Returns:
      Found    - is there one at all
      Name     - what it is called
      Healthy  - last run succeeded (or, on launchd, it is loaded and last exit 0)
      Detail   - one line for a human
  #>
  param([string]$Match = 'Canvas')
  $plat = Get-CanvasPlatform
  if ($plat -eq 'windows') {
    if (-not (Get-Command Get-ScheduledTask -EA SilentlyContinue)) {
      return @{ Found = $false; Name = $null; Healthy = $false; Detail = 'ScheduledTasks module unavailable' }
    }
    $t = Get-ScheduledTask | Where-Object { $_.TaskName -like "*$Match*" } | Select-Object -First 1
    if (-not $t) { return @{ Found = $false; Name = $null; Healthy = $false; Detail = 'no scheduled task found' } }
    $i = Get-ScheduledTaskInfo -TaskName $t.TaskName
    $rc = [uint32]$i.LastTaskResult
    $why = switch ($rc) {
      0          { $null }
      267009     { 'it is running right now - not a failure' }
      267011     { 'it has not run yet' }
      4294770688 { 'the workspace drive was offline when it fired' }
      default    { 'look up the hex code, or run canvas-watch.ps1 by hand' }
    }
    if ($rc -eq 0) { return @{ Found = $true; Name = $t.TaskName; Healthy = $true; Detail = "next run $($i.NextRunTime)" } }
    return @{ Found = $true; Name = $t.TaskName; Healthy = $false; Detail = ("last exited 0x{0:X8} - {1}" -f $rc, $why) }
  }
  if ($plat -ne 'macos' -or -not (Test-CanvasReal)) {
    return @{ Found = $false; Name = $null; Healthy = $false; Detail = "cannot inspect a $plat schedule from here" }
  }
  $line = @(& launchctl list 2>$null | Select-String -SimpleMatch $script:LAUNCHD_PREFIX)
  if (-not $line.Count) { return @{ Found = $false; Name = $null; Healthy = $false; Detail = 'no launchd agent loaded' } }
  # launchctl list prints: <PID or -> <last exit status> <label>
  $cols = ($line[0].ToString().Trim() -split '\s+')
  $label = $cols[-1]
  $status = 0
  [void][int]::TryParse($cols[1], [ref]$status)
  if ($status -eq 0) { return @{ Found = $true; Name = $label; Healthy = $true; Detail = 'loaded, last run exited 0' } }
  return @{ Found = $true; Name = $label; Healthy = $false; Detail = "loaded, but last run exited $status - run canvas-watch.ps1 by hand to see why" }
}
