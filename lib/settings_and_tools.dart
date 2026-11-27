import 'dart:convert';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core.dart';

class UserSettingsDialog extends StatefulWidget {
  final Map<String, JsonRow> profilesMap;
  final VoidCallback onProfileUpdated;

  const UserSettingsDialog({
    super.key,
    required this.profilesMap,
    required this.onProfileUpdated,
  });

  @override
  State<UserSettingsDialog> createState() => _UserSettingsDialogState();
}

class _UserSettingsDialogState extends State<UserSettingsDialog> {
  late TextEditingController nameCtrl;
  final transferEmailCtrl = TextEditingController();
  bool savingName = false;
  String? currentSessionId;
  List<JsonRow> sessions = [];
  bool loadingSessions = true;

  String get uid => supabase.auth.currentUser!.id;
  JsonRow? get myProfile => widget.profilesMap[uid];
  bool get isSuperAdmin => myProfile?['is_super_admin'] == true;

  @override
  void initState() {
    super.initState();
    nameCtrl = TextEditingController(
      text: (myProfile?['full_name'] as String?) ?? '',
    );
    _loadSessions();
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    transferEmailCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSessions() async {
    final p = await SharedPreferences.getInstance();
    currentSessionId = p.getString('current_session_row_id');
    try {
      final data = await supabase
          .from('user_sessions')
          .select()
          .eq('user_id', uid)
          .order('last_active', ascending: false);
      if (mounted) {
        setState(() {
          sessions = List<JsonRow>.from(data);
          loadingSessions = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => loadingSessions = false);
    }
  }

  Future<void> _saveName() async {
    final newName = nameCtrl.text.trim();
    if (newName.isEmpty) return;
    setState(() => savingName = true);
    try {
      await supabase
          .from('profiles')
          .update({'full_name': newName}).eq('id', uid);
      widget.onProfileUpdated();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('نام کاربری به‌روزرسانی شد.', 'Name updated.'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => savingName = false);
    }
  }

  Future<void> _transferSuperAdmin() async {
    final mail = transferEmailCtrl.text.trim();
    if (mail.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('انتقال مدیریت کل شرکت', 'Transfer Super Admin')),
        content: Text(
          tr(
            'آیا مطمئن هستید که مدیریت کل شرکت را به «$mail» واگذار کنید؟ پس از این کار دسترسی مدیریت کل شما بلافاصله لغو می‌شود و فقط مدیر جدید می‌تواند آن را تغییر دهد.',
            'Are you sure you want to transfer Super Admin to $mail? You will immediately lose Super Admin access.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('انصراف', 'Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('تأیید و انتقال', 'Confirm Transfer')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await supabase.rpc('transfer_super_admin', params: {'target_email': mail});
      widget.onProfileUpdated();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('مدیریت کل با موفقیت منتقل شد.', 'Super Admin transferred.')),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appSettings,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.settings_rounded, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr('تنظیمات حساب و برنامه', 'Account & App Settings'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tr('پروفایل کاربری', 'User Profile'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: nameCtrl,
                          decoration: InputDecoration(
                            labelText: tr('نام نمایشی', 'Display Name'),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: savingName ? null : _saveName,
                        child: Text(tr('ذخیره', 'Save')),
                      ),
                    ],
                  ),
                  const Divider(height: 28),
                  Text(
                    tr('ظاهر، رنگ‌بندی و زبان', 'Appearance & Language'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: List.generate(appPalettes.length, (i) {
                      final p = appPalettes[i];
                      final selected = appSettings.colorIndex == i;
                      return InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () => appSettings.setColor(i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: selected
                                ? p.seed.withAlpha(35)
                                : cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: selected ? p.seed : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircleAvatar(radius: 8, backgroundColor: p.seed),
                              const SizedBox(width: 6),
                              Text(
                                tr(p.nameFa, p.nameEn),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('حالت شب (تیره)', 'Dark Mode')),
                    secondary: Icon(
                      appSettings.isDark
                          ? Icons.dark_mode_rounded
                          : Icons.light_mode_rounded,
                    ),
                    value: appSettings.isDark,
                    onChanged: (v) => appSettings.setDark(v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('صدای تیک زدن کارها', 'Task Completion Sound')),
                    secondary: const Icon(Icons.volume_up_outlined),
                    value: appSettings.soundEnabled,
                    onChanged: (v) => appSettings.setSound(v),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.language_rounded, size: 22),
                      const SizedBox(width: 10),
                      Text(
                        tr('زبان برنامه', 'Language'),
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'fa', label: Text('فارسی')),
                        ButtonSegment(value: 'en', label: Text('English')),
                      ],
                      selected: {appSettings.lang},
                      onSelectionChanged: (s) => appSettings.setLang(s.first),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Icon(Icons.format_textdirection_r_to_l, size: 22),
                      const SizedBox(width: 10),
                      Text(
                        tr('جهت چیدمان صفحه', 'Page Direction'),
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(
                            value: true, label: Text(tr('راست‌چین', 'RTL'))),
                        ButtonSegment(
                            value: false, label: Text(tr('چپ‌چین', 'LTR'))),
                      ],
                      selected: {appSettings.isRtl},
                      onSelectionChanged: (s) => appSettings.setRtl(s.first),
                    ),
                  ),
                  const Divider(height: 28),
                  Text(
                    tr('دستگاه‌های متصل به حساب شما', 'Connected Devices'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (loadingSessions)
                    const Center(child: CircularProgressIndicator())
                  else if (sessions.isEmpty)
                    Text(
                      tr('نشستی ثبت نشده است.', 'No sessions logged.'),
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                    )
                  else
                    ...sessions.take(8).map((s) {
                      final isCurrent = s['id'] == currentSessionId;
                      final revoked = s['is_revoked'] == true;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          s['platform'] == 'Web'
                              ? Icons.computer_rounded
                              : Icons.phone_android_rounded,
                          color: revoked ? Colors.grey : cs.primary,
                        ),
                        title: Text(
                          '${s['device_name']}${isCurrent ? tr(' (این دستگاه)', ' (This device)') : ''}',
                          style: TextStyle(
                            decoration:
                                revoked ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        subtitle: Text(
                          '${tr('آخرین فعالیت:', 'Last active:')} ${formatAppDate(s['last_active'] as String?, withTime: true)}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: !revoked
                            ? TextButton(
                                style: TextButton.styleFrom(
                                    foregroundColor: Colors.red),
                                onPressed: () async {
                                  await supabase
                                      .from('user_sessions')
                                      .update({'is_revoked': true})
                                      .eq('id', s['id']);
                                  if (isCurrent) {
                                    await supabase.auth.signOut();
                                    if (context.mounted) Navigator.pop(context);
                                  } else {
                                    await _loadSessions();
                                  }
                                },
                                child: Text(tr('خروج', 'Logout')),
                              )
                            : Text(
                                tr('خارج شده', 'Revoked'),
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey),
                              ),
                      );
                    }),
                  const Divider(height: 28),
                  Text(
                    tr('ابزارها و مدیریت داده‌ها', 'Tools & Data'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.delete_outline_rounded,
                        color: Colors.orange),
                    title: Text(tr('سطل زباله (۳۰ روزه)', 'Trash Bin (30 Days)')),
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (_) =>
                            TrashBinDialog(onRestored: widget.onProfileUpdated),
                      );
                    },
                  ),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.download_for_offline_outlined,
                        color: cs.primary),
                    title: Text(tr('ورود از Microsoft To Do',
                        'Import from Microsoft To Do')),
                    onTap: () {
                      final email = supabase.auth.currentUser?.email ?? '';
                      final name =
                          (myProfile?['full_name'] as String?) ?? email;
                      showDialog(
                        context: context,
                        builder: (_) => TodoImportDialog(
                          currentUserEmail: email,
                          currentUserName: name,
                          onImported: widget.onProfileUpdated,
                        ),
                      );
                    },
                  ),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading:
                        Icon(Icons.restore_page_outlined, color: cs.primary),
                    title: Text(
                        tr('بازیابی از فایل بکاپ', 'Restore from Backup')),
                    onTap: () => showBackupRestoreDialog(
                        context, widget.onProfileUpdated),
                  ),
                  if (isSuperAdmin) ...[
                    const Divider(height: 28),
                    Row(
                      children: [
                        Icon(Icons.admin_panel_settings_rounded,
                            color: cs.error),
                        const SizedBox(width: 6),
                        Text(
                          tr('پنل مدیر کل شرکت', 'Company Super Admin Panel'),
                          style: TextStyle(
                              fontWeight: FontWeight.bold, color: cs.error),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      tr(
                        'مدیریت وضعیت کارمندان (با غیرفعال کردن، دسترسی قطع می‌شود اما تاریخچه و کارها باقی می‌مانند):',
                        'Manage employees (deactivating cuts access while preserving all history):',
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    ...widget.profilesMap.values.map((p) {
                      final active = p['is_active'] != false;
                      final isMe = p['id'] == uid;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                            '${p['full_name'] ?? 'کاربر'} (${p['email']})'),
                        trailing: isMe
                            ? Chip(label: Text(tr('مدیر کل', 'Super Admin')))
                            : Switch(
                                value: active,
                                onChanged: (val) async {
                                  await supabase.rpc(
                                    'set_user_active_status',
                                    params: {
                                      'target_user_id': p['id'],
                                      'active_state': val,
                                    },
                                  );
                                  widget.onProfileUpdated();
                                  if (mounted) setState(() {});
                                },
                              ),
                      );
                    }),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: transferEmailCtrl,
                            textDirection: TextDirection.ltr,
                            decoration: InputDecoration(
                              hintText: tr(
                                  'ایمیل مدیر جدید شرکت برای انتقال',
                                  'New Super Admin email'),
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: Colors.red),
                          onPressed: _transferSuperAdmin,
                          child: Text(tr('انتقال مدیریت کل', 'Transfer')),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () async {
                await supabase.auth.signOut();
                if (context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: Text(tr('خروج از حساب', 'Sign Out')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('بستن', 'Close')),
            ),
          ],
        );
      },
    );
  }
}

// سطل زباله اختصاصی (۳۰ روز قابل بازیابی در نرم‌افزار)
class TrashBinDialog extends StatefulWidget {
  final VoidCallback onRestored;
  const TrashBinDialog({super.key, required this.onRestored});

  @override
  State<TrashBinDialog> createState() => _TrashBinDialogState();
}

class _TrashBinDialogState extends State<TrashBinDialog> {
  List<JsonRow> deletedTasks = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadTrash();
  }

  Future<void> _loadTrash() async {
    setState(() => loading = true);
    try {
      final cutoff = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: trashVisibleDays))
          .toIso8601String();
      final data = await supabase
          .from('tasks')
          .select('id, title, deleted_at, lists(title)')
          .not('deleted_at', 'is', null)
          .gte('deleted_at', cutoff)
          .order('deleted_at', ascending: false);
      if (mounted) {
        setState(() {
          deletedTasks = List<JsonRow>.from(data);
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.delete_outline_rounded, color: Colors.orange),
          const SizedBox(width: 8),
          Text(tr('سطل زباله (۳۰ روزه)', 'Trash Bin (30 Days)')),
        ],
      ),
      content: SizedBox(
        width: 450,
        child: loading
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            : deletedTasks.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      tr(
                        'سطل زباله خالی است. کارهای حذف‌شده تا ۳۰ روز اینجا قابل بازیابی هستند.',
                        'Trash bin is empty. Deleted tasks stay here for 30 days.',
                      ),
                    ),
                  )
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 340),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: deletedTasks.length,
                      itemBuilder: (_, i) {
                        final t = deletedTasks[i];
                        final delDt = DateTime.tryParse(
                                (t['deleted_at'] as String?) ?? '') ??
                            DateTime.now();
                        final daysLeft = (trashVisibleDays -
                                DateTime.now().difference(delDt).inDays)
                            .clamp(1, trashVisibleDays);
                        final listTitle =
                            (t['lists'] as JsonRow?)?['title'] ?? '';
                        return ListTile(
                          dense: true,
                          title: Text(t['title'] as String),
                          subtitle: Text(
                            '$listTitle • ${toPersianDigits(daysLeft.toString())} ${tr('روز تا حذف خودکار', 'days left')}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: FilledButton.tonal(
                            onPressed: () async {
                              await supabase.from('tasks').update({
                                'deleted_at': null,
                                'deleted_by': null,
                              }).eq('id', t['id']);
                              widget.onRestored();
                              await _loadTrash();
                            },
                            child: Text(tr('بازیابی', 'Restore')),
                          ),
                        );
                      },
                    ),
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('بستن', 'Close')),
        ),
      ],
    );
  }
}

