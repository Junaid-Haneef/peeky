import 'package:dio/dio.dart';

import '../store/peeky_store.dart';

const _kId = '_peeky_id';
const _kStart = '_peeky_start';

/// A Dio [Interceptor] that captures every request and response into
/// [PeekyStore], making them visible in the Peeky inspector panel.
///
/// ## Usage
///
/// ```dart
/// dio.interceptors.add(PeekyDioInterceptor());
/// ```
class PeekyDioInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final body = options.data?.toString();

    final log = PeekyStore.instance.addRequest(
      method: options.method,
      url: options.uri.toString(),
      requestHeaders:
          options.headers.map((k, v) => MapEntry(k.toString(), v.toString())),
      requestBody: body,
    );

    options.extra[_kId] = log.id;
    options.extra[_kStart] = DateTime.now();
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final id = response.requestOptions.extra[_kId] as String?;
    final start = response.requestOptions.extra[_kStart] as DateTime?;

    if (id != null) {
      PeekyStore.instance.updateResponse(
        id: id,
        statusCode: response.statusCode ?? 0,
        responseHeaders:
            response.headers.map.map((k, v) => MapEntry(k, v.join(', '))),
        responseBody: response.data?.toString() ?? '',
        duration:
            start != null ? DateTime.now().difference(start) : Duration.zero,
      );
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final id = err.requestOptions.extra[_kId] as String?;
    final start = err.requestOptions.extra[_kStart] as DateTime?;

    if (id != null) {
      PeekyStore.instance.updateError(
        id: id,
        error: err.message ?? err.type.name,
        statusCode: err.response?.statusCode,
        responseBody: err.response?.data?.toString(),
        duration: start != null ? DateTime.now().difference(start) : null,
      );
    }
    handler.next(err);
  }
}
