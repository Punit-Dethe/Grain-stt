"""Validation utilities for Open Voice Router."""

from __future__ import annotations

from urllib.parse import urlparse


def validate_provider_url(url: str) -> bool:
    """Return True iff *url* is a well-formed HTTPS URL with a non-empty host.

    Checks:
    - scheme is exactly "https"
    - netloc (host) is non-empty

    Examples::

        >>> validate_provider_url("https://api.deepgram.com")
        True
        >>> validate_provider_url("http://api.deepgram.com")
        False
        >>> validate_provider_url("api.deepgram.com")
        False
        >>> validate_provider_url("")
        False

    Validates: Requirements 9.3
    """
    if not url:
        return False
    try:
        parsed = urlparse(url)
    except Exception:
        return False
    return parsed.scheme == "https" and bool(parsed.netloc)
