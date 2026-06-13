"""LLMClient — large language model via OpenAI-compatible endpoints.

All three built-in presets (Cerebras, Gemini, Groq) expose the standard
OpenAI /v1/chat/completions API, so no provider-specific adapters are needed.

Implements Requirements 7.1, 7.2.
Timeout: 60 seconds.
"""

from __future__ import annotations

from open_voice_router.exceptions import ProviderError, RateLimitError
from open_voice_router.models import LLMResult, ProviderConfig
from open_voice_router.services.llm_rotation import parse_rate_limit_headers

# httpx is imported lazily inside chat() — it costs ~19 MB of RAM and is only
# needed while a completion request is in flight.

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
        # Priority: caller-supplied > provider-level > hard default
        resolved_system_prompt = (
            system_prompt
            or provider.system_prompt
            or "You are a helpful assistant."
        )
        messages = [
            {"role": "system", "content": resolved_system_prompt},
            {"role": "user", "content": transcript},
        ]
        return await self.chat(provider, messages, api_key)

    async def complete_detailed(
        self,
        provider: ProviderConfig,
        transcript: str,
        api_key: str | None = None,
        system_prompt: str | None = None,
    ) -> LLMResult:
        """Like :meth:`complete` but returns text + usage/limit signals.

        Used by the smart-rotation processing path so the tracker can learn
        each provider's real headroom from every response.
        """
        resolved_system_prompt = (
            system_prompt or provider.system_prompt or "You are a helpful assistant."
        )
        messages = [
            {"role": "system", "content": resolved_system_prompt},
            {"role": "user", "content": transcript},
        ]
        return await self.chat_detailed(provider, messages, api_key)

    async def chat(
        self,
        provider: ProviderConfig,
        messages: list[dict],
        api_key: str | None = None,
    ) -> str:
        """Send a full OpenAI-style *messages* list and return the reply text.

        Used by multi-turn flows (Grain Assist follow-ups) where the caller
        owns the conversation history, system prompt included.

        Raises:
            ProviderError: On HTTP errors, timeouts, or provider-side errors.
        """
        return (await self.chat_detailed(provider, messages, api_key)).text

    async def chat_detailed(
        self,
        provider: ProviderConfig,
        messages: list[dict],
        api_key: str | None = None,
    ) -> LLMResult:
        """Like :meth:`chat`, but returns text + live usage/limit signals.

        Raises:
            RateLimitError: On HTTP 429, carrying the server's Retry-After.
            ProviderError:  On other HTTP errors, timeouts, or bad responses.
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
        import httpx  # lazy — see module-level note

        url = f"{provider.base_url.rstrip('/')}/chat/completions"
        headers = {
            "Authorization": f"Bearer {api_key or ''}",
            "Content-Type": "application/json",
        }
        payload = {
            "model": provider.model,
            "messages": messages,
        }

        try:
            async with httpx.AsyncClient(timeout=_LLM_TIMEOUT) as client:
                response = await client.post(url, headers=headers, json=payload)
                if response.status_code == 429:
                    raise RateLimitError(
                        f"Rate limited by {provider.name}",
                        retry_after_s=_parse_retry_after(response.headers),
                    )
                response.raise_for_status()
                data = response.json()
                text = data["choices"][0]["message"]["content"]
                usage = data.get("usage") or {}
                total_tokens = usage.get("total_tokens")
                rem_req, rem_tok = parse_rate_limit_headers(response.headers)
                return LLMResult(
                    text=text,
                    total_tokens=int(total_tokens) if total_tokens else None,
                    remaining_requests=rem_req,
                    remaining_tokens=rem_tok,
                )
        except RateLimitError:
            raise
        except httpx.TimeoutException as exc:
            raise ProviderError(f"LLM request timed out: {exc}") from exc
        except httpx.HTTPStatusError as exc:
            raise ProviderError(
                f"LLM HTTP error {exc.response.status_code}: {exc.response.text}"
            ) from exc
        except httpx.HTTPError as exc:
            raise ProviderError(f"LLM HTTP error: {exc}") from exc


def _parse_retry_after(headers) -> float:
    """Read Retry-After (seconds form) or x-ratelimit-reset; fall back to 60 s."""
    for name in ("retry-after", "x-ratelimit-reset-requests", "x-ratelimit-reset-tokens"):
        value = headers.get(name)
        if value is None:
            continue
        try:
            # Most of these are plain seconds; some carry a "1.5s"/"2m" suffix.
            text = str(value).strip().lower()
            if text.endswith("ms"):
                return max(1.0, float(text[:-2]) / 1000.0)
            if text.endswith("s"):
                text = text[:-1]
            if text.endswith("m"):
                return max(1.0, float(text[:-1]) * 60.0)
            return max(1.0, float(text))
        except (TypeError, ValueError):
            continue
    return 60.0
