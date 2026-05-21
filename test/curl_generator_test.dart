import 'package:flutter_test/flutter_test.dart';
import 'package:peeky/peeky.dart';

void main() {
  group('CurlGenerator', () {
    test('generates basic GET', () {
      final log = PeekyStore.instance
          .addRequest(url: 'https://api.example.com/users', method: 'GET');
      final curl = CurlGenerator.generate(log);
      expect(curl, contains('curl -X GET'));
      expect(curl, contains('"https://api.example.com/users"'));
    });

    test('includes headers', () {
      final log = PeekyStore.instance.addRequest(
        url: 'https://api.example.com/users',
        method: 'GET',
        requestHeaders: {'Authorization': 'Bearer token123'},
      );
      final curl = CurlGenerator.generate(log);
      expect(curl, contains('-H "Authorization: Bearer token123"'));
    });

    test('includes body for POST', () {
      final log = PeekyStore.instance.addRequest(
        url: 'https://api.example.com/users',
        method: 'POST',
        requestBody: '{"name":"Alice"}',
      );
      final curl = CurlGenerator.generate(log);
      expect(curl, contains("-d '"));
      expect(curl, contains('Alice'));
    });

    test('escapes single quotes in body', () {
      final log = PeekyStore.instance.addRequest(
        url: 'https://api.example.com/x',
        method: 'POST',
        requestBody: "it's a test",
      );
      final curl = CurlGenerator.generate(log);
      expect(curl, contains("'\\''"));
    });
  });
}
