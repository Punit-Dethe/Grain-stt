import pytest
from open_voice_router.validation import validate_provider_url


def test_valid_https_simple():
    assert validate_provider_url("https://api.deepgram.com") is True


def test_valid_https_with_path():
    assert validate_provider_url("https://api.cerebras.ai/v1") is True


def test_valid_https_long_path():
    url = "https://generativelanguage.googleapis.com/v1beta/openai"
    assert validate_provider_url(url) is True


def test_valid_https_with_port():
    assert validate_provider_url("https://localhost:8080") is True


def test_valid_https_ip():
    assert validate_provider_url("https://192.168.1.1") is True


def test_valid_https_trailing_slash():
    assert validate_provider_url("https://example.com/") is True


def test_http_returns_false():
    assert validate_provider_url("http://api.deepgram.com") is False


def test_http_with_path_returns_false():
    assert validate_provider_url("http://example.com/v1") is False


def test_http_localhost_returns_false():
    assert validate_provider_url("http://localhost:8080") is False


def test_bare_hostname_returns_false():
    assert validate_provider_url("api.deepgram.com") is False


def test_bare_hostname_with_path_returns_false():
    assert validate_provider_url("api.deepgram.com/v1") is False


def test_localhost_no_scheme_returns_false():
    assert validate_provider_url("localhost") is False


def test_localhost_with_port_no_scheme_returns_false():
    assert validate_provider_url("localhost:8080") is False


def test_empty_string_returns_false():
    assert validate_provider_url("") is False


def test_whitespace_returns_false():
    assert validate_provider_url("   ") is False


def test_plain_word_returns_false():
    assert validate_provider_url("notaurl") is False


def test_ftp_scheme_returns_false():
    assert validate_provider_url("ftp://files.example.com") is False


def test_scheme_only_returns_false():
    assert validate_provider_url("https://") is False


def test_no_host_returns_false():
    assert validate_provider_url("https:///path") is False


def test_random_sentence_returns_false():
    assert validate_provider_url("this is not a url at all") is False


def test_no_scheme_separator_returns_false():
    assert validate_provider_url("https:example.com") is False
