import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'package:share_plus/share_plus.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter/services.dart'
    show FilteringTextInputFormatter, rootBundle;

import 'capture_location_service.dart';
import 'cloud_sync_page.dart';
import 'capture_weather_service.dart';
import 'native_watermark_camera_bridge.dart';
import 'native_watermark_camera_panel.dart';
import 'native_watermark_camera_preview.dart';
import 'raw_capture_batch_page.dart';
import 'raw_capture_material_repository.dart';
import 'rikka_page_transitions.dart';
import 'watermark_capture_overlay.dart';
import 'watermark_template_118.dart';

// -------------------- Models --------------------
class InspectionItem {
  final int id;
  String name;
  String type;
  String location;
  String serial;
  List<String> photoPaths; // 存储已拍照片路径
  bool isCompleted;

  InspectionItem({
    required this.id,
    required this.name,
    required this.type,
    required this.location,
    required this.serial,
    this.photoPaths = const [],
    this.isCompleted = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'location': location,
    'serial': serial,
    'photoPaths': photoPaths,
    'isCompleted': isCompleted,
  };

  factory InspectionItem.fromJson(Map<String, dynamic> json) => InspectionItem(
    id: json['id'],
    name: json['name'],
    type: json['type'],
    location: json['location'],
    serial: json['serial'],
    photoPaths: List<String>.from(json['photoPaths'] ?? []),
    isCompleted: json['isCompleted'] ?? false,
  );
}

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

Future<Map<String, dynamic>> _createInspectionZipInBackground(
  Map<String, dynamic> request,
) async {
  final photoPaths = List<String>.from(
    request['photoPaths'] as List<dynamic>? ?? const <dynamic>[],
  );
  final zipPath = (request['zipPath'] as String?)?.trim() ?? '';
  if (zipPath.isEmpty) {
    throw ArgumentError('zipPath is required');
  }

  final encoder = ZipFileEncoder();
  encoder.create(zipPath);

  var addedCount = 0;
  try {
    for (final photoPath in photoPaths) {
      final file = File(photoPath);
      if (!file.existsSync()) {
        continue;
      }
      encoder.addFile(file);
      addedCount++;
    }
  } finally {
    encoder.close();
  }

  return <String, dynamic>{'zipPath': zipPath, 'addedCount': addedCount};
}

enum ConflictStrategy { overwrite, increment }

enum OcrMode { local, online }

final RouteObserver<ModalRoute<void>> appRouteObserver =
    RouteObserver<ModalRoute<void>>();

const String kPrefMeterOverloadTemplatesKey = 'meter_overload_templates';
const String _bundledCloudDataAssetPath =
    'assets/cloud/photo_namer_cloud_data.json';

const List<MeterTimeSlotDefinition> kDefaultMeterTimeSlots = [
  MeterTimeSlotDefinition(label: '2点', assetPath: 'csv/2点.json'),
  MeterTimeSlotDefinition(label: '6点', assetPath: 'csv/6点.json'),
  MeterTimeSlotDefinition(label: '12点', assetPath: 'csv/12点.json'),
  MeterTimeSlotDefinition(label: '18点', assetPath: 'csv/18点.json'),
  MeterTimeSlotDefinition(label: '22点', assetPath: 'csv/22点.json'),
];

Map<String, dynamic> _stringKeyedMap(dynamic raw) {
  if (raw is! Map) {
    return <String, dynamic>{};
  }
  return <String, dynamic>{
    for (final entry in raw.entries) entry.key.toString(): entry.value,
  };
}

List<Map<String, dynamic>> _stringKeyedMapList(dynamic raw) {
  if (raw is! List) {
    return <Map<String, dynamic>>[];
  }
  return raw.whereType<Map>().map(_stringKeyedMap).toList(growable: false);
}

Map<String, int> _intMapFromJson(dynamic raw) {
  final source = _stringKeyedMap(raw);
  final result = <String, int>{};
  for (final entry in source.entries) {
    final value = entry.value is num
        ? (entry.value as num).toInt()
        : int.tryParse(entry.value.toString());
    if (value != null) {
      result[entry.key] = value;
    }
  }
  return result;
}

List<int> _intListFromJson(dynamic raw) {
  if (raw is! List) {
    return <int>[];
  }
  return raw
      .map((value) => value is num ? value.toInt() : int.tryParse('$value'))
      .whereType<int>()
      .toList(growable: false);
}

String _cloudStringDefault(
  Map<String, dynamic> source,
  String key,
  String fallback,
) {
  final value = source[key];
  return value is String ? value : fallback;
}

bool _cloudBoolDefault(Map<String, dynamic> source, String key, bool fallback) {
  final value = source[key];
  return value is bool ? value : fallback;
}

int _cloudIntDefault(Map<String, dynamic> source, String key, int fallback) {
  final value = source[key];
  return value is num ? value.toInt() : fallback;
}

double _cloudDoubleDefault(
  Map<String, dynamic> source,
  String key,
  double fallback,
) {
  final value = source[key];
  return value is num ? value.toDouble() : fallback;
}

Future<Map<String, dynamic>?> _loadBundledCloudData() async {
  try {
    final raw = await rootBundle.loadString(_bundledCloudDataAssetPath);
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('内置云配置不是对象');
    }
    return _stringKeyedMap(decoded);
  } catch (error) {
    debugPrint('Load bundled cloud defaults failed: $error');
    return null;
  }
}

List<Map<String, dynamic>> _bundledInspectionDefaults(dynamic raw) {
  return _stringKeyedMapList(raw)
      .map((item) {
        // The cloud snapshot contains device-specific photo state. Defaults start clean.
        return <String, dynamic>{
          ...item,
          'photoPaths': const <String>[],
          'isCompleted': false,
        };
      })
      .toList(growable: false);
}

class FabMenuAction {
  final String label;
  final IconData icon;
  final FutureOr<void> Function() onTap;
  final bool danger;

  const FabMenuAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.danger = false,
  });
}

class ExpandableFab extends StatefulWidget {
  final List<FabMenuAction> actions;
  final String? heroTag;
  final FabMenuAction? primaryOverrideAction;

  const ExpandableFab({
    super.key,
    required this.actions,
    this.heroTag,
    this.primaryOverrideAction,
  });

  @override
  State<ExpandableFab> createState() => _ExpandableFabState();
}

