# Peeky

An in-app network request inspector for Flutter. Captures every HTTP request and response in real time and displays them in a scrollable, searchable panel — no desktop tools required.

Works with the [`http`](https://pub.dev/packages/http) package and [Dio](https://pub.dev/packages/dio). Safe to leave in release builds (just set `enabled: false`).

## Screenshots

<p float="left">
  <img src="https://raw.githubusercontent.com/Junaid-Haneef/peeky/main/assets/inspector_main_panel.png" width="45%" alt="Inspector main panel" />
  <img src="https://raw.githubusercontent.com/Junaid-Haneef/peeky/main/assets/inspector_response_image.png" width="45%" alt="Request response detail" />
</p>

## Features

- Live request/response log with status code, method, URL, headers and body
- Filter by status class (2xx · 4xx · 5xx · errors)
- Full-text search across all logs
- One-tap cURL export for each request
- Captures Flutter framework errors in a separate **Errors** tab
- Draggable floating button to open the inspector — works on all platforms
- Plug in any custom trigger stream (shake, keyboard shortcut, etc.)
- Supports Android · iOS · macOS · Web · Windows · Linux

## Getting started

Add peeky to your `pubspec.yaml`:

```yaml
dependencies:
  peeky: ^0.0.1
```

## Usage

### 1 — Wrap your app

Place `Peeky` inside `MaterialApp.builder` and pass the same `navigatorKey`:

```dart
final _navKey = GlobalKey<NavigatorState>();

MaterialApp(
  navigatorKey: _navKey,
  builder: (context, child) => Peeky(
    navigatorKey: _navKey,
    child: child!,
  ),
  home: const HomeScreen(),
)
```

A small floating button will appear over your UI. Tap it to open the inspector panel.

### 2a — Capture requests with the `http` package

```dart
import 'package:peeky/peeky.dart';
import 'package:http/http.dart' as http;

// Before
final client = http.Client();

// After — one-word change
final client = PeekyHttpClient(http.Client());
```

All requests made through `client` are now visible in the panel.

### 2b — Capture requests with Dio

```dart
import 'package:peeky/peeky_dio.dart';

dio.interceptors.add(PeekyDioInterceptor());
```

### Shake to open (optional, mobile only)

The core package has no sensor dependency so it runs on all platforms. To restore shake-to-open on Android/iOS, add `sensors_plus` to **your** app's `pubspec.yaml` and wire it to `triggerStream`:

```dart
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';

Peeky(
  navigatorKey: _navKey,
  showFloatingButton: false,          // hide the button when using shake
  triggerStream: accelerometerEventStream()
      .where((e) => sqrt(e.x * e.x + e.y * e.y + e.z * e.z) > 20)
      .map((_) => null),
  child: child!,
)
```

### Disabling for production

```dart
Peeky(
  enabled: kDebugMode,   // or your own FlavorConfig flag
  navigatorKey: _navKey,
  child: child!,
)
```

## Additional information

- File bugs and feature requests on the [issue tracker](https://github.com/Junaid-Haneef/peeky/issues).
- Pull requests are welcome — see the repository at [github.com/Junaid-Haneef/peeky](https://github.com/Junaid-Haneef/peeky).
