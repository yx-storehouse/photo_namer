
import 'package:flutter/material.dart';

import 'package:photo_namer/models/meter_models.dart';

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

