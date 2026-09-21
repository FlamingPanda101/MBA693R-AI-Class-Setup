# mba-canvas-workspace

One folder per class, mirrored from Canvas, ready for Claude Code, Codex, or
Antigravity to work in. A scheduled job refreshes every course and writes a
single `DUE.md` of everything outstanding across all your classes.

Read-only. It never submits, grades, or messages. Your Canvas token stays on
your machine and is never written to a file.

## Install

You need **one** of Claude Code, Codex, or Antigravity. Open it and paste this in:

```text
Set up my class workspace from https://github.com/FlamingPanda101/MBA693R-AI-Class-Setup

Clone that repo into a temporary folder, read its SKILL.md, and follow it.
Ask me the questions one at a time, build the workspace somewhere else on my
machine, and then show me how to use it. I am not a programmer, so explain
what each answer does before you ask for it.
```

That is the whole thing. **You do not type any commands.** It works out whether
you are on Windows or a Mac by itself, downloads the files, asks you seven short
questions, builds everything, explains each step in plain English as it
happens, and then walks you through what you got.

1. Have you already set this up on another computer?
2. Do you have Google Drive on this machine, and should the workspace live there?
3. Where should the workspace live?
4. Which AI coding tools do you use? (only those get instruction files)
5. Which school's Canvas?
6. How often should it check?
7. Want a daily standup, and at what time?

Every question has a sensible default, and there is exactly one step it cannot do
for you: making a Canvas token, because only you can log into your Canvas. It
walks you through that too.

**Ask it anything as you go** - "what is a token?", "why does it want Google
Drive?", "can you change that answer?". It has the full instructions and can
explain any step, redo one, or change an answer later.

**On a Mac** it will check for PowerShell 7 and, if it is missing, give you the
one-line `brew install --cask powershell` and wait. Nothing is changed until then.
You do not need Windows or a VM.

<details>
<summary>No AI assistant? Do it by hand instead</summary>

Get the files, then run the launcher for your computer. You still do not need to
know which shell you are on or which flags it wants - that is the launcher's job.

```bash
git clone https://github.com/FlamingPanda101/MBA693R-AI-Class-Setup.git
cd MBA693R-AI-Class-Setup
```

Then, **on Windows**, double-click `setup.cmd` in the folder - or from a
terminal:

```powershell
.\setup.cmd
```

The `.\` matters in PowerShell - without it you get "not recognized as the name
of a cmdlet", because PowerShell deliberately does not run programs from the
current folder.

**On macOS**, in Terminal:

```bash
./setup.sh
```

Both ask the same seven questions and build the same workspace. `setup.sh` will
tell you how to install PowerShell if it is missing, and changes nothing until
it is. When setup finishes it prints the exact commands for *your* machine, so
you never have to translate anything from this README.

No Git? On the GitHub page click the green **Code** button, then **Download
ZIP** and unpack it - right-click and **Extract All** on Windows, double-click on
macOS - then use the launcher in the extracted folder.

This folder is only the installer. It asks where your workspace should live and
builds it there - your coursework never lives in the cloned copy, so you can
delete it afterwards.

</details>

## A daily brief on your phone

`notify.ps1` sends a short, lock-screen-sized version of the standup to your own
WhatsApp: what's due, what's genuinely at risk, and the big items far enough
ahead that you can still do something about them.

```powershell
.\notify.ps1 -Setup             connect it (walks you through the whole thing)
.\notify.ps1 -DryRun            show exactly what would be sent, send nothing
.\notify.ps1                    send it now
.\notify.ps1 -ScheduleAt 07:30  send it every morning
.\notify.ps1 -Unschedule        stop
```

It sends **only** to the number you record during setup. There is deliberately
no recipient argument. The provider's API key is stored by your operating system
— the Windows user environment or the macOS login Keychain — never in a file
here, and never printed, including on errors.

Two honest limits. It goes to **you, not a group**: WhatsApp groups need a
verified business account through Meta's Groups API, which this is not. And the
message text passes through CallMeBot's relay, so treat course names and
assignment titles as "not secret" rather than "private". If you want a group, or
you want no third party in the path, Telegram's bot API does the same job in
about five minutes — ask your assistant to add it.

## Using it afterwards

You still do not type commands. Open the assistant **in your workspace folder**
so it picks up the rules, and ask in plain language:

```text
What's due this week?
Run my standup.
What changed in Canvas since yesterday?
Help me start the Fabritek case.
Add my new class.
```

It refreshes Canvas every hour on its own, so the answer is current without you
asking for a refresh.

If you would rather run it yourself, setup prints the exact commands for *your*
machine when it finishes - no translating from this README. For reference, the
standup is:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\standup.ps1
```

and on macOS:

```bash
pwsh -NoProfile -File ./standup.ps1
```

Prints what is due today, what is coming in the next 7 days, and what is past
due; rewrites `STANDUP.md`; and refreshes `canvas-deadlines.ics` for your
calendar. Add `-Refresh` to pull Canvas first, `-Days 14` for a wider window.

