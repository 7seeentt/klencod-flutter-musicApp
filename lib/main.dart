import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query_forked/on_audio_query.dart';

final player = AudioPlayer();
final audioQuery = OnAudioQuery();
List<SongModel> queue = [];

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

Future<void> playQueue(List<SongModel> songs, int index, {bool? shuffle}) async {
  queue = songs;
  if (shuffle != null) await player.setShuffleModeEnabled(shuffle);
  await player.setAudioSource(
    ConcatenatingAudioSource(
      children: songs.map((s) => AudioSource.uri(Uri.parse(s.uri!))).toList(),
    ),
    initialIndex: index,
  );
  player.play();
}

void openPlayer(BuildContext context) {
  Navigator.of(context).push(PageRouteBuilder(
    transitionDuration: const Duration(milliseconds: 400),
    pageBuilder: (_, __, ___) => const NowPlayingPage(),
    transitionsBuilder: (_, a, __, child) => SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
          .chain(CurveTween(curve: Curves.easeOutCubic))
          .animate(a),
      child: child,
    ),
  ));
}

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: ColorScheme.fromSeed(
            seedColor: accent, brightness: Brightness.dark),
      ),
      home: const HomePage(),
    );
  }
}

// ---------- الصفحة الرئيسية ----------
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<SongModel> _all = [];
  List<SongModel> _shown = [];
  bool _loading = true;
  bool _granted = false;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final ok = await audioQuery.checkAndRequest(retryRequest: true);
    _granted = ok;
    if (ok) await _loadSongs();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadSongs() async {
    final res = await audioQuery.querySongs(
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );
    _all = res
        .where((s) =>
            (s.isMusic ?? true) && (s.duration ?? 0) > 30000 && s.uri != null)
        .toList();
    if (mounted) _filter(_search.text);
  }

  void _filter(String q) {
    final t = q.trim().toLowerCase();
    setState(() {
      _shown = t.isEmpty
          ? _all
          : _all
              .where((s) =>
                  s.title.toLowerCase().contains(t) ||
                  (s.artist ?? '').toLowerCase().contains(t))
              .toList();
    });
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (!_granted) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 56, color: Colors.white38),
            const SizedBox(height: 12),
            const Text('نحتاج إذن الوصول لأغاني الجهاز'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                setState(() => _loading = true);
                _init();
              },
              child: const Text('السماح'),
            ),
          ],
        ),
      );
    }
    if (_shown.isEmpty) return const Center(child: Text('ما لقينا أغاني'));
    return RefreshIndicator(
      onRefresh: _loadSongs,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 12),
        itemCount: _shown.length,
        itemBuilder: (_, i) => SongTile(
          song: _shown[i],
          index: i,
          onTap: () => playQueue(_shown, i),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('مكتبتي',
                            style: TextStyle(
                                fontSize: 30, fontWeight: FontWeight.bold)),
                      ),
                      if (_all.isNotEmpty)
                        FilledButton.icon(
                          onPressed: () => playQueue(
                              _all, math.Random().nextInt(_all.length),
                              shuffle: true),
                          icon: const Icon(Icons.shuffle),
                          label: const Text('عشوائي'),
                        ),
                    ],
                  ),
                  Text('${_all.length} أغنية',
                      style: const TextStyle(color: Colors.white54)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _search,
                    onChanged: _filter,
                    decoration: InputDecoration(
                      hintText: 'ابحث في أغانيك',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: cardColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
      bottomNavigationBar: const MiniPlayer(),
    );
  }
}

