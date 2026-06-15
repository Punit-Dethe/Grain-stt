# Grain — Voice, Text, and AI for Your Desktop

> Press a shortcut. Speak. Your words land wherever you're typing — clean, fast, and processed the way you want.

Grain is an open-source Windows desktop app that puts speech-to-text and AI one keystroke away. It stays in the background consuming almost nothing, loads what it needs on demand, and gets out of the way the moment you're done.

---

## What Grain does

You speak. Grain decides what to do with it based on which shortcut you use to stop.

```
Start recording  →  Stop normally    =  Plain transcription
Start recording  →  Stop with AI key =  AI-processed output
```

Both modes work in real-time (rolling transcription as you speak) and batch (record then transcribe). You choose per session by which start shortcut you press.

---

## Features

### Transcription
- **Real-time mode** — rolling windows, text appears as you speak
- **Batch mode** — records first, transcribes when you stop; better for lower-end hardware and smaller models
- **On-device transcription** — Parakeet TDT 0.6B v2, no audio ever leaves your machine
- **Cloud STT** — Deepgram, AssemblyAI, Groq Whisper, or any compatible endpoint

### AI Processing
- **Prompt profiles** — cycle with `Alt + ←` / `Alt + →` during recording; pick an intent (Email, Meeting Notes, Research, Translation, custom) before you finish speaking
- **Grain Assist** — `Ctrl+Shift+G` selects text, you give an instruction, AI acts on it; works without selection too, as a general chat
- **Multi-provider LLM** — OpenAI, Gemini, Groq, Cerebras, Mistral, Anthropic, OpenRouter, NVIDIA NIM, or any OpenAI-compatible endpoint

### Smart Routing
- Run multiple accounts or providers simultaneously
- Grain rotates requests across them, watching live quota and rate-limit headers
- When one is rate-limited or slow, the next takes over — invisibly

### Always-on, Never Heavy
- ~100 MB base footprint when idle with cloud providers
- Models load on demand, unload automatically after inactivity (configurable: 5 min / 10 min / 15 min / never)
- Floating pill widget appears at your cursor during recording — no window to switch to
- System tray entry always available

### Configuration
- **Quick Panel** — fast access to model switching, audio controls, history, and common settings
- **Advanced Panel** — full provider management, routing config, dictionary, prompt profiles, hotkeys; independent light/dark theme
- **Dictionary** — teach Grain names, domain terms, and corrections that persist across sessions
- **First-run wizard** — guided mic setup, model selection, and provider config on fresh install

---

## Getting started

### Download

Grab the latest installer from the [Releases](../../releases) page and run `GrainSTT-Setup.exe`.

### Build from source

**Requirements:** Python 3.11, Windows 10/11

```bash
git clone https://github.com/Punit-Dethe/Grain-stt.git
cd Grain-stt
pip install -r requirements.txt
python -m open_voice_router.main
```

**Build the EXE + installer:**
```bash
# PyInstaller
pyinstaller grain_stt.spec --noconfirm

# Inno Setup (requires Inno Setup 6 installed)
iscc installer.iss
```

---

## Project layout

```
open_voice_router/
  main.py              # Entry point + window lifecycle
  app_controller.py    # Orchestration (hotkeys, audio, routing)
  models.py            # Data models and provider presets
  services/            # STT + LLM adapters, smart rotation
  storage/             # Settings and credential persistence
  local_asr/           # On-device Parakeet integration
  ui/
    pill/              # Floating recording widget (QML)
    console/           # Quick Panel and Advanced Panel (QML)
    onboarding/        # First-run wizard (QML)
website/               # Marketing site (Vercel, root = website/)
```

---

## Architecture

Grain is built on **PySide6 + QML** with a Python backend. A few design choices worth knowing if you want to contribute:

- **Audio pipeline** — sounddevice feeds a rolling buffer; real-time mode chunks audio into overlapping windows and streams partial results; batch mode accumulates the full clip then transcribes once.
- **Provider abstraction** — all STT and LLM backends implement a common async interface. Every LLM backend speaks the OpenAI chat completions format, so adding a new provider is one entry in `PROVIDER_PRESETS` plus (if it needs special auth) a small adapter.
- **Smart rotation** — the router reads `X-RateLimit-*` response headers and 429 bodies to maintain per-provider cooldown windows. Fallback order is determined at runtime from live state, not a static priority list.
- **Window lifecycle** — QML engines are created and fully destroyed (collectGarbage → clearComponentCache → deleteLater → EmptyWorkingSet) when windows close, keeping idle RAM near baseline. The pill, assistant, and onboarding wizard each run in their own throwaway engine.
- **Frozen build** — PyInstaller with `grain_stt.spec`; asset paths use `sys._MEIPASS` in frozen context.

---

## License

MIT — do what you want, keep the attribution.
