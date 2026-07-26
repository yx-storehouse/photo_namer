import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:photo_namer/capture_location_service.dart';

void main() {
  test('formats Chinese placemark into compact address', () {
    final placemark = Placemark(
      administrativeArea: '浙江省',
      locality: '杭州市',
      subAdministrativeArea: '萧山区',
      subLocality: '戴村镇',
      street: '泰悦银座',
    );

    expect(
      CaptureLocationService.formatPlacemark(placemark),
      '浙江省杭州市萧山区戴村镇泰悦银座',
    );
  });
}
