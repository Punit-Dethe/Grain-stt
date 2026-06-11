"""
Vendored Groxaxo/Parakeet TDT 0.6B v3 ASR server.

Source: https://github.com/groxaxo/parakeet-tdt-0.6b-v3-fastapi-openai
License: MIT (open source)

Vendored into Open Voice Router so users only need to install the ONNX model —
no external git clone or separate install step required.

Configuration via environment variables (set by LocalSTTManager):
  MODELS_DIR   — where onnx_asr stores/looks for model files
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

import os, sys, json, math, re, threading
import shutil
import uuid
import subprocess
import datetime
import wave
import numpy as np
from typing import List, Tuple, Optional
from werkzeug.utils import secure_filename

import flask
from flask import Flask, request, jsonify, Response
from waitress import serve
from pathlib import Path

# Allow env override of port and host
port = int(os.environ.get("PORT", port))
host = os.environ.get("HOST", host)

ROOT_DIR = str(Path(os.path.dirname(os.path.abspath(__file__))))
MODELS_DIR = os.environ.get("MODELS_DIR", os.path.join(ROOT_DIR, "models"))
os.environ["HF_HOME"] = MODELS_DIR
os.environ["HF_HUB_CACHE"] = MODELS_DIR
os.environ["HF_HUB_DISABLE_SYMLINKS_WARNING"] = "true"

# Honour the offline cache (R10.3): HF_HOME / HF_HUB_CACHE point at MODELS_DIR so
# onnx_asr / huggingface_hub resolve the model from the local snapshot. When the
# manager has set HF_HUB_OFFLINE / TRANSFORMERS_OFFLINE (on-demand load with the
# cache already present) we leave those flags untouched so no network HEAD request
# is issued for cache-freshness. We do NOT force offline here, so the initial
# install download path still works when the cache is absent.
_HF_OFFLINE = os.environ.get("HF_HUB_OFFLINE", "") in ("1", "true", "True")
_startup_marker(
    f"hf cache resolved (models_dir={MODELS_DIR!r}, offline={_HF_OFFLINE})"
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


def _detect_cpu_flags() -> set:
    flags = set()
    if sys.platform.startswith("linux"):
        try:
            with open("/proc/cpuinfo", "r", encoding="utf-8", errors="replace") as f:
                for line in f:
                    if line.lower().startswith("flags"):
                        _, value = line.split(":", 1)
                        flags.update(value.strip().lower().split())
        except OSError:
            pass
    return flags


CPU_FLAGS = _detect_cpu_flags()
CPU_OPTIMIZATION = {
    "available_logical_cpus": _get_available_logical_cpus(),
    "physical_cpus": _physical_cpu_count(),
    "avx2_available": "avx2" in CPU_FLAGS,
    "fma_available": "fma" in CPU_FLAGS,
}
default_ort_intra_threads = min(
    CPU_OPTIMIZATION["physical_cpus"], CPU_OPTIMIZATION["available_logical_cpus"]
)
CPU_OPTIMIZATION["ort_intra_op_threads"] = get_env_int(
    "PARAKEET_ORT_INTRA_THREADS", default_ort_intra_threads
)
CPU_OPTIMIZATION["ort_inter_op_threads"] = get_env_int("PARAKEET_ORT_INTER_THREADS", 1)
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


def build_session_options():
    """Build ORT SessionOptions tuned for fast load and efficient CPU inference.

    Uses ORT_ENABLE_EXTENDED rather than ORT_ENABLE_ALL.  The ALL level adds the
    NchwcTransformer (a Windows-specific memory-layout pass) which takes ~2-3 s on
    every cold start and whose output is never reused between process restarts because
    ORT's optimized_model_filepath is write-only — it is not read back automatically
    on subsequent sessions.  EXTENDED still applies operator fusion, constant folding,
    and all other generic optimisations, so inference quality and throughput are
    unchanged.
    """
    sess_options = ort.SessionOptions()
    sess_options.intra_op_num_threads = CPU_OPTIMIZATION["ort_intra_op_threads"]
    sess_options.inter_op_num_threads = CPU_OPTIMIZATION["ort_inter_op_threads"]
    sess_options.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
    sess_options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_EXTENDED
    sess_options.add_session_config_entry("session.set_denormal_as_zero", "1")
    sess_options.add_session_config_entry("session.intra_op.allow_spinning", "1")
    sess_options.add_session_config_entry("session.inter_op.allow_spinning", "0")
    return sess_options


def _load_model(hf_id: str, quantization, providers_to_try):
    """Load an onnx_asr model with production-tuned session options."""
    return onnx_asr.load_model(
        hf_id,
        quantization=quantization,
        providers=providers_to_try,
        sess_options=build_session_options(),
    ).with_timestamps()


def get_providers_to_try():
    available_providers = ort.get_available_providers()
    providers = []
    if "TensorrtExecutionProvider" in available_providers:
        providers.append("TensorrtExecutionProvider")
    if "CUDAExecutionProvider" in available_providers:
        providers.append("CUDAExecutionProvider")
    providers.append("CPUExecutionProvider")
    return available_providers, providers


MODEL_CONFIGS = {
    "parakeet-tdt-0.6b-v3": {
        "hf_id": "nemo-parakeet-tdt-0.6b-v3",
        "quantization": "int8",
        "description": "INT8 (fastest, default)",
    },
    "istupakov/parakeet-tdt-0.6b-v3-onnx": {
        "hf_id": "istupakov/parakeet-tdt-0.6b-v3-onnx",
        "quantization": None,
        "description": "FP32",
    },
    "grikdotnet/parakeet-tdt-0.6b-fp16": {
        "hf_id": "grikdotnet/parakeet-tdt-0.6b-fp16",
        "quantization": "fp16",
        "description": "FP16",
    },
}

model_cache = {}

# -----------------------------------------------------------------------
# Flask app — created HERE, before model loading, so Waitress can start
# in parallel with onnx_asr.load_model().  The /health endpoint returns
# 503 until _model_ready is set; the health poller in LocalSTTManager
# will not signal server_ready until it sees a 200.
# -----------------------------------------------------------------------

_model_ready = threading.Event()

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
        result = subprocess.run(command, capture_output=True, text=True, check=True)
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
                                timeout=SILENCE_DETECT_TIMEOUT)
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
        return jsonify({"status": "loading"}), 503
    return jsonify({"status": "healthy", "models": list(MODEL_CONFIGS.keys()), "default_model": "parakeet-tdt-0.6b-v3"})


@app.route("/docs")
def docs():
    return jsonify({"status": "ok", "info": "Parakeet TDT 0.6B V3 OpenAI-compatible ASR"})


def get_model(model_name):
    if model_name not in MODEL_CONFIGS:
        model_name = "parakeet-tdt-0.6b-v3"
    if model_name in model_cache:
        return model_cache[model_name]
    config = MODEL_CONFIGS[model_name]
    _, providers_to_try = get_providers_to_try()
    model = _load_model(config["hf_id"], config["quantization"], providers_to_try)
    model_cache[model_name] = model
    return model


@app.route("/v1/audio/transcriptions", methods=["POST"])
def transcribe_audio():
    if not _model_ready.is_set():
        return jsonify({"error": "Model is still loading"}), 503
    if "file" not in request.files:
        return jsonify({"error": "No file part in the request"}), 400
    file = request.files["file"]
    if not file or not file.filename:
        return jsonify({"error": "No file selected"}), 400

    model_name = request.form.get("model", "parakeet-tdt-0.6b-v3").lower()
    response_format = request.form.get("response_format", "json")

    if model_name not in MODEL_CONFIGS:
        model_name = "parakeet-tdt-0.6b-v3"

    model_to_use = get_model(model_name)
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
            result = subprocess.run(ffmpeg_command, capture_output=True, text=True)
            if result.returncode != 0:
                return jsonify({"error": "File conversion failed", "details": result.stderr}), 500
            temp_files_to_clean.append(target_wav_path)

        total_duration = (
            wav_info["duration"] if direct_waveform is not None
            else get_audio_duration(target_wav_path)
        )
        if total_duration == 0:
            return jsonify({"error": "Cannot process audio with 0 duration"}), 400

        chunk_paths = []
        split_points = []

        if total_duration > CHUNK_DURATION_SECONDS:
            silence_points = detect_silence_points(target_wav_path, total_duration=total_duration)
            if silence_points:
                split_points = find_optimal_split_points(total_duration, CHUNK_DURATION_SECONDS, silence_points)

        if split_points:
            chunk_boundaries = [0.0] + split_points + [total_duration]
            num_chunks = len(chunk_boundaries) - 1
        else:
            num_chunks = math.ceil(total_duration / CHUNK_DURATION_SECONDS)
            chunk_boundaries = [min(i * CHUNK_DURATION_SECONDS, total_duration) for i in range(num_chunks + 1)]

        chunk_durations = [chunk_boundaries[i + 1] - chunk_boundaries[i] for i in range(num_chunks)]

        if num_chunks > 1:
            for i in range(num_chunks):
                chunk_path = os.path.join(app.config["UPLOAD_FOLDER"], f"{unique_id}_chunk_{i}.wav")
                chunk_paths.append(chunk_path)
                temp_files_to_clean.append(chunk_path)
                chunk_command = [
                    "ffmpeg", "-nostdin", "-y", "-loglevel", "error",
                    "-ss", str(chunk_boundaries[i]), "-t", str(chunk_durations[i]),
                    "-i", target_wav_path, "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", chunk_path,
                ]
                subprocess.run(chunk_command, capture_output=True, text=True)
        else:
            chunk_paths.append(direct_waveform if direct_waveform is not None else target_wav_path)

        all_segments = []
        all_words = []
        cumulative_time_offset = 0.0

        def clean_text(text):
            if not text:
                return ""
            text = text.replace("▁", " ").strip()
            return re.sub(r"\s+", " ", text).replace(" '", "'")

        for i, chunk_path in enumerate(chunk_paths):
            result = model_to_use.recognize(chunk_path)
            if result and result.text:
                start_time = result.timestamps[0] if result.timestamps else 0
                end_time = result.timestamps[-1] if len(result.timestamps) > 1 else start_time + 0.1
                cleaned_text = clean_text(result.text)
                all_segments.append({
                    "start": start_time + cumulative_time_offset,
                    "end": end_time + cumulative_time_offset,
                    "segment": cleaned_text,
                })
                for j, (token, timestamp) in enumerate(zip(result.tokens, result.timestamps)):
                    word_end = result.timestamps[j + 1] if j < len(result.timestamps) - 1 else end_time
                    all_words.append({
                        "start": timestamp + cumulative_time_offset,
                        "end": word_end + cumulative_time_offset,
                        "word": token.replace("▁", " ").strip(),
                    })
            cumulative_time_offset += chunk_durations[i]

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
            })
        else:
            return jsonify({"text": full_text})

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
# bind + thread-pool setup (~1.6 s) overlaps with onnx_asr model load
# (~2.2 s).  Without this overlap the two phases were sequential, adding
# ~1.6 s to the total time-to-ready.  The /health endpoint returns 503
# until _model_ready is set, so the health poller never fires early.
# -----------------------------------------------------------------------

print(f"Open Voice Router — Local ASR Server")
print(f"Endpoint: POST http://{host}:{port}/v1/audio/transcriptions")

_waitress_thread = threading.Thread(
    target=lambda: serve(app, host=host, port=port, threads=threads),
    daemon=True,
    name="waitress",
)
_waitress_thread.start()
_startup_marker("waitress thread started (overlapping with model load)")

try:
    print("Initializing ONNX Runtime...")
    import onnx_asr
    import onnxruntime as ort

    _startup_marker("after imports (onnx_asr + onnxruntime)")

    available_providers, providers_to_try = get_providers_to_try()
    print(f"Providers: {providers_to_try}")

    _startup_marker("after session-options build")
    default_config = MODEL_CONFIGS["parakeet-tdt-0.6b-v3"]
    print("Loading Parakeet TDT 0.6B V3 INT8 model (downloading if needed)...")
    asr_model = _load_model(
        default_config["hf_id"],
        default_config["quantization"],
        providers_to_try,
    )
    model_cache["parakeet-tdt-0.6b-v3"] = asr_model
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
