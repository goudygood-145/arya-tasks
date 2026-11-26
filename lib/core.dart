import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String supabaseUrl = 'https://kvkgyrifhqiukgjkojyx.supabase.co';
const String supabaseAnonKey = 'sb_publishable_fClXOE3GkV3Gj8VeVTPMSQ_erzUihwc';

const int storageQuotaBytes = 1024 * 1024 * 1024; // 1 GB
const int lowStorageThresholdBytes = 100 * 1024 * 1024; // 100 MB
const int trashVisibleDays = 30;

typedef JsonRow = Map<String, dynamic>;

final supabase = Supabase.instance.client;

class ThemePalette {
  final String nameFa;
  final String nameEn;
  final Color seed;
  const ThemePalette(this.nameFa, this.nameEn, this.seed);
}

const List<ThemePalette> appPalettes = [
  ThemePalette('سبز سازمانی', 'Green', Color(0xFF16A34A)),
  ThemePalette('آبی کلاسیک', 'Blue', Color(0xFF1F6FEB)),
  ThemePalette('بنفش مدرن', 'Purple', Color(0xFF7C3AED)),
  ThemePalette('فیروزه‌ای', 'Teal', Color(0xFF0D9488)),
  ThemePalette('نارنجی گرم', 'Orange', Color(0xFFEA580C)),
  ThemePalette('زرشکی', 'Rose', Color(0xFFE11D48)),
];

const List<Color> listColorOptions = [
  Color(0xFF16A34A),
  Color(0xFF1F6FEB),
  Color(0xFF7C3AED),
  Color(0xFF0D9488),
  Color(0xFFEA580C),
  Color(0xFFE11D48),
  Color(0xFFD97706),
  Color(0xFF475569),
];

class AppSettings extends ChangeNotifier {
  int colorIndex = 0;
  bool isDark = false;
  String lang = 'fa';
  bool isRtl = true;
  bool soundEnabled = true;
  String sortBy = 'created';

  // فولدربندی و رنگ‌بندی شخصی (محلی روی دستگاه کاربر)
  List<String> personalFolders = [];
  Map<String, String> listToFolder = {};
  Map<String, int> listColors = {};

  ThemePalette get palette =>
      appPalettes[colorIndex.clamp(0, appPalettes.length - 1)];

