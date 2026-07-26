import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const String _nativeCameraPreviewViewType = 'photo_namer/native_camera_preview';

class NativeWatermarkPreviewState {
  const NativeWatermarkPreviewState({
    required this.watermarkEnabled,
    required this.location,
    required this.weatherText,
    required this.roomCode,
    required this.imprintText,
    required this.timeOverrideText,
    required this.dateOverrideText,
    required this.antiFakeCode,
    required this.antiFakeCodeLocked,
    required this.defaults,
    required this.adjustments,
  });

  final bool watermarkEnabled;
  final String location;
  final String weatherText;
  final String roomCode;
  final String imprintText;
  final String? timeOverrideText;
  final String? dateOverrideText;
  final String antiFakeCode;
  final bool antiFakeCodeLocked;
  final Map<String, String?> defaults;
  final Map<String, double> adjustments;

  factory NativeWatermarkPreviewState.fromMap(Map<String, dynamic> map) {
    final rawDefaults = (map['defaults'] as Map?)?.cast<Object?, Object?>();
    final rawAdjustments = (map['adjustments'] as Map?)
        ?.cast<Object?, Object?>();
    return NativeWatermarkPreviewState(
      watermarkEnabled: (map['watermarkEnabled'] as bool?) ?? true,
      location: (map['location'] as String?) ?? '',
      weatherText: (map['weatherText'] as String?) ?? '',
      roomCode: (map['roomCode'] as String?) ?? '',
      imprintText: (map['imprintText'] as String?) ?? '',
      timeOverrideText:
          (map['timeOverrideText'] as String?)?.trim().isEmpty ?? true
          ? null
          : (map['timeOverrideText'] as String?)?.trim(),
      dateOverrideText:
          (map['dateOverrideText'] as String?)?.trim().isEmpty ?? true
          ? null
          : (map['dateOverrideText'] as String?)?.trim(),
      antiFakeCode: (map['antiFakeCode'] as String?) ?? '',
      antiFakeCodeLocked: (map['antiFakeCodeLocked'] as bool?) ?? false,
      defaults: <String, String?>{
        if (rawDefaults != null)
          for (final entry in rawDefaults.entries)
            entry.key.toString(): entry.value?.toString(),
      },
      adjustments: <String, double>{
        if (rawAdjustments != null)
          for (final entry in rawAdjustments.entries)
            entry.key.toString(): (entry.value as num?)?.toDouble() ?? 0,
      },
    );
  }

  String? defaultValue(String key) => defaults[key];

  double adjustment(String key, [double fallback = 0]) {
    return adjustments[key] ?? fallback;
  }
}

class NativeWatermarkCameraPreviewController {
  NativeWatermarkCameraPreviewController._({
    required MethodChannel channel,
    this.onCameraReady,
    this.onCameraError,
  }) : _channel = channel {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  final MethodChannel _channel;
  final VoidCallback? onCameraReady;
  final ValueChanged<String>? onCameraError;

  Future<Map<String, dynamic>> capture() async {
    final dynamic rawResult = await _channel.invokeMethod<dynamic>('capture');
    if (rawResult is Map) {
      return Map<String, dynamic>.from(rawResult);
    }
    throw StateError('原生相机没有返回有效结果');
  }

  Future<NativeWatermarkPreviewState> getWatermarkState() async {
    final dynamic rawResult = await _channel.invokeMethod<dynamic>(
      'getWatermarkState',
    );
    if (rawResult is Map) {
      return NativeWatermarkPreviewState.fromMap(
        Map<String, dynamic>.from(rawResult),
      );
    }
    throw StateError('原生水印状态返回无效');
  }

  Future<NativeWatermarkPreviewState> updateWatermarkState(
    Map<String, dynamic> changes,
  ) async {
    final dynamic rawResult = await _channel.invokeMethod<dynamic>(
      'updateWatermarkState',
      changes,
    );
    if (rawResult is Map) {
      return NativeWatermarkPreviewState.fromMap(
        Map<String, dynamic>.from(rawResult),
      );
    }
    throw StateError('原生水印状态更新失败');
  }

  Future<void> shutdownCamera() async {
    await _channel.invokeMethod<void>('shutdownCamera');
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'cameraReady':
        onCameraReady?.call();
        return;
      case 'cameraError':
        final args = call.arguments;
        if (args is Map) {
          final message = (args['message'] as String?)?.trim();
          onCameraError?.call(
            message?.isNotEmpty == true ? message! : '相机初始化失败',
          );
          return;
        }
        onCameraError?.call('相机初始化失败');
        return;
      default:
        return;
    }
  }
}

class NativeWatermarkCameraPreview extends StatefulWidget {
  const NativeWatermarkCameraPreview({
    super.key,
    required this.title,
    required this.roomCode,
    required this.location,
    required this.weatherText,
    required this.imprintText,
    required this.watermarkEnabled,
    required this.onCreated,
    this.onCameraReady,
    this.onCameraError,
  });

  final String title;
  final String roomCode;
  final String location;
  final String weatherText;
  final String imprintText;
  final bool watermarkEnabled;
  final ValueChanged<NativeWatermarkCameraPreviewController> onCreated;
  final VoidCallback? onCameraReady;
  final ValueChanged<String>? onCameraError;

  @override
  State<NativeWatermarkCameraPreview> createState() =>
      _NativeWatermarkCameraPreviewState();
}

class _NativeWatermarkCameraPreviewState
    extends State<NativeWatermarkCameraPreview> {
  NativeWatermarkCameraPreviewController? _controller;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const SizedBox.shrink();
    }

    return AndroidView(
      viewType: _nativeCameraPreviewViewType,
      creationParams: <String, dynamic>{
        'title': widget.title,
        'roomCode': widget.roomCode,
        'location': widget.location,
        'weatherText': widget.weatherText,
        'imprintText': widget.imprintText,
        'watermarkEnabled': widget.watermarkEnabled,
      },
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: _handlePlatformViewCreated,
    );
  }

  void _handlePlatformViewCreated(int viewId) {
    final previousController = _controller;
    final controller = NativeWatermarkCameraPreviewController._(
      channel: MethodChannel('photo_namer/native_camera_preview_$viewId'),
      onCameraReady: widget.onCameraReady,
      onCameraError: widget.onCameraError,
    );
    _controller = controller;
    previousController?.dispose();
    widget.onCreated(controller);
  }
}
