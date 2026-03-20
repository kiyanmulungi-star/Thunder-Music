// lib/main.dart
// Single-file Thunder Music app with runtime token dialog.
// Add to pubspec.yaml: http: ^0.13.6, cupertino_icons: ^1.0.5
// Run: flutter pub get && flutter run -d chrome
// Before testing: obtain a Spotify access token and paste it via the key icon.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const ThunderMusicApp());
}

class ThunderMusicApp extends StatelessWidget {
  const ThunderMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Thunder Music',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        useMaterial3: true,
      ),
      home: const ThunderMusicHome(),
    );
  }
}

/// Spotify helper. For quick testing paste a token into SpotifyApi.accessToken
class SpotifyApi {
  // For quick testing you can set a token here, but prefer pasting at runtime.
  static String accessToken = '<PASTE_SPOTIFY_ACCESS_TOKEN_HERE>';

  static Future<List<Map<String, dynamic>>> searchTracks(String query) async {
    if (accessToken.isEmpty || accessToken.startsWith('<')) {
      throw Exception(
          'Spotify access token missing. Implement OAuth or set accessToken.');
    }

    final url = Uri.https('api.spotify.com', '/v1/search', {
      'q': query,
      'type': 'track',
      'limit': '20',
    });

    http.Response resp;
    try {
      resp = await http.get(url, headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 10));
    } on SocketException {
      throw Exception('Network error. Check your connection.');
    } on TimeoutException {
      throw Exception('Request timed out. Try again.');
    }

    if (resp.statusCode != 200) {
      String message = 'Spotify search failed: ${resp.statusCode}';
      try {
        final body = jsonDecode(resp.body);
        if (body is Map && body['error'] != null) {
          final err = body['error'];
          message = 'Spotify error: ${err['message'] ?? resp.body}';
        } else {
          message = 'Spotify error: ${resp.body}';
        }
      } catch (_) {}
      throw Exception(message);
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final items = (data['tracks']?['items'] ?? []) as List<dynamic>;

    return items.map((it) {
      final artists =
          (it['artists'] as List<dynamic>).map((a) => a['name']).join(', ');
      final images = (it['album']?['images'] ?? []) as List<dynamic>;
      final imageUrl = images.isNotEmpty ? images.first['url'] as String : '';
      return {
        'id': it['id'],
        'name': it['name'],
        'artists': artists,
        'album': it['album']?['name'] ?? '',
        'image': imageUrl,
        'uri': it['uri'],
      };
    }).toList();
  }
}

class ThunderMusicHome extends StatefulWidget {
  const ThunderMusicHome({super.key});

  @override
  State<ThunderMusicHome> createState() => _ThunderMusicHomeState();
}

