import 'package:flutter_test/flutter_test.dart';
import 'package:peeky/peeky.dart';

void main() {
  setUp(PeekyStore.instance.clearLogs);

  group('PeekyStore', () {
    test('addRequest returns a pending log', () {
      final log = PeekyStore.instance
          .addRequest(url: 'https://api.example.com/users', method: 'GET');
      expect(log.isPending, isTrue);
      expect(log.isSuccess, isFalse);
      expect(log.statusCode, isNull);
    });

    test('updateResponse marks log as success', () {
      final log = PeekyStore.instance
          .addRequest(url: 'https://api.example.com/items', method: 'POST');
      PeekyStore.instance.updateResponse(
        id: log.id,
        statusCode: 201,
        responseBody: '{"id":1}',
        responseHeaders: {'content-type': 'application/json'},
        duration: const Duration(milliseconds: 123),
      );
      expect(log.isPending, isFalse);
      expect(log.isSuccess, isTrue);
      expect(log.statusCode, 201);
      expect(log.statusLabel, '201');
      expect(log.durationLabel, '123ms');
    });

    test('updateError marks log as network error', () {
      final log = PeekyStore.instance
          .addRequest(url: 'https://api.example.com/fail', method: 'GET');
      PeekyStore.instance.updateError(
        id: log.id,
        error: 'SocketException: no route to host',
        duration: const Duration(milliseconds: 50),
      );
      expect(log.isNetworkError, isTrue);
      expect(log.isError, isTrue);
      expect(log.statusLabel, 'ERR');
    });

    test('ring buffer does not exceed maxSize', () {
      PeekyStore.instance.configure(maxSize: 5);
      for (int i = 0; i < 10; i++) {
        PeekyStore.instance
            .addRequest(url: 'https://api.example.com/$i', method: 'GET');
      }
      expect(PeekyStore.instance.logs.length, 5);
      // Cleanup
      PeekyStore.instance.configure(maxSize: 200);
    });

    test('clearLogs empties the store', () {
      PeekyStore.instance
          .addRequest(url: 'https://api.example.com/x', method: 'GET');
      PeekyStore.instance.clearLogs();
      expect(PeekyStore.instance.logs, isEmpty);
    });

    test('addFlutterError records to errors list', () {
      PeekyStore.instance.clearErrors();
      PeekyStore.instance.addFlutterError('Null check failed', null);
      expect(PeekyStore.instance.errors.length, 1);
      expect(PeekyStore.instance.errors.first.message,
          contains('Null check failed'));
      PeekyStore.instance.clearErrors();
    });

    test('shortUrl strips query params from display', () {
      final log = PeekyStore.instance.addRequest(
          url: 'https://api.example.com/search?q=hello&page=2', method: 'GET');
      expect(log.shortUrl, isNot(contains('?')));
    });

    test('durationLabel shows pending for pending log', () {
      final log = PeekyStore.instance
          .addRequest(url: 'https://api.example.com/slow', method: 'GET');
      expect(log.durationLabel, '-');
    });
  });
}
