# Publishing RTL Picker to the Chrome Web Store

Step by step, with the exact text to paste into each field. Budget about an hour for the first
submission, then a few days of waiting for review.

---

## 1. Create a developer account

1. Go to the [Chrome Web Store Developer Dashboard](https://chrome.google.com/webstore/devconsole).
2. Sign in with the Google account you want to own the extension. **Pick carefully** — transferring
   an extension to a different account later is awkward, and the account's email is what Google
   contacts about reviews and policy issues.
3. Pay the **one-time US$5 registration fee**. This is per account, not per extension, and it is
   not refundable.
4. Verify your email address if prompted.

## 2. Set your publisher name to `kareem.argoon`

This is the name shown as **"Offered by"** on your store listing. It comes from your developer
account, *not* from `manifest.json` — there is no field in the manifest that controls it.

1. In the dashboard, open **Settings** (gear icon, left sidebar).
2. Under **Publisher display name**, enter:

   ```
   kareem.argoon
   ```

3. Save.

Notes worth knowing before you commit to it:

- Changing the display name later re-triggers review of your listings.
- If you ever want a verified publisher badge, you need to add and verify a domain you own under
  **Account → Verified publisher**. Without it the name still displays, just without the badge.
- A publisher name that looks like it belongs to someone else will be rejected. `kareem.argoon` is
  your own name, so this is fine.

## 3. Package the extension

The store wants a `.zip` with **`manifest.json` at its root** — not a folder containing it. Getting
this wrong is the single most common cause of a rejected upload.

```bash
powershell -NoProfile -Command "Compress-Archive -Path 'extension\*' -DestinationPath 'rtl-picker-1.0.0.zip' -Force"
```

Note the `\*` — it zips the folder's *contents*, which is what puts the manifest at the root. Zipping
the `extension` folder itself will be rejected.

Check it before uploading: open the zip and confirm you see `manifest.json`, `icons` and `src` at the
top level, not a single `extension` folder.

> **Do not upload a `.crx`, and never upload a `.pem`.** The store signs the package itself. If you
> have an `extension.pem` lying around from packing locally, delete it — anyone holding it can sign
> updates that impersonate your extension. It is already in `.gitignore`.

## 4. Create the listing

**New item → upload `dist\rtl-picker-1.0.0.zip`.**

### Store listing tab

**Name** (45 characters max):

```
RTL Picker — fix Arabic & Hebrew text
```

**Short description** (132 characters max, appears in search results):

```
Makes Arabic, Hebrew and Persian text read right-to-left on any site, including ChatGPT, Claude and Gemini. Auto-detect + picker.
```

**Detailed description:**

```
RTL Picker makes right-to-left languages display correctly on websites that were never designed for them — especially AI chat apps.

WHAT IT DOES

• Auto-detect — every block of text is measured, and blocks that are mostly Arabic, Hebrew, Persian, Urdu or other RTL scripts are flipped to read right-to-left. It counts characters instead of relying on the browser's built-in dir="auto", which only looks at the first character and leaves "Here is the answer: مرحبا" stuck left-to-right.

• Works while AI replies stream in — the page is re-checked as tokens arrive, so answers settle into RTL as they are written.

• Mixed messages are handled paragraph by paragraph. An Arabic message containing one English paragraph flips the Arabic and leaves the English alone.

• Input boxes flip as you type, and flip back when you switch language. Rich editors get one direction per line.

• The picker — for anything auto-detect gets wrong. Press Alt+Shift+P, hover to highlight any element, click to force RTL. Shift+click forces LTR. Arrow keys widen or narrow the selection. Your rules are saved per site and reapplied on every visit.

• Code blocks are left alone by default, because right-to-left code is almost never what you want.

TESTED ON

ChatGPT, Claude, Gemini, Grok, Perplexity, and any other website.

SETTINGS

Per-site on/off switch, master switch, sensitivity slider, and toggles for auto-detect, input boxes and code blocks.

PRIVACY

No data collection of any kind. No analytics, no tracking, no network requests at all. Your settings and rules are stored locally in your own browser and never leave your device. The full source code is public.

Open source (MIT) — https://github.com/kareem-alargoon/rtl-picker
```

**Category:** `Productivity`
**Language:** English (add Arabic as an additional language if you want an Arabic listing too)

### Graphic assets

| Asset | Requirement | Notes |
| --- | --- | --- |
| Store icon | 128×128 PNG | Use `extension/icons/icon128.png` |
| Screenshots | 1280×800 or 640×400, **at least 1**, up to 5 | See below |
| Small promo tile | 440×280 PNG | Optional but improves placement |
| Marquee promo tile | 1400×560 PNG | Optional, needed for featuring |

Screenshots must show the extension actually working. Good ones to capture:

1. An Arabic ChatGPT or Claude conversation, correctly right-aligned — the headline benefit.
2. A before/after pair of the same conversation.
3. The picker mid-hover, with the blue highlight and the selector readout visible.
4. The popup, showing the toggles and a couple of saved rules.

Capture at exactly 1280×800. On Windows, set the browser window to that size, then use
**Win+Shift+S** or a full-page screenshot extension. Blurry or stretched screenshots are a common
rejection reason.

## 5. Privacy tab — the part that gets submissions rejected

**Single purpose description:**

```
RTL Picker changes the text direction of web pages so that right-to-left languages such as Arabic, Hebrew and Persian display correctly.
```

**Permission justifications** — you must fill in one for each:

| Permission | Paste this |
| --- | --- |
| `storage` | `Stores the user's own settings (enabled/disabled per site, detection sensitivity, and the element rules they create) locally in their browser. Nothing is transmitted anywhere.` |
| `activeTab` | `Lets the toolbar popup read the current tab's address so that settings and saved rules are applied to the correct site, and so the user can enable or disable the extension for that site.` |
| Host permission `<all_urls>` | `Right-to-left text can appear on any website, and the extension cannot know in advance which sites the user visits. Access is used solely to read text in order to detect its writing direction, and to apply CSS text-direction to the page. No page content is collected, stored or transmitted.` |

**Are you using remote code?** → **No, I am not using remote code.**
(True — everything is bundled in the package. Answering yes triggers a much deeper review.)

**Data usage** — tick **nothing**, then certify all three statements:

- ☑ I do not sell or transfer user data to third parties, outside of approved use cases
- ☑ I do not use or transfer user data for purposes unrelated to my item's single purpose
- ☑ I do not use or transfer user data to determine creditworthiness or for lending purposes

**Privacy policy URL** — required because the extension requests broad host permissions. Use the raw
URL of `PRIVACY.md` in your public repo:

```
https://github.com/kareem-alargoon/rtl-picker/blob/main/PRIVACY.md
```

## 6. Submit

**Submit for review.** Expect a few days; extensions requesting `<all_urls>` are looked at more
closely than narrow ones. You will get an email either way.

If it is rejected, the email names the specific policy. The two most likely for this extension:

- **Broad host permissions insufficiently justified** — expand the `<all_urls>` justification with
  concrete examples of sites it is needed on.
- **Screenshots don't demonstrate functionality** — replace them with real before/after captures.

Fix and resubmit; there is no penalty for resubmitting.

## 7. Shipping updates

1. Bump `version` in `extension/manifest.json` (e.g. `1.0.0` → `1.0.1`). The store rejects an upload
   whose version is not higher than the published one.
2. Re-zip with the command from step 3, using the new version in the filename.
3. In the dashboard: your item → **Package → Upload new package** → submit.

Updates usually clear review faster than the first submission. Users get the update automatically
within a few hours of approval.

---

## Optional: Microsoft Edge Add-ons

The same zip works, and **registration is free** — no $5 fee. Submit at
[Partner Center](https://partner.microsoft.com/dashboard/microsoftedge/public/login). Review is
typically quicker, and it is a reasonable place to publish first if you want to see the extension
live before paying Google.
