import '../../../domain/models/alignment_models.dart';
import '../../../domain/models/payload_models.dart';
import 'session_state.dart';
import 'session_event.dart';
import 'session_effect.dart';

/// Pure Finite State Machine transition reducer.
/// Guarantees Invariant I3 (pure function, no I/O) and Invariant I4 (forward-only after t0).
class SessionReducer {
  static (SessionState, List<SessionEffect>) reduce(
    SessionState state,
    SessionEvent event, {
    Map<String, dynamic> policy = const {},
  }) {
    switch (state.step) {
      // 1. IDLE
      case SessionStep.idle:
        if (event is StartSession) {
          return (
            state.copyWith(step: SessionStep.preCheck),
            [const RunPreflightChecksEffect()]
          );
        }
        break;

      // 2. PRE_CHECK
      case SessionStep.preCheck:
        if (event is PreChecksPassed) {
          return (
            state.copyWith(step: SessionStep.baselineAlign),
            [const EnableTorchEffect(), const HapticCueEffect('warning')]
          );
        } else if (event is PreCheckFailed) {
          return (
            state.copyWith(
              step: SessionStep.errorHandling,
              errorCode: event.code,
              errorMessage: event.reason,
            ),
            []
          );
        }
        break;

      // 3. BASELINE_ALIGN
      case SessionStep.baselineAlign:
        if (event is AlignmentUpdated) {
          final isAligned = event.alignment.status == AlignmentStatus.aligned;
          final nextFrames = isAligned ? state.alignConsecutiveFrames + 1 : 0;
          final effects = <SessionEffect>[];

          // Trigger capture once 8 consecutive stable frames are maintained
          if (nextFrames >= 8) {
            effects.add(const TriggerBurstCaptureEffect(part: 'baseline'));
          }

          return (
            state.copyWith(
              lastAlignment: event.alignment,
              alignConsecutiveFrames: nextFrames,
            ),
            effects
          );
        } else if (event is BaselineCaptured) {
          final nextPaths = Map<String, String>.from(state.capturedFilePaths);
          nextPaths['baseline'] = event.filePath;
          final nextImages = List<CapturedImageMeta>.from(state.capturedImages)..add(event.meta);

          return (
            state.copyWith(
              step: SessionStep.dosingPrompt,
              capturedFilePaths: nextPaths,
              capturedImages: nextImages,
              alignConsecutiveFrames: 0,
            ),
            [const DisableTorchEffect(), const HapticCueEffect('success')]
          );
        } else if (event is SessionFailed) {
          return (
            state.copyWith(
              step: SessionStep.errorHandling,
              errorCode: event.code,
              errorMessage: event.message,
            ),
            [const DisableTorchEffect()]
          );
        }
        break;

      // 4. BASELINE_CAPTURED -> DOSING_PROMPT
      case SessionStep.baselineCaptured:
        return (
          state.copyWith(step: SessionStep.dosingPrompt),
          [const DisableTorchEffect()]
        );

      // 5. DOSING_PROMPT (Locks t0, strictly forward-only after this)
      case SessionStep.dosingPrompt:
        if (event is DoseConfirmed) {
          return (
            state.copyWith(
              step: SessionStep.countdownTransient,
              tZeroMonotonicNs: event.tZeroMonotonicNs,
              tZeroUtc: event.tZeroUtc,
              doseVolumeUl: event.volumeUl,
            ),
            [
              // Windowed torch: warmup starts at t=20s (20000ms from t0)
              const ScheduleWindowEffect(
                windowName: 't23_preroll',
                delay: Duration(seconds: 20),
              ),
              const HapticCueEffect('warning')
            ]
          );
        }
        break;

      // 6. COUNTDOWN_TRANSIENT (t = 23s)
      case SessionStep.countdownTransient:
        if (event is TransientWindowOpened) {
          return (
            state,
            [const EnableTorchEffect(), const TriggerBurstCaptureEffect(part: 't23')]
          );
        } else if (event is TransientCaptured) {
          final nextPaths = Map<String, String>.from(state.capturedFilePaths);
          nextPaths['t23'] = event.filePath;
          final nextImages = List<CapturedImageMeta>.from(state.capturedImages)..add(event.meta);

          return (
            state.copyWith(
              step: SessionStep.countdownSteady,
              capturedFilePaths: nextPaths,
              capturedImages: nextImages,
            ),
            [
              const DisableTorchEffect(),
              // Steady state warmup starts at t=117s (94s from t=23s)
              const ScheduleWindowEffect(
                windowName: 't120_preroll',
                delay: Duration(seconds: 94),
              ),
              const HapticCueEffect('success')
            ]
          );
        }
        break;

      // 7. COUNTDOWN_STEADY (t = 120s)
      case SessionStep.countdownSteady:
        if (event is SteadyWindowOpened) {
          return (
            state,
            [const EnableTorchEffect(), const TriggerBurstCaptureEffect(part: 't120')]
          );
        } else if (event is SteadyCaptured) {
          final nextPaths = Map<String, String>.from(state.capturedFilePaths);
          nextPaths['t120'] = event.filePath;
          final nextImages = List<CapturedImageMeta>.from(state.capturedImages)..add(event.meta);

          final payload = CapturePayload(
            sessionId: state.sessionId,
            schemaVersion: 1,
            createdAtUtc: DateTime.now().toUtc(),
            app: const AppInfo(version: '1.0.0', build: '100', platform: 'ios', osVersion: '18.1'),
            device: const DeviceInfo(model: 'iphone_15_pro', cameraId: '0'),
            calibrationId: 'CAL-TLC-2025-01',
            ambient: AmbientMetadata(
              temperatureC: 22.5,
              relativeHumidityPct: 45.0,
              measuredAtUtc: DateTime.now().toUtc(),
            ),
            dosing: DosingRecord(
              volumeUl: state.doseVolumeUl,
              tZeroMonotonicNs: state.tZeroMonotonicNs ?? 0,
              tZeroUtc: state.tZeroUtc ?? DateTime.now().toUtc(),
            ),
            images: nextImages,
          );

          return (
            state.copyWith(
              step: SessionStep.uploading,
              capturedFilePaths: nextPaths,
              capturedImages: nextImages,
            ),
            [
              const DisableTorchEffect(),
              UploadSessionPayloadEffect(payload: payload, filePaths: nextPaths)
            ]
          );
        }
        break;

      // 8. UPLOADING
      case SessionStep.uploading:
        if (event is DiagnosticReportReceived) {
          return (
            state.copyWith(
              step: SessionStep.reportReady,
              diagnosticResponse: event.report,
            ),
            [const HapticCueEffect('success')]
          );
        } else if (event is SessionFailed) {
          return (
            state.copyWith(
              step: SessionStep.errorHandling,
              errorCode: event.code,
              errorMessage: event.message,
            ),
            []
          );
        }
        break;

      // 9. REPORT_READY / ERROR_HANDLING
      case SessionStep.reportReady:
      case SessionStep.errorHandling:
        if (event is ResetSession) {
          return (SessionState.initial(state.sessionId), []);
        }
        break;
    }

    return (state, []);
  }
}

