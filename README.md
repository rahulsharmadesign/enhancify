<p align="center"><img src="Logo/Enhancify-AppIcon.png" width="128" alt="Enhancify icon"></p>

# Enhancify

Select text anywhere on your Mac, press a shortcut, and get a better version back, in place.

Enhancify does two jobs:

- **Enhance Prompt** turns a rough idea into a clear prompt for the AI you are using: Cursor, Claude, ChatGPT, Codex, Gemini, and others. It also fixes your spelling and grammar along the way, without changing what you meant.
- **Grammar** fixes, shortens, translates, or restyles your own writing.

It lives in the menu bar and never takes over the app you are writing in.

![macOS 26+](https://img.shields.io/badge/macOS-26%2B-blue)
![Swift 6](https://img.shields.io/badge/Swift-6-orange)
![License: MIT](https://img.shields.io/badge/license-MIT-green)

## How it works

1. Select text in any app.
2. Press **⌃⌥⌘P**.
3. Enhancify opens on the right job for where you are: **Enhance** in AI tools (Cursor, Claude, ChatGPT, VS Code), **Grammar** in text fields and in chat or mail apps.
4. Press **⌘↩** to replace your selection, or **⌘C** to copy.

With nothing selected, type or speak a rough idea and press Return.

| Key | Does |
|---|---|
| **⌃⌥⌘P** | Open Enhancify on the selection (change it in Settings) |
| **⌃⌥⌘L** | Dictate. Speech is transcribed on this Mac |
| **Tab** | Switch between Enhance and Grammar |
| **⌘↩** | Replace the selection with the result |
| **⌘L**, or start typing | Refine the result ("shorter", "mention the tests") |
| **Esc** | Close |

Results type out as clean text. In Grammar, changed words are lightly underlined and **Show changes** reveals the full diff. The panel grows with the result and scrolls once it reaches the screen height.

## Grammar styles

| Style | What it does |
|---|---|
| **Proofread** | Fixes spelling, grammar, and punctuation. Keeps your words |
| **Shorten** | Same facts and tone, fewer words |
| **To English** | Hinglish, Hindi, or any language into natural English |
| **Humanize** | Removes AI-sounding filler from pasted ChatGPT text |
| **More ▾** | Tone: Formal, Friendly, Confident, LinkedIn post. Just for fun: Gen Z, Shakespearean, Pirate, Stand-up comedian, News anchor, Bollywood dialogue, Emoji madness |

## Install

macOS 26 or later.

1. Download the latest **Enhancify-&lt;version&gt;.dmg** from [Releases](https://github.com/rahulsharmadesign/enhancify/releases).
2. Open it and drag **Enhancify** into **Applications**.
3. The app is not notarized, so allow it once:

   ```bash
   xattr -cr /Applications/Enhancify.app
   ```

   Or Control-click the app and choose **Open**.
4. Open Enhancify and allow **Accessibility** when asked. It is needed to read and replace the selection.

Updates install from **Settings → About → Check for Updates**.

## Models

| Provider | Best for | You need |
|---|---|---|
| **Apple on-device** (default) | Private and free. Good for Grammar | A Mac with Apple Intelligence |
| **Anthropic** | Best quality, especially for Enhance | An API key |
| **API** (Groq, OpenAI, OpenRouter, LM Studio…) | Any OpenAI-compatible `/v1` host | Base URL, model id, key if required |
| **Ollama** | Local models | [Ollama](https://ollama.com) and a pulled model |

Local models share memory with every other app. On a 16 GB Mac a 7B model next to an editor and a browser can slow everything down, so Enhancify defaults to `qwen2.5:3b` below 24 GB, only loads the model when you press the shortcut, and warns in Settings when a model is heavy for your Mac. On 8 GB Macs, use Apple on-device or an API model.

## Settings

Open from the menu bar. **General** (shortcuts, launch at login, accent color), **Models**, **Permissions**, **About**.

## Privacy

- No account, no server, no analytics, no telemetry.
- Selected text goes only to the model provider you choose. With Apple on-device or Ollama it never leaves your Mac.
- API keys are stored in the macOS Keychain.
- Nothing you select or type is written to disk. Settings live in the app's preferences; there is no history.
- Replace pastes through the clipboard only as a fallback, marks that paste as transient so clipboard managers skip it, and restores your clipboard afterward.
- In-app updates download only over HTTPS from this repository's Releases, and the new app's code signature and bundle id are checked before it replaces the old one.
- Enhancify is not sandboxed, because Accessibility cannot work inside the App Sandbox.

Found a security problem? Report it privately through a [security advisory](https://github.com/rahulsharmadesign/enhancify/security/advisories/new), not a public issue.

## Build from source

```bash
brew install xcodegen
git clone https://github.com/rahulsharmadesign/enhancify.git
cd enhancify
./scripts/make-signing-cert.sh   # once: a local certificate so Accessibility survives rebuilds
./scripts/install.sh             # build, sign, install to /Applications, launch
```

`./scripts/qa.sh` runs the static checks, build, and tests. CI runs it on every pull request.

**Release:** bump `MARKETING_VERSION` in `project.yml`, merge to `main`, then either push a `v<version>` tag or run **Actions → Release → Run workflow** on `main`. Either way the DMG is built and published to Releases.

## Support

Bugs and ideas: [open an issue](https://github.com/rahulsharmadesign/enhancify/issues). If Enhancify saves you time, [send a tip](https://razorpay.me/@rahulsharmadesign).

## License

[MIT](LICENSE) © 2026 Rahul Sharma
