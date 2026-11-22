import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ------------------------------------------------------------------
// اطلاعات اتصال به Supabase را دقیقاً در این دو خط جایگزین کنید:
const String supabaseUrl = 'https://kvkgyrifhqiukgjkojyx.supabase.co/rest/v1/';
const String supabaseAnonKey = 'sb_publishable_fClXOE3GkV3Gj8VeVTPMSQ_erzUihwc';
// ------------------------------------------------------------------

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );
  runApp(const AryaTasksApp());
}

final supabase = Supabase.instance.client;

String toPersianDigits(String input) {
  const en = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
  const fa = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
  var res = input;
  for (int i = 0; i < 10; i++) {
    res = res.replaceAll(en[i], fa[i]);
  }
  return res;
}

String formatShamsi(String? isoDate, {bool withTime = false}) {
  if (isoDate == null || isoDate.isEmpty) return '';
  final dt = DateTime.tryParse(isoDate)?.toLocal();
  if (dt == null) return '';
  final j = Jalali.fromDateTime(dt);
  final dateStr =
      '${j.year}/${j.month.toString().padLeft(2, '0')}/${j.day.toString().padLeft(2, '0')}';
  if (!withTime) return toPersianDigits(dateStr);
  final timeStr =
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  return toPersianDigits('$dateStr - $timeStr');
}

