import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

class Watermark118Adjustments {
  final double anchorStartDp;
  final double anchorEndDp;
  final double anchorBottomDp;
  final double locationColumnWidthDp;
  final double leftScale;
  final double leftXdp;
  final double leftYdp;
  final double timeTextSizeDp;
  final double timeGlowRadiusDp;
  final double timeXdp;
  final double timeYdp;
  final double rightScale;
  final double rightXdp;
  final double rightYdp;
  final double secureXdp;
  final double secureYdp;
  final double secureCodeTextSizeDp;
  final double secureTitleScale;
  final double secureShadowScaleX;
  final double secureShadowScaleY;
  final double secureShadowXdp;
  final double secureShadowYdp;
  final double secureCodeSpacingValue;
  final double demoXdp;
  final double demoYdp;
  final double roomCodeVerticalPaddingDp;
  final double roomCodeTextSizeSp;
  final double imprintIconWidthSp;
  final double imprintIconHeightSp;
  final double imprintTextSizeSp;

  const Watermark118Adjustments({
    this.anchorStartDp = 18,
    this.anchorEndDp = 18,
    this.anchorBottomDp = 9,
    this.locationColumnWidthDp = 265,
    this.leftScale = 1,
    this.leftXdp = -12.9,
    this.leftYdp = 3.3,
    this.timeTextSizeDp = 25,
    this.timeGlowRadiusDp = 0.5,
    this.timeXdp = 3.4,
    this.timeYdp = -0.7,
    this.rightScale = 1,
    this.rightXdp = 13.8,
    this.rightYdp = 6.8,
    this.secureXdp = 3.0,
    this.secureYdp = -1.6,
    this.secureCodeTextSizeDp = 5,
    this.secureTitleScale = 1,
    this.secureShadowScaleX = 0.7,
    this.secureShadowScaleY = 1,
    this.secureShadowXdp = -7.2,
    this.secureShadowYdp = 0,
    this.secureCodeSpacingValue = 0,
    this.demoXdp = 2,
    this.demoYdp = -2,
    this.roomCodeVerticalPaddingDp = 7,
    this.roomCodeTextSizeSp = 14,
    this.imprintIconWidthSp = 12,
    this.imprintIconHeightSp = 14,
    this.imprintTextSizeSp = 12,
  });

  factory Watermark118Adjustments.fromMap(Map<String, dynamic> map) {
    double read(String key, double fallback) {
      final rawValue = map[key];
      return rawValue is num ? rawValue.toDouble() : fallback;
    }

    const defaults = Watermark118Adjustments();
    return Watermark118Adjustments(
      anchorStartDp: read('anchorStartDp', defaults.anchorStartDp),
      anchorEndDp: read('anchorEndDp', defaults.anchorEndDp),
      anchorBottomDp: read('anchorBottomDp', defaults.anchorBottomDp),
      locationColumnWidthDp: read(
        'locationColumnWidthDp',
        defaults.locationColumnWidthDp,
      ),
      leftScale: read('leftScale', defaults.leftScale),
      leftXdp: read('leftXdp', defaults.leftXdp),
      leftYdp: read('leftYdp', defaults.leftYdp),
      timeTextSizeDp: read('timeTextSizeDp', defaults.timeTextSizeDp),
      timeGlowRadiusDp: read('timeGlowRadiusDp', defaults.timeGlowRadiusDp),
      timeXdp: read('timeXdp', defaults.timeXdp),
      timeYdp: read('timeYdp', defaults.timeYdp),
      rightScale: read('rightScale', defaults.rightScale),
      rightXdp: read('rightXdp', defaults.rightXdp),
      rightYdp: read('rightYdp', defaults.rightYdp),
      secureXdp: read('secureXdp', defaults.secureXdp),
      secureYdp: read('secureYdp', defaults.secureYdp),
      secureCodeTextSizeDp: read(
        'secureCodeTextSizeDp',
        defaults.secureCodeTextSizeDp,
      ),
      secureTitleScale: read('secureTitleScale', defaults.secureTitleScale),
      secureShadowScaleX: read(
        'secureShadowScaleX',
        defaults.secureShadowScaleX,
      ),
      secureShadowScaleY: read(
        'secureShadowScaleY',
        defaults.secureShadowScaleY,
      ),
      secureShadowXdp: read('secureShadowXdp', defaults.secureShadowXdp),
      secureShadowYdp: read('secureShadowYdp', defaults.secureShadowYdp),
      secureCodeSpacingValue: read(
        'secureCodeSpacingValue',
        defaults.secureCodeSpacingValue,
      ),
      demoXdp: read('demoXdp', defaults.demoXdp),
      demoYdp: read('demoYdp', defaults.demoYdp),
      roomCodeVerticalPaddingDp: read(
        'roomCodeVerticalPaddingDp',
        defaults.roomCodeVerticalPaddingDp,
      ),
      roomCodeTextSizeSp: read(
        'roomCodeTextSizeSp',
        defaults.roomCodeTextSizeSp,
      ),
      imprintIconWidthSp: read(
        'imprintIconWidthSp',
        defaults.imprintIconWidthSp,
      ),
      imprintIconHeightSp: read(
        'imprintIconHeightSp',
        defaults.imprintIconHeightSp,
      ),
      imprintTextSizeSp: read('imprintTextSizeSp', defaults.imprintTextSizeSp),
    );
  }

