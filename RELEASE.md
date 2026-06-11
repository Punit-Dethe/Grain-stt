# Grain v1.0.0 — First Release

**The open voice layer for your desktop.**  
Hold a key, speak, release — your words are already text, pasted where your cursor lives.

---

## Download

**[GrainSTT-Setup.exe](https://github.com/Punit-Dethe/Grain-stt/releases/download/v1.0.0/GrainSTT-Setup.exe)**  
Windows 11 · 64-bit · Free · MIT License

---

## What's in this release

### Near real-time transcription
Unlike every other open-source tool, Grain does not record first and transcribe after. It transcribes as you speak using rolling windows, overlap, and voice-activity detection. Release the key and your text is already there — real-world delay is rarely even half a second.

### Two OpenAI-compatible layers
Both the transcription layer and the processing layer expose OpenAI-compatible endpoints. Bring any hosted API, self-hosted server, or on-device model — swap backends without changing anything about your workflow.

**Layer 1 — Transcription**
- Deepgram, AssemblyAI, Groq (cloud)
- Local Parakeet 0.6B — fully on-device, no audio leaves your machine

**Layer 2 — Processing**
- Gemini, Groq, Cerebras, OpenAI, any OpenAI-compatible endpoint
- Custom directive prompts per task
- Vocabulary dictionary for proper nouns and technical terms (e.g. LinkedIn, GitHub, ChatGPT)

### Smart provider rotation
Add every API key you have — including multiple keys from the same provider. Grain rotates across them based on daily quota, latency, and context length. When one backend is rate-limited or down, it falls through to the next automatically.

### Wake-loading local model
The local Parakeet model loads the moment you press the hotkey and unloads on your schedule (instant, 5 min, 10 min, or never). Idle memory footprint is ~100 MB with the UI closed, ~150 MB with the full console open. The model itself uses ~1 GB only while actively transcribing.

### Floating pill widget
A small always-on-top pill appears at your cursor when you hold the hotkey. The left side pulses with your live voice level so you know it is listening. Nothing else gets in the way — no window to switch to, no focus stolen.

### Two hotkey modes
- **Dictation** — speech is cleaned up and pasted as text
- **Voice-to-AI** — speech goes through your configured processing layer with your directive prompt

### Full settings console
- Provider configuration for both layers (BYOK)
- Hotkey assignment
- Microphone selection
- Directive prompts — write and save multiple prompts, switch between them
- Vocabulary dictionary
- Model unload timer
- Smart rotation toggle
- Light and dark theme
- Telemetry log viewer

### System integration
- Minimises to the system tray — always available, never in the way
- Launch on boot option
- Audio confirmation sounds on trigger
- Fully decoupled UI — close the console and the voice layer keeps running

---

## System requirements

| | |
|---|---|
| OS | Windows 11 64-bit |
| RAM | 4 GB minimum (8 GB recommended for local model) |
| Python | Not required — fully self-contained installer |

---

## Installation

Run `GrainSTT-Setup.exe` and follow the installer. Grain installs to `C:\Program Files\Grain` and appears in Apps & Features with a proper uninstaller. No account required.

Your API keys and settings are stored in `%APPDATA%\open-voice-router` and are not touched by the uninstaller.

---

## Coming soon

- **Grain Agent** — select any text anywhere on your desktop, press a shortcut, and ask anything: summarise it, restructure it, draft an email, or just ask a question. Routes to the smartest model in your configured stack automatically.
- Expanded local model support (Moonshine-class lightweight tier)
- Additional cloud STT providers

---

## License

MIT — see [LICENSE](LICENSE) for details.
