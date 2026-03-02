import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
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

enum ConflictStrategy { overwrite, increment }
enum OcrMode { local, online }

Route<T> buildAppRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0.06, 0), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class MeterDevice {
  String name;
  List<String> values;

  static List<String> defaultMeterValues() => ['220', '220', '220', '0', '0', '0'];

  MeterDevice({required this.name, List<String>? values})
      : values = values ?? List<String>.from(defaultMeterValues());

  Map<String, dynamic> toJson() => {
        'name': name,
        'values': values,
      };

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
        devices: (json['devices'] as List<dynamic>? ?? []).map((e) => MeterDevice.fromJson(e)).toList(),
      );
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
      title: '智慧巡检',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        scaffoldBackgroundColor: const Color(0xFFF6F8FC),
      ),
      home: HomePage(cameras: cameras),
    );
  }
}

// -------------------- Home Page --------------------
class HomePage extends StatefulWidget {
  final List<CameraDescription> cameras;
  const HomePage({super.key, required this.cameras});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const String _prefItemsKey = 'inspection_items';
  static const String _prefFolderKey = 'save_folder_name';
  static const String _prefSaveDirKey = 'save_directory_path';
  static const String _prefStrategyKey = 'conflict_strategy';
  static const String _prefSortByKey = 'sort_by';
  static const String _prefMeterRoomsKey = 'meter_rooms';
  static const String _prefShowHomeAddButtonKey = 'show_home_add_button';
  static const String _prefShowMeterRoomAddButtonKey = 'show_meter_room_add_button';
  static const String _prefShowMeterDeviceAddButtonKey = 'show_meter_device_add_button';

  List<InspectionItem> _items = [];
  String _saveFolderName = 'PhotoNamer';
  String? _saveDirectoryPath;
  ConflictStrategy _strategy = ConflictStrategy.increment;
  String _sortBy = 'serial';
  List<MeterRoom> _meterRooms = [];
  bool _showHomeAddButton = true;
  bool _showMeterRoomAddButton = true;
  bool _showMeterDeviceAddButton = true;

  final TextEditingController _searchCtrl = TextEditingController();
  String _floorFilter = '全部';
  int _currentTabIndex = 0; // 0: 待办, 1: 完成

  // --- Optimization Cache ---
  Map<String, List<InspectionItem>> _groupedData = {};
  List<String> _sortedTypes = [];
  List<String> _floorLabels = ['全部'];
  int _pendingCount = 0;
  int _completedCount = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    _saveFolderName = prefs.getString(_prefFolderKey) ?? 'PhotoNamer';
    _saveDirectoryPath = prefs.getString(_prefSaveDirKey);
    final strategyStr = prefs.getString(_prefStrategyKey) ?? 'increment';
    _strategy = strategyStr == 'overwrite' ? ConflictStrategy.overwrite : ConflictStrategy.increment;
    _sortBy = prefs.getString(_prefSortByKey) ?? 'serial';
    _showHomeAddButton = prefs.getBool(_prefShowHomeAddButtonKey) ?? true;
    _showMeterRoomAddButton = prefs.getBool(_prefShowMeterRoomAddButtonKey) ?? true;
    _showMeterDeviceAddButton = prefs.getBool(_prefShowMeterDeviceAddButtonKey) ?? true;

    final String? itemsJson = prefs.getString(_prefItemsKey);
    if (itemsJson != null) {
      final List<dynamic> decoded = jsonDecode(itemsJson);
      _items = decoded.map((e) => InspectionItem.fromJson(e)).toList();
    } else {
      _items = _defaultItemsFromDataTs();
      await _saveData();
    }

    final String? meterRoomsJson = prefs.getString(_prefMeterRoomsKey);
    if (meterRoomsJson != null) {
      final List<dynamic> decoded = jsonDecode(meterRoomsJson);
      _meterRooms = decoded.map((e) => MeterRoom.fromJson(e)).toList();
    }

    // 安装默认模板：当不存在或为空时，自动将所有“低压配电室”加入抄表模式
    if (_meterRooms.isEmpty) {
      _meterRooms = _items
          .where((e) => e.type == '低压配电室')
          .map(_buildMeterRoomFromInspection)
          .toList();
      await _saveData();
    }

