#!/bin/sh
# setup.sh - the macOS (and Linux) way in. Run ./setup.sh and answer the questions.
#
# This exists because the one thing that cannot self-detect is the shell used to
# launch a self-detecting script. setup.ps1 knows which OS it is on; getting it
# running does not. So: this file on macOS, setup.cmd on Windows, and nobody has
# to remember that -ExecutionPolicy is Windows-only.
#
# Any arguments are passed straight through. With none, it runs the interview.
set -eu

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

find_pwsh() {
  if command -v pwsh >/dev/null 2>&1; then command -v pwsh; return 0; fi
  for p in /opt/homebrew/bin/pwsh /usr/local/bin/pwsh /usr/bin/pwsh; do
    [ -x "$p" ] && { printf '%s\n' "$p"; return 0; }
  done
  return 1
}

if ! PWSH=$(find_pwsh); then
  cat >&2 <<'MSG'

PowerShell 7 is not installed, and these scripts are written in PowerShell.

  macOS:  brew install --cask powershell
          (no Homebrew? get it from https://brew.sh, or download PowerShell
           from https://github.com/PowerShell/PowerShell/releases)

  Linux:  see https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux

Then run ./setup.sh again. Nothing has been changed.

MSG
  exit 1
fi

# No -ExecutionPolicy: it does not exist outside Windows and pwsh errors on it.
if [ "$#" -eq 0 ]; then
  exec "$PWSH" -NoProfile -File "$DIR/setup.ps1" -Interview
fi
exec "$PWSH" -NoProfile -File "$DIR/setup.ps1" "$@"
