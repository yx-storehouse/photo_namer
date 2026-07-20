import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:photo_namer/capture_location_service.dart';
import 'package:photo_namer/capture_weather_service.dart';
import 'package:photo_namer/models/camera_capture_result.dart';
import 'package:photo_namer/models/meter_models.dart';
import 'package:photo_namer/native_watermark_camera_panel.dart';
import 'package:photo_namer/native_watermark_camera_preview.dart';
import 'package:photo_namer/watermark_capture_overlay.dart';
import 'package:photo_namer/watermark_template_118.dart';

class CameraPage extends StatefulWidget {
  final CameraDescription camera;
  final String title;
  final int captureCount;
  final bool allowContinuousCapture;
  final String roomCode;
  final String initialWatermarkLocation;
  final String weatherText;
  final String imprintText;
  final bool enableCameraAttachDelay;
  final int cameraAttachDelayMs;
  final bool initialWatermarkEnabled;
  final Future<void> Function(bool value)? onWatermarkPreferenceChanged;
  final Future<void> Function(CameraCaptureResult capture, int captureIndex)?
  onCaptureProcessed;
  const CameraPage({
    super.key,
    required this.camera,
    required this.title,
    required this.captureCount,
    this.allowContinuousCapture = false,
    required this.roomCode,
    required this.initialWatermarkLocation,
    required this.weatherText,
    required this.imprintText,
    required this.enableCameraAttachDelay,
    required this.cameraAttachDelayMs,
    required this.initialWatermarkEnabled,
    this.onWatermarkPreferenceChanged,
    this.onCaptureProcessed,
  });
  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  static const Duration _finalCaptureReturnDelay = Duration(milliseconds: 140);
  static const String _defaultWatermarkEnabledPreferenceKey =
      'default_watermark_enabled';
  static const String _cachedCaptureWeatherTextPreferenceKey =
      'cached_capture_weather_text';
  static const String _lastWeatherRefreshSlotPreferenceKey =
      'last_weather_refresh_slot';
  static const String _continuousCaptureRoomCodePlaceholder = '点击填写备注';

  CameraController? _controller;
  NativeWatermarkCameraPreviewController? _nativePreviewController;
  NativeWatermarkPreviewState? _nativeWatermarkState;
  Animation<double>? _routeAnimation;
  int _cameraStartScheduleToken = 0;
  bool _isReady = false;
  bool _isRefreshingNativeAddress = false;
  bool _isRefreshingNativeWeather = false;
  bool _cameraSessionStarted = false;
  bool _attachNativePreview = false;
  bool _pendingCloseAfterEnter = false;
  bool _isClosing = false;
  bool _allowSystemPop = false;
  bool _isCapturing = false;
  late bool _watermarkEnabled;
  late String _currentRoomCode;
  late String _currentLocation;
  int _captured = 0;
  final List<CameraCaptureResult> _photos = [];
  Timer? _previewTicker;
  Timer? _weatherSlotRefreshTicker;
  Watermark118Data? _previewData;
  late String _currentWeatherText;
  String _currentWeatherSlotKey = '';
  bool _isAutoRefreshingWeatherSlot = false;

  bool get _useNativePreview => Platform.isAndroid;

  Duration get _cameraAttachDelay {
    if (!widget.enableCameraAttachDelay || widget.cameraAttachDelayMs <= 0) {
      return Duration.zero;
    }
    return Duration(milliseconds: widget.cameraAttachDelayMs);
  }

  @override
  void initState() {
    super.initState();
    _watermarkEnabled = widget.initialWatermarkEnabled;
    _currentRoomCode = widget.roomCode.trim();
    _currentLocation = widget.initialWatermarkLocation.trim();
    _currentWeatherText = widget.weatherText.trim().isNotEmpty
        ? widget.weatherText.trim()
        : WatermarkTemplate118Composer.defaultWeatherText;
    if (_watermarkEnabled) {
      _previewData = _buildPreviewData(captureTime: DateTime.now());
    }
    _startWeatherSlotRefreshTicker();
    unawaited(_syncWeatherForCurrentSlot());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final routeAnimation = ModalRoute.of(context)?.animation;
    if (_routeAnimation == routeAnimation) {
      return;
    }
    _routeAnimation?.removeStatusListener(_handleRouteAnimationStatusChanged);
    _routeAnimation = routeAnimation;
    _routeAnimation?.addStatusListener(_handleRouteAnimationStatusChanged);

    if (routeAnimation == null ||
        routeAnimation.status == AnimationStatus.completed) {
      _scheduleCameraStartAfterEnter();
    }
  }

