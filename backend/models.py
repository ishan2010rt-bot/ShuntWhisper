"""
Pydantic v2 data models for the ShuntWhisper analytical backend and client REST contracts.
Conforms strictly to Section B of docs/ShuntWhisper_Mobile_App_Blueprint.md.
"""

from __future__ import annotations
import enum
from datetime import datetime, timezone
from typing import Dict, List, Optional, Any, Union
from pydantic import BaseModel, Field, ConfigDict


# =============================================================================
# Enums
# =============================================================================

class AlignmentStatus(str, enum.Enum):
    ALIGNED = "ALIGNED"
    MISALIGNED = "MISALIGNED"
    UNSTABLE = "UNSTABLE"
    NOT_DETECTED = "NOT_DETECTED"


class AlignmentViolation(str, enum.Enum):
    TOO_FAR = "TOO_FAR"
    TOO_CLOSE = "TOO_CLOSE"
    PITCH = "PITCH"
    YAW = "YAW"
    ROLL = "ROLL"
    OFF_CENTER = "OFF_CENTER"
    LATERAL_OFFSET = "LATERAL_OFFSET"
    NEAR_FRAME_EDGE = "NEAR_FRAME_EDGE"
    BLUR = "BLUR"
    GLARE = "GLARE"
    UNDER_EXPOSED = "UNDER_EXPOSED"


class Classification(str, enum.Enum):
    PATENT_HIGH = "PATENT_HIGH"
    PATENT_MARGINAL = "PATENT_MARGINAL"
    OCCLUDED = "OCCLUDED"
    INCONCLUSIVE = "INCONCLUSIVE"
    UNKNOWN = "UNKNOWN"


class InconclusiveReason(str, enum.Enum):
    INSUFFICIENT_HYDRATION = "INSUFFICIENT_HYDRATION"
    OUT_OF_RANGE_WARM = "OUT_OF_RANGE_WARM"
    OUT_OF_RANGE_COLD = "OUT_OF_RANGE_COLD"
    QC_MOTION_BLUR = "QC_MOTION_BLUR"
    QC_REGISTRATION = "QC_REGISTRATION"
    QC_EXPOSURE = "QC_EXPOSURE"
    QC_COLOR_FIT = "QC_COLOR_FIT"
    QC_ILLUMINATION = "QC_ILLUMINATION"
    SPECULAR_ROI = "SPECULAR_ROI"
    REVERSE_GRADIENT = "REVERSE_GRADIENT"
    LOW_SNR = "LOW_SNR"
    SINK_UNVERIFIABLE = "SINK_UNVERIFIABLE"
    OTHER = "OTHER"


class TorchMode(str, enum.Enum):
    OFF = "OFF"
    ON = "ON"


class TorchPolicy(str, enum.Enum):
    ALWAYS_ON = "always_on"
    WINDOWED = "windowed"


class DoseDetection(str, enum.Enum):
    MANUAL_TAP = "manual_tap"
    AUTO_FOAM = "auto_foam"


class AmbientSource(str, enum.Enum):
    MANUAL = "manual"
    SENSOR = "sensor"
    BLE = "ble"


class IntrinsicsSource(str, enum.Enum):
    CAMERA_CHARACTERISTICS = "camera_characteristics"
    PROFILE = "profile"
    ESTIMATED = "estimated"


class RoiVisualKind(str, enum.Enum):
    CROP = "crop"
    OVERLAY = "overlay"
    NORMALIZED = "normalized"
    SPEC_MASK = "spec_mask"


# =============================================================================
# Helper & Geometric DTOs
# =============================================================================