    _recalculateDisplayData();
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
      bool floorMatch = _floorFilter == '全部' || _floorFromLocation(it.location) == targetFloor;
      bool searchMatch = q.isEmpty || it.serial.toLowerCase().contains(q) || it.name.toLowerCase().contains(q);
      return floorMatch && searchMatch;
    }).toList();
    
    _pendingCount = allFiltered.where((e) => !e.isCompleted).length;
    _completedCount = allFiltered.where((e) => e.isCompleted).length;

    // 3. Filter by tab
    var currentList = allFiltered.where((e) => _currentTabIndex == 0 ? !e.isCompleted : e.isCompleted).toList();

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
    
    setState(() {
      _groupedData = grouped;
      _sortedTypes = grouped.keys.toList()..sort();
    });
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

  String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[/:*?"<>|]'), '_');
  }

  Future<void> _pickSaveDirectory(StateSetter setModalState) async {
    try {
      final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: '选择保存目录');
      if (dir == null) return;
      setState(() {
        _saveDirectoryPath = dir;
      });
      setModalState(() {});
      await _saveData();
    } catch (e) {
      debugPrint('Pick directory error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('选择目录失败: $e')));
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefItemsKey, jsonEncode(_items.map((e) => e.toJson()).toList()));
    await prefs.setString(_prefFolderKey, _saveFolderName);
    if (_saveDirectoryPath != null) {
      await prefs.setString(_prefSaveDirKey, _saveDirectoryPath!);
    } else {
      await prefs.remove(_prefSaveDirKey);
    }
    await prefs.setString(_prefStrategyKey, _strategy.name);
    await prefs.setString(_prefSortByKey, _sortBy);
    await prefs.setString(_prefMeterRoomsKey, jsonEncode(_meterRooms.map((e) => e.toJson()).toList()));
    await prefs.setBool(_prefShowHomeAddButtonKey, _showHomeAddButton);
    await prefs.setBool(_prefShowMeterRoomAddButtonKey, _showMeterRoomAddButton);
    await prefs.setBool(_prefShowMeterDeviceAddButtonKey, _showMeterDeviceAddButton);
  }

  Future<void> _clearAllCapturedPhotos() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('一键删除全部已拍照片'),
        content: const Text('将清空所有项目的已拍照片，并尝试删除对应图片文件。此操作不可恢复，确定继续吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除全部')),
        ],
      ),
    );

    if (confirm != true) return;

    int removedFileCount = 0;
    for (final item in _items) {
      for (final p in item.photoPaths) {
        final file = File(p);
        if (await file.exists()) {
          try {
            await file.delete();
            removedFileCount++;
          } catch (_) {}
        }
      }
      item.photoPaths = [];
      item.isCompleted = false;
    }

    await _saveData();
    _recalculateDisplayData();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已清空全部拍照记录，删除文件 $removedFileCount 张')),
    );
  }

  String _defaultMeterRoomNameTemplate(InspectionItem it) {
    // 房间级模板：默认使用“位置 + 类型 + 编号”作为抄表房间名
    final parts = <String>[];
    if (it.location.trim().isNotEmpty && it.location != '-') parts.add(it.location.trim());
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
        MeterRoomsPage(
          allInspectionItems: _items,
          meterRooms: _meterRooms,
          cameras: widget.cameras,
          onSave: (rooms) async {
            _meterRooms = rooms;
            await _saveData();
          },
          onCreateRoomFromInspection: _buildMeterRoomFromInspection,
          showMeterRoomAddButton: _showMeterRoomAddButton,
          showMeterDeviceAddButton: _showMeterDeviceAddButton,
        ),
      ),
    );

    if (result == true && mounted) {
      setState(() {});
    }
  }

  List<InspectionItem> _defaultItemsFromDataTs() {
    return [
      InspectionItem(id: 1, name: '1-1空调间PK03', type: '空调间', location: '1-1', serial: 'PK03'),
      InspectionItem(id: 2, name: '1-1低压配电室PD01', type: '低压配电室', location: '1-1', serial: 'PD01'),
      InspectionItem(id: 3, name: '1-1电池室PC01', type: '电池室', location: '1-1', serial: 'PC01'),
      InspectionItem(id: 4, name: '1-1高压配电室PG01', type: '高压配电室', location: '1-1', serial: 'PG01'),
      InspectionItem(id: 5, name: '1-2冷冻机房PK02', type: '冷冻机房', location: '1-2', serial: 'PK02'),
      InspectionItem(id: 6, name: '1-1冷冻机房PK01', type: '冷冻机房', location: '1-1', serial: 'PK01'),
      InspectionItem(id: 7, name: '1-2低压配电室PD02', type: '低压配电室', location: '1-2', serial: 'PD02'),
      InspectionItem(id: 8, name: '1-2电池室PC02', type: '电池室', location: '1-2', serial: 'PC02'),
      InspectionItem(id: 9, name: '1-2空调间PK04', type: '空调间', location: '1-2', serial: 'PK04'),
      InspectionItem(id: 10, name: '1-3空调间PK05', type: '空调间', location: '1-3', serial: 'PK05'),
      InspectionItem(id: 11, name: '1-3配电室PP01', type: '配电室', location: '1-3', serial: 'PP01'),
      InspectionItem(id: 12, name: '1-4空调间PK06', type: '空调间', location: '1-4', serial: 'PK06'),
      InspectionItem(id: 13, name: '1-4配电室PP02', type: '配电室', location: '1-4', serial: 'PP02'),
      InspectionItem(id: 14, name: '1-5空调间PK07', type: '空调间', location: '1-5', serial: 'PK07'),
      InspectionItem(id: 15, name: '1-6空调间PK08', type: '空调间', location: '1-6', serial: 'PK08'),
      InspectionItem(id: 16, name: '1-2高压配电室PG02', type: '高压配电室', location: '1-2', serial: 'PG02'),
      InspectionItem(id: 17, name: '3-1低压配电室PD05', type: '低压配电室', location: '3-1', serial: 'PD05'),
      InspectionItem(id: 18, name: '3-1电池室PC05', type: '电池室', location: '3-1', serial: 'PC05'),
      InspectionItem(id: 19, name: '3-1网络传输机房Z02', type: '网络传输机房', location: '3-1', serial: 'Z02('),
      InspectionItem(id: 20, name: '3-2低压配电室PD06', type: '低压配电室', location: '3-2', serial: 'PD06'),
      InspectionItem(id: 21, name: '3-2电池室PC06', type: '电池室', location: '3-2', serial: 'PC06'),
      InspectionItem(id: 22, name: '3-3机房ID07', type: '机房', location: '3-3', serial: 'ID07'),
      InspectionItem(id: 23, name: '3-3空调间PK20', type: '空调间', location: '3-3', serial: 'PK20'),
      InspectionItem(id: 24, name: '3-4机房ID08', type: '机房', location: '3-4', serial: 'ID08'),
      InspectionItem(id: 25, name: '3-4空调间PK21', type: '空调间', location: '3-4', serial: 'PK21'),
      InspectionItem(id: 26, name: '3-5空调间PK22', type: '空调间', location: '3-5', serial: 'PK22'),
      InspectionItem(id: 27, name: '3-6空调间PK23', type: '空调间', location: '3-6', serial: 'PK23'),
      InspectionItem(id: 28, name: '3-7空调间PK24', type: '空调间', location: '3-7', serial: 'PK24'),
      InspectionItem(id: 29, name: '3-8空调间PK25', type: '空调间', location: '3-8', serial: 'PK25'),
      InspectionItem(id: 30, name: '4-1空调间PK27', type: '空调间', location: '4-1', serial: 'PK27'),
      InspectionItem(id: 31, name: '4-1低压配电室PD07', type: '低压配电室', location: '4-1', serial: 'PD07'),
      InspectionItem(id: 32, name: '4-1电池室PC07', type: '电池室', location: '4-1', serial: 'PC07'),
      InspectionItem(id: 33, name: '4-1网络传输机房Z03', type: '网络传输机房', location: '4-1', serial: 'Z03('),
      InspectionItem(id: 34, name: '4-1机房ID09', type: '机房', location: '4-1', serial: 'ID09'),
      InspectionItem(id: 35, name: '4-2低压配电室PD08', type: '低压配电室', location: '4-2', serial: 'PD08'),
      InspectionItem(id: 36, name: '4-2电池室PC08', type: '电池室', location: '4-2', serial: 'PC08'),
      InspectionItem(id: 38, name: '4-5空调间PK31', type: '空调间', location: '4-5', serial: 'PK31'),
      InspectionItem(id: 39, name: '4-6空调间PK32', type: '空调间', location: '4-6', serial: 'PK32'),
      InspectionItem(id: 40, name: '4-7空调间PK33', type: '空调间', location: '4-7', serial: 'PK33'),
      InspectionItem(id: 41, name: '4-8空调间PK34', type: '空调间', location: '4-8', serial: 'PK34'),
      InspectionItem(id: 42, name: '5-1低压配电室PD09', type: '低压配电室', location: '5-1', serial: 'PD09'),
      InspectionItem(id: 43, name: '5-1电池室PC09', type: '电池室', location: '5-1', serial: 'PC09'),
      InspectionItem(id: 44, name: '5-1机房ID13', type: '机房', location: '5-1', serial: 'ID13'),
      InspectionItem(id: 45, name: '5-1空调间PK36', type: '空调间', location: '5-1', serial: 'PK36'),
      InspectionItem(id: 46, name: '5-2低压配电室PD10', type: '低压配电室', location: '5-2', serial: 'PD10'),
      InspectionItem(id: 47, name: '5-2电池室PC10', type: '电池室', location: '5-2', serial: 'PC10'),
      InspectionItem(id: 48, name: '5-2机房ID14', type: '机房', location: '5-2', serial: 'ID14'),
      InspectionItem(id: 49, name: '5-2空调间PK37', type: '空调间', location: '5-2', serial: 'PK37'),
      InspectionItem(id: 50, name: '5-3机房ID15', type: '机房', location: '5-3', serial: 'ID15'),
      InspectionItem(id: 51, name: '5-3空调间PK38', type: '空调间', location: '5-3', serial: 'PK38'),
      InspectionItem(id: 52, name: '5-4机房ID16', type: '机房', location: '5-4', serial: 'ID16'),
      InspectionItem(id: 53, name: '5-4空调间PK39', type: '空调间', location: '5-4', serial: 'PK39'),
      InspectionItem(id: 54, name: '5-5空调间PK40', type: '空调间', location: '5-5', serial: 'PK40'),
      InspectionItem(id: 55, name: '5-6空调间PK41', type: '空调间', location: '5-6', serial: 'PK41'),
      InspectionItem(id: 56, name: '5-7空调间PK42', type: '空调间', location: '5-7', serial: 'PK42'),
      InspectionItem(id: 57, name: '5-8空调间PK43', type: '空调间', location: '5-8', serial: 'PK43'),
      InspectionItem(id: 60, name: '柴油机PY01', type: '柴油机', location: '-', serial: 'PY01'),
      InspectionItem(id: 61, name: '4-9空调间PK35', type: '空调间', location: '4-9', serial: 'PK35'),
      InspectionItem(id: 62, name: '3-9空调间PK26', type: '空调间', location: '3-9', serial: 'PK26'),
    ];
  }

  Future<void> _exportZip() async {
    if (_items.every((e) => !e.isCompleted)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('当前没有已拍的照片可以打包')));
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final encoder = ZipFileEncoder();
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final Directory tempDir = await getTemporaryDirectory();
      final String zipPath = path.join(tempDir.path, '巡检照片_$timestamp.zip');
      
      encoder.create(zipPath);
      
      int addedCount = 0;
      for (var item in _items) {
        if (item.isCompleted) {
          for (var p in item.photoPaths) {
            final file = File(p);
            if (file.existsSync()) {
              encoder.addFile(file);
              addedCount++;
            }
          }
        }
      }
      
      encoder.close();
      if (!mounted) return;
      Navigator.pop(context); // Close loading

      if (addedCount == 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未找到有效的照片文件')));
        return;
      }

      await Share.shareXFiles([XFile(zipPath)], text: '巡检照片导出');
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('打包失败: $e')));
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
              '由于需要保存照片到根目录，请在跳转后的页面找到“photo_namer”并开启“允许访问所有文件”开关。'
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('去设置')),
        ],
      ),
    );
  }

  Future<String> _saveImage(XFile photo, String fileName) async {
    try {
      Directory saveDir;
      if (_saveDirectoryPath != null && _saveDirectoryPath!.isNotEmpty) {
        saveDir = Directory(_saveDirectoryPath!);
      } else {
        saveDir = Directory(path.join('/storage/emulated/0', _saveFolderName));
      }

      if (!saveDir.existsSync()) await saveDir.create(recursive: true);

      String finalPath = path.join(saveDir.path, fileName);
      if (_strategy == ConflictStrategy.increment && File(finalPath).existsSync()) {
        int idx = 1;
        final base = path.basenameWithoutExtension(fileName);
        final String ext = path.extension(fileName);
        while (File(finalPath).existsSync()) {
          finalPath = path.join(saveDir.path, '${base}_$idx$ext');
          idx++;
        }
      }

      await File(photo.path).copy(finalPath);
      return finalPath;
    } catch (e) {
      debugPrint('Save error: $e');
      return '';
    }
  }

  Future<void> _takePhoto(InspectionItem item) async {
    if (widget.cameras.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未检测到相机')));
      return;
    }

    if (!(await _ensurePermissions())) return;

    if (!mounted) return;

    final bool isMulti = item.type == '低压配电室' || item.type == '网络传输机房';
    final int count = isMulti ? 2 : 1;

    final List<XFile>? photos = await Navigator.push<List<XFile>?>(
      context,
      buildAppRoute(
        CameraPage(
          camera: widget.cameras.first,
          title: item.name,
          captureCount: count,
        ),
      ),
    );

    if (photos == null || photos.isEmpty) return;

    List<String> savedPaths = [];
    for (int i = 0; i < photos.length; i++) {
      final photo = photos[i];
      final String fileName = isMulti
          ? '${_sanitizeFileName(item.serial)}_$i.jpg'
          : '${_sanitizeFileName(item.serial)}.jpg';

      final savedPath = await _saveImage(photo, fileName);
      if (savedPath.isNotEmpty) savedPaths.add(savedPath);
    }

    if (savedPaths.isNotEmpty) {
      item.isCompleted = true;
      item.photoPaths = savedPaths;
      await _saveData();
      _recalculateDisplayData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已保存: ${savedPaths.length} 张照片')),
        );
      }
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
              TextField(controller: serCtrl, decoration: const InputDecoration(labelText: '编号 (卡片大字)')),
              TextField(controller: locCtrl, decoration: const InputDecoration(labelText: '位置 (1-1)')),
              TextField(controller: typeCtrl, decoration: const InputDecoration(labelText: '分类')),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '保存文件名')),
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              if (item == null) {
                _items.add(InspectionItem(
                  id: DateTime.now().millisecondsSinceEpoch,
                  name: nameCtrl.text.trim(),
                  type: typeCtrl.text.trim(),
                  location: locCtrl.text.trim(),
                  serial: serCtrl.text.trim(),
                ));
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

  void _viewPhotos(InspectionItem item) {
    showDialog(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text('${item.serial} 的照片'),
            leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ),
          body: PageView.builder(
            itemCount: item.photoPaths.length,
            itemBuilder: (context, index) {
              final file = File(item.photoPaths[index]);
              if (!file.existsSync()) return const Center(child: Text('图片已丢失'));
              return InteractiveViewer(child: Image.file(file, fit: BoxFit.contain));
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('设置', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: _exportZip, icon: const Icon(Icons.folder_zip_outlined), label: const Text('打包导出照片 (ZIP)'))),
              const SizedBox(height: 20),
              const Text('保存路径', style: TextStyle(fontWeight: FontWeight.bold)),
              Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(12)), child: Text(_currentSavePathDisplay(), style: const TextStyle(fontSize: 12))),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => _pickSaveDirectory(setModalState), child: const Text('选择目录'))),
                const SizedBox(width: 10),
                Expanded(child: OutlinedButton(onPressed: () async { setState(() => _saveDirectoryPath = null); setModalState(() {}); await _saveData(); }, child: const Text('默认'))),
              ]),
              const SizedBox(height: 18),
              const Text('权限状态', style: TextStyle(fontWeight: FontWeight.bold)),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.storage_rounded),
                title: const Text('所有文件访问权限', style: TextStyle(fontSize: 14)),
                subtitle: FutureBuilder<bool>(
                  future: Permission.manageExternalStorage.isGranted,
                  builder: (context, snapshot) {
                    final granted = snapshot.data ?? false;
                    return Text(granted ? '已开启' : '未开启 (点击去设置)', 
                      style: TextStyle(color: granted ? Colors.green : Colors.red, fontSize: 12));
                  },
                ),
                onTap: () async {
                  await _openAllFilesAccessSettings();
                  if (context.mounted) Navigator.pop(context);
                },
              ),
              const Text('排序方式', style: TextStyle(fontWeight: FontWeight.bold)),
              DropdownButton<String>(
                isExpanded: true, value: _sortBy, items: const [
                  DropdownMenuItem(value: 'serial', child: Text('按编号')),
                  DropdownMenuItem(value: 'location', child: Text('按位置')),
                  DropdownMenuItem(value: 'name', child: Text('按保存名')),
                ],
                onChanged: (v) { setModalState(() => _sortBy = v!); _saveData(); _recalculateDisplayData(); },
              ),
              const SizedBox(height: 14),
              const Text('添加按钮显示方式', style: TextStyle(fontWeight: FontWeight.bold)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('首页添加按钮直接显示'),
                subtitle: const Text('关闭后合并到右上角三点菜单'),
                value: _showHomeAddButton,
                onChanged: (v) async {
                  setState(() => _showHomeAddButton = v);
                  setModalState(() {});
                  await _saveData();
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('抄表房间添加按钮直接显示'),
                subtitle: const Text('关闭后合并到抄表页三点菜单'),
                value: _showMeterRoomAddButton,
                onChanged: (v) async {
                  setState(() => _showMeterRoomAddButton = v);
                  setModalState(() {});
                  await _saveData();
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('抄表设备添加按钮直接显示'),
                subtitle: const Text('关闭后合并到抄表详情三点菜单'),
                value: _showMeterDeviceAddButton,
                onChanged: (v) async {
                  setState(() => _showMeterDeviceAddButton = v);
                  setModalState(() {});
                  await _saveData();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _resetProgress() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重置进度'),
        content: const Text('确定要恢复所有项为待办吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirm == true) {
      for (var it in _items) {
        it.isCompleted = false;
        it.photoPaths = [];
      }
      await _saveData();
      _recalculateDisplayData();
    }
  }

  void _showHomeActionsSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(99))),
            const SizedBox(height: 12),
            const ListTile(title: Text('更多操作', style: TextStyle(fontWeight: FontWeight.bold))),
            if (!_showHomeAddButton)
              ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: const Text('新增预设'),
                onTap: () {
                  Navigator.pop(context);
                  _showAddEditDialog();
                },
              ),
            ListTile(
              leading: const Icon(Icons.folder_zip_outlined),
              title: const Text('打包导出照片 (ZIP)'),
              onTap: () async {
                Navigator.pop(context);
                await _exportZip();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep_outlined, color: Colors.red),
              title: const Text('一键删除全部已拍照片', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(context);
                await _clearAllCapturedPhotos();
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('设置'),
              onTap: () {
                Navigator.pop(context);
                _showConfigSheet(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('重置进度'),
              onTap: () async {
                Navigator.pop(context);
                await _resetProgress();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('功能导航', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            ListTile(
              leading: const Icon(Icons.fact_check_outlined),
              title: const Text('动力抄表'),
              subtitle: const Text('进入抄表房间与数据管理'),
              onTap: () async {
                Navigator.pop(context);
                await _openMeterFeature();
              },
            ),
            const Divider(height: 1),
            const ListTile(
              leading: Icon(Icons.dashboard_customize_outlined, color: Colors.black45),
              title: Text('更多栏目敬请期待', style: TextStyle(color: Colors.black54)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: _buildHomeDrawer(),
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            tooltip: '打开导航菜单',
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: const Text('PhotoNamer', style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: false,
        backgroundColor: const Color(0xFFF6F8FC),
        actions: [
          IconButton(onPressed: _showHomeActionsSheet, icon: const Icon(Icons.more_horiz), tooltip: '更多操作'),
        ],
      ),
      floatingActionButton: _showHomeAddButton
          ? FloatingActionButton(onPressed: () => _showAddEditDialog(), child: const Icon(Icons.add))
          : null,
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
                            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, 6))],
                          ),
                          child: TextField(
                            controller: _searchCtrl,
                            onChanged: (_) => _recalculateDisplayData(),
                            decoration: const InputDecoration(
                              hintText: '搜索编号或名称...',
                              prefixIcon: Icon(Icons.search),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 44,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _floorLabels.length,
                            itemBuilder: (context, index) {
                              final label = _floorLabels[index];
                              return _FloorChip(
                                label: label,
                                selected: _floorFilter == label,
                                onTap: () {
                                  _floorFilter = label;
                                  _recalculateDisplayData();
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],
                    ),
                  ),
                ),
                if (_sortedTypes.isEmpty)
                  const SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('暂无数据'))),
                for (final type in _sortedTypes) ...[
                  SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: _SectionHeader(title: type))),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3, crossAxisSpacing: 14, mainAxisSpacing: 14, childAspectRatio: 0.95,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final it = _groupedData[type]![index];
                          return RepaintBoundary(child: _RoomCard(
                            key: ValueKey(it.id),
                            serial: it.serial,
                            location: it.location,
                            isCompleted: it.isCompleted,
                            onTap: () => it.isCompleted ? _viewPhotos(it) : _takePhoto(it),
                            onLongPress: () => _showAddEditDialog(it),
                          ));
                        },
                        childCount: _groupedData[type]!.length,
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          ),
          Positioned(
            bottom: 20, left: 20, right: 20,
            child: RepaintBoundary(child: Container(
              height: 60,
              decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(30)),
              padding: const EdgeInsets.all(6),
              child: Row(
                children: [
                  Expanded(child: _TabButton(label: '待办 ($_pendingCount)', active: _currentTabIndex == 0, onTap: () {
                    setState(() => _currentTabIndex = 0);
                    _recalculateDisplayData();
                  })),
                  Expanded(child: _TabButton(label: '完成 ($_completedCount)', active: _currentTabIndex == 1, onTap: () {
                    setState(() => _currentTabIndex = 1);
                    _recalculateDisplayData();
                  })),
                ],
              ),
            )),
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
  final Future<void> Function(List<MeterRoom>) onSave;
  final MeterRoom Function(InspectionItem item) onCreateRoomFromInspection;
  final bool showMeterRoomAddButton;
  final bool showMeterDeviceAddButton;

  const MeterRoomsPage({
    super.key,
    required this.allInspectionItems,
    required this.meterRooms,
    required this.cameras,
    required this.onSave,
    required this.onCreateRoomFromInspection,
    required this.showMeterRoomAddButton,
    required this.showMeterDeviceAddButton,
  });

  @override
  State<MeterRoomsPage> createState() => _MeterRoomsPageState();
}

