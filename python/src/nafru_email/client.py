import os
import re
from typing import Callable, Optional

from . import SDK_VERSION
from ._http import DeprecationNotice, Http, Transport, mask_secret, urllib_transport
from .app import Connect, Connection, OnTokenRefresh, TokenManager
from .dev_outbox import DevOutbox, resolve_dev_outbox
from .resources import (
    ApiKeys,
    BrandResource,
    Broadcasts,
    ContactProperties,
    Contacts,
    Domains,
    Emails,
    Events,
    Segments,
    Templates,
    Topics,
    Webhooks,
)

USER_AGENT = f"nafru-email-python/{SDK_VERSION}"

#: Nafru Email üretim API'si; `base_url` verilmezse (ya da boşsa) kullanılır.
DEFAULT_BASE_URL = "https://email.nafru.com/api"


class NafruEmail:
    """API anahtarlı istemci.

    - `api_key`: Dashboard'dan üretilen anahtar; verilmezse `NAFRU_API_KEY` ortam değişkeni. Yalnız sunucuda; `sending_access` anahtarı bile e-posta gönderebilir.
    - `base_url`: API kök adresi; varsayılan `DEFAULT_BASE_URL` (yerelde `http://localhost:48787/api`).
    - `transport`: özel HTTP taşıyıcısı (test, proxy).
    - `max_retries`: `429` ve güvenli isteklerde sunucu/ağ hatası için yeniden deneme; varsayılan 2, `0` kapatır.
    - `timeout`: istek başına zaman aşımı (saniye); varsayılan 30.
    - `dev_outbox`: verilirse `emails.send`/`batch` gönderim yapmaz, bu klasöre `.txt` + `.html` yazar. Varsayılan:
      `NODE_ENV=development` iken `.nafru/emails`, aksi hâlde kapalı; `False` her zaman gerçek gönderim.
    """

    def __init__(
        self,
        api_key: Optional[str] = None,
        base_url: Optional[str] = None,
        *,
        transport: Optional[Transport] = None,
        max_retries: int = 2,
        timeout: float = 30.0,
        dev_outbox: DevOutbox = None,
    ) -> None:
        # Resend gibi: anahtar verilmezse ortamdan okunur.
        api_key = api_key or os.environ.get("NAFRU_API_KEY")
        if not api_key:
            raise ValueError("Nafru SDK: api_key gerekli (ya da NAFRU_API_KEY ortam değişkeni)")
        self._base_url = base_url or DEFAULT_BASE_URL
        self._api_key = api_key
        http = Http(
            api_key=api_key,
            base_url=self._base_url,
            transport=transport or urllib_transport,
            max_retries=max_retries,
            timeout=timeout,
            user_agent=USER_AGENT,
            deprecation=DeprecationNotice(SDK_VERSION),
        )
        self.emails = Emails(http, resolve_dev_outbox(dev_outbox))
        self.domains = Domains(http)
        self.contacts = Contacts(http)
        self.contact_properties = ContactProperties(http)
        self.segments = Segments(http)
        self.topics = Topics(http)
        self.broadcasts = Broadcasts(http)
        self.templates = Templates(http)
        self.brand = BrandResource(http)
        self.webhooks = Webhooks(http)
        self.api_keys = ApiKeys(http)
        self.events = Events(http)

    def __repr__(self) -> str:
        return f"NafruEmail(base_url={self._base_url!r}, api_key={mask_secret(self._api_key)})"


class NafruConnect(Connect):
    """"Nafru ile bağlan" istemcisi: müşterinin Nafru Email hesabına tek tıkla bağlanır, o hesap adına gönderir.
    Tek alan adı/anahtar için `NafruEmail("nafru_...")` kullanın.

    - `client_id`: kayıtlı uygulamanın `app_…` kimliği. `client_secret`: yalnız sunucunuzda.
    - `base_url`: API kök adresi; varsayılan `DEFAULT_BASE_URL`.
    - `web_url`: izin ekranının kök adresi; verilmezse `base_url` sonundaki `/api` atılır.

    `authorize_url`, `exchange`, `revoke` ve `connection` doğrudan bu nesnededir.
    """

    def __init__(
        self,
        client_id: str,
        client_secret: str,
        base_url: Optional[str] = None,
        *,
        web_url: Optional[str] = None,
        transport: Optional[Transport] = None,
        max_retries: int = 2,
        timeout: float = 30.0,
        dev_outbox: DevOutbox = None,
    ) -> None:
        if not client_id:
            raise ValueError("Nafru SDK: client_id gerekli")
        if not client_secret:
            raise ValueError("Nafru SDK: client_secret gerekli")
        base_url = base_url or DEFAULT_BASE_URL
        self._dev_outbox = resolve_dev_outbox(dev_outbox)
        deprecation = DeprecationNotice(SDK_VERSION)

        def make_http(authorize: Callable[[], Optional[str]]) -> Http:
            return Http(
                api_key="",
                base_url=base_url,
                transport=transport or urllib_transport,
                max_retries=max_retries,
                timeout=timeout,
                user_agent=USER_AGENT,
                authorize=authorize,
                deprecation=deprecation,
            )

        self._make_http = make_http
        # Token uçları kimlik bilgisini gövdede taşır; Authorization başlığı yok.
        super().__init__(make_http(lambda: None), client_id, client_secret, web_url or re.sub(r"/api/*$", "", base_url))

    def __repr__(self) -> str:
        return f"NafruConnect(client_id={self._client_id!r}, client_secret={mask_secret(self._client_secret)})"

    def connection(self, connection_id: str, *, refresh_token: str, on_token_refresh: OnTokenRefresh) -> Connection:
        """Saklanan yenileme belirteciyle bir müşteri bağlantısı. Yenileme otomatiktir; yeni belirteç `on_token_refresh` ile gelir
        ve KALICI yazılmadan eskisi geçersizdir. Geri çağrı hata fırlatırsa çağrı `token_persist_failed` ile fırlar."""
        tokens = TokenManager(self._oauth, self._client_id, self._client_secret, refresh_token, on_token_refresh)
        return Connection(connection_id, self._make_http, tokens, self._dev_outbox)
