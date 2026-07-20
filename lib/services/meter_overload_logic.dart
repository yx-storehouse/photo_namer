import 'dart:math' as math;

import 'package:photo_namer/models/meter_models.dart';

/// 动力超标随机浮动导出的纯逻辑,便于单元测试。
/// 行为与原 MeterOverloadPage 内的私有实现完全一致。

String deviceLockKey(
  MeterTimeSlotDataset dataset,
  MeterRoom room,
  MeterDevice device,
) {
  return '${dataset.slot.label}::${room.roomId}::${device.name}';
}

int decimalPlaces(String raw) {
  final normalized = raw.trim();
  final dotIndex = normalized.indexOf('.');
  if (dotIndex < 0) {
    return 0;
  }
  return normalized.length - dotIndex - 1;
}

String formatRandomizedValue(double value, String originalRaw) {
  final decimals = decimalPlaces(originalRaw);
  return value.toStringAsFixed(decimals);
}

/// 对单个读数做随机浮动;0 或非数字保持原样。
String randomizeCurrentValue(
  String raw,
  double downPercent,
  double upPercent,
  math.Random random,
) {
  final original = double.tryParse(raw.trim());
  if (original == null || original == 0) {
    return raw;
  }

  final minFactor = math.max(0.0, 1 - downPercent / 100);
  final maxFactor = 1 + upPercent / 100;
  final factor = minFactor + random.nextDouble() * (maxFactor - minFactor);
  final randomized = math.max(0.0, original * factor);
  return formatRandomizedValue(randomized, raw);
}

List<Map<String, dynamic>> lockedDeviceSummariesForDataset(
  MeterTimeSlotDataset dataset,
  Set<String> lockedDeviceKeys,
) {
  final summaries = <Map<String, dynamic>>[];
  for (final room in dataset.rooms) {
    for (final device in room.devices) {
      if (lockedDeviceKeys.contains(deviceLockKey(dataset, room, device))) {
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

/// 构建随机浮动后的导出数据。只处理电流(values[3..5]),
/// 锁定设备整台跳过,payload 附带随机元信息。
Map<String, dynamic> buildRandomizedPayload(
  MeterTimeSlotDataset dataset, {
  required double downPercent,
  required double upPercent,
  required Set<String> lockedDeviceKeys,
  required math.Random random,
  DateTime? now,
}) {
  int randomizedValueCount = 0;
  final lockedDeviceSummaries = lockedDeviceSummariesForDataset(
    dataset,
    lockedDeviceKeys,
  );
  final randomizedRooms = dataset.rooms.map((room) {
    return {
      'roomId': room.roomId,
      'roomName': room.roomName,
      'roomType': room.roomType,
      'location': room.location,
      'devices': room.devices.map((device) {
        final values = List<String>.from(device.values);
        final locked = lockedDeviceKeys.contains(
          deviceLockKey(dataset, room, device),
        );
        if (!locked) {
          for (int i = 3; i <= 5 && i < values.length; i++) {
            final oldValue = values[i];
            final newValue = randomizeCurrentValue(
              oldValue,
              downPercent,
              upPercent,
              random,
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
  payload['randomizedAt'] = (now ?? DateTime.now()).toIso8601String();
  payload['randomizedValueCount'] = randomizedValueCount;
  payload['lockedDeviceCount'] = lockedDeviceSummaries.length;
  payload['lockedDevices'] = lockedDeviceSummaries;
  payload['randomRangePercent'] = {'down': downPercent, 'up': upPercent};
  return payload;
}

/// 清理某时段下已失效(设备被删除)的锁定 key;其他时段的 key 原样保留。
Set<String> pruneLockedKeysForDataset(
  MeterTimeSlotDataset dataset,
  Set<String> source,
) {
  final validKeys = <String>{};
  for (final room in dataset.rooms) {
    for (final device in room.devices) {
      validKeys.add(deviceLockKey(dataset, room, device));
    }
  }

  return source.where((key) {
    if (!key.startsWith('${dataset.slot.label}::')) {
      return true;
    }
    return validKeys.contains(key);
  }).toSet();
}