// ابزار ورود اطلاعات از Microsoft To Do (با استخراج کامل زیروظایف، سررسید، اولویت، تگ و تکرار)
class TodoImportDialog extends StatefulWidget {
  final String currentUserEmail;
  final String currentUserName;
  final VoidCallback onImported;

  const TodoImportDialog({
    super.key,
    required this.currentUserEmail,
    required this.currentUserName,
    required this.onImported,
  });

  @override
  State<TodoImportDialog> createState() => _TodoImportDialogState();
}

class _TodoImportDialogState extends State<TodoImportDialog> {
  final emailCheckCtrl = TextEditingController();
  Map<String, List<JsonRow>> parsedLists = {};
  Set<String> selectedLists = {};
  String importMode = 'unchecked'; // unchecked, checked, both
  bool importing = false;
  String? errorMsg;

  @override
  void initState() {
    super.initState();
    emailCheckCtrl.text = widget.currentUserEmail;
  }

  @override
  void dispose() {
    emailCheckCtrl.dispose();
    super.dispose();
  }

  String? _normalizeDueDate(dynamic raw) {
    String? str;
    if (raw is Map && raw['dateTime'] != null) {
      str = raw['dateTime'].toString();
    } else if (raw is String && raw.trim().isNotEmpty) {
      str = raw.trim();
    }
    if (str == null) return null;
    final dt = DateTime.tryParse(str);
    if (dt == null) return null;
    return DateTime.utc(dt.year, dt.month, dt.day, 12).toIso8601String();
  }

