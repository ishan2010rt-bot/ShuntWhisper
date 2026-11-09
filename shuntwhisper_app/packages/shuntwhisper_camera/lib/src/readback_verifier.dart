import 'package:shuntwhisper_app/domain/models/camera_models.dart';

/// Implements Invariant I1: Apply -> Read Back -> Verify.
class ReadbackVerifier {
  static const double exposureTolerance = 0.02; // ±2%
  static const double gainsTolerance = 0.01;    // ±1%
  static const double focusTolerance = 0.05;    // ±5%
  static const double torchTolerance = 0.05;    // ±0.05

  static AppliedCameraState verify({
    required CameraHardwareConfig requested,
    required AppliedCameraState actual,
  }) {
    final List<ParamDeviation> deviations = [];
    bool allWithinTolerance = true;

    // 1. Exposure Time check
    final expDiff = (actual.exposureTimeNs - requested.exposureTimeNs).abs() / requested.exposureTimeNs;
    final expOk = expDiff <= exposureTolerance;
    if (!expOk) {
      allWithinTolerance = false;
      deviations.add(ParamDeviation(
        param: 'exposureTimeNs',
        requested: requested.exposureTimeNs.toDouble(),
        applied: actual.exposureTimeNs.toDouble(),
        withinTolerance: false,
      ));
    }

    // 2. White Balance Gains check
    if (requested.whiteBalance.gains != null && actual.whiteBalanceGains != null) {
      final reqG = requested.whiteBalance.gains!;
      final actG = actual.whiteBalanceGains!;
      final rDiff = (actG.r - reqG.r).abs() / reqG.r;
      final bDiff = (actG.b - reqG.b).abs() / reqG.b;
      if (rDiff > gainsTolerance || bDiff > gainsTolerance) {
        allWithinTolerance = false;
        deviations.add(ParamDeviation(
          param: 'wbGains',
          requested: reqG.r,
          applied: actG.r,
          withinTolerance: false,
        ));
      }
    }

    // 3. Focus Distance check
    if (requested.focus.androidDiopters != null && actual.focusDistanceDiopters != null) {
      final reqD = requested.focus.androidDiopters!;
      final actD = actual.focusDistanceDiopters!;
      final dDiff = reqD > 0 ? (actD - reqD).abs() / reqD : 0.0;
      if (dDiff > focusTolerance) {
        allWithinTolerance = false;
        deviations.add(ParamDeviation(
          param: 'focusDiopters',
          requested: reqD,
          applied: actD,
          withinTolerance: false,
        ));
      }
    }

    // 4. Torch check
    final reqTorch = requested.torch.level;
    final actTorch = actual.torchLevel;
    if ((actTorch - reqTorch).abs() > torchTolerance) {
      allWithinTolerance = false;
      deviations.add(ParamDeviation(
        param: 'torchLevel',
        requested: reqTorch,
        applied: actTorch,
        withinTolerance: false,
      ));
    }

    return AppliedCameraState(
      iso: actual.iso,
      exposureTimeNs: actual.exposureTimeNs,
      whiteBalanceGains: actual.whiteBalanceGains,
      focusDistanceDiopters: actual.focusDistanceDiopters,
      lensPosition: actual.lensPosition,
      torchLevel: actual.torchLevel,
      awbLocked: actual.awbLocked,
      aeLocked: actual.aeLocked,
      sensorTimestampNs: actual.sensorTimestampNs,
      verified: allWithinTolerance && actual.aeLocked && actual.awbLocked,
      deviations: deviations,
    );
  }
}

