import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core.dart';
import 'settings_and_tools.dart';
import 'task_detail.dart';
import 'updater_stub.dart' if (dart.library.io) 'updater_android.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    await BrowserContextMenu.disableContextMenu();
  }
  await appSettings.load();
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );
  runApp(const AryaTasksApp());
}

class AryaTasksApp extends StatelessWidget {
  const AryaTasksApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appSettings,
      builder: (context, _) {
        return MaterialApp(
          title: 'H.A. Tasks',
          debugShowCheckedModeBanner: false,
          theme: appSettings.buildTheme(Brightness.light),
          darkTheme: appSettings.buildTheme(Brightness.dark),
          themeMode: appSettings.isDark ? ThemeMode.dark : ThemeMode.light,
          builder: (context, child) {
            return Directionality(
              textDirection:
                  appSettings.isRtl ? TextDirection.rtl : TextDirection.ltr,
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const AuthGate(),
        );
      },
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
  bool obscurePass = true;
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
      _showMsg(tr('ایمیل معتبر و رمز حداقل ۶ کاراکتری وارد کنید.',
          'Enter valid email and 6+ char password.'));
      return;
    }
    if (!isLogin && name.isEmpty) {
      _showMsg(tr('نام و نام خانوادگی را وارد کنید.', 'Enter your full name.'));
      return;
    }

    setState(() => loading = true);
    try {
      if (isLogin) {
        final res = await supabase.auth
            .signInWithPassword(email: email, password: pass);
        final uid = res.user?.id;
        if (uid != null) {
          final prof = await supabase
              .from('profiles')
              .select('is_active')
              .eq('id', uid)
              .maybeSingle();
          if (prof != null && prof['is_active'] == false) {
            await supabase.auth.signOut();
            _showMsg(tr('حساب کاربری شما توسط مدیر کل غیرفعال شده است.',
                'Your account has been deactivated by admin.'));
            return;
          }
        }
      } else {
        final res = await supabase.auth.signUp(
          email: email,
          password: pass,
          data: {'full_name': name},
        );
        if (res.session == null && mounted) {
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(tr('تأیید ایمیل الزامی است', 'Email Confirmation Required')),
              content: Text(
                tr(
                  'لینک تأیید به ایمیل «$email» ارسال شد. لطفاً صندوق ورودی (یا پوشه Spam) ایمیل خود را باز کرده و روی لینک تأیید کلیک کنید، سپس وارد شوید.',
                  'A verification link was sent to $email. Please confirm your email before signing in.',
                ),
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(tr('متوجه شدم', 'OK')),
                ),
              ],
            ),
          );
          setState(() => isLogin = true);
        }
      }
    } on AuthException catch (e) {
      _showMsg('${tr('خطا:', 'Error:')} ${e.message}');
    } catch (e) {
      _showMsg('${tr('خطای ارتباط با سرور:', 'Connection error:')} $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const HaLogoBadge(size: 64),
                    const SizedBox(height: 14),
                    Text(
                      isLogin
                          ? tr('ورود به میز کار H.A.', 'Sign in to H.A. Tasks')
                          : tr('ثبت‌نام همکار جدید', 'Create Employee Account'),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 22),
                    if (!isLogin) ...[
                      TextField(
                        controller: nameCtrl,
                        decoration: InputDecoration(
                          labelText: tr('نام و نام خانوادگی', 'Full Name'),
                          prefixIcon: const Icon(Icons.person_outline),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                        labelText: tr('ایمیل سازمانی یا شخصی', 'Email'),
                        prefixIcon: const Icon(Icons.email_outlined),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: passCtrl,
                      obscureText: obscurePass,
                      textDirection: TextDirection.ltr,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: tr('رمز عبور (حداقل ۶ کاراکتر)', 'Password (6+ chars)'),
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscurePass
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () =>
                              setState(() => obscurePass = !obscurePass),
                        ),
                        border: const OutlineInputBorder(),
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
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Text(isLogin
                                ? tr('ورود', 'Sign In')
                                : tr('ثبت‌نام و ارسال ایمیل تأیید', 'Sign Up')),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => setState(() => isLogin = !isLogin),
                      child: Text(
                        isLogin
                            ? tr('حساب ندارید؟ ثبت‌نام کنید', 'No account? Sign up')
                            : tr('حساب دارید؟ وارد شوید', 'Have an account? Sign in'),
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

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<JsonRow> lists = [];
  List<JsonRow> _allTasks = [];
  List<JsonRow> _allSubtasks = [];
  Map<String, JsonRow> profilesMap = {};
  Map<String, String> myListRoles = {};
  List<JsonRow> currentListMembers = [];

  String? selectedListId;
  String? quickAddTargetListId;
  // all, today, overdue, starred, assigned, planned
  String smartFilter = 'all';
  String? starredListFilterId;
  String? selectedTaskId;
  String searchQuery = '';
  bool showSearch = false;
  String get sortBy => appSettings.sortBy;

  // انتخاب چندتایی و ترتیب دستی
  bool selectionMode = false;
  final Set<String> selectedTaskIds = {};
  List<String> _manualOrderIds = [];

  bool loadingLists = true;
  int totalStorageUsedBytes = 0;

  final quickAddCtrl = TextEditingController();
  final searchCtrl = TextEditingController();
  StreamSubscription? _sessionSub;
  StreamSubscription? _tasksSub;
  StreamSubscription? _subtasksSub;
  late final Stream<List<JsonRow>> _notificationsStream;

  String get currentUserId => supabase.auth.currentUser!.id;
  String get currentUserEmail => supabase.auth.currentUser?.email ?? '';
  String get currentUserName =>
      (profilesMap[currentUserId]?['full_name'] as String?) ?? currentUserEmail;
  bool get isSuperAdmin => profilesMap[currentUserId]?['is_super_admin'] == true;
  bool get isStorageLow =>
      (storageQuotaBytes - totalStorageUsedBytes) <= lowStorageThresholdBytes;

  bool _canEditList(String? listId) {
    if (isSuperAdmin) return true;
    if (listId == null) return true;
    final role = myListRoles[listId];
    return role == 'owner' || role == 'member';
  }

  bool _isOwnerOfList(String listId) {
    if (isSuperAdmin) return true;
    return myListRoles[listId] == 'owner';
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notificationsStream = supabase
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', currentUserId);
    _tasksSub = supabase
        .from('tasks')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .listen((rows) {
      if (mounted) {
        setState(() => _allTasks = List<JsonRow>.from(rows));
      }
    });
    _subtasksSub = supabase.from('subtasks').stream(primaryKey: ['id']).listen((rows) {
      if (mounted) {
        setState(() => _allSubtasks = List<JsonRow>.from(rows));
      }
    });
    appSettings.addListener(_onSettingsChanged);
    _loadManualOrder();
    _initSessionWatch();
    _loadInitialData();
    _refreshTasks();
    _refreshStorage();
    _checkAndroidPermissions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkForAndroidUpdate(context);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndroidPermissions();
      _refreshTasks();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    appSettings.removeListener(_onSettingsChanged);
    _sessionSub?.cancel();
    _tasksSub?.cancel();
    _subtasksSub?.cancel();
    quickAddCtrl.dispose();
    searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkAndroidPermissions() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final status = await Permission.notification.status;
      if (status.isDenied || status.isPermanentlyDenied) {
        await Permission.notification.request();
      }
    } catch (_) {}
  }

  Future<void> _loadManualOrder() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getStringList('manual_task_order_ids') ?? [];
    if (mounted) setState(() => _manualOrderIds = saved);
  }

  Future<void> _saveManualOrder() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList('manual_task_order_ids', _manualOrderIds);
  }

  Future<void> _initSessionWatch() async {
    final sid = await registerCurrentSession();
    if (sid == null) return;
    _sessionSub = supabase
        .from('user_sessions')
        .stream(primaryKey: ['id'])
        .eq('id', sid)
        .listen((rows) async {
      if (rows.isNotEmpty && rows.first['is_revoked'] == true) {
        final p = await SharedPreferences.getInstance();
        await p.remove('current_session_row_id');
        await supabase.auth.signOut();
      }
    });
  }

  Future<void> _refreshStorage() async {
    final used = await fetchTotalStorageBytes();
    if (mounted) setState(() => totalStorageUsedBytes = used);
  }

  Future<void> _refreshTasks() async {
    try {
      final tData = await supabase
          .from('tasks')
          .select()
          .order('created_at', ascending: false);
      final sData = await supabase.from('subtasks').select();
      if (mounted) {
        setState(() {
          _allTasks = List<JsonRow>.from(tData);
          _allSubtasks = List<JsonRow>.from(sData);
        });
      }
    } catch (_) {}
  }

  Future<void> _loadInitialData() async {
    setState(() => loadingLists = true);
    try {
      final profData = await supabase.from('profiles').select();
      final map = <String, JsonRow>{};
      for (final p in profData) {
        map[p['id'] as String] = JsonRow.from(p);
      }

      if (map[currentUserId]?['is_active'] == false) {
        await supabase.auth.signOut();
        return;
      }

      final memData = await supabase
          .from('list_members')
          .select('list_id, role')
          .eq('user_id', currentUserId);
      final roleMap = <String, String>{};
      for (final m in memData) {
        roleMap[m['list_id'] as String] = m['role'] as String;
      }

      final listData = await supabase
          .from('lists')
          .select()
          .order('created_at', ascending: true);

      if (!mounted) return;
      setState(() {
        profilesMap = map;
        myListRoles = roleMap;
        lists = List<JsonRow>.from(listData);
        if (quickAddTargetListId != null &&
            !lists.any((l) => l['id'] == quickAddTargetListId)) {
          quickAddTargetListId = null;
        }
        loadingLists = false;
      });

      if (selectedListId != null) {
        await _loadMembers(selectedListId!);
      }
      await _refreshTasks();
    } catch (e) {
      if (mounted) {
        setState(() => loadingLists = false);
        _showMsg('${tr('خطا در دریافت داده‌ها:', 'Error:')} $e');
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
        setState(() => currentListMembers = List<JsonRow>.from(data));
      }
    } catch (_) {}
  }

  void _selectList(String? listId, {String filter = 'all'}) {
    setState(() {
      selectedListId = listId;
      smartFilter = filter;
      starredListFilterId = null;
      selectedTaskId = null;
      currentListMembers = [];
      selectionMode = false;
      selectedTaskIds.clear();
    });
    if (listId != null) _loadMembers(listId);
  }

  void _toggleTaskSelection(String taskId) {
    setState(() {
      if (selectedTaskIds.contains(taskId)) {
        selectedTaskIds.remove(taskId);
        if (selectedTaskIds.isEmpty) selectionMode = false;
      } else {
        selectionMode = true;
        selectedTaskIds.add(taskId);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      selectionMode = false;
      selectedTaskIds.clear();
    });
  }

  Future<void> _bulkMoveTasks() async {
    if (selectedTaskIds.isEmpty) return;
    final editableLists =
        lists.where((l) => _canEditList(l['id'] as String)).toList();
    String? targetId =
        editableLists.isNotEmpty ? editableLists.first['id'] as String : null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(tr(
            'انتقال ${toPersianDigits(selectedTaskIds.length.toString())} کار انتخاب‌شده',
            'Move ${selectedTaskIds.length} Selected Tasks',
          )),
          content: DropdownButtonFormField<String?>(
            value: targetId,
            isExpanded: true,
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(tr('بدون لیست (فقط همه کارها)', 'No List (All Tasks)')),
              ),
              ...editableLists.map((l) => DropdownMenuItem<String?>(
                    value: l['id'] as String,
                    child: Text(l['title'] as String),
                  )),
            ],
            onChanged: (v) => setD(() => targetId = v),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('انصراف', 'Cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr('انتقال', 'Move'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await supabase
          .from('tasks')
          .update({'list_id': targetId})
          .inFilter('id', selectedTaskIds.toList());
      _exitSelectionMode();
      await _refreshTasks();
      _showMsg(tr('کارهای انتخاب‌شده منتقل شدند.', 'Selected tasks moved.'));
    } catch (e) {
      _showMsg('$e');
    }
  }

  Future<void> _bulkDeleteTasks() async {
    if (selectedTaskIds.isEmpty) return;
    final count = selectedTaskIds.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('حذف گروهی کارها', 'Delete Selected Tasks')),
        content: Text(
          tr(
            '${toPersianDigits(count.toString())} کار انتخاب‌شده به سطل زباله منتقل شوند؟',
            'Move $count selected tasks to Trash?',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('انصراف', 'Cancel'))),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('حذف همه', 'Delete All'))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final ids = selectedTaskIds.toList();
      await supabase.from('tasks').update({
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
        'deleted_by': currentUserId,
      }).inFilter('id', ids);
      if (selectedTaskId != null && ids.contains(selectedTaskId)) {
        selectedTaskId = null;
      }
      _exitSelectionMode();
      await _refreshTasks();
      _showMsg(tr('کارهای انتخاب‌شده به سطل زباله منتقل شدند.', 'Moved to Trash.'));
    } catch (e) {
      _showMsg('$e');
    }
  }

  // افزودن سریع کار از طریق پنجره (برای صفحه اصلی و گوشی)
  Future<void> _showQuickAddTaskDialog() async {
    final titleCtrl = TextEditingController();
    final editableLists =
        lists.where((l) => _canEditList(l['id'] as String)).toList();
    String? targetList = selectedListId ??
        (editableLists.isNotEmpty ? editableLists.first['id'] as String : null);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(tr('افزودن کار جدید', 'New Task')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                autofocus: true,
                onSubmitted: (_) async {
                  final t = titleCtrl.text.trim();
                  if (t.isEmpty) return;
                  Navigator.pop(ctx);
                  await _addTask(
                      overrideTitle: t,
                      overrideListId: targetList,
                      useOverrideList: true);
                },
                decoration: InputDecoration(
                  labelText: tr('عنوان کار', 'Task title'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                value: targetList,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: tr('انتخاب لیست', 'Select list'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(tr('بدون لیست (فقط همه کارها)', 'No list (All Tasks)')),
                  ),
                  ...editableLists.map((l) => DropdownMenuItem<String?>(
                        value: l['id'] as String,
                        child: Text((l['title'] ?? '').toString()),
                      )),
                ],
                onChanged: (v) => setD(() => targetList = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('انصراف', 'Cancel')),
            ),
            FilledButton(
              onPressed: () async {
                final t = titleCtrl.text.trim();
                if (t.isEmpty) return;
                Navigator.pop(ctx);
                await _addTask(
                    overrideTitle: t,
                    overrideListId: targetList,
                    useOverrideList: true);
              },
              child: Text(tr('ثبت', 'Add')),
            ),
          ],
        ),
      ),
    );
  }

  // ساخت لیست جدید (پشتیبانی از کلید Enter)
  Future<void> _createListDialog() async {
    final ctrl = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('ساخت لیست کاری جدید', 'New List')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          decoration: InputDecoration(
            hintText: tr('نام لیست را بنویسید و Enter بزنید...', 'List title + Enter...'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('انصراف', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(tr('ساخت لیست', 'Create')),
          ),
        ],
      ),
    );

    if (title != null && title.isNotEmpty) {
      try {
        final inserted = await supabase
            .from('lists')
            .insert({
              'title': title,
              'owner_id': currentUserId,
              'created_by_name': currentUserName,
            })
            .select()
            .single();
        await _loadInitialData();
        _selectList(inserted['id'] as String);
      } catch (e) {
        _showMsg('${tr('خطا در ساخت لیست:', 'Error:')} $e');
      }
    }
  }

  Future<void> _copyListDialog(JsonRow list) async {
    final ctrl = TextEditingController(text: '${list['title']} (کپی)');
    bool includeTasks = true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(tr('کپی کردن لیست', 'Copy List')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                decoration: InputDecoration(
                  labelText: tr('نام لیست جدید', 'New List Name'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              RadioListTile<bool>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(tr('همراه با تسک‌ها و زیروظایف (تیک‌نخورده)',
                    'With tasks & subtasks (unchecked)')),
                value: true,
                groupValue: includeTasks,
                onChanged: (v) => setD(() => includeTasks = v!),
              ),
              RadioListTile<bool>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(tr('فقط خود لیست (بدون تسک‌ها)', 'Empty list (no tasks)')),
                value: false,
                groupValue: includeTasks,
                onChanged: (v) => setD(() => includeTasks = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('انصراف', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('کپی', 'Copy')),
            ),
          ],
        ),
      ),
    );

    if (ok != true || ctrl.text.trim().isEmpty) return;
    try {
      final newList = await supabase
          .from('lists')
          .insert({
            'title': ctrl.text.trim(),
            'owner_id': currentUserId,
            'created_by_name': currentUserName,
          })
          .select('id')
          .single();
      final newListId = newList['id'] as String;

      if (includeTasks) {
        final origTasks = await supabase
            .from('tasks')
            .select()
            .eq('list_id', list['id'])
            .isFilter('deleted_at', null);
        for (final t in origTasks) {
          final createdTask = await supabase
              .from('tasks')
              .insert({
                'list_id': newListId,
                'title': t['title'],
                'notes': t['notes'] ?? '',
                'priority': t['priority'] ?? 'normal',
                'tags': t['tags'] ?? [],
                'is_completed': false,
                'created_by': currentUserId,
                'created_by_name': currentUserName,
              })
              .select('id')
              .single();
          final origSubs = await supabase
              .from('subtasks')
              .select('title')
              .eq('task_id', t['id']);
          for (final s in origSubs) {
            await supabase.from('subtasks').insert({
              'task_id': createdTask['id'],
              'title': s['title'],
              'is_completed': false,
            });
          }
        }
      }
      await _loadInitialData();
      _selectList(newListId);
      _showMsg(tr('لیست با موفقیت کپی شد.', 'List copied.'));
    } catch (e) {
      _showMsg('$e');
    }
  }

  Future<void> _deleteList(JsonRow list) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('حذف لیست', 'Delete List')),
        content: Text(
          tr(
            'آیا از حذف لیست «${list['title']}» مطمئن هستید؟',
            'Delete list "${list['title']}"?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('خیر', 'No')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('حذف', 'Delete')),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final listTasks =
          await supabase.from('tasks').select('id').eq('list_id', list['id']);
      for (final t in listTasks) {
        await deleteStorageFilesForTask(t['id'] as String);
      }
      await supabase.from('lists').delete().eq('id', list['id']);
      if (selectedListId == list['id']) {
        selectedListId = null;
        selectedTaskId = null;
      }
      await _loadInitialData();
      await _refreshStorage();
    } catch (e) {
      _showMsg(tr('فقط مدیر اصلی لیست می‌تواند آن را حذف کند.', 'Owner only.'));
    }
  }

  Future<void> _transferListOwnerDialog(JsonRow list) async {
    final members = await supabase
        .from('list_members')
        .select('user_id, role, profiles(full_name, email)')
        .eq('list_id', list['id']);
    final candidates = List<JsonRow>.from(members)
        .where((m) => m['user_id'] != list['owner_id'])
        .toList();
    if (!mounted) return;
    if (candidates.isEmpty) {
      _showMsg(tr('ابتدا همکار دیگری را به این لیست اضافه کنید.', 'Add another member first.'));
      return;
    }

    String selectedUid = candidates.first['user_id'] as String;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(tr('تغییر مدیر اصلی لیست', 'Transfer List Owner')),
          content: DropdownButtonFormField<String>(
            value: selectedUid,
            items: candidates.map((m) {
              final p = m['profiles'] as JsonRow?;
              return DropdownMenuItem(
                value: m['user_id'] as String,
                child: Text('${p?['full_name'] ?? ''} (${p?['email'] ?? ''})'),
              );
            }).toList(),
            onChanged: (v) => setD(() => selectedUid = v!),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('انصراف', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('انتقال مدیریت', 'Transfer')),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await supabase.rpc('transfer_list_owner', params: {
        'target_list_id': list['id'],
        'new_owner_id': selectedUid,
      });
      await _loadInitialData();
      _showMsg(tr('مدیر اصلی لیست تغییر کرد.', 'List owner updated.'));
    } catch (e) {
      _showMsg('$e');
    }
  }

  Future<void> _cleanupCompletedFilesForList(JsonRow list) async {
    final files = await supabase
        .from('task_attachments')
        .select('id, file_name, file_path, file_size, tasks!inner(list_id, is_completed)')
        .eq('tasks.list_id', list['id'])
        .eq('tasks.is_completed', true);
    final items = List<JsonRow>.from(files);
    if (!mounted) return;
    if (items.isEmpty) {
      _showMsg(tr('فایل اضافه‌ای در کارهای تیک‌خورده این لیست وجود ندارد.',
          'No files in completed tasks of this list.'));
      return;
    }
    final totalSize = items.fold<int>(
        0, (s, f) => s + ((f['file_size'] as num?)?.toInt() ?? 0));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('پاکسازی فایل‌های کارهای تیک‌خورده', 'Cleanup Completed Files')),
        content: Text(
          tr(
            '${toPersianDigits(items.length.toString())} فایل (مجموعاً ${formatBytes(totalSize)}) در کارهای تیک‌خورده لیست «${list['title']}» پاک شوند؟',
            'Delete ${items.length} files (${formatBytes(totalSize)}) from completed tasks?',
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
            child: Text(tr('پاکسازی', 'Clean Up')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final paths = items.map((f) => f['file_path'] as String).toList();
    final ids = items.map((f) => f['id'] as String).toList();
    await supabase.storage.from('task-files').remove(paths);
    await supabase.from('task_attachments').delete().inFilter('id', ids);
    await _refreshStorage();
    _showMsg(tr('فایل‌های اضافی پاکسازی شدند.', 'Files cleaned up.'));
  }

  Future<void> _customizeListPersonalDialog(JsonRow list) async {
    final lid = list['id'] as String;
    String? folder = appSettings.listToFolder[lid];
    int? colorVal = appSettings.listColors[lid];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(tr('فولدر و رنگ شخصی لیست', 'Personal Folder & Color')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String?>(
                value: appSettings.personalFolders.contains(folder) ? folder : null,
                decoration: InputDecoration(
                  labelText: tr('انتخاب فولدر شخصی', 'Personal Folder'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(tr('بدون فولدر (اصلی)', 'No Folder')),
                  ),
                  ...appSettings.personalFolders.map(
                    (f) => DropdownMenuItem<String?>(value: f, child: Text(f)),
                  ),
                ],
                onChanged: (v) => setD(() => folder = v),
              ),
              const SizedBox(height: 16),
              Text(tr('رنگ شخصی لیست:', 'Personal Color:')),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(tr('پیش‌فرض', 'Default')),
                    selected: colorVal == null,
                    onSelected: (_) => setD(() => colorVal = null),
                  ),
                  ...listColorOptions.map((c) => InkWell(
                        onTap: () => setD(() => colorVal = c.toARGB32()),
                        child: CircleAvatar(
                          radius: 15,
                          backgroundColor: c,
                          child: colorVal == c.toARGB32()
                              ? const Icon(Icons.check,
                                  color: Colors.white, size: 16)
                              : null,
                        ),
                      )),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('انصراف', 'Cancel')),
            ),
            FilledButton(
              onPressed: () async {
                await appSettings.assignListFolder(lid, folder);
                await appSettings.setListColor(lid, colorVal);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(tr('ذخیره', 'Save')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showListContextMenu(
      Offset pos, JsonRow list, List<JsonRow> allActiveTasks) async {
    final lid = list['id'] as String;
    final owner = _isOwnerOfList(lid);
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      items: [
        PopupMenuItem(
          value: 'copy',
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.copy_rounded),
            title: Text(tr('کپی کردن لیست', 'Copy List')),
          ),
        ),
        PopupMenuItem(
          value: 'personal',
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.palette_outlined),
            title: Text(tr('فولدر و رنگ شخصی', 'Personal Folder/Color')),
          ),
        ),
        PopupMenuItem(
          value: 'csv',
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.table_view_outlined),
            title: Text(tr('خروجی گزارش اکسل (CSV)', 'Export CSV')),
          ),
        ),
        if (owner) ...[
          PopupMenuItem(
            value: 'transfer',
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.swap_horiz_rounded),
              title: Text(tr('تغییر مدیر اصلی لیست', 'Transfer Owner')),
            ),
          ),
          PopupMenuItem(
            value: 'cleanup',
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.cleaning_services_outlined,
                  color: Colors.orange),
              title: Text(tr('پاکسازی فایل‌های تیک‌خورده', 'Cleanup Done Files')),
            ),
          ),
          PopupMenuItem(
            value: 'delete',
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: Text(tr('حذف لیست', 'Delete List'),
                  style: const TextStyle(color: Colors.red)),
            ),
          ),
        ],
      ],
    );

    if (selected == 'copy') await _copyListDialog(list);
    if (selected == 'personal') await _customizeListPersonalDialog(list);
    if (selected == 'transfer') await _transferListOwnerDialog(list);
    if (selected == 'cleanup') await _cleanupCompletedFilesForList(list);
    if (selected == 'delete') await _deleteList(list);
    if (selected == 'csv' && mounted) {
      final listTasks =
          allActiveTasks.where((t) => t['list_id'] == lid).toList();
      await exportTasksCsvToClipboard(
          context, list['title'] as String, listTasks, profilesMap);
    }
  }

  Future<void> _showTaskContextMenu(Offset pos, JsonRow task) async {
    if (!_canEditList(task['list_id'] as String?)) return;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      items: [
        PopupMenuItem(
          value: 'select',
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.checklist_rtl_rounded),
            title: Text(tr('انتخاب چندتایی', 'Select Multiple')),
          ),
        ),
        PopupMenuItem(
          value: 'move',
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.drive_file_move_outline),
            title: Text(tr('انتقال به لیست دیگر', 'Move to Another List')),
          ),
        ),
        PopupMenuItem(
          value: 'copy',
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.copy_rounded),
            title: Text(tr('کپی کردن کار', 'Duplicate Task')),
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: Text(tr('انتقال به سطل زباله', 'Move to Trash'),
                style: const TextStyle(color: Colors.red)),
          ),
        ),
      ],
    );

    if (selected == 'select') {
      _toggleTaskSelection(task['id'] as String);
    } else if (selected == 'copy') {
      await supabase.from('tasks').insert({
        'list_id': task['list_id'],
        'title': '${task['title']} (کپی)',
        'notes': task['notes'] ?? '',
        'priority': task['priority'] ?? 'normal',
        'tags': task['tags'] ?? [],
        'created_by': currentUserId,
        'created_by_name': currentUserName,
      });
      await _refreshTasks();
      _showMsg(tr('کار کپی شد.', 'Task duplicated.'));
    } else if (selected == 'move') {
      final editableLists =
          lists.where((l) => _canEditList(l['id'] as String)).toList();
      if (!mounted) return;
      String? targetId = editableLists.isNotEmpty
          ? editableLists.first['id'] as String
          : null;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setD) => AlertDialog(
            title: Text(tr('انتقال کار به لیست دیگر', 'Move Task')),
            content: DropdownButtonFormField<String?>(
              value: targetId,
              isExpanded: true,
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(tr('بدون لیست (فقط همه کارها)', 'No List (All Tasks)')),
                ),
                ...editableLists.map((l) => DropdownMenuItem<String?>(
                      value: l['id'] as String,
                      child: Text(l['title'] as String),
                    )),
              ],
              onChanged: (v) => setD(() => targetId = v),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(tr('انصراف', 'Cancel'))),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(tr('انتقال', 'Move'))),
            ],
          ),
        ),
      );
      if (ok == true) {
        await supabase
            .from('tasks')
            .update({'list_id': targetId}).eq('id', task['id']);
        await _refreshTasks();
        _showMsg(tr('کار منتقل شد.', 'Task moved.'));
      }
    } else if (selected == 'delete') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('انتقال به سطل زباله', 'Move to Trash')),
          content: Text(
            tr(
              'این تسک، یادداشت‌ها و فایل‌های آن تا ۳۰ روز در سطل زباله باقی می‌مانند و سپس به‌صورت خودکار پاک می‌شوند. ادامه می‌دهید؟',
              'Task, notes, and files remain in Trash for 30 days before automatic removal.',
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('انصراف', 'Cancel'))),
            FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr('حذف', 'Delete'))),
          ],
        ),
      );
      if (confirm == true) {
        await supabase.from('tasks').update({
          'deleted_at': DateTime.now().toUtc().toIso8601String(),
          'deleted_by': currentUserId,
        }).eq('id', task['id']);
        if (selectedTaskId == task['id']) selectedTaskId = null;
        await _refreshTasks();
      }
    }
  }

  Future<void> _showMembersDialog() async {
    if (selectedListId == null) return;
    final emailCtrl = TextEditingController();
    String selectedRole = 'member';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(tr('اعضای لیست و سطح دسترسی', 'List Members & Roles')),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_canEditList(selectedListId)) ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: emailCtrl,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(
                            hintText: tr('ایمیل همکار', 'Employee email'),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      DropdownButton<String>(
                        value: selectedRole,
                        items: [
                          DropdownMenuItem(
                              value: 'member', child: Text(tr('عضو', 'Member'))),
                          DropdownMenuItem(
                              value: 'viewer',
                              child: Text(tr('ناظر', 'Viewer'))),
                        ],
                        onChanged: (v) => setD(() => selectedRole = v!),
                      ),
                      const SizedBox(width: 6),
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
                              _showMsg(tr('کاربری با این ایمیل ثبت‌نام نکرده است.',
                                  'User not found.'));
                              return;
                            }
                            await supabase.from('list_members').insert({
                              'list_id': selectedListId,
                              'user_id': user['id'],
                              'role': selectedRole,
                            });
                            await sendAppNotification(
                              targetUserId: user['id'] as String,
                              title: tr('دعوت به لیست جدید', 'Added to a list'),
                              body: _getHeaderTitle(),
                              listId: selectedListId,
                            );
                            emailCtrl.clear();
                            await _loadMembers(selectedListId!);
                            setD(() {});
                          } catch (_) {
                            _showMsg(tr('این کاربر قبلاً عضو لیست است.', 'Already a member.'));
                          }
                        },
                        child: Text(tr('افزودن', 'Add')),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                ],
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: currentListMembers.length,
                    itemBuilder: (_, i) {
                      final m = currentListMembers[i];
                      final prof = m['profiles'] as JsonRow?;
                      final name = prof?['full_name'] ?? 'کاربر';
                      final email = prof?['email'] ?? '';
                      final role = m['role'] as String;
                      final roleFa = role == 'owner'
                          ? tr('مدیر', 'Owner')
                          : (role == 'viewer'
                              ? tr('ناظر (فقط‌خواندنی)', 'Viewer')
                              : tr('عضو', 'Member'));
                      return ListTile(
                        dense: true,
                        title: Text('$name ($roleFa)'),
                        subtitle: Text(email.toString()),
                        trailing: (role != 'owner' &&
                                _isOwnerOfList(selectedListId!))
                            ? IconButton(
                                icon: const Icon(Icons.person_remove_outlined,
                                    color: Colors.red, size: 20),
                                onPressed: () async {
                                  await supabase
                                      .from('list_members')
                                      .delete()
                                      .eq('id', m['id']);
                                  await _loadMembers(selectedListId!);
                                  setD(() {});
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
                child: Text(tr('بستن', 'Close'))),
          ],
        ),
      ),
    );
  }

  Future<void> _showNotificationsDialog() async {
    final rows = await supabase
        .from('notifications')
        .select()
        .eq('user_id', currentUserId)
        .order('created_at', ascending: false)
        .limit(30);
    final items = List<JsonRow>.from(rows);
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.notifications_active_outlined),
            const SizedBox(width: 8),
            Expanded(child: Text(tr('اعلان‌ها و منشن‌ها', 'Notifications'))),
            TextButton(
              onPressed: () async {
                await supabase
                    .from('notifications')
                    .update({'is_read': true}).eq('user_id', currentUserId);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(tr('خواندن همه', 'Mark all read')),
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: items.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(tr('اعلان جدیدی وجود ندارد.', 'No notifications.')),
                )
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 340),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final n = items[i];
                      final unread = n['is_read'] != true;
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          unread
                              ? Icons.circle
                              : Icons.notifications_none_rounded,
                          size: unread ? 10 : 18,
                          color: unread ? Colors.red : Colors.grey,
                        ),
                        title: Text(
                          n['title'] as String,
                          style: TextStyle(
                            fontWeight:
                                unread ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(
                          '${n['body'] ?? ''}\n${formatAppDate(n['created_at'] as String?, withTime: true)}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        onTap: () async {
                          await supabase
                              .from('notifications')
                              .update({'is_read': true}).eq('id', n['id']);
                          if (n['task_id'] != null) {
                            setState(() =>
                                selectedTaskId = n['task_id'] as String);
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
                ),
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('بستن', 'Close'))),
        ],
      ),
    );
  }

  Future<void> _addTask({
    String? overrideTitle,
    String? overrideListId,
    bool useOverrideList = false,
  }) async {
    final title = (overrideTitle ?? quickAddCtrl.text).trim();
    if (title.isEmpty) return;
    final targetListId = useOverrideList
        ? overrideListId
        : (selectedListId ?? quickAddTargetListId);
    if (targetListId != null && !_canEditList(targetListId)) {
      _showMsg(tr('دسترسی شما در این لیست فقط خواندنی است.', 'View-only access.'));
      return;
    }
    if (overrideTitle == null) quickAddCtrl.clear();
    try {
      final now = DateTime.now();
      final payload = <String, dynamic>{
        'list_id': targetListId,
        'title': title,
        'created_by': currentUserId,
        'created_by_name': currentUserName,
      };
      if (selectedListId == null && smartFilter == 'today') {
        payload['due_date'] =
            DateTime.utc(now.year, now.month, now.day, 12).toIso8601String();
      }
      if (selectedListId == null && smartFilter == 'starred') {
        payload['is_starred'] = true;
      }
      await supabase.from('tasks').insert(payload);
      await _refreshTasks();
    } catch (e) {
      _showMsg('$e');
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
    switch (smartFilter) {
      case 'today':
        return tr('سررسید امروز', 'Due Today');
      case 'overdue':
        return tr('تاریخ‌گذشته‌ها', 'Overdue');
      case 'starred':
        return tr('کارهای ستاره‌دار', 'Starred');
      case 'assigned':
        return tr('واگذارشده به من', 'Assigned to Me');
      case 'planned':
        return tr('برنامه‌ریزی‌شده‌ها', 'Planned');
      default:
        return tr('همه کارها', 'All Tasks');
    }
  }

  bool _isToday(DateTime dt) {
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
  }

  bool _isOverdue(DateTime dt) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    return dt.isBefore(todayStart);
  }

  List<JsonRow> _getFilteredTasks(
    List<JsonRow> allActiveTasks,
    Map<String, List<JsonRow>> subtasksByTask,
  ) {
    var filtered = allActiveTasks.where((t) {
      if (selectedListId != null) return t['list_id'] == selectedListId;
      if (smartFilter == 'starred') {
        if (t['is_starred'] != true) return false;
        if (starredListFilterId != null &&
            t['list_id'] != starredListFilterId) {
          return false;
        }
        return true;
      }
      if (smartFilter == 'today') {
        final d = DateTime.tryParse((t['due_date'] as String?) ?? '')?.toLocal();
        return d != null && _isToday(d);
      }
      if (smartFilter == 'overdue') {
        final d = DateTime.tryParse((t['due_date'] as String?) ?? '')?.toLocal();
        return t['is_completed'] != true && d != null && _isOverdue(d);
      }
      if (smartFilter == 'assigned') {
        if (t['assigned_to'] == currentUserId) return true;
        final subs = subtasksByTask[t['id']] ?? [];
        return subs.any((s) => s['assigned_to'] == currentUserId);
      }
      if (smartFilter == 'planned') {
        return (t['due_date'] as String?) != null;
      }
      return true;
    }).toList();

    if (searchQuery.trim().isNotEmpty) {
      final q = searchQuery.trim().toLowerCase();
      filtered = filtered.where((t) {
        final title = (t['title'] ?? '').toString().toLowerCase();
        final notes = (t['notes'] ?? '').toString().toLowerCase();
        final tags = ((t['tags'] as List?) ?? []).join(' ').toLowerCase();
        return title.contains(q) || notes.contains(q) || tags.contains(q);
      }).toList();
    }

    int prioWeight(String? p) => p == 'urgent' ? 0 : (p == 'medium' ? 1 : 2);
    filtered.sort((a, b) {
      if (sortBy == 'manual') {
        final ia = _manualOrderIds.indexOf(a['id'] as String);
        final ib = _manualOrderIds.indexOf(b['id'] as String);
        if (ia != -1 && ib != -1) return ia.compareTo(ib);
        if (ia != -1) return -1;
        if (ib != -1) return 1;
        return ((b['created_at'] as String?) ?? '')
            .compareTo((a['created_at'] as String?) ?? '');
      }
      if (sortBy == 'due') {
        final da = (a['due_date'] as String?) ?? '9999';
        final db = (b['due_date'] as String?) ?? '9999';
        return da.compareTo(db);
      }
      if (sortBy == 'priority') {
        final sa = a['is_starred'] == true ? 0 : 1;
        final sb = b['is_starred'] == true ? 0 : 1;
        if (sa != sb) return sa.compareTo(sb);
        final pa = prioWeight(a['priority'] as String?);
        final pb = prioWeight(b['priority'] as String?);
        if (pa != pb) return pa.compareTo(pb);
        return ((b['created_at'] as String?) ?? '')
            .compareTo((a['created_at'] as String?) ?? '');
      }
      if (sortBy == 'starred') {
        final sa = a['is_starred'] == true ? 0 : 1;
        final sb = b['is_starred'] == true ? 0 : 1;
        return sa.compareTo(sb);
      }
      return ((b['created_at'] as String?) ?? '')
          .compareTo((a['created_at'] as String?) ?? '');
    });

    return filtered;
  }

  Widget _buildSidebar(
    List<JsonRow> allActiveTasks,
    Map<String, List<JsonRow>> subtasksByTask, {
    bool closeDrawerOnTap = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final totalAll = allActiveTasks.length;
    final doneAll = allActiveTasks.where((t) => t['is_completed'] == true).length;
    final openAll = totalAll - doneAll;

    final openTasks = allActiveTasks.where((t) => t['is_completed'] != true);
    final starredCount = openTasks.where((t) => t['is_starred'] == true).length;
    final todayCount = openTasks.where((t) {
      final d = DateTime.tryParse((t['due_date'] as String?) ?? '')?.toLocal();
      return d != null && _isToday(d);
    }).length;
    final overdueCount = openTasks.where((t) {
      final d = DateTime.tryParse((t['due_date'] as String?) ?? '')?.toLocal();
      return d != null && _isOverdue(d);
    }).length;
    final plannedCount =
        openTasks.where((t) => (t['due_date'] as String?) != null).length;
    final assignedCount = openTasks.where((t) {
      if (t['assigned_to'] == currentUserId) return true;
      final subs = subtasksByTask[t['id']] ?? [];
      return subs.any((s) => s['assigned_to'] == currentUserId);
    }).length;

    Widget buildListRow(JsonRow list) {
      final lid = list['id'] as String;
      final isSel = selectedListId == lid;
      final openInList = openTasks.where((t) => t['list_id'] == lid).length;
      final customColorVal = appSettings.listColors[lid];
      final iconColor =
          customColorVal != null ? Color(customColorVal) : cs.primary;

      return DragTarget<JsonRow>(
        onWillAcceptWithDetails: (details) =>
            _canEditList(lid) && details.data['list_id'] != lid,
        onAcceptWithDetails: (details) async {
          final task = details.data;
          await supabase
              .from('tasks')
              .update({'list_id': lid}).eq('id', task['id']);
          await _refreshTasks();
          _showMsg(tr(
            'کار «${task['title']}» به لیست «${list['title']}» منتقل شد.',
            'Moved "${task['title']}" to "${list['title']}".',
          ));
        },
        builder: (context, candidateData, rejectedData) {
          final isHovering = candidateData.isNotEmpty;
          return GestureDetector(
            onSecondaryTapDown: (d) =>
                _showListContextMenu(d.globalPosition, list, allActiveTasks),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isHovering
                    ? cs.primary.withAlpha(45)
                    : (isSel ? cs.primaryContainer : Colors.transparent),
                borderRadius: BorderRadius.circular(10),
                border: isHovering
                    ? Border.all(color: cs.primary, width: 1.5)
                    : null,
              ),
              child: ListTile(
                dense: true,
                leading:
                    Icon(Icons.list_alt_rounded, color: iconColor, size: 20),
                title: Text(
                  list['title'] as String,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSel ? cs.onPrimaryContainer : cs.onSurface,
                    fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (openInList > 0)
                      Text(
                        toPersianDigits(openInList.toString()),
                        style:
                            TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    IconButton(
                      icon: Icon(Icons.more_vert,
                          size: 16, color: cs.onSurfaceVariant),
                      onPressed: () {
                        final box = context.findRenderObject() as RenderBox?;
                        final pos = box != null
                            ? box.localToGlobal(const Offset(120, 260))
                            : const Offset(120, 260);
                        _showListContextMenu(pos, list, allActiveTasks);
                      },
                    ),
                  ],
                ),
                onTap: () {
                  _selectList(lid);
                  if (closeDrawerOnTap) Navigator.pop(context);
                },
              ),
            ),
          );
        },
      );
    }

    final uncategorizedLists = lists
        .where((l) => !appSettings.personalFolders
            .contains(appSettings.listToFolder[l['id']]))
        .toList();

    return Container(
      color: cs.surface,
      child: SafeArea(
        child: Column(
          children: [
            InkWell(
              onTap: () {
                showDialog(
                  context: context,
                  builder: (_) => UserSettingsDialog(
                    profilesMap: profilesMap,
                    onProfileUpdated: _loadInitialData,
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                color: cs.primaryContainer.withAlpha(110),
                child: Row(
                  children: [
                    const HaLogoBadge(size: 38),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentUserName,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            currentUserEmail,
                            style: TextStyle(
                                fontSize: 11, color: cs.onSurfaceVariant),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.settings_outlined,
                        size: 20, color: cs.onSurfaceVariant),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            _smartTile(
              icon: Icons.inbox_rounded,
              color: cs.primary,
              title: tr('همه کارها', 'All Tasks'),
              selected: selectedListId == null && smartFilter == 'all',
              subtitleWidget: Row(
                children: [
                  Text(
                    '${tr('کل:', 'All:')} ${toPersianDigits(totalAll.toString())}',
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.check_circle, size: 12, color: Colors.green),
                  const SizedBox(width: 2),
                  Text(
                    toPersianDigits(doneAll.toString()),
                    style: const TextStyle(fontSize: 10, color: Colors.green),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.unpublished_outlined,
                      size: 12, color: Colors.red),
                  const SizedBox(width: 2),
                  Text(
                    toPersianDigits(openAll.toString()),
                    style: const TextStyle(fontSize: 10, color: Colors.red),
                  ),
                ],
              ),
              onTap: () {
                _selectList(null, filter: 'all');
                if (closeDrawerOnTap) Navigator.pop(context);
              },
            ),
            _smartTile(
              icon: Icons.star_rounded,
              color: Colors.amber.shade700,
              title: tr('ستاره‌دارها', 'Starred'),
              count: starredCount,
              selected: selectedListId == null && smartFilter == 'starred',
              onTap: () {
                _selectList(null, filter: 'starred');
                if (closeDrawerOnTap) Navigator.pop(context);
              },
            ),
            _smartTile(
              icon: Icons.wb_sunny_outlined,
              color: Colors.orange,
              title: tr('سررسید امروز', 'Due Today'),
              count: todayCount,
              selected: selectedListId == null && smartFilter == 'today',
              onTap: () {
                _selectList(null, filter: 'today');
                if (closeDrawerOnTap) Navigator.pop(context);
              },
            ),
            _smartTile(
              icon: Icons.event_busy_outlined,
              color: Colors.red,
              title: tr('تاریخ‌گذشته‌ها', 'Overdue'),
              count: overdueCount,
              selected: selectedListId == null && smartFilter == 'overdue',
              onTap: () {
                _selectList(null, filter: 'overdue');
                if (closeDrawerOnTap) Navigator.pop(context);
              },
            ),
            _smartTile(
              icon: Icons.assignment_ind_outlined,
              color: Colors.indigo,
              title: tr('واگذارشده به من', 'Assigned to Me'),
              count: assignedCount,
              selected: selectedListId == null && smartFilter == 'assigned',
              onTap: () {
                _selectList(null, filter: 'assigned');
                if (closeDrawerOnTap) Navigator.pop(context);
              },
            ),
            _smartTile(
              icon: Icons.calendar_month_outlined,
              color: Colors.teal,
              title: tr('برنامه‌ریزی‌شده‌ها', 'Planned'),
              count: plannedCount,
              selected: selectedListId == null && smartFilter == 'planned',
              onTap: () {
                _selectList(null, filter: 'planned');
                if (closeDrawerOnTap) Navigator.pop(context);
              },
            ),
            const Divider(height: 16),
            Expanded(
              child: loadingLists
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      children: [
                        ...appSettings.personalFolders.map((folderName) {
                          final folderLists = lists
                              .where((l) =>
                                  appSettings.listToFolder[l['id']] ==
                                  folderName)
                              .toList();
                          return ExpansionTile(
                            initiallyExpanded: true,
                            leading: Icon(Icons.folder_outlined,
                                color: cs.primary, size: 20),
                            title: Text(folderName,
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.bold)),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, size: 16),
                              onPressed: () =>
                                  appSettings.removePersonalFolder(folderName),
                            ),
                            children: folderLists.map(buildListRow).toList(),
                          );
                        }),
                        ...uncategorizedLists.map(buildListRow),
                      ],
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                      ),
                      onPressed: _createListDialog,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(
                        tr('لیست جدید', 'New List'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    onPressed: () async {
                      final c = TextEditingController();
                      final name = await showDialog<String>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(
                              tr('فولدر شخصی جدید', 'New Personal Folder')),
                          content: TextField(
                            controller: c,
                            autofocus: true,
                            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
                            decoration: InputDecoration(
                              hintText: tr('نام فولدر...', 'Folder name...'),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: Text(tr('انصراف', 'Cancel')),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.pop(ctx, c.text.trim()),
                              child: Text(tr('ساخت', 'Create')),
                            ),
                          ],
                        ),
                      );
                      if (name != null && name.isNotEmpty) {
                        await appSettings.addPersonalFolder(name);
                      }
                    },
                    icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                    label: Text(tr('فولدر', 'Folder')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _smartTile({
    required IconData icon,
    required Color color,
    required String title,
    required bool selected,
    required VoidCallback onTap,
    int? count,
    Widget? subtitleWidget,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: selected ? cs.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: color, size: 20),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            color: selected ? cs.onPrimaryContainer : cs.onSurface,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: subtitleWidget,
        trailing: (count != null && count > 0)
            ? Text(
                toPersianDigits(count.toString()),
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              )
            : null,
        onTap: onTap,
      ),
    );
  }

  Widget _buildTasksPane(
    bool isDesktop,
    List<JsonRow> filtered,
    Map<String, List<JsonRow>> subtasksByTask,
    List<String> allTags,
  ) {
    final cs = Theme.of(context).colorScheme;
    final remaining = (storageQuotaBytes - totalStorageUsedBytes)
        .clamp(0, storageQuotaBytes);
    final listTitleMap = {
      for (final l in lists) l['id'] as String: l['title'] as String
    };
    final editableLists =
        lists.where((l) => _canEditList(l['id'] as String)).toList();

    final activeTasks =
        filtered.where((t) => t['is_completed'] != true).toList();
    final doneTasks = filtered.where((t) => t['is_completed'] == true).toList();

    final canAddHere =
        selectedListId == null || _canEditList(selectedListId);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (selectedTaskId != null) {
          setState(() => selectedTaskId = null);
        }
      },
      child: Container(
        color: cs.surfaceContainerLow,
        child: Column(
          children: [
            if (isStorageLow)
              Container(
                width: double.infinity,
                color: Colors.red.shade700,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tr(
                          'هشدار کمبود فضا: فقط ${formatBytes(remaining)} باقی مانده است. از کلیک راست روی لیست‌ها، فایل‌های کارهای تیک‌خورده را پاکسازی کنید.',
                          'Low storage: ${formatBytes(remaining)} left.',
                        ),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            if (selectedListId == null && smartFilter == 'starred')
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: FilterChip(
                        label: Text(tr('همه لیست‌ها', 'All Lists')),
                        selected: starredListFilterId == null,
                        onSelected: (_) =>
                            setState(() => starredListFilterId = null),
                      ),
                    ),
                    ...lists.map((l) => Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: FilterChip(
                            label: Text(l['title'] as String),
                            selected: starredListFilterId == l['id'],
                            onSelected: (_) => setState(() =>
                                starredListFilterId = l['id'] as String),
                          ),
                        )),
                  ],
                ),
              ),
            // کادر افزودن سریع کار (هم در لیست‌ها و هم در صفحه اصلی «همه کارها»)
            if (canAddHere)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.add, color: cs.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: quickAddCtrl,
                            onSubmitted: (_) => _addTask(),
                            decoration: InputDecoration(
                              hintText: tr('افزودن کار جدید و فشردن Enter...',
                                  'Add a task + Enter...'),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                        FilledButton(
                          onPressed: _addTask,
                          child: Text(tr('ثبت', 'Add')),
                        ),
                      ],
                    ),
                    if (selectedListId == null) ...[
                      const Divider(height: 8),
                      Row(
                        children: [
                          Icon(Icons.list_alt_rounded,
                              size: 16, color: cs.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Text(
                            tr('لیست مقصد:', 'List:'),
                            style: TextStyle(
                                fontSize: 12, color: cs.onSurfaceVariant),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String?>(
                                isDense: true,
                                isExpanded: true,
                                value: editableLists.any(
                                        (l) => l['id'] == quickAddTargetListId)
                                    ? quickAddTargetListId
                                    : null,
                                items: [
                                  DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text(
                                      tr('بدون لیست (همه کارها)',
                                          'No list (All Tasks)'),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  ...editableLists.map(
                                    (l) => DropdownMenuItem<String?>(
                                      value: l['id'] as String,
                                      child: Text(
                                        (l['title'] ?? '').toString(),
                                        style: const TextStyle(fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ],
                                onChanged: (v) =>
                                    setState(() => quickAddTargetListId = v),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        tr('هیچ کاری در این بخش وجود ندارد.', 'No tasks here.'),
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 84),
                      children: [
                        ReorderableListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          buildDefaultDragHandles: false,
                          itemCount: activeTasks.length,
                          onReorder: (oldIndex, newIndex) async {
                            if (newIndex > oldIndex) newIndex -= 1;
                            final ids = activeTasks
                                .map((t) => t['id'] as String)
                                .toList();
                            final moved = ids.removeAt(oldIndex);
                            ids.insert(newIndex, moved);
                            // حفظ ترتیب سایر کارها و اعمال ترتیب جدید
                            final rest = _manualOrderIds
                                .where((id) => !ids.contains(id))
                                .toList();
                            setState(() {
                              _manualOrderIds = [...ids, ...rest];
                            });
                            await _saveManualOrder();
                            if (sortBy != 'manual') {
                              await appSettings.setSortBy('manual');
                            }
                          },
                          itemBuilder: (context, index) {
                            final t = activeTasks[index];
                            return KeyedSubtree(
                              key: ValueKey(t['id']),
                              child: _taskCard(
                                t,
                                isDesktop,
                                subtasksByTask[t['id']] ?? [],
                                listTitleMap,
                                allTags,
                                reorderIndex: index,
                              ),
                            );
                          },
                        ),
                        if (doneTasks.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Text(
                              '${tr('انجام‌شده‌ها', 'Completed')} (${toPersianDigits(doneTasks.length.toString())})',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          ...doneTasks.map((t) => _taskCard(
                                t,
                                isDesktop,
                                subtasksByTask[t['id']] ?? [],
                                listTitleMap,
                                allTags,
                              )),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _taskCard(
    JsonRow task,
    bool isDesktop,
    List<JsonRow> subs,
    Map<String, String> listTitleMap,
    List<String> allTags, {
    int? reorderIndex,
  }) {
    final cs = Theme.of(context).colorScheme;
    final taskId = task['id'] as String;
    final isDone = task['is_completed'] == true;
    final isStarred = task['is_starred'] == true;
    final isMultiSelected = selectionMode && selectedTaskIds.contains(taskId);
    final isSelected = isDesktop && !selectionMode && selectedTaskId == taskId;
    final canEdit = _canEditList(task['list_id'] as String?);
    final dueDate = formatAppDate(task['due_date'] as String?);
    final prio = (task['priority'] as String?) ?? 'normal';
    final tags = List<String>.from((task['tags'] as List?) ?? []);

    final assigneeNames = <String>{};
    for (final s in subs) {
      final uid = s['assigned_to'] as String?;
      if (uid != null && profilesMap[uid] != null) {
        assigneeNames.add((profilesMap[uid]!['full_name'] ?? '').toString());
      }
    }
    if (assigneeNames.isEmpty && task['assigned_to'] != null) {
      final uid = task['assigned_to'] as String;
      if (profilesMap[uid] != null) {
        assigneeNames.add((profilesMap[uid]!['full_name'] ?? '').toString());
      }
    }
    final assigneesLabel =
        assigneeNames.where((e) => e.isNotEmpty).join('، ');

    final doneSubs = subs.where((s) => s['is_completed'] == true).length;
    final progress = subs.isEmpty ? 0.0 : (doneSubs / subs.length);
    final listName = listTitleMap[task['list_id']] ?? '';

    Color prioColor = Colors.transparent;
    if (prio == 'urgent') prioColor = Colors.red;
    if (prio == 'medium') prioColor = Colors.orange;

    final cardWidget = GestureDetector(
      onSecondaryTapDown: (d) => _showTaskContextMenu(d.globalPosition, task),
      child: Card(
        elevation: (isSelected || isMultiSelected) ? 3 : 0.8,
        color: isMultiSelected
            ? cs.secondaryContainer
            : (isSelected
                ? cs.primaryContainer.withAlpha(130)
                : (isDone ? cs.surface.withAlpha(170) : cs.surface)),
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: (isSelected || isMultiSelected)
              ? BorderSide(color: cs.primary, width: 1.6)
              : (prioColor != Colors.transparent
                  ? BorderSide(color: prioColor.withAlpha(160), width: 1.2)
                  : BorderSide.none),
        ),
        child: ListTile(
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (reorderIndex != null && !selectionMode)
                ReorderableDragStartListener(
                  index: reorderIndex,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 2, right: 2),
                    child: Icon(Icons.drag_indicator_rounded,
                        size: 20, color: cs.onSurfaceVariant.withAlpha(160)),
                  ),
                ),
              if (selectionMode)
                Checkbox(
                  value: isMultiSelected,
                  onChanged: (_) => _toggleTaskSelection(taskId),
                )
              else
                Checkbox(
                  value: isDone,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4)),
                  onChanged: canEdit
                      ? (val) async {
                          final checked = val ?? false;
                          if (!checked) {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text(tr('بازگشایی کار', 'Reopen Task')),
                                content: Text(
                                  tr(
                                    'موارد قبلی این کار قفل می‌مانند و فقط امکان ثبت به‌روزرسانی جدید وجود دارد. ادامه می‌دهید؟',
                                    'Previous items stay locked; only new updates allowed.',
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: Text(tr('انصراف', 'Cancel'))),
                                  FilledButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: Text(tr('بازگشایی', 'Reopen'))),
                                ],
                              ),
                            );
                            if (ok != true) return;
                            await supabase.from('tasks').update({
                              'is_completed': false,
                              'reopened_at':
                                  DateTime.now().toUtc().toIso8601String(),
                            }).eq('id', taskId);
                          } else {
                            await playTickSound();
                            await supabase.from('tasks').update({
                              'is_completed': true,
                              'completed_at':
                                  DateTime.now().toUtc().toIso8601String(),
                              'completed_by': currentUserId,
                              'completed_by_name': currentUserName,
                            }).eq('id', taskId);
                            await supabase
                                .from('subtasks')
                                .update({'is_locked': true}).eq('task_id', taskId);
                            await supabase
                                .from('comments')
                                .update({'is_locked': true}).eq('task_id', taskId);
                            await supabase
                                .from('note_history')
                                .update({'is_locked': true}).eq('task_id', taskId);
                          }
                          await _refreshTasks();
                        }
                      : null,
                ),
            ],
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  task['title'] as String,
                  style: TextStyle(
                    decoration: isDone ? TextDecoration.lineThrough : null,
                    color: isDone ? cs.onSurfaceVariant : cs.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (selectedListId == null && listName.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    listName,
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (subs.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor: cs.surfaceContainerHighest,
                          valueColor: const AlwaysStoppedAnimation(
                              Color(0xFF16A34A)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${toPersianDigits((progress * 100).round().toString())}٪',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF16A34A),
                      ),
                    ),
                  ],
                ),
              ],
              if (assigneesLabel.isNotEmpty ||
                  dueDate.isNotEmpty ||
                  tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      if (dueDate.isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.calendar_today,
                                size: 12, color: cs.onSurfaceVariant),
                            const SizedBox(width: 3),
                            Text(dueDate, style: const TextStyle(fontSize: 11)),
                          ],
                        ),
                      if (assigneesLabel.isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.group_outlined,
                                size: 13, color: cs.primary),
                            const SizedBox(width: 3),
                            Text(assigneesLabel,
                                style: const TextStyle(fontSize: 11)),
                          ],
                        ),
                      ...tags.map((tg) => Text(
                            '#$tg',
                            style: TextStyle(
                                fontSize: 11,
                                color: cs.primary,
                                fontWeight: FontWeight.w500),
                          )),
                    ],
                  ),
                ),
            ],
          ),
          trailing: selectionMode
              ? null
              : IconButton(
                  icon: Icon(
                    isStarred ? Icons.star_rounded : Icons.star_border_rounded,
                    color: isStarred ? Colors.amber.shade700 : Colors.grey,
                  ),
                  onPressed: canEdit
                      ? () async {
                          await supabase
                              .from('tasks')
                              .update({'is_starred': !isStarred})
                              .eq('id', taskId);
                          await _refreshTasks();
                        }
                      : null,
                ),
          onLongPress: () => _toggleTaskSelection(taskId),
          onTap: () {
            if (selectionMode) {
              _toggleTaskSelection(taskId);
              return;
            }
            if (isDesktop) {
              setState(() => selectedTaskId = taskId);
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar:
                        AppBar(title: Text(tr('جزئیات کار', 'Task Details'))),
                    body: TaskDetailPanel(
                      taskId: taskId,
                      profilesMap: profilesMap,
                      existingTags: allTags,
                      canEdit: canEdit,
                      onStorageChanged: _refreshStorage,
                      onDeleted: () {
                        Navigator.pop(context);
                        _refreshTasks();
                      },
                    ),
                  ),
                ),
              ).then((_) => _refreshTasks());
            }
          },
        ),
      ),
    );

    // روی دسکتاپ/وب می‌توان کارت را مستقیم روی لیست‌های منوی کناری درگ و رها کرد
    if (isDesktop && !selectionMode && canEdit) {
      return Draggable<JsonRow>(
        data: task,
        feedback: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 280,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.primary),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.drive_file_move_outline,
                    size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    task['title'] as String,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: cardWidget),
        child: cardWidget,
      );
    }

    return cardWidget;
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 920;
    final cs = Theme.of(context).colorScheme;

    final allActiveTasks =
        _allTasks.where((t) => t['deleted_at'] == null).toList();
    final allTags = allActiveTasks
        .expand((t) => List<String>.from((t['tags'] as List?) ?? []))
        .toSet()
        .toList();

    final subtasksByTask = <String, List<JsonRow>>{};
    for (final s in _allSubtasks) {
      final tid = s['task_id'] as String;
      subtasksByTask.putIfAbsent(tid, () => []).add(s);
    }

    final filteredTasks = _getFilteredTasks(allActiveTasks, subtasksByTask);

    final selectedTaskListId = selectedTaskId != null
        ? allActiveTasks
            .where((t) => t['id'] == selectedTaskId)
            .map((t) => t['list_id'] as String?)
            .firstOrNull
        : null;

    return Scaffold(
      appBar: selectionMode
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitSelectionMode,
              ),
              title: Text(
                '${toPersianDigits(selectedTaskIds.length.toString())} ${tr('انتخاب‌شده', 'selected')}',
              ),
              actions: [
                IconButton(
                  tooltip: tr('انتخاب همه', 'Select All'),
                  icon: const Icon(Icons.select_all_rounded),
                  onPressed: () {
                    setState(() {
                      if (selectedTaskIds.length == filteredTasks.length) {
                        selectedTaskIds.clear();
                        selectionMode = false;
                      } else {
                        selectedTaskIds
                            .addAll(filteredTasks.map((t) => t['id'] as String));
                      }
                    });
                  },
                ),
                IconButton(
                  tooltip: tr('انتقال گروهی', 'Move Selected'),
                  icon: const Icon(Icons.drive_file_move_outline),
                  onPressed: _bulkMoveTasks,
                ),
                IconButton(
                  tooltip: tr('حذف گروهی', 'Delete Selected'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _bulkDeleteTasks,
                ),
              ],
            )
          : AppBar(
              title: showSearch
                  ? TextField(
                      controller: searchCtrl,
                      autofocus: true,
                      style: TextStyle(color: cs.onPrimary),
                      decoration: InputDecoration(
                        hintText: tr(
                            'جستجو در کارها، یادداشت‌ها و تگ‌ها...', 'Search...'),
                        hintStyle: TextStyle(color: cs.onPrimary.withAlpha(180)),
                        border: InputBorder.none,
                      ),
                      onChanged: (v) => setState(() => searchQuery = v),
                    )
                  : Text(_getHeaderTitle()),
              actions: [
                IconButton(
                  tooltip: tr('انتخاب چندتایی', 'Multi-select'),
                  icon: const Icon(Icons.checklist_rtl_rounded),
                  onPressed: () => setState(() => selectionMode = true),
                ),
                IconButton(
                  tooltip: tr('جستجو', 'Search'),
                  icon: Icon(showSearch ? Icons.close : Icons.search_rounded),
                  onPressed: () {
                    setState(() {
                      showSearch = !showSearch;
                      if (!showSearch) {
                        searchCtrl.clear();
                        searchQuery = '';
                      }
                    });
                  },
                ),
                PopupMenuButton<String>(
                  tooltip: tr('مرتب‌سازی', 'Sort'),
                  icon: const Icon(Icons.sort_rounded),
                  onSelected: (v) => appSettings.setSortBy(v),
                  itemBuilder: (_) => [
                    CheckedPopupMenuItem(
                      value: 'manual',
                      checked: sortBy == 'manual',
                      child: Text(tr('ترتیب دستی (درگ)', 'Manual Order')),
                    ),
                    CheckedPopupMenuItem(
                      value: 'created',
                      checked: sortBy == 'created',
                      child: Text(tr('جدیدترین‌ها', 'Newest')),
                    ),
                    CheckedPopupMenuItem(
                      value: 'due',
                      checked: sortBy == 'due',
                      child: Text(tr('تاریخ سررسید', 'Due Date')),
                    ),
                    CheckedPopupMenuItem(
                      value: 'priority',
                      checked: sortBy == 'priority',
                      child: Text(tr('اولویت', 'Priority')),
                    ),
                    CheckedPopupMenuItem(
                      value: 'starred',
                      checked: sortBy == 'starred',
                      child: Text(tr('ستاره‌دارها', 'Starred')),
                    ),
                  ],
                ),
                StreamBuilder<List<JsonRow>>(
                  stream: _notificationsStream,
                  builder: (ctx, nSnap) {
                    final unread = (nSnap.data ?? [])
                        .where((n) => n['is_read'] != true)
                        .length;
                    return IconButton(
                      tooltip: tr('اعلان‌ها', 'Notifications'),
                      onPressed: _showNotificationsDialog,
                      icon: Badge(
                        isLabelVisible: unread > 0,
                        label: Text(toPersianDigits(unread.toString())),
                        child: const Icon(Icons.notifications_outlined),
                      ),
                    );
                  },
                ),
                if (selectedListId != null)
                  TextButton.icon(
                    style:
                        TextButton.styleFrom(foregroundColor: cs.onPrimary),
                    onPressed: _showMembersDialog,
                    icon: const Icon(Icons.group_add_outlined),
                    label: Text(
                      toPersianDigits(currentListMembers.length.toString()),
                    ),
                  ),
                const SizedBox(width: 6),
              ],
            ),
      drawer: isDesktop
          ? null
          : Drawer(
              child: _buildSidebar(
                allActiveTasks,
                subtasksByTask,
                closeDrawerOnTap: true,
              ),
            ),
      floatingActionButton: selectionMode
          ? null
          : FloatingActionButton.extended(
              onPressed: _showQuickAddTaskDialog,
              icon: const Icon(Icons.add_task_rounded),
              label: Text(tr('کار جدید', 'New Task')),
            ),
      body: isDesktop
          ? Row(
              children: [
                SizedBox(
                  width: 280,
                  child: _buildSidebar(allActiveTasks, subtasksByTask),
                ),
                VerticalDivider(width: 1, color: cs.outlineVariant),
                Expanded(
                  flex: 3,
                  child: _buildTasksPane(
                    true,
                    filteredTasks,
                    subtasksByTask,
                    allTags,
                  ),
                ),
                if (selectedTaskId != null)
                  Container(
                    width: 420,
                    decoration: BoxDecoration(
                      color: cs.surface,
                      border: Border(
                        right: BorderSide(color: cs.outlineVariant),
                      ),
                    ),
                    child: TaskDetailPanel(
                      key: ValueKey(selectedTaskId),
                      taskId: selectedTaskId!,
                      profilesMap: profilesMap,
                      existingTags: allTags,
                      canEdit: _canEditList(selectedTaskListId),
                      onStorageChanged: _refreshStorage,
                      onClose: () => setState(() => selectedTaskId = null),
                      onDeleted: () {
                        setState(() => selectedTaskId = null);
                        _refreshTasks();
                      },
                    ),
                  ),
              ],
            )
          : _buildTasksPane(
              false,
              filteredTasks,
              subtasksByTask,
              allTags,
            ),
    );
  }
}
