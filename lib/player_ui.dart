import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query_forked/on_audio_query.dart';
import 'core.dart';
import 'widgets.dart';

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
                        ListenableBuilder(
                          listenable: userLib,
                          builder: (_, __) => IconButton(
                            icon: Icon(
                              userLib.isFav(song.id)
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              color: userLib.isFav(song.id)
                                  ? accent
                                  : Colors.white70,
                            ),
                            onPressed: () => userLib.toggleFav(song.id),
                          ),
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
// ===== END player_ui =====