**Picture guides** (prompts you can feed to any image model - see `docs\`):
- [How to use the repo link](docs/image-prompt-repo-link.md)
- [How to get your Canvas API token](docs/image-prompt-canvas-token.md)

**Want your Slack, email and calendar in there too?**
See [Connecting Slack, email and calendar](docs/connect-slack-email-calendar.md).
Your Canvas deadlines go into Google/Outlook/Apple Calendar with no accounts at
all - `standup.ps1` writes a `.ics` file you just import. Live connections to
mail and Slack are a separate, bigger decision, and that guide covers both.

**By hand** - three steps:

1. Canvas -> Account -> Settings -> **+ New Access Token**. Copy it.
2. Open **Windows PowerShell** — *not* Command Prompt, not the black `cmd`
   window — and run exactly this:

   ```powershell
   [Environment]::SetEnvironmentVariable('CANVAS_TOKEN', (Get-Clipboard), 'User'); Set-Clipboard -Value 'cleared'
   ```

   It takes the token straight from your clipboard, so it never appears on
   screen or in your shell history, then wipes the clipboard so a stray Ctrl+V
   cannot paste it into a chat window. Using Win+V clipboard history? Clear it
   too: Settings > System > Clipboard.

   > **Why not `setx`?** `setx` receives the token as a command-line argument,
   > and Windows process auditing and most corporate EDR agents record full
   > command lines. On a managed laptop that ships your token to a central log.
   > The line above sets the same value in-process, with no child process.
   >
   > **Why PowerShell specifically?** `Get-Clipboard` does not exist in Command
   > Prompt, and it fails *silently* — cmd stores the literal text
   > `(Get-Clipboard)` and prints `SUCCESS`, so you would think you were done.

   (Not BYU? Also set `CANVAS_BASE` to `https://yourschool.instructure.com` the
   same way. It must start with `https://`.)
3. ```powershell
   powershell -ExecutionPolicy Bypass -File .\setup.ps1 -Root C:\Users\you\School -Agents claude
   ```

   `-Agents` takes any subset of `claude,codex,antigravity`; omit it to get all
   three. Add `-Reuse` if this workspace already came from another computer -
   setup will adopt it instead of rebuilding.

`-Root` must be a different folder from this repo. Setup greets you by name,
discovers your courses, builds the folders, `git init`s each one, takes the
first snapshot, and schedules a refresh every hour.

No new terminal needed: the scripts read the User-scope value directly, so they
work immediately - including when an AI agent runs them for you.

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
| Add or drop an AI tool | rerun setup with `-Agents claude,antigravity` |
| Move to a new computer | install Drive (or copy the folder), then rerun setup with `-Reuse` |
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

## What this does and does not do

Built for a course that asks you to set up a private folder per class, two local
AI agents with shared rules, and a bounded review between them. It covers the
parts a script can:

**Covered** - folder per class with `sources`, `work`, `submissions`, `skills`;
`AGENTS.md` shared rules plus `CLAUDE.md` / `GEMINI.md` wired to them; a
read-only Canvas mirror with a cross-class `DUE.md`; a standup; a calendar
export; `doctor.ps1` to check the setup and say what is missing.

**NOT covered, still yours** - buying and enrolling in the course book; any
cold-benchmark or survey you are told to answer yourself; installing and signing
into the agent CLIs; mobile agent access; saving your authentic conversation
into `submissions\`; and actually running the bounded cross-agent review.

`doctor.ps1` prints that same list every run, so a green report is never
mistaken for a finished setup assignment:

```powershell
powershell -ExecutionPolicy Bypass -File .\doctor.ps1
```

It checks which agents are installed, whether they authenticate (a version
number proves neither), whether `CLAUDE.md` / `GEMINI.md` really import the
shared rules, whether every class folder has all four subfolders, and whether
the Canvas mirror and scheduled task are healthy. `-Fast` skips the live agent
calls so it uses none of your account allowance.

**If Gemini CLI will not sign in**, that is Google, not you - individual
accounts now get `IneligibleTierError / UNSUPPORTED_CLIENT` and are pointed at
the Antigravity suite. See [Gemini CLI, Antigravity and Spark](docs/gemini-vs-antigravity.md),
which also explains why those three names are not interchangeable.

## Requirements

A Canvas account, and either:

- **Windows 10/11** with Windows PowerShell 5.1+ — already installed, nothing to add.
- **macOS** with PowerShell 7: `brew install --cask powershell`, then use `pwsh`
  wherever this README says `powershell`, and drop `-ExecutionPolicy Bypass`
  (it does not exist outside Windows and pwsh errors on it).

What differs between the two is confined to `platform.ps1`: the token goes in
the Windows user environment or the macOS login Keychain, and the hourly refresh
is a Task Scheduler task or a launchd agent. Everything else is the same file.

Linux will mirror Canvas, build the folders and run standups, but nothing
schedules the refresh — setup says so and suggests cron rather than pretending.

**Using Codex? You also need Git** (`winget install Git.Git` on Windows, `brew
install git` or the Xcode command line tools on macOS, or git-scm.com).
Codex refuses any folder that is not a git repository. When git is present the
tool runs `git init` in each class folder for you; when it is absent, setup
warns you and the folders are created anyway, but Codex will not open them.

Each class folder gets a `.gitignore` that excludes your Canvas mirror, notes
and coursework, and so does the workspace root. Those repos exist so Codex will
open the folders — they are not meant to be pushed anywhere.

## Origin

Built for BYU MBA 693R (AI Engagement), Fall 2026, as the reusable-skill
assignment. Every bug listed in `SKILL.md` was found by running the tool
against a real Canvas account, not by reading the code.
