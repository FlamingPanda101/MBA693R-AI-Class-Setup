@echo off
rem setup.cmd - the Windows way in. Double-click it, or run setup.cmd.
rem
rem This exists because the one thing that cannot self-detect is the shell used
rem to launch a self-detecting script. setup.ps1 knows which OS it is on;
rem getting it running does not. So: this file on Windows, setup.sh on macOS,
rem and nobody has to remember -ExecutionPolicy or which PowerShell to open.
rem
rem Any arguments pass straight through. With none, it runs the interview.
setlocal
set "HERE=%~dp0"

rem Windows PowerShell 5.1 is present on every Windows 10/11 machine, so it is
rem the safe default. -ExecutionPolicy Bypass applies to this process only; it
rem changes no machine setting, and without it an unsigned script on a synced
rem drive is refused.
if "%~1"=="" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HERE%setup.ps1" -Interview
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HERE%setup.ps1" %*
)
set "RC=%ERRORLEVEL%"

rem Double-clicked windows close the instant the script ends, taking the output
rem with them. Pause only when there were no arguments, which is that case; a
rem terminal run with flags is left alone.
if "%~1"=="" (
  echo.
  pause
)
exit /b %RC%
