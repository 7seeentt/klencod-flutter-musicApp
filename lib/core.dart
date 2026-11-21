import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:on_audio_query_forked/on_audio_query.dart';
import 'package:shared_preferences/shared_preferences.dart';

final player = AudioPlayer();
final audioQuery = OnAudioQuery();
List<SongModel> queue = [];
List<SongModel> allSongs = [];
ConcatenatingAudioSource? playlistSource;

const unknownArtist = 'فنان غير معروف';
const accents = <Color>[
  Color(0xFF8B5CF6), Color(0xFF3B82F6), Color(0xFF10B981),
  Color(0xFFF59E0B), Color(0xFFEF4444), Color(0xFFEC4899),
];

extension UiColors on BuildContext {
  Color get accent => Theme.of(this).colorScheme.primary;
  Color get card => Theme.of(this).cardColor;
  Color get bg => Theme.of(this).scaffoldBackgroundColor;
}

String fmt(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '${d.inMinutes}:$s';
}

String artistOf(SongModel s) {
  final a = s.artist;
  return (a == null || a == '<unknown>') ? unknownArtist : a;
}

String albumOf(SongModel s) {
  final a = s.album;
  return (a == null || a == '<unknown>') ? 'ألبوم غير معروف' : a;
}

List<SongModel> songsByIds(List<int> ids) {
  final byId = {for (final s in allSongs) s.id: s};
  return [for (final id in ids) if (byId[id] != null) byId[id]!];
}

void sortSongs(List<SongModel> l) {
  switch (settings.sortIndex) {
    case 1:
      l.sort((a, b) => artistOf(a).toLowerCase().compareTo(artistOf(b).toLowerCase()));
      break;
    case 2:
      l.sort((a, b) => (b.dateAdded ?? 0).compareTo(a.dateAdded ?? 0));
      break;
    case 3:
      l.sort((a, b) => (b.duration ?? 0).compareTo(a.duration ?? 0));
      break;
    default:
      l.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }
}

// ---------- الإعدادات ----------
class AppSettings extends ChangeNotifier {
  int accentIndex = 0;
  bool amoled = false;
  bool dynamicColors = true;
  bool blurBg = true;
  int minSeconds = 30;
  int sortIndex = 0;
  SharedPreferences? _p;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _p = p;
    accentIndex = (p.getInt('s_accent') ?? 0).clamp(0, accents.length - 1).toInt();
    amoled = p.getBool('s_amoled') ?? false;
    dynamicColors = p.getBool('s_dyn') ?? true;
    blurBg = p.getBool('s_blur') ?? true;
    minSeconds = p.getInt('s_min') ?? 30;
    sortIndex = p.getInt('s_sort') ?? 0;
    notifyListeners();
  }

  void update(void Function() change) {
    change();
    final p = _p;
    if (p != null) {
      p.setInt('s_accent', accentIndex);
      p.setBool('s_amoled', amoled);
      p.setBool('s_dyn', dynamicColors);
      p.setBool('s_blur', blurBg);
      p.setInt('s_min', minSeconds);
      p.setInt('s_sort', sortIndex);
    }
    notifyListeners();
  }

  Map<String, dynamic> toMap() => {
        'accent': accentIndex, 'amoled': amoled, 'dyn': dynamicColors,
        'blur': blurBg, 'min': minSeconds, 'sort': sortIndex,
      };

  void fromMap(Map<String, dynamic> m) => update(() {
        accentIndex = ((m['accent'] as num?)?.toInt() ?? 0).clamp(0, accents.length - 1).toInt();
        amoled = (m['amoled'] as bool?) ?? false;
        dynamicColors = (m['dyn'] as bool?) ?? true;
        blurBg = (m['blur'] as bool?) ?? true;
        minSeconds = (m['min'] as num?)?.toInt() ?? 30;
        sortIndex = (m['sort'] as num?)?.toInt() ?? 0;
      });
}

final settings = AppSettings();

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
        playlists = m.map((k, v) => MapEntry(k, (v as List).map((e) => e as int).toList()));
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

  Map<String, dynamic> toMap() => {'fav': favorites.toList(), 'playlists': playlists};

  void fromMap(Map<String, dynamic> m) {
    favorites = ((m['fav'] as List?) ?? []).map((e) => (e as num).toInt()).toSet();
    final pl = (m['playlists'] as Map?) ?? {};
    playlists = {
      for (final e in pl.entries)
        e.key.toString(): [for (final x in (e.value as List)) (x as num).toInt()]
    };
    _save();
  }

  void _save() {
    _p?.setStringList('fav', favorites.map((e) => e.toString()).toList());
    _p?.setString('playlists', jsonEncode(playlists));
    notifyListeners();
  }
}

final userLib = UserLibrary();

