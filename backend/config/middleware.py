"""Default security headers; public legal HTML explicitly permits its inline stylesheet."""


class SecurityHeadersMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        response = self.get_response(request)
        response.headers.setdefault("Content-Security-Policy",
                                    "default-src 'none'; frame-ancestors 'none'")
        response.headers.setdefault("Permissions-Policy",
                                    "camera=(), microphone=(), geolocation=()")
        return response
