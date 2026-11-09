import 'dart:async';
import 'package:flutter/services.dart';
import 'package:shuntwhisper_camera/src/camera_service.dart';
import '../../../data/api/shuntwhisper_api.dart';
import '../../../domain/models/camera_models.dart';
import 'session_effect.dart';
import 'session_event.dart';

class EffectRunner {
  final CameraService cameraService;
  final ShuntWhisperApi api;
  final void Function(SessionEvent event) dispatch;

  EffectRunner({
    required this.cameraService,
    required this.api,
    required this.dispatch,
  });

  Future<void> run(SessionEffect effect) async {
    switch (effect) {
      case RunPreflightChecksEffect():
        // Simulate checking camera permission, battery level, storage
        await Future.delayed(const Duration(milliseconds: 300));
        dispatch(const PreChecksPassed());
        break;

      case EnableTorchEffect(:final level):
        await cameraService.setTorch(TorchMode.on, level);
        break;

      case DisableTorchEffect():
        await cameraService.setTorch(TorchMode.off, 0.0);
        break;

      case TriggerBurstCaptureEffect(:final part):
        final res = await cameraService.captureBurst(burstCount: 3);
        res.fold(
          (images) {
            if (images.isNotEmpty) {
              final best = images.first;
              final path = '/tmp/${part}_capture.png';
              if (part == 'baseline') {
                dispatch(BaselineCaptured(filePath: path, meta: best));
              } else if (part == 't23') {
                dispatch(TransientCaptured(filePath: path, meta: best));
              } else if (part == 't120') {
                dispatch(SteadyCaptured(filePath: path, meta: best));
              }
            }
          },
          (failure) {
            dispatch(SessionFailed(code: failure.code, message: failure.message));
          },
        );
        break;

      case ScheduleWindowEffect(:final windowName, :final delay):
        Timer(delay, () {
          if (windowName == 't23_preroll') {
            dispatch(const TransientWindowOpened());
          } else if (windowName == 't120_preroll') {
            dispatch(const SteadyWindowOpened());
          }
        });
        break;

      case UploadSessionPayloadEffect(:final payload, :final filePaths):
        final submitRes = await api.submitSession(payload, filePaths);
        submitRes.fold(
          (sessionId) async {
            // Poll for result
            final pollRes = await api.pollSession(sessionId);
            pollRes.fold(
              (report) => dispatch(DiagnosticReportReceived(report)),
              (failure) => dispatch(SessionFailed(code: failure.code, message: failure.message)),
            );
          },
          (failure) => dispatch(SessionFailed(code: failure.code, message: failure.message)),
        );
        break;

      case HapticCueEffect(:final type):
        if (type == 'warning') {
          HapticFeedback.mediumImpact();
        } else if (type == 'success') {
          HapticFeedback.heavyImpact();
        }
        break;
    }
  }
}

