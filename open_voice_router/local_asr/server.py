"""
Open Voice Router — local ASR sidecar server.

Engine-agnostic HTTP layer exposing an OpenAI-compatible
``POST /v1/audio/transcriptions`` endpoint. The model to serve is selected via
the MODEL_ID environment variable (set by LocalSTTManager) and resolved
through the model registry (registry.py); the matching engine wrapper
(engines/) performs inference. One process serves exactly one model.

Originally based on Groxaxo/parakeet-tdt-0.6b-v3-fastapi-openai (MIT).

Configuration via environment variables (set by LocalSTTManager):
  MODEL_ID     — registry id of the model to load (default: registry default)
  MODELS_DIR   — where model files are stored/looked up (HF cache layout)
  PORT         — HTTP port (default 5092)
  HOST         — bind address (default 0.0.0.0)
"""
from __future__ import annotations

host = "0.0.0.0"
port = 5092
CHUNK_MINUTE = 1.5

SILENCE_THRESHOLD = "-40dB"
SILENCE_MIN_DURATION = 0.5
SILENCE_SEARCH_WINDOW = 30.0
SILENCE_DETECT_TIMEOUT = 300
MIN_SPLIT_GAP = 5.0
MAX_WAITRESS_THREADS = 8
WAITRESS_CPU_DIVISOR = 2

import sys
sys.stdout = sys.stderr

import time

# --- Startup latency instrumentation (R10.1) -------------------------------
# Monotonic time captured as early as possible so the "process start" marker
# reflects the moment this script began executing. Markers are printed to
# stdout, which LocalSTTManager redirects to server.log, so each Load_Latency
# contributor in the design's investigation table is measurable from the log.
_STARTUP_T0 = time.monotonic()


def _startup_marker(label: str) -> None:
    """Print a monotonic startup marker to server.log (via stdout)."""
    elapsed_ms = (time.monotonic() - _STARTUP_T0) * 1000.0
    print(
        f"[startup] {label}: +{elapsed_ms:.1f} ms "
        f"(monotonic={time.monotonic():.6f})",
        flush=True,
    )


_startup_marker("process start")

import os, json, math, re, threading
import shutil
import uuid
import subprocess
import datetime

# Windowless child processes on Windows — ffmpeg/ffprobe are console apps and
# would each flash a command-prompt window when called from this hidden server.
_NO_WINDOW = 0x08000000 if sys.platform == "win32" else 0
import wave
import numpy as np
from typing import List, Tuple, Optional
from werkzeug.utils import secure_filename

import flask
from flask import Flask, request, jsonify, Response
from waitress import serve
from pathlib import Path

# Sibling modules (registry, engines) — this script runs standalone inside the
# sidecar venv, so its own directory must be importable.
ROOT_DIR = str(Path(os.path.dirname(os.path.abspath(__file__))))
if ROOT_DIR not in sys.path:
    sys.path.insert(0, ROOT_DIR)

import registry
from engines import create_engine

# Allow env override of port and host
port = int(os.environ.get("PORT", port))
host = os.environ.get("HOST", host)

MODELS_DIR = os.environ.get("MODELS_DIR", os.path.join(ROOT_DIR, "models"))
os.environ["HF_HOME"] = MODELS_DIR
os.environ["HF_HUB_CACHE"] = MODELS_DIR
os.environ["HF_HUB_DISABLE_SYMLINKS_WARNING"] = "true"

# Honour the offline cache (R10.3): HF_HOME / HF_HUB_CACHE point at MODELS_DIR so
# the engines resolve models from the local snapshot. When the manager has set
# HF_HUB_OFFLINE / TRANSFORMERS_OFFLINE (on-demand load with the cache already
# present) we leave those flags untouched so no network HEAD request is issued
# for cache-freshness. We do NOT force offline here, so the initial install
# download path still works when the cache is absent.
_HF_OFFLINE = os.environ.get("HF_HUB_OFFLINE", "") in ("1", "true", "True")