class _ExpandableFabState extends State<ExpandableFab>
    with SingleTickerProviderStateMixin, RouteAware {
  late final AnimationController _controller;
  late final Animation<double> _expand;
  ModalRoute<dynamic>? _route;

  @override
  void didUpdateWidget(covariant ExpandableFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.primaryOverrideAction != null && _controller.value > 0) {
      _controller.reverse();
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _expand = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null && route != _route) {
      if (_route != null) {
        appRouteObserver.unsubscribe(this);
      }
      _route = route;
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() {
    if (_controller.value > 0) {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    _controller.dispose();
    super.dispose();
  }

  bool get _open => _controller.value > 0.5;

  Future<void> _toggle() async {
    if (widget.primaryOverrideAction != null) {
      await widget.primaryOverrideAction!.onTap();
      return;
    }
    if (_controller.status == AnimationStatus.forward ||
        _controller.status == AnimationStatus.reverse)
      return;
    if (_open) {
      await _controller.reverse();
    } else {
      await _controller.forward();
    }
  }

  Future<void> _onActionTap(FabMenuAction action) async {
    if (_open) {
      await _controller.reverse();
    }
    await action.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final h = 86.0 + widget.actions.length * 64.0;
    final colorScheme = Theme.of(context).colorScheme;

    return TapRegion(
      onTapOutside: (_) {
        if (_controller.value > 0) {
          _controller.reverse();
        }
      },
      child: SizedBox(
        width: 238,
        height: h,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Stack(
              alignment: Alignment.bottomRight,
              children: [
                ...List.generate(widget.actions.length, (i) {
                  final action = widget.actions[i];
                  final offsetY = (i + 1) * 64.0;
                  final btnBg = action.danger
                      ? const Color(0xFFD92D20)
                      : colorScheme.primary;
                  final btnFg = action.danger
                      ? Colors.white
                      : colorScheme.onPrimary;

                  return Positioned(
                    right: 0,
                    bottom: 12 + offsetY * _expand.value,
                    child: IgnorePointer(
                      ignoring: _expand.value < 0.95,
                      child: Opacity(
                        opacity: _expand.value,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: action.danger
                                      ? const Color(0xFFFDA29B)
                                      : Colors.black12,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.2),
                                    blurRadius: 14,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Text(
                                action.label,
                                style: TextStyle(
                                  color: action.danger
                                      ? const Color(0xFFB42318)
                                      : Colors.black87,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 44,
                              height: 44,
                              child: FloatingActionButton(
                                heroTag: null,
                                mini: true,
                                backgroundColor: btnBg,
                                foregroundColor: btnFg,
                                elevation: 6,
                                highlightElevation: 10,
                                onPressed: () => _onActionTap(action),
                                child: Icon(action.icon, size: 20),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                SizedBox(
                  width: 58,
                  height: 58,
                  child: FloatingActionButton(
                    heroTag: widget.heroTag,
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    elevation: 8,
                    highlightElevation: 12,
                    onPressed: _toggle,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(scale: animation, child: child),
                      ),
                      child: widget.primaryOverrideAction != null
                          ? Icon(
                              widget.primaryOverrideAction!.icon,
                              key: const ValueKey('primary_override'),
                              size: 26,
                            )
                          : Transform.rotate(
                              key: const ValueKey('primary_plus'),
                              angle: _expand.value * 0.785398,
                              child: const Icon(Icons.add, size: 28),
                            ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class MeterDevice {
  String name;
  List<String> values;

  static List<String> defaultMeterValues() => [
    '220',
    '220',
    '220',
    '0',
    '0',
    '0',
  ];

  MeterDevice({required this.name, List<String>? values})
    : values = values ?? List<String>.from(defaultMeterValues());

  Map<String, dynamic> toJson() => {'name': name, 'values': values};

  factory MeterDevice.fromJson(Map<String, dynamic> json) => MeterDevice(
    name: json['name'] ?? '',
    values: List<String>.from(json['values'] ?? defaultMeterValues()),
  );
}

class MeterRoom {
  int roomId;
  String roomName;
  String roomType;
  String location;
  List<MeterDevice> devices;

  MeterRoom({
    required this.roomId,
    required this.roomName,
    required this.roomType,
    required this.location,
    required this.devices,
  });

  Map<String, dynamic> toJson() => {
    'roomId': roomId,
    'roomName': roomName,
    'roomType': roomType,
    'location': location,
    'devices': devices.map((e) => e.toJson()).toList(),
  };

  factory MeterRoom.fromJson(Map<String, dynamic> json) => MeterRoom(
    roomId: json['roomId'],
    roomName: json['roomName'] ?? '',
    roomType: json['roomType'] ?? '',
    location: json['location'] ?? '',
    devices: (json['devices'] as List<dynamic>? ?? [])
        .map((e) => MeterDevice.fromJson(e))
        .toList(),
  );
}

class MeterTimeSlotDefinition {
  final String label;
  final String assetPath;

  const MeterTimeSlotDefinition({required this.label, required this.assetPath});
}

class MeterTimeSlotDataset {
  final MeterTimeSlotDefinition slot;
  final String exportedAt;
  final Map<String, dynamic> rawData;
  final List<MeterRoom> rooms;

  const MeterTimeSlotDataset({
    required this.slot,
    required this.exportedAt,
    required this.rawData,
    required this.rooms,
  });

  int get roomCount => rooms.length;

  int get deviceCount =>
      rooms.fold<int>(0, (sum, room) => sum + room.devices.length);

  int get currentValueCount => rooms.fold<int>(
    0,
    (sum, room) => sum + room.devices.fold<int>(0, (acc, d) => acc + 3),
  );
}

const List<String> kInspectionCalendarWeekdayLabels = [
  '一',
  '二',
  '三',
  '四',
  '五',
  '六',
  '日',
];

int? meterTimeSlotHourFromLabel(String label) {
  final hourText = label.replaceAll('点', '').trim();
  return int.tryParse(hourText);
}

int nearestMeterTimeSlotIndex(
  DateTime now, {
  List<MeterTimeSlotDefinition> slots = kDefaultMeterTimeSlots,
}) {
  if (slots.isEmpty) {
    return 0;
  }

  final currentHourValue = now.hour + now.minute / 60.0;
  var bestIndex = 0;
  var bestDistance = double.infinity;

  for (int index = 0; index < slots.length; index++) {
    final slotHour = meterTimeSlotHourFromLabel(slots[index].label);
    if (slotHour == null) {
      continue;
    }

    final diff = (currentHourValue - slotHour).abs();
    final circularDiff = math.min(diff, 24 - diff);
    if (circularDiff < bestDistance) {
      bestDistance = circularDiff;
      bestIndex = index;
    }
  }

  return bestIndex;
}

String nearestMeterTimeSlotLabel(
  DateTime now, {
  List<MeterTimeSlotDefinition> slots = kDefaultMeterTimeSlots,
}) {
  if (slots.isEmpty) {
    return '';
  }
  return slots[nearestMeterTimeSlotIndex(now, slots: slots)].label;
}

String captureWeatherRefreshSlotKey(
  DateTime now, {
  List<MeterTimeSlotDefinition> slots = kDefaultMeterTimeSlots,
}) {
  final slotLabel = nearestMeterTimeSlotLabel(now, slots: slots).trim();
  if (slotLabel.isEmpty) {
    return '';
  }
  return '${formatInspectionCalendarDateKey(now)}|$slotLabel';
}

String formatInspectionCalendarDateKey(DateTime date) {
  final local = date.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}

DateTime? parseInspectionCalendarDateKey(String raw) {
  final parts = raw.trim().split('-');
  if (parts.length != 3) {
    return null;
  }
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) {
    return null;
  }
  return DateTime(year, month, day);
}

DateTime normalizeInspectionCalendarMonth(DateTime date) {
  final local = date.toLocal();
  return DateTime(local.year, local.month);
}

class InspectionCalendarDayRecord {
  final String dateKey;
  final Set<String> completedSlots;
  final String updatedAt;

  const InspectionCalendarDayRecord({
    required this.dateKey,
    required this.completedSlots,
    required this.updatedAt,
  });

  factory InspectionCalendarDayRecord.empty(String dateKey) {
    return InspectionCalendarDayRecord(
      dateKey: dateKey,
      completedSlots: const <String>{},
      updatedAt: '',
    );
  }

  factory InspectionCalendarDayRecord.fromJson(
    String dateKey,
    Map<String, dynamic> json,
  ) {
    final rawCompletedSlots = json['completedSlots'];
    final normalizedSlots = <String>{};
    if (rawCompletedSlots is List) {
      for (final entry in rawCompletedSlots) {
        final label = entry.toString().trim();
        if (label.isNotEmpty) {
          normalizedSlots.add(label);
        }
      }
    }
    return InspectionCalendarDayRecord(
      dateKey: dateKey,
      completedSlots: normalizedSlots,
      updatedAt: (json['updatedAt'] ?? '').toString(),
    );
  }

  int get completedCount => completedSlots.length;

  Map<String, dynamic> toJson() {
    final sortedSlots = completedSlots.toList()..sort();
    return <String, dynamic>{
      'completedSlots': sortedSlots,
      'updatedAt': updatedAt,
    };
  }

  InspectionCalendarDayRecord copyWith({
    Set<String>? completedSlots,
    String? updatedAt,
  }) {
    return InspectionCalendarDayRecord(
      dateKey: dateKey,
      completedSlots: Set<String>.from(completedSlots ?? this.completedSlots),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

Map<String, InspectionCalendarDayRecord> cloneInspectionCalendarRecords(
  Map<String, InspectionCalendarDayRecord> source,
) {
  return <String, InspectionCalendarDayRecord>{
    for (final entry in source.entries)
      entry.key: entry.value.copyWith(
        completedSlots: Set<String>.from(entry.value.completedSlots),
      ),
  };
}

Map<String, InspectionCalendarDayRecord> decodeInspectionCalendarRecords(
  String? raw,
) {
  if (raw == null || raw.trim().isEmpty) {
    return <String, InspectionCalendarDayRecord>{};
  }

  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return <String, InspectionCalendarDayRecord>{};
    }

    final normalized = <String, InspectionCalendarDayRecord>{};
    for (final entry in decoded.entries) {
      final dateKey = entry.key.toString().trim();
      final value = entry.value;
      if (dateKey.isEmpty || value is! Map) {
        continue;
      }

      final record = InspectionCalendarDayRecord.fromJson(
        dateKey,
        Map<String, dynamic>.from(
          value.map((key, dynamic value) => MapEntry(key.toString(), value)),
        ),
      );
      if (record.completedSlots.isNotEmpty) {
        normalized[dateKey] = record;
      }
    }
    return normalized;
  } catch (_) {
    return <String, InspectionCalendarDayRecord>{};
  }
}

String encodeInspectionCalendarRecords(
  Map<String, InspectionCalendarDayRecord> records,
) {
  final normalized = <String, dynamic>{};
  final sortedKeys = records.keys.toList()..sort();
  for (final key in sortedKeys) {
    final record = records[key];
    if (record == null || record.completedSlots.isEmpty) {
      continue;
    }
    normalized[key] = record.toJson();
  }
  return jsonEncode(normalized);
}

enum InspectionShiftType { morning, middle, night, rest }

const List<InspectionShiftType> kInspectionShiftCycle = [
  InspectionShiftType.morning,
  InspectionShiftType.morning,
  InspectionShiftType.middle,
  InspectionShiftType.middle,
  InspectionShiftType.night,
  InspectionShiftType.night,
  InspectionShiftType.rest,
  InspectionShiftType.rest,
];

const Map<InspectionShiftType, List<String>> kInspectionShiftRequiredSlots = {
  InspectionShiftType.morning: ['12点'],
  InspectionShiftType.middle: ['18点'],
  InspectionShiftType.night: ['22点', '2点', '6点'],
  InspectionShiftType.rest: <String>[],
};

class InspectionShiftScheduleConfig {
  final String firstMorningShiftDateKey;
  final int rotationMemberCount;
  final String firstInspectionDateKey;
  final String firstInspectionSlotLabel;

  const InspectionShiftScheduleConfig({
    required this.firstMorningShiftDateKey,
    required this.rotationMemberCount,
    required this.firstInspectionDateKey,
    required this.firstInspectionSlotLabel,
  });

  factory InspectionShiftScheduleConfig.fallback() {
    final todayKey = formatInspectionCalendarDateKey(DateTime.now());
    return InspectionShiftScheduleConfig(
      firstMorningShiftDateKey: todayKey,
      rotationMemberCount: 1,
      firstInspectionDateKey: todayKey,
      firstInspectionSlotLabel: '',
    );
  }

  factory InspectionShiftScheduleConfig.fromJson(Map<String, dynamic> json) {
    final fallback = InspectionShiftScheduleConfig.fallback();
    final rawMorning = (json['firstMorningShiftDateKey'] ?? '')
        .toString()
        .trim();
    if (rawMorning.isEmpty ||
        parseInspectionCalendarDateKey(rawMorning) == null) {
      return InspectionShiftScheduleConfig.fallback();
    }

    final rawRotationCount = int.tryParse(
      (json['rotationMemberCount'] ?? '').toString().trim(),
    );
    final rotationMemberCount = math.max(1, rawRotationCount ?? 1);

    final rawInspectionDate = (json['firstInspectionDateKey'] ?? '')
        .toString()
        .trim();
    final firstInspectionDateKey =
        rawInspectionDate.isNotEmpty &&
            parseInspectionCalendarDateKey(rawInspectionDate) != null
        ? rawInspectionDate
        : fallback.firstInspectionDateKey;

    final firstInspectionSlotLabel = (json['firstInspectionSlotLabel'] ?? '')
        .toString()
        .trim();

    return InspectionShiftScheduleConfig(
      firstMorningShiftDateKey: rawMorning,
      rotationMemberCount: rotationMemberCount,
      firstInspectionDateKey: firstInspectionDateKey,
      firstInspectionSlotLabel: firstInspectionSlotLabel,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'firstMorningShiftDateKey': firstMorningShiftDateKey,
      'rotationMemberCount': rotationMemberCount,
      'firstInspectionDateKey': firstInspectionDateKey,
      'firstInspectionSlotLabel': firstInspectionSlotLabel,
    };
  }

  InspectionShiftScheduleConfig copyWith({
    String? firstMorningShiftDateKey,
    int? rotationMemberCount,
    String? firstInspectionDateKey,
    String? firstInspectionSlotLabel,
  }) {
    return InspectionShiftScheduleConfig(
      firstMorningShiftDateKey:
          firstMorningShiftDateKey ?? this.firstMorningShiftDateKey,
      rotationMemberCount: rotationMemberCount ?? this.rotationMemberCount,
      firstInspectionDateKey:
          firstInspectionDateKey ?? this.firstInspectionDateKey,
      firstInspectionSlotLabel:
          firstInspectionSlotLabel ?? this.firstInspectionSlotLabel,
    );
  }
}

InspectionShiftScheduleConfig decodeInspectionShiftScheduleConfig(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return InspectionShiftScheduleConfig.fallback();
  }

  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return InspectionShiftScheduleConfig.fallback();
    }
    return InspectionShiftScheduleConfig.fromJson(
      Map<String, dynamic>.from(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      ),
    );
  } catch (_) {
    return InspectionShiftScheduleConfig.fallback();
  }
}

String encodeInspectionShiftScheduleConfig(
  InspectionShiftScheduleConfig config,
) {
  return jsonEncode(config.toJson());
}

DateTime normalizeInspectionCalendarDate(DateTime date) {
  final local = date.toLocal();
  return DateTime(local.year, local.month, local.day);
}

InspectionShiftType inspectionShiftTypeForDate(
  DateTime date,
  InspectionShiftScheduleConfig config,
) {
  final baseDate =
      parseInspectionCalendarDateKey(config.firstMorningShiftDateKey) ??
      normalizeInspectionCalendarDate(DateTime.now());
  final normalizedDate = normalizeInspectionCalendarDate(date);
  final diffDays = normalizedDate.difference(baseDate).inDays;
  final cycleIndex =
      ((diffDays % kInspectionShiftCycle.length) +
          kInspectionShiftCycle.length) %
      kInspectionShiftCycle.length;
  return kInspectionShiftCycle[cycleIndex];
}

List<String> inspectionRequiredSlotsForShift(InspectionShiftType shiftType) {
  return List<String>.from(
    kInspectionShiftRequiredSlots[shiftType] ?? const <String>[],
  );
}

DateTime inspectionRotationStartDateForConfig(
  InspectionShiftScheduleConfig config,
) {
  return parseInspectionCalendarDateKey(config.firstInspectionDateKey) ??
      normalizeInspectionCalendarDate(DateTime.now());
}

List<String> inspectionRequiredSlotsForDate(
  DateTime date,
  InspectionShiftScheduleConfig config,
) {
  return inspectionRequiredSlotsForShift(
    inspectionShiftTypeForDate(date, config),
  );
}

String resolveInspectionRotationStartSlotLabel(
  InspectionShiftScheduleConfig config,
) {
  final startDate = inspectionRotationStartDateForConfig(config);
  final candidateSlots = inspectionRequiredSlotsForDate(startDate, config);
  if (candidateSlots.isEmpty) {
    return '';
  }

  final stored = config.firstInspectionSlotLabel.trim();
  if (stored.isNotEmpty && candidateSlots.contains(stored)) {
    return stored;
  }
  return candidateSlots.first;
}

List<String> assignedInspectionSlotsForDate(
  DateTime date,
  InspectionShiftScheduleConfig config,
) {
  final targetDate = normalizeInspectionCalendarDate(date);
  final startDate = inspectionRotationStartDateForConfig(config);
  if (targetDate.isBefore(startDate)) {
    return const <String>[];
  }

  final teamSize = math.max(1, config.rotationMemberCount);
  final startSlotLabel = resolveInspectionRotationStartSlotLabel(config);
  var rotationIndex = 0;
  final assignedSlots = <String>[];

  for (
    DateTime cursor = startDate;
    !cursor.isAfter(targetDate);
    cursor = cursor.add(const Duration(days: 1))
  ) {
    final daySlots = inspectionRequiredSlotsForDate(cursor, config);
    if (daySlots.isEmpty) {
      continue;
    }

    var effectiveSlots = daySlots;
    if (DateUtils.isSameDay(cursor, startDate)) {
      final startIndex = daySlots.indexOf(startSlotLabel);
      effectiveSlots = daySlots.sublist(startIndex >= 0 ? startIndex : 0);
    }

    for (final slot in effectiveSlots) {
      if (rotationIndex % teamSize == 0 &&
          DateUtils.isSameDay(cursor, targetDate)) {
        assignedSlots.add(slot);
      }
      rotationIndex++;
    }
  }

  return assignedSlots;
}

String matchedInspectionSlotLabelForMoment(
  DateTime moment,
  InspectionShiftScheduleConfig config,
) {
  final assignedSlots = assignedInspectionSlotsForDate(moment, config);
  if (assignedSlots.isEmpty) {
    return '';
  }

  final candidateSlots = kDefaultMeterTimeSlots
      .where((slot) => assignedSlots.contains(slot.label))
      .toList(growable: false);
  if (candidateSlots.isEmpty) {
    return assignedSlots.first;
  }
  return nearestMeterTimeSlotLabel(moment, slots: candidateSlots);
}

String inspectionShiftTypeLabel(InspectionShiftType shiftType) {
  switch (shiftType) {
    case InspectionShiftType.morning:
      return '早班';
    case InspectionShiftType.middle:
      return '中班';
    case InspectionShiftType.night:
      return '晚班';
    case InspectionShiftType.rest:
      return '休息';
  }
}

String inspectionShiftTypeShortLabel(InspectionShiftType shiftType) {
  switch (shiftType) {
    case InspectionShiftType.morning:
      return '早';
    case InspectionShiftType.middle:
      return '中';
    case InspectionShiftType.night:
      return '晚';
    case InspectionShiftType.rest:
      return '休';
  }
}

// -------------------- App --------------------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  List<CameraDescription> cameras = [];
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint('availableCameras error: $e');
  }

  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  const MyApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2563EB);
    return MaterialApp(
      title: 'photo_namer',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [appRouteObserver],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        scaffoldBackgroundColor: const Color(0xFFF6F8FC),
      ),
      onGenerateRoute: (settings) {
        return buildAppRoute<void>(
          page: HomePage(cameras: cameras),
          settings: settings,
        );
      },
    );
  }
}

// -------------------- Home Page --------------------
class _MergedGridSegment {
  final String type;
  final List<InspectionItem> items;

  const _MergedGridSegment({required this.type, required this.items});
}

class _MergedGridRow {
  final List<_MergedGridSegment> segments;

  const _MergedGridRow({required this.segments});
}

class _TypeColorTheme {
  final String id;
  final String name;
  final String description;
  final Map<String, Color> roleColors;
  final List<Color> fallbackColors;

  const _TypeColorTheme({
    required this.id,
    required this.name,
    required this.description,
    required this.roleColors,
    required this.fallbackColors,
  });
}

class HomePage extends StatefulWidget {
  final List<CameraDescription> cameras;
  const HomePage({super.key, required this.cameras});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with RouteAware, WidgetsBindingObserver {
  static const String _prefItemsKey = 'inspection_items';
  static const String _prefFolderKey = 'save_folder_name';
  static const String _prefSaveDirKey = 'save_directory_path';
  static const String _prefStrategyKey = 'conflict_strategy';
  static const String _prefSortByKey = 'sort_by';
  static const String _prefMeterRoomsKey = 'meter_rooms';
  static const String _prefPhotoToMeterQuickJumpKey =
      'photo_to_meter_quick_jump';
  static const String _prefGridColumnsKey = 'home_grid_columns';
  static const String _prefMergedLayoutEnabledKey =
      'home_merged_layout_enabled';
  static const String _prefTypeColorOverridesKey = 'home_type_color_overrides';
  static const String _prefTypeColorThemeIdKey = 'home_type_color_theme_id';
  static const String _prefMergedContentMaxHeightKey =
      'home_merged_content_max_height';
  static const String _prefRecentTypeColorsKey = 'home_recent_type_colors';
  static const String _prefMergedDeepSearchEnabledKey =
      'home_merged_deep_search_enabled';
  static const String _prefMergedUniformHeightEnabledKey =
      'home_merged_uniform_height_enabled';
  static const String _prefMergedUltraCompactEnabledKey =
      'home_merged_ultra_compact_enabled';
  static const String _prefCameraAttachDelayEnabledKey =
      'camera_attach_delay_enabled';
  static const String _prefCameraAttachDelayMsKey = 'camera_attach_delay_ms';
  static const String _prefDefaultWatermarkEnabledKey =
      'default_watermark_enabled';
  static const String _prefIncomingCabinetOnlineOcrEnabledKey =
      'incoming_cabinet_online_ocr_enabled';
  static const String _prefDefaultWatermarkLocationFallbackKey =
      'default_watermark_location_fallback';
  static const String _prefDefaultWatermarkImprintTextKey =
      'default_watermark_imprint_text';
  static const String _prefCachedCaptureWeatherTextKey =
      'cached_capture_weather_text';
  static const String _prefLastWeatherRefreshSlotKey =
      'last_weather_refresh_slot';
  static const String _prefDirectCaptureSaveDirKey =
      'direct_capture_save_directory_path';
  static const String _prefInspectionCalendarRecordsKey =
      'inspection_calendar_records';
  static const String _prefInspectionShiftScheduleConfigKey =
      'inspection_shift_schedule_config';
  static const String _defaultDirectCaptureFolderName =
      'PhotoNamer_DirectCapture';

  List<InspectionItem> _items = [];
  String _saveFolderName = 'PhotoNamer';
  String? _saveDirectoryPath;
  String? _directCaptureSaveDirectoryPath;
  ConflictStrategy _strategy = ConflictStrategy.increment;
  String _sortBy = 'serial';
  List<MeterRoom> _meterRooms = [];
  bool _photoToMeterQuickJumpEnabled = true;
  bool _mergedLayoutEnabled = true;
  bool _mergedDeepSearchEnabled = true;
  bool _mergedUniformHeightEnabled = false;
  bool _mergedUltraCompactEnabled = false;
  bool _cameraAttachDelayEnabled = true;
  bool _defaultWatermarkEnabled = true;
  bool _incomingCabinetOnlineOcrEnabled = false;
  String _defaultWatermarkLocationFallback = '';
  String _defaultWatermarkImprintText =
      WatermarkTemplate118Composer.defaultImprintText;
  String _cachedCaptureWeatherText =
      WatermarkTemplate118Composer.defaultWeatherText;
  Map<String, InspectionCalendarDayRecord> _inspectionCalendarRecords = {};
  InspectionShiftScheduleConfig _inspectionShiftScheduleConfig =
      InspectionShiftScheduleConfig.fallback();
  int _cameraAttachDelayMs = 320;
  int _gridColumns = 3;
  double _mergedContentMaxHeight = 110;
  bool _showMergedLayoutDebug = false;
  Map<String, int> _typeColorOverrides = {};
  String _typeColorThemeId = 'inspection_semantic';
  List<int> _recentTypeColors = [];

  final TextEditingController _searchCtrl = TextEditingController();
  String _floorFilter = '全部';
  int _currentTabIndex = 0; // 0: 待办, 1: 完成

  // --- Optimization Cache ---
  Map<String, List<InspectionItem>> _groupedData = {};
  List<_MergedGridRow> _mergedRows = [];
  List<String> _sortedTypes = [];
  List<String> _floorLabels = ['全部'];
  int _floorFilterPulse = 0;
  int _roomRevealPulse = 0;
  int _pendingCount = 0;
  int _completedCount = 0;
  int _pendingRawMaterialCount = 0;
  bool _isExportingZip = false;
  ModalRoute<dynamic>? _route;
  final RawCaptureMaterialRepository _rawCaptureRepository =
      RawCaptureMaterialRepository.instance;
  Future<String>? _captureWeatherWarmupFuture;
  bool _didTriggerLaunchWeatherWarmup = false;
  bool _didFinishSessionWeatherWarmup = false;
  bool _lastCaptureWeatherRefreshHadPosition = false;
  String _lastWeatherRefreshSlotKey = '';
  Timer? _weatherSlotRefreshTicker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(maybeAutoCheckCloudAppUpdateOnLaunch(context));
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null && route != _route) {
      if (_route != null) {
        appRouteObserver.unsubscribe(this);
      }
      _route = route;
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    if (_route != null) {
      appRouteObserver.unsubscribe(this);
    }
    WidgetsBinding.instance.removeObserver(this);
    _weatherSlotRefreshTicker?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void didPopNext() {
    if (!mounted) {
      return;
    }
    setState(() {
      _floorFilterPulse++;
      _roomRevealPulse++;
    });
    unawaited(_ensureCaptureWeatherWarmup());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_ensureCaptureWeatherWarmup());
    }
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final bundledCloudData = await _loadBundledCloudData();
    final bundledPreferences = _stringKeyedMap(
      bundledCloudData?['appPreferences'],
    );
    final bundledWatermarkTemplate = _stringKeyedMap(
      bundledCloudData?['watermarkTemplate'],
    );
    final bundledInspectionItems = _bundledInspectionDefaults(
      bundledCloudData?['inspectionItems'],
    );
    final bundledMeterRooms = _stringKeyedMapList(
      bundledCloudData?['meterRooms'],
    );
    final bundledOverloadTemplates = _stringKeyedMapList(
      bundledCloudData?['overloadTemplates'],
    );
    var shouldPersistBundledDefaults =
        bundledCloudData != null &&
        (!prefs.containsKey(_prefItemsKey) ||
            !prefs.containsKey(_prefMeterRoomsKey) ||
            !prefs.containsKey(kPrefMeterOverloadTemplatesKey) ||
            !prefs.containsKey(_prefFolderKey) ||
            !prefs.containsKey(_prefStrategyKey) ||
            !prefs.containsKey(_prefSortByKey) ||
            !prefs.containsKey(_prefPhotoToMeterQuickJumpKey) ||
            !prefs.containsKey(_prefMergedLayoutEnabledKey) ||
            !prefs.containsKey(_prefMergedDeepSearchEnabledKey) ||
            !prefs.containsKey(_prefMergedUniformHeightEnabledKey) ||
            !prefs.containsKey(_prefMergedUltraCompactEnabledKey) ||
            !prefs.containsKey(_prefCameraAttachDelayEnabledKey) ||
            !prefs.containsKey(_prefCameraAttachDelayMsKey) ||
            !prefs.containsKey(_prefDefaultWatermarkEnabledKey) ||
            !prefs.containsKey(_prefIncomingCabinetOnlineOcrEnabledKey) ||
            !prefs.containsKey(_prefDefaultWatermarkLocationFallbackKey) ||
            !prefs.containsKey(_prefDefaultWatermarkImprintTextKey) ||
            !prefs.containsKey(_prefCachedCaptureWeatherTextKey) ||
            !prefs.containsKey(_prefGridColumnsKey) ||
            !prefs.containsKey(_prefMergedContentMaxHeightKey) ||
            !prefs.containsKey(_prefTypeColorThemeIdKey) ||
            !prefs.containsKey(_prefTypeColorOverridesKey) ||
            !prefs.containsKey(_prefRecentTypeColorsKey));

    final bundledLocationFallback = _cloudStringDefault(
      bundledPreferences,
      'defaultWatermarkLocationFallback',
      _cloudStringDefault(
        bundledWatermarkTemplate,
        'defaultLocationFallback',
        '',
      ),
    );
    final bundledImprintText = _cloudStringDefault(
      bundledPreferences,
      'defaultWatermarkImprintText',
      _cloudStringDefault(
        bundledWatermarkTemplate,
        'defaultImprintText',
        WatermarkTemplate118Composer.defaultImprintText,
      ),
    );
    final bundledWeatherText = _cloudStringDefault(
      bundledWatermarkTemplate,
      'defaultWeatherText',
      WatermarkTemplate118Composer.defaultWeatherText,
    );

    _saveFolderName =
        prefs.getString(_prefFolderKey) ??
        _cloudStringDefault(bundledPreferences, 'saveFolderName', 'PhotoNamer');
    _saveDirectoryPath = prefs.getString(_prefSaveDirKey);
    _directCaptureSaveDirectoryPath = prefs.getString(
      _prefDirectCaptureSaveDirKey,
    );
    final strategyStr =
        prefs.getString(_prefStrategyKey) ??
        _cloudStringDefault(
          bundledPreferences,
          'conflictStrategy',
          'increment',
        );
    _strategy = strategyStr == 'overwrite'
        ? ConflictStrategy.overwrite
        : ConflictStrategy.increment;
    _sortBy =
        prefs.getString(_prefSortByKey) ??
        _cloudStringDefault(bundledPreferences, 'sortBy', 'serial');
    _photoToMeterQuickJumpEnabled =
        prefs.getBool(_prefPhotoToMeterQuickJumpKey) ??
        _cloudBoolDefault(
          bundledPreferences,
          'photoToMeterQuickJumpEnabled',
          true,
        );
    _mergedLayoutEnabled =
        prefs.getBool(_prefMergedLayoutEnabledKey) ??
        _cloudBoolDefault(bundledPreferences, 'mergedLayoutEnabled', true);
    _mergedDeepSearchEnabled =
        prefs.getBool(_prefMergedDeepSearchEnabledKey) ??
        _cloudBoolDefault(bundledPreferences, 'mergedDeepSearchEnabled', true);
    _mergedUniformHeightEnabled =
        prefs.getBool(_prefMergedUniformHeightEnabledKey) ??
        _cloudBoolDefault(
          bundledPreferences,
          'mergedUniformHeightEnabled',
          false,
        );
    _mergedUltraCompactEnabled =
        prefs.getBool(_prefMergedUltraCompactEnabledKey) ??
        _cloudBoolDefault(
          bundledPreferences,
          'mergedUltraCompactEnabled',
          false,
        );
    _cameraAttachDelayEnabled =
        prefs.getBool(_prefCameraAttachDelayEnabledKey) ??
        _cloudBoolDefault(bundledPreferences, 'cameraAttachDelayEnabled', true);
    _defaultWatermarkEnabled =
        prefs.getBool(_prefDefaultWatermarkEnabledKey) ??
        _cloudBoolDefault(bundledPreferences, 'defaultWatermarkEnabled', true);
    _incomingCabinetOnlineOcrEnabled =
        prefs.getBool(_prefIncomingCabinetOnlineOcrEnabledKey) ??
        _cloudBoolDefault(
          bundledPreferences,
          'incomingCabinetOnlineOcrEnabled',
          false,
        );
    _defaultWatermarkLocationFallback =
        prefs.getString(_prefDefaultWatermarkLocationFallbackKey) ??
        bundledLocationFallback;
    _defaultWatermarkImprintText =
        prefs.getString(_prefDefaultWatermarkImprintTextKey) ??
        bundledImprintText;
    _cachedCaptureWeatherText =
        prefs.getString(_prefCachedCaptureWeatherTextKey) ?? bundledWeatherText;
    _lastWeatherRefreshSlotKey =
        prefs.getString(_prefLastWeatherRefreshSlotKey) ?? '';
    _cameraAttachDelayMs =
        (prefs.getInt(_prefCameraAttachDelayMsKey) ??
                _cloudIntDefault(
                  bundledPreferences,
                  'cameraAttachDelayMs',
                  320,
                ))
            .clamp(0, 1000);
    _typeColorThemeId =
        prefs.getString(_prefTypeColorThemeIdKey) ??
        _cloudStringDefault(
          bundledPreferences,
          'typeColorThemeId',
          'inspection_semantic',
        );
    if (!_typeColorThemes.any((e) => e.id == _typeColorThemeId)) {
      _typeColorThemeId = _typeColorThemes.first.id;
    }
    final savedColumns =
        prefs.getInt(_prefGridColumnsKey) ??
        _cloudIntDefault(bundledPreferences, 'gridColumns', 3);
    _gridColumns = savedColumns.clamp(3, 6);
    final colorJson = prefs.getString(_prefTypeColorOverridesKey);
    if (colorJson != null && colorJson.isNotEmpty) {
      final decoded = jsonDecode(colorJson);
      if (decoded is Map) {
        _typeColorOverrides = _intMapFromJson(decoded);
      }
    } else if (colorJson == null) {
      _typeColorOverrides = _intMapFromJson(
        bundledPreferences['typeColorOverrides'],
      );
    }
    final recentColorsJson = prefs.getString(_prefRecentTypeColorsKey);
    if (recentColorsJson != null && recentColorsJson.isNotEmpty) {
      final decoded = jsonDecode(recentColorsJson);
      if (decoded is List) {
        _recentTypeColors = _intListFromJson(decoded);
      }
    } else if (recentColorsJson == null) {
      _recentTypeColors = _intListFromJson(
        bundledPreferences['recentTypeColors'],
      );
    }
    _mergedContentMaxHeight =
        (prefs.getDouble(_prefMergedContentMaxHeightKey) ??
                _cloudDoubleDefault(
                  bundledPreferences,
                  'mergedContentMaxHeight',
                  110,
                ))
            .clamp(36, 220)
            .toDouble();

    final String? itemsJson = prefs.getString(_prefItemsKey);
    if (itemsJson != null) {
      final List<dynamic> decoded = jsonDecode(itemsJson);
      _items = decoded.map((e) => InspectionItem.fromJson(e)).toList();
    } else {
      _items = bundledInspectionItems.isNotEmpty
          ? bundledInspectionItems
                .map(InspectionItem.fromJson)
                .toList(growable: false)
          : _defaultItemsFromDataTs();
      shouldPersistBundledDefaults = true;
    }

    _inspectionCalendarRecords = decodeInspectionCalendarRecords(
      prefs.getString(_prefInspectionCalendarRecordsKey),
    );
    _inspectionShiftScheduleConfig = decodeInspectionShiftScheduleConfig(
      prefs.getString(_prefInspectionShiftScheduleConfigKey),
    );

    final String? meterRoomsJson = prefs.getString(_prefMeterRoomsKey);
    if (meterRoomsJson != null) {
      final List<dynamic> decoded = jsonDecode(meterRoomsJson);
      _meterRooms = decoded.map((e) => MeterRoom.fromJson(e)).toList();
    } else if (bundledMeterRooms.isNotEmpty) {
      _meterRooms = bundledMeterRooms
          .map(MeterRoom.fromJson)
          .toList(growable: false);
      shouldPersistBundledDefaults = true;
    }

    if (!prefs.containsKey(kPrefMeterOverloadTemplatesKey) &&
        bundledOverloadTemplates.isNotEmpty) {
      await prefs.setString(
        kPrefMeterOverloadTemplatesKey,
        jsonEncode(bundledOverloadTemplates),
      );
      shouldPersistBundledDefaults = true;
    }

    // 安装默认模板：当不存在或为空时，自动将所有“低压配电室”加入抄表模式
    if (_meterRooms.isEmpty) {
      _meterRooms = _items
          .where((e) => e.type == '低压配电室')
          .map(_buildMeterRoomFromInspection)
          .toList();
      shouldPersistBundledDefaults = true;
    }

    if (shouldPersistBundledDefaults) {
      await _saveData();
    }

    await _rawCaptureRepository.init();
    await _refreshRawMaterialStats();
    _recalculateDisplayData();
    _startWeatherSlotRefreshTicker();
    unawaited(_warmupCaptureWeatherOnLaunch());
  }

  void _recalculateDisplayData() {
    // 1. Calculate floor labels (only once or on data change)
    final floors = <int>{};
    for (final it in _items) {
      final f = _floorFromLocation(it.location);
      if (f != null) floors.add(f);
    }
    final sortedFloors = floors.toList()..sort();
    _floorLabels = ['全部', ...sortedFloors.map((f) => '${f}层')];

    // 2. Filter by floor and search
    final q = _searchCtrl.text.trim().toLowerCase();
    final targetFloor = int.tryParse(_floorFilter.replaceAll('层', ''));

    final allFiltered = _items.where((it) {
      bool floorMatch =
          _floorFilter == '全部' ||
          _floorFromLocation(it.location) == targetFloor;
      bool searchMatch =
          q.isEmpty ||
          it.serial.toLowerCase().contains(q) ||
          it.name.toLowerCase().contains(q);
      return floorMatch && searchMatch;
    }).toList();

    _pendingCount = allFiltered.where((e) => !e.isCompleted).length;
    _completedCount = allFiltered.where((e) => e.isCompleted).length;

    // 3. Filter by tab
    var currentList = allFiltered
        .where((e) => _currentTabIndex == 0 ? !e.isCompleted : e.isCompleted)
        .toList();

    // 4. Sort
    currentList.sort((a, b) {
      if (_sortBy == 'location') return a.location.compareTo(b.location);
      if (_sortBy == 'name') return a.name.compareTo(b.name);
      return a.serial.compareTo(b.serial);
    });

    // 5. Group
    final Map<String, List<InspectionItem>> grouped = {};
    for (final it in currentList) {
      grouped.putIfAbsent(it.type, () => []).add(it);
    }

    final sortedTypes = grouped.keys.toList()..sort();
    final mergedRows = _buildMergedRows(grouped, sortedTypes, _gridColumns);

    setState(() {
      _groupedData = grouped;
      _sortedTypes = sortedTypes;
      _mergedRows = mergedRows;
    });
  }

  void _applyFloorFilter(String label) {
    if (_floorFilter == label) {
      return;
    }
    _floorFilter = label;
    _floorFilterPulse++;
    _triggerRoomReveal();
    _recalculateDisplayData();
  }

  void _switchCurrentTab(int nextTabIndex) {
    if (_currentTabIndex == nextTabIndex) {
      return;
    }
    setState(() {
      _currentTabIndex = nextTabIndex;
    });
    _triggerRoomReveal();
    _recalculateDisplayData();
  }

  void _triggerRoomReveal() {
    _roomRevealPulse++;
  }

  List<_MergedGridRow> _buildMergedRows(
    Map<String, List<InspectionItem>> grouped,
    List<String> sortedTypes,
    int columns,
  ) {
    final rows = <_MergedGridRow>[];
    if (columns <= 0) return rows;

    final progress = <String, int>{for (final t in sortedTypes) t: 0};
    int index = 0;

    while (index < sortedTypes.length) {
      final baseType = sortedTypes[index];
      final baseItems = grouped[baseType] ?? const <InspectionItem>[];
      final baseStart = progress[baseType] ?? 0;

      if (baseStart >= baseItems.length) {
        index++;
        continue;
      }

      final segments = <_MergedGridSegment>[];
      int remain = columns;
      bool stopSearch = false;

      for (
        int cursor = index;
        cursor < sortedTypes.length && !stopSearch;
        cursor++
      ) {
        final type = sortedTypes[cursor];
        final items = grouped[type] ?? const <InspectionItem>[];
        final start = progress[type] ?? 0;
        final left = items.length - start;
        if (left <= 0) continue;

        if (left > remain) {
          if (cursor == index) {
            final takeItems = items.sublist(start, start + remain);
            segments.add(_MergedGridSegment(type: type, items: takeItems));
            progress[type] = start + remain;
            stopSearch = true;
            continue;
          }
          if (!_mergedDeepSearchEnabled) {
            stopSearch = true;
          }
          continue;
        }

        final takeItems = items.sublist(start, start + left);
        segments.add(_MergedGridSegment(type: type, items: takeItems));
        progress[type] = start + left;
        remain -= left;

        if (remain == 0) {
          stopSearch = true;
        }
      }

      if (segments.isNotEmpty) {
        rows.add(_MergedGridRow(segments: segments));
      }

      final baseAfter = progress[baseType] ?? 0;
      if (baseAfter >= baseItems.length) {
        index++;
      }
    }

    return rows;
  }

  double _mergedRowButtonCapByWidth({
    required double maxWidth,
    required _MergedGridRow row,
    required double segmentGap,
    required double itemGap,
    required double segmentHorizontalPadding,
  }) {
    final segmentCount = row.segments.length;
    final totalItems = row.segments.fold<int>(
      0,
      (sum, seg) => sum + seg.items.length,
    );
    if (segmentCount <= 0 || totalItems <= 0) return 24.0;

    final totalItemGaps = row.segments.fold<int>(
      0,
      (sum, seg) => sum + math.max(0, seg.items.length - 1),
    );
    final fixedWidth =
        math.max(0, segmentCount - 1) * segmentGap +
        totalItemGaps * itemGap +
        segmentCount * segmentHorizontalPadding * 2;
    final availableForItems = maxWidth - fixedWidth;
    if (availableForItems <= 0) return 24.0;
    return (availableForItems / totalItems).clamp(24.0, 9999.0).toDouble();
  }

  double _mergedUniformButtonSize({
    required double maxWidth,
    required double slotWidth,
    required double targetButtonSize,
    required double segmentGap,
    required double itemGap,
    required double segmentHorizontalPadding,
  }) {
    double minRowCap = double.infinity;
    for (final row in _mergedRows) {
      if (row.segments.isEmpty) continue;
      final rowCap = _mergedRowButtonCapByWidth(
        maxWidth: maxWidth,
        row: row,
        segmentGap: segmentGap,
        itemGap: itemGap,
        segmentHorizontalPadding: segmentHorizontalPadding,
      );
      if (rowCap < minRowCap) {
        minRowCap = rowCap;
      }
    }
    final safeCap = minRowCap.isFinite ? minRowCap : 24.0;
    return math.min(targetButtonSize, math.min(slotWidth, safeCap));
  }

  double _mergedGroupExtraHeight({
    required bool showDebug,
    required bool showTypeLabel,
    required double topPadding,
    required double bottomPadding,
  }) {
    final titleHeight = showTypeLabel ? 18.0 : 0.0;
    final titleBottomGap = showTypeLabel ? 8.0 : 0.0;
    const debugLineHeight = 14.0;
    const debugBottomGap = 6.0;
    final debugHeight = showDebug ? (debugLineHeight + debugBottomGap) : 0.0;
    return topPadding +
        titleHeight +
        titleBottomGap +
        debugHeight +
        bottomPadding;
  }

  String _shortTypeLabel(String type) {
    final text = type.trim();
    if (text.characters.length <= 2) return text;
    return text.characters.take(2).toString();
  }

  static const String _rolePowerHigh = 'power_high';
  static const String _rolePowerLow = 'power_low';
  static const String _roleBattery = 'battery';
  static const String _roleCooling = 'cooling';
  static const String _roleNetwork = 'network';
  static const String _roleEngine = 'engine';
  static const String _roleSafety = 'safety';
  static const String _roleGeneric = 'generic';

  static const List<_TypeColorTheme> _typeColorThemes = [
    _TypeColorTheme(
      id: 'inspection_semantic',
      name: '巡检语义·柔和',
      description: '按分类语义自动配色，适合日常巡检',
      roleColors: {
        _rolePowerHigh: Color(0xFFFDE6D6),
        _rolePowerLow: Color(0xFFE7F1FF),
        _roleBattery: Color(0xFFE8F6DA),
        _roleCooling: Color(0xFFE1F7F3),
        _roleNetwork: Color(0xFFECE9FF),
        _roleEngine: Color(0xFFF8E9DE),
        _roleSafety: Color(0xFFFFE4E4),
        _roleGeneric: Color(0xFFEFF2F5),
      },
      fallbackColors: [
        Color(0xFFE7F1FF),
        Color(0xFFE1F7F3),
        Color(0xFFE8F6DA),
        Color(0xFFFDE6D6),
        Color(0xFFECE9FF),
        Color(0xFFFFE4E4),
        Color(0xFFF8E9DE),
        Color(0xFFEFF2F5),
      ],
    ),
    _TypeColorTheme(
      id: 'inspection_vivid',
      name: '巡检语义·鲜明',
      description: '同类更易区分，适合快速扫读',
      roleColors: {
        _rolePowerHigh: Color(0xFFFFD9BA),
        _rolePowerLow: Color(0xFFDDEAFF),
        _roleBattery: Color(0xFFDFF2CB),
        _roleCooling: Color(0xFFD3F2ED),
        _roleNetwork: Color(0xFFE1DAFF),
        _roleEngine: Color(0xFFF3DDC9),
        _roleSafety: Color(0xFFFFD8D8),
        _roleGeneric: Color(0xFFE6EAEE),
      },
      fallbackColors: [
        Color(0xFFDDEAFF),
        Color(0xFFD3F2ED),
        Color(0xFFDFF2CB),
        Color(0xFFFFD9BA),
        Color(0xFFE1DAFF),
        Color(0xFFFFD8D8),
        Color(0xFFF3DDC9),
        Color(0xFFE6EAEE),
      ],
    ),
    _TypeColorTheme(
      id: 'industrial_neutral',
      name: '工业中性',
      description: '低饱和稳重，久看不疲劳',
      roleColors: {
        _rolePowerHigh: Color(0xFFF4E7DA),
        _rolePowerLow: Color(0xFFE6ECF5),
        _roleBattery: Color(0xFFE6EFE1),
        _roleCooling: Color(0xFFE1EEF0),
        _roleNetwork: Color(0xFFE8E6F0),
        _roleEngine: Color(0xFFEDE3D8),
        _roleSafety: Color(0xFFF2E4E4),
        _roleGeneric: Color(0xFFE9ECEF),
      },
      fallbackColors: [
        Color(0xFFE6ECF5),
        Color(0xFFE1EEF0),
        Color(0xFFE6EFE1),
        Color(0xFFF4E7DA),
        Color(0xFFE8E6F0),
        Color(0xFFF2E4E4),
        Color(0xFFEDE3D8),
        Color(0xFFE9ECEF),
      ],
    ),
    _TypeColorTheme(
      id: 'night_soft',
      name: '夜班护眼',
      description: '对比柔和，夜间查看更舒适',
      roleColors: {
        _rolePowerHigh: Color(0xFFF0DDCF),
        _rolePowerLow: Color(0xFFD8E4F6),
        _roleBattery: Color(0xFFD8E8CD),
        _roleCooling: Color(0xFFD2E8E6),
        _roleNetwork: Color(0xFFDDD7F0),
        _roleEngine: Color(0xFFE6D8CC),
        _roleSafety: Color(0xFFF1D6D6),
        _roleGeneric: Color(0xFFE0E5EA),
      },
      fallbackColors: [
        Color(0xFFD8E4F6),
        Color(0xFFD2E8E6),
        Color(0xFFD8E8CD),
        Color(0xFFF0DDCF),
        Color(0xFFDDD7F0),
        Color(0xFFF1D6D6),
        Color(0xFFE6D8CC),
        Color(0xFFE0E5EA),
      ],
    ),
  ];

  _TypeColorTheme get _activeTypeColorTheme {
    for (final theme in _typeColorThemes) {
      if (theme.id == _typeColorThemeId) return theme;
    }
    return _typeColorThemes.first;
  }

  String _typeColorRole(String type) {
    if (type.contains('高压')) return _rolePowerHigh;
    if (type.contains('低压') ||
        type.contains('配电') ||
        type.contains('动力') ||
        type.contains('电气') ||
        type.contains('电力')) {
      return _rolePowerLow;
    }
    if (type.contains('电池') || type.contains('蓄电')) return _roleBattery;
    if (type.contains('柴油') ||
        type.contains('发电') ||
        type.contains('油机') ||
        type.contains('燃气')) {
      return _roleEngine;
    }
    if (type.contains('冷冻') ||
        type.contains('空调') ||
        type.contains('制冷') ||
        type.contains('冷却') ||
        type.contains('暖通') ||
        type.contains('风机')) {
      return _roleCooling;
    }
    if (type.contains('网络') ||
        type.contains('传输') ||
        type.contains('通信') ||
        type.contains('弱电') ||
        type.contains('机房')) {
      return _roleNetwork;
    }
    if (type.contains('消防') || type.contains('安防') || type.contains('火')) {
      return _roleSafety;
    }
    return _roleGeneric;
  }

  Color _themeColorForType(String type) {
    final theme = _activeTypeColorTheme;
    final role = _typeColorRole(type);
    final roleColor = theme.roleColors[role];
    if (roleColor != null) return roleColor;
    final idx = type.hashCode.abs() % theme.fallbackColors.length;
    return theme.fallbackColors[idx];
  }

  List<Color> get _presetTypeColors => _activeTypeColorTheme.fallbackColors;

  Color _typeBaseColor(String type) {
    final saved = _typeColorOverrides[type];
    if (saved != null) return Color(saved);
    return _themeColorForType(type);
  }

  Future<void> _applyCurrentThemeToAllTypes(StateSetter setModalState) async {
    final allTypes = _items.map((e) => e.type).toSet();
    if (allTypes.isEmpty) return;
    setState(() {
      for (final type in allTypes) {
        _typeColorOverrides[type] = _themeColorForType(type).toARGB32();
      }
    });
    setModalState(() {});
    await _saveData();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已按主题覆盖全部分类颜色')));
  }

  Future<void> _clearTypeColorOverrides(StateSetter setModalState) async {
    setState(() {
      _typeColorOverrides.clear();
    });
    setModalState(() {});
    await _saveData();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已清除手动颜色，改为跟随主题')));
  }

  void _pushRecentTypeColor(Color color) {
    final argb = color.toARGB32();
    _recentTypeColors.remove(argb);
    _recentTypeColors.insert(0, argb);
    if (_recentTypeColors.length > 8) {
      _recentTypeColors = _recentTypeColors.take(8).toList();
    }
  }

  Future<void> _pickTypeColor(String type, StateSetter setModalState) async {
    final current = _typeBaseColor(type);
    Color tempColor = current;
    bool followTheme = !_typeColorOverrides.containsKey(type);

    final picked = await showDialog<Color>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('选择 ${_shortTypeLabel(type)} 分类颜色'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ColorPicker(
                  pickerColor: tempColor,
                  onColorChanged: (c) => setDialogState(() {
                    tempColor = c;
                    followTheme = false;
                  }),
                  enableAlpha: false,
                  displayThumbColor: true,
                  pickerAreaHeightPercent: 0.75,
                  labelTypes: const [ColorLabelType.rgb],
                  paletteType: PaletteType.hsvWithHue,
                ),
                const SizedBox(height: 8),
                if (_recentTypeColors.isNotEmpty) ...[
                  const Text(
                    '最近使用颜色',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final argb in _recentTypeColors)
                        InkWell(
                          onTap: () => setDialogState(() {
                            tempColor = Color(argb);
                            followTheme = false;
                          }),
                          borderRadius: BorderRadius.circular(22),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Color(argb),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: tempColor.toARGB32() == argb
                                    ? Colors.black87
                                    : Colors.black26,
                                width: tempColor.toARGB32() == argb ? 2 : 1,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                const Text(
                  '预设颜色',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final c in _presetTypeColors)
                      InkWell(
                        onTap: () => setDialogState(() {
                          tempColor = c;
                          followTheme = false;
                        }),
                        borderRadius: BorderRadius.circular(22),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: tempColor.toARGB32() == c.toARGB32()
                                  ? Colors.black87
                                  : Colors.black26,
                              width: tempColor.toARGB32() == c.toARGB32()
                                  ? 2
                                  : 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => setDialogState(() {
                tempColor = _themeColorForType(type);
                followTheme = true;
              }),
              child: const Text('跟随主题'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, tempColor),
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );

    if (picked == null) return;
    setState(() {
      if (followTheme) {
        _typeColorOverrides.remove(type);
      } else {
        _typeColorOverrides[type] = picked.toARGB32();
        _pushRecentTypeColor(picked);
      }
    });
    setModalState(() {});
    await _saveData();
  }

  int? _floorFromLocation(String location) {
    final match = RegExp(r'^(\d+)-').firstMatch(location);
    if (match == null) return null;
    return int.tryParse(match.group(1) ?? '');
  }

  String _currentSavePathDisplay() {
    if (_saveDirectoryPath != null && _saveDirectoryPath!.trim().isNotEmpty) {
      return _saveDirectoryPath!;
    }
    return '/storage/emulated/0/$_saveFolderName';
  }

  String _currentDirectCapturePathDisplay() {
    if (_directCaptureSaveDirectoryPath != null &&
        _directCaptureSaveDirectoryPath!.trim().isNotEmpty) {
      return _directCaptureSaveDirectoryPath!;
    }
    return '/storage/emulated/0/$_defaultDirectCaptureFolderName';
  }

  String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[/:*?"<>|]'), '_');
  }

  Future<void> _pickSaveDirectory(StateSetter setModalState) async {
    try {
      final dir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择保存目录',
      );
      if (dir == null) return;
      setState(() {
        _saveDirectoryPath = dir;
      });
      setModalState(() {});
      await _saveData();
    } catch (e) {
      debugPrint('Pick directory error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('选择目录失败: $e')));
    }
  }

  Future<void> _pickDirectCaptureSaveDirectory(
    StateSetter setModalState,
  ) async {
    try {
      final dir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择直拍保存目录',
      );
      if (dir == null) return;
      setState(() {
        _directCaptureSaveDirectoryPath = dir;
      });
      setModalState(() {});
      await _saveData();
    } catch (e) {
      debugPrint('Pick direct capture directory error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('选择直拍目录失败: $e')));
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefItemsKey,
      jsonEncode(_items.map((e) => e.toJson()).toList()),
    );
    await prefs.setString(_prefFolderKey, _saveFolderName);
    if (_saveDirectoryPath != null) {
      await prefs.setString(_prefSaveDirKey, _saveDirectoryPath!);
    } else {
      await prefs.remove(_prefSaveDirKey);
    }
    if (_directCaptureSaveDirectoryPath != null) {
      await prefs.setString(
        _prefDirectCaptureSaveDirKey,
        _directCaptureSaveDirectoryPath!,
      );
    } else {
      await prefs.remove(_prefDirectCaptureSaveDirKey);
    }
    await prefs.setString(_prefStrategyKey, _strategy.name);
    await prefs.setString(_prefSortByKey, _sortBy);
    await prefs.setBool(
      _prefPhotoToMeterQuickJumpKey,
      _photoToMeterQuickJumpEnabled,
    );
    await prefs.setBool(_prefMergedLayoutEnabledKey, _mergedLayoutEnabled);
    await prefs.setBool(
      _prefMergedDeepSearchEnabledKey,
      _mergedDeepSearchEnabled,
    );
    await prefs.setBool(
      _prefMergedUniformHeightEnabledKey,
      _mergedUniformHeightEnabled,
    );
    await prefs.setBool(
      _prefMergedUltraCompactEnabledKey,
      _mergedUltraCompactEnabled,
    );
    await prefs.setBool(
      _prefCameraAttachDelayEnabledKey,
      _cameraAttachDelayEnabled,
    );
    await prefs.setBool(
      _prefDefaultWatermarkEnabledKey,
      _defaultWatermarkEnabled,
    );
    await prefs.setBool(
      _prefIncomingCabinetOnlineOcrEnabledKey,
      _incomingCabinetOnlineOcrEnabled,
    );
    await prefs.setString(
      _prefDefaultWatermarkLocationFallbackKey,
      _defaultWatermarkLocationFallback,
    );
    await prefs.setString(
      _prefDefaultWatermarkImprintTextKey,
      _defaultWatermarkImprintText,
    );
    await prefs.setInt(
      _prefCameraAttachDelayMsKey,
      _cameraAttachDelayMs.clamp(0, 1000),
    );
    await prefs.setInt(_prefGridColumnsKey, _gridColumns.clamp(3, 6));
    await prefs.setDouble(
      _prefMergedContentMaxHeightKey,
      _mergedContentMaxHeight.clamp(36, 220).toDouble(),
    );
    await prefs.setString(_prefTypeColorThemeIdKey, _typeColorThemeId);
    await prefs.setString(
      _prefTypeColorOverridesKey,
      jsonEncode(_typeColorOverrides),
    );
    await prefs.setString(
      _prefRecentTypeColorsKey,
      jsonEncode(_recentTypeColors),
    );
    await prefs.setString(
      _prefMeterRoomsKey,
      jsonEncode(_meterRooms.map((e) => e.toJson()).toList()),
    );
    await prefs.setString(
      _prefInspectionCalendarRecordsKey,
      encodeInspectionCalendarRecords(_inspectionCalendarRecords),
    );
    await prefs.setString(
      _prefInspectionShiftScheduleConfigKey,
      encodeInspectionShiftScheduleConfig(_inspectionShiftScheduleConfig),
    );
  }

  Future<List<Map<String, dynamic>>>
  _loadEffectiveOverloadTemplateEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(kPrefMeterOverloadTemplatesKey);
    if (stored != null && stored.trim().isNotEmpty) {
      final decoded = jsonDecode(stored);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map(
              (entry) => Map<String, dynamic>.from(
                entry.map((key, value) => MapEntry(key.toString(), value)),
              ),
            )
            .toList();
      }
    }

    final entries = <Map<String, dynamic>>[];
    for (final slot in kDefaultMeterTimeSlots) {
      final text = await rootBundle.loadString(slot.assetPath);
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        continue;
      }
      entries.add(<String, dynamic>{
        'label': slot.label,
        'assetPath': slot.assetPath,
        'rawData': Map<String, dynamic>.from(decoded),
      });
    }
    return entries;
  }

  Map<String, dynamic> _buildCloudSyncPreferencesPayload() {
    return <String, dynamic>{
      'sortBy': _sortBy,
      'photoToMeterQuickJumpEnabled': _photoToMeterQuickJumpEnabled,
      'mergedLayoutEnabled': _mergedLayoutEnabled,
      'mergedDeepSearchEnabled': _mergedDeepSearchEnabled,
      'mergedUniformHeightEnabled': _mergedUniformHeightEnabled,
      'mergedUltraCompactEnabled': _mergedUltraCompactEnabled,
      'cameraAttachDelayEnabled': _cameraAttachDelayEnabled,
      'cameraAttachDelayMs': _cameraAttachDelayMs,
      'defaultWatermarkEnabled': _defaultWatermarkEnabled,
      'incomingCabinetOnlineOcrEnabled': _incomingCabinetOnlineOcrEnabled,
      'defaultWatermarkLocationFallback': _defaultWatermarkLocationFallback,
      'defaultWatermarkImprintText': _defaultWatermarkImprintText,
      'gridColumns': _gridColumns,
      'mergedContentMaxHeight': _mergedContentMaxHeight,
      'typeColorThemeId': _typeColorThemeId,
      'typeColorOverrides': _typeColorOverrides,
      'recentTypeColors': _recentTypeColors,
      'saveFolderName': _saveFolderName,
      'conflictStrategy': _strategy.name,
    };
  }

  Future<Map<String, dynamic>> _buildCloudSyncBundle() async {
    final overloadTemplates = await _loadEffectiveOverloadTemplateEntries();
    return <String, dynamic>{
      'schemaVersion': 1,
      'appId': 'photo_namer',
      'exportedAt': DateTime.now().toIso8601String(),
      'inspectionItems': _items.map((item) => item.toJson()).toList(),
      'meterRooms': _meterRooms.map((room) => room.toJson()).toList(),
      'overloadTemplates': overloadTemplates,
      'appPreferences': _buildCloudSyncPreferencesPayload(),
      'watermarkTemplate': <String, dynamic>{
        'defaultWeatherText': WatermarkTemplate118Composer.defaultWeatherText,
        'defaultLocationFallback': _defaultWatermarkLocationFallback,
        'defaultImprintText': _defaultWatermarkImprintText,
        'defaultAdjustments': const Watermark118Adjustments().toMap(),
      },
    };
  }

  Future<void> _applyCloudSyncBundle(
    Map<String, dynamic> bundle,
    CloudSyncApplySelection selection,
  ) async {
    if (selection.inspectionItems) {
      final inspectionItemsRaw = bundle['inspectionItems'];
      if (inspectionItemsRaw is List) {
        _items = inspectionItemsRaw
            .whereType<Map>()
            .map(
              (entry) => InspectionItem.fromJson(
                Map<String, dynamic>.from(
                  entry.map((key, value) => MapEntry(key.toString(), value)),
                ),
              ),
            )
            .toList();
      }
    }

    if (selection.meterRooms) {
      final meterRoomsRaw = bundle['meterRooms'];
      if (meterRoomsRaw is List) {
        _meterRooms = meterRoomsRaw
            .whereType<Map>()
            .map(
              (entry) => MeterRoom.fromJson(
                Map<String, dynamic>.from(
                  entry.map((key, value) => MapEntry(key.toString(), value)),
                ),
              ),
            )
            .toList();
      }
    }

    if (selection.appPreferences) {
      final appPreferencesRaw = bundle['appPreferences'];
      if (appPreferencesRaw is Map) {
        final prefsMap = Map<String, dynamic>.from(
          appPreferencesRaw.map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        );
        final sortBy = prefsMap['sortBy'];
        if (sortBy is String && sortBy.trim().isNotEmpty) {
          _sortBy = sortBy;
        }
        final saveFolderName = prefsMap['saveFolderName'];
        if (saveFolderName is String && saveFolderName.trim().isNotEmpty) {
          _saveFolderName = saveFolderName.trim();
        }
        final conflictStrategy = prefsMap['conflictStrategy'];
        if (conflictStrategy is String && conflictStrategy == 'overwrite') {
          _strategy = ConflictStrategy.overwrite;
        } else if (conflictStrategy is String &&
            conflictStrategy == 'increment') {
          _strategy = ConflictStrategy.increment;
        }

        void readBool(String key, void Function(bool value) apply) {
          final raw = prefsMap[key];
          if (raw is bool) {
            apply(raw);
          }
        }

        void readInt(String key, void Function(int value) apply) {
          final raw = prefsMap[key];
          if (raw is num) {
            apply(raw.toInt());
          }
        }

        void readDouble(String key, void Function(double value) apply) {
          final raw = prefsMap[key];
          if (raw is num) {
            apply(raw.toDouble());
          }
        }

        readBool(
          'photoToMeterQuickJumpEnabled',
          (value) => _photoToMeterQuickJumpEnabled = value,
        );
        readBool(
          'mergedLayoutEnabled',
          (value) => _mergedLayoutEnabled = value,
        );
        readBool(
          'mergedDeepSearchEnabled',
          (value) => _mergedDeepSearchEnabled = value,
        );
        readBool(
          'mergedUniformHeightEnabled',
          (value) => _mergedUniformHeightEnabled = value,
        );
        readBool(
          'mergedUltraCompactEnabled',
          (value) => _mergedUltraCompactEnabled = value,
        );
        readBool(
          'cameraAttachDelayEnabled',
          (value) => _cameraAttachDelayEnabled = value,
        );
        readBool(
          'defaultWatermarkEnabled',
          (value) => _defaultWatermarkEnabled = value,
        );
        readBool(
          'incomingCabinetOnlineOcrEnabled',
          (value) => _incomingCabinetOnlineOcrEnabled = value,
        );
        readInt(
          'cameraAttachDelayMs',
          (value) => _cameraAttachDelayMs = value.clamp(0, 1000),
        );
        readInt('gridColumns', (value) => _gridColumns = value.clamp(3, 6));
        readDouble(
          'mergedContentMaxHeight',
          (value) => _mergedContentMaxHeight = value.clamp(36, 220).toDouble(),
        );

        final typeColorThemeId = prefsMap['typeColorThemeId'];
        if (typeColorThemeId is String &&
            _typeColorThemes.any((theme) => theme.id == typeColorThemeId)) {
          _typeColorThemeId = typeColorThemeId;
        }

        final typeColorOverrides = prefsMap['typeColorOverrides'];
        if (typeColorOverrides is Map) {
          _typeColorOverrides = typeColorOverrides.map(
            (key, value) => MapEntry(key.toString(), (value as num).toInt()),
          );
        }

        final recentTypeColors = prefsMap['recentTypeColors'];
        if (recentTypeColors is List) {
          _recentTypeColors = recentTypeColors
              .whereType<num>()
              .map((value) => value.toInt())
              .toList();
        }
      }
    }

    if (selection.watermarkTemplate) {
      final watermarkTemplateRaw = bundle['watermarkTemplate'];
      if (watermarkTemplateRaw is Map) {
        final watermarkTemplate = Map<String, dynamic>.from(
          watermarkTemplateRaw.map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        );
        final rawLocationFallback =
            watermarkTemplate['defaultLocationFallback'];
        if (rawLocationFallback is String) {
          _defaultWatermarkLocationFallback = rawLocationFallback;
        }
        final rawImprintText = watermarkTemplate['defaultImprintText'];
        if (rawImprintText is String) {
          _defaultWatermarkImprintText = rawImprintText;
        }
      }
    }

    if (selection.overloadTemplates) {
      final prefs = await SharedPreferences.getInstance();
      final overloadTemplatesRaw = bundle['overloadTemplates'];
      if (overloadTemplatesRaw is List) {
        final normalized = overloadTemplatesRaw
            .whereType<Map>()
            .map(
              (entry) => Map<String, dynamic>.from(
                entry.map((key, value) => MapEntry(key.toString(), value)),
              ),
            )
            .toList();
        await prefs.setString(
          kPrefMeterOverloadTemplatesKey,
          jsonEncode(normalized),
        );
      }
    }

    await _saveData();
    await _refreshRawMaterialStats();
    _recalculateDisplayData();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _openCloudSyncPage() async {
    await Navigator.push<void>(
      context,
      buildAppRoute(
        page: CloudSyncPage(
          buildLocalBundle: _buildCloudSyncBundle,
          applyRemoteBundle: _applyCloudSyncBundle,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _openInspectionCalendarPage() async {
    await Navigator.push<void>(
      context,
      buildAppRoute(
        page: ShiftAwareInspectionCalendarPage(
          initialRecords: _inspectionCalendarRecords,
          initialScheduleConfig: _inspectionShiftScheduleConfig,
          onRecordsChanged: _updateInspectionCalendarRecords,
          onScheduleConfigChanged: _updateInspectionShiftScheduleConfig,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  String _formatCaptureFileStamp(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final second = local.second.toString().padLeft(2, '0');
    return '${local.year}$month${day}_$hour$minute$second';
  }

  String _buildDirectCaptureFileName(
    String remark,
    DateTime captureTime,
    int index,
  ) {
    final normalizedRemark = _sanitizeFileName(
      remark.trim().replaceAll(RegExp(r'\s+'), '_'),
    );
    final prefix = normalizedRemark.isEmpty
        ? 'direct_capture'
        : normalizedRemark;
    final safePrefix = prefix.length > 24 ? prefix.substring(0, 24) : prefix;
    final sequence = (index + 1).toString().padLeft(2, '0');
    return '${safePrefix}_${_formatCaptureFileStamp(captureTime)}_$sequence.jpg';
  }

  Future<String> _saveDirectCaptureImmediately(
    CameraCaptureResult capture,
    int captureIndex,
  ) async {
    final saveDir = await _resolveDirectCaptureDirectory();
    final fileName = _buildDirectCaptureFileName(
      capture.watermarkData.roomCode,
      capture.watermarkData.captureTime,
      captureIndex,
    );
    return capture.watermarkEnabled
        ? _saveImageToDirectory(
            photo: capture.photo,
            fileName: fileName,
            watermarkData: capture.watermarkData,
            skipCompose: capture.skipCompose,
            preferNativeCompose: capture.preferNativeCompose,
            saveDir: saveDir,
          )
        : _copyPhotoToDirectory(
            photo: capture.photo,
            fileName: fileName,
            saveDir: saveDir,
          );
  }

  Future<void> _openDirectCaptureMode() async {
    if (widget.cameras.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('未检测到相机')));
      return;
    }

    if (!(await _ensurePermissions())) {
      return;
    }

    if (!mounted) {
      return;
    }

    final initialWeatherText = await _prepareInitialCaptureWeatherText();
    if (!mounted) {
      return;
    }

    final captures = await Navigator.push<List<CameraCaptureResult>?>(
      context,
      buildAppRoute(
        page: CameraPage(
          camera: widget.cameras.first,
          title: '直拍',
          captureCount: 1,
          allowContinuousCapture: true,
          roomCode: '',
          initialWatermarkLocation: _defaultWatermarkLocationFallback.trim(),
          weatherText: initialWeatherText,
          imprintText: _resolvedDefaultWatermarkImprintText(),
          enableCameraAttachDelay: _cameraAttachDelayEnabled,
          cameraAttachDelayMs: _cameraAttachDelayMs,
          initialWatermarkEnabled: _defaultWatermarkEnabled,
          onWatermarkPreferenceChanged: _setDefaultWatermarkEnabled,
          onCaptureProcessed: (capture, captureIndex) async {
            final savedPath = await _saveDirectCaptureImmediately(
              capture,
              captureIndex,
            );
            if (savedPath.isEmpty) {
              throw StateError('直拍照片保存失败');
            }
          },
        ),
      ),
    );

    if (captures == null || captures.isEmpty || !mounted) {
      return;
    }
    if (!mounted) {
      return;
    }

    final pathHint = _currentDirectCapturePathDisplay();
    final summary = '直拍本次已保存 ${captures.length} 张照片\n目录：$pathHint';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(summary), duration: const Duration(seconds: 4)),
    );
  }

  Future<void> _updateInspectionCalendarRecords(
    Map<String, InspectionCalendarDayRecord> records,
  ) async {
    final normalized = cloneInspectionCalendarRecords(records);
    if (mounted) {
      setState(() {
        _inspectionCalendarRecords = normalized;
      });
    } else {
      _inspectionCalendarRecords = normalized;
    }
    await _saveData();
  }

  Future<void> _updateInspectionShiftScheduleConfig(
    InspectionShiftScheduleConfig config,
  ) async {
    if (mounted) {
      setState(() {
        _inspectionShiftScheduleConfig = config;
      });
    } else {
      _inspectionShiftScheduleConfig = config;
    }
    await _saveData();
  }

  bool _recordInspectionActivityAt(DateTime moment) {
    final slotLabel = matchedInspectionSlotLabelForMoment(
      moment,
      _inspectionShiftScheduleConfig,
    );
    if (slotLabel.isEmpty) {
      return false;
    }

    final dateKey = formatInspectionCalendarDateKey(moment);
    final nextSlots = Set<String>.from(
      _inspectionCalendarRecords[dateKey]?.completedSlots ?? const <String>{},
    );
    if (!nextSlots.add(slotLabel)) {
      return false;
    }

    _inspectionCalendarRecords = <String, InspectionCalendarDayRecord>{
      ..._inspectionCalendarRecords,
      dateKey: InspectionCalendarDayRecord(
        dateKey: dateKey,
        completedSlots: nextSlots,
        updatedAt: moment.toIso8601String(),
      ),
    };
    return true;
  }

  Future<void> _recordInspectionActivityAndSave(DateTime moment) async {
    final changed = _recordInspectionActivityAt(moment);
    if (!changed) {
      return;
    }
    if (mounted) {
      setState(() {});
    }
    await _saveData();
  }

  Future<void> _setDefaultWatermarkEnabled(bool value) async {
    if (_defaultWatermarkEnabled != value && mounted) {
      setState(() {
        _defaultWatermarkEnabled = value;
      });
    } else {
      _defaultWatermarkEnabled = value;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefDefaultWatermarkEnabledKey, value);
  }

  String _resolvedDefaultWatermarkLocation(InspectionItem item) {
    final override = _defaultWatermarkLocationFallback.trim();
    if (override.isNotEmpty) {
      return override;
    }
    return item.location;
  }

  String _resolvedDefaultWatermarkImprintText() {
    final value = _defaultWatermarkImprintText.trim();
    if (value.isNotEmpty) {
      return value;
    }
    return WatermarkTemplate118Composer.defaultImprintText;
  }

  String _resolvedInitialWeatherText() {
    final value = _cachedCaptureWeatherText.trim();
    if (value.isNotEmpty) {
      return value;
    }
    return WatermarkTemplate118Composer.defaultWeatherText;
  }

  Future<void> _persistCachedCaptureWeatherText(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefCachedCaptureWeatherTextKey, value);
  }

  Future<void> _persistLastWeatherRefreshSlotKey(String value) async {
    _lastWeatherRefreshSlotKey = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefLastWeatherRefreshSlotKey, value);
  }

  String _currentWeatherRefreshSlotKey([DateTime? moment]) {
    return captureWeatherRefreshSlotKey(moment ?? DateTime.now());
  }

  void _startWeatherSlotRefreshTicker() {
    _weatherSlotRefreshTicker?.cancel();
    _weatherSlotRefreshTicker = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_ensureCaptureWeatherWarmup()),
    );
  }

  Future<String> _refreshCachedCaptureWeatherText() async {
    final fallbackWeatherText = _resolvedInitialWeatherText();
    final snapshot = await CaptureLocationService.resolveSnapshot(
      fallbackAddress: _defaultWatermarkLocationFallback.trim(),
    );
    _lastCaptureWeatherRefreshHadPosition = snapshot.position != null;
    final weatherText = await CaptureWeatherService.resolveCurrentWeather(
      fallbackWeatherText: fallbackWeatherText,
      position: snapshot.position,
    );
    final normalized = weatherText.trim().isNotEmpty
        ? weatherText.trim()
        : fallbackWeatherText;

    if (_cachedCaptureWeatherText != normalized) {
      if (mounted) {
        setState(() {
          _cachedCaptureWeatherText = normalized;
        });
      } else {
        _cachedCaptureWeatherText = normalized;
      }
    }
    await _persistCachedCaptureWeatherText(normalized);
    return normalized;
  }

  Future<String> _ensureCaptureWeatherWarmup({bool force = false}) {
    final slotKey = _currentWeatherRefreshSlotKey();
    if (!force &&
        _didFinishSessionWeatherWarmup &&
        slotKey.isNotEmpty &&
        _lastWeatherRefreshSlotKey == slotKey) {
      return Future<String>.value(_resolvedInitialWeatherText());
    }

    if (!_defaultWatermarkEnabled) {
      return Future<String>.value(
        WatermarkTemplate118Composer.defaultWeatherText,
      );
    }

    final existing = _captureWeatherWarmupFuture;
    if (existing != null) {
      return existing;
    }

    final future = () async {
      final status = await Permission.location.status;
      if (!status.isGranted) {
        return _resolvedInitialWeatherText();
      }
      final refreshed = await _refreshCachedCaptureWeatherText();
      if (slotKey.isNotEmpty && _lastCaptureWeatherRefreshHadPosition) {
        await _persistLastWeatherRefreshSlotKey(slotKey);
      }
      return refreshed;
    }();
    _captureWeatherWarmupFuture = future;
    future.whenComplete(() {
      _didFinishSessionWeatherWarmup = true;
      if (identical(_captureWeatherWarmupFuture, future)) {
        _captureWeatherWarmupFuture = null;
      }
    });
    return future;
  }

  Future<void> _warmupCaptureWeatherOnLaunch() async {
    if (_didTriggerLaunchWeatherWarmup || !_defaultWatermarkEnabled) {
      return;
    }
    _didTriggerLaunchWeatherWarmup = true;

    try {
      await _ensureCaptureWeatherWarmup();
    } catch (error) {
      debugPrint('launch weather warmup skipped: $error');
    }
  }

  Future<String> _prepareInitialCaptureWeatherText() async {
    if (!_defaultWatermarkEnabled) {
      return WatermarkTemplate118Composer.defaultWeatherText;
    }

    final fallback = _resolvedInitialWeatherText();
    try {
      return await _ensureCaptureWeatherWarmup().timeout(
        const Duration(seconds: 4),
        onTimeout: () => fallback,
      );
    } catch (error) {
      debugPrint('prepare initial capture weather failed: $error');
      return _resolvedInitialWeatherText();
    }
  }

  Future<void> _refreshRawMaterialStats() async {
    final pendingCount = await _rawCaptureRepository.countPendingMaterials();
    if (!mounted) {
      _pendingRawMaterialCount = pendingCount;
      return;
    }
    setState(() {
      _pendingRawMaterialCount = pendingCount;
    });
  }

  Future<void> _resetAllProgress() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重置进度'),
        content: const Text('确定要恢复所有项为待办吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    for (var it in _items) {
      it.isCompleted = false;
      it.photoPaths = [];
    }
    await _rawCaptureRepository.deleteAllMaterials();
    await _saveData();
    await _refreshRawMaterialStats();
    _recalculateDisplayData();
  }

  Future<int> _deleteItemPhotoFiles(InspectionItem item) async {
    final paths = <String>{...item.photoPaths};
    final rawMaterials = await _rawCaptureRepository.fetchMaterialsForItem(
      item.id,
    );
    for (final material in rawMaterials) {
      if (material.rawPhotoPath.trim().isNotEmpty) {
        paths.add(material.rawPhotoPath);
      }
      final composedPath = material.composedPhotoPath?.trim() ?? '';
      if (composedPath.isNotEmpty) {
        paths.add(composedPath);
      }
    }

    int removedFileCount = 0;
    for (final p in paths) {
      final file = File(p);
      if (await file.exists()) {
        try {
          await file.delete();
          removedFileCount++;
        } catch (_) {}
      }
    }
    await _rawCaptureRepository.deleteMaterialsForItem(item.id);
    return removedFileCount;
  }

  Future<void> _deleteCapturedPhotosForItem(
    InspectionItem item, {
    bool needConfirm = true,
  }) async {
    if (needConfirm) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除该房间已拍照片'),
          content: Text('将删除【${item.serial}】的已拍照片，并恢复为待办。此操作不可恢复，确定继续吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    final removedFileCount = await _deleteItemPhotoFiles(item);
    item.photoPaths = [];
    item.isCompleted = false;

    await _saveData();
    await _refreshRawMaterialStats();
    _recalculateDisplayData();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已删除【${item.serial}】照片，删除文件 $removedFileCount 张')),
    );
  }

  Future<void> _clearAllCapturedPhotos() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('一键删除全部已拍照片'),
        content: const Text('将清空所有项目的已拍照片，并尝试删除对应图片文件。此操作不可恢复，确定继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除全部'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    int removedFileCount = 0;
    for (final item in _items) {
      removedFileCount += await _deleteItemPhotoFiles(item);
      item.photoPaths = [];
      item.isCompleted = false;
    }

    await _saveData();
    await _refreshRawMaterialStats();
    _recalculateDisplayData();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已清空全部拍照记录，删除文件 $removedFileCount 张')),
    );
  }

  String _defaultMeterRoomNameTemplate(InspectionItem it) {
    // 房间级模板：默认使用“位置 + 类型 + 编号”作为抄表房间名
    final parts = <String>[];
    if (it.location.trim().isNotEmpty && it.location != '-')
      parts.add(it.location.trim());
    if (it.type.trim().isNotEmpty) parts.add(it.type.trim());
    if (it.serial.trim().isNotEmpty) parts.add(it.serial.trim());
    return parts.isEmpty ? it.name : parts.join('-');
  }

  List<MeterDevice> _defaultMeterDevicesTemplateByRoomType(String roomType) {
    // 统一设备模板：8个UPS + 2个进线柜
    return [
      MeterDevice(name: 'UPS-1'),
      MeterDevice(name: 'UPS-2'),
      MeterDevice(name: 'UPS-3'),
      MeterDevice(name: 'UPS-4'),
      MeterDevice(name: 'UPS-5'),
      MeterDevice(name: 'UPS-6'),
      MeterDevice(name: 'UPS-7'),
      MeterDevice(name: 'UPS-8'),
      MeterDevice(name: '进线柜-1'),
      MeterDevice(name: '进线柜-2'),
    ];
  }

  MeterRoom _buildMeterRoomFromInspection(InspectionItem it) {
    return MeterRoom(
      roomId: it.id,
      roomName: _defaultMeterRoomNameTemplate(it),
      roomType: it.type,
      location: it.location,
      devices: _defaultMeterDevicesTemplateByRoomType(it.type),
    );
  }

  Future<void> _openMeterFeature() async {
    final result = await Navigator.push<bool>(
      context,
      buildAppRoute(
        page: MeterRoomsPage(
          allInspectionItems: _items,
          meterRooms: _meterRooms,
          cameras: widget.cameras,
          defaultIncomingCabinetOnlineOcrEnabled:
              _incomingCabinetOnlineOcrEnabled,
          onSave: (rooms) async {
            _meterRooms = rooms;
            await _saveData();
          },
          onCreateRoomFromInspection: _buildMeterRoomFromInspection,
        ),
      ),
    );

    if (result == true && mounted) {
      setState(() {});
    }
  }

  Future<void> _quickJumpToMeterDetail(InspectionItem item) async {
    final idx = _meterRooms.indexWhere((r) => r.roomId == item.id);
    if (idx < 0) return;
    final room = _meterRooms[idx];

    await Navigator.push(
      context,
      buildAppRoute(
        page: MeterDetailPage(
          room: room,
          cameras: widget.cameras,
          defaultIncomingCabinetOnlineOcrEnabled:
              _incomingCabinetOnlineOcrEnabled,
          onChanged: () async {
            await _saveData();
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }

  Future<void> _showPhotoToMeterQuickJumpIfNeeded(InspectionItem item) async {
    if (!_photoToMeterQuickJumpEnabled) return;
    final hasMeterRoom = _meterRooms.any((r) => r.roomId == item.id);
    if (!hasMeterRoom || !mounted) return;

    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('拍照完成'),
        content: const Text('该房间已纳入动力抄表，是否立即跳转到对应房间开始抄表？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('稍后'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('立即前往'),
          ),
        ],
      ),
    );

    if (go == true && mounted) {
      await _quickJumpToMeterDetail(item);
    }
  }

  List<InspectionItem> _defaultItemsFromDataTs() {
    return [
      InspectionItem(
        id: 1,
        name: '1-1空调间PK03',
        type: '空调间',
        location: '1-1',
        serial: 'PK03',
      ),
      InspectionItem(
        id: 2,
        name: '1-1低压配电室PD01',
        type: '低压配电室',
        location: '1-1',
        serial: 'PD01',
      ),
      InspectionItem(
        id: 3,
        name: '1-1电池室PC01',
        type: '电池室',
        location: '1-1',
        serial: 'PC01',
      ),
      InspectionItem(
        id: 4,
        name: '1-1高压配电室PG01',
        type: '高压配电室',
        location: '1-1',
        serial: 'PG01',
      ),
      InspectionItem(
        id: 5,
        name: '1-2冷冻机房PK02',
        type: '冷冻机房',
        location: '1-2',
        serial: 'PK02',
      ),
      InspectionItem(
        id: 6,
        name: '1-1冷冻机房PK01',
        type: '冷冻机房',
        location: '1-1',
        serial: 'PK01',
      ),
      InspectionItem(
        id: 7,
        name: '1-2低压配电室PD02',
        type: '低压配电室',
        location: '1-2',
        serial: 'PD02',
      ),
      InspectionItem(
        id: 8,
        name: '1-2电池室PC02',
        type: '电池室',
        location: '1-2',
        serial: 'PC02',
      ),
      InspectionItem(
        id: 9,
        name: '1-2空调间PK04',
        type: '空调间',
        location: '1-2',
        serial: 'PK04',
      ),
      InspectionItem(
        id: 10,
        name: '1-3空调间PK05',
        type: '空调间',
        location: '1-3',
        serial: 'PK05',
      ),
      InspectionItem(
        id: 11,
        name: '1-3配电室PP01',
        type: '配电室',
        location: '1-3',
        serial: 'PP01',
      ),
      InspectionItem(
        id: 12,
        name: '1-4空调间PK06',
        type: '空调间',
        location: '1-4',
        serial: 'PK06',
      ),
      InspectionItem(
        id: 13,
        name: '1-4配电室PP02',
        type: '配电室',
        location: '1-4',
        serial: 'PP02',
      ),
      InspectionItem(
        id: 14,
        name: '1-5空调间PK07',
        type: '空调间',
        location: '1-5',
        serial: 'PK07',
      ),
      InspectionItem(
        id: 15,
        name: '1-6空调间PK08',
        type: '空调间',
        location: '1-6',
        serial: 'PK08',
      ),
      InspectionItem(
        id: 16,
        name: '1-2高压配电室PG02',
        type: '高压配电室',
        location: '1-2',
        serial: 'PG02',
      ),
      InspectionItem(
        id: 17,
        name: '3-1低压配电室PD05',
        type: '低压配电室',
        location: '3-1',
        serial: 'PD05',
      ),
      InspectionItem(
        id: 18,
        name: '3-1电池室PC05',
        type: '电池室',
        location: '3-1',
        serial: 'PC05',
      ),
      InspectionItem(
        id: 19,
        name: '3-1网络传输机房Z02',
        type: '网络传输机房',
        location: '3-1',
        serial: 'Z02(',
      ),
      InspectionItem(
        id: 20,
        name: '3-2低压配电室PD06',
        type: '低压配电室',
        location: '3-2',
        serial: 'PD06',
      ),
      InspectionItem(
        id: 21,
        name: '3-2电池室PC06',
        type: '电池室',
        location: '3-2',
        serial: 'PC06',
      ),
      InspectionItem(
        id: 22,
        name: '3-3机房ID07',
        type: '机房',
        location: '3-3',
        serial: 'ID07',
      ),
      InspectionItem(
        id: 23,
        name: '3-3空调间PK20',
        type: '空调间',
        location: '3-3',
        serial: 'PK20',
      ),
      InspectionItem(
        id: 24,
        name: '3-4机房ID08',
        type: '机房',
        location: '3-4',
        serial: 'ID08',
      ),
      InspectionItem(
        id: 25,
        name: '3-4空调间PK21',
        type: '空调间',
        location: '3-4',
        serial: 'PK21',
      ),
      InspectionItem(
        id: 26,
        name: '3-5空调间PK22',
        type: '空调间',
        location: '3-5',
        serial: 'PK22',
      ),
      InspectionItem(
        id: 27,
        name: '3-6空调间PK23',
        type: '空调间',
        location: '3-6',
        serial: 'PK23',
      ),
      InspectionItem(
        id: 28,
        name: '3-7空调间PK24',
        type: '空调间',
        location: '3-7',
        serial: 'PK24',
      ),
      InspectionItem(
        id: 29,
        name: '3-8空调间PK25',
        type: '空调间',
        location: '3-8',
        serial: 'PK25',
      ),
      InspectionItem(
        id: 30,
        name: '4-1空调间PK27',
        type: '空调间',
        location: '4-1',
        serial: 'PK27',
      ),
      InspectionItem(
        id: 31,
        name: '4-1低压配电室PD07',
        type: '低压配电室',
        location: '4-1',
        serial: 'PD07',
      ),
      InspectionItem(
        id: 32,
        name: '4-1电池室PC07',
        type: '电池室',
        location: '4-1',
        serial: 'PC07',
      ),
      InspectionItem(
        id: 33,
        name: '4-1网络传输机房Z03',
        type: '网络传输机房',
        location: '4-1',
        serial: 'Z03(',
      ),
      InspectionItem(
        id: 34,
        name: '4-1机房ID09',
        type: '机房',
        location: '4-1',
        serial: 'ID09',
      ),
      InspectionItem(
        id: 35,
        name: '4-2低压配电室PD08',
        type: '低压配电室',
        location: '4-2',
        serial: 'PD08',
      ),
      InspectionItem(
        id: 36,
        name: '4-2电池室PC08',
        type: '电池室',
        location: '4-2',
        serial: 'PC08',
      ),
      InspectionItem(
        id: 38,
        name: '4-5空调间PK31',
        type: '空调间',
        location: '4-5',
        serial: 'PK31',
      ),
      InspectionItem(
        id: 39,
        name: '4-6空调间PK32',
        type: '空调间',
        location: '4-6',
        serial: 'PK32',
      ),
      InspectionItem(
        id: 40,
        name: '4-7空调间PK33',
        type: '空调间',
        location: '4-7',
        serial: 'PK33',
      ),
      InspectionItem(
        id: 41,
        name: '4-8空调间PK34',
        type: '空调间',
        location: '4-8',
        serial: 'PK34',
      ),
      InspectionItem(
        id: 42,
        name: '5-1低压配电室PD09',
        type: '低压配电室',
        location: '5-1',
        serial: 'PD09',
      ),
      InspectionItem(
        id: 43,
        name: '5-1电池室PC09',
        type: '电池室',
        location: '5-1',
        serial: 'PC09',
      ),
      InspectionItem(
        id: 44,
        name: '5-1机房ID13',
        type: '机房',
        location: '5-1',
        serial: 'ID13',
      ),
      InspectionItem(
        id: 45,
        name: '5-1空调间PK36',
        type: '空调间',
        location: '5-1',
        serial: 'PK36',
      ),
      InspectionItem(
        id: 46,
        name: '5-2低压配电室PD10',
        type: '低压配电室',
        location: '5-2',
        serial: 'PD10',
      ),
      InspectionItem(
        id: 47,
        name: '5-2电池室PC10',
        type: '电池室',
        location: '5-2',
        serial: 'PC10',
      ),
      InspectionItem(
        id: 48,
        name: '5-2机房ID14',
        type: '机房',
        location: '5-2',
        serial: 'ID14',
      ),
      InspectionItem(
        id: 49,
        name: '5-2空调间PK37',
        type: '空调间',
        location: '5-2',
        serial: 'PK37',
      ),
      InspectionItem(
        id: 50,
        name: '5-3机房ID15',
        type: '机房',
        location: '5-3',
        serial: 'ID15',
      ),
      InspectionItem(
        id: 51,
        name: '5-3空调间PK38',
        type: '空调间',
        location: '5-3',
        serial: 'PK38',
      ),
      InspectionItem(
        id: 52,
        name: '5-4机房ID16',
        type: '机房',
        location: '5-4',
        serial: 'ID16',
      ),
      InspectionItem(
        id: 53,
        name: '5-4空调间PK39',
        type: '空调间',
        location: '5-4',
        serial: 'PK39',
      ),
      InspectionItem(
        id: 54,
        name: '5-5空调间PK40',
        type: '空调间',
        location: '5-5',
        serial: 'PK40',
      ),
      InspectionItem(
        id: 55,
        name: '5-6空调间PK41',
        type: '空调间',
        location: '5-6',
        serial: 'PK41',
      ),
      InspectionItem(
        id: 56,
        name: '5-7空调间PK42',
        type: '空调间',
        location: '5-7',
        serial: 'PK42',
      ),
      InspectionItem(
        id: 57,
        name: '5-8空调间PK43',
        type: '空调间',
        location: '5-8',
        serial: 'PK43',
      ),
      InspectionItem(
        id: 60,
        name: '1-1柴油机PY01',
        type: '柴油机',
        location: '1-1',
        serial: 'PY01',
      ),
      InspectionItem(
        id: 61,
        name: '4-9空调间PK35',
        type: '空调间',
        location: '4-9',
        serial: 'PK35',
      ),
      InspectionItem(
        id: 62,
        name: '3-9空调间PK26',
        type: '空调间',
        location: '3-9',
        serial: 'PK26',
      ),
    ];
  }

  List<String> _collectCompletedPhotoPaths() {
    final uniquePaths = <String>{};
    for (final item in _items) {
      if (!item.isCompleted) {
        continue;
      }
      for (final photoPath in item.photoPaths) {
        final normalized = photoPath.trim();
        if (normalized.isNotEmpty) {
          uniquePaths.add(normalized);
        }
      }
    }
    return uniquePaths.toList(growable: false);
  }

  Widget _buildZipExportProgressDialog(
    ValueListenable<String> messageListenable,
  ) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.6),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: messageListenable,
                builder: (context, message, _) {
                  return Text(message);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportZip() async {
    if (_isExportingZip) {
      return;
    }

    final photoPaths = _collectCompletedPhotoPaths();
    if (photoPaths.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前没有已拍的照片可以打包')));
      return;
    }

    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    final progressMessage = ValueNotifier<String>(
      '正在整理 ${photoPaths.length} 张照片...',
    );
    var showedProgressDialog = false;

    if (mounted) {
      setState(() {
        _isExportingZip = true;
      });
      showedProgressDialog = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _buildZipExportProgressDialog(progressMessage),
      );
      await Future<void>.delayed(const Duration(milliseconds: 32));
    } else {
      _isExportingZip = true;
    }

    try {
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final Directory tempDir = await getTemporaryDirectory();
      final String zipPath = path.join(tempDir.path, '巡检照片_$timestamp.zip');
      progressMessage.value = '正在后台压缩，请稍候...';

      final result = await compute(
        _createInspectionZipInBackground,
        <String, dynamic>{'photoPaths': photoPaths, 'zipPath': zipPath},
      );
      final addedCount = (result['addedCount'] as num?)?.toInt() ?? 0;
      if (!mounted) {
        return;
      }

      if (addedCount == 0) {
        if (showedProgressDialog) {
          rootNavigator.pop();
          showedProgressDialog = false;
        }
        messenger.showSnackBar(const SnackBar(content: Text('未找到有效的照片文件')));
        return;
      }

      await _recordInspectionActivityAndSave(DateTime.now());
      progressMessage.value = '压缩完成，正在拉起分享...';
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (showedProgressDialog) {
        rootNavigator.pop();
        showedProgressDialog = false;
      }
      await Share.shareXFiles([XFile(zipPath)], text: '巡检照片导出');
    } catch (e) {
      if (!mounted) {
        return;
      }
      if (showedProgressDialog) {
        rootNavigator.pop();
        showedProgressDialog = false;
      }
      messenger.showSnackBar(SnackBar(content: Text('打包失败: $e')));
    } finally {
      if (showedProgressDialog && rootNavigator.mounted) {
        rootNavigator.pop();
      }
      progressMessage.dispose();
      if (mounted) {
        setState(() {
          _isExportingZip = false;
        });
      } else {
        _isExportingZip = false;
      }
    }
  }

  Future<int> _androidSdkInt() async {
    if (!Platform.isAndroid) return 0;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return info.version.sdkInt;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _openAllFilesAccessSettings() async {
    if (!Platform.isAndroid) return;

    // Android 11+ 才有“所有文件访问权限”页面
    final sdkInt = await _androidSdkInt();
    if (sdkInt < 30) {
      await openAppSettings();
      return;
    }

    // 优先直达：设置 -> 特殊应用访问权限 -> 所有文件访问权限 -> 本应用
    // ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION
    // 注意：某些系统（如小米 HyperOS/MIUI）直接带 package data 可能导致设置应用崩溃
    try {
      final intent = AndroidIntent(
        action: 'android.settings.MANAGE_APP_ALL_FILES_ACCESS_PERMISSION',
        data: 'package:com.example.photo_namer',
      );
      await intent.launch();
      return;
    } catch (e) {
      debugPrint('直达授权页失败: $e');
    }

    // 退化方案 1：不带 data 启动（只到列表页），由用户手动找应用，这种方式最稳妥
    try {
      final intent = AndroidIntent(
        action: 'android.settings.MANAGE_ALL_FILES_ACCESS_PERMISSION',
      );
      await intent.launch();
      return;
    } catch (e) {
      debugPrint('跳转列表页失败: $e');
    }

    // 最后兜底：应用详情页
    await openAppSettings();
  }

  Future<bool> _ensurePermissions() async {
    final cameraStatus = await Permission.camera.request();
    if (!cameraStatus.isGranted) {
      if (mounted) _showPermissionDialog('相机', 'App需要相机权限才能拍照');
      return false;
    }

    if (Platform.isAndroid) {
      final sdkInt = await _androidSdkInt();
      if (sdkInt >= 30) {
        // Android 11 (SDK 30) 及以上使用 ManageExternalStorage
        var status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) {
          if (mounted) {
            final res = await _showPermissionDialog(
              '所有文件访问权限',
              '由于需要保存照片到根目录，请在跳转后的页面找到“photo_namer”并开启“允许访问所有文件”开关。',
            );
            if (res == true) {
              await _openAllFilesAccessSettings();
            }
          }
          return await Permission.manageExternalStorage.isGranted;
        }
      } else {
        // Android 10 及以下使用旧版存储权限
        var status = await Permission.storage.request();
        if (!status.isGranted) {
          if (mounted) _showPermissionDialog('存储权限', 'App需要存储权限才能保存照片');
          return false;
        }
      }
    }
    return true;
  }

  Future<bool?> _showPermissionDialog(String title, String content) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  Future<Directory> _resolveDirectory({
    String? directoryPath,
    required String fallbackFolderName,
  }) async {
    final saveDir = directoryPath != null && directoryPath.trim().isNotEmpty
        ? Directory(directoryPath.trim())
        : Directory(path.join('/storage/emulated/0', fallbackFolderName));
    if (!saveDir.existsSync()) {
      await saveDir.create(recursive: true);
    }
    return saveDir;
  }

  Future<Directory> _resolveSaveDirectory() async {
    return _resolveDirectory(
      directoryPath: _saveDirectoryPath,
      fallbackFolderName: _saveFolderName,
    );
  }

  Future<Directory> _resolveDirectCaptureDirectory() async {
    return _resolveDirectory(
      directoryPath: _directCaptureSaveDirectoryPath,
      fallbackFolderName: _defaultDirectCaptureFolderName,
    );
  }

  Future<Directory> _resolveRawMaterialDirectory() async {
    final saveDir = await _resolveSaveDirectory();
    final rawDir = Directory(path.join(saveDir.path, 'raw_materials'));
    if (!rawDir.existsSync()) {
      await rawDir.create(recursive: true);
    }
    return rawDir;
  }

  String _resolveOutputPath(Directory saveDir, String fileName) {
    String finalPath = path.join(saveDir.path, fileName);
    if (_strategy == ConflictStrategy.increment &&
        File(finalPath).existsSync()) {
      int idx = 1;
      final base = path.basenameWithoutExtension(fileName);
      final ext = path.extension(fileName);
      while (File(finalPath).existsSync()) {
        finalPath = path.join(saveDir.path, '${base}_$idx$ext');
        idx++;
      }
    }
    return finalPath;
  }

  Future<void> _deleteTempCaptureIfNeeded(
    String sourcePath,
    String finalPath,
  ) async {
    if (sourcePath == finalPath) {
      return;
    }
    try {
      await File(sourcePath).delete();
    } catch (_) {}
  }

  Future<String> _saveImage(
    XFile photo,
    String fileName,
    Watermark118Data watermarkData,
    bool skipCompose,
    bool preferNativeCompose,
  ) async {
    final saveDir = await _resolveSaveDirectory();
    return _saveImageToDirectory(
      photo: photo,
      fileName: fileName,
      watermarkData: watermarkData,
      skipCompose: skipCompose,
      preferNativeCompose: preferNativeCompose,
      saveDir: saveDir,
    );
  }

  Future<String> _saveImageToDirectory({
    required XFile photo,
    required String fileName,
    required Watermark118Data watermarkData,
    required bool skipCompose,
    required bool preferNativeCompose,
    required Directory saveDir,
  }) async {
    try {
      final finalPath = _resolveOutputPath(saveDir, fileName);

      if (skipCompose) {
        await File(photo.path).copy(finalPath);
        unawaited(_deleteTempCaptureIfNeeded(photo.path, finalPath));
      } else {
        if (preferNativeCompose && Platform.isAndroid) {
          try {
            await _composeSingleWatermarkImageNatively(
              sourcePath: photo.path,
              outputPath: finalPath,
              watermarkData: watermarkData,
            );
          } catch (error) {
            debugPrint(
              'native single compose failed, fallback to dart: $error',
            );
            await WatermarkTemplate118Composer.composePhoto(
              sourcePath: photo.path,
              outputPath: finalPath,
              data: watermarkData,
            );
          }
        } else {
          await WatermarkTemplate118Composer.composePhoto(
            sourcePath: photo.path,
            outputPath: finalPath,
            data: watermarkData,
          );
        }
        unawaited(_deleteTempCaptureIfNeeded(photo.path, finalPath));
      }
      return finalPath;
    } catch (e) {
      debugPrint('Save error: $e');
      return '';
    }
  }

  Future<void> _composeSingleWatermarkImageNatively({
    required String sourcePath,
    required String outputPath,
    required Watermark118Data watermarkData,
  }) async {
    final result = await NativeWatermarkCameraBridge.composeWatermark118Batch(
      entries: <Map<String, dynamic>>[
        <String, dynamic>{
          'materialId': null,
          'inspectionItemId': -1,
          'rawPhotoPath': sourcePath,
          'outputPath': outputPath,
          'captureTimeMillis': watermarkData.captureTime.millisecondsSinceEpoch,
          'location': watermarkData.location,
          'roomCode': watermarkData.roomCode,
          'weatherText': watermarkData.weatherText,
          'imprintText': watermarkData.imprintText,
          'displayTimeText': watermarkData.formattedTime,
          'displayDateText': watermarkData.formattedDate,
          'antiFakeCode': watermarkData.antiFakeCode,
        },
      ],
    );

    final rawResults = result['results'];
    if (rawResults is! List || rawResults.isEmpty || rawResults.first is! Map) {
      throw StateError('原生单张合成返回无效结果');
    }

    final entry = Map<String, dynamic>.from(rawResults.first as Map);
    final status = (entry['status'] as String?)?.trim() ?? '';
    if (status != 'success') {
      throw StateError('原生单张合成失败: $status');
    }
  }

  Future<String> _saveRawMaterialImage(XFile photo, String fileName) async {
    final rawDir = await _resolveRawMaterialDirectory();
    return _copyPhotoToDirectory(
      photo: photo,
      fileName: fileName,
      saveDir: rawDir,
    );
  }

  Future<String> _copyPhotoToDirectory({
    required XFile photo,
    required String fileName,
    required Directory saveDir,
  }) async {
    try {
      final finalPath = _resolveOutputPath(saveDir, fileName);
      await File(photo.path).copy(finalPath);
      unawaited(_deleteTempCaptureIfNeeded(photo.path, finalPath));
      return finalPath;
    } catch (e) {
      debugPrint('Copy capture file error: $e');
      return '';
    }
  }

  // 118 备注块默认文案：
  // 优先使用“房间号 + 类型名 + 编号”的完整房间名，和你现在期望的原始命名一致。
  // 例如：`1-1低压配电室PD01`
  String _defaultWatermarkRoomRemark(InspectionItem item) {
    final parts = <String>[
      item.location.trim(),
      item.type.trim(),
      item.serial.trim(),
    ].where((value) => value.isNotEmpty).toList();
    if (parts.isNotEmpty) {
      return parts.join();
    }

    final itemName = item.name.trim();
    if (itemName.isNotEmpty) {
      return itemName;
    }
    return item.serial.trim();
  }

  RawCaptureMaterial _buildRawCaptureMaterial({
    required InspectionItem item,
    required CameraCaptureResult capture,
    required String rawPhotoPath,
    required String preferredOutputFileName,
  }) {
    final watermarkData = capture.watermarkData;
    return RawCaptureMaterial(
      inspectionItemId: item.id,
      itemSerial: item.serial,
      itemName: item.name,
      roomCode: watermarkData.roomCode,
      preferredOutputFileName: preferredOutputFileName,
      rawPhotoPath: rawPhotoPath,
      captureTimeMillis: watermarkData.captureTime.millisecondsSinceEpoch,
      location: watermarkData.location,
      weatherText: watermarkData.weatherText,
      imprintText: watermarkData.imprintText,
      adjustments: watermarkData.adjustments,
      displayTimeText: watermarkData.formattedTime,
      displayDateText: watermarkData.formattedDate,
      createdAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _syncItemPhotoPathsFromRawMaterials(
    Iterable<int> itemIds,
  ) async {
    for (final itemId in itemIds.toSet()) {
      final itemIndex = _items.indexWhere((item) => item.id == itemId);
      if (itemIndex < 0) {
        continue;
      }
      final displayPaths = await _rawCaptureRepository
          .fetchDisplayPhotoPathsForItem(itemId);
      if (displayPaths.isEmpty) {
        continue;
      }
      _items[itemIndex].photoPaths = displayPaths;
      _items[itemIndex].isCompleted = displayPaths.isNotEmpty;
    }
  }

  Future<void> _openRawBatchCompose() async {
    final pendingMaterials = await _rawCaptureRepository
        .fetchPendingMaterials();
    if (pendingMaterials.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('当前没有待合成的无水印照片')));
      }
      return;
    }

    final sample = pendingMaterials.first;
    if (!mounted) {
      return;
    }

    final options = await Navigator.push<BatchComposeOptions?>(
      context,
      buildAppRoute(
        page: RawCaptureBatchPage(
          pendingCount: pendingMaterials.length,
          initialLocation: sample.location,
          initialWeatherText: sample.weatherText,
          initialRoomCode: sample.roomCode,
          initialImprintText: sample.imprintText,
        ),
      ),
    );
    if (options == null) {
      return;
    }

    await _composePendingRawMaterials(pendingMaterials, options);
  }

  Future<void> _composePendingRawMaterials(
    List<RawCaptureMaterial> materials,
    BatchComposeOptions options,
  ) async {
    if (materials.isEmpty) {
      return;
    }

    var showedProgressDialog = false;
    if (mounted) {
      showedProgressDialog = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.6),
                ),
                SizedBox(width: 16),
                Expanded(child: Text('正在批量合成水印，请稍候...')),
              ],
            ),
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await WidgetsBinding.instance.endOfFrame;
    }

    int successCount = 0;
    int missingCount = 0;
    int failedCount = 0;
    final syncedItemIds = <int>{};

    try {
      final result = Platform.isAndroid
          ? await _composePendingRawMaterialsNatively(materials, options)
          : await _composePendingRawMaterialsInFlutterFallback(
              materials,
              options,
            );
      successCount = (result['successCount'] as int?) ?? 0;
      missingCount = (result['missingCount'] as int?) ?? 0;
      failedCount = (result['failedCount'] as int?) ?? 0;
      final rawSyncedItemIds = result['syncedItemIds'];
      if (rawSyncedItemIds is Set<int>) {
        syncedItemIds.addAll(rawSyncedItemIds);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('批量合成失败: $error')));
      }
      return;
    } finally {
      if (showedProgressDialog && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    await _syncItemPhotoPathsFromRawMaterials(syncedItemIds);
    await _saveData();
    _recalculateDisplayData();
    await _refreshRawMaterialStats();

    if (!mounted) {
      return;
    }

    final parts = <String>[];
    if (successCount > 0) {
      parts.add('成功 $successCount 张');
    }
    if (missingCount > 0) {
      parts.add('原图缺失 $missingCount 张');
    }
    if (failedCount > 0) {
      parts.add('失败 $failedCount 张');
    }
    if (parts.isEmpty) {
      parts.add('没有可处理的照片');
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('批量合成完成：${parts.join('，')}')));
  }

  Future<Map<String, dynamic>> _composePendingRawMaterialsNatively(
    List<RawCaptureMaterial> materials,
    BatchComposeOptions options,
  ) async {
    final saveDir = await _resolveSaveDirectory();
    final entries = _buildNativeBatchComposeEntries(
      materials,
      options,
      saveDir,
    );
    final result = await NativeWatermarkCameraBridge.composeWatermark118Batch(
      entries: entries,
    );

    final syncedItemIds = <int>{};
    final rawResults = result['results'];
    if (rawResults is List) {
      for (final rawEntry in rawResults) {
        if (rawEntry is! Map) {
          continue;
        }
        final entry = Map<String, dynamic>.from(rawEntry);
        final status = (entry['status'] as String?)?.trim() ?? '';
        if (status != 'success') {
          continue;
        }

        final materialId = (entry['materialId'] as num?)?.toInt();
        final inspectionItemId = (entry['inspectionItemId'] as num?)?.toInt();
        final outputPath = (entry['outputPath'] as String?)?.trim() ?? '';
        if (materialId != null && outputPath.isNotEmpty) {
          await _rawCaptureRepository.markMaterialComposed(
            materialId: materialId,
            composedPhotoPath: outputPath,
          );
        }
        if (inspectionItemId != null) {
          syncedItemIds.add(inspectionItemId);
        }
      }
    }

    return <String, dynamic>{
      'successCount': _readBatchCount(result['successCount']),
      'missingCount': _readBatchCount(result['missingCount']),
      'failedCount': _readBatchCount(result['failedCount']),
      'syncedItemIds': syncedItemIds,
    };
  }

  Future<Map<String, dynamic>> _composePendingRawMaterialsInFlutterFallback(
    List<RawCaptureMaterial> materials,
    BatchComposeOptions options,
  ) async {
    final saveDir = await _resolveSaveDirectory();
    int successCount = 0;
    int missingCount = 0;
    int failedCount = 0;
    final syncedItemIds = <int>{};

    for (final material in materials) {
      final rawFile = File(material.rawPhotoPath);
      if (!await rawFile.exists()) {
        missingCount++;
        continue;
      }

      final captureTime = options.useCaptureTime
          ? DateTime.fromMillisecondsSinceEpoch(material.captureTimeMillis)
          : options.customCaptureTime;
      final data = Watermark118Data(
        location: options.useStoredLocation
            ? material.location
            : options.customLocation,
        roomCode: options.useStoredRoomCode
            ? material.roomCode
            : options.customRoomCode,
        weatherText: options.useStoredWeatherText
            ? material.weatherText
            : options.customWeatherText,
        captureTime: captureTime,
        imprintText: options.useStoredImprintText
            ? material.imprintText
            : options.customImprintText,
        antiFakeCode: WatermarkTemplate118Composer.generateAntiFakeCode(),
        secureCodeSpacingValue: material.adjustments.secureCodeSpacingValue,
        adjustments: material.adjustments,
        timeOverrideText: options.useCaptureTime
            ? material.displayTimeText
            : null,
        dateOverrideText: options.useCaptureTime
            ? material.displayDateText
            : null,
      );

      try {
        final outputPath = _resolveOutputPath(
          saveDir,
          material.preferredOutputFileName,
        );
        await WatermarkTemplate118Composer.composePhoto(
          sourcePath: material.rawPhotoPath,
          outputPath: outputPath,
          data: data,
        );

        final materialId = material.id;
        if (materialId != null) {
          await _rawCaptureRepository.markMaterialComposed(
            materialId: materialId,
            composedPhotoPath: outputPath,
          );
        }
        syncedItemIds.add(material.inspectionItemId);
        successCount++;
      } catch (error) {
        debugPrint('batch compose failed for ${material.rawPhotoPath}: $error');
        failedCount++;
      }
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }

    return <String, dynamic>{
      'successCount': successCount,
      'missingCount': missingCount,
      'failedCount': failedCount,
      'syncedItemIds': syncedItemIds,
    };
  }

  List<Map<String, dynamic>> _buildNativeBatchComposeEntries(
    List<RawCaptureMaterial> materials,
    BatchComposeOptions options,
    Directory saveDir,
  ) {
    final reservedPaths = <String>{};
    return materials.map((material) {
      final captureTime = options.useCaptureTime
          ? DateTime.fromMillisecondsSinceEpoch(material.captureTimeMillis)
          : options.customCaptureTime;
      return <String, dynamic>{
        'materialId': material.id,
        'inspectionItemId': material.inspectionItemId,
        'rawPhotoPath': material.rawPhotoPath,
        'outputPath': _resolvePlannedOutputPath(
          saveDir,
          material.preferredOutputFileName,
          reservedPaths,
        ),
        'captureTimeMillis': captureTime.millisecondsSinceEpoch,
        'location': options.useStoredLocation
            ? material.location
            : options.customLocation,
        'roomCode': options.useStoredRoomCode
            ? material.roomCode
            : options.customRoomCode,
        'weatherText': options.useStoredWeatherText
            ? material.weatherText
            : options.customWeatherText,
        'imprintText': options.useStoredImprintText
            ? material.imprintText
            : options.customImprintText,
        'displayTimeText': options.useCaptureTime
            ? material.displayTimeText
            : null,
        'displayDateText': options.useCaptureTime
            ? material.displayDateText
            : null,
      };
    }).toList();
  }

  String _resolvePlannedOutputPath(
    Directory saveDir,
    String fileName,
    Set<String> reservedPaths,
  ) {
    String finalPath = path.join(saveDir.path, fileName);
    if (_strategy == ConflictStrategy.increment &&
        (File(finalPath).existsSync() || reservedPaths.contains(finalPath))) {
      int idx = 1;
      final base = path.basenameWithoutExtension(fileName);
      final ext = path.extension(fileName);
      while (File(finalPath).existsSync() ||
          reservedPaths.contains(finalPath)) {
        finalPath = path.join(saveDir.path, '${base}_$idx$ext');
        idx++;
      }
    }
    if (_strategy == ConflictStrategy.increment) {
      reservedPaths.add(finalPath);
    }
    return finalPath;
  }

  int _readBatchCount(Object? value) {
    return value is num ? value.toInt() : 0;
  }

  Future<void> _takePhoto(InspectionItem item) async {
    if (widget.cameras.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('未检测到相机')));
      return;
    }

    if (!(await _ensurePermissions())) return;

    if (!mounted) return;

    final bool isMulti = item.type == '低压配电室' || item.type == '网络传输机房';
    final int count = isMulti ? 2 : 1;
    final watermarkRoomRemark = _defaultWatermarkRoomRemark(item);
    final initialWeatherText = await _prepareInitialCaptureWeatherText();

    if (!mounted) return;

    final captures = await Navigator.push<List<CameraCaptureResult>?>(
      context,
      buildAppRoute(
        page: CameraPage(
          camera: widget.cameras.first,
          title: item.name,
          captureCount: count,
          roomCode: watermarkRoomRemark,
          initialWatermarkLocation: _resolvedDefaultWatermarkLocation(item),
          weatherText: initialWeatherText,
          imprintText: _resolvedDefaultWatermarkImprintText(),
          enableCameraAttachDelay: _cameraAttachDelayEnabled,
          cameraAttachDelayMs: _cameraAttachDelayMs,
          initialWatermarkEnabled: _defaultWatermarkEnabled,
          onWatermarkPreferenceChanged: _setDefaultWatermarkEnabled,
        ),
      ),
    );

    if (captures == null || captures.isEmpty) return;

    List<String> savedPaths = [];
    final rawMaterials = <RawCaptureMaterial>[];
    for (int i = 0; i < captures.length; i++) {
      final capture = captures[i];
      final String fileName = isMulti
          ? '${_sanitizeFileName(item.serial)}_$i.jpg'
          : '${_sanitizeFileName(item.serial)}.jpg';

      final savedPath = capture.watermarkEnabled
          ? await _saveImage(
              capture.photo,
              fileName,
              capture.watermarkData,
              capture.skipCompose,
              capture.preferNativeCompose,
            )
          : await _saveRawMaterialImage(capture.photo, fileName);
      if (savedPath.isNotEmpty) savedPaths.add(savedPath);
      if (!capture.watermarkEnabled && savedPath.isNotEmpty) {
        rawMaterials.add(
          _buildRawCaptureMaterial(
            item: item,
            capture: capture,
            rawPhotoPath: savedPath,
            preferredOutputFileName: fileName,
          ),
        );
      }
    }

    if (savedPaths.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('水印照片生成失败')));
      }
      return;
    }

    if (rawMaterials.isNotEmpty) {
      await _rawCaptureRepository.insertMaterials(rawMaterials);
      await _refreshRawMaterialStats();
    }

    if (savedPaths.isNotEmpty) {
      item.isCompleted = true;
      item.photoPaths = savedPaths;
      _recordInspectionActivityAt(DateTime.now());
      await _saveData();
      _recalculateDisplayData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              rawMaterials.isEmpty
                  ? '已保存: ${savedPaths.length} 张照片'
                  : '已保存无水印原图: ${savedPaths.length} 张',
            ),
          ),
        );
      }
      await _showPhotoToMeterQuickJumpIfNeeded(item);
    }
  }

  void _showAddEditDialog([InspectionItem? item]) {
    final nameCtrl = TextEditingController(text: item?.name ?? '');
    final typeCtrl = TextEditingController(text: item?.type ?? '');
    final locCtrl = TextEditingController(text: item?.location ?? '');
    final serCtrl = TextEditingController(text: item?.serial ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item == null ? '新增预设' : '编辑预设'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: serCtrl,
                decoration: const InputDecoration(labelText: '编号 (卡片大字)'),
              ),
              TextField(
                controller: locCtrl,
                decoration: const InputDecoration(labelText: '位置 (1-1)'),
              ),
              TextField(
                controller: typeCtrl,
                decoration: const InputDecoration(labelText: '分类'),
              ),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '保存文件名'),
              ),
            ],
          ),
        ),
        actions: [
          if (item != null)
            TextButton(
              onPressed: () async {
                _items.removeWhere((e) => e.id == item.id);
                await _saveData();
                _recalculateDisplayData();
                if (mounted) Navigator.pop(context);
              },
              child: const Text('删除', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              if (item == null) {
                _items.add(
                  InspectionItem(
                    id: DateTime.now().millisecondsSinceEpoch,
                    name: nameCtrl.text.trim(),
                    type: typeCtrl.text.trim(),
                    location: locCtrl.text.trim(),
                    serial: serCtrl.text.trim(),
                  ),
                );
              } else {
                item.name = nameCtrl.text.trim();
                item.type = typeCtrl.text.trim();
                item.location = locCtrl.text.trim();
                item.serial = serCtrl.text.trim();
              }
              await _saveData();
              _recalculateDisplayData();
              if (mounted) Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _retakePhotosForItem(InspectionItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重拍该房间'),
        content: Text('将删除【${item.serial}】当前已拍照片后重新拍摄，确定继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('重拍'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await _deleteCapturedPhotosForItem(item, needConfirm: false);
    if (!mounted) return;
    await _takePhoto(item);
  }

  Future<void> _showCompletedItemActions(InspectionItem item) async {
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('查看照片'),
              onTap: () {
                Navigator.pop(ctx);
                _viewPhotos(item);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('重拍该房间'),
              onTap: () async {
                Navigator.pop(ctx);
                await _retakePhotosForItem(item);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('删除该房间照片', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(ctx);
                await _deleteCapturedPhotosForItem(item);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _viewPhotos(InspectionItem item) {
    showDialog(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text('${item.serial} 的照片'),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: PageView.builder(
            itemCount: item.photoPaths.length,
            itemBuilder: (context, index) {
              final file = File(item.photoPaths[index]);
              if (!file.existsSync()) return const Center(child: Text('图片已丢失'));
              return InteractiveViewer(
                child: Image.file(file, fit: BoxFit.contain),
              );
            },
          ),
        ),
      ),
    );
  }

  void _showConfigSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.9,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                MediaQuery.of(context).viewInsets.bottom + 28,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '设置',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isExportingZip ? null : _exportZip,
                      icon: const Icon(Icons.folder_zip_outlined),
                      label: Text(
                        _isExportingZip ? '正在打包照片...' : '打包导出照片 (ZIP)',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _openCloudSyncPage();
                      },
                      icon: const Icon(Icons.cloud_sync_outlined),
                      label: const Text('云端同步 (Gitee)'),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '保存路径',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _currentSavePathDisplay(),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _pickSaveDirectory(setModalState),
                          child: const Text('选择目录'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            setState(() => _saveDirectoryPath = null);
                            setModalState(() {});
                            await _saveData();
                          },
                          child: const Text('默认'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '直拍保存路径',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _currentDirectCapturePathDisplay(),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () =>
                              _pickDirectCaptureSaveDirectory(setModalState),
                          child: const Text('选择目录'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            setState(
                              () => _directCaptureSaveDirectoryPath = null,
                            );
                            setModalState(() {});
                            await _saveData();
                          },
                          child: const Text('默认'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    '权限状态',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.storage_rounded),
                    title: const Text(
                      '所有文件访问权限',
                      style: TextStyle(fontSize: 14),
                    ),
                    subtitle: FutureBuilder<bool>(
                      future: Permission.manageExternalStorage.isGranted,
                      builder: (context, snapshot) {
                        final granted = snapshot.data ?? false;
                        return Text(
                          granted ? '已开启' : '未开启 (点击去设置)',
                          style: TextStyle(
                            color: granted ? Colors.green : Colors.red,
                            fontSize: 12,
                          ),
                        );
                      },
                    ),
                    onTap: () async {
                      await _openAllFilesAccessSettings();
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                  const Text(
                    '联动设置',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      '拍照完成后提示跳转动力抄表',
                      style: TextStyle(fontSize: 14),
                    ),
                    subtitle: const Text(
                      '仅对已纳入动力抄表的房间生效',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: _photoToMeterQuickJumpEnabled,
                    onChanged: (v) async {
                      setState(() => _photoToMeterQuickJumpEnabled = v);
                      setModalState(() {});
                      await _saveData();
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '拍照设置',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      '进入拍照页延迟启动相机',
                      style: TextStyle(fontSize: 14),
                    ),
                    subtitle: Text(
                      _cameraAttachDelayEnabled
                          ? '当前延迟 $_cameraAttachDelayMs ms，优先让页面转场完整跑完'
                          : '关闭后会在转场结束后立即启动相机',
                      style: const TextStyle(fontSize: 12),
                    ),
                    value: _cameraAttachDelayEnabled,
                    onChanged: (v) async {
                      setState(() => _cameraAttachDelayEnabled = v);
                      setModalState(() {});
                      await _saveData();
                    },
                  ),
                  Row(
                    children: [
                      Text(
                        '$_cameraAttachDelayMs ms',
                        style: TextStyle(
                          fontSize: 13,
                          color: _cameraAttachDelayEnabled
                              ? Colors.black54
                              : Colors.black38,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '0',
                        style: TextStyle(
                          fontSize: 12,
                          color: _cameraAttachDelayEnabled
                              ? Colors.black45
                              : Colors.black26,
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: _cameraAttachDelayMs.toDouble(),
                          min: 0,
                          max: 1000,
                          divisions: 20,
                          label: '$_cameraAttachDelayMs ms',
                          onChanged: _cameraAttachDelayEnabled
                              ? (value) {
                                  final next = value.round().clamp(0, 1000);
                                  setState(() => _cameraAttachDelayMs = next);
                                  setModalState(() {});
                                }
                              : null,
                          onChangeEnd: _cameraAttachDelayEnabled
                              ? (_) async {
                                  await _saveData();
                                }
                              : null,
                        ),
                      ),
                      Text(
                        '1000',
                        style: TextStyle(
                          fontSize: 12,
                          color: _cameraAttachDelayEnabled
                              ? Colors.black45
                              : Colors.black26,
                        ),
                      ),
                    ],
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      '默认启用拍照水印',
                      style: TextStyle(fontSize: 14),
                    ),
                    subtitle: Text(
                      _defaultWatermarkEnabled
                          ? '进入拍照页时默认是水印模式'
                          : '进入拍照页时默认保存无水印原图',
                      style: const TextStyle(fontSize: 12),
                    ),
                    value: _defaultWatermarkEnabled,
                    onChanged: (v) async {
                      await _setDefaultWatermarkEnabled(v);
                      setModalState(() {});
                    },
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      '进线柜拍照默认在线 OCR',
                      style: TextStyle(fontSize: 14),
                    ),
                    subtitle: const Text(
                      '开启后，设备名里不带 ups，且同房仅剩 2-3 台这类设备时，会默认走百度仪表 OCR；仍可在抄表页右上角手动切换。',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: _incomingCabinetOnlineOcrEnabled,
                    onChanged: (v) async {
                      setState(() => _incomingCabinetOnlineOcrEnabled = v);
                      setModalState(() {});
                      await _saveData();
                    },
                  ),
                  TextFormField(
                    initialValue: _defaultWatermarkLocationFallback,
                    decoration: const InputDecoration(
                      labelText: '默认水印地址',
                      hintText: '留空时默认使用房间位置',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (value) {
                      setState(() => _defaultWatermarkLocationFallback = value);
                      setModalState(() {});
                      unawaited(_saveData());
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    initialValue: _defaultWatermarkImprintText,
                    decoration: const InputDecoration(
                      labelText: '默认验证文案',
                      hintText: '留空时使用模板默认文案',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (value) {
                      setState(() => _defaultWatermarkImprintText = value);
                      setModalState(() {});
                      unawaited(_saveData());
                    },
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '这两个默认值会参与云端同步，拉取覆盖后新开的拍照页会直接使用。',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _pendingRawMaterialCount > 0
                          ? () {
                              Navigator.pop(ctx);
                              _openRawBatchCompose();
                            }
                          : null,
                      icon: const Icon(Icons.auto_fix_high),
                      label: Text(
                        _pendingRawMaterialCount > 0
                            ? '批量合成无水印照片 ($_pendingRawMaterialCount)'
                            : '批量合成无水印照片',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '排序方式',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: _sortBy,
                    items: const [
                      DropdownMenuItem(value: 'serial', child: Text('按编号')),
                      DropdownMenuItem(value: 'location', child: Text('按位置')),
                      DropdownMenuItem(value: 'name', child: Text('按保存名')),
                    ],
                    onChanged: (v) {
                      setModalState(() => _sortBy = v!);
                      _saveData();
                      _recalculateDisplayData();
                    },
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '排版模式',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      '启用分类融合排版',
                      style: TextStyle(fontSize: 14),
                    ),
                    subtitle: const Text(
                      '关闭后恢复原始分类分组布局',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: _mergedLayoutEnabled,
                    onChanged: (v) async {
                      setState(() => _mergedLayoutEnabled = v);
                      setModalState(() {});
                      _recalculateDisplayData();
                      await _saveData();
                    },
                  ),
                  const SizedBox(height: 12),
                  if (_mergedLayoutEnabled) ...[
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        '启用融合分类向下查找',
                        style: TextStyle(fontSize: 14),
                      ),
                      subtitle: const Text(
                        '遇到超出剩余格数的分类时继续向下尝试融合',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: _mergedDeepSearchEnabled,
                      onChanged: (v) {
                        setState(() => _mergedDeepSearchEnabled = v);
                        setModalState(() {});
                        _recalculateDisplayData();
                        _saveData();
                      },
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        '融合模式分类高度统一',
                        style: TextStyle(fontSize: 14),
                      ),
                      subtitle: const Text(
                        '按当前屏宽动态统一高度并自动防止按钮溢出',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: _mergedUniformHeightEnabled,
                      onChanged: (v) {
                        setState(() => _mergedUniformHeightEnabled = v);
                        setModalState(() {});
                        _recalculateDisplayData();
                        _saveData();
                      },
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        '超紧凑模式',
                        style: TextStyle(fontSize: 14),
                      ),
                      subtitle: const Text(
                        '隐藏类名并取消类别上下间距',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: _mergedUltraCompactEnabled,
                      onChanged: (v) {
                        setState(() => _mergedUltraCompactEnabled = v);
                        setModalState(() {});
                        _recalculateDisplayData();
                        _saveData();
                      },
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '分类配色主题',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    DropdownButton<String>(
                      isExpanded: true,
                      value: _typeColorThemeId,
                      items: [
                        for (final theme in _typeColorThemes)
                          DropdownMenuItem(
                            value: theme.id,
                            child: Text(theme.name),
                          ),
                      ],
                      onChanged: (v) async {
                        if (v == null) return;
                        setState(() => _typeColorThemeId = v);
                        setModalState(() {});
                        _recalculateDisplayData();
                        await _saveData();
                      },
                    ),
                    Text(
                      _activeTypeColorTheme.description,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () async {
                            await _applyCurrentThemeToAllTypes(setModalState);
                          },
                          child: const Text('按主题覆盖全部分类'),
                        ),
                        TextButton(
                          onPressed: () async {
                            await _clearTypeColorOverrides(setModalState);
                          },
                          child: const Text('清除手动颜色'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '分类颜色（融合模式）',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final type in _sortedTypes)
                          InkWell(
                            borderRadius: BorderRadius.circular(99),
                            onTap: () => _pickTypeColor(type, setModalState),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _typeBaseColor(type),
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(color: Colors.black12),
                              ),
                              child: Text(
                                _shortTypeLabel(type),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '房间编号按钮边长（正方形）',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Row(
                      children: [
                        Text(
                          '${_mergedContentMaxHeight.round()} px',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black54,
                          ),
                        ),
                        const Spacer(),
                        const Text(
                          '40',
                          style: TextStyle(fontSize: 12, color: Colors.black45),
                        ),
                        Expanded(
                          child: Slider(
                            value: _mergedContentMaxHeight,
                            min: 40,
                            max: 180,
                            divisions: 28,
                            label: _mergedContentMaxHeight.round().toString(),
                            onChanged: (value) {
                              setState(() => _mergedContentMaxHeight = value);
                              setModalState(() {});
                              _recalculateDisplayData();
                              _saveData();
                            },
                          ),
                        ),
                        const Text(
                          '180',
                          style: TextStyle(fontSize: 12, color: Colors.black45),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        '显示融合布局调试信息',
                        style: TextStyle(fontSize: 14),
                      ),
                      subtitle: const Text(
                        '显示每个分类块的宽高计算结果',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: _showMergedLayoutDebug,
                      onChanged: (v) {
                        setState(() => _showMergedLayoutDebug = v);
                        setModalState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  const Text(
                    '首页网格布局',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        '每行 $_gridColumns 个',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black54,
                        ),
                      ),
                      const Spacer(),
                      const Text(
                        '3',
                        style: TextStyle(fontSize: 12, color: Colors.black45),
                      ),
                      Expanded(
                        child: Slider(
                          value: _gridColumns.toDouble(),
                          min: 3,
                          max: 6,
                          divisions: 3,
                          label: '$_gridColumns',
                          onChanged: (value) {
                            final next = value.round().clamp(3, 6);
                            setState(() => _gridColumns = next);
                            setModalState(() {});
                            _recalculateDisplayData();
                            _saveData();
                          },
                        ),
                      ),
                      const Text(
                        '6',
                        style: TextStyle(fontSize: 12, color: Colors.black45),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mergedRevealIndexById = <int, int>{};
    var mergedRevealIndex = 0;
    for (final row in _mergedRows) {
      for (final segment in row.segments) {
        for (final item in segment.items) {
          mergedRevealIndexById[item.id] = mergedRevealIndex++;
        }
      }
    }

    final gridRevealBaseByType = <String, int>{};
    var gridRevealIndex = 0;
    for (final type in _sortedTypes) {
      gridRevealBaseByType[type] = gridRevealIndex;
      gridRevealIndex += _groupedData[type]?.length ?? 0;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'PhotoNamer',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: false,
        backgroundColor: const Color(0xFFF6F8FC),
        actions: [
          IconButton(
            onPressed: () => _showConfigSheet(context),
            icon: const Icon(Icons.tune),
            tooltip: '设置',
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            children: [
              const ListTile(
                title: Text(
                  '功能导航',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text('后续可继续扩展新栏目'),
              ),
              ListTile(
                leading: const Icon(Icons.fact_check_outlined),
                title: const Text('动力抄表'),
                onTap: () async {
                  Navigator.pop(context);
                  await _openMeterFeature();
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_outlined),
                title: const Text('直拍'),
                subtitle: const Text('手动备注，连续拍照，独立目录保存'),
                onTap: () async {
                  Navigator.pop(context);
                  await _openDirectCaptureMode();
                },
              ),
              ListTile(
                leading: const Icon(Icons.cloud_sync_outlined),
                title: const Text('云端同步'),
                subtitle: const Text('房间模板、超标时段与参数同步'),
                onTap: () async {
                  Navigator.pop(context);
                  await _openCloudSyncPage();
                },
              ),
              ListTile(
                leading: const Icon(Icons.calendar_month_outlined),
                title: const Text('巡检日历'),
                subtitle: const Text('按日期查看五个巡检时段记录'),
                onTap: () async {
                  Navigator.pop(context);
                  await _openInspectionCalendarPage();
                },
              ),
              const Divider(height: 24),
              const ListTile(
                leading: Icon(Icons.add_box_outlined),
                title: Text('更多栏目敬请期待'),
                subtitle: Text('可在此继续新增业务入口'),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: ExpandableFab(
        heroTag: 'fab_main_action',
        actions: [
          FabMenuAction(
            label: '切到待办 ($_pendingCount)',
            icon: Icons.pending_actions_outlined,
            onTap: () => _switchCurrentTab(0),
          ),
          FabMenuAction(
            label: '切到完成 ($_completedCount)',
            icon: Icons.task_alt_outlined,
            onTap: () => _switchCurrentTab(1),
          ),
          FabMenuAction(
            label: '新增预设',
            icon: Icons.add_task_outlined,
            onTap: () => _showAddEditDialog(),
          ),
          FabMenuAction(
            label: '动力抄表',
            icon: Icons.fact_check_outlined,
            onTap: _openMeterFeature,
          ),
          FabMenuAction(
            label: '直拍',
            icon: Icons.camera_outlined,
            onTap: _openDirectCaptureMode,
          ),
          FabMenuAction(
            label: _pendingRawMaterialCount > 0
                ? '批量合成原图 ($_pendingRawMaterialCount)'
                : '批量合成原图',
            icon: Icons.auto_fix_high,
            onTap: _openRawBatchCompose,
          ),
          FabMenuAction(
            label: '删除已拍照片',
            icon: Icons.delete_sweep_outlined,
            onTap: _clearAllCapturedPhotos,
            danger: true,
          ),
          FabMenuAction(
            label: '重置进度',
            icon: Icons.refresh,
            onTap: _resetAllProgress,
          ),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Column(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 12,
                                offset: Offset(0, 6),
                              ),
                            ],
                          ),
                          child: TextField(
                            controller: _searchCtrl,
                            onChanged: (_) => _recalculateDisplayData(),
                            decoration: const InputDecoration(
                              hintText: '搜索编号或名称...',
                              prefixIcon: Icon(Icons.search),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 16,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _AnimatedFloorFilterBar(
                          labels: _floorLabels,
                          selectedLabel: _floorFilter,
                          selectionPulse: _floorFilterPulse,
                          onSelect: _applyFloorFilter,
                        ),
                        const SizedBox(height: 18),
                      ],
                    ),
                  ),
                ),
                if (_mergedLayoutEnabled) ...[
                  if (_mergedRows.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: Text('暂无数据')),
                    ),
                  for (final row in _mergedRows) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          _mergedUltraCompactEnabled ? 0 : 8,
                          16,
                          _mergedUltraCompactEnabled ? 0 : 8,
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final slotWidth =
                                (constraints.maxWidth -
                                    (_gridColumns - 1) * 12) /
                                _gridColumns;
                            final segmentGap = _mergedUltraCompactEnabled
                                ? 0.0
                                : 12.0;
                            const itemGap = 12.0;
                            final segmentHorizontalPadding =
                                _mergedUltraCompactEnabled ? 10.0 : 8.0;
                            final showTypeLabel = !_mergedUltraCompactEnabled;
                            const segmentTopPadding = 8.0;
                            final segmentBottomPadding =
                                _mergedUltraCompactEnabled ? 8.0 : 10.0;

                            final rowCapByWidth = _mergedRowButtonCapByWidth(
                              maxWidth: constraints.maxWidth,
                              row: row,
                              segmentGap: segmentGap,
                              itemGap: itemGap,
                              segmentHorizontalPadding:
                                  segmentHorizontalPadding,
                            );

                            final targetButtonSize = _mergedContentMaxHeight;
                            final rowButtonSize = math.min(
                              targetButtonSize,
                              math.min(slotWidth, rowCapByWidth),
                            );
                            final uniformButtonSize =
                                _mergedUniformHeightEnabled
                                ? _mergedUniformButtonSize(
                                    maxWidth: constraints.maxWidth,
                                    slotWidth: slotWidth,
                                    targetButtonSize: targetButtonSize,
                                    segmentGap: segmentGap,
                                    itemGap: itemGap,
                                    segmentHorizontalPadding:
                                        segmentHorizontalPadding,
                                  )
                                : rowButtonSize;
                            final effectiveButtonSize =
                                _mergedUniformHeightEnabled
                                ? uniformButtonSize
                                : rowButtonSize;
                            final groupHeight =
                                effectiveButtonSize +
                                _mergedGroupExtraHeight(
                                  showDebug: _showMergedLayoutDebug,
                                  showTypeLabel: showTypeLabel,
                                  topPadding: segmentTopPadding,
                                  bottomPadding: segmentBottomPadding,
                                );
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (
                                  int i = 0;
                                  i < row.segments.length;
                                  i++
                                ) ...[
                                  if (i > 0) SizedBox(width: segmentGap),
                                  SizedBox(
                                    width:
                                        segmentHorizontalPadding * 2 +
                                        effectiveButtonSize *
                                            row.segments[i].items.length +
                                        (row.segments[i].items.length - 1) *
                                            itemGap,
                                    child: SizedBox(
                                      height: groupHeight,
                                      child: Container(
                                        padding: EdgeInsets.fromLTRB(
                                          segmentHorizontalPadding,
                                          segmentTopPadding,
                                          segmentHorizontalPadding,
                                          segmentBottomPadding,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _typeBaseColor(
                                            row.segments[i].type,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: Colors.black.withValues(
                                              alpha: 0.12,
                                            ),
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (showTypeLabel) ...[
                                              Text(
                                                _shortTypeLabel(
                                                  row.segments[i].type,
                                                ),
                                                textAlign: TextAlign.center,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w800,
                                                  color: Color(0xFF33406E),
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                            ],
                                            if (_showMergedLayoutDebug)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 6,
                                                ),
                                                child: Text(
                                                  'slot:${slotWidth.toStringAsFixed(1)} target:${targetButtonSize.toStringAsFixed(1)} actual:${effectiveButtonSize.toStringAsFixed(1)} h:${groupHeight.toStringAsFixed(1)} n:${row.segments[i].items.length}',
                                                  textAlign: TextAlign.center,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.black54,
                                                  ),
                                                ),
                                              ),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                for (
                                                  int j = 0;
                                                  j <
                                                      row
                                                          .segments[i]
                                                          .items
                                                          .length;
                                                  j++
                                                ) ...[
                                                  if (j > 0)
                                                    const SizedBox(width: 12),
                                                  SizedBox(
                                                    width: effectiveButtonSize,
                                                    height: effectiveButtonSize,
                                                    child: _FilterReveal(
                                                      pulse: _roomRevealPulse,
                                                      index:
                                                          mergedRevealIndexById[row
                                                              .segments[i]
                                                              .items[j]
                                                              .id] ??
                                                          0,
                                                      child: RepaintBoundary(
                                                        child: _RoomCard(
                                                          key: ValueKey(
                                                            row
                                                                .segments[i]
                                                                .items[j]
                                                                .id,
                                                          ),
                                                          serial: row
                                                              .segments[i]
                                                              .items[j]
                                                              .serial,
                                                          location: row
                                                              .segments[i]
                                                              .items[j]
                                                              .location,
                                                          showLocation:
                                                              _gridColumns <= 5,
                                                          isCompleted: row
                                                              .segments[i]
                                                              .items[j]
                                                              .isCompleted,
                                                          onTap: () =>
                                                              row
                                                                  .segments[i]
                                                                  .items[j]
                                                                  .isCompleted
                                                              ? _showCompletedItemActions(
                                                                  row
                                                                      .segments[i]
                                                                      .items[j],
                                                                )
                                                              : _takePhoto(
                                                                  row
                                                                      .segments[i]
                                                                      .items[j],
                                                                ),
                                                          onLongPress: () =>
                                                              _showAddEditDialog(
                                                                row
                                                                    .segments[i]
                                                                    .items[j],
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ] else ...[
                  if (_sortedTypes.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: Text('暂无数据')),
                    ),
                  for (final type in _sortedTypes) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: _SectionHeader(title: type),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: _gridColumns,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: _gridColumns >= 5
                              ? 0.82
                              : (_gridColumns == 4 ? 0.86 : 0.95),
                        ),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final it = _groupedData[type]![index];
                          return _FilterReveal(
                            pulse: _roomRevealPulse,
                            index: (gridRevealBaseByType[type] ?? 0) + index,
                            child: RepaintBoundary(
                              child: _RoomCard(
                                key: ValueKey(it.id),
                                serial: it.serial,
                                location: it.location,
                                showLocation: _gridColumns <= 5,
                                isCompleted: it.isCompleted,
                                onTap: () => it.isCompleted
                                    ? _showCompletedItemActions(it)
                                    : _takePhoto(it),
                                onLongPress: () => _showAddEditDialog(it),
                              ),
                            ),
                          );
                        }, childCount: _groupedData[type]!.length),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  ],
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class InspectionCalendarPage extends StatefulWidget {
  final Map<String, InspectionCalendarDayRecord> initialRecords;
  final Future<void> Function(Map<String, InspectionCalendarDayRecord> records)
  onChanged;

  const InspectionCalendarPage({
    super.key,
    required this.initialRecords,
    required this.onChanged,
  });

  @override
  State<InspectionCalendarPage> createState() => _InspectionCalendarPageState();
}

class _InspectionCalendarPageState extends State<InspectionCalendarPage> {
  static const List<Color> _slotColors = [
    Color(0xFF2563EB),
    Color(0xFF0F766E),
    Color(0xFFF59E0B),
    Color(0xFFEA580C),
    Color(0xFFDC2626),
  ];

  late Map<String, InspectionCalendarDayRecord> _records;
  late DateTime _visibleMonth;
  late DateTime _selectedDate;
  late final List<String> _slotLabels;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _records = cloneInspectionCalendarRecords(widget.initialRecords);
    _visibleMonth = normalizeInspectionCalendarMonth(today);
    _selectedDate = DateTime(today.year, today.month, today.day);
    _slotLabels = kDefaultMeterTimeSlots
        .map((slot) => slot.label)
        .toList(growable: false);
  }

  String get _selectedDateKey => formatInspectionCalendarDateKey(_selectedDate);

  InspectionCalendarDayRecord get _selectedRecord =>
      _records[_selectedDateKey] ??
      InspectionCalendarDayRecord.empty(_selectedDateKey);

  bool get _selectedDateIsToday =>
      DateUtils.isSameDay(_selectedDate, DateTime.now());

  String get _recommendedSlotLabel => nearestMeterTimeSlotLabel(DateTime.now());

  Color _slotColorForIndex(int index) {
    return _slotColors[index % _slotColors.length];
  }

  Future<void> _persistRecords() async {
    await widget.onChanged(cloneInspectionCalendarRecords(_records));
  }

  void _applySlotsForDate(DateTime date, Set<String> completedSlots) {
    final dateKey = formatInspectionCalendarDateKey(date);
    final normalizedSlots = <String>{};
    for (final slot in completedSlots) {
      if (_slotLabels.contains(slot)) {
        normalizedSlots.add(slot);
      }
    }

    setState(() {
      if (normalizedSlots.isEmpty) {
        _records.remove(dateKey);
      } else {
        _records[dateKey] = InspectionCalendarDayRecord(
          dateKey: dateKey,
          completedSlots: normalizedSlots,
          updatedAt: DateTime.now().toIso8601String(),
        );
      }
    });
    unawaited(_persistRecords());
  }

  void _toggleSelectedSlot(String label) {
    final nextSlots = Set<String>.from(_selectedRecord.completedSlots);
    if (!nextSlots.add(label)) {
      nextSlots.remove(label);
    }
    _applySlotsForDate(_selectedDate, nextSlots);
  }

  void _markSelectedDayAllCompleted() {
    _applySlotsForDate(_selectedDate, Set<String>.from(_slotLabels));
  }

  void _clearSelectedDay() {
    _applySlotsForDate(_selectedDate, <String>{});
  }

  void _markRecommendedSlotForSelectedDay() {
    final label = _recommendedSlotLabel;
    if (label.isEmpty) {
      return;
    }
    final nextSlots = Set<String>.from(_selectedRecord.completedSlots)
      ..add(label);
    _applySlotsForDate(_selectedDate, nextSlots);
  }

  void _jumpToToday() {
    final now = DateTime.now();
    setState(() {
      _visibleMonth = normalizeInspectionCalendarMonth(now);
      _selectedDate = DateTime(now.year, now.month, now.day);
    });
  }

  void _changeMonth(int offset) {
    final nextMonth = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + offset,
    );
    final maxDay = DateUtils.getDaysInMonth(nextMonth.year, nextMonth.month);
    setState(() {
      _visibleMonth = nextMonth;
      _selectedDate = DateTime(
        nextMonth.year,
        nextMonth.month,
        math.min(_selectedDate.day, maxDay),
      );
    });
  }

  List<DateTime?> _buildMonthCells() {
    final firstDayOfMonth = DateTime(
      _visibleMonth.year,
      _visibleMonth.month,
      1,
    );
    final daysInMonth = DateUtils.getDaysInMonth(
      _visibleMonth.year,
      _visibleMonth.month,
    );
    final leadingEmptyCount = firstDayOfMonth.weekday - 1;
    final cells = <DateTime?>[
      for (int i = 0; i < leadingEmptyCount; i++) null,
      for (int day = 1; day <= daysInMonth; day++)
        DateTime(_visibleMonth.year, _visibleMonth.month, day),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return cells;
  }

  Iterable<InspectionCalendarDayRecord> _recordsForMonth(DateTime month) sync* {
    for (final entry in _records.entries) {
      final date = parseInspectionCalendarDateKey(entry.key);
      if (date == null) {
        continue;
      }
      if (date.year == month.year && date.month == month.month) {
        yield entry.value;
      }
    }
  }

  String _formatMonthTitle(DateTime month) {
    final value = month.toLocal();
    return '${value.year}年${value.month.toString().padLeft(2, '0')}月';
  }

  String _formatFullDate(DateTime date) {
    final local = date.toLocal();
    final weekday = kInspectionCalendarWeekdayLabels[local.weekday - 1];
    return '${local.year}年${local.month.toString().padLeft(2, '0')}月${local.day.toString().padLeft(2, '0')}日 周$weekday';
  }

  String _formatUpdatedAt(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      return raw.isEmpty ? '未记录' : raw;
    }
    final local = parsed.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute';
  }

  Widget _buildWeekdayHeader() {
    return Row(
      children: [
        for (final label in kInspectionCalendarWeekdayLabels)
          Expanded(
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF475467),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLegend() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (int index = 0; index < _slotLabels.length; index++)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _slotColorForIndex(index).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: _slotColorForIndex(index).withValues(alpha: 0.26),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _slotColorForIndex(index),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _slotLabels[index],
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildDayCell(DateTime? date) {
    if (date == null) {
      return const SizedBox.shrink();
    }

    final record = _records[formatInspectionCalendarDateKey(date)];
    final completedSlots = record?.completedSlots ?? const <String>{};
    final isSelected = DateUtils.isSameDay(date, _selectedDate);
    final isToday = DateUtils.isSameDay(date, DateTime.now());
    final borderColor = isSelected
        ? Theme.of(context).colorScheme.primary
        : isToday
        ? const Color(0xFF60A5FA)
        : const Color(0xFFE4E7EC);
    final backgroundColor = isSelected
        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
        : isToday
        ? const Color(0xFFF7FBFF)
        : Colors.white;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        setState(() {
          _selectedDate = date;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: isSelected ? 1.6 : 1),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.14),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ]
              : const [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${date.day}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : const Color(0xFF101828),
                    ),
                  ),
                ),
                if (isToday)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDBEAFE),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      '今',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1D4ED8),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${completedSlots.length}/${_slotLabels.length} 时段',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF667085),
              ),
            ),
            const Spacer(),
            Wrap(
              spacing: 3,
              runSpacing: 3,
              children: [
                for (int index = 0; index < _slotLabels.length; index++)
                  Container(
                    width: completedSlots.contains(_slotLabels[index]) ? 12 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: completedSlots.contains(_slotLabels[index])
                          ? _slotColorForIndex(index)
                          : const Color(0xFFD0D5DD),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final monthRecords = _recordsForMonth(
      _visibleMonth,
    ).toList(growable: false);
    final monthActiveDays = monthRecords.length;
    final monthCompletedSlots = monthRecords.fold<int>(
      0,
      (sum, record) => sum + record.completedCount,
    );
    final monthDays = DateUtils.getDaysInMonth(
      _visibleMonth.year,
      _visibleMonth.month,
    );
    final todayRecord =
        _records[formatInspectionCalendarDateKey(DateTime.now())];
    final todayCompletedCount = todayRecord?.completedCount ?? 0;
    final cells = _buildMonthCells();

    return Scaffold(
      appBar: AppBar(
        title: const Text('巡检日历'),
        actions: [
          TextButton.icon(
            onPressed: _jumpToToday,
            icon: const Icon(Icons.today_outlined),
            label: const Text('今天'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE4E7EC)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '本月巡检概览',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_formatMonthTitle(_visibleMonth)} 已记录 $monthCompletedSlots 次时段巡检',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF667085),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _InspectionCalendarStatTile(
                        label: '有记录天数',
                        value: '$monthActiveDays/$monthDays',
                        hint: '当月覆盖',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _InspectionCalendarStatTile(
                        label: '时段命中数',
                        value: '$monthCompletedSlots',
                        hint: '五时段累计',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _InspectionCalendarStatTile(
                        label: '今天进度',
                        value: '$todayCompletedCount/${_slotLabels.length}',
                        hint: '今日巡检',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: monthDays == 0 ? 0 : monthActiveDays / monthDays,
                    minHeight: 8,
                    backgroundColor: const Color(0xFFE4E7EC),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF2563EB),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE4E7EC)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0A101828),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => _changeMonth(-1),
                      icon: const Icon(Icons.chevron_left_rounded),
                      tooltip: '上个月',
                    ),
                    Expanded(
                      child: Text(
                        _formatMonthTitle(_visibleMonth),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _changeMonth(1),
                      icon: const Icon(Icons.chevron_right_rounded),
                      tooltip: '下个月',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildLegend(),
                const SizedBox(height: 16),
                _buildWeekdayHeader(),
                const SizedBox(height: 10),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 7,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 0.78,
                  children: cells.map(_buildDayCell).toList(growable: false),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE4E7EC)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0A101828),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatFullDate(_selectedDate),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _selectedDateIsToday
                                ? '当前最近时段：${_recommendedSlotLabel.isEmpty ? '未匹配' : _recommendedSlotLabel}'
                                : '当天已记录 ${_selectedRecord.completedCount}/${_slotLabels.length} 个时段',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF667085),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2F4F7),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '${_selectedRecord.completedCount}/${_slotLabels.length}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (int index = 0; index < _slotLabels.length; index++)
                      FilterChip(
                        selected: _selectedRecord.completedSlots.contains(
                          _slotLabels[index],
                        ),
                        showCheckmark: false,
                        avatar:
                            _selectedDateIsToday &&
                                _recommendedSlotLabel == _slotLabels[index]
                            ? Icon(
                                Icons.access_time_rounded,
                                size: 16,
                                color: _slotColorForIndex(index),
                              )
                            : null,
                        label: Text(_slotLabels[index]),
                        selectedColor: _slotColorForIndex(
                          index,
                        ).withValues(alpha: 0.14),
                        side: BorderSide(
                          color:
                              _selectedRecord.completedSlots.contains(
                                _slotLabels[index],
                              )
                              ? _slotColorForIndex(index)
                              : const Color(0xFFD0D5DD),
                        ),
                        labelStyle: TextStyle(
                          fontWeight: FontWeight.w700,
                          color:
                              _selectedRecord.completedSlots.contains(
                                _slotLabels[index],
                              )
                              ? _slotColorForIndex(index)
                              : const Color(0xFF344054),
                        ),
                        onSelected: (_) =>
                            _toggleSelectedSlot(_slotLabels[index]),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  _selectedRecord.updatedAt.isEmpty
                      ? '当天暂未记录'
                      : '最后更新：${_formatUpdatedAt(_selectedRecord.updatedAt)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF667085),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (_selectedDateIsToday &&
                        _recommendedSlotLabel.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: _markRecommendedSlotForSelectedDay,
                        icon: const Icon(Icons.access_time_rounded),
                        label: Text('补记 $_recommendedSlotLabel'),
                      ),
                    FilledButton.icon(
                      onPressed: _slotLabels.isEmpty
                          ? null
                          : _markSelectedDayAllCompleted,
                      icon: const Icon(Icons.done_all_rounded),
                      label: const Text('当天全部完成'),
                    ),
                    TextButton.icon(
                      onPressed: _selectedRecord.completedSlots.isEmpty
                          ? null
                          : _clearSelectedDay,
                      icon: const Icon(Icons.cleaning_services_outlined),
                      label: const Text('清空当天'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  '提示：用户成功拍照后，系统会按当前时间自动记到最近的巡检时段；这里也支持手动补录和修正。',
                  style: TextStyle(fontSize: 12, color: Color(0xFF667085)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InspectionCalendarStatTile extends StatelessWidget {
  final String label;
  final String value;
  final String hint;

  const _InspectionCalendarStatTile({
    required this.label,
    required this.value,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF667085),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            hint,
            style: const TextStyle(fontSize: 12, color: Color(0xFF98A2B3)),
          ),
        ],
      ),
    );
  }
}

class ShiftAwareInspectionCalendarPage extends StatefulWidget {
  final Map<String, InspectionCalendarDayRecord> initialRecords;
  final InspectionShiftScheduleConfig initialScheduleConfig;
  final Future<void> Function(Map<String, InspectionCalendarDayRecord> records)
  onRecordsChanged;
  final Future<void> Function(InspectionShiftScheduleConfig config)
  onScheduleConfigChanged;

  const ShiftAwareInspectionCalendarPage({
    super.key,
    required this.initialRecords,
    required this.initialScheduleConfig,
    required this.onRecordsChanged,
    required this.onScheduleConfigChanged,
  });

  @override
  State<ShiftAwareInspectionCalendarPage> createState() =>
      _ShiftAwareInspectionCalendarPageState();
}

class _ShiftAwareInspectionCalendarPageState
    extends State<ShiftAwareInspectionCalendarPage> {
  static const List<Color> _slotColors = [
    Color(0xFF2563EB),
    Color(0xFF0F766E),
    Color(0xFFF59E0B),
    Color(0xFFEA580C),
    Color(0xFFDC2626),
  ];

  late Map<String, InspectionCalendarDayRecord> _records;
  late InspectionShiftScheduleConfig _scheduleConfig;
  late DateTime _visibleMonth;
  late DateTime _selectedDate;
  late final List<String> _slotLabels;

  @override
  void initState() {
    super.initState();
    final today = normalizeInspectionCalendarDate(DateTime.now());
    _records = cloneInspectionCalendarRecords(widget.initialRecords);
    _scheduleConfig = widget.initialScheduleConfig;
    _visibleMonth = normalizeInspectionCalendarMonth(today);
    _selectedDate = today;
    _slotLabels = kDefaultMeterTimeSlots
        .map((slot) => slot.label)
        .toList(growable: false);
  }

  String get _selectedDateKey => formatInspectionCalendarDateKey(_selectedDate);

  InspectionCalendarDayRecord get _selectedRecord =>
      _records[_selectedDateKey] ??
      InspectionCalendarDayRecord.empty(_selectedDateKey);

  InspectionShiftType get _selectedShiftType =>
      inspectionShiftTypeForDate(_selectedDate, _scheduleConfig);

  List<String> get _selectedRequiredSlots =>
      inspectionRequiredSlotsForShift(_selectedShiftType);

  List<String> get _selectedAssignedSlots =>
      assignedInspectionSlotsForDate(_selectedDate, _scheduleConfig);

  bool get _selectedDateIsToday =>
      DateUtils.isSameDay(_selectedDate, DateTime.now());

  String get _recommendedSlotLabel =>
      matchedInspectionSlotLabelForMoment(DateTime.now(), _scheduleConfig);

  DateTime get _firstMorningShiftDate =>
      parseInspectionCalendarDateKey(
        _scheduleConfig.firstMorningShiftDateKey,
      ) ??
      normalizeInspectionCalendarDate(DateTime.now());

  DateTime get _firstInspectionDate =>
      inspectionRotationStartDateForConfig(_scheduleConfig);

  InspectionShiftType get _firstInspectionShiftType =>
      inspectionShiftTypeForDate(_firstInspectionDate, _scheduleConfig);

  List<String> get _firstInspectionCandidateSlots =>
      inspectionRequiredSlotsForDate(_firstInspectionDate, _scheduleConfig);

  String get _firstInspectionSlotLabel =>
      resolveInspectionRotationStartSlotLabel(_scheduleConfig);

  Color _slotColorForIndex(int index) =>
      _slotColors[index % _slotColors.length];

  Color _shiftColor(InspectionShiftType shiftType) {
    switch (shiftType) {
      case InspectionShiftType.morning:
        return const Color(0xFF2563EB);
      case InspectionShiftType.middle:
        return const Color(0xFFEA580C);
      case InspectionShiftType.night:
        return const Color(0xFF7C3AED);
      case InspectionShiftType.rest:
        return const Color(0xFF98A2B3);
    }
  }

  Future<void> _persistRecords() async {
    await widget.onRecordsChanged(cloneInspectionCalendarRecords(_records));
  }

  Future<void> _persistScheduleConfig() async {
    await widget.onScheduleConfigChanged(_scheduleConfig);
  }

  List<String> _assignedSlotsForDate(DateTime date) {
    return assignedInspectionSlotsForDate(date, _scheduleConfig);
  }

  int _completedAssignedCount(DateTime date, Set<String> completedSlots) {
    final assignedSlots = _assignedSlotsForDate(date);
    var count = 0;
    for (final slot in assignedSlots) {
      if (completedSlots.contains(slot)) {
        count++;
      }
    }
    return count;
  }

  bool _isAssignedInspectionDay(DateTime date) {
    return _assignedSlotsForDate(date).isNotEmpty;
  }

  bool _isAssignedInspectionDayCompleted(DateTime date) {
    final assignedSlots = _assignedSlotsForDate(date);
    if (assignedSlots.isEmpty) {
      return false;
    }
    final record =
        _records[formatInspectionCalendarDateKey(date)] ??
        InspectionCalendarDayRecord.empty(
          formatInspectionCalendarDateKey(date),
        );
    return _completedAssignedCount(date, record.completedSlots) >=
        assignedSlots.length;
  }

  void _applySlotsForDate(DateTime date, Set<String> completedSlots) {
    final dateKey = formatInspectionCalendarDateKey(date);
    final normalizedSlots = <String>{};
    for (final slot in completedSlots) {
      if (_slotLabels.contains(slot)) {
        normalizedSlots.add(slot);
      }
    }

    setState(() {
      if (normalizedSlots.isEmpty) {
        _records.remove(dateKey);
      } else {
        _records[dateKey] = InspectionCalendarDayRecord(
          dateKey: dateKey,
          completedSlots: normalizedSlots,
          updatedAt: DateTime.now().toIso8601String(),
        );
      }
    });
    unawaited(_persistRecords());
  }

  void _toggleSelectedSlot(String label) {
    final nextSlots = Set<String>.from(_selectedRecord.completedSlots);
    if (!nextSlots.add(label)) {
      nextSlots.remove(label);
    }
    _applySlotsForDate(_selectedDate, nextSlots);
  }

  void _markSelectedShiftCompleted() {
    if (_selectedAssignedSlots.isEmpty) {
      return;
    }
    final nextSlots = Set<String>.from(_selectedRecord.completedSlots)
      ..addAll(_selectedAssignedSlots);
    _applySlotsForDate(_selectedDate, nextSlots);
  }

  void _markSelectedDayAllCompleted() {
    _applySlotsForDate(_selectedDate, Set<String>.from(_slotLabels));
  }

  void _clearSelectedDay() {
    _applySlotsForDate(_selectedDate, <String>{});
  }

  void _markRecommendedSlotForSelectedDay() {
    if (_recommendedSlotLabel.isEmpty) {
      return;
    }
    final nextSlots = Set<String>.from(_selectedRecord.completedSlots)
      ..add(_recommendedSlotLabel);
    _applySlotsForDate(_selectedDate, nextSlots);
  }

  void _jumpToToday() {
    final now = normalizeInspectionCalendarDate(DateTime.now());
    setState(() {
      _visibleMonth = normalizeInspectionCalendarMonth(now);
      _selectedDate = now;
    });
  }

  void _changeMonth(int offset) {
    final nextMonth = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + offset,
    );
    final maxDay = DateUtils.getDaysInMonth(nextMonth.year, nextMonth.month);
    setState(() {
      _visibleMonth = nextMonth;
      _selectedDate = DateTime(
        nextMonth.year,
        nextMonth.month,
        math.min(_selectedDate.day, maxDay),
      );
    });
  }

  Future<void> _pickFirstMorningShiftDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _firstMorningShiftDate,
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: DateTime(now.year + 5, 12, 31),
      helpText: '选择第一个早班日期',
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _scheduleConfig = _scheduleConfig.copyWith(
        firstMorningShiftDateKey: formatInspectionCalendarDateKey(picked),
      );
    });
    unawaited(_persistScheduleConfig());
  }

  void _changeRotationMemberCount(int delta) {
    final nextCount = math.max(1, _scheduleConfig.rotationMemberCount + delta);
    if (nextCount == _scheduleConfig.rotationMemberCount) {
      return;
    }
    setState(() {
      _scheduleConfig = _scheduleConfig.copyWith(
        rotationMemberCount: nextCount,
      );
    });
    unawaited(_persistScheduleConfig());
  }

  Future<void> _pickFirstInspectionDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _firstInspectionDate,
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: DateTime(now.year + 5, 12, 31),
      helpText: '选择首次轮到巡检日期',
    );
    if (picked == null || !mounted) {
      return;
    }

    final normalizedPicked = normalizeInspectionCalendarDate(picked);
    final candidateSlots = inspectionRequiredSlotsForDate(
      normalizedPicked,
      _scheduleConfig,
    );
    if (candidateSlots.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('所选日期是休息日，不能作为首次轮值日期')));
      return;
    }

    final nextSlotLabel = candidateSlots.contains(_firstInspectionSlotLabel)
        ? _firstInspectionSlotLabel
        : candidateSlots.first;
    setState(() {
      _scheduleConfig = _scheduleConfig.copyWith(
        firstInspectionDateKey: formatInspectionCalendarDateKey(
          normalizedPicked,
        ),
        firstInspectionSlotLabel: nextSlotLabel,
      );
    });
    unawaited(_persistScheduleConfig());
  }

  void _setFirstInspectionSlotLabel(String label) {
    if (label.trim().isEmpty || label == _firstInspectionSlotLabel) {
      return;
    }
    setState(() {
      _scheduleConfig = _scheduleConfig.copyWith(
        firstInspectionSlotLabel: label,
      );
    });
    unawaited(_persistScheduleConfig());
  }

  List<DateTime?> _buildMonthCells() {
    final firstDayOfMonth = DateTime(
      _visibleMonth.year,
      _visibleMonth.month,
      1,
    );
    final daysInMonth = DateUtils.getDaysInMonth(
      _visibleMonth.year,
      _visibleMonth.month,
    );
    final leadingEmptyCount = firstDayOfMonth.weekday - 1;
    final cells = <DateTime?>[
      for (int i = 0; i < leadingEmptyCount; i++) null,
      for (int day = 1; day <= daysInMonth; day++)
        DateTime(_visibleMonth.year, _visibleMonth.month, day),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return cells;
  }

  int _countWorkingDaysInMonth(DateTime month) {
    final monthDays = DateUtils.getDaysInMonth(month.year, month.month);
    var count = 0;
    for (int day = 1; day <= monthDays; day++) {
      if (_isAssignedInspectionDay(DateTime(month.year, month.month, day))) {
        count++;
      }
    }
    return count;
  }

  int _countCompletedWorkingDaysInMonth(DateTime month) {
    final monthDays = DateUtils.getDaysInMonth(month.year, month.month);
    var count = 0;
    for (int day = 1; day <= monthDays; day++) {
      if (_isAssignedInspectionDayCompleted(
        DateTime(month.year, month.month, day),
      )) {
        count++;
      }
    }
    return count;
  }

  int _countRequiredInspectionsInMonth(DateTime month) {
    final monthDays = DateUtils.getDaysInMonth(month.year, month.month);
    var count = 0;
    for (int day = 1; day <= monthDays; day++) {
      count += _assignedSlotsForDate(
        DateTime(month.year, month.month, day),
      ).length;
    }
    return count;
  }

  int _countCompletedRequiredInspectionsInMonth(DateTime month) {
    final monthDays = DateUtils.getDaysInMonth(month.year, month.month);
    var count = 0;
    for (int day = 1; day <= monthDays; day++) {
      final date = DateTime(month.year, month.month, day);
      final record =
          _records[formatInspectionCalendarDateKey(date)] ??
          InspectionCalendarDayRecord.empty(
            formatInspectionCalendarDateKey(date),
          );
      count += _completedAssignedCount(date, record.completedSlots);
    }
    return count;
  }

  String _formatMonthTitle(DateTime month) {
    final value = month.toLocal();
    return '${value.year}年${value.month.toString().padLeft(2, '0')}月';
  }

  String _formatFullDate(DateTime date) {
    final local = date.toLocal();
    final weekday = kInspectionCalendarWeekdayLabels[local.weekday - 1];
    return '${local.year}年${local.month.toString().padLeft(2, '0')}月${local.day.toString().padLeft(2, '0')}日 周$weekday';
  }

  String _formatUpdatedAt(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      return raw.isEmpty ? '未记录' : raw;
    }
    final local = parsed.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute';
  }

  Widget _buildShiftPatternChips() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final shiftType in kInspectionShiftCycle)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _shiftColor(shiftType).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _shiftColor(shiftType).withValues(alpha: 0.2),
              ),
            ),
            child: Text(
              inspectionShiftTypeShortLabel(shiftType),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: _shiftColor(shiftType),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildShiftLegend() {
    final entries = <InspectionShiftType>[
      InspectionShiftType.morning,
      InspectionShiftType.middle,
      InspectionShiftType.night,
      InspectionShiftType.rest,
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final shiftType in entries)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _shiftColor(shiftType).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: _shiftColor(shiftType).withValues(alpha: 0.22),
              ),
            ),
            child: Text(
              shiftType == InspectionShiftType.rest
                  ? '休息：无需巡检'
                  : '${inspectionShiftTypeLabel(shiftType)}：${inspectionRequiredSlotsForShift(shiftType).join('、')}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _shiftColor(shiftType),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildUpcomingSchedulePreview() {
    final start = normalizeInspectionCalendarDate(DateTime.now());
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (int offset = 0; offset < 8; offset++)
          Builder(
            builder: (context) {
              final date = start.add(Duration(days: offset));
              final shiftType = inspectionShiftTypeForDate(
                date,
                _scheduleConfig,
              );
              final shiftSlots = inspectionRequiredSlotsForShift(shiftType);
              final assignedSlots = _assignedSlotsForDate(date);
              final isRestDay = shiftType == InspectionShiftType.rest;
              final isAssignedDay = assignedSlots.isNotEmpty;
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _shiftColor(shiftType).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _shiftColor(shiftType).withValues(alpha: 0.18),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${date.month}/${date.day}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      inspectionShiftTypeLabel(shiftType),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: _shiftColor(shiftType),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isRestDay
                          ? '当天休息'
                          : isAssignedDay
                          ? '轮到 ${assignedSlots.join('、')}'
                          : '今天轮休',
                      style: const TextStyle(fontSize: 11),
                    ),
                    if (!isRestDay) ...[
                      const SizedBox(height: 2),
                      Text(
                        '全班 ${shiftSlots.join('、')}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF667085),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildWeekdayHeader() {
    return Row(
      children: [
        for (final label in kInspectionCalendarWeekdayLabels)
          Expanded(
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF475467),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSlotLegend() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (int index = 0; index < _slotLabels.length; index++)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _slotColorForIndex(index).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: _slotColorForIndex(index).withValues(alpha: 0.26),
              ),
            ),
            child: Text(
              _slotLabels[index],
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _slotColorForIndex(index),
              ),
            ),
          ),
      ],
    );
  }

  String _compactSlotLabel(String label) {
    return label.replaceAll('点', '').trim();
  }

  Widget _buildShiftBadge(InspectionShiftType shiftType) {
    final shiftColor = _shiftColor(shiftType);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: shiftColor.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        inspectionShiftTypeShortLabel(shiftType),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: shiftColor,
          height: 1,
        ),
      ),
    );
  }

  Widget _buildAssignedSlotBadges(
    List<String> assignedSlots,
    Set<String> completedSlots,
    InspectionShiftType shiftType,
  ) {
    if (shiftType == InspectionShiftType.rest) {
      return const Text(
        '当日休息',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Color(0xFF98A2B3),
        ),
      );
    }

    if (assignedSlots.isEmpty) {
      return Text(
        '今天轮休',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: _shiftColor(shiftType).withValues(alpha: 0.8),
        ),
      );
    }

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (int index = 0; index < assignedSlots.length; index++)
          Container(
            constraints: const BoxConstraints(minWidth: 18),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: completedSlots.contains(assignedSlots[index])
                  ? _slotColorForIndex(index).withValues(alpha: 0.16)
                  : const Color(0xFFF2F4F7),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: completedSlots.contains(assignedSlots[index])
                    ? _slotColorForIndex(index).withValues(alpha: 0.45)
                    : const Color(0xFFD0D5DD),
              ),
            ),
            child: Text(
              _compactSlotLabel(assignedSlots[index]),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w800,
                color: completedSlots.contains(assignedSlots[index])
                    ? _slotColorForIndex(index)
                    : const Color(0xFF98A2B3),
                height: 1,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDayCell(DateTime? date) {
    if (date == null) {
      return const SizedBox.shrink();
    }

    final dateKey = formatInspectionCalendarDateKey(date);
    final record = _records[dateKey];
    final completedSlots = record?.completedSlots ?? const <String>{};
    final shiftType = inspectionShiftTypeForDate(date, _scheduleConfig);
    final assignedSlots = _assignedSlotsForDate(date);
    final assignedCount = assignedSlots.length;
    final completedAssignedCount = _completedAssignedCount(
      date,
      completedSlots,
    );
    final extraCompletedCount = completedSlots
        .where((slot) => !assignedSlots.contains(slot))
        .length;
    final isSelected = DateUtils.isSameDay(date, _selectedDate);
    final isToday = DateUtils.isSameDay(date, DateTime.now());
    final shiftColor = _shiftColor(shiftType);

    final borderColor = isSelected
        ? Theme.of(context).colorScheme.primary
        : isToday
        ? shiftColor.withValues(alpha: 0.9)
        : const Color(0xFFE4E7EC);
    final backgroundColor = isSelected
        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
        : shiftType == InspectionShiftType.rest
        ? const Color(0xFFF8FAFC)
        : assignedCount == 0
        ? shiftColor.withValues(alpha: 0.025)
        : shiftColor.withValues(alpha: 0.06);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        setState(() {
          _selectedDate = date;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(7, 7, 7, 6),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: isSelected ? 1.6 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${date.day}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    height: 1,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : const Color(0xFF101828),
                  ),
                ),
                const Spacer(),
                if (isToday)
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.only(top: 3),
                    decoration: const BoxDecoration(
                      color: Color(0xFF2563EB),
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                _buildShiftBadge(shiftType),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    shiftType == InspectionShiftType.rest
                        ? '休息'
                        : assignedCount == 0
                        ? '轮休'
                        : '$completedAssignedCount/$assignedCount',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF667085),
                      height: 1.1,
                    ),
                  ),
                ),
                if (extraCompletedCount > 0)
                  Container(
                    margin: const EdgeInsets.only(left: 3),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '+$extraCompletedCount',
                      style: const TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF4F46E5),
                        height: 1,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Align(
                alignment: Alignment.topLeft,
                child: _buildAssignedSlotBadges(
                  assignedSlots,
                  completedSlots,
                  shiftType,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = normalizeInspectionCalendarDate(DateTime.now());
    final todayShiftType = inspectionShiftTypeForDate(today, _scheduleConfig);
    final todayShiftRequiredSlots = inspectionRequiredSlotsForShift(
      todayShiftType,
    );
    final todayAssignedSlots = _assignedSlotsForDate(today);
    final todayRecord =
        _records[formatInspectionCalendarDateKey(today)] ??
        InspectionCalendarDayRecord.empty(
          formatInspectionCalendarDateKey(today),
        );
    final todayCompletedCount = _completedAssignedCount(
      today,
      todayRecord.completedSlots,
    );

    final selectedShiftRequiredSlots = _selectedRequiredSlots;
    final selectedAssignedSlots = _selectedAssignedSlots;
    final selectedAssignedCount = selectedAssignedSlots.length;
    final selectedCompletedCount = _completedAssignedCount(
      _selectedDate,
      _selectedRecord.completedSlots,
    );
    final selectedExtraCount =
        _selectedRecord.completedSlots.length - selectedCompletedCount;
    final selectedSummaryLabel = _selectedShiftType == InspectionShiftType.rest
        ? '休息'
        : selectedAssignedCount == 0
        ? '轮休'
        : '$selectedCompletedCount/$selectedAssignedCount';
    final selectedPrimaryDescription =
        _selectedShiftType == InspectionShiftType.rest
        ? '这一天是休息日，无需巡检。'
        : selectedAssignedCount == 0
        ? '这一天是${inspectionShiftTypeLabel(_selectedShiftType)}，但这次没有轮到你。'
        : '这一天轮到你巡检：${selectedAssignedSlots.join('、')}。';
    final selectedSecondaryDescription =
        _selectedShiftType == InspectionShiftType.rest
        ? ''
        : '全班应巡时段：${selectedShiftRequiredSlots.join('、')}';

    final monthWorkingDays = _countWorkingDaysInMonth(_visibleMonth);
    final monthCompletedDays = _countCompletedWorkingDaysInMonth(_visibleMonth);
    final monthRequiredCount = _countRequiredInspectionsInMonth(_visibleMonth);
    final monthCompletedCount = _countCompletedRequiredInspectionsInMonth(
      _visibleMonth,
    );
    final progressValue = monthRequiredCount == 0
        ? 0.0
        : monthCompletedCount / monthRequiredCount;
    final cells = _buildMonthCells();

    return Scaffold(
      appBar: AppBar(
        title: const Text('巡检日历'),
        actions: [
          TextButton.icon(
            onPressed: _jumpToToday,
            icon: const Icon(Icons.today_outlined),
            label: const Text('今天'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE4E7EC)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '个人排班计划',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                const Text(
                  '按“早早中中晚晚休休”8天循环，再结合轮班人数与首次轮值日期，自动算出今天是否轮到你以及该巡哪个时段。',
                  style: TextStyle(fontSize: 13, color: Color(0xFF667085)),
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompact = constraints.maxWidth < 420;
                    final itemWidth = isCompact
                        ? (constraints.maxWidth - 10) / 2
                        : (constraints.maxWidth - 20) / 3;
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        SizedBox(
                          width: itemWidth,
                          child: _InspectionCalendarStatTile(
                            label: '本月轮到天',
                            value: '$monthCompletedDays/$monthWorkingDays',
                            hint: '按个人轮值',
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _InspectionCalendarStatTile(
                            label: '本月轮到次',
                            value: '$monthCompletedCount/$monthRequiredCount',
                            hint: '按个人轮值',
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _InspectionCalendarStatTile(
                            label: '今日安排',
                            value: todayShiftType == InspectionShiftType.rest
                                ? '休息'
                                : todayAssignedSlots.isEmpty
                                ? '轮休'
                                : '$todayCompletedCount/${todayAssignedSlots.length}',
                            hint: todayShiftType == InspectionShiftType.rest
                                ? '今天无需巡检'
                                : todayAssignedSlots.isEmpty
                                ? '班次 ${inspectionShiftTypeLabel(todayShiftType)} · 全班 ${todayShiftRequiredSlots.join('、')}'
                                : '轮到 ${todayAssignedSlots.join('、')} · 全班 ${todayShiftRequiredSlots.join('、')}',
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progressValue.clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: const Color(0xFFE4E7EC),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF2563EB),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '第一个早班日期：${_scheduleConfig.firstMorningShiftDateKey}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _pickFirstMorningShiftDate,
                      icon: const Icon(Icons.edit_calendar_outlined),
                      label: const Text('改起始早班'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '轮班人数：${_scheduleConfig.rotationMemberCount} 人',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton.outlined(
                      onPressed: _scheduleConfig.rotationMemberCount <= 1
                          ? null
                          : () => _changeRotationMemberCount(-1),
                      icon: const Icon(Icons.remove),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: () => _changeRotationMemberCount(1),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '首次轮到巡检：${_scheduleConfig.firstInspectionDateKey}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _pickFirstInspectionDate,
                      icon: const Icon(Icons.event_repeat_outlined),
                      label: const Text('改首次轮值'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _firstInspectionShiftType == InspectionShiftType.rest
                      ? '首次轮值日期不能是休息日，请重新选择。'
                      : _firstInspectionShiftType == InspectionShiftType.night
                      ? '首次轮值是晚班，请再选一个起始时段。'
                      : '首次轮值班次：${inspectionShiftTypeLabel(_firstInspectionShiftType)}，起始时段会自动固定为 ${_firstInspectionSlotLabel}。',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF667085),
                  ),
                ),
                if (_firstInspectionCandidateSlots.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final slotLabel in _firstInspectionCandidateSlots)
                        ChoiceChip(
                          label: Text(slotLabel),
                          selected: _firstInspectionSlotLabel == slotLabel,
                          onSelected: _firstInspectionCandidateSlots.length == 1
                              ? null
                              : (_) => _setFirstInspectionSlotLabel(slotLabel),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                _buildShiftPatternChips(),
                const SizedBox(height: 12),
                _buildShiftLegend(),
                const SizedBox(height: 12),
                _buildUpcomingSchedulePreview(),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE4E7EC)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0A101828),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => _changeMonth(-1),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Text(
                        _formatMonthTitle(_visibleMonth),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _changeMonth(1),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildSlotLegend(),
                const SizedBox(height: 16),
                _buildWeekdayHeader(),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompact = constraints.maxWidth < 380;
                    final spacing = isCompact ? 5.0 : 8.0;
                    final cellWidth = (constraints.maxWidth - spacing * 6) / 7;
                    final cellHeight = math.max(
                      isCompact ? 92.0 : 100.0,
                      cellWidth * (isCompact ? 1.5 : 1.55),
                    );
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: cells.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7,
                        crossAxisSpacing: spacing,
                        mainAxisSpacing: spacing,
                        mainAxisExtent: cellHeight,
                      ),
                      itemBuilder: (context, index) =>
                          _buildDayCell(cells[index]),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE4E7EC)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0A101828),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatFullDate(_selectedDate),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '班次：${inspectionShiftTypeLabel(_selectedShiftType)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _shiftColor(_selectedShiftType),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _shiftColor(
                          _selectedShiftType,
                        ).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        selectedSummaryLabel,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _shiftColor(_selectedShiftType),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  selectedPrimaryDescription,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF667085),
                  ),
                ),
                if (selectedSecondaryDescription.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    selectedSecondaryDescription,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF667085),
                    ),
                  ),
                ],
                if (_selectedDateIsToday &&
                    _recommendedSlotLabel.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    '当前时间最适合补记：$_recommendedSlotLabel',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                ],
                if (selectedExtraCount > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '另外还记录了 $selectedExtraCount 个非计划时段，系统会一并保留。',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF667085),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (int index = 0; index < _slotLabels.length; index++)
                      FilterChip(
                        selected: _selectedRecord.completedSlots.contains(
                          _slotLabels[index],
                        ),
                        showCheckmark: false,
                        avatar:
                            _selectedDateIsToday &&
                                _recommendedSlotLabel == _slotLabels[index]
                            ? Icon(
                                Icons.access_time_rounded,
                                size: 16,
                                color: _slotColorForIndex(index),
                              )
                            : selectedAssignedSlots.contains(_slotLabels[index])
                            ? Icon(
                                Icons.person_pin_circle_outlined,
                                size: 16,
                                color: _slotColorForIndex(index),
                              )
                            : selectedShiftRequiredSlots.contains(
                                _slotLabels[index],
                              )
                            ? Icon(
                                Icons.flag_outlined,
                                size: 16,
                                color: _shiftColor(_selectedShiftType),
                              )
                            : null,
                        label: Text(_slotLabels[index]),
                        selectedColor: _slotColorForIndex(
                          index,
                        ).withValues(alpha: 0.14),
                        side: BorderSide(
                          color:
                              _selectedRecord.completedSlots.contains(
                                _slotLabels[index],
                              )
                              ? _slotColorForIndex(index)
                              : const Color(0xFFD0D5DD),
                        ),
                        labelStyle: TextStyle(
                          fontWeight: FontWeight.w700,
                          color:
                              _selectedRecord.completedSlots.contains(
                                _slotLabels[index],
                              )
                              ? _slotColorForIndex(index)
                              : const Color(0xFF344054),
                        ),
                        onSelected: (_) =>
                            _toggleSelectedSlot(_slotLabels[index]),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  _selectedRecord.updatedAt.isEmpty
                      ? '当天暂未记录'
                      : '最后更新：${_formatUpdatedAt(_selectedRecord.updatedAt)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF667085),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (selectedAssignedCount > 0)
                      FilledButton.icon(
                        onPressed: _markSelectedShiftCompleted,
                        icon: const Icon(Icons.done_all_rounded),
                        label: const Text('完成我的轮值'),
                      ),
                    if (_selectedDateIsToday &&
                        _recommendedSlotLabel.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: _markRecommendedSlotForSelectedDay,
                        icon: const Icon(Icons.access_time_rounded),
                        label: Text('补记 $_recommendedSlotLabel'),
                      ),
                    OutlinedButton.icon(
                      onPressed: _markSelectedDayAllCompleted,
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('全部时段记完'),
                    ),
                    TextButton.icon(
                      onPressed: _selectedRecord.completedSlots.isEmpty
                          ? null
                          : _clearSelectedDay,
                      icon: const Icon(Icons.cleaning_services_outlined),
                      label: const Text('清空当天'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  '自动规则：排班计划会自动判断今天是不是轮到你，并给出当前最匹配的巡检时段；记录仍然会保留你手动补记的额外时段。',
                  style: TextStyle(fontSize: 12, color: Color(0xFF667085)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MeterRoomsPage extends StatefulWidget {
  final List<InspectionItem> allInspectionItems;
  final List<MeterRoom> meterRooms;
  final List<CameraDescription> cameras;
  final bool defaultIncomingCabinetOnlineOcrEnabled;
  final Future<void> Function(List<MeterRoom>) onSave;
  final MeterRoom Function(InspectionItem item) onCreateRoomFromInspection;

  const MeterRoomsPage({
    super.key,
    required this.allInspectionItems,
    required this.meterRooms,
    required this.cameras,
    required this.defaultIncomingCabinetOnlineOcrEnabled,
    required this.onSave,
    required this.onCreateRoomFromInspection,
  });

  @override
  State<MeterRoomsPage> createState() => _MeterRoomsPageState();
}

class _MeterRoomsPageState extends State<MeterRoomsPage> {
  late List<MeterRoom> _rooms;

  Map<String, dynamic> _buildMeterTemplatePayload() {
    return <String, dynamic>{
      'version': 2,
      'templateType': 'meter_room_template',
      'exportedAt': DateTime.now().toIso8601String(),
      'rooms': _rooms
          .map(
            (room) => <String, dynamic>{
              'roomId': room.roomId,
              'roomName': room.roomName,
              'roomType': room.roomType,
              'location': room.location,
              'devices': room.devices
                  .map((device) => <String, dynamic>{'name': device.name})
                  .toList(growable: false),
            },
          )
          .toList(growable: false),
    };
  }

  Map<String, dynamic> _buildMeterDataPayload() {
    final deviceCount = _rooms.fold<int>(
      0,
      (sum, room) => sum + room.devices.length,
    );

    return <String, dynamic>{
      'version': 2,
      'templateType': 'meter_room_data',
      'exportedAt': DateTime.now().toIso8601String(),
      'roomCount': _rooms.length,
      'deviceCount': deviceCount,
      'rooms': _rooms.map((room) => room.toJson()).toList(growable: false),
    };
  }

  List<MeterRoom> _parseMeterTemplateRooms(dynamic decoded) {
    final rooms = (decoded is Map<String, dynamic>)
        ? (decoded['rooms'] as List<dynamic>? ?? const <dynamic>[])
        : const <dynamic>[];

    return rooms
        .map((entry) {
          final roomMap = entry as Map<String, dynamic>;
          final deviceEntries =
              roomMap['devices'] as List<dynamic>? ?? const [];
          return MeterRoom(
            roomId: roomMap['roomId'] is int
                ? roomMap['roomId']
                : DateTime.now().millisecondsSinceEpoch,
            roomName: (roomMap['roomName'] ?? '').toString(),
            roomType: (roomMap['roomType'] ?? '').toString(),
            location: (roomMap['location'] ?? '').toString(),
            devices: deviceEntries
                .map(
                  (deviceEntry) => MeterDevice(
                    name:
                        (((deviceEntry as Map<String, dynamic>)['name']) ??
                                '未命名设备')
                            .toString(),
                  ),
                )
                .toList(growable: false),
          );
        })
        .toList(growable: false);
  }

  Future<void> _openMeterOverloadPage() async {
    await Navigator.push(
      context,
      buildAppRoute(
        page: MeterOverloadPage(
          currentRooms: _rooms,
          onApplyToCurrentRooms: (rooms) async {
            if (!mounted) {
              return;
            }
            setState(() {
              _rooms = rooms
                  .map(
                    (room) => MeterRoom(
                      roomId: room.roomId,
                      roomName: room.roomName,
                      roomType: room.roomType,
                      location: room.location,
                      devices: room.devices
                          .map(
                            (device) => MeterDevice(
                              name: device.name,
                              values: List<String>.from(device.values),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  )
                  .toList(growable: false);
            });
            await widget.onSave(_rooms);
          },
        ),
      ),
    );
  }

  Future<void> _exportRoomConfig() async {
    try {
      final data = _buildMeterTemplatePayload();

      final dir = await getTemporaryDirectory();
      final file = File(
        path.join(
          dir.path,
          '抄表设备模板_${DateTime.now().millisecondsSinceEpoch}.json',
        ),
      );
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(data),
      );

      await Share.shareXFiles([XFile(file.path)], text: '抄表设备模板导出');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出失败: $e')));
    }
  }

  Future<void> _importRoomConfig() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (picked == null || picked.files.single.path == null) return;

      final filePath = picked.files.single.path!;
      final text = await File(filePath).readAsString();
      final decoded = jsonDecode(text);
      final imported = _parseMeterTemplateRooms(decoded);
      if (imported.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('导入文件无有效设备模板')));
        return;
      }

      setState(() => _rooms = imported);
      await widget.onSave(_rooms);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已导入 ${_rooms.length} 个房间的设备模板')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导入失败: $e')));
    }
  }

  Future<void> _exportMeterData() async {
    try {
      final data = _buildMeterDataPayload();

      final dir = await getTemporaryDirectory();
      final file = File(
        path.join(
          dir.path,
          '当前抄表数据_${DateTime.now().millisecondsSinceEpoch}.json',
        ),
      );
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(data),
      );

      await Share.shareXFiles([XFile(file.path)], text: '当前抄表数据导出');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出失败: $e')));
    }
  }

  Future<void> _clearMeterValues() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('一键清空抄表数据'),
        content: const Text('将清空所有房间设备的抄表数值，房间和设备配置会保留，确定继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      for (final room in _rooms) {
        for (final device in room.devices) {
          device.values = List<String>.from(MeterDevice.defaultMeterValues());
        }
      }
    });
    await widget.onSave(_rooms);

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已清空抄表数据')));
  }

  @override
  void initState() {
    super.initState();
    _rooms = widget.meterRooms
        .map(
          (e) => MeterRoom(
            roomId: e.roomId,
            roomName: e.roomName,
            roomType: e.roomType,
            location: e.location,
            devices: e.devices
                .map(
                  (d) => MeterDevice(
                    name: d.name,
                    values: List<String>.from(d.values),
                  ),
                )
                .toList(),
          ),
        )
        .toList();
  }

  Future<void> _pickRoomAndAdd() async {
    final exists = _rooms.map((e) => e.roomId).toSet();
    final candidates = widget.allInspectionItems
        .where((e) => !exists.contains(e.id))
        .toList();
    if (candidates.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有可新增的房间了')));
      return;
    }

    InspectionItem? selected;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择房间加入抄表'),
        content: StatefulBuilder(
          builder: (context, setStateDialog) => SizedBox(
            width: 360,
            height: 420,
            child: ListView.builder(
              itemCount: candidates.length,
              itemBuilder: (context, index) {
                final it = candidates[index];
                return RadioListTile<int>(
                  value: it.id,
                  groupValue: selected?.id,
                  onChanged: (_) => setStateDialog(() => selected = it),
                  title: Text(it.serial),
                  subtitle: Text('${it.location} · ${it.type}'),
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              if (selected != null) Navigator.pop(context);
            },
            child: const Text('加入'),
          ),
        ],
      ),
    );

    if (selected == null) return;
    setState(() {
      _rooms.add(widget.onCreateRoomFromInspection(selected!));
    });
    await widget.onSave(_rooms);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('动力抄表')),
      floatingActionButton: ExpandableFab(
        heroTag: 'fab_main_action',
        actions: [
          FabMenuAction(
            label: '动力超标',
            icon: Icons.warning_amber_rounded,
            onTap: _openMeterOverloadPage,
          ),
          FabMenuAction(
            label: '添加房间',
            icon: Icons.add_home_work_outlined,
            onTap: _pickRoomAndAdd,
          ),
          FabMenuAction(
            label: '导入设备模板',
            icon: Icons.file_download_outlined,
            onTap: _importRoomConfig,
          ),
          FabMenuAction(
            label: '导出设备模板',
            icon: Icons.data_object_outlined,
            onTap: _exportRoomConfig,
          ),
          FabMenuAction(
            label: '导出当前抄表数据',
            icon: Icons.file_upload_outlined,
            onTap: _exportMeterData,
          ),
          FabMenuAction(
            label: '清空抄表数据',
            icon: Icons.cleaning_services_outlined,
            onTap: _clearMeterValues,
            danger: true,
          ),
        ],
      ),
      body: _rooms.isEmpty
          ? const Center(
              child: Text('还没有抄表房间\n点击右下角添加', textAlign: TextAlign.center),
            )
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 0.95,
              ),
              itemCount: _rooms.length,
              itemBuilder: (context, index) {
                final room = _rooms[index];
                return _RoomCard(
                  serial: room.roomName,
                  location: room.location,
                  isCompleted: false,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      buildAppRoute(
                        page: MeterDetailPage(
                          room: room,
                          cameras: widget.cameras,
                          defaultIncomingCabinetOnlineOcrEnabled:
                              widget.defaultIncomingCabinetOnlineOcrEnabled,
                          onChanged: () async {
                            await widget.onSave(_rooms);
                            if (mounted) setState(() {});
                          },
                        ),
                      ),
                    );
                  },
                  onLongPress: () async {
                    final del = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('移除房间'),
                        content: Text('确定移除 ${room.roomName} 吗？'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('取消'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('移除'),
                          ),
                        ],
                      ),
                    );
                    if (del == true) {
                      setState(() => _rooms.removeAt(index));
                      await widget.onSave(_rooms);
                    }
                  },
                );
              },
            ),
    );
  }
}

