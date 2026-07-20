import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';


class MeterOcrCameraPage extends StatefulWidget {
  final CameraDescription camera;
  final String title;
  final Rect focusRectNormalized;
  final bool isSingleLineRecognition;
  const MeterOcrCameraPage({
    super.key,
    required this.camera,
    required this.title,
    required this.focusRectNormalized,
    required this.isSingleLineRecognition,
  });

  @override
  State<MeterOcrCameraPage> createState() => _MeterOcrCameraPageState();
}

class _MeterOcrCameraPageState extends State<MeterOcrCameraPage> {
  CameraController? _controller;
  bool _isReady = false;
  FlashMode _flashMode = FlashMode.off;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.high,
      enableAudio: false,
    );
    try {
      await _controller!.initialize();
      await _controller!.setFlashMode(_flashMode);
      if (mounted) setState(() => _isReady = true);
    } catch (e) {
      debugPrint('Meter OCR camera init error: $e');
    }
  }

  Future<void> _toggleFlash() async {
    if (_controller == null) return;
    _flashMode = _flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
    try {
      await _controller!.setFlashMode(_flashMode);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Toggle flash error: $e');
    }
  }

  Future<void> _capture() async {
    if (_controller == null || !_isReady) return;
    try {
      final file = await _controller!.takePicture();
      if (!mounted) return;
      Navigator.pop(context, file);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('拍照失败: $e')));
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('识别电流 - ${widget.title}'),
        actions: [
          IconButton(
            onPressed: _toggleFlash,
            icon: Icon(
              _flashMode == FlashMode.torch ? Icons.flash_on : Icons.flash_off,
            ),
            tooltip: _flashMode == FlashMode.torch ? '闪光灯常开' : '闪光灯关闭',
          ),
        ],
      ),
      body: _isReady && _controller != null
          ? LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final h = constraints.maxHeight;
                final focusRect = widget.focusRectNormalized;
                final left = w * focusRect.left;
                final top = h * focusRect.top;
                final rectW = w * focusRect.width;
                final rectH = h * focusRect.height;

                return Stack(
                  children: [
                    Positioned.fill(child: CameraPreview(_controller!)),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(color: Colors.black38),
                      ),
                    ),
                    Positioned(
                      left: left,
                      top: top,
                      width: rectW,
                      height: rectH,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.lightGreenAccent,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          color: Colors.transparent,
                        ),
                      ),
                    ),
                    Positioned(
                      left: left + 8,
                      top: top + 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          widget.isSingleLineRecognition ? '单行识别区域' : '识别区域',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 120,
                      left: 20,
                      right: 20,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          widget.isSingleLineRecognition
                              ? '将需要识别的一行电流数据放入绿色框内，避免拍入其它数值'
                              : '将“电流 A/B/C + 单位 A”放入绿色框内，尽量只拍屏幕数据区',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                );
              },
            )
          : const Center(child: CircularProgressIndicator()),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Hero(
        tag: 'fab_main_action',
        child: FloatingActionButton.large(
          heroTag: null,
          onPressed: _isReady ? _capture : null,
          child: const Icon(Icons.camera_alt, size: 28),
        ),
      ),
    );
  }
}

