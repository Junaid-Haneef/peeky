import 'dart:convert';

import 'package:http/http.dart' as http;

import '../store/peeky_store.dart';

/// A drop-in [http.Client] wrapper that captures every request and response
/// into [PeekyStore], making them visible in the Peeky inspector panel.
///
/// ## Usage
///
/// Wrap your existing [http.Client] once — all requests through it are
/// automatically captured:
///
/// ```dart
/// // Before
/// RestClient(httpClient: http.Client(), ...)
///
/// // After — one word change
/// RestClient(httpClient: PeekyHttpClient(http.Client()), ...)
/// ```
class PeekyHttpClient extends http.BaseClient {
  final http.Client _inner;

  PeekyHttpClient([http.Client? inner]) : _inner = inner ?? http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final startTime = DateTime.now();

    String? requestBody;
    if (request is http.Request && request.body.isNotEmpty) {
      requestBody = request.body;
    } else if (request is http.MultipartRequest) {
      requestBody = '[multipart/form-data — ${request.files.length} file(s), '
          '${request.fields.length} field(s)]';
    }

    final log = PeekyStore.instance.addRequest(
      method: request.method,
      url: request.url.toString(),
      requestHeaders: request.headers,
      requestBody: requestBody,
    );

    try {
      final response = await _inner.send(request);

      // The response body is a one-time-read stream.
      // We capture the bytes, record them, then rebuild the stream
      // so the caller receives an identical response.
      final bytes = await response.stream.toBytes();
      final duration = DateTime.now().difference(startTime);

      String responseBody;
      try {
        responseBody = utf8.decode(bytes);
      } catch (_) {
        responseBody = '[binary — ${bytes.length} bytes]';
      }

      PeekyStore.instance.updateResponse(
        id: log.id,
        statusCode: response.statusCode,
        responseHeaders: response.headers,
        responseBody: responseBody,
        duration: duration,
      );

      return http.StreamedResponse(
        Stream.value(bytes),
        response.statusCode,
        headers: response.headers,
        reasonPhrase: response.reasonPhrase,
        contentLength: bytes.length,
        request: response.request,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
      );
    } catch (e) {
      PeekyStore.instance.updateError(
        id: log.id,
        error: e.toString(),
        duration: DateTime.now().difference(startTime),
      );
      rethrow;
    }
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
