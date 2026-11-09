"""
Diagnostic Service: Orchestrates image decoding, vision engine analysis,
response transformation, and ROI artifact generation.
"""

from __future__ import annotations
import os
import math
import cv2
import numpy as np
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Dict, Optional, Tuple, List

from vision_engine.shuntwhisper_vision import (
    ShuntWhisperEngine,
    PatchGeometry,
    HueTempCalibration,
    EngineConfig,
    FlowStatus,
    DiagnosticReport,
    FrameAnalysis,
    RoiStats,
    CameraIntrinsics,
)
from backend.models import (
    DiagnosticResponse,
    Classification,
    InconclusiveReason,
    Measured,
    EvapMeasured,
    FlowEstimate,
    TimepointResult,
    TemperaturesBreakdown,
    RoiVisual,
    RoiVisualKind,
    RetestAdvice,
    CapturePayload,
)

VISUALS_DIR = Path("/tmp/shuntwhisper_visuals")
VISUALS_DIR.mkdir(parents=True, exist_ok=True)


class DiagnosticService:
    def __init__(self, geom: Optional[PatchGeometry] = None, cal: Optional[HueTempCalibration] = None):
        self.geom = geom or PatchGeometry()
        self.cal = cal or HueTempCalibration.default()
        self.engine = ShuntWhisperEngine(self.geom, cal=self.cal)

    def process_session(
        self,
        payload: CapturePayload,
        image_bytes: Dict[str, bytes],
        base_url: str = "http://127.0.0.1:8000"
    ) -> DiagnosticResponse:
        session_id = payload.session_id

        # 1. Decode uploaded image bytes into BGR numpy arrays
        images_bgr: Dict[str, np.ndarray] = {}
        for part, b in image_bytes.items():
            arr = np.frombuffer(b, np.uint8)
            img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
            if img is not None:
                images_bgr[part] = img

        baseline_bgr = images_bgr.get("baseline")

        # 2. Map sample timepoints (t23 -> 23.0s, t120 -> 120.0s)
        samples: Dict[float, np.ndarray] = {}
        if "t23" in images_bgr:
            samples[23.0] = images_bgr["t23"]
        if "t120" in images_bgr:
            samples[120.0] = images_bgr["t120"]

        # 3. Execute analytical diagnostic engine
        report: DiagnosticReport = self.engine.diagnose(baseline_bgr, samples, keep_debug=True)

        # 4. Map engine status to client classification
        status_map = {
            FlowStatus.PATENT_NORMAL: Classification.PATENT_HIGH,
            FlowStatus.PATENT_LOW: Classification.PATENT_MARGINAL,
            FlowStatus.OCCLUSION: Classification.OCCLUDED,
            FlowStatus.INDETERMINATE: Classification.INCONCLUSIVE,
        }
        classification = status_map.get(report.status, Classification.UNKNOWN)

        # 5. Inconclusive reason handling
        inconclusive_reason: Optional[InconclusiveReason] = None
        inconclusive_raw: Optional[str] = None
        if classification == Classification.INCONCLUSIVE:
            inconclusive_raw = report.reason
            try:
                inconclusive_reason = InconclusiveReason(report.reason)
            except ValueError:
                inconclusive_reason = InconclusiveReason.OTHER

        # 6. Primary frame analysis (t = 120s or fallback)
        primary_fa: Optional[FrameAnalysis] = report.frames.get(report.primary_t)

        # 7. Extract primary differential metric ΔT_ud
        delta_t_ud: Optional[Measured] = None
        if primary_fa and np.isfinite(primary_fa.dT_ud_c):
            val = float(primary_fa.dT_ud_c)
            sig = float(primary_fa.sigma_dT_c) if np.isfinite(primary_fa.sigma_dT_c) else 0.035
            delta_t_ud = Measured(
                value=round(val, 3),
                sigma=round(sig, 3),
                ci95Lo=round(val - 1.96 * sig, 3),
                ci95Hi=round(val + 1.96 * sig, 3),
            )

        # 8. Extract evaporative depression metric ΔT_evap
        delta_t_evap: Optional[EvapMeasured] = None
        if primary_fa and np.isfinite(primary_fa.sink_drop_c):
            val_evap = float(primary_fa.sink_drop_c)
            delta_t_evap = EvapMeasured(
                value=round(val_evap, 3),
                sigma=0.05,
                isLowerBound=primary_fa.sink_drop_is_lower_bound,
                definition="T_lateral_ref - 0.5*(T_up + T_down)",
            )

        # 9. Experimental flow rate estimation Q (mL/min)
        flow_estimate: Optional[FlowEstimate] = None
        if delta_t_ud is not None and classification in (Classification.PATENT_HIGH, Classification.PATENT_MARGINAL):
            # Characteristic calibration: ~0.45 mL/min at dT ~ 0.40 degC
            q_est = max(0.03, min(0.60, 0.45 * (delta_t_ud.value / 0.40)))
            flow_estimate = FlowEstimate(
                point=round(q_est, 3),
                lo=round(max(0.01, q_est - 0.08), 3),
                hi=round(min(0.80, q_est + 0.08), 3),
                method="empirical_characteristic_inversion",
                validated=False,
                is_experimental=True,
            )
        elif classification == Classification.OCCLUDED:
            flow_estimate = FlowEstimate(
                point=0.00,
                lo=0.00,
                hi=0.04,
                method="symmetric_thermal_signature",
                validated=False,
                is_experimental=True,
            )

        # 10. Temperatures breakdown
        temperatures = TemperaturesBreakdown()
        if primary_fa:
            up_roi = primary_fa.rois.get("upstream")
            if up_roi and np.isfinite(up_roi.temp_c):
                temperatures.upstream_c = Measured(
                    value=round(float(up_roi.temp_c), 2),
                    sigma=round(float(up_roi.temp_se_c), 2),
                )
            dn_roi = primary_fa.rois.get("downstream")
            if dn_roi and np.isfinite(dn_roi.temp_c):
                temperatures.downstream_c = Measured(
                    value=round(float(dn_roi.temp_c), 2),
                    sigma=round(float(dn_roi.temp_se_c), 2),
                )
            lat_roi = primary_fa.rois.get("lateral_ref") or primary_fa.rois.get("substrate_ref")
            if lat_roi and np.isfinite(lat_roi.temp_c):
                temperatures.lateral_ref_c = Measured(
                    value=round(float(lat_roi.temp_c), 2),
                    sigma=round(float(lat_roi.temp_se_c), 2),
                )

        # 11. Timepoints summary
        timepoints: List[TimepointResult] = []
        for t_nom, fa in report.frames.items():
            t_class = status_map.get(fa.status, Classification.UNKNOWN)
            t_dT: Optional[Measured] = None
            if np.isfinite(fa.dT_ud_c):
                t_dT = Measured(
                    value=round(float(fa.dT_ud_c), 3),
                    sigma=round(float(fa.sigma_dT_c), 3) if np.isfinite(fa.sigma_dT_c) else 0.035,
                )
            timepoints.append(
                TimepointResult(
                    tNominalS=t_nom,
                    classification=t_class,
                    deltaTUdC=t_dT,
                    confidencePct=round(float(fa.confidence), 1),
                    qaPassed=fa.qa.passed,
                    qaFailures=list(fa.qa.failures),
                )
            )

        # 12. Save ROI visual assets and generate URLs
        roi_visuals: List[RoiVisual] = []
        session_visuals_dir = VISUALS_DIR / session_id
        session_visuals_dir.mkdir(parents=True, exist_ok=True)
        expires_at = datetime.now(timezone.utc) + timedelta(minutes=60)

        if primary_fa and "overlay" in primary_fa.debug:
            overlay_path = session_visuals_dir / "overlay.png"
            cv2.imwrite(str(overlay_path), primary_fa.debug["overlay"])
            h, w = primary_fa.debug["overlay"].shape[:2]
            roi_visuals.append(
                RoiVisual(
                    name="overlay",
                    kind=RoiVisualKind.OVERLAY,
                    url=f"{base_url}/v1/sessions/{session_id}/rois/overlay",
                    expiresAtUtc=expires_at,
                    widthPx=w,
                    heightPx=h,
                )
            )

        # 13. Retest advice
        retest_advice: Optional[RetestAdvice] = None
        if classification == Classification.INCONCLUSIVE:
            req_new = inconclusive_reason in (
                InconclusiveReason.INSUFFICIENT_HYDRATION,
                InconclusiveReason.REVERSE_GRADIENT,
                InconclusiveReason.SPECULAR_ROI,
            )
            retest_advice = RetestAdvice(
                code=inconclusive_raw or "RETEST_NEEDED",
                requiresNewPatch=req_new,
            )

        return DiagnosticResponse(
            sessionId=session_id,
            engineVersion="1.2.0",
            calibrationIdUsed=payload.calibration_id,
            processedAtUtc=datetime.now(timezone.utc),
            classification=classification,
            inconclusiveReason=inconclusive_reason,
            inconclusiveReasonRaw=inconclusive_raw,
            deltaTUdC=delta_t_ud,
            deltaTEvapC=delta_t_evap,
            estimatedFlowMlMin=flow_estimate,
            confidencePct=round(float(report.confidence), 1),
            confidenceFactors={k: round(float(v), 3) for k, v in primary_fa.confidence_factors.items()} if primary_fa else {},
            snrResolutionDb=round(float(primary_fa.snr_resolution_db), 1) if primary_fa and np.isfinite(primary_fa.snr_resolution_db) else None,
            temperatures=temperatures,
            timepoints=timepoints,
            flags=list(report.flags),
            roiVisuals=roi_visuals,
            retestAdvice=retest_advice,
        )

