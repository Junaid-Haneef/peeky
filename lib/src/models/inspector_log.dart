/// A single captured network request + response pair.
///
/// Created when a request starts ([isPending] = true).
/// Updated in-place when the response arrives or an error occurs.
class InspectorLog {
  static int _counter = 0;

  final String id;
  final DateTime timestamp;
  final String method;
  final String url;
  final Map<String, String> requestHeaders;
  final String? requestBody;

  // Populated once the response arrives
  int? statusCode;
  Map<String, String>? responseHeaders;
  String? responseBody;
  Duration? duration;
  String? error;

  InspectorLog({
    required this.method,
    required this.url,
    required this.requestHeaders,
    this.requestBody,
  })  : id = (++_counter).toString(),
        timestamp = DateTime.now();

  bool get isPending => statusCode == null && error == null;
  bool get isNetworkError => error != null && statusCode == null;
  bool get isError =>
      isNetworkError || (statusCode != null && statusCode! >= 400);
  bool get isSuccess => statusCode != null && statusCode! < 300;
  bool get isRedirect =>
      statusCode != null && statusCode! >= 300 && statusCode! < 400;

  String get statusLabel {
    if (isPending) return '...';
    if (isNetworkError) return 'ERR';
    return statusCode.toString();
  }

  String get durationLabel {
    if (duration == null) return '-';
    final ms = duration!.inMilliseconds;
    return ms >= 1000 ? '${(ms / 1000).toStringAsFixed(1)}s' : '${ms}ms';
  }

  /// Short path portion of the URL for compact list display.
  String get shortUrl {
    try {
      return Uri.parse(url).path.isNotEmpty ? Uri.parse(url).path : url;
    } catch (_) {
      return url;
    }
  }
}

/// A captured Flutter widget / Dart error.
class InspectorErrorLog {
  final String id;
  final DateTime timestamp;
  final String message;
  final String? stackTrace;

  InspectorErrorLog({required this.message, this.stackTrace})
      : id = DateTime.now().microsecondsSinceEpoch.toString(),
        timestamp = DateTime.now();
}