class _ThunderMusicHomeState extends State<ThunderMusicHome> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  String? _error;

  // Playback state (mock)
  Map<String, dynamic>? _currentTrack;
  bool _isPlaying = false;
  double _position = 0.0; // 0.0 - 1.0
  Timer? _progressTimer;
  bool _shuffle = false;
  bool _repeat = false;
  final Random _random = Random();

  Future<void> _search() async {
    final q = _searchController.text.trim();
    if (q.isEmpty) return;
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _results = [];
    });
    try {
      final tracks = await SpotifyApi.searchTracks(q);
      if (!mounted) return;
      setState(() {
        _results = tracks;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _startPlayback(Map<String, dynamic> track) {
    _stopProgress();
    if (!mounted) return;
    setState(() {
      _currentTrack = track;
      _isPlaying = true;
      _position = 0.0;
    });
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _stopProgress();
        return;
      }
      setState(() {
        _position += 0.01;
        if (_position >= 1.0) {
          if (_repeat) {
            _position = 0.0;
          } else {
            _isPlaying = false;
            _stopProgress();
          }
        }
      });
    });
  }

  void _stopProgress() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  void _togglePlayPause() {
    if (!mounted) return;
    setState(() {
      _isPlaying = !_isPlaying;
    });
    if (_isPlaying && _progressTimer == null) {
      _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) {
          _stopProgress();
          return;
        }
        setState(() {
          _position += 0.01;
          if (_position >= 1.0) {
            if (_repeat) {
              _position = 0.0;
            } else {
              _isPlaying = false;
              _stopProgress();
            }
          }
        });
      });
    } else if (!_isPlaying) {
      _stopProgress();
    }
  }

  void _nextTrack() {
    if (_results.isEmpty) return;
    if (_shuffle) {
      final idx = _random.nextInt(_results.length);
      _startPlayback(_results[idx]);
      return;
    }
    if (_currentTrack == null) {
      _startPlayback(_results.first);
      return;
    }
    final currentIndex =
        _results.indexWhere((t) => t['id'] == _currentTrack!['id']);
    final nextIndex = (currentIndex + 1) % _results.length;
    _startPlayback(_results[nextIndex]);
  }

  void _previousTrack() {
    if (_results.isEmpty) return;
    if (_currentTrack == null) {
      _startPlayback(_results.first);
      return;
    }
    final currentIndex =
        _results.indexWhere((t) => t['id'] == _currentTrack!['id']);
    final prevIndex =
        (currentIndex - 1) < 0 ? _results.length - 1 : currentIndex - 1;
    _startPlayback(_results[prevIndex]);
  }

  @override
  void dispose() {
    _stopProgress();
    _searchController.dispose();
    super.dispose();
  }

  // --- Token dialog: paste token at runtime ---
  void _showSetTokenDialog() {
    final controller = TextEditingController(text: SpotifyApi.accessToken);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set Spotify Access Token'),
        content: TextField(
          controller: controller,
          decoration:
              const InputDecoration(hintText: 'Paste access token here'),
          maxLines: 3,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final token = controller.text.trim();
              if (token.isNotEmpty) {
                SpotifyApi.accessToken = token;
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Token saved')));
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _buildNowPlaying() {
    if (_currentTrack == null) {
      return const SizedBox.shrink();
    }
    final track = _currentTrack!;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: track['image'] != null &&
                        (track['image'] as String).isNotEmpty
                    ? Image.network(
                        track['image'] as String,
                        width: 84,
                        height: 84,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) {
                          return Container(
                              width: 84,
                              height: 84,
                              color: Colors.grey.shade300);
                        },
                      )
                    : Container(
                        width: 84, height: 84, color: Colors.grey.shade300),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(track['name'] ?? '',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(track['artists'] ?? '',
                        style: TextStyle(color: Colors.grey.shade700)),
                    const SizedBox(height: 6),
                    Text(track['album'] ?? '',
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              Slider(
                value: _position.clamp(0.0, 1.0),
                onChanged: (v) {
                  if (!mounted) return;
                  setState(() => _position = v);
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatTime(
                      _position * 180)), // assume 3:00 track for demo
                  Text(_formatTime(180)),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(_shuffle ? Icons.shuffle_on : Icons.shuffle),
                onPressed: () {
                  if (!mounted) return;
                  setState(() => _shuffle = !_shuffle);
                },
              ),
              IconButton(
                icon: const Icon(Icons.skip_previous),
                iconSize: 36,
                onPressed: _previousTrack,
              ),
              IconButton(
                icon: Icon(_isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_filled),
                iconSize: 64,
                onPressed: _togglePlayPause,
              ),
              IconButton(
                icon: const Icon(Icons.skip_next),
                iconSize: 36,
                onPressed: _nextTrack,
              ),
              IconButton(
                icon: Icon(_repeat ? Icons.repeat_on : Icons.repeat),
                onPressed: () {
                  if (!mounted) return;
                  setState(() => _repeat = !_repeat);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatTime(double seconds) {
    final s = seconds.round();
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thunder Music'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.vpn_key),
            tooltip: 'Set Spotify token',
            onPressed: _showSetTokenDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Rounded search bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search Spotify',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 0, horizontal: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _search,
                    style: ElevatedButton.styleFrom(
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                    child: const Text('Search'),
                  ),
                ],
              ),
            ),

            if (_loading) const LinearProgressIndicator(),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),

            // Results list
            Expanded(
              child: _results.isEmpty
                  ? Center(
                      child: Text(_loading
                          ? 'Searching...'
                          : 'No results yet. Try searching Spotify.'))
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final t = _results[index];
                        return ListTile(
                          leading: t['image'] != null &&
                                  (t['image'] as String).isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.network(
                                    t['image'] as String,
                                    width: 56,
                                    height: 56,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) {
                                      return Container(
                                          width: 56,
                                          height: 56,
                                          color: Colors.grey.shade300);
                                    },
                                  ),
                                )
                              : Container(
                                  width: 56,
                                  height: 56,
                                  color: Colors.grey.shade300),
                          title: Text(t['name'] ?? ''),
                          subtitle: Text(t['artists'] ?? ''),
                          trailing: IconButton(
                            icon: const Icon(Icons.play_arrow),
                            onPressed: () => _startPlayback(t),
                          ),
                          onTap: () => _startPlayback(t),
                        );
                      },
                    ),
            ),

            // Now playing area (if any)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _currentTrack != null
                  ? _buildNowPlaying()
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
