import 'dart:convert';

/// Kind of content held in a request/response body, used to decide which
/// view modes the body viewer offers.
enum BodyKind { json, xml, text }

/// Detection and formatting helpers for request/response bodies.
class BodyFormatter {
  BodyFormatter._();

  /// Detects whether [body] is JSON, XML/HTML, or plain text.
  static BodyKind detect(String body) {
    final t = body.trimLeft();
    if (t.startsWith('{') || t.startsWith('[')) {
      try {
        jsonDecode(body);
        return BodyKind.json;
      } catch (_) {
        return BodyKind.text;
      }
    }
    if (t.startsWith('<')) {
      return BodyKind.xml;
    }
    return BodyKind.text;
  }

  /// Pretty-prints XML/HTML with 2-space indentation.
  /// Best-effort: returns [input] unchanged when it cannot be tokenized.
  static String formatXml(String input) {
    final tokens = <String>[];
    final buf = StringBuffer();
    var inTag = false;
    for (var i = 0; i < input.length; i++) {
      final c = input[i];
      if (c == '<') {
        final text = buf.toString().trim();
        if (text.isNotEmpty) {
          tokens.add(text);
        }
        buf.clear();
        inTag = true;
        buf.write(c);
      } else if (c == '>' && inTag) {
        buf.write(c);
        tokens.add(buf.toString());
        buf.clear();
        inTag = false;
      } else {
        buf.write(c);
      }
    }
    final tail = buf.toString().trim();
    if (tail.isNotEmpty) {
      // Unbalanced '<' — give up rather than emit mangled output.
      return input;
    }

    final out = StringBuffer();
    var depth = 0;
    for (var i = 0; i < tokens.length; i++) {
      final tok = tokens[i];
      final isTag = tok.startsWith('<');
      final isClose = tok.startsWith('</');
      final isSelfContained = !isTag ||
          tok.endsWith('/>') ||
          tok.startsWith('<?') ||
          tok.startsWith('<!');

      if (isClose && depth > 0) {
        depth--;
      }

      // Collapse <tag>text</tag> onto one line for readability.
      if (isTag && !isClose && !isSelfContained) {
        final next = i + 1 < tokens.length ? tokens[i + 1] : null;
        final after = i + 2 < tokens.length ? tokens[i + 2] : null;
        if (next != null &&
            !next.startsWith('<') &&
            after != null &&
            after.startsWith('</')) {
          out.writeln('${'  ' * depth}$tok$next$after');
          i += 2;
          continue;
        }
      }

      out.writeln('${'  ' * depth}$tok');

      if (isTag && !isClose && !isSelfContained) {
        depth++;
      }
    }
    return out.toString().trimRight();
  }

  /// Human-readable byte size, e.g. `312 B`, `4.2 KB`, `1.3 MB`.
  static String sizeLabel(String body) {
    final bytes = utf8.encode(body).length;
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
