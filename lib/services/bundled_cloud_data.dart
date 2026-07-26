import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:photo_namer/services/json_utils.dart';

const String bundledCloudDataAssetPath =
    'assets/cloud/photo_namer_cloud_data.json';


Future<Map<String, dynamic>?> loadBundledCloudData() async {
  try {
    final raw = await rootBundle.loadString(bundledCloudDataAssetPath);
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('内置云配置不是对象');
    }
    return stringKeyedMap(decoded);
  } catch (error) {
    debugPrint('Load bundled cloud defaults failed: $error');
    return null;
  }
}

List<Map<String, dynamic>> bundledInspectionDefaults(dynamic raw) {
  return stringKeyedMapList(raw)
      .map((item) {
        // The cloud snapshot contains device-specific photo state. Defaults start clean.
        return <String, dynamic>{
          ...item,
          'photoPaths': const <String>[],
          'isCompleted': false,
        };
      })
      .toList(growable: false);
}

