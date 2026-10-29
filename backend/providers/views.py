from django.conf import settings
from django.http import HttpResponse
from rest_framework.decorators import api_view
from rest_framework.response import Response

from .registry import all_providers
from .serializers import ProviderSerializer, SkyImageRequestSerializer
from .services import get_sky_image


@api_view(["GET"])
def providers(request):
    data = ProviderSerializer([p.metadata() for p in all_providers()], many=True).data
    return Response({"default": settings.DEFAULT_PROVIDER, "providers": data})


@api_view(["POST"])
def sky_image(request):
    s = SkyImageRequestSerializer(data=request.data)
    s.is_valid(raise_exception=True)
    d = s.validated_data
    result = get_sky_image(d["ra"] % 360, d["dec"], d["fov"], d["rotation"] % 360,
                           d["provider"] or None, d["width"], d["height"])
    resp = HttpResponse(result.data, content_type="image/jpeg")
    resp["X-Provider"] = result.provider.key
    resp["X-Provider-Name"] = result.provider.name
    resp["X-Credit"] = _ascii(result.provider.credit)
    resp["X-Fallback-Used"] = "true" if result.fallback_used else "false"
    if result.fallback_used:
        resp["X-Fallback-Reason"] = result.fallback_reason
        resp["X-Fallback-Message"] = _ascii(result.message)
    resp["Cache-Control"] = "public, max-age=86400"
    return resp


def _ascii(text: str) -> str:
    """Keep headers plain ASCII (common symbols spelled out, anything else dropped)."""
    for src, dst in (("≤", "<="), ("≥", ">="), ("°", " deg"), ("’", "'")):
        text = text.replace(src, dst)
    return text.encode("ascii", "ignore").decode()
