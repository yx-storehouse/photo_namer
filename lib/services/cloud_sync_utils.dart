import 'dart:convert';


import 'package:photo_namer/models/cloud_sync_models.dart';

List<Map<String, dynamic>> asMapList(dynamic value) {
  if (value is! List) {
    return const <Map<String, dynamic>>[];
  }
  return value
      .whereType<Map>()
      .map(
        (entry) => Map<String, dynamic>.from(
          entry.map((key, value) => MapEntry(key.toString(), value)),
        ),
      )
      .toList(growable: false);
}

Map<String, dynamic> asStringMap(dynamic value) {
  if (value is! Map) {
    return <String, dynamic>{};
  }
  return Map<String, dynamic>.from(
    value.map((key, value) => MapEntry(key.toString(), value)),
  );
}

List<String> asStringList(dynamic value) {
  if (value is! List) {
    return const <String>[];
  }
  return value.map((item) => item.toString()).toList(growable: false);
}

String normalizedText(dynamic value) => (value ?? '').toString().trim();

String displayRoomName(Map<String, dynamic> room, int index) {
  final roomName = normalizedText(room['roomName']);
  if (roomName.isNotEmpty) {
    return roomName;
  }
  final roomId = normalizedText(room['roomId']);
  if (roomId.isNotEmpty) {
    return '房间#$roomId';
  }
  return '房间$index';
}

String? formatBidirectionalDifference(Set<String> local, Set<String> remote) {
  final localOnly = local.difference(remote);
  final remoteOnly = remote.difference(local);
  if (localOnly.isEmpty && remoteOnly.isEmpty) {
    return null;
  }

  final parts = <String>[];
  if (localOnly.isNotEmpty) {
    parts.add('本机独有 ${previewItems(localOnly)}');
  }
  if (remoteOnly.isNotEmpty) {
    parts.add('云端独有 ${previewItems(remoteOnly)}');
  }
  return parts.join('；');
}

String previewItems(Iterable<String> items, {int limit = 3}) {
  final normalized =
      items.map((item) => item.trim()).where((item) => item.isNotEmpty).toList()
        ..sort();
  if (normalized.isEmpty) {
    return '无';
  }
  if (normalized.length <= limit) {
    return normalized.join('、');
  }
  final preview = normalized.take(limit).join('、');
  return '$preview 等 ${normalized.length} 项';
}

String formatWatermarkFieldValue(
  Map<String, dynamic>? watermarkTemplate,
  String key, {
  String emptyLabel = '未设置',
}) {
  if (watermarkTemplate == null) {
    return '暂无';
  }
  final value = (watermarkTemplate[key] ?? '').toString().trim();
  if (value.isEmpty) {
    return emptyLabel;
  }
  return value;
}

String stableJsonString(dynamic value) {
  return jsonEncode(_canonicalizeJsonLike(value));
}

dynamic _canonicalizeJsonLike(dynamic value) {
  if (value is Map) {
    final entries =
        value.entries
            .map(
              (entry) => MapEntry(
                entry.key.toString(),
                _canonicalizeJsonLike(entry.value),
              ),
            )
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    return <String, dynamic>{
      for (final entry in entries) entry.key: entry.value,
    };
  }
  if (value is List) {
    return value
        .map<dynamic>((item) => _canonicalizeJsonLike(item))
        .toList(growable: false);
  }
  return value;
}

Map<String, dynamic> emptyPublishedBundle() => <String, dynamic>{
  'inspectionItems': const <Map<String, dynamic>>[],
  'meterRooms': const <Map<String, dynamic>>[],
  'overloadTemplates': const <Map<String, dynamic>>[],
  'appPreferences': <String, dynamic>{},
  'watermarkTemplate': <String, dynamic>{},
};

Map<String, dynamic> emptyReviewTargetBundle() => <String, dynamic>{
  'inspectionItems': const <Map<String, dynamic>>[],
  'meterRooms': const <Map<String, dynamic>>[],
  'overloadTemplates': const <Map<String, dynamic>>[],
};

