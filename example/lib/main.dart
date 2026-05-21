import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:peeky/peeky.dart';

/// Simple example showing how to integrate the peeky package.
///
/// 1. Wrap with [Peeky] inside [MaterialApp.builder].
/// 2. Use [PeekyHttpClient] instead of a raw http.Client.
/// 3. Shake the device to open the inspector panel.
void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Peeky Example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      // ✅ Wrap here — works whether Peeky is a parent or a sibling of nav stack.
      builder: (context, child) => Peeky(
        enabled: true, // set to FlavorConfig.isInternal in real apps
        child: child!,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // ✅ Use PeekyHttpClient — wraps any http.BaseClient transparently.
  final _client = PeekyHttpClient(http.Client());
  final _messages = <String>[];
  bool _loading = false;

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<void> _get200() async {
    setState(() => _loading = true);
    try {
      final res = await _client
          .get(Uri.parse('https://jsonplaceholder.typicode.com/posts/1'));
      _add('GET 200: ${res.statusCode}');
    } catch (e) {
      _add('Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _post201() async {
    setState(() => _loading = true);
    try {
      final res = await _client.post(
        Uri.parse('https://jsonplaceholder.typicode.com/posts'),
        headers: {'Content-Type': 'application/json'},
        body: '{"title":"Peeky test","body":"hello","userId":1}',
      );
      _add('POST 201: ${res.statusCode}');
    } catch (e) {
      _add('Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _get404() async {
    setState(() => _loading = true);
    try {
      final res = await _client
          .get(Uri.parse('https://jsonplaceholder.typicode.com/posts/99999'));
      _add('GET 404: ${res.statusCode}');
    } catch (e) {
      _add('Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _networkError() async {
    setState(() => _loading = true);
    try {
      await _client.get(Uri.parse('https://this.domain.does.not.exist/'));
      _add('Unexpected success');
    } catch (e) {
      _add('Network error captured ✓');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _add(String msg) => setState(() => _messages.insert(0, msg));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Peeky Example'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Shake the device to open the inspector',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text(
                        '📳 Shake the device to open the Peeky inspector')),
              );
            },
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Tap buttons to fire API calls, then shake to inspect them.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
                onPressed: _loading ? null : _get200,
                child: const Text('GET /posts/1  → 200')),
            const SizedBox(height: 8),
            ElevatedButton(
                onPressed: _loading ? null : _post201,
                child: const Text('POST /posts  → 201')),
            const SizedBox(height: 8),
            ElevatedButton(
                onPressed: _loading ? null : _get404,
                child: const Text('GET /posts/99999  → 404')),
            const SizedBox(height: 8),
            OutlinedButton(
                onPressed: _loading ? null : _networkError,
                child: const Text('Invalid URL  → Network error')),
            const SizedBox(height: 20),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: _messages.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(_messages[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
