"""Nafru Email için resmi Python SDK'sı (yalnız standart kitaplık)."""

SDK_VERSION = "0.1.1"
__version__ = SDK_VERSION

from ._http import HttpRequest, HttpResponse, Transport  # noqa: E402
from .app import Connection, ConnectionGrant, ConnectionTokens, create_pkce  # noqa: E402
from .client import DEFAULT_BASE_URL, NafruConnect, NafruEmail  # noqa: E402
from .dev_outbox import resolve_dev_outbox  # noqa: E402
from .errors import NafruError  # noqa: E402
from .pagination import paginate  # noqa: E402
from .webhook import verify_webhook  # noqa: E402

__all__ = [
    "DEFAULT_BASE_URL",
    "SDK_VERSION",
    "Connection",
    "ConnectionGrant",
    "ConnectionTokens",
    "HttpRequest",
    "HttpResponse",
    "NafruConnect",
    "NafruEmail",
    "NafruError",
    "Transport",
    "create_pkce",
    "paginate",
    "resolve_dev_outbox",
    "verify_webhook",
]
