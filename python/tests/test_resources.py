import functools
import json
import os

import pytest

from helpers import json_response, setup
from nafru_email import NafruError, paginate, verify_webhook

OK = json_response({"ok": True})

CASES = [
    ("emails.batch", lambda n: n.emails.batch([{"from": "a@x.test", "to": "b@x.test", "subject": "s", "text": "t"}]),
     "POST", "/emails/batch", [{"from": "a@x.test", "to": "b@x.test", "subject": "s", "text": "t"}]),
    ("emails.get", lambda n: n.emails.get("e 1"), "GET", "/emails/e%201", None),
    ("emails.list", lambda n: n.emails.list(limit=2, status="sent"), "GET", "/emails?limit=2&status=sent", None),
    ("emails.update", lambda n: n.emails.update("e1", {"scheduled_at": "in 1 hour"}), "PATCH", "/emails/e1",
     {"scheduled_at": "in 1 hour"}),
    ("emails.cancel", lambda n: n.emails.cancel("e1"), "POST", "/emails/e1/cancel", None),
    ("domains.create", lambda n: n.domains.create({"name": "x.test"}), "POST", "/domains", {"name": "x.test"}),
    ("domains.verify", lambda n: n.domains.verify("d1"), "POST", "/domains/d1/verify", None),
    ("domains.remove", lambda n: n.domains.remove("d1"), "DELETE", "/domains/d1", None),
    ("contacts.get email", lambda n: n.contacts.get("a+b@x.test"), "GET", "/contacts/a%2Bb%40x.test", None),
    ("contacts.update", lambda n: n.contacts.update("c1", {"unsubscribed": True}), "PATCH", "/contacts/c1",
     {"unsubscribed": True}),
    ("contacts.segments.add", lambda n: n.contacts.segments.add("c1", "s1"), "POST", "/contacts/c1/segments/s1", None),
    ("contacts.segments.remove", lambda n: n.contacts.segments.remove("c1", "s1"), "DELETE",
     "/contacts/c1/segments/s1", None),
    ("contacts.topics.list", lambda n: n.contacts.topics.list("c1"), "GET", "/contacts/c1/topics", None),
    ("contacts.topics.update bare array",
     lambda n: n.contacts.topics.update("c1", {"topics": [{"id": "t1", "subscription": "opt_in"}]}),
     "PATCH", "/contacts/c1/topics", [{"id": "t1", "subscription": "opt_in"}]),
    ("contact_properties.create", lambda n: n.contact_properties.create({"key": "plan", "type": "string"}), "POST",
     "/contact-properties", {"key": "plan", "type": "string"}),
    ("segments.contacts", lambda n: n.segments.contacts("s1", limit=3, after="c9"), "GET",
     "/segments/s1/contacts?limit=3&after=c9", None),
    ("topics.update", lambda n: n.topics.update("t1", {"name": "Haber"}), "PATCH", "/topics/t1", {"name": "Haber"}),
    ("broadcasts.send", lambda n: n.broadcasts.send("b1"), "POST", "/broadcasts/b1/send", {}),
    ("broadcasts.cancel", lambda n: n.broadcasts.cancel("b1"), "POST", "/broadcasts/b1/cancel", None),
    ("templates.publish", lambda n: n.templates.publish("welcome"), "POST", "/templates/welcome/publish", None),
    ("templates.duplicate", lambda n: n.templates.duplicate("welcome"), "POST", "/templates/welcome/duplicate", None),
    ("templates.put_translation", lambda n: n.templates.put_translation("welcome", "pt-BR", {"html": "<p/>"}), "PUT",
     "/templates/welcome/translations/pt-BR", {"html": "<p/>"}),
    ("templates.remove_translation", lambda n: n.templates.remove_translation("welcome", "de"), "DELETE",
     "/templates/welcome/translations/de", None),
    ("brand.get", lambda n: n.brand.get(), "GET", "/brand", None),
    ("brand.update", lambda n: n.brand.update({"accent_color": "#ff6600"}), "PUT", "/brand", {"accent_color": "#ff6600"}),
    ("webhooks.list", lambda n: n.webhooks.list(limit=1), "GET", "/webhooks?limit=1", None),
    ("api_keys.remove", lambda n: n.api_keys.remove("k1"), "DELETE", "/api-keys/k1", None),
    ("events.list", lambda n: n.events.list(name="email.opened", contact_id="c1"), "GET",
     "/events?name=email.opened&contact_id=c1", None),
]


@pytest.mark.parametrize("name,run,method,path,body", CASES, ids=[c[0] for c in CASES])
def test_resource_mapping(name, run, method, path, body):
    nafru, rec = setup([OK])
    run(nafru)
    call = rec.calls[0]
    assert call.method == method
    assert call.url.replace("https://api.test", "") == path
    assert rec.json(0) == body


def test_events_send_idempotency():
    nafru, rec = setup([json_response({"id": "ev1"})])
    nafru.events.send({"name": "plan_upgraded", "contact": {"email": "a@x.test"}}, idempotency_key="ev-k")
    assert rec.calls[0].headers["idempotency-key"] == "ev-k"


def test_paginate_follows_after_cursor():
    pages = [
        json_response({"object": "list", "data": [{"id": "a"}, {"id": "b"}], "has_more": True}),
        json_response({"object": "list", "data": [{"id": "c"}], "has_more": False}),
    ]
    nafru, rec = setup(pages)
    assert [c["id"] for c in paginate(nafru.contacts.list, limit=2)] == ["a", "b", "c"]
    assert [c.url for c in rec.calls] == ["https://api.test/contacts?limit=2", "https://api.test/contacts?limit=2&after=b"]


