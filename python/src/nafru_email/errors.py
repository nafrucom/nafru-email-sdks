from typing import Any, Dict, List, Mapping, Optional

from .types import NafruFieldError

NAMES_BY_STATUS: Dict[int, str] = {
    400: "invalid_request",
    401: "unauthorized",
    403: "forbidden",
    404: "not_found",
    409: "conflict",
    413: "payload_too_large",
    422: "validation_error",
    429: "rate_limit_exceeded",
}


class NafruError(Exception):
    """Her başarısız çağrının fırlattığı hata. `status_code` ağ hatalarında `None`'dır. `name`, sunucunun hata adıdır
    (`validation_error`, `rate_limit_exceeded`, `not_found`, …); ağ ve zaman aşımı için `application_error` / `timeout_error`."""

    def __init__(
        self,
        status_code: Optional[int],
        name: str,
        message: str,
        errors: Optional[List[NafruFieldError]] = None,
        retry_after: Optional[float] = None,
    ) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.name = name
        self.message = message
        self.errors: List[NafruFieldError] = errors or []
        #: `429` yanıtındaki `retry-after` (saniye).
        self.retry_after = retry_after

    def __repr__(self) -> str:
        return f"NafruError(status_code={self.status_code!r}, name={self.name!r}, message={self.message!r})"


def network_error(message: str) -> NafruError:
    return NafruError(None, "application_error", message)


def timeout_error(timeout: float) -> NafruError:
    return NafruError(None, "timeout_error", f"İstek {int(timeout * 1000)} ms içinde tamamlanmadı")


def _read_retry_after(headers: Mapping[str, str]) -> Optional[float]:
    value = headers.get("retry-after")
    if value is None:
        return None
    try:
        number = float(value)
    except ValueError:
        return None
    return number if number >= 0 and number != float("inf") else None


def parse_error(status: int, reason: str, headers: Mapping[str, str], body: Any) -> NafruError:
    """Standart gövde (`statusCode`, `name`, `message`, `errors`) yoksa durumdan makul bir hata kurar (ara katman HTML'i, boş gövde)."""
    retry_after = _read_retry_after(headers)
    fallback = NAMES_BY_STATUS.get(status, "application_error")
    if isinstance(body, dict) and isinstance(body.get("message"), str):
        errors: List[NafruFieldError] = []
        for entry in body.get("errors") or []:
            if not isinstance(entry, dict):
                continue
            item: NafruFieldError = {
                "field": entry["field"] if isinstance(entry.get("field"), str) else "",
                "message": entry["message"] if isinstance(entry.get("message"), str) else "",
            }
            if isinstance(entry.get("i18nTranslationKey"), str):
                item["i18nTranslationKey"] = entry["i18nTranslationKey"]
            errors.append(item)
        code = body.get("statusCode")
        name = body.get("name")
        return NafruError(
            code if isinstance(code, int) and not isinstance(code, bool) else status,
            name if isinstance(name, str) else fallback,
            body["message"],
            errors,
            retry_after,
        )
    return NafruError(status, fallback, reason or f"HTTP {status}", None, retry_after)
