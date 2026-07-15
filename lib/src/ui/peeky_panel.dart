import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/inspector_log.dart';
import '../store/peeky_store.dart';
import '../utils/body_formatter.dart';
import '../utils/curl_generator.dart';
import '../utils/json_formatter.dart';
import 'json_tree_view.dart';

// ─── Tab / Filter enums ───────────────────────────────────────────────────────

enum _PanelTab { network, errors }

enum _Filter { all, s2xx, s4xx, s5xx, err }

extension _FilterLabel on _Filter {
  String get label => switch (this) {
        _Filter.all => 'All',
        _Filter.s2xx => '2xx',
        _Filter.s4xx => '4xx',
        _Filter.s5xx => '5xx',
        _Filter.err => 'Failed',
      };

  Color? get dotColor => switch (this) {
        _Filter.all => null,
        _Filter.s2xx => const Color(0xFF22C55E),
        _Filter.s4xx => const Color(0xFFF59E0B),
        _Filter.s5xx => const Color(0xFFEF4444),
        _Filter.err => const Color(0xFFEF4444),
      };
}

// ─── Shared helpers ───────────────────────────────────────────────────────────

Color _statusColorFor(InspectorLog log) {
  if (log.isNetworkError) {
    return const Color(0xFFEF4444);
  }
  if (log.isPending) {
    return const Color(0xFF94A3B8);
  }
  final s = log.statusCode!;
  if (s < 300) {
    return const Color(0xFF22C55E);
  }
  if (s < 400) {
    return const Color(0xFF3B82F6);
  }
  if (s < 500) {
    return const Color(0xFFF59E0B);
  }
  return const Color(0xFFEF4444);
}

Color _methodColor(String method) => switch (method.toUpperCase()) {
      'GET' => const Color(0xFF3B82F6),
      'POST' => const Color(0xFF22C55E),
      'PUT' => const Color(0xFFF59E0B),
      'PATCH' => const Color(0xFFA855F7),
      'DELETE' => const Color(0xFFEF4444),
      _ => const Color(0xFF64748B),
    };

String _fmtTime(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:'
    '${t.minute.toString().padLeft(2, '0')}:'
    '${t.second.toString().padLeft(2, '0')}';

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
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
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
                    bottom: 24,
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
        // ── Header ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Text('👀', style: TextStyle(fontSize: 17)),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Peeky',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  Text('Network Inspector',
                      style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurface.withValues(alpha: 0.5))),
                ],
              ),
              const Spacer(),
              _RoundIconBtn(
                icon: Icons.delete_outline,
                tooltip: _tab == _PanelTab.network
                    ? 'Clear requests'
                    : 'Clear errors',
                onTap: () {
                  if (_tab == _PanelTab.network) {
                    PeekyStore.instance.clearLogs();
                  } else {
                    PeekyStore.instance.clearErrors();
                  }
                },
              ),
              const SizedBox(width: 8),
              _RoundIconBtn(
                icon: Icons.close,
                tooltip: 'Close',
                onTap: _close,
              ),
            ],
          ),
        ),
        // ── Segmented Network / Errors tabs ──
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: StreamBuilder<List<InspectorErrorLog>>(
            stream: PeekyStore.instance.errorStream,
            initialData: PeekyStore.instance.errors,
            builder: (_, snap) {
              final errCount = snap.data?.length ?? 0;
              return _SegmentedTabs(
                labels: const ['Network', 'Errors'],
                icons: const [Icons.swap_vert_rounded, Icons.bug_report_outlined],
                badges: [null, errCount == 0 ? null : errCount],
                index: _tab.index,
                onChanged: (i) => setState(() {
                  _tab = _PanelTab.values[i];
                  if (_tab == _PanelTab.network) {
                    _search = '';
                  }
                }),
              );
            },
          ),
        ),
        if (_tab == _PanelTab.network)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              onChanged: (s) => setState(() => _search = s),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search URL…',
                hintStyle: TextStyle(
                    fontSize: 13, color: cs.onSurface.withValues(alpha: 0.4)),
                prefixIcon: Icon(Icons.search,
                    size: 19, color: cs.onSurface.withValues(alpha: 0.4)),
                filled: true,
                fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              ),
              style: const TextStyle(fontSize: 13),
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

// ─── Round icon button ────────────────────────────────────────────────────────

class _RoundIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _RoundIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon,
                size: 18, color: cs.onSurface.withValues(alpha: 0.7)),
          ),
        ),
      ),
    );
  }
}

