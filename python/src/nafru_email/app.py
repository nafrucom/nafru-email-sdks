""""Nafru ile bağlan": PKCE'li izin adresi, kod takası, iptal ve müşteri bağlantısı adına çağrılar."""

import base64
import hashlib
import secrets
import threading
import time
from concurrent.futures import Future
from dataclasses import dataclass
from typing import Any, Callable, List, Optional, Tuple, cast
from urllib.parse import urlencode

from ._http import Http, mask_secret, require_https
from .errors import NafruError
from .resources import Emails
from .types import (
    AuthorizeUrl,
    ConnectionSenders,
    ConnectionStatus,
    Email,
    ListResponse,
    SendEmailInput,
    SendEmailResponse,
)

#: Süre dolmadan bu kadar önce yenilenir (saat farkı ve ağ gecikmesi payı).
EARLY_REFRESH_SECONDS = 30.0

@dataclass(frozen=True)
class ConnectionGrant:
    """`exchange` sonucu. `refresh_token`'ı şifreleyerek saklayın; her yenilemede değişir (`on_token_refresh`)."""

    #: `conn_…`: müşteri bağlantısının kalıcı kimliği.
    connection_id: str
    refresh_token: str
    scopes: List[str]

    def __repr__(self) -> str:
        return (
            f"ConnectionGrant(connection_id={self.connection_id!r}, refresh_token={mask_secret(self.refresh_token)}, "
            f"scopes={self.scopes!r})"
        )


@dataclass(frozen=True)
class ConnectionTokens:
    """`on_token_refresh`'e gelen yeni belirteç; kalıcı yazılmadan eskisi geçersizdir."""

    refresh_token: str

    def __repr__(self) -> str:
        return f"ConnectionTokens(refresh_token={mask_secret(self.refresh_token)})"


OnTokenRefresh = Callable[[ConnectionTokens], Any]


def _base64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def create_pkce() -> Tuple[str, str]:
    """PKCE (S256): 32 rastgele bayttan 43 karakterlik doğrulayıcı ve SHA-256 sınaması: `(verifier, challenge)`."""
    verifier = _base64url(secrets.token_bytes(32))
    return verifier, _base64url(hashlib.sha256(verifier.encode("ascii")).digest())


class Connect:
    def __init__(self, oauth: Http, client_id: str, client_secret: str, web_url: str) -> None:
        require_https(web_url, "web_url")
        self._oauth = oauth
        self._client_id = client_id
        self._client_secret = client_secret
        self._web = web_url.rstrip("/")

    def authorize_url(
        self, *, redirect_uri: str, state: str, scopes: List[str], login_hint: Optional[str] = None
    ) -> AuthorizeUrl:
        """Müşteriyi yönlendireceğiniz "Nafru ile bağlan" adresi. `code_verifier`'ı oturumda saklayın; dönüşte `exchange`'e verin.
        Dönüşte `state`'i kendi sakladığınız değerle karşılaştırmak sizin sorumluluğunuzdur."""
        if not state:
            raise ValueError("Nafru SDK: state gerekli (CSRF koruması)")
        if not scopes:
            raise ValueError("Nafru SDK: en az bir izin (scopes) gerekli")
        verifier, challenge = create_pkce()
        params = {
            "client_id": self._client_id,
            "redirect_uri": redirect_uri,
            "state": state,
            "scope": " ".join(scopes),
            "code_challenge": challenge,
            "code_challenge_method": "S256",
        }
        if login_hint:
            params["login_hint"] = login_hint
        return {"url": f"{self._web}/connect?{urlencode(params)}", "code_verifier": verifier}

    def exchange(self, *, code: str, code_verifier: str, redirect_uri: str) -> ConnectionGrant:
        """Dönüşteki tek kullanımlık `code`'u bağlantıya çevirir (sunucunuzdan çağırın)."""
        data = self._oauth.request(
            "POST",
            "/oauth/token",
            body={
                "grant_type": "authorization_code",
                "client_id": self._client_id,
                "client_secret": self._client_secret,
                "code": code,
                "code_verifier": code_verifier,
                "redirect_uri": redirect_uri,
            },
        )
        return ConnectionGrant(data["connection_id"], data["refresh_token"], data["scopes"])

    def revoke(self, *, refresh_token: str) -> None:
        """Bağlantıyı uygulama tarafından iptal eder (müşteri hesabını kapattığında). Belirteçler anında geçersiz olur."""
        self._oauth.request(
            "POST",
            "/oauth/revoke",
            body={"client_id": self._client_id, "client_secret": self._client_secret, "token": refresh_token},
        )


def _revoked(cause: NafruError) -> NafruError:
    error = NafruError(
        cause.status_code,
        "connection_revoked",
        "Bağlantı iptal edilmiş ya da yenileme belirteci geçersiz; müşterinin yeniden bağlanması gerekir.",
        cause.errors,
        cause.retry_after,
    )
    error.__cause__ = cause
    return error


