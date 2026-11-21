import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query_forked/on_audio_query.dart';
import 'core.dart';

const sheetShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
);

void toast(BuildContext c, String m) => ScaffoldMessenger.of(c)
    .showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 2)));

// ---------- غلاف الأغنية ----------
class Art extends StatelessWidget {
  final int id;
  final double size;
  final double radius;
  const Art({super.key, required this.id, required this.size, this.radius = 12});

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    final a = context.accent;
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
          gradient: LinearGradient(
            colors: [a, Color.lerp(a, Colors.black, 0.5)!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Icon(Icons.music_note_rounded, color: Colors.white70, size: size * 0.45),
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
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = context.accent;
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
              decoration: BoxDecoration(color: a, borderRadius: BorderRadius.circular(2)),
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
        if (proc == ProcessingState.loading || proc == ProcessingState.buffering) {
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

// ---------- عنصر الأغنية ----------
class SongTile extends StatelessWidget {
  final SongModel song;
  final int index;
  final VoidCallback onTap;
  final String? playlist;
  const SongTile({
    super.key,
    required this.song,
    required this.index,
    required this.onTap,
    this.playlist,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + math.min(index, 8) * 50),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 24 * (1 - v)), child: child),
      ),
      child: ListenableBuilder(
        listenable: userLib,
        builder: (context, _) => StreamBuilder<int?>(
          stream: player.currentIndexStream,
          builder: (context, snap) {
            final i = snap.data;
            final current = i != null && i < queue.length && queue[i].id == song.id;
            return ListTile(
              onTap: onTap,
              contentPadding: const EdgeInsets.only(left: 20, right: 4),
              leading: Art(id: song.id, size: 52, radius: 12),
              title: Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: current ? context.accent : null,
                ),
              ),
              subtitle: Text(
                '${artistOf(song)} • ${fmt(Duration(milliseconds: song.duration ?? 0))}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (userLib.isFav(song.id))
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(Icons.favorite, size: 16, color: context.accent),
                    ),
                  if (current)
                    StreamBuilder<bool>(
                      stream: player.playingStream,
                      builder: (_, s) => EqBars(playing: s.data ?? false),
                    ),
                  IconButton(
                    icon: const Icon(Icons.more_vert, color: Colors.white54),
                    onPressed: () => showSongMenu(context, song, playlist: playlist),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ---------- قوائم ونوافذ ----------
Future<String?> askName(BuildContext context, String title) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: context.card,
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'اسم القائمة'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('حفظ')),
      ],
    ),
  );
}

void showSongMenu(BuildContext context, SongModel song, {String? playlist}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: context.card,
    shape: sheetShape,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Art(id: song.id, size: 48, radius: 10),
              title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(artistOf(song)),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                userLib.isFav(song.id) ? Icons.favorite : Icons.favorite_border,
                color: context.accent,
              ),
              title: Text(userLib.isFav(song.id) ? 'إزالة من المفضلة' : 'إضافة للمفضلة'),
              onTap: () {
                userLib.toggleFav(song.id);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_play),
              title: const Text('تشغيل بعد الأغنية الحالية'),
              onTap: () {
                playNext(song);
                Navigator.pop(ctx);
                toast(context, 'تمت الإضافة');
              },
            ),
            ListTile(
              leading: const Icon(Icons.queue),
              title: const Text('إضافة لقائمة الانتظار'),
              onTap: () {
                addToQueue(song);
                Navigator.pop(ctx);
                toast(context, 'تمت الإضافة للانتظار');
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('إضافة إلى قائمة تشغيل'),
              onTap: () {
                Navigator.pop(ctx);
                pickPlaylist(context, song);
              },
            ),
            if (playlist != null)
              ListTile(
                leading: const Icon(Icons.remove_circle_outline),
                title: const Text('إزالة من هذه القائمة'),
                onTap: () {
                  userLib.removeFromPlaylist(playlist, song.id);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    ),
  );
}

void pickPlaylist(BuildContext context, SongModel song) {
  showModalBottomSheet(
    context: context,
    backgroundColor: context.card,
    shape: sheetShape,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ListenableBuilder(
        listenable: userLib,
        builder: (_, __) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.add, color: context.accent),
                title: const Text('قائمة جديدة'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final n = await askName(context, 'قائمة جديدة');
                  if (n != null && n.isNotEmpty) {
                    userLib.createPlaylist(n);
                    userLib.addToPlaylist(n, song.id);
                  }
                },
              ),
              for (final name in userLib.playlists.keys)
                ListTile(
                  leading: const Icon(Icons.queue_music),
                  title: Text(name),
                  onTap: () {
                    userLib.addToPlaylist(name, song.id);
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
// ===== END widgets =====