import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:on_audio_query_forked/on_audio_query.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core.dart';

class LrcLine {
  final Duration time;
  final String text;
  LrcLine(this.time, this.text);
}

class LyricsResult {
  final List<LrcLine> synced;
  final String plain;
  LyricsResult(this.synced, this.plain);
  bool get hasAny => synced.isNotEmpty || plain.trim().isNotEmpty;
}

List<LrcLine> parseLrc(String raw) {
  final out = <LrcLine>[];
  final re = RegExp(r'\[(\d+):(\d+(?:\.\d+)?)\]');
  for (final line in raw.split('\n')) {
    final matches = re.allMatches(line).toList();
    if (matches.isEmpty) continue;
    final text = line.replaceAll(re, '').trim();
    for (final m in matches) {
      final min = int.parse(m.group(1)!);
      final sec = double.parse(m.group(2)!);
      out.add(LrcLine(Duration(milliseconds: ((min * 60 + sec) * 1000).round()), text));
    }
  }
  out.sort((a, b) => a.time.compareTo(b.time));
  return out;
}

const _headers = {'User-Agent': 'musicApp/1.0 (personal use)'};
final Map<int, LyricsResult> _mem = {};

bool _hasText(Map<String, dynamic> m) =>
    ((m['syncedLyrics'] ?? '') as String).isNotEmpty ||
    ((m['plainLyrics'] ?? '') as String).isNotEmpty;

Future<List<Map<String, dynamic>>> lrclibSearch(String title, String artist) async {
  try {
    final q = '$title $artist'.trim();
    if (q.isEmpty) return [];
    final uri = Uri.https('lrclib.net', '/api/search', {'q': q});
    final r = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return [];
    final list = jsonDecode(utf8.decode(r.bodyBytes)) as List;
    return list.take(10).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  } catch (_) {
    return [];
  }
}

Future<Map<String, dynamic>?> _autoFind(SongModel s) async {
  final artist = artistOf(s);
  final known = artist != unknownArtist;
  try {
    if (known) {
      final uri = Uri.https('lrclib.net', '/api/get', {
        'track_name': s.title,
        'artist_name': artist,
        'duration': ((s.duration ?? 0) / 1000).round().toString(),
      });
      final r = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        final m = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        if (_hasText(m)) return m;
      }
    }
    final res = await lrclibSearch(s.title, known ? artist : '');
    for (final m in res) {
      if (_hasText(m)) return m;
    }
  } catch (_) {}
  return null;
}

Future<void> saveLyricsFor(int id, Map<String, dynamic> item) async {
  final synced = (item['syncedLyrics'] ?? '') as String;
  final plain = (item['plainLyrics'] ?? '') as String;
  _mem[id] = LyricsResult(parseLrc(synced), plain);
  final p = await SharedPreferences.getInstance();
  await p.setString('lyr_$id', jsonEncode({'s': synced, 'p': plain}));
}

Future<LyricsResult> getLyrics(SongModel s) async {
  final mem = _mem[s.id];
  if (mem != null) return mem;
  final p = await SharedPreferences.getInstance();
  final cached = p.getString('lyr_${s.id}');
  if (cached != null) {
    try {
      final m = jsonDecode(cached) as Map<String, dynamic>;
      final r = LyricsResult(parseLrc((m['s'] ?? '') as String), (m['p'] ?? '') as String);
      _mem[s.id] = r;
      return r;
    } catch (_) {}
  }
  final item = await _autoFind(s);
  if (item == null) return LyricsResult([], '');
  await saveLyricsFor(s.id, item);
  return _mem[s.id]!;
}

Future<void> clearLyricsCache() async {
  _mem.clear();
  final p = await SharedPreferences.getInstance();
  for (final k in p.getKeys().where((k) => k.startsWith('lyr_')).toList()) {
    await p.remove(k);
  }
}

// ---------- صفحة الكلمات ----------
class LyricsPage extends StatefulWidget {
  const LyricsPage({super.key});
  @override
  State<LyricsPage> createState() => _LyricsPageState();
}

class _LyricsPageState extends State<LyricsPage> {
  int? _forId;
  Future<LyricsResult>? _future;

  void _reload(SongModel s) {
    _forId = s.id;
    _future = getLyrics(s);
  }

