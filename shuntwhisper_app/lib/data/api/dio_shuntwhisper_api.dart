import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../core/result.dart';
import '../../domain/models/config_models.dart';
import '../../domain/models/diagnostic_models.dart';
import '../../domain/models/payload_models.dart';
import 'shuntwhisper_api.dart';
import 'auth_interceptor.dart';
import 'retry_interceptor.dart';
import 'problem_details.dart';

class DioShuntwhisperApi implements ShuntWhisperApi {
  final Dio dio;

  DioShuntwhisperApi({
    required String baseUrl,
    required Future<String?> Function() tokenProvider,
    Dio? customDio,
    Future<void> Function(Duration)? sleeper,
  }) : dio = customDio ?? Dio() {
    dio.options.baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), '');
    dio.options.connectTimeout = const Duration(seconds: 10);
    dio.options.receiveTimeout = const Duration(seconds: 30);
    dio.options.sendTimeout = const Duration(seconds: 120);

    dio.interceptors.add(AuthInterceptor(tokenProvider: tokenProvider));
    dio.interceptors.add(RetryInterceptor(dio: dio, sleeper: sleeper));
  }

  Failure _mapDioError(DioException e) {
    if (e.response != null && e.response?.data != null) {
      final data = e.response!.data;
      if (data is Map<String, dynamic>) {
        final problem = ProblemDetails.fromJson(data);
        return Failure(
          code: problem.code,
          message: problem.detail ?? problem.title,
          details: problem,
        );
      }
    }

    return switch (e.type) {
      DioExceptionType.connectionTimeout =>
        const Failure(code: 'NETWORK_TIMEOUT', message: 'Connection timed out'),
      DioExceptionType.sendTimeout =>
        const Failure(code: 'NETWORK_TIMEOUT', message: 'Upload timed out'),
      DioExceptionType.receiveTimeout =>
        const Failure(code: 'NETWORK_TIMEOUT', message: 'Server response timed out'),
      DioExceptionType.connectionError =>
        const Failure(code: 'NETWORK_OFFLINE', message: 'No network connection available'),
      _ => Failure(code: 'NETWORK_ERROR', message: e.message ?? 'Unknown network failure'),
    };
  }

  @override
  Future<Result<RemoteConfig>> getConfig({String? ifNoneMatch}) async {
    try {
      final headers = <String, dynamic>{};
      if (ifNoneMatch != null) {
        headers['If-None-Match'] = ifNoneMatch;
      }

      final res = await dio.get('/v1/config', options: Options(headers: headers));
      if (res.statusCode == 304) {
        return const Err(Failure(code: 'NOT_MODIFIED', message: 'Configuration has not changed'));
      }

      final config = RemoteConfig.fromJson(res.data);
      return Ok(config);
    } on DioException catch (e) {
      return Err(_mapDioError(e));
    } catch (e) {
      return Err(Failure(code: 'PARSE_ERROR', message: e.toString()));
    }
  }

  @override
  Future<Result<DeviceProfile>> getDeviceProfile(String platform, String model) async {
    try {
      final res = await dio.get('/v1/device-profiles/$platform/$model');
      final profile = DeviceProfile.fromJson(res.data);
      return Ok(profile);
    } on DioException catch (e) {
      return Err(_mapDioError(e));
    } catch (e) {
      return Err(Failure(code: 'PARSE_ERROR', message: e.toString()));
    }
  }

  @override
  Future<Result<Map<String, dynamic>>> validateCalibration(String calibrationId) async {
    try {
      final res = await dio.get('/v1/calibrations/$calibrationId');
      return Ok(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      return Err(_mapDioError(e));
    } catch (e) {
      return Err(Failure(code: 'PARSE_ERROR', message: e.toString()));
    }
  }

  @override
  Future<Result<String>> submitSession(
    CapturePayload payload,
    Map<String, String> filePathsByPart, {
    ProgressCallback? onSendProgress,
  }) async {
    try {
      final Map<String, dynamic> formMap = {
        'metadata': MultipartFile.fromString(
          jsonEncode(payload.toJson()),
          contentType: DioMediaType('application', 'json'),
        ),
      };

      for (final entry in filePathsByPart.entries) {
        final partName = entry.key; // 'baseline', 't23', 't120'
        final filePath = entry.value;
        formMap[partName] = await MultipartFile.fromFile(
          filePath,
          filename: '$partName.png',
          contentType: DioMediaType('image', 'png'),
        );
      }

      final formData = FormData.fromMap(formMap);

      final res = await dio.post(
        '/v1/sessions',
        data: formData,
        options: Options(
          headers: {'Idempotency-Key': payload.sessionId},
        ),
        onSendProgress: onSendProgress,
      );

      final ack = res.data as Map<String, dynamic>;
      final sessionId = ack['sessionId'] ?? ack['session_id'];
      return Ok(sessionId.toString());
    } on DioException catch (e) {
      return Err(_mapDioError(e));
    } catch (e) {
      return Err(Failure(code: 'UPLOAD_ERROR', message: e.toString()));
    }
  }

  @override
  Future<Result<DiagnosticResponse>> pollSession(String sessionId) async {
    try {
      final res = await dio.get('/v1/sessions/$sessionId');
      final response = DiagnosticResponse.fromJson(res.data);
      return Ok(response);
    } on DioException catch (e) {
      return Err(_mapDioError(e));
    } catch (e) {
      return Err(Failure(code: 'PARSE_ERROR', message: e.toString()));
    }
  }

  @override
  Future<Result<Uint8List>> downloadRoi(String url) async {
    try {
      final res = await dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      return Ok(Uint8List.fromList(res.data!));
    } on DioException catch (e) {
      return Err(_mapDioError(e));
    } catch (e) {
      return Err(Failure(code: 'DOWNLOAD_ERROR', message: e.toString()));
    }
  }

  @override
  Future<Result<void>> deleteSession(String sessionId) async {
    try {
      await dio.delete('/v1/sessions/$sessionId');
      return const Ok(null);
    } on DioException catch (e) {
      return Err(_mapDioError(e));
    } catch (e) {
      return Err(Failure(code: 'DELETE_ERROR', message: e.toString()));
    }
  }
}

