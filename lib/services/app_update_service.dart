import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'package:photo_namer/services/cloud_sync_utils.dart';
import 'package:photo_namer/services/gitee_cloud_service.dart';

class LocalAppVersion {
  final String versionName;
  final int versionCode;

  const LocalAppVersion({
    required this.versionName,
    required this.versionCode,
  });

  String get label => versionName;
}

List<int> _extractComparableVersionParts(String versionName) {
  return RegExp(r'\d+')
      .allMatches(versionName)
      .map((match) => int.tryParse(match.group(0) ?? '') ?? 0)
      .toList(growable: false);
}

int _compareVersionNames(String left, String right) {
  final leftParts = _extractComparableVersionParts(left);
  final rightParts = _extractComparableVersionParts(right);

  if (leftParts.isEmpty && rightParts.isEmpty) {
    return left.trim().toLowerCase().compareTo(right.trim().toLowerCase());
  }

  final maxLength = math.max(leftParts.length, rightParts.length);
  for (var index = 0; index < maxLength; index++) {
    final leftValue = index < leftParts.length ? leftParts[index] : 0;
    final rightValue = index < rightParts.length ? rightParts[index] : 0;
    final delta = leftValue.compareTo(rightValue);
    if (delta != 0) {
      return delta;
    }
  }

  return 0;
}

class CloudAppUpdateManifest {
  final String versionName;
  final int versionCode;
  final String title;
  final String downloadUrl;
  final List<String> changelog;
  final bool forceUpdate;
  final String publishedAt;
  final String publishedBy;

  const CloudAppUpdateManifest({
    required this.versionName,
    required this.versionCode,
    required this.title,
    required this.downloadUrl,
    required this.changelog,
    required this.forceUpdate,
    required this.publishedAt,
    required this.publishedBy,
  });

  bool get hasDownloadUrl => downloadUrl.trim().isNotEmpty;
  String get label => versionName;

  bool isNewerThan(LocalAppVersion? localVersion) {
    if (localVersion == null) {
      return false;
    }

    final versionNameComparison = _compareVersionNames(
      versionName,
      localVersion.versionName,
    );
    if (versionNameComparison != 0) {
      return versionNameComparison > 0;
    }

    if (versionCode > 0 && localVersion.versionCode > 0) {
      return versionCode > localVersion.versionCode;
    }

    return false;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'appId': 'photo_namer',
      'versionName': versionName,
      'versionCode': versionCode,
      'title': title,
      'downloadUrl': downloadUrl,
      'changelog': changelog,
      'forceUpdate': forceUpdate,
      'publishedAt': publishedAt,
      'publishedBy': publishedBy,
    };
  }

  factory CloudAppUpdateManifest.fromJson(Map<String, dynamic> json) {
    final versionName = normalizedText(json['versionName']);
    final versionCodeRaw = json['versionCode'];
    final versionCode = versionCodeRaw is num
        ? versionCodeRaw.toInt()
        : int.tryParse(versionCodeRaw?.toString() ?? '') ?? 0;
    final title = normalizedText(json['title']).isEmpty
        ? '发现新版本'
        : normalizedText(json['title']);
    return CloudAppUpdateManifest(
      versionName: versionName.isEmpty ? '未命名版本' : versionName,
      versionCode: versionCode,
      title: title,
      downloadUrl: normalizedText(json['downloadUrl']),
      changelog: asStringList(json['changelog'])
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList(growable: false),
      forceUpdate: json['forceUpdate'] == true,
      publishedAt: normalizedText(json['publishedAt']),
      publishedBy: normalizedText(json['publishedBy']),
    );
  }
}

class NativeAppUpdateInstaller {
  static const MethodChannel _channel = MethodChannel('photo_namer/app_update');

  static Future<bool> canRequestPackageInstalls() async {
    if (!Platform.isAndroid) {
      return false;
    }
    final result = await _channel.invokeMethod<bool>(
      'canRequestPackageInstalls',
    );
    return result ?? false;
  }

  static Future<void> openManageUnknownAppSources() {
    return _channel.invokeMethod<void>('openManageUnknownAppSources');
  }

  static Future<void> installApk(String filePath) {
    return _channel.invokeMethod<void>('installApk', <String, dynamic>{
      'filePath': filePath,
    });
  }
}

bool hasAutoCheckedAppUpdateThisSession = false;
bool isAutoCheckingAppUpdateThisSession = false;

Future<LocalAppVersion?> readInstalledAppVersion() async {
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    final versionName = packageInfo.version.trim().isEmpty
        ? '0.0.0'
        : packageInfo.version.trim();
    final versionCode = int.tryParse(packageInfo.buildNumber.trim()) ?? 0;
    return LocalAppVersion(
      versionName: versionName,
      versionCode: versionCode,
    );
  } catch (_) {
    return null;
  }
}