  String _normalizeRecurrence(dynamic raw) {
    if (raw is String) {
      final v = raw.toLowerCase();
      if (v == 'daily' || v == 'weekly' || v == 'monthly') return v;
      return 'none';
    }
    if (raw is Map) {
      final pType = (raw['pattern'] is Map ? raw['pattern']['type'] : raw['type'])
              ?.toString()
              .toLowerCase() ??
          '';
      if (pType.contains('daily')) return 'daily';
      if (pType.contains('weekly')) return 'weekly';
      if (pType.contains('monthly')) return 'monthly';
    }
    return 'none';
  }

  List<JsonRow> _extractSubtasks(dynamic raw) {
    final result = <JsonRow>[];
    if (raw is! List) return result;
    for (final item in raw) {
      if (item is Map) {
        final title = (item['displayName'] ?? item['title'] ?? '').toString().trim();
        if (title.isEmpty) continue;
        final done = item['isChecked'] == true || item['is_completed'] == true;
        result.add({'title': title, 'is_completed': done});
      }
    }
    return result;
  }

  Future<void> _pickFile() async {
    setState(() => errorMsg = null);
    if (emailCheckCtrl.text.trim().toLowerCase() !=
        widget.currentUserEmail.toLowerCase()) {
      setState(() {
        errorMsg = tr(
          'ایمیل اکانت To Do باید دقیقاً با ایمیل حساب فعلی شما یکسان باشد.',
          'Microsoft To Do email must match your current account email.',
        );
      });
      return;
    }

    final file = await openFile();
    if (file == null) return;
    try {
      final content = utf8.decode(await file.readAsBytes());
      final Map<String, List<JsonRow>> grouped = {};

      if (content.trim().startsWith('{') || content.trim().startsWith('[')) {
        final decoded = jsonDecode(content);
        if (decoded is Map && decoded['email'] != null) {
          final fileMail = decoded['email'].toString().trim().toLowerCase();
          if (fileMail != widget.currentUserEmail.toLowerCase()) {
            setState(() {
              errorMsg = tr(
                'ایمیل ثبت‌شده داخل فایل ($fileMail) با ایمیل اکانت شما یکسان نیست.',
                'Email in file ($fileMail) does not match your account.',
              );
            });
            return;
          }
        }
        final rawLists = (decoded is Map && decoded['lists'] is List)
            ? decoded['lists'] as List
            : (decoded is List ? decoded : []);
        for (final item in rawLists) {
          if (item is Map) {
            final lName =
                (item['displayName'] ?? item['title'] ?? 'لیست To Do')
                    .toString();
            final tasks = (item['tasks'] is List) ? item['tasks'] as List : [];
            grouped.putIfAbsent(lName, () => []);
            for (final t in tasks) {
              if (t is Map) {
                final isImportant =
                    t['importance']?.toString().toLowerCase() == 'high' ||
                        t['is_starred'] == true;
                final rawPriority = t['priority']?.toString().toLowerCase();
                final priority = isImportant
                    ? 'urgent'
                    : (rawPriority == 'urgent' || rawPriority == 'medium'
                        ? rawPriority!
                        : 'normal');
                final rawTags = (t['categories'] is List)
                    ? t['categories'] as List
                    : ((t['tags'] is List) ? t['tags'] as List : []);
                final tags = rawTags
                    .map((e) => e.toString().trim().replaceAll('#', ''))
                    .where((e) => e.isNotEmpty)
                    .toList();

                grouped[lName]!.add({
                  'title': (t['title'] ?? '').toString().trim(),
                  'is_completed': t['status'] == 'completed' ||
                      t['is_completed'] == true,
                  'notes': (t['body'] is Map
                          ? t['body']['content']
                          : t['notes'])
                      ?.toString()
                      .trim() ??
                      '',
                  'due_date': _normalizeDueDate(t['dueDateTime'] ?? t['due_date']),
                  'is_starred': isImportant,
                  'priority': priority,
                  'tags': tags,
                  'recurrence': _normalizeRecurrence(t['recurrence']),
                  'subtasks': _extractSubtasks(t['checklistItems'] ?? t['subtasks']),
                });
              }
            }
          }
        }
      } else {
        final lines = const LineSplitter().convert(content);
        for (int i = 1; i < lines.length; i++) {
          final cols = lines[i].split(',');
          if (cols.length < 2) continue;
          final lName = cols[0].replaceAll('"', '').trim();
          final tTitle = cols[1].replaceAll('"', '').trim();
          final done = cols.length > 2 &&
              ['true', '1', 'completed', 'yes']
                  .contains(cols[2].replaceAll('"', '').trim().toLowerCase());
          final notes = cols.length > 3 ? cols[3].replaceAll('"', '').trim() : '';
          final due = cols.length > 4
              ? _normalizeDueDate(cols[4].replaceAll('"', '').trim())
              : null;
          if (tTitle.isEmpty) continue;
          grouped.putIfAbsent(lName.isEmpty ? 'To Do' : lName, () => []).add({
            'title': tTitle,
            'is_completed': done,
            'notes': notes,
            'due_date': due,
            'is_starred': false,
            'priority': 'normal',
            'tags': <String>[],
            'recurrence': 'none',
            'subtasks': <JsonRow>[],
          });
        }
      }

      if (grouped.isEmpty) {
        setState(() {
          errorMsg = tr(
            'لیستی در فایل انتخاب‌شده شناسایی نشد. از فایل خروجی JSON یا CSV استفاده کنید.',
            'No lists found in the selected JSON/CSV file.',
          );
        });
        return;
      }

      setState(() {
        parsedLists = grouped;
        selectedLists = grouped.keys.toSet();
      });
    } catch (e) {
      setState(() => errorMsg = '${tr('خطا در خواندن فایل:', 'Parse error:')} $e');
    }
  }

