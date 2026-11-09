import 'dart:math';
import 'package:dio/dio.dart';

/// Exponential backoff retry interceptor for Dio.
/// Retries ONLY on connection timeouts, 5xx server errors, and 429 rate limits.
class RetryInterceptor extends Interceptor {
  final Dio dio;
  final int maxRetries;
  final List<int> baseDelaysSeconds;
  final Future<void> Function(Duration)? sleeper;
  final Random _rng = Random();

  RetryInterceptor({
    required this.dio,
    this.maxRetries = 4,
    this.baseDelaysSeconds = const [2, 4, 8, 16],
    this.sleeper,
  });

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final requestOptions = err.requestOptions;
    final int attempt = (requestOptions.extra['retry_attempt'] as int? ?? 0);

    if (!_shouldRetry(err) || attempt >= maxRetries) {
      return handler.next(err);
    }

    final int nextAttempt = attempt + 1;
    requestOptions.extra['retry_attempt'] = nextAttempt;

    Duration delay = _calculateDelay(attempt, err.response);
    if (sleeper != null) {
      await sleeper!(delay);
    } else {
      await Future<void>.delayed(delay);
    }

    try {
      final response = await dio.fetch(requestOptions);
      return handler.resolve(response);
    } on DioException catch (e) {
      return handler.next(e);
    }
  }

  bool _shouldRetry(DioException err) {
    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError) {
      return true;
    }

    final statusCode = err.response?.statusCode;
    if (statusCode == null) return false;

    // Retry on 429 Rate Limited or 5xx Server Errors
    if (statusCode == 429 || (statusCode >= 500 && statusCode < 600)) {
      return true;
    }

    return false;
  }

  Duration _calculateDelay(int attempt, Response? response) {
    // Check Retry-After header
    final retryAfterHeader = response?.headers.value('retry-after');
    if (retryAfterHeader != null) {
      final seconds = int.tryParse(retryAfterHeader);
      if (seconds != null) {
        return Duration(seconds: seconds);
      }
    }

    final baseSec = attempt < baseDelaysSeconds.length
        ? baseDelaysSeconds[attempt]
        : baseDelaysSeconds.last;

    // ±20% jitter
    final jitterMultiplier = 0.8 + 0.4 * _rng.nextDouble();
    final delayMs = (baseSec * 1000 * jitterMultiplier).toInt();
    return Duration(milliseconds: delayMs);
  }
}

