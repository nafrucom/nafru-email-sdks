"""Svix / Standard Webhooks uyumlu imza doğrulama.

  imzalanan  = f"{svix-id}.{svix-timestamp}.{ham gövde}"
  anahtar    = `whsec_` sonrası base64 çözülmüş `signing_secret`
  başlık     = `v1,<base64 HMAC-SHA256>` (anahtar döndürmede boşlukla ayrılmış birden çok imza)
"""

import base64
import binascii
import hashlib
import hmac
import math
import time
from typing import Mapping, Optional, Union

SECRET_PREFIX = "whsec_"
DEFAULT_TOLERANCE_SECONDS = 300


def _decode(text: str) -> bytes:
    return base64.b64decode(text, validate=True)


def verify_webhook(
    payload: Union[str, bytes],
    headers: Mapping[str, str],
    secret: str,
    *,
    tolerance_seconds: int = DEFAULT_TOLERANCE_SECONDS,
    now: Optional[float] = None,
) -> bool:
    """İmza ve zaman damgası geçerliyse `True`. Bozuk imza ya da zaman damgası `False`; bozuk `secret` `ValueError` fırlatır.

    `payload`: HAM istek gövdesi (ayrıştırılıp yeniden dizilmiş JSON imzayı bozar).
    `headers`: `{"id": svix-id, "timestamp": svix-timestamp, "signature": svix-signature}`.
    `now`: şimdiki zaman (saniye); testler için.
    """
    if not secret.startswith(SECRET_PREFIX):
        raise ValueError("Geçersiz imza anahtarı: whsec_ ile başlamalı")
    try:
        key = _decode(secret[len(SECRET_PREFIX) :])
    except (binascii.Error, ValueError):
        raise ValueError("Geçersiz imza anahtarı: base64 çözülemedi") from None

    raw_timestamp = headers.get("timestamp") or ""
    signatures = headers.get("signature") or ""
    if not raw_timestamp or not signatures or not isinstance(raw_timestamp, str) or not isinstance(signatures, str):
        return False
    try:
        timestamp = float(raw_timestamp)
    except ValueError:
        return False
    now_seconds = math.floor(time.time() if now is None else now)
    if not math.isfinite(timestamp) or abs(now_seconds - timestamp) > tolerance_seconds:
        return False

    body = payload.encode("utf-8") if isinstance(payload, str) else payload
    content = f"{headers.get('id') or ''}.{raw_timestamp}.".encode("utf-8") + body
    expected = hmac.new(key, content, hashlib.sha256).digest()

    # Kötü niyetli uzun başlık işlemciyi yormasın: ilk 32 imza yeter (anahtar döndürmede birkaç tane gelir).
    for candidate in signatures.split(" ")[:32]:
        version, _, value = candidate.partition(",")
        if version != "v1" or not value:
            continue
        try:
            mac = _decode(value)
        except (binascii.Error, ValueError):
            continue
        if hmac.compare_digest(mac, expected):  # sabit zamanlı karşılaştırma
            return True
    return False