  Future<void> _doImport() async {
    if (selectedLists.isEmpty) return;
    setState(() => importing = true);
    try {
      final uid = supabase.auth.currentUser!.id;
      for (final listName in selectedLists) {
        final created = await supabase
            .from('lists')
            .insert({
              'title': listName,
              'owner_id': uid,
              'created_by_name': widget.currentUserName,
            })
            .select('id')
            .single();
        final newListId = created['id'] as String;

        final tasks = parsedLists[listName] ?? [];
        for (final t in tasks) {
          final title = (t['title'] ?? '').toString();
          if (title.isEmpty) continue;
          final done = t['is_completed'] == true;
          if (importMode == 'unchecked' && done) continue;
          if (importMode == 'checked' && !done) continue;

          final notes = (t['notes'] ?? '').toString();
          final insertedTask = await supabase
              .from('tasks')
              .insert({
                'list_id': newListId,
                'title': title,
                'notes': notes,
                'is_completed': done,
                'due_date': t['due_date'],
                'is_starred': t['is_starred'] == true,
                'priority': t['priority'] ?? 'normal',
                'tags': t['tags'] ?? [],
                'recurrence': t['recurrence'] ?? 'none',
                'created_by': uid,
                'created_by_name': widget.currentUserName,
              })
              .select('id')
              .single();

          final newTaskId = insertedTask['id'] as String;

          if (notes.isNotEmpty) {
            await supabase.from('note_history').insert({
              'task_id': newTaskId,
              'content': notes,
              'author_id': uid,
              'author_name': widget.currentUserName,
              'action': 'created',
            });
          }

          final subs = (t['subtasks'] as List?) ?? [];
          for (final s in subs) {
            if (s is Map) {
              await supabase.from('subtasks').insert({
                'task_id': newTaskId,
                'title': s['title'],
                'is_completed': s['is_completed'] == true,
              });
            }
          }
        }
      }
      widget.onImported();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('اطلاعات با تمام جزئیات وارد شد.', 'Full import completed.')),
          ),
        );
      }
    } catch (e) {
      setState(() {
        importing = false;
        errorMsg = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('ورود اطلاعات از Microsoft To Do', 'Import from Microsoft To Do')),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: emailCheckCtrl,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: tr('تأیید ایمیل یکسان اکانت To Do', 'Confirm matching To Do email'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: _pickFile,
                icon: const Icon(Icons.upload_file_rounded),
                label: Text(tr('انتخاب فایل خروجی To Do (JSON یا CSV)', 'Select To Do JSON/CSV file')),
              ),
              if (errorMsg != null) ...[
                const SizedBox(height: 8),
                Text(errorMsg!, style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],
              if (parsedLists.isNotEmpty) ...[
                const Divider(height: 24),
                Text(
                  tr('کدام لیست‌ها وارد شوند؟', 'Which lists to import?'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                ...parsedLists.entries.map((e) => CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('${e.key} (${toPersianDigits(e.value.length.toString())})'),
                      value: selectedLists.contains(e.key),
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            selectedLists.add(e.key);
                          } else {
                            selectedLists.remove(e.key);
                          }
                        });
                      },
                    )),
                const SizedBox(height: 8),
                Text(
                  tr('وضعیت کارها:', 'Which tasks to include?'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                RadioListTile<String>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('فقط کارهای تیک‌نخورده', 'Unchecked only')),
                  value: 'unchecked',
                  groupValue: importMode,
                  onChanged: (v) => setState(() => importMode = v!),
                ),
                RadioListTile<String>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('فقط کارهای تیک‌خورده', 'Completed only')),
                  value: 'checked',
                  groupValue: importMode,
                  onChanged: (v) => setState(() => importMode = v!),
                ),
                RadioListTile<String>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('هر دو (تیک‌خورده و تیک‌نخورده)', 'Both')),
                  value: 'both',
                  groupValue: importMode,
                  onChanged: (v) => setState(() => importMode = v!),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('انصراف', 'Cancel')),
        ),
        if (parsedLists.isNotEmpty)
          FilledButton(
            onPressed: importing ? null : _doImport,
            child: Text(importing ? tr('در حال ورود...', 'Importing...') : tr('شروع ورود', 'Import')),
          ),
      ],
    );
  }
}

