from rest_framework.decorators import api_view, parser_classes
from rest_framework.parsers import MultiPartParser
from rest_framework.response import Response

from .serializers import SolveRequestSerializer, SolveResponseSerializer
from .services import solve as solve_service


@api_view(["POST"])
@parser_classes([MultiPartParser])
def solve(request):
    s = SolveRequestSerializer(data=request.data)
    s.is_valid(raise_exception=True)
    result = solve_service(s.validated_data["image"].read(), s.validated_data["metadata"])
    return Response(SolveResponseSerializer(result).data)
