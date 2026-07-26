import 'dart:math' as math;


import 'package:photo_namer/models/inspection_calendar.dart';

const String kPrefMeterOverloadTemplatesKey = 'meter_overload_templates';

const List<MeterTimeSlotDefinition> kDefaultMeterTimeSlots = [
  MeterTimeSlotDefinition(label: '2点', assetPath: 'csv/2点.json'),
  MeterTimeSlotDefinition(label: '6点', assetPath: 'csv/6点.json'),
  MeterTimeSlotDefinition(label: '12点', assetPath: 'csv/12点.json'),
  MeterTimeSlotDefinition(label: '18点', assetPath: 'csv/18点.json'),
  MeterTimeSlotDefinition(label: '22点', assetPath: 'csv/22点.json'),
];


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