// ─── Segmented tabs ───────────────────────────────────────────────────────────

class _SegmentedTabs extends StatelessWidget {
  final List<String> labels;
  final List<IconData>? icons;
  final List<int?>? badges;
  final int index;
  final ValueChanged<int> onChanged;

  const _SegmentedTabs({
    required this.labels,
    this.icons,
    this.badges,
    required this.index,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: List.generate(labels.length, (i) {
          final active = i == index;
          final badge = badges?[i];
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: active ? cs.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: active
                      ? const [
                          BoxShadow(
                            color: Color(0x1A000000),
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icons != null) ...[
                      Icon(icons![i],
                          size: 15,
                          color: active
                              ? cs.primary
                              : cs.onSurface.withValues(alpha: 0.5)),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        color: active
                            ? cs.primary
                            : cs.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: cs.error,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          '$badge',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: cs.onError,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
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
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: _Filter.values
                .map((f) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _FilterPill(
                        filter: f,
                        selected: filter == f,
                        onTap: () => onFilterChanged(f),
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
                return const _EmptyState(
                  icon: Icons.wifi_tethering_off,
                  title: 'No requests yet',
                  hint: 'Make an API call and it will show up here.',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 16),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) =>
                    _LogCard(log: filtered[i], onTap: onLogTap),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── Filter pill ──────────────────────────────────────────────────────────────

class _FilterPill extends StatelessWidget {
  final _Filter filter;
  final bool selected;
  final VoidCallback onTap;

  const _FilterPill({
    required this.filter,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? cs.primary
              : cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (filter.dotColor != null) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: filter.dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              filter.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? cs.onPrimary
                    : cs.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Log card ─────────────────────────────────────────────────────────────────

class _LogCard extends StatelessWidget {
  final InspectorLog log;
  final ValueChanged<InspectorLog> onTap;

  const _LogCard({required this.log, required this.onTap});

  String get _host {
    try {
      return Uri.parse(log.url).host;
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = _statusColorFor(log);
    final methodColor = _methodColor(log.method);

    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => onTap(log),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.5), width: 0.8),
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                padding: const EdgeInsets.symmetric(vertical: 5),
                decoration: BoxDecoration(
                  color: methodColor.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  log.method,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: methodColor,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      log.shortUrl,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (_host.isNotEmpty) _host,
                        _fmtTime(log.timestamp),
                        if (log.duration != null) log.durationLabel,
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withValues(alpha: 0.45),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (log.isPending)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    log.statusLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: statusColor,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String hint;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child:
                Icon(icon, size: 32, color: cs.onSurface.withValues(alpha: 0.3)),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: cs.onSurface.withValues(alpha: 0.65),
            ),
          ),
          if (hint.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.45),
              ),
            ),
          ],
        ],
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
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<List<InspectorErrorLog>>(
      stream: PeekyStore.instance.errorStream,
      initialData: PeekyStore.instance.errors,
      builder: (_, snap) {
        final list = snap.data ?? [];
        if (list.isEmpty) {
          return const _EmptyState(
            icon: Icons.check_circle_outline,
            title: 'No Flutter errors',
            hint: 'Widget and framework errors will be captured here.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final e = list[i];
            return Material(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: e.stackTrace != null ? () => onErrorTap(e) : null,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.5),
                        width: 0.8),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: cs.errorContainer.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.priority_high_rounded,
                            size: 18, color: cs.error),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.message,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _fmtTime(e.timestamp),
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurface.withValues(alpha: 0.45),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (e.stackTrace != null)
                        Icon(Icons.chevron_right,
                            size: 18,
                            color: cs.onSurface.withValues(alpha: 0.35)),
                    ],
                  ),
                ),
              ),
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
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Row(
            children: [
              _RoundIconBtn(
                icon: Icons.arrow_back,
                tooltip: 'Back',
                onTap: onBack,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Error details',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
              _RoundIconBtn(
                icon: Icons.copy,
                tooltip: 'Copy error and stack trace',
                onTap: () {
                  Clipboard.setData(ClipboardData(
                      text: '${error.message}\n\n${error.stackTrace}'));
                  onToast('Copied to clipboard');
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cs.errorContainer.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: SelectableText(
                    error.message,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                      color: cs.onErrorContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.5),
                        width: 0.8),
                  ),
                  child: SelectableText(
                    error.stackTrace ?? '',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.55,
                      fontFamily: 'monospace',
                      color: cs.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ],
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

class _DetailViewState extends State<_DetailView> {
  int _section = 1; // 0 = request, 1 = response, 2 = headers

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    final cs = Theme.of(context).colorScheme;
    final statusColor = _statusColorFor(log);
    final methodColor = _methodColor(log.method);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Row(
            children: [
              _RoundIconBtn(
                icon: Icons.arrow_back,
                tooltip: 'Back',
                onTap: widget.onBack,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Request details',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
              _RoundIconBtn(
                icon: Icons.link,
                tooltip: 'Copy URL',
                onTap: () {
                  Clipboard.setData(ClipboardData(text: log.url));
                  widget.onToast('URL copied');
                },
              ),
            ],
          ),
        ),
        // ── Hero summary card ──
        Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.5), width: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: methodColor.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      log.method,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: methodColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SelectableText(
                      log.url,
                      maxLines: 3,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _MetaPill(
                    label: log.isPending ? 'Pending' : log.statusLabel,
                    background: statusColor,
                    foreground: Colors.white,
                    bold: true,
                  ),
                  _MetaPill(
                      icon: Icons.timer_outlined, label: log.durationLabel),
                  if (log.responseBody != null &&
                      log.responseBody!.isNotEmpty)
                    _MetaPill(
                      icon: Icons.download_outlined,
                      label: BodyFormatter.sizeLabel(log.responseBody!),
                    ),
                  _MetaPill(
                      icon: Icons.schedule, label: _fmtTime(log.timestamp)),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: _SegmentedTabs(
            labels: const ['Request', 'Response', 'Headers'],
            index: _section,
            onChanged: (i) => setState(() => _section = i),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _section,
            children: [
              _BodyView(
                  content: log.requestBody, placeholder: 'No request body'),
              _BodyView(
                  content: log.error ?? log.responseBody,
                  placeholder: 'No response body',
                  isError: log.isError),
              _HeadersView(
                requestHeaders: log.requestHeaders,
                responseHeaders: log.responseHeaders,
                onToast: widget.onToast,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.terminal, size: 16),
                  label: const Text('Copy cURL'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13)),
                    textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  onPressed: () {
                    Clipboard.setData(
                        ClipboardData(text: CurlGenerator.generate(log)));
                    widget.onToast('cURL copied');
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.copy_all, size: 16),
                  label: const Text('Copy Body'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13)),
                    textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700),
                  ),
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

// ─── Meta pill ────────────────────────────────────────────────────────────────

class _MetaPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? background;
  final Color? foreground;
  final bool bold;

  const _MetaPill({
    required this.label,
    this.icon,
    this.background,
    this.foreground,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = foreground ?? cs.onSurface.withValues(alpha: 0.65);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: background ?? cs.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Body view ────────────────────────────────────────────────────────────────

enum _BodyMode { tree, pretty, raw }

extension _BodyModeLabel on _BodyMode {
  String get label => switch (this) {
        _BodyMode.tree => 'Tree',
        _BodyMode.pretty => 'Pretty',
        _BodyMode.raw => 'Raw',
      };
}

class _BodyView extends StatefulWidget {
  final String? content;
  final String placeholder;
  final bool isError;

  const _BodyView({
    this.content,
    required this.placeholder,
    this.isError = false,
  });

  @override
  State<_BodyView> createState() => _BodyViewState();
}

class _BodyViewState extends State<_BodyView> {
  late final BodyKind _kind;
  late _BodyMode _mode;
  dynamic _decoded;

  // Expand/collapse-all signal for the tree (see JsonTreeView).
  int _generation = 0;
  bool? _forceExpanded;

  bool get _hasContent =>
      widget.content != null && widget.content!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (!_hasContent) {
      _kind = BodyKind.text;
      _mode = _BodyMode.raw;
      return;
    }
    _kind = BodyFormatter.detect(widget.content!);
    if (_kind == BodyKind.json) {
      _decoded = jsonDecode(widget.content!);
      _mode = _BodyMode.tree;
    } else if (_kind == BodyKind.xml) {
      _mode = _BodyMode.pretty;
    } else {
      _mode = _BodyMode.raw;
    }
  }

  List<_BodyMode> get _modes => switch (_kind) {
        BodyKind.json => const [_BodyMode.tree, _BodyMode.pretty, _BodyMode.raw],
        BodyKind.xml => const [_BodyMode.pretty, _BodyMode.raw],
        BodyKind.text => const [],
      };

  @override
  Widget build(BuildContext context) {
    if (!_hasContent) {
      return _EmptyState(
        icon: Icons.inbox_outlined,
        title: widget.placeholder,
        hint: '',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_modes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(
              children: [
                _ModeToggle(
                  modes: _modes,
                  selected: _mode,
                  onChanged: (m) => setState(() => _mode = m),
                ),
                const Spacer(),
                if (_mode == _BodyMode.tree) ...[
                  _ToolIconBtn(
                    icon: Icons.unfold_more,
                    tooltip: 'Expand all',
                    onTap: () => setState(() {
                      _generation++;
                      _forceExpanded = true;
                    }),
                  ),
                  const SizedBox(width: 4),
                  _ToolIconBtn(
                    icon: Icons.unfold_less,
                    tooltip: 'Collapse all',
                    onTap: () => setState(() {
                      _generation++;
                      _forceExpanded = false;
                    }),
                  ),
                ],
              ],
            ),
          ),
        Expanded(child: _buildBody(context)),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget child;
    if (_mode == _BodyMode.tree && _decoded != null) {
      child = JsonTreeView(
        data: _decoded,
        generation: _generation,
        forceExpanded: _forceExpanded,
      );
    } else {
      final text = switch (_mode) {
        _BodyMode.pretty when _kind == BodyKind.json =>
          JsonFormatter.tryFormat(widget.content),
        _BodyMode.pretty when _kind == BodyKind.xml =>
          BodyFormatter.formatXml(widget.content!),
        _ => widget.content!,
      };
      final dark = Theme.of(context).brightness == Brightness.dark;
      child = SelectableText(
        text,
        style: TextStyle(
          fontSize: 12,
          height: 1.55,
          fontFamily: 'monospace',
          color: widget.isError
              ? (dark ? Colors.red.shade200 : Colors.red.shade800)
              : null,
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.5), width: 0.8),
        ),
        child: child,
      ),
    );
  }
}

// ─── Mode toggle (segmented) ──────────────────────────────────────────────────

class _ModeToggle extends StatelessWidget {
  final List<_BodyMode> modes;
  final _BodyMode selected;
  final ValueChanged<_BodyMode> onChanged;

  const _ModeToggle({
    required this.modes,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: modes.map((m) {
          final active = m == selected;
          return InkWell(
            onTap: () => onChanged(m),
            borderRadius: BorderRadius.circular(8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding:
                  const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
              decoration: BoxDecoration(
                color: active ? cs.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                boxShadow: active
                    ? const [
                        BoxShadow(
                          color: Color(0x1A000000),
                          blurRadius: 3,
                          offset: Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                m.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active
                      ? cs.primary
                      : cs.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Small icon button ────────────────────────────────────────────────────────

class _ToolIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ToolIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon,
              size: 15, color: cs.onSurface.withValues(alpha: 0.65)),
        ),
      ),
    );
  }
}

// ─── Headers view ─────────────────────────────────────────────────────────────

class _HeadersView extends StatelessWidget {
  final Map<String, String> requestHeaders;
  final Map<String, String>? responseHeaders;
  final ValueChanged<String> onToast;

  const _HeadersView({
    required this.requestHeaders,
    required this.responseHeaders,
    required this.onToast,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _section(context, Icons.upload_outlined, 'Request Headers',
              requestHeaders),
          if (responseHeaders != null) ...[
            const SizedBox(height: 10),
            _section(context, Icons.download_outlined, 'Response Headers',
                responseHeaders!),
          ],
        ],
      ),
    );
  }

  Widget _section(BuildContext context, IconData icon, String title,
      Map<String, String> headers) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.5), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: cs.primary),
              const SizedBox(width: 6),
              Text(title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 0.2,
                    color: cs.onSurface.withValues(alpha: 0.8),
                  )),
              const Spacer(),
              Text('${headers.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withValues(alpha: 0.4),
                  )),
            ],
          ),
          const SizedBox(height: 9),
          if (headers.isEmpty)
            Text('None',
                style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.45), fontSize: 12))
          else
            ...headers.entries.map(
              (e) => InkWell(
                onLongPress: () {
                  Clipboard.setData(
                      ClipboardData(text: '${e.key}: ${e.value}'));
                  onToast('Header copied');
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 125,
                        child: Text(e.key,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.45,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'monospace',
                              color: cs.primary,
                            )),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SelectableText(e.value,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.45,
                              fontFamily: 'monospace',
                              color: cs.onSurface.withValues(alpha: 0.85),
                            )),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
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
          color: const Color(0xE6212121),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle,
                color: Color(0xFF4ADE80), size: 15),
            const SizedBox(width: 7),
            Text(message,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
