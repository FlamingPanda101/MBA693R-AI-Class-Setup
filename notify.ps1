<#
notify.ps1 - send the daily brief to your own phone.

  .\notify.ps1 -Setup                 walk through connecting a provider
  .\notify.ps1                        build today's brief and send it
  .\notify.ps1 -DryRun                print exactly what would be sent, send nothing
  .\notify.ps1 -Text "..."            send one arbitrary line instead of the brief

Sends ONLY to the single number recorded during -Setup, and only to you. There
is no recipient argument on purpose: a notifier that can be pointed anywhere is
one bad variable away from mailing your coursework to a stranger.

The provider's API key is stored by the operating system - the Windows user
environment or the macOS login Keychain - never in a file here, and never
printed. The URL it is embedded in is never logged either, which is why errors
below report a status code rather than echoing the request.
#>
param(
  [switch]$Setup,
  [switch]$DryRun,
  [string]$Text,
  [switch]$Quiet,
  # 24-hour HH:mm. Registers a daily send - a Windows task or a launchd agent,
  # whichever this machine uses.
  [string]$ScheduleAt,
  [switch]$Unschedule
)
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
. (Join-Path $PSScriptRoot 'platform.ps1')

$cfgPath = Join-Path (Get-CanvasConfigDir) 'notify.json'

