import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query_forked/on_audio_query.dart';
import 'core.dart';
import 'widgets.dart';
import 'lyrics.dart';

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
        decoration: BoxDecoration(color: context.card, borderRadius: BorderRadius.circular(20)),
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
                      Hero(tag: 'art', child: Art(id: song.id, size: 48, radius: 12)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(artistOf(song),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white54, fontSize: 12)),
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
                        : (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0).toDouble();
                    return ClipRRect(
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                      child: LinearProgressIndicator(
                        value: v,
                        minHeight: 3,
                        backgroundColor: Colors.white10,
                        color: context.accent,
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
    return Scaffold(
      body: StreamBuilder<int?>(
        stream: player.currentIndexStream,
        builder: (context, snap) {
          final i = snap.data;
          if (i == null || i >= queue.length) return const SizedBox();
          return _PlayerBody(song: queue[i]);
        },
      ),
    );
  }
}

class _PlayerBody extends StatelessWidget {
  final SongModel song;
  const _PlayerBody({required this.song});

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => FutureBuilder<ArtInfo>(
        future: artInfoFor(song.id),
        initialData: cachedArt(song.id),
        builder: (context, snap) {
          final info = snap.data;
          final c = info?.color;
          final dyn = (settings.dynamicColors && c != null) ? c : base.colorScheme.primary;
          return Theme(
            data: base.copyWith(colorScheme: base.colorScheme.copyWith(primary: dyn)),
            child: _PlayerView(song: song, info: info, color: dyn),
          );
        },
      ),
    );
  }
}

