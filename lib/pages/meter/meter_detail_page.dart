import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;

import 'package:photo_namer/models/app_enums.dart';
import 'package:photo_namer/models/meter_models.dart';
import 'package:photo_namer/pages/meter/meter_ocr_camera_page.dart';
import 'package:photo_namer/rikka_page_transitions.dart';
import 'package:photo_namer/widgets/expandable_fab.dart';

class MeterDetailPage extends StatefulWidget {
  final MeterRoom room;
  final List<CameraDescription> cameras;
  final bool defaultIncomingCabinetOnlineOcrEnabled;
  final Future<void> Function() onChanged;
  const MeterDetailPage({
    super.key,
    required this.room,
    required this.cameras,
    required this.defaultIncomingCabinetOnlineOcrEnabled,
    required this.onChanged,
  });

  @override
  State<MeterDetailPage> createState() => _MeterDetailPageState();
}

class _MeterDetailPageState extends State<MeterDetailPage> {
  final Map<String, FocusNode> _focusNodes = {};
  final Map<String, TextEditingController> _valueControllers = {};
  int _nextDeviceIndexForCurrent = 0;
  int _nextCurrentFieldIndex = 3;
  int? _activeCurrentDeviceIndex;
  int? _activeCurrentFieldIndex;
  bool _hasCurrentInputFocus = false;

  String _lastOcrRawText = '';
  List<String> _lastOcrNumbers = [];
  List<String> _lastOcrFocusLines = [];

  static const Rect _ocrFocusRectNormalized = Rect.fromLTWH(
    0.22,
    0.32,
    0.56,
    0.36,
  );
  static const Rect _singleLineOcrFocusRectNormalized = Rect.fromLTWH(
    0.12,
    0.43,
    0.76,
    0.14,
  );

  static const String _baiduApiKey = 'GOiAIygVECnMVJWnpQGcBbNs';
  static const String _baiduSecretKey = 's7nnGZ9mhNv8in2b7eyjm0g3zjrhXUqv';
  static const String _baiduMeterOcrEndpoint =
      'https://aip.baidubce.com/rest/2.0/ocr/v1/meter';

  OcrMode _ocrMode = OcrMode.local;
  bool _ocrModeManuallySelected = false;
  String? _baiduAccessToken;
  DateTime? _baiduTokenExpireAt;

  FocusNode _focusNodeFor(int deviceIndex, int fieldIndex) {
    final key = '$deviceIndex-$fieldIndex';
    return _focusNodes.putIfAbsent(key, () {
      final node = FocusNode();
      node.addListener(() {
        if (!mounted) return;
        final isCurrentField = fieldIndex >= 3 && fieldIndex <= 5;
        if (node.hasFocus && isCurrentField) {
          if (!_hasCurrentInputFocus) {
            setState(() => _hasCurrentInputFocus = true);
          }
          _activeCurrentDeviceIndex = deviceIndex;
          _activeCurrentFieldIndex = fieldIndex;
          return;
        }

        if (!node.hasFocus && isCurrentField) {
          final stillFocused = _focusNodes.entries.any((entry) {
            final parts = entry.key.split('-');
            if (parts.length != 2) return false;
            final idx = int.tryParse(parts[1]);
            if (idx == null || idx < 3 || idx > 5) return false;
            return entry.value.hasFocus;
          });
          if (_hasCurrentInputFocus != stillFocused) {
            setState(() => _hasCurrentInputFocus = stillFocused);
          }
        }
      });
      return node;
    });
  }

  TextEditingController _controllerFor(
    int deviceIndex,
    int fieldIndex,
    String value,
  ) {
    final key = '$deviceIndex-$fieldIndex';
    return _valueControllers.putIfAbsent(
      key,
      () => TextEditingController(text: value),
    );
  }

