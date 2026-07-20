import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:photo_namer/models/inspection_item.dart';
import 'package:photo_namer/models/meter_models.dart';
import 'package:photo_namer/pages/meter/meter_detail_page.dart';
import 'package:photo_namer/pages/meter/meter_overload_page.dart';
import 'package:photo_namer/rikka_page_transitions.dart';
import 'package:photo_namer/widgets/expandable_fab.dart';
import 'package:photo_namer/widgets/room_card.dart';

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
                return RoomCard(
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