  Future<void> _initCamera() async {
    final controller = CameraController(
      widget.camera,
      ResolutionPreset.high,
      enableAudio: false,
    );
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted || _isClosing || _controller != controller) {
        await controller.dispose();
        return;
      }
      setState(() => _isReady = true);
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_handleRouteAnimationStatusChanged);
    _previewTicker?.cancel();
    _weatherSlotRefreshTicker?.cancel();
    _nativePreviewController?.dispose();
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      unawaited(controller.dispose());
    }
    super.dispose();
  }

  void _handleRouteAnimationStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) {
      return;
    }
    if (_pendingCloseAfterEnter) {
      _pendingCloseAfterEnter = false;
      unawaited(_handleCloseRequested());
      return;
    }
    _scheduleCameraStartAfterEnter();
  }

  void _scheduleCameraStartAfterEnter() {
    final int scheduleToken = ++_cameraStartScheduleToken;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_startCameraSessionAfterDelay(scheduleToken));
    });
  }

  Future<void> _startCameraSessionAfterDelay(int scheduleToken) async {
    final delay = _cameraAttachDelay;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (!mounted ||
        _isClosing ||
        _pendingCloseAfterEnter ||
        scheduleToken != _cameraStartScheduleToken) {
      return;
    }
    _startCameraSessionIfNeeded();
  }

  void _startPreviewClockIfNeeded() {
    if (_useNativePreview || !_watermarkEnabled || _previewTicker != null) {
      return;
    }
    _previewData = _buildPreviewData();
    _previewTicker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _refreshPreviewClock(),
    );
  }

  void _stopPreviewClock() {
    _previewTicker?.cancel();
    _previewTicker = null;
  }

  String _resolvedCurrentWeatherText() {
    final value = _currentWeatherText.trim();
    if (value.isNotEmpty) {
      return value;
    }
    return WatermarkTemplate118Composer.defaultWeatherText;
  }

  String _resolvedWeatherFallbackAddress() {
    final nativeLocation = _nativeWatermarkState?.location.trim() ?? '';
    if (nativeLocation.isNotEmpty) {
      return nativeLocation;
    }
    final previewLocation = _previewData?.location.trim() ?? '';
    if (previewLocation.isNotEmpty) {
      return previewLocation;
    }
    return widget.initialWatermarkLocation;
  }

  String _resolvedCurrentRoomCode() {
    final value = _currentRoomCode.trim();
    if (value.isNotEmpty) {
      return value;
    }
    return widget.roomCode;
  }

  String _resolvedCurrentLocation() {
    final value = _currentLocation.trim();
    if (value.isNotEmpty) {
      return value;
    }
    return widget.initialWatermarkLocation;
  }

  bool _isPreviewPlaceholderRoomCode(String value) {
    return widget.allowContinuousCapture &&
        value.trim() == _continuousCaptureRoomCodePlaceholder;
  }

  String _roomCodeForPreview() {
    final value = _resolvedCurrentRoomCode().trim();
    if (value.isNotEmpty) {
      return value;
    }
    if (widget.allowContinuousCapture) {
      return _continuousCaptureRoomCodePlaceholder;
    }
    return widget.roomCode;
  }

  void _startWeatherSlotRefreshTicker() {
    _weatherSlotRefreshTicker?.cancel();
    _weatherSlotRefreshTicker = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_syncWeatherForCurrentSlot()),
    );
  }

  Future<void> _persistWeatherRefreshCache(
    String weatherText,
    String slotKey,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cachedCaptureWeatherTextPreferenceKey, weatherText);
    await prefs.setString(_lastWeatherRefreshSlotPreferenceKey, slotKey);
  }

  Future<String?> _resolveLatestWeatherText({
    required bool requestPermission,
    bool showNoLocationMessage = false,
  }) async {
    if (requestPermission) {
      if (!await _ensureNativeLocationPermission('天气')) {
        return null;
      }
    } else {
      final status = await Permission.location.status;
      if (!status.isGranted) {
        return null;
      }
    }

    final fallbackWeatherText = _resolvedCurrentWeatherText();
    final snapshot = await CaptureLocationService.resolveSnapshot(
      fallbackAddress: _resolvedWeatherFallbackAddress(),
    );
    if (snapshot.position == null) {
      if (showNoLocationMessage && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('未获取到定位，天气保持不变')));
      }
      return null;
    }

    final weatherText = await CaptureWeatherService.resolveCurrentWeather(
      fallbackWeatherText: fallbackWeatherText,
      position: snapshot.position,
    );
    return weatherText.trim().isNotEmpty
        ? weatherText.trim()
        : fallbackWeatherText;
  }

  Future<void> _applyWeatherText(
    String weatherText, {
    bool silent = true,
  }) async {
    final normalized = weatherText.trim().isNotEmpty
        ? weatherText.trim()
        : _resolvedCurrentWeatherText();
    final currentPreview = _previewData;
    final shouldRebuildPreview = currentPreview != null || !_useNativePreview;

    if (mounted) {
      setState(() {
        _currentWeatherText = normalized;
        if (shouldRebuildPreview) {
          _previewData = _buildPreviewData(
            captureTime: currentPreview?.captureTime ?? DateTime.now(),
            antiFakeCode: currentPreview?.antiFakeCode,
            location: currentPreview?.location,
            weatherText: normalized,
          );
        }
      });
    } else {
      _currentWeatherText = normalized;
      if (shouldRebuildPreview) {
        _previewData = _buildPreviewData(
          captureTime: currentPreview?.captureTime ?? DateTime.now(),
          antiFakeCode: currentPreview?.antiFakeCode,
          location: currentPreview?.location,
          weatherText: normalized,
        );
      }
    }

    final nativeState = _nativeWatermarkState;
    if (_useNativePreview &&
        nativeState != null &&
        nativeState.weatherText != normalized) {
      await _updateNativeWatermarkState(<String, dynamic>{
        'weatherText': normalized,
      }, silent: silent);
    }
  }

  Future<void> _syncWeatherForCurrentSlot({bool force = false}) async {
    if (_isClosing ||
        _isAutoRefreshingWeatherSlot ||
        _isRefreshingNativeWeather) {
      return;
    }

    final slotKey = captureWeatherRefreshSlotKey(DateTime.now());
    if (slotKey.isEmpty) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final cachedWeatherText =
        (prefs.getString(_cachedCaptureWeatherTextPreferenceKey) ?? '').trim();
    final cachedSlotKey =
        (prefs.getString(_lastWeatherRefreshSlotPreferenceKey) ?? '').trim();

    if (!force && cachedSlotKey == slotKey) {
      _currentWeatherSlotKey = slotKey;
      if (cachedWeatherText.isNotEmpty) {
        await _applyWeatherText(cachedWeatherText);
      }
      return;
    }

    if (!force && _currentWeatherSlotKey == slotKey) {
      return;
    }

    _isAutoRefreshingWeatherSlot = true;
    try {
      final weatherText = await _resolveLatestWeatherText(
        requestPermission: false,
      );
      if (weatherText == null) {
        return;
      }
      await _persistWeatherRefreshCache(weatherText, slotKey);
      _currentWeatherSlotKey = slotKey;
      await _applyWeatherText(weatherText);
    } catch (error) {
      debugPrint('camera slot weather refresh skipped: $error');
    } finally {
      _isAutoRefreshingWeatherSlot = false;
    }
  }

  void _startCameraSessionIfNeeded() {
    if (_cameraSessionStarted || _isClosing || _pendingCloseAfterEnter) {
      return;
    }
    _cameraSessionStarted = true;
    if (_useNativePreview) {
      setState(() {
        _attachNativePreview = true;
      });
      return;
    }
    if (_watermarkEnabled) {
      _startPreviewClockIfNeeded();
    }
    unawaited(_initCamera());
  }

  bool _routeIsStillEntering() {
    final routeAnimation = _routeAnimation;
    if (routeAnimation == null) {
      return false;
    }
    return routeAnimation.status != AnimationStatus.completed;
  }

  Future<void> _shutdownCameraSession() async {
    _stopPreviewClock();

    final nativeController = _nativePreviewController;
    _nativePreviewController = null;
    if (nativeController != null) {
      try {
        await nativeController.shutdownCamera().timeout(
          const Duration(milliseconds: 500),
        );
      } catch (error) {
        debugPrint('Native camera shutdown error: $error');
      } finally {
        nativeController.dispose();
      }
    }

    final controller = _controller;
    _controller = null;
    if (controller != null) {
      try {
        await controller.dispose();
      } catch (error) {
        debugPrint('Camera dispose error: $error');
      }
    }
  }

  Future<void> _beginCameraShutdown() async {
    if (!mounted || _allowSystemPop || _isClosing) {
      return;
    }

    setState(() {
      _cameraStartScheduleToken++;
      _isClosing = true;
      _isReady = false;
      _attachNativePreview = false;
      _cameraSessionStarted = false;
    });
    await _shutdownCameraSession();
  }

  void _completePop([List<CameraCaptureResult>? result]) {
    if (!mounted || _allowSystemPop) {
      return;
    }

    final navigator = Navigator.of(context);
    setState(() {
      _allowSystemPop = true;
    });
    navigator.pop(result);
  }

  Future<void> _closeCameraAndPop([List<CameraCaptureResult>? result]) async {
    await _beginCameraShutdown();
    if (!mounted) {
      return;
    }
    _completePop(result);
  }

  Future<void> _handleCloseRequested() async {
    if (!mounted || _allowSystemPop || _isClosing) {
      return;
    }
    if (_isCapturing) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('正在拍照，请稍候')));
      return;
    }
    if (_routeIsStillEntering()) {
      _pendingCloseAfterEnter = true;
      return;
    }

    final result = widget.allowContinuousCapture && _photos.isNotEmpty
        ? List<CameraCaptureResult>.from(_photos)
        : null;
    await _closeCameraAndPop(result);
  }

  Watermark118Data _buildCurrentWatermarkInteractionData() {
    final previewData = _previewData;
    final nativeState = _nativeWatermarkState;
    final adjustments = nativeState == null
        ? previewData?.adjustments ?? const Watermark118Adjustments()
        : Watermark118Adjustments.fromMap(
            Map<String, dynamic>.from(nativeState.adjustments),
          );
    return Watermark118Data(
      location: nativeState?.location.trim().isNotEmpty == true
          ? nativeState!.location
          : previewData?.location ?? _resolvedCurrentLocation(),
      roomCode:
          nativeState?.roomCode.trim().isNotEmpty == true &&
              !_isPreviewPlaceholderRoomCode(nativeState!.roomCode)
          ? nativeState.roomCode
          : _roomCodeForPreview(),
      weatherText: nativeState?.weatherText.trim().isNotEmpty == true
          ? nativeState!.weatherText
          : previewData?.weatherText ?? _resolvedCurrentWeatherText(),
      captureTime: previewData?.captureTime ?? DateTime.now(),
      imprintText: nativeState?.imprintText.trim().isNotEmpty == true
          ? nativeState!.imprintText
          : previewData?.imprintText ?? widget.imprintText,
      antiFakeCode: WatermarkTemplate118Composer.ensureAntiFakeCode(
        nativeState?.antiFakeCode ?? previewData?.antiFakeCode,
      ),
      timeOverrideText:
          nativeState?.timeOverrideText ?? previewData?.timeOverrideText,
      dateOverrideText:
          nativeState?.dateOverrideText ?? previewData?.dateOverrideText,
      adjustments: adjustments,
    );
  }

  Future<void> _applyCurrentRoomCode(String nextRoomCode) async {
    final normalized = nextRoomCode.trim();
    final currentPreview = _previewData;
    setState(() {
      _currentRoomCode = normalized;
      if (currentPreview != null || !_useNativePreview || _watermarkEnabled) {
        _previewData = _buildPreviewData(
          captureTime: currentPreview?.captureTime ?? DateTime.now(),
          antiFakeCode: currentPreview?.antiFakeCode,
          location: currentPreview?.location,
          weatherText: currentPreview?.weatherText,
        );
      }
    });

    if (_useNativePreview && _nativePreviewController != null) {
      await _updateNativeWatermarkState(<String, dynamic>{
        'roomCode': normalized,
      });
    }
  }

  Future<void> _applyCurrentLocation(String nextLocation) async {
    final normalized = nextLocation.trim();
    final currentPreview = _previewData;
    setState(() {
      _currentLocation = normalized;
      if (currentPreview != null || !_useNativePreview || _watermarkEnabled) {
        _previewData = _buildPreviewData(
          captureTime: currentPreview?.captureTime ?? DateTime.now(),
          antiFakeCode: currentPreview?.antiFakeCode,
          location: normalized,
          weatherText: currentPreview?.weatherText,
        );
      }
    });

    if (_useNativePreview && _nativePreviewController != null) {
      await _updateNativeWatermarkState(<String, dynamic>{
        'location': normalized,
      });
    }
  }

  Future<void> _editCurrentRoomCode() async {
    final controller = TextEditingController(text: _resolvedCurrentRoomCode());
    try {
      final nextValue = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('修改拍照备注'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: '备注内容',
              hintText: '请输入本次拍照备注',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('更新'),
            ),
          ],
        ),
      );
      if (!mounted || nextValue == null) {
        return;
      }
      final normalized = nextValue.trim();
      if (normalized.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('备注不能为空')));
        return;
      }
      if (normalized == _resolvedCurrentRoomCode()) {
        return;
      }
      await _applyCurrentRoomCode(normalized);
    } finally {
      controller.dispose();
    }
  }

  Future<void> _editCurrentLocation() async {
    final controller = TextEditingController(text: _resolvedCurrentLocation());
    try {
      final nextValue = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('修改水印地址'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: '地址内容',
              hintText: '请输入当前水印地址',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('更新'),
            ),
          ],
        ),
      );
      if (!mounted || nextValue == null) {
        return;
      }
      final normalized = nextValue.trim();
      if (normalized == _resolvedCurrentLocation()) {
        return;
      }
      await _applyCurrentLocation(normalized);
    } finally {
      controller.dispose();
    }
  }

  Widget _buildRoomCodeEditOverlay({
    required double bottomReserved,
    required Size viewportSize,
  }) {
    if (!_watermarkEnabled ||
        viewportSize.width <= 0 ||
        viewportSize.height <= 0) {
      return const SizedBox.shrink();
    }
    final rect = WatermarkTemplate118Composer.estimateRoomCodeBadgeRect(
      imageWidth: viewportSize.width,
      imageHeight: viewportSize.height,
      data: _buildCurrentWatermarkInteractionData(),
      extraBottomInsetPx: bottomReserved,
    );
    if (rect.width <= 0 || rect.height <= 0) {
      return const SizedBox.shrink();
    }
    return Positioned.fromRect(
      rect: rect,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => unawaited(_editCurrentRoomCode()),
        child: const SizedBox.expand(),
      ),
    );
  }

  Watermark118Data _buildPreviewData({
    DateTime? captureTime,
    String? antiFakeCode,
    String? location,
    String? weatherText,
  }) {
    final current = _previewData;
    return Watermark118Data(
      location: location ?? current?.location ?? _resolvedCurrentLocation(),
      roomCode: _roomCodeForPreview(),
      weatherText:
          weatherText ?? current?.weatherText ?? _resolvedCurrentWeatherText(),
      captureTime: captureTime ?? DateTime.now(),
      imprintText: widget.imprintText,
      antiFakeCode: WatermarkTemplate118Composer.ensureAntiFakeCode(
        antiFakeCode ?? current?.antiFakeCode,
      ),
      adjustments: current?.adjustments ?? const Watermark118Adjustments(),
    );
  }

  void _refreshPreviewClock() {
    if (!mounted || !_watermarkEnabled) {
      return;
    }
    final next = _buildPreviewData(captureTime: DateTime.now());
    if (_previewData?.formattedTime == next.formattedTime) {
      return;
    }
    setState(() {
      _previewData = next;
    });
  }

  Future<void> _loadNativeWatermarkState() async {
    final controller = _nativePreviewController;
    if (!_useNativePreview || controller == null || _isClosing) {
      return;
    }
    try {
      final state = await controller.getWatermarkState();
      if (!mounted || _isClosing || controller != _nativePreviewController) {
        return;
      }
      setState(() {
        _nativeWatermarkState = state;
        _watermarkEnabled = state.watermarkEnabled;
        _currentLocation = state.location.trim().isEmpty
            ? _currentLocation
            : state.location;
        _currentRoomCode =
            state.roomCode.trim().isEmpty ||
                _isPreviewPlaceholderRoomCode(state.roomCode)
            ? _currentRoomCode
            : state.roomCode;
      });
      final currentWeatherText = _resolvedCurrentWeatherText();
      if (state.weatherText != currentWeatherText) {
        await _updateNativeWatermarkState(<String, dynamic>{
          'weatherText': currentWeatherText,
        }, silent: true);
      }
    } catch (error) {
      debugPrint('load native watermark state failed: $error');
    }
  }

  Future<void> _persistWatermarkEnabledPreference(bool value) async {
    try {
      final onChanged = widget.onWatermarkPreferenceChanged;
      if (onChanged != null) {
        await onChanged(value);
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_defaultWatermarkEnabledPreferenceKey, value);
    } catch (error) {
      debugPrint('persist watermark preference failed: $error');
    }
  }

  Future<NativeWatermarkPreviewState?> _updateNativeWatermarkState(
    Map<String, dynamic> changes, {
    bool silent = false,
  }) async {
    final controller = _nativePreviewController;
    if (!_useNativePreview || controller == null || _isClosing) {
      return null;
    }
    try {
      final state = await controller.updateWatermarkState(changes);
      if (!mounted || _isClosing || controller != _nativePreviewController) {
        return null;
      }
      setState(() {
        _nativeWatermarkState = state;
        _watermarkEnabled = state.watermarkEnabled;
        _currentLocation = state.location.trim().isEmpty
            ? _currentLocation
            : state.location;
        _currentRoomCode =
            state.roomCode.trim().isEmpty ||
                _isPreviewPlaceholderRoomCode(state.roomCode)
            ? _currentRoomCode
            : state.roomCode;
      });
      return state;
    } catch (error) {
      if (!mounted || silent) {
        return null;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('更新水印失败: $error')));
      return null;
    }
  }

  Future<bool> _ensureNativeLocationPermission(String targetLabel) async {
    final status = await Permission.location.status;
    if (status.isDenied) {
      final requested = await Permission.location.request();
      if (!requested.isGranted) {
        if (requested.isPermanentlyDenied && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('定位权限已被永久拒绝，已为你打开$targetLabel的系统设置入口'),
              action: SnackBarAction(label: '设置', onPressed: openAppSettings),
            ),
          );
        }
        return false;
      }
    } else if (status.isPermanentlyDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('需要定位权限才能获取$targetLabel'),
            action: SnackBarAction(label: '设置', onPressed: openAppSettings),
          ),
        );
      }
      return false;
    }
    return true;
  }

  Future<NativeWatermarkPreviewState?> _refreshNativeAddress() async {
    final currentState = _nativeWatermarkState;
    if (!_useNativePreview ||
        currentState == null ||
        _isRefreshingNativeAddress) {
      return null;
    }

    setState(() {
      _isRefreshingNativeAddress = true;
    });

    try {
      if (!await _ensureNativeLocationPermission('地址')) {
        return null;
      }

      final snapshot = await CaptureLocationService.resolveSnapshot(
        fallbackAddress: currentState.location,
      );
      if (snapshot.position == null &&
          snapshot.address == currentState.location) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('未获取到最新地址，已保留当前文本')));
        }
        return null;
      }

      final state = await _updateNativeWatermarkState(<String, dynamic>{
        'location': snapshot.address,
      });
      if (mounted && state != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('地址已刷新')));
      }
      return state;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('地址刷新失败: $error')));
      }
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingNativeAddress = false;
        });
      }
    }
  }

  Future<NativeWatermarkPreviewState?> _refreshNativeWeather() async {
    final currentState = _nativeWatermarkState;
    if (!_useNativePreview ||
        currentState == null ||
        _isRefreshingNativeWeather ||
        _isAutoRefreshingWeatherSlot) {
      return null;
    }

    setState(() {
      _isRefreshingNativeWeather = true;
    });

    try {
      final weatherText = await _resolveLatestWeatherText(
        requestPermission: true,
        showNoLocationMessage: true,
      );
      if (weatherText == null) {
        return null;
      }

      final slotKey = captureWeatherRefreshSlotKey(DateTime.now());
      if (slotKey.isNotEmpty) {
        await _persistWeatherRefreshCache(weatherText, slotKey);
        _currentWeatherSlotKey = slotKey;
      }
      await _applyWeatherText(weatherText);
      final state = _nativeWatermarkState;
      if (mounted && state != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('天气已刷新')));
      }
      return state;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('天气刷新失败: $error')));
      }
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingNativeWeather = false;
        });
      }
    }
  }

  Future<void> _setWatermarkEnabled(bool value) async {
    if (_watermarkEnabled == value || _isClosing) {
      return;
    }

    if (_useNativePreview) {
      final state = await _updateNativeWatermarkState(<String, dynamic>{
        'watermarkEnabled': value,
      });
      if (!mounted || state == null) {
        return;
      }
      await _persistWatermarkEnabledPreference(state.watermarkEnabled);
      return;
    }

    setState(() {
      _watermarkEnabled = value;
      if (value) {
        _previewData = _buildPreviewData(captureTime: DateTime.now());
      }
    });
    if (value) {
      _startPreviewClockIfNeeded();
    } else {
      _stopPreviewClock();
    }
    await _persistWatermarkEnabledPreference(value);
  }

  Widget _buildViewportPlaceholder(String label) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.6),
            ),
            const SizedBox(height: 14),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClosingViewport() {
    return const ColoredBox(
      color: Colors.black,
      child: Center(
        child: Text(
          '正在关闭相机...',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildCameraViewport() {
    if (_isClosing) {
      return _buildClosingViewport();
    }

    if (_useNativePreview) {
      if (!_attachNativePreview) {
        return _buildViewportPlaceholder('等待页面切换完成...');
      }
      return Stack(
        children: [
          Positioned.fill(
            child: NativeWatermarkCameraPreview(
              title: widget.title,
              roomCode: _roomCodeForPreview(),
              location: _resolvedCurrentLocation(),
              weatherText: _resolvedCurrentWeatherText(),
              imprintText: widget.imprintText,
              watermarkEnabled: _watermarkEnabled,
              onCreated: (controller) {
                if (_isClosing) {
                  unawaited(
                    controller
                        .shutdownCamera()
                        .catchError(
                          (Object error) => debugPrint(
                            'Native camera early shutdown error: $error',
                          ),
                        )
                        .whenComplete(controller.dispose),
                  );
                  return;
                }
                _nativePreviewController = controller;
                unawaited(_loadNativeWatermarkState());
              },
              onCameraReady: _handleNativePreviewReady,
              onCameraError: _handleNativePreviewError,
            ),
          ),
          if (!_isReady)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black26,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      );
    }

    final controller = _controller;
    if (!_isReady || controller == null) {
      return _buildViewportPlaceholder(
        _cameraSessionStarted ? '正在打开相机...' : '等待页面切换完成...',
      );
    }

    final previewSize = controller.value.previewSize;
    if (previewSize == null) {
      return Center(child: CameraPreview(controller));
    }

    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: previewSize.height,
          height: previewSize.width,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  Future<void> _onShoot() async {
    if (!_isReady || _isClosing || _isCapturing) {
      return;
    }
    if (widget.allowContinuousCapture &&
        _resolvedCurrentRoomCode().trim().isEmpty) {
      await _editCurrentRoomCode();
      if (!mounted || _resolvedCurrentRoomCode().trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('请先填写拍照备注再拍摄')));
        }
        return;
      }
    }
    setState(() {
      _isCapturing = true;
    });
    try {
      CameraCaptureResult? captureResult;
      if (_useNativePreview) {
        final controller = _nativePreviewController;
        if (controller == null) {
          return;
        }
        final nativeResult = await controller.capture();
        final capture = _buildNativeCaptureResult(nativeResult);
        if (capture == null) {
          throw StateError('原生相机没有返回照片');
        }
        captureResult = capture;
      } else {
        final controller = _controller;
        if (controller == null) {
          return;
        }
        final captureData = _buildPreviewData(captureTime: DateTime.now());
        if (_watermarkEnabled) {
          setState(() {
            _previewData = captureData;
          });
        }
        final image = await controller.takePicture();
        captureResult = CameraCaptureResult(
          photo: image,
          watermarkData: captureData,
          skipCompose: !_watermarkEnabled,
          watermarkEnabled: _watermarkEnabled,
        );
      }

      final nextCaptureCount = _captured + 1;
      final onCaptureProcessed = widget.onCaptureProcessed;
      if (onCaptureProcessed != null) {
        await onCaptureProcessed(captureResult, nextCaptureCount);
      }
      _photos.add(captureResult);
      _captured++;
      if (!mounted) return;
      final bool isFinalCapture =
          !widget.allowContinuousCapture && _captured >= widget.captureCount;
      Future<void>? shutdownFuture;
      if (isFinalCapture) {
        shutdownFuture = _beginCameraShutdown();
      }
      await _showCaptureFeedback();
      if (!mounted) return;
      if (isFinalCapture) {
        if (shutdownFuture != null) {
          await shutdownFuture;
        }
        if (!mounted) return;
        await Future<void>.delayed(_finalCaptureReturnDelay);
        if (!mounted) return;
        _completePop(_photos);
      } else if (_useNativePreview) {
        setState(() {});
      } else if (_watermarkEnabled) {
        setState(() {
          _previewData = _buildPreviewData(
            captureTime: DateTime.now(),
            antiFakeCode: WatermarkTemplate118Composer.generateAntiFakeCode(),
          );
        });
      } else {
        setState(() {});
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('拍照失败: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      } else {
        _isCapturing = false;
      }
    }
  }

  Future<void> _showCaptureFeedback() async {
    final entry = OverlayEntry(
      builder: (context) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 50),
                const SizedBox(height: 10),
                Text(
                  widget.allowContinuousCapture
                      ? '已拍 $_captured 张'
                      : widget.captureCount > 1
                      ? '第 $_captured / ${widget.captureCount} 张'
                      : '拍照成功',
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(entry);
    await Future.delayed(const Duration(milliseconds: 800));
    entry.remove();
  }

  CameraCaptureResult? _buildNativeCaptureResult(Map<String, dynamic> entry) {
    final photoPath = (entry['photoPath'] as String?)?.trim() ?? '';
    if (photoPath.isEmpty) {
      return null;
    }

    final captureTimeMillis =
        (entry['captureTimeMillis'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;
    final rawAdjustments = entry['adjustments'];
    final adjustments = rawAdjustments is Map
        ? Watermark118Adjustments.fromMap(
            Map<String, dynamic>.from(
              rawAdjustments.map(
                (key, value) => MapEntry(key.toString(), value),
              ),
            ),
          )
        : _nativeWatermarkState != null
        ? Watermark118Adjustments.fromMap(
            Map<String, dynamic>.from(_nativeWatermarkState!.adjustments),
          )
        : const Watermark118Adjustments();

    return CameraCaptureResult(
      photo: XFile(photoPath),
      skipCompose:
          (entry['skipCompose'] as bool?) ??
          !((entry['watermarkEnabled'] as bool?) ?? true),
      watermarkEnabled: (entry['watermarkEnabled'] as bool?) ?? true,
      preferNativeCompose:
          ((entry['watermarkEnabled'] as bool?) ?? true) &&
          ((entry['preferNativeCompose'] as bool?) ?? true),
      watermarkData: Watermark118Data(
        location: (entry['location'] as String?) ?? _resolvedCurrentLocation(),
        roomCode: (entry['roomCode'] as String?) ?? _resolvedCurrentRoomCode(),
        weatherText:
            (entry['weatherText'] as String?) ?? _resolvedCurrentWeatherText(),
        captureTime: DateTime.fromMillisecondsSinceEpoch(captureTimeMillis),
        imprintText: (entry['imprintText'] as String?) ?? widget.imprintText,
        antiFakeCode: WatermarkTemplate118Composer.ensureAntiFakeCode(
          entry['antiFakeCode'] as String?,
        ),
        secureCodeSpacingValue: adjustments.secureCodeSpacingValue,
        timeOverrideText: (entry['displayTimeText'] as String?)
            ?.trim()
            .replaceAll('\n', ' ')
            .trim(),
        dateOverrideText: (entry['displayDateText'] as String?)
            ?.trim()
            .replaceAll('\n', ' ')
            .trim(),
        adjustments: adjustments,
      ),
    );
  }

  void _handleNativePreviewReady() {
    if (!mounted || _isClosing) {
      return;
    }
    setState(() {
      _isReady = true;
    });
    unawaited(_loadNativeWatermarkState());
    unawaited(_syncWeatherForCurrentSlot());
  }

  void _handleNativePreviewError(String message) {
    if (!mounted || _isClosing) {
      return;
    }
    setState(() {
      _isReady = false;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('原生预览初始化失败: $message')));
  }

  @override
  Widget build(BuildContext context) {
    final previewBottomReserved = 144 + MediaQuery.paddingOf(context).bottom;

    return PopScope(
      canPop: _allowSystemPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          unawaited(_handleCloseRequested());
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          leading: IconButton(
            onPressed: _isClosing
                ? null
                : () => unawaited(_handleCloseRequested()),
            icon: const Icon(Icons.arrow_back_ios_new),
          ),
          title: Text(widget.title),
          backgroundColor: Colors.black.withValues(alpha: 0.18),
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              onPressed: _isClosing
                  ? null
                  : () => unawaited(_editCurrentLocation()),
              icon: const Icon(Icons.edit_location_alt_outlined),
              tooltip: '修改水印地址',
            ),
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: TextButton.icon(
                onPressed: _isClosing
                    ? null
                    : () => unawaited(_setWatermarkEnabled(!_watermarkEnabled)),
                icon: Icon(
                  _watermarkEnabled
                      ? Icons.branding_watermark_outlined
                      : Icons.image_not_supported_outlined,
                  color: Colors.white,
                ),
                label: Text(
                  _watermarkEnabled ? '水印开' : '水印关',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
            if (_useNativePreview && _attachNativePreview && _watermarkEnabled)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: NativeWatermarkControlPanel(
                    state: _nativeWatermarkState,
                    isRefreshingAddress: _isRefreshingNativeAddress,
                    isRefreshingWeather: _isRefreshingNativeWeather,
                    onUpdateState: _updateNativeWatermarkState,
                    onRefreshAddress: _refreshNativeAddress,
                    onRefreshWeather: _refreshNativeWeather,
                  ),
                ),
              ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final viewportSize = Size(
              constraints.maxWidth,
              constraints.maxHeight,
            );
            return Stack(
              children: [
                Positioned.fill(child: _buildCameraViewport()),
                if (!_useNativePreview)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.16),
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.26),
                              Colors.black.withValues(alpha: 0.4),
                            ],
                            stops: const [0, 0.22, 0.72, 1],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (!_useNativePreview &&
                    _watermarkEnabled &&
                    _previewData != null)
                  Positioned.fill(
                    child: Watermark118CaptureOverlay(
                      data: _previewData!,
                      bottomReserved: previewBottomReserved,
                    ),
                  ),
                _buildRoomCodeEditOverlay(
                  bottomReserved: previewBottomReserved,
                  viewportSize: viewportSize,
                ),
                Positioned(
                  bottom: 112 + MediaQuery.paddingOf(context).bottom,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.56),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _isClosing
                            ? '正在关闭相机...'
                            : !_cameraSessionStarted
                            ? '等待页面切换完成'
                            : widget.allowContinuousCapture
                            ? _captured == 0
                                  ? '连续拍照模式，返回结束本次拍摄'
                                  : '已连续拍摄 $_captured 张，返回结束本次拍摄'
                            : widget.captureCount > 1
                            ? '拍摄第 ${_captured + 1} 张'
                            : !_watermarkEnabled
                            ? '无水印原图模式'
                            : _useNativePreview
                            ? '原生实时预览'
                            : '实时水印预览',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: Hero(
          tag: 'fab_main_action',
          child: FloatingActionButton.large(
            heroTag: null,
            onPressed: _isReady && !_isClosing && !_isCapturing
                ? _onShoot
                : null,
            backgroundColor: Colors.white,
            child: Icon(
              Icons.camera_alt,
              color: Theme.of(context).primaryColor,
            ),
          ),
        ),
      ),
    );
  }
}
