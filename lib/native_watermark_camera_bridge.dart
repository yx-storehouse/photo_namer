import 'package:flutter/services.dart';

class NativeWatermarkCameraBridge {
  static const MethodChannel _channel = MethodChannel(
    'photo_namer/native_watermark_camera',
  );

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
