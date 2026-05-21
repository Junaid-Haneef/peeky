import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/inspector_log.dart';
import '../store/peeky_store.dart';
import '../utils/curl_generator.dart';
import '../utils/json_formatter.dart';

// ─── Tab / Filter enums ───────────────────────────────────────────────────────

enum _PanelTab { network, errors }

enum _Filter { all, s2xx, s4xx, s5xx, err }

extension _FilterLabel on _Filter {
  String get label => switch (this) {
        _Filter.all => 'ALL',
        _Filter.s2xx => '2xx',
        _Filter.s4xx => '4xx',
        _Filter.s5xx => '5xx',
        _Filter.err => 'ERR',
      };
}

// ─── Root panel ───────────────────────────────────────────────────────────────

/// Full-screen inspector panel — no Scaffold, no Navigator/Overlay dependency.
/// Safe to use inside [MaterialApp.builder] (outside the Navigator).
class PeekyPanel extends StatefulWidget {
  final VoidCallback onClose;
  const PeekyPanel({super.key, required this.onClose});

  @override
  State<PeekyPanel> createState() => _PeekyPanelState();
}

class _PeekyPanelState extends State<PeekyPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;

  _PanelTab _tab = _PanelTab.network;
  _Filter _filter = _Filter.all;
  String _search = '';

  // Inline navigation state (no Navigator needed)
  InspectorLog? _selectedLog;
  InspectorErrorLog? _selectedError;

  // Widget-based toast (no ScaffoldMessenger/Overlay needed)
  String? _toastMsg;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280))
      ..forward();
    _slide = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    await _ctrl.reverse();
    widget.onClose();
  }

  void _toast(String msg) {
    _toastTimer?.cancel();
    setState(() => _toastMsg = msg);
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _toastMsg = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          // Back button: let the sub-views navigate back first, then close.
          if (_selectedLog != null) {
            setState(() => _selectedLog = null);
          } else if (_selectedError != null) {
            setState(() => _selectedError = null);
          } else {
            _close();
          }
        }
      },
      child: SlideTransition(
        position: _slide,
        child: Material(
          color: cs.surface,
          child: SafeArea(
            child: Stack(
              children: [
                if (_selectedLog != null)
                  _DetailView(
                    log: _selectedLog!,
                    onBack: () => setState(() => _selectedLog = null),
                    onToast: _toast,
                  )
                else if (_selectedError != null)
                  _ErrorDetailView(
                    error: _selectedError!,
                    onBack: () => setState(() => _selectedError = null),
                    onToast: _toast,
                  )
                else
                  _buildListView(cs),
                if (_toastMsg != null)
                  Positioned(
                    bottom: 20,
                    left: 20,
                    right: 20,
                    child: _PeekyToast(message: _toastMsg!),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildListView(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header — close button always visible via Spacer
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 4, 0),
          child: Row(
            children: [
              const Text('👀', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              const Text('Peeky',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(width: 6),
              StreamBuilder<List<InspectorErrorLog>>(
                stream: PeekyStore.instance.errorStream,
                initialData: PeekyStore.instance.errors,
                builder: (_, snap) {
                  final count = snap.data?.length ?? 0;
                  if (count == 0) return const SizedBox.shrink();
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('$count',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 10)),
                  );
                },
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: 'Clear',
                onPressed: () {
                  if (_tab == _PanelTab.network) {
                    PeekyStore.instance.clearLogs();
                  } else {
                    PeekyStore.instance.clearErrors();
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: _close,
              ),
            ],
          ),
        ),
        Row(
          children: [
            _TabBtn(
              label: 'Network',
              active: _tab == _PanelTab.network,
              onTap: () => setState(() {
                _tab = _PanelTab.network;
                _search = '';
              }),
            ),
            _TabBtn(
              label: 'Errors',
              active: _tab == _PanelTab.errors,
              onTap: () => setState(() => _tab = _PanelTab.errors),
            ),
          ],
        ),
        const Divider(height: 1),
        if (_tab == _PanelTab.network)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
            child: TextField(
              onChanged: (s) => setState(() => _search = s),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search URL...',
                prefixIcon: const Icon(Icons.search, size: 18),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              ),
            ),
          ),
        Expanded(
          child: _tab == _PanelTab.network
              ? _NetworkList(
                  filter: _filter,
                  search: _search,
                  onFilterChanged: (f) => setState(() => _filter = f),
                  onLogTap: (log) => setState(() => _selectedLog = log),
                )
              : _ErrorList(
                  onErrorTap: (e) => setState(() => _selectedError = e),
                ),
        ),
      ],
    );
  }
}

// ─── Tab button ───────────────────────────────────────────────────────────────

class _TabBtn extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _TabBtn(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? cs.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
            color: active ? cs.primary : cs.onSurface.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }
}