class SizeDto(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    width_px: int = Field(..., alias="widthPx")
    height_px: int = Field(..., alias="heightPx")


class PointDto(BaseModel):
    x: float
    y: float


class SizeMm(BaseModel):
    w: float
    h: float


class FiducialSpec(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    id: int
    center_mm: PointDto = Field(..., alias="centerMm")
    side_mm: float = Field(..., alias="sideMm")


class PatchLayout(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    upstream_center_mm: PointDto = Field(..., alias="upstreamCenterMm")
    downstream_center_mm: PointDto = Field(..., alias="downstreamCenterMm")
    lateral_ref_center_mm: PointDto = Field(..., alias="lateralRefCenterMm")
    aperture_center_mm: PointDto = Field(..., alias="apertureCenterMm")
    aperture_size_mm: SizeMm = Field(..., alias="apertureSizeMm")
    roi_size_mm: SizeMm = Field(..., alias="roiSizeMm")
    fiducials: List[FiducialSpec]


# =============================================================================
# Camera Hardware & Capabilities
# =============================================================================

class FocusSpec(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    target_distance_mm: float = Field(100.0, alias="targetDistanceMm")
    android_diopters: Optional[float] = Field(None, alias="androidDiopters")
    ios_lens_position: Optional[float] = Field(None, alias="iosLensPosition")


class TorchSpec(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    mode: TorchMode = TorchMode.OFF
    level: float = 1.0
    policy: TorchPolicy = TorchPolicy.WINDOWED
    pre_roll_ms: int = Field(2500, alias="preRollMs")


class WbGains(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    r: float
    g_even: float = Field(..., alias="gEven")
    g_odd: float = Field(..., alias="gOdd")
    b: float


class WhiteBalanceSpec(BaseModel):
    gains: Optional[WbGains] = None
    kelvin: int = 5500
    tint: int = 0


class IspSpec(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    tonemap: str = "srgbPreset"
    noise_reduction: str = Field("minimal", alias="noiseReduction")
    edge_mode: str = Field("off", alias="edgeMode")
    ois: str = "off"
    video_stabilization: str = Field("off", alias="videoStabilization")
    hdr: str = "off"
    zoom_ratio: float = Field(1.0, alias="zoomRatio")


class CameraHardwareConfig(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    camera_id: str = Field(..., alias="cameraId")
    iso: int = 50
    exposure_time_ns: int = Field(10_000_000, alias="exposureTimeNs")
    frame_duration_ns: int = Field(33_333_333, alias="frameDurationNs")
    focus: FocusSpec = Field(default_factory=FocusSpec)
    torch: TorchSpec = Field(default_factory=TorchSpec)
    white_balance: WhiteBalanceSpec = Field(default_factory=WhiteBalanceSpec, alias="whiteBalance")
    mains_hz: int = Field(50, alias="mainsHz")
    isp: IspSpec = Field(default_factory=IspSpec)
    still_size: SizeDto = Field(..., alias="stillSize")
    preview_analysis_size: SizeDto = Field(..., alias="previewAnalysisSize")


class ParamDeviation(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    param: str
    requested: float
    applied: float
    within_tolerance: bool = Field(..., alias="withinTolerance")


class AppliedCameraState(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    iso: int
    exposure_time_ns: int = Field(..., alias="exposureTimeNs")
    white_balance_gains: Optional[WbGains] = Field(None, alias="whiteBalanceGains")
    focus_distance_diopters: Optional[float] = Field(None, alias="focusDistanceDiopters")
    lens_position: Optional[float] = Field(None, alias="lensPosition")
    torch_level: float = Field(1.0, alias="torchLevel")
    awb_locked: bool = Field(True, alias="awbLocked")
    ae_locked: bool = Field(True, alias="aeLocked")
    sensor_timestamp_ns: int = Field(..., alias="sensorTimestampNs")
    verified: bool = True
    deviations: List[ParamDeviation] = Field(default_factory=list)


class CameraCapabilities(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    has_manual_sensor: bool = Field(..., alias="hasManualSensor")
    iso_min: int = Field(..., alias="isoMin")
    iso_max: int = Field(..., alias="isoMax")
    exposure_min_ns: int = Field(..., alias="exposureMinNs")
    exposure_max_ns: int = Field(..., alias="exposureMaxNs")
    min_focus_distance_mm: Optional[float] = Field(None, alias="minFocusDistanceMm")
    has_torch: bool = Field(..., alias="hasTorch")
    supports_wb_gains: bool = Field(..., alias="supportsWbGains")
    supported_still_sizes: List[SizeDto] = Field(default_factory=list, alias="supportedStillSizes")
    hardware_level: str = Field("FULL", alias="hardwareLevel")
    physical_camera_ids: List[str] = Field(default_factory=list, alias="physicalCameraIds")


# =============================================================================
# Alignment & Computer Vision State
# =============================================================================

class FiducialAlignmentState(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    frame_seq: int = Field(0, alias="frameSeq")
    timestamp_ns: int = Field(0, alias="timestampNs")
    analysis_size: SizeDto = Field(..., alias="analysisSize")
    markers_detected: int = Field(..., alias="markersDetected")
    marker_centers_px: List[Optional[PointDto]] = Field(default_factory=list, alias="markerCentersPx")
    canon_to_image_h: Optional[List[float]] = Field(None, alias="canonToImageH")
    roi_quads_px: Dict[str, List[PointDto]] = Field(default_factory=dict, alias="roiQuadsPx")
    pitch_deg: Optional[float] = Field(None, alias="pitchDeg")
    yaw_deg: Optional[float] = Field(None, alias="yawDeg")
    roll_deg: Optional[float] = Field(None, alias="rollDeg")
    distance_mm: Optional[float] = Field(None, alias="distanceMm")
    lateral_offset_mm: Optional[PointDto] = Field(None, alias="lateralOffsetMm")
    center_offset_frac: Optional[float] = Field(None, alias="centerOffsetFrac")
    sharpness: Optional[float] = None
    stability_score: float = Field(1.0, alias="stabilityScore")
    consecutive_aligned_frames: int = Field(8, alias="consecutiveAlignedFrames")
    aligned_for_ms: int = Field(800, alias="alignedForMs")
    status: AlignmentStatus = AlignmentStatus.ALIGNED
    violations: List[AlignmentViolation] = Field(default_factory=list)


class FrameValidationResult(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    passed: bool
    sharpness: float
    white_level: float = Field(..., alias="whiteLevel")
    white_clip_frac: float = Field(..., alias="whiteClipFrac")
    specular_frac_by_roi: Dict[str, float] = Field(default_factory=dict, alias="specularFracByRoi")
    markers_detected: int = Field(4, alias="markersDetected")
    reg_rms_px: Optional[float] = Field(None, alias="regRmsPx")
    failures: List[str] = Field(default_factory=list)


# =============================================================================
# Upload & Capture Payload Models
# =============================================================================

class AmbientMetadata(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    temperature_c: float = Field(..., alias="temperatureC")
    relative_humidity_pct: float = Field(..., alias="relativeHumidityPct")
    source: AmbientSource = AmbientSource.MANUAL
    measured_at_utc: datetime = Field(..., alias="measuredAtUtc")


class DosingRecord(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    volume_ul: float = Field(70.0, alias="volumeUl")
    t_zero_monotonic_ns: int = Field(..., alias="tZeroMonotonicNs")
    t_zero_utc: datetime = Field(..., alias="tZeroUtc")
    detection: DoseDetection = DoseDetection.MANUAL_TAP
    out_of_spec: bool = Field(False, alias="outOfSpec")


class Intrinsics(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    fx: float
    fy: float
    cx: float
    cy: float
    image_w: int = Field(..., alias="imageW")
    image_h: int = Field(..., alias="imageH")
    source: IntrinsicsSource = IntrinsicsSource.PROFILE


class CapturedImageMeta(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    part: str  # 'baseline' | 't23' | 't120'
    t_nominal_s: float = Field(..., alias="tNominalS")
    t_actual_s: float = Field(..., alias="tActualS")
    mime: str = "image/png"
    encoding: str = "raw"
    jpeg_quality: Optional[int] = Field(None, alias="jpegQuality")
    width_px: int = Field(..., alias="widthPx")
    height_px: int = Field(..., alias="heightPx")
    size_bytes: int = Field(..., alias="sizeBytes")
    sha256: str
    applied_camera: AppliedCameraState = Field(..., alias="appliedCamera")
    alignment_at_capture: FiducialAlignmentState = Field(..., alias="alignmentAtCapture")
    validation: FrameValidationResult
    intrinsics: Intrinsics
    burst_index: int = Field(0, alias="burstIndex")
    burst_size: int = Field(3, alias="burstSize")


class AppInfo(BaseModel):
    version: str
    build: str
    platform: str
    os_version: str = Field(..., alias="osVersion")


class DeviceInfo(BaseModel):
    model: str
    camera_id: str = Field(..., alias="cameraId")
    hardware_level: str = Field("FULL", alias="hardwareLevel")
    profile_version: int = Field(1, alias="profileVersion")


class CapturePayload(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    session_id: str = Field(..., alias="sessionId")
    schema_version: int = Field(1, alias="schemaVersion")
    created_at_utc: datetime = Field(..., alias="createdAtUtc")
    subject_ref: Optional[str] = Field(None, alias="subjectRef")
    app: AppInfo
    device: DeviceInfo
    calibration_id: str = Field(..., alias="calibrationId")
    patch_lot_id: Optional[str] = Field(None, alias="patchLotId")
    patch_serial: Optional[str] = Field(None, alias="patchSerial")
    ambient: AmbientMetadata
    dosing: DosingRecord
    images: List[CapturedImageMeta] = Field(default_factory=list)
    flags: List[str] = Field(default_factory=list)
    policy_snapshot: Dict[str, Any] = Field(default_factory=dict, alias="policySnapshot")


# =============================================================================
# Diagnostic Response & Analytics Models
# =============================================================================

class Measured(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    value: float
    sigma: float
    ci95_lo: Optional[float] = Field(None, alias="ci95Lo")
    ci95_hi: Optional[float] = Field(None, alias="ci95Hi")


class EvapMeasured(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    value: float
    sigma: float
    is_lower_bound: bool = Field(False, alias="isLowerBound")
    definition: str = "T_lateral_ref - 0.5*(T_up + T_down)"


class FlowEstimate(BaseModel):
    point: Optional[float] = None
    lo: float = 0.0
    hi: float = 0.0
    method: str = "empirical_characteristic_inversion"
    validated: bool = False
    is_experimental: bool = True


class TimepointResult(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    t_nominal_s: float = Field(..., alias="tNominalS")
    classification: Classification
    delta_t_ud_c: Optional[Measured] = Field(None, alias="deltaTUdC")
    confidence_pct: float = Field(..., alias="confidencePct")
    qa_passed: bool = Field(..., alias="qaPassed")
    qa_failures: List[str] = Field(default_factory=list, alias="qaFailures")


class TemperaturesBreakdown(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    upstream_c: Optional[Measured] = Field(None, alias="upstreamC")
    downstream_c: Optional[Measured] = Field(None, alias="downstreamC")
    lateral_ref_c: Optional[Measured] = Field(None, alias="lateralRefC")


class RoiVisual(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    name: str  # upstream | downstream | lateral_ref | aperture | overlay
    kind: RoiVisualKind
    url: str
    expires_at_utc: datetime = Field(..., alias="expiresAtUtc")
    width_px: int = Field(..., alias="widthPx")
    height_px: int = Field(..., alias="heightPx")


class RetestAdvice(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    code: str
    requires_new_patch: bool = Field(True, alias="requiresNewPatch")


class DiagnosticResponse(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    session_id: str = Field(..., alias="sessionId")
    engine_version: str = Field("1.2.0", alias="engineVersion")
    calibration_id_used: str = Field(..., alias="calibrationIdUsed")
    processed_at_utc: datetime = Field(default_factory=lambda: datetime.now(timezone.utc), alias="processedAtUtc")
    classification: Classification
    inconclusive_reason: Optional[InconclusiveReason] = Field(None, alias="inconclusiveReason")
    inconclusive_reason_raw: Optional[str] = Field(None, alias="inconclusiveReasonRaw")
    delta_t_ud_c: Optional[Measured] = Field(None, alias="deltaTUdC")
    delta_t_evap_c: Optional[EvapMeasured] = Field(None, alias="deltaTEvapC")
    estimated_flow_ml_min: Optional[FlowEstimate] = Field(None, alias="estimatedFlowMlMin")
    confidence_pct: float = Field(..., alias="confidencePct")
    confidence_factors: Dict[str, float] = Field(default_factory=dict, alias="confidenceFactors")
    snr_resolution_db: Optional[float] = Field(None, alias="snrResolutionDb")
    temperatures: TemperaturesBreakdown = Field(default_factory=TemperaturesBreakdown)
    timepoints: List[TimepointResult] = Field(default_factory=list)
    flags: List[str] = Field(default_factory=list)
    roi_visuals: List[RoiVisual] = Field(default_factory=list, alias="roiVisuals")
    retest_advice: Optional[RetestAdvice] = Field(None, alias="retestAdvice")


# =============================================================================
# Configuration & Remote Setup Models
# =============================================================================

class RemoteConfig(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    session_policy: Dict[str, Any] = Field(default_factory=dict, alias="sessionPolicy")
    alignment_thresholds: Dict[str, float] = Field(default_factory=dict, alias="alignmentThresholds")
    validator_thresholds: Dict[str, float] = Field(default_factory=dict, alias="validatorThresholds")
    patch_layout: PatchLayout = Field(..., alias="patchLayout")
    feature_flags: Dict[str, bool] = Field(default_factory=dict, alias="featureFlags")
    device_profile_version: int = Field(1, alias="deviceProfileVersion")


class DeviceProfile(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    platform: str
    model: str
    camera_id: str = Field(..., alias="cameraId")
    preview_analysis_size: SizeDto = Field(..., alias="previewAnalysisSize")
    still_size: SizeDto = Field(..., alias="stillSize")
    target_distance_mm: float = Field(100.0, alias="targetDistanceMm")
    android_focus_diopters: Optional[float] = Field(10.0, alias="androidFocusDiopters")
    ios_lens_position: Optional[float] = Field(0.10, alias="iosLensPosition")
    neutral_wb_gains: Optional[WbGains] = Field(None, alias="neutralWbGains")
    intrinsics_by_still: List[Intrinsics] = Field(default_factory=list, alias="intrinsicsByStill")
    version: int = 1


class SubmitAck(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    session_id: str = Field(..., alias="sessionId")
    status_url: str = Field(..., alias="statusUrl")


class SessionPoll(BaseModel):
    status: str  # processing | done | failed
    response: Optional[DiagnosticResponse] = None
    error_code: Optional[str] = None


class ProblemDetails(BaseModel):
    type: str = "about:blank"
    title: str
    status: int
    detail: Optional[str] = None
    code: str
    instance: Optional[str] = None

