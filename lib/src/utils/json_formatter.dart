import 'dart:convert';

/// Attempts to pretty-print a JSON string with 2-space indentation.
/// Returns the original string unchanged if it is not valid JSON.
class JsonFormatter {
  JsonFormatter._();

  static const _encoder = JsonEncoder.withIndent('  ');

  static String tryFormat(String? input) {
    if (input == null || input.isEmpty) {
      return '';
    }
    try {
      return _encoder.convert(jsonDecode(input));
    } catch (_) {
      return input;
    }
  }

  static bool looksLikeJson(String? input) {
    if (input == null || input.isEmpty) {
      return false;
    }
    final t = input.trimLeft();
    return t.startsWith('{') || t.startsWith('[');
  }
}
