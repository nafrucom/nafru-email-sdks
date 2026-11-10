import time

import pytest

from helpers import Recorder, json_response, setup
from nafru_email import DEFAULT_BASE_URL, SDK_VERSION, HttpResponse, NafruEmail, NafruError


def test_headers_and_json_body():
    nafru, rec = setup([json_response({"id": "e1"})])
    assert nafru.emails.send({"from": "a@x.test", "to": "b@x.test", "subject": "s", "text": "t"}) == {"id": "e1"}
    call = rec.calls[0]
    assert call.url == "https://api.test/emails"
    assert call.method == "POST"
    assert call.headers["authorization"] == "Bearer key_test"
    assert call.headers["content-type"] == "application/json"
    assert call.headers["user-agent"] == f"nafru-email-python/{SDK_VERSION}"
    assert "idempotency-key" not in call.headers


def test_send_idempotency_header():
    nafru, rec = setup([json_response({"id": "e1"})])
    nafru.emails.send({"to": "x", "text": "t"}, idempotency_key="k-1")
    assert rec.calls[0].headers["idempotency-key"] == "k-1"


def test_query_skips_empty_values():
    nafru, rec = setup([json_response({"object": "list", "data": [], "has_more": False})])
    nafru.contacts.list(limit=5, after=None, search="ali")
    assert rec.calls[0].url == "https://api.test/contacts?limit=5&search=ali"
    nafru.contacts.list(search="")
    assert rec.calls[1].url == "https://api.test/contacts"


def test_error_body_parsed():
    body = {
        "statusCode": 422,
        "name": "validation_error",
        "message": "Geçersiz",
        "errors": [{"field": "to", "message": "zorunlu", "i18nTranslationKey": "k"}],
    }
    nafru, _ = setup([json_response(body, 422)])
    with pytest.raises(NafruError) as info:
        nafru.emails.send({"to": "x", "text": "t"})
    error = info.value
    assert (error.status_code, error.name, error.message) == (422, "validation_error", "Geçersiz")
    assert error.errors == body["errors"]
    assert error.retry_after is None


def test_non_standard_body_falls_back_to_status():
    nafru, _ = setup([HttpResponse(502, {}, b"<html>bad gateway</html>", "Bad Gateway")])
    with pytest.raises(NafruError) as info:
        nafru.emails.get("e1")
    assert (info.value.status_code, info.value.name, info.value.message) == (502, "application_error", "Bad Gateway")


def test_network_error_has_null_status():
    def boom(_request):
        raise OSError("bağlantı reddedildi")

    nafru, _ = setup([boom])
    with pytest.raises(NafruError) as info:
        nafru.emails.send({"to": "x", "text": "t"})
    assert (info.value.status_code, info.value.name, info.value.message) == (
        None,
        "application_error",
        "bağlantı reddedildi",
    )


def test_timeout_error():
    def slow(_request):
        raise TimeoutError("timed out")

    nafru, _ = setup([slow])
    with pytest.raises(NafruError) as info:
        nafru.emails.get("e1")
    assert (info.value.status_code, info.value.name) == (None, "timeout_error")


def limited(retry_after: str = "0"):
    return json_response(
        {"statusCode": 429, "name": "rate_limit_exceeded", "message": "yavaş"}, 429, {"Retry-After": retry_after}
    )


def test_429_retried_with_retry_after_even_for_post(monkeypatch):
    sleeps = []
    monkeypatch.setattr(time, "sleep", sleeps.append)
    nafru, rec = setup([limited("1"), json_response({"id": "e1"})], max_retries=2)
    assert nafru.emails.send({"to": "x", "text": "t"}) == {"id": "e1"}
    assert len(rec.calls) == 2
    assert sleeps == [1.0]


def test_retry_after_capped_at_8s(monkeypatch):
    sleeps = []
    monkeypatch.setattr(time, "sleep", sleeps.append)
    nafru, _ = setup([limited("120"), json_response({"id": "e1"})], max_retries=1)
    nafru.emails.get("e1")
    assert sleeps == [8.0]


def test_429_exhausted_raises_with_retry_after():
    nafru, rec = setup([limited("0")], max_retries=1)
    with pytest.raises(NafruError) as info:
        nafru.emails.get("e1")
    assert (info.value.status_code, info.value.name, info.value.retry_after) == (429, "rate_limit_exceeded", 0)
    assert len(rec.calls) == 2


def test_get_5xx_retried_post_without_key_not(monkeypatch):
    sleeps = []
    monkeypatch.setattr(time, "sleep", sleeps.append)
    down = json_response({"statusCode": 500, "name": "application_error", "message": "x"}, 500)
    nafru, rec = setup([down, json_response({"id": "e1"})], max_retries=1)
    assert nafru.emails.get("e1")["id"] == "e1"
    assert len(rec.calls) == 2
    assert sleeps == [0.3]  # 300ms * 2^0

    nafru, rec = setup([down, json_response({"id": "e1"})], max_retries=1)
    with pytest.raises(NafruError) as info:
        nafru.emails.send({"to": "x", "text": "t"})
    assert info.value.status_code == 500
    assert len(rec.calls) == 1


