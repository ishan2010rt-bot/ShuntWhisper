"""
FastAPI application for ShuntWhisper Mobile Vision and Diagnostic Engine.
Implements the OpenAPI contract defined in Section B.5 of the Mobile App Blueprint.
"""

from __future__ import annotations
import hashlib
import json
import os
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Dict, Optional, Any

from fastapi import (
    FastAPI,
    Request,
    Response,
    Header,
    HTTPException,
    Depends,
    UploadFile,
    File,
    Form,
    status,
)
from fastapi.responses import JSONResponse, FileResponse
from fastapi.middleware.cors import CORSMiddleware

from backend.models import (
    RemoteConfig,
    DeviceProfile,
    SubmitAck,
    DiagnosticResponse,
    ProblemDetails,
    CapturePayload,
)
from backend.config import (
    AUTH_BEARER_TOKEN,
    DEFAULT_REMOTE_CONFIG,
    DEFAULT_DEVICE_PROFILES,
)
from backend.services.diagnostic_service import DiagnosticService, VISUALS_DIR

app = FastAPI(
    title="ShuntWhisper Vision & Diagnostic Engine API",
    version="1.2.0",
    description="Production-grade API for VP shunt occlusion detection using evaporative cooling TLC colorimetry.",
)

# Enable CORS for local app testing and dashboard embedding
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# In-memory store for session results and idempotency
_SESSIONS_DB: Dict[str, DiagnosticResponse] = {}
_SESSIONS_PAYLOADS: Dict[str, CapturePayload] = {}
_SERVICE = DiagnosticService()


# =============================================================================
# Authentication & Security
# =============================================================================

async def verify_bearer_auth(authorization: Optional[str] = Header(None)) -> str:
    """Enforces static bearer token authentication for P0/competition evaluation."""
    if not authorization:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing Authorization header",
            headers={"WWW-Authenticate": "Bearer"},
        )
    parts = authorization.split()
    if len(parts) != 2 or parts[0].lower() != "bearer" or parts[1] != AUTH_BEARER_TOKEN:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired bearer token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return parts[1]


# =============================================================================
# Exception Handlers (RFC 7807 Problem+JSON)
# =============================================================================

@app.exception_handler(HTTPException)
async def problem_details_handler(request: Request, exc: HTTPException):
    code_map = {
        400: "INVALID_REQUEST",
        401: "UNAUTHENTICATED",
        404: "NOT_FOUND",
        413: "PAYLOAD_TOO_LARGE",
        415: "UNSUPPORTED_MEDIA",
        422: "UPLOAD_INVALID_IMAGE",
        429: "RATE_LIMITED",
        500: "ENGINE_FAILURE",
    }
    code = code_map.get(exc.status_code, "UNKNOWN")
    problem = ProblemDetails(
        type=f"https://shuntwhisper.internal/errors/{code.lower()}",
        title=exc.detail if isinstance(exc.detail, str) else "Error",
        status=exc.status_code,
        detail=str(exc.detail),
        code=code,
        instance=str(request.url),
    )
    return JSONResponse(
        status_code=exc.status_code,
        content=problem.model_dump(),
        media_type="application/problem+json",
        headers=exc.headers,
    )


# =============================================================================
# Endpoints
# =============================================================================

@app.get("/v1/config", response_model=RemoteConfig)
async def get_config(
    if_none_match: Optional[str] = Header(None, alias="If-None-Match"),
    _: str = Depends(verify_bearer_auth),
):
    """Returns remote session policy, patch layout, and thresholds with ETag caching."""
    cfg_json = DEFAULT_REMOTE_CONFIG.model_dump_json(by_alias=True)
    etag = f'"{hashlib.sha256(cfg_json.encode("utf-8")).hexdigest()[:16]}"'

    if if_none_match and if_none_match.strip() == etag:
        return Response(status_code=status.HTTP_304_NOT_MODIFIED, headers={"ETag": etag})

    return JSONResponse(
        content=json.loads(cfg_json),
        headers={"ETag": etag, "Cache-Control": "public, max-age=300"},
    )


