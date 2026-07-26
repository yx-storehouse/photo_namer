import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import 'package:photo_namer/models/cloud_sync_models.dart';
import 'package:photo_namer/services/app_update_service.dart';

class GiteeCloudFile {
  final String path;
  final String content;
  final String sha;

  const GiteeCloudFile({
    required this.path,
    required this.content,
    required this.sha,
  });
}

class GiteeCloudSyncConfig {
  static const String accessToken = '9f43664de2ca43df41b8c78b1ea88019';
  static const String repoOwner = 'yxnbkls';
  static const String repoName = 'storge';
  static const String branch = 'master';
  static const String configFilePath =
      'photo_namer/photo_namer_cloud_config.json';
  static const String dataFilePath = 'photo_namer/photo_namer_cloud_data.json';
  static const String appUpdateFilePath =
      'photo_namer/photo_namer_app_update.json';
  static const String guestSubmissionDirectoryPath =
      'photo_namer/guest_updates';

  static const String adminUser = 'admin';
  static const String adminPassword = '918891474';
}

class GiteeCloudSyncService {
  const GiteeCloudSyncService();

  Uri _contentsUri(String? targetPath, {bool avoidCache = false}) {
    final queryParameters = <String, String>{
      'access_token': GiteeCloudSyncConfig.accessToken,
      'ref': GiteeCloudSyncConfig.branch,
    };
    if (avoidCache) {
      queryParameters['t'] = DateTime.now().millisecondsSinceEpoch.toString();
    }
    final normalizedPath = targetPath?.trim() ?? '';
    final requestPath = normalizedPath.isEmpty
        ? '/api/v5/repos/${GiteeCloudSyncConfig.repoOwner}/${GiteeCloudSyncConfig.repoName}/contents'
        : '/api/v5/repos/${GiteeCloudSyncConfig.repoOwner}/${GiteeCloudSyncConfig.repoName}/contents/$normalizedPath';
    return Uri.https('gitee.com', requestPath, queryParameters);
  }

  Uri _blobUri(String sha) {
    return Uri.https(
      'gitee.com',
      '/api/v5/repos/${GiteeCloudSyncConfig.repoOwner}/${GiteeCloudSyncConfig.repoName}/git/blobs/$sha',
      <String, String>{'access_token': GiteeCloudSyncConfig.accessToken},
    );
  }

  String _decodeBase64Content(String rawContent) {
    final normalized = rawContent.replaceAll('\n', '').trim();
    return utf8.decode(base64Decode(normalized));
  }

