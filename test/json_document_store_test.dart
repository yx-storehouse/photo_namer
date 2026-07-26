import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_namer/services/json_document_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late JsonDocumentStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('json_doc_store_');
    store = JsonDocumentStore.instance;
    store.debugOverrideDirectory(tempDir);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('写入后可读取,exists 返回true', () async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();

    await store.write('demo', '{"a":1}');
    expect(await store.read('demo'), '{"a":1}');
    expect(
      await store.exists('demo', prefs: prefs, legacyPrefsKey: 'demo'),
      isTrue,
    );
  });

  test('文件缺失时从 SharedPreferences 迁移并移除旧键', () async {
    SharedPreferences.setMockInitialValues({'legacy_key': '{"rooms":[]}'});
    final prefs = await SharedPreferences.getInstance();

    final content = await store.read(
      'migrated_doc',
      prefs: prefs,
      legacyPrefsKey: 'legacy_key',
    );

    expect(content, '{"rooms":[]}');
    expect(prefs.containsKey('legacy_key'), isFalse);
    // 再次读取直接命中文件
    expect(await store.read('migrated_doc'), '{"rooms":[]}');
    final file = File('${tempDir.path}/migrated_doc.json');
    expect(await file.exists(), isTrue);
  });

  test('两处都没有数据时返回null,exists 返回false', () async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();

    expect(
      await store.read('missing', prefs: prefs, legacyPrefsKey: 'missing'),
      isNull,
    );
    expect(
      await store.exists('missing', prefs: prefs, legacyPrefsKey: 'missing'),
      isFalse,
    );
  });

  test('连续写入串行化,最后一次内容生效', () async {
    await Future.wait([
      store.write('serial', 'v1'),
      store.write('serial', 'v2'),
      store.write('serial', 'v3'),
    ]);
    expect(await store.read('serial'), 'v3');
  });
}
