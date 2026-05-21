import 'dart:async';

import 'package:flutter/material.dart';

import '../shake/shake_detector.dart';
import '../store/peeky_store.dart';
import 'peeky_panel.dart';

/// Wrap your widget tree once to enable the Peeky network inspector.
///
/// **Recommended placement** — inside [MaterialApp.builder] so the panel
/// has access to theming and navigation:
///
/// ```dart
/// MaterialApp(
///   builder: (context, child) => Peeky(child: child!),
///   home: HomeScreen(),
/// )
/// ```
///
/// ### Triggering the inspector
///
/// On desktop/web a draggable floating button is shown by default.
/// On mobile you can wire up any gesture stream — including a shake detector
/// from the `sensors_plus` package — via [triggerStream]:
///
/// ```dart
/// // Add sensors_plus to your app's pubspec.yaml, then:
/// import 'package:sensors_plus/sensors_plus.dart';
///
/// Stream<void> _buildShakeStream() async* {
///   const threshold = 20.0;
///   await for (final e in accelerometerEventStream()) {
///     final m = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
///     if (m > threshold) yield null;
///   }
/// }
///
/// Peeky(
///   triggerStream: _buildShakeStream(),
///   child: child!,
/// )
/// ```
///
/// Set [enabled] to `false` for Play Store / App Store production builds:
///
/// ```dart
/// Peeky(
///   enabled: FlavorConfig.isInternal,
///   child: child!,
/// )
/// ```
class Peeky extends StatefulWidget {
  final Widget child;

  /// Master switch. When `false` no logs are stored and the panel is never
  /// shown. Safe to ship in production with `enabled: false`.
  final bool enabled;

  /// Maximum number of request logs to keep in the ring buffer.
  final int maxLogs;

  /// When `true`, chains into [FlutterError.onError] to also capture widget
  /// errors into the Errors tab. Existing handlers (e.g. Crashlytics) are
  /// still called.
  final bool captureFlutterErrors;

  /// Navigator key used to push the inspector panel as a screen.
  ///
  /// Required when [Peeky] is placed inside [MaterialApp.builder] because that
  /// context has no [Navigator] ancestor. Pass the same key that you give to
  /// [MaterialApp.navigatorKey].
  ///
  /// When [Peeky] is placed *inside* the navigator tree (e.g. wrapping `home`)
  /// this may be left null and the ambient [Navigator] is used instead.
  final GlobalKey<NavigatorState>? navigatorKey;

  /// Optional stream whose events open the inspector panel.
  ///
  /// Use this to plug in any external trigger — a shake gesture, a button
  /// press, a keyboard shortcut, or a timer. The stream is cancelled when
  /// this widget is disposed.
  ///
  /// Example — shake on mobile using `sensors_plus`:
  /// ```dart
  /// triggerStream: accelerometerEventStream()
  ///     .where((e) => sqrt(e.x*e.x+e.y*e.y+e.z*e.z) > 20)
  ///     .map((_) => null)
  /// ```
  final Stream<void>? triggerStream;

  /// When `true` (default) a small draggable floating button is rendered over
  /// the app content. Tap it to open the inspector. Useful on desktop or
  /// any platform where a gesture-based trigger is inconvenient.
  ///
  /// Set to `false` when you provide your own [triggerStream] and do not want
  /// the extra UI element.
  final bool showFloatingButton;

  /// Number of simultaneous fingers that must touch the screen to open the
  /// inspector. Defaults to `3` (three-finger tap).
  ///
  /// This is a zero-dependency alternative to a shake gesture — no extra
  /// package required. Works on any touch-capable platform.
  ///
  /// Set to `0` to disable the multi-finger trigger entirely.
  ///
  /// Example — disable button and rely solely on three-finger tap on mobile:
  /// ```dart
  /// Peeky(
  ///   showFloatingButton: false,
  ///   tapTriggerFingers: 3,
  ///   child: child!,
  /// )
  /// ```
  final int tapTriggerFingers;

  const Peeky({
    super.key,
    required this.child,
    this.enabled = true,
    this.maxLogs = 200,
    this.captureFlutterErrors = true,
    this.navigatorKey,
    this.triggerStream,
    this.showFloatingButton = true,
    this.tapTriggerFingers = 3,
  });

  @override
  State<Peeky> createState() => _PeekyState();
}

class _PeekyState extends State<Peeky> {
  ShakeDetector? _trigger;
  void Function(FlutterErrorDetails)? _prevErrorHandler;

