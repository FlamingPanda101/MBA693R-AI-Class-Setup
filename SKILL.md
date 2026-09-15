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
   `C:\Users\<name>\School`. If it will sit in OneDrive or Google Drive, one sync
   client only - two on the same folder corrupt the git repos the tool creates.

2. **Check the token, but do not touch it.** Run
   `if ($env:CANVAS_TOKEN) { 'set' } else { 'missing' }`.
   If missing, have THEM do this, in their own terminal:
   - Open `https://<school>.instructure.com/profile/settings` -> **+ New Access Token**.
     Purpose `canvas-watcher`, expiry end of semester.
   - Copy it, then run `setx CANVAS_TOKEN (Get-Clipboard)` - reads it straight
     from the clipboard so it never appears on screen or in shell history.
   - Open a NEW terminal. `setx` does not affect the current one.
   Wait until they confirm all three.

3. **Not BYU?** `setx CANVAS_BASE https://<school>.instructure.com`, then a new terminal.

4. **Run setup** from the directory containing this file:

       powershell -ExecutionPolicy Bypass -File ".\setup.ps1" -Root "<workspace path>"

   It greets them by name (proves the token works), writes `courses.json`,
   makes the folders, takes the first snapshot, and schedules the watcher every
   4 hours. `-NoSchedule` skips the schedule; `-Every 6` changes the interval.

5. **Show them `DUE.md`.** Read out the "Next 14 days" table. Point out that
   rows tagged `(paper)` are handed in physically and will never show as
   submitted, and that 0-point rows are usually readings or attendance markers.

6. **Tell them how to steer it:**
   - Skip a course: set `"enabled": false` in `courses.json`, rerun `setup.ps1`.
   - New semester: rerun `setup.ps1`; new courses merge in, nothing is lost.
   - Change a shared rule: edit `templates\shared-rules.md`, rerun `scaffold-class.ps1`.
   - Token expiry nag: put the date in `courses.json` as `"tokenExpires": "2026-12-13"`.
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