// ابزار بازیابی از فایل بکاپ ماهانه
Future<void> showBackupRestoreDialog(
  BuildContext context,
  VoidCallback onRestored,
) async {
  final file = await openFile();
  if (file == null || !context.mounted) return;
  try {
    final decoded = jsonDecode(utf8.decode(await file.readAsBytes()));
    if (decoded is! Map) throw 'فرمت فایل بکاپ معتبر نیست.';
    final lists = (decoded['lists'] as List?) ?? [];
    final tasks = (decoded['tasks'] as List?) ?? [];
    final subtasks = (decoded['subtasks'] as List?) ?? [];

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('بازیابی از فایل بکاپ', 'Restore from Backup')),
        content: Text(
          tr(
            'فایل شامل ${toPersianDigits(lists.length.toString())} لیست و ${toPersianDigits(tasks.length.toString())} کار است. موارد پاک‌شده بدون آسیب به اطلاعات فعلی بازیابی شوند؟',
            'Backup has ${lists.length} lists and ${tasks.length} tasks. Restore missing items?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('انصراف', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('بازیابی', 'Restore')),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    for (final l in lists) {
      await supabase.from('lists').upsert(Map<String, dynamic>.from(l));
    }
    for (final t in tasks) {
      final row = Map<String, dynamic>.from(t);
      row['deleted_at'] = null;
      await supabase.from('tasks').upsert(row);
    }
    for (final s in subtasks) {
      await supabase.from('subtasks').upsert(Map<String, dynamic>.from(s));
    }
    onRestored();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('بازیابی با موفقیت انجام شد.', 'Restore successful.'))),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${tr('خطا در بازیابی:', 'Restore error:')} $e')),
      );
    }
  }
}