  Map<String, double> toMap() {
    return <String, double>{
      'anchorStartDp': anchorStartDp,
      'anchorEndDp': anchorEndDp,
      'anchorBottomDp': anchorBottomDp,
      'locationColumnWidthDp': locationColumnWidthDp,
      'leftScale': leftScale,
      'leftXdp': leftXdp,
      'leftYdp': leftYdp,
      'timeTextSizeDp': timeTextSizeDp,
      'timeGlowRadiusDp': timeGlowRadiusDp,
      'timeXdp': timeXdp,
      'timeYdp': timeYdp,
      'rightScale': rightScale,
      'rightXdp': rightXdp,
      'rightYdp': rightYdp,
      'secureXdp': secureXdp,
      'secureYdp': secureYdp,
      'secureCodeTextSizeDp': secureCodeTextSizeDp,
      'secureTitleScale': secureTitleScale,
      'secureShadowScaleX': secureShadowScaleX,
      'secureShadowScaleY': secureShadowScaleY,
      'secureShadowXdp': secureShadowXdp,
      'secureShadowYdp': secureShadowYdp,
      'secureCodeSpacingValue': secureCodeSpacingValue,
      'demoXdp': demoXdp,
      'demoYdp': demoYdp,
      'roomCodeVerticalPaddingDp': roomCodeVerticalPaddingDp,
      'roomCodeTextSizeSp': roomCodeTextSizeSp,
      'imprintIconWidthSp': imprintIconWidthSp,
      'imprintIconHeightSp': imprintIconHeightSp,
      'imprintTextSizeSp': imprintTextSizeSp,
    };
  }
}

class Watermark118Data {
  final String location;
  final String roomCode;
  final String weatherText;
  final DateTime captureTime;
  final String imprintText;
  final String antiFakeCode;
  final double secureCodeSpacingValue;
  final String? timeOverrideText;
  final String? dateOverrideText;
  final Watermark118Adjustments adjustments;

  const Watermark118Data({
    required this.location,
    required this.roomCode,
    required this.weatherText,
    required this.captureTime,
    required this.imprintText,
    required this.antiFakeCode,
    this.secureCodeSpacingValue = 0,
    this.timeOverrideText,
    this.dateOverrideText,
    this.adjustments = const Watermark118Adjustments(),
  });

  String get formattedTime {
    if (timeOverrideText != null && timeOverrideText!.trim().isNotEmpty) {
      return timeOverrideText!.trim();
    }
    final hour = captureTime.hour.toString().padLeft(2, '0');
    final minute = captureTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String get formattedDate {
    if (dateOverrideText != null && dateOverrideText!.trim().isNotEmpty) {
      return dateOverrideText!.trim();
    }
    const weekdays = <int, String>{
      DateTime.monday: '星期一',
      DateTime.tuesday: '星期二',
      DateTime.wednesday: '星期三',
      DateTime.thursday: '星期四',
      DateTime.friday: '星期五',
      DateTime.saturday: '星期六',
      DateTime.sunday: '星期日',
    };
    final date =
        '${captureTime.year.toString().padLeft(4, '0')}.${captureTime.month.toString().padLeft(2, '0')}.${captureTime.day.toString().padLeft(2, '0')}';
    return '$date ${weekdays[captureTime.weekday] ?? ''}'.trim();
  }
}

class _ImprintParts {
  final String prefix;
  final String? divider;
  final String? suffix;

  const _ImprintParts({required this.prefix, this.divider, this.suffix});
}

class WatermarkTemplate118Composer {
  static const String defaultWeatherText = '天气获取中';
  static const String defaultImprintText = '今日水印相机已验证|时间地点真实';
  static const int defaultAntiFakeCodeLength = 14;
  static const String _antiFakeAlphabet =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  static const double _designWidth = 768;
  static const double _leftScaleBase = 2.08;
  static const double _rightScaleBase = 2.18;
  static const double _leftRootWidth = 252;
  static const double _leftRootHeight = 129;
  static const double _rightShellMinWidth = 64;
  static const double _rightShellHeight = 37;
  static const double _rightBrandWidth = 56;
  static const double _rightBrandHeight = 26;
  static const double _rightTitleWidth = 10;
  static const double _rightTitleHeight = 7;
  static const double _rightCodeMinWidth = 53;
  static const double _rightCodeHeight = 8;
  static const double _rightRowGapX = 1;
  static const double _rightRowGapY = 3;
  static const double _rightCodeInsetLeft = 1;
  static const double _rightCodeInsetTop = 0.5;
  static const double _rightCodeBgTopInset = 1;
  static const double _rightCodeFontSize = 6.2;
  static const double _leftVerticalLiftRef = 287;
  static const double _rightVerticalLiftRef = 106;

  static const String _timeBgAsset =
      'assets/watermark_118/images/dk_102_time_new.png';
  static const String _tagIconAsset = 'assets/watermark_118/images/dk_tu2.png';
  static const String _brandAsset = 'assets/watermark_118/images/water17.png';
  static const String _antiTitleAsset =
      'assets/watermark_118/images/bg_tv_anti_fake.png';
  static const String _antiBgAsset =
      'assets/watermark_118/images/bg_code_shadow.png';
  static const String _imprintAsset =
      'assets/watermark_118/images/imprint_1.png';
  static const String _bebasFontAsset =
      'assets/watermark_118/fonts/BebasDaka.ttf';
  static const String _heiFontAsset =
      'assets/watermark_118/fonts/HYQiHeiX2-65W.otf';
  static const String _monoFontAsset =
      'assets/watermark_118/fonts/PTMono-Bold.ttf';

