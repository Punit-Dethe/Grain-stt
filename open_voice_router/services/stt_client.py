"""STTClient — speech-to-text via provider-specific adapters.

Supports:
- Deepgram  (api.deepgram.com)   — native Deepgram v1/listen API
- AssemblyAI (api.assemblyai.com) — native AssemblyAI v2 async API
- Generic fallback               — OpenAI-compatible /v1/audio/transcriptions

Every adapter returns a normalized :class:`TranscriptionResult` — the plain
transcript plus optional word-level timings. Word timings power the
time-based overlap dedup in the streaming path; adapters that cannot provide
them return ``words=None`` and the assembler falls back to text merging.

Implements Requirements 6.1, 6.2.
"""

from __future__ import annotations

import asyncio
from typing import TYPE_CHECKING

from open_voice_router.exceptions import ProviderError
from open_voice_router.models import ProviderConfig, TranscriptionResult, WordTiming

if TYPE_CHECKING:  # httpx is imported lazily — it costs ~19 MB of RAM and is
    import httpx   # only needed while a transcription request is in flight.

# ---------------------------------------------------------------------------
# Named provider presets (kept for reference / UI pre-fill)
# ---------------------------------------------------------------------------

STT_PRESETS: dict[str, dict] = {
    "deepgram": {
        "name": "Deepgram",
        "base_url": "https://api.deepgram.com",
        "model": "nova-3",
    },
    "assemblyai": {
        "name": "AssemblyAI",
        "base_url": "https://api.assemblyai.com",
        "model": "best",
    },
}

# Timeout parameters as plain floats; the httpx.Timeout objects are built
# lazily inside transcribe() so importing this module never pulls in httpx.
_STT_READ_TIMEOUT_S = 60.0
_STT_CONNECT_TIMEOUT_S = 10.0
# Local STT runs a synchronous ONNX model that can take a while on a long
# recording (it silence-splits and transcribes each segment). Give localhost a
# much more generous read timeout so long utterances never time out.
_LOCAL_READ_TIMEOUT_S = 300.0
_LOCAL_CONNECT_TIMEOUT_S = 5.0
# AssemblyAI async polling deadline (seconds).
_ASSEMBLYAI_POLL_DEADLINE_S = 60.0


def _is_local(provider: ProviderConfig) -> bool:
    base = (provider.base_url or "").lower()
    return "127.0.0.1" in base or "localhost" in base


def _parse_words(raw: object) -> tuple[WordTiming, ...] | None:
    """Parse an OpenAI-style ``words`` array into WordTiming tuples.

    Returns None when the payload is missing or malformed — word timings are
    an enhancement, never a hard requirement.
    """
    if not isinstance(raw, list) or not raw:
        return None
    words: list[WordTiming] = []
    try:
        for item in raw:
            text = str(item["word"]).strip()
            if not text:
                continue
            words.append(
                WordTiming(word=text, start=float(item["start"]), end=float(item["end"]))
            )
    except (KeyError, TypeError, ValueError):
        return None
    return tuple(words) or None


# ---------------------------------------------------------------------------
# Provider-specific adapters
# ---------------------------------------------------------------------------


async def _transcribe_deepgram(
    client: httpx.AsyncClient,
    provider: ProviderConfig,
    audio: bytes,
    api_key: str | None,
) -> TranscriptionResult:
    """POST raw WAV bytes to Deepgram's /v1/listen endpoint."""
    url = f"{provider.base_url.rstrip('/')}/v1/listen"
    params = {
        "model": provider.model or "nova-3",
        "punctuate": "true",
        # smart_format removed — it can trim trailing incomplete words when
        # the user stops mid-sentence, causing the last few words to be dropped.
    }
    headers = {
        "Authorization": f"Token {api_key or ''}",
        "Content-Type": "audio/wav",
    }
    response = await client.post(url, content=audio, params=params, headers=headers)
    response.raise_for_status()
    data = response.json()
    try:
        alternative = data["results"]["channels"][0]["alternatives"][0]
        transcript = alternative["transcript"]
    except (KeyError, IndexError, TypeError) as exc:
        raise ProviderError(
            f"Deepgram response missing expected structure: {exc}. Response: {data}"
        ) from exc
    # Deepgram always includes word timings — pass them through.
    words = _parse_words(alternative.get("words"))
    # Empty transcript is valid (silence) — return it as-is
    return TranscriptionResult(text=transcript, words=words)


