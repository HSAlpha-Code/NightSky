"""Local curator endpoints + page. Every write needs the X-Curator header (blocks other
websites from posting to localhost) and the host must be 127.0.0.1/localhost."""
import json
from pathlib import Path

from django.conf import settings
from django.db.models import Count
from django.http import HttpResponse, HttpResponseForbidden, JsonResponse
from django.views.decorators.http import require_http_methods

from curated.models import CuratedHighlight
from curated.repo import thumb_name
from landmarks.catalog import get_catalog

import curator_images
from curator_export import export_bundle

PAGE = Path(__file__).with_name("curator_page.html")
FIELDS = ("title", "source_outlet", "source_url", "credit", "caption")


class CuratorGuardMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        if request.method not in ("GET", "HEAD") and request.headers.get("X-Curator") != "1":
            return HttpResponseForbidden("Missing X-Curator header")
        response = self.get_response(request)
        response["Cache-Control"] = "no-store"
        return response


def _media() -> Path:
    return Path(settings.CURATED_MEDIA_ROOT)


def _item(h: CuratedHighlight) -> dict:
    return {"id": h.id, "body_id": h.body_id, "body_name": h.body_name, "enabled": h.enabled,
            "sort_order": h.sort_order, "image_url": f"/media/{h.image_file}",
            "thumbnail_url": f"/media/{thumb_name(h.image_file)}",
            **{f: getattr(h, f) for f in FIELDS}}


def _counts() -> dict:
    return {r["body_id"]: r["n"] for r in
            CuratedHighlight.objects.values("body_id").annotate(n=Count("id"))}


def page(request):
    return HttpResponse(PAGE.read_text(encoding="utf-8"), content_type="text/html; charset=utf-8")


def bodies(request):
    """Search the catalogue (name, id, alias); no query = bodies that already have highlights."""
    q = request.GET.get("q", "").strip().lower()
    counts = _counts()
    catalog = get_catalog()
    if not q:
        out = []
        for body_id, n in sorted(counts.items()):
            lm = catalog.get(body_id)
            name = lm.name if lm else CuratedHighlight.objects.filter(
                body_id=body_id).values_list("body_name", flat=True).first()
            out.append({"id": body_id, "name": name, "type": lm.type_label if lm else "", "count": n})
        return JsonResponse({"bodies": out})
    found = []
    for lm in catalog.landmarks:
        hay = [lm.id.lower(), lm.name.lower(), *(a.lower() for a in lm.aliases)]
        if any(q in h for h in hay):
            exact = q in hay
            found.append((not exact, lm.magnitude if lm.magnitude is not None else 99, lm))
    found.sort(key=lambda t: t[:2])
    return JsonResponse({"bodies": [
        {"id": lm.id, "name": lm.name, "type": lm.type_label, "count": counts.get(lm.id, 0),
         "aliases": list(lm.aliases)[:3]} for _, _, lm in found[:40]]})


def _apply(h: CuratedHighlight, data) -> None:
    for f in FIELDS:
        if f in data:
            setattr(h, f, str(data[f]).strip())


@require_http_methods(["GET", "POST"])
def highlights(request):
    if request.method == "GET":
        body_id = request.GET.get("body_id", "")
        return JsonResponse({"highlights": [_item(h) for h in
                                            CuratedHighlight.objects.filter(body_id=body_id)]})
    body_id = request.POST.get("body_id", "")
    lm = get_catalog().get(body_id)
    if not lm:
        return JsonResponse({"error": "Unknown body."}, status=400)
    try:
        upload = request.FILES.get("file")
        if upload:
            data = upload.read()
        elif request.POST.get("image_url", "").strip():
            data = curator_images.fetch_url(request.POST["image_url"].strip())
        else:
            return JsonResponse({"error": "Choose a file or paste an image URL."}, status=400)
        name = curator_images.store_image(data, _media())
    except curator_images.ImageError as exc:
        return JsonResponse({"error": str(exc)}, status=400)
    last = CuratedHighlight.objects.filter(body_id=body_id).order_by("-sort_order").first()
    h = CuratedHighlight(body_id=body_id, body_name=lm.name, image_file=name, ra=lm.ra, dec=lm.dec,
                         sort_order=(last.sort_order + 1) if last else 0)
    _apply(h, request.POST)
    h.save()
    return JsonResponse(_item(h), status=201)


@require_http_methods(["PATCH", "DELETE"])
def highlight_item(request, pk: int):
    try:
        h = CuratedHighlight.objects.get(pk=pk)
    except CuratedHighlight.DoesNotExist:
        return JsonResponse({"error": "Not found."}, status=404)
    if request.method == "DELETE":
        others = CuratedHighlight.objects.filter(image_file=h.image_file).exclude(pk=pk).exists()
        h.delete()
        if not others:
            curator_images.delete_files(h.image_file, _media())
        return JsonResponse({"deleted": pk})
    data = json.loads(request.body or b"{}")
    _apply(h, data)
    if "enabled" in data:
        h.enabled = bool(data["enabled"])
    h.save()
    return JsonResponse(_item(h))


@require_http_methods(["POST"])
def reorder(request):
    ids = json.loads(request.body or b"{}").get("ids", [])
    for position, pk in enumerate(ids):
        CuratedHighlight.objects.filter(pk=pk).update(sort_order=position)
    return JsonResponse({"ok": True})


@require_http_methods(["POST"])
def export_view(request):
    return JsonResponse(export_bundle())
