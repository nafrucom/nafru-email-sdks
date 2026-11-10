import base64
import hashlib
import re
import threading
import time
from urllib.parse import parse_qs, urlparse

import pytest

from helpers import Recorder, json_response
from nafru_email import ConnectionGrant, NafruConnect, NafruError, create_pkce

URLSAFE43 = re.compile(r"^[A-Za-z0-9_-]{43}$")


def server(route):
    rec = Recorder([route])
    nafru = NafruConnect(
        "app_x", "nfs_secret", "https://api.test/", web_url="https://web.test", transport=rec, max_retries=0,
        dev_outbox=False,
    )
    return nafru, rec


def token(n):
    return {
        "access_token": f"nfa_{n}",
        "refresh_token": f"nfr_{n}",
        "token_type": "Bearer",
        "expires_in": 3600,
        "connection_id": "conn_1",
        "scopes": ["emails.send"],
    }


def grant_error(_request=None):
    return json_response({"statusCode": 400, "name": "invalid_grant", "message": "invalid"}, 400)


def is_token(request):
    return request.url.endswith("/oauth/token")


def api_calls(rec):
    return [c for c in rec.calls if "/oauth/" not in c.url]


def test_pkce():
    verifier, challenge = create_pkce()
    assert URLSAFE43.match(verifier)
    expected = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    assert challenge == expected
    assert create_pkce()[0] != verifier


def test_authorize_url():
    nafru, _ = server(lambda r: json_response({}))
    result = nafru.authorize_url(
        redirect_uri="https://scout.test/cb", state="st1", scopes=["emails.send", "templates.read"], login_hint="a@b.co"
    )
    parsed = urlparse(result["url"])
    assert f"{parsed.scheme}://{parsed.netloc}{parsed.path}" == "https://web.test/connect"
    q = {k: v[0] for k, v in parse_qs(parsed.query).items()}
    assert q["client_id"] == "app_x"
    assert q["redirect_uri"] == "https://scout.test/cb"
    assert q["state"] == "st1"
    assert q["scope"] == "emails.send templates.read"
    assert q["code_challenge_method"] == "S256"
    assert q["login_hint"] == "a@b.co"
    assert URLSAFE43.match(q["code_challenge"]) and URLSAFE43.match(result["code_verifier"])
    with pytest.raises(ValueError):
        nafru.authorize_url(redirect_uri="x", state="", scopes=["emails.send"])
    with pytest.raises(ValueError):
        nafru.authorize_url(redirect_uri="x", state="s", scopes=[])


def test_web_url_defaults_to_base_without_api():
    nafru = NafruConnect("app_x", "s", "https://email.nafru.test/api", transport=lambda r: json_response({}))
    assert nafru.authorize_url(redirect_uri="r", state="s", scopes=["emails.send"])["url"].startswith(
        "https://email.nafru.test/connect?"
    )


def test_default_base_url_and_web_url():
    rec = Recorder([json_response(token(1))])
    nafru = NafruConnect("app_x", "s", transport=rec)
    assert nafru.authorize_url(redirect_uri="r", state="s", scopes=["emails.send"])["url"].startswith(
        "https://email.nafru.com/connect?"
    )
    nafru.exchange(code="c", code_verifier="v", redirect_uri="r")
    assert rec.calls[0].url == "https://email.nafru.com/api/oauth/token"
    with pytest.raises(ValueError, match="client_id"):
        NafruConnect("", "s")


def test_exchange_no_authorization_header():
    nafru, rec = server(lambda r: json_response(token(1)))
    grant = nafru.exchange(code="nfc_1", code_verifier="v" * 43, redirect_uri="https://scout.test/cb")
    assert grant == ConnectionGrant("conn_1", "nfr_1", ["emails.send"])
    call = rec.calls[0]
    assert call.url == "https://api.test/oauth/token"
    assert "authorization" not in call.headers
    body = rec.json(0)
    assert body["grant_type"] == "authorization_code" and body["client_secret"] == "nfs_secret"


def test_exchange_error_raises():
    nafru, _ = server(grant_error)
    with pytest.raises(NafruError) as info:
        nafru.exchange(code="c", code_verifier="v", redirect_uri="r")
    assert (info.value.status_code, info.value.name) == (400, "invalid_grant")


def test_revoke():
    nafru, rec = server(lambda r: json_response({}))
    assert nafru.revoke(refresh_token="nfr_1") is None
    assert rec.json(0) == {"client_id": "app_x", "client_secret": "nfs_secret", "token": "nfr_1"}


def open_connection(route):
    nafru, rec = server(route)
    saved = []
    connection = nafru.connection("conn_1", refresh_token="nfr_0", on_token_refresh=lambda t: saved.append(t.refresh_token))
    return connection, rec, saved