def test_paginate_with_id_via_partial():
    nafru, rec = setup([json_response({"object": "list", "data": [{"id": "t1"}], "has_more": False})])
    assert list(paginate(functools.partial(nafru.contacts.topics.list, "c1"))) == [{"id": "t1"}]
    assert rec.calls[0].url == "https://api.test/contacts/c1/topics"


def test_paginate_raises_on_error():
    nafru, _ = setup([json_response({"statusCode": 401, "name": "unauthorized", "message": "anahtar yok"}, 401)])
    with pytest.raises(NafruError) as info:
        list(paginate(nafru.contacts.list))
    assert (info.value.message, info.value.status_code) == ("anahtar yok", 401)


VECTOR = json.load(open(os.path.join(os.path.dirname(__file__), "..", "..", "webhook-test-vector.json")))


def _verify(**overrides):
    v = {**VECTOR, **overrides}
    return verify_webhook(
        v["payload"],
        {"id": v["id"], "timestamp": v["timestamp"], "signature": v["signature"]},
        v["secret"],
        now=v["now_seconds"],
    )


def test_webhook_shared_vector():
    assert _verify() is True
    assert _verify(payload=VECTOR["payload"].replace("em_123", "em_124")) is False
    assert _verify(payload=VECTOR["payload"].encode()) is True


def test_webhook_multiple_signatures_and_tolerance():
    assert _verify(signature=f"v1,AAAA {VECTOR['signature']}") is True
    assert _verify(signature="v2,zzz v1,@@@") is False
    assert _verify(now_seconds=VECTOR["now_seconds"] + 301) is False
    assert _verify(timestamp="abc") is False


def test_webhook_bad_secret_raises():
    with pytest.raises(ValueError, match="whsec_"):
        _verify(secret="nope")
    with pytest.raises(ValueError, match="base64"):
        _verify(secret="whsec_!!!")


def test_broadcast_recurrence_and_data_source():
    detail = {
        "object": "broadcast", "id": "b1", "name": "Haftalık", "status": "draft",
        "recurrence": {"type": "weekly", "days": [1, 3], "time": "09:00"},
        "trigger_state": "active", "next_run_at": "2026-11-09T06:00:00.000Z", "parent_id": None,
        "data": {"plan": "pro"},
        "data_source": {"type": "url", "url": "https://x.test/d.json", "header_name": "X-Key", "has_header_value": True},
    }
    nafru, rec = setup([json_response(detail)])
    broadcast = nafru.broadcasts.get("b1")
    assert broadcast["recurrence"] == {"type": "weekly", "days": [1, 3], "time": "09:00"}
    assert broadcast["data_source"]["type"] == "url" and broadcast["data_source"]["has_header_value"] is True
    assert broadcast["trigger_state"] == "active" and broadcast["parent_id"] is None

    # Bilinmeyen tür ayrıştırmayı bozmaz.
    nafru, _ = setup([json_response({**detail, "recurrence": {"type": "yearly"}, "data_source": {"type": "sftp"}})])
    assert nafru.broadcasts.get("b1")["recurrence"]["type"] == "yearly"

    nafru, rec = setup([json_response({"object": "broadcast", "id": "b2"})])
    nafru.broadcasts.create({
        "segment_id": "s1", "from": "a@x.test", "html": "<p>{{{data.plan}}}</p>",
        "recurrence": {"type": "interval", "every_days": 7, "time": "08:30"},
        "data_source": {"type": "url", "url": "https://x.test/d.json", "header_value": None},
    })
    body = rec.json(0)
    assert body["recurrence"] == {"type": "interval", "every_days": 7, "time": "08:30"}
    assert body["data_source"]["header_value"] is None

    # Güncellemede None alanı temizler (null gider), verilmeyen anahtar gitmez.
    nafru, rec = setup([json_response({"object": "broadcast", "id": "b1"})])
    nafru.broadcasts.update("b1", {"recurrence": None, "data": None})
    assert rec.json(0) == {"recurrence": None, "data": None}
    nafru, rec = setup([json_response({"object": "broadcast", "id": "b1"})])
    nafru.broadcasts.send("b1", {"data": {"plan": "pro"}})
    assert rec.json(0) == {"data": {"plan": "pro"}}


def test_webhook_missing_or_bad_headers_return_false():
    secret = VECTOR["secret"]
    assert verify_webhook(VECTOR["payload"], {}, secret) is False
    assert verify_webhook(VECTOR["payload"], {"id": "", "timestamp": "", "signature": ""}, secret) is False
    assert verify_webhook(VECTOR["payload"], {"id": VECTOR["id"], "timestamp": VECTOR["timestamp"], "signature": None}, secret) is False


def test_webhook_tolerance_both_directions_and_signature_cap():
    assert _verify(now_seconds=VECTOR["now_seconds"] - 301) is False  # zaman damgası gelecekte
    assert _verify(now_seconds=VECTOR["now_seconds"] - 299) is True
    assert _verify(signature=" ".join(["v1,AAAA"] * 32 + [VECTOR["signature"]])) is False  # 33. imza yok sayılır
    assert _verify(signature=" ".join(["v1,AAAA"] * 31 + [VECTOR["signature"]])) is True
