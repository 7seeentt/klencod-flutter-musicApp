import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:on_audio_query_forked/on_audio_query.dart';
import 'package:shared_preferences/shared_preferences.dart';

final player = AudioPlayer();
final audioQuery = OnAudioQuery();
List<SongModel> queue = [];
List<SongModel> allSongs = [];

const bg = Color(0xFF0E0E14);
const cardColor = Color(0xFF1A1A24);
const accent = Color(0xFF8B5CF6);

String fmt(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '${d.inMinutes}:$s';
}

String artistOf(SongModel s) {
  final a = s.artist;
  return (a == null || a == '<unknown>') ? 'فنان غير معروف' : a;
}

String albumOf(SongModel s) {
  final a = s.album;
  return (a == null || a == '<unknown>') ? 'ألبوم غير معروف' : a;
}

List<SongModel> songsByIds(List<int> ids) {
  final byId = {for (final s in allSongs) s.id: s};
  return [
    for (final id in ids)
      if (byId[id] != null) byId[id]!
  ];
}

// ---------- المفضلة وقوائم التشغيل ----------
class UserLibrary extends ChangeNotifier {
  Set<int> favorites = {};
  Map<String, List<int>> playlists = {};
  SharedPreferences? _p;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _p = p;
    favorites = (p.getStringList('fav') ?? []).map(int.parse).toSet();
    final raw = p.getString('playlists');
    if (raw != null) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        playlists = m.map((k, v) =>
            MapEntry(k, (v as List).map((e) => e as int).toList()));
      } catch (_) {}
    }
    notifyListeners();
  }

  bool isFav(int id) => favorites.contains(id);

  void toggleFav(int id) {
    if (!favorites.remove(id)) favorites.add(id);
    _save();
  }

  void createPlaylist(String name) {
    if (name.isEmpty || playlists.containsKey(name)) return;
    playlists[name] = [];
    _save();
  }

  void deletePlaylist(String name) {
    playlists.remove(name);
    _save();
  }

  void addToPlaylist(String name, int id) {
    final l = playlists.putIfAbsent(name, () => []);
    if (!l.contains(id)) l.add(id);
    _save();
  }

  void removeFromPlaylist(String name, int id) {
    playlists[name]?.remove(id);
    _save();
  }

  void _save() {
    _p?.setStringList('fav', favorites.map((e) => e.toString()).toList());
    _p?.setString('playlists', jsonEncode(playlists));
    notifyListeners();
  }
}

final userLib = UserLibrary();

// ---------- التشغيل ----------
AudioSource _source(SongModel s) {
  final aid = s.albumId;
  return AudioSource.uri(
    Uri.parse(s.uri!),
    tag: MediaItem(
      id: s.id.toString(),
      title: s.title,
      artist: artistOf(s),
      duration: Duration(milliseconds: s.duration ?? 0),
      artUri: aid == null
          ? null
          : Uri.parse('content://media/external/audio/albumart/$aid'),
    ),
  );
}

ConcatenatingAudioSource _concat(List<SongModel> songs) =>
    ConcatenatingAudioSource(children: songs.map(_source).toList());

Future<void> playQueue(List<SongModel> songs, int index,
    {bool? shuffle}) async {
  queue = songs;
  if (shuffle != null) await player.setShuffleModeEnabled(shuffle);
  await player.setAudioSource(_concat(songs), initialIndex: index);
  player.play();
  saveQueue();
}

// ---------- حفظ واسترجاع آخر تشغيل ----------
Future<void> saveQueue() async {
  final p = await SharedPreferences.getInstance();
  await p.setStringList(
      'queue_ids', queue.map((s) => s.id.toString()).toList());
}

Future<void> saveProgress() async {
  if (queue.isEmpty) return;
  final p = await SharedPreferences.getInstance();
  await p.setInt('last_index', player.currentIndex ?? 0);
  await p.setInt('last_pos', player.position.inMilliseconds);
}

Future<void> restoreLast(List<SongModel> all) async {
  if (queue.isNotEmpty) return;
  try {
    final p = await SharedPreferences.getInstance();
    final ids = p.getStringList('queue_ids');
    if (ids == null || ids.isEmpty) return;
    final byId = {for (final s in all) s.id.toString(): s};
    final songs = [
      for (final id in ids)
        if (byId[id] != null) byId[id]!
    ];
    if (songs.isEmpty) return;
    var index = p.getInt('last_index') ?? 0;
    if (index >= songs.length) index = 0;
    queue = songs;
    await player.setAudioSource(
      _concat(songs),
      initialIndex: index,
      initialPosition: Duration(milliseconds: p.getInt('last_pos') ?? 0),
    );
  } catch (_) {}
}
// ===== END core =====