  static final Map<String, Future<ui.Image>> _assetImageCache =
      <String, Future<ui.Image>>{};
  static Future<void>? _fontLoadFuture;
  static const Watermark118Adjustments _defaultAdjustments =
      Watermark118Adjustments();

  static Watermark118Data buildDefaultData({
    required String location,
    required String roomCode,
    DateTime? captureTime,
    String weatherText = defaultWeatherText,
    String imprintText = defaultImprintText,
    String? antiFakeCode,
    double secureCodeSpacingValue = 0,
    String? timeOverrideText,
    String? dateOverrideText,
    Watermark118Adjustments adjustments = const Watermark118Adjustments(),
  }) {
    return Watermark118Data(
      location: location,
      roomCode: roomCode,
      weatherText: weatherText,
      captureTime: captureTime ?? DateTime.now(),
      imprintText: imprintText,
      antiFakeCode: ensureAntiFakeCode(antiFakeCode),
      secureCodeSpacingValue: secureCodeSpacingValue,
      timeOverrideText: timeOverrideText,
      dateOverrideText: dateOverrideText,
      adjustments: adjustments,
    );
  }

  static Rect estimateRoomCodeBadgeRect({
    required double imageWidth,
    required double imageHeight,
    required Watermark118Data data,
    double extraBottomInsetPx = 0,
    double hitPaddingPx = 12,
  }) {
    final adjustments = data.adjustments;
    final globalScale = imageWidth / _designWidth;
    final leftScale = globalScale * _leftScaleBase * adjustments.leftScale;
    final origin = Offset(
      adjustments.anchorStartDp * globalScale +
          _scaledOuterDelta(
            adjustments.leftXdp,
            _defaultAdjustments.leftXdp,
            globalScale,
          ),
      imageHeight -
          extraBottomInsetPx -
          (adjustments.anchorBottomDp * globalScale) -
          (_leftRootHeight * leftScale) -
          ((_leftVerticalLiftRef / 1920) * imageWidth) +
          _scaledOuterDelta(
            adjustments.leftYdp,
            _defaultAdjustments.leftYdp,
            globalScale,
          ),
    );
    final textLength = math.max(4, data.roomCode.trim().runes.length);
    final estimatedTextWidth =
        (textLength * adjustments.roomCodeTextSizeSp * 0.72 * leftScale) +
        (16 * leftScale);
    final badgeWidth = math.min(
      math.max(96 * leftScale, estimatedTextWidth),
      240 * leftScale,
    );
    final badgeHeight = math.max(
      27 * leftScale,
      ((adjustments.roomCodeTextSizeSp +
                  (adjustments.roomCodeVerticalPaddingDp * 2)) *
              1.12) *
          leftScale,
    );
    final badgeRect = Rect.fromLTWH(
      origin.dx,
      origin.dy + (132 * leftScale),
      badgeWidth,
      badgeHeight,
    ).inflate(hitPaddingPx);
    final bounds = Rect.fromLTWH(0, 0, imageWidth, imageHeight);
    return Rect.fromLTRB(
      badgeRect.left.clamp(bounds.left, bounds.right),
      badgeRect.top.clamp(bounds.top, bounds.bottom),
      badgeRect.right.clamp(bounds.left, bounds.right),
      badgeRect.bottom.clamp(bounds.top, bounds.bottom),
    );
  }

  static String ensureAntiFakeCode(
    String? rawCode, {
    math.Random? random,
    int length = defaultAntiFakeCodeLength,
  }) {
    final normalized = rawCode?.trim() ?? '';
    if (normalized.isNotEmpty) {
      return normalized;
    }
    return generateAntiFakeCode(random: random, length: length);
  }

  static String generateAntiFakeCode({
    math.Random? random,
    int length = defaultAntiFakeCodeLength,
  }) {
    return generateRawAntiFakeCode(random: random, length: length);
  }

  static String generateRawAntiFakeCode({
    math.Random? random,
    int length = defaultAntiFakeCodeLength,
  }) {
    final generator = random ?? math.Random.secure();
    final buffer = StringBuffer();
    for (int i = 0; i < length; i++) {
      buffer.write(
        _antiFakeAlphabet[generator.nextInt(_antiFakeAlphabet.length)],
      );
    }
    return buffer.toString();
  }

  static Future<void> composePreview({
    required String outputPath,
    required Watermark118Data data,
    int width = 1920,
    int height = 2560,
  }) async {
    await _ensureFontsLoaded();
    final sourceImage = await _buildPreviewBaseImage(
      width: width,
      height: height,
    );

    try {
      await _composeWithSourceImage(
        sourceImage: sourceImage,
        outputPath: outputPath,
        data: data,
      );
    } finally {
      sourceImage.dispose();
    }
  }

