# Gemini CLI, Antigravity, and Spark are three different things

If a syllabus tells you to install Gemini CLI and it refuses to sign in, this
page is why. Read the three names first, because they are easy to confuse and
the fix depends on which one you actually need.

| Name | What it is | Where it runs |
|---|---|---|
| **Gemini CLI** | `npm install -g @google/gemini-cli`, command `gemini` | your terminal |
| **Antigravity** | Google's separate agent suite; its CLI is `agy` | your terminal (and an IDE) |
| **Spark** | the task-performing agent inside the Gemini **desktop app** | that app's window |

**Spark is not Antigravity**, and neither is a drop-in for the other. Spark is a
desktop feature that connects to folders you pick. Antigravity is a different
product whose CLI does the terminal work a course means when it says "install
the CLI".

## What actually happens on an individual account

Verified 2026-09-14 on `@google/gemini-cli` **0.61.0-nightly**, signed in to a
personal Google account holding Google AI Pro:

```
$ gemini -p "reply OK"
Error authenticating: IneligibleTierError: This client is no longer supported
for Gemini Code Assist for individuals. To continue using Gemini, please
migrate to the Antigravity suite of products: https://antigravity.google
  reasonCode: 'UNSUPPORTED_CLIENT'
  tierId: 'free-tier'
  tierName: 'Gemini Code Assist for individuals'
```

That is Google's own message, not a local misconfiguration. Installing a newer
version does not help: 0.59.0 failed the same way earlier the same day, and
0.61.0-nightly is the current build. The CLI installs fine and prints a version
number - it just will not authenticate. **A version number proves installation,
never sign-in**, which is exactly why this trips people up.

## What to do instead

Install Google's replacement CLI. In Windows PowerShell (on macOS see the note below):

```powershell
irm https://antigravity.google/cli/install.ps1 | iex
```

The binary lands at `%LOCALAPPDATA%\agy\bin\agy.exe` on Windows, or `~/.agy/bin/agy` on macOS. It inherits credentials
from the Antigravity desktop app, so if you have signed in there you do not sign
in again. Check it:

```powershell
agy --version
agy            # interactive; ask it to read a file in your class folder
```

If `agy` is not found after installing, add it to PATH for the current window:

```powershell
$env:PATH += ";$env:LOCALAPPDATA\agy\bin"
```

## Does this satisfy a "two local agents" requirement?

Yes. `agy` is Google's own published successor for the terminal and does the job
the requirement is after.

**MBA 693R (BYU, Fall 2026): confirmed with the instructor on 2026-09-14 that
Antigravity is the intended Google route for this course.** So for this class you
do not need to justify the substitution - just use it.

In any other course, the syllabus wording may predate Google's migration. There,
**tell your instructor which pairing you used and why**, and keep the error
message above as your evidence. Do not quietly substitute and hope nobody asks.

Either way, the lowest-friction pairing on Windows is **Claude Code + Codex** -
both install and authenticate with none of this. Antigravity is the Google
option, not a required third install.

## Known quirks of `agy`

Each of these cost real time to find:

- **`agy -p` (print mode) loads no context at all.** It starts empty, so it will
  not see `GEMINI.md` or `AGENTS.md`. Interactive `agy` does load them. Any
  headless review must therefore paste the file contents into the prompt.
- **Launch it from the class folder.** If its banner shows `~` you are in your
  home folder and no course rules loaded.
- **PowerShell 5.1 mangles quotes in `-p "..."`.** Pipe the prompt in on stdin
  instead: `"your prompt" | agy`
- **Credits are metered.** An `AI: Out of credits` indicator appeared after
  roughly six calls in one morning on a Google AI Pro account, though it kept
  answering afterwards. Treat `agy` calls as rationed.

## Spark, briefly

Spark lives in the Gemini desktop app and connects to folders you choose. On
macOS it has documented folder controls. On Windows those controls were not
confirmed at the time of writing, so **do not assume the Windows app can work
with local files the way the Mac app does** - use the CLI route for anything
that must touch your course folder.

Spark also currently requires age 18+, a personal (not school-managed) Google
account, Google AI Pro or Ultra, and Keep Activity enabled. That last one is a
privacy setting worth reading before you turn it on, and it is a fair reason to
choose a different agent entirely.

Availability changes. Check Google's current pages before concluding anything
here is still true, and re-run `doctor.ps1` after any change.