  @override
  void dispose() {
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    for (final controller in _valueControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _editRoomName() async {
    final ctrl = TextEditingController(text: widget.room.roomName);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑房间名称'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: '房间名'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ok == true) {
      setState(
        () => widget.room.roomName = ctrl.text.trim().isEmpty
            ? widget.room.roomName
            : ctrl.text.trim(),
      );
      await widget.onChanged();
    }
  }

  Future<void> _addDevice() async {
    final ctrl = TextEditingController(
      text: 'UPS-${widget.room.devices.length + 1}',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新增设备'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: '例如 UPS-3 / 进线柜-2'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (ok == true) {
      setState(
        () => widget.room.devices.add(
          MeterDevice(
            name: ctrl.text.trim().isEmpty ? '未命名设备' : ctrl.text.trim(),
          ),
        ),
      );
      await widget.onChanged();
    }
  }

  Future<void> _showDeviceSettingsDialog(int index) async {
    final device = widget.room.devices[index];
    final nameCtrl = TextEditingController(text: device.name);
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('设备设置'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: '设备名称 (UPS/进线柜)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'delete'),
            child: const Text('删除设备', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (action == 'save') {
      setState(
        () => device.name = nameCtrl.text.trim().isEmpty
            ? device.name
            : nameCtrl.text.trim(),
      );
      await widget.onChanged();
    } else if (action == 'delete') {
      setState(() => widget.room.devices.removeAt(index));
      await widget.onChanged();
    }
  }

  bool _isLikelyCurrentValue(String raw) {
    final v = double.tryParse(_normalizeOcrNumber(raw));
    if (v == null) return false;
    return v >= 0 && v <= 600;
  }

  String _normalizeOcrNumber(String raw) {
    var s = raw.trim().replaceAll(',', '.');
    if (!s.contains('.') && s.length >= 4) {
      final v = int.tryParse(s);
      if (v != null && v >= 1000 && v <= 9999) {
        s = '${s.substring(0, s.length - 1)}.${s.substring(s.length - 1)}';
      }
    }
    return s;
  }

  List<String> _numbersFromLine(String line) {
    final numberReg = RegExp(r'[-+]?\d+(?:[\.,]\d+)?');
    return numberReg
        .allMatches(line)
        .map((m) => _normalizeOcrNumber(m.group(0)!))
        .toList();
  }

  bool _isPowerFactorLike(String raw) {
    final v = double.tryParse(_normalizeOcrNumber(raw));
    if (v == null) return false;
    return v > 0 && v < 1.2;
  }

  List<String>? _pickThreeCurrentLike(List<String> source) {
    final filtered = source
        .where((n) => _isLikelyCurrentValue(n) && !_isPowerFactorLike(n))
        .toList();
    if (filtered.length >= 3) return filtered.take(3).toList();
    return null;
  }

  bool _isLikelyPhaseVoltage(String raw) {
    final v = double.tryParse(_normalizeOcrNumber(raw));
    if (v == null) return false;
    return v >= 180 && v <= 260;
  }

  List<String>? _extractByVoltageRowThenNextRow(List<String> lines) {
    for (int i = 0; i + 1 < lines.length; i++) {
      final row = _numbersFromLine(lines[i]);
      final next = _numbersFromLine(lines[i + 1]);
      if (row.length < 3 || next.length < 3) continue;

      final voltageRow = row.take(3).every(_isLikelyPhaseVoltage);
      if (!voltageRow) continue;

      final picked = _pickThreeCurrentLike(next.take(3).toList());
      if (picked != null) {
        _lastOcrFocusLines = [lines[i], lines[i + 1]];
        return picked;
      }
    }
    return null;
  }

  List<String>? _extractByVerticalColumnsUnder220(List<String> lines) {
    final result = <String>[];
    final focus = <String>[];

    for (int i = 0; i + 1 < lines.length; i++) {
      final top = _numbersFromLine(lines[i]);
      final below = _numbersFromLine(lines[i + 1]);
      if (top.length != 1 || below.length != 1) continue;
      if (!_isLikelyPhaseVoltage(top.first)) continue;

      final vBelow = double.tryParse(_normalizeOcrNumber(below.first));
      if (vBelow == null) continue;
      if (vBelow <= 1.2 || vBelow > 600) continue;

      result.add(_normalizeOcrNumber(below.first));
      focus.add(lines[i]);
      focus.add(lines[i + 1]);
      if (result.length >= 3) {
        _lastOcrFocusLines = focus;
        return result.take(3).toList();
      }
    }

    return null;
  }

  List<String> _extractIncomingCabinetCurrentCandidates(String text) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    _lastOcrFocusLines = [];

    final skipKeyword = RegExp(
      r'(打卡|今日水印|时间地点|杭州|中国电信|PD\d+|低压进线柜|A\s*$)',
      caseSensitive: false,
    );

    // 进线柜数字表：通常是 3 行单值（每行后面可能带 A），优先连续三行提取
    for (int i = 0; i + 2 < lines.length; i++) {
      final l1 = lines[i];
      final l2 = lines[i + 1];
      final l3 = lines[i + 2];
      if (skipKeyword.hasMatch(l1) ||
          skipKeyword.hasMatch(l2) ||
          skipKeyword.hasMatch(l3)) {
        continue;
      }

      final n1 = _numbersFromLine(l1);
      final n2 = _numbersFromLine(l2);
      final n3 = _numbersFromLine(l3);
      if (n1.length != 1 || n2.length != 1 || n3.length != 1) continue;

      final triple = [n1.first, n2.first, n3.first];
      if (triple.every((n) {
        final v = double.tryParse(n);
        return v != null && v > 1.2 && v <= 9999;
      })) {
        _lastOcrFocusLines = [l1, l2, l3];
        return triple;
      }
    }

    // 保底：从全部数字中取最后 3 个像电流的值
    final all = _numbersFromLine(text).where((n) {
      final v = double.tryParse(n);
      return v != null && v > 1.2 && v <= 9999;
    }).toList();

    if (all.length <= 3) return all;
    return all.sublist(all.length - 3);
  }

  List<String> _extractCurrentCandidates(String text) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    _lastOcrFocusLines = [];

    final keywordCurrent = RegExp(
      r'(电流|相电流|current|curr|\bia\b|\bib\b|\bic\b|\bi\b)',
      caseSensitive: false,
    );
    final skipKeyword = RegExp(
      r'(Hz|频率|功率因数|PF|kvar|kw|kva|负载率|有功|视在|合计|总功率)',
      caseSensitive: false,
    );

    // 1) 先按“220.*下一行就是电流”规则抽取（你最新两组日志对应这个规律）
    final byVoltageRow = _extractByVoltageRowThenNextRow(lines);
    if (byVoltageRow != null) return byVoltageRow;

    // 2) 再按“每个220下面一个值”的竖列规则抽取
    final byColumns = _extractByVerticalColumnsUnder220(lines);
    if (byColumns != null) return byColumns;

    // 3) 有标签时，按“电流”关键词附近纵向抽取
    for (int i = 0; i < lines.length; i++) {
      if (!keywordCurrent.hasMatch(lines[i])) continue;
      final pool = <String>[];
      for (int j = i; j <= i + 7 && j < lines.length; j++) {
        pool.addAll(_numbersFromLine(lines[j]));
      }
      final picked = _pickThreeCurrentLike(pool);
      if (picked != null) {
        _lastOcrFocusLines = [
          lines[i],
          for (int j = i + 1; j <= i + 4 && j < lines.length; j++) lines[j],
        ];
        return picked;
      }
    }

    // 4) 最终兜底：仅使用纵向滑窗，且跳过明显非电流行
    for (int start = 0; start < lines.length; start++) {
      final window = <String>[];
      final focus = <String>[];
      for (int j = start; j < start + 5 && j < lines.length; j++) {
        if (skipKeyword.hasMatch(lines[j])) continue;
        focus.add(lines[j]);
        window.addAll(_numbersFromLine(lines[j]));
      }
      final picked = _pickThreeCurrentLike(window);
      if (picked != null) {
        _lastOcrFocusLines = focus;
        return picked;
      }
    }

    final allNumbers = _numbersFromLine(
      text,
    ).where((n) => !_isPowerFactorLike(n)).toList();
    if (allNumbers.length <= 3) return allNumbers;
    return allNumbers.sublist(0, 3);
  }

  Future<void> _showOcrDebugDialog() async {
    if (!mounted) return;

    final numbersText = _lastOcrNumbers.isEmpty
        ? '（无）'
        : _lastOcrNumbers.join(', ');
    final focusText = _lastOcrFocusLines.isEmpty
        ? '（无）'
        : _lastOcrFocusLines.join('\n');
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('OCR 调试结果'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '识别到的全部数字：',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                SelectableText(numbersText),
                const SizedBox(height: 12),
                const Text(
                  '用于判定的关键行：',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.lightBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(focusText),
                ),
                const SizedBox(height: 12),
                const Text(
                  '原始 OCR 文本：',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    _lastOcrRawText.isEmpty ? '（无）' : _lastOcrRawText,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<String?> _buildCroppedImageFilePath(
    String originalPath,
    Rect normalizedRect,
  ) async {
    try {
      final bytes = await File(originalPath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final srcImage = frame.image;

      final width = srcImage.width.toDouble();
      final height = srcImage.height.toDouble();

      final left = (normalizedRect.left * width).clamp(0.0, width - 1);
      final top = (normalizedRect.top * height).clamp(0.0, height - 1);
      final right = (normalizedRect.right * width).clamp(left + 1, width);
      final bottom = (normalizedRect.bottom * height).clamp(top + 1, height);

      final srcRect = Rect.fromLTRB(left, top, right, bottom);
      final targetW = srcRect.width.round();
      final targetH = srcRect.height.round();

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final dstRect = Rect.fromLTWH(
        0,
        0,
        targetW.toDouble(),
        targetH.toDouble(),
      );
      canvas.drawImageRect(srcImage, srcRect, dstRect, Paint());
      final picture = recorder.endRecording();
      final cropped = await picture.toImage(targetW, targetH);
      final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return null;

      final dir = await getTemporaryDirectory();
      final outPath = path.join(
        dir.path,
        'ocr_crop_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await File(outPath).writeAsBytes(data.buffer.asUint8List(), flush: true);
      return outPath;
    } catch (e) {
      debugPrint('build crop image error: $e');
      return null;
    }
  }

  bool _containsUpsKeyword(String name) {
    return name.trim().toLowerCase().contains('ups');
  }

  bool _isIncomingCabinetDeviceAt(int deviceIndex) {
    if (deviceIndex < 0 || deviceIndex >= widget.room.devices.length) {
      return false;
    }

    final device = widget.room.devices[deviceIndex];
    final name = device.name.trim().toLowerCase();
    if (name.contains('进线柜') ||
        name.contains('incoming') ||
        name.contains('feeder')) {
      return true;
    }
    if (_containsUpsKeyword(device.name)) {
      return false;
    }

    final nonUpsDevices = widget.room.devices
        .where((entry) {
          final entryName = entry.name.trim();
          if (entryName.isEmpty) {
            return false;
          }
          return !_containsUpsKeyword(entryName);
        })
        .toList(growable: false);

    return nonUpsDevices.length >= 2 &&
        nonUpsDevices.length <= 3 &&
        nonUpsDevices.contains(device);
  }

  bool _isTransformerDeviceAt(int deviceIndex) {
    if (deviceIndex < 0 || deviceIndex >= widget.room.devices.length) {
      return false;
    }

    final device = widget.room.devices[deviceIndex];
    final source =
        '${device.name} ${widget.room.roomName} ${widget.room.roomType}'
            .toLowerCase();
    return source.contains('变压') || source.contains('transformer');
  }

  OcrMode _resolvedOcrModeForDevice(int deviceIndex) {
    if (_ocrModeManuallySelected) {
      return _ocrMode;
    }
    if (widget.defaultIncomingCabinetOnlineOcrEnabled &&
        _isIncomingCabinetDeviceAt(deviceIndex)) {
      return OcrMode.online;
    }
    return OcrMode.local;
  }

  String get _ocrModeChipLabel {
    if (!_ocrModeManuallySelected &&
        widget.defaultIncomingCabinetOnlineOcrEnabled) {
      return '自动';
    }
    return _ocrMode == OcrMode.online ? '在线' : '本地';
  }

  Future<String> _recognizeTextWithLocalOcr(
    String imagePath,
    String originalPath,
  ) async {
    final recognizerCn = TextRecognizer(script: TextRecognitionScript.chinese);
    final recognizerLatin = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final fullImage = InputImage.fromFilePath(originalPath);
      String text = '';

      try {
        final resultCn = await recognizerCn.processImage(inputImage);
        text = resultCn.text.trim();
      } catch (e) {
        debugPrint('Chinese OCR failed, fallback to latin: $e');
      }

      if (text.isEmpty) {
        final resultLatin = await recognizerLatin.processImage(inputImage);
        text = resultLatin.text;
      }

      if (text.trim().isEmpty) {
        final retryCn = await recognizerCn.processImage(fullImage);
        text = retryCn.text.trim();
      }
      if (text.trim().isEmpty) {
        final retryLatin = await recognizerLatin.processImage(fullImage);
        text = retryLatin.text;
      }

      return text.trim();
    } finally {
      recognizerCn.close();
      recognizerLatin.close();
    }
  }

  Future<String?> _ensureBaiduAccessToken() async {
    final now = DateTime.now();
    if (_baiduAccessToken != null &&
        _baiduTokenExpireAt != null &&
        now.isBefore(_baiduTokenExpireAt!)) {
      return _baiduAccessToken;
    }

    final uri = Uri.parse('https://aip.baidubce.com/oauth/2.0/token');
    final response = await http.post(
      uri,
      body: {
        'grant_type': 'client_credentials',
        'client_id': _baiduApiKey,
        'client_secret': _baiduSecretKey,
      },
    );

    if (response.statusCode != 200) {
      throw Exception('获取百度 access_token 失败(${response.statusCode})');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final token = (data['access_token'] ?? '').toString();
    if (token.isEmpty) {
      throw Exception('百度返回 access_token 为空');
    }

    final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 0;
    _baiduAccessToken = token;
    _baiduTokenExpireAt = now.add(
      Duration(seconds: expiresIn > 120 ? expiresIn - 120 : expiresIn),
    );
    return token;
  }

  Future<String> _recognizeTextWithBaiduOcr(String imagePath) async {
    final token = await _ensureBaiduAccessToken();
    if (token == null || token.isEmpty) {
      throw Exception('百度 access_token 不可用');
    }

    final bytes = await File(imagePath).readAsBytes();
    final imageBase64 = base64Encode(bytes);

    final uri = Uri.parse('$_baiduMeterOcrEndpoint?access_token=$token');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'image': imageBase64,
        'probability': 'false',
        'poly_location': 'false',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('百度仪表 OCR 请求失败(${response.statusCode})');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['error_code'] != null) {
      throw Exception(
        '百度仪表 OCR 错误: ${data['error_msg'] ?? data['error_code']}',
      );
    }

    final wordsResult = data['words_result'];
    if (wordsResult is! List) return '';

    final lines = wordsResult
        .whereType<Map>()
        .map((e) => (e['words'] ?? '').toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return lines.join('\n');
  }

  Future<void> _recognizeCurrentFromCamera(int deviceIndex) async {
    if (widget.cameras.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('未检测到相机')));
      return;
    }

    final cameraStatus = await Permission.camera.request();
    if (!cameraStatus.isGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先授予相机权限')));
      return;
    }

    final isTransformer = _isTransformerDeviceAt(deviceIndex);
    final focusRect = isTransformer
        ? _ocrFocusRectNormalized
        : _singleLineOcrFocusRectNormalized;
    if (!mounted) return;
    final XFile? photo = await Navigator.push<XFile?>(
      context,
      buildAppRoute(
        page: MeterOcrCameraPage(
          camera: widget.cameras.first,
          title: widget.room.devices[deviceIndex].name,
          focusRectNormalized: focusRect,
          isSingleLineRecognition: !isTransformer,
        ),
      ),
    );

    if (photo == null) return;

    try {
      final isIncoming = _isIncomingCabinetDeviceAt(deviceIndex);
      final resolvedMode = _resolvedOcrModeForDevice(deviceIndex);

      final croppedPath = await _buildCroppedImageFilePath(
        photo.path,
        focusRect,
      );
      final targetPath = croppedPath ?? photo.path;

      final text = resolvedMode == OcrMode.online
          ? await _recognizeTextWithBaiduOcr(targetPath)
          : await _recognizeTextWithLocalOcr(targetPath, photo.path);

      final allNumbers = RegExp(
        r'[-+]?\d+(?:[\.,]\d+)?',
      ).allMatches(text).map((m) => _normalizeOcrNumber(m.group(0)!)).toList();
      final matches = isIncoming
          ? _extractIncomingCabinetCurrentCandidates(text)
          : _extractCurrentCandidates(text);

      setState(() {
        _lastOcrRawText = text;
        _lastOcrNumbers = allNumbers;
      });

      if (matches.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('未识别到电流数值')));
        return;
      }

      final device = widget.room.devices[deviceIndex];
      for (int i = 0; i < 3 && i < matches.length; i++) {
        final value = _normalizeOcrNumber(matches[i]);
        final targetIndex = 3 + i;
        device.values[targetIndex] = value;
        _controllerFor(deviceIndex, targetIndex, value).text = value;
      }

      await widget.onChanged();
      if (!mounted) return;
      final modeLabel = resolvedMode == OcrMode.online
          ? '在线(百度仪表OCR)'
          : '本地(MLKit)';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '[$modeLabel] 识别完成，候选:${matches.join('/')}（可点右上角查看完整 OCR）',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('识别失败: $e')));
    }
  }

