import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'core.dart';

const List<String> defaultTagSuggestions = [
  'فوری',
  'مالی',
  'فنی',
  'مشتری',
  'اداری',
  'پیگیری',
  'جلسه',
  'پروژه',
];

class TaskDetailPanel extends StatefulWidget {
  final String taskId;
  final Map<String, JsonRow> profilesMap;
  final List<String> existingTags;
  final bool canEdit;
  final VoidCallback? onClose;
  final VoidCallback? onDeleted;
  final Future<void> Function()? onStorageChanged;

  const TaskDetailPanel({
    super.key,
    required this.taskId,
    required this.profilesMap,
    required this.existingTags,
    required this.canEdit,
    this.onClose,
    this.onDeleted,
    this.onStorageChanged,
  });

  @override
  State<TaskDetailPanel> createState() => _TaskDetailPanelState();
}

class _TaskDetailPanelState extends State<TaskDetailPanel> {
  final subtaskCtrl = TextEditingController();
  final commentCtrl = TextEditingController();
  final noteUpdateCtrl = TextEditingController();
  final tagCtrl = TextEditingController();

  bool uploadingFile = false;
  List<JsonRow> listMembers = [];
  String? loadedListId;
  String? selectedSubtaskAssignee;

  String get currentUid => supabase.auth.currentUser!.id;
  String get currentUserName =>
      (widget.profilesMap[currentUid]?['full_name'] as String?) ??
      (supabase.auth.currentUser?.email ?? 'کاربر');

  @override
  void dispose() {
    subtaskCtrl.dispose();
    commentCtrl.dispose();
    noteUpdateCtrl.dispose();
    tagCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchMembersForTask(String listId) async {
    if (loadedListId == listId) return;
    loadedListId = listId;
    try {
      final data = await supabase
          .from('list_members')
          .select('user_id, role, profiles(id, full_name, email)')
          .eq('list_id', listId);
      if (mounted) {
        setState(() {
          listMembers = List<JsonRow>.from(data);
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleTaskCompleted(JsonRow task, bool newVal) async {
    if (!widget.canEdit) return;
    final nowIso = DateTime.now().toUtc().toIso8601String();

    if (!newVal) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('بازگشایی مجدد کار', 'Reopen Task')),
          content: Text(
            tr(
              'آیا می‌خواهید تیک این کار را بردارید؟ تمام یادداشت‌ها، زیروظایف و کامنت‌های قبلی غیرقابل تغییر باقی می‌مانند و فقط می‌توانید موارد جدید با تاریخ جدید ثبت کنید.',
              'Reopen this task? Previous notes, subtasks, and comments remain locked; you can only add new updates.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('انصراف', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('بازگشایی', 'Reopen')),
            ),
          ],
        ),
      );
      if (confirm != true) return;

      await supabase.from('tasks').update({
        'is_completed': false,
        'reopened_at': nowIso,
      }).eq('id', task['id']);
      await logActivity(widget.taskId, currentUserName, 'کار را دوباره باز کرد');
      return;
    }

    await playTickSound();
    await supabase.from('tasks').update({
      'is_completed': true,
      'completed_at': nowIso,
      'completed_by': currentUid,
      'completed_by_name': currentUserName,
    }).eq('id', task['id']);

    await supabase
        .from('subtasks')
        .update({'is_locked': true}).eq('task_id', widget.taskId);
    await supabase
        .from('comments')
        .update({'is_locked': true}).eq('task_id', widget.taskId);
    await supabase
        .from('note_history')
        .update({'is_locked': true}).eq('task_id', widget.taskId);

    await logActivity(widget.taskId, currentUserName, 'کار را تیک زد (انجام شد)');

    final rec = (task['recurrence'] as String?) ?? 'none';
    if (rec != 'none') {
      final baseDate =
          DateTime.tryParse((task['due_date'] as String?) ?? '') ??
              DateTime.now();
      DateTime nextDate = baseDate;
      if (rec == 'daily') nextDate = baseDate.add(const Duration(days: 1));
      if (rec == 'weekly') nextDate = baseDate.add(const Duration(days: 7));
      if (rec == 'monthly') {
        nextDate = DateTime(baseDate.year, baseDate.month + 1, baseDate.day);
      }
      await supabase.from('tasks').insert({
        'list_id': task['list_id'],
        'title': task['title'],
        'notes': task['notes'] ?? '',
        'priority': task['priority'] ?? 'normal',
        'tags': task['tags'] ?? [],
        'recurrence': rec,
        'due_date': nextDate.toIso8601String(),
        'assigned_to': task['assigned_to'],
        'created_by': currentUid,
        'created_by_name': currentUserName,
      });
      _showMsg(tr('کار تکرارشونده برای دوره بعدی ساخته شد.',
          'Next recurring task created.'));
    }
  }

  Future<void> _softDeleteTask(JsonRow task) async {
    if (!widget.canEdit) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('انتقال به سطل زباله', 'Move to Trash')),
        content: Text(
          tr(
            'با حذف این کار، خود تسک، یادداشت‌ها و فایل‌های ضمیمه آن تا ۳۰ روز در سطل زباله شما باقی می‌مانند و قابل بازیابی هستند و پس از آن به‌صورت خودکار حذف می‌شوند. آیا مطمئن هستید؟',
            'This task, its notes, and attachments will remain in Trash for 30 days before automatic removal. Continue?',
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
            child: Text(tr('تأیید و حذف', 'Delete')),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await supabase.from('tasks').update({
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
      'deleted_by': currentUid,
    }).eq('id', widget.taskId);
    await logActivity(
        widget.taskId, currentUserName, 'کار را به سطل زباله منتقل کرد');
    widget.onDeleted?.call();
  }

  Future<void> _pickDueDate(JsonRow task) async {
    if (!widget.canEdit || task['is_completed'] == true) return;
    final initial = DateTime.tryParse(task['due_date'] ?? '') ?? DateTime.now();
    final picked = await pickAppDate(context, initialDate: initial);
    if (picked != null) {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final pickedDay = DateTime(picked.year, picked.month, picked.day);

      if (pickedDay.isBefore(todayStart) && mounted) {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                const SizedBox(width: 8),
                Text(tr('هشدار تاریخ گذشته', 'Past Date Warning')),
              ],
            ),
            content: Text(
              tr(
                'تاریخ انتخاب‌شده (${formatAppDate(picked.toIso8601String())}) مربوط به گذشته است. آیا مطمئن هستید که می‌خواهید این تاریخ را ثبت کنید؟',
                'The selected date (${formatAppDate(picked.toIso8601String())}) is in the past. Are you sure you want to set it?',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('انصراف', 'Cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr('بله، ثبت شود', 'Yes, Set Date')),
              ),
            ],
          ),
        );
        if (confirm != true) return;
      }

      final safeDateIso =
          DateTime.utc(picked.year, picked.month, picked.day, 12)
              .toIso8601String();
      await supabase
          .from('tasks')
          .update({'due_date': safeDateIso}).eq('id', task['id']);
      await logActivity(
        widget.taskId,
        currentUserName,
        'سررسید را به ${formatAppDate(safeDateIso)} تغییر داد',
      );
    }
  }