  ThemeData buildTheme(Brightness brightness) {
    final cs = ColorScheme.fromSeed(
      seedColor: palette.seed,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Vazirmatn',
      colorScheme: cs,
      scaffoldBackgroundColor: cs.surfaceContainerLow,
      appBarTheme: AppBarTheme(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: cs.surface,
        surfaceTintColor: cs.surfaceTint,
      ),
    );
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    colorIndex = p.getInt('cfg_color') ?? 0;
    isDark = p.getBool('cfg_dark') ?? false;
    lang = p.getString('cfg_lang') ?? 'fa';
    isRtl = p.getBool('cfg_rtl') ?? (lang == 'fa');
    soundEnabled = p.getBool('cfg_sound') ?? true;
    sortBy = p.getString('cfg_sort_by') ?? 'created';

    personalFolders = p.getStringList('cfg_folders') ?? [];
    final folderMapStr = p.getString('cfg_list_folders');
    if (folderMapStr != null) {
      try {
        listToFolder = Map<String, String>.from(jsonDecode(folderMapStr));
      } catch (_) {}
    }
    final colorMapStr = p.getString('cfg_list_colors');
    if (colorMapStr != null) {
      try {
        final raw = Map<String, dynamic>.from(jsonDecode(colorMapStr));
        listColors = raw.map((k, v) => MapEntry(k, (v as num).toInt()));
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> setColor(int idx) async {
    colorIndex = idx;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setInt('cfg_color', idx);
  }

  Future<void> setDark(bool val) async {
    isDark = val;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool('cfg_dark', val);
  }

  Future<void> setLang(String val) async {
    lang = val;
    isRtl = (val == 'fa');
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('cfg_lang', val);
    await p.setBool('cfg_rtl', isRtl);
  }

  Future<void> setRtl(bool val) async {
    isRtl = val;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool('cfg_rtl', val);
  }

  Future<void> setSound(bool val) async {
    soundEnabled = val;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool('cfg_sound', val);
  }

  Future<void> setSortBy(String val) async {
    sortBy = val;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('cfg_sort_by', val);
  }

  Future<void> addPersonalFolder(String name) async {
    final clean = name.trim();
    if (clean.isEmpty || personalFolders.contains(clean)) return;
    personalFolders.add(clean);
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setStringList('cfg_folders', personalFolders);
  }

  Future<void> removePersonalFolder(String name) async {
    personalFolders.remove(name);
    listToFolder.removeWhere((_, v) => v == name);
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setStringList('cfg_folders', personalFolders);
    await p.setString('cfg_list_folders', jsonEncode(listToFolder));
  }

  Future<void> assignListFolder(String listId, String? folderName) async {
    if (folderName == null || folderName.isEmpty) {
      listToFolder.remove(listId);
    } else {
      listToFolder[listId] = folderName;
    }
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('cfg_list_folders', jsonEncode(listToFolder));
  }

  Future<void> setListColor(String listId, int? colorValue) async {
    if (colorValue == null) {
      listColors.remove(listId);
    } else {
      listColors[listId] = colorValue;
    }
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('cfg_list_colors', jsonEncode(listColors));
  }
}

final AppSettings appSettings = AppSettings();

String tr(String fa, String en) => appSettings.lang == 'en' ? en : fa;

String toPersianDigits(String input) {
  if (appSettings.lang == 'en') return input;
  const en = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
  const fa = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
  var res = input;
  for (int i = 0; i < 10; i++) {
    res = res.replaceAll(en[i], fa[i]);
  }
  return res;
}

String formatAppDate(String? isoDate, {bool withTime = false}) {
  if (isoDate == null || isoDate.isEmpty) return '';
  final dt = DateTime.tryParse(isoDate)?.toLocal();
  if (dt == null) return '';
  if (appSettings.lang == 'en') {
    final d =
        '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
    if (!withTime) return d;
    final t =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '$d - $t';
  }
  final j = Jalali.fromDateTime(dt);
  final dateStr =
      '${j.year}/${j.month.toString().padLeft(2, '0')}/${j.day.toString().padLeft(2, '0')}';
  if (!withTime) return toPersianDigits(dateStr);
  final timeStr =
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  return toPersianDigits('$dateStr - $timeStr');
}

String formatBytes(int bytes) {
  if (bytes < 1024) {
    return '${toPersianDigits(bytes.toString())} ${tr('بایت', 'B')}';
  }
  final kb = bytes / 1024;
  if (kb < 1024) {
    return '${toPersianDigits(kb.toStringAsFixed(1))} ${tr('کیلوبایت', 'KB')}';
  }
  final mb = kb / 1024;
  return '${toPersianDigits(mb.toStringAsFixed(1))} ${tr('مگابایت', 'MB')}';
}

Future<void> playTickSound() async {
  if (!appSettings.soundEnabled) return;
  try {
    await SystemSound.play(SystemSoundType.click);
  } catch (_) {}
}

String buildSafeStoragePath(String taskId, String originalName) {
  final dotIndex = originalName.lastIndexOf('.');
  String ext = '';
  if (dotIndex != -1 && dotIndex < originalName.length - 1) {
    final rawExt = originalName.substring(dotIndex + 1).toLowerCase();
    final cleanExt = rawExt.replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (cleanExt.isNotEmpty) ext = '.$cleanExt';
  }
  final ts = DateTime.now().millisecondsSinceEpoch;
  return '$taskId/$ts$ext';
}

Future<int> fetchTotalStorageBytes() async {
  try {
    final res = await supabase.rpc('get_total_storage_bytes');
    return (res as num?)?.toInt() ?? 0;
  } catch (_) {
    return 0;
  }
}

Future<void> deleteStorageFilesForTask(String taskId) async {
  try {
    final rows = await supabase
        .from('task_attachments')
        .select('file_path')
        .eq('task_id', taskId);
    final paths = rows
        .map((r) => r['file_path'] as String?)
        .whereType<String>()
        .toList();
    if (paths.isNotEmpty) {
      await supabase.storage.from('task-files').remove(paths);
    }
  } catch (_) {}
}

Future<String?> registerCurrentSession() async {
  final user = supabase.auth.currentUser;
  if (user == null) return null;
  final prefs = await SharedPreferences.getInstance();
  final existingId = prefs.getString('current_session_row_id');
  final platform = kIsWeb ? 'Web' : defaultTargetPlatform.name;
  final deviceName = kIsWeb ? 'مرورگر وب ($platform)' : 'اپلیکیشن ($platform)';

  try {
    if (existingId != null) {
      final found = await supabase
          .from('user_sessions')
          .select('id, is_revoked')
          .eq('id', existingId)
          .maybeSingle();
      if (found != null && found['is_revoked'] != true) {
        await supabase
            .from('user_sessions')
            .update({'last_active': DateTime.now().toUtc().toIso8601String()})
            .eq('id', existingId);
        return existingId;
      }
    }
    final inserted = await supabase
        .from('user_sessions')
        .insert({
          'user_id': user.id,
          'device_name': deviceName,
          'platform': platform,
        })
        .select('id')
        .single();
    final newId = inserted['id'] as String;
    await prefs.setString('current_session_row_id', newId);
    return newId;
  } catch (_) {
    return null;
  }
}

Future<void> logActivity(String taskId, String actorName, String action) async {
  try {
    await supabase.from('activity_logs').insert({
      'task_id': taskId,
      'actor_id': supabase.auth.currentUser?.id,
      'actor_name': actorName,
      'action': action,
    });
  } catch (_) {}
}

Future<void> sendAppNotification({
  required String targetUserId,
  required String title,
  required String body,
  String? taskId,
  String? listId,
}) async {
  if (targetUserId == supabase.auth.currentUser?.id) return;
  try {
    await supabase.from('notifications').insert({
      'user_id': targetUserId,
      'title': title,
      'body': body,
      'task_id': taskId,
      'list_id': listId,
    });
  } catch (_) {}
}

// لوگوی اختصاصی سبز رنگ H.A. همراه با تیک
class HaLogoBadge extends StatelessWidget {
  final double size;
  const HaLogoBadge({super.key, this.size = 56});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF16A34A),
        borderRadius: BorderRadius.circular(size * 0.22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF16A34A).withAlpha(70),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_rounded, color: Colors.white, size: size * 0.5),
          Text(
            'H.A.',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: size * 0.24,
              height: 0.9,
            ),
          ),
        ],
      ),
    );
  }
}

