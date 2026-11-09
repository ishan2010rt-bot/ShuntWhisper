# ShuntWhisper Client App — Master Architecture Blueprint

> **Audience:** Gemini 2.5 Flash (code generation) + the human integrator.
> **Status:** Design only. No implementation code is included beyond schemas and signatures.
> **Backend dependency:** the Python engine in `vision_engine/shuntwhisper_vision.py` (library + CLI). **No HTTP service exists yet**, so Track B (§F) must be built in parallel.

---

## 0. Read First — Reconciliation of Locked Specs vs. the Existing Engine

These mismatches are real. Each one changes a contract below, so each has a stated decision. Items marked ❓ need the owner's confirmation before Prompt 1 is run.

| # | Locked spec (this brief) | Existing engine (`shuntwhisper_vision.py`) | Decision in this blueprint |
|---|---|---|---|
| R1 | Discrete TLC patches at x = ±8.7 mm; lateral reference 12 mm off-axis; 7.6×7.6 mm bare-foam aperture | One continuous TLC film, ROIs at ±13 mm, 80×40 mm window, 10 px/mm, `substrate_ref`/`evap_center` ROIs | **Backend task B0:** re-parameterise `PatchGeometry`. Client never hard-codes geometry. It reads a `PatchLayout` from `GET /v1/config`. Defaults in §B.7 are placeholders. |
| R2 | `ΔT_evap` is a required response field | Engine has `sink_drop_c` = T_substrate − T_evap_center, which assumes TLC *under/next to* the foam | Foam aperture is **bare melamine, no TLC under it**, so `ΔT_evap` is undefined as written. ❓ Proposed definition: `ΔT_evap ≡ T_lateral_ref − ½(T_up + T_down)`. Backend B3 implements it. The client treats it as an opaque, nullable number with a `definition` string. |
| R3 | Classes `PATENT_HIGH / PATENT_MARGINAL / OCCLUDED / INCONCLUSIVE` | `PATENT_NORMAL / PATENT_LOW / OCCLUSION / INDETERMINATE` | Backend adapter maps 1:1 (§B.6). Thresholds stay 0.10 / 0.35 °C. Your characteristic patent band (0.2–0.8) is inside those. ❓ Confirm 0.10–0.35 = MARGINAL. |
| R4 | Estimated flow rate `Q` | **Not implemented.** No validated ΔT→Q map exists. | Field is nullable, carries `lo/hi/method/validated`, and is behind feature flag `showFlowEstimate` (default **false**). |
| R5 | Dose 60–80 µL | Engine/hydration gate is dose-agnostic | Dose range is remote config. UI warns outside the range, still allows, and uploads `dose_out_of_spec=true`. |
| R6 | "Baseline at t = 0" | Engine baseline is the **dry** frame; timer starts at dosing | **Assumption:** baseline is captured immediately *before* dosing. **t = 0 ≡ dose-confirmed instant.** ❓ Confirm. |
| R7 | Backend is a "previously built engine" | CLI + library only | Track B: FastAPI wrapper around `ShuntWhisperEngine.diagnose()` (the repo already lists `fastapi` and `uvicorn` in `requirements.txt`). |
| R8 | 4 fiducials implied | `DICT_4X4_50`, ids 0–3 | Kept. Marker size/positions come from `PatchLayout`. |
| R9 | Bragg viewing-angle effect | Engine corrects with PnP, so it needs **real camera intrinsics** | Client uploads intrinsics per image (§B.3). Without them the backend falls back to an FOV guess, which degrades the correction. |

> [!IMPORTANT]
> The Bragg cos θ artefact makes **lateral camera offset** a first-order error source. At x₀ = 8.7 mm, d = 100 mm and κ = 13.75 °C per unit cos θ (κ is **unmeasured**), the uncorrected error is ≈ **0.024 °C per mm** of lateral offset. Alignment thresholds in §B.2 follow from this.

---

## A. Technical Stack & Project Tree

### A.1 Framework decision: **Flutter + a custom native camera plugin**

| Criterion | Flutter (official `camera`) | React Native (`react-native-vision-camera`) | Verdict |
|---|---|---|---|
| Manual ISO / shutter | ❌ Exposure *offset* only | Reported ✅ (verify against current docs) | Neither stock option is enough alone |
| AWB **gains** (not presets) | ❌ Presets/lock only | Reported ✅ | |
| Manual lens distance | ❌ Tap-to-focus only | Reported ✅ | |
| `TONEMAP`, `NOISE_REDUCTION`, `EDGE`, colour-transform identity, OIS-off, torch **level** | ❌ | ❌ not exposed as a contract | **Required for a deterministic radiometric pipeline** |
| **Read-back of the applied state** | ❌ | ❌ | **Required** (see invariant I1) |
| Typed host↔native contract | Pigeon (codegen) | JSI/TurboModule (hand-written) | Flutter wins for LLM-generated code |
| FSM tooling | `flutter_bloc` + `bloc_test` | Redux/XState | Equal |
| Custom HUD drawing | `CustomPainter` | Skia/Reanimated | Equal |

The web research summary for RN's manual-control API names was model-generated and **unverified**. Regardless, **both frameworks need a purpose-built native capture module** to control the CaptureRequest fields that determine radiometric fidelity.

**Decision:** Flutter UI + Bloc FSM + a first-party plugin `shuntwhisper_camera` (Kotlin/Camera2, Swift/AVFoundation) behind a **Pigeon** contract. React Native is acceptable only if the team's skills dictate, and the same native modules would be reused.

**Architecture invariants (non-negotiable):**
- **I1 — Apply → Read back → Verify.** Every camera configuration returns an `AppliedCameraState` read from capture results. If it deviates beyond tolerance, capture is blocked. The app never assumes a setting took effect.
- **I2 — Monotonic time only.** Elapsed time uses `SystemClock.elapsedRealtimeNanos` / `mach_continuous_time`. Frame times are sensor timestamps. Wall-clock is audit-only.
- **I3 — Pure FSM.** `reduce(state, event, policy) → (state, effects)` has no I/O. An `EffectRunner` performs side effects.
- **I4 — Forward-only after t0.** Once dosing is confirmed, the physics cannot be rewound. Failures degrade (missed timepoint) or end in retest. There is no "go back".
- **I5 — Contract-first.** The backend is defined by OpenAPI 3.1 (`docs/openapi.yaml`). The native plugin is defined by Pigeon. Dart models mirror both.
- **I6 — No frames over the platform channel at full res.** Preview analysis uses a downscaled luma plane (~10 Hz). Full-res stills stay native until encoded to disk.

### A.2 Packages (pin exact versions in `pubspec.yaml` at generation time)

`flutter_bloc`, `equatable`, `freezed(+annotation)`, `json_serializable(+annotation)`, `build_runner`, `dio`, `drift` (+`sqlite3_flutter_libs`), `path_provider`, `get_it`, `go_router`, `wakelock_plus`, `permission_handler`, `battery_plus`, `connectivity_plus`, `flutter_local_notifications`, `workmanager`, `uuid`, `crypto`, `pdf`, `printing`, `share_plus`, `opencv_dart` (**spike S1**, see risks), dev: `pigeon`, `bloc_test`, `mocktail`, `very_good_analysis`, `golden_toolkit`.

### A.3 Project file tree

```text
shuntwhisper_app/
├─ pubspec.yaml · analysis_options.yaml · build.yaml · melos.yaml
├─ docs/
│  ├─ openapi.yaml                  # single source of truth for backend contract
│  ├─ fsm_table.md                  # mirror of §C table (tests read it)
│  └─ device_profiles/              # seed JSON per phone model
├─ packages/
│  └─ shuntwhisper_camera/          # native plugin
│     ├─ pigeons/camera_api.dart    # Pigeon source of truth
│     ├─ lib/shuntwhisper_camera.dart
│     ├─ lib/src/{camera_service.dart, camera_service_impl.dart, frame_validator.dart,
│     │           fiducial_tracker.dart, fiducial_tracker_opencv.dart, pose_math.dart,
│     │           readback_verifier.dart, generated/camera_api.g.dart}
│     ├─ android/src/main/kotlin/…/{ShuntCameraPlugin.kt, Camera2Session.kt,
│     │           ManualRequestBuilder.kt, CapabilityProbe.kt, ReadbackVerifier.kt,
│     │           TorchGovernor.kt, StillRing.kt, PngEncoder.kt, PreviewLumaStreamer.kt}
│     └─ ios/Classes/{ShuntCameraPlugin.swift, CaptureSession.swift, ManualConfigurator.swift,
│                     CapabilityProbe.swift, ReadbackVerifier.swift, TorchGovernor.swift,
│                     StillRing.swift, PngEncoder.swift, PreviewLumaStreamer.swift}
├─ lib/
│  ├─ main.dart · app.dart · bootstrap.dart
│  ├─ core/
│  │  ├─ di/injection.dart
│  │  ├─ config/{session_policy.dart, remote_config_cache.dart, env.dart}
│  │  ├─ errors/{failure.dart, error_codes.dart}
│  │  ├─ time/{monotonic_clock.dart, fake_clock.dart}
│  │  └─ logging/app_logger.dart
│  ├─ domain/
│  │  ├─ models/            # §B (freezed + json_serializable)
│  │  │  ├─ enums.dart · remote_config.dart · patch_layout.dart · device_profile.dart
│  │  │  ├─ camera_hardware_config.dart · camera_capabilities.dart · applied_camera_state.dart
│  │  │  ├─ fiducial_alignment_state.dart · frame_validation_result.dart
│  │  │  ├─ capture_payload.dart · captured_image_meta.dart · ambient_metadata.dart · dosing_record.dart
│  │  │  ├─ diagnostic_response.dart · roi_visual.dart · session_checkpoint.dart
│  │  ├─ repositories/{diagnostic_repository.dart, config_repository.dart, session_store.dart}
│  │  └─ usecases/{run_preflight.dart, select_best_frame.dart, build_capture_payload.dart,
│  │               map_failure_to_recovery.dart}
│  ├─ data/
│  │  ├─ api/{shuntwhisper_api.dart, dio_shuntwhisper_api.dart, retry_interceptor.dart,
│  │  │       auth_interceptor.dart, problem_details.dart, multipart_builder.dart}
│  │  ├─ local/{app_database.dart, outbox_dao.dart, session_dao.dart, history_dao.dart}
│  │  └─ repositories/{diagnostic_repository_impl.dart, config_repository_impl.dart,
│  │                   session_store_impl.dart}
│  ├─ features/
│  │  ├─ session/  (FSM)   bloc/{session_bloc.dart, session_state.dart, session_event.dart,
│  │  │                          session_effect.dart, session_reducer.dart, effect_runner.dart}
│  │  ├─ preflight/        presentation/{preflight_page.dart, check_tile.dart}
│  │  ├─ alignment/        bloc/alignment_cubit.dart
│  │  │                    presentation/{viewfinder_page.dart, viewfinder_view.dart}
│  │  ├─ dosing/           presentation/{dosing_prompt_sheet.dart, dose_volume_picker.dart}
│  │  ├─ countdown/        presentation/{countdown_page.dart, countdown_ring.dart}
│  │  ├─ upload/           presentation/upload_page.dart
│  │  ├─ report/           presentation/{report_page.dart, status_banner.dart, metric_card.dart,
│  │  │                                  thermal_comparison_view.dart, roi_gallery.dart,
│  │  │                                  why_inconclusive_panel.dart}
│  │  │                    pdf/report_pdf_builder.dart
│  │  ├─ history/          presentation/history_page.dart
│  │  └─ error/            presentation/error_page.dart
│  ├─ presentation/
│  │  ├─ router/app_router.dart · theme/app_theme.dart
│  │  └─ hud/{alignment_hud.dart, reticle_painter.dart, patch_box_painter.dart,
│  │          stability_indicator.dart, guidance_banner.dart, coordinate_mapper.dart}
│  └─ l10n/{app_en.arb, app_hi.arb}
├─ test/
│  ├─ fsm/{reducer_table_test.dart, policy_boundary_test.dart}
│  ├─ models/{json_roundtrip_test.dart}  fixtures/{engine_response_*.json}
│  ├─ data/{api_retry_test.dart, multipart_test.dart}
│  └─ presentation/{hud_golden_test.dart, report_golden_test.dart}
├─ integration_test/{camera_conformance_test.dart, full_session_fake_camera_test.dart}
└─ tool/{gen_all.sh, verify_fsm_doc.dart}
```

---

## B. Interface Contracts & Data Models

**Conventions:** Dart models are `freezed` + `json_serializable`, with `fieldRename: FieldRename.snake`. SI units, and unit suffix in every name (`…Ns`, `…Mm`, `…C`, `…Deg`, `…Ul`). Unknown enum values deserialize to a `unknown` member and never throw. Times on the wire are ISO-8601 UTC; durations are integer ms.

### B.1 `CameraHardwareConfig` (request) · `AppliedCameraState` (read-back) · `CameraCapabilities`

**`CameraHardwareConfig`**

| Field | Type | Constraint / note |
|---|---|---|
| `cameraId` | `String` | Chosen physical lens id. Same lens for the whole session. |
| `iso` | `int` | Target 50. Clamped to the sensor range. Never auto. |
| `exposureTimeNs` | `int` | 10 000 000 (1/100 s, 50 Hz mains) or 8 333 333 (1/120 s, 60 Hz). From `mainsHz`. |
| `frameDurationNs` | `int` | ≥ exposure. Default 33 333 333. |
| `focus` | `FocusSpec` | `{ targetDistanceMm: 100, androidDiopters?: double, iosLensPosition?: double }`. The platform value comes from the device profile. |
| `torch` | `TorchSpec` | `{ mode: off\|on, level: 0..1 (1.0 default), policy: always_on\|windowed, preRollMs: 2500 }` |
| `whiteBalance` | `WhiteBalanceSpec` | `{ mode: lockedGains, gains: {r, gEven, gOdd, b}?, kelvin: 5500, tint: 0 }`. Gains come from the device profile. If absent, the platform derives them from 5500 K. |
| `mainsHz` | `int` | 50 or 60 |
| `isp` | `IspSpec` | `{ tonemap: srgbPreset, noiseReduction: minimal\|off, edgeMode: off, ois: off, videoStabilization: off, hdr: off, zoomRatio: 1.0 }` |
| `stillSize` | `SizeDto` | ≤ ~12 MP. From the profile. |
| `previewAnalysisSize` | `SizeDto` | 1280×960 luma stream, 10 Hz |

