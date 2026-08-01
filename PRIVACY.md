# Privacy Policy — RTL Picker

**Last updated:** 1 August 2026
**Contact:** Kareem Argoon — via [GitHub issues](https://github.com/kareem-alargoon/rtl-picker/issues)

## The short version

RTL Picker collects nothing, sends nothing, and contains no analytics, tracking or telemetry of any
kind. It makes no network requests whatsoever. Everything it stores stays on your own device.

## What the extension stores

Only your own settings, saved locally through the browser's `chrome.storage.local` API:

- Whether the extension is enabled, globally and per site
- Your toggles: auto-detect, input-box flipping, code-block exclusion, sensitivity
- The CSS selector rules you create with the picker, grouped by site origin
  (for example `https://chatgpt.com` → `div[data-message-author-role="assistant"]`)

This data never leaves your browser. It is not synced to any server, including any belonging to the
developer. Uninstalling the extension removes it.

## What it does *not* collect

- No page content. The extension reads text on the page to decide whether it is right-to-left, but
  that happens entirely in memory on your machine and is never stored or transmitted.
- No browsing history, URLs or page titles. Site origins are stored **only** for sites where you
  personally created a rule or turned the extension off.
- No personal information, credentials, form data, keystrokes or clipboard contents.
- No identifiers, cookies, IP logging or usage statistics.

## Why the extension asks for broad site access

The `<all_urls>` host permission exists because right-to-left text can appear on any website, and the
extension cannot know in advance which ones you use. It is used solely to read text and apply CSS
direction on pages you visit. It is never used to extract, collect or transmit anything.

You can restrict this at any time in Chrome: **Extensions → RTL Picker → Site access**, set to
*On click* or *On specific sites*.

## The desktop app

The Windows companion app (`RTLPicker.exe`) is separate software, not part of the extension, and also
makes no network requests. It writes a local diagnostic log to
`%LOCALAPPDATA%\RTLPicker\rtlpicker.log` recording which window was focused when an action ran and
how many characters were processed. That file stays on your machine; delete it any time.

When you use a wrap or read shortcut, the app briefly copies your current selection through the
Windows clipboard, then restores whatever was on the clipboard before. Clipboard contents are never
stored or sent anywhere.

## Changes

Any change to this policy will be published in this file in the public repository, with the date
above updated.

## Verify it yourself

The complete source is public. There are no network calls anywhere in the extension — confirm with:

```bash
grep -rE "fetch\(|XMLHttpRequest|sendBeacon|WebSocket|https?://" extension/
```