// تقویم انتخاب تاریخ کاملاً شمسی (و میلادی در حالت انگلیسی)
Future<DateTime?> pickAppDate(
  BuildContext context, {
  DateTime? initialDate,
}) async {
  final init = initialDate ?? DateTime.now();
  if (appSettings.lang == 'en') {
    return showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
  }

  Jalali current = Jalali.fromDateTime(init);
  int viewYear = current.year;
  int viewMonth = current.month;
  Jalali selected = current;

  const monthNames = [
    'فروردین',
    'اردیبهشت',
    'خرداد',
    'تیر',
    'مرداد',
    'شهریور',
    'مهر',
    'آبان',
    'آذر',
    'دی',
    'بهمن',
    'اسفند',
  ];
  const weekDays = ['ش', 'ی', 'د', 'س', 'چ', 'پ', 'ج'];

  return showDialog<DateTime>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final cs = Theme.of(ctx).colorScheme;
        final firstDay = Jalali(viewYear, viewMonth, 1);
        final daysInMonth = firstDay.monthLength;
        final startOffset = (firstDay.weekDay - 1) % 7;

        return AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () {
                  setState(() {
                    if (viewMonth == 1) {
                      viewMonth = 12;
                      viewYear--;
                    } else {
                      viewMonth--;
                    }
                  });
                },
              ),
              Text(
                '${monthNames[viewMonth - 1]} ${toPersianDigits(viewYear.toString())}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () {
                  setState(() {
                    if (viewMonth == 12) {
                      viewMonth = 1;
                      viewYear++;
                    } else {
                      viewMonth++;
                    }
                  });
                },
              ),
            ],
          ),
          content: SizedBox(
            width: 310,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: weekDays
                      .map((w) => SizedBox(
                            width: 36,
                            child: Center(
                              child: Text(
                                w,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: cs.primary,
                                ),
                              ),
                            ),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                  ),
                  itemCount: startOffset + daysInMonth,
                  itemBuilder: (_, idx) {
                    if (idx < startOffset) return const SizedBox.shrink();
                    final day = idx - startOffset + 1;
                    final isSel = selected.year == viewYear &&
                        selected.month == viewMonth &&
                        selected.day == day;
                    return InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        setState(() {
                          selected = Jalali(viewYear, viewMonth, day);
                        });
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSel ? cs.primary : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            toPersianDigits(day.toString()),
                            style: TextStyle(
                              color: isSel ? cs.onPrimary : cs.onSurface,
                              fontWeight:
                                  isSel ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('انصراف'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, DateTime.now()),
              child: const Text('امروز'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, selected.toDateTime()),
              child: const Text('تأیید'),
            ),
          ],
        );
      },
    ),
  );
}
