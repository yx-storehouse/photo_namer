import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter, rootBundle;

import 'package:photo_namer/models/meter_models.dart';
import 'package:photo_namer/pages/meter/meter_locked_devices_page.dart';
import 'package:photo_namer/rikka_page_transitions.dart';
import 'package:photo_namer/services/meter_overload_logic.dart' as overload;

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

  bool _isDeviceLocked(
    MeterTimeSlotDataset dataset,
    MeterRoom room,
    MeterDevice device,
  ) {
    return _lockedDeviceKeys.contains(
      overload.deviceLockKey(dataset, room, device),
    );
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

  Map<String, dynamic> _buildRandomizedPayload(
    MeterTimeSlotDataset dataset, {
    required double downPercent,
    required double upPercent,
  }) {
    return overload.buildRandomizedPayload(
      dataset,
      downPercent: downPercent,
      upPercent: upPercent,
      lockedDeviceKeys: _lockedDeviceKeys,
      random: _random,
    );
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
    return overload.pruneLockedKeysForDataset(dataset, source);
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