  static Future<void> composePhoto({
    required String sourcePath,
    required String outputPath,
    required Watermark118Data data,
  }) async {
    await _ensureFontsLoaded();
    final sourceImage = await _loadSourceImage(sourcePath);
    try {
      await _composeWithSourceImage(
        sourceImage: sourceImage,
        outputPath: outputPath,
        data: data,
      );
    } finally {
      sourceImage.dispose();
    }
  }

  static Future<Uint8List> renderOverlayPngBytes({
    required int width,
    required int height,
    required Watermark118Data data,
    double extraBottomInsetPx = 0,
  }) async {
    await _ensureFontsLoaded();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    await _drawWatermarkBlocks(
      canvas,
      imageWidth: width.toDouble(),
      imageHeight: height.toDouble(),
      data: data,
      extraBottomInsetPx: extraBottomInsetPx,
    );

    final picture = recorder.endRecording();
    final overlayImage = await picture.toImage(width, height);
    try {
      final pngData = await overlayImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (pngData == null) {
        throw StateError('生成预览水印失败');
      }
      return pngData.buffer.asUint8List();
    } finally {
      overlayImage.dispose();
    }
  }

  static Future<void> _composeWithSourceImage({
    required ui.Image sourceImage,
    required String outputPath,
    required Watermark118Data data,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.drawImage(sourceImage, Offset.zero, Paint());

    await _drawWatermarkBlocks(
      canvas,
      imageWidth: sourceImage.width.toDouble(),
      imageHeight: sourceImage.height.toDouble(),
      data: data,
    );

    final picture = recorder.endRecording();
    final mergedImage = await picture.toImage(
      sourceImage.width,
      sourceImage.height,
    );

    try {
      final pngData = await mergedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (pngData == null) {
        throw StateError('生成水印图片失败');
      }

      final rasterized = img.decodeImage(pngData.buffer.asUint8List());
      if (rasterized == null) {
        throw StateError('输出图片解码失败');
      }

      final jpgBytes = img.encodeJpg(rasterized, quality: 95);
      await File(outputPath).writeAsBytes(jpgBytes, flush: true);
    } finally {
      mergedImage.dispose();
    }
  }

  static Future<void> _drawWatermarkBlocks(
    Canvas canvas, {
    required double imageWidth,
    required double imageHeight,
    required Watermark118Data data,
    double extraBottomInsetPx = 0,
  }) async {
    final globalScale = imageWidth / _designWidth;
    final adjustments = data.adjustments;
    final leftScale = globalScale * _leftScaleBase * adjustments.leftScale;
    final rightScale = globalScale * _rightScaleBase * adjustments.rightScale;
    final rightShellWidth = _measureRightShellWidth(
      data: data,
      scale: rightScale,
    );

    await _drawLeftBlock(
      canvas,
      origin: Offset(
        adjustments.anchorStartDp * globalScale +
            _scaledOuterDelta(
              adjustments.leftXdp,
              _defaultAdjustments.leftXdp,
              globalScale,
            ),
        imageHeight -
            extraBottomInsetPx -
            (adjustments.anchorBottomDp * globalScale) -
            (_leftRootHeight * leftScale) -
            ((_leftVerticalLiftRef / 1920) * imageWidth) +
            _scaledOuterDelta(
              adjustments.leftYdp,
              _defaultAdjustments.leftYdp,
              globalScale,
            ),
      ),
      scale: leftScale,
      data: data,
    );

    await _drawRightBlock(
      canvas,
      origin: Offset(
        imageWidth -
            (adjustments.anchorEndDp * globalScale) -
            rightShellWidth +
            _scaledOuterDelta(
              adjustments.rightXdp,
              _defaultAdjustments.rightXdp,
              globalScale,
            ),
        imageHeight -
            extraBottomInsetPx -
            (adjustments.anchorBottomDp * globalScale) -
            (_rightShellHeight * rightScale) -
            ((_rightVerticalLiftRef / 1920) * imageWidth) +
            _scaledOuterDelta(
              adjustments.rightYdp,
              _defaultAdjustments.rightYdp,
              globalScale,
            ),
      ),
      scale: rightScale,
      data: data,
    );
  }

  static Future<void> _drawLeftBlock(
    Canvas canvas, {
    required Offset origin,
    required double scale,
    required Watermark118Data data,
  }) async {
    final adjustments = data.adjustments;
    final timeBg = await _loadAssetImage(_timeBgAsset);
    final tagIcon = await _loadAssetImage(_tagIconAsset);
    final imprintIcon = await _loadAssetImage(_imprintAsset);
    final timeFontSize = math
        .max(
          1,
          (29 +
                  (adjustments.timeTextSizeDp -
                      _defaultAdjustments.timeTextSizeDp)) *
              scale,
        )
        .toDouble();
    final baselineTimeFontSize = math.max(1, 29 * scale).toDouble();
    final timeFontRatio = timeFontSize / baselineTimeFontSize;
    final timeXOffset = _scaledInnerDelta(
      adjustments.timeXdp,
      _defaultAdjustments.timeXdp,
      scale,
    );
    final timeYOffset = _scaledInnerDelta(
      adjustments.timeYdp,
      _defaultAdjustments.timeYdp,
      scale,
    );
    final timeGlowBoost = _scaledInnerDelta(
      adjustments.timeGlowRadiusDp,
      _defaultAdjustments.timeGlowRadiusDp,
      scale,
    );

    final timeRect = Rect.fromLTWH(
      origin.dx,
      origin.dy,
      100 * scale,
      30 * scale,
    );
    _drawImageBox(canvas, timeBg, timeRect);

    final tagRect = Rect.fromLTWH(
      origin.dx + (4 * scale),
      origin.dy + (3 * scale),
      36 * scale,
      24 * scale,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(tagRect, Radius.circular(2 * scale)),
      Paint()..color = const Color(0xFFFFC233),
    );
    _drawImageBox(
      canvas,
      tagIcon,
      Rect.fromCenter(
        center: tagRect.center,
        width: 28 * scale,
        height: 14 * scale,
      ),
    );

    final clockRect = Rect.fromLTWH(
      origin.dx + (41 * scale) + timeXOffset,
      origin.dy + (3 * scale) + timeYOffset,
      53 * scale,
      24 * scale,
    );
    _paintStrokedGradientText(
      canvas,
      text: data.formattedTime,
      rect: clockRect,
      fontFamily: 'BebasDaka',
      fontSize: timeFontSize,
      strokeWidth: math.max(0.6, 2.95 * scale * timeFontRatio).toDouble(),
      letterSpacing: 0.55 * scale * timeFontRatio,
      verticalNudge: -0.35 * scale,
      startColor: const Color(0xFF0075FF),
      endColor: Colors.black,
      glowBoost: timeGlowBoost,
    );

    final detailsOrigin = Offset(origin.dx, origin.dy + (38 * scale));
    final textMaxWidth = math
        .max(
          1,
          ((_leftRootWidth - 11) * scale) +
              _scaledInnerDelta(
                adjustments.locationColumnWidthDp,
                _defaultAdjustments.locationColumnWidthDp,
                scale,
              ),
        )
        .toDouble();
    const textShadowColor = Color(0x66000000);
    final textShadows = <Shadow>[
      Shadow(
        color: textShadowColor,
        offset: Offset(0, 1.8 * scale),
        blurRadius: 4.2 * scale,
      ),
    ];

    final addressPainter = _createTextPainter(
      text: data.location,
      maxWidth: textMaxWidth,
      style: TextStyle(
        fontFamily: 'HYQiHei',
        fontSize: 15.6 * scale,
        height: 1.16,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        shadows: textShadows,
      ),
    );
    final datePainter = _createTextPainter(
      text: data.formattedDate,
      maxWidth: textMaxWidth,
      style: TextStyle(
        fontFamily: 'HYQiHei',
        fontSize: 13.4 * scale,
        height: 1.08,
        fontWeight: FontWeight.w600,
        color: Colors.white,
        shadows: textShadows,
      ),
    );
    final weatherPainter = _createTextPainter(
      text: data.weatherText,
      maxWidth: textMaxWidth,
      style: TextStyle(
        fontFamily: 'HYQiHei',
        fontSize: 13.4 * scale,
        height: 1.08,
        fontWeight: FontWeight.w600,
        color: Colors.white,
        shadows: textShadows,
      ),
    );

    final copyX = detailsOrigin.dx + (11 * scale);
    final copyY = detailsOrigin.dy;
    addressPainter.paint(canvas, Offset(copyX, copyY));
    final dateY = copyY + addressPainter.height + (8 * scale);
    datePainter.paint(canvas, Offset(copyX, dateY));
    final weatherY = dateY + datePainter.height + (8 * scale);
    weatherPainter.paint(canvas, Offset(copyX, weatherY));

    final copyHeight = (weatherY + weatherPainter.height - copyY).clamp(
      0.0,
      double.infinity,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          detailsOrigin.dx,
          detailsOrigin.dy,
          3 * scale,
          copyHeight,
        ),
        Radius.circular(99 * scale),
      ),
      Paint()..color = const Color(0xFFFFC233),
    );

