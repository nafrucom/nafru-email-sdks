import ipaddress
import json
import re
import socket
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, Mapping, Optional
from urllib.parse import quote, urlencode, urlsplit

from .errors import NafruError, network_error, parse_error, timeout_error

MAX_BACKOFF = 8.0
BASE_BACKOFF = 0.3
#: Yanıt gövdesi üst sınırı: bozuk ya da kötü niyetli bir ara katman belleği tüketemesin.
MAX_RESPONSE_BYTES = 10 * 1024 * 1024
_CONTROL_CHARS = re.compile(r"[\x00-\x1f\x7f]")


def mask_secret(value: Optional[str]) -> str:
    """Gizli değeri yazdırılabilir kılar: önek korunur (`nafru_****`), gerisi gizlenir."""
    if not value:
        return "''"
    prefix, sep, _ = value.partition("_")
    return f"'{prefix}_****'" if sep and len(prefix) <= 8 else "'[REDACTED]'"


def _is_loopback(host: str) -> bool:
    host = host.lower()
    if host == "localhost" or host.endswith(".localhost"):
        return True
    try:
        return ipaddress.ip_address(host).is_loopback
    except ValueError:
        return False


def require_https(url: str, name: str) -> None:
    """Kimlik bilgisi düz metin gitmesin: http yalnız yerel geliştirme adreslerinde kabul edilir."""
    parts = urlsplit(url)
    if parts.scheme == "https" and parts.hostname:
        return
    if parts.scheme == "http" and parts.hostname and _is_loopback(parts.hostname):
        return
    raise ValueError(f"Nafru SDK: {name} https kullanmalı (http yalnız localhost için)")


def invalid_argument(message: str) -> NafruError:
    return NafruError(None, "invalid_argument", message)


@dataclass
class HttpRequest:
    method: str
    url: str
    headers: Dict[str, str]
    body: Optional[bytes]
    #: Saniye.
    timeout: float

    def __repr__(self) -> str:
        headers = {k: ("[REDACTED]" if k == "authorization" else v) for k, v in self.headers.items()}
        return f"HttpRequest(method={self.method!r}, url={self.url!r}, headers={headers!r}, timeout={self.timeout!r})"


@dataclass
class HttpResponse:
    status: int
    #: Başlık adları küçük harfle.
    headers: Dict[str, str] = field(default_factory=dict)
    body: bytes = b""
    reason: str = ""