// خروجی گزارش CSV از لیست برای اکسل و جلسات
Future<void> exportTasksCsvToClipboard(
  BuildContext context,
  String listTitle,
  List<JsonRow> tasks,
  Map<String, JsonRow> profilesMap,
) async {
  final sb = StringBuffer();
  sb.writeln('Title,Status,Priority,DueDate,CreatedBy,Tags,Notes');
  for (final t in tasks) {
    final title = (t['title'] ?? '').toString().replaceAll(',', ' ');
    final status = t['is_completed'] == true ? 'Done' : 'Open';
    final prio = (t['priority'] ?? 'normal').toString();
    final due = formatAppDate(t['due_date'] as String?);
    final creator = (t['created_by_name'] ?? '').toString().replaceAll(',', ' ');
    final tags = ((t['tags'] as List?) ?? []).join(' ');
    final notes = (t['notes'] ?? '').toString().replaceAll('\n', ' ').replaceAll(',', ' ');
    sb.writeln('"$title","$status","$prio","$due","$creator","$tags","$notes"');
  }
  await Clipboard.setData(ClipboardData(text: sb.toString()));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tr(
            'گزارش CSV لیست «$listTitle» در حافظه کپی شد؛ می‌توانید مستقیم در Excel یا Notepad ذخیره کنید.',
            'CSV report copied to clipboard.',
          ),
        ),
      ),
    );
  }
}
