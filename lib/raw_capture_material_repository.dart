import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'watermark_template_118.dart';

class RawCaptureMaterial {
  final int? id;
  final int inspectionItemId;
  final String itemSerial;
  final String itemName;
  final String roomCode;
  final String preferredOutputFileName;
  final String rawPhotoPath;
  final int captureTimeMillis;
  final String location;
  final String weatherText;
  final String imprintText;
  final Watermark118Adjustments adjustments;
  final String? displayTimeText;
  final String? displayDateText;
  final String? composedPhotoPath;
  final int? composedAtMillis;
  final int createdAtMillis;

  const RawCaptureMaterial({
    this.id,
    required this.inspectionItemId,
    required this.itemSerial,
    required this.itemName,
    required this.roomCode,
    required this.preferredOutputFileName,
    required this.rawPhotoPath,
    required this.captureTimeMillis,
    required this.location,
    required this.weatherText,
    required this.imprintText,
    this.adjustments = const Watermark118Adjustments(),
    this.displayTimeText,
    this.displayDateText,
    this.composedPhotoPath,
    this.composedAtMillis,
    required this.createdAtMillis,
  });

  bool get isComposed =>
      composedPhotoPath != null && composedPhotoPath!.trim().isNotEmpty;

  RawCaptureMaterial copyWith({
    int? id,
    int? inspectionItemId,
    String? itemSerial,
    String? itemName,
    String? roomCode,
    String? preferredOutputFileName,
    String? rawPhotoPath,
    int? captureTimeMillis,
    String? location,
    String? weatherText,
    String? imprintText,
    Watermark118Adjustments? adjustments,
    String? displayTimeText,
    String? displayDateText,
    String? composedPhotoPath,
    int? composedAtMillis,
    int? createdAtMillis,
  }) {
    return RawCaptureMaterial(
      id: id ?? this.id,
      inspectionItemId: inspectionItemId ?? this.inspectionItemId,
      itemSerial: itemSerial ?? this.itemSerial,
      itemName: itemName ?? this.itemName,
      roomCode: roomCode ?? this.roomCode,
      preferredOutputFileName:
          preferredOutputFileName ?? this.preferredOutputFileName,
      rawPhotoPath: rawPhotoPath ?? this.rawPhotoPath,
      captureTimeMillis: captureTimeMillis ?? this.captureTimeMillis,
      location: location ?? this.location,
      weatherText: weatherText ?? this.weatherText,
      imprintText: imprintText ?? this.imprintText,
      adjustments: adjustments ?? this.adjustments,
      displayTimeText: displayTimeText ?? this.displayTimeText,
      displayDateText: displayDateText ?? this.displayDateText,
      composedPhotoPath: composedPhotoPath ?? this.composedPhotoPath,
      composedAtMillis: composedAtMillis ?? this.composedAtMillis,
      createdAtMillis: createdAtMillis ?? this.createdAtMillis,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'inspection_item_id': inspectionItemId,
      'item_serial': itemSerial,
      'item_name': itemName,
      'room_code': roomCode,
      'preferred_output_file_name': preferredOutputFileName,
      'raw_photo_path': rawPhotoPath,
      'capture_time_millis': captureTimeMillis,
      'location': location,
      'weather_text': weatherText,
      'imprint_text': imprintText,
      'adjustments': adjustments.toMap(),
      'display_time_text': displayTimeText,
      'display_date_text': displayDateText,
      'composed_photo_path': composedPhotoPath,
      'composed_at_millis': composedAtMillis,
      'created_at_millis': createdAtMillis,
    };
  }

  factory RawCaptureMaterial.fromMap(Map<String, Object?> map) {
    return RawCaptureMaterial(
      id: (map['id'] as num?)?.toInt(),
      inspectionItemId: (map['inspection_item_id'] as num?)?.toInt() ?? 0,
      itemSerial: (map['item_serial'] as String?) ?? '',
      itemName: (map['item_name'] as String?) ?? '',
      roomCode: (map['room_code'] as String?) ?? '',
      preferredOutputFileName:
          (map['preferred_output_file_name'] as String?) ?? '',
      rawPhotoPath: (map['raw_photo_path'] as String?) ?? '',
      captureTimeMillis: (map['capture_time_millis'] as num?)?.toInt() ?? 0,
      location: (map['location'] as String?) ?? '',
      weatherText: (map['weather_text'] as String?) ?? '',
      imprintText: (map['imprint_text'] as String?) ?? '',
      adjustments: _readAdjustments(map['adjustments']),
      displayTimeText: _cleanNullableString(
        map['display_time_text'] as String?,
      ),
      displayDateText: _cleanNullableString(
        map['display_date_text'] as String?,
      ),
      composedPhotoPath: _cleanNullableString(
        map['composed_photo_path'] as String?,
      ),
      composedAtMillis: (map['composed_at_millis'] as num?)?.toInt(),
      createdAtMillis: (map['created_at_millis'] as num?)?.toInt() ?? 0,
    );
  }

  static String? _cleanNullableString(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  static Watermark118Adjustments _readAdjustments(Object? rawValue) {
    if (rawValue is Map) {
      return Watermark118Adjustments.fromMap(
        Map<String, dynamic>.from(
          rawValue.map((key, value) => MapEntry(key.toString(), value)),
        ),
      );
    }
    return const Watermark118Adjustments();
  }
}

class RawCaptureMaterialRepository {
  RawCaptureMaterialRepository._();

  static final RawCaptureMaterialRepository instance =
      RawCaptureMaterialRepository._();

  static const String _storageFileName = 'photo_namer_raw_materials.json';

  File? _storageFile;
  List<RawCaptureMaterial>? _materials;
  Future<void>? _initFuture;
  Future<void> _pendingWrite = Future<void>.value();

