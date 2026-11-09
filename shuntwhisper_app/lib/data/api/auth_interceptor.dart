import 'package:dio/dio.dart';

/// Interceptor that attaches the Bearer token to all outgoing HTTP requests.
class AuthInterceptor extends Interceptor {
  final Future<String?> Function() tokenProvider;

  AuthInterceptor({required this.tokenProvider});

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await tokenProvider();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    return handler.next(options);
  }
}

