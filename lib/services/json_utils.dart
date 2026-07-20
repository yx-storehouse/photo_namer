


Map<String, dynamic> stringKeyedMap(dynamic raw) {
  if (raw is! Map) {
    return <String, dynamic>{};
  }
  return <String, dynamic>{
    for (final entry in raw.entries) entry.key.toString(): entry.value,
  };
}

List<Map<String, dynamic>> stringKeyedMapList(dynamic raw) {
  if (raw is! List) {
    return <Map<String, dynamic>>[];
  }
  return raw.whereType<Map>().map(stringKeyedMap).toList(growable: false);
}

Map<String, int> intMapFromJson(dynamic raw) {
  final source = stringKeyedMap(raw);
  final result = <String, int>{};
  for (final entry in source.entries) {
    final value = entry.value is num
        ? (entry.value as num).toInt()
        : int.tryParse(entry.value.toString());
    if (value != null) {
      result[entry.key] = value;
    }
  }
  return result;
}

List<int> intListFromJson(dynamic raw) {
  if (raw is! List) {
    return <int>[];
  }
  return raw
      .map((value) => value is num ? value.toInt() : int.tryParse('$value'))
      .whereType<int>()
      .toList(growable: false);
}

String cloudStringDefault(
  Map<String, dynamic> source,
  String key,
  String fallback,
) {
  final value = source[key];
  return value is String ? value : fallback;
}

bool cloudBoolDefault(Map<String, dynamic> source, String key, bool fallback) {
  final value = source[key];
  return value is bool ? value : fallback;
}

int cloudIntDefault(Map<String, dynamic> source, String key, int fallback) {
  final value = source[key];
  return value is num ? value.toInt() : fallback;
}

double cloudDoubleDefault(
  Map<String, dynamic> source,
  String key,
  double fallback,
) {
  final value = source[key];
  return value is num ? value.toDouble() : fallback;
}

