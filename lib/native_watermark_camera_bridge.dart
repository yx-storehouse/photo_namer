import 'dart:convert';

import 'package:flutter/services.dart';

class NativeWatermarkCameraBridge {
  static const MethodChannel _channel = MethodChannel(
    'photo_namer/native_watermark_camera',
  );

  static Future<List<Map<String, dynamic>>?> launchWatermark118Camera({
    required String title,
    required int captureCount,
    required String roomCode,
    required String location,
    required String weatherText,
    required String imprintText,
  }) async {
    final jsonString = await _channel
        .invokeMethod<String>('launchWatermark118Camera', <String, dynamic>{
          'title': title,
          'captureCount': captureCount,
          'roomCode': roomCode,
          'location': location,
          'weatherText': weatherText,
          'imprintText': imprintText,
        });

    if (jsonString == null || jsonString.isEmpty) {
      return null;
    }

    final decoded = jsonDecode(jsonString);
    if (decoded is! List) {
      return null;
    }

    return decoded
        .map((dynamic item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  static Future<Map<String, dynamic>> composeWatermark118Batch({
    required List<Map<String, dynamic>> entries,
  }) async {
    final dynamic rawResult = await _channel.invokeMethod<dynamic>(
      'composeWatermark118Batch',
      <String, dynamic>{'entries': entries},
    );
    if (rawResult is Map) {
      return Map<String, dynamic>.from(rawResult);
    }
    throw StateError('原生批量合成返回无效结果');
  }
}
