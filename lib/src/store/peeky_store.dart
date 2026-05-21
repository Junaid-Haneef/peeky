import 'dart:async';

import '../models/inspector_log.dart';

/// Singleton ring-buffer that stores all captured network logs and Flutter errors.
///
/// Both [PeekyHttpClient] and [PeekyDioInterceptor] write to this store.
/// The UI subscribes to [logStream] and [errorStream] for live updates.
class PeekyStore {
  PeekyStore._();
  static final PeekyStore instance = PeekyStore._();

  int _maxSize = 200;
  bool _enabled = false;

  final _logs = <InspectorLog>[];
  final _errors = <InspectorErrorLog>[];

  final _logController = StreamController<List<InspectorLog>>.broadcast();
  final _errorController =
      StreamController<List<InspectorErrorLog>>.broadcast();

  /// Live stream of logs — newest first.
  Stream<List<InspectorLog>> get logStream => _logController.stream;

  /// Live stream of Flutter/Dart errors.
  Stream<List<InspectorErrorLog>> get errorStream => _errorController.stream;

  /// Current snapshot of logs (newest first).
  List<InspectorLog> get logs => List.unmodifiable(_logs.reversed.toList());

  /// Current snapshot of errors (newest first).
  List<InspectorErrorLog> get errors =>
      List.unmodifiable(_errors.reversed.toList());

  /// Called once from [Peeky] widget to activate the store and set ring-buffer size.
  /// Until this is called (or when [enabled] is false) all write operations are no-ops.
  void configure({int maxSize = 200, bool enabled = true}) {
    _maxSize = maxSize;
    _enabled = enabled;
  }

  // ── Called by http client / Dio interceptor ──────────────────────────────

  InspectorLog addRequest({
    required String method,
    required String url,
    Map<String, String> requestHeaders = const {},
    String? requestBody,
  }) {
    if (!_enabled)
      return InspectorLog(method: method, url: url, requestHeaders: const {});
    final log = InspectorLog(
      method: method,
      url: url,
      requestHeaders: requestHeaders,
      requestBody: requestBody,
    );
    _logs.add(log);
    if (_logs.length > _maxSize) _logs.removeAt(0);
    _notifyLogs();
    return log;
  }

  void updateResponse({
    required String id,
    required int statusCode,
    required Map<String, String> responseHeaders,
    required String responseBody,
    required Duration duration,
  }) {
    if (!_enabled) return;
    final log = _findById(id);
    if (log == null) return;
    log.statusCode = statusCode;
    log.responseHeaders = responseHeaders;
    log.responseBody = responseBody;
    log.duration = duration;
    _notifyLogs();
  }

  void updateError({
    required String id,
    required String error,
    int? statusCode,
    String? responseBody,
    Duration? duration,
  }) {
    if (!_enabled) return;
    final log = _findById(id);
    if (log == null) return;
    log.error = error;
    log.statusCode = statusCode;
    log.responseBody = responseBody;
    log.duration = duration;
    _notifyLogs();
  }

  void addFlutterError(String message, StackTrace? stack) {
    if (!_enabled) return;
    _errors.add(InspectorErrorLog(
      message: message,
      stackTrace: stack?.toString(),
    ));
    if (_errors.length > _maxSize) _errors.removeAt(0);
    _errorController.add(errors);
  }

  void clearLogs() {
    _logs.clear();
    _notifyLogs();
  }

  void clearErrors() {
    _errors.clear();
    _errorController.add(errors);
  }

  // ─────────────────────────────────────────────────────────────────────────

  InspectorLog? _findById(String id) {
    try {
      return _logs.lastWhere((l) => l.id == id);
    } catch (_) {
      return null;
    }
  }

  void _notifyLogs() => _logController.add(logs);
}
