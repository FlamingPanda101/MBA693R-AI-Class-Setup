---
name: mba-canvas-workspace
description: Bootstrap a folder-per-class AI workspace mirrored from Canvas - one folder per course with rules for Claude Code, Codex, and Antigravity, a scheduled read-only Canvas watcher, and a cross-class DUE.md of everything outstanding. Use when a student asks to track Canvas classes, set up class folders for AI agents, or see what is due across all courses.
---

# Canvas workspace

You are helping a student set up a folder-per-class workspace that mirrors
Canvas. The scripts next to this file do the work. Your job is to handle the
two things a script cannot do, run it, and explain the result.

## Never
- Never ask for, read, echo, hash, or store the Canvas token. It is their
  entire account. If they paste it into the chat, tell them to regenerate it.
- Never submit, grade, or message anything in Canvas. Everything here is read-only.
- Never run any command with a permission-bypass flag.

## Steps

1. **Where should the workspace live?** Ask. A sensible default is
   `C:\Users\<name>\School`. It must be a *different* folder from this one - if
   the tool folder were the workspace, this folder's `CLAUDE.md` / `AGENTS.md` /
   `GEMINI.md` would sit above every class and each class session would load the
   installer instructions instead of that class's rules. `setup.ps1` refuses it.
   If the workspace sits in OneDrive or Google Drive, use one sync client only -
   two on the same folder corrupt the per-class git repos.

2. **Check the token, but do not touch it.** Run
   `if ([Environment]::GetEnvironmentVariable('CANVAS_TOKEN','User')) { 'set' } else { 'missing' }`.
   Check the **User scope**, not `$env:CANVAS_TOKEN` - `setx` writes the registry,
   and your own process cannot see it until you restart, so `$env:` will say
   "missing" long after they have set it correctly.
   If missing, have THEM do this, in their own terminal:
   - Open `https://<school>.instructure.com/profile/settings` -> **+ New Access Token**.
     Purpose `canvas-watcher`, expiry end of semester.
   - Copy it, then run, exactly:
     `setx CANVAS_TOKEN (Get-Clipboard); Set-Clipboard -Value 'cleared'`
     The first half reads it straight from the clipboard so it never appears on
     screen or in shell history; the second wipes the clipboard so a stray
     Ctrl+V cannot paste their token into a chat window.
   - If they use Win+V clipboard history: Settings > System > Clipboard > Clear.
   Wait until they confirm.

3. **Not BYU?** `setx CANVAS_BASE https://<school>.instructure.com`.

4. **Run setup** from the directory containing this file. The scripts read the
   User scope themselves, so no terminal or agent restart is needed:

       powershell -ExecutionPolicy Bypass -File ".\setup.ps1" -Root "<workspace path>"

   It greets them by name (proves the token works), writes `courses.json`,
   makes the folders, `git init`s each one (Codex needs that), takes the first
   snapshot, and schedules the watcher every 4 hours. `-NoSchedule` skips the
   schedule; `-Every 6` changes the interval.

5. **Show them `DUE.md`.** Read out the "Next 14 days" table. Point out that
   rows tagged `(paper)` are handed in physically and will never show as
   submitted, and that 0-point rows are usually readings or attendance markers.

6. **Tell them how to steer it.** Every path below is in the **workspace**, not
   in this tool folder - the workspace copies are the ones that run. And every
   rerun needs `-ExecutionPolicy Bypass`, or Windows' default policy blocks it:
   - Skip a course: `"enabled": false` in `<workspace>\courses.json`, then
     `powershell -ExecutionPolicy Bypass -File <workspace>\setup.ps1 -Root <workspace>`
   - New semester: same command; new courses merge in, edits are kept.
   - Change a shared rule: edit `<workspace>\templates\shared-rules.md`, then
     `powershell -ExecutionPolicy Bypass -File <workspace>\scaffold-class.ps1`
   - Token expiry nag: `"tokenExpires": "2026-12-13"` in `courses.json`.
   - Health check: `Get-ScheduledTaskInfo -TaskName 'Canvas Watch - <folder>'`
     (`LastTaskResult 0` is healthy).

## What it makes
```
<workspace>\
  DUE.md                  everything outstanding, all classes, by date
  CHANGES.md              what changed since the last run
  courses.json            the course -> folder map (edit to rename or skip)
  templates\shared-rules.md
  <Course A>\
    AGENTS.md CLAUDE.md GEMINI.md STATUS.md
    canvas\ sources\ work\ submissions\
  <Course B>\ ...
```

## Windows PowerShell 5.1 traps the scripts already avoid
Worth knowing if you edit them:
- Variable names are case-insensitive: `$Due` and `$due` are the same variable.
- `@(Some-Function ...)` nests a returned array as one element instead of enumerating it.
- `h` is an alias for `Get-History`; do not name a function `H`.
- A UTF-8 script without a BOM is read as ANSI: keep `.ps1` files ASCII.
- OneDrive and Google Drive hold file handles briefly after syncing; writes retry.
- Canvas due dates are UTC; `05:59:59Z` is 11:59 PM the previous day in Mountain Time.
