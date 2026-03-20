// lib/main.dart
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MyApp());
}

// ---------- PKCE helpers ----------
String _randomString(int length) {
  final rand = Random.secure();
  final bytes = List<int>.generate(length, (_) => rand.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

String _codeChallenge(String verifier) {
  final bytes = sha256.convert(utf8.encode(verifier)).bytes;
  return base64Url.encode(bytes).replaceAll('=', '');
}

// ---------- Auth service (minimal) ----------
class SpotifyAuthService {
  final String clientId;
  final String redirectUri;
  final List<String> scopes;
  final _storage = const FlutterSecureStorage();

  SpotifyAuthService({
    required this.clientId,
    required this.redirectUri,
    required this.scopes,
  });

  Future<void> authenticate() async {
    final verifier = _randomString(64);
    final challenge = _codeChallenge(verifier);

    final authUri = Uri.https('accounts.spotify.com', '/authorize', {
      'client_id': clientId,
      'response_type': 'code',
      'redirect_uri': redirectUri,
      'code_challenge_method': 'S256',
      'code_challenge': challenge,
      'scope': scopes.join(' ')
    });

    final result = await FlutterWebAuth2.authenticate(
      url: authUri.toString(),
      callbackUrlScheme: Uri.parse(redirectUri).scheme,
    );

    final code = Uri.parse(result).queryParameters['code'];
    if (code == null) throw Exception('Authorization code not returned');

    final tokenResp = await http.post(
      Uri.parse('https://accounts.spotify.com/api/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirectUri,
        'client_id': clientId,
        'code_verifier': verifier,
      },
    );

    final json = jsonDecode(tokenResp.body) as Map<String, dynamic>;
    if (json.containsKey('error')) {
      throw Exception(json['error_description'] ?? json['error']);
    }

    await _storage.write(
        key: 'spotify_access_token', value: json['access_token']);
    if (json.containsKey('refresh_token')) {
      await _storage.write(
          key: 'spotify_refresh_token', value: json['refresh_token']);
    }
    if (json.containsKey('expires_in')) {
      await _storage.write(
        key: 'spotify_token_expires_at',
        value: DateTime.now()
            .add(Duration(seconds: json['expires_in']))
            .toIso8601String(),
      );
    }
  }

  Future<String?> getAccessToken() async {
    final token = await _storage.read(key: 'spotify_access_token');
    final expiresAt = await _storage.read(key: 'spotify_token_expires_at');
    if (token == null) return null;
    if (expiresAt != null &&
        DateTime.parse(expiresAt).isBefore(DateTime.now())) {
      return await refreshToken();
    }
    return token;
  }

  Future<String?> refreshToken() async {
    final refresh = await _storage.read(key: 'spotify_refresh_token');
    if (refresh == null) return null;

    final resp = await http.post(
      Uri.parse('https://accounts.spotify.com/api/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': refresh,
        'client_id': clientId,
      },
    );

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    if (json.containsKey('error')) {
      throw Exception(json['error_description'] ?? json['error']);
    }

    if (json.containsKey('access_token')) {
      await _storage.write(
          key: 'spotify_access_token', value: json['access_token']);
      if (json.containsKey('expires_in')) {
        await _storage.write(
          key: 'spotify_token_expires_at',
          value: DateTime.now()
              .add(Duration(seconds: json['expires_in']))
              .toIso8601String(),
        );
      }
      return json['access_token'];
    }
    return null;
  }

  Future<void> signOut() async => await _storage.deleteAll();
}

// ---------- UI with search ----------
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Thunder Music (Spotify Search)',
      theme: ThemeData.dark(),
      home: const SpotifySearchScreen(),
    );
  }
}

class SpotifySearchScreen extends StatefulWidget {
  const SpotifySearchScreen({super.key});

  @override
  State<SpotifySearchScreen> createState() => _SpotifySearchScreenState();
}

class _SpotifySearchScreenState extends State<SpotifySearchScreen> {
  final _controller = TextEditingController();
  final List<Map<String, dynamic>> _tracks = [];
  bool _loading = false;

  // *** REPLACE THESE VALUES ***
  final _auth = SpotifyAuthService(
    clientId: 'eee7f530a6574d79a99f04674240ddcf', // your Spotify app client ID
    redirectUri: 'https://thundermusic.com',
    scopes: ['user-read-email'], // add scopes you need
  );

  Future<void> _ensureAuth() async {
    final token = await _auth.getAccessToken();
    if (token == null) {
      await _auth.authenticate();
    }
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      await _ensureAuth();
      final token = await _auth.getAccessToken();
      if (token == null) throw Exception('No access token');

      final uri = Uri.https('api.spotify.com', '/v1/search',
          {'q': q, 'type': 'track', 'limit': '12'});
      final resp =
          await http.get(uri, headers: {'Authorization': 'Bearer $token'});

      if (resp.statusCode == 401) {
        await _auth.refreshToken();
        final retryToken = await _auth.getAccessToken();
        final retry = await http
            .get(uri, headers: {'Authorization': 'Bearer $retryToken'});
        if (retry.statusCode != 200) {
          throw Exception('Search failed: ${retry.body}');
        }
        final json = jsonDecode(retry.body);
        setState(() => _tracks.clear());
        for (var item in json['tracks']['items']) {
          _tracks.add(Map<String, dynamic>.from(item));
        }
      } else if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body);
        setState(() {
          _tracks.clear();
          for (var item in json['tracks']['items']) {
            _tracks.add(Map<String, dynamic>.from(item));
          }
        });
      } else {
        throw Exception('Search failed: ${resp.body}');
      }
    } catch (e) {
      debugPrint('Search error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  Widget _buildTile(Map<String, dynamic> track) {
    final name = track['name'] ?? 'Unknown';
    final artist = (track['artists'] as List).isNotEmpty
        ? track['artists'][0]['name']
        : 'Unknown';
    final image = (track['album']?['images'] as List?)?.isNotEmpty == true
        ? track['album']['images'][0]['url']
        : null;
    final preview = track['preview_url']; // may be null
    return ListTile(
      leading: image != null
          ? Image.network(image, width: 56, height: 56, fit: BoxFit.cover)
          : const Icon(Icons.music_note),
      title: Text(name),
      subtitle: Text(artist),
      trailing: preview != null ? const Icon(Icons.play_arrow) : null,
      onTap: () {
        // For now just show preview availability
        final msg =
            preview != null ? 'Preview available' : 'No preview for this track';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thunder Music — Spotify Search'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await _auth.signOut();
              if (mounted) {
                messenger
                    .showSnackBar(const SnackBar(content: Text('Signed out')));
              }
            },
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: 'Search tracks, artists, albums',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _search(_controller.text),
                ),
              ),
              onSubmitted: _search,
            ),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(),
            Expanded(
              child: ListView.builder(
                itemCount: _tracks.length,
                itemBuilder: (_, i) => _buildTile(_tracks[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