def test_first_call_refreshes_and_rotates():
    connection, rec, saved = open_connection(
        lambda r: json_response(token(1)) if is_token(r) else json_response({"object": "connection", "ready": True})
    )
    assert connection.id == "conn_1"
    assert connection.status()["ready"] is True
    assert saved == ["nfr_1"]
    body = rec.json(0)
    assert body["grant_type"] == "refresh_token" and body["refresh_token"] == "nfr_0"
    first = api_calls(rec)[0]
    assert first.url == "https://api.test/connection" and first.headers["authorization"] == "Bearer nfa_1"


def test_single_flight_refresh_under_concurrency():
    def route(r):
        if is_token(r):
            time.sleep(0.05)
            return json_response(token(1))
        return json_response({"ready": True})

    connection, rec, saved = open_connection(route)
    errors = []

    def run():
        try:
            connection.status()
        except Exception as e:  # noqa: BLE001
            errors.append(e)

    threads = [threading.Thread(target=run) for _ in range(5)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert errors == []
    assert len([c for c in rec.calls if is_token(c)]) == 1
    assert saved == ["nfr_1"]
    connection.status()
    assert len([c for c in rec.calls if is_token(c)]) == 1


def test_invalid_token_refreshes_once_and_retries():
    refreshes = []

    def route(r):
        if is_token(r):
            refreshes.append(1)
            return json_response(token(len(refreshes)))
        if r.headers.get("authorization") == "Bearer nfa_1":
            return json_response({"statusCode": 401, "name": "invalid_token", "message": "expired"}, 401)
        return json_response({"ready": True})

    connection, rec, saved = open_connection(route)
    assert connection.status() == {"ready": True}
    assert len(refreshes) == 2
    assert [c.headers["authorization"] for c in api_calls(rec)] == ["Bearer nfa_1", "Bearer nfa_2"]
    assert saved == ["nfr_1", "nfr_2"]


def test_refresh_rejected_maps_to_connection_revoked():
    connection, rec, _ = open_connection(grant_error)
    with pytest.raises(NafruError) as info:
        connection.status()
    assert info.value.name == "connection_revoked"
    assert api_calls(rec) == []


def test_refresh_403_maps_to_connection_revoked():
    connection, _, _ = open_connection(
        lambda r: json_response({"statusCode": 403, "name": "forbidden", "message": "x"}, 403)
    )
    with pytest.raises(NafruError) as info:
        connection.status()
    assert info.value.name == "connection_revoked"


def test_persist_failure_then_retried_without_new_refresh():
    nafru, rec = server(lambda r: json_response(token(1)))
    saved = []
    failures = [1]

    def on_refresh(tokens):
        if failures[0] > 0:
            failures[0] -= 1
            raise RuntimeError("disk dolu")
        saved.append(tokens.refresh_token)

    connection = nafru.connection("conn_1", refresh_token="nfr_0", on_token_refresh=on_refresh)
    with pytest.raises(NafruError) as info:
        connection.status()
    assert info.value.name == "token_persist_failed" and "disk dolu" in info.value.message
    connection.status()
    assert saved == ["nfr_1"]
    assert len([c for c in rec.calls if is_token(c)]) == 1


def test_connection_endpoints():
    connection, rec, _ = open_connection(
        lambda r: json_response(token(1)) if is_token(r) else json_response({"id": "e1", "data": []})
    )
    connection.senders.list()
    connection.templates.list()
    connection.emails.send({"from": "a@b.co", "to": ["c@d.co"], "subject": "s", "html": "<p>x</p>"}, idempotency_key="k1")
    connection.emails.get("e1")
    connection.emails.list()
    assert [f"{c.method} {urlparse(c.url).path}" for c in api_calls(rec)] == [
        "GET /senders",
        "GET /templates",
        "POST /emails",
        "GET /emails/e1",
        "GET /emails",
    ]
    assert api_calls(rec)[2].headers["idempotency-key"] == "k1"
    assert not hasattr(connection.emails, "batch")


def test_connection_server_error_raises():
    connection, _, _ = open_connection(
        lambda r: json_response(token(1))
        if is_token(r)
        else json_response({"statusCode": 403, "name": "insufficient_scope", "message": "scope"}, 403)
    )
    with pytest.raises(NafruError) as info:
        connection.templates.list()
    assert (info.value.status_code, info.value.name) == (403, "insufficient_scope")


def test_https_required_for_web_url():
    with pytest.raises(ValueError, match="web_url"):
        NafruConnect("app_x", "s", "https://api.test", web_url="http://web.test", transport=lambda r: json_response({}))


def test_secrets_redacted_in_repr():
    connect = NafruConnect("app_x", "nfs_supersecret", transport=lambda r: json_response({}))
    grant = ConnectionGrant("conn_1", "nfr_supersecret", ["emails.send"])
    text = f"{connect!r} {connect} {grant!r} {grant}"
    assert "supersecret" not in text
    assert "nfs_****" in text and "nfr_****" in text and "conn_1" in text