  /// Guard: prevents pushing the panel twice while it is already open.
  bool _panelOpen = false;

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) return;

    PeekyStore.instance.configure(maxSize: widget.maxLogs, enabled: true);

    _trigger = ShakeDetector(
      onShake: _openPanel,
      triggerStream: widget.triggerStream,
    )..start();

    if (widget.captureFlutterErrors) {
      _prevErrorHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        PeekyStore.instance
            .addFlutterError(details.exceptionAsString(), details.stack);
        _prevErrorHandler?.call(details);
      };
    }
  }

  @override
  void dispose() {
    _trigger?.stop();
    if (widget.captureFlutterErrors) {
      FlutterError.onError = _prevErrorHandler;
    }
    super.dispose();
  }

  void _openPanel() {
    if (!mounted || _panelOpen) return;

    final nav = widget.navigatorKey?.currentState ?? Navigator.maybeOf(context);
    if (nav == null) return;

    _panelOpen = true;
    nav
        .push<void>(
          PageRouteBuilder(
            // opaque keeps the route's background solid (panel has its own bg)
            opaque: true,
            // Let PeekyPanel's own SlideTransition handle the animation
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (_, __, ___) => PeekyPanel(
              onClose: () {
                _panelOpen = false;
                nav.pop();
              },
            ),
          ),
        )
        .whenComplete(() => _panelOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    Widget tree = widget.child;

    // Wrap with multi-finger tap zone when requested.
    if (widget.tapTriggerFingers > 0) {
      tree = _PeekyTapZone(
        fingers: widget.tapTriggerFingers,
        onTriggered: _openPanel,
        child: tree,
      );
    }

    if (!widget.showFloatingButton) return tree;

    return Stack(
      children: [
        tree,
        _PeekyFloatingButton(onTap: _openPanel),
      ],
    );
  }
}

// ─── Floating trigger button ──────────────────────────────────────────────────

class _PeekyFloatingButton extends StatefulWidget {
  final VoidCallback onTap;
  const _PeekyFloatingButton({required this.onTap});

  @override
  State<_PeekyFloatingButton> createState() => _PeekyFloatingButtonState();
}

class _PeekyFloatingButtonState extends State<_PeekyFloatingButton> {
  // Position relative to top-left of Stack — default bottom-right area.
  double _dx = 16;
  double _dy = 120;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF212121).withAlpha(204),
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                color: Color(0x55000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(
            Icons.network_check_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    );

    // Tooltip requires an Overlay ancestor (provided by Navigator/MaterialApp).
    // When Peeky is placed above MaterialApp no overlay exists yet, so we skip
    // the tooltip to avoid a "No Overlay widget found" exception.
    final hasOverlay = Overlay.maybeOf(context) != null;

    return Positioned(
      right: _dx,
      bottom: _dy,
      child: GestureDetector(
        onPanUpdate: (d) {
          setState(() {
            _dx = (_dx - d.delta.dx).clamp(0, size.width - 48);
            _dy = (_dy - d.delta.dy).clamp(0, size.height - 48);
          });
        },
        child: hasOverlay
            ? Tooltip(message: 'Peeky inspector', child: button)
            : button,
      ),
    );
  }
}

// ─── Multi-finger tap trigger ─────────────────────────────────────────────────

/// Transparent overlay that counts simultaneous pointer-down events.
/// When [fingers] pointers are active at the same time, [onTriggered] fires.
/// Uses [Listener] so it never competes with the child's gesture recognisers.
class _PeekyTapZone extends StatefulWidget {
  final Widget child;
  final int fingers;
  final VoidCallback onTriggered;

  const _PeekyTapZone({
    required this.child,
    required this.fingers,
    required this.onTriggered,
  });

  @override
  State<_PeekyTapZone> createState() => _PeekyTapZoneState();
}

class _PeekyTapZoneState extends State<_PeekyTapZone> {
  int _activePointers = 0;
  bool _fired = false;

  void _onDown(PointerDownEvent _) {
    _activePointers++;
    if (!_fired && _activePointers >= widget.fingers) {
      _fired = true;
      widget.onTriggered();
    }
  }

  void _onUp(PointerUpEvent _) => _onRelease();
  void _onCancel(PointerCancelEvent _) => _onRelease();

  void _onRelease() {
    _activePointers = (_activePointers - 1).clamp(0, 99);
    if (_activePointers < widget.fingers) _fired = false;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onDown,
      onPointerUp: _onUp,
      onPointerCancel: _onCancel,
      child: widget.child,
    );
  }
}
