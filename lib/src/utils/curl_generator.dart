import '../models/inspector_log.dart';

/// Generates a runnable cURL command from an [InspectorLog].
class CurlGenerator {
  CurlGenerator._();

  static String generate(InspectorLog log) {
    final buf = StringBuffer('curl -X ${log.method}');

    log.requestHeaders.forEach((key, value) {
      final escaped = value.replaceAll('"', r'\"');
      buf.write(' \\\n  -H "$key: $escaped"');
    });

    if (log.requestBody != null && log.requestBody!.isNotEmpty) {
      final escaped = log.requestBody!.replaceAll("'", "'\\''");
      buf.write(" \\\n  -d '$escaped'");
    }

    buf.write(' \\\n  "${log.url}"');
    return buf.toString();
  }
}