**`AppliedCameraState`** is read from `CaptureResult` (Android) or KVO (iOS):
`iso`, `exposureTimeNs`, `whiteBalanceGains`, `focusDistanceDiopters?`, `lensPosition?`, `torchLevel`, `awbLocked`, `aeLocked`, `sensorTimestampNs`, `verified: bool`, `deviations: List<ParamDeviation{param, requested, applied, withinTolerance}>`.

*Tolerances:* ISO exact (or the nearest supported value, flagged); exposure ±2 %; gains ±1 %; focus ±5 %; torch ±0.05.

**`CameraCapabilities`**: `hasManualSensor`, `isoRange`, `exposureRangeNs`, `minFocusDistanceMm`, `hasTorch`, `torchLevels`, `supportsWbGains`, `supportedStillSizes`, `intrinsics?`, `hardwareLevel`, `physicalCameraIds`.

### B.2 `FiducialAlignmentState` (emitted ≈10 Hz)

| Field | Type | Note |
|---|---|---|
| `frameSeq`, `timestampNs` | `int` | Sensor-clock time |
| `analysisSize` | `SizeDto` | Coordinate space of all `*Px` fields |
| `markersDetected` | `int 0..4` | |
| `markerCentersPx` | `List<PointDto?>` len 4, ordered by id 0..3 | `null` = not found. Projectively correct centre (diagonal intersection). |
| `canonToImageH` | `List<double>?` len 9 | Homography from patch-frame mm to analysis px. Drives HUD boxes. |
| `roiQuadsPx` | `Map<String, List<PointDto>>` | `upstream`, `downstream`, `lateral_ref`, `aperture`: 4 corners each |
| `pitchDeg`, `yawDeg`, `rollDeg` | `double?` | Patch-normal tilt and in-plane roll |
| `distanceMm` | `double?` | |
| `lateralOffsetMm` | `PointDto?` | Camera offset from the aperture axis, in the patch frame |
| `centerOffsetFrac` | `double?` | Patch centre vs frame centre, as a fraction of the diagonal |
| `sharpness` | `double?` | Normalised Laplacian variance (§D.2) |
| `stabilityScore` | `double 0..1` | `1 − clamp(σ_centres_px / 3 px)` over the last 8 frames |
| `consecutiveAlignedFrames`, `alignedForMs` | `int` | |
| `status` | `AlignmentStatus` | `ALIGNED`, `MISALIGNED`, `UNSTABLE` (+ `NOT_DETECTED` added: fewer than 4 markers) |
| `violations` | `List<AlignmentViolation>` | `TOO_FAR`, `TOO_CLOSE`, `PITCH`, `YAW`, `ROLL`, `OFF_CENTER`, `LATERAL_OFFSET`, `NEAR_FRAME_EDGE`, `BLUR`, `GLARE`, `UNDER_EXPOSED` |

**Status rules**
- `NOT_DETECTED`: markersDetected < 4.
- `UNSTABLE`: stabilityScore < 0.8.
- `MISALIGNED`: any violation.
- `ALIGNED`: none of the above.

**Default `AlignmentThresholds`** (remote-configurable):

| Threshold | Default | Origin |
|---|---|---|
| Distance | target ±10 % | engine `GuidanceChecker` |
| Pitch / yaw | ≤ 5° | engine |
| Roll | ≤ 8° | engine |
| Centre offset | ≤ 0.05 of the diagonal | engine |
| Lateral offset | ≤ ±2 mm | derived from the 0.024 °C/mm figure above (0.05 °C uncorrected) |
| Frame margin | ≥ 4 % | engine |

### B.3 `CapturePayload`

Wire format is **multipart/form-data**: part `metadata` (JSON) + binary parts `baseline`, `t23`, `t120`. Header `Idempotency-Key: <sessionId>`. Base64-in-JSON is rejected: it adds 33 % size and memory pressure.

**`CapturePayload` (metadata JSON)**

| Field | Type | Note |
|---|---|---|
| `sessionId` | uuid v4 | Client-generated; idempotency key |
| `schemaVersion` | `int` | 1 |
| `createdAtUtc` | ISO-8601 | |
| `subjectRef?` | `String` | Pseudonymous. Never a name or MRN. |
| `app` | `{version, build, platform, osVersion}` | |
| `device` | `{model, cameraId, hardwareLevel, profileVersion}` | |
| `calibrationId` | `String` | TLC lot calibration. **Required.** |
| `patchLotId?`, `patchSerial?` | `String` | |
| `ambient` | `AmbientMetadata` | `{temperatureC, relativeHumidityPct, source: manual\|sensor\|ble, measuredAtUtc}` |
| `dosing` | `DosingRecord` | `{volumeUl, tZeroMonotonicNs, tZeroUtc, detection: manual_tap\|auto_foam, outOfSpec}` |
| `images` | `List<CapturedImageMeta>` | 1–3 entries, see below |
| `flags` | `List<String>` | e.g. `T23_MISSED`, `STEADY_MISSING`, `DOSE_OUT_OF_SPEC`, `TORCH_WINDOWED`, `APP_BACKGROUNDED` |
| `policySnapshot` | `{windowHalfWidthS, torchPolicy, …}` | Reproducibility |

**`CapturedImageMeta`**

| Field | Note |
|---|---|
| `part` | `baseline` \| `t23` \| `t120` (multipart part name) |
| `tNominalS` | −0 (baseline), 23, 120 |
| `tActualS` | `(sensorTimestamp − tZeroMonotonic)`, so baseline is ≤ 0 |
| `mime`, `encoding` | `image/png` (lossless, preferred) or `image/jpeg` + `jpegQuality`/`chromaSubsampling` |
| `widthPx`, `heightPx`, `sizeBytes`, `sha256` | Integrity |
| `appliedCamera` | `AppliedCameraState` at capture |
| `alignmentAtCapture` | `FiducialAlignmentState` summary |
| `validation` | `FrameValidationResult` (§D.2) |
| `intrinsics` | `{fx, fy, cx, cy, imageW, imageH, source: camera_characteristics\|profile\|estimated}` |
| `burstIndex`, `burstSize` | Which frame of the burst was chosen |

### B.4 `DiagnosticResponse`

| Field | Type | Note |
|---|---|---|
| `sessionId`, `engineVersion`, `calibrationIdUsed`, `processedAtUtc` | | |
| `classification` | `PATENT_HIGH \| PATENT_MARGINAL \| OCCLUDED \| INCONCLUSIVE \| UNKNOWN` | §B.6 |
| `inconclusiveReason?` | `InconclusiveReason` | §B.6. Raw string preserved in `inconclusiveReasonRaw`. |
| `deltaTUdC` | `Measured{value, sigma, ci95Lo?, ci95Hi?}` | Primary result. Sign is T_up − T_down. |
| `deltaTEvapC` | `Measured{value, sigma, isLowerBound, definition}?` | See R2 |
| `estimatedFlowMlMin` | `FlowEstimate{point?, lo, hi, method, validated}?` | See R4 |
| `confidencePct` | `double 0..100` | |
| `confidenceFactors` | `Map<String,double>` | `registration`, `sharpness`, `color_fit`, `exposure`, `illumination`, `specular`, `roi_validity`, `resolution_snr`, `illum_drift` |
| `snrResolutionDb` | `double?` | 20·log₁₀(0.1 °C / σ_ΔT) |
| `temperatures` | `{upstreamC, downstreamC, lateralRefC}` as `Measured?` | |
| `timepoints` | `List<TimepointResult>` | `{tNominalS, classification, deltaTUdC, confidencePct, qaPassed, qaFailures[]}` |
| `flags` | `List<String>` | e.g. `SPECULAR_NEAR_ROI`, `NEAR_DECISION_BOUNDARY`, `FALLBACK_TO_TRANSIENT` |
| `roiVisuals` | `List<RoiVisual>` | `{name: upstream\|downstream\|lateral_ref\|aperture\|overlay, kind: crop\|overlay\|normalized\|spec_mask, url, expiresAtUtc, widthPx, heightPx}`. URLs are signed and expire (≈15 min). |
| `retestAdvice?` | `{code, requiresNewPatch}` | Copy lives in client ARB files, never in the API. |

### B.5 Backend REST contract (OpenAPI source of truth)

| Method + path | Purpose | Success |
|---|---|---|
| `GET /v1/config` | `RemoteConfig{sessionPolicy, alignmentThresholds, validatorThresholds, patchLayout, featureFlags, deviceProfileVersion}` | 200 + `ETag` |
| `GET /v1/device-profiles/{platform}/{model}` | `DeviceProfile` (404 → default profile) | 200 |
| `GET /v1/calibrations/{calibrationId}` | `{valid, expiresAtUtc, lotId}` | 200 |
| `POST /v1/sessions` | Multipart upload | **202** `{sessionId, statusUrl}`; replay with the same key → 200/202 |
| `GET /v1/sessions/{id}` | Poll | **200** `DiagnosticResponse` · **202** `{status: queued\|processing}` · 200 `{status: failed, code}` |
| `GET /v1/sessions/{id}/rois/{name}` | ROI PNG (signed URL) | 200 |
| `DELETE /v1/sessions/{id}` | PHI erasure | 204 |

- **Auth:** OAuth2 bearer. Per-install token via a device-registration flow (details TBD ❓). TLS ≥ 1.2.
- **Errors:** RFC 7807 `application/problem+json` with a `code` enum: `INVALID_IMAGE`, `PAYLOAD_TOO_LARGE`, `UNSUPPORTED_MEDIA`, `CALIBRATION_UNKNOWN`, `CALIBRATION_EXPIRED`, `RATE_LIMITED`, `ENGINE_FAILURE`, `UNAUTHENTICATED`.
- **Limits:** ≤ 25 MB per part; ≤ 60 MB total.

### B.6 Engine → client mapping

| Engine `FlowStatus` | Client `classification` | UI wording (never "diagnosis") |
|---|---|---|
| `PATENT_NORMAL_FLOW` | `PATENT_HIGH` | "Flow signature present" |
| `PATENT_LOW_FLOW` | `PATENT_MARGINAL` | "Weak flow signature" |
| `OCCLUSION_SUSPECTED` | `OCCLUDED` | "Possible blockage — seek clinical evaluation" |
| `INDETERMINATE_RETEST` | `INCONCLUSIVE` | "Test could not be interpreted" |

`InconclusiveReason` (engine codes): `INSUFFICIENT_HYDRATION`, `OUT_OF_RANGE_WARM`, `OUT_OF_RANGE_COLD`, `QC_MOTION_BLUR`, `QC_REGISTRATION`, `QC_EXPOSURE`, `QC_COLOR_FIT`, `QC_ILLUMINATION`, `SPECULAR_ROI`, `REVERSE_GRADIENT`, `LOW_SNR`, `SINK_UNVERIFIABLE`, `OTHER`.

> [!WARNING]
> `INSUFFICIENT_HYDRATION` must **never** render as "blocked". An un-cooled patch is symmetric and looks like an occlusion. The engine gates on it first, and the UI must preserve that distinction.

### B.7 `PatchLayout` (defaults are placeholders; backend `/v1/config` is authoritative)

Patch frame: origin at the aperture centre, x along the catheter (flow +x), y perpendicular, units mm.

| Element | Default | Source |
|---|---|---|
| `upstream` centre | (−8.7, 0) | locked |
| `downstream` centre | (+8.7, 0) | locked |
| `lateralRef` centre | (0, +12) | locked magnitude; **sign ❓** |
| `aperture` | 7.6 × 7.6 at (0, 0) | locked |
| `roiSizeMm` | 4.0 × 4.0 | **assumed ❓** |
| `fiducials` | 4× ArUco `DICT_4X4_50`, ids 0–3 TL/TR/BR/BL, centres + side from config | not in brief ❓ |

---

## C. Client Lifecycle FSM

### C.1 Diagram

```mermaid
stateDiagram-v2
    [*] --> IDLE
    IDLE --> PRE_CHECK: start session
    PRE_CHECK --> BASELINE_ALIGN: all checks pass
    PRE_CHECK --> ERROR_HANDLING: blocking check failed
    BASELINE_ALIGN --> BASELINE_CAPTURED: aligned and stable and baseline frame passes QC
    BASELINE_ALIGN --> ERROR_HANDLING: align timeout or camera lost
    BASELINE_CAPTURED --> DOSING_PROMPT: auto after 1.5 s
    BASELINE_CAPTURED --> BASELINE_ALIGN: user retake
    DOSING_PROMPT --> COUNTDOWN_TRANSIENT: dose confirmed sets t0
    DOSING_PROMPT --> BASELINE_ALIGN: baseline stale after 180 s
    COUNTDOWN_TRANSIENT --> COUNTDOWN_STEADY: t reaches 24 s window closed
    COUNTDOWN_STEADY --> UPLOADING: t reaches 121 s window closed
    COUNTDOWN_TRANSIENT --> ERROR_HANDLING: abort or camera lost or timer expired
    COUNTDOWN_STEADY --> ERROR_HANDLING: abort or no usable frames or timer expired
    UPLOADING --> REPORT_READY: result received
    UPLOADING --> ERROR_HANDLING: rejected or analysis failed
    UPLOADING --> IDLE: saved offline or result pending
    REPORT_READY --> IDLE: new session
    ERROR_HANDLING --> PRE_CHECK: retry pre-dose
    ERROR_HANDLING --> IDLE: restart or give up
    IDLE --> [*]
```