class _MeterRoomsPageState extends State<MeterRoomsPage> {
  late List<MeterRoom> _rooms;

  Future<void> _exportRoomConfig() async {
    try {
      final data = {
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'rooms': _rooms
            .map((r) => {
                  'roomId': r.roomId,
                  'roomName': r.roomName,
                  'roomType': r.roomType,
                  'location': r.location,
                  'devices': r.devices.map((d) => {'name': d.name}).toList(),
                })
            .toList(),
      };

      final dir = await getTemporaryDirectory();
      final file = File(path.join(dir.path, '抄表房间配置_${DateTime.now().millisecondsSinceEpoch}.json'));
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));

      await Share.shareXFiles([XFile(file.path)], text: '抄表房间配置导出');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出失败: $e')));
    }
  }

  Future<void> _importRoomConfig() async {
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
      if (picked == null || picked.files.single.path == null) return;

      final filePath = picked.files.single.path!;
      final text = await File(filePath).readAsString();
      final decoded = jsonDecode(text);
      final List<dynamic> rooms = (decoded is Map<String, dynamic>) ? (decoded['rooms'] as List<dynamic>? ?? []) : [];
      if (rooms.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('导入文件无有效房间配置')));
        return;
      }

      final imported = rooms.map((e) {
        final m = e as Map<String, dynamic>;
        final List<dynamic> ds = m['devices'] as List<dynamic>? ?? [];
        return MeterRoom(
          roomId: m['roomId'] is int ? m['roomId'] : DateTime.now().millisecondsSinceEpoch,
          roomName: (m['roomName'] ?? '').toString(),
          roomType: (m['roomType'] ?? '').toString(),
          location: (m['location'] ?? '').toString(),
          devices: ds
              .map((d) => MeterDevice(name: ((d as Map<String, dynamic>)['name'] ?? '未命名设备').toString()))
              .toList(),
        );
      }).toList();

      setState(() => _rooms = imported);
      await widget.onSave(_rooms);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已导入 ${_rooms.length} 个房间配置')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败: $e')));
    }
  }

  Future<void> _exportMeterData() async {
    try {
      final data = {
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'rooms': _rooms.map((r) => r.toJson()).toList(),
      };

      final dir = await getTemporaryDirectory();
      final file = File(path.join(dir.path, '抄表数据_${DateTime.now().millisecondsSinceEpoch}.json'));
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));

      await Share.shareXFiles([XFile(file.path)], text: '抄表数据导出');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('抄表数据导出失败: $e')));
    }
  }

  Future<void> _importMeterData() async {
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
      if (picked == null || picked.files.single.path == null) return;

      final filePath = picked.files.single.path!;
      final text = await File(filePath).readAsString();
      final decoded = jsonDecode(text);
      final List<dynamic> rooms = (decoded is Map<String, dynamic>) ? (decoded['rooms'] as List<dynamic>? ?? []) : [];

      if (rooms.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('导入文件无有效抄表数据')));
        return;
      }

      final imported = rooms.map((e) {
        final m = e as Map<String, dynamic>;
        final List<dynamic> ds = m['devices'] as List<dynamic>? ?? [];

        return MeterRoom(
          roomId: m['roomId'] is int ? m['roomId'] : DateTime.now().millisecondsSinceEpoch,
          roomName: (m['roomName'] ?? '').toString(),
          roomType: (m['roomType'] ?? '').toString(),
          location: (m['location'] ?? '').toString(),
          devices: ds.map((d) {
            final dm = d as Map<String, dynamic>;
            final rawValues = dm['values'];
            List<String> values = List<String>.from(MeterDevice.defaultMeterValues());
            if (rawValues is List) {
              final parsed = rawValues.map((v) => (v ?? '').toString()).toList();
              for (int i = 0; i < values.length && i < parsed.length; i++) {
                values[i] = parsed[i];
              }
            }

            return MeterDevice(
              name: (dm['name'] ?? '未命名设备').toString(),
              values: values,
            );
          }).toList(),
        );
      }).toList();

      if (!mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导入抄表数据'),
          content: Text('即将导入 ${imported.length} 个房间的数据，并覆盖当前动力抄表页数据，是否继续？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('导入覆盖')),
          ],
        ),
      );

      if (confirm != true) return;

      setState(() => _rooms = imported);
      await widget.onSave(_rooms);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已导入 ${_rooms.length} 个房间的抄表数据')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入抄表数据失败: $e')));
    }
  }

  Future<void> _clearMeterValues() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('一键清空抄表数据'),
        content: const Text('将清空所有房间设备的抄表数值，房间和设备配置会保留，确定继续吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('清空')),
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
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已清空抄表数据')));
  }

  void _showMeterActionsSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(99))),
            const SizedBox(height: 12),
            const ListTile(title: Text('抄表操作', style: TextStyle(fontWeight: FontWeight.bold))),
            ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: const Text('导入配置'),
              onTap: () async {
                Navigator.pop(context);
                await _importRoomConfig();
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: const Text('导出配置'),
              onTap: () async {
                Navigator.pop(context);
                await _exportRoomConfig();
              },
            ),
            ListTile(
              leading: const Icon(Icons.data_array_outlined),
              title: const Text('导入抄表数据'),
              onTap: () async {
                Navigator.pop(context);
                await _importMeterData();
              },
            ),
            ListTile(
              leading: const Icon(Icons.data_object_outlined),
              title: const Text('导出抄表数据'),
              onTap: () async {
                Navigator.pop(context);
                await _exportMeterData();
              },
            ),
            if (!widget.showMeterRoomAddButton)
              ListTile(
                leading: const Icon(Icons.add_home_outlined),
                title: const Text('添加房间'),
                onTap: () async {
                  Navigator.pop(context);
                  await _pickRoomAndAdd();
                },
              ),
            ListTile(
              leading: const Icon(Icons.cleaning_services_outlined, color: Colors.red),
              title: const Text('一键清空抄表数据', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(context);
                await _clearMeterValues();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _rooms = widget.meterRooms
        .map((e) => MeterRoom(
              roomId: e.roomId,
              roomName: e.roomName,
              roomType: e.roomType,
              location: e.location,
              devices: e.devices.map((d) => MeterDevice(name: d.name, values: List<String>.from(d.values))).toList(),
            ))
        .toList();
  }

  Future<void> _pickRoomAndAdd() async {
    final exists = _rooms.map((e) => e.roomId).toSet();
    final candidates = widget.allInspectionItems.where((e) => !exists.contains(e.id)).toList();
    if (candidates.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('没有可新增的房间了')));
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
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
      appBar: AppBar(
        title: const Text('动力抄表'),
        actions: [
          IconButton(onPressed: _showMeterActionsSheet, icon: const Icon(Icons.more_horiz), tooltip: '抄表更多操作'),
        ],
      ),
      floatingActionButton: widget.showMeterRoomAddButton
          ? FloatingActionButton.extended(
              onPressed: _pickRoomAndAdd,
              icon: const Icon(Icons.add),
              label: const Text('添加房间'),
            )
          : null,
      body: _rooms.isEmpty
          ? const Center(child: Text('还没有抄表房间\n点击右下角添加', textAlign: TextAlign.center))
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
                        MeterDetailPage(
                          room: room,
                          cameras: widget.cameras,
                          showAddDeviceButton: widget.showMeterDeviceAddButton,
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
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('移除')),
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

class MeterDetailPage extends StatefulWidget {
  final MeterRoom room;
  final List<CameraDescription> cameras;
  final Future<void> Function() onChanged;
  final bool showAddDeviceButton;
  const MeterDetailPage({
    super.key,
    required this.room,
    required this.cameras,
    required this.onChanged,
    required this.showAddDeviceButton,
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

  String _lastOcrRawText = '';
  List<String> _lastOcrNumbers = [];
  List<String> _lastOcrFocusLines = [];

  static const Rect _ocrFocusRectNormalized = Rect.fromLTWH(0.22, 0.32, 0.56, 0.36);
  static const Rect _incomingCabinetRectNormalized = Rect.fromLTWH(0.28, 0.22, 0.44, 0.48);

  static const String _baiduAppId = '7473614';
  static const String _baiduApiKey = 'GOiAIygVECnMVJWnpQGcBbNs';
  static const String _baiduSecretKey = 's7nnGZ9mhNv8in2b7eyjm0g3zjrhXUqv';

  OcrMode _ocrMode = OcrMode.local;
  String? _baiduAccessToken;
  DateTime? _baiduTokenExpireAt;

  FocusNode _focusNodeFor(int deviceIndex, int fieldIndex) {
    final key = '$deviceIndex-$fieldIndex';
    return _focusNodes.putIfAbsent(key, () => FocusNode());
  }

  TextEditingController _controllerFor(int deviceIndex, int fieldIndex, String value) {
    final key = '$deviceIndex-$fieldIndex';
    return _valueControllers.putIfAbsent(key, () => TextEditingController(text: value));
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
        content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: '房间名')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('保存')),
        ],
      ),
    );
    if (ok == true) {
      setState(() => widget.room.roomName = ctrl.text.trim().isEmpty ? widget.room.roomName : ctrl.text.trim());
      await widget.onChanged();
    }
  }

  Future<void> _addDevice() async {
    final ctrl = TextEditingController(text: 'UPS-${widget.room.devices.length + 1}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新增设备'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: '例如 UPS-3 / 进线柜-2')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('添加')),
        ],
      ),
    );
    if (ok == true) {
      setState(() => widget.room.devices.add(MeterDevice(name: ctrl.text.trim().isEmpty ? '未命名设备' : ctrl.text.trim())));
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
          TextButton(onPressed: () => Navigator.pop(context, 'cancel'), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, 'save'), child: const Text('保存')),
        ],
      ),
    );

    if (action == 'save') {
      setState(() => device.name = nameCtrl.text.trim().isEmpty ? device.name : nameCtrl.text.trim());
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
    final filtered = source.where((n) => _isLikelyCurrentValue(n) && !_isPowerFactorLike(n)).toList();
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

    final skipKeyword = RegExp(r'(打卡|今日水印|时间地点|杭州|中国电信|PD\d+|低压进线柜|A\s*$)', caseSensitive: false);

    // 进线柜数字表：通常是 3 行单值（每行后面可能带 A），优先连续三行提取
    for (int i = 0; i + 2 < lines.length; i++) {
      final l1 = lines[i];
      final l2 = lines[i + 1];
      final l3 = lines[i + 2];
      if (skipKeyword.hasMatch(l1) || skipKeyword.hasMatch(l2) || skipKeyword.hasMatch(l3)) continue;

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

    final keywordCurrent = RegExp(r'(电流|相电流|current|curr|\bia\b|\bib\b|\bic\b|\bi\b)', caseSensitive: false);
    final skipKeyword = RegExp(r'(Hz|频率|功率因数|PF|kvar|kw|kva|负载率|有功|视在|合计|总功率)', caseSensitive: false);

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

    final allNumbers = _numbersFromLine(text).where((n) => !_isPowerFactorLike(n)).toList();
    if (allNumbers.length <= 3) return allNumbers;
    return allNumbers.sublist(0, 3);
  }

  Future<void> _showOcrDebugDialog() async {
    if (!mounted) return;

    final numbersText = _lastOcrNumbers.isEmpty ? '（无）' : _lastOcrNumbers.join(', ');
    final focusText = _lastOcrFocusLines.isEmpty ? '（无）' : _lastOcrFocusLines.join('\n');
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
                const Text('识别到的全部数字：', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                SelectableText(numbersText),
                const SizedBox(height: 12),
                const Text('用于判定的关键行：', style: TextStyle(fontWeight: FontWeight.bold)),
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
                const Text('原始 OCR 文本：', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(_lastOcrRawText.isEmpty ? '（无）' : _lastOcrRawText),
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

  Future<String?> _buildCroppedImageFilePath(String originalPath, Rect normalizedRect) async {
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
      final dstRect = Rect.fromLTWH(0, 0, targetW.toDouble(), targetH.toDouble());
      canvas.drawImageRect(srcImage, srcRect, dstRect, Paint());
      final picture = recorder.endRecording();
      final cropped = await picture.toImage(targetW, targetH);
      final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return null;

      final dir = await getTemporaryDirectory();
      final outPath = path.join(dir.path, 'ocr_crop_${DateTime.now().millisecondsSinceEpoch}.png');
      await File(outPath).writeAsBytes(data.buffer.asUint8List(), flush: true);
      return outPath;
    } catch (e) {
      debugPrint('build crop image error: $e');
      return null;
    }
  }

  bool _isIncomingCabinetDevice(MeterDevice device) {
    final name = device.name.trim().toLowerCase();
    return name.contains('进线柜') || name.contains('incoming') || name.contains('feeder');
  }

  Future<String> _recognizeTextWithLocalOcr(String imagePath, String originalPath) async {
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
    final response = await http.post(uri, body: {
      'grant_type': 'client_credentials',
      'client_id': _baiduApiKey,
      'client_secret': _baiduSecretKey,
    });

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
    _baiduTokenExpireAt = now.add(Duration(seconds: expiresIn > 120 ? expiresIn - 120 : expiresIn));
    return token;
  }

  Future<String> _recognizeTextWithBaiduOcr(String imagePath) async {
    final token = await _ensureBaiduAccessToken();
    if (token == null || token.isEmpty) {
      throw Exception('百度 access_token 不可用');
    }

    final bytes = await File(imagePath).readAsBytes();
    final imageBase64 = base64Encode(bytes);

    final uri = Uri.parse('https://aip.baidubce.com/rest/2.0/ocr/v1/general_basic?access_token=$token');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'image': imageBase64,
        'language_type': 'CHN_ENG',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('百度 OCR 请求失败(${response.statusCode})');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['error_code'] != null) {
      throw Exception('百度 OCR 错误: ${data['error_msg'] ?? data['error_code']}');
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未检测到相机')));
      return;
    }

    final cameraStatus = await Permission.camera.request();
    if (!cameraStatus.isGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先授予相机权限')));
      return;
    }

    final XFile? photo = await Navigator.push<XFile?>(
      context,
      buildAppRoute(
        MeterOcrCameraPage(camera: widget.cameras.first, title: widget.room.devices[deviceIndex].name),
      ),
    );

    if (photo == null) return;

    try {
      final isIncoming = _isIncomingCabinetDevice(widget.room.devices[deviceIndex]);
      final focusRect = isIncoming ? _incomingCabinetRectNormalized : _ocrFocusRectNormalized;

      final croppedPath = await _buildCroppedImageFilePath(photo.path, focusRect);
      final targetPath = croppedPath ?? photo.path;

      final text = _ocrMode == OcrMode.online
          ? await _recognizeTextWithBaiduOcr(targetPath)
          : await _recognizeTextWithLocalOcr(targetPath, photo.path);

      final allNumbers = RegExp(r'[-+]?\d+(?:[\.,]\d+)?').allMatches(text).map((m) => _normalizeOcrNumber(m.group(0)!)).toList();
      final matches = isIncoming
          ? _extractIncomingCabinetCurrentCandidates(text)
          : _extractCurrentCandidates(text);

      setState(() {
        _lastOcrRawText = text;
        _lastOcrNumbers = allNumbers;
      });

      if (matches.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未识别到电流数值')));
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
      final modeLabel = _ocrMode == OcrMode.online ? '在线(百度)' : '本地(MLKit)';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('[$modeLabel] 识别完成，候选:${matches.join('/')}（可点右上角查看完整 OCR）')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('识别失败: $e')));
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

    final controller = _controllerFor(deviceIndex, fieldIndex, widget.room.devices[deviceIndex].values[fieldIndex]);
    controller.selection = TextSelection(baseOffset: 0, extentOffset: controller.text.length);
    FocusScope.of(context).requestFocus(_focusNodeFor(deviceIndex, fieldIndex));

    _activeCurrentDeviceIndex = deviceIndex;
    _activeCurrentFieldIndex = fieldIndex;

    if (fieldIndex == 5) {
      _nextCurrentFieldIndex = 3;
      _nextDeviceIndexForCurrent = (deviceIndex + 1) % widget.room.devices.length;
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
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
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
          PopupMenuButton<OcrMode>(
            tooltip: 'OCR 模式切换',
            onSelected: (mode) {
              setState(() => _ocrMode = mode);
              final label = mode == OcrMode.online ? '在线(百度 OCR)' : '本地(MLKit)';
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已切换到$label')));
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: OcrMode.local, child: Text('本地模式 (MLKit)')),
              PopupMenuItem(value: OcrMode.online, child: Text('在线模式 (百度 OCR)')),
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
                  Text(_ocrMode == OcrMode.online ? '在线' : '本地'),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: _showOcrDebugDialog,
            icon: const Icon(Icons.bug_report_outlined),
            tooltip: '查看 OCR 调试结果',
          ),
          if (!widget.showAddDeviceButton)
            IconButton(
              onPressed: _addDevice,
              icon: const Icon(Icons.playlist_add_outlined),
              tooltip: '新增UPS/进线柜',
            ),
          IconButton(onPressed: _editRoomName, icon: const Icon(Icons.edit)),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: FloatingActionButton(
              heroTag: 'fab_next_current',
              mini: true,
              onPressed: _focusNextCurrentGlobal,
              tooltip: '下一个电流输入框',
              child: const Icon(Icons.arrow_downward_rounded, size: 20),
            ),
          ),
          if (widget.showAddDeviceButton) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: 44,
              height: 44,
              child: FloatingActionButton(
                heroTag: 'fab_add_device',
                mini: true,
                onPressed: _addDevice,
                tooltip: '新增UPS/进线柜',
                child: const Icon(Icons.add, size: 20),
              ),
            ),
          ],
        ],
      ),
      body: ListView.builder(
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
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
                      )
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
                        onChanged: (v) async { device.values[0] = v; await widget.onChanged(); },
                      ),
                      _buildValueInput(
                        label: '电压B(V)',
                        deviceIndex: index,
                        fieldIndex: 1,
                        value: device.values[1],
                        onChanged: (v) async { device.values[1] = v; await widget.onChanged(); },
                      ),
                      _buildValueInput(
                        label: '电压C(V)',
                        deviceIndex: index,
                        fieldIndex: 2,
                        value: device.values[2],
                        onChanged: (v) async { device.values[2] = v; await widget.onChanged(); },
                      ),
                      _buildValueInput(
                        label: '电流A(A)',
                        deviceIndex: index,
                        fieldIndex: 3,
                        value: device.values[3],
                        onChanged: (v) async { device.values[3] = v; await widget.onChanged(); },
                      ),
                      _buildValueInput(
                        label: '电流B(A)',
                        deviceIndex: index,
                        fieldIndex: 4,
                        value: device.values[4],
                        onChanged: (v) async { device.values[4] = v; await widget.onChanged(); },
                      ),
                      _buildValueInput(
                        label: '电流C(A)',
                        deviceIndex: index,
                        fieldIndex: 5,
                        value: device.values[5],
                        onChanged: (v) async { device.values[5] = v; await widget.onChanged(); },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class MeterOcrCameraPage extends StatefulWidget {
  final CameraDescription camera;
  final String title;
  const MeterOcrCameraPage({super.key, required this.camera, required this.title});

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
    _controller = CameraController(widget.camera, ResolutionPreset.high, enableAudio: false);
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('拍照失败: $e')));
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
            icon: Icon(_flashMode == FlashMode.torch ? Icons.flash_on : Icons.flash_off),
            tooltip: _flashMode == FlashMode.torch ? '闪光灯常开' : '闪光灯关闭',
          ),
        ],
      ),
      body: _isReady && _controller != null
          ? LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final h = constraints.maxHeight;
                final left = w * 0.22;
                final top = h * 0.32;
                final rectW = w * 0.56;
                final rectH = h * 0.36;

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
                          border: Border.all(color: Colors.lightGreenAccent, width: 2),
                          borderRadius: BorderRadius.circular(10),
                          color: Colors.transparent,
                        ),
                      ),
                    ),
                    Positioned(
                      left: left + 8,
                      top: top + 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                        child: const Text(
                          '识别区域',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 120,
                      left: 20,
                      right: 20,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                        child: const Text(
                          '将“电流 A/B/C + 单位 A”放入绿色框内，尽量只拍屏幕数据区',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                );
              },
            )
          : const Center(child: CircularProgressIndicator()),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.large(
        onPressed: _isReady ? _capture : null,
        child: const Icon(Icons.camera_alt),
      ),
    );
  }
}