  void _focusNextCurrentGlobal() {
    if (widget.room.devices.isEmpty) return;

    int deviceIndex = _nextDeviceIndexForCurrent;
    int fieldIndex = _nextCurrentFieldIndex;

    if (_activeCurrentDeviceIndex != null && _activeCurrentFieldIndex != null) {
      deviceIndex = _activeCurrentDeviceIndex!;
      fieldIndex = _activeCurrentFieldIndex!;
      if (fieldIndex == 5) {
        fieldIndex = 3;
        deviceIndex = (deviceIndex + 1) % widget.room.devices.length;
      } else {
        fieldIndex += 1;
      }
    }

    if (deviceIndex >= widget.room.devices.length) {
      deviceIndex = 0;
      fieldIndex = 3;
    }

    final controller = _controllerFor(
      deviceIndex,
      fieldIndex,
      widget.room.devices[deviceIndex].values[fieldIndex],
    );
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
    FocusScope.of(context).requestFocus(_focusNodeFor(deviceIndex, fieldIndex));

    _activeCurrentDeviceIndex = deviceIndex;
    _activeCurrentFieldIndex = fieldIndex;

    if (fieldIndex == 5) {
      _nextCurrentFieldIndex = 3;
      _nextDeviceIndexForCurrent =
          (deviceIndex + 1) % widget.room.devices.length;
    } else {
      _nextCurrentFieldIndex = fieldIndex + 1;
      _nextDeviceIndexForCurrent = deviceIndex;
    }
  }

