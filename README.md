# mba-canvas-workspace

One folder per class, mirrored from Canvas, ready for Claude Code, Codex, or
Antigravity to work in. A scheduled job refreshes every course and writes a
single `DUE.md` of everything outstanding across all your classes.

Read-only. It never submits, grades, or messages. Your Canvas token stays on
your machine and is never written to a file.

## Install (Windows, PowerShell 5.1 or later)

**With Claude Code** - paste the repo link and say "set up my Canvas workspace".
The skill walks you through it.

**With Codex or Antigravity** - clone, then open the folder in the agent and
say the same thing. `AGENTS.md` / `GEMINI.md` point it at the procedure.

**By hand** - three steps:

1. Canvas -> Account -> Settings -> **+ New Access Token**. Copy it.
2. Run exactly this:

   ```powershell
   setx CANVAS_TOKEN (Get-Clipboard); Set-Clipboard -Value 'cleared'
   ```

   The first half reads the token from your clipboard so it never appears on
   screen or in your shell history. The second wipes the clipboard, so a stray
   Ctrl+V cannot paste your token into a chat window. Using Win+V clipboard
   history? Clear it too: Settings > System > Clipboard.
   (Not BYU? Also `setx CANVAS_BASE https://yourschool.instructure.com`.)
3. ```powershell
   powershell -ExecutionPolicy Bypass -File .\setup.ps1 -Root C:\Users\you\School
   ```

`-Root` must be a different folder from this repo. Setup greets you by name,
discovers your courses, builds the folders, `git init`s each one, takes the
first snapshot, and schedules a refresh every 4 hours.

No new terminal needed: the scripts read the value `setx` wrote directly, so
they work immediately - including when an AI agent runs them for you.

## What you get

```
School\
  DUE.md              <- open this. Everything due, all classes, by date.
  CHANGES.md          <- what changed since the last run
  courses.json        <- course -> folder map. Rename folders or skip courses here.
  MBA 501 - Corporate Financial Reporting\
    AGENTS.md         <- rules the agents follow (shared block + course facts)
    CLAUDE.md GEMINI.md STATUS.md
    canvas\           <- generated mirror: syllabus.md, assignments.md, assignments.json
    sources\ work\ submissions\
  MBA 520 - Business Finance\ ...
```

`DUE.md` tags on-paper submissions `(paper)` - Canvas never shows those as
submitted, so they stay listed until the instructor grades them.

## Steering it

Everything below lives in your **workspace** (the `-Root` folder), not in this
repo - the workspace copies are the ones that actually run. Reruns need
`-ExecutionPolicy Bypass`, same as the install.

| Want to... | Do this |
|---|---|
| Skip a course | `"enabled": false` in `courses.json`, rerun setup |
| Rename a class folder | edit `folder` in `courses.json` before first run |
| New semester | rerun setup - new courses merge in, your edits are kept |
| Change a shared rule | edit `templates\shared-rules.md`, then run the scaffold command below |
| Get warned before the token expires | `"tokenExpires": "2026-12-13"` in `courses.json` |
| Check the schedule | `Get-ScheduledTaskInfo -TaskName 'Canvas Watch - School'` |
| Force a refresh now | `Start-ScheduledTask -TaskName 'Canvas Watch - School'` |

Rerun commands in full:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Users\you\School\setup.ps1 -Root C:\Users\you\School
powershell -ExecutionPolicy Bypass -File C:\Users\you\School\scaffold-class.ps1
```

Updating the tool overwrites the three scripts but never your
`templates\shared-rules.md`.

## Why the rules are copied into every folder instead of imported

Claude Code will not read a file above the folder it was launched in, so a
`@..\shared-rules.md` import silently loads nothing. `scaffold-class.ps1`
therefore copies the shared block into each class's `AGENTS.md` between
markers and refreshes only that block on rerun. Your own edits outside the
markers survive.

## Requirements

Windows 10/11, PowerShell 5.1+, a Canvas account. Git is optional, but install
it if you use Codex: Codex refuses any folder that is not a git repo, and when
git is present the tool runs `git init` in each class folder for you.

## Origin

Built for BYU MBA 693R (AI Engagement), Fall 2026, as the reusable-skill
assignment. Every bug listed in `SKILL.md` was found by running the tool
against a real Canvas account, not by reading the code.
