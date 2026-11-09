"""
Authoritative configurations, default patch layout, and device profiles for ShuntWhisper.
"""

from __future__ import annotations
from typing import Dict, Any
from backend.models import (
    PointDto,
    SizeMm,
    SizeDto,
    FiducialSpec,
    PatchLayout,
    RemoteConfig,
    DeviceProfile,
    WbGains,
    Intrinsics,
    IntrinsicsSource,
)

AUTH_BEARER_TOKEN = "shuntwhisper-p0-local-token"

# Authoritative physical patch layout per locked project specifications
DEFAULT_PATCH_LAYOUT = PatchLayout(
    upstreamCenterMm=PointDto(x=-8.7, y=0.0),
    downstreamCenterMm=PointDto(x=8.7, y=0.0),
    lateralRefCenterMm=PointDto(x=0.0, y=12.0),
    apertureCenterMm=PointDto(x=0.0, y=0.0),
    apertureSizeMm=SizeMm(w=7.6, h=7.6),
    roiSizeMm=SizeMm(w=4.0, h=6.0),
    fiducials=[
        FiducialSpec(id=0, centerMm=PointDto(x=-18.0, y=-18.0), sideMm=6.0),
        FiducialSpec(id=1, centerMm=PointDto(x=18.0, y=-18.0), sideMm=6.0),
        FiducialSpec(id=2, centerMm=PointDto(x=18.0, y=18.0), sideMm=6.0),
        FiducialSpec(id=3, centerMm=PointDto(x=-18.0, y=18.0), sideMm=6.0),
    ],
)

DEFAULT_REMOTE_CONFIG = RemoteConfig(
    sessionPolicy={
        "targetDistanceMm": 100.0,
        "alignStableFrames": 8,
        "alignStableMs": 800,
        "alignTimeoutS": 120,
        "baselineCaptureBurst": 3,
        "baselineStaleS": 180,
        "doseVolumeUlMin": 60.0,
        "doseVolumeUlMax": 80.0,
        "doseVolumeUlNominal": 70.0,
        "tTransientS": 23.0,
        "tSteadyS": 120.0,
        "windowHalfWidthS": 1.0,
        "torchPolicy": "windowed",
        "torchPreRollMs": 2500,
        "minBatteryPct": 20,
        "minFreeMb": 500,
        "ambientHardRangeC": [10.0, 35.0],
        "ambientWarnRangeC": [15.0, 30.0],
    },
    alignmentThresholds={
        "maxPitchDeg": 5.0,
        "maxYawDeg": 5.0,
        "maxRollDeg": 8.0,
        "maxCenterOffsetFrac": 0.05,
        "maxLateralOffsetMm": 2.0,
        "distanceTolFrac": 0.10,
        "minFrameMarginFrac": 0.04,
    },
    validatorThresholds={
        "minSharpness": 0.06,
        "maxWhiteClipFrac": 0.02,
        "maxColorFitRms": 0.06,
        "maxRegRmsPx": 3.0,
    },
    patchLayout=DEFAULT_PATCH_LAYOUT,
    featureFlags={
        "showFlowEstimate": False,
        "windowedTorch": True,
        "enableAutoWetDetection": False,
        "exportDiagnosticPdf": True,
    },
    deviceProfileVersion=1,
)

# Device profiles for calibrated hardware models
DEFAULT_DEVICE_PROFILES: Dict[str, DeviceProfile] = {
    "android/pixel_8": DeviceProfile(
        platform="android",
        model="pixel_8",
        cameraId="0",
        previewAnalysisSize=SizeDto(widthPx=1280, heightPx=960),
        stillSize=SizeDto(widthPx=4080, heightPx=3072),
        targetDistanceMm=100.0,
        androidFocusDiopters=10.0,
        iosLensPosition=None,
        neutralWbGains=WbGains(r=1.95, gEven=1.0, gOdd=1.0, b=1.82),
        intrinsicsByStill=[
            Intrinsics(
                fx=3120.0,
                fy=3120.0,
                cx=2040.0,
                cy=1536.0,
                imageW=4080,
                imageH=3072,
                source=IntrinsicsSource.PROFILE,
            )
        ],
        version=1,
    ),
    "ios/iphone_15_pro": DeviceProfile(
        platform="ios",
        model="iphone_15_pro",
        cameraId="com.apple.avfoundation.back.telephoto",
        previewAnalysisSize=SizeDto(widthPx=1280, heightPx=960),
        stillSize=SizeDto(widthPx=4032, heightPx=3024),
        targetDistanceMm=100.0,
        androidFocusDiopters=None,
        iosLensPosition=0.10,
        neutralWbGains=WbGains(r=1.88, gEven=1.0, gOdd=1.0, b=1.92),
        intrinsicsByStill=[
            Intrinsics(
                fx=3080.0,
                fy=3080.0,
                cx=2016.0,
                cy=1512.0,
                imageW=4032,
                imageH=3024,
                source=IntrinsicsSource.PROFILE,
            )
        ],
        version=1,
    ),
    "generic": DeviceProfile(
        platform="generic",
        model="generic",
        cameraId="0",
        previewAnalysisSize=SizeDto(widthPx=1280, heightPx=960),
        stillSize=SizeDto(widthPx=2560, heightPx=1920),
        targetDistanceMm=100.0,
        androidFocusDiopters=10.0,
        iosLensPosition=0.10,
        neutralWbGains=None,
        intrinsicsByStill=[],
        version=1,
    ),
}

