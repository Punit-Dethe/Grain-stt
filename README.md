# Grain — The Open Voice Layer

> Speak anywhere you type. No lock-in, no subscription wall.

Grain is an open-source Windows desktop app that sits between your voice and your tools. Press a hotkey, speak, and your words land as clean text in whatever window has focus — or get sent straight to your AI of choice.

---

## What it does

**Two layers, both pluggable:**

| Layer | What it does | Backends |
|---|---|---|
| L1 — Transcription | Speech → raw text | Deepgram, AssemblyAI, Groq, Local Parakeet (on-device) |
| L2 — Processing | Raw text → clean text via LLM | OpenAI, Gemini, Groq, Cerebras, any OpenAI-compatible endpoint |

Both layers expose OpenAI-compatible endpoints so you can swap backends without changing anything else. Use a cloud API today, switch to a self-hosted model tomorrow.

**The widget:**  
A small pill appears at your cursor when you hold the hotkey. The left side pulses with your live voice level. Release — text is pasted. No window to switch to, no focus stolen.

**The router:**  
Grain watches quota, latency, and provider health. When one backend is rate-limited or down, it falls through to the next — invisibly.

---

## Features

- Configurable hotkeys for dictation and voice-to-AI
- Smart provider rotation with automatic fallback
- On-device transcription (Local Parakeet — no audio leaves your machine)
- Custom directive prompts per task
- Vocabulary dictionary for proper nouns and technical terms
- System tray — always available, never in the way
- Full settings console: providers, prompts, dictionary, routing config

---

## Getting started

### Download

Grab the latest release from the [Releases](../../releases) page. No installer needed — unzip and run `GrainSTT.exe`.

### Build from source

**Requirements:** Python 3.11+, Windows 11

```bash
git clone https://github.com/your-username/grain-stt.git
cd grain-stt
pip install -r requirements.txt
python -m open_voice_router.main
```

**Build EXE:**
```bash
pip install pyinstaller
python -m PyInstaller grain_stt.spec --noconfirm
```

---

## Project structure

```
open_voice_router/
  main.py              # Entry point
  app_controller.py    # Core orchestration
  router.py            # Provider routing engine
  models.py            # Data models & defaults
  services/            # STT + LLM service adapters
  storage/             # Settings persistence
  local_asr/           # On-device Parakeet integration
  ui/
    pill/              # Floating voice widget (QML)
    console/           # Settings console (QML)
website/               # Marketing site (deploy root for Vercel)
```

---

## Website

The `website/` folder is the marketing site, deployable to Vercel with the root set to `website/`.

---

## License

MIT — do what you want, keep the attribution.