#: Özel taşıyıcı (test, proxy). İstisna fırlatırsa ağ hatası sayılır; `TimeoutError`/`socket.timeout` zaman aşımıdır.
Transport = Callable[[HttpRequest], HttpResponse]


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """API asla yönlendirmez; yönlendirme izlenirse `Authorization` başka bir sunucuya sızabilir. 3xx olduğu gibi döner."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):  # type: ignore[no-untyped-def]
        return None


# Sertifika doğrulaması varsayılan bağlamla hep açık; kapatma seçeneği yoktur.
_OPENER = urllib.request.build_opener(_NoRedirect)


def urllib_transport(request: HttpRequest) -> HttpResponse:
    req = urllib.request.Request(request.url, data=request.body, headers=request.headers, method=request.method)
    try:
        with _OPENER.open(req, timeout=request.timeout) as response:
            return HttpResponse(
                response.status,
                {k.lower(): v for k, v in response.headers.items()},
                response.read(MAX_RESPONSE_BYTES + 1),
                response.reason,
            )
    except urllib.error.HTTPError as error:
        headers = {k.lower(): v for k, v in (error.headers or {}).items()}
        return HttpResponse(error.code, headers, error.read(MAX_RESPONSE_BYTES + 1), error.reason)
    except urllib.error.URLError as error:
        if isinstance(error.reason, (socket.timeout, TimeoutError)):
            raise TimeoutError(str(error.reason)) from error
        raise


class DeprecationNotice:
    """İstemci başına tek uyarı: aynı istemcinin tüm `Http` örnekleri bunu paylaşır."""

    def __init__(self, version: str) -> None:
        self.version = version
        self.warned = False

    def check(self, headers: Dict[str, str]) -> None:
        if self.warned or "deprecation" not in headers:
            return
        self.warned = True
        message = f"[nafru] Bu SDK sürümü (python {self.version}) kullanımdan kaldırıldı; lütfen güncelleyin."
        if headers.get("sunset"):
            message += f" Son tarih: {headers['sunset']}"
        link = re.search(r"<([^>]+)>", headers.get("link", "")) or re.match(r"\s*(\S+)", headers.get("link", ""))
        if link:
            message += f" Ayrıntı: {link.group(1)}"
        print(message, file=sys.stderr)


def seg(value: str) -> str:
    """Yol parçası: kimlik ya da e-posta (kişi uçları e-postayı kimlik gibi kabul eder) güvenle kaçırılır (`encodeURIComponent`).
    Boş, `.` ve `..` reddedilir: URL normalleştirmesi onları başka bir uca çevirirdi."""
    if not isinstance(value, str) or value in ("", ".", ".."):
        raise invalid_argument(f"Geçersiz yol parçası: {value!r}")
    return quote(value, safe="-_.!~*'()")


def serialize_query(query: Optional[Mapping[str, Any]]) -> str:
    pairs = []
    for key, value in (query or {}).items():
        if value is None or value == "":
            continue
        pairs.append((key, ("true" if value else "false") if isinstance(value, bool) else str(value)))
    return f"?{urlencode(pairs)}" if pairs else ""


class Http:
    """`GET` ve `DELETE` yinelenebilir; `POST`/`PATCH` yalnız istek işlenmeden reddedildiyse (429) ya da `Idempotency-Key`
    taşıyorsa yinelenir: anahtarsız sunucu hatasında e-posta çift gidebilir."""

    def __init__(
        self,
        *,
        api_key: str,
        base_url: str,
        transport: Transport,
        max_retries: int,
        timeout: float,
        user_agent: str,
        authorize: Optional[Callable[[], Optional[str]]] = None,
        deprecation: Optional[DeprecationNotice] = None,
    ) -> None:
        #: Uyarı hiçbir zaman çağrıyı bozmaz; verilmezse bu örneğe özel.
        self._deprecation = deprecation or DeprecationNotice(user_agent.rsplit("/", 1)[-1])
        require_https(base_url, "base_url")
        self._api_key = api_key
        self._base = base_url.rstrip("/")
        self._transport = transport
        self._max_retries = max_retries
        self._timeout = timeout
        self._user_agent = user_agent
        #: Verilirse `api_key` yerine her denemede bundan alınan belirteç kullanılır (`None`: başlık yok); hata fırlatırsa istek gitmez.
        self._authorize = authorize

    def request(
        self,
        method: str,
        path: str,
        *,
        query: Optional[Mapping[str, Any]] = None,
        body: Any = None,
        idempotency_key: Optional[str] = None,
    ) -> Any:
        headers = {"accept": "application/json", "user-agent": self._user_agent}
        if self._authorize is None:
            headers["authorization"] = f"Bearer {self._api_key}"
        data: Optional[bytes] = None
        if body is not None:
            data = json.dumps(body, ensure_ascii=False).encode("utf-8")
            headers["content-type"] = "application/json"
        if idempotency_key is not None:
            # Başlık enjeksiyonu: CR/LF ve diğer denetim karakterleri yeni başlık açabilir.
            if not idempotency_key or _CONTROL_CHARS.search(idempotency_key):
                raise invalid_argument("idempotency_key boş olamaz ve denetim karakteri içeremez")
            headers["idempotency-key"] = idempotency_key
        url = f"{self._base}{path}{serialize_query(query)}"
        safe = method in ("GET", "DELETE") or idempotency_key is not None

        attempt = 0
        while True:
            if self._authorize is not None:
                token = self._authorize()
                if token is None:
                    headers.pop("authorization", None)
                else:
                    headers["authorization"] = f"Bearer {token}"
            last = attempt >= self._max_retries
            try:
                response = self._transport(HttpRequest(method, url, dict(headers), data, self._timeout))
            except Exception as cause:  # noqa: BLE001 — taşıyıcının her hatası ağ hatasıdır
                if not last and safe:
                    time.sleep(min(BASE_BACKOFF * 2**attempt, MAX_BACKOFF))
                    attempt += 1
                    continue
                if isinstance(cause, (TimeoutError, socket.timeout)):
                    raise timeout_error(self._timeout) from cause
                raise network_error(str(cause) or "Sunucuya ulaşılamadı") from cause

            response_headers = {k.lower(): v for k, v in response.headers.items()}
            try:
                self._deprecation.check(response_headers)
            except Exception:  # noqa: BLE001 — uyarı çağrıyı asla bozmaz
                pass
            if len(response.body) > MAX_RESPONSE_BYTES:
                raise NafruError(response.status, "response_too_large", "Yanıt gövdesi 10 MB sınırını aşıyor")
            if 300 <= response.status < 400:
                raise NafruError(response.status, "unexpected_redirect", "API yönlendirme döndürdü; izlenmedi")
            payload = _read_body(response.body)
            if 200 <= response.status < 300:
                return payload

            error = parse_error(response.status, response.reason, response_headers, payload)
            retryable = response.status == 429 or (response.status >= 500 and safe)
            if retryable and not last:
                wait = error.retry_after if error.retry_after is not None else BASE_BACKOFF * 2**attempt
                time.sleep(min(wait, MAX_BACKOFF))
                attempt += 1
                continue
            raise error


def _read_body(raw: bytes) -> Any:
    if not raw:
        return None
    try:
        return json.loads(raw)
    except ValueError:
        return None