`UPLOADING` has internal sub-states `ENCODING → SENDING → ANALYZING` (with `OFFLINE_QUEUED`). `COUNTDOWN_*` each have sub-states `WAITING → PREROLL → CAPTURING → SELECTING`.

### C.2 `SessionPolicy` (remote-configurable defaults)

| Key | Default | Meaning |
|---|---|---|
| `targetDistanceMm` | 100 | Overridden by the device profile |
| `alignStableFrames` / `alignStableMs` | 8 / 800 | Trigger for baseline capture |
| `alignTimeoutS` | 120 | |
| `baselineCaptureBurst` | 3 frames @ ≥ 4 fps | |
| `baselineRetryMax` | 3 | |
| `baselineStaleS` | 180 | Rollback trigger (patch thermal drift) |
| `doseVolumeUl` | 60–80 (default 70) | |
| `tTransientS`, `tSteadyS` | 23, 120 | Counted from t0 |
| `windowHalfWidthS` | 1.0 | Capture windows [22, 24] and [119, 121] |
| `burstFrames` / `burstMinFps` | 8 / 4 | |
| `torchPolicy` / `torchPreRollMs` | `windowed` / 2500 | See note below |
| `preWarnS` | 3 | "Hold steady" cue before each window |
| `timerExpiredGraceS` | 30 | After the T120 window closes with no capture |
| `uploadRetryBackoffS` | 2, 4, 8, 16, 32 (±20 % jitter), max 5 | |
| `analysisPollS` | 1.0 ×15, then 2.0, until 90 s | |
| `minBatteryPct`, `minFreeMb` | 20, 500 | |
| `ambientHardRangeC` / `ambientWarnRangeC` | 10–35 / 15–30 | |

> [!NOTE]
> **Torch policy `windowed` is a design hypothesis, not a measured result.** A phone and a continuous LED at 10 cm may warm the patch and block airflow over the foam, which would bias the evaporative sink. `windowed` limits LED-on time. Illumination changes are absorbed by the backend swatch normalisation and its `illum_drift` factor. Bench-test `always_on` vs `windowed` before locking the default.

### C.3 Transition table (authoritative)

`t` is elapsed monotonic time since t0. "Pass" for frame QC means all validators in §D.2 pass.

| ID | From | Event / trigger | Guard | Entry & transition actions | To |
|---|---|---|---|---|---|
| T01 | IDLE | `StartSession` | none | New `sessionId`; wakelock on; load config from cache | PRE_CHECK |
| T02 | PRE_CHECK | `ChecksComplete` | All blocking checks pass (below) | Persist checkpoint | BASELINE_ALIGN |
| T03 | PRE_CHECK | `CheckFailed(code)` | Any blocking check fails | Build `ErrorRecoveryPlan` | ERROR_HANDLING |
| T04 | BASELINE_ALIGN | *(entry)* | none | `applyConfig` → read back (≤ 3 attempts, 250 ms apart) → torch on, 1.5 s warm-up → start 10 Hz analysis | (stay) |
| T05 | BASELINE_ALIGN | `ConfigVerifyFailed` | After 3 attempts | Log the deviations | ERROR_HANDLING (`CAMERA_CONFIG_UNVERIFIED`) |
| T06 | BASELINE_ALIGN | `AlignmentFrame` | none | Update HUD and guidance text | (stay) |
| T07 | BASELINE_ALIGN | `AlignmentFrame` | `status==ALIGNED` for ≥ 8 frames **and** ≥ 800 ms | Capture burst of 3; pick best by `sharpness`; run still validators | BASELINE_CAPTURED if best frame passes; else stay with `retries++` |
| T08 | BASELINE_ALIGN | `retries ≥ 3` | none | Show specific `violations` (glare → "use diffuser shroud") | (stay, retries reset) |
| T09 | BASELINE_ALIGN | `Tick` | elapsed in state > 120 s | | ERROR_HANDLING (`ALIGN_TIMEOUT`) |
| T10 | BASELINE_CAPTURED | *(entry)* | none | Save PNG + sha256; show ✓ | (stay) |
| T11 | BASELINE_CAPTURED | `Tick` | 1.5 s elapsed | | DOSING_PROMPT |
| T12 | BASELINE_CAPTURED | `UserRetake` | pre-dose | Discard baseline | BASELINE_ALIGN |
| T13 | DOSING_PROMPT | *(entry)* | none | Show syringe instructions; keep preview, torch and analysis live; start stale timer | (stay) |
| T14 | DOSING_PROMPT | `DoseConfirmed(volumeUl)` | none. Out of range → warn; set `DOSE_OUT_OF_SPEC` | **t0 = monotonic now.** Haptic. Start ticker. Persist checkpoint (t0, files) | COUNTDOWN_TRANSIENT |
| T15 | DOSING_PROMPT | `FoamWetDetected(ts)` | `autoDetect` flag on | **t0 = ts (latency-corrected).** Auto-advance; flag `T0_AUTO` | COUNTDOWN_TRANSIENT |
| T16 | DOSING_PROMPT | `Tick` | time in state > 180 s | Discard baseline | BASELINE_ALIGN |
| T17 | COUNTDOWN_TRANSIENT | `Tick` | `t ≥ 20` (= 23 − preWarn) | "Hold steady" haptic and banner | (stay) |
| T18 | COUNTDOWN_TRANSIENT | `Tick` | `t ≥ 22 − preRoll/1000` | Torch on (if windowed) | (stay, PREROLL) |
| T19 | COUNTDOWN_TRANSIENT | `Tick` | `t ≥ 22.0` | Start burst: 8 frames ≥ 4 fps; tag each with `t_actual` | (stay, CAPTURING) |
| T20 | COUNTDOWN_TRANSIENT | `Tick` | `t ≥ 24.0` or burst full | Select best passing frame; if none, flag `T23_MISSED`. **No rollback.** Torch off if windowed | COUNTDOWN_STEADY |
| T21 | COUNTDOWN_STEADY | `Tick` | `t ≥ 116` (= 119 − 3 s preroll cue) | Torch on, 2.5 s warm-up (if windowed) | (stay, PREROLL) |
| T22 | COUNTDOWN_STEADY | `Tick` | `t ≥ 119.0` | Start burst | (stay, CAPTURING) |
| T23 | COUNTDOWN_STEADY | `Tick` | `t ≥ 121.0` or burst full | Select best. Torch off. Release camera | UPLOADING if a T120 frame, or baseline + T23 frame exists (flag `STEADY_MISSING`); else ERROR_HANDLING (`NO_USABLE_FRAMES`) |
| T24 | UPLOADING | *(entry)* | none | ENCODING (isolate): PNG encode, sha256, build payload; **persist outbox row before any network I/O** | (stay) |
| T25 | UPLOADING | `UploadSucceeded(202)` | none | Start polling | (stay, ANALYZING) |
| T26 | UPLOADING | `NetworkError` / 5xx / 429 | attempts < 5 | Back off per policy; honour `Retry-After` | (stay) |
| T27 | UPLOADING | `NetworkError` | 2 failures **and** offline | Mark outbox `OFFLINE_QUEUED`; schedule WorkManager / BGTask; notify "Saved, will upload" | IDLE |
| T28 | UPLOADING | `HttpRejected(4xx)` | 400/413/415/422 | No retry | ERROR_HANDLING (`UPLOAD_REJECTED`) |
| T29 | UPLOADING | `ResultReady(resp)` | `200` | Persist to history; haptic by class | REPORT_READY |
| T30 | UPLOADING | `AnalysisFailed(code)` | `status==failed` | | ERROR_HANDLING (`ANALYSIS_FAILED`) |
| T31 | UPLOADING | `Tick` | polling > 90 s | History row "pending" | IDLE |
| T32 | REPORT_READY | `NewSession` | none | Release camera, wakelock off | IDLE |
| T33 | any COUNTDOWN_* | `UserAbort` | After confirm dialog | Release camera, torch off. Mark patch consumed | ERROR_HANDLING (`USER_ABORT`) |
| T34 | any camera-active | `CameraLost` | Recovery (reopen + re-apply + verify) fails within 2 s, 3 tries | If in COUNTDOWN_*: keep timer running, mark the affected windows missed | ERROR_HANDLING (`CAMERA_LOST`) unless a window can still be met |
| T35 | any COUNTDOWN_* | `AppResumed` | Elapsed from monotonic clock | If past a window, mark it missed; if `t > 121 + 30 s` with no T120 frame → `TIMER_EXPIRED` | continue or ERROR_HANDLING |
| T36 | any pre-dose | `AppPaused` | | Torch off, release camera | (stay, camera reopens on resume) |
| T37 | any camera-active | `ThermalSevere` | | Reduce analysis fps; if in a window, still capture | (stay) |
| T38 | ERROR_HANDLING | `Recover(route)` | `RETRY_PRE_DOSE` only if t0 unset | | PRE_CHECK |
| T39 | ERROR_HANDLING | `Recover(route)` | otherwise | Camera/torch released; wakelock off | IDLE |
| T40 | boot | `CheckpointFound` | state ≥ COUNTDOWN and `t < 151 s` | Offer resume; otherwise record as aborted | per T35 |