class _PlayerView extends StatelessWidget {
  final SongModel song;
  final ArtInfo? info;
  final Color color;
  const _PlayerView({required this.song, required this.info, required this.color});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final artSize = math.min(size.width - 64, size.height * 0.34);
    final dark = HSLColor.fromColor(color).withLightness(0.18).toColor();
    final bytes = info?.bytes;
    return Stack(
      fit: StackFit.expand,
      children: [
        TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: dark),
          duration: const Duration(milliseconds: 700),
          builder: (context, c, _) => DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [c ?? dark, context.bg, context.bg],
              ),
            ),
          ),
        ),
        if (settings.blurBg && bytes != null && bytes.isNotEmpty) ...[
          Opacity(
            opacity: 0.45,
            child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
            child: Container(color: Colors.black.withAlpha(110)),
          ),
        ],
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Spacer(),
                    const Text('يتم التشغيل الآن', style: TextStyle(color: Colors.white70)),
                    const Spacer(),
                    ListenableBuilder(
                      listenable: userLib,
                      builder: (_, __) {
                        final fav = userLib.isFav(song.id);
                        return IconButton(
                          icon: Icon(fav ? Icons.favorite : Icons.favorite_border,
                              color: fav ? context.accent : Colors.white70),
                          onPressed: () => userLib.toggleFav(song.id),
                        );
                      },
                    ),
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
                            color: context.accent.withAlpha(90),
                            blurRadius: 40,
                            offset: const Offset(0, 20),
                          ),
                        ],
                      ),
                      child: Hero(tag: 'art', child: Art(id: song.id, size: artSize, radius: 28)),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text(song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(artistOf(song),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white60)),
                const Spacer(),
                StreamBuilder<Duration>(
                  stream: player.positionStream,
                  builder: (_, s) {
                    final pos = s.data ?? Duration.zero;
                    final dur = player.duration ?? Duration.zero;
                    final maxMs = dur.inMilliseconds > 0 ? dur.inMilliseconds : 1;
                    final curMs = pos.inMilliseconds.clamp(0, maxMs).toDouble();
                    return Column(
                      children: [
                        Slider(
                          value: curMs,
                          max: maxMs.toDouble(),
                          onChanged: (v) => player.seek(Duration(milliseconds: v.toInt())),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(fmt(pos), style: const TextStyle(color: Colors.white54)),
                              Text(fmt(dur), style: const TextStyle(color: Colors.white54)),
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
                          icon: Icon(Icons.shuffle, color: on ? context.accent : Colors.white54),
                          onPressed: () => player.setShuffleModeEnabled(!on),
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
                            m == LoopMode.one ? Icons.repeat_one : Icons.repeat,
                            color: m == LoopMode.off ? Colors.white54 : context.accent,
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
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.lyrics_outlined),
                      color: Colors.white70,
                      tooltip: 'الكلمات',
                      onPressed: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => const LyricsPage())),
                    ),
                    IconButton(
                      icon: const Icon(Icons.queue_music),
                      color: Colors.white70,
                      tooltip: 'قائمة الانتظار',
                      onPressed: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => const QueuePage())),
                    ),
                    StreamBuilder<double>(
                      stream: player.speedStream,
                      builder: (_, s) => IconButton(
                        icon: const Icon(Icons.speed),
                        color: (s.data ?? 1.0) == 1.0 ? Colors.white70 : context.accent,
                        tooltip: 'السرعة',
                        onPressed: () => showSpeedSheet(context),
                      ),
                    ),
                    ValueListenableBuilder<Duration?>(
                      valueListenable: sleepLeft,
                      builder: (_, left, __) => IconButton(
                        icon: const Icon(Icons.bedtime_outlined),
                        color: left == null ? Colors.white70 : context.accent,
                        tooltip: 'مؤقّت النوم',
                        onPressed: () => showSleepSheet(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------- قائمة الانتظار ----------
class QueuePage extends StatefulWidget {
  const QueuePage({super.key});
  @override
  State<QueuePage> createState() => _QueuePageState();
}

class _QueuePageState extends State<QueuePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('قائمة الانتظار'), backgroundColor: Colors.transparent),
      body: queue.isEmpty
          ? const Center(child: Text('القائمة فاضية'))
          : StreamBuilder<int?>(
              stream: player.currentIndexStream,
              builder: (context, snap) {
                final cur = snap.data;
                return ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  itemCount: queue.length,
                  onReorder: (o, n) async {
                    if (n > o) n -= 1;
                    await moveInQueue(o, n);
                    if (mounted) setState(() {});
                  },
                  itemBuilder: (context, i) {
                    final s = queue[i];
                    final isCur = i == cur;
                    return ListTile(
                      key: ValueKey('q$i-${s.id}'),
                      onTap: () => player.seek(Duration.zero, index: i),
                      leading: Art(id: s.id, size: 48, radius: 10),
                      title: Text(s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isCur ? context.accent : null,
                          )),
                      subtitle: Text(artistOf(s),
                          maxLines: 1, style: const TextStyle(color: Colors.white54)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white38),
                            onPressed: () async {
                              await removeFromQueue(i);
                              if (mounted) setState(() {});
                            },
                          ),
                          ReorderableDragStartListener(
                            index: i,
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.drag_handle, color: Colors.white38),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

// ---------- سرعة التشغيل ----------
void showSpeedSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: context.card,
    shape: sheetShape,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: StreamBuilder<double>(
          stream: player.speedStream,
          builder: (_, s) {
            final cur = s.data ?? 1.0;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('سرعة التشغيل',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final v in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                      ChoiceChip(
                        label: Text('${v}x'),
                        selected: (cur - v).abs() < 0.01,
                        onSelected: (_) => player.setSpeed(v),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

// ---------- مؤقّت النوم ----------
void showSleepSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: context.card,
    shape: sheetShape,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ValueListenableBuilder<Duration?>(
        valueListenable: sleepLeft,
        builder: (_, left, __) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  left == null ? 'مؤقّت النوم' : 'يتوقف بعد ${fmt(left)}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              for (final m in const [5, 15, 30, 45, 60])
                ListTile(
                  leading: const Icon(Icons.bedtime_outlined),
                  title: Text('$m دقيقة'),
                  onTap: () {
                    startSleep(Duration(minutes: m));
                    Navigator.pop(ctx);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.music_off_outlined),
                title: const Text('عند نهاية الأغنية'),
                onTap: () {
                  final d = (player.duration ?? Duration.zero) - player.position;
                  startSleep(d > Duration.zero ? d : const Duration(minutes: 1));
                  Navigator.pop(ctx);
                },
              ),
              if (left != null)
                ListTile(
                  leading: const Icon(Icons.close, color: Colors.redAccent),
                  title: const Text('إلغاء المؤقّت'),
                  onTap: () {
                    cancelSleep();
                    Navigator.pop(ctx);
                  },
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
// ===== END player_ui =====