Future<bool> showCloudAppUpdateDialog(
  BuildContext context,
  CloudAppUpdateManifest manifest, {
  LocalAppVersion? localVersion,
}) async {
  final localLabel = localVersion?.label ?? '未知版本';
  final remoteLabel = manifest.label;
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: !manifest.forceUpdate,
    builder: (context) => PopScope(
      canPop: !manifest.forceUpdate,
      child: AlertDialog(
        title: Text(manifest.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('当前版本：$localLabel'),
              const SizedBox(height: 4),
              Text('云端版本：$remoteLabel'),
              if (manifest.publishedAt.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('发布时间：${manifest.publishedAt.trim()}'),
              ],
              if (manifest.publishedBy.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('发布人：${manifest.publishedBy.trim()}'),
              ],
              if (manifest.forceUpdate) ...[
                const SizedBox(height: 8),
                const Chip(
                  avatar: Icon(Icons.priority_high_outlined, size: 18),
                  label: Text('重要更新，需要立即安装'),
                ),
              ],
              if (manifest.changelog.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  '更新内容',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                ...manifest.changelog.map(
                  (line) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Icon(Icons.fiber_manual_record, size: 8),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(line)),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (!manifest.forceUpdate)
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('稍后再说'),
            ),
          FilledButton.icon(
            onPressed: manifest.hasDownloadUrl
                ? () => Navigator.of(context).pop(true)
                : null,
            icon: const Icon(Icons.download_outlined),
            label: Text(manifest.forceUpdate ? '立即更新' : '下载并安装'),
          ),
        ],
      ),
    ),
  );
  return result == true;
}

Future<void> performAppUpdateDownloadAndInstall(
  BuildContext context,
  CloudAppUpdateManifest manifest, {
  void Function(String message, bool isError)? onStatus,
  void Function(double? progress)? onProgress,
}) async {
  if (!Platform.isAndroid) {
    if (!context.mounted) {
      return;
    }
    onStatus?.call('当前仅支持 Android 应用内下载并安装更新。', true);
    return;
  }

  final canInstall = await NativeAppUpdateInstaller.canRequestPackageInstalls();
  if (!canInstall) {
    if (!context.mounted) {
      return;
    }
    final openSettings = await showDialog<bool>(
      context: context,
      barrierDismissible: !manifest.forceUpdate,
      builder: (context) => PopScope(
        canPop: !manifest.forceUpdate,
        child: AlertDialog(
          title: const Text('需要安装权限'),
          content: const Text('系统还没有允许本应用安装更新包，请先打开“允许安装未知应用”后再回来继续安装。'),
          actions: [
            if (!manifest.forceUpdate)
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('去设置'),
            ),
          ],
        ),
      ),
    );
    if (openSettings == true) {
      await NativeAppUpdateInstaller.openManageUnknownAppSources();
      onStatus?.call('请开启安装权限后，重新点击更新。', false);
    } else if (manifest.forceUpdate) {
      onStatus?.call('重要更新尚未完成，请先开启安装权限。', true);
    }
    return;
  }

  http.Client? client;
  File? apkFile;
  IOSink? sink;
  try {
    onStatus?.call('正在下载更新包...', false);
    onProgress?.call(null);

    final uri = Uri.parse(manifest.downloadUrl);
    client = http.Client();
    final response = await client.send(http.Request('GET', uri));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('下载更新包失败(${response.statusCode})');
    }

    final tempDir = await getTemporaryDirectory();
    final fileName =
        'photo_namer_${manifest.versionName}_${manifest.versionCode}.apk'
            .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    apkFile = File(path.join(tempDir.path, fileName));
    if (await apkFile.exists()) {
      await apkFile.delete();
    }

    sink = apkFile.openWrite();
    final totalBytes = response.contentLength ?? 0;
    var receivedBytes = 0;
    await for (final chunk in response.stream) {
      sink.add(chunk);
      receivedBytes += chunk.length;
      if (totalBytes > 0) {
        onProgress?.call(receivedBytes / totalBytes);
      }
    }
    await sink.flush();
    await sink.close();
    sink = null;

    if (!await apkFile.exists()) {
      throw Exception('更新包保存失败');
    }

    onStatus?.call('下载完成，正在打开安装器...', false);
    await NativeAppUpdateInstaller.installApk(apkFile.path);

    if (!context.mounted) {
      return;
    }
    onStatus?.call('更新包已下载完成，系统安装器已打开。', false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('更新包已下载，正在打开安装器')));
  } catch (error) {
    if (apkFile != null && await apkFile.exists()) {
      await apkFile.delete();
    }
    if (!context.mounted) {
      return;
    }
    onStatus?.call('下载或安装更新失败: $error', true);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('下载或安装更新失败: $error')));
  } finally {
    await sink?.close();
    client?.close();
    onProgress?.call(null);
  }
}

Future<void> maybeAutoCheckCloudAppUpdateOnLaunch(BuildContext context) async {
  if (hasAutoCheckedAppUpdateThisSession ||
      isAutoCheckingAppUpdateThisSession) {
    return;
  }

  hasAutoCheckedAppUpdateThisSession = true;
  isAutoCheckingAppUpdateThisSession = true;
  try {
    final localVersion = await readInstalledAppVersion();
    final manifest = await const GiteeCloudSyncService()
        .fetchAppUpdateManifest();

    if (!context.mounted ||
        localVersion == null ||
        manifest == null ||
        !manifest.isNewerThan(localVersion) ||
        !manifest.hasDownloadUrl) {
      return;
    }

    if (!manifest.forceUpdate) {
      return;
    }

    final shouldDownload = await showCloudAppUpdateDialog(
      context,
      manifest,
      localVersion: localVersion,
    );
    if (!shouldDownload || !context.mounted) {
      return;
    }

    await performAppUpdateDownloadAndInstall(context, manifest);
  } catch (error) {
    debugPrint('Auto app update check failed: $error');
  } finally {
    isAutoCheckingAppUpdateThisSession = false;
  }
}
