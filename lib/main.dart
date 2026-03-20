// lib/main.dart
// Minimal, ready-to-paste Flutter app compatible with web and the pubspec.yaml you added.
// Guards web-unsafe packages with kIsWeb to avoid runtime issues on web builds.

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Thunder Music Demo',
      theme: ThemeData(primarySwatch: Colors.indigo),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _storage = const FlutterSecureStorage();
  String _httpResult = 'No request yet';
  String _hashResult = '';
  String _storageResult = 'no value';
  String _authResult = 'not attempted';

  Future<void> _doHttpGet() async {
    try {
      final res = await http.get(Uri.parse('https://httpbin.org/get'));
      setState(() => _httpResult = 'Status ${res.statusCode}');
    } catch (e) {
      setState(() => _httpResult = 'Error: $e');
    }
  }

  void _computeHash() {
    final bytes = utf8.encode('thunder_music_example');
    final digest = sha256.convert(bytes);
    setState(() => _hashResult = digest.toString());
  }

  Future<void> _useSecureStorage() async {
    try {
      if (kIsWeb) {
        setState(() => _storageResult = 'Secure storage skipped on web');
        return;
      }
      await _storage.write(key: 'demo_key', value: 'demo_value');
      final v = await _storage.read(key: 'demo_key');
      setState(() => _storageResult = v ?? 'null');
    } catch (e) {
      setState(() => _storageResult = 'Error: $e');
    }
  }

  Future<void> _startWebAuth() async {
    try {
      if (kIsWeb) {
        setState(
            () => _authResult = 'Web auth skipped on web (use provider SDK)');
        return;
      }
      final result = await FlutterWebAuth2.authenticate(
        url: 'https://example.com/auth?demo=1',
        callbackUrlScheme: 'example',
      );
      setState(() => _authResult = 'Result: $result');
    } catch (e) {
      setState(() => _authResult = 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thunder Music — Demo'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ElevatedButton.icon(
              onPressed: _doHttpGet,
              icon: const Icon(Icons.cloud_download),
              label: const Text('HTTP GET (httpbin)'),
            ),
            const SizedBox(height: 8),
            Text('HTTP: $_httpResult'),
            const Divider(),
            ElevatedButton.icon(
              onPressed: _computeHash,
              icon: const Icon(Icons.lock),
              label: const Text('Compute SHA-256'),
            ),
            const SizedBox(height: 8),
            Text('SHA-256: $_hashResult'),
            const Divider(),
            ElevatedButton.icon(
              onPressed: _useSecureStorage,
              icon: const Icon(Icons.storage),
              label: const Text('Test Secure Storage'),
            ),
            const SizedBox(height: 8),
            Text('Storage: $_storageResult'),
            const Divider(),
            ElevatedButton.icon(
              onPressed: _startWebAuth,
              icon: const Icon(Icons.login),
              label: const Text('Start Web Auth (demo)'),
            ),
            const SizedBox(height: 8),
            Text('Auth: $_authResult'),
            const Spacer(),
            const Text(
              'Notes: Secure storage and web auth are guarded for web builds. '
              'Replace demo URLs and callback schemes with your real values.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
