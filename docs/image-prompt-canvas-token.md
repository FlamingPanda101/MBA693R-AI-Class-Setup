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
> Step 5 - "Open Windows PowerShell and store it": a terminal window whose title
> bar clearly reads **Windows PowerShell**, with a small inset showing the
> Windows Start menu with "PowerShell" typed into the search box. The terminal
> shows exactly one line of white monospace text:
> `[Environment]::SetEnvironmentVariable('CANVAS_TOKEN', (Get-Clipboard), 'User'); Set-Clipboard -Value 'cleared'`
> with a caption beneath: "Windows PowerShell only - not Command Prompt. Takes
> the token from your clipboard, then wipes the clipboard. Nothing is printed."
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
- The terminal must be **Windows PowerShell**, not Command Prompt. This matters
  more than it looks: `Get-Clipboard` does not exist in cmd, and the command
  fails *silently* there - cmd would store the literal characters
  `(Get-Clipboard)` and print `SUCCESS`, so the student walks away believing the
  token is saved when it is not, with their real token still on the clipboard.
- Use `[Environment]::SetEnvironmentVariable(...)`, **not** `setx`. Both persist
  to the same place, but `setx` receives the token as a command-line argument,
  which Windows process auditing and corporate EDR agents record and forward.
- Do not render any readable token characters anywhere in the image.
