"""
End-to-End Contract & API Tests for ShuntWhisper Backend.
Tests all endpoints, authentication, multipart payloads, and diagnostic engine integration.
"""

import json
import pytest
import cv2
import numpy as np
from fastapi.testclient import TestClient

from backend.app import app
from backend.config import AUTH_BEARER_TOKEN
from vision_engine.shuntwhisper_vision import (
    PatchGeometry,
    HueTempCalibration,
    render_frame,
    SCENARIOS,
)

client = TestClient(app)
AUTH_HEADER = {"Authorization": f"Bearer {AUTH_BEARER_TOKEN}"}


def _encode_png(img_bgr: np.ndarray) -> bytes:
    _, buf = cv2.imencode(".png", img_bgr)
    return buf.tobytes()


def _make_payload_dict(session_id: str = "test-session-001") -> dict:
    return {
        "sessionId": session_id,
        "schemaVersion": 1,
        "createdAtUtc": "2026-11-09T09:00:00Z",
        "app": {
            "version": "1.0.0",
            "build": "100",
            "platform": "ios",
            "osVersion": "18.1",
        },
        "device": {
            "model": "iphone_15_pro",
            "cameraId": "0",
            "hardwareLevel": "FULL",
            "profileVersion": 1,
        },
        "calibrationId": "CAL-TLC-2025-01",
        "ambient": {
            "temperatureC": 22.5,
            "relativeHumidityPct": 45.0,
            "source": "manual",
            "measuredAtUtc": "2026-11-09T08:59:00Z",
        },
        "dosing": {
            "volumeUl": 70.0,
            "tZeroMonotonicNs": 1000000000,
            "tZeroUtc": "2026-11-09T09:00:05Z",
            "detection": "manual_tap",
            "outOfSpec": False,
        },
        "images": [],
        "flags": [],
        "policySnapshot": {},
    }


def test_auth_enforcement():
    """Endpoints require valid Bearer token."""
    r = client.get("/v1/config")
    assert r.status_code == 401
    assert r.headers["content-type"] == "application/problem+json"
    assert r.json()["code"] == "UNAUTHENTICATED"


def test_get_config():
    """GET /v1/config returns layout and supports ETag 304."""
    r = client.get("/v1/config", headers=AUTH_HEADER)
    assert r.status_code == 200
    data = r.json()
    assert "patchLayout" in data
    assert data["patchLayout"]["upstreamCenterMm"]["x"] == -8.7
    assert data["patchLayout"]["downstreamCenterMm"]["x"] == 8.7
    assert data["patchLayout"]["lateralRefCenterMm"]["y"] == 12.0
    etag = r.headers.get("ETag")
    assert etag is not None

    # Test conditional request
    r304 = client.get("/v1/config", headers={**AUTH_HEADER, "If-None-Match": etag})
    assert r304.status_code == 304


def test_get_device_profile():
    """GET /v1/device-profiles returns platform profiles."""
    r = client.get("/v1/device-profiles/android/pixel_8", headers=AUTH_HEADER)
    assert r.status_code == 200
    data = r.json()
    assert data["platform"] == "android"
    assert data["model"] == "pixel_8"
    assert data["targetDistanceMm"] == 100.0


def test_get_calibration():
    """GET /v1/calibrations validates lot IDs."""
    r = client.get("/v1/calibrations/CAL-TLC-2025-01", headers=AUTH_HEADER)
    assert r.status_code == 200
    assert r.json()["valid"] is True

    r_bad = client.get("/v1/calibrations/UNKNOWN-LOT", headers=AUTH_HEADER)
    assert r_bad.status_code == 404


