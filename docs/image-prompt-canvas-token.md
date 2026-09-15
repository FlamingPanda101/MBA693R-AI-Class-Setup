# Image prompt: getting a Canvas API token

Paste the prompt below into an image model (ChatGPT/DALL-E, Midjourney, Gemini,
Nano Banana, Firefly). It produces a printable step-by-step guide for the one
part of setup a student must do themselves.

**Check the result before you share it.** Image models garble small text and
invent UI. Open Canvas side by side and confirm every label matches what is
actually on screen. If the model cannot render the text cleanly, ask it for the
layout only and add the captions yourself.

---

## Prompt

> Create a clean instructional infographic titled **"Get your Canvas API token"**,
> portrait orientation, 1080x1920, designed to be read on a phone.
>
> Five numbered steps stacked vertically, each a rounded card with a soft drop
> shadow on a very light grey background. Each card has a small step number in a
> filled circle on the left, a short bold heading, one line of plain-English
> detail, and a simplified illustration of the relevant screen on the right.
>
> Step 1 - "Open your Canvas settings": a simplified browser window, address bar
> reading `yourschool.instructure.com/profile/settings`, a left sidebar with a
> highlighted "Account" item.
>
> Step 2 - "Click + New Access Token": the same page scrolled to a section headed
> "Approved Integrations", with a blue button labelled **+ New Access Token**
> circled in orange.
>
> Step 3 - "Name it and set an expiry": a small modal dialog with a text field
> labelled "Purpose" containing `canvas-watcher`, and a date field labelled
> "Expires" containing an end-of-semester date. A blue "Generate Token" button.
>
> Step 4 - "Copy it now": the dialog showing a token as a row of blurred dots
> with a copy icon, and a red warning banner reading **"Shown only once - copy it
> before you leave this page"**. Do not render any readable token characters.
>
> Step 5 - "Store it in your terminal": a single panel split left and right by a
> thin vertical rule, each half labelled with its platform name.
>
> Left half, headed **Windows**: a terminal whose title bar clearly reads
> **Windows PowerShell**, with a small inset of the Start menu with "PowerShell"
> typed into the search box. One line of white monospace text:
> `[Environment]::SetEnvironmentVariable('CANVAS_TOKEN', (Get-Clipboard), 'User'); Set-Clipboard -Value 'cleared'`
> Caption: "Windows PowerShell only - not Command Prompt. Takes the token from
> your clipboard, then wipes it. Nothing is printed."
>
> Right half, headed **macOS**: a macOS Terminal window. One line of white
> monospace text:
> `security add-generic-password -a "$USER" -s canvas-workspace-token -U -w`
> with the cursor sitting on a following line that reads
> `password data for new item:` and nothing typed after it.
> Caption: "The bare -w at the end is deliberate - Terminal prompts for the
> token instead of putting it on the command line. Paste, press Return, then
> run pbcopy < /dev/null to clear the clipboard."
>
> At the bottom, a red-bordered callout box with a lock icon reading:
> **"Never paste this token into a chat, a document, or a screenshot. It is full
> access to your Canvas account."**
>
> Style: flat modern vector, generous white space, one accent colour (Canvas
> red-orange #E4060F) against neutral greys, high-contrast legible sans-serif.
> No photorealism, no people, no fictional branding. All text spelled exactly as
> written above.

---

## If the model mangles the text

Ask for the frame only, then add captions in any editor:

> Same layout and style as above, but render every text area as an empty grey
> placeholder bar. No lettering anywhere in the image.

## Facts the picture must not get wrong

- The token is shown **once**. Leaving the page means generating a new one.
- The button really is labelled **+ New Access Token**, under **Approved Integrations**.
- Purpose is a free-text label; `canvas-watcher` is a convention, not a requirement.
- An expiry is optional in Canvas, but end-of-semester is the safe choice.
- The token grants the student's **whole** Canvas account. It is not scoped to one course.
- On Windows the terminal must be **Windows PowerShell**, not Command Prompt.
  This matters more than it looks: `Get-Clipboard` does not exist in cmd, and
  the command fails *silently* there - cmd would store the literal characters
  `(Get-Clipboard)` and print `SUCCESS`, so the student walks away believing the
  token is saved when it is not, with their real token still on the clipboard.
- Use `[Environment]::SetEnvironmentVariable(...)`, **not** `setx`. Both persist
  to the same place, but `setx` receives the token as a command-line argument,
  which Windows process auditing and corporate EDR agents record and forward.
- On macOS the token goes to the **login Keychain**, not a file and not a shell
  profile. The `-w` at the end of the `security` command must have **nothing
  after it** - that is what makes it prompt. Writing `-w "<the token>"` would
  put the secret on the command line, where `ps` and shell history both keep it,
  which is the same mistake as `setx` on Windows.
- The image must not imply the tool is Windows-only. Both halves are equally
  supported; a Mac needs PowerShell 7 (`brew install --cask powershell`) to run
  the scripts afterwards, but the token step above uses only built-in macOS.
- Do not show the two halves as "recommended" and "alternative". They are the
  same step on two platforms, and a student sees only their own.
- Do not render any readable token characters anywhere in the image.
