import html as html_lib
import json
import os
import re
import secrets
import time
from datetime import datetime, timezone
from typing import Any, Literal, Mapping, Optional, Union

from .types import SendEmailResponse

DevOutbox = Union[str, "os.PathLike[str]", Literal[False], None]

_BASE36 = "0123456789abcdefghijklmnopqrstuvwxyz"


def resolve_dev_outbox(dev_outbox: DevOutbox) -> Optional[str]:
    """`dev_outbox` verilmezse: yalnız `NODE_ENV=development` iken `.nafru/emails`; aksi hâlde gerçek gönderim (`None`)."""
    if dev_outbox is None:
        return ".nafru/emails" if os.environ.get("NODE_ENV") == "development" else None
    return os.fspath(dev_outbox) if dev_outbox is not False else None


def _base36(number: int) -> str:
    out = ""
    while number:
        number, rest = divmod(number, 36)
        out = _BASE36[rest] + out
    return out or "0"


def _join(value: Any) -> str:
    return ", ".join(value) if isinstance(value, list) else (value or "")


# shortcut: kaba HTML→metin dönüşümü (etiket silme); yalnız dev önizlemesi için, gerçek gönderime girmez.
def _html_to_text(html: str) -> str:
    text = re.sub(r"<(style|script)[\s\S]*?</\1>", "", html, flags=re.I)
    text = re.sub(r"<br\s*/?>|</(p|div|h[1-6]|li|tr)>", "\n", text, flags=re.I)
    text = re.sub(r"<[^>]+>", "", text)
    for entity, char in (("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", '"'), ("&amp;", "&")):
        text = text.replace(entity, char)
    return re.sub(r"\n{3,}", "\n\n", text).strip()


def _body_text(email: Mapping[str, Any]) -> str:
    if email.get("text"):
        return str(email["text"])
    if email.get("html"):
        return _html_to_text(email["html"])
    template = email.get("template")
    if template:
        return f"[şablon {template['id']}]\n{json.dumps(template.get('variables') or {}, indent=2, ensure_ascii=False)}"
    return ""


def write_dev_email(directory: str, email: Mapping[str, Any]) -> SendEmailResponse:
    """E-postayı göndermeden `directory` altına `.txt` ve `.html` olarak yazar, yolu ve düz metni konsola basar."""
    email_id = f"dev_{_base36(int(time.time() * 1000))}{''.join(secrets.choice(_BASE36) for _ in range(6))}"
    stamp = datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")
    folder = os.path.abspath(directory)
    base = os.path.join(folder, f"{re.sub(r'[:.]', '-', stamp)}-{email_id}")
    lines = [
        f"From: {email.get('from') or ''}",
        f"To: {_join(email.get('to'))}",
        f"Cc: {_join(email['cc'])}" if email.get("cc") else None,
        f"Bcc: {_join(email['bcc'])}" if email.get("bcc") else None,
        f"Reply-To: {_join(email['reply_to'])}" if email.get("reply_to") else None,
        f"Subject: {email.get('subject') or ''}",
        f"Scheduled-At: {email['scheduled_at']}" if email.get("scheduled_at") else None,
    ]
    body = _body_text(email)
    text = "\n".join(line for line in lines if line is not None) + f"\n\n{body}\n"
    page = email.get("html") or f"<pre>{html_lib.escape(body, quote=True).replace('&#x27;', chr(39))}</pre>"

    os.makedirs(folder, exist_ok=True)
    with open(f"{base}.txt", "w", encoding="utf-8") as handle:
        handle.write(text)
    with open(f"{base}.html", "w", encoding="utf-8") as handle:
        handle.write(page)
    print(f"[nafru] dev: e-posta gönderilmedi\n  {base}.txt\n  {base}.html\n\n{text}")
    return {"id": email_id}