Map<String, dynamic> buildReviewTargetBundle(Map<String, dynamic> bundle) {
  return <String, dynamic>{
    'inspectionItems': asMapList(bundle['inspectionItems']),
    'meterRooms': asMapList(bundle['meterRooms']),
    'overloadTemplates': asMapList(bundle['overloadTemplates']),
  };
}

Map<String, dynamic> mergeReviewBundleIntoFullBundle({
  required Map<String, dynamic> baseBundle,
  required Map<String, dynamic> reviewBundle,
}) {
  final merged = Map<String, dynamic>.from(emptyPublishedBundle())
    ..addAll(baseBundle);
  merged['inspectionItems'] = asMapList(reviewBundle['inspectionItems']);
  merged['meterRooms'] = asMapList(reviewBundle['meterRooms']);
  merged['overloadTemplates'] = asMapList(reviewBundle['overloadTemplates']);
  merged['appPreferences'] = asStringMap(merged['appPreferences']);
  merged['watermarkTemplate'] = asStringMap(merged['watermarkTemplate']);
  return merged;
}

Map<String, Map<String, dynamic>> indexRecords(
  List<Map<String, dynamic>> items,
  String Function(Map<String, dynamic> item, int index) keyBuilder,
) {
  final map = <String, Map<String, dynamic>>{};
  for (var index = 0; index < items.length; index++) {
    final item = items[index];
    var key = keyBuilder(item, index).trim();
    if (key.isEmpty) {
      key = 'item_${index + 1}';
    }
    var dedupedKey = key;
    var suffix = 2;
    while (map.containsKey(dedupedKey)) {
      dedupedKey = '$key#$suffix';
      suffix++;
    }
    map[dedupedKey] = item;
  }
  return map;
}

String inspectionKeyOf(Map<String, dynamic> item, int index) {
  final name = normalizedText(item['name']);
  if (name.isNotEmpty) {
    return 'name:$name';
  }
  final serial = normalizedText(item['serial']);
  if (serial.isNotEmpty) {
    return 'serial:$serial';
  }
  final id = normalizedText(item['id']);
  if (id.isNotEmpty) {
    return 'id:$id';
  }
  return 'inspection_${index + 1}';
}

String inspectionLabelOf(Map<String, dynamic> item) {
  final name = normalizedText(item['name']);
  if (name.isNotEmpty) {
    return name;
  }
  final serial = normalizedText(item['serial']);
  if (serial.isNotEmpty) {
    return serial;
  }
  final id = normalizedText(item['id']);
  if (id.isNotEmpty) {
    return '房间#$id';
  }
  return '未命名房间';
}

String roomKeyOf(Map<String, dynamic> room, int index) {
  final roomName = normalizedText(room['roomName']);
  if (roomName.isNotEmpty) {
    return 'room:$roomName';
  }
  final roomId = normalizedText(room['roomId']);
  if (roomId.isNotEmpty) {
    return 'id:$roomId';
  }
  return 'room_${index + 1}';
}

String roomLabelOf(Map<String, dynamic> room, int index) =>
    displayRoomName(room, index + 1);

String deviceKeyOf(Map<String, dynamic> device, int index) {
  final name = normalizedText(device['name']);
  if (name.isNotEmpty) {
    return 'device:$name';
  }
  return 'device_${index + 1}';
}

String deviceLabelOf(Map<String, dynamic> device, int index) {
  final name = normalizedText(device['name']);
  if (name.isNotEmpty) {
    return name;
  }
  return '设备${index + 1}';
}

String overloadSlotLabelOf(Map<String, dynamic> entry, int index) {
  final label = normalizedText(entry['label']);
  if (label.isNotEmpty) {
    return label;
  }
  return '未命名时段${index + 1}';
}

String displayOptionalText(dynamic value) {
  final text = normalizedText(value);
  return text.isEmpty ? '未设置' : text;
}

