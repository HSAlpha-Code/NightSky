"""Shared HTTP helper: timeouts + simple retry with backoff for all external calls."""
import logging
import time

import httpx
from django.conf import settings

log = logging.getLogger(__name__)

RETRY_STATUS = {429, 500, 502, 503, 504}
USER_AGENT = "NightSkyReplacement/0.1 (+https://github.com/)"


class ExternalServiceError(Exception):
    """Raised when an external service fails after all retries."""


def http_get(url: str, params: dict | None = None, timeout: float | None = None,
             retries: int | None = None) -> httpx.Response:
    timeout = timeout if timeout is not None else settings.HTTP_TIMEOUT_SECONDS
    retries = retries if retries is not None else settings.HTTP_RETRIES
    limits = httpx.Timeout(timeout, connect=min(timeout, settings.HTTP_CONNECT_TIMEOUT_SECONDS))
    last_error: Exception | None = None
    for attempt in range(retries + 1):
        try:
            resp = httpx.get(url, params=params, timeout=limits, follow_redirects=True,
                             headers={"User-Agent": USER_AGENT})
            if resp.status_code in RETRY_STATUS:
                last_error = ExternalServiceError(f"HTTP {resp.status_code} from {url}")
            else:
                resp.raise_for_status()
                return resp
        except httpx.HTTPStatusError as exc:  # non-retryable 4xx
            raise ExternalServiceError(f"HTTP {exc.response.status_code} from {url}") from exc
        except httpx.HTTPError as exc:
            last_error = exc
        if attempt < retries:
            delay = 1.5 * (2 ** attempt)
            log.warning("GET %s failed (%s), retrying in %.1fs", url, last_error, delay)
            time.sleep(delay)
    raise ExternalServiceError(f"GET {url} failed: {last_error}") from last_error
