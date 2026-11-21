import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:on_audio_query_forked/on_audio_query.dart';
import 'core.dart';
import 'widgets.dart';
import 'player_ui.dart';
import 'settings_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.you.musiicc.channel.audio',
    androidNotificationChannelName: 'تشغيل الموسيقى',
    androidNotificationOngoing: true,
    androidNotificationIcon: 'drawable/ic_launcher',
    notificationColor: accents[0],
  );
  await settings.load();
  await userLib.load();
  player.currentIndexStream.listen((_) => saveProgress());
  player.playingStream.listen((playing) {
    if (!playing) saveProgress();
  });
  Timer.periodic(const Duration(seconds: 5), (_) {
    if (player.playing) saveProgress();
  });
  runApp(const MyApp());
}

ThemeData buildTheme() {
  final a = accents[settings.accentIndex];
  final bgc = settings.amoled ? Colors.black : const Color(0xFF0E0E14);
  final card = settings.amoled ? const Color(0xFF14141B) : const Color(0xFF1A1A24);
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bgc,
    cardColor: card,
    colorScheme: ColorScheme.fromSeed(seedColor: a, brightness: Brightness.dark),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const SplashPage(),
      ),
    );
  }
}

// ---------- شاشة البداية ----------
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});
  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, __, ___) => const HomePage(),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = context.accent;
    return Scaffold(
      body: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutBack,
          builder: (_, v, child) => Opacity(
            opacity: v.clamp(0.0, 1.0).toDouble(),
            child: Transform.scale(scale: 0.6 + 0.4 * v, child: child),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  gradient: LinearGradient(
                    colors: [a, Color.lerp(a, Colors.black, 0.5)!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [BoxShadow(color: a.withAlpha(90), blurRadius: 40)],
                ),
                child: const Icon(Icons.music_note_rounded, size: 64, color: Colors.white),
              ),
              const SizedBox(height: 20),
              const Text('musicApp',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 1)),
            ],
          ),
        ),
      ),
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
  List<SongModel> _raw = [];
  List<SongModel> _shown = [];
  Map<String, List<SongModel>> _albums = {};
  Map<String, List<SongModel>> _artists = {};
  bool _loading = true;
  bool _granted = false;
  int _sortKey = -1;
  int _minKey = -1;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    settings.addListener(_onSettings);
    _init();
  }

  @override
  void dispose() {
    settings.removeListener(_onSettings);
    _search.dispose();
    super.dispose();
  }

  void _onSettings() {
    if (_raw.isNotEmpty &&
        (_sortKey != settings.sortIndex || _minKey != settings.minSeconds)) {
      _compute();
      _filter(_search.text);
    }
  }

  Future<void> _init() async {
    final ok = await audioQuery.checkAndRequest(retryRequest: true);
    _granted = ok;
    if (ok) await _loadSongs();
    if (mounted) setState(() => _loading = false);
  }

  Map<String, List<SongModel>> _group(List<SongModel> songs, String Function(SongModel) key) {
    final m = <String, List<SongModel>>{};
    for (final s in songs) {
      m.putIfAbsent(key(s), () => []).add(s);
    }
    return m;
  }

  void _compute() {
    _sortKey = settings.sortIndex;
    _minKey = settings.minSeconds;
    allSongs = _raw.where((s) => (s.duration ?? 0) >= settings.minSeconds * 1000).toList();
    sortSongs(allSongs);
    _albums = _group(allSongs, albumOf);
    _artists = _group(allSongs, artistOf);
  }

  Future<void> _loadSongs() async {
    final res = await audioQuery.querySongs(
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );
    _raw = res.where((s) => (s.isMusic ?? true) && s.uri != null).toList();
    _compute();
    await restoreLast(_raw);
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
        backgroundColor: context.card,
        title: Text('حذف "$name"؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
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
        itemBuilder: (_, i) =>
            SongTile(song: _shown[i], index: i, onTap: () => playQueue(_shown, i)),
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
          subtitle: Text('${songs.length} أغنية', style: const TextStyle(color: Colors.white54)),
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
          itemBuilder: (_, i) =>
              SongTile(song: favs[i], index: i, onTap: () => playQueue(favs, i)),
        );
      },
    );
  }

  Widget _iconBox(IconData icon) => Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: context.accent.withAlpha(50),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: context.accent),
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
                subtitle: Text('${userLib.playlists[name]!.length} أغنية',
                    style: const TextStyle(color: Colors.white54)),
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
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text('مكتبتي',
                              style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
                        ),
                        if (allSongs.isNotEmpty)
                          FilledButton.icon(
                            onPressed: () => playQueue(
                                allSongs, math.Random().nextInt(allSongs.length),
                                shuffle: true),
                            icon: const Icon(Icons.shuffle),
                            label: const Text('عشوائي'),
                          ),
                        IconButton(
                          icon: const Icon(Icons.settings_outlined),
                          tooltip: 'الإعدادات',
                          onPressed: () => _open(const SettingsPage()),
                        ),
                      ],
                    ),
                    Text('${allSongs.length} أغنية',
                        style: const TextStyle(color: Colors.white54)),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: TextField(
                        controller: _search,
                        onChanged: _filter,
                        decoration: InputDecoration(
                          hintText: 'ابحث في أغانيك',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: context.card,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
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
                  color: context.accent.withAlpha(60),
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
  const SongListPage({super.key, required this.title, this.songs, this.playlist});

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
                    Text('${list.length} أغنية', style: const TextStyle(color: Colors.white54)),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: () =>
                          playQueue(list, math.Random().nextInt(list.length), shuffle: true),
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