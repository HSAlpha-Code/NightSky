"""Public, read-only API for curated highlights. No write or admin functionality here."""
import re
from itertools import groupby

from django.http import FileResponse, Http404, HttpResponse
from django.views.decorators.http import require_GET
from rest_framework import status
from rest_framework.decorators import api_view
from rest_framework.response import Response

from config.errors import NOT_FOUND, ApiError

from . import repo

CACHE_CONTROL = "public, max-age=300, must-revalidate"
IMAGE_NAME = re.compile(r"^[A-Za-z0-9_-][A-Za-z0-9_.-]*\.(jpg|jpeg|png|webp)$")
CONTENT_TYPES = {"jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png",
                 "webp": "image/webp"}


def _etag_matches(request, etag: str) -> bool:
    header = request.headers.get("If-None-Match", "")
    tags = [t.strip().removeprefix("W/") for t in header.split(",") if t.strip()]
    return "*" in tags or etag in tags


def _respond(request, version: str, payload: dict) -> Response:
    etag = f'"{version}"'
    resp = Response(status=304) if _etag_matches(request, etag) else Response(payload)
    resp["ETag"] = etag
    resp["Cache-Control"] = CACHE_CONTROL
    return resp


def _image_url(request, name: str) -> str:
    return request.build_absolute_uri(f"/api/curated/image/{name}")


@api_view(["GET"])
def curated_index(request):
    records = repo.enabled_highlights()
    bodies = []
    for body_id, group in groupby(records, key=lambda r: r["body_id"]):
        rows = list(group)
        bodies.append({"body_id": body_id, "body_name": rows[0]["body_name"],
                       "count": len(rows)})
    version = repo.fingerprint(records)
    updated = max((r["updated_at"] for r in records), default=None)
    return _respond(request, version,
                    {"version": version, "updated_at": updated, "bodies": bodies})


@api_view(["GET"])
def curated_body(request, body_id: str):
    rows = [r for r in repo.enabled_highlights() if r["body_id"] == body_id]
    if not rows:
        raise ApiError(NOT_FOUND, "No curated highlights for this object.",
                       status.HTTP_404_NOT_FOUND)
    version = repo.fingerprint(rows)
    return _respond(request, version, {
        "body_id": body_id,
        "body_name": rows[0]["body_name"],
        "version": version,
        "highlights": [{
            "id": r["id"],
            "title": r["title"],
            "image_url": _image_url(request, r["image_file"]),
            "thumbnail_url": _image_url(request, repo.thumb_name(r["image_file"])),
            "source_outlet": r["source_outlet"],
            "source_url": r["source_url"],
            "credit": r["credit"],
            "caption": r["caption"],
            "ra": r["ra"],
            "dec": r["dec"],
        } for r in rows],
    })


@require_GET
def curated_image(request, name: str):
    """Serves a stored file as-is. Only plain file names inside the image folder."""
    match = IMAGE_NAME.match(name)
    if not match:
        raise Http404
    folder = repo.image_dir().resolve()
    path = (folder / name).resolve()
    if path.parent != folder or not path.is_file():
        raise Http404
    stat = path.stat()
    etag = f'"{stat.st_mtime_ns:x}-{stat.st_size:x}"'
    if _etag_matches(request, etag):
        resp = HttpResponse(status=304)
    else:
        resp = FileResponse(path.open("rb"), content_type=CONTENT_TYPES[match.group(1)])
    resp["ETag"] = etag
    resp["Cache-Control"] = "public, max-age=86400"
    return resp
