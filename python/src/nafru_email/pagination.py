from typing import Any, Callable, Dict, Iterator, Optional


def paginate(list_fn: Callable[..., Any], **query: Any) -> Iterator[Dict[str, Any]]:
    """Bir liste çağrısını tüm sayfalar boyunca gezer (`after` imleci). Hata `NafruError` olarak fırlar: sayfalama döngüsünde
    sessizce kesmek eksik veri okutur. Kimlik isteyen listelerde `functools.partial(nafru.contacts.topics.list, "c1")` verin."""
    query.pop("after", None)
    query.pop("before", None)
    after: Optional[str] = None
    while True:
        page = list_fn(**query, **({"after": after} if after else {}))
        items = page["data"]
        yield from items
        if not page.get("has_more") or not items:
            return
        after = items[-1]["id"]
