"""Uniform API errors: {"error": {"code": ..., "message": ..., "details": ...}}."""
from rest_framework import status
from rest_framework.exceptions import ValidationError
from rest_framework.response import Response
from rest_framework.views import exception_handler

SOLVE_FAILED = "SOLVE_FAILED"
PROVIDER_UNAVAILABLE = "PROVIDER_UNAVAILABLE"
NO_COVERAGE = "NO_COVERAGE"
INVALID_REQUEST = "INVALID_REQUEST"


class ApiError(Exception):
    def __init__(self, code: str, message: str, http_status: int = status.HTTP_400_BAD_REQUEST,
                 details=None):
        super().__init__(message)
        self.code = code
        self.message = message
        self.http_status = http_status
        self.details = details


def error_body(code: str, message: str, details=None) -> dict:
    body = {"code": code, "message": message}
    if details is not None:
        body["details"] = details
    return {"error": body}


def api_exception_handler(exc, context):
    if isinstance(exc, ApiError):
        return Response(error_body(exc.code, exc.message, exc.details), status=exc.http_status)
    response = exception_handler(exc, context)
    if response is None:
        return None
    if isinstance(exc, ValidationError):
        response.data = error_body(INVALID_REQUEST, "Invalid request.", response.data)
    else:
        detail = response.data.get("detail", str(exc)) if isinstance(response.data, dict) else str(exc)
        response.data = error_body(INVALID_REQUEST, str(detail))
    return response
