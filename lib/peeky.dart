/// Peeky — in-app network inspector for Flutter.
///
/// Quick start:
/// ```dart
/// // 1) Wrap your app
/// MaterialApp(
///   builder: (ctx, child) => Peeky(child: child!),
/// )
///
/// // 2) Use PeekyHttpClient instead of http.Client()
/// final client = PeekyHttpClient(http.Client());
/// ```
library peeky;

export 'src/models/inspector_log.dart';
export 'src/store/peeky_store.dart';
export 'src/clients/peeky_http_client.dart';
export 'src/ui/peeky_widget.dart';
export 'src/utils/curl_generator.dart';
export 'src/utils/json_formatter.dart';
