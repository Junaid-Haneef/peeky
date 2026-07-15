import 'package:flutter/material.dart';

/// Collapsible, syntax-colored viewer for decoded JSON data.
///
/// Every object/array node can be expanded or collapsed individually.
/// Bump [generation] (together with [forceExpanded]) to reset all nodes to
/// a fully expanded or fully collapsed state — used by the expand-all /
/// collapse-all buttons in the body viewer.
class JsonTreeView extends StatelessWidget {
  final dynamic data;

  /// Incremented by the parent every time expand-all / collapse-all is tapped.
  final int generation;

  /// State applied to every node when [generation] changes.
  /// `null` means "use the default": expanded up to [_defaultDepth].
  final bool? forceExpanded;

  const JsonTreeView({
    super.key,
    required this.data,
    this.generation = 0,
    this.forceExpanded,
  });

  /// Nodes deeper than this start collapsed (keeps huge bodies fast).
  static const int _defaultDepth = 2;

  @override
  Widget build(BuildContext context) {
    final palette = _JsonPalette.of(context);
    return SelectionArea(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _JsonNode(
              nodeKey: null,
              value: data,
              depth: 0,
              generation: generation,
              forceExpanded: forceExpanded,
              palette: palette,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Palette ──────────────────────────────────────────────────────────────────

class _JsonPalette {
  final Color key;
  final Color string;
  final Color number;
  final Color boolean;
  final Color nil;
  final Color bracket;
  final Color summary;

  const _JsonPalette({
    required this.key,
    required this.string,
    required this.number,
    required this.boolean,
    required this.nil,
    required this.bracket,
    required this.summary,
  });

  static _JsonPalette of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark
        ? const _JsonPalette(
            key: Color(0xFF82AAFF),
            string: Color(0xFFC3E88D),
            number: Color(0xFFF78C6C),
            boolean: Color(0xFFC792EA),
            nil: Color(0xFF9E9E9E),
            bracket: Color(0xFFB0BEC5),
            summary: Color(0xFF757575),
          )
        : const _JsonPalette(
            key: Color(0xFF1565C0),
            string: Color(0xFF2E7D32),
            number: Color(0xFFE65100),
            boolean: Color(0xFF6A1B9A),
            nil: Color(0xFF757575),
            bracket: Color(0xFF546E7A),
            summary: Color(0xFF9E9E9E),
          );
  }
}

// ─── Node ─────────────────────────────────────────────────────────────────────

class _JsonNode extends StatefulWidget {
  final String? nodeKey;
  final dynamic value;
  final int depth;
  final int generation;
  final bool? forceExpanded;
  final _JsonPalette palette;

  const _JsonNode({
    required this.nodeKey,
    required this.value,
    required this.depth,
    required this.generation,
    required this.forceExpanded,
    required this.palette,
  });

  @override
  State<_JsonNode> createState() => _JsonNodeState();
}

class _JsonNodeState extends State<_JsonNode> {
  late bool _expanded;

  static const _mono = TextStyle(
    fontSize: 12,
    height: 1.5,
    fontFamily: 'monospace',
  );

  bool get _isContainer =>
      (widget.value is Map && (widget.value as Map).isNotEmpty) ||
      (widget.value is List && (widget.value as List).isNotEmpty);

  @override
  void initState() {
    super.initState();
    _expanded = _resetState();
  }

  @override
  void didUpdateWidget(covariant _JsonNode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.generation != widget.generation) {
      _expanded = _resetState();
    }
  }

  bool _resetState() =>
      widget.forceExpanded ?? widget.depth < JsonTreeView._defaultDepth;

  @override
  Widget build(BuildContext context) {
    if (!_isContainer) {
      return Padding(
        padding: const EdgeInsets.only(left: 20),
        child: Text.rich(TextSpan(children: [
          ..._keySpans(),
          _valueSpan(widget.value),
        ])),
      );
    }

    final isMap = widget.value is Map;
    final count = isMap
        ? (widget.value as Map).length
        : (widget.value as List).length;
    final p = widget.palette;

    final header = InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _expanded ? Icons.arrow_drop_down : Icons.arrow_right,
            size: 20,
            color: p.summary,
          ),
          Text.rich(TextSpan(children: [
            ..._keySpans(),
            TextSpan(
              text: isMap ? '{' : '[',
              style: _mono.copyWith(color: p.bracket),
            ),
            if (!_expanded)
              TextSpan(
                text: ' … ${isMap ? '}' : ']'}',
                style: _mono.copyWith(color: p.bracket),
              ),
            TextSpan(
              text: isMap
                  ? '  $count ${count == 1 ? 'field' : 'fields'}'
                  : '  $count ${count == 1 ? 'item' : 'items'}',
              style: _mono.copyWith(color: p.summary, fontSize: 11),
            ),
          ])),
        ],
      ),
    );

    if (!_expanded) {
      return header;
    }

    final children = <Widget>[];
    if (isMap) {
      for (final e in (widget.value as Map).entries) {
        children.add(_child('${e.key}', e.value));
      }
    } else {
      final list = widget.value as List;
      for (var i = 0; i < list.length; i++) {
        children.add(_child('$i', list[i]));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        Padding(
          padding: const EdgeInsets.only(left: 9),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: p.summary.withValues(alpha: 0.25)),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 20),
          child: Text(isMap ? '}' : ']',
              style: _mono.copyWith(color: p.bracket)),
        ),
      ],
    );
  }

  Widget _child(String key, dynamic value) {
    return _JsonNode(
      nodeKey: key,
      value: value,
      depth: widget.depth + 1,
      generation: widget.generation,
      forceExpanded: widget.forceExpanded,
      palette: widget.palette,
    );
  }

  List<TextSpan> _keySpans() {
    if (widget.nodeKey == null) {
      return const [];
    }
    return [
      TextSpan(
        text: '"${widget.nodeKey}"',
        style: _mono.copyWith(color: widget.palette.key),
      ),
      TextSpan(text: ': ', style: _mono.copyWith(color: widget.palette.bracket)),
    ];
  }

  TextSpan _valueSpan(dynamic value) {
    final p = widget.palette;
    if (value == null) {
      return TextSpan(text: 'null', style: _mono.copyWith(color: p.nil));
    }
    if (value is bool) {
      return TextSpan(text: '$value', style: _mono.copyWith(color: p.boolean));
    }
    if (value is num) {
      return TextSpan(text: '$value', style: _mono.copyWith(color: p.number));
    }
    if (value is Map) {
      return TextSpan(text: '{}', style: _mono.copyWith(color: p.bracket));
    }
    if (value is List) {
      return TextSpan(text: '[]', style: _mono.copyWith(color: p.bracket));
    }
    return TextSpan(
      text: '"$value"',
      style: _mono.copyWith(color: p.string),
    );
  }
}
