import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

const clientId = 'e8d898e5';

class Track {
  final String name, artist, image, audio;
  Track(this.name, this.artist, this.image, this.audio);
  factory Track.fromJson(Map<String, dynamic> j) => Track(
        j['name'] ?? '',
        j['artist_name'] ?? '',
        j['image'] ?? '',
        j['audio'] ?? '',
      );
}

Future<List<Track>> fetchTracks({String query = ''}) async {
  final uri = Uri.https('api.jamendo.com', '/v3.0/tracks/', {
    'client_id': clientId,
    'format': 'json',
    'limit': '30',
    'imagesize': '300',
    if (query.isEmpty) 'order': 'popularity_week' else 'search': query,
  });
  final res = await http.get(uri);
  final data = jsonDecode(res.body);
  return (data['results'] as List).map((e) => Track.fromJson(e)).toList();
}

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: const HomePage(),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _player = AudioPlayer();
  List<Track> _tracks = [];
  Track? _current;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _load(String q) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final t = await fetchTracks(query: q);
      setState(() {
        _tracks = t;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'تعذر تحميل الأغاني';
        _loading = false;
      });
    }
  }

  Future<void> _play(Track t) async {
    setState(() => _current = t);
    await _player.setUrl(t.audio);
    _player.play();
  }

  Widget _cover(String url, double size) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
              width: size,
              height: size,
              color: Colors.white12,
              child: const Icon(Icons.music_note)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          decoration: const InputDecoration(
              hintText: 'ابحث عن أغنية أو فنان',
              border: InputBorder.none),
          onSubmitted: _load,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView.builder(
                  itemCount: _tracks.length,
                  itemBuilder: (_, i) {
                    final t = _tracks[i];
                    return ListTile(
                      leading: _cover(t.image, 52),
                      title: Text(t.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(t.artist),
                      onTap: () => _play(t),
                    );
                  },
                ),
      bottomNavigationBar: _current == null
          ? null
          : SafeArea(
              child: Container(
                color: const Color(0xFF1E1E26),
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    _cover(_current!.image, 48),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_current!.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(_current!.artist,
                              style: const TextStyle(
                                  color: Colors.white60, fontSize: 12)),
                        ],
                      ),
                    ),
                    StreamBuilder<PlayerState>(
                      stream: _player.playerStateStream,
                      builder: (_, snap) {
                        final playing = snap.data?.playing ?? false;
                        return IconButton(
                          iconSize: 40,
                          icon: Icon(playing
                              ? Icons.pause_circle
                              : Icons.play_circle),
                          onPressed:
                              playing ? _player.pause : _player.play,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}