String backupJson() =>
    jsonEncode({'v': 1, 'library': userLib.toMap(), 'settings': settings.toMap()});

bool restoreBackup(String text) {
  try {
    final m = jsonDecode(text) as Map<String, dynamic>;
    userLib.fromMap(Map<String, dynamic>.from(m['library'] as Map));
    settings.fromMap(Map<String, dynamic>.from(m['settings'] as Map));
    return true;
  } catch (_) {
    return false;
  }
}

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
      artUri: aid == null ? null : Uri.parse('content://media/external/audio/albumart/$aid'),
    ),
  );
}

ConcatenatingAudioSource _concat(List<SongModel> songs) =>
    ConcatenatingAudioSource(children: songs.map(_source).toList());

Future<void> playQueue(List<SongModel> songs, int index, {bool? shuffle}) async {
  queue = List.of(songs);
  if (shuffle != null) await player.setShuffleModeEnabled(shuffle);
  final src = _concat(queue);
  playlistSource = src;
  await player.setAudioSource(src, initialIndex: index);
  player.play();
  saveQueue();
}

Future<void> playNext(SongModel s) async {
  final src = playlistSource;
  if (src == null || queue.isEmpty) {
    await playQueue([s], 0);
    return;
  }
  final at = ((player.currentIndex ?? -1) + 1).clamp(0, queue.length).toInt();
  queue.insert(at, s);
  await src.insert(at, _source(s));
  saveQueue();
}

Future<void> addToQueue(SongModel s) async {
  final src = playlistSource;
  if (src == null || queue.isEmpty) {
    await playQueue([s], 0);
    return;
  }
  queue.add(s);
  await src.add(_source(s));
  saveQueue();
}

Future<void> moveInQueue(int from, int to) async {
  final s = queue.removeAt(from);
  queue.insert(to, s);
  await playlistSource?.move(from, to);
  saveQueue();
}

Future<void> removeFromQueue(int i) async {
  queue.removeAt(i);
  await playlistSource?.removeAt(i);
  saveQueue();
}

// ---------- حفظ واسترجاع آخر تشغيل ----------
Future<void> saveQueue() async {
  final p = await SharedPreferences.getInstance();
  await p.setStringList('queue_ids', queue.map((s) => s.id.toString()).toList());
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
    final songs = [for (final id in ids) if (byId[id] != null) byId[id]!];
    if (songs.isEmpty) return;
    var index = p.getInt('last_index') ?? 0;
    if (index >= songs.length) index = 0;
    queue = songs;
    final src = _concat(songs);
    playlistSource = src;
    await player.setAudioSource(
      src,
      initialIndex: index,
      initialPosition: Duration(milliseconds: p.getInt('last_pos') ?? 0),
    );
  } catch (_) {}
}

// ---------- مؤقّت النوم ----------
final sleepLeft = ValueNotifier<Duration?>(null);
Timer? _sleepTimer;

void startSleep(Duration d) {
  cancelSleep();
  sleepLeft.value = d;
  _sleepTimer = Timer.periodic(const Duration(seconds: 1), (t) {
    final left = (sleepLeft.value ?? Duration.zero) - const Duration(seconds: 1);
    if (left <= Duration.zero) {
      t.cancel();
      _sleepTimer = null;
      sleepLeft.value = null;
      _fadeOutAndPause();
    } else {
      sleepLeft.value = left;
    }
  });
}

void cancelSleep() {
  _sleepTimer?.cancel();
  _sleepTimer = null;
  sleepLeft.value = null;
}

Future<void> _fadeOutAndPause() async {
  for (var i = 9; i >= 0; i--) {
    await player.setVolume(i / 10);
    await Future.delayed(const Duration(milliseconds: 250));
  }
  await player.pause();
  await player.setVolume(1.0);
}

// ---------- صورة الغلاف ولونه ----------
class ArtInfo {
  final Uint8List? bytes;
  final Color? color;
  ArtInfo(this.bytes, this.color);
}

final Map<int, ArtInfo> _artCache = {};

ArtInfo? cachedArt(int id) => _artCache[id];

Future<ArtInfo> artInfoFor(int id) async {
  final c = _artCache[id];
  if (c != null) return c;
  Uint8List? bytes;
  Color? color;
  try {
    bytes = await audioQuery.queryArtwork(id, ArtworkType.AUDIO, size: 400);
    if (bytes != null && bytes.isNotEmpty) {
      final scheme = await ColorScheme.fromImageProvider(
        provider: MemoryImage(bytes),
        brightness: Brightness.dark,
      );
      color = scheme.primary;
    }
  } catch (_) {}
  final info = ArtInfo(bytes, color);
  if (_artCache.length > 60) _artCache.remove(_artCache.keys.first);
  _artCache[id] = info;
  return info;
}
// ===== END core =====