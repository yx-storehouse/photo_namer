import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

class CaptureLocationSnapshot {
  final Position? position;
  final String address;

  const CaptureLocationSnapshot({
    required this.position,
    required this.address,
  });
}

class CaptureLocationService {
  static Future<String> resolveAddress({
    required String fallbackAddress,
  }) async {
    final snapshot = await resolveSnapshot(fallbackAddress: fallbackAddress);
    return snapshot.address;
  }

  static Future<CaptureLocationSnapshot> resolveSnapshot({
    required String fallbackAddress,
  }) async {
    Position? position;
    try {
      position = await _resolveCurrentPosition();
      if (position == null) {
        return CaptureLocationSnapshot(
          position: null,
          address: fallbackAddress,
        );
      }

      await setLocaleIdentifier('zh_CN');
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isEmpty) {
        return CaptureLocationSnapshot(
          position: position,
          address: fallbackAddress,
        );
      }

      final address = formatPlacemark(placemarks.first);
      return CaptureLocationSnapshot(
        position: position,
        address: address.isEmpty ? fallbackAddress : address,
      );
    } catch (e) {
      debugPrint('resolve address failed: $e');
      return CaptureLocationSnapshot(
        position: position,
        address: fallbackAddress,
      );
    }
  }

  static Future<Position?> _resolveCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    Position? position = await Geolocator.getLastKnownPosition();
    position ??= await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 6),
      ),
    );
    return position;
  }

  static String formatPlacemark(Placemark placemark) {
    final parts = <String>[];

    void append(String? raw) {
      var value = raw?.trim() ?? '';
      if (value.isEmpty) return;
      if (parts.isEmpty) {
        parts.add(value);
        return;
      }

      final joined = parts.join('');
      if (joined == value || joined.contains(value)) return;
      if (value.contains(joined)) {
        value = value.substring(value.indexOf(joined) + joined.length).trim();
        if (value.isEmpty) return;
      }

      final last = parts.last;
      if (last == value || last.contains(value)) return;
      if (value.contains(last)) {
        value = value.substring(value.indexOf(last) + last.length).trim();
        if (value.isEmpty) return;
      }
      parts.add(value);
    }

    append(placemark.administrativeArea);
    append(placemark.locality);
    append(placemark.subAdministrativeArea);
    append(placemark.subLocality);

    final thoroughfare =
        '${placemark.thoroughfare ?? ''}${placemark.subThoroughfare ?? ''}'
            .trim();
    append(thoroughfare);
    append(_stripKnownPrefix(placemark.street, parts, placemark));
    append(_stripKnownPrefix(placemark.name, parts, placemark));

    return parts.join('');
  }

  static String _stripKnownPrefix(
    String? raw,
    List<String> parts,
    Placemark placemark,
  ) {
    var value = raw?.trim() ?? '';
    if (value.isEmpty) return '';

    for (var length = parts.length; length > 0; length--) {
      final prefix = parts.take(length).join('');
      if (prefix.isNotEmpty && value.startsWith(prefix)) {
        value = value.substring(prefix.length).trim();
        break;
      }
    }

    final thoroughfare = (placemark.thoroughfare ?? '').trim();
    if (thoroughfare.isNotEmpty && value.startsWith(thoroughfare)) {
      value = value.substring(thoroughfare.length).trim();
    }

    final subThoroughfare = (placemark.subThoroughfare ?? '').trim();
    if (subThoroughfare.isNotEmpty && value.startsWith(subThoroughfare)) {
      value = value.substring(subThoroughfare.length).trim();
    }

    return value;
  }
}