async def _transcribe_assemblyai(
    client: httpx.AsyncClient,
    provider: ProviderConfig,
    audio: bytes,
    api_key: str | None,
) -> TranscriptionResult:
    """Upload WAV bytes to AssemblyAI and poll until transcription completes."""
    base = provider.base_url.rstrip("/")
    headers = {"Authorization": api_key or ""}

    # Step 1: upload audio
    upload_resp = await client.post(
        f"{base}/v2/upload",
        content=audio,
        headers={**headers, "Content-Type": "application/octet-stream"},
    )
    upload_resp.raise_for_status()
    upload_url: str = upload_resp.json()["upload_url"]

    # Step 2: request transcription
    transcript_resp = await client.post(
        f"{base}/v2/transcript",
        json={"audio_url": upload_url},
        headers={**headers, "Content-Type": "application/json"},
    )
    transcript_resp.raise_for_status()
    transcript_id: str = transcript_resp.json()["id"]

    # Step 3: poll until completed or error (poll every 2 s up to the deadline)
    poll_url = f"{base}/v2/transcript/{transcript_id}"
    deadline = asyncio.get_event_loop().time() + _ASSEMBLYAI_POLL_DEADLINE_S
    while True:
        poll_resp = await client.get(poll_url, headers=headers)
        poll_resp.raise_for_status()
        body = poll_resp.json()
        status = body.get("status")
        if status == "completed":
            # AssemblyAI word timings are in milliseconds — normalize to seconds.
            words = None
            raw_words = body.get("words")
            if isinstance(raw_words, list) and raw_words:
                try:
                    words = tuple(
                        WordTiming(
                            word=str(w["text"]).strip(),
                            start=float(w["start"]) / 1000.0,
                            end=float(w["end"]) / 1000.0,
                        )
                        for w in raw_words
                        if str(w["text"]).strip()
                    ) or None
                except (KeyError, TypeError, ValueError):
                    words = None
            return TranscriptionResult(text=body["text"], words=words)
        if status == "error":
            raise ProviderError(
                f"AssemblyAI transcription error: {body.get('error', 'unknown')}"
            )
        if asyncio.get_event_loop().time() >= deadline:
            raise ProviderError(
                f"AssemblyAI transcription timed out after {_ASSEMBLYAI_POLL_DEADLINE_S:.0f} s"
            )
        await asyncio.sleep(2)


async def _transcribe_generic(
    client: httpx.AsyncClient,
    provider: ProviderConfig,
    audio: bytes,
    api_key: str | None,
) -> TranscriptionResult:
    """POST to an OpenAI-compatible /v1/audio/transcriptions endpoint.

    For local providers we request ``verbose_json`` with word granularity so
    the streaming assembler can dedup overlap by time. Arbitrary remote
    endpoints may not support that, so they get the plain ``json`` format.
    If a local server replies without a ``words`` array we degrade to text.
    """
    url = f"{provider.base_url.rstrip('/')}/v1/audio/transcriptions"
    # Only send Authorization header if an API key is actually present.
    # Local providers (Parakeet) reject empty Bearer headers.
    headers: dict[str, str] = {}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    files = {"file": ("audio.wav", audio, "audio/wav")}
    data: dict[str, str] = {"model": provider.model}
    if _is_local(provider):
        data["response_format"] = "verbose_json"
        data["timestamp_granularities[]"] = "word"
    response = await client.post(url, headers=headers, files=files, data=data)
    response.raise_for_status()
    body = response.json()
    return TranscriptionResult(
        text=body.get("text") or "",
        words=_parse_words(body.get("words")),
    )


# ---------------------------------------------------------------------------
# Public client
# ---------------------------------------------------------------------------


class STTClient:
    """Thin async HTTP client for speech-to-text transcription.

    Routes to the correct adapter based on ``provider.base_url``:

    - ``api.deepgram.com``   → Deepgram native adapter
    - ``api.assemblyai.com`` → AssemblyAI async polling adapter
    - anything else          → generic OpenAI-compatible adapter

    Dispatched inside a QRunnable worker by AppController.
    Timeout: 30 seconds.
    """

    async def transcribe(
        self,
        provider: ProviderConfig,
        audio: bytes,
        api_key: str | None = None,
    ) -> TranscriptionResult:
        """Transcribe *audio* (WAV bytes) using *provider*.

        Args:
            provider: Provider configuration (URL, model, etc.).
            audio:    Raw WAV bytes to transcribe.
            api_key:  API key for the provider (not stored in ProviderConfig).

        Returns:
            A :class:`TranscriptionResult` with the transcript and, when the
            provider supplies them, word-level timings.

        Raises:
            ProviderError: On HTTP errors, timeouts, or provider-side errors.
        """
        import httpx  # lazy — see module docstring note

        try:
            timeout = (
                httpx.Timeout(_LOCAL_READ_TIMEOUT_S, connect=_LOCAL_CONNECT_TIMEOUT_S)
                if _is_local(provider)
                else httpx.Timeout(_STT_READ_TIMEOUT_S, connect=_STT_CONNECT_TIMEOUT_S)
            )
            async with httpx.AsyncClient(timeout=timeout) as client:
                base = provider.base_url.lower()
                if "api.deepgram.com" in base:
                    return await _transcribe_deepgram(client, provider, audio, api_key)
                elif "api.assemblyai.com" in base:
                    return await _transcribe_assemblyai(client, provider, audio, api_key)
                else:
                    return await _transcribe_generic(client, provider, audio, api_key)
        except ProviderError:
            raise
        except httpx.TimeoutException as exc:
            raise ProviderError(f"STT request timed out: {exc}") from exc
        except httpx.HTTPStatusError as exc:
            raise ProviderError(
                f"STT HTTP error {exc.response.status_code}: {exc.response.text}"
            ) from exc
        except httpx.HTTPError as exc:
            raise ProviderError(f"STT HTTP error: {exc}") from exc