// ─── Network list ─────────────────────────────────────────────────────────────

class _NetworkList extends StatelessWidget {
  final _Filter filter;
  final String search;
  final ValueChanged<_Filter> onFilterChanged;
  final ValueChanged<InspectorLog> onLogTap;

  const _NetworkList({
    required this.filter,
    required this.search,
    required this.onFilterChanged,
    required this.onLogTap,
  });

  List<InspectorLog> _apply(List<InspectorLog> all) {
    return all.where((l) {
      if (search.isNotEmpty &&
          !l.url.toLowerCase().contains(search.toLowerCase())) {
        return false;
      }
      return switch (filter) {
        _Filter.all => true,
        _Filter.s2xx =>
          l.statusCode != null && l.statusCode! >= 200 && l.statusCode! < 300,
        _Filter.s4xx =>
          l.statusCode != null && l.statusCode! >= 400 && l.statusCode! < 500,
        _Filter.s5xx => l.statusCode != null && l.statusCode! >= 500,
        _Filter.err => l.isNetworkError,
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: _Filter.values
                .map((f) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label:
                            Text(f.label, style: const TextStyle(fontSize: 12)),
                        selected: filter == f,
                        onSelected: (_) => onFilterChanged(f),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                      ),
                    ))
                .toList(),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<InspectorLog>>(
            stream: PeekyStore.instance.logStream,
            initialData: PeekyStore.instance.logs,
            builder: (_, snap) {
              final filtered = _apply(snap.data ?? []);
              if (filtered.isEmpty) {
                return const Center(
                  child: Text(
                    'No requests yet.\nMake an API call.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }
              return ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) =>
                    _LogTile(log: filtered[i], onTap: onLogTap),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── Log tile ─────────────────────────────────────────────────────────────────

class _LogTile extends StatelessWidget {
  final InspectorLog log;
  final ValueChanged<InspectorLog> onTap;

  const _LogTile({required this.log, required this.onTap});

  Color _color() {
    if (log.isNetworkError) return Colors.red;
    if (log.isPending) return Colors.grey;
    final s = log.statusCode!;
    if (s < 300) return Colors.green;
    if (s < 400) return Colors.blue;
    if (s < 500) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final color = _color();
    return InkWell(
      onTap: () => onTap(log),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 46,
              padding: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                log.method,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.bold, color: color),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                log.shortUrl,
                style: const TextStyle(fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(log.statusLabel,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: color)),
                Text(log.durationLabel,
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Error list ───────────────────────────────────────────────────────────────

class _ErrorList extends StatelessWidget {
  final ValueChanged<InspectorErrorLog> onErrorTap;

  const _ErrorList({required this.onErrorTap});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<InspectorErrorLog>>(
      stream: PeekyStore.instance.errorStream,
      initialData: PeekyStore.instance.errors,
      builder: (_, snap) {
        final list = snap.data ?? [];
        if (list.isEmpty) {
          return const Center(
            child: Text('No Flutter errors captured.',
                style: TextStyle(color: Colors.grey)),
          );
        }
        return ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final e = list[i];
            final time = '${e.timestamp.hour.toString().padLeft(2, '0')}:'
                '${e.timestamp.minute.toString().padLeft(2, '0')}:'
                '${e.timestamp.second.toString().padLeft(2, '0')}';
            return ListTile(
              leading: const Icon(Icons.error_outline, color: Colors.red),
              title: Text(e.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13)),
              subtitle: Text(time, style: const TextStyle(fontSize: 11)),
              trailing: e.stackTrace != null
                  ? const Icon(Icons.chevron_right, size: 18)
                  : null,
              onTap: e.stackTrace != null ? () => onErrorTap(e) : null,
            );
          },
        );
      },
    );
  }
}

// ─── Error detail view ────────────────────────────────────────────────────────

class _ErrorDetailView extends StatelessWidget {
  final InspectorErrorLog error;
  final VoidCallback onBack;
  final ValueChanged<String> onToast;

  const _ErrorDetailView({
    required this.error,
    required this.onBack,
    required this.onToast,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: onBack,
              ),
              Expanded(
                child: Text(
                  error.message,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: 'Copy',
                onPressed: () {
                  Clipboard.setData(ClipboardData(
                      text: '${error.message}\n\n${error.stackTrace}'));
                  onToast('Copied to clipboard');
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              error.stackTrace ?? '',
              style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: Colors.red.shade700),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Network detail view ──────────────────────────────────────────────────────

class _DetailView extends StatefulWidget {
  final InspectorLog log;
  final VoidCallback onBack;
  final ValueChanged<String> onToast;

  const _DetailView({
    required this.log,
    required this.onBack,
    required this.onToast,
  });

  @override
  State<_DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends State<_DetailView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Color _statusColor() {
    final log = widget.log;
    if (log.isNetworkError) return Colors.red;
    if (log.isPending) return Colors.grey;
    final s = log.statusCode!;
    if (s < 300) return Colors.green;
    if (s < 400) return Colors.blue;
    if (s < 500) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    final cs = Theme.of(context).colorScheme;
    final color = _statusColor();
    final time = '${log.timestamp.hour.toString().padLeft(2, '0')}:'
        '${log.timestamp.minute.toString().padLeft(2, '0')}:'
        '${log.timestamp.second.toString().padLeft(2, '0')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              ),
              Expanded(
                child: Text(
                  '${log.method}  ${log.shortUrl}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: cs.surfaceContainerHighest,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(log.statusLabel,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
              ),
              const SizedBox(width: 12),
              Text(log.durationLabel, style: const TextStyle(fontSize: 13)),
              const Spacer(),
              Text(time,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
        TabBar(
          controller: _tabs,
          labelStyle: const TextStyle(fontSize: 12),
          tabs: const [
            Tab(text: 'REQUEST'),
            Tab(text: 'RESPONSE'),
            Tab(text: 'HEADERS'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _BodyView(
                  content: log.requestBody, placeholder: 'No request body'),
              _BodyView(
                  content: log.error ?? log.responseBody,
                  placeholder: 'No response body',
                  isError: log.isError),
              _HeadersView(
                  requestHeaders: log.requestHeaders,
                  responseHeaders: log.responseHeaders),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy cURL'),
                  onPressed: () {
                    Clipboard.setData(
                        ClipboardData(text: CurlGenerator.generate(log)));
                    widget.onToast('cURL copied');
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.copy_all, size: 16),
                  label: const Text('Copy Body'),
                  onPressed: (log.responseBody != null || log.error != null)
                      ? () {
                          Clipboard.setData(ClipboardData(
                              text: log.error ?? log.responseBody ?? ''));
                          widget.onToast('Response copied');
                        }
                      : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Body view ────────────────────────────────────────────────────────────────

class _BodyView extends StatelessWidget {
  final String? content;
  final String placeholder;
  final bool isError;

  const _BodyView({
    this.content,
    required this.placeholder,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    if (content == null || content!.isEmpty) {
      return Center(
        child: Text(placeholder, style: const TextStyle(color: Colors.grey)),
      );
    }
    final display = JsonFormatter.looksLikeJson(content)
        ? JsonFormatter.tryFormat(content)
        : content!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        display,
        style: TextStyle(
          fontSize: 12,
          fontFamily: 'monospace',
          color: isError ? Colors.red.shade700 : null,
        ),
      ),
    );
  }
}

// ─── Headers view ─────────────────────────────────────────────────────────────

class _HeadersView extends StatelessWidget {
  final Map<String, String> requestHeaders;
  final Map<String, String>? responseHeaders;

  const _HeadersView(
      {required this.requestHeaders, required this.responseHeaders});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _section('Request Headers', requestHeaders),
          if (responseHeaders != null) ...[
            const SizedBox(height: 20),
            _section('Response Headers', responseHeaders!),
          ],
        ],
      ),
    );
  }

  Widget _section(String title, Map<String, String> headers) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 8),
        if (headers.isEmpty)
          const Text('None', style: TextStyle(color: Colors.grey, fontSize: 12))
        else
          ...headers.entries.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 130,
                    child: Text(e.key,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace')),
                  ),
                  Expanded(
                    child: Text(e.value,
                        style: const TextStyle(
                            fontSize: 11, fontFamily: 'monospace')),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Toast ────────────────────────────────────────────────────────────────────

class _PeekyToast extends StatelessWidget {
  final String message;
  const _PeekyToast({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(message,
            style: const TextStyle(color: Colors.white, fontSize: 13)),
      ),
    );
  }
}