class MeterOverloadPage extends StatefulWidget {
  final List<MeterRoom> currentRooms;
  final Future<void> Function(List<MeterRoom> rooms)? onApplyToCurrentRooms;

  const MeterOverloadPage({
    super.key,
    this.currentRooms = const <MeterRoom>[],
    this.onApplyToCurrentRooms,
  });

  @override
  State<MeterOverloadPage> createState() => _MeterOverloadPageState();
}

class _MeterOverloadPageState extends State<MeterOverloadPage> {
  bool _isLoading = true;
  bool _isExporting = false;
  bool _isUpdatingSlot = false;
  bool _isApplyingToCurrent = false;
  int _selectedIndex = 0;
  String? _loadError;
  List<MeterTimeSlotDataset> _datasets = const [];
  List<MeterRoom> _currentRoomsDraft = const [];
  final math.Random _random = math.Random();
  late final TextEditingController _downRangeCtrl;
  late final TextEditingController _upRangeCtrl;
  Set<String> _lockedDeviceKeys = <String>{};

  bool get _isBusy => _isExporting || _isUpdatingSlot || _isApplyingToCurrent;

  int _nearestSlotIndex(DateTime now) {
    return nearestMeterTimeSlotIndex(now, slots: kDefaultMeterTimeSlots);
  }