class _FloorChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FloorChip({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 10),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? Theme.of(context).colorScheme.primary : Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              label,
              style: TextStyle(color: selected ? Colors.white : Colors.black54, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      );
}

class _TabButton extends StatelessWidget {
  final String label; final bool active; final VoidCallback onTap;
  const _TabButton({required this.label, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap, child: Container(decoration: BoxDecoration(color: active ? Theme.of(context).colorScheme.primary : Colors.transparent, borderRadius: BorderRadius.circular(24)), alignment: Alignment.center, child: Text(label, style: TextStyle(color: active ? Colors.white : Colors.white54, fontWeight: FontWeight.bold))));
}

class _SectionHeader extends StatelessWidget {
  final String title; const _SectionHeader({required this.title});
  @override
  Widget build(BuildContext context) => Row(children: [Container(width: 4, height: 18, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(99))), const SizedBox(width: 10), Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))]);
}

class _RoomCard extends StatefulWidget {
  final String serial;
  final String location;
  final bool isCompleted;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _RoomCard({
    super.key,
    required this.serial,
    required this.location,
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
                  Text(
                    widget.serial,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: widget.isCompleted ? Colors.green : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.location,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    style: const TextStyle(fontSize: 11, color: Colors.black38),
                  ),
                  if (widget.isCompleted)
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.check_circle, color: Colors.green, size: 14),
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
  final CameraDescription camera; final String title; final int captureCount;
  const CameraPage({super.key, required this.camera, required this.title, required this.captureCount});
  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  CameraController? _controller; bool _isReady = false; int _captured = 0; final List<XFile> _photos = [];
  @override
  void initState() { super.initState(); _initCamera(); }
  Future<void> _initCamera() async { 
    _controller = CameraController(widget.camera, ResolutionPreset.high, enableAudio: false); 
    try { 
      // 延迟初始化以保证页面转场流畅
      await Future.delayed(const Duration(milliseconds: 300));
      await _controller!.initialize(); 
      if (mounted) setState(() => _isReady = true); 
    } catch (e) { debugPrint('Camera init error: $e'); } 
  }
  @override
  void dispose() { 
    _controller?.dispose(); 
    super.dispose(); 
  }
  Future<void> _onShoot() async {
    if (!_isReady || _controller == null) return;
    try {
      final image = await _controller!.takePicture();
      _photos.add(image); _captured++;
      if (!mounted) return;
      OverlayEntry entry = OverlayEntry(builder: (context) => Center(child: Material(color: Colors.transparent, child: Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(16)), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.check_circle, color: Colors.green, size: 50), const SizedBox(height: 10), Text(widget.captureCount > 1 ? '第 $_captured / ${widget.captureCount} 张' : '拍照成功', style: const TextStyle(color: Colors.white, fontSize: 18))])))));
      Overlay.of(context).insert(entry); await Future.delayed(const Duration(milliseconds: 800)); entry.remove();
      if (!mounted) return;
      if (_captured >= widget.captureCount) Navigator.pop(context, _photos); else setState(() {});
    } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('拍照失败: $e'))); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: Colors.black, appBar: AppBar(title: Text(widget.title), backgroundColor: Colors.white), body: Stack(children: [if (_isReady && _controller != null) Center(child: CameraPreview(_controller!)) else const Center(child: CircularProgressIndicator()), Positioned(bottom: 120, left: 0, right: 0, child: Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)), child: Text(widget.captureCount > 1 ? '拍摄第 ${_captured + 1} 张' : '点击拍照', style: const TextStyle(color: Colors.white)))))]), floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat, floatingActionButton: FloatingActionButton.large(onPressed: _isReady ? _onShoot : null, backgroundColor: Colors.white, child: Icon(Icons.camera_alt, color: Theme.of(context).primaryColor)));
}