**Blocking pre-checks (T02):**
1. Camera permission granted.
2. `hasManualSensor` and `hasTorch`.
3. `minFocusDistanceMm ≤ targetDistanceMm × 1.1` (else the profile's `targetDistanceMm` is raised, or ERROR `FOCUS_UNREACHABLE`).
4. Battery ≥ 20 % or charging.
5. Free storage ≥ 500 MB.
6. Calibration id valid and unexpired.
7. Ambient temperature entered and in [10, 35] °C.
8. Device profile loaded (default allowed with a warning flag).

**Rollback rules (answering "severe blur during countdown"):**
- **Pre-dose** (BASELINE_ALIGN, BASELINE_CAPTURED, DOSING_PROMPT): rollbacks are free (T12, T16).
- **Post-dose:** no rollback (invariant I4). Blur or glare inside a window drops that burst's frames, flags the timepoint missed, and the session continues. T120 missing → partial upload; baseline, T23 and T120 all missing → retest with a **new patch** (a wetted foam cannot be reused).

**`ErrorRecoveryPlan`** `{code, severity, messageKey, routes[]}` — routes: `RETRY_PRE_DOSE`, `RESTART_NEW_PATCH`, `CHECK_SETTINGS`, `CONTACT_SUPPORT`, `VIEW_HISTORY`.

---

## D. Low-Level Camera & Computer-Vision Contract

### D.1 Hardware configuration rules (client side)

**Android (Camera2)** — `TEMPLATE_MANUAL` request, all keys explicit:

| Group | Setting |
|---|---|
| 3A off | `CONTROL_MODE = OFF`, `CONTROL_AE_MODE = OFF`, `CONTROL_AWB_MODE = OFF`, `CONTROL_AF_MODE = OFF`, `CONTROL_AE_LOCK`/`AWB_LOCK` set where available |
| Exposure | `SENSOR_SENSITIVITY` = 50 (clamped to `SENSOR_INFO_SENSITIVITY_RANGE`); `SENSOR_EXPOSURE_TIME` = 10 000 000 ns (50 Hz) or 8 333 333 ns (60 Hz); `SENSOR_FRAME_DURATION` ≥ exposure |
| White balance | `COLOR_CORRECTION_MODE = TRANSFORM_MATRIX`; `COLOR_CORRECTION_GAINS` = profile neutral-5500 K gains; `COLOR_CORRECTION_TRANSFORM` = **identity** |
| Focus | `LENS_FOCUS_DISTANCE` = 1000 / targetDistanceMm = **10.0 diopters**, clamped to `LENS_INFO_MINIMUM_FOCUS_DISTANCE`. If the clamp binds, raise `targetDistanceMm` (pre-check 3). |
| Torch | `FLASH_MODE = TORCH` (honoured because AE is OFF) |
| ISP | `TONEMAP_MODE = PRESET_CURVE` / `TONEMAP_PRESET_CURVE_SRGB`; `NOISE_REDUCTION_MODE = MINIMAL` (or OFF); `EDGE_MODE = OFF`; `LENS_OPTICAL_STABILIZATION_MODE = OFF`; `CONTROL_VIDEO_STABILIZATION_MODE = OFF`; `CONTROL_ZOOM_RATIO = 1.0`; full `SCALER_CROP_REGION` |
| Capability gates | Require `MANUAL_SENSOR` and `MANUAL_POST_PROCESSING`. Otherwise **block**, never silently degrade. |
| Read-back | Verify `SENSOR_EXPOSURE_TIME`, `SENSOR_SENSITIVITY`, `COLOR_CORRECTION_GAINS`, `LENS_FOCUS_DISTANCE` on three consecutive results |
| Lens choice | A fixed physical camera id with `MANUAL_SENSOR` and the smallest `MINIMUM_FOCUS_DISTANCE`. Never a logical multi-camera that can switch lenses. |

**iOS (AVFoundation)**:

| Group | Setting |
|---|---|
| Exposure | `setExposureModeCustom(duration:iso:)`; duration 1/100 s (50 Hz) or 1/120 s; ISO clamped to `activeFormat.minISO…maxISO` |
| White balance | `deviceWhiteBalanceGains(for: {5500 K, tint 0})`, each gain clamped to [1, `maxWhiteBalanceGain`], then `setWhiteBalanceModeLocked(with:)` |
| Focus | `setFocusModeLocked(lensPosition:)`. Lens position is non-linear, so use the **per-model calibrated** value from the profile, with `minimumFocusDistance` as a floor. |
| Torch | `setTorchModeOn(level: 1.0)` |
| Pipeline | Frames from `AVCaptureVideoDataOutput` (not the Photo output), HDR off, stabilisation off, `isSubjectAreaChangeMonitoringEnabled = false`, `isSmoothAutoFocusEnabled = false`; highest format ≤ ~12 MP |
| Read-back | KVO on `exposureDuration`, `ISO`, `deviceWhiteBalanceGains`, `lensPosition`, `torchLevel` |

**Calibration of device profiles (offline tool, not an app feature):**
1. *Focus sweep:* step lens position or diopters across the patch and pick the maximum fiducial sharpness (§D.2).
2. *Neutral gains:* gray-card sweep at 5500 K.
3. Record intrinsics for each `stillSize`.

> [!CAUTION]
> Many phone main cameras cannot focus as close as 10 cm. Where `minFocusDistance` exceeds the target, either move to the ultra-wide/macro lens (device-dependent) or set a longer working distance. That shrinks the patch in the frame. The Bragg and resolution budgets must be re-checked.

### D.2 On-device frame validation (before accepting any frame)

Run on a downscaled luma copy in a Dart isolate. These rules are the on-device twin of the engine's `measure_sharpness` and QC gates. **Thresholds are initial values copied from the Python engine and MUST be re-fitted per device profile.**

**1. Blur** — normalised Laplacian variance on the fiducials (matches the engine):
- For each marker: crop the marker's bounding square expanded by 10 % per side, resize to **72×72** (`INTER_AREA`), 3×3 Laplacian.
- `s_marker = var(Lap) / (P98 − P2)²`, using P2/P98 of the same crop.
- `sharpness = median over detected markers`.
- **Reject if `sharpness < 0.06`.** "Good" at ≥ 0.20. The engine's synthetic sharp frames score ≈ 0.39.

**2. Exposure / blowout of the reference white:**
- White-swatch region: fraction of pixels with any channel ≥ 251/255 must be **≤ 2 %**.
- Mean encoded white level must be in **[0.55, 0.93]**. Below 0.35 is a hard fail (the engine's gate).
- White level must stay within **±15 %** of the baseline frame's white level (illumination drift).

**3. Mylar specular blowout on the TLC patches** (per patch ROI via `roiQuadsPx`):
- Specular pixel = `min(R,G,B) ≥ 251` **or** (`V > 0.95` and `S < 0.15`), dilated by 6 px.
- Upstream/downstream: fraction **> 10 % → reject frame**; > 0 % → raise `GLARE`.
- If glare persists at an ALIGNED pose, the fix is hardware (diffuser shroud or cross-polarisation), not more tilt. Tilt is bounded by ±5° because of the Bragg artefact.

**4. Under-exposure:** mean luma inside any patch ROI < 0.08 is not a blur fail. A dark TLC means "out of band", so only the *white references* are exposure-checked on the client.

**5. Registration:** all 4 markers; reprojection RMS of all 16 corners ≤ 3 px (engine gate); `stabilityScore ≥ 0.8`.

`FrameValidationResult` = `{passed, sharpness, whiteLevel, whiteClipFrac, specularFracByRoi, markersDetected, regRmsPx, failures[]}`.

---

## E. Sequential Code-Generation Prompts for Gemini Flash

### How to use

1. Run **Gate G0** first (below). Without it you are generating a camera layer you cannot trust.
2. For each step, paste the **PREAMBLE** followed by **Prompt n**, in order. Keep one chat per prompt.
3. After each prompt: run `dart run build_runner build -d`, `dart analyze` and the generated tests. Fix before moving on.
4. If Flash replies with `// QUESTION:` comments, resolve them. Do not let it guess.

> **Gate G0 (human, ~2 days):** two reference phones (one Android, one iPhone). A throwaway app applies the §D.1 config and logs requested vs applied values, 30 s of frame timestamps, and fiducial sharpness across a focus sweep. Pass = read-back within tolerance on 3 consecutive results, and exposure stable ±2 %. **Spike S1:** confirm `opencv_dart` exposes ArUco (`ArucoDetector`) and `solvePnP`. If it does not, `FiducialTracker` falls back to a native JNI/ObjC++ implementation behind the same interface.

### PREAMBLE (paste before every prompt)

````text
PROJECT: ShuntWhisper client app. Flutter >=3.24, Dart >=3.5, sound null safety. Package name: shuntwhisper_app.
LAYERING: lib/domain (models, repository interfaces, use cases; NO Flutter imports) -> lib/data (dio, drift)
-> lib/features (bloc + presentation) -> lib/presentation (shared UI). Presentation never calls dio or the camera plugin directly.
STYLE: very_good_analysis lints. No `dynamic`. No `print`. Immutable models via freezed + json_serializable
(fieldRename: snake). Provide .dart sources with annotations only; I will run build_runner. SI units; every field name carries a unit suffix
(Ns, Mm, C, Deg, Ul, Pct, Px). Time on the wire = ISO-8601 UTC. Elapsed time = monotonic clock only (never DateTime.now()).
ERRORS: no thrown exceptions across layer boundaries. Return Result<T> = sealed (Ok<T>, Err(Failure)). Failure is a sealed class with a stable string `code`.
ENUMS: every wire enum has an `unknown` member via @JsonKey(unknownEnumValue: ...). Deserialization must never throw on unknown enum values or extra fields.
FORBIDDEN: placeholder bodies (// TODO implement), invented fields, extra dependencies beyond the list given in the prompt,
business logic inside widgets, global mutable state.
AMBIGUITY RULE: if a requirement is ambiguous, pick the documented default, add a `// QUESTION: ...` comment at that spot, and continue. Do not stop.
OUTPUT FORMAT: for each file output a line `// FILE: <relative path>` followed by ONE fenced code block with the full file. No prose between files.
After the files, output `// TESTS:` and the test files in the same format. Finish with a checklist `// ACCEPTANCE:` mapping each acceptance item to the test that proves it.
DISCLAIMER TEXT (use verbatim wherever a clinical result is shown): "Research prototype. Not a validated medical device. Does not replace clinical evaluation."
````

---

### PROMPT 1 — Data Models & API Service

````text
TASK: Generate all domain data models, JSON serialization, and the HTTP API client for the ShuntWhisper backend.

PACKAGES ALLOWED: freezed(+annotation), json_serializable(+annotation), dio, equatable, uuid, crypto, http_parser, mocktail (tests), test.

FILES TO PRODUCE
lib/core/errors/failure.dart                  sealed Failure + codes below; Result<T>
lib/domain/models/enums.dart
lib/domain/models/{patch_layout,remote_config,device_profile,camera_hardware_config,camera_capabilities,applied_camera_state,
  fiducial_alignment_state,frame_validation_result,capture_payload,captured_image_meta,ambient_metadata,dosing_record,
  diagnostic_response,roi_visual,session_checkpoint}.dart
lib/domain/repositories/{diagnostic_repository,config_repository}.dart
lib/data/api/{shuntwhisper_api,dio_shuntwhisper_api,retry_interceptor,auth_interceptor,problem_details,multipart_builder}.dart
test/models/json_roundtrip_test.dart, test/data/{api_retry_test,multipart_test}.dart, test/models/fixtures/*.json

ENUMS (+ unknown)
 AlignmentStatus {aligned, misaligned, unstable, notDetected}
 AlignmentViolation {tooFar, tooClose, pitch, yaw, roll, offCenter, lateralOffset, nearFrameEdge, blur, glare, underExposed}
 Classification {patentHigh, patentMarginal, occluded, inconclusive} <-> wire "PATENT_HIGH","PATENT_MARGINAL","OCCLUDED","INCONCLUSIVE"
 InconclusiveReason {insufficientHydration, outOfRangeWarm, outOfRangeCold, qcMotionBlur, qcRegistration, qcExposure, qcColorFit,
   qcIllumination, specularRoi, reverseGradient, lowSnr, sinkUnverifiable, other} (wire = UPPER_SNAKE; keep raw string in a sibling field)
 TorchMode {off,on}  TorchPolicy {alwaysOn, windowed}  DoseDetection {manualTap, autoFoam}  AmbientSource {manual, sensor, ble}
 IntrinsicsSource {cameraCharacteristics, profile, estimated}  RoiVisualKind {crop, overlay, normalized, specMask}

MODELS (field: type; `?` = nullable). All are freezed with toJson/fromJson.
 SizeDto{widthPx:int, heightPx:int}  PointDto{x:double, y:double}  Measured{value:double, sigma:double, ci95Lo:double?, ci95Hi:double?}
 PatchLayout{upstreamCenterMm:PointDto, downstreamCenterMm:PointDto, lateralRefCenterMm:PointDto, apertureCenterMm:PointDto,
   apertureSizeMm:SizeMm{w,h}, roiSizeMm:SizeMm, fiducials:List<FiducialSpec{id:int, centerMm:PointDto, sideMm:double}>}
 CameraHardwareConfig{cameraId:String, iso:int, exposureTimeNs:int, frameDurationNs:int, focus:FocusSpec{targetDistanceMm:double,
   androidDiopters:double?, iosLensPosition:double?}, torch:TorchSpec{mode:TorchMode, level:double, policy:TorchPolicy, preRollMs:int},
   whiteBalance:WhiteBalanceSpec{gains:WbGains{r,gEven,gOdd,b}?, kelvin:int, tint:int}, mainsHz:int,
   isp:IspSpec{tonemap:String, noiseReduction:String, edgeMode:String, ois:String, videoStabilization:String, hdr:String, zoomRatio:double},
   stillSize:SizeDto, previewAnalysisSize:SizeDto}
 ParamDeviation{param:String, requested:double, applied:double, withinTolerance:bool}
 AppliedCameraState{iso:int, exposureTimeNs:int, whiteBalanceGains:WbGains?, focusDistanceDiopters:double?, lensPosition:double?,
   torchLevel:double, awbLocked:bool, aeLocked:bool, sensorTimestampNs:int, verified:bool, deviations:List<ParamDeviation>}
 CameraCapabilities{hasManualSensor:bool, isoMin:int, isoMax:int, exposureMinNs:int, exposureMaxNs:int, minFocusDistanceMm:double?,
   hasTorch:bool, supportsWbGains:bool, supportedStillSizes:List<SizeDto>, hardwareLevel:String, physicalCameraIds:List<String>}
 FiducialAlignmentState{frameSeq:int, timestampNs:int, analysisSize:SizeDto, markersDetected:int, markerCentersPx:List<PointDto?>(len 4),
   canonToImageH:List<double>?(len 9), roiQuadsPx:Map<String,List<PointDto>>, pitchDeg,yawDeg,rollDeg,distanceMm:double?,
   lateralOffsetMm:PointDto?, centerOffsetFrac:double?, sharpness:double?, stabilityScore:double, consecutiveAlignedFrames:int,
   alignedForMs:int, status:AlignmentStatus, violations:List<AlignmentViolation>}
 FrameValidationResult{passed:bool, sharpness:double, whiteLevel:double, whiteClipFrac:double, specularFracByRoi:Map<String,double>,
   markersDetected:int, regRmsPx:double?, failures:List<String>}
 AmbientMetadata{temperatureC:double, relativeHumidityPct:double, source:AmbientSource, measuredAtUtc:DateTime}
 DosingRecord{volumeUl:double, tZeroMonotonicNs:int, tZeroUtc:DateTime, detection:DoseDetection, outOfSpec:bool}
 Intrinsics{fx,fy,cx,cy:double, imageW:int, imageH:int, source:IntrinsicsSource}
 CapturedImageMeta{part:String('baseline'|'t23'|'t120'), tNominalS:double, tActualS:double, mime:String, encoding:String, jpegQuality:int?,
   widthPx:int, heightPx:int, sizeBytes:int, sha256:String, appliedCamera:AppliedCameraState, alignmentAtCapture:FiducialAlignmentState,
   validation:FrameValidationResult, intrinsics:Intrinsics, burstIndex:int, burstSize:int}
 CapturePayload{sessionId:String(uuid v4), schemaVersion:int=1, createdAtUtc:DateTime, subjectRef:String?,
   app:{version,build,platform,osVersion}, device:{model,cameraId,hardwareLevel,profileVersion}, calibrationId:String,
   patchLotId:String?, patchSerial:String?, ambient:AmbientMetadata, dosing:DosingRecord, images:List<CapturedImageMeta>(1..3),
   flags:List<String>, policySnapshot:Map<String,Object?>}
   + local-only (NOT serialized): Map<String,String> filePathsByPart  (keys baseline|t23|t120)
 RoiVisual{name:String, kind:RoiVisualKind, url:String, expiresAtUtc:DateTime, widthPx:int, heightPx:int}
 FlowEstimate{point:double?, lo:double, hi:double, method:String, validated:bool}
 TimepointResult{tNominalS:double, classification:Classification, deltaTUdC:Measured?, confidencePct:double, qaPassed:bool, qaFailures:List<String>}
 DiagnosticResponse{sessionId, engineVersion, calibrationIdUsed, processedAtUtc:DateTime, classification:Classification,
   inconclusiveReason:InconclusiveReason?, inconclusiveReasonRaw:String?, deltaTUdC:Measured?, deltaTEvapC:EvapMeasured{value,sigma,isLowerBound,definition}?,
   estimatedFlowMlMin:FlowEstimate?, confidencePct:double, confidenceFactors:Map<String,double>, snrResolutionDb:double?,
   temperatures:{upstreamC:Measured?, downstreamC:Measured?, lateralRefC:Measured?}, timepoints:List<TimepointResult>, flags:List<String>,
   roiVisuals:List<RoiVisual>, retestAdvice:{code:String, requiresNewPatch:bool}?}
 RemoteConfig{sessionPolicy:Map<String,Object?>, alignmentThresholds:Map<String,double>, validatorThresholds:Map<String,double>,
   patchLayout:PatchLayout, featureFlags:Map<String,bool>, deviceProfileVersion:int}
 DeviceProfile{platform,model,cameraId:String, previewAnalysisSize,stillSize:SizeDto, targetDistanceMm:double, androidFocusDiopters:double?,
   iosLensPosition:double?, neutralWbGains:WbGains?, intrinsicsByStill:List<Intrinsics>, version:int}
 SessionCheckpoint{sessionId, stateName:String, tZeroMonotonicNs:int?, tZeroUtc:DateTime?, baselinePath:String?, t23Path:String?, t120Path:String?,
   flags:List<String>, updatedAtUtc:DateTime}

API INTERFACE (abstract class ShuntWhisperApi; every method returns Future<Result<T>>)
 getConfig({String? etag}) -> RemoteConfig|NotModified    getDeviceProfile(platform, model) -> DeviceProfile (404 => Err code DEVICE_PROFILE_NOT_FOUND)
 validateCalibration(id) -> {valid, expiresAtUtc}
 submitSession(CapturePayload, {onSendProgress}) -> SubmitAck{sessionId, statusUrl}   POST /v1/sessions multipart/form-data
     part "metadata" = JSON (application/json); parts "baseline","t23","t120" = file bytes with the CapturedImageMeta.mime; header Idempotency-Key = sessionId
 pollSession(sessionId) -> sealed SessionPoll {Processing(status), Done(DiagnosticResponse), Failed(code)}  (HTTP 202 => Processing; 200 with {"status":"failed"} => Failed)
 downloadRoi(url) -> Uint8List         deleteSession(sessionId)
DioShuntwhisperApi: baseUrl injected; connectTimeout 10s; receiveTimeout 30s; sendTimeout 120s.
AuthInterceptor: attaches "Authorization: Bearer <token>" from an injected `Future<String?> Function()`; on 401 calls injected `refresh()` once then replays.
RetryInterceptor: retry ONLY on connection errors/timeouts, 5xx, 429. Backoff 2,4,8,16,32 s with +-20% jitter, max 5 attempts, honor Retry-After.
  Never retry 4xx except 429. submitSession retries MUST reuse the same Idempotency-Key and rebuild the multipart body from file paths (streams are single-use).
Error mapping (Failure.code): timeouts=>NETWORK_TIMEOUT, no connection=>NETWORK_OFFLINE, 400/422 body code INVALID_IMAGE=>UPLOAD_INVALID_IMAGE,
  413=>PAYLOAD_TOO_LARGE, 415=>UNSUPPORTED_MEDIA, 401=>UNAUTHENTICATED, 429=>RATE_LIMITED, 5xx=>SERVER_ERROR, calibration codes=>CALIBRATION_UNKNOWN|CALIBRATION_EXPIRED,
  anything else=>UNKNOWN. Parse RFC 7807 problem+json into ProblemDetails{type,title,status,detail,code,instance}; if the body is not JSON keep status only.
Use dio's Clock/transformer hooks or injected `Future<void> Function(Duration)` sleeper so retry tests run instantly.

TESTS (must be generated)
 - JSON round-trip for EVERY model using fixture files; unknown enum value and unknown extra field must parse without throwing.
 - DiagnosticResponse fixture for each of the four classifications + an INCONCLUSIVE with reason INSUFFICIENT_HYDRATION.
 - Retry: 503,503,200 => success after 2 retries; 400 => exactly 1 attempt; 429 with Retry-After honored; Idempotency-Key identical across attempts.
 - Multipart: metadata part is valid JSON; part names are exactly baseline/t23/t120 for present images only; missing t23 => no t23 part.
 - 202 poll => Processing; 200 failed => Failed.

ACCEPTANCE: all models compile after build_runner; all tests green; no model has a nullable field not listed as nullable above.
````

---

### PROMPT 2 — Manual Camera Service (send as 2A, 2B, 2C)

````text
[PROMPT 2A — Pigeon contract, Dart service, validators]
TASK: Build the `shuntwhisper_camera` plugin's Dart side and Pigeon contract. Native code comes in 2B (Android) and 2C (iOS).
PACKAGES ALLOWED: pigeon (dev), opencv_dart (ONLY inside fiducial_tracker_opencv.dart, behind the FiducialTracker interface), meta, plus the domain models from Prompt 1 (import them as-is).
MODELS AVAILABLE (do not redefine): CameraHardwareConfig, AppliedCameraState, CameraCapabilities, FiducialAlignmentState, FrameValidationResult,
  PatchLayout, Result<T>, Failure.

FILES: packages/shuntwhisper_camera/pigeons/camera_api.dart
 lib/src/{camera_service.dart (abstract), camera_service_impl.dart, readback_verifier.dart, frame_validator.dart,
   fiducial_tracker.dart (abstract), fiducial_tracker_opencv.dart, pose_math.dart}
 test/{readback_verifier_test.dart, frame_validator_test.dart, pose_math_test.dart, camera_service_impl_test.dart (mock host api)}

PIGEON CONTRACT
 @HostApi CameraHostApi:
   CapabilitiesDto probeCapabilities(String? cameraId)
   int open(String cameraId)                        // returns Flutter texture id for the preview
   AppliedCameraStateDto applyConfig(CameraHardwareConfigDto config)   // MUST read back before returning
   void startPreviewAnalysis(int width, int height, int fps)           // luma Y plane stream
   void stopPreviewAnalysis()
   void setTorch(double level)                      // 0 = off
   List<StillHandleDto> captureBurst(int count, int minFps, int windowId)  // handle{id, sensorTimestampNs, widthPx, heightPx}; frames stay native
   Uint8List getLumaDownscaled(int stillId, int width, int height)     // for Dart-side validation of a captured still
   String encodePng(int stillId, String outPath)                       // returns sha256 of the written file
   void releaseStills(List<int> ids)
   void close()
 @FlutterApi CameraFlutterApi:
   void onPreviewFrame(PreviewFrameDto f)  // {seq, timestampNs, width, height, luma: Uint8List, exposureTimeNs, iso}
   void onCameraEvent(CameraEventDto e)    // {type: error|disconnected|thermalSevere|configDrift, message}
 DTOs mirror the Dart domain models field-for-field (same names, same units).

camera_service.dart (abstract CameraService; all methods return Future<Result<...>>):
   probe(), open(), applyAndVerify(CameraHardwareConfig), alignmentStream (Stream<FiducialAlignmentState>), setTorch(level),
   captureBurst({count, minFps, windowId}) -> List<StillCapture{id, sensorTimestampNs, validation: FrameValidationResult}>, encodeToPng(stillId, path), close(), events (Stream<CameraEvent>)
READBACK VERIFIER (pure function): verify(requested: CameraHardwareConfig, applied: AppliedCameraState) -> List<ParamDeviation>.
  Tolerances: iso exact OR nearest supported (withinTolerance=true but add flag `ISO_CLAMPED`); exposure +-2%; gains +-1% each channel; focus +-5%; torch +-0.05.
  applyAndVerify: call host applyConfig up to 3 times, 250 ms apart; success only if verified on the LAST call; else Err(CAMERA_CONFIG_UNVERIFIED) carrying the deviations.
  ALSO: while previewing, onPreviewFrame.exposureTimeNs/iso differing from config by > tolerance for 3 consecutive frames => emit CameraEvent(configDrift).
FRAME VALIDATOR (pure, runs in an isolate via Isolate.run; input = Uint8List luma + width + height + FiducialAlignmentState for geometry)
  Implement exactly:
   1) sharpness: per detected marker, crop its bounding square expanded 10% per side, resize to 72x72 (area), 3x3 Laplacian (kernel [0 1 0;1 -4 1;0 1 0]),
      s = var(lap)/max((P98-P2),1)^2 using percentiles of the same crop; sharpness = MEDIAN over detected markers. Reject if < validatorThresholds.minSharpness (default 0.06).
   2) white reference: region = white-swatch quad from roiQuadsPx['white_swatch'] (if absent skip with failure `NO_WHITE_REF`): clipFrac = share of pixels >= 251 must be <= 0.02;
      whiteLevel = mean/255 must be within [0.55, 0.93]; hard fail < 0.35.
   3) specular per patch ROI (upstream, downstream, lateral_ref): pixel is specular if luma >= 251; dilate 6px; fraction > 0.10 for upstream or downstream => reject (failure `GLARE_UPSTREAM`/`GLARE_DOWNSTREAM`).
   4) registration: markersDetected must be 4.
  FrameValidationResult.failures uses these exact codes: BLUR, WHITE_CLIPPED, WHITE_LOW, WHITE_OUT_OF_RANGE, GLARE_UPSTREAM, GLARE_DOWNSTREAM, MARKERS_MISSING, NO_WHITE_REF.
POSE MATH (pure Dart, unit-tested): from 4 marker centers (px) + intrinsics + PatchLayout fiducials => pitchDeg, yawDeg, rollDeg, distanceMm, lateralOffsetMm.
  Use cv solvePnP with ITERATIVE (NOT IPPE: it is badly conditioned near fronto-parallel views, 0.01 px noise already yields ~0.4 deg tilt error).
  lateralOffsetMm = camera center expressed in the patch frame: C = -R^T t, report (C.x, C.y).
FiducialTracker interface: Future<FiducialAlignmentState> analyze(PreviewFrameDto, PatchLayout, AlignmentThresholds, AlignmentHistory). Implementation detects ArUco DICT_4X4_50 ids 0-3,
  uses cornerSubPix, marker center = intersection of the two diagonals, computes homography patch(mm)->px (getPerspectiveTransform on the 4 centers) for HUD quads,
  stabilityScore = 1 - clamp(std of the 4 centers (px) over the last 8 frames / 3.0, 0, 1). status rules: <4 markers => notDetected; stabilityScore<0.8 => unstable; any violation => misaligned; else aligned.
  Violations use AlignmentThresholds defaults: distance target +-10%, pitch/yaw <=5deg, roll <=8deg, centerOffsetFrac<=0.05, |lateralOffset|<=2mm, frame margin>=4%.

TESTS: readback tolerance boundaries (just inside/just outside each); applyAndVerify retry/fail path with mock host; frame validator on synthetic luma images
 (sharp checkerboard => pass, gaussian-blurred => BLUR, saturated white patch => WHITE_CLIPPED, large 255 blob over upstream ROI => GLARE_UPSTREAM);
 pose_math round trip: project known pose with a pinhole model, add 0.05 px noise, recover tilt < 0.2 deg and lateral < 0.5 mm.
ACCEPTANCE: Pigeon file generates without errors; no dart:ui or Flutter widgets imported in pure files; every validator code above is reachable by a test.
````

````text
[PROMPT 2B — Android (Kotlin, Camera2)]
TASK: Implement the Android side of `shuntwhisper_camera` against the Pigeon-generated `CameraHostApi`/`CameraFlutterApi` from 2A. Kotlin only. No CameraX.
FILES: android/src/main/kotlin/<pkg>/{ShuntCameraPlugin.kt, Camera2Session.kt, ManualRequestBuilder.kt, CapabilityProbe.kt, ReadbackVerifier.kt, TorchGovernor.kt, StillRing.kt, PngEncoder.kt, PreviewLumaStreamer.kt}
 android/src/test/... JVM unit tests for ManualRequestBuilder and ReadbackVerifier (use mocked CameraCharacteristics wrappers behind interfaces).

HARD RULES (every line is mandatory; implement as an explicit key list in ManualRequestBuilder):
 template TEMPLATE_MANUAL. CONTROL_MODE=OFF, CONTROL_AE_MODE=OFF, CONTROL_AWB_MODE=OFF, CONTROL_AF_MODE=OFF, CONTROL_AE_LOCK=true, CONTROL_AWB_LOCK=true.
 SENSOR_SENSITIVITY = clamp(config.iso, SENSOR_INFO_SENSITIVITY_RANGE). SENSOR_EXPOSURE_TIME = clamp(config.exposureTimeNs, SENSOR_INFO_EXPOSURE_TIME_RANGE).
 SENSOR_FRAME_DURATION = max(config.frameDurationNs, exposure).
 COLOR_CORRECTION_MODE=TRANSFORM_MATRIX; COLOR_CORRECTION_GAINS = RggbChannelVector(config gains); COLOR_CORRECTION_TRANSFORM = identity ColorSpaceTransform (rationals 1/1,0/1,... row-major).
 LENS_FOCUS_DISTANCE = min(config.focus.androidDiopters, LENS_INFO_MINIMUM_FOCUS_DISTANCE).
 FLASH_MODE = TORCH when torch level>0 else OFF. TONEMAP_MODE=PRESET_CURVE, TONEMAP_PRESET_CURVE=SRGB. NOISE_REDUCTION_MODE=MINIMAL (OFF if config says off).
 EDGE_MODE=OFF. LENS_OPTICAL_STABILIZATION_MODE=OFF. CONTROL_VIDEO_STABILIZATION_MODE=OFF. CONTROL_ZOOM_RATIO=1.0. SCALER_CROP_REGION=full active array.
CAPABILITY GATES (CapabilityProbe): require REQUEST_AVAILABLE_CAPABILITIES contains MANUAL_SENSOR and MANUAL_POST_PROCESSING, FLASH_INFO_AVAILABLE=true.
 Choose the PHYSICAL camera id: among back-facing cameras with MANUAL_SENSOR, the one with the largest LENS_INFO_MINIMUM_FOCUS_DISTANCE value (closest focus). Never a logical multi-camera that can switch lenses.
 If a gate fails return a typed error code (MANUAL_SENSOR_UNSUPPORTED etc.). NEVER silently fall back to auto.
READBACK: ReadbackVerifier builds AppliedCameraState from TotalCaptureResult (SENSOR_EXPOSURE_TIME, SENSOR_SENSITIVITY, COLOR_CORRECTION_GAINS, LENS_FOCUS_DISTANCE, FLASH_STATE/torch level, CONTROL_AWB_LOCK/AE_LOCK, SENSOR_TIMESTAMP).
 applyConfig returns only after 3 consecutive results have been collected and compared; it returns the LAST one.
STREAMS: ImageReader #1 YUV_420_888 at previewAnalysisSize, forward ONLY the Y plane (row-stride-aware copy into a tight Uint8List) at <= 10 fps via PreviewLumaStreamer (drop frames if the Flutter side is busy; never queue).
 ImageReader #2 YUV_420_888 at stillSize with maxImages=6 used by StillRing (ring of 6; captureBurst fills it from the repeating request at >= minFps and returns handles whose sensorTimestampNs = SENSOR_TIMESTAMP).
 Preview texture: SurfaceTextureEntry from the plugin registry; also add it as a target.
TORCH: TorchGovernor applies level via FLASH_MODE in the repeating request; refuses levels >0 when thermal status >= THERMAL_STATUS_SEVERE and emits onCameraEvent(thermalSevere).
ENCODE: PngEncoder converts a still (YUV->sRGB using the standard BT.601 full-range matrix as specified by the camera's YUV output) to PNG on a background thread, writes outPath, returns SHA-256 hex.
 NEVER use Bitmap.compress JPEG for science frames.
LIFECYCLE: close() stops repeating requests, turns torch off, closes session/device/readers. Handle CameraDevice.StateCallback.onDisconnected/onError => onCameraEvent(disconnected/error) and release everything.
 All Camera2 callbacks on a dedicated HandlerThread; Pigeon results delivered on the platform thread.
ERROR BOUNDARY: no uncaught exceptions out of the plugin; map CameraAccessException/IllegalStateException/SecurityException to FlutterError with a stable code.
TESTS: ManualRequestBuilder emits EVERY key listed above with the expected values (assert on a recording fake builder); clamping behavior at range edges; gate failures; verifier tolerance boundaries.
ACCEPTANCE: a checklist mapping each HARD RULE line to the unit test asserting it.
````

````text
[PROMPT 2C — iOS (Swift, AVFoundation)]
TASK: Implement the iOS side of `shuntwhisper_camera` against the Pigeon-generated Swift protocols from 2A. Swift only (no Objective-C unless Pigeon requires).
FILES: ios/Classes/{ShuntCameraPlugin.swift, CaptureSession.swift, ManualConfigurator.swift, CapabilityProbe.swift, ReadbackVerifier.swift, TorchGovernor.swift, StillRing.swift, PngEncoder.swift, PreviewLumaStreamer.swift}
 + XCTest unit tests for ManualConfigurator clamping and ReadbackVerifier.
HARD RULES:
 Device: AVCaptureDevice chosen by cameraId from the profile (builtInWideAngleCamera or builtInUltraWideCamera). Use AVCaptureVideoDataOutput for both preview-analysis and stills (NOT AVCapturePhotoOutput),
 pixel format kCVPixelFormatType_420YpCbCr8BiPlanarFullRange. Pick the format with the largest resolution <= ~12 MP that supports >= 30 fps; set activeFormat before locking exposure.
 lockForConfiguration then, in this order: setFocusModeLocked(lensPosition: profile.iosLensPosition) ; setExposureModeCustom(duration: clamp to activeFormat min/maxExposureDuration, iso: clamp to minISO...maxISO) ;
 white balance: gains = deviceWhiteBalanceGains(for: WhiteBalanceTemperatureAndTintValues(temperature: 5500, tint: 0)) unless the profile supplies neutralWbGains; clamp each channel to [1, maxWhiteBalanceGain]; setWhiteBalanceModeLocked(with:).
 isSubjectAreaChangeMonitoringEnabled=false; isSmoothAutoFocusEnabled=false if supported; videoStabilizationMode off on the connection; HDR: set automaticallyAdjustsVideoHDREnabled=false and isVideoHDREnabled=false.
 Torch: setTorchModeOn(level:) with level clamped to (0, 1]; level 0 => torchMode off. TorchGovernor refuses on ProcessInfo.thermalState >= .serious and emits thermalSevere.
 Capability gates: isExposureModeSupported(.custom), isLockingFocusWithCustomLensPositionSupported, isLockingWhiteBalanceWithCustomDeviceGainsSupported, hasTorch. Fail with typed codes; NEVER fall back to auto.
 minimumFocusDistance (iOS 15+, millimetres; -1 => unknown) must be reported in CameraCapabilities.minFocusDistanceMm.
READBACK: KVO (or polling at 30 Hz on the session queue) of exposureDuration, iso, deviceWhiteBalanceGains, lensPosition, torchLevel. applyConfig completes only after 3 consecutive observations are stable and compared; return the last as AppliedCameraState.
 sensorTimestampNs from CMSampleBuffer presentation timestamp converted to nanoseconds on the host clock (mach_continuous_time domain).
STREAMS: PreviewLumaStreamer copies ONLY the Y plane (honor bytesPerRow) of a downscaled copy at previewAnalysisSize, <= 10 fps, dropping if busy. StillRing keeps the last 6 CMSampleBuffers at full res (retain/release carefully; hard cap 6).
 Preview texture: FlutterTexture backed by CVPixelBuffer from the same output.
ENCODE: PngEncoder converts YCbCr full-range -> sRGB with the BT.601 matrix, writes PNG via CGImageDestination, returns SHA-256 hex (CryptoKit). Never JPEG.
LIFECYCLE: close() turns torch off, stops running, removes inputs/outputs. Observe AVCaptureSession.runtimeErrorNotification/wasInterrupted => onCameraEvent. Handle app backgrounding by stopping the session; reopening is driven by Dart.
ERROR BOUNDARY: map all NSError/AVError to PigeonError with stable codes; no force-unwraps in production paths.
TESTS: clamping logic (pure functions extracted from ManualConfigurator), gain clamping, verifier tolerance boundaries.
ACCEPTANCE: checklist mapping each HARD RULE line to a test or to an explicit "device-only: verified in Gate G0" note.
````

---

### PROMPT 3 — HUD & Viewfinder UI

````text
TASK: Build the live viewfinder with an alignment HUD for ShuntWhisper. Rendering only; no business logic.
PACKAGES ALLOWED: flutter_bloc, equatable, golden_toolkit (tests). No other deps.
MODELS AVAILABLE (do not redefine): FiducialAlignmentState, AlignmentStatus, AlignmentViolation, PatchLayout, SizeDto, PointDto.
INPUTS: `Stream<FiducialAlignmentState>` (about 10 Hz), `int previewTextureId`, `PatchLayout`, `Size analysisSize` (taken from each state), device orientation locked to portrait (the camera sensor may be rotated: take `int sensorRotationDeg` (0/90/180/270) as an explicit parameter).

FILES
 lib/presentation/hud/{coordinate_mapper.dart, alignment_hud.dart, reticle_painter.dart, patch_box_painter.dart, stability_indicator.dart, guidance_banner.dart}
 lib/features/alignment/bloc/alignment_cubit.dart
 lib/features/alignment/presentation/{viewfinder_view.dart, viewfinder_page.dart}
 test/presentation/{coordinate_mapper_test.dart, hud_golden_test.dart, alignment_cubit_test.dart}

COORDINATE MAPPER (pure, unit-tested): maps analysis-image px -> widget px for BoxFit.cover, with sensorRotationDeg and optional mirror=false.
 Provide `Offset map(PointDto p)` and `Rect mapRect(...)`. Tests: identity, 90-degree rotation, aspect mismatch crop on both axes, round trip within 0.5 px.
HUD LAYERS (back to front, wrapped in RepaintBoundary, painters must not allocate per paint: cache Paint/Path objects, repaint only via `Listenable`):
 1. Texture(textureId) fills the box.
 2. TARGET FRAME (static): the ideal position of the 4 fiducial centers for the nominal pose, drawn as 4 L-shaped corner brackets (dashed white, 60% opacity).
    Ideal positions are provided by the cubit as `List<PointDto> targetCentersPx` (computed from layout + nominal distance + intrinsics; the cubit just exposes what it receives from config).
 3. FIDUCIALS: for each of the 4 ids draw a crosshair at markerCentersPx[i]; detected = solid ring + id label; missing = dashed red ring at the target position with a "?" label.
 4. PATCH BOXES: from roiQuadsPx draw THREE patch quads (upstream, downstream, lateral_ref) as polygons with 2 px stroke and 12% fill, plus the aperture as a dashed outline.
    Labels: "UP", "DOWN", "REF", "FOAM" (7.6 mm). Add a small flow arrow (->) along the upstream->downstream axis so the user can see catheter direction. If roiQuadsPx is empty, draw nothing for this layer.
 5. STABILITY INDICATOR: circular ring around the screen center; sweep = stabilityScore; below it, a progress bar = min(consecutiveAlignedFrames/8, alignedForMs/800) labelled "Hold steady".
 6. POSE READOUT chips (top): distance (mm), tilt (deg, max(|pitch|,|yaw|)), lateral offset (mm), sharpness. Each chip turns amber when its violation is active.
 7. GUIDANCE BANNER (bottom): ONE message chosen by priority: NOT_DETECTED > TOO_FAR/TOO_CLOSE > LATERAL_OFFSET > YAW/PITCH > ROLL > OFF_CENTER > BLUR > GLARE > UNDER_EXPOSED > NEAR_FRAME_EDGE > UNSTABLE > "Hold steady".
    Message text and arrows come from ARB keys (provide app_en.arb entries): e.g. alignMoveCloser, alignMoveFarther, alignShiftLeft/Right/Up/Down (derived from lateralOffsetMm sign), alignTiltDown/Up, alignRotateLeft/Right,
    alignRollClockwise/CounterClockwise, alignCenter, alignBlur, alignGlare ("Glare detected: use the diffuser shroud"), alignHold.
COLOR SEMANTICS + ACCESSIBILITY: ALIGNED = green, UNSTABLE = amber, MISALIGNED = red, NOT_DETECTED = grey. NEVER color alone: every status also has an icon + text label and a Semantics label.
 Haptic: single light impact when status first becomes ALIGNED; selection click each time a violation appears. Rate limit haptics to 1 per 500 ms.
STATE: AlignmentCubit subscribes to the stream, keeps only the latest state (latest-wins; drop intermediate), exposes `AlignmentViewState{FiducialAlignmentState? latest, DateTime? lastFrameAt, bool stale}`.
 `stale` = no frame for > 500 ms (use an injectable Clock). When stale, dim the HUD and show "Camera paused".
PERFORMANCE: HUD repaint <= 10 Hz; no setState in painters; no per-frame widget tree rebuilds (use CustomPaint with a repaint Listenable).
EDGE CASES: markerCentersPx contains nulls; homography null; analysisSize changes mid-stream (rebuild mapper); zero-size layout.
TESTS: goldens for ALIGNED, MISALIGNED (yaw violation), UNSTABLE, NOT_DETECTED (2 markers), stale state; mapper tests; cubit latest-wins + stale timing with a fake clock.
ACCEPTANCE: goldens render all 7 layers where data exists; banner priority test covers every pair of adjacent priorities; no painter allocates in paint() (add a lint-style test that Paint objects are fields).
````

---

### PROMPT 4 — Workflow State Machine & Timer Coordinator

````text
TASK: Implement the session FSM as a PURE reducer plus an effect runner and a Bloc. Do not write UI.
PACKAGES ALLOWED: flutter_bloc, equatable, bloc_test, mocktail, uuid, meta.
MODELS/SERVICES AVAILABLE (import, do not redefine): SessionPolicy (create it as a freezed class in lib/core/config/session_policy.dart with the fields in POLICY below),
 CapturePayload, CapturedImageMeta, DosingRecord, AmbientMetadata, DiagnosticResponse, Classification, FiducialAlignmentState, AlignmentStatus, FrameValidationResult,
 SessionCheckpoint, Failure, Result<T>, abstract CameraService, abstract DiagnosticRepository, abstract SessionStore, abstract Clock (lib/core/time/monotonic_clock.dart: `int nowNs()`).

FILES
 lib/core/time/{monotonic_clock.dart, fake_clock.dart}
 lib/features/session/bloc/{session_state.dart, session_event.dart, session_effect.dart, session_reducer.dart, effect_runner.dart, session_bloc.dart}
 lib/domain/usecases/{run_preflight.dart, select_best_frame.dart, build_capture_payload.dart, map_failure_to_recovery.dart}
 docs/fsm_table.md   (the table below, verbatim; tests parse it)
 test/fsm/{reducer_table_test.dart, policy_boundary_test.dart, session_bloc_test.dart}

STATES (sealed, equatable): Idle, PreCheck{checks}, BaselineAlign{alignment, retries, enteredAtNs}, BaselineCaptured{baselinePath, enteredAtNs},
 DosingPrompt{enteredAtNs, volumeUl}, CountdownTransient{tZeroNs, phase: waiting|preroll|capturing|selecting, burst}, CountdownSteady{tZeroNs, phase, burst},
 Uploading{phase: encoding|sending|analyzing|offlineQueued, attempt, progress}, ReportReady{response}, ErrorHandling{plan: ErrorRecoveryPlan, preDose: bool}.
 Every state carries `SessionContext{sessionId, flags:Set<String>, baseline, t23, t120 (captured frame refs), dosing?, ambient, calibrationId}`.
EVENTS: StartSession(ambient, calibrationId), ChecksComplete, CheckFailed(code), ConfigVerifyFailed, AlignmentFrame(FiducialAlignmentState), BaselineBurstDone(frames),
 UserRetake, Tick(nowNs), DoseConfirmed(volumeUl), FoamWetDetected(tsNs), BurstDone(windowId, frames), UploadProgress, UploadSucceeded, NetworkError(offline:bool, attempt),
 HttpRejected(status), ResultReady(DiagnosticResponse), AnalysisFailed(code), UserAbort, CameraLost, AppResumed, AppPaused, ThermalSevere, Recover(route), NewSession, CheckpointFound(cp).
EFFECTS (data objects, no I/O in the reducer): ApplyCameraConfig, SetTorch(level), StartAnalysis, StopAnalysis, CaptureBurst(count, minFps, windowId), SaveBaseline, EncodeAndBuildPayload,
 PersistOutbox, UploadPayload, ScheduleBackoff(duration), PollResult, ScheduleOfflineWork, Haptic(kind), ShowNotification, Wakelock(bool), ReleaseCamera, PersistCheckpoint, RunPreflight, StartTicker, StopTicker, Navigate(route).

POLICY (defaults): alignStableFrames 8; alignStableMs 800; alignTimeoutS 120; baselineRetryMax 3; baselineStaleS 180; baselineCapturedHoldMs 1500;
 tTransientS 23; tSteadyS 120; windowHalfWidthS 1.0; burstFrames 8; burstMinFps 4; torchPolicy windowed; torchPreRollMs 2500; preWarnS 3;
 timerExpiredGraceS 30; uploadMaxAttempts 5; offlineAfterFailures 2; analysisPollS 1.0 x15 then 2.0, analysisTimeoutS 90; doseMinUl 60; doseMaxUl 80.

TRANSITION TABLE (implement every row; `t` = (nowNs - tZeroNs)/1e9)
 T01 Idle --StartSession--> PreCheck | effects: Wakelock(true), RunPreflight
 T02 PreCheck --ChecksComplete--> BaselineAlign | ApplyCameraConfig, SetTorch(1.0), StartAnalysis, PersistCheckpoint
 T03 PreCheck --CheckFailed--> ErrorHandling(preDose=true)
 T05 BaselineAlign --ConfigVerifyFailed--> ErrorHandling(CAMERA_CONFIG_UNVERIFIED)
 T06 BaselineAlign --AlignmentFrame--> BaselineAlign (store latest)
 T07 BaselineAlign --AlignmentFrame--> (stay) emit CaptureBurst(3,4,windowId=0) WHEN status==aligned AND consecutiveAlignedFrames>=alignStableFrames AND alignedForMs>=alignStableMs AND no burst in flight
 T07b BaselineAlign --BaselineBurstDone--> BaselineCaptured if select_best_frame finds a passing frame; else retries+1 and stay
 T08 BaselineAlign: retries>=baselineRetryMax => surface violations, reset retries (stay)
 T09 BaselineAlign --Tick--> ErrorHandling(ALIGN_TIMEOUT) when now-enteredAt > alignTimeoutS
 T10/T11 BaselineCaptured --(entry: SaveBaseline)--/--Tick after baselineCapturedHoldMs--> DosingPrompt
 T12 BaselineCaptured --UserRetake--> BaselineAlign (discard baseline)
 T14 DosingPrompt --DoseConfirmed--> CountdownTransient | tZero=nowNs; flag DOSE_OUT_OF_SPEC if volume outside [doseMinUl,doseMaxUl]; Haptic(heavy), StartTicker, PersistCheckpoint
 T15 DosingPrompt --FoamWetDetected(ts)--> CountdownTransient | tZero=ts; flag T0_AUTO
 T16 DosingPrompt --Tick--> BaselineAlign when now-enteredAt > baselineStaleS (discard baseline)
 T17 CountdownTransient --Tick--> (stay) Haptic(warn) once when t >= tTransientS - preWarnS
 T18 CountdownTransient --Tick--> phase=preroll, SetTorch(1.0) when torchPolicy==windowed AND t >= tTransientS - windowHalfWidthS - torchPreRollMs/1000
 T19 CountdownTransient --Tick--> phase=capturing, CaptureBurst(burstFrames, burstMinFps, windowId=23) when t >= tTransientS - windowHalfWidthS  (exactly once)
 T20 CountdownTransient --BurstDone(23)|Tick t>=tTransientS+windowHalfWidthS--> CountdownSteady | choose best passing frame else add flag T23_MISSED; SetTorch(0) if windowed. NO ROLLBACK.
 T21 CountdownSteady --Tick--> phase=preroll, SetTorch(1.0) when windowed AND t >= tSteadyS - windowHalfWidthS - torchPreRollMs/1000
 T22 CountdownSteady --Tick--> phase=capturing, CaptureBurst(...,windowId=120) when t >= tSteadyS - windowHalfWidthS (exactly once)
 T23 CountdownSteady --BurstDone(120)|Tick t>=tSteadyS+windowHalfWidthS--> Uploading(encoding) if (t120 frame) OR (baseline AND t23 frame, flag STEADY_MISSING); else ErrorHandling(NO_USABLE_FRAMES). ReleaseCamera, StopAnalysis, StopTicker
 T24 Uploading(encoding) --(entry)--> EncodeAndBuildPayload then PersistOutbox BEFORE UploadPayload
 T25 UploadSucceeded --> Uploading(analyzing) | PollResult
 T26 NetworkError (retryable, attempt<uploadMaxAttempts) --> Uploading(sending) | ScheduleBackoff(2,4,8,16,32 s x attempt index)
 T27 NetworkError with offline==true AND attempt>=offlineAfterFailures --> Idle | ScheduleOfflineWork, ShowNotification("saved")
 T28 HttpRejected(400|413|415|422) --> ErrorHandling(UPLOAD_REJECTED) (no retry)
 T29 ResultReady --> ReportReady | Haptic by class, Wakelock(false)
 T30 AnalysisFailed --> ErrorHandling(ANALYSIS_FAILED)
 T31 Uploading(analyzing) --Tick--> Idle (history "pending") when elapsed analyzing > analysisTimeoutS
 T32 ReportReady --NewSession--> Idle | ReleaseCamera
 T33 any Countdown* --UserAbort--> ErrorHandling(USER_ABORT, preDose=false) | ReleaseCamera, SetTorch(0)
 T34 any camera-active state --CameraLost--> ErrorHandling(CAMERA_LOST) UNLESS in Countdown* and a window remains reachable (then add flag CAMERA_RECOVERED_ATTEMPT and stay)
 T35 any Countdown* --AppResumed--> recompute t from the monotonic clock; mark any window with t > target+windowHalfWidthS and no frame as missed; if t > tSteadyS+windowHalfWidthS+timerExpiredGraceS and no t120 frame => ErrorHandling(TIMER_EXPIRED)
 T36 any pre-dose camera state --AppPaused--> (stay) ReleaseCamera, SetTorch(0); on AppResumed re-run ApplyCameraConfig
 T38 ErrorHandling --Recover(RETRY_PRE_DOSE)--> PreCheck ONLY if preDose==true (tZero unset); otherwise ignore
 T39 ErrorHandling --Recover(other)--> Idle | ReleaseCamera, Wakelock(false)
 T40 CheckpointFound(cp) with stateName>=Countdown AND (now-tZero) < tSteadyS+windowHalfWidthS+timerExpiredGraceS => offer resume (restore state, apply T35); else mark aborted.
 Any (state,event) pair NOT in the table => state unchanged, no effects (and a `UnhandledEvent` log effect).

INVARIANTS (assert in tests)
 I-A After tZero is set, NO transition leads to BaselineAlign, BaselineCaptured, DosingPrompt or PreCheck.
 I-B Every CaptureBurst effect for window 23 and window 120 is emitted AT MOST ONCE per session.
 I-C PersistOutbox always precedes UploadPayload in the effect list.
 I-D Time is only read from Tick.nowNs / event payloads. The reducer never calls a clock.
 I-E The camera is released and the torch is off in every transition into Idle, ReportReady, ErrorHandling.
RUNNER: EffectRunner executes effects against the injected services, feeding results back as events. StartTicker emits Tick(nowNs) every 50 ms from the injected Clock, auto-stops on StopTicker.
 Timer drift test: with a fake clock advanced by uneven steps (30..120 ms) the capture window opens within one tick of the exact time.
ERROR PLANS (map_failure_to_recovery): code -> {severity, messageKey, routes}: CAMERA_CONFIG_UNVERIFIED -> CHECK_SETTINGS,CONTACT_SUPPORT; ALIGN_TIMEOUT -> RETRY_PRE_DOSE;
 NO_USABLE_FRAMES, TIMER_EXPIRED, USER_ABORT, CAMERA_LOST (post-dose) -> RESTART_NEW_PATCH; UPLOAD_REJECTED, ANALYSIS_FAILED -> RESTART_NEW_PATCH,CONTACT_SUPPORT; pre-check codes -> RETRY_PRE_DOSE.
TESTS: one reducer test per table row (generated from docs/fsm_table.md where possible); boundary tests at t = 21.99/22.00/22.01, 23.99/24.00, 118.99/119.00, 120.99/121.00 s;
 invariants I-A..I-E via a randomized event fuzzer (1000 sequences, fixed seed) that must never violate them; bloc_test for the happy path using fakes.
ACCEPTANCE: happy path Idle -> ... -> ReportReady with a fake clock; burst windows produce exactly two CaptureBurst effects; offline path ends in Idle with an outbox row; fuzz passes.
````

---

### PROMPT 5 — Diagnostic Dashboard & Results View

````text
TASK: Build the results UI for ShuntWhisper: status banner, metric cards, thermal comparison view, ROI gallery, "why inconclusive" panel, history list, and PDF export.
PACKAGES ALLOWED: flutter_bloc, equatable, pdf, printing, share_plus, path_provider, intl, golden_toolkit (tests).
MODELS AVAILABLE (do not redefine): DiagnosticResponse, Measured, EvapMeasured, FlowEstimate, TimepointResult, RoiVisual, Classification, InconclusiveReason, RemoteConfig.featureFlags.
INPUT: `DiagnosticResponse response`, `Map<String,bool> featureFlags`, `Future<Result<Uint8List>> Function(RoiVisual) loadRoi`, `bool offlineCachedImages`.

FILES
 lib/features/report/presentation/{report_page.dart, status_banner.dart, metric_card.dart, thermal_comparison_view.dart, roi_gallery.dart, why_inconclusive_panel.dart}
 lib/features/report/pdf/report_pdf_builder.dart
 lib/features/history/presentation/history_page.dart
 lib/l10n/app_en.arb (all strings, including every reason code message and the disclaimer)
 test/presentation/report_golden_test.dart, test/features/report/{pdf_builder_test.dart, wording_test.dart}

STATUS BANNER (class -> color, icon, headline, sub-line; NEVER use the words "diagnosis", "confirmed", "normal shunt", "failure confirmed")
 PATENT_HIGH     green  check   "Flow signature present"          sub: "Upstream is warmer than downstream by the expected margin."
 PATENT_MARGINAL amber  warning "Weak flow signature"             sub: "Result is near the decision boundary. Repeat the test or seek clinical review if symptomatic."
 OCCLUDED        red    alert   "Possible blockage"               sub: "No flow signature detected. Seek clinical evaluation. This test cannot confirm shunt failure."
 INCONCLUSIVE    grey   info    "Test could not be interpreted"   sub: reason-specific text from WhyInconclusivePanel.
 Banner always shows the confidence percentage as a labelled gauge (0-100), the DISCLAIMER TEXT, and a Semantics label. Color is never the only signal.
 If confidencePct < 50 for a non-INCONCLUSIVE class: add a visible "Low confidence" chip and move the class headline under it.
METRIC CARDS (each is a MetricCard with title, value, unit, uncertainty, help tooltip)
 1. "Upstream - downstream" = deltaTUdC.value with "+/- sigma" (2 decimals, degC). Subtext: reference bands "0.10 / 0.35 degC" with a small bar showing the value against the bands.
 2. "Evaporative cooling (reference minus patches)" = deltaTEvapC; if isLowerBound show ">= value". Show deltaTEvapC.definition in the tooltip.
 3. "Estimated flow" ONLY if featureFlags['showFlowEstimate']==true AND estimatedFlowMlMin != null: show lo-hi mL/min; if !validated show the chip "Unvalidated estimate". Otherwise do not render the card at all.
 4. "Measurement quality": confidencePct gauge + snrResolutionDb ("can resolve 0.1 degC: yes/marginal/no" at >=10 dB / 3-10 / <3).
 5. "Timepoints": list of TimepointResult (23 s and 120 s): class chip, deltaT, qaPassed icon. If the timepoints disagree show a note "Early and late readings differ".
THERMAL COMPARISON VIEW (CustomPaint, no chart package)
 A dumbbell chart of upstream vs downstream temperature (degC) with +/- sigma error bars, the lateral reference as a dashed horizontal line, and the difference annotated.
 Axis auto-scales to the data +/- 0.5 degC and never starts at zero. Missing temperatures render a grey "n/a" marker. Include a text alternative (Semantics) stating all three numbers.
ROI GALLERY: horizontal list of RoiVisual items via loadRoi; each tile shows a spinner, an error state with Retry, and on success the image. Tapping opens a full-screen InteractiveViewer.
 Group the tiles: "Patches" (crop), "Overlay", "Normalized". Handle expired URLs (expiresAtUtc passed) by showing "Image expired" + a Refresh callback (parameter `onRefreshUrls`). Cache decoded bytes in memory only; no disk caching.
WHY INCONCLUSIVE PANEL: for each InconclusiveReason show: title, one-sentence cause, ordered remediation steps, and whether a NEW patch is required:
 insufficientHydration: "The foam did not cool enough." / re-dose 60-80 uL, ensure the foam is in contact with the silicone / new patch YES. IMPORTANT: this must never be described as a blockage.
 outOfRangeWarm: "Patch too warm for the color range." / let the patient and room settle, avoid heat sources / new patch YES.
 outOfRangeCold: "Patch too cold for the color range." / warm the area to room temperature / new patch YES.
 qcMotionBlur: "Image was blurred." / use the stand, hold steady / YES. qcRegistration: "Markers not clearly visible." / YES. qcExposure/qcIllumination: "Lighting problem." / use the diffuser shroud / YES.
 specularRoi: "Glare on the patches." / use the diffuser shroud, avoid direct light / YES. reverseGradient: "Unexpected temperature pattern." / check the patch orientation (flow arrow) / YES.
 lowSnr: "Signal too small to resolve." / seek clinical evaluation if symptomatic / YES. sinkUnverifiable, qcColorFit, other: generic text / YES.
PDF EXPORT (ReportPdfBuilder.build(response, roiBytes, appInfo, subjectRef) -> Future<Uint8List>)
 A4 portrait. Header: "ShuntWhisper test report" + sessionId + processedAtUtc + engineVersion + calibrationIdUsed + subjectRef (pseudonymous only; NEVER a name field).
 Body: banner (class + headline), metric table (every metric above that is displayed in the app, same rounding), the dumbbell chart rendered with pdf widgets, ROI images (max 6, scaled), flags list,
 the DISCLAIMER TEXT in a boxed footer on EVERY page, page numbers. Fonts: bundle a Unicode font asset via rootBundle for the degree sign and plus/minus; fail gracefully if absent.
 Share via Printing.sharePdf / share_plus. The file name pattern: shuntwhisper_<sessionId>_<yyyyMMdd>.pdf
HISTORY: list of stored sessions (id, time, class chip, delta T, confidence, pending flag); data comes from an injected `HistoryRepository` (abstract; define the interface: watchAll(), get(id), delete(id)).
STATE: ReportPage is a StatelessWidget reading an immutable ReportViewModel built by a pure function `buildReportViewModel(response, flags)` (unit-tested). No network calls inside widgets.
EDGE CASES: deltaTUdC null (INCONCLUSIVE), roiVisuals empty, confidence 0, unknown classification (render as INCONCLUSIVE with "Update the app" notice), very long flags list (collapse after 5), RTL locale, text scale 2.0 (no overflow).
TESTS: goldens for each of the 4 classes + insufficientHydration + low-confidence + text scale 2.0; wording_test asserts the forbidden words never appear in any ARB string or rendered banner;
 view-model tests for flow-estimate gating and the dumbbell axis range; PDF builder test that the PDF bytes start with "%PDF" and contain the disclaimer text.
ACCEPTANCE: INSUFFICIENT_HYDRATION never maps to OCCLUDED wording anywhere (test); flow-estimate card hidden unless flag AND value; disclaimer present on screen and on every PDF page.
````

---

## F. Parallel Backend Track (required for the app to function)

| ID | Task | Notes |
|---|---|---|
| B0 | Re-parameterise `PatchGeometry` for discrete patches at ±8.7 mm, the 7.6 mm aperture and the lateral reference (R1). Re-run `selftest`. | Re-derive Bragg numbers: x₀/d = 0.087. |
| B1 | FastAPI service (`/v1/sessions` etc.) around `ShuntWhisperEngine.diagnose()`; accept intrinsics per image | Matches OpenAPI in §B.5. |
| B2 | Response adapter: engine `FrameAnalysis`/`DiagnosticReport` → §B.4 JSON with the §B.6 class mapping | |
| B3 | Define and implement `ΔT_evap` (R2) and the flow-estimate stub (R4: `validated:false`) | Needs owner decision. |
| B4 | ROI visuals: signed, expiring PNGs (crop, overlay, normalised, spec-mask) | |
| B5 | Contract tests: golden JSON fixtures shared with the app's `test/models/fixtures` | |
| B6 | `/v1/config`, `/v1/device-profiles`, `/v1/calibrations` endpoints and seed data | |

## G. Risk Register (top items)

| Risk | Impact | Mitigation |
|---|---|---|
| Phones cannot focus at 10 cm | Wrong working distance, smaller patch | Pre-check 3; per-device profile; macro/ultra-wide lens; re-budget |
| Manual settings not honoured by an OEM | Silent radiometric drift | I1 read-back + Gate G0 + `configDrift` events |
| Bragg viewing-angle error | False flow or false occlusion | Alignment thresholds + PnP correction + intrinsics upload |
| `opencv_dart` lacks ArUco/PnP | Blocks guidance | Spike S1; native fallback behind `FiducialTracker` |
| Torch heating / airflow bias | Biased sink | `windowed` torch policy; bench-test before locking |
| t0 uncertainty (tap latency) | 23 s timepoint error | Auto foam-wet detection (flagged); log `T0_AUTO` vs `manual_tap` |
| ΔT_evap undefined with a bare-foam aperture | Missing field | R2 decision |
| Unvalidated flow estimate shown to users | Clinical misinterpretation | Feature flag off by default; "Unvalidated" chip |
| Regulatory | Not a medical device | Disclaimer everywhere; plan IEC 62304 / ISO 14971 before any clinical use |

## H. Open Questions for the Owner (needed before Prompt 1)

1. ❓ R6: is **t = 0 the dose instant**, with the baseline taken just before?
2. ❓ R2: is `ΔT_evap ≡ T_lateral_ref − ½(T_up + T_down)` acceptable?
3. ❓ R3: confirm **0.10–0.35 °C = PATENT_MARGINAL**.
4. ❓ B.7: patch ROI size (assumed 4×4 mm), the **sign of the lateral-reference offset**, and fiducial marker size and positions.
5. ❓ Auth model for the backend (per-install token vs user login).
6. ❓ Do you want `torchPolicy` default `windowed` until bench data exists?

Here are the confirmed answers for Section H to unblock Prompt 1:

1. **R6 (Timeline / t = 0):** **YES.** 
   - Baseline is captured dry immediately before dosing ($t_{\text{baseline}} < 0$).
   - The user taps "Dosed & Ready" upon dispensing the $60\text{–}80\text{ }\mu\text{L}$ volume. That tap sets **$t = 0.00\text{ s}$**.
   - Checkpoint captures trigger automatically at $t = 23\text{ s} \pm 1\text{ s}$ (transient inflection) and $t = 120\text{ s} \pm 2\text{ s}$ (thermal steady state).

2. **R2 (Evaporative Metric):** **YES, ACCEPTED.**
   $$\Delta T_{\text{evap}} = T_{\text{lateral\_ref}} - \frac{T_{\text{upstream}} + T_{\text{downstream}}}{2}$$
   - Apply a minimum validity gate: if $\Delta T_{\text{evap}} < 1.50^\circ\text{C}$ at $t = 120\text{ s}$, flag as `INCONCLUSIVE_INSUFFICIENT_HYDRATION`. Never report an occlusion if the evaporative sink failed to establish.

3. **R3 (Diagnostic Decision Boundaries):** **CONFIRMED.**
   - $\Delta T_{UD} \ge 0.35^\circ\text{C}$: `PATENT_NORMAL_FLOW` (or `PATENT_HIGH`)
   - $0.10^\circ\text{C} \le \Delta T_{UD} < 0.35^\circ\text{C}$: `PATENT_LOW_FLOW` (or `PATENT_MARGINAL`)
   - $-0.08^\circ\text{C} \le \Delta T_{UD} < 0.10^\circ\text{C}$: `OCCLUSION_SUSPECTED` (Symmetric cooling profile)
   - $\Delta T_{UD} < -0.08^\circ\text{C}$: `INCONCLUSIVE_REVERSED_GRADIENT` (Thermal inversion / ambient draft artifact)

4. **B.7 (Geometry, ROI Sizes, and Coordinates):**
   - **Patch Origin $(0, 0, 0)$:** Geometric center of the central $7.6 \times 7.6\text{ mm}$ foam aperture. Flow axis is along $+X$.
   - **ROI Sizes:** Use **$4.0\text{ mm} \times 6.0\text{ mm}$** (4 mm along the catheter flow axis $X$, 6 mm transverse width along $Y$).
   - **Centers:**
     - Upstream ROI: $(x = -8.7\text{ mm}, y = 0.0\text{ mm})$
     - Downstream ROI: $(x = +8.7\text{ mm}, y = 0.0\text{ mm})$
     - Lateral Reference ROI: $(x = 0.0\text{ mm}, y = +12.0\text{ mm})$ (**Positive $Y$ offset**, placed over solid silicone clear of the central aperture).
   - **Fiducials:** 4 ArUco markers (`DICT_4X4_50`, IDs 0, 1, 2, 3), each **$6.0 \times 6.0\text{ mm}$**, centered symmetrically at $(\pm 18.0\text{ mm}, \pm 18.0\text{ mm})$.

5. **Auth Model:** **STATIC PRE-SHARED BEARER TOKEN.**
   - For this P0/competition test phase, use a pre-shared token passed in HTTP headers: `Authorization: Bearer shuntwhisper-p0-local-token`. No user login or OAuth required.

6. **Torch Policy:** **YES, DEFAULT TO `windowed`.**
   - Keep the torch off during idle intervals to avoid parasitic radiative heating of the patch.
   - Torch engages automatically only during capture gates:
     - Baseline: $t = -3\text{ s}$ to $0\text{ s}$
     - Transient: $t = 20\text{ s}$ to $24\text{ s}$
     - Steady State: $t = 117\text{ s}$ to $121\text{ s}$

All open questions are locked. Please proceed directly with generating Prompt 1 for Gemini Flash.

# Master Architectural Directive & Parameter Reconciliation Patch

Claude, accept the following decisions as finalized project specifications. Update your contracts, schemas, and state logic accordingly, and immediately generate the final **Sections A through E (including all copy-pasteable Gemini 2.5 Flash prompts)** without further caveats or pauses.

---

## 1. Resolution of the 6 Architectural Ambiguities

### Q1: Timeline & Time Zero Definition ($t = 0$)
- **Resolution**: **$t = 0\text{ s}$ is defined as the exact moment the user confirms foam hydration.**
- **Sequence**:
  1. `BASELINE_CAPTURE` occurs immediately **before** hydration on the dry, thermally equilibrated patch ($t_{\text{baseline}} < 0$).
  2. The app prompts: *"Hydrate foam with 60–80 µL distilled water."*
  3. The user taps **"Dosed & Ready"**. This button press resets and starts the master clock at **$t = 0.00\text{ s}$**.
  4. Automated checkpoint captures trigger at **$t = 23\text{ s} \pm 1\text{ s}$** (transient inflection) and **$t = 120\text{ s} \pm 2\text{ s}$** (thermal steady-state).

### Q2: Mathematical Definition of Evaporative Sink Metric ($\Delta T_{\text{evap}}$)
- **Resolution**: Because the central $7.6 \times 7.6\text{ mm}$ aperture contains bare foam without TLC, $\Delta T_{\text{evap}}$ is calculated using the uncooled lateral reference patch:
  $$\Delta T_{\text{evap}} = T_{\text{lateral\_ref}} - \frac{T_{\text{upstream}} + T_{\text{downstream}}}{2}$$
- **Validity Gate**: If $\Delta T_{\text{evap}} < 1.50^\circ\text{C}$ at $t = 120\text{ s}$, the evaporative sink has failed to establish (e.g., dry foam, ambient $\text{RH} \approx 100\%$, or ambient draft). The result MUST be classified as `INCONCLUSIVE_INSUFFICIENT_HYDRATION` and never as an occlusion.

### Q3: Diagnostic Classification Boundaries
- **Resolution**: The diagnostic decision thresholds are locked as follows:
  - **$\Delta T_{UD} \ge 0.35^\circ\text{C}$**: `PATENT_NORMAL_FLOW` (Green banner).
  - **$0.10^\circ\text{C} \le \Delta T_{UD} < 0.35^\circ\text{C}$**: `PATENT_LOW_FLOW` (Amber banner).
  - **$-0.08^\circ\text{C} \le \Delta T_{UD} < 0.10^\circ\text{C}$**: `OCCLUSION_SUSPECTED` (Red banner, symmetric thermal profile).
  - **$\Delta T_{UD} < -0.08^\circ\text{C}$**: `INCONCLUSIVE_REVERSED_GRADIENT` (Thermal inversion / ambient artifact; requires retest).

### Q4: Exact Coordinate Geometry & ROI Layout
- **Resolution**: Set the patch origin $(0, 0, 0)$ at the physical center of the $7.6 \times 7.6\text{ mm}$ central foam aperture, with the catheter running along the $X$-axis (flow directed from $-X$ to $+X$):
  - **$ROI_{\text{upstream}}$**: Center at $(x = -8.7\text{ mm}, y = 0.0\text{ mm})$; dimensions $4.0\text{ mm} \times 6.0\text{ mm}$ (spanning $-10.7\text{ mm} \le x \le -6.7\text{ mm}$, $-3.0\text{ mm} \le y \le +3.0\text{ mm}$).
  - **$ROI_{\text{downstream}}$**: Center at $(x = +8.7\text{ mm}, y = 0.0\text{ mm})$; dimensions $4.0\text{ mm} \times 6.0\text{ mm}$ (spanning $+6.7\text{ mm} \le x \le +10.7\text{ mm}$, $-3.0\text{ mm} \le y \le +3.0\text{ mm}$).
  - **$ROI_{\text{lateral\_ref}}$**: Center at $(x = 0.0\text{ mm}, y = +12.0\text{ mm})$; dimensions $4.0\text{ mm} \times 6.0\text{ mm}$ (spanning $-2.0\text{ mm} \le x \le +2.0\text{ mm}$, $+9.0\text{ mm} \le y \le +15.0\text{ mm}$).
  - **Central Foam Collar**: Square aperture from $-3.8\text{ mm} \le x \le +3.8\text{ mm}$, $-3.8\text{ mm} \le y \le +3.8\text{ mm}$.
  - **Fiducial Framing**: 4 ArUco markers (`DICT_4X4_50`, IDs 0, 1, 2, 3), each $6.0 \times 6.0\text{ mm}$, centered at outer coordinates $(\pm 18.0\text{ mm}, \pm 18.0\text{ mm})$.

### Q5: Backend Communication & Authentication
- **Resolution**: For this P0/competition milestone, the mobile client communicates with a local FastAPI/Flask backend over local Wi-Fi / loopback:
  - **Auth**: Static pre-shared bearer token (`Authorization: Bearer shuntwhisper-p0-local-token`) passed in HTTP headers.
  - **Payload Format**: `multipart/form-data` containing three PNG image files (`baseline_img`, `sample23_img`, `sample120_img`) alongside a serialized JSON metadata string (`device_metadata`).
  - **Estimated Flow Rate ($Q$)**: The backend calculates and returns $Q$ in $\text{mL/min}$ as an experimental estimation field, but flags it with `is_experimental: true`. The UI will display it inside an "Engineering / Flow Estimation" card, but the primary clinical banner will rely strictly on the categorical status (`PATENT_NORMAL_FLOW`, `PATENT_LOW_FLOW`, `OCCLUSION_SUSPECTED`).

### Q6: LED Torch Thermal Duty Cycle
- **Resolution**: Continuous torch illumination