  @override
  void initState() {
    super.initState();
    _currentRoomsDraft = _cloneMeterRooms(widget.currentRooms);
    _downRangeCtrl = TextEditingController(text: '5');
    _upRangeCtrl = TextEditingController(text: '5');
    _loadDatasets();
  }

  @override
  void dispose() {
    _downRangeCtrl.dispose();
    _upRangeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDatasets() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final datasets = <MeterTimeSlotDataset>[];
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(kPrefMeterOverloadTemplatesKey);
      if (stored != null && stored.trim().isNotEmpty) {
        final decodedList = jsonDecode(stored);
        if (decodedList is List) {
          for (final entry in decodedList.whereType<Map>()) {
            final map = Map<String, dynamic>.from(
              entry.map((key, value) => MapEntry(key.toString(), value)),
            );
            final label = (map['label'] ?? '').toString().trim();
            final assetPath = (map['assetPath'] ?? '').toString().trim();
            final rawData = map['rawData'];
            if (label.isEmpty || rawData is! Map) {
              continue;
            }
            final normalizedRawData = Map<String, dynamic>.from(
              rawData.map((key, value) => MapEntry(key.toString(), value)),
            );
            datasets.add(
              MeterTimeSlotDataset(
                slot: MeterTimeSlotDefinition(
                  label: label,
                  assetPath: assetPath,
                ),
                exportedAt: (normalizedRawData['exportedAt'] ?? '').toString(),
                rawData: normalizedRawData,
                rooms: _parseMeterRoomsFromRawData(normalizedRawData),
              ),
            );
          }
        }
      }

      if (datasets.isEmpty) {
        for (final slot in kDefaultMeterTimeSlots) {
          final text = await rootBundle.loadString(slot.assetPath);
          final decoded = jsonDecode(text);
          if (decoded is! Map<String, dynamic>) {
            throw const FormatException('时段数据格式不正确');
          }

          datasets.add(
            MeterTimeSlotDataset(
              slot: slot,
              exportedAt: (decoded['exportedAt'] ?? '').toString(),
              rawData: Map<String, dynamic>.from(decoded),
              rooms: _parseMeterRoomsFromRawData(decoded),
            ),
          );
        }
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _datasets = datasets;
        _selectedIndex = datasets.isEmpty
            ? 0
            : _nearestSlotIndex(DateTime.now()).clamp(0, datasets.length - 1);
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = error.toString();
        _isLoading = false;
      });
    }
  }

  List<MeterRoom> _parseMeterRoomsFromRawData(Map<String, dynamic> rawData) {
    final rooms = <MeterRoom>[];
    final rawRooms = rawData['rooms'];
    if (rawRooms is List) {
      for (final entry in rawRooms) {
        if (entry is Map) {
          rooms.add(
            MeterRoom.fromJson(
              Map<String, dynamic>.from(
                entry.map((key, value) => MapEntry(key.toString(), value)),
              ),
            ),
          );
        }
      }
    }
    return rooms;
  }

  String _formatExportedAt(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      return raw.isEmpty ? '未知' : raw;
    }
    final local = parsed.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute';
  }

  int _decimalPlaces(String raw) {
    final normalized = raw.trim();
    final dotIndex = normalized.indexOf('.');
    if (dotIndex < 0) {
      return 0;
    }
    return normalized.length - dotIndex - 1;
  }

  String _formatRandomizedValue(double value, String originalRaw) {
    final decimals = _decimalPlaces(originalRaw);
    return value.toStringAsFixed(decimals);
  }

  String _deviceLockKey(
    MeterTimeSlotDataset dataset,
    MeterRoom room,
    MeterDevice device,
  ) {
    return '${dataset.slot.label}::${room.roomId}::${device.name}';
  }

  bool _isDeviceLocked(
    MeterTimeSlotDataset dataset,
    MeterRoom room,
    MeterDevice device,
  ) {
    return _lockedDeviceKeys.contains(_deviceLockKey(dataset, room, device));
  }

  int _lockedDeviceCountForDataset(MeterTimeSlotDataset dataset) {
    var count = 0;
    for (final room in dataset.rooms) {
      for (final device in room.devices) {
        if (_isDeviceLocked(dataset, room, device)) {
          count++;
        }
      }
    }
    return count;
  }

  List<Map<String, dynamic>> _lockedDeviceSummariesForDataset(
    MeterTimeSlotDataset dataset,
  ) {
    final summaries = <Map<String, dynamic>>[];
    for (final room in dataset.rooms) {
      for (final device in room.devices) {
        if (_isDeviceLocked(dataset, room, device)) {
          summaries.add({
            'roomId': room.roomId,
            'roomName': room.roomName,
            'deviceName': device.name,
          });
        }
      }
    }
    return summaries;
  }

  MeterRoom _cloneMeterRoom(MeterRoom room) {
    return MeterRoom(
      roomId: room.roomId,
      roomName: room.roomName,
      roomType: room.roomType,
      location: room.location,
      devices: room.devices
          .map(
            (device) => MeterDevice(
              name: device.name,
              values: List<String>.from(device.values),
            ),
          )
          .toList(growable: false),
    );
  }

  List<MeterRoom> _cloneMeterRooms(List<MeterRoom> rooms) {
    return rooms.map(_cloneMeterRoom).toList(growable: false);
  }

  int get _currentRoomCount => _currentRoomsDraft.length;

  int get _currentDeviceCount =>
      _currentRoomsDraft.fold<int>(0, (sum, room) => sum + room.devices.length);

  ({double downPercent, double upPercent})? _readRandomRangePercent() {
    final down = double.tryParse(_downRangeCtrl.text.trim());
    final up = double.tryParse(_upRangeCtrl.text.trim());
    if (down == null || up == null || down < 0 || up < 0) {
      return null;
    }
    return (downPercent: down, upPercent: up);
  }

  String _randomizeCurrentValue(
    String raw,
    double downPercent,
    double upPercent,
  ) {
    final original = double.tryParse(raw.trim());
    if (original == null || original == 0) {
      return raw;
    }

    final minFactor = math.max(0.0, 1 - downPercent / 100);
    final maxFactor = 1 + upPercent / 100;
    final factor = minFactor + _random.nextDouble() * (maxFactor - minFactor);
    final randomized = math.max(0.0, original * factor);
    return _formatRandomizedValue(randomized, raw);
  }

  Map<String, dynamic> _buildRandomizedPayload(
    MeterTimeSlotDataset dataset, {
    required double downPercent,
    required double upPercent,
  }) {
    int randomizedValueCount = 0;
    final lockedDeviceSummaries = _lockedDeviceSummariesForDataset(dataset);
    final randomizedRooms = dataset.rooms.map((room) {
      return {
        'roomId': room.roomId,
        'roomName': room.roomName,
        'roomType': room.roomType,
        'location': room.location,
        'devices': room.devices.map((device) {
          final values = List<String>.from(device.values);
          if (!_isDeviceLocked(dataset, room, device)) {
            for (int i = 3; i <= 5 && i < values.length; i++) {
              final oldValue = values[i];
              final newValue = _randomizeCurrentValue(
                oldValue,
                downPercent,
                upPercent,
              );
              if (newValue != oldValue) {
                randomizedValueCount++;
              }
              values[i] = newValue;
            }
          }
          return {'name': device.name, 'values': values};
        }).toList(),
      };
    }).toList();

    final payload = Map<String, dynamic>.from(dataset.rawData);
    payload['rooms'] = randomizedRooms;
    payload['selectedTimeSlot'] = dataset.slot.label;
    payload['randomized'] = true;
    payload['randomizedAt'] = DateTime.now().toIso8601String();
    payload['randomizedValueCount'] = randomizedValueCount;
    payload['lockedDeviceCount'] = lockedDeviceSummaries.length;
    payload['lockedDevices'] = lockedDeviceSummaries;
    payload['randomRangePercent'] = {'down': downPercent, 'up': upPercent};
    return payload;
  }

  Map<String, dynamic> _serializeDatasetEntry(MeterTimeSlotDataset dataset) {
    return <String, dynamic>{
      'label': dataset.slot.label,
      'assetPath': dataset.slot.assetPath,
      'rawData': dataset.rawData,
    };
  }

  Map<String, dynamic> _buildStoredPayloadFromCurrentRooms(
    MeterTimeSlotDataset dataset, {
    required String exportedAt,
  }) {
    final payload = Map<String, dynamic>.from(dataset.rawData);
    payload.remove('selectedTimeSlot');
    payload.remove('exportedFromAppAt');
    payload.remove('randomized');
    payload.remove('randomizedAt');
    payload.remove('randomizedValueCount');
    payload.remove('lockedDeviceCount');
    payload.remove('lockedDevices');
    payload.remove('randomRangePercent');
    payload['version'] = (payload['version'] as num?)?.toInt() ?? 1;
    payload['exportedAt'] = exportedAt;
    payload['updatedFromCurrentMeterDataAt'] = exportedAt;
    payload['rooms'] = _currentRoomsDraft
        .map((room) => room.toJson())
        .toList(growable: false);
    return payload;
  }

  Set<String> _pruneLockedKeysForDataset(
    MeterTimeSlotDataset dataset,
    Set<String> source,
  ) {
    final validKeys = <String>{};
    for (final room in dataset.rooms) {
      for (final device in room.devices) {
        validKeys.add(_deviceLockKey(dataset, room, device));
      }
    }

    return source.where((key) {
      if (!key.startsWith('${dataset.slot.label}::')) {
        return true;
      }
      return validKeys.contains(key);
    }).toSet();
  }

  Future<bool> _confirmWriteCurrentRoomsToSelectedSlot(
    MeterTimeSlotDataset dataset,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('写入 ${dataset.slot.label} 时段'),
          content: Text(
            '这会用当前抄表页的 $_currentRoomCount 个房间、$_currentDeviceCount 台设备覆盖 ${dataset.slot.label} 时段模板。\n\n'
            '写入后，这个时段后续的导出和云端同步都会使用新数据。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认写入'),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  Future<void> _writeCurrentRoomsToSelectedSlot() async {
    if (_datasets.isEmpty || _isUpdatingSlot) {
      return;
    }
    if (_currentRoomsDraft.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前没有可写入的抄表数据')));
      return;
    }

    final currentDataset = _datasets[_selectedIndex];
    final confirmed = await _confirmWriteCurrentRoomsToSelectedSlot(
      currentDataset,
    );
    if (!confirmed || !mounted) {
      return;
    }

    setState(() {
      _isUpdatingSlot = true;
    });

    try {
      final exportedAt = DateTime.now().toIso8601String();
      final updatedRawData = _buildStoredPayloadFromCurrentRooms(
        currentDataset,
        exportedAt: exportedAt,
      );
      final updatedDataset = MeterTimeSlotDataset(
        slot: currentDataset.slot,
        exportedAt: exportedAt,
        rawData: updatedRawData,
        rooms: _parseMeterRoomsFromRawData(updatedRawData),
      );
      final nextDatasets = List<MeterTimeSlotDataset>.from(_datasets);
      nextDatasets[_selectedIndex] = updatedDataset;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        kPrefMeterOverloadTemplatesKey,
        jsonEncode(
          nextDatasets.map(_serializeDatasetEntry).toList(growable: false),
        ),
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _datasets = nextDatasets;
        _lockedDeviceKeys = _pruneLockedKeysForDataset(
          updatedDataset,
          _lockedDeviceKeys,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已将当前抄表数据写入 ${currentDataset.slot.label} 时段')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('写入时段失败: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingSlot = false;
        });
      }
    }
  }

  Future<bool> _confirmApplySelectedSlotToCurrentRooms(
    MeterTimeSlotDataset dataset,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('应用 ${dataset.slot.label} 时段'),
          content: Text(
            '这会用 ${dataset.slot.label} 时段模板的 ${dataset.roomCount} 个房间、${dataset.deviceCount} 台设备覆盖当前抄表数据。\n\n'
            '覆盖后，抄表页里的当前房间设备数据会立即变成这个时段模板内容。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认覆盖'),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  Future<void> _applySelectedSlotToCurrentRooms() async {
    if (_datasets.isEmpty || _isApplyingToCurrent) {
      return;
    }
    final applyCallback = widget.onApplyToCurrentRooms;
    if (applyCallback == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前入口不支持回写到抄表数据')));
      return;
    }

    final currentDataset = _datasets[_selectedIndex];
    final confirmed = await _confirmApplySelectedSlotToCurrentRooms(
      currentDataset,
    );
    if (!confirmed || !mounted) {
      return;
    }

    setState(() {
      _isApplyingToCurrent = true;
    });

    try {
      final nextRooms = _cloneMeterRooms(currentDataset.rooms);
      await applyCallback(nextRooms);
      if (!mounted) {
        return;
      }
      setState(() {
        _currentRoomsDraft = _cloneMeterRooms(nextRooms);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已将 ${currentDataset.slot.label} 时段模板覆盖到当前抄表数据'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('覆盖当前抄表数据失败: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isApplyingToCurrent = false;
        });
      }
    }
  }

  Future<void> _openLockedDevicePage() async {
    if (_datasets.isEmpty) {
      return;
    }

    final dataset = _datasets[_selectedIndex];
    final result = await Navigator.push<Set<String>>(
      context,
      buildAppRoute(
        page: MeterLockedDevicesPage(
          dataset: dataset,
          initialLockedKeys: _lockedDeviceKeys,
        ),
      ),
    );
    if (result == null || !mounted) {
      return;
    }
    setState(() {
      _lockedDeviceKeys = result;
    });
  }

  Future<void> _exportSelectedDataset() async {
    if (_datasets.isEmpty || _isBusy) {
      return;
    }

    setState(() {
      _isExporting = true;
    });

    try {
      final dataset = _datasets[_selectedIndex];
      final dir = await getTemporaryDirectory();
      final file = File(
        path.join(
          dir.path,
          '动力超标_${dataset.slot.label}_${DateTime.now().millisecondsSinceEpoch}.json',
        ),
      );
      final payload = Map<String, dynamic>.from(dataset.rawData);
      payload['selectedTimeSlot'] = dataset.slot.label;
      payload['exportedFromAppAt'] = DateTime.now().toIso8601String();

      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
      );
      await Share.shareXFiles([
        XFile(file.path),
      ], text: '动力超标 ${dataset.slot.label} 时段数据导出');
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出失败: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  Future<void> _exportRandomizedDataset() async {
    if (_datasets.isEmpty || _isBusy) {
      return;
    }

    final range = _readRandomRangePercent();
    if (range == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入有效的浮动百分比，且不能小于 0')));
      return;
    }

    setState(() {
      _isExporting = true;
    });

    try {
      final dataset = _datasets[_selectedIndex];
      final dir = await getTemporaryDirectory();
      final file = File(
        path.join(
          dir.path,
          '动力超标_${dataset.slot.label}_随机浮动_${DateTime.now().millisecondsSinceEpoch}.json',
        ),
      );
      final payload = _buildRandomizedPayload(
        dataset,
        downPercent: range.downPercent,
        upPercent: range.upPercent,
      );
      payload['exportedFromAppAt'] = DateTime.now().toIso8601String();

      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
      );
      await Share.shareXFiles(
        [XFile(file.path)],
        text:
            '动力超标 ${dataset.slot.label} 随机浮动数据导出（-${range.downPercent}% / +${range.upPercent}%）',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('随机导出失败: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  Widget _buildRangeInput({
    required String label,
    required String suffix,
    required TextEditingController controller,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}$')),
      ],
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dataset = _datasets.isEmpty ? null : _datasets[_selectedIndex];
    final lockedDeviceCount = dataset == null
        ? 0
        : _lockedDeviceCountForDataset(dataset);

    return Scaffold(
      appBar: AppBar(title: const Text('动力超标')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 42,
                      color: Colors.redAccent,
                    ),
                    const SizedBox(height: 12),
                    Text('时段数据加载失败\n$_loadError', textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _loadDatasets,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重新加载'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          '时段导出',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '已接入 csv 目录下的五套电流时段数据。先选一个时段，可以导出，也可以把当前抄表页数据回写到这个时段模板。',
                          style: TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                for (int index = 0; index < _datasets.length; index++) ...[
                  Builder(
                    builder: (context) {
                      final entry = _datasets[index];
                      final isSelected = _selectedIndex == index;
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _selectedIndex = index;
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Icon(
                                  isSelected
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_off,
                                  color: isSelected
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.black45,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${entry.slot.label} 时段',
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '房间 ${entry.roomCount} 个 · 设备 ${entry.deviceCount} 台 · 录入时间 ${_formatExportedAt(entry.exportedAt)}',
                                        style: const TextStyle(
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                ],
                if (dataset != null)
                  Card(
                    color: Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withValues(alpha: 0.45),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '当前选择: ${dataset.slot.label}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text('房间数量: ${dataset.roomCount}'),
                          Text('设备数量: ${dataset.deviceCount}'),
                          Text('电流值数量: ${dataset.currentValueCount}'),
                          Text(
                            '源数据时间: ${_formatExportedAt(dataset.exportedAt)}',
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.tonalIcon(
                              onPressed: _currentRoomCount == 0 || _isBusy
                                  ? null
                                  : _writeCurrentRoomsToSelectedSlot,
                              icon: _isUpdatingSlot
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.save_as_outlined),
                              label: Text(
                                _isUpdatingSlot ? '写入中...' : '将当前抄表数据写入本时段',
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed:
                                  widget.onApplyToCurrentRooms == null ||
                                      dataset.roomCount == 0 ||
                                      _isBusy
                                  ? null
                                  : _applySelectedSlotToCurrentRooms,
                              icon: _isApplyingToCurrent
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.download_for_offline_outlined,
                                    ),
                              label: Text(
                                _isApplyingToCurrent
                                    ? '覆盖中...'
                                    : '将本时段模板覆盖到当前抄表数据',
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '当前可写入数据：$_currentRoomCount 个房间，$_currentDeviceCount 台设备。',
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '当前时段模板：${dataset.roomCount} 个房间，${dataset.deviceCount} 台设备。',
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '随机浮动导出',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '仅处理非零电流值，电压列和为 0 的电流值保持不变。浮动按百分比计算，例如 5 表示最多下浮 5% 或上浮 5%。',
                          style: TextStyle(color: Colors.black54),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: dataset == null || _isBusy
                                ? null
                                : _openLockedDevicePage,
                            icon: const Icon(Icons.lock_outline),
                            label: Text(
                              lockedDeviceCount > 0
                                  ? '锁定设备 ($lockedDeviceCount)'
                                  : '锁定设备',
                            ),
                          ),
                        ),
                        if (lockedDeviceCount > 0) ...[
                          const SizedBox(height: 10),
                          Text(
                            '当前时段已有 $lockedDeviceCount 台设备被锁定，随机导出时这些设备不会参与随机。',
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: _buildRangeInput(
                                label: '向下浮动',
                                suffix: '%',
                                controller: _downRangeCtrl,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildRangeInput(
                                label: '向上浮动',
                                suffix: '%',
                                controller: _upRangeCtrl,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: dataset == null || _isBusy
                        ? null
                        : _exportSelectedDataset,
                    icon: _isExporting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.ios_share_outlined),
                    label: Text(_isExporting ? '导出中...' : '导出选中时段数据'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: dataset == null || _isBusy
                        ? null
                        : _exportRandomizedDataset,
                    icon: _isExporting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.shuffle),
                    label: Text(_isExporting ? '导出中...' : '随机处理后导出'),
                  ),
                ),
              ],
            ),
    );
  }
}

class MeterLockedDevicesPage extends StatefulWidget {
  final MeterTimeSlotDataset dataset;
  final Set<String> initialLockedKeys;

  const MeterLockedDevicesPage({
    super.key,
    required this.dataset,
    required this.initialLockedKeys,
  });

  @override
  State<MeterLockedDevicesPage> createState() => _MeterLockedDevicesPageState();
}

class _MeterLockedDevicesPageState extends State<MeterLockedDevicesPage> {
  late Set<String> _draftLockedKeys;
  late final TextEditingController _searchCtrl;
  bool _showLockedOnly = false;

  @override
  void initState() {
    super.initState();
    _draftLockedKeys = Set<String>.from(widget.initialLockedKeys);
    _searchCtrl = TextEditingController()..addListener(_handleSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl
      ..removeListener(_handleSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  String _deviceKey(MeterRoom room, MeterDevice device) {
    return '${widget.dataset.slot.label}::${room.roomId}::${device.name}';
  }

  bool _isLocked(MeterRoom room, MeterDevice device) {
    return _draftLockedKeys.contains(_deviceKey(room, device));
  }

  bool _matchesQuery(MeterRoom room, MeterDevice device) {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }
    final haystack =
        '${room.roomName} ${room.location} ${room.roomType} ${device.name}'
            .toLowerCase();
    return haystack.contains(query);
  }

  List<MeterDevice> _visibleDevicesForRoom(MeterRoom room) {
    return room.devices.where((device) {
      if (_showLockedOnly && !_isLocked(room, device)) {
        return false;
      }
      return _matchesQuery(room, device);
    }).toList();
  }

  int _lockedCountForRoom(MeterRoom room) {
    return room.devices.where((device) => _isLocked(room, device)).length;
  }

  int _visibleLockedCountForRoom(MeterRoom room) {
    return _visibleDevicesForRoom(
      room,
    ).where((device) => _isLocked(room, device)).length;
  }

  int get _totalDeviceCount => widget.dataset.deviceCount;

  int get _lockedDeviceCount {
    var count = 0;
    for (final room in widget.dataset.rooms) {
      count += _lockedCountForRoom(room);
    }
    return count;
  }

  int get _visibleDeviceCount {
    var count = 0;
    for (final room in widget.dataset.rooms) {
      count += _visibleDevicesForRoom(room).length;
    }
    return count;
  }

  void _setDeviceLocked(MeterRoom room, MeterDevice device, bool locked) {
    final key = _deviceKey(room, device);
    setState(() {
      if (locked) {
        _draftLockedKeys.add(key);
      } else {
        _draftLockedKeys.remove(key);
      }
    });
  }

  void _setDevicesLocked(
    Iterable<MapEntry<MeterRoom, MeterDevice>> targets,
    bool locked,
  ) {
    setState(() {
      for (final entry in targets) {
        final key = _deviceKey(entry.key, entry.value);
        if (locked) {
          _draftLockedKeys.add(key);
        } else {
          _draftLockedKeys.remove(key);
        }
      }
    });
  }

  Iterable<MapEntry<MeterRoom, MeterDevice>> _visibleEntries() sync* {
    for (final room in widget.dataset.rooms) {
      for (final device in _visibleDevicesForRoom(room)) {
        yield MapEntry(room, device);
      }
    }
  }

  void _lockAllVisible() {
    _setDevicesLocked(_visibleEntries(), true);
  }

  void _unlockAllVisible() {
    _setDevicesLocked(_visibleEntries(), false);
  }

  void _clearCurrentSlotLocks() {
    setState(() {
      for (final room in widget.dataset.rooms) {
        for (final device in room.devices) {
          _draftLockedKeys.remove(_deviceKey(room, device));
        }
      }
    });
  }

  void _setRoomVisibleDevicesLocked(MeterRoom room, bool locked) {
    final entries = _visibleDevicesForRoom(
      room,
    ).map((device) => MapEntry(room, device));
    _setDevicesLocked(entries, locked);
  }

  @override
  Widget build(BuildContext context) {
    final visibleRooms = widget.dataset.rooms
        .where((room) => _visibleDevicesForRoom(room).isNotEmpty)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('锁定设备 - ${widget.dataset.slot.label}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _draftLockedKeys),
            child: const Text('保存'),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, _draftLockedKeys),
                  child: const Text('保存锁定'),
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: '搜索房间名、位置或设备名',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchCtrl.text.trim().isEmpty
                        ? null
                        : IconButton(
                            onPressed: _searchCtrl.clear,
                            icon: const Icon(Icons.close),
                          ),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '当前时段：${widget.dataset.slot.label}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '已锁定 $_lockedDeviceCount / $_totalDeviceCount 台设备，当前筛选显示 $_visibleDeviceCount 台。',
                          style: const TextStyle(color: Colors.black54),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            FilterChip(
                              selected: _showLockedOnly,
                              onSelected: (value) {
                                setState(() {
                                  _showLockedOnly = value;
                                });
                              },
                              label: const Text('仅看已锁定'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _visibleDeviceCount == 0
                                  ? null
                                  : _lockAllVisible,
                              icon: const Icon(Icons.lock),
                              label: const Text('锁定当前筛选'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _visibleDeviceCount == 0
                                  ? null
                                  : _unlockAllVisible,
                              icon: const Icon(Icons.lock_open),
                              label: const Text('解锁当前筛选'),
                            ),
                            TextButton(
                              onPressed: _lockedDeviceCount == 0
                                  ? null
                                  : _clearCurrentSlotLocks,
                              child: const Text('清空本时段锁定'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: visibleRooms.isEmpty
                ? const Center(
                    child: Text(
                      '当前没有匹配到设备\n可以试试清空搜索或关闭“仅看已锁定”',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: visibleRooms.length,
                    itemBuilder: (context, index) {
                      final room = visibleRooms[index];
                      final visibleDevices = _visibleDevicesForRoom(room);
                      final roomLockedCount = _lockedCountForRoom(room);
                      final visibleLockedCount = _visibleLockedCountForRoom(
                        room,
                      );

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          room.roomName,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${room.location} · 当前显示 ${visibleDevices.length}/${room.devices.length} 台 · 已锁定 $roomLockedCount 台',
                                          style: const TextStyle(
                                            color: Colors.black54,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    children: [
                                      OutlinedButton(
                                        onPressed: visibleDevices.isEmpty
                                            ? null
                                            : () =>
                                                  _setRoomVisibleDevicesLocked(
                                                    room,
                                                    true,
                                                  ),
                                        child: const Text('本房全锁'),
                                      ),
                                      const SizedBox(height: 8),
                                      OutlinedButton(
                                        onPressed: visibleLockedCount == 0
                                            ? null
                                            : () =>
                                                  _setRoomVisibleDevicesLocked(
                                                    room,
                                                    false,
                                                  ),
                                        child: const Text('本房解锁'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Divider(height: 1),
                              const SizedBox(height: 4),
                              for (final device in visibleDevices)
                                SwitchListTile.adaptive(
                                  value: _isLocked(room, device),
                                  onChanged: (value) =>
                                      _setDeviceLocked(room, device, value),
                                  title: Text(device.name),
                                  subtitle: Text(
                                    _isLocked(room, device)
                                        ? '已锁定，随机导出时保持原值'
                                        : '未锁定，会参与随机处理',
                                  ),
                                  contentPadding: EdgeInsets.zero,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

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

  static const String _baiduAppId = '7473614';
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
          skipKeyword.hasMatch(l3))
        continue;

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
                    color: Colors.lightBlue.withOpacity(0.12),
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

class _FloorChip extends StatelessWidget {
  final String label;
  final bool selected;
  final int selectionPulse;
  final VoidCallback onTap;
  const _FloorChip({
    required this.label,
    required this.selected,
    required this.selectionPulse,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 10),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: TweenAnimationBuilder<double>(
        key: ValueKey('floor-chip-$label-$selected-$selectionPulse'),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          final pulseCurve = selected
              ? Curves.easeOutBack.transform(value)
              : Curves.easeOut.transform(value);
          return Transform.translate(
            offset: Offset(0, ui.lerpDouble(5, 0, pulseCurve)!),
            child: Transform.scale(
              scale: selected
                  ? ui.lerpDouble(0.94, 1.0, pulseCurve)!
                  : ui.lerpDouble(0.98, 1.0, pulseCurve)!,
              child: child,
            ),
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.14)
                  : Colors.black.withValues(alpha: 0.05),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.black54,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    ),
  );
}

class _AnimatedFloorFilterBar extends StatefulWidget {
  final List<String> labels;
  final String selectedLabel;
  final int selectionPulse;
  final ValueChanged<String> onSelect;

  const _AnimatedFloorFilterBar({
    required this.labels,
    required this.selectedLabel,
    required this.selectionPulse,
    required this.onSelect,
  });

  @override
  State<_AnimatedFloorFilterBar> createState() =>
      _AnimatedFloorFilterBarState();
}

class _AnimatedFloorFilterBarState extends State<_AnimatedFloorFilterBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late String _labelsSignature;

  @override
  void initState() {
    super.initState();
    _labelsSignature = _buildSignature(widget.labels);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _controller.forward(from: 0);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _AnimatedFloorFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextSignature = _buildSignature(widget.labels);
    if (nextSignature != _labelsSignature ||
        oldWidget.selectedLabel != widget.selectedLabel ||
        oldWidget.selectionPulse != widget.selectionPulse) {
      _labelsSignature = nextSignature;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _buildSignature(List<String> labels) => labels.join('|');

  @override
  Widget build(BuildContext context) {
    final labels = widget.labels;
    final containerCurve = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.68, curve: Curves.easeOutCubic),
    );

    return AnimatedSize(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        reverseDuration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: SizeTransition(
              sizeFactor: animation,
              axisAlignment: -1,
              child: child,
            ),
          );
        },
        child: labels.isEmpty
            ? const SizedBox.shrink()
            : FadeTransition(
                key: ValueKey(_labelsSignature),
                opacity: containerCurve,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.22),
                    end: Offset.zero,
                  ).animate(containerCurve),
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.05),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(8, 2, 6, 2),
                        child: Row(
                          children: [
                            for (int index = 0; index < labels.length; index++)
                              _AnimatedFloorFilterChip(
                                animation: _controller,
                                index: index,
                                total: labels.length,
                                child: _FloorChip(
                                  label: labels[index],
                                  selected:
                                      widget.selectedLabel == labels[index],
                                  selectionPulse: widget.selectionPulse,
                                  onTap: () => widget.onSelect(labels[index]),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _AnimatedFloorFilterChip extends StatelessWidget {
  final Animation<double> animation;
  final int index;
  final int total;
  final Widget child;

  const _AnimatedFloorFilterChip({
    required this.animation,
    required this.index,
    required this.total,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final safeTotal = total <= 0 ? 1 : total;
    final perItemWindow = math.min(0.11, 0.42 / safeTotal);
    final start = (0.12 + index * 0.055).clamp(0.0, 0.78);
    final end = (start + 0.22 + perItemWindow).clamp(start + 0.01, 1.0);
    final curved = CurvedAnimation(
      parent: animation,
      curve: Interval(start, end, curve: Curves.easeOutBack),
    );

    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.08, 0.26),
          end: Offset.zero,
        ).animate(curved),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
          child: child,
        ),
      ),
    );
  }
}

class _FilterReveal extends StatelessWidget {
  final int pulse;
  final int index;
  final Widget child;

  const _FilterReveal({
    required this.pulse,
    required this.index,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (pulse <= 0) {
      return child;
    }

    final clampedIndex = index.clamp(0, 7);
    final start = (clampedIndex * 0.075).clamp(0.0, 0.42).toDouble();

    return TweenAnimationBuilder<double>(
      key: ValueKey('filter-reveal-$pulse-$index'),
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 560 + clampedIndex * 32),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, child) {
        final normalized = ((value - start) / (1 - start)).clamp(0.0, 1.0);
        final fadeProgress = Curves.easeOut.transform(normalized);
        final motionProgress = Curves.easeOutBack.transform(normalized);

        return Opacity(
          opacity: ui.lerpDouble(0.0, 1.0, fadeProgress)!,
          child: Transform.translate(
            offset: Offset(0, ui.lerpDouble(22, 0, motionProgress)!),
            child: Transform.scale(
              scale: ui.lerpDouble(0.9, 1.0, motionProgress)!,
              alignment: Alignment.center,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TabButton({
    required this.label,
    required this.active,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      decoration: BoxDecoration(
        color: active
            ? Theme.of(context).colorScheme.primary
            : Colors.transparent,
        borderRadius: BorderRadius.circular(24),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: active ? Colors.white : Colors.white54,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 4,
        height: 18,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(99),
        ),
      ),
      const SizedBox(width: 10),
      Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    ],
  );
}

class _RoomCard extends StatefulWidget {
  final String serial;
  final String location;
  final bool showLocation;
  final bool isCompleted;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _RoomCard({
    super.key,
    required this.serial,
    required this.location,
    this.showLocation = true,
    required this.isCompleted,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<_RoomCard> createState() => _RoomCardState();
}

class _RoomCardState extends State<_RoomCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      duration: const Duration(milliseconds: 110),
      scale: _pressed ? 0.97 : 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _pressed ? 0.06 : 0.1),
              blurRadius: _pressed ? 6 : 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          elevation: 0,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            onHighlightChanged: (v) => setState(() => _pressed = v),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          widget.serial,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: widget.isCompleted
                                ? Colors.green
                                : Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.showLocation) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.location,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black38,
                      ),
                    ),
                  ],
                  if (widget.isCompleted)
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 14,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -------------------- Camera Page --------------------
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
