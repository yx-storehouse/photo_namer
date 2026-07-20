
import 'package:camera/camera.dart';
import 'package:share_plus/share_plus.dart';

import 'package:photo_namer/watermark_template_118.dart';

class CameraCaptureResult {
  final XFile photo;
  final Watermark118Data watermarkData;
  final bool skipCompose;
  final bool watermarkEnabled;
  final bool preferNativeCompose;

  const CameraCaptureResult({
    required this.photo,
    required this.watermarkData,
    this.skipCompose = false,
    this.watermarkEnabled = true,
    this.preferNativeCompose = false,
  });
}

