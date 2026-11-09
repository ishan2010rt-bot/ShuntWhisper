import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:shuntwhisper_app/core/result.dart';
import 'package:shuntwhisper_app/domain/models/camera_models.dart';
import 'package:shuntwhisper_app/domain/models/alignment_models.dart';
import 'package:shuntwhisper_app/domain/models/payload_models.dart';
import 'camera_service.dart';
import 'readback_verifier.dart';
import 'frame_validator.dart';

class CameraServiceImpl implements CameraService {
  static const MethodChannel _channel = MethodChannel('com.shuntwhisper.camera/methods');
  static const EventChannel _lumaChannel = EventChannel('com.shuntwhisper.camera/luma_stream');

  final StreamController<FiducialAlignmentState> _alignmentController = StreamController.broadcast();
  final StreamController<Uint8List> _lumaController = StreamController.broadcast();
  final FrameValidator _frameValidator;

  CameraHardwareConfig? _lastConfig;
  StreamSubscription? _lumaSub;

  CameraServiceImpl({FrameValidator? frameValidator})
      : _frameValidator = frameValidator ?? const FrameValidator();

  @override
  Stream<FiducialAlignmentState> get alignmentStream => _alignmentController.stream;

  @override
  Stream<Uint8List> get lumaFrameStream => _lumaController.stream;

  @override
  Future<Result<CameraCapabilities>> getCapabilities() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('getCapabilities');
      if (res == null) {
        return const Err(Failure(code: 'CAMERA_NOT_FOUND', message: 'Unable to query camera capabilities'));
      }
      return Ok(CameraCapabilities.fromJson(res));
    } on PlatformException catch (e) {
      return Err(Failure(code: e.code, message: e.message ?? 'Capabilities query failed'));
    }
  }

  @override
  Future<Result<AppliedCameraState>> initialize(CameraHardwareConfig config) async {
    _lastConfig = config;
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('initialize', config.toJson());
      if (res == null) {
        return const Err(Failure(code: 'INIT_FAILED', message: 'Camera initialization returned null'));
      }
      final rawApplied = AppliedCameraState.fromJson(res);
      final verified = ReadbackVerifier.verify(requested: config, actual: rawApplied);
      return Ok(verified);
    } on PlatformException catch (e) {
      return Err(Failure(code: e.code, message: e.message ?? 'Initialization failed'));
    }
  }

  @override
  Future<Result<AppliedCameraState>> applyConfig(CameraHardwareConfig config) async {
    _lastConfig = config;
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('applyConfig', config.toJson());
      if (res == null) {
        return const Err(Failure(code: 'CONFIG_FAILED', message: 'Apply config returned null'));
      }
      final rawApplied = AppliedCameraState.fromJson(res);
      final verified = ReadbackVerifier.verify(requested: config, actual: rawApplied);
      return Ok(verified);
    } on PlatformException catch (e) {
      return Err(Failure(code: e.code, message: e.message ?? 'Apply config failed'));
    }
  }

  @override
  Future<Result<void>> setTorch(TorchMode mode, double level) async {
    try {
      await _channel.invokeMethod('setTorch', {
        'mode': mode.toWire(),
        'level': level,
      });
      return const Ok(null);
    } on PlatformException catch (e) {
      return Err(Failure(code: e.code, message: e.message ?? 'Set torch failed'));
    }
  }

  @override
  Future<Result<List<CapturedImageMeta>>> captureBurst({int burstCount = 3}) async {
    try {
      final res = await _channel.invokeListMethod<Map<dynamic, dynamic>>('captureBurst', {
        'burstCount': burstCount,
      });
      if (res == null || res.isEmpty) {
        return const Err(Failure(code: 'CAPTURE_EMPTY', message: 'Burst capture returned no frames'));
      }

      final List<CapturedImageMeta> results = [];
      for (int i = 0; i < res.length; i++) {
        final item = Map<String, dynamic>.from(res[i]);
        results.add(CapturedImageMeta.fromJson(item));
      }
      return Ok(results);
    } on PlatformException catch (e) {
      return Err(Failure(code: e.code, message: e.message ?? 'Burst capture failed'));
    }
  }

  @override
  Future<void> startPreviewAnalysis() async {
    await _channel.invokeMethod('startPreviewAnalysis');
    _lumaSub?.cancel();
    _lumaSub = _lumaChannel.receiveBroadcastStream().listen((dynamic event) {
      if (event is Uint8List) {
        _lumaController.add(event);
      }
    });
  }

  @override
  Future<void> stopPreviewAnalysis() async {
    await _lumaSub?.cancel();
    _lumaSub = null;
    await _channel.invokeMethod('stopPreviewAnalysis');
  }

  @override
  Future<void> dispose() async {
    await stopPreviewAnalysis();
    await _channel.invokeMethod('dispose');
    await _alignmentController.close();
    await _lumaController.close();
  }
}