class TokenManager:
    """Bağlantının erişim belirtecini tutar ve yeniler. Eşzamanlı çağrılar TEK yenilemeyi paylaşır (tek uçuş): dönüşlü yenileme
    belirteci ikinci bir eşzamanlı yenilemede "yeniden kullanım" sayılır ve bağlantıyı iptal ettirirdi."""

    def __init__(
        self, oauth: Http, client_id: str, client_secret: str, refresh_token: str, on_token_refresh: OnTokenRefresh
    ) -> None:
        self._oauth = oauth
        self._client_id = client_id
        self._client_secret = client_secret
        self._refresh_token = refresh_token
        self._on_token_refresh = on_token_refresh
        self._access_token: Optional[str] = None
        self._expires_at = 0.0
        self._lock = threading.Lock()
        self._inflight: Optional["Future[str]"] = None
        #: Yenileme sunucuda başarılı oldu ama yeni yenileme belirteci saklanamadı: eski belirteç artık geçersiz, bu kaybolmamalı.
        self._unpersisted = False

    def _persist(self) -> None:
        try:
            self._on_token_refresh(ConnectionTokens(self._refresh_token))
            self._unpersisted = False
        except Exception as cause:  # noqa: BLE001 — geri çağrının her hatası saklama hatasıdır
            self._unpersisted = True
            raise NafruError(None, "token_persist_failed", f"Yeni yenileme belirteci saklanamadı: {cause}") from cause

    def _do_refresh(self) -> str:
        try:
            data = self._oauth.request(
                "POST",
                "/oauth/token",
                body={
                    "grant_type": "refresh_token",
                    "client_id": self._client_id,
                    "client_secret": self._client_secret,
                    "refresh_token": self._refresh_token,
                },
            )
        except NafruError as error:
            # Geçersiz/tüketilmiş belirteç ya da iptal: kalıcı hata. Ağ ve 5xx geçici hata olarak olduğu gibi fırlar.
            if error.name in ("invalid_grant", "connection_revoked") or (
                error.status_code == 403 and error.name != "rate_limit_exceeded"
            ):
                raise _revoked(error) from error
            raise
        self._refresh_token = data["refresh_token"]
        self._access_token = data["access_token"]
        self._expires_at = time.time() + float(data["expires_in"])
        self._persist()
        return cast(str, data["access_token"])

    def _refresh(self) -> str:
        with self._lock:
            future = self._inflight
            owner = future is None
            if future is None:
                future = self._inflight = Future()
        if owner:
            try:
                future.set_result(self._do_refresh())
            except BaseException as error:  # noqa: BLE001 — bekleyen tüm çağrılar aynı hatayı alır
                future.set_exception(error)
            finally:
                with self._lock:
                    self._inflight = None
        return future.result()

    def access_token(self) -> str:
        """Geçerli erişim belirteci; yoksa ya da dolmak üzereyse tek uçuşla yeniler."""
        if self._unpersisted:
            self._persist()
        token = self._access_token
        if token is not None and time.time() < self._expires_at - EARLY_REFRESH_SECONDS:
            return token
        return self._refresh()

    def invalidate(self, stale: str) -> str:
        """Sunucu 401 `invalid_token` dedi: eldeki belirteci at ve yenile (aynı belirteçle eşzamanlı 401'ler tek yenilemeyi paylaşır)."""
        with self._lock:
            if self._access_token == stale:
                self._access_token = None
            token = self._access_token
        return token if token is not None else self._refresh()


class _ConnectionHttp:
    """`Http` her denemede belirteci `TokenManager`'dan alır; 401 `invalid_token` (süre dolmuş / yenilenmiş) ise bir kez yenileyip tekrar dener."""

    def __init__(self, make_http: Callable[[Callable[[], Optional[str]]], Http], tokens: TokenManager) -> None:
        self._tokens = tokens
        self._local = threading.local()
        self._http = make_http(self._authorize)

    def _authorize(self) -> Optional[str]:
        token = self._tokens.access_token()
        self._local.current = token
        return token

    def request(self, method: str, path: str, **kwargs: Any) -> Any:
        self._local.current = None
        try:
            return self._http.request(method, path, **kwargs)
        except NafruError as error:
            current = getattr(self._local, "current", None)
            if error.name != "invalid_token" or current is None:
                raise
        self._tokens.invalidate(current)
        return self._http.request(method, path, **kwargs)


class ConnectionEmails:
    def __init__(self, emails: Emails) -> None:
        self._emails = emails

    def send(self, params: SendEmailInput, *, idempotency_key: Optional[str] = None) -> SendEmailResponse:
        return self._emails.send(params, idempotency_key=idempotency_key)

    def get(self, id: str) -> Email:
        return self._emails.get(id)

    def list(
        self,
        *,
        limit: Optional[int] = None,
        after: Optional[str] = None,
        before: Optional[str] = None,
        status: Optional[str] = None,
    ) -> ListResponse:
        """Öğeler: `EmailListItem`."""
        return self._emails.list(limit=limit, after=after, before=before, status=status)


class ConnectionSendersResource:
    def __init__(self, http: _ConnectionHttp) -> None:
        self._http = http

    def list(self) -> ConnectionSenders:
        return cast(ConnectionSenders, self._http.request("GET", "/senders"))


class ConnectionTemplatesResource:
    def __init__(self, http: _ConnectionHttp) -> None:
        self._http = http

    def list(self) -> ListResponse:
        """Öğeler: `ConnectionTemplate`. Müşterinin yayınlanmış şablonları ile uygulamanın paketi: anahtar başına tek öğe."""
        return cast(ListResponse, self._http.request("GET", "/templates"))


class Connection:
    """Bir müşteri bağlantısı adına çağrı yapar. Yönetim uçları yoktur; yalnız gönderim, okuma ve keşif."""

    def __init__(
        self,
        connection_id: str,
        make_http: Callable[[Callable[[], Optional[str]]], Http],
        tokens: TokenManager,
        dev_outbox: Optional[str],
    ) -> None:
        self.id = connection_id
        self._http = _ConnectionHttp(make_http, tokens)
        self.senders = ConnectionSendersResource(self._http)
        self.templates = ConnectionTemplatesResource(self._http)
        self.emails = ConnectionEmails(Emails(cast(Http, self._http), dev_outbox))

    def status(self) -> ConnectionStatus:
        """`GET /connection`: hazır mı, eksik ne, ücret modu ve müşterinin kurulum adresi."""
        return cast(ConnectionStatus, self._http.request("GET", "/connection"))
