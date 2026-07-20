import 'package:flutter_test/flutter_test.dart';
import 'package:photo_namer/models/inspection_calendar.dart';

void main() {
  group('日期key编解码', () {
    test('格式化与解析互逆', () {
      final date = DateTime(2026, 7, 5);
      final key = formatInspectionCalendarDateKey(date);
      expect(key, '2026-07-05');
      expect(parseInspectionCalendarDateKey(key), DateTime(2026, 7, 5));
    });

    test('非法key解析返回null', () {
      expect(parseInspectionCalendarDateKey('2026-13'), isNull);
      expect(parseInspectionCalendarDateKey('abc-de-fg'), isNull);
    });
  });

  group('巡检记录编解码', () {
    test('往返编解码保留完成时段', () {
      final records = {
        '2026-07-20': const InspectionCalendarDayRecord(
          dateKey: '2026-07-20',
          completedSlots: {'12点', '18点'},
          updatedAt: '2026-07-20T18:05:00',
        ),
      };
      final decoded = decodeInspectionCalendarRecords(
        encodeInspectionCalendarRecords(records),
      );
      expect(decoded.keys, ['2026-07-20']);
      expect(decoded['2026-07-20']!.completedSlots, {'12点', '18点'});
    });

    test('空时段记录在编码时被丢弃,坏数据解码为空表', () {
      final records = {
        '2026-07-20': InspectionCalendarDayRecord.empty('2026-07-20'),
      };
      expect(encodeInspectionCalendarRecords(records), '{}');
      expect(decodeInspectionCalendarRecords('not json'), isEmpty);
      expect(decodeInspectionCalendarRecords(null), isEmpty);
    });
  });

  group('轮班类型推算', () {
    // 8天循环:早早中中晚晚休休
    final config = InspectionShiftScheduleConfig(
      firstMorningShiftDateKey: '2026-07-01',
      rotationMemberCount: 1,
      firstInspectionDateKey: '2026-07-01',
      firstInspectionSlotLabel: '',
    );

    test('按8天循环推算班次', () {
      expect(
        inspectionShiftTypeForDate(DateTime(2026, 7, 1), config),
        InspectionShiftType.morning,
      );
      expect(
        inspectionShiftTypeForDate(DateTime(2026, 7, 3), config),
        InspectionShiftType.middle,
      );
      expect(
        inspectionShiftTypeForDate(DateTime(2026, 7, 5), config),
        InspectionShiftType.night,
      );
      expect(
        inspectionShiftTypeForDate(DateTime(2026, 7, 7), config),
        InspectionShiftType.rest,
      );
      // 下一个循环重新开始
      expect(
        inspectionShiftTypeForDate(DateTime(2026, 7, 9), config),
        InspectionShiftType.morning,
      );
    });

    test('基准日之前的日期按负偏移回绕', () {
      // 6月30日是基准日前一天 → 循环末位:休
      expect(
        inspectionShiftTypeForDate(DateTime(2026, 6, 30), config),
        InspectionShiftType.rest,
      );
    });

    test('班次对应的必巡时段', () {
      expect(inspectionRequiredSlotsForShift(InspectionShiftType.morning), [
        '12点',
      ]);
      expect(inspectionRequiredSlotsForShift(InspectionShiftType.night), [
        '22点',
        '2点',
        '6点',
      ]);
      expect(
        inspectionRequiredSlotsForShift(InspectionShiftType.rest),
        isEmpty,
      );
    });
  });

  group('轮值分配', () {
    test('单人轮值时所有排班时段都归自己', () {
      final config = InspectionShiftScheduleConfig(
        firstMorningShiftDateKey: '2026-07-01',
        rotationMemberCount: 1,
        firstInspectionDateKey: '2026-07-01',
        firstInspectionSlotLabel: '',
      );
      expect(assignedInspectionSlotsForDate(DateTime(2026, 7, 1), config), [
        '12点',
      ]);
      expect(assignedInspectionSlotsForDate(DateTime(2026, 7, 5), config), [
        '22点',
        '2点',
        '6点',
      ]);
    });

    test('两人轮值时按时段序号隔一个轮到一次', () {
      final config = InspectionShiftScheduleConfig(
        firstMorningShiftDateKey: '2026-07-01',
        rotationMemberCount: 2,
        firstInspectionDateKey: '2026-07-01',
        firstInspectionSlotLabel: '',
      );
      // 时段序列: 7/1[12点]=0, 7/2[12点]=1, 7/3[18点]=2, 7/4[18点]=3,
      // 7/5[22,2,6]=4,5,6 ...
      expect(
        assignedInspectionSlotsForDate(DateTime(2026, 7, 1), config),
        ['12点'], // index 0 → 自己
      );
      expect(
        assignedInspectionSlotsForDate(DateTime(2026, 7, 2), config),
        isEmpty, // index 1 → 另一人
      );
      expect(assignedInspectionSlotsForDate(DateTime(2026, 7, 5), config), [
        '22点',
        '6点',
      ]); // index 4、6 是自己,5 是另一人
    });

    test('起始日之前不分配', () {
      final config = InspectionShiftScheduleConfig(
        firstMorningShiftDateKey: '2026-07-01',
        rotationMemberCount: 1,
        firstInspectionDateKey: '2026-07-10',
        firstInspectionSlotLabel: '',
      );
      expect(
        assignedInspectionSlotsForDate(DateTime(2026, 7, 5), config),
        isEmpty,
      );
    });
  });

  group('拍照时刻自动补记时段', () {
    test('取当天分配时段中距当前时刻最近的', () {
      final config = InspectionShiftScheduleConfig(
        firstMorningShiftDateKey: '2026-07-01',
        rotationMemberCount: 1,
        firstInspectionDateKey: '2026-07-01',
        firstInspectionSlotLabel: '',
      );
      // 7/5 是晚班(22/2/6),23:30 最接近22点
      expect(
        matchedInspectionSlotLabelForMoment(
          DateTime(2026, 7, 5, 23, 30),
          config,
        ),
        '22点',
      );
      // 休息日没有分配 → 空
      expect(
        matchedInspectionSlotLabelForMoment(
          DateTime(2026, 7, 7, 12, 0),
          config,
        ),
        '',
      );
    });
  });
}
