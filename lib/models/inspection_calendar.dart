import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:photo_namer/models/meter_models.dart';

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