  Future<void> init() async {
    final existing = _initFuture;
    if (existing != null) {
      await existing;
      return;
    }

    final future = _loadFromDisk();
    _initFuture = future;
    try {
      await future;
    } catch (_) {
      _initFuture = null;
      rethrow;
    }
  }

  Future<int> countPendingMaterials() async {
    final materials = await _ensureLoaded();
    return materials.where((material) => !material.isComposed).length;
  }

  Future<void> insertMaterials(List<RawCaptureMaterial> materials) async {
    if (materials.isEmpty) {
      return;
    }

    final existing = await _ensureLoaded();
    var nextId = _nextMaterialId(existing);
    final updated = List<RawCaptureMaterial>.from(existing);
    for (final material in materials) {
      updated.add(material.copyWith(id: nextId));
      nextId++;
    }
    await _persist(updated);
  }

  Future<List<RawCaptureMaterial>> fetchPendingMaterials() async {
    final materials = await _ensureLoaded();
    return _sortMaterials(
      materials.where((material) => !material.isComposed).toList(),
    );
  }

  Future<List<RawCaptureMaterial>> fetchMaterialsForItem(int itemId) async {
    final materials = await _ensureLoaded();
    return _sortMaterials(
      materials
          .where((material) => material.inspectionItemId == itemId)
          .toList(),
    );
  }

  Future<List<String>> fetchComposedPhotoPathsForItem(int itemId) async {
    final materials = await fetchMaterialsForItem(itemId);
    return materials
        .map((material) => material.composedPhotoPath?.trim() ?? '')
        .where((path) => path.isNotEmpty)
        .toList();
  }

  Future<List<String>> fetchDisplayPhotoPathsForItem(int itemId) async {
    final materials = await fetchMaterialsForItem(itemId);
    return materials
        .map((material) {
          final composedPath = material.composedPhotoPath?.trim() ?? '';
          if (composedPath.isNotEmpty) {
            return composedPath;
          }
          return material.rawPhotoPath;
        })
        .where((path) => path.trim().isNotEmpty)
        .toList();
  }

  Future<void> markMaterialComposed({
    required int materialId,
    required String composedPhotoPath,
    int? composedAtMillis,
  }) async {
    final materials = await _ensureLoaded();
    final updated = materials.map((material) {
      if (material.id != materialId) {
        return material;
      }
      return material.copyWith(
        composedPhotoPath: composedPhotoPath,
        composedAtMillis:
            composedAtMillis ?? DateTime.now().millisecondsSinceEpoch,
      );
    }).toList();
    await _persist(updated);
  }

  Future<void> deleteMaterialsForItem(int itemId) async {
    final materials = await _ensureLoaded();
    final updated = materials
        .where((material) => material.inspectionItemId != itemId)
        .toList();
    await _persist(updated);
  }

  Future<void> deleteAllMaterials() async {
    await _persist(const <RawCaptureMaterial>[]);
  }

  Future<List<RawCaptureMaterial>> _ensureLoaded() async {
    await init();
    return List<RawCaptureMaterial>.from(
      _materials ?? const <RawCaptureMaterial>[],
    );
  }

  Future<void> _loadFromDisk() async {
    final storageFile = await _resolveStorageFile();
    _storageFile = storageFile;
    if (!await storageFile.exists()) {
      _materials = <RawCaptureMaterial>[];
      return;
    }

    final rawText = await storageFile.readAsString();
    if (rawText.trim().isEmpty) {
      _materials = <RawCaptureMaterial>[];
      return;
    }

    final decoded = jsonDecode(rawText);
    if (decoded is! Map<String, dynamic>) {
      _materials = <RawCaptureMaterial>[];
      return;
    }

    final rawItems = decoded['items'];
    if (rawItems is! List) {
      _materials = <RawCaptureMaterial>[];
      return;
    }

    final materials = <RawCaptureMaterial>[];
    for (final entry in rawItems) {
      if (entry is Map) {
        materials.add(
          RawCaptureMaterial.fromMap(
            Map<String, Object?>.from(entry.cast<Object?, Object?>()),
          ),
        );
      }
    }
    _materials = _sortMaterials(materials);
  }

  Future<void> _persist(List<RawCaptureMaterial> materials) async {
    final storageFile = _storageFile ?? await _resolveStorageFile();
    final normalized = _sortMaterials(materials);
    final payload = <String, Object?>{
      'items': normalized.map((material) => material.toMap()).toList(),
    };

    _pendingWrite = _pendingWrite
        .catchError((_) {})
        .then((_) => storageFile.writeAsString(jsonEncode(payload)))
        .then((_) {
          _storageFile = storageFile;
          _materials = normalized;
        });
    await _pendingWrite;
  }

  Future<File> _resolveStorageFile() async {
    final supportDir = await getApplicationSupportDirectory();
    if (!await supportDir.exists()) {
      await supportDir.create(recursive: true);
    }
    return File(path.join(supportDir.path, _storageFileName));
  }

  int _nextMaterialId(List<RawCaptureMaterial> materials) {
    var maxId = 0;
    for (final material in materials) {
      final id = material.id ?? 0;
      if (id > maxId) {
        maxId = id;
      }
    }
    return maxId + 1;
  }

  List<RawCaptureMaterial> _sortMaterials(List<RawCaptureMaterial> materials) {
    final sorted = List<RawCaptureMaterial>.from(materials);
    sorted.sort((a, b) {
      final timeCompare = a.captureTimeMillis.compareTo(b.captureTimeMillis);
      if (timeCompare != 0) {
        return timeCompare;
      }
      return (a.id ?? 0).compareTo(b.id ?? 0);
    });
    return sorted;
  }
}
