# Image prompt: how to use the repo link

Paste the prompt below into an image model (ChatGPT/DALL-E, Midjourney, Gemini,
Nano Banana, Firefly). It produces a one-page visual for classmates who have
never cloned a repository: what the link is, where to paste it, and what happens.

**Check the result before you share it.** Image models garble small text and
invent UI. Confirm the repo URL is character-perfect before sending it to anyone.

---

## Prompt

> Create a clean instructional infographic titled **"Set up your class workspace
> in 4 steps"** with a smaller subtitle directly beneath reading **"Windows 10/11"**,
> landscape orientation, 1920x1080, designed to be read on a laptop.
>
> Across the top, a single wide pill-shaped bar containing the repository link in
> monospace text, with a copy icon at the right end:
> `https://github.com/FlamingPanda101/MBA693R-AI-Class-Setup`
>
> Below it, four equal columns separated by thin vertical rules, each with a
> large numbered circle, a bold heading, one line of plain English, and a
> simplified illustration.
>
> Column 1 - "Copy the link": a simplified GitHub repository page with a green
> "Code" button, the URL above highlighted, and a cursor clicking a copy icon.
>
> Column 2 - "Paste it into your AI": a chat window with a text bubble reading
> "Set up my Canvas workspace using this repo:" followed by a shortened link.
> Below the chat window, three small labelled app tiles side by side -
> **Claude Code**, **Codex**, **Antigravity** - with a caption underneath:
> "Any one of these. You do not need all three." and, in smaller text under the
> Codex tile only, a footnote marker reading "Codex also needs Git installed".
>
> Column 3 - "Make a Canvas token": a simplified Canvas settings page with a blue
> button labelled **+ New Access Token**, and beneath it a caption in a tinted
> box: "The one step only you can do. Takes a minute - see the token guide."
>
> Column 4 - "Answer seven questions": a simplified checklist card with seven
> short rows, each with a checkbox: "Set up before?", "Google Drive?", "Where?",
> "Which AI tools?", "Which school?", "How often?", "Daily standup?". One row is
> highlighted as in-progress.
>
> Across the bottom, a wide result strip showing a simplified file tree:
> a folder icon labelled `School`, containing `DUE.md` with a small calendar
> icon, and three folders labelled `MBA 501`, `MBA 520`, `MBA 530`. Caption:
> **"One folder per class, plus a single list of everything that's due."**
>
> In the bottom-right corner, a small speech-bubble callout reading:
> **"Stuck? Just ask your AI - it has the full instructions."**
>
> Style: flat modern vector, generous white space, dark-on-light, one accent
> colour (indigo #4F46E5) against neutral greys, high-contrast legible
> sans-serif, monospace only for the link. No photorealism, no people, no
> fictional logos. All text spelled exactly as written above.

---

## If the model mangles the text

Ask for the frame only, then add captions in any editor:

> Same layout and style as above, but render every text area as an empty grey
> placeholder bar. No lettering anywhere in the image.

## Facts the picture must not get wrong

- **Windows only.** The tool is Windows PowerShell 5.1 plus Windows Task
  Scheduler; there is no macOS or Linux path. The picture must say so up front,
  because a Mac classmate who follows it will create a full-account Canvas token
  before discovering nothing can use it. Making a token is the irreversible step.
- The link is the **repository**, not a download of a single file.
- Any **one** of the three agents is enough — *except* that Codex additionally
  requires Git to be installed. Without it the class folders are not
  repositories and Codex refuses to open them. Do not let the picture imply the
  three tiles are interchangeable with no strings attached.
- **A Canvas token is required and cannot be skipped.** An earlier version of
  this prompt showed three steps and omitted it, which promised a finished
  workspace that setup would refuse to build. It is its own column for a reason.
- Nothing is installed by clicking the link: the agent clones it and runs setup.
- The seven questions are asked by the assistant (or `setup.ps1 -Interview`), not GitHub.
- The end result is a folder per class plus one `DUE.md`, not a website or an app.