def test_session_normal_flow_diagnosis():
    """Multipart upload with normal flow frames returns PATENT_HIGH."""
    geom = PatchGeometry()
    cal = HueTempCalibration.default()
    sc = SCENARIOS["normal_flow"]

    base_bgr = render_frame(geom, sc, 0.0, cal)
    t23_bgr = render_frame(geom, sc, 23.0, cal)
    t120_bgr = render_frame(geom, sc, 120.0, cal)

    session_id = "test-session-normal-flow"
    payload = _make_payload_dict(session_id)

    files = [
        ("metadata", (None, json.dumps(payload), "application/json")),
        ("baseline", ("base.png", _encode_png(base_bgr), "image/png")),
        ("t23", ("t23.png", _encode_png(t23_bgr), "image/png")),
        ("t120", ("t120.png", _encode_png(t120_bgr), "image/png")),
    ]

    r_post = client.post(
        "/v1/sessions",
        files=files,
        headers={**AUTH_HEADER, "Idempotency-Key": session_id},
    )
    assert r_post.status_code == 202
    assert r_post.json()["sessionId"] == session_id

    # Poll session result
    r_get = client.get(f"/v1/sessions/{session_id}", headers=AUTH_HEADER)
    assert r_get.status_code == 200
    res = r_get.json()
    assert res["classification"] == "PATENT_HIGH"
    assert res["deltaTUdC"]["value"] >= 0.35
    assert res["deltaTEvapC"]["value"] >= 1.50
    assert res["confidencePct"] > 80.0
    assert len(res["roiVisuals"]) > 0

    # Verify visual asset
    r_vis = client.get(f"/v1/sessions/{session_id}/rois/overlay")
    assert r_vis.status_code == 200
    assert r_vis.headers["content-type"] == "image/png"

    # Cleanup
    r_del = client.delete(f"/v1/sessions/{session_id}", headers=AUTH_HEADER)
    assert r_del.status_code == 204


def test_session_occluded_diagnosis():
    """Occluded patch produces OCCLUDED classification with symmetric profile."""
    geom = PatchGeometry()
    cal = HueTempCalibration.default()
    sc = SCENARIOS["occluded"]

    base_bgr = render_frame(geom, sc, 0.0, cal)
    t120_bgr = render_frame(geom, sc, 120.0, cal)

    session_id = "test-session-occluded"
    payload = _make_payload_dict(session_id)

    files = [
        ("metadata", (None, json.dumps(payload), "application/json")),
        ("baseline", ("base.png", _encode_png(base_bgr), "image/png")),
        ("t120", ("t120.png", _encode_png(t120_bgr), "image/png")),
    ]

    r_post = client.post("/v1/sessions", files=files, headers=AUTH_HEADER)
    assert r_post.status_code == 202

    r_get = client.get(f"/v1/sessions/{session_id}", headers=AUTH_HEADER)
    assert r_get.status_code == 200
    res = r_get.json()
    assert res["classification"] == "OCCLUDED"
    assert -0.08 <= res["deltaTUdC"]["value"] < 0.10


def test_session_insufficient_hydration_diagnosis():
    """Dry foam produces INCONCLUSIVE with reason INSUFFICIENT_HYDRATION."""
    geom = PatchGeometry()
    cal = HueTempCalibration.default()
    sc = SCENARIOS["dry_foam"]

    base_bgr = render_frame(geom, sc, 0.0, cal)
    t120_bgr = render_frame(geom, sc, 120.0, cal)

    session_id = "test-session-dry-foam"
    payload = _make_payload_dict(session_id)

    files = [
        ("metadata", (None, json.dumps(payload), "application/json")),
        ("baseline", ("base.png", _encode_png(base_bgr), "image/png")),
        ("t120", ("t120.png", _encode_png(t120_bgr), "image/png")),
    ]

    r_post = client.post("/v1/sessions", files=files, headers=AUTH_HEADER)
    assert r_post.status_code == 202

    r_get = client.get(f"/v1/sessions/{session_id}", headers=AUTH_HEADER)
    assert r_get.status_code == 200
    res = r_get.json()
    assert res["classification"] == "INCONCLUSIVE"
    assert res["inconclusiveReason"] == "INSUFFICIENT_HYDRATION"

