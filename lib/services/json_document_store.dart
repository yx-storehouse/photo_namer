import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 各数据集的文档名(同时也是迁移前的 SharedPreferences 键名)。
const String kDocInspectionItems = 'inspection_items';
const String kDocMeterRooms = 'meter_rooms';
const String kDocMeterOverloadTemplates = 'meter_overload_templates';
const String kDocInspectionCalendarRecords = 'inspection_calendar_records';

/// 大体量 JSON 数据集的文件存储。
///
/// SharedPreferences 在 Android 上是整文件读写,不适合存放会持续增长的
/// 数据集(房间模板、抄表数据、巡检记录等)。这里将其落到应用文档目录下
/// photo_namer_data/ 的独立 JSON 文件,并在首次访问时自动把
/// SharedPreferences 里的历史数据迁移过来(迁移后移除旧键)。
class JsonDocumentStore {
  JsonDocumentStore._();

  static final JsonDocumentStore instance = JsonDocumentStore._();

  static const String _directoryName = 'photo_namer_data';

  Directory? _directory;
  final Map<String, Future<void>> _pendingWrites = <String, Future<void>>{};

  /// 仅测试用:覆盖存储目录,绕过 path_provider 平台通道。
  @visibleForTesting
  void debugOverrideDirectory(Directory dir) {
    _directory = dir;
  }

  Future<Directory> _ensureDirectory() async {
    final existing = _directory;
    if (existing != null) {
      return existing;
    }
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(path.join(docs.path, _directoryName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _directory = dir;
    return dir;
  }

  Future<File> _fileFor(String name) async {
    final dir = await _ensureDirectory();
    return File(path.join(dir.path, '$name.json'));
  }

  /// 读取文档内容;文件不存在时尝试从 SharedPreferences 的
  /// [legacyPrefsKey] 迁移旧数据,两处都没有则返回 null。
  Future<String?> read(
    String name, {
    SharedPreferences? prefs,
    String? legacyPrefsKey,
  }) async {
    final file = await _fileFor(name);
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          return content;
        }
      } catch (_) {
        // 文件损坏按不存在处理,继续走迁移/默认值逻辑。
      }
    }

    if (prefs != null && legacyPrefsKey != null) {
      final legacy = prefs.getString(legacyPrefsKey);
      if (legacy != null && legacy.trim().isNotEmpty) {
        await write(name, legacy);
        await prefs.remove(legacyPrefsKey);
        return legacy;
      }
    }
    return null;
  }

  /// 是否已有数据(文件或尚未迁移的 SharedPreferences 旧值)。
  Future<bool> exists(
    String name, {
    SharedPreferences? prefs,
    String? legacyPrefsKey,
  }) async {
    final file = await _fileFor(name);
    if (await file.exists()) {
      return true;
    }
    if (prefs != null && legacyPrefsKey != null) {
      return prefs.containsKey(legacyPrefsKey);
    }
    return false;
  }

  /// 写入文档。同名写入串行化,先写临时文件再替换,
  /// 避免写入中途进程被杀导致整份数据损坏。
  Future<void> write(String name, String content) {
    final previous = _pendingWrites[name] ?? Future<void>.value();
    final next = previous.catchError((_) {}).then((_) async {
      final file = await _fileFor(name);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(content, flush: true);
      if (await file.exists()) {
        await file.delete();
      }
      await tmp.rename(file.path);
    });
    _pendingWrites[name] = next;
    return next;
  }
}