function Read-NotifyConfig {
  if (-not (Test-Path $cfgPath)) { return $null }
  try { return (Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Write-NotifyConfig($provider, $phone) {
  $dir = Get-CanvasConfigDir
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  # The phone number is personal but it is not a credential, so a config file is
  # the right home for it. The API key is NOT written here - see the header.
  $obj = [pscustomobject]@{ provider = $provider; phone = $phone }
  [System.IO.File]::WriteAllText($cfgPath, (ConvertTo-Json -InputObject $obj -Depth 3), (New-Object System.Text.UTF8Encoding($false)))
}

# ---------------------------------------------------------------- setup
if ($Setup) {
  Write-Host ""
  Write-Host "Daily brief to your phone - setup" -F Cyan
  Write-Host ""
  Write-Host "This uses CallMeBot, a free relay that forwards a message to your own" -F DarkGray
  Write-Host "WhatsApp. Two things to know before you start:" -F DarkGray
  Write-Host "  - Your message text passes through their server. Course names and" -F DarkGray
  Write-Host "    assignment titles are not secret, but they are not private either." -F DarkGray
  Write-Host "  - It sends to YOU only. WhatsApp groups need a verified business" -F DarkGray
  Write-Host "    account, which this is not. Telegram is the easy route for groups." -F DarkGray
  Write-Host ""
  Write-Host "Step 1. On your phone, add +34 644 51 95 23 to your contacts as 'CallMeBot'." -F White
  Write-Host "Step 2. Send that contact this exact WhatsApp message:" -F White
  Write-Host "            I allow callmebot to send me messages" -F Yellow
  Write-Host "Step 3. Wait for its reply. It contains your API key." -F White
  Write-Host ""
  Write-Host "Step 4. Store the key so this script can read it:" -F White
  Write-Host (Get-CanvasNotifyKeyInstructions) -F Gray
  Write-Host ""
  $phone = Read-Host "Step 5. Your WhatsApp number in full international form, e.g. +18015551234"
  if ($null -eq $phone) { Write-Error "-Setup needs a terminal to read your answer." }
  $phone = ([string]$phone).Trim() -replace '[\s\-\(\)]', ''
  if ($phone -notmatch '^\+[1-9]\d{6,14}$') {
    Write-Error "That does not look like an international number. It must start with + and the country code, e.g. +18015551234 - got '$phone'."
  }
  Write-NotifyConfig 'callmebot' $phone
  Write-Host ""
  Write-Host "Saved. Recipient locked to $phone." -F Green
  if (-not (Get-CanvasNotifyKey)) {
    Write-Warning "No API key stored yet. Do step 4, then run: .\notify.ps1 -DryRun"
  } else {
    Write-Host "Now test it without sending:  .\notify.ps1 -DryRun" -F DarkGray
  }
  exit 0
}

# ---------------------------------------------------------------- schedule
if ($ScheduleAt) {
  # Validated before anything is registered, so a typo cannot leave a half-made
  # task behind. Same 'H:mm' shape setup.ps1 accepts, so 7:30 and 07:30 both work.
  if ($ScheduleAt -notmatch '^([01]?\d|2[0-3]):[0-5]\d$') {
    Write-Error "-ScheduleAt must be a 24-hour time like 07:30 or 7:30 - got '$ScheduleAt'."
  }
  if (-not (Read-NotifyConfig)) { Write-Error "Set up the provider first: .\notify.ps1 -Setup" }
  $r = Register-CanvasSchedule -Name "Canvas Daily Brief - $(Split-Path $Root -Leaf)" `
         -ScriptPath (Join-Path $Root 'notify.ps1') -ExtraArgs @('-Quiet') `
         -DailyAt $ScheduleAt -EveryHours 24 `
         -Description 'Sends the daily Canvas brief to the owner. Read-only against Canvas.'
  if ($r.Ok) { Write-Host "$($r.Detail) Daily at $ScheduleAt." -F Green }
  else { Write-Warning "Could not schedule it: $($r.Detail). You can still run .\notify.ps1 by hand." }
  exit 0
}
if ($Unschedule) {
  $name = "Canvas Daily Brief - $(Split-Path $Root -Leaf)"
  if ((Get-CanvasPlatform) -eq 'windows' -and (Get-Command Unregister-ScheduledTask -EA SilentlyContinue)) {
    if (Get-ScheduledTask -TaskName $name -EA SilentlyContinue) {
      Unregister-ScheduledTask -TaskName $name -Confirm:$false
      Write-Host "Removed '$name'. Nothing else changed." -F Green
    } else { Write-Host "No such task - nothing to remove." -F DarkGray }
  } else {
    $label = "com.canvas-workspace.$($name -replace '[^A-Za-z0-9]+','-')".ToLower().Trim('-')
    Write-Host "To stop it on this machine:" -F Cyan
    Write-Host "  launchctl bootout gui/`$(id -u)/$label" -F Gray
    Write-Host "  rm ~/Library/LaunchAgents/$label.plist" -F Gray
  }
  exit 0
}

# ---------------------------------------------------------------- send
$cfg = Read-NotifyConfig
if (-not $cfg) { Write-Error "Not set up yet. Run: .\notify.ps1 -Setup" }
if (-not $cfg.phone) { Write-Error "No recipient recorded. Rerun: .\notify.ps1 -Setup" }

# Build the message. Regenerating rather than reading a stale BRIEF.txt means a
# scheduled send can never quietly deliver yesterday's news.
if ($Text) {
  $body = $Text
} else {
  & (Join-Path $Root 'standup.ps1') -Brief -Quiet | Out-Null
  $briefPath = Join-Path $Root 'BRIEF.txt'
  if (-not (Test-Path $briefPath)) { Write-Error "standup.ps1 -Brief did not produce BRIEF.txt." }
  $body = (Get-Content $briefPath -Raw -Encoding UTF8).TrimEnd()
}
if ([string]::IsNullOrWhiteSpace($body)) { Write-Error "Nothing to send - the brief came back empty." }

# CallMeBot passes the text in a URL query string, so a long brief becomes a
# very long URL and some hops truncate it silently. Cut with a visible marker
# rather than letting the tail disappear without saying so.
$LIMIT = 1200
if ($body.Length -gt $LIMIT) {
  $body = $body.Substring(0, $LIMIT - 40).TrimEnd() + "`n... (trimmed - see STANDUP.md)"
}

if ($DryRun) {
  Write-Host ""
  Write-Host "WOULD SEND to $($cfg.phone) via $($cfg.provider):" -F Cyan
  Write-Host ""
  Write-Output $body
  Write-Host ""
  Write-Host ("({0} characters; API key {1})" -f $body.Length, $(if (Get-CanvasNotifyKey) { 'is stored' } else { 'is MISSING - run -Setup step 4' })) -F DarkGray
  exit 0
}

$key = Get-CanvasNotifyKey
if (-not $key) {
  Write-Error ("No API key stored. Run .\notify.ps1 -Setup and complete step 4.`n" + (Get-CanvasNotifyKeyInstructions))
}

switch ($cfg.provider) {
  'callmebot' {
    $uri = 'https://api.callmebot.com/whatsapp.php?phone={0}&text={1}&apikey={2}' -f `
             [uri]::EscapeDataString($cfg.phone), [uri]::EscapeDataString($body), [uri]::EscapeDataString($key)
    try {
      $r = Invoke-WebRequest -Uri $uri -Method Get -UseBasicParsing -TimeoutSec 60
      if (-not $Quiet) { Write-Host "Sent to $($cfg.phone) ($($body.Length) chars, HTTP $($r.StatusCode))." -F Green }
    } catch {
      # Deliberately does NOT include $uri or $_.Exception.Message verbatim:
      # both can carry the full request, and the API key lives in it.
      $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
      Write-Error ("CallMeBot rejected the request (HTTP $code). Usual causes: the API key is wrong or was revoked, " +
                   "the number does not match the one you authorised, or you have not messaged the bot in a while. " +
                   "Rerun .\notify.ps1 -Setup to re-authorise. The request URL is not shown because your API key is in it.")
    }
  }
  default { Write-Error "Unknown provider '$($cfg.provider)' in $cfgPath. Rerun -Setup." }
}
