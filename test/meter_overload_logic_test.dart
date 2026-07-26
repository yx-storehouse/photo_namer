import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_namer/models/meter_models.dart';
import 'package:photo_namer/services/meter_overload_logic.dart';

/// 固定输出的 Random,便于断言随机浮动结果。
class _FixedRandom implements math.Random {
  final double value;
  _FixedRandom(this.value);

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => value;

  @override
  int nextInt(int max) => 0;
}

MeterTimeSlotDataset _buildDataset({List<MeterRoom>? rooms}) {
  final effectiveRooms =
      rooms ??
      [
        MeterRoom(
          roomId: 1,
          roomName: '一号配电房',
          roomType: '配电房',
          location: '1F',
          devices: [
            MeterDevice(
              name: 'UPS-A',
              values: ['220', '221', '219', '10.5', '0', '8'],
            ),
            MeterDevice(
              name: '进线柜',
              values: ['380', '381', '379', '100', '105', '98'],
            ),
          ],
        ),
      ];
  return MeterTimeSlotDataset(
    slot: const MeterTimeSlotDefinition(label: '12点', assetPath: 'csv/12点.json'),
    exportedAt: '2026-01-01T12:00:00',
    rawData: {'version': 1, 'note': 'origin'},
    rooms: effectiveRooms,
  );
}

void main() {
  group('randomizeCurrentValue', () {
    test('零值与非数字保持原样', () {
      final random = _FixedRandom(0.5);
      expect(randomizeCurrentValue('0', 5, 5, random), '0');
      expect(randomizeCurrentValue('abc', 5, 5, random), 'abc');
      expect(randomizeCurrentValue('', 5, 5, random), '');
    });

    test('浮动结果保留原始小数位数', () {
      final random = _FixedRandom(1.0); // factor = 1 + up%
      expect(randomizeCurrentValue('10.5', 0, 10, random), '11.6');
      expect(randomizeCurrentValue('100', 0, 10, random), '110');
      expect(randomizeCurrentValue('3.25', 0, 100, random), '6.50');
    });

    test('浮动范围受上下限约束', () {
      final original = 100.0;
      for (final r in [0.0, 0.25, 0.5, 0.75, 0.999]) {
        final produced = double.parse(
          randomizeCurrentValue('100', 5, 5, _FixedRandom(r)),
        );
        expect(produced, greaterThanOrEqualTo(original * 0.95));
        expect(produced, lessThanOrEqualTo(original * 1.05));
      }
    });

    test('下浮不会产生负数', () {
      final produced = double.parse(
        randomizeCurrentValue('1', 200, 0, _FixedRandom(0.0)),
      );
      expect(produced, greaterThanOrEqualTo(0));
    });
  });

  group('buildRandomizedPayload', () {
    test('只随机电流位(索引3-5),电压位不变', () {
      final dataset = _buildDataset();
      final payload = buildRandomizedPayload(
        dataset,
        downPercent: 0,
        upPercent: 10,
        lockedDeviceKeys: const <String>{},
        random: _FixedRandom(1.0),
      );

      final rooms = payload['rooms'] as List;
      final devices = (rooms.first as Map)['devices'] as List;
      final upsValues = (devices.first as Map)['values'] as List;

      expect(upsValues.sublist(0, 3), ['220', '221', '219']);
      expect(upsValues[3], '11.6'); // 10.5 * 1.1,保留1位小数
      expect(upsValues[4], '0'); // 零值不参与
      expect(upsValues[5], '9'); // 8 * 1.1 = 8.8 → 整数位则四舍五入为9
      expect(payload['randomized'], isTrue);
      expect(payload['selectedTimeSlot'], '12点');
      expect(payload['randomRangePercent'], {'down': 0.0, 'up': 10.0});
    });

    test('锁定设备整台不参与随机,并记录到 lockedDevices', () {
      final dataset = _buildDataset();
      final lockedKey = deviceLockKey(
        dataset,
        dataset.rooms.first,
        dataset.rooms.first.devices.first,
      );
      final payload = buildRandomizedPayload(
        dataset,
        downPercent: 0,
        upPercent: 50,
        lockedDeviceKeys: {lockedKey},
        random: _FixedRandom(1.0),
      );

      final rooms = payload['rooms'] as List;
      final devices = (rooms.first as Map)['devices'] as List;
      final lockedValues = (devices.first as Map)['values'] as List;
      final freeValues = (devices.last as Map)['values'] as List;

      expect(lockedValues, ['220', '221', '219', '10.5', '0', '8']);
      expect(freeValues[3], isNot('100'));
      expect(payload['lockedDeviceCount'], 1);
      expect((payload['lockedDevices'] as List).single, {
        'roomId': 1,
        'roomName': '一号配电房',
        'deviceName': 'UPS-A',
      });
      expect(payload['randomizedValueCount'], 3); // 进线柜的三个非零电流
    });

    test('原始 rawData 字段透传且不被修改', () {
      final dataset = _buildDataset();
      final payload = buildRandomizedPayload(
        dataset,
        downPercent: 5,
        upPercent: 5,
        lockedDeviceKeys: const <String>{},
        random: _FixedRandom(0.5),
      );
      expect(payload['note'], 'origin');
      expect(dataset.rawData.containsKey('randomized'), isFalse);
    });
  });

  group('pruneLockedKeysForDataset', () {
    test('清除本时段失效key,保留其他时段key', () {
      final dataset = _buildDataset();
      final validKey = deviceLockKey(
        dataset,
        dataset.rooms.first,
        dataset.rooms.first.devices.first,
      );
      final staleKey = '12点::1::已删除的设备';
      final otherSlotKey = '22点::9::任意设备';

      final pruned = pruneLockedKeysForDataset(dataset, {
        validKey,
        staleKey,
        otherSlotKey,
      });

      expect(pruned, contains(validKey));
      expect(pruned, isNot(contains(staleKey)));
      expect(pruned, contains(otherSlotKey));
    });
  });

  group('nearestMeterTimeSlot', () {
    test('整点附近匹配到最近时段', () {
      expect(nearestMeterTimeSlotLabel(DateTime(2026, 7, 20, 11, 40)), '12点');
      expect(nearestMeterTimeSlotLabel(DateTime(2026, 7, 20, 17, 10)), '18点');
      expect(nearestMeterTimeSlotLabel(DateTime(2026, 7, 20, 2, 5)), '2点');
    });

    test('跨零点按环形距离匹配(23:50 更接近 2点而不是 22点)', () {
      // 23:50 距 22点 1.83h,距 2点(次日) 2.17h → 仍是22点;
      // 0:30 距 2点 1.5h,距 22点 2.5h → 2点。
      expect(nearestMeterTimeSlotLabel(DateTime(2026, 7, 20, 23, 50)), '22点');
      expect(nearestMeterTimeSlotLabel(DateTime(2026, 7, 21, 0, 30)), '2点');
    });

    test('天气刷新key由日期与时段组成', () {
      expect(
        captureWeatherRefreshSlotKey(DateTime(2026, 7, 20, 11, 40)),
        '2026-07-20|12点',
      );
    });
  });
}
