"""STTClient — speech-to-text via provider-specific adapters.

Supports:
- Deepgram  (api.deepgram.com)   — native Deepgram v1/listen API
- AssemblyAI (api.assemblyai.com) — native AssemblyAI v2 async API
- Generic fallback               — OpenAI-compatible /v1/audio/transcriptions

Implements Requirements 6.1, 6.2.
Timeout: 30 seconds.
"""

from __future__ import annotations

import asyncio

import httpx

from open_voice_router.exceptions import ProviderError
from open_voice_router.models import ProviderConfig

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

_STT_TIMEOUT = httpx.Timeout(60.0, connect=10.0)
# Local STT runs a synchronous ONNX model that can take a while on a long
# recording (it silence-splits and transcribes each segment). Give localhost a
# much more generous read timeout so long utterances never time out.
_LOCAL_STT_TIMEOUT = httpx.Timeout(300.0, connect=5.0)


def _is_local(provider: ProviderConfig) -> bool:
    base = (provider.base_url or "").lower()
    return "127.0.0.1" in base or "localhost" in base


# ---------------------------------------------------------------------------
# Provider-specific adapters
# ---------------------------------------------------------------------------


async def _transcribe_deepgram(
    client: httpx.AsyncClient,
    provider: ProviderConfig,
    audio: bytes,
    api_key: str | None,
) -> str:
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
        transcript = data["results"]["channels"][0]["alternatives"][0]["transcript"]
    except (KeyError, IndexError, TypeError) as exc:
        raise ProviderError(
            f"Deepgram response missing expected structure: {exc}. Response: {data}"
        ) from exc
    # Empty transcript is valid (silence) — return it as-is
    return transcript


async def _transcribe_assemblyai(
    client: httpx.AsyncClient,
    provider: ProviderConfig,
    audio: bytes,
    api_key: str | None,
) -> str:
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

    # Step 3: poll until completed or error (max 30 s, poll every 2 s)
    poll_url = f"{base}/v2/transcript/{transcript_id}"
    deadline = asyncio.get_event_loop().time() + _STT_TIMEOUT
    while True:
        poll_resp = await client.get(poll_url, headers=headers)
        poll_resp.raise_for_status()
        body = poll_resp.json()
        status = body.get("status")
        if status == "completed":
            return body["text"]
        if status == "error":
            raise ProviderError(
                f"AssemblyAI transcription error: {body.get('error', 'unknown')}"
            )
        if asyncio.get_event_loop().time() >= deadline:
            raise ProviderError("AssemblyAI transcription timed out after 30 s")
        await asyncio.sleep(2)


async def _transcribe_generic(
    client: httpx.AsyncClient,
    provider: ProviderConfig,
    audio: bytes,
    api_key: str | None,
) -> str:
    """POST to an OpenAI-compatible /v1/audio/transcriptions endpoint."""
    url = f"{provider.base_url.rstrip('/')}/v1/audio/transcriptions"
    # Only send Authorization header if an API key is actually present.
    # Local providers (Parakeet) reject empty Bearer headers.
    headers: dict[str, str] = {}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    files = {"file": ("audio.wav", audio, "audio/wav")}
    data = {"model": provider.model}
    response = await client.post(url, headers=headers, files=files, data=data)
    response.raise_for_status()
    return response.json().get("text") or ""


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
    ) -> str:
        """Transcribe *audio* (WAV bytes) using *provider*.

        Args:
            provider: Provider configuration (URL, model, etc.).
            audio:    Raw WAV bytes to transcribe.
            api_key:  API key for the provider (not stored in ProviderConfig).

        Returns:
            The transcript as a plain string.

        Raises:
            ProviderError: On HTTP errors, timeouts, or provider-side errors.
        """
        try:
            timeout = _LOCAL_STT_TIMEOUT if _is_local(provider) else _STT_TIMEOUT
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