MODEL_SPEC = registry.get_model(os.environ.get("MODEL_ID"))
_startup_marker(
    f"model resolved (id={MODEL_SPEC.id!r}, engine={MODEL_SPEC.engine!r}, "
    f"models_dir={MODELS_DIR!r}, offline={_HF_OFFLINE})"
)

os.makedirs(MODELS_DIR, exist_ok=True)
if sys.platform == "win32":
    os.environ["PATH"] = ROOT_DIR + f";{ROOT_DIR}/ffmpeg;" + os.environ["PATH"]


def get_env_int(name: str, default: int, minimum: int = 1) -> int:
    try:
        return max(minimum, int(os.environ.get(name, default)))
    except (TypeError, ValueError):
        fallback = max(minimum, default)
        print(f"Warning: Invalid {name} value; using {fallback}")
        return fallback


def _get_available_logical_cpus() -> int:
    try:
        return len(os.sched_getaffinity(0))
    except (AttributeError, OSError):
        cpu_count = os.cpu_count()
        return cpu_count if cpu_count else 1


def _physical_cpu_count() -> int:
    # psutil gives physical-core count; fall back to logical if unavailable.
    try:
        import psutil as _psutil
        cpu_count = _psutil.cpu_count(logical=False)
        if cpu_count and cpu_count > 0:
            return cpu_count
    except Exception:
        pass
    return _get_available_logical_cpus()


