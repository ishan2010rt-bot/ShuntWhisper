import 'package:flutter_test/flutter_test.dart';
import 'package:shuntwhisper_app/domain/models/alignment_models.dart';
import 'package:shuntwhisper_app/domain/models/camera_models.dart';
import 'package:shuntwhisper_app/domain/models/diagnostic_models.dart';
import 'package:shuntwhisper_app/domain/models/enums.dart';
import 'package:shuntwhisper_app/domain/models/geometry_models.dart';
import 'package:shuntwhisper_app/domain/models/payload_models.dart';
import 'package:shuntwhisper_app/features/session/bloc/session_state.dart';
import 'package:shuntwhisper_app/features/session/bloc/session_event.dart';
import 'package:shuntwhisper_app/features/session/bloc/session_effect.dart';
import 'package:shuntwhisper_app/features/session/bloc/session_reducer.dart';

void main() {
  group('SessionReducer Pure FSM Verification', () {
    const sessionId = 'test-session-123';
    late SessionState initialState;

    setUp(() {
      initialState = SessionState.initial(sessionId);
    });

    test('T01: StartSession transitions IDLE -> PRE_CHECK with RunPreflightChecksEffect', () {
      final (nextState, effects) = SessionReducer.reduce(initialState, const StartSession());
      expect(nextState.step, SessionStep.preCheck);
      expect(effects, [const RunPreflightChecksEffect()]);
    });

    test('T02: PreChecksPassed transitions PRE_CHECK -> BASELINE_ALIGN with EnableTorchEffect', () {
      final state = initialState.copyWith(step: SessionStep.preCheck);
      final (nextState, effects) = SessionReducer.reduce(state, const PreChecksPassed());
      expect(nextState.step, SessionStep.baselineAlign);
      expect(effects, [const EnableTorchEffect(), const HapticCueEffect('warning')]);
    });

    test('T07: 8 consecutive stable aligned frames trigger baseline capture', () {
      var state = initialState.copyWith(
        step: SessionStep.baselineAlign,
        alignConsecutiveFrames: 7,
      );

      const alignment = FiducialAlignmentState(
        analysisSize: SizeDto(widthPx: 1280, heightPx: 960),
        markersDetected: 4,
        status: AlignmentStatus.aligned,
      );

      final (nextState, effects) = SessionReducer.reduce(state, const AlignmentUpdated(alignment));
      expect(nextState.alignConsecutiveFrames, 8);
      expect(effects, [const TriggerBurstCaptureEffect(part: 'baseline')]);
    });

    test('T09: BaselineCaptured transitions BASELINE_ALIGN -> DOSING_PROMPT', () {
      final state = initialState.copyWith(step: SessionStep.baselineAlign);
      const meta = CapturedImageMeta(
        part: 'baseline',
        tNominalS: 0.0,
        tActualS: -2.5,
        widthPx: 4080,
        heightPx: 3072,
        sizeBytes: 2048,
        sha256: 'mock_sha',
        appliedCamera: AppliedCameraState(iso: 50, exposureTimeNs: 10000000, sensorTimestampNs: 0),
        alignmentAtCapture: FiducialAlignmentState(
          analysisSize: SizeDto(widthPx: 1280, heightPx: 960),
          markersDetected: 4,
          status: AlignmentStatus.aligned,
        ),
        validation: FrameValidationResult(passed: true, sharpness: 0.20, whiteLevel: 0.5, whiteClipFrac: 0.0),
        intrinsics: Intrinsics(fx: 3120, fy: 3120, cx: 2040, cy: 1536, imageW: 4080, imageH: 3072),
      );

      final (nextState, effects) = SessionReducer.reduce(
        state,
        const BaselineCaptured(filePath: '/tmp/baseline.png', meta: meta),
      );

      expect(nextState.step, SessionStep.dosingPrompt);
      expect(nextState.capturedFilePaths['baseline'], '/tmp/baseline.png');
      expect(effects, [const DisableTorchEffect(), const HapticCueEffect('success')]);
    });

    test('T10 (Invariant I4): DoseConfirmed locks t0 and transitions DOSING_PROMPT -> COUNTDOWN_TRANSIENT', () {
      final state = initialState.copyWith(step: SessionStep.dosingPrompt);
      final nowUtc = DateTime.now().toUtc();
      const nowNanos = 5000000000;

      final (nextState, effects) = SessionReducer.reduce(
        state,
        DoseConfirmed(tZeroMonotonicNs: nowNanos, tZeroUtc: nowUtc, volumeUl: 75.0),
      );

      expect(nextState.step, SessionStep.countdownTransient);
      expect(nextState.tZeroMonotonicNs, nowNanos);
      expect(nextState.tZeroUtc, nowUtc);
      expect(nextState.doseVolumeUl, 75.0);
      expect(effects, [
        const ScheduleWindowEffect(windowName: 't23_preroll', delay: Duration(seconds: 20)),
        const HapticCueEffect('warning'),
      ]);
    });

    test('T14: DiagnosticReportReceived transitions UPLOADING -> REPORT_READY', () {
      final state = initialState.copyWith(step: SessionStep.uploading);
      final report = DiagnosticResponse(
        sessionId: sessionId,
        calibrationIdUsed: 'CAL-TLC-2025-01',
        processedAtUtc: DateTime.now().toUtc(),
        classification: Classification.patentHigh,
        deltaTUdC: const Measured(value: 0.45, sigma: 0.03),
        confidencePct: 95.0,
      );

      final (nextState, effects) = SessionReducer.reduce(
        state,
        DiagnosticReportReceived(report),
      );

      expect(nextState.step, SessionStep.reportReady);
      expect(nextState.diagnosticResponse, report);
      expect(effects, [const HapticCueEffect('success')]);
    });
  });
}