  Widget _buildValueInput({
    required String label,
    required int deviceIndex,
    required int fieldIndex,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    final focusNode = _focusNodeFor(deviceIndex, fieldIndex);
    final controller = _controllerFor(deviceIndex, fieldIndex, value);
    if (controller.text != value) {
      controller.text = value;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 6),
        TextFormField(
          focusNode: focusNode,
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          ),
          onTap: () {
            if (fieldIndex >= 3 && fieldIndex <= 5) {
              _activeCurrentDeviceIndex = deviceIndex;
              _activeCurrentFieldIndex = fieldIndex;
            }
          },
          onChanged: onChanged,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('抄表 - ${widget.room.roomName}'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'OCR 模式切换',
            onSelected: (mode) {
              if (mode == 'auto') {
                setState(() {
                  _ocrMode = OcrMode.local;
                  _ocrModeManuallySelected = false;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已切换到自动模式：进线柜默认在线 OCR，其它设备默认本地 OCR'),
                  ),
                );
                return;
              }

              final selectedMode = mode == 'online'
                  ? OcrMode.online
                  : OcrMode.local;
              setState(() {
                _ocrMode = selectedMode;
                _ocrModeManuallySelected = true;
              });
              final label = selectedMode == OcrMode.online
                  ? '在线(百度仪表 OCR)'
                  : '本地(MLKit)';
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('已切换到$label')));
            },
            itemBuilder: (_) => <PopupMenuEntry<String>>[
              if (widget.defaultIncomingCabinetOnlineOcrEnabled)
                const PopupMenuItem(value: 'auto', child: Text('自动模式 (进线柜在线)')),
              const PopupMenuItem(value: 'local', child: Text('本地模式 (MLKit)')),
              const PopupMenuItem(
                value: 'online',
                child: Text('在线模式 (百度仪表 OCR)'),
              ),
            ],
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.black12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cloud_sync_outlined, size: 18),
                  const SizedBox(width: 6),
                  Text(_ocrModeChipLabel),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: _showOcrDebugDialog,
            icon: const Icon(Icons.bug_report_outlined),
            tooltip: '查看 OCR 调试结果',
          ),
          IconButton(onPressed: _editRoomName, icon: const Icon(Icons.edit)),
        ],
      ),
      floatingActionButton: ExpandableFab(
        heroTag: 'fab_main_action',
        primaryOverrideAction: _hasCurrentInputFocus
            ? FabMenuAction(
                label: '下一个电流输入框',
                icon: Icons.arrow_downward_rounded,
                onTap: () => _focusNextCurrentGlobal(),
              )
            : null,
        actions: [
          FabMenuAction(
            label: '下一个电流输入框',
            icon: Icons.arrow_downward_rounded,
            onTap: () => _focusNextCurrentGlobal(),
          ),
          FabMenuAction(label: '新增UPS/进线柜', icon: Icons.add, onTap: _addDevice),
          FabMenuAction(
            label: 'OCR调试结果',
            icon: Icons.bug_report_outlined,
            onTap: _showOcrDebugDialog,
          ),
          FabMenuAction(
            label: '编辑房间名称',
            icon: Icons.edit,
            onTap: _editRoomName,
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView.builder(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          itemCount: widget.room.devices.length,
          itemBuilder: (context, index) {
            final device = widget.room.devices[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            device.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => _recognizeCurrentFromCamera(index),
                          icon: const Icon(Icons.document_scanner_outlined),
                          tooltip: '拍照识别电流',
                        ),
                        IconButton(
                          onPressed: () => _showDeviceSettingsDialog(index),
                          icon: const Icon(Icons.settings_outlined),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.8,
                      children: [
                        _buildValueInput(
                          label: '电压A(V)',
                          deviceIndex: index,
                          fieldIndex: 0,
                          value: device.values[0],
                          onChanged: (v) async {
                            device.values[0] = v;
                            await widget.onChanged();
                          },
                        ),
                        _buildValueInput(
                          label: '电压B(V)',
                          deviceIndex: index,
                          fieldIndex: 1,
                          value: device.values[1],
                          onChanged: (v) async {
                            device.values[1] = v;
                            await widget.onChanged();
                          },
                        ),
                        _buildValueInput(
                          label: '电压C(V)',
                          deviceIndex: index,
                          fieldIndex: 2,
                          value: device.values[2],
                          onChanged: (v) async {
                            device.values[2] = v;
                            await widget.onChanged();
                          },
                        ),
                        _buildValueInput(
                          label: '电流A(A)',
                          deviceIndex: index,
                          fieldIndex: 3,
                          value: device.values[3],
                          onChanged: (v) async {
                            device.values[3] = v;
                            await widget.onChanged();
                          },
                        ),
                        _buildValueInput(
                          label: '电流B(A)',
                          deviceIndex: index,
                          fieldIndex: 4,
                          value: device.values[4],
                          onChanged: (v) async {
                            device.values[4] = v;
                            await widget.onChanged();
                          },
                        ),
                        _buildValueInput(
                          label: '电流C(A)',
                          deviceIndex: index,
                          fieldIndex: 5,
                          value: device.values[5],
                          onChanged: (v) async {
                            device.values[5] = v;
                            await widget.onChanged();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