@app.get("/v1/device-profiles/{platform}/{model}", response_model=DeviceProfile)
async def get_device_profile(
    platform: str,
    model: str,
    _: str = Depends(verify_bearer_auth),
):
    """Fetches device-specific camera calibration parameters and intrinsics."""
    key = f"{platform.lower()}/{model.lower()}"
    profile = DEFAULT_DEVICE_PROFILES.get(key)
    if not profile:
        profile = DEFAULT_DEVICE_PROFILES.get("generic")
    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Device profile not found for {platform}/{model}",
        )
    return profile


@app.get("/v1/calibrations/{calibration_id}")
async def get_calibration(
    calibration_id: str,
    _: str = Depends(verify_bearer_auth),
):
    """Validates TLC batch lot calibration identifier."""
    # Standard competition demo lots
    valid_lots = {"CAL-TLC-2025-01", "CAL-TLC-LOT-A", "default"}
    if calibration_id not in valid_lots:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Calibration ID '{calibration_id}' unknown or expired",
        )
    return {
        "valid": True,
        "lotId": calibration_id,
        "tMinC": 25.0,
        "tMaxC": 30.0,
        "expiresAtUtc": (datetime.now(timezone.utc) + timedelta(days=90)).isoformat(),
    }


@app.post("/v1/sessions", status_code=status.HTTP_202_ACCEPTED, response_model=SubmitAck)
async def submit_session(
    request: Request,
    metadata: str = Form(..., description="Serialized CapturePayload JSON"),
    baseline: Optional[UploadFile] = File(None),
    t23: Optional[UploadFile] = File(None),
    t120: Optional[UploadFile] = File(None),
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key"),
    _: str = Depends(verify_bearer_auth),
):
    """
    Accepts multipart/form-data upload containing session metadata and captured frame images.
    Returns HTTP 202 with polling status URL.
    """
    try:
        payload_dict = json.loads(metadata)
        payload = CapturePayload(**payload_dict)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Invalid metadata JSON in payload: {str(e)}",
        )

    session_id = idempotency_key or payload.session_id

    # Check idempotency replay
    if session_id in _SESSIONS_DB:
        base_url = str(request.base_url).rstrip("/")
        return SubmitAck(
            sessionId=session_id,
            statusUrl=f"{base_url}/v1/sessions/{session_id}",
        )

    # Read binary image bytes
    image_bytes: Dict[str, bytes] = {}
    if baseline:
        image_bytes["baseline"] = await baseline.read()
    if t23:
        image_bytes["t23"] = await t23.read()
    if t120:
        image_bytes["t120"] = await t120.read()

    # Process diagnosis synchronously
    base_url = str(request.base_url).rstrip("/")
    diag_response = _SERVICE.process_session(payload, image_bytes, base_url=base_url)

    _SESSIONS_DB[session_id] = diag_response
    _SESSIONS_PAYLOADS[session_id] = payload

    return SubmitAck(
        sessionId=session_id,
        statusUrl=f"{base_url}/v1/sessions/{session_id}",
    )


@app.get("/v1/sessions/{session_id}", response_model=DiagnosticResponse)
async def get_session(
    session_id: str,
    _: str = Depends(verify_bearer_auth),
):
    """Polls diagnostic report results for a given session ID."""
    if session_id not in _SESSIONS_DB:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Session {session_id} not found",
        )
    return _SESSIONS_DB[session_id]


@app.get("/v1/sessions/{session_id}/rois/{name}")
async def get_roi_visual(
    session_id: str,
    name: str,
):
    """Serves generated ROI visual assets (e.g. overlay contour heatmap)."""
    visual_path = VISUALS_DIR / session_id / f"{name}.png"
    if not visual_path.exists():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Visual asset {name} for session {session_id} not found",
        )
    return FileResponse(str(visual_path), media_type="image/png")


@app.delete("/v1/sessions/{session_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_session(
    session_id: str,
    _: str = Depends(verify_bearer_auth),
):
    """Performs PHI erasure, deleting in-memory records and cached image files."""
    _SESSIONS_DB.pop(session_id, None)
    _SESSIONS_PAYLOADS.pop(session_id, None)
    session_dir = VISUALS_DIR / session_id
    if session_dir.exists():
        for f in session_dir.glob("*"):
            f.unlink()
        session_dir.rmdir()
    return Response(status_code=status.HTTP_204_NO_CONTENT)

