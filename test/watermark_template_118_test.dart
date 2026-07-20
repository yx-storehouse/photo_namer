import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:photo_namer/watermark_template_118.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('118 template composer writes a jpg file', () async {
    final tempDir = await Directory.systemTemp.createTemp('watermark_118_');
    addTearDown(() => tempDir.delete(recursive: true));

    final outputPath = path.join(tempDir.path, 'output.jpg');
    final sourcePath = path.join(
      Directory.current.parent.path,
      'watermark_demo_standalone',
      'preview_118_test.png',
    );

    await WatermarkTemplate118Composer.composePhoto(
      sourcePath: sourcePath,
      outputPath: outputPath,
      data: Watermark118Data(
        location: '杭州市萧山区 · 小诺宠物(泰悦银座店)',
        roomCode: 'pk01',
        weatherText: WatermarkTemplate118Composer.defaultWeatherText,
        captureTime: DateTime(2026, 3, 12, 17, 37),
        imprintText: WatermarkTemplate118Composer.defaultImprintText,
        antiFakeCode: '12345678901234',
      ),
    );

    final outputFile = File(outputPath);
    expect(await outputFile.exists(), isTrue);
    expect(await outputFile.length(), greaterThan(0));
  });

  test('raw anti-fake generator returns 14 alpha-numeric chars', () {
    final code = WatermarkTemplate118Composer.generateRawAntiFakeCode(
      random: _SequenceRandom(),
    );

    expect(code, matches(r'^[0-9A-Z]{14}$'));
    expect(code, '0123456789ABCD');
  });

  test('anti-fake code generator matches original 14-char format', () {
    final code = WatermarkTemplate118Composer.generateAntiFakeCode(
      random: _SequenceRandom(),
    );

    expect(code, matches(r'^[0-9A-Z]{14}$'));
    expect(code, '0123456789ABCD');
  });

  test('blank anti-fake code falls back to generated value', () {
    final code = WatermarkTemplate118Composer.ensureAntiFakeCode(
      '   ',
      random: _SequenceRandom(),
    );

    expect(code, matches(r'^[0-9A-Z]{14}$'));
    expect(code, '0123456789ABCD');
  });

  test('118 preview artifact can be exported under build directory', () async {
    final outputDir = Directory(path.join(Directory.current.path, 'build'));
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }

    final outputPath = path.join(outputDir.path, 'watermark_preview_118.jpg');
    final sourcePath = await _createPreviewSource(outputDir.path);

    await WatermarkTemplate118Composer.composePhoto(
      sourcePath: sourcePath,
      outputPath: outputPath,
      data: WatermarkTemplate118Composer.buildDefaultData(
        location: '杭州市萧山区 · 小诺宠物(泰悦银座店)',
        roomCode: 'pk01',
        weatherText: '晴 11°C',
        captureTime: DateTime(2026, 3, 12, 17, 37),
        antiFakeCode: '12345678901234',
      ),
    );

    final outputFile = File(outputPath);
    expect(await outputFile.exists(), isTrue);
    expect(await outputFile.length(), greaterThan(0));
  });

  test('alignment preview can be exported from base image', () async {
    final outputDir = Directory(path.join(Directory.current.path, 'build'));
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }

    final outputPath = path.join(outputDir.path, 'alignment_preview.jpg');
    final sourcePath = path.join(
      Directory.current.parent.path,
      'watermark_demo_standalone',
      'preview_118_test.png',
    );

    await WatermarkTemplate118Composer.composePhoto(
      sourcePath: sourcePath,
      outputPath: outputPath,
      data: WatermarkTemplate118Composer.buildDefaultData(
        location: '浙江省杭州市萧山区戴村镇泰悦银座',
        roomCode: 'PK02',
        weatherText: '晴 7°C',
        captureTime: DateTime(2026, 3, 12, 22, 33),
        antiFakeCode: 'E9GT2K6NKAE232',
      ),
    );

    final outputFile = File(outputPath);
    expect(await outputFile.exists(), isTrue);
    expect(await outputFile.length(), greaterThan(0));
  });

  test('composer can export a synthetic preview image', () async {
    final outputDir = Directory(path.join(Directory.current.path, 'build'));
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }

    final outputPath = path.join(outputDir.path, 'preview_page_118.jpg');
    await WatermarkTemplate118Composer.composePreview(
      outputPath: outputPath,
      data: WatermarkTemplate118Composer.buildDefaultData(
        location: '杭州市萧山区 · 小诺宠物(泰悦银座店)',
        roomCode: 'PK01',
        weatherText: '晴 11°C',
        captureTime: DateTime(2026, 3, 12, 17, 37),
      ),
    );

    final outputFile = File(outputPath);
    expect(await outputFile.exists(), isTrue);
    expect(await outputFile.length(), greaterThan(0));
  });
}

Future<String> _createPreviewSource(String outputDirPath) async {
  final image = img.Image(width: 900, height: 1380);
  for (int y = 0; y < image.height; y++) {
    final t = y / (image.height - 1);
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
    y2: 1379,
    color: img.ColorRgba8(12, 18, 27, 235),
  );
  img.fillRect(
    image,
    x1: 690,
    y1: 155,
    x2: 899,
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

  final outputPath = path.join(outputDirPath, 'watermark_preview_source.jpg');
  await File(outputPath).writeAsBytes(img.encodeJpg(image, quality: 92));
  return outputPath;
}

int _lerpInt(int a, int b, double t) {
  return (a + ((b - a) * t)).round();
}

class _SequenceRandom implements Random {
  int _index = 0;

  @override
  bool nextBool() => nextInt(2) == 0;

  @override
  double nextDouble() => (nextInt(1000) / 1000).clamp(0, 0.999);

  @override
  int nextInt(int max) {
    final value = _index % max;
    _index++;
    return value;
  }
}
