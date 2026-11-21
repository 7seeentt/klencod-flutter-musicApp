import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:on_audio_query_forked/on_audio_query.dart';
import 'core.dart';
import 'widgets.dart';
import 'player_ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.you.musiicc.channel.audio',
    androidNotificationChannelName: 'تشغيل الموسيقى',
    androidNotificationOngoing: true,
    androidNotificationIcon: 'drawable/ic_launcher',
    notificationColor: accent,
  );
  player.currentIndexStream.listen((_) => saveProgress());
  player.playingStream.listen((playing) {
    if (!playing) saveProgress();
  });
  Timer.periodic(const Duration(seconds: 5), (_) {
    if (player.playing) saveProgress();
  });
  runApp(const MyApp());
}

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
  List<SongModel> _shown = [];
  Map<String, List<SongModel>> _albums = {};
  Map<String, List<SongModel>> _artists = {};
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
    await userLib.load();
    if (ok) await _loadSongs();
    if (mounted) setState(() => _loading = false);
  }

  Map<String, List<SongModel>> _group(
      List<SongModel> songs, String Function(SongModel) key) {
    final m = <String, List<SongModel>>{};
    for (final s in songs) {
      m.putIfAbsent(key(s), () => []).add(s);
    }
    return m;
  }

  Future<void> _loadSongs() async {
    final res = await audioQuery.querySongs(
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );
    allSongs = res
        .where((s) =>
            (s.isMusic ?? true) && (s.duration ?? 0) > 30000 && s.uri != null)
        .toList();
    _albums = _group(allSongs, albumOf);
    _artists = _group(allSongs, artistOf);
    await restoreLast(allSongs);
    if (mounted) _filter(_search.text);
  }

  void _filter(String q) {
    final t = q.trim().toLowerCase();
    setState(() {
      _shown = t.isEmpty
          ? allSongs
          : allSongs
              .where((s) =>
                  s.title.toLowerCase().contains(t) ||
                  (s.artist ?? '').toLowerCase().contains(t))
              .toList();
    });
  }

  void _open(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  Future<void> _confirmDelete(String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardColor,
        title: Text('حذف "$name"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok == true) userLib.deletePlaylist(name);
  }

  // ----- التبويبات -----
  Widget _songsTab() {
    if (_shown.isEmpty) return const Center(child: Text('ما لقينا أغاني'));
    return RefreshIndicator(
      onRefresh: _loadSongs,
      child: ListView.builder(
        itemExtent: 72,
        cacheExtent: 600,
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

  Widget _albumsTab() {
    final keys = _albums.keys.toList()..sort();
    final w = (MediaQuery.of(context).size.width - 44) / 2;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
        childAspectRatio: w / (w + 56),
      ),
      itemCount: keys.length,
      itemBuilder: (_, i) {
        final name = keys[i];
        final songs = _albums[name]!;
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _open(SongListPage(title: name, songs: songs)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Art(id: songs.first.id, size: w, radius: 16),
              const SizedBox(height: 8),
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('${songs.length} أغنية',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        );
      },
    );
  }

  Widget _artistsTab() {
    final keys = _artists.keys.toList()..sort();
    return ListView.builder(
      itemExtent: 72,
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: keys.length,
      itemBuilder: (_, i) {
        final name = keys[i];
        final songs = _artists[name]!;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          leading: Art(id: songs.first.id, size: 52, radius: 26),
          title: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${songs.length} أغنية',
              style: const TextStyle(color: Colors.white54)),
          onTap: () => _open(SongListPage(title: name, songs: songs)),
        );
      },
    );
  }

  Widget _favoritesTab() {
    return ListenableBuilder(
      listenable: userLib,
      builder: (_, __) {
        final favs = allSongs.where((s) => userLib.isFav(s.id)).toList();
        if (favs.isEmpty) {
          return const Center(
            child: Text(
              'ما عندك أغاني مفضلة بعد\nاضغط ⋮ على أي أغنية وأضفها',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54),
            ),
          );
        }
        return ListView.builder(
          itemExtent: 72,
          padding: const EdgeInsets.only(bottom: 12),
          itemCount: favs.length,
          itemBuilder: (_, i) => SongTile(
            song: favs[i],
            index: i,
            onTap: () => playQueue(favs, i),
          ),
        );
      },
    );
  }

  Widget _iconBox(IconData icon) => Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: accent.withAlpha(50),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: accent),
      );

  Widget _playlistsTab() {
    return ListenableBuilder(
      listenable: userLib,
      builder: (_, __) {
        final names = userLib.playlists.keys.toList();
        return ListView(
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: _iconBox(Icons.add),
              title: const Text('قائمة تشغيل جديدة',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () async {
                final n = await askName(context, 'قائمة جديدة');
                if (n != null && n.isNotEmpty) userLib.createPlaylist(n);
              },
            ),
            for (final name in names)
              ListTile(
                contentPadding: const EdgeInsets.only(left: 20, right: 4),
                leading: _iconBox(Icons.queue_music),
                title: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  '${userLib.playlists[name]!.length} أغنية',
                  style: const TextStyle(color: Colors.white54),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.white38),
                  onPressed: () => _confirmDelete(name),
                ),
                onTap: () => _open(SongListPage(title: name, playlist: name)),
              ),
          ],
        );
      },
    );
  }

  Widget _permissionView() {
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_granted) return Scaffold(body: _permissionView());
    return DefaultTabController(
      length: 5,
      child: Scaffold(
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
                        if (allSongs.isNotEmpty)
                          FilledButton.icon(
                            onPressed: () => playQueue(allSongs,
                                math.Random().nextInt(allSongs.length),
                                shuffle: true),
                            icon: const Icon(Icons.shuffle),
                            label: const Text('عشوائي'),
                          ),
                      ],
                    ),
                    Text('${allSongs.length} أغنية',
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
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: accent.withAlpha(60),
                  borderRadius: BorderRadius.circular(20),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white54,
                labelStyle: const TextStyle(fontWeight: FontWeight.w600),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                tabs: const [
                  Tab(text: 'الأغاني'),
                  Tab(text: 'الألبومات'),
                  Tab(text: 'الفنانين'),
                  Tab(text: 'المفضلة'),
                  Tab(text: 'القوائم'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _songsTab(),
                    _albumsTab(),
                    _artistsTab(),
                    _favoritesTab(),
                    _playlistsTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: const MiniPlayer(),
      ),
    );
  }
}

// ---------- صفحة قائمة أغاني (ألبوم / فنان / قائمة تشغيل) ----------
class SongListPage extends StatelessWidget {
  final String title;
  final List<SongModel>? songs;
  final String? playlist;
  const SongListPage(
      {super.key, required this.title, this.songs, this.playlist});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), backgroundColor: Colors.transparent),
      body: ListenableBuilder(
        listenable: userLib,
        builder: (_, __) {
          final list = playlist != null
              ? songsByIds(userLib.playlists[playlist] ?? <int>[])
              : (songs ?? <SongModel>[]);
          if (list.isEmpty) return const Center(child: Text('القائمة فاضية'));
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Row(
                  children: [
                    Text('${list.length} أغنية',
                        style: const TextStyle(color: Colors.white54)),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: () => playQueue(
                          list, math.Random().nextInt(list.length),
                          shuffle: true),
                      icon: const Icon(Icons.shuffle),
                      label: const Text('عشوائي'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemExtent: 72,
                  itemCount: list.length,
                  itemBuilder: (_, i) => SongTile(
                    song: list[i],
                    index: i,
                    onTap: () => playQueue(list, i),
                    playlist: playlist,
                  ),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: const MiniPlayer(),
    );
  }
}
// ===== END main =====