class AryaTasksApp extends StatelessWidget {
  const AryaTasksApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1F6FEB),
        surface: const Color(0xFFF6F8FA),
      ),
    );

    return MaterialApp(
      title: 'مدیریت کار تیمی',
      debugShowCheckedModeBanner: false,
      theme: baseTheme.copyWith(
        textTheme: GoogleFonts.vazirmatnTextTheme(baseTheme.textTheme),
      ),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? supabase.auth.currentSession;
        if (session != null) {
          return const HomeScreen();
        }
        return const AuthScreen();
      },
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool isLogin = true;
  bool loading = false;
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  final nameCtrl = TextEditingController();

  @override
  void dispose() {
    emailCtrl.dispose();
    passCtrl.dispose();
    nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = emailCtrl.text.trim();
    final pass = passCtrl.text.trim();
    final name = nameCtrl.text.trim();

    if (email.isEmpty || pass.length < 6) {
      _showMsg('لطفاً ایمیل معتبر و رمز عبور حداقل ۶ کاراکتری وارد کنید.');
      return;
    }
    if (!isLogin && name.isEmpty) {
      _showMsg('لطفاً نام و نام خانوادگی خود را وارد کنید.');
      return;
    }

    setState(() => loading = true);
    try {
      if (isLogin) {
        await supabase.auth.signInWithPassword(email: email, password: pass);
      } else {
        await supabase.auth.signUp(
          email: email,
          password: pass,
          data: {'full_name': name},
        );
      }
    } on AuthException catch (e) {
      _showMsg('خطا: ${e.message}');
    } catch (e) {
      _showMsg('خطای ارتباط با سرور: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _showMsg(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEEF2F6),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle_outline_rounded,
                      size: 56,
                      color: Color(0xFF1F6FEB),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isLogin ? 'ورود به میز کار شرکت' : 'ثبت‌نام همکار جدید',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (!isLogin) ...[
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'نام و نام خانوادگی',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(
                        labelText: 'ایمیل سازمانی یا شخصی',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: passCtrl,
                      obscureText: true,
                      textDirection: TextDirection.ltr,
                      onSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(
                        labelText: 'رمز عبور (حداقل ۶ کاراکتر)',
                        prefixIcon: Icon(Icons.lock_outline),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: loading ? null : _submit,
                        child: loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(isLogin ? 'ورود' : 'ساخت حساب کاربری'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => setState(() => isLogin = !isLogin),
                      child: Text(
                        isLogin
                            ? 'حساب ندارید؟ ثبت‌نام کنید'
                            : 'قبلاً ثبت‌نام کرده‌اید؟ وارد شوید',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List> lists = [];
  Map<String, Map<String, dynamic>> profilesMap = {};
  List> currentListMembers = [];

  // اگر null باشد یعنی فیلتر هوشمند (همه یا ستاره‌دار) انتخاب شده
  String? selectedListId;
  String smartFilter = 'all'; // 'all' یا 'starred'
  String? selectedTaskId;
  bool loadingLists = true;

  final quickAddCtrl = TextEditingController();

  String get currentUserId => supabase.auth.currentUser!.id;
  String get currentUserEmail => supabase.auth.currentUser?.email ?? '';

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    quickAddCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => loadingLists = true);
    try {
      final profData = await supabase.from('profiles').select();
      final map = <String, Map<String, dynamic>>{};
      for (final p in profData) {
        map[p['id'] as String] = Map<String, dynamic>.from(p);
      }

      final listData = await supabase
          .from('lists')
          .select()
          .order('created_at', ascending: true);

      if (!mounted) return;
      setState(() {
        profilesMap = map;
        lists = List>.from(listData);
        if (selectedListId == null && lists.isNotEmpty && smartFilter == 'all') {
          selectedListId = lists.first['id'] as String;
        }
        loadingLists = false;
      });

      if (selectedListId != null) {
        await _loadMembers(selectedListId!);
      }
    } catch (e) {
      if (mounted) {
        setState(() => loadingLists = false);
        _showMsg('خطا در دریافت لیست‌ها: $e');
      }
    }
  }

  Future<void> _loadMembers(String listId) async {
    try {
      final data = await supabase
          .from('list_members')
          .select('id, role, user_id, profiles(id, email, full_name)')
          .eq('list_id', listId);
      if (mounted) {
        setState(() {
          currentListMembers = List>.from(data);
        });
      }
    } catch (_) {}
  }

  void _selectList(String? listId, {String filter = 'all'}) {
    setState(() {
      selectedListId = listId;
      smartFilter = filter;
      selectedTaskId = null;
      currentListMembers = [];
    });
    if (listId != null) {
      _loadMembers(listId);
    }
  }

  Future<void> _createListDialog() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ساخت لیست کاری جدید'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'مثلاً: واحد فنی، فروش، پیگیری‌ها...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ساخت لیست'),
          ),
        ],
      ),
    );

    if (ok == true && ctrl.text.trim().isNotEmpty) {
      try {
        final inserted = await supabase
            .from('lists')
            .insert({
              'title': ctrl.text.trim(),
              'owner_id': currentUserId,
            })
            .select()
            .single();
        await _loadInitialData();
        _selectList(inserted['id'] as String);
      } catch (e) {
        _showMsg('خطا در ساخت لیست: $e');
      }
    }
  }

  Future<void> _deleteList(Map<String, dynamic> list) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف لیست'),
        content: Text(
          'آیا از حذف لیست «${list['title']}» و تمام کارهای داخل آن مطمئن هستید؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('خیر'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await supabase.from('lists').delete().eq('id', list['id']);
        if (selectedListId == list['id']) {
          selectedListId = null;
          selectedTaskId = null;
        }
        await _loadInitialData();
      } catch (e) {
        _showMsg('فقط سازنده لیست می‌تواند آن را حذف کند.');
      }
    }
  }

  Future<void> _showMembersDialog() async {
    if (selectedListId == null) return;
    final emailCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('اعضای این لیست و دعوت همکار'),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: emailCtrl,
                          textDirection: TextDirection.ltr,
                          decoration: const InputDecoration(
                            hintText: 'ایمیل همکار (ثبت‌نام شده)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () async {
                          final mail = emailCtrl.text.trim().toLowerCase();
                          if (mail.isEmpty) return;
                          try {
                            final user = await supabase
                                .from('profiles')
                                .select()
                                .ilike('email', mail)
                                .maybeSingle();
                            if (user == null) {
                              _showMsg(
                                'کاربری با این ایمیل هنوز ثبت‌نام نکرده است.',
                              );
                              return;
                            }
                            await supabase.from('list_members').insert({
                              'list_id': selectedListId,
                              'user_id': user['id'],
                              'role': 'member',
                            });
                            emailCtrl.clear();
                            await _loadMembers(selectedListId!);
                            setDialogState(() {});
                            _showMsg('همکار با موفقیت به لیست اضافه شد.');
                          } catch (e) {
                            _showMsg('این کاربر احتمالاً قبلاً عضو لیست است.');
                          }
                        },
                        child: const Text('افزودن'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: currentListMembers.length,
                      itemBuilder: (_, i) {
                        final m = currentListMembers[i];
                        final prof = m['profiles'] as Map<String, dynamic>?;
                        final name = prof?['full_name'] ?? 'کاربر';
                        final email = prof?['email'] ?? '';
                        final role = m['role'] == 'owner' ? 'مدیر' : 'عضو';
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 16,
                            child: Text(
                              name.toString().isNotEmpty
                                  ? name.toString()[0]
                                  : '؟',
                            ),
                          ),
                          title: Text('$name ($role)'),
                          subtitle: Text(email.toString()),
                          trailing: m['role'] != 'owner'
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.person_remove_outlined,
                                    color: Colors.red,
                                    size: 20,
                                  ),
                                  onPressed: () async {
                                    await supabase
                                        .from('list_members')
                                        .delete()
                                        .eq('id', m['id']);
                                    await _loadMembers(selectedListId!);
                                    setDialogState(() {});
                                  },
                                )
                              : null,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('بستن'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addTask() async {
    final title = quickAddCtrl.text.trim();
    if (title.isEmpty) return;
    if (selectedListId == null) {
      _showMsg('ابتدا یک لیست را انتخاب کنید یا لیست جدید بسازید.');
      return;
    }
    quickAddCtrl.clear();
    try {
      await supabase.from('tasks').insert({
        'list_id': selectedListId,
        'title': title,
        'created_by': currentUserId,
      });
    } catch (e) {
      _showMsg('خطا در ثبت کار: $e');
    }
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _getHeaderTitle() {
    if (selectedListId != null) {
      final found = lists.where((l) => l['id'] == selectedListId);
      if (found.isNotEmpty) return found.first['title'] as String;
    }
    return smartFilter == 'starred' ? 'کارهای ستاره‌دار' : 'همه کارها';
  }

  Stream<List>> _tasksStream() {
    if (selectedListId != null) {
      return supabase
          .from('tasks')
          .stream(primaryKey: ['id'])
          .eq('list_id', selectedListId!)
          .order('created_at', ascending: false);
    }
    return supabase
        .from('tasks')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);
  }

  Widget _buildSidebar({bool closeDrawerOnTap = false}) {
    final myProfile = profilesMap[currentUserId];
    final myName = myProfile?['full_name'] ?? currentUserEmail;

    return Container(
      color: const Color(0xFF1B2430),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: const Color(0xFF141B24),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFF1F6FEB),
                    child: Text(
                      myName.toString().isNotEmpty ? myName.toString()[0] : 'ک',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          myName.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          currentUserEmail,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 11,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'به‌روزرسانی لیست‌ها',
                    icon: const Icon(Icons.refresh, color: Colors.white70),
                    onPressed: _loadInitialData,
                  ),
                  IconButton(
                    tooltip: 'خروج از حساب',
                    icon: const Icon(Icons.logout, color: Colors.redAccent),
                    onPressed: () => supabase.auth.signOut(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _sidebarTile(
              icon: Icons.inbox_rounded,
              color: Colors.lightBlueAccent,
              title: 'همه کارها',
              selected: selectedListId == null && smartFilter == 'all',
              onTap: () {
                _selectList(null, filter: 'all');
                if (closeDrawerOnTap) Navigator.pop(context);
              },
            ),
            _sidebarTile(
              icon: Icons.star_rounded,
              color: Colors.amber,
              title: 'ستاره‌دارها',
              selected: selectedListId == null && smartFilter == 'starred',
              onTap: () {
                _selectList(null, filter: 'starred');
                if (closeDrawerOnTap) Navigator.pop(context);
              },
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Divider(color: Colors.white24),
            ),
            Expanded(
              child: loadingLists
                  ? const Center(child: CircularProgressIndicator())
                  : lists.isEmpty
                      ? const Center(
                          child: Text(
                            'هنوز لیستی نساخته‌اید',
                            style: TextStyle(color: Colors.white54),
                          ),
                        )
                      : ListView.builder(
                          itemCount: lists.length,
                          itemBuilder: (_, i) {
                            final list = lists[i];
                            final isSelected = selectedListId == list['id'];
                            final isOwner = list['owner_id'] == currentUserId;
                            return _sidebarTile(
                              icon: Icons.list_alt_rounded,
                              color: Colors.tealAccent,
                              title: list['title'] as String,
                              selected: isSelected,
                              trailing: isOwner
                                  ? IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.white38,
                                        size: 18,
                                      ),
                                      onPressed: () => _deleteList(list),
                                    )
                                  : null,
                              onTap: () {
                                _selectList(list['id'] as String);
                                if (closeDrawerOnTap) Navigator.pop(context);
                              },
                            );
                          },
                        ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1F6FEB),
                  ),
                  onPressed: _createListDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('ساخت لیست جدید'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sidebarTile({
    required IconData icon,
    required Color color,
    required String title,
    required bool selected,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: selected ? Colors.white.withAlpha(30) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: color, size: 22),
        title: Text(
          title,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }

  Widget _buildTasksPane(bool isDesktop) {
    return Container(
      color: const Color(0xFFE9EEF5),
      child: Column(
        children: [
          if (selectedListId != null)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.add, color: Color(0xFF1F6FEB)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: quickAddCtrl,
                      onSubmitted: (_) => _addTask(),
                      decoration: const InputDecoration(
                        hintText: 'افزودن کار جدید و فشردن Enter...',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: _addTask,
                    child: const Text('ثبت'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: StreamBuilder<List>>(
              stream: _tasksStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                var allTasks = snapshot.data ?? [];
                if (selectedListId == null && smartFilter == 'starred') {
                  allTasks = allTasks
                      .where((t) => t['is_starred'] == true)
                      .toList();
                }

                if (allTasks.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.task_alt_rounded,
                          size: 64,
                          color: Colors.grey.withAlpha(120),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'هیچ کاری در این بخش ثبت نشده است.',
                          style: TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  );
                }

                final activeTasks =
                    allTasks.where((t) => t['is_completed'] != true).toList();
                final doneTasks =
                    allTasks.where((t) => t['is_completed'] == true).toList();

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    ...activeTasks.map((t) => _taskCard(t, isDesktop)),
                    if (doneTasks.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'انجام‌شده‌ها (${toPersianDigits(doneTasks.length.toString())})',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                      ...doneTasks.map((t) => _taskCard(t, isDesktop)),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _taskCard(Map<String, dynamic> task, bool isDesktop) {
    final isDone = task['is_completed'] == true;
    final isStarred = task['is_starred'] == true;
    final isSelected = isDesktop && selectedTaskId == task['id'];
    final assigneeId = task['assigned_to'] as String?;
    final assigneeName = assigneeId != null
        ? (profilesMap[assigneeId]?['full_name'] ?? '')
        : '';
    final dueDate = formatShamsi(task['due_date'] as String?);

    return Card(
      elevation: isSelected ? 3 : 0.8,
      color: isSelected
          ? const Color(0xFFE3F2FD)
          : (isDone ? Colors.white.withAlpha(180) : Colors.white),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: isSelected
            ? const BorderSide(color: Color(0xFF1F6FEB), width: 1.5)
            : BorderSide.none,
      ),
      child: ListTile(
        leading: Checkbox(
          value: isDone,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          onChanged: (val) async {
            await supabase
                .from('tasks')
                .update({'is_completed': val ?? false}).eq('id', task['id']);
          },
        ),
        title: Text(
          task['title'] as String,
          style: TextStyle(
            decoration: isDone ? TextDecoration.lineThrough : null,
            color: isDone ? Colors.black45 : Colors.black87,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: (assigneeName.isNotEmpty || dueDate.isNotEmpty)
            ? Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 12,
                  children: [
                    if (dueDate.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.calendar_today,
                            size: 13,
                            color: Colors.blueGrey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            dueDate,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    if (assigneeName.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.person,
                            size: 14,
                            color: Colors.indigo,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            assigneeName.toString(),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                  ],
                ),
              )
            : null,
        trailing: IconButton(
          icon: Icon(
            isStarred ? Icons.star_rounded : Icons.star_border_rounded,
            color: isStarred ? Colors.amber.shade700 : Colors.grey,
          ),
          onPressed: () async {
            await supabase
                .from('tasks')
                .update({'is_starred': !isStarred}).eq('id', task['id']);
          },
        ),
        onTap: () {
          if (isDesktop) {
            setState(() => selectedTaskId = task['id'] as String);
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('جزئیات کار و گفت‌وگو')),
                  body: TaskDetailPanel(
                    taskId: task['id'] as String,
                    profilesMap: profilesMap,
                    onDeleted: () => Navigator.pop(context),
                  ),
                ),
              ),
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F6FEB),
        foregroundColor: Colors.white,
        title: Text(_getHeaderTitle()),
        actions: [
          if (selectedListId != null)
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: _showMembersDialog,
              icon: const Icon(Icons.group_add_outlined),
              label: Text(
                isDesktop
                    ? 'اعضا (${toPersianDigits(currentListMembers.length.toString())})'
                    : toPersianDigits(currentListMembers.length.toString()),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: isDesktop
          ? null
          : Drawer(child: _buildSidebar(closeDrawerOnTap: true)),
      body: isDesktop
          ? Row(
              children: [
                SizedBox(width: 270, child: _buildSidebar()),
                Expanded(flex: 3, child: _buildTasksPane(true)),
                if (selectedTaskId != null)
                  Container(
                    width: 390,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        right: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    child: TaskDetailPanel(
                      key: ValueKey(selectedTaskId),
                      taskId: selectedTaskId!,
                      profilesMap: profilesMap,
                      onClose: () => setState(() => selectedTaskId = null),
                      onDeleted: () => setState(() => selectedTaskId = null),
                    ),
                  ),
              ],
            )
          : _buildTasksPane(false),
    );
  }
}

class TaskDetailPanel extends StatefulWidget {
  final String taskId;
  final Map<String, Map<String, dynamic>> profilesMap;
  final VoidCallback? onClose;
  final VoidCallback? onDeleted;

  const TaskDetailPanel({
    super.key,
    required this.taskId,
    required this.profilesMap,
    this.onClose,
    this.onDeleted,
  });

  @override
  State<TaskDetailPanel> createState() => _TaskDetailPanelState();
}

class _TaskDetailPanelState extends State<TaskDetailPanel> {
  final subtaskCtrl = TextEditingController();
  final commentCtrl = TextEditingController();
  final notesCtrl = TextEditingController();
  bool notesInitialized = false;
  List> listMembers = [];
  String? loadedListId;

  @override
  void dispose() {
    subtaskCtrl.dispose();
    commentCtrl.dispose();
    notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchMembersForTask(String listId) async {
    if (loadedListId == listId) return;
    loadedListId = listId;
    try {
      final data = await supabase
          .from('list_members')
          .select('user_id, profiles(id, full_name, email)')
          .eq('list_id', listId);
      if (mounted) {
        setState(() {
          listMembers = List>.from(data);
        });
      }
    } catch (_) {}
  }

  Future<void> _pickDueDate(Map<String, dynamic> task) async {
    final initial = DateTime.tryParse(task['due_date'] ?? '') ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      await supabase
          .from('tasks')
          .update({'due_date': picked.toIso8601String()}).eq('id', task['id']);
    }
  }

  Future<void> _addSubtask() async {
    final text = subtaskCtrl.text.trim();
    if (text.isEmpty) return;
    subtaskCtrl.clear();
    await supabase.from('subtasks').insert({
      'task_id': widget.taskId,
      'title': text,
    });
  }

  Future<void> _addComment() async {
    final text = commentCtrl.text.trim();
    if (text.isEmpty) return;
    commentCtrl.clear();
    await supabase.from('comments').insert({
      'task_id': widget.taskId,
      'user_id': supabase.auth.currentUser!.id,
      'content': text,
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List>>(
      stream: supabase
          .from('tasks')
          .stream(primaryKey: ['id'])
          .eq('id', widget.taskId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return const Center(child: Text('این کار حذف شده است.'));
        }
        final task = snapshot.data!.first;
        _fetchMembersForTask(task['list_id'] as String);

        if (!notesInitialized) {
          notesCtrl.text = (task['notes'] as String?) ?? '';
          notesInitialized = true;
        }

        final dueStr = formatShamsi(task['due_date'] as String?);
        final currentAssignee = task['assigned_to'] as String?;

        return Column(
          children: [
            if (widget.onClose != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: Colors.grey.shade100,
                child: Row(
                  children: [
                    const Text(
                      'جزئیات کار',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'حذف کار',
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () async {
                        await supabase
                            .from('tasks')
                            .delete()
                            .eq('id', widget.taskId);
                        widget.onDeleted?.call();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Checkbox(
                        value: task['is_completed'] == true,
                        onChanged: (v) async {
                          await supabase.from('tasks').update(
                              {'is_completed': v ?? false}).eq('id', task['id']);
                        },
                      ),
                      Expanded(
                        child: Text(
                          task['title'] as String,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (widget.onClose == null)
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red),
                          onPressed: () async {
                            await supabase
                                .from('tasks')
                                .delete()
                                .eq('id', widget.taskId);
                            widget.onDeleted?.call();
                          },
                        ),
                    ],
                  ),
                  const Divider(),
                  // تاریخ سررسید
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_month_outlined),
                    title: Text(
                      dueStr.isEmpty ? 'تعیین تاریخ سررسید' : 'سررسید: $dueStr',
                    ),
                    trailing: dueStr.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () async {
                              await supabase.from('tasks').update(
                                  {'due_date': null}).eq('id', task['id']);
                            },
                          )
                        : null,
                    onTap: () => _pickDueDate(task),
                  ),
                  // ارجاع به همکار
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_outline),
                    title: DropdownButtonFormField<String?>(
                      value: listMembers
                              .any((m) => m['user_id'] == currentAssignee)
                          ? currentAssignee
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'مسئول انجام کار',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('تعیین نشده'),
                        ),
                        ...listMembers.map((m) {
                          final prof = m['profiles'] as Map<String, dynamic>?;
                          return DropdownMenuItem<String?>(
                            value: m['user_id'] as String,
                            child: Text(
                              (prof?['full_name'] ?? prof?['email'] ?? 'عضو')
                                  .toString(),
                            ),
                          );
                        }),
                      ],
                      onChanged: (val) async {
                        await supabase.from('tasks').update(
                            {'assigned_to': val}).eq('id', task['id']);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  // یادداشت
                  TextField(
                    controller: notesCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'یادداشت و توضیحات',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: 'ذخیره یادداشت',
                        icon: const Icon(Icons.save_outlined),
                        onPressed: () async {
                          await supabase.from('tasks').update(
                              {'notes': notesCtrl.text}).eq('id', task['id']);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('یادداشت ذخیره شد.')),
                            );
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  // زیروظایف
                  const Text(
                    'زیروظایف (چک‌لیست)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: subtaskCtrl,
                          onSubmitted: (_) => _addSubtask(),
                          decoration: const InputDecoration(
                            hintText: 'افزودن مرحله کوچک‌تر...',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _addSubtask,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  StreamBuilder<List>>(
                    stream: supabase
                        .from('subtasks')
                        .stream(primaryKey: ['id'])
                        .eq('task_id', widget.taskId)
                        .order('created_at', ascending: true),
                    builder: (context, subSnap) {
                      final subs = subSnap.data ?? [];
                      return Column(
                        children: subs.map((s) {
                          final done = s['is_completed'] == true;
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Checkbox(
                              value: done,
                              onChanged: (v) async {
                                await supabase.from('subtasks').update(
                                    {'is_completed': v ?? false}).eq(
                                    'id', s['id']);
                              },
                            ),
                            title: Text(
                              s['title'] as String,
                              style: TextStyle(
                                decoration:
                                    done ? TextDecoration.lineThrough : null,
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              onPressed: () async {
                                await supabase
                                    .from('subtasks')
                                    .delete()
                                    .eq('id', s['id']);
                              },
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                  const Divider(height: 28),
                  // بخش گفت‌وگو و کامنت‌ها
                  const Text(
                    'گفت‌وگو و تبادل نظر تیمی',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  StreamBuilder<List>>(
                    stream: supabase
                        .from('comments')
                        .stream(primaryKey: ['id'])
                        .eq('task_id', widget.taskId)
                        .order('created_at', ascending: true),
                    builder: (context, cSnap) {
                      final comments = cSnap.data ?? [];
                      if (comments.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'هنوز پیامی ثبت نشده است.',
                            style: TextStyle(color: Colors.black45),
                          ),
                        );
                      }
                      return Column(
                        children: comments.map((c) {
                          final uid = c['user_id'] as String;
                          final sender =
                              widget.profilesMap[uid]?['full_name'] ?? 'همکار';
                          final isMe = uid == supabase.auth.currentUser?.id;
                          return Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isMe
                                  ? const Color(0xFFE3F2FD)
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      sender.toString(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                    Text(
                                      formatShamsi(
                                        c['created_at'] as String?,
                                        withTime: true,
                                      ),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(c['content'] as String),
                              ],
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
            // کادر ارسال پیام پایین صفحه
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(top: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: commentCtrl,
                      onSubmitted: (_) => _addComment(),
                      decoration: const InputDecoration(
                        hintText: 'نوشتن پیام برای همکاران...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _addComment,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