List<String> normalizedValueList(dynamic value) {
  if (value is! List) {
    return const <String>[];
  }
  return value.map((item) => item.toString().trim()).toList(growable: false);
}

bool stringListsEqual(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

String formatValueList(List<String> values) {
  if (values.isEmpty) {
    return '空';
  }
  return values.join('/');
}

void _appendFieldChange(
  List<String> changes, {
  required String label,
  required dynamic remoteValue,
  required dynamic candidateValue,
}) {
  final remoteText = displayOptionalText(remoteValue);
  final candidateText = displayOptionalText(candidateValue);
  if (remoteText != candidateText) {
    changes.add('$label $remoteText -> $candidateText');
  }
}

List<String> sortedKeysOf(Iterable<String> keys) {
  final list = keys.toList()..sort();
  return list;
}

String formatOverloadSlotOverview(Map<String, dynamic> entry, int index) {
  final rooms = asMapList(asStringMap(entry['rawData'])['rooms']);
  final deviceCount = rooms.fold<int>(
    0,
    (sum, room) => sum + asMapList(room['devices']).length,
  );
  return '${overloadSlotLabelOf(entry, index)}（${rooms.length} 房 / $deviceCount 台）';
}

List<String> buildDeviceValueChangeLines({
  required Map<String, Map<String, dynamic>> candidateDevices,
  required Map<String, Map<String, dynamic>> remoteDevices,
  required String prefix,
}) {
  final detailed = <String>[];
  final changedNames = <String>[];
  final commonKeys = sortedKeysOf(
    candidateDevices.keys.toSet().intersection(remoteDevices.keys.toSet()),
  );
  for (final key in commonKeys) {
    final candidateDevice = candidateDevices[key]!;
    final remoteDevice = remoteDevices[key]!;
    final candidateValues = normalizedValueList(candidateDevice['values']);
    final remoteValues = normalizedValueList(remoteDevice['values']);
    if (stringListsEqual(candidateValues, remoteValues)) {
      continue;
    }
    final deviceName = deviceLabelOf(candidateDevice, 0);
    changedNames.add(deviceName);
    if (changedNames.length <= 4) {
      detailed.add(
        '$prefix设备 $deviceName 参数 ${formatValueList(remoteValues)} -> ${formatValueList(candidateValues)}',
      );
    }
  }
  if (changedNames.length > 4) {
    return <String>['$prefix设备模板有变化：${previewItems(changedNames)}'];
  }
  return detailed;
}

CloudReviewDiff buildReviewDiff({
  required Map<String, dynamic> candidateReviewBundle,
  required Map<String, dynamic> remoteReviewBundle,
}) {
  final inspectionAdded = <String>[];
  final inspectionRemoved = <String>[];
  final inspectionChanged = <String>[];
  final inspectionChangedLabels = <String>{};

  final candidateInspection = asMapList(
    candidateReviewBundle['inspectionItems'],
  );
  final remoteInspection = asMapList(remoteReviewBundle['inspectionItems']);
  final candidateInspectionMap = indexRecords(
    candidateInspection,
    inspectionKeyOf,
  );
  final remoteInspectionMap = indexRecords(remoteInspection, inspectionKeyOf);
  for (final key in sortedKeysOf({
    ...candidateInspectionMap.keys,
    ...remoteInspectionMap.keys,
  })) {
    final candidateItem = candidateInspectionMap[key];
    final remoteItem = remoteInspectionMap[key];
    if (remoteItem == null && candidateItem != null) {
      inspectionAdded.add(inspectionLabelOf(candidateItem));
      continue;
    }
    if (candidateItem == null && remoteItem != null) {
      inspectionRemoved.add(inspectionLabelOf(remoteItem));
      continue;
    }
    if (candidateItem == null || remoteItem == null) {
      continue;
    }
    final roomLabel = inspectionLabelOf(candidateItem);
    final changes = <String>[];
    _appendFieldChange(
      changes,
      label: '名称',
      remoteValue: remoteItem['name'],
      candidateValue: candidateItem['name'],
    );
    _appendFieldChange(
      changes,
      label: '位置',
      remoteValue: remoteItem['location'],
      candidateValue: candidateItem['location'],
    );
    _appendFieldChange(
      changes,
      label: '类型',
      remoteValue: remoteItem['type'],
      candidateValue: candidateItem['type'],
    );
    _appendFieldChange(
      changes,
      label: '编号',
      remoteValue: remoteItem['serial'],
      candidateValue: candidateItem['serial'],
    );
    if (changes.isNotEmpty) {
      inspectionChanged.add('$roomLabel：${changes.join('；')}');
      inspectionChangedLabels.add(roomLabel);
    }
  }

  final meterRoomAdded = <String>[];
  final meterRoomRemoved = <String>[];
  final meterRoomChanged = <String>[];
  final meterRoomChangedLabels = <String>{};

  final candidateMeterRooms = asMapList(candidateReviewBundle['meterRooms']);
  final remoteMeterRooms = asMapList(remoteReviewBundle['meterRooms']);
  final candidateMeterMap = indexRecords(candidateMeterRooms, roomKeyOf);
  final remoteMeterMap = indexRecords(remoteMeterRooms, roomKeyOf);
  for (final key in sortedKeysOf({
    ...candidateMeterMap.keys,
    ...remoteMeterMap.keys,
  })) {
    final candidateRoom = candidateMeterMap[key];
    final remoteRoom = remoteMeterMap[key];
    if (remoteRoom == null && candidateRoom != null) {
      meterRoomAdded.add(roomLabelOf(candidateRoom, 0));
      continue;
    }
    if (candidateRoom == null && remoteRoom != null) {
      meterRoomRemoved.add(roomLabelOf(remoteRoom, 0));
      continue;
    }
    if (candidateRoom == null || remoteRoom == null) {
      continue;
    }
    final roomLabel = roomLabelOf(candidateRoom, 0);
    final roomMetaChanges = <String>[];
    _appendFieldChange(
      roomMetaChanges,
      label: '房间类型',
      remoteValue: remoteRoom['roomType'],
      candidateValue: candidateRoom['roomType'],
    );
    _appendFieldChange(
      roomMetaChanges,
      label: '位置',
      remoteValue: remoteRoom['location'],
      candidateValue: candidateRoom['location'],
    );
    if (roomMetaChanges.isNotEmpty) {
      meterRoomChanged.add('$roomLabel：${roomMetaChanges.join('；')}');
      meterRoomChangedLabels.add(roomLabel);
    }

    final candidateDevices = asMapList(candidateRoom['devices']);
    final remoteDevices = asMapList(remoteRoom['devices']);
    final candidateDeviceMap = indexRecords(candidateDevices, deviceKeyOf);
    final remoteDeviceMap = indexRecords(remoteDevices, deviceKeyOf);
    final addedDevices =
        sortedKeysOf(
              candidateDeviceMap.keys.toSet().difference(
                remoteDeviceMap.keys.toSet(),
              ),
            )
            .map((deviceKey) => deviceLabelOf(candidateDeviceMap[deviceKey]!, 0))
            .toList();
    final removedDevices = sortedKeysOf(
      remoteDeviceMap.keys.toSet().difference(candidateDeviceMap.keys.toSet()),
    ).map((deviceKey) => deviceLabelOf(remoteDeviceMap[deviceKey]!, 0)).toList();
    if (addedDevices.isNotEmpty) {
      meterRoomChanged.add(
        '$roomLabel：新增设备 ${previewItems(addedDevices, limit: 6)}',
      );
      meterRoomChangedLabels.add(roomLabel);
    }
    if (removedDevices.isNotEmpty) {
      meterRoomChanged.add(
        '$roomLabel：删除设备 ${previewItems(removedDevices, limit: 6)}',
      );
      meterRoomChangedLabels.add(roomLabel);
    }
  }

  final overloadSlotAdded = <String>[];
  final overloadSlotRemoved = <String>[];
  final overloadSlotChanged = <String>[];
  final overloadSlotChangedLabels = <String>{};

  final candidateOverloadTemplates = asMapList(
    candidateReviewBundle['overloadTemplates'],
  );
  final remoteOverloadTemplates = asMapList(
    remoteReviewBundle['overloadTemplates'],
  );
  final candidateOverloadMap = indexRecords(
    candidateOverloadTemplates,
    (entry, index) => overloadSlotLabelOf(entry, index),
  );
  final remoteOverloadMap = indexRecords(
    remoteOverloadTemplates,
    (entry, index) => overloadSlotLabelOf(entry, index),
  );
  for (final key in sortedKeysOf({
    ...candidateOverloadMap.keys,
    ...remoteOverloadMap.keys,
  })) {
    final candidateSlot = candidateOverloadMap[key];
    final remoteSlot = remoteOverloadMap[key];
    if (remoteSlot == null && candidateSlot != null) {
      overloadSlotAdded.add(formatOverloadSlotOverview(candidateSlot, 0));
      continue;
    }
    if (candidateSlot == null && remoteSlot != null) {
      overloadSlotRemoved.add(formatOverloadSlotOverview(remoteSlot, 0));
      continue;
    }
    if (candidateSlot == null || remoteSlot == null) {
      continue;
    }
    final slotLabel = overloadSlotLabelOf(candidateSlot, 0);
    final candidateRooms = asMapList(
      asStringMap(candidateSlot['rawData'])['rooms'],
    );
    final remoteRooms = asMapList(
      asStringMap(remoteSlot['rawData'])['rooms'],
    );
    final candidateRoomMap = indexRecords(candidateRooms, roomKeyOf);
    final remoteRoomMap = indexRecords(remoteRooms, roomKeyOf);

    final addedRooms = sortedKeysOf(
      candidateRoomMap.keys.toSet().difference(remoteRoomMap.keys.toSet()),
    ).map((roomKey) => roomLabelOf(candidateRoomMap[roomKey]!, 0)).toList();
    final removedRooms = sortedKeysOf(
      remoteRoomMap.keys.toSet().difference(candidateRoomMap.keys.toSet()),
    ).map((roomKey) => roomLabelOf(remoteRoomMap[roomKey]!, 0)).toList();
    if (addedRooms.isNotEmpty) {
      overloadSlotChanged.add(
        '$slotLabel：新增房间 ${previewItems(addedRooms, limit: 6)}',
      );
      overloadSlotChangedLabels.add(slotLabel);
    }
    if (removedRooms.isNotEmpty) {
      overloadSlotChanged.add(
        '$slotLabel：删除房间 ${previewItems(removedRooms, limit: 6)}',
      );
      overloadSlotChangedLabels.add(slotLabel);
    }

    for (final roomKey in sortedKeysOf(
      candidateRoomMap.keys.toSet().intersection(remoteRoomMap.keys.toSet()),
    )) {
      final candidateRoom = candidateRoomMap[roomKey]!;
      final remoteRoom = remoteRoomMap[roomKey]!;
      final roomLabel = roomLabelOf(candidateRoom, 0);
      final roomMetaChanges = <String>[];
      _appendFieldChange(
        roomMetaChanges,
        label: '房间类型',
        remoteValue: remoteRoom['roomType'],
        candidateValue: candidateRoom['roomType'],
      );
      _appendFieldChange(
        roomMetaChanges,
        label: '位置',
        remoteValue: remoteRoom['location'],
        candidateValue: candidateRoom['location'],
      );
      if (roomMetaChanges.isNotEmpty) {
        overloadSlotChanged.add(
          '$slotLabel / $roomLabel：${roomMetaChanges.join('；')}',
        );
        overloadSlotChangedLabels.add(slotLabel);
      }

      final candidateDevices = asMapList(candidateRoom['devices']);
      final remoteDevices = asMapList(remoteRoom['devices']);
      final candidateDeviceMap = indexRecords(candidateDevices, deviceKeyOf);
      final remoteDeviceMap = indexRecords(remoteDevices, deviceKeyOf);
      final addedDevices =
          sortedKeysOf(
                candidateDeviceMap.keys.toSet().difference(
                  remoteDeviceMap.keys.toSet(),
                ),
              )
              .map(
                (deviceKey) => deviceLabelOf(candidateDeviceMap[deviceKey]!, 0),
              )
              .toList();
      final removedDevices =
          sortedKeysOf(
                remoteDeviceMap.keys.toSet().difference(
                  candidateDeviceMap.keys.toSet(),
                ),
              )
              .map((deviceKey) => deviceLabelOf(remoteDeviceMap[deviceKey]!, 0))
              .toList();
      if (addedDevices.isNotEmpty) {
        overloadSlotChanged.add(
          '$slotLabel / $roomLabel：新增设备 ${previewItems(addedDevices, limit: 6)}',
        );
        overloadSlotChangedLabels.add(slotLabel);
      }
      if (removedDevices.isNotEmpty) {
        overloadSlotChanged.add(
          '$slotLabel / $roomLabel：删除设备 ${previewItems(removedDevices, limit: 6)}',
        );
        overloadSlotChangedLabels.add(slotLabel);
      }
      final deviceValueChanges = buildDeviceValueChangeLines(
        candidateDevices: candidateDeviceMap,
        remoteDevices: remoteDeviceMap,
        prefix: '$slotLabel / $roomLabel：',
      );
      if (deviceValueChanges.isNotEmpty) {
        overloadSlotChanged.addAll(deviceValueChanges);
        overloadSlotChangedLabels.add(slotLabel);
      }
    }
  }

  final summaryLines = <String>[];
  if (inspectionAdded.isNotEmpty ||
      inspectionRemoved.isNotEmpty ||
      inspectionChangedLabels.isNotEmpty) {
    summaryLines.add(
      '拍照房间：新增 ${inspectionAdded.length} 个，删除 ${inspectionRemoved.length} 个，修改 ${inspectionChangedLabels.length} 个',
    );
  }
  if (meterRoomAdded.isNotEmpty ||
      meterRoomRemoved.isNotEmpty ||
      meterRoomChangedLabels.isNotEmpty) {
    summaryLines.add(
      '动力抄表模板：新增房间 ${meterRoomAdded.length} 个，删除 ${meterRoomRemoved.length} 个，修改房间 ${meterRoomChangedLabels.length} 个',
    );
  }
  if (overloadSlotAdded.isNotEmpty ||
      overloadSlotRemoved.isNotEmpty ||
      overloadSlotChangedLabels.isNotEmpty) {
    summaryLines.add(
      '动力超标时段：新增时段 ${overloadSlotAdded.length} 个，删除时段 ${overloadSlotRemoved.length} 个，修改时段 ${overloadSlotChangedLabels.length} 个',
    );
  }

  return CloudReviewDiff(
    summaryLines: List<String>.unmodifiable(summaryLines),
    inspectionAdded: List<String>.unmodifiable(inspectionAdded),
    inspectionRemoved: List<String>.unmodifiable(inspectionRemoved),
    inspectionChanged: List<String>.unmodifiable(inspectionChanged),
    inspectionChangedCount: inspectionChangedLabels.length,
    meterRoomAdded: List<String>.unmodifiable(meterRoomAdded),
    meterRoomRemoved: List<String>.unmodifiable(meterRoomRemoved),
    meterRoomChanged: List<String>.unmodifiable(meterRoomChanged),
    meterRoomChangedCount: meterRoomChangedLabels.length,
    overloadSlotAdded: List<String>.unmodifiable(overloadSlotAdded),
    overloadSlotRemoved: List<String>.unmodifiable(overloadSlotRemoved),
    overloadSlotChanged: List<String>.unmodifiable(overloadSlotChanged),
    overloadSlotChangedCount: overloadSlotChangedLabels.length,
  );
}
