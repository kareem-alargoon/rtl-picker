# RTL Picker

**Makes Arabic, Hebrew, Persian and other right-to-left text actually read right-to-left** — in AI
chats, on any website, and in Windows desktop apps.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Manifest V3](https://img.shields.io/badge/chrome-Manifest%20V3-brightgreen)
![Windows](https://img.shields.io/badge/windows-10%20%2F%2011-0078D6)
![No tracking](https://img.shields.io/badge/telemetry-none-success)

By **kareem.argoon**

Websites and desktop apps built for English routinely mangle Arabic and Hebrew: paragraphs
left-aligned, punctuation on the wrong side, brackets and numbers scrambled. Browsers ship a partial
fix — `dir="auto"` — but it only inspects the *first* strong character, so a reply beginning
"Here is the answer: مرحبا" stays stubbornly left-to-right. RTL Picker measures the whole block
instead, and gives you a manual override for whatever it still gets wrong.

Two independent pieces, usable separately:

| | What it covers | How |
| --- | --- | --- |
| **`extension/`** | ChatGPT, Claude, Gemini, Grok, Perplexity, and every other website | Chrome/Edge extension (Manifest V3) |
| **`desktop/`** | Word, Notepad, Slack, VS Code, Electron apps — including read-only text | Native Windows tray app, ~48 KB, no install |

## Quick start

**Browser** — open `chrome://extensions`, turn on **Developer mode**, click **Load unpacked**, pick
the `extension` folder. Arabic pages flip immediately.

**Windows** — double-click `desktop\RTLPicker.exe`. Select any text and press
<kbd>Ctrl</kbd>+<kbd>Alt</kbd>+<kbd>D</kbd> to read it right-to-left, even where the text can't be
edited.

Publishing to the Chrome Web Store? See **[docs/PUBLISHING.md](docs/PUBLISHING.md)**.
Privacy: **[PRIVACY.md](PRIVACY.md)** — nothing is collected, and there are no network calls at all.

---

## Browser extension

### Install

1. Open `chrome://extensions` (or `edge://extensions`).
2. Turn on **Developer mode**.
3. Click **Load unpacked** and choose the `extension` folder.

Works in Chrome, Edge, Brave, Opera, Arc — anything Chromium-based.

### What it does

**Auto-detect.** Every block of text on the page is measured: if enough of its strong characters
are RTL, the block is flipped. It counts characters rather than using the browser's built-in
`dir="auto"`, which looks only at the *first* strong character and therefore leaves
`Here is the answer: مرحبا…` stuck left-to-right.

It keeps working while an AI streams its reply — a throttled `MutationObserver` re-checks blocks as
tokens arrive, so the answer settles into RTL as it's written.

Mixed messages are handled paragraph by paragraph: an Arabic message containing one English
paragraph flips the Arabic and pins the English back to LTR rather than letting it inherit.

**Input boxes.** Chat composers, search fields and rich-text editors (ProseMirror, Lexical, Quill)
flip as you type, and flip back when you switch language. Rich editors get one direction per line.

**The picker.** For anything auto-detect gets wrong or can't see. Press <kbd>Alt</kbd>+<kbd>Shift</kbd>+<kbd>P</kbd>
or click **Pick an element** in the popup, then:

| | |
| --- | --- |
| Hover | highlights the element under the cursor and shows the selector it would save |
| <kbd>↑</kbd> / <kbd>↓</kbd> | widen to the parent / narrow to the child — grab the whole message bubble, not one `<span>` |
| Click | force RTL |
| <kbd>Shift</kbd>+click | force LTR (handy for a code block that keeps getting flipped) |
| <kbd>Alt</kbd>+click | this one element only, instead of everything that looks like it |
| <kbd>Esc</kbd> | cancel |

Rules are saved per site and re-applied on every visit, including to elements that didn't exist yet.
By default a rule **generalises**: picking one chat bubble writes a selector that matches all of
them. The popup shows how many elements each rule currently hits.

### Shortcuts

| | |
| --- | --- |
| <kbd>Alt</kbd>+<kbd>Shift</kbd>+<kbd>R</kbd> | turn the extension on/off for the current site |
| <kbd>Alt</kbd>+<kbd>Shift</kbd>+<kbd>P</kbd> | start the picker |

Rebind them at `chrome://extensions/shortcuts`.

### Settings (toolbar popup)

- **Auto-detect RTL text** — the automatic pass. Turn it off to rely purely on saved rules.
- **Flip input boxes while typing**
- **Leave code blocks alone** — keeps `<pre>` and `<code>` left-to-right even when the comments are
  Arabic. On by default, because RTL code is almost never what you want.
- **Sensitivity** — how much of a block must be RTL before it flips. 25% by default; raise it if
  short Arabic quotes inside English paragraphs are flipping things you'd rather leave alone.
- Per-site switch in the header, master switch in the footer.

### Limits

- Content inside cross-origin iframes gets auto-detect, but the picker only runs in the top frame.
- Doesn't run on `chrome://` pages or the Chrome Web Store — Chrome forbids it.
- A saved rule is a CSS selector. If a site ships a redesign, the selector may stop matching; the
  popup will show `0×` next to it, and re-picking takes a second.

---

## Desktop app (Windows)

Native apps can't be restyled the way a web page can, so this takes the two approaches that do work
everywhere.

### Run it

Double-click **`desktop\RTLPicker.exe`**. That's it — a real ~48 KB executable, no install, no
dependencies beyond the .NET Framework that ships with Windows. It lives in the system tray;
right-click for the menu, including **Start with Windows**.

No `powershell.exe` in Task Manager, no console window, and it's ready in about a second instead of
the ~8 the script needed to compile its helpers at every startup.

### Building it yourself

The exe is committed ready to run, but the full source is `desktop\src\RTLPicker.cs` and it builds
with the C# compiler that ships with Windows — no dotnet SDK, no NuGet, no ps2exe:

```bash
%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe /target:winexe /optimize+ /codepage:65001 /reference:System.dll /reference:System.Drawing.dll /reference:System.Windows.Forms.dll /out:desktop\RTLPicker.exe desktop\src\RTLPicker.cs
```

`/target:winexe` is what makes it a windowed app with no console. Add
`/win32icon:<file>.ico` to embed an icon.

Verify a build with `RTLPicker.exe --selftest`, which runs the checks and writes a report to
`%LOCALAPPDATA%\RTLPicker\selftest.txt` (a windowed exe has no console of its own).

### The PowerShell version

`desktop\RTLPicker.ps1` is the original, kept as a no-build fallback and still fully working:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "desktop\RTLPicker.ps1"
```

Quote the path — it contains a space, and an unquoted `-File` argument exits silently.

⚠️ **The same behaviour now exists in two languages, which will drift.** `desktop\src\RTLPicker.cs`
is the one to change; delete the `.ps1` once you're happy with the exe. Two differences to know
about if you use it: the script writes a Startup-folder shortcut where the exe uses the `HKCU\...\Run`
registry key, and running both at once means they fight over the same global hotkeys.

### Hotkeys

| | | |
| --- | --- | --- |
| <kbd>Ctrl</kbd>+<kbd>Alt</kbd>+<kbd>D</kbd> | **read the selection in an RTL window** | **works anywhere, editable or not** |
| <kbd>Ctrl</kbd>+<kbd>Alt</kbd>+<kbd>R</kbd> | wrap the selected text as RTL | editable fields |
| <kbd>Ctrl</kbd>+<kbd>Alt</kbd>+<kbd>L</kbd> | strip the direction marks back out | editable fields |
| <kbd>Ctrl</kbd>+<kbd>Alt</kbd>+<kbd>B</kbd> | wrap whatever is on the clipboard | works everywhere |
| <kbd>Ctrl</kbd>+<kbd>Alt</kbd>+<kbd>Shift</kbd>+<kbd>R</kbd> | native paragraph direction → RTL | Word, WordPad, Outlook only |
| <kbd>Ctrl</kbd>+<kbd>Alt</kbd>+<kbd>Shift</kbd>+<kbd>L</kbd> | native paragraph direction → LTR | Word, WordPad, Outlook only |

They're deliberately different from the extension's <kbd>Alt</kbd>+<kbd>Shift</kbd> shortcuts — a
global hotkey would otherwise steal them from Chrome. These are only the defaults: rebind any of them
from **Keyboard shortcuts…** in the tray menu (see below). If one is already taken when the app
starts, it falls back to an alternate automatically and tells you which.

**The first three edit the text itself**, wrapping it in Unicode bidi control characters (`U+202B` …
`U+202C`). Any app implementing the Unicode bidirectional algorithm then lays that run out
right-to-left — that's Chromium and therefore every Electron app (Claude, Slack, VS Code, Discord),
plus Word, Notepad and browsers. The direction travels with the text when you send it. The selection
is copied, transformed, pasted back, and your original clipboard is restored.

**The two `Shift` ones** send Windows' native paragraph-direction command (Ctrl + Right/Left Shift).
Only RichEdit controls understand it; Chromium and Electron ignore it completely.

**Compose in RTL…** (tray menu) opens a small always-on-top box with a proper RTL text field. Type
or paste there, hit **Copy as RTL**, and paste the marked-up result wherever you need it. Easiest way
to see what the tool does.

**Wrap each line separately** (tray menu, on by default) gives every line its own RTL run. Turn it
off to treat the whole selection as one.

**Keyboard shortcuts…** (tray menu) lets you pick your own key for every action. Click a box, press
the chord you want, and **Save** — the global hotkeys are re-registered live, with no restart. If a
key is already owned by another app, the old one is kept and you're told which clashed. **Clear** on
any row removes its hotkey entirely; that action then runs only from the tray menu, freeing the key
for something else.

**Choose apps it works in…** (tray menu) scopes where the shortcuts fire. Global hotkeys can't be
limited to one app by Windows itself, so the tool checks the focused app when a key is pressed:
leave it at *every app* (the default), restrict it to *only* a ticked set, or block an *except* set.
Tick from the list of running apps or type a name like `chrome`. Choices persist in
`%LOCALAPPDATA%\RTLPicker\settings.ini`.

Every action shows a small toast in the corner — a custom window, not a balloon tip, because Windows
notification settings silently swallow those. Actions are also written to
`%LOCALAPPDATA%\RTLPicker\rtlpicker.log`, reachable from **Open log** in the tray menu; each entry
records which window was focused, so a failed action can be traced to a target.

### The reader — for text you can't edit

<kbd>Ctrl</kbd>+<kbd>Alt</kbd>+<kbd>D</kbd> is the answer to read-only text: Claude's replies, a
chat transcript, a rendered page. Those can't be modified — there is nothing to paste into — so
instead of fighting the source app, the reader copies your selection and shows it in **its own
window**, laid out right-to-left. The source app is never touched, nothing is injected into it, and
your clipboard is put back immediately.

Select the text, press the key, read it, press <kbd>Esc</kbd>. The window fades in and out, stays on
top, and remembers its size and position between reads.

| in the reader | |
| --- | --- |
| <kbd>Esc</kbd> | close |
| <kbd>+</kbd> / <kbd>-</kbd>, or `A+` / `A-` | text size |
| `RTL / LTR` | override the direction if the guess is wrong |
| `Copy` | copy the selection, or everything if nothing is selected |

Direction is detected with the same character-ratio test the extension uses, so a mostly-English
paragraph containing one Arabic word stays left-to-right.

**Read clipboard in RTL** in the tray menu does the same for whatever you've already copied.

### Where the wrap actions work

The wrap actions are copy → transform → paste, so their target must be an **editable** field: the
Claude Desktop prompt box, Slack's composer, the VS Code editor, Word, Notepad, any browser input.
For anything read-only, use the reader above.

### What it can and can't do

The wrap actions fix **text**, not **layout** — punctuation, brackets, numbers and embedded English
land in the correct places, but they cannot right-align another application's interface. Only that
app's own settings can do that.

The reader sidesteps this entirely: it doesn't try to change the other app at all, it just gives you
a properly laid-out copy to read in. That's why it's the one action that works on Claude's replies.

The alternative for Claude specifically would be launching it with a DevTools port and injecting the
extension's engine into its renderer. That works, but it leaves a local endpoint with full control
over the running app — including your session — so the reader is the better trade.

Terminals (Windows Terminal, conhost, anything on xterm.js) implement no bidi algorithm at all, so
the marks have no effect there — they'll show up as invisible characters and nothing more.

---

## Layout

```
extension/
  manifest.json
  icons/                     16, 32, 48 and 128 px
  src/core/detect.js         which script a chunk of text is in
  src/core/selector.js       turning a picked element into a reusable CSS selector
  src/core/settings.js       storage, shared by content script, popup and worker
  src/content/content.js     auto-detect, fields, rules, mutation pipeline
  src/content/picker.js      hover-and-click picker
  src/content/content.css    the direction rules plus the picker overlay
  src/popup/                 toolbar UI
  src/background/            keyboard commands and the toolbar badge
desktop/
  RTLPicker.exe              the app — double-click this
  src/RTLPicker.cs           its source; the maintained implementation
  RTLPicker.ps1              original PowerShell version, no-build fallback
  Start RTL Picker.cmd       launcher (prefers the exe)
```

## Development

The extension has **no build step**. Edit the files and hit reload at `chrome://extensions`.

Syntax check without a browser:

```bash
node --check extension/src/content/content.js
```

The desktop app's maintained source is `desktop/src/RTLPicker.cs` — see
[Building it yourself](#building-it-yourself) above. `RTLPicker.exe --selftest` runs its unit checks.

### One trap worth knowing

**Never compare these strings with `-eq` or `-ceq` in PowerShell.** Both are culture sensitive, and
bidi control characters carry zero collation weight, so .NET reports wrapped and unwrapped text as
*equal*. That shipped once and silently discarded every transform — the feature looked completely
dead while working perfectly. Use
`[string]::Equals($a, $b, [System.StringComparison]::Ordinal)`. C#'s `==` on strings is already
ordinal, so the native build can't hit this, and `--selftest` asserts it explicitly.

---

## Contributing

Issues and pull requests are welcome. Worth knowing before you start:

- The extension has no build step — edit, reload, done.
- The desktop app's source is `desktop/src/RTLPicker.cs`; rebuild with the `csc.exe` command above
  and re-run `--selftest`.
- Desktop changes that touch the clipboard or hotkey paths deserve a manual check against a real
  focused window; synthetic input silently does nothing without real focus.

## Privacy

No data collection, no analytics, no telemetry, and no network requests of any kind — verify with
`grep -rE "fetch\(|XMLHttpRequest|https?://" extension/`. Settings stay in your own browser. Full
details in [PRIVACY.md](PRIVACY.md).

## License

[MIT](LICENSE) © 2026 Kareem Argoon (**kareem.argoon**)
