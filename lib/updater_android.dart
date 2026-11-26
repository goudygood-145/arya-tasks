import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'core.dart';

const int currentBuildNumber =
    int.fromEnvironment('APP_BUILD_NUMBER', defaultValue: 0);
const String versionJsonUrl =
    'https://github.com/goudygood-145/arya-tasks/releases/latest/download/version.json';
const String updateApkFileName = 'ha_tasks_update.apk';

Future<void> _cleanupDownloadedApk() async {
  try {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$updateApkFileName');
    if (await file.exists()) {
      await file.delete();
    }
  } catch (_) {}
}

Future<void> checkForAndroidUpdate(BuildContext context) async {
  if (!Platform.isAndroid) return;

  // به محض باز شدن برنامه (از جمله پس از اتمام نصب/آپدیت)، فایل APK قبلی پاک می‌شود
  await _cleanupDownloadedApk();

  if (currentBuildNumber <= 0) return;

  try {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    final req = await client.getUrl(Uri.parse(versionJsonUrl));
    final resp = await req.close().timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) {
      client.close();
      return;
    }

    final body = await resp.transform(utf8.decoder).join();
    client.close();

    final data = jsonDecode(body);
    final remoteBuild = (data['build'] as num?)?.toInt() ?? 0;
    final apkUrl = (data['apk_url'] as String?) ?? '';

    if (remoteBuild <= currentBuildNumber || apkUrl.isEmpty) return;
    if (!context.mounted) return;

    await _showUpdateDialog(context, remoteBuild, apkUrl);
  } catch (_) {}
}

Future<void> _showUpdateDialog(
  BuildContext context,
  int remoteBuild,
  String apkUrl,
) async {
  bool downloading = false;
  double progress = 0.0;
  String? errorText;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) {
        Future<void> startDownloadAndInstall() async {
          setD(() {
            downloading = true;
            progress = 0.0;
            errorText = null;
          });

          HttpClient? client;
          try {
            final dir = await getTemporaryDirectory();
            final apkFile = File('${dir.path}/$updateApkFileName');
            if (await apkFile.exists()) {
              await apkFile.delete();
            }

            client = HttpClient();
            final req = await client.getUrl(Uri.parse(apkUrl));
            final resp = await req.close();
            if (resp.statusCode != 200) {
              throw 'HTTP ${resp.statusCode}';
            }

            final totalBytes = resp.contentLength;
            int receivedBytes = 0;
            final sink = apkFile.openWrite();

            await for (final chunk in resp) {
              sink.add(chunk);
              receivedBytes += chunk.length;
              if (totalBytes > 0 && ctx.mounted) {
                setD(() => progress = receivedBytes / totalBytes);
              }
            }
            await sink.flush();
            await sink.close();
            client.close();

            if (ctx.mounted) Navigator.pop(ctx);

            final openRes = await OpenFilex.open(
              apkFile.path,
              type: 'application/vnd.android.package-archive',
            );
            if (openRes.type != ResultType.done && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '${tr('خطا در باز کردن نصب‌کننده:', 'Installer error:')} ${openRes.message}',
                  ),
                ),
              );
            }
          } catch (e) {
            client?.close();
            if (ctx.mounted) {
              setD(() {
                downloading = false;
                errorText = '${tr('خطا در دانلود:', 'Download error:')} $e';
              });
            }
          }
        }

        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.system_update_rounded, color: Color(0xFF16A34A)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr('نسخه جدید برنامه آماده است', 'New Update Available'),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(
                  'نسخه جدید (بیلد ${toPersianDigits(remoteBuild.toString())}) منتشر شده است. با زدن دکمه زیر، فایل به‌صورت خودکار دانلود و نصب می‌شود و پس از آپدیت برای اشغال نکردن حافظه پاک خواهد شد.',
                  'A new version (Build #$remoteBuild) is available. It will download, install, and delete the installer file automatically after updating.',
                ),
              ),
              if (downloading) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: progress > 0 ? progress : null,
                ),
                const SizedBox(height: 6),
                Text(
                  progress > 0
                      ? '${tr('در حال دانلود:', 'Downloading:')} ${toPersianDigits((progress * 100).round().toString())}٪'
                      : tr('در حال اتصال به سرور...', 'Connecting...'),
                  style: const TextStyle(fontSize: 12),
                ),
              ],
              if (errorText != null) ...[
                const SizedBox(height: 10),
                Text(
                  errorText!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
            ],
          ),
          actions: [
            if (!downloading)
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr('بعداً', 'Later')),
              ),
            FilledButton.icon(
              onPressed: downloading ? null : startDownloadAndInstall,
              icon: const Icon(Icons.download_rounded),
              label: Text(
                downloading
                    ? tr('لطفاً صبر کنید...', 'Please wait...')
                    : tr('دانلود و نصب', 'Download & Install'),
              ),
            ),
          ],
        );
      },
    ),
  );
}
