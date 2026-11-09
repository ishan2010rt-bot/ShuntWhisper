import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../core/result.dart';
import '../../domain/models/config_models.dart';
import '../../domain/models/diagnostic_models.dart';
import '../../domain/models/payload_models.dart';

abstract class ShuntWhisperApi {
  Future<Result<RemoteConfig>> getConfig({String? ifNoneMatch});
  Future<Result<DeviceProfile>> getDeviceProfile(String platform, String model);
  Future<Result<Map<String, dynamic>>> validateCalibration(String calibrationId);
  Future<Result<String>> submitSession(
    CapturePayload payload,
    Map<String, String> filePathsByPart, {
    ProgressCallback? onSendProgress,
  });
  Future<Result<DiagnosticResponse>> pollSession(String sessionId);
  Future<Result<Uint8List>> downloadRoi(String url);
  Future<Result<void>> deleteSession(String sessionId);
}