  Future<void> _addNoteEntry(JsonRow task) async {
    final text = noteUpdateCtrl.text.trim();
    if (text.isEmpty) return;
    noteUpdateCtrl.clear();
    await supabase.from('note_history').insert({
      'task_id': widget.taskId,
      'content': text,
      'author_id': currentUid,
      'author_name': currentUserName,
      'action': (task['notes'] ?? '').toString().isEmpty ? 'created' : 'updated',
    });
    await supabase.from('tasks').update({'notes': text}).eq('id', task['id']);
    await logActivity(widget.taskId, currentUserName, 'یادداشت جدید ثبت کرد');
  }

  Future<void> _addTag(JsonRow task, String rawTag) async {
    final clean = rawTag.trim().replaceAll('#', '');
    if (clean.isEmpty) return;
    final currentTags = List<String>.from((task['tags'] as List?) ?? []);
    if (!currentTags.contains(clean)) {
      currentTags.add(clean);
      await supabase
          .from('tasks')
          .update({'tags': currentTags}).eq('id', task['id']);
    }
    tagCtrl.clear();
  }

  Future<void> _removeTag(JsonRow task, String tag) async {
    final currentTags = List<String>.from((task['tags'] as List?) ?? []);
    currentTags.remove(tag);
    await supabase
        .from('tasks')
        .update({'tags': currentTags}).eq('id', task['id']);
  }

