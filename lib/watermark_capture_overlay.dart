import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'watermark_template_118.dart';

class Watermark118CaptureOverlay extends StatelessWidget {
  const Watermark118CaptureOverlay({
    super.key,
    required this.data,
    this.bottomReserved = 0,
  });

  final Watermark118Data data;
  final double bottomReserved;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          if (width <= 0 || height <= 0) {
            return const SizedBox.shrink();
          }

          return _RasterizedWatermark118Overlay(
            data: data,
            logicalWidth: width,
            logicalHeight: height,
            devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
            bottomReserved: bottomReserved,
          );
        },
      ),
    );
  }
}

class _RasterizedWatermark118Overlay extends StatefulWidget {
  const _RasterizedWatermark118Overlay({
    required this.data,
    required this.logicalWidth,
    required this.logicalHeight,
    required this.devicePixelRatio,
    required this.bottomReserved,
  });

  final Watermark118Data data;
  final double logicalWidth;
  final double logicalHeight;
  final double devicePixelRatio;
  final double bottomReserved;

  @override
  State<_RasterizedWatermark118Overlay> createState() =>
      _RasterizedWatermark118OverlayState();
}

class _RasterizedWatermark118OverlayState
    extends State<_RasterizedWatermark118Overlay> {
  Uint8List? _overlayBytes;
  int _renderToken = 0;

  @override
  void initState() {
    super.initState();
    _renderOverlay();
  }

  @override
  void didUpdateWidget(covariant _RasterizedWatermark118Overlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_needsRerender(oldWidget)) {
      _renderOverlay();
    }
  }

  bool _needsRerender(_RasterizedWatermark118Overlay oldWidget) {
    return oldWidget.logicalWidth != widget.logicalWidth ||
        oldWidget.logicalHeight != widget.logicalHeight ||
        oldWidget.devicePixelRatio != widget.devicePixelRatio ||
        oldWidget.bottomReserved != widget.bottomReserved ||
        oldWidget.data.location != widget.data.location ||
        oldWidget.data.roomCode != widget.data.roomCode ||
        oldWidget.data.weatherText != widget.data.weatherText ||
        oldWidget.data.formattedTime != widget.data.formattedTime ||
        oldWidget.data.formattedDate != widget.data.formattedDate ||
        oldWidget.data.imprintText != widget.data.imprintText ||
        oldWidget.data.antiFakeCode != widget.data.antiFakeCode;
  }

  Future<void> _renderOverlay() async {
    final token = ++_renderToken;
    final pixelWidth = math.max(
      1,
      (widget.logicalWidth * widget.devicePixelRatio).round(),
    );
    final pixelHeight = math.max(
      1,
      (widget.logicalHeight * widget.devicePixelRatio).round(),
    );

    final bytes = await WatermarkTemplate118Composer.renderOverlayPngBytes(
      width: pixelWidth,
      height: pixelHeight,
      data: widget.data,
      extraBottomInsetPx: widget.bottomReserved * widget.devicePixelRatio,
    );

    if (!mounted || token != _renderToken) {
      return;
    }

    setState(() {
      _overlayBytes = bytes;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _overlayBytes;
    if (bytes == null) {
      return const SizedBox.shrink();
    }

    return Image.memory(
      bytes,
      width: widget.logicalWidth,
      height: widget.logicalHeight,
      fit: BoxFit.fill,
      gaplessPlayback: true,
      filterQuality: FilterQuality.high,
    );
  }
}