  Future<void> _manual(SongModel s) async {
    final a = artistOf(s);
    final picked = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _LyricsSearchDialog(
        initialTitle: s.title,
        initialArtist: a == unknownArtist ? '' : a,
      ),
    );
    if (picked != null) {
      await saveLyricsFor(s.id, picked);
      if (mounted) setState(() => _reload(s));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<int?>(
        stream: player.currentIndexStream,
        builder: (context, snap) {
          final i = snap.data;
          if (i == null || i >= queue.length) return const SizedBox();
          final song = queue[i];
          if (_forId != song.id) _reload(song);
          return SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text(artistOf(song), maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white54, fontSize: 12)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.search),
                        tooltip: 'بحث يدوي',
                        onPressed: () => _manual(song),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: FutureBuilder<LyricsResult>(
                    future: _future,
                    builder: (context, fs) {
                      if (fs.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final r = fs.data;
                      if (r == null || !r.hasAny) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.lyrics_outlined, size: 56, color: Colors.white38),
                              const SizedBox(height: 12),
                              const Text('ما لقينا كلمات لهذي الأغنية'),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: () => _manual(song),
                                child: const Text('بحث يدوي'),
                              ),
                            ],
                          ),
                        );
                      }
                      if (r.synced.isNotEmpty) {
                        return _SyncedView(key: ValueKey(song.id), lines: r.synced);
                      }
                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Text(r.plain,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 20, height: 1.8)),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SyncedView extends StatefulWidget {
  final List<LrcLine> lines;
  const _SyncedView({super.key, required this.lines});
  @override
  State<_SyncedView> createState() => _SyncedViewState();
}

class _SyncedViewState extends State<_SyncedView> {
  final _c = ScrollController();
  int _last = -2;
  static const _ext = 64.0;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  int _indexFor(Duration pos) {
    var idx = -1;
    for (var i = 0; i < widget.lines.length; i++) {
      if (widget.lines[i].time <= pos) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, cons) {
      final pad = cons.maxHeight / 2 - _ext / 2;
      return StreamBuilder<Duration>(
        stream: player.positionStream,
        builder: (context, snap) {
          final idx = _indexFor(snap.data ?? Duration.zero);
          if (idx != _last) {
            _last = idx;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!_c.hasClients || idx < 0) return;
              final t = (idx * _ext).clamp(0.0, _c.position.maxScrollExtent).toDouble();
              _c.animateTo(t,
                  duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
            });
          }
          return ListView.builder(
            controller: _c,
            itemExtent: _ext,
            padding: EdgeInsets.symmetric(vertical: pad),
            itemCount: widget.lines.length,
            itemBuilder: (_, i) {
              final cur = i == idx;
              final line = widget.lines[i];
              return InkWell(
                onTap: () => player.seek(line.time),
                child: Center(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 250),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: cur ? 24 : 19,
                      fontWeight: cur ? FontWeight.bold : FontWeight.w500,
                      color: cur ? context.accent : (i < idx ? Colors.white38 : Colors.white54),
                    ),
                    child: Text(line.text.isEmpty ? '♪' : line.text),
                  ),
                ),
              );
            },
          );
        },
      );
    });
  }
}

class _LyricsSearchDialog extends StatefulWidget {
  final String initialTitle;
  final String initialArtist;
  const _LyricsSearchDialog({required this.initialTitle, required this.initialArtist});
  @override
  State<_LyricsSearchDialog> createState() => _LyricsSearchDialogState();
}

class _LyricsSearchDialogState extends State<_LyricsSearchDialog> {
  late final TextEditingController _t = TextEditingController(text: widget.initialTitle);
  late final TextEditingController _a = TextEditingController(text: widget.initialArtist);
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  bool _searched = false;

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _searched = true;
    });
    final r = await lrclibSearch(_t.text.trim(), _a.text.trim());
    if (!mounted) return;
    setState(() {
      _results = r.where(_hasText).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.card,
      title: const Text('بحث عن الكلمات'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: _t, decoration: const InputDecoration(labelText: 'اسم الأغنية')),
              const SizedBox(height: 8),
              TextField(controller: _a, decoration: const InputDecoration(labelText: 'الفنان (اختياري)')),
              const SizedBox(height: 12),
              FilledButton(onPressed: _search, child: const Text('بحث')),
              const SizedBox(height: 8),
              if (_loading)
                const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())
              else if (_searched && _results.isEmpty)
                const Padding(padding: EdgeInsets.all(12), child: Text('ما لقينا نتائج')),
              if (_results.isNotEmpty)
                SizedBox(
                  height: 240,
                  child: ListView(
                    children: [
                      for (final m in _results)
                        ListTile(
                          dense: true,
                          title: Text('${m['trackName'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${m['artistName'] ?? ''} • ${m['albumName'] ?? ''}',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Icon(((m['syncedLyrics'] ?? '') as String).isNotEmpty
                              ? Icons.timer_outlined
                              : Icons.notes),
                          onTap: () => Navigator.pop(context, m),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق'))],
    );
  }
}
// ===== END lyrics =====