def test_post_with_idempotency_key_retried_on_5xx(monkeypatch):
    monkeypatch.setattr(time, "sleep", lambda _s: None)
    down = json_response({"statusCode": 503, "name": "application_error", "message": "x"}, 503)
    nafru, rec = setup([down, json_response({"id": "e1"})], max_retries=1)
    assert nafru.emails.send({"to": "x", "text": "t"}, idempotency_key="k-1") == {"id": "e1"}
    assert len(rec.calls) == 2
    assert rec.calls[1].headers["idempotency-key"] == "k-1"


def test_required_options_and_default_base_url(monkeypatch):
    monkeypatch.delenv("NAFRU_API_KEY", raising=False)
    with pytest.raises(ValueError, match="api_key"):
        NafruEmail("", "http://x")
    with pytest.raises(ValueError, match="api_key"):
        NafruEmail()
    for base_url in (None, ""):
        rec = Recorder([json_response({"id": "e1"})])
        NafruEmail("k", base_url, transport=rec).emails.get("e1")
        assert rec.calls[0].url == f"{DEFAULT_BASE_URL}/emails/e1" == "https://email.nafru.com/api/emails/e1"


def test_deprecation_warning_once_per_client(capsys):
    headers = {"Deprecation": "true", "Sunset": "Wed, 31 Dec 2026 23:59:59 GMT", "Link": '<https://nafru.com/sdk>; rel="deprecation"'}
    nafru, _ = setup([json_response({"id": "e1"}, headers=headers)])
    assert nafru.emails.get("e1") == {"id": "e1"}
    nafru.emails.get("e1")
    err = capsys.readouterr().err
    assert err.count("[nafru]") == 1
    assert (
        f"[nafru] Bu SDK sürümü (python {SDK_VERSION}) kullanımdan kaldırıldı; lütfen güncelleyin."
        " Son tarih: Wed, 31 Dec 2026 23:59:59 GMT Ayrıntı: https://nafru.com/sdk"
    ) in err


def test_api_key_from_environment(monkeypatch):
    monkeypatch.setenv("NAFRU_API_KEY", "nafru_env")
    rec = Recorder([json_response({"id": "e1"})])
    NafruEmail(transport=rec).emails.get("e1")
    assert rec.calls[0].headers["authorization"] == "Bearer nafru_env"
    NafruEmail("nafru_arg", transport=rec).emails.get("e1")
    assert rec.calls[1].headers["authorization"] == "Bearer nafru_arg"


@pytest.mark.parametrize("url", ["http://api.example.com/api", "ftp://api.test", "api.test", "http://localhost.evil.com"])
def test_base_url_must_be_https(url):
    with pytest.raises(ValueError, match="https"):
        NafruEmail("k", url)


@pytest.mark.parametrize(
    "url", ["http://localhost:48787/api", "http://app.localhost/api", "http://127.0.0.5:1/api", "http://[::1]:8/api"]
)
def test_http_allowed_for_loopback(url):
    NafruEmail("k", url)


def test_redirect_is_an_error_and_not_retried():
    nafru, rec = setup([HttpResponse(302, {"location": "https://evil.test/"}, b"", "Found")], max_retries=2)
    with pytest.raises(NafruError) as info:
        nafru.emails.get("e1")
    assert (info.value.status_code, info.value.name) == (302, "unexpected_redirect")
    assert len(rec.calls) == 1


def test_default_transport_does_not_follow_redirects():
    import threading
    from http.server import BaseHTTPRequestHandler, HTTPServer

    hits = []

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802
            hits.append((self.path, self.headers.get("authorization")))
            self.send_response(302)
            self.send_header("Location", "/stolen")
            self.end_headers()

        def log_message(self, *args):
            pass

    server = HTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        nafru = NafruEmail("nafru_k", f"http://127.0.0.1:{server.server_port}", max_retries=0)
        with pytest.raises(NafruError) as info:
            nafru.emails.get("e1")
        assert info.value.name == "unexpected_redirect"
        assert [path for path, _ in hits] == ["/emails/e1"]
    finally:
        server.shutdown()


def test_response_too_large():
    nafru, _ = setup([HttpResponse(200, {}, b" " * (10 * 1024 * 1024 + 1))])
    with pytest.raises(NafruError) as info:
        nafru.emails.get("e1")
    assert info.value.name == "response_too_large"


@pytest.mark.parametrize("segment", ["", ".", ".."])
def test_unsafe_path_segment_rejected_before_request(segment):
    nafru, rec = setup([json_response({})])
    with pytest.raises(NafruError) as info:
        nafru.contacts.get(segment)
    assert info.value.name == "invalid_argument"
    assert rec.calls == []


@pytest.mark.parametrize("key", ["", "a\r\nX-Evil: 1", "a\nb", "tab\tkey", "nul\x00"])
def test_idempotency_key_header_injection_rejected(key):
    nafru, rec = setup([json_response({"id": "e1"})])
    with pytest.raises(NafruError) as info:
        nafru.emails.send({"to": "x", "text": "t"}, idempotency_key=key)
    assert info.value.name == "invalid_argument"
    assert rec.calls == []


def test_client_and_request_repr_hide_api_key():
    nafru, rec = setup([json_response({"id": "e1"})])
    secret_client = NafruEmail("nafru_supersecret", "https://api.test", transport=rec)
    secret_client.emails.get("e1")
    text = f"{secret_client!r} {secret_client} {rec.calls[-1]!r}"
    assert "supersecret" not in text and "nafru_****" in text