    final badgeText = _createTextPainter(
      text: data.roomCode,
      maxWidth: 220 * scale,
      style: TextStyle(
        fontFamily: 'HYQiHei',
        fontSize: math
            .max(
              1,
              (12 +
                      (adjustments.roomCodeTextSizeSp -
                          _defaultAdjustments.roomCodeTextSizeSp)) *
                  scale,
            )
            .toDouble(),
        height: 1,
        color: const Color(0xF0FFFFFF),
      ),
    );
    final badgeHeight = math
        .max(
          27 * scale,
          badgeText.height +
              math
                  .max(
                    0,
                    (12 +
                            ((adjustments.roomCodeVerticalPaddingDp -
                                    _defaultAdjustments
                                        .roomCodeVerticalPaddingDp) *
                                2)) *
                        scale,
                  )
                  .toDouble(),
        )
        .toDouble();
    final badgeRect = Rect.fromLTWH(
      origin.dx,
      origin.dy + (132 * scale),
      math.min(
        (badgeText.width + (16 * scale)).clamp(0, 240 * scale),
        240 * scale,
      ),
      badgeHeight,
    );
    final badgePaint = Paint()
      ..shader = ui.Gradient.linear(
        badgeRect.topLeft,
        badgeRect.topRight,
        const <Color>[Color(0x40EEEEEE), Color(0x12D8D8D8)],
      );
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        badgeRect,
        topLeft: Radius.circular(6 * scale),
        bottomLeft: Radius.circular(6 * scale),
        topRight: Radius.circular(6 * scale),
        bottomRight: Radius.circular(6 * scale),
      ),
      badgePaint,
    );
    badgeText.paint(
      canvas,
      Offset(
        badgeRect.left + (8 * scale),
        badgeRect.top + (badgeRect.height - badgeText.height) / 2,
      ),
    );

    final imprintParts = _parseImprintParts(data.imprintText);
    final imprintTextStyle = TextStyle(
      fontFamily: 'HYQiHei',
      fontSize: math
          .max(
            1,
            (12.3 +
                    (adjustments.imprintTextSizeSp -
                        _defaultAdjustments.imprintTextSizeSp)) *
                scale,
          )
          .toDouble(),
      height: 1,
      color: const Color(0xB3FFFFFF),
      shadows: textShadows,
    );
    final imprintDividerStyle = imprintTextStyle.copyWith(
      color: const Color(0x80FFFFFF),
    );
    final imprintPrefixPainter = _createTextPainter(
      text: imprintParts.prefix,
      maxWidth: (_leftRootWidth * scale) - (16 * scale),
      style: imprintTextStyle,
    );
    final imprintDividerPainter = imprintParts.suffix == null
        ? null
        : _createTextPainter(
            text: imprintParts.divider ?? 'I',
            maxWidth: 14 * scale,
            style: imprintDividerStyle,
          );
    final imprintSuffixPainter = imprintParts.suffix == null
        ? null
        : _createTextPainter(
            text: imprintParts.suffix!,
            maxWidth: (_leftRootWidth * scale) - (16 * scale),
            style: imprintTextStyle,
          );
    final imprintY = origin.dy + (165 * scale);
    final imprintIconWidth = math
        .max(1, adjustments.imprintIconWidthSp * scale)
        .toDouble();
    final imprintIconHeight = math
        .max(1, adjustments.imprintIconHeightSp * scale)
        .toDouble();
    _drawImageBox(
      canvas,
      imprintIcon,
      Rect.fromLTWH(origin.dx, imprintY, imprintIconWidth, imprintIconHeight),
      opacity: 0.7,
    );
    var imprintTextX = origin.dx + (16 * scale);
    final imprintCenterY = imprintY + imprintIconHeight / 2;
    imprintPrefixPainter.paint(
      canvas,
      Offset(imprintTextX, imprintCenterY - imprintPrefixPainter.height / 2),
    );
    imprintTextX += imprintPrefixPainter.width;
    if (imprintDividerPainter != null && imprintSuffixPainter != null) {
      imprintTextX += 4 * scale;
      imprintDividerPainter.paint(
        canvas,
        Offset(imprintTextX, imprintCenterY - imprintDividerPainter.height / 2),
      );
      imprintTextX += imprintDividerPainter.width + (4 * scale);
      imprintSuffixPainter.paint(
        canvas,
        Offset(imprintTextX, imprintCenterY - imprintSuffixPainter.height / 2),
      );
    }
  }

  static Future<void> _drawRightBlock(
    Canvas canvas, {
    required Offset origin,
    required double scale,
    required Watermark118Data data,
  }) async {
    final adjustments = data.adjustments;
    final titleScale = adjustments.secureTitleScale;
    final titleWidth = _rightTitleWidth * scale * titleScale;
    final titleHeight = _rightTitleHeight * scale * titleScale;
    final secureRowX = _scaledInnerDelta(
      adjustments.secureXdp,
      _defaultAdjustments.secureXdp,
      scale,
    );
    final secureRowY = _scaledInnerDelta(
      adjustments.secureYdp,
      _defaultAdjustments.secureYdp,
      scale,
    );
    final brand = await _loadAssetImage(_brandAsset);
    final antiTitle = await _loadAssetImage(_antiTitleAsset);
    final antiBg = await _loadAssetImage(_antiBgAsset);
    final codePainter = _createAntiFakeCodePainter(
      text: data.antiFakeCode,
      scale: scale,
      spacingValue: _effectiveSecureCodeSpacingValue(data),
      fontSize: math
          .max(
            1,
            (_rightCodeFontSize +
                    (adjustments.secureCodeTextSizeDp -
                        _defaultAdjustments.secureCodeTextSizeDp)) *
                scale,
          )
          .toDouble(),
    );
    final codeBoxWidth = math
        .max(
          _rightCodeMinWidth * scale,
          (_rightCodeInsetLeft * scale) + codePainter.width,
        )
        .toDouble();
    final rowWidth = titleWidth + (_rightRowGapX * scale) + codeBoxWidth;
    final shellWidth = math
        .max(_rightShellMinWidth * scale, rowWidth)
        .toDouble();
    final brandX = origin.dx + shellWidth - (_rightBrandWidth * scale);
    final rowX = origin.dx + shellWidth - rowWidth + secureRowX;

    _drawImageBox(
      canvas,
      brand,
      Rect.fromLTWH(
        brandX,
        origin.dy,
        _rightBrandWidth * scale,
        _rightBrandHeight * scale,
      ),
    );

    final rowY =
        origin.dy + ((_rightBrandHeight + _rightRowGapY) * scale) + secureRowY;
    _drawImageBox(
      canvas,
      antiTitle,
      Rect.fromLTWH(rowX, rowY, titleWidth, titleHeight),
    );

    final codeShellRect = Rect.fromLTWH(
      rowX + titleWidth + (_rightRowGapX * scale),
      rowY,
      codeBoxWidth,
      _rightCodeHeight * scale,
    );
    final rawCodeBgRect = Rect.fromLTWH(
      codeShellRect.left + (_rightCodeInsetLeft * scale),
      codeShellRect.top + (_rightCodeBgTopInset * scale),
      codeShellRect.width - (_rightCodeInsetLeft * scale),
      codeShellRect.height - (_rightCodeBgTopInset * scale),
    );
    final codeBgRect = Rect.fromCenter(
      center: rawCodeBgRect.center.translate(
        _scaledInnerDelta(
          adjustments.secureShadowXdp,
          _defaultAdjustments.secureShadowXdp,
          scale,
        ),
        _scaledInnerDelta(
          adjustments.secureShadowYdp,
          _defaultAdjustments.secureShadowYdp,
          scale,
        ),
      ),
      width: rawCodeBgRect.width * adjustments.secureShadowScaleX,
      height: rawCodeBgRect.height * adjustments.secureShadowScaleY,
    );
    _drawImageBox(canvas, antiBg, codeBgRect);
    codePainter.paint(
      canvas,
      Offset(
        codeShellRect.left + (_rightCodeInsetLeft * scale),
        codeShellRect.top + (_rightCodeInsetTop * scale),
      ),
    );
  }

  static Future<ui.Image> _loadSourceImage(String sourcePath) async {
    final bytes = await File(sourcePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw StateError('原图解码失败');
    }
    final baked = img.bakeOrientation(decoded);
    final pngBytes = Uint8List.fromList(img.encodePng(baked));
    final codec = await ui.instantiateImageCodec(pngBytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  static Future<ui.Image> _buildPreviewBaseImage({
    required int width,
    required int height,
  }) async {
    final image = img.Image(width: width, height: height);
    for (int y = 0; y < image.height; y++) {
      final t = y / math.max(1, image.height - 1);
      final r = _lerpInt(43, 8, t);
      final g = _lerpInt(49, 8, t);
      final b = _lerpInt(59, 12, t);
      img.fillRect(
        image,
        x1: 0,
        y1: y,
        x2: image.width - 1,
        y2: y,
        color: img.ColorRgb8(r, g, b),
      );
    }

    img.fillRect(
      image,
      x1: 55,
      y1: 50,
      x2: 260,
      y2: 175,
      color: img.ColorRgb8(230, 230, 232),
    );
    img.fillRect(
      image,
      x1: 0,
      y1: 240,
      x2: 280,
      y2: image.height - 1,
      color: img.ColorRgba8(12, 18, 27, 235),
    );
    img.fillRect(
      image,
      x1: image.width - 210,
      y1: 155,
      x2: image.width - 1,
      y2: 1040,
      color: img.ColorRgba8(58, 63, 74, 180),
    );
    img.fillRect(
      image,
      x1: 320,
      y1: 710,
      x2: 710,
      y2: 1170,
      color: img.ColorRgba8(22, 29, 42, 140),
    );

    final pngBytes = Uint8List.fromList(img.encodePng(image));
    final codec = await ui.instantiateImageCodec(pngBytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  static Future<ui.Image> _loadAssetImage(String assetPath) {
    return _assetImageCache.putIfAbsent(assetPath, () async {
      final byteData = await rootBundle.load(assetPath);
      final codec = await ui.instantiateImageCodec(
        byteData.buffer.asUint8List(),
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    });
  }

  static Future<void> _ensureFontsLoaded() {
    return _fontLoadFuture ??= _loadFonts();
  }

  static Future<void> _loadFonts() async {
    await Future.wait(<Future<void>>[
      _loadFont('BebasDaka', _bebasFontAsset),
      _loadFont('HYQiHei', _heiFontAsset),
      _loadFont('PTMonoBold', _monoFontAsset),
    ]);
  }

  static Future<void> _loadFont(String family, String assetPath) async {
    final loader = FontLoader(family);
    loader.addFont(rootBundle.load(assetPath));
    await loader.load();
  }

  static TextPainter _createTextPainter({
    required String text,
    required double maxWidth,
    required TextStyle style,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    return painter;
  }

  static _ImprintParts _parseImprintParts(String rawValue) {
    final trimmedValue = rawValue.trim();
    if (trimmedValue.isEmpty) {
      return const _ImprintParts(prefix: '');
    }

    final pipeIndex = trimmedValue.indexOf('|');
    if (pipeIndex > 0 && pipeIndex < trimmedValue.length - 1) {
      return _ImprintParts(
        prefix: trimmedValue.substring(0, pipeIndex).trim(),
        divider: 'I',
        suffix: trimmedValue.substring(pipeIndex + 1).trim(),
      );
    }

    final spacedMatch = RegExp(
      r'^(.*?)(\s+[I丨｜]\s+)(.+)$',
    ).firstMatch(trimmedValue);
    if (spacedMatch != null) {
      return _ImprintParts(
        prefix: (spacedMatch.group(1) ?? '').trim(),
        divider: (spacedMatch.group(2) ?? 'I').trim().replaceAll('|', 'I'),
        suffix: (spacedMatch.group(3) ?? '').trim(),
      );
    }

    return _ImprintParts(prefix: trimmedValue);
  }

  static TextPainter _createAntiFakeCodePainter({
    required String text,
    required double scale,
    required double spacingValue,
    required double fontSize,
  }) {
    final spacingEm = spacingValue.clamp(0.0, 100.0).toDouble() / 100.0;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'PTMonoBold',
          fontSize: fontSize,
          height: 1,
          letterSpacing: fontSize * spacingEm,
          color: Colors.white,
          shadows: <Shadow>[
            Shadow(
              color: const Color(0x66000000),
              offset: Offset(0, 0.5 * scale),
              blurRadius: 0.5 * scale,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return painter;
  }

  static double _measureRightShellWidth({
    required Watermark118Data data,
    required double scale,
  }) {
    final adjustments = data.adjustments;
    final titleWidth = _rightTitleWidth * scale * adjustments.secureTitleScale;
    final codePainter = _createAntiFakeCodePainter(
      text: data.antiFakeCode,
      scale: scale,
      spacingValue: _effectiveSecureCodeSpacingValue(data),
      fontSize: math
          .max(
            1,
            (_rightCodeFontSize +
                    (adjustments.secureCodeTextSizeDp -
                        _defaultAdjustments.secureCodeTextSizeDp)) *
                scale,
          )
          .toDouble(),
    );
    final codeBoxWidth = math
        .max(
          _rightCodeMinWidth * scale,
          (_rightCodeInsetLeft * scale) + codePainter.width,
        )
        .toDouble();
    final rowWidth = titleWidth + (_rightRowGapX * scale) + codeBoxWidth;
    return math.max(_rightShellMinWidth * scale, rowWidth).toDouble();
  }

  static void _paintStrokedGradientText(
    Canvas canvas, {
    required String text,
    required Rect rect,
    required String fontFamily,
    required double fontSize,
    required double strokeWidth,
    required double letterSpacing,
    required double verticalNudge,
    required Color startColor,
    required Color endColor,
    double glowBoost = 0,
  }) {
    final glowPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: fontSize,
          height: 1,
          letterSpacing: letterSpacing,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth + (fontSize * 0.08)
            ..strokeJoin = StrokeJoin.round
            ..color = const Color(0xB3FFFFFF)
            ..maskFilter = MaskFilter.blur(
              BlurStyle.normal,
              math.max(0.1, (fontSize * 0.12) + glowBoost),
            ),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: rect.width * 2);

    final innerGlowPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: fontSize,
          height: 1,
          letterSpacing: letterSpacing,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth + (fontSize * 0.03)
            ..strokeJoin = StrokeJoin.round
            ..color = const Color(0xF2FFFFFF)
            ..maskFilter = MaskFilter.blur(
              BlurStyle.normal,
              math.max(0.1, (fontSize * 0.06) + (glowBoost * 0.5)),
            ),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: rect.width * 2);

    final strokePainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: fontSize,
          height: 1,
          letterSpacing: letterSpacing,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth
            ..strokeJoin = StrokeJoin.round
            ..color = const Color(0xFFF7FBFF),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: rect.width * 2);

    final fillPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: fontSize,
          height: 1,
          letterSpacing: letterSpacing,
          foreground: Paint()
            ..shader = ui.Gradient.linear(
              Offset(0, rect.top),
              Offset(0, rect.bottom),
              <Color>[startColor, endColor],
            ),
          shadows: <Shadow>[
            Shadow(
              color: const Color(0x3DFFFFFF),
              offset: Offset(0, 0.35 * fontSize / 29),
              blurRadius: 0,
            ),
            Shadow(
              color: const Color(0x33122139),
              offset: Offset(0, 1.1 * fontSize / 29),
              blurRadius: 2.2 * fontSize / 29,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: rect.width * 2);

    final dx = rect.left + (rect.width - fillPainter.width) / 2;
    final dy =
        rect.top + (rect.height - fillPainter.height) / 2 + verticalNudge;
    glowPainter.paint(canvas, Offset(dx, dy));
    innerGlowPainter.paint(canvas, Offset(dx, dy));
    strokePainter.paint(canvas, Offset(dx, dy));
    fillPainter.paint(canvas, Offset(dx, dy));
  }

  static void _drawImageBox(
    Canvas canvas,
    ui.Image image,
    Rect rect, {
    double opacity = 1,
  }) {
    final paint = Paint();
    if (opacity < 1) {
      paint.colorFilter = ui.ColorFilter.mode(
        Colors.white.withValues(alpha: opacity),
        BlendMode.modulate,
      );
    }
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      rect,
      paint,
    );
  }

  static int _lerpInt(int a, int b, double t) {
    return (a + ((b - a) * t)).round();
  }

  static double _scaledOuterDelta(
    double value,
    double defaultValue,
    double globalScale,
  ) {
    return (value - defaultValue) * globalScale;
  }

  static double _scaledInnerDelta(
    double value,
    double defaultValue,
    double scale,
  ) {
    return (value - defaultValue) * scale;
  }

  static double _effectiveSecureCodeSpacingValue(Watermark118Data data) {
    if (data.secureCodeSpacingValue != 0) {
      return data.secureCodeSpacingValue;
    }
    return data.adjustments.secureCodeSpacingValue;
  }
}