CPU_OPTIMIZATION = {
    "available_logical_cpus": _get_available_logical_cpus(),
    "physical_cpus": _physical_cpu_count(),
}
# Reserve one core for the HOST app's UI thread. The Pill recording widget
# animates via per-frame JavaScript (rollDots) on the main app's Qt GUI thread.
# If this engine claims EVERY core — and ONNX Runtime's worker threads spin
# (busy-wait) at 100% — the GUI thread has no core to run on during model load
# and the Pill visibly freezes. Lowering the subprocess priority (done at spawn)
# cannot help when every core is saturated, and moving the spawn off-thread
# cannot help because the animation itself lives on the starved GUI thread.
# Leaving one core free guarantees the host's GUI thread is always schedulable,
# so the Pill keeps animating no matter how busy inference is. Costs at most one
# thread of engine throughput — imperceptible for streaming dictation, where a
# ~1.5 s chunk still transcribes far faster than real time. Override via
# ASR_ENGINE_THREADS if a headless/batch deployment wants every core.
_engine_thread_budget = min(
    CPU_OPTIMIZATION["physical_cpus"], CPU_OPTIMIZATION["available_logical_cpus"]
)
default_engine_threads = max(1, _engine_thread_budget - 1)
ENGINE_CPU_THREADS = get_env_int("ASR_ENGINE_THREADS", default_engine_threads)
default_waitress_threads = min(
    MAX_WAITRESS_THREADS,
    max(1, CPU_OPTIMIZATION["available_logical_cpus"] // WAITRESS_CPU_DIVISOR),
)
threads = get_env_int("PARAKEET_WAITRESS_THREADS", default_waitress_threads)

for _thread_env in (
    "OMP_NUM_THREADS", "MKL_NUM_THREADS", "OPENBLAS_NUM_THREADS",
    "NUMEXPR_NUM_THREADS", "VECLIB_MAXIMUM_THREADS",
):
    os.environ.setdefault(_thread_env, "1")


# -----------------------------------------------------------------------
# Flask app — created HERE, before model loading, so Waitress can start
# in parallel with the engine load.  The /health endpoint returns 503
# until _model_ready is set; the health poller in LocalSTTManager
# will not signal server_ready until it sees a 200.
# -----------------------------------------------------------------------

_model_ready = threading.Event()
_engine = None  # set by the startup code at the bottom of this file

app = Flask(__name__)
import tempfile as _tempfile
_default_temp = os.path.join(_tempfile.gettempdir(), "open-voice-router-uploads")
app.config["UPLOAD_FOLDER"] = os.environ.get("TEMP_DIR", _default_temp)
os.makedirs(app.config["UPLOAD_FOLDER"], exist_ok=True)
app.config["MAX_CONTENT_LENGTH"] = 2000 * 1024 * 1024
progress_tracker = {}


def get_audio_duration(file_path):
    wav_info = get_wav_info(file_path)
    if wav_info is not None:
        return wav_info["duration"]
    command = ["ffprobe", "-v", "error", "-show_entries", "format=duration",
               "-of", "default=noprint_wrappers=1:nokey=1", file_path]
    try:
        result = subprocess.run(command, capture_output=True, text=True, check=True,
                                creationflags=_NO_WINDOW)
        return float(result.stdout)
    except Exception:
        return 0.0


def get_wav_info(file_path):
    try:
        with wave.open(file_path, "rb") as wf:
            return {
                "duration": wf.getnframes() / wf.getframerate() if wf.getframerate() else 0.0,
                "sample_rate": wf.getframerate(),
                "channels": wf.getnchannels(),
                "sample_width": wf.getsampwidth(),
                "compression": wf.getcomptype(),
            }
    except Exception:
        return None


def load_pcm_wav_as_16k_float(file_path, wav_info):
    # audioop is deprecated in Python 3.13; import lazily to keep it off the
    # startup path and to isolate the deprecation warning to this function.
    import audioop  # noqa: PLC0415
    if wav_info["compression"] != "NONE":
        return None
    sample_width = wav_info["sample_width"]
    channels = wav_info["channels"]
    if sample_width not in (1, 2, 3, 4) or channels not in (1, 2):
        return None
    try:
        with wave.open(file_path, "rb") as wf:
            pcm = wf.readframes(wf.getnframes())
        if channels == 2:
            pcm = audioop.tomono(pcm, sample_width, 0.5, 0.5)
        if wav_info["sample_rate"] != 16000:
            pcm, _ = audioop.ratecv(pcm, sample_width, 1, wav_info["sample_rate"], 16000, None)
        if sample_width == 1:
            return (np.frombuffer(pcm, dtype=np.uint8).astype(np.float32) - 128.0) / 128.0
        if sample_width == 2:
            return np.frombuffer(pcm, dtype="<i2").astype(np.float32) / 32768.0
        if sample_width == 4:
            return np.frombuffer(pcm, dtype="<i4").astype(np.float32) / 2147483648.0
        pcm_16 = audioop.lin2lin(pcm, sample_width, 2)
        return np.frombuffer(pcm_16, dtype="<i2").astype(np.float32) / 32768.0
    except Exception:
        return None


def detect_silence_points(file_path, silence_thresh=SILENCE_THRESHOLD,
                           silence_duration=SILENCE_MIN_DURATION, total_duration=None):
    if not os.path.exists(file_path):
        return []
    command = ["ffmpeg", "-hide_banner", "-nostats", "-i", file_path,
               "-af", f"silencedetect=noise={silence_thresh}:d={silence_duration}",
               "-f", "null", "-"]
    try:
        result = subprocess.run(command, capture_output=True, text=True,
                                timeout=SILENCE_DETECT_TIMEOUT,
                                creationflags=_NO_WINDOW)
        silence_points = []
        silence_start = None
        for line in result.stderr.splitlines():
            if "silence_start:" in line:
                try:
                    silence_start = float(line.split("silence_start:")[1].split()[0])
                except Exception:
                    silence_start = None
            elif "silence_end:" in line and silence_start is not None:
                try:
                    silence_end = float(line.split("silence_end:")[1].split()[0])
                    silence_points.append((silence_start, silence_end))
                    silence_start = None
                except Exception:
                    pass
        if silence_start is not None and total_duration is not None:
            silence_points.append((silence_start, total_duration))
        return silence_points
    except Exception:
        return []


def find_optimal_split_points(total_duration, target_chunk_duration, silence_points,
                               search_window=SILENCE_SEARCH_WINDOW, min_gap=MIN_SPLIT_GAP):
    if not silence_points or total_duration <= target_chunk_duration:
        return []
    split_points = []
    prev = 0.0
    num_chunks = math.ceil(total_duration / target_chunk_duration)
    for i in range(1, num_chunks):
        target_time = i * target_chunk_duration
        search_start = max(0.0, target_time - search_window)
        search_end = min(total_duration, target_time + search_window)
        candidates = [(s, e) for (s, e) in silence_points if s <= search_end and e >= search_start]
        chosen = None
        if candidates:
            candidates_sorted = sorted(candidates, key=lambda r: abs(((r[0] + r[1]) / 2.0) - target_time))
            for start, end in candidates_sorted:
                sp = (start + end) / 2.0
                if sp > prev + min_gap and sp <= total_duration - min_gap:
                    chosen = sp
                    break
        if chosen is None:
            chosen = max(prev + min_gap, min(target_time, total_duration - min_gap))
            if chosen > total_duration:
                chosen = None
        split_points.append(chosen)
        prev = chosen if chosen is not None else prev
    return [sp for sp in split_points if sp is not None]


def format_srt_time(seconds):
    delta = datetime.timedelta(seconds=seconds)
    s = str(delta)
    if "." in s:
        parts = s.split(".")
        integer_part = parts[0]
        fractional_part = parts[1][:3]
    else:
        integer_part = s
        fractional_part = "000"
    if len(integer_part.split(":")) == 2:
        integer_part = "0:" + integer_part
    return f"{integer_part},{fractional_part}"


def segments_to_srt(segments):
    lines = []
    for i, seg in enumerate(segments):
        text = seg["segment"].strip()
        if text:
            lines += [str(i + 1), f"{format_srt_time(seg['start'])} --> {format_srt_time(seg['end'])}", text, ""]
    return "\n".join(lines)


def segments_to_vtt(segments):
    lines = ["WEBVTT", ""]
    for seg in segments:
        text = seg["segment"].strip()
        if text:
            lines += [f"{format_srt_time(seg['start']).replace(',', '.')} --> {format_srt_time(seg['end']).replace(',', '.')}", text, ""]
    return "\n".join(lines)


@app.route("/health")
def health():
    if not _model_ready.is_set():
        return jsonify({"status": "loading", "model": MODEL_SPEC.id}), 503
    return jsonify({
        "status": "healthy",
        "model": MODEL_SPEC.id,
        "engine": MODEL_SPEC.engine,
        "models": [MODEL_SPEC.id],
        "default_model": MODEL_SPEC.id,
    })


@app.route("/docs")
def docs():
    return jsonify({
        "status": "ok",
        "info": f"Open Voice Router local ASR — {MODEL_SPEC.display_name} "
                f"({MODEL_SPEC.engine}), OpenAI-compatible",
    })


def clean_text(text):
    if not text:
        return ""
    text = text.replace("▁", " ").strip()
    return re.sub(r"\s+", " ", text).replace(" '", "'")


@app.route("/v1/audio/transcriptions", methods=["POST"])
def transcribe_audio():
    if not _model_ready.is_set() or _engine is None:
        return jsonify({"error": "Model is still loading"}), 503
    if "file" not in request.files:
        return jsonify({"error": "No file part in the request"}), 400
    file = request.files["file"]
    if not file or not file.filename:
        return jsonify({"error": "No file selected"}), 400

    # One process serves one model; a mismatched request is logged, not an
    # error — OpenAI clients routinely send a model name the server maps.
    requested_model = (request.form.get("model") or "").lower()
    if requested_model and requested_model != MODEL_SPEC.id.lower():
        print(f"Note: requested model {requested_model!r}; serving {MODEL_SPEC.id!r}")
    response_format = request.form.get("response_format", "json")

    original_filename = secure_filename(file.filename)
    unique_id = str(uuid.uuid4())
    temp_original_path = os.path.join(app.config["UPLOAD_FOLDER"], f"{unique_id}_{original_filename}")
    target_wav_path = os.path.join(app.config["UPLOAD_FOLDER"], f"{unique_id}.wav")
    temp_files_to_clean = []

    try:
        file.save(temp_original_path)
        temp_files_to_clean.append(temp_original_path)

        CHUNK_DURATION_SECONDS = CHUNK_MINUTE * 60
        wav_info = get_wav_info(temp_original_path)
        direct_waveform = (
            load_pcm_wav_as_16k_float(temp_original_path, wav_info)
            if wav_info is not None and wav_info["duration"] <= CHUNK_DURATION_SECONDS
            else None
        )
        can_use_original_wav = (
            wav_info is not None
            and wav_info["sample_rate"] == 16000
            and wav_info["channels"] == 1
            and wav_info["compression"] == "NONE"
        )

        if can_use_original_wav:
            target_wav_path = temp_original_path
        elif direct_waveform is None:
            ffmpeg_command = [
                "ffmpeg", "-nostdin", "-y", "-loglevel", "error",
                "-i", temp_original_path, "-ac", "1", "-ar", "16000",
                "-c:a", "pcm_s16le", target_wav_path,
            ]
            result = subprocess.run(ffmpeg_command, capture_output=True, text=True,
                                    creationflags=_NO_WINDOW)
            if result.returncode != 0:
                return jsonify({"error": "File conversion failed", "details": result.stderr}), 500
            temp_files_to_clean.append(target_wav_path)

        total_duration = (
            wav_info["duration"] if direct_waveform is not None
            else get_audio_duration(target_wav_path)
        )
        if total_duration == 0:
            return jsonify({"error": "Cannot process audio with 0 duration"}), 400

        # ------------------------------------------------------------------
        # Build the list of waveforms to transcribe. Short uploads (the app's
        # streaming chunks are <=25 s) go through as a single array; long
        # uploads are split at silence into engine-sized pieces.
        # ------------------------------------------------------------------
        waveforms: list = []          # np.float32 mono 16 kHz arrays
        piece_durations: list = []    # seconds, parallel to waveforms

        if direct_waveform is not None and total_duration <= CHUNK_DURATION_SECONDS:
            waveforms.append(direct_waveform)
            piece_durations.append(total_duration)
        else:
            split_points = []
            if total_duration > CHUNK_DURATION_SECONDS:
                silence_points = detect_silence_points(target_wav_path, total_duration=total_duration)
                if silence_points:
                    split_points = find_optimal_split_points(total_duration, CHUNK_DURATION_SECONDS, silence_points)

            if split_points:
                chunk_boundaries = [0.0] + split_points + [total_duration]
                num_chunks = len(chunk_boundaries) - 1
            else:
                num_chunks = max(1, math.ceil(total_duration / CHUNK_DURATION_SECONDS))
                chunk_boundaries = [min(i * CHUNK_DURATION_SECONDS, total_duration) for i in range(num_chunks + 1)]

            chunk_durations = [chunk_boundaries[i + 1] - chunk_boundaries[i] for i in range(num_chunks)]

            if num_chunks == 1:
                # No real split needed: target_wav_path is already 16 kHz mono
                # PCM, so load it directly rather than spawning a redundant
                # ffmpeg pass to re-extract the whole file as a single chunk.
                single_info = get_wav_info(target_wav_path)
                single_wave = (
                    load_pcm_wav_as_16k_float(target_wav_path, single_info)
                    if single_info is not None else None
                )
                if single_wave is not None:
                    waveforms.append(single_wave)
                    piece_durations.append(chunk_durations[0])
            else:
                for i in range(num_chunks):
                    piece_path = os.path.join(app.config["UPLOAD_FOLDER"], f"{unique_id}_chunk_{i}.wav")
                    temp_files_to_clean.append(piece_path)
                    chunk_command = [
                        "ffmpeg", "-nostdin", "-y", "-loglevel", "error",
                        "-ss", str(chunk_boundaries[i]), "-t", str(chunk_durations[i]),
                        "-i", target_wav_path, "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", piece_path,
                    ]
                    subprocess.run(chunk_command, capture_output=True, text=True,
                                   creationflags=_NO_WINDOW)
                    piece_info = get_wav_info(piece_path)
                    piece_wave = (
                        load_pcm_wav_as_16k_float(piece_path, piece_info)
                        if piece_info is not None else None
                    )
                    if piece_wave is not None:
                        waveforms.append(piece_wave)
                        piece_durations.append(chunk_durations[i])

        # ------------------------------------------------------------------
        # Transcribe each piece via the engine; offset times onto the upload's
        # own timeline.
        # ------------------------------------------------------------------
        all_segments = []
        all_words = []
        cumulative_time_offset = 0.0

        for piece_wave, piece_duration in zip(waveforms, piece_durations):
            engine_result = _engine.transcribe(piece_wave)
            text = clean_text(engine_result.text)
            if text:
                if engine_result.words:
                    seg_start = engine_result.words[0]["start"]
                    seg_end = engine_result.words[-1]["end"]
                else:
                    seg_start, seg_end = 0.0, piece_duration
                all_segments.append({
                    "start": seg_start + cumulative_time_offset,
                    "end": seg_end + cumulative_time_offset,
                    "segment": text,
                })
                for w in engine_result.words:
                    all_words.append({
                        "word": w["word"],
                        "start": round(w["start"] + cumulative_time_offset, 3),
                        "end": round(w["end"] + cumulative_time_offset, 3),
                    })
            cumulative_time_offset += piece_duration

        full_text = " ".join(seg["segment"] for seg in all_segments)

        if response_format == "srt":
            return Response(segments_to_srt(all_segments), mimetype="text/plain")
        elif response_format == "vtt":
            return Response(segments_to_vtt(all_segments), mimetype="text/plain")
        elif response_format == "text":
            return Response(full_text, mimetype="text/plain")
        elif response_format == "verbose_json":
            return jsonify({
                "task": "transcribe", "language": "english",
                "duration": total_duration, "text": full_text,
                "segments": [{"id": idx, "start": s["start"], "end": s["end"], "text": s["segment"]}
                              for idx, s in enumerate(all_segments)],
                "words": all_words,
            })
        else:
            return jsonify({"text": full_text, "words": all_words})

    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({"error": "Internal server error", "details": str(e)}), 500
    finally:
        for f_path in temp_files_to_clean:
            if os.path.exists(f_path):
                try:
                    os.remove(f_path)
                except OSError:
                    pass


# -----------------------------------------------------------------------
# Startup — Waitress starts in a background thread immediately so its
# bind + thread-pool setup (~1.6 s) overlaps with the engine's model load
# (~2.2 s for Parakeet INT8).  Without this overlap the two phases were
# sequential, adding ~1.6 s to the total time-to-ready.  The /health
# endpoint returns 503 until _model_ready is set, so the health poller
# never fires early.
# -----------------------------------------------------------------------

print("Open Voice Router — Local ASR Server")
print(f"Model: {MODEL_SPEC.display_name} ({MODEL_SPEC.id}, engine={MODEL_SPEC.engine})")
print(f"Endpoint: POST http://{host}:{port}/v1/audio/transcriptions")

_waitress_thread = threading.Thread(
    target=lambda: serve(app, host=host, port=port, threads=threads),
    daemon=True,
    name="waitress",
)
_waitress_thread.start()
_startup_marker("waitress thread started (overlapping with model load)")

try:
    print(f"Initializing {MODEL_SPEC.engine} engine...")
    _engine = create_engine(
        MODEL_SPEC, cpu_threads=ENGINE_CPU_THREADS, models_dir=MODELS_DIR
    )
    _startup_marker("after engine construction (imports deferred to load)")
    print(f"Loading model {MODEL_SPEC.id} (downloading if needed)...")
    _engine.load()
    _startup_marker("after model load")
    print("Model loaded.")
    _model_ready.set()
    _startup_marker("server ready (accepting requests)")
except Exception as e:
    print(f"Model loading failed: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)

_waitress_thread.join()
