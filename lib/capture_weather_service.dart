import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class CaptureWeatherService {
  static Future<String> resolveCurrentWeather({
    required String fallbackWeatherText,
    required Position? position,
  }) async {
    if (position == null) {
      return fallbackWeatherText;
    }

    try {
      final uri =
          Uri.https('api.open-meteo.com', '/v1/forecast', <String, String>{
            'latitude': position.latitude.toStringAsFixed(6),
            'longitude': position.longitude.toStringAsFixed(6),
            'current': 'temperature_2m,weather_code',
            'timezone': 'auto',
            'forecast_days': '1',
          });

      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        debugPrint('resolve weather failed: HTTP ${response.statusCode}');
        return fallbackWeatherText;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return fallbackWeatherText;
      }

      final current = decoded['current'];
      if (current is! Map<String, dynamic>) {
        return fallbackWeatherText;
      }

      final temperature = (current['temperature_2m'] as num?)?.toDouble();
      final weatherCode = (current['weather_code'] as num?)?.toInt();
      if (temperature == null || weatherCode == null) {
        return fallbackWeatherText;
      }

      final conditionText = _mapWeatherCode(weatherCode);
      final temperatureText = '${temperature.round()}°C';
      return '$conditionText $temperatureText';
    } catch (error) {
      debugPrint('resolve weather failed: $error');
      return fallbackWeatherText;
    }
  }

  static String _mapWeatherCode(int code) {
    switch (code) {
      case 0:
      case 1:
        return '晴';
      case 2:
        return '多云';
      case 3:
        return '阴';
      case 45:
      case 48:
        return '有雾';
      case 51:
      case 53:
      case 55:
      case 56:
      case 57:
        return '毛毛雨';
      case 61:
      case 80:
        return '小雨';
      case 63:
      case 81:
        return '中雨';
      case 65:
      case 82:
        return '大雨';
      case 66:
      case 67:
        return '冻雨';
      case 71:
      case 77:
      case 85:
        return '小雪';
      case 73:
      case 86:
        return '中雪';
      case 75:
        return '大雪';
      case 95:
        return '雷雨';
      case 96:
      case 99:
        return '强雷雨';
      default:
        return '天气';
    }
  }
}
