"""Per-client rate limits. Anonymous API, so clients are identified by IP address."""
from rest_framework.throttling import AnonRateThrottle


class HeavyRateThrottle(AnonRateThrottle):
    """Stricter limit for endpoints that render images or fan out to upstream services."""
    scope = "heavy"
