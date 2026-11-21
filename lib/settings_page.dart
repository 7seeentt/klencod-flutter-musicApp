import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core.dart';
import 'lyrics.dart';
import 'widgets.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Widget _section(BuildContext c, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 6),
        child: Text(t, style: TextStyle(color: c.accent, fontWeight: FontWeight.bold)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات'), backgroundColor: Colors.transparent),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(bottom: 30),
          children: [
            _section(context, 'المظهر'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('لون التطبيق'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 14,
                    runSpacing: 10,
                    children: [
                      for (var i = 0; i < accents.length; i++)
                        GestureDetector(
                          onTap: () => settings.update(() => settings.accentIndex = i),
                          child: CircleAvatar(
                            radius: 20,
                            backgroundColor: accents[i],
                            child: i == settings.accentIndex
                                ? const Icon(Icons.check, color: Colors.white, size: 20)
                                : null,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            SwitchListTile(
              title: const Text('خلفية سوداء (AMOLED)'),
              subtitle: const Text('توفّر البطارية على شاشات AMOLED'),
              value: settings.amoled,
              onChanged: (v) => settings.update(() => settings.amoled = v),
            ),
            SwitchListTile(
              title: const Text('ألوان من غلاف الأغنية'),
              subtitle: const Text('تتغير ألوان شاشة التشغيل حسب الغلاف'),
              value: settings.dynamicColors,
              onChanged: (v) => settings.update(() => settings.dynamicColors = v),
            ),
            SwitchListTile(
              title: const Text('خلفية ضبابية'),
              subtitle: const Text('صورة الغلاف كخلفية ضبابية بشاشة التشغيل'),
              value: settings.blurBg,
              onChanged: (v) => settings.update(() => settings.blurBg = v),
            ),
            _section(context, 'المكتبة'),
            ListTile(
              title: const Text('ترتيب الأغاني'),
              trailing: DropdownButton<int>(
                value: settings.sortIndex,
                dropdownColor: context.card,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('الاسم')),
                  DropdownMenuItem(value: 1, child: Text('الفنان')),
                  DropdownMenuItem(value: 2, child: Text('الأحدث إضافة')),
                  DropdownMenuItem(value: 3, child: Text('المدة')),
                ],
                onChanged: (v) {
                  if (v != null) settings.update(() => settings.sortIndex = v);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(settings.minSeconds == 0
                  ? 'إظهار كل المقاطع'
                  : 'إخفاء المقاطع الأقصر من ${settings.minSeconds} ثانية'),
            ),
            Slider(
              value: settings.minSeconds.toDouble(),
              min: 0,
              max: 120,
              divisions: 12,
              label: '${settings.minSeconds}',
              onChanged: (v) => settings.update(() => settings.minSeconds = v.round()),
            ),
            _section(context, 'الكلمات والبيانات'),
            ListTile(
              leading: const Icon(Icons.delete_sweep_outlined),
              title: const Text('مسح كاش الكلمات'),
              onTap: () async {
                await clearLyricsCache();
                if (context.mounted) toast(context, 'تم مسح الكلمات المحفوظة');
              },
            ),
            ListTile(
              leading: const Icon(Icons.upload_outlined),
              title: const Text('نسخ احتياطي'),
              subtitle: const Text('ينسخ المفضلة والقوائم والإعدادات للحافظة'),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: backupJson()));
                if (context.mounted) toast(context, 'تم النسخ، الصقه بأي مكان تحفظه فيه');
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('استعادة من الحافظة'),
              subtitle: const Text('انسخ النسخة الاحتياطية أول ثم اضغط هنا'),
              onTap: () async {
                final d = await Clipboard.getData(Clipboard.kTextPlain);
                final ok = restoreBackup(d?.text ?? '');
                if (context.mounted) {
                  toast(context, ok ? 'تمت الاستعادة' : 'الحافظة ما فيها نسخة صحيحة');
                }
              },
            ),
            _section(context, 'حول'),
            const ListTile(
              leading: Icon(Icons.music_note_rounded),
              title: Text('musicApp'),
              subtitle: Text('الإصدار 3.0'),
            ),
          ],
        ),
      ),
    );
  }
}
// ===== END settings =====