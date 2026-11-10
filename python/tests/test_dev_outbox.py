import os

from nafru_email import NafruEmail, resolve_dev_outbox


def test_writes_files_instead_of_sending(tmp_path, capsys):
    def transport(_request):
        raise AssertionError("taşıyıcı çağrılmamalı")

    nafru = NafruEmail("k", "https://api.test", transport=transport, dev_outbox=str(tmp_path))
    data = nafru.emails.send(
        {
            "from": "a@x.com",
            "to": ["b@y.com", "c@y.com"],
            "subject": "Merhaba",
            "html": "<p>Selam <b>Ali</b></p><p>&amp; hoş geldin</p>",
        }
    )
    batch = nafru.emails.batch([{"from": "a@x.com", "to": "d@y.com", "subject": "S", "text": "düz"}])

    assert data["id"].startswith("dev_")
    assert len(batch["data"]) == 1
    files = sorted(os.listdir(tmp_path))
    assert len([f for f in files if f.endswith(".txt")]) == 2
    assert len([f for f in files if f.endswith(".html")]) == 2
    txt_name = next(f for f in files if data["id"] in f and f.endswith(".txt"))
    txt = (tmp_path / txt_name).read_text(encoding="utf-8")
    assert "To: b@y.com, c@y.com" in txt
    assert "Subject: Merhaba" in txt
    assert "Selam Ali\n& hoş geldin" in txt
    html_name = next(f for f in files if data["id"] in f and f.endswith(".html"))
    assert "<b>Ali</b>" in (tmp_path / html_name).read_text(encoding="utf-8")
    assert str(tmp_path / txt_name) in capsys.readouterr().out


def test_default_only_in_development(monkeypatch):
    monkeypatch.setenv("NODE_ENV", "development")
    assert resolve_dev_outbox(None) == ".nafru/emails"
    assert resolve_dev_outbox(False) is None
    monkeypatch.setenv("NODE_ENV", "production")
    assert resolve_dev_outbox(None) is None