  Future<List<Map<String, dynamic>>> _fetchDirectoryEntries(
    String dirPath, {
    bool avoidCache = false,
  }) async {
    final response = await http.get(
      _contentsUri(dirPath.isEmpty ? null : dirPath, avoidCache: avoidCache),
      headers: const <String, String>{'Cache-Control': 'no-cache'},
    );
    if (response.statusCode == 404) {
      return const <Map<String, dynamic>>[];
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('读取云端目录失败(${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map(
            (entry) => Map<String, dynamic>.from(
              entry.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .toList();
    }
    if (decoded is Map<String, dynamic>) {
      return <Map<String, dynamic>>[decoded];
    }
    throw const FormatException('云端目录响应格式不正确');
  }

  Future<String> _fetchBlobContentBySha(String sha) async {
    final response = await http.get(
      _blobUri(sha),
      headers: const <String, String>{'Cache-Control': 'no-cache'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('读取云端 blob 失败(${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('云端 blob 响应格式不正确');
    }
    return _decodeBase64Content((decoded['content'] ?? '').toString());
  }

  Future<GiteeCloudFile?> fetchFile(
    String filePath, {
    bool avoidCache = false,
  }) async {
    final normalizedPath = filePath.trim();
    if (normalizedPath.isEmpty) {
      return null;
    }

    final parentDir = path.posix.dirname(normalizedPath);
    final dirPath = parentDir == '.' ? '' : parentDir;
    final fileName = path.posix.basename(normalizedPath);
    final entries = await _fetchDirectoryEntries(
      dirPath,
      avoidCache: avoidCache,
    );

    Map<String, dynamic>? matched;
    for (final entry in entries) {
      final entryPath = (entry['path'] ?? '').toString();
      final entryName = (entry['name'] ?? '').toString();
      if (entryPath == normalizedPath || entryName == fileName) {
        matched = entry;
        break;
      }
    }
    if (matched == null) {
      return null;
    }

    final sha = (matched['sha'] ?? '').toString();
    if (sha.isEmpty) {
      throw const FormatException('云端文件缺少 sha 信息');
    }

    return GiteeCloudFile(
      path: (matched['path'] ?? normalizedPath).toString(),
      content: await _fetchBlobContentBySha(sha),
      sha: sha,
    );
  }

  Future<void> upsertFile({
    required String filePath,
    required String content,
    required String message,
  }) async {
    final existing = await fetchFile(filePath, avoidCache: true);
    final body = <String, String>{
      'access_token': GiteeCloudSyncConfig.accessToken,
      'content': base64Encode(utf8.encode(content)),
      'message': message,
      'branch': GiteeCloudSyncConfig.branch,
    };

    late final http.Response response;
    if (existing == null) {
      response = await http.post(
        _contentsUri(filePath),
        headers: const <String, String>{
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: body,
      );
    } else {
      body['sha'] = existing.sha;
      response = await http.put(
        _contentsUri(filePath),
        headers: const <String, String>{
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: body,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('写入云端文件失败(${response.statusCode}): ${response.body}');
    }
  }

  Future<Map<String, dynamic>?> fetchManifest() async {
    final file = await fetchFile(
      GiteeCloudSyncConfig.configFilePath,
      avoidCache: true,
    );
    if (file == null) {
      return null;
    }
    final decoded = jsonDecode(file.content);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('云端配置文件格式不正确');
    }
    return decoded;
  }

  Future<CloudAppUpdateManifest?> fetchAppUpdateManifest() async {
    final file = await fetchFile(
      GiteeCloudSyncConfig.appUpdateFilePath,
      avoidCache: true,
    );
    if (file == null) {
      return null;
    }
    final decoded = jsonDecode(file.content);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('云端版本文件格式不正确');
    }
    return CloudAppUpdateManifest.fromJson(decoded);
  }

  Future<void> publishBundle(
    Map<String, dynamic> bundle, {
    required String operatorName,
  }) async {
    final now = DateTime.now().toIso8601String();
    final dataPayload = <String, dynamic>{
      ...bundle,
      'publishedAt': now,
      'publishedBy': operatorName,
    };

    await upsertFile(
      filePath: GiteeCloudSyncConfig.dataFilePath,
      content: const JsonEncoder.withIndent('  ').convert(dataPayload),
      message: 'photo_namer publish data $now',
    );

    final inspectionItems = bundle['inspectionItems'];
    final meterRooms = bundle['meterRooms'];
    final overloadTemplates = bundle['overloadTemplates'];

    final manifest = <String, dynamic>{
      'appId': 'photo_namer',
      'appName': 'photo_namer',
      'schemaVersion': 1,
      'updatedAt': now,
      'updatedBy': operatorName,
      'repository': <String, dynamic>{
        'owner': GiteeCloudSyncConfig.repoOwner,
        'name': GiteeCloudSyncConfig.repoName,
        'branch': GiteeCloudSyncConfig.branch,
      },
      'configFilePath': GiteeCloudSyncConfig.configFilePath,
      'dataFilePath': GiteeCloudSyncConfig.dataFilePath,
      'categories': const <Map<String, String>>[
        <String, String>{'id': 'inspectionItems', 'name': '房间模板'},
        <String, String>{'id': 'meterRooms', 'name': '动力抄表模板'},
        <String, String>{'id': 'overloadTemplates', 'name': '动力超标模板'},
        <String, String>{'id': 'appPreferences', 'name': '应用参数模板'},
        <String, String>{'id': 'watermarkTemplate', 'name': '水印参数模板'},
      ],
      'summary': <String, dynamic>{
        'inspectionItemCount': inspectionItems is List
            ? inspectionItems.length
            : 0,
        'meterRoomCount': meterRooms is List ? meterRooms.length : 0,
        'overloadTemplateCount': overloadTemplates is List
            ? overloadTemplates.length
            : 0,
      },
    };

    await upsertFile(
      filePath: GiteeCloudSyncConfig.configFilePath,
      content: const JsonEncoder.withIndent('  ').convert(manifest),
      message: 'photo_namer publish manifest $now',
    );
  }

  Future<CloudAppUpdateManifest> publishAppUpdateManifest(
    CloudAppUpdateManifest manifest, {
    required String operatorName,
  }) async {
    final now = DateTime.now().toIso8601String();
    final publishedManifest = CloudAppUpdateManifest(
      versionName: manifest.versionName,
      versionCode: manifest.versionCode,
      title: manifest.title,
      downloadUrl: manifest.downloadUrl,
      changelog: manifest.changelog,
      forceUpdate: manifest.forceUpdate,
      publishedAt: now,
      publishedBy: operatorName,
    );
    await upsertFile(
      filePath: GiteeCloudSyncConfig.appUpdateFilePath,
      content: const JsonEncoder.withIndent(
        '  ',
      ).convert(publishedManifest.toJson()),
      message: 'photo_namer publish app update $now',
    );
    return publishedManifest;
  }

  Future<List<CloudGuestSubmission>> fetchGuestSubmissions() async {
    final entries = await _fetchDirectoryEntries(
      GiteeCloudSyncConfig.guestSubmissionDirectoryPath,
      avoidCache: true,
    );
    final fileEntries = entries
        .where((entry) {
          final type = (entry['type'] ?? '').toString();
          final name = (entry['name'] ?? '').toString().toLowerCase();
          return type == 'file' && name.endsWith('.json');
        })
        .toList(growable: false);

    final submissions = await Future.wait(
      fileEntries.map((entry) async {
        final sha = (entry['sha'] ?? '').toString();
        if (sha.isEmpty) {
          return null;
        }
        final content = await _fetchBlobContentBySha(sha);
        final decoded = jsonDecode(content);
        if (decoded is! Map) {
          return null;
        }
        return CloudGuestSubmission.fromJson(
          Map<String, dynamic>.from(
            decoded.map((key, value) => MapEntry(key.toString(), value)),
          ),
          filePath: (entry['path'] ?? '').toString(),
        );
      }),
    );

    return submissions.whereType<CloudGuestSubmission>().toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<CloudGuestSubmission> submitGuestSubmission({
    required Map<String, dynamic> reviewBundle,
    required String submittedBy,
    required String note,
    required CloudReviewDiff diff,
    required String baseCloudUpdatedAt,
  }) async {
    final createdAt = DateTime.now().toIso8601String();
    final id = 'guest_${DateTime.now().millisecondsSinceEpoch}';
    final filePath =
        '${GiteeCloudSyncConfig.guestSubmissionDirectoryPath}/$id.json';
    final submission = CloudGuestSubmission(
      id: id,
      filePath: filePath,
      createdAt: createdAt,
      submittedBy: submittedBy,
      note: note,
      status: guestSubmissionStatusPending,
      baseCloudUpdatedAt: baseCloudUpdatedAt,
      reviewedAt: null,
      reviewedBy: null,
      reviewBundle: reviewBundle,
      submittedDiff: diff,
      reviewDiff: diff,
    );
    await upsertFile(
      filePath: filePath,
      content: const JsonEncoder.withIndent('  ').convert(submission.toJson()),
      message: 'photo_namer guest submission $createdAt',
    );
    return submission;
  }

  Future<void> saveGuestSubmission(CloudGuestSubmission submission) async {
    await upsertFile(
      filePath: submission.filePath,
      content: const JsonEncoder.withIndent('  ').convert(submission.toJson()),
      message:
          'photo_namer guest submission status ${submission.status} ${DateTime.now().toIso8601String()}',
    );
  }

  Future<Map<String, dynamic>> downloadBundle({
    Map<String, dynamic>? manifest,
  }) async {
    final resolvedManifest = manifest ?? await fetchManifest();
    final dataFilePath =
        (resolvedManifest?['dataFilePath'] ??
                GiteeCloudSyncConfig.dataFilePath)
            .toString();
    final file = await fetchFile(dataFilePath, avoidCache: true);
    if (file == null) {
      throw const FormatException('云端还没有可用的 photo_namer 配置数据');
    }
    final decoded = jsonDecode(file.content);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('云端数据文件格式不正确');
    }
    return decoded;
  }
}