  Future<void> _uploadAttachment() async {
    try {
      final file = await openFile();
      if (file == null) return;
      final bytes = await file.readAsBytes();

      setState(() => uploadingFile = true);
      final safePath = buildSafeStoragePath(widget.taskId, file.name);

      await supabase.storage.from('task-files').uploadBinary(safePath, bytes);
      await supabase.from('task_attachments').insert({
        'task_id': widget.taskId,
        'file_name': file.name,
        'file_path': safePath,
        'file_size': bytes.length,
        'uploaded_by': currentUid,
      });

      await logActivity(
          widget.taskId, currentUserName, 'فایل «${file.name}» را ضمیمه کرد');
      await widget.onStorageChanged?.call();

      final totalUsed = await fetchTotalStorageBytes();
      final remaining =
          (storageQuotaBytes - totalUsed).clamp(0, storageQuotaBytes);
      if (remaining <= lowStorageThresholdBytes && mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.red),
                const SizedBox(width: 8),
                Text(tr('هشدار پر شدن فضای سرور', 'Low Storage Warning')),
              ],
            ),
            content: Text(
              tr(
                'فایل «${file.name}» آپلود شد، اما حجم باقی‌مانده سرور فقط ${formatBytes(remaining)} است!\nلطفاً مدیر لیست، فایل‌های کارهای تیک‌خورده را پاکسازی کند.',
                'File uploaded, but only ${formatBytes(remaining)} storage remains!',
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
      } else {
        _showMsg(tr('فایل با موفقیت آپلود شد.', 'File uploaded.'));
      }
    } catch (e) {
      _showMsg('${tr('خطا در آپلود:', 'Upload error:')} $e');
    } finally {
      if (mounted) setState(() => uploadingFile = false);
    }
  }

  Future<void> _openAttachment(JsonRow attachment) async {
    try {
      final signedUrl = await supabase.storage
          .from('task-files')
          .createSignedUrl(attachment['file_path'] as String, 3600);
      await launchUrl(Uri.parse(signedUrl),
          mode: LaunchMode.externalApplication);
    } catch (e) {
      _showMsg('$e');
    }
  }

  Future<void> _deleteAttachment(JsonRow attachment) async {
    try {
      await supabase.storage
          .from('task-files')
          .remove([attachment['file_path'] as String]);
      await supabase
          .from('task_attachments')
          .delete()
          .eq('id', attachment['id']);
      await widget.onStorageChanged?.call();
      _showMsg(tr('فایل حذف شد.', 'File deleted.'));
    } catch (e) {
      _showMsg('$e');
    }
  }

  Future<void> _addSubtask(JsonRow task) async {
    final text = subtaskCtrl.text.trim();
    if (text.isEmpty) return;
    subtaskCtrl.clear();
    await supabase.from('subtasks').insert({
      'task_id': widget.taskId,
      'title': text,
      'assigned_to': selectedSubtaskAssignee,
    });
    if (selectedSubtaskAssignee != null) {
      await sendAppNotification(
        targetUserId: selectedSubtaskAssignee!,
        title: tr('زیروظیفه جدید به شما واگذار شد', 'New subtask assigned'),
        body: '${task['title']} -> $text',
        taskId: widget.taskId,
        listId: task['list_id'] as String?,
      );
    }
    setState(() => selectedSubtaskAssignee = null);
  }

  Future<void> _addComment(JsonRow task) async {
    final text = commentCtrl.text.trim();
    if (text.isEmpty) return;
    commentCtrl.clear();
    await supabase.from('comments').insert({
      'task_id': widget.taskId,
      'user_id': currentUid,
      'author_name': currentUserName,
      'content': text,
    });

    for (final m in listMembers) {
      final prof = m['profiles'] as JsonRow?;
      final uid = m['user_id'] as String?;
      if (prof == null || uid == null) continue;
      final fname = (prof['full_name'] ?? '').toString();
      final emailPrefix = (prof['email'] ?? '').toString().split('@').first;
      if ((fname.isNotEmpty && text.contains('@$fname')) ||
          (emailPrefix.isNotEmpty && text.contains('@$emailPrefix'))) {
        await sendAppNotification(
          targetUserId: uid,
          title: '$currentUserName ${tr('شما را منشن کرد', 'mentioned you')}',
          body: '${task['title']}: $text',
          taskId: widget.taskId,
          listId: task['list_id'] as String?,
        );
      }
    }
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _sectionHeader(String title, IconData icon, ColorScheme cs) {
    return Row(
      children: [
        Icon(icon, size: 16, color: cs.primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.bold,
            color: cs.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildClickableText(String text, {TextStyle? style}) {
    final regex = RegExp(
      r'((https?:\/\/|www\.)[^\s]+|(\+98|0)?9\d{9})',
      caseSensitive: false,
    );
    final spans = <InlineSpan>[];
    int lastEnd = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      final token = match.group(0)!;
      final isPhone = RegExp(r'^(\+98|0)?9\d{9}$').hasMatch(token);
      spans.add(
        TextSpan(
          text: token,
          style: const TextStyle(
            color: Colors.blue,
            decoration: TextDecoration.underline,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () async {
              final uri = isPhone
                  ? Uri.parse('tel:$token')
                  : Uri.parse(
                      token.startsWith('http') ? token : 'https://$token',
                    );
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
        ),
      );
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }
    return RichText(
      text: TextSpan(
        style: style ??
            TextStyle(
              fontSize: 12.5,
              color: Theme.of(context).colorScheme.onSurface,
              fontFamily: 'Vazirmatn',
            ),
        children: spans,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final optionStyle = TextStyle(
      fontSize: 12,
      color: cs.onSurfaceVariant,
      fontFamily: 'Vazirmatn',
    );
    final labelStyle = TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      color: cs.onSurface,
      fontFamily: 'Vazirmatn',
    );
    final hintStyle = TextStyle(
      fontSize: 11.5,
      color: cs.onSurfaceVariant.withAlpha(170),
      fontFamily: 'Vazirmatn',
    );

    return StreamBuilder<List<JsonRow>>(
      stream: supabase
          .from('tasks')
          .stream(primaryKey: ['id'])
          .eq('id', widget.taskId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return Center(
              child: Text(tr('این کار حذف شده است.', 'Task deleted.')));
        }
        final task = snapshot.data!.first;
        _fetchMembersForTask(task['list_id'] as String);

        final isDone = task['is_completed'] == true;
        final isEditable = widget.canEdit && !isDone;
        final dueStr = formatAppDate(task['due_date'] as String?);
        final currentAssignee = task['assigned_to'] as String?;
        final currentPriority = (task['priority'] as String?) ?? 'normal';
        final currentRecurrence = (task['recurrence'] as String?) ?? 'none';
        final currentTags = List<String>.from((task['tags'] as List?) ?? []);
        final creatorName =
            (task['created_by_name'] as String?)?.isNotEmpty == true
                ? task['created_by_name'] as String
                : (widget.profilesMap[task['created_by']]?['full_name'] ??
                    'نامشخص');

        final allSuggestions = <String>{
          ...defaultTagSuggestions,
          ...widget.existingTags,
        }.where((t) => !currentTags.contains(t)).toList();

        return Column(
          children: [
            if (widget.onClose != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: cs.surfaceContainerHighest,
                child: Row(
                  children: [
                    Text(
                      tr('جزئیات کار', 'Task Details'),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const Spacer(),
                    if (widget.canEdit)
                      IconButton(
                        tooltip: tr('انتقال به سطل زباله', 'Move to Trash'),
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.red),
                        onPressed: () => _softDeleteTask(task),
                      ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
              ),
            if (isDone)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                color: Colors.green.withAlpha(30),
                child: Row(
                  children: [
                    const Icon(Icons.lock_outline,
                        size: 16, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tr(
                          'این کار تیک خورده و قفل شده است (${task['completed_by_name'] ?? ''} - ${formatAppDate(task['completed_at'] as String?, withTime: true)}).',
                          'Completed and locked.',
                        ),
                        style:
                            const TextStyle(fontSize: 11, color: Colors.green),
                      ),
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
                        value: isDone,
                        onChanged: widget.canEdit
                            ? (v) => _toggleTaskCompleted(task, v ?? false)
                            : null,
                      ),
                      Expanded(
                        child: Text(
                          task['title'] as String,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            decoration:
                                isDone ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                      if (widget.onClose == null && widget.canEdit)
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red),
                          onPressed: () => _softDeleteTask(task),
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${tr('ایجاد توسط:', 'Created by:')} $creatorName • ${formatAppDate(task['created_at'] as String?, withTime: true)}',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: cs.onSurfaceVariant.withAlpha(190),
                      ),
                    ),
                  ),
                  const Divider(height: 16),

                  // کادر مشخص و برجسته برای تاریخ سررسید
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: isEditable ? () => _pickDueDate(task) : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: dueStr.isNotEmpty
                            ? cs.primaryContainer.withAlpha(90)
                            : cs.surfaceContainerHighest.withAlpha(130),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: dueStr.isNotEmpty
                              ? cs.primary.withAlpha(140)
                              : cs.outlineVariant,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_month_rounded,
                              size: 20, color: cs.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tr('تاریخ سررسید', 'Due Date'),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: cs.onSurface,
                                  ),
                                ),
                                Text(
                                  dueStr.isEmpty
                                      ? tr('برای انتخاب تاریخ کلیک کنید',
                                          'Tap to pick a date')
                                      : dueStr,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: dueStr.isNotEmpty
                                        ? cs.primary
                                        : cs.onSurfaceVariant,
                                    fontWeight: dueStr.isNotEmpty
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (dueStr.isNotEmpty && isEditable)
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.clear, size: 17),
                              onPressed: () async {
                                await supabase.from('tasks').update(
                                    {'due_date': null}).eq('id', task['id']);
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // اولویت و تکرار با فونت داخلی ظریف‌تر و کمرنگ‌تر
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: currentPriority,
                          style: optionStyle,
                          decoration: InputDecoration(
                            labelText: tr('اولویت', 'Priority'),
                            labelStyle: labelStyle,
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 'normal',
                              child: Text(tr('عادی', 'Normal'),
                                  style: optionStyle),
                            ),
                            DropdownMenuItem(
                              value: 'medium',
                              child: Text(
                                tr('متوسط', 'Medium'),
                                style: optionStyle.copyWith(
                                    color: Colors.orange.shade700),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'urgent',
                              child: Text(
                                tr('فوری', 'Urgent'),
                                style: optionStyle.copyWith(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                          onChanged: isEditable
                              ? (v) async {
                                  if (v == null) return;
                                  await supabase.from('tasks').update(
                                      {'priority': v}).eq('id', task['id']);
                                  await logActivity(widget.taskId,
                                      currentUserName, 'اولویت را به $v تغییر داد');
                                }
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: currentRecurrence,
                          style: optionStyle,
                          decoration: InputDecoration(
                            labelText: tr('تکرار', 'Repeat'),
                            labelStyle: labelStyle,
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            DropdownMenuItem(
                                value: 'none',
                                child: Text(tr('بدون تکرار', 'None'),
                                    style: optionStyle)),
                            DropdownMenuItem(
                                value: 'daily',
                                child: Text(tr('روزانه', 'Daily'),
                                    style: optionStyle)),
                            DropdownMenuItem(
                                value: 'weekly',
                                child: Text(tr('هفتگی', 'Weekly'),
                                    style: optionStyle)),
                            DropdownMenuItem(
                                value: 'monthly',
                                child: Text(tr('ماهانه', 'Monthly'),
                                    style: optionStyle)),
                          ],
                          onChanged: isEditable
                              ? (v) async {
                                  if (v == null) return;
                                  await supabase.from('tasks').update(
                                      {'recurrence': v}).eq('id', task['id']);
                                }
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // مسئول اصلی کار
                  DropdownButtonFormField<String?>(
                    value: listMembers
                            .any((m) => m['user_id'] == currentAssignee)
                        ? currentAssignee
                        : null,
                    style: optionStyle,
                    decoration: InputDecoration(
                      labelText: tr('مسئول اصلی کار', 'Task Assignee'),
                      labelStyle: labelStyle,
                      prefixIcon: const Icon(Icons.person_outline, size: 18),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(tr('تعیین نشده', 'Unassigned'),
                            style: optionStyle),
                      ),
                      ...listMembers.map((m) {
                        final prof = m['profiles'] as JsonRow?;
                        return DropdownMenuItem<String?>(
                          value: m['user_id'] as String,
                          child: Text(
                            (prof?['full_name'] ?? prof?['email'] ?? 'عضو')
                                .toString(),
                            style: optionStyle,
                          ),
                        );
                      }),
                    ],
                    onChanged: isEditable
                        ? (val) async {
                            await supabase.from('tasks').update(
                                {'assigned_to': val}).eq('id', task['id']);
                            final targetName = val != null
                                ? (widget.profilesMap[val]?['full_name'] ?? '')
                                : 'تعیین نشده';
                            await logActivity(widget.taskId, currentUserName,
                                'مسئول کار را به $targetName تغییر داد');
                            if (val != null) {
                              await sendAppNotification(
                                targetUserId: val,
                                title: tr('کار جدید به شما واگذار شد',
                                    'Task assigned to you'),
                                body: task['title'] as String,
                                taskId: widget.taskId,
                                listId: task['list_id'] as String?,
                              );
                            }
                          }
                        : null,
                  ),
                  const SizedBox(height: 16),

                  // برچسب‌ها
                  _sectionHeader(
                      tr('برچسب‌ها (تگ‌ها)', 'Tags'), Icons.tag_rounded, cs),
                  const SizedBox(height: 6),
                  if (currentTags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: currentTags
                            .map((t) => Chip(
                                  label: Text('#$t',
                                      style: const TextStyle(fontSize: 11.5)),
                                  visualDensity: VisualDensity.compact,
                                  onDeleted: isEditable
                                      ? () => _removeTag(task, t)
                                      : null,
                                ))
                            .toList(),
                      ),
                    ),
                  if (isEditable)
                    Autocomplete<String>(
                      optionsBuilder: (val) {
                        final q = val.text.trim().replaceAll('#', '');
                        if (q.isEmpty) return allSuggestions.take(5);
                        return allSuggestions.where(
                            (s) => s.toLowerCase().contains(q.toLowerCase()));
                      },
                      onSelected: (sel) => _addTag(task, sel),
                      fieldViewBuilder: (ctx, ctrl, focus, onSubmit) {
                        return TextField(
                          controller: ctrl,
                          focusNode: focus,
                          style: const TextStyle(fontSize: 12.5),
                          onSubmitted: (v) {
                            _addTag(task, v);
                            ctrl.clear();
                          },
                          decoration: InputDecoration(
                            hintText: tr(
                                'تایپ تگ جدید یا انتخاب از پیشنهادها...',
                                'Add tag...'),
                            hintStyle: hintStyle,
                            border: const OutlineInputBorder(),
                            isDense: true,
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.add, size: 18),
                              onPressed: () {
                                _addTag(task, ctrl.text);
                                ctrl.clear();
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  const Divider(height: 24),

                  // زیروظایف
                  StreamBuilder<List<JsonRow>>(
                    stream: supabase
                        .from('subtasks')
                        .stream(primaryKey: ['id'])
                        .eq('task_id', widget.taskId)
                        .order('created_at', ascending: true),
                    builder: (context, subSnap) {
                      final subs = subSnap.data ?? [];
                      final doneCount =
                          subs.where((s) => s['is_completed'] == true).length;
                      final percent =
                          subs.isEmpty ? 0.0 : (doneCount / subs.length);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _sectionHeader(
                                  tr('زیروظایف (چک‌لیست)', 'Subtasks'),
                                  Icons.checklist_rounded,
                                  cs),
                              if (subs.isNotEmpty)
                                Text(
                                  '${toPersianDigits((percent * 100).round().toString())}٪',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF16A34A),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                            ],
                          ),
                          if (subs.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: percent,
                                minHeight: 7,
                                backgroundColor: cs.surfaceContainerHighest,
                                valueColor: const AlwaysStoppedAnimation(
                                    Color(0xFF16A34A)),
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          if (isEditable) ...[
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: subtaskCtrl,
                                    style: const TextStyle(fontSize: 12.5),
                                    onSubmitted: (_) => _addSubtask(task),
                                    decoration: InputDecoration(
                                      hintText: tr('افزودن زیروظیفه...',
                                          'Add subtask...'),
                                      hintStyle: hintStyle,
                                      border: const OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                PopupMenuButton<String?>(
                                  tooltip: tr('ارجاع این زیروظیفه به همکار',
                                      'Assign subtask'),
                                  icon: Icon(
                                    Icons.person_add_alt_1_outlined,
                                    size: 20,
                                    color: selectedSubtaskAssignee != null
                                        ? cs.primary
                                        : cs.onSurfaceVariant,
                                  ),
                                  onSelected: (v) => setState(
                                      () => selectedSubtaskAssignee = v),
                                  itemBuilder: (_) => [
                                    PopupMenuItem<String?>(
                                      value: null,
                                      child: Text(
                                          tr('بدون مسئول', 'Unassigned'),
                                          style: optionStyle),
                                    ),
                                    ...listMembers.map((m) {
                                      final p = m['profiles'] as JsonRow?;
                                      return PopupMenuItem<String?>(
                                        value: m['user_id'] as String,
                                        child: Text(
                                          (p?['full_name'] ??
                                                  p?['email'] ??
                                                  'عضو')
                                              .toString(),
                                          style: optionStyle,
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                                IconButton.filled(
                                  onPressed: () => _addSubtask(task),
                                  icon: const Icon(Icons.add, size: 18),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                          ],
                          ...subs.map((s) {
                            final done = s['is_completed'] == true;
                            final locked = s['is_locked'] == true || !isEditable;
                            final subAssigneeId = s['assigned_to'] as String?;
                            final subAssigneeName = subAssigneeId != null
                                ? (widget.profilesMap[subAssigneeId]
                                        ?['full_name'] ??
                                    '')
                                : '';
                            final compBy =
                                (s['completed_by_name'] ?? '').toString();
                            final compAt = formatAppDate(
                                s['completed_at'] as String?,
                                withTime: true);

                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Checkbox(
                                value: done,
                                onChanged: locked
                                    ? null
                                    : (v) async {
                                        final checked = v ?? false;
                                        if (checked) await playTickSound();
                                        await supabase.from('subtasks').update({
                                          'is_completed': checked,
                                          'completed_by':
                                              checked ? currentUid : null,
                                          'completed_by_name':
                                              checked ? currentUserName : '',
                                          'completed_at': checked
                                              ? DateTime.now()
                                                  .toUtc()
                                                  .toIso8601String()
                                              : null,
                                        }).eq('id', s['id']);
                                      },
                              ),
                              title: Text(
                                s['title'] as String,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  decoration:
                                      done ? TextDecoration.lineThrough : null,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (subAssigneeName.toString().isNotEmpty)
                                    Text(
                                      '${tr('مسئول:', 'Assignee:')} $subAssigneeName',
                                      style: TextStyle(
                                          fontSize: 10.5, color: cs.primary),
                                    ),
                                  if (done && compBy.isNotEmpty)
                                    Text(
                                      '${tr('تیک توسط:', 'Checked by:')} $compBy • $compAt',
                                      style: const TextStyle(
                                          fontSize: 10, color: Colors.green),
                                    ),
                                ],
                              ),
                              trailing: locked
                                  ? const Icon(Icons.lock_outline,
                                      size: 14, color: Colors.grey)
                                  : IconButton(
                                      icon: const Icon(Icons.close, size: 16),
                                      onPressed: () async {
                                        await supabase
                                            .from('subtasks')
                                            .delete()
                                            .eq('id', s['id']);
                                      },
                                    ),
                            );
                          }),
                        ],
                      );
                    },
                  ),
                  const Divider(height: 24),

                  // یادداشت‌ها
                  _sectionHeader(
                      tr('یادداشت‌ها و تاریخچه به‌روزرسانی', 'Notes & History'),
                      Icons.notes_rounded,
                      cs),
                  const SizedBox(height: 8),
                  if (isEditable)
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: noteUpdateCtrl,
                            maxLines: 2,
                            style: const TextStyle(fontSize: 12.5),
                            decoration: InputDecoration(
                              hintText: tr(
                                  'ثبت یادداشت یا به‌روزرسانی جدید...',
                                  'Add new note update...'),
                              hintStyle: hintStyle,
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          tooltip: tr('ثبت یادداشت', 'Save Note'),
                          onPressed: () => _addNoteEntry(task),
                          icon: const Icon(Icons.save_outlined, size: 18),
                        ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  StreamBuilder<List<JsonRow>>(
                    stream: supabase
                        .from('note_history')
                        .stream(primaryKey: ['id'])
                        .eq('task_id', widget.taskId)
                        .order('created_at', ascending: false),
                    builder: (context, nhSnap) {
                      final entries = nhSnap.data ?? [];
                      if (entries.isEmpty) {
                        final fallback = (task['notes'] ?? '').toString();
                        if (fallback.isEmpty) {
                          return Text(
                            tr('یادداشتی ثبت نشده است.', 'No notes yet.'),
                            style: hintStyle,
                          );
                        }
                        return _buildClickableText(fallback);
                      }
                      return Column(
                        children: entries.map((n) {
                          final locked = n['is_locked'] == true;
                          return Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest.withAlpha(140),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    if (locked)
                                      const Padding(
                                        padding: EdgeInsets.only(left: 4),
                                        child: Icon(Icons.lock_outline,
                                            size: 12, color: Colors.grey),
                                      ),
                                    Text(
                                      n['author_name'] as String,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11),
                                    ),
                                    const Spacer(),
                                    Text(
                                      formatAppDate(n['created_at'] as String?,
                                          withTime: true),
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: cs.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                _buildClickableText(n['content'] as String),
                              ],
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                  const Divider(height: 24),

                  // فایل‌های ضمیمه
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _sectionHeader(tr('فایل‌های ضمیمه', 'Attachments'),
                          Icons.attach_file_rounded, cs),
                      if (isEditable)
                        FilledButton.tonalIcon(
                          onPressed: uploadingFile ? null : _uploadAttachment,
                          icon: uploadingFile
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.upload_file_rounded, size: 16),
                          label: Text(
                            uploadingFile
                                ? tr('در حال آپلود...', 'Uploading...')
                                : tr('افزودن فایل', 'Add File'),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  StreamBuilder<List<JsonRow>>(
                    stream: supabase
                        .from('task_attachments')
                        .stream(primaryKey: ['id'])
                        .eq('task_id', widget.taskId)
                        .order('created_at', ascending: true),
                    builder: (context, attSnap) {
                      final files = attSnap.data ?? [];
                      if (files.isEmpty) {
                        return Text(
                          tr('فایلی ضمیمه نشده است.', 'No files attached.'),
                          style: hintStyle,
                        );
                      }
                      return Column(
                        children: files.map((f) {
                          final size = (f['file_size'] as num?)?.toInt() ?? 0;
                          return Card(
                            elevation: 0,
                            color: cs.surfaceContainerHighest,
                            margin: const EdgeInsets.only(bottom: 6),
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.insert_drive_file_outlined,
                                  size: 18, color: cs.primary),
                              title: Text(f['file_name'] as String,
                                  style: const TextStyle(fontSize: 12),
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text(formatBytes(size),
                                  style: const TextStyle(fontSize: 10.5)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: tr('دانلود', 'Download'),
                                    icon: const Icon(Icons.download_rounded,
                                        size: 18),
                                    onPressed: () => _openAttachment(f),
                                  ),
                                  if (isEditable)
                                    IconButton(
                                      tooltip: tr('حذف فایل', 'Delete file'),
                                      icon: const Icon(Icons.delete_outline,
                                          color: Colors.red, size: 18),
                                      onPressed: () => _deleteAttachment(f),
                                    ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                  const Divider(height: 24),

                  // گفت‌وگو و تبادل نظر
                  _sectionHeader(
                      tr('گفت‌وگو و تبادل نظر (با @ منشن کنید)',
                          'Comments (use @ to mention)'),
                      Icons.chat_bubble_outline_rounded,
                      cs),
                  const SizedBox(height: 8),
                  StreamBuilder<List<JsonRow>>(
                    stream: supabase
                        .from('comments')
                        .stream(primaryKey: ['id'])
                        .eq('task_id', widget.taskId)
                        .order('created_at', ascending: true),
                    builder: (context, cSnap) {
                      final comments = cSnap.data ?? [];
                      if (comments.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            tr('هنوز پیامی ثبت نشده است.', 'No comments yet.'),
                            style: hintStyle,
                          ),
                        );
                      }
                      return Column(
                        children: comments.map((c) {
                          final uid = c['user_id'] as String?;
                          final sender =
                              (c['author_name'] as String?)?.isNotEmpty == true
                                  ? c['author_name'] as String
                                  : (uid != null
                                      ? (widget.profilesMap[uid]?['full_name'] ??
                                          'همکار')
                                      : 'همکار سابق');
                          final isMe = uid == currentUid;
                          return Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isMe
                                  ? cs.primaryContainer
                                  : cs.surfaceContainerHighest,
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
                                          fontSize: 11.5),
                                    ),
                                    Text(
                                      formatAppDate(c['created_at'] as String?,
                                          withTime: true),
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: cs.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                _buildClickableText(c['content'] as String),
                              ],
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                  const Divider(height: 24),

                  // سابقه تغییرات
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: _sectionHeader(
                        tr('سابقه تغییرات (Activity Log)', 'Activity Log'),
                        Icons.history_rounded,
                        cs),
                    children: [
                      StreamBuilder<List<JsonRow>>(
                        stream: supabase
                            .from('activity_logs')
                            .stream(primaryKey: ['id'])
                            .eq('task_id', widget.taskId)
                            .order('created_at', ascending: false),
                        builder: (context, logSnap) {
                          final logs = logSnap.data ?? [];
                          if (logs.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                tr('تغییری ثبت نشده است.', 'No activity yet.'),
                                style: hintStyle,
                              ),
                            );
                          }
                          return Column(
                            children: logs
                                .take(20)
                                .map((l) => ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      leading:
                                          const Icon(Icons.history, size: 15),
                                      title: Text(
                                        '${l['actor_name']}: ${l['action']}',
                                        style: const TextStyle(fontSize: 11.5),
                                      ),
                                      subtitle: Text(
                                        formatAppDate(
                                            l['created_at'] as String?,
                                            withTime: true),
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                    ))
                                .toList(),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (isEditable)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.surface,
                  border: Border(top: BorderSide(color: cs.outlineVariant)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: commentCtrl,
                        style: const TextStyle(fontSize: 12.5),
                        onSubmitted: (_) => _addComment(task),
                        decoration: InputDecoration(
                          hintText: tr('نوشتن پیام برای همکاران...',
                              'Write a comment...'),
                          hintStyle: hintStyle,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: () => _addComment(task),
                      icon: const Icon(Icons.send_rounded, size: 18),
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