// ---------- عنصر الأغنية ----------
class SongTile extends StatelessWidget {
  final SongModel song;
  final int index;
  final VoidCallback onTap;
  const SongTile({
    super.key,
    required this.song,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + math.min(index, 8) * 50),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 24 * (1 - v)),
          child: child,
        ),
      ),
      child: StreamBuilder<int?>(
        stream: player.currentIndexStream,
        builder: (context, snap) {
          final i = snap.data;
          final current =
              i != null && i < queue.length && queue[i].id == song.id;
          return ListTile(
            onTap: onTap,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
            leading: Art(id: song.id, size: 52, radius: 12),
            title: Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: current ? accent : null,
              ),
            ),
            subtitle: Text(
              '${artistOf(song)} • ${fmt(Duration(milliseconds: song.duration ?? 0))}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54),
            ),
            trailing: current
                ? StreamBuilder<bool>(
                    stream: player.playingStream,
                    builder: (_, s) => EqBars(playing: s.data ?? false),
                  )
                : null,
          );
        },
      ),
    );
  }
}

// ---------- غلاف الأغنية ----------
class Art extends StatelessWidget {
  final int id;
  final double size;
  final double radius;
  const Art({super.key, required this.id, required this.size, this.radius = 12});

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return QueryArtworkWidget(
      id: id,
      type: ArtworkType.AUDIO,
      size: size > 100 ? 800 : 200,
      quality: 90,
      artworkWidth: size,
      artworkHeight: size,
      artworkBorder: r,
      nullArtworkWidget: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: r,
          gradient: const LinearGradient(
            colors: [Color(0xFF8B5CF6), Color(0xFF3B2A7A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Icon(Icons.music_note_rounded,
            color: Colors.white70, size: size * 0.45),
      ),
    );
  }
}

// ---------- موجات صوتية متحركة ----------
class EqBars extends StatefulWidget {
  final bool playing;
  const EqBars({super.key, required this.playing});
  @override
  State<EqBars> createState() => _EqBarsState();
}

class _EqBarsState extends State<EqBars> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(3, (i) {
            final h = widget.playing
                ? 6 + 16 * (0.5 + 0.5 * math.sin(_c.value * 2 * math.pi + i * 1.4))
                : 6.0;
            return Container(
              width: 4,
              height: h,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ---------- زر التشغيل / الإيقاف ----------
class PlayPauseButton extends StatelessWidget {
  final double size;
  const PlayPauseButton({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlayerState>(
      stream: player.playerStateStream,
      builder: (_, snap) {
        final st = snap.data;
        final playing = st?.playing ?? false;
        final proc = st?.processingState;
        if (proc == ProcessingState.loading ||
            proc == ProcessingState.buffering) {
          return SizedBox(
            width: size,
            height: size,
            child: Padding(
              padding: EdgeInsets.all(size * 0.25),
              child: const CircularProgressIndicator(strokeWidth: 3),
            ),
          );
        }
        return IconButton(
          iconSize: size,
          padding: EdgeInsets.zero,
          onPressed: () {
            if (proc == ProcessingState.completed) {
              player.seek(Duration.zero, index: 0);
              player.play();
            } else if (playing) {
              player.pause();
            } else {
              player.play();
            }
          },
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: Icon(
              playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
              key: ValueKey(playing),
              size: size,
            ),
          ),
        );
      },
    );
  }
}

// ---------- المشغّل المصغّر ----------
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int?>(
      stream: player.currentIndexStream,
      builder: (context, snap) {
        final i = snap.data;
        return AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          child: (i != null && i < queue.length)
              ? _bar(context, queue[i])
              : const SizedBox(width: double.infinity),
        );
      },
    );
  }

  Widget _bar(BuildContext context, SongModel song) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => openPlayer(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      Hero(
                        tag: 'art',
                        child: Art(id: song.id, size: 48, radius: 12),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              artistOf(song),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const PlayPauseButton(size: 36),
                      IconButton(
                        icon: const Icon(Icons.skip_next_rounded),
                        onPressed: () => player.seekToNext(),
                      ),
                    ],
                  ),
                ),
                StreamBuilder<Duration>(
                  stream: player.positionStream,
                  builder: (_, s) {
                    final pos = s.data ?? Duration.zero;
                    final dur = player.duration ?? Duration.zero;
                    final v = dur.inMilliseconds == 0
                        ? 0.0
                        : (pos.inMilliseconds / dur.inMilliseconds)
                            .clamp(0.0, 1.0)
                            .toDouble();
                    return ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(20)),
                      child: LinearProgressIndicator(
                        value: v,
                        minHeight: 3,
                        backgroundColor: Colors.white10,
                        color: accent,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- شاشة التشغيل الكاملة ----------
class NowPlayingPage extends StatelessWidget {
  const NowPlayingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width - 64;
    return Scaffold(
      body: StreamBuilder<int?>(
        stream: player.currentIndexStream,
        builder: (context, snap) {
          final i = snap.data;
          if (i == null || i >= queue.length) return const SizedBox();
          final song = queue[i];
          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF3B2A7A), bg, bg],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.keyboard_arrow_down_rounded,
                              size: 32),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const Spacer(),
                        const Text('يتم التشغيل الآن',
                            style: TextStyle(color: Colors.white70)),
                        const Spacer(),
                        const SizedBox(width: 48),
                      ],
                    ),
                    const Spacer(),
                    StreamBuilder<bool>(
                      stream: player.playingStream,
                      builder: (_, s) => AnimatedScale(
                        scale: (s.data ?? false) ? 1.0 : 0.85,
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutBack,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: accent.withAlpha(90),
                                blurRadius: 40,
                                offset: const Offset(0, 20),
                              ),
                            ],
                          ),
                          child: Hero(
                            tag: 'art',
                            child: Art(id: song.id, size: w, radius: 28),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      artistOf(song),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white60),
                    ),
                      const Spacer(),
                    StreamBuilder<Duration>(
                      stream: player.positionStream,
                      builder: (_, s) {
                        final pos = s.data ?? Duration.zero;
                        final dur = player.duration ?? Duration.zero;
                        final maxMs =
                            dur.inMilliseconds > 0 ? dur.inMilliseconds : 1;
                        final curMs =
                            pos.inMilliseconds.clamp(0, maxMs).toDouble();
                        return Column(
                          children: [
                            Slider(
                              value: curMs,
                              max: maxMs.toDouble(),
                              onChanged: (v) => player
                                  .seek(Duration(milliseconds: v.toInt())),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(fmt(pos),
                                      style: const TextStyle(
                                          color: Colors.white54)),
                                  Text(fmt(dur),
                                      style: const TextStyle(
                                          color: Colors.white54)),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        StreamBuilder<bool>(
                          stream: player.shuffleModeEnabledStream,
                          builder: (_, s) {
                            final on = s.data ?? false;
                            return IconButton(
                              icon: Icon(Icons.shuffle,
                                  color: on ? accent : Colors.white54),
                              onPressed: () =>
                                  player.setShuffleModeEnabled(!on),
                            );
                          },
                        ),
                        IconButton(
                          iconSize: 40,
                          icon: const Icon(Icons.skip_previous_rounded),
                          onPressed: () => player.seekToPrevious(),
                        ),
                        const PlayPauseButton(size: 72),
                        IconButton(
                          iconSize: 40,
                          icon: const Icon(Icons.skip_next_rounded),
                          onPressed: () => player.seekToNext(),
                        ),
                        StreamBuilder<LoopMode>(
                          stream: player.loopModeStream,
                          builder: (_, s) {
                            final m = s.data ?? LoopMode.off;
                            return IconButton(
                              icon: Icon(
                                m == LoopMode.one
                                    ? Icons.repeat_one
                                    : Icons.repeat,
                                color: m == LoopMode.off
                                    ? Colors.white54
                                    : accent,
                              ),
                              onPressed: () => player.setLoopMode(
                                m == LoopMode.off
                                    ? LoopMode.all
                                    : m == LoopMode.all
                                        ? LoopMode.one
                                        : LoopMode.off,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ===== END =====