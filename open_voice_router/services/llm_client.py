"""LLMClient — large language model via OpenAI-compatible endpoints.

All three built-in presets (Cerebras, Gemini, Groq) expose the standard
OpenAI /v1/chat/completions API, so no provider-specific adapters are needed.

Implements Requirements 7.1, 7.2.
Timeout: 60 seconds.
"""

from __future__ import annotations

import httpx

from open_voice_router.exceptions import ProviderError
from open_voice_router.models import ProviderConfig

# ---------------------------------------------------------------------------
# Named provider presets (kept for reference / UI pre-fill)
# ---------------------------------------------------------------------------

LLM_PRESETS: dict[str, dict] = {
    "cerebras": {
        "name": "Cerebras",
        "base_url": "https://api.cerebras.ai/v1",
        "model": "llama-4-scout-17b-16e-instruct",
    },
    "gemini": {
        "name": "Gemini",
        "base_url": "https://generativelanguage.googleapis.com/v1beta/openai",
        "model": "gemini-2.0-flash",
    },
    "groq": {
        "name": "Groq",
        "base_url": "https://api.groq.com/openai/v1",
        "model": "llama-3.1-8b-instant",
    },
}

_LLM_TIMEOUT = 60.0  # seconds


class LLMClient:
    """Thin async HTTP client for LLM completions.

    Uses the OpenAI-compatible ``/v1/chat/completions`` endpoint.
    All three built-in presets (Cerebras, Gemini, Groq) support this natively.

    Dispatched inside a QRunnable worker by AppController.
    Timeout: 60 seconds.
    """

    async def complete(
        self,
        provider: ProviderConfig,
        transcript: str,
        api_key: str | None = None,
        system_prompt: str | None = None,
    ) -> str:
        """Send *transcript* to *provider* and return the response text.

        Args:
            provider:      Provider configuration (URL, model, system prompt, etc.).
            transcript:    The user's transcribed speech to send as the user message.
            api_key:       API key for the provider (not stored in ProviderConfig).
            system_prompt: Override system prompt.  Takes priority over
                           ``provider.system_prompt``.  Falls back to a default
                           if neither is set.

        Returns:
            The LLM response content as a plain string.

        Raises:
            ProviderError: On HTTP errors, timeouts, or provider-side errors.
        """
        # Build the completions URL.
        # Convention: base_url is the provider's API root path prefix.
        # We append /chat/completions directly.
        #
        # Examples:
        #   Groq:     https://api.groq.com/openai/v1     → .../v1/chat/completions    ✓
        #   Cerebras: https://api.cerebras.ai/v1          → .../v1/chat/completions    ✓
        #   Gemini:   https://.../v1beta/openai            → .../openai/chat/completions ✓
        #   Custom:   https://my-server.com/v1             → .../v1/chat/completions    ✓
        url = f"{provider.base_url.rstrip('/')}/chat/completions"
        headers = {
            "Authorization": f"Bearer {api_key or ''}",
            "Content-Type": "application/json",
        }
        # Priority: caller-supplied > provider-level > hard default
        resolved_system_prompt = (
            system_prompt
            or provider.system_prompt
            or "You are a helpful assistant."
        )
        payload = {
            "model": provider.model,
            "messages": [
                {
                    "role": "system",
                    "content": resolved_system_prompt,
                },
                {
                    "role": "user",
                    "content": transcript,
                },
            ],
        }

        try:
            async with httpx.AsyncClient(timeout=_LLM_TIMEOUT) as client:
                response = await client.post(url, headers=headers, json=payload)
                response.raise_for_status()
                data = response.json()
                return data["choices"][0]["message"]["content"]
        except httpx.TimeoutException as exc:
            raise ProviderError(f"LLM request timed out: {exc}") from exc
        except httpx.HTTPStatusError as exc:
            raise ProviderError(
                f"LLM HTTP error {exc.response.status_code}: {exc.response.text}"
            ) from exc
        except httpx.HTTPError as exc:
            raise ProviderError(f"LLM HTTP error: {exc}") from exc
