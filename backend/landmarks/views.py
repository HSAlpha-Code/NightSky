import base64

from rest_framework.decorators import api_view
from rest_framework.response import Response

from .serializers import LandmarkDetailQuerySerializer, LandmarksQuerySerializer
from .services import landmark_detail, landmarks_in_field


@api_view(["GET"])
def landmarks(request):
    s = LandmarksQuerySerializer(data=request.query_params)
    s.is_valid(raise_exception=True)
    d = s.validated_data
    return Response(landmarks_in_field(d["ra"] % 360, d["dec"], d["fov"], d["rotation"] % 360,
                                       d["aspect"], d.get("limit")))


@api_view(["GET"])
def landmark_detail_view(request):
    s = LandmarkDetailQuerySerializer(data=request.query_params)
    s.is_valid(raise_exception=True)
    d = s.validated_data
    detail = landmark_detail(d["id"], d["provider"] or None, d["view"])
    resp = Response({
        "landmark": detail.landmark,
        "view": detail.view,
        "image_source": detail.image_source,
        "credit": detail.credit,
        "caption": detail.caption,
        "fov": detail.fov_deg,
        "image_jpeg_base64": base64.b64encode(detail.image).decode(),
    })
    resp["Cache-Control"] = "public, max-age=86400"
    return resp
