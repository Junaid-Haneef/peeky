import 'dart:async';

import 'package:flutter/foundation.dart';

/// Subscribes to an external trigger stream and fires [onShake] on each event.
///
/// Pass an accelerometer-based stream on mobile (e.g. from `sensors_plus`)
/// or any other `Stream<void>` to customise how the inspector is opened.
/// On platforms where accelerometers are unavailable the stream may be omitted
/// and the built-in floating button can be used instead.
class ShakeDetector {
  final VoidCallback onShake;

  /// Optional stream whose events open the inspector panel.
  final Stream<void>? triggerStream;

  StreamSubscription<void>? _subscription;

  ShakeDetector({required this.onShake, this.triggerStream});

  /// Start listening to [triggerStream], if one was provided.
  void start() {
    if (kReleaseMode && triggerStream == null) {
      return;
    }
    _subscription = triggerStream?.listen((_) => onShake(), onError: (_) {});
  }

  /// Stop listening.
  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }
}
