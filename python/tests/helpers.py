import json
from typing import Any, Callable, List, Optional, Union

from nafru_email import HttpRequest, HttpResponse, NafruEmail


def json_response(body: Any, status: int = 200, headers: Optional[dict] = None, reason: str = "") -> HttpResponse:
    return HttpResponse(status, {"content-type": "application/json", **(headers or {})}, json.dumps(body).encode(), reason)


class Recorder:
    """Sahte taşıyıcı: yanıtları sırayla verir, son yanıtı tekrarlar; çağrıları kaydeder."""

    def __init__(self, responses: List[Union[HttpResponse, Callable[[HttpRequest], HttpResponse]]]) -> None:
        self.responses = responses
        self.calls: List[HttpRequest] = []

    def __call__(self, request: HttpRequest) -> HttpResponse:
        nxt = self.responses[min(len(self.calls), len(self.responses) - 1)]
        self.calls.append(request)
        return nxt(request) if callable(nxt) else nxt

    def json(self, index: int) -> Any:
        body = self.calls[index].body
        return json.loads(body) if body is not None else None


def setup(responses: list, max_retries: int = 0):
    recorder = Recorder(responses)
    nafru = NafruEmail("key_test", "https://api.test/", transport=recorder, max_retries=max_retries, dev_outbox=False)
    return nafru, recorder
