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
import 'package:share_plus/share_plus.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:photo_namer/app_route_observer.dart';
import 'package:photo_namer/capture_location_service.dart';
import 'package:photo_namer/capture_weather_service.dart';
import 'package:photo_namer/cloud_sync_page.dart';
import 'package:photo_namer/models/app_enums.dart';
import 'package:photo_namer/models/camera_capture_result.dart';
import 'package:photo_namer/models/inspection_calendar.dart';
import 'package:photo_namer/models/inspection_item.dart';
import 'package:photo_namer/models/meter_models.dart';
import 'package:photo_namer/native_watermark_camera_bridge.dart';
import 'package:photo_namer/pages/calendar/shift_aware_inspection_calendar_page.dart';
import 'package:photo_namer/pages/camera/camera_page.dart';
import 'package:photo_namer/pages/meter/meter_detail_page.dart';
import 'package:photo_namer/pages/meter/meter_rooms_page.dart';
import 'package:photo_namer/raw_capture_batch_page.dart';
import 'package:photo_namer/raw_capture_material_repository.dart';
import 'package:photo_namer/rikka_page_transitions.dart';
import 'package:photo_namer/services/bundled_cloud_data.dart';
import 'package:photo_namer/services/inspection_zip.dart';
import 'package:photo_namer/services/json_utils.dart';
import 'package:photo_namer/watermark_template_118.dart';
import 'package:photo_namer/widgets/expandable_fab.dart';
import 'package:photo_namer/widgets/room_card.dart';
import 'package:photo_namer/widgets/section_header.dart';

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
    final bundledCloudData = await loadBundledCloudData();
    final bundledPreferences = stringKeyedMap(
      bundledCloudData?['appPreferences'],
    );
    final bundledWatermarkTemplate = stringKeyedMap(
      bundledCloudData?['watermarkTemplate'],
    );
    final bundledInspectionItems = bundledInspectionDefaults(
      bundledCloudData?['inspectionItems'],
    );
    final bundledMeterRooms = stringKeyedMapList(
      bundledCloudData?['meterRooms'],
    );
    final bundledOverloadTemplates = stringKeyedMapList(
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

    final bundledLocationFallback = cloudStringDefault(
      bundledPreferences,
      'defaultWatermarkLocationFallback',
      cloudStringDefault(
        bundledWatermarkTemplate,
        'defaultLocationFallback',
        '',
      ),
    );
    final bundledImprintText = cloudStringDefault(
      bundledPreferences,
      'defaultWatermarkImprintText',
      cloudStringDefault(
        bundledWatermarkTemplate,
        'defaultImprintText',
        WatermarkTemplate118Composer.defaultImprintText,
      ),
    );
    final bundledWeatherText = cloudStringDefault(
      bundledWatermarkTemplate,
      'defaultWeatherText',
      WatermarkTemplate118Composer.defaultWeatherText,
    );

    _saveFolderName =
        prefs.getString(_prefFolderKey) ??
        cloudStringDefault(bundledPreferences, 'saveFolderName', 'PhotoNamer');
    _saveDirectoryPath = prefs.getString(_prefSaveDirKey);
    _directCaptureSaveDirectoryPath = prefs.getString(
      _prefDirectCaptureSaveDirKey,
    );
    final strategyStr =
        prefs.getString(_prefStrategyKey) ??
        cloudStringDefault(
          bundledPreferences,
          'conflictStrategy',
          'increment',
        );
    _strategy = strategyStr == 'overwrite'
        ? ConflictStrategy.overwrite
        : ConflictStrategy.increment;
    _sortBy =
        prefs.getString(_prefSortByKey) ??
        cloudStringDefault(bundledPreferences, 'sortBy', 'serial');
    _photoToMeterQuickJumpEnabled =
        prefs.getBool(_prefPhotoToMeterQuickJumpKey) ??
        cloudBoolDefault(
          bundledPreferences,
          'photoToMeterQuickJumpEnabled',
          true,
        );
    _mergedLayoutEnabled =
        prefs.getBool(_prefMergedLayoutEnabledKey) ??
        cloudBoolDefault(bundledPreferences, 'mergedLayoutEnabled', true);
    _mergedDeepSearchEnabled =
        prefs.getBool(_prefMergedDeepSearchEnabledKey) ??
        cloudBoolDefault(bundledPreferences, 'mergedDeepSearchEnabled', true);
    _mergedUniformHeightEnabled =
        prefs.getBool(_prefMergedUniformHeightEnabledKey) ??
        cloudBoolDefault(
          bundledPreferences,
          'mergedUniformHeightEnabled',
          false,
        );
    _mergedUltraCompactEnabled =
        prefs.getBool(_prefMergedUltraCompactEnabledKey) ??
        cloudBoolDefault(
          bundledPreferences,
          'mergedUltraCompactEnabled',
          false,
        );
    _cameraAttachDelayEnabled =
        prefs.getBool(_prefCameraAttachDelayEnabledKey) ??
        cloudBoolDefault(bundledPreferences, 'cameraAttachDelayEnabled', true);
    _defaultWatermarkEnabled =
        prefs.getBool(_prefDefaultWatermarkEnabledKey) ??
        cloudBoolDefault(bundledPreferences, 'defaultWatermarkEnabled', true);
    _incomingCabinetOnlineOcrEnabled =
        prefs.getBool(_prefIncomingCabinetOnlineOcrEnabledKey) ??
        cloudBoolDefault(
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
                cloudIntDefault(
                  bundledPreferences,
                  'cameraAttachDelayMs',
                  320,
                ))
            .clamp(0, 1000);
    _typeColorThemeId =
        prefs.getString(_prefTypeColorThemeIdKey) ??
        cloudStringDefault(
          bundledPreferences,
          'typeColorThemeId',
          'inspection_semantic',
        );
    if (!_typeColorThemes.any((e) => e.id == _typeColorThemeId)) {
      _typeColorThemeId = _typeColorThemes.first.id;
    }
    final savedColumns =
        prefs.getInt(_prefGridColumnsKey) ??
        cloudIntDefault(bundledPreferences, 'gridColumns', 3);
    _gridColumns = savedColumns.clamp(3, 6);
    final colorJson = prefs.getString(_prefTypeColorOverridesKey);
    if (colorJson != null && colorJson.isNotEmpty) {
      final decoded = jsonDecode(colorJson);
      if (decoded is Map) {
        _typeColorOverrides = intMapFromJson(decoded);
      }
    } else if (colorJson == null) {
      _typeColorOverrides = intMapFromJson(
        bundledPreferences['typeColorOverrides'],
      );
    }
    final recentColorsJson = prefs.getString(_prefRecentTypeColorsKey);
    if (recentColorsJson != null && recentColorsJson.isNotEmpty) {
      final decoded = jsonDecode(recentColorsJson);
      if (decoded is List) {
        _recentTypeColors = intListFromJson(decoded);
      }
    } else if (recentColorsJson == null) {
      _recentTypeColors = intListFromJson(
        bundledPreferences['recentTypeColors'],
      );
    }
    _mergedContentMaxHeight =
        (prefs.getDouble(_prefMergedContentMaxHeightKey) ??
                cloudDoubleDefault(
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
        createInspectionZipInBackground,
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
                                                        child: RoomCard(
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
                        child: SectionHeader(title: type),
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
                              child: RoomCard(
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

