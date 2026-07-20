import 'dart:async';

import 'package:path/path.dart' as path;

import 'package:photo_namer/services/cloud_sync_utils.dart';

typedef CloudBundleBuilder = Future<Map<String, dynamic>> Function();
typedef CloudBundleApplier =
    Future<void> Function(
      Map<String, dynamic> bundle,
      CloudSyncApplySelection selection,
    );

class CloudSyncApplySelection {
  final bool inspectionItems;
  final bool meterRooms;
  final bool overloadTemplates;
  final bool appPreferences;
  final bool watermarkTemplate;

  const CloudSyncApplySelection({
    required this.inspectionItems,
    required this.meterRooms,
    required this.overloadTemplates,
    required this.appPreferences,
    required this.watermarkTemplate,
  });

  const CloudSyncApplySelection.all()
    : inspectionItems = true,
      meterRooms = true,
      overloadTemplates = true,
      appPreferences = true,
      watermarkTemplate = true;

  bool get hasAny =>
      inspectionItems ||
      meterRooms ||
      overloadTemplates ||
      appPreferences ||
      watermarkTemplate;

  List<String> get labels => [
    if (inspectionItems) '拍照房间模板',
    if (meterRooms) '动力抄表模板',
    if (overloadTemplates) '动力超标时段',
    if (appPreferences) '应用参数',
    if (watermarkTemplate) '水印参数',
  ];

  CloudSyncApplySelection copyWith({
    bool? inspectionItems,
    bool? meterRooms,
    bool? overloadTemplates,
    bool? appPreferences,
    bool? watermarkTemplate,
  }) {
    return CloudSyncApplySelection(
      inspectionItems: inspectionItems ?? this.inspectionItems,
      meterRooms: meterRooms ?? this.meterRooms,
      overloadTemplates: overloadTemplates ?? this.overloadTemplates,
      appPreferences: appPreferences ?? this.appPreferences,
      watermarkTemplate: watermarkTemplate ?? this.watermarkTemplate,
    );
  }
}

const String guestSubmissionStatusPending = 'pending';
const String guestSubmissionStatusApproved = 'approved';
const String guestSubmissionStatusRejected = 'rejected';

class CloudBundleSnapshot {
  final int inspectionItemCount;
  final Set<String> inspectionNames;
  final String inspectionFingerprint;
  final int meterRoomCount;
  final int meterDeviceCount;
  final Set<String> meterRoomNames;
  final String meterRoomsFingerprint;
  final int overloadTemplateCount;
  final int overloadRoomCount;
  final int overloadDeviceCount;
  final Map<String, CloudOverloadSlotSnapshot> overloadSlots;
  final Map<String, dynamic> appPreferences;
  final Map<String, dynamic> watermarkTemplate;

  const CloudBundleSnapshot({
    required this.inspectionItemCount,
    required this.inspectionNames,
    required this.inspectionFingerprint,
    required this.meterRoomCount,
    required this.meterDeviceCount,
    required this.meterRoomNames,
    required this.meterRoomsFingerprint,
    required this.overloadTemplateCount,
    required this.overloadRoomCount,
    required this.overloadDeviceCount,
    required this.overloadSlots,
    required this.appPreferences,
    required this.watermarkTemplate,
  });

  Set<String> get overloadSlotLabels => overloadSlots.keys.toSet();

  String get summaryText =>
      '房间模板 $inspectionItemCount 个，抄表 $meterRoomCount 个房间 / $meterDeviceCount 台设备，超标 $overloadTemplateCount 个时段 / $overloadRoomCount 个房间 / $overloadDeviceCount 台设备，参数 ${appPreferences.length} 项';

  factory CloudBundleSnapshot.fromBundle(Map<String, dynamic> bundle) {
    final inspectionItems = asMapList(bundle['inspectionItems']);
    final inspectionComparable = inspectionItems
        .map(
          (item) => <String, dynamic>{
            'id': item['id'],
            'name': normalizedText(item['name']),
            'type': normalizedText(item['type']),
            'location': normalizedText(item['location']),
            'serial': normalizedText(item['serial']),
          },
        )
        .toList(growable: false);
    final inspectionNames = inspectionComparable
        .map((item) => normalizedText(item['name']))
        .where((name) => name.isNotEmpty)
        .toSet();

    final meterRooms = asMapList(bundle['meterRooms']);
    var meterDeviceCount = 0;
    final meterComparable = <Map<String, dynamic>>[];
    final meterRoomNames = <String>{};
    for (var index = 0; index < meterRooms.length; index++) {
      final room = meterRooms[index];
      final roomName = displayRoomName(room, index + 1);
      final devices = asMapList(room['devices']);
      meterDeviceCount += devices.length;
      meterRoomNames.add(roomName);
      meterComparable.add(<String, dynamic>{
        'roomId': room['roomId'],
        'roomName': roomName,
        'roomType': normalizedText(room['roomType']),
        'location': normalizedText(room['location']),
        'devices': devices
            .map(
              (device) => <String, dynamic>{
                'name': normalizedText(device['name']),
              },
            )
            .toList(growable: false),
      });
    }

    final overloadTemplates = asMapList(bundle['overloadTemplates']);
    var overloadRoomCount = 0;
    var overloadDeviceCount = 0;
    final overloadSlots = <String, CloudOverloadSlotSnapshot>{};
    for (var index = 0; index < overloadTemplates.length; index++) {
      final entry = overloadTemplates[index];
      final label = normalizedText(entry['label']).isEmpty
          ? '未命名时段${index + 1}'
          : normalizedText(entry['label']);
      final rawData = asStringMap(entry['rawData']);
      final comparableRawData = Map<String, dynamic>.from(rawData)
        ..remove('exportedAt');
      final rooms = asMapList(rawData['rooms']);
      final roomCount = rooms.length;
      final deviceCount = rooms.fold<int>(
        0,
        (sum, room) => sum + asMapList(room['devices']).length,
      );
      overloadRoomCount += roomCount;
      overloadDeviceCount += deviceCount;
      overloadSlots[label] = CloudOverloadSlotSnapshot(
        label: label,
        roomCount: roomCount,
        deviceCount: deviceCount,
        fingerprint: stableJsonString(comparableRawData),
      );
    }

    return CloudBundleSnapshot(
      inspectionItemCount: inspectionItems.length,
      inspectionNames: inspectionNames,
      inspectionFingerprint: stableJsonString(inspectionComparable),
      meterRoomCount: meterRooms.length,
      meterDeviceCount: meterDeviceCount,
      meterRoomNames: meterRoomNames,
      meterRoomsFingerprint: stableJsonString(meterComparable),
      overloadTemplateCount: overloadTemplates.length,
      overloadRoomCount: overloadRoomCount,
      overloadDeviceCount: overloadDeviceCount,
      overloadSlots: overloadSlots,
      appPreferences: asStringMap(bundle['appPreferences']),
      watermarkTemplate: asStringMap(bundle['watermarkTemplate']),
    );
  }
}

class CloudOverloadSlotSnapshot {
  final String label;
  final int roomCount;
  final int deviceCount;
  final String fingerprint;

  const CloudOverloadSlotSnapshot({
    required this.label,
    required this.roomCount,
    required this.deviceCount,
    required this.fingerprint,
  });
}

class CloudReviewDiff {
  final List<String> summaryLines;
  final List<String> inspectionAdded;
  final List<String> inspectionRemoved;
  final List<String> inspectionChanged;
  final int inspectionChangedCount;
  final List<String> meterRoomAdded;
  final List<String> meterRoomRemoved;
  final List<String> meterRoomChanged;
  final int meterRoomChangedCount;
  final List<String> overloadSlotAdded;
  final List<String> overloadSlotRemoved;
  final List<String> overloadSlotChanged;
  final int overloadSlotChangedCount;

  const CloudReviewDiff({
    required this.summaryLines,
    required this.inspectionAdded,
    required this.inspectionRemoved,
    required this.inspectionChanged,
    required this.inspectionChangedCount,
    required this.meterRoomAdded,
    required this.meterRoomRemoved,
    required this.meterRoomChanged,
    required this.meterRoomChangedCount,
    required this.overloadSlotAdded,
    required this.overloadSlotRemoved,
    required this.overloadSlotChanged,
    required this.overloadSlotChangedCount,
  });

  const CloudReviewDiff.empty()
    : summaryLines = const <String>[],
      inspectionAdded = const <String>[],
      inspectionRemoved = const <String>[],
      inspectionChanged = const <String>[],
      inspectionChangedCount = 0,
      meterRoomAdded = const <String>[],
      meterRoomRemoved = const <String>[],
      meterRoomChanged = const <String>[],
      meterRoomChangedCount = 0,
      overloadSlotAdded = const <String>[],
      overloadSlotRemoved = const <String>[],
      overloadSlotChanged = const <String>[],
      overloadSlotChangedCount = 0;

  bool get isEmpty =>
      summaryLines.isEmpty &&
      inspectionAdded.isEmpty &&
      inspectionRemoved.isEmpty &&
      inspectionChanged.isEmpty &&
      meterRoomAdded.isEmpty &&
      meterRoomRemoved.isEmpty &&
      meterRoomChanged.isEmpty &&
      overloadSlotAdded.isEmpty &&
      overloadSlotRemoved.isEmpty &&
      overloadSlotChanged.isEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'summaryLines': summaryLines,
    'inspectionAdded': inspectionAdded,
    'inspectionRemoved': inspectionRemoved,
    'inspectionChanged': inspectionChanged,
    'inspectionChangedCount': inspectionChangedCount,
    'meterRoomAdded': meterRoomAdded,
    'meterRoomRemoved': meterRoomRemoved,
    'meterRoomChanged': meterRoomChanged,
    'meterRoomChangedCount': meterRoomChangedCount,
    'overloadSlotAdded': overloadSlotAdded,
    'overloadSlotRemoved': overloadSlotRemoved,
    'overloadSlotChanged': overloadSlotChanged,
    'overloadSlotChangedCount': overloadSlotChangedCount,
  };

  factory CloudReviewDiff.fromJson(Map<String, dynamic> json) {
    return CloudReviewDiff(
      summaryLines: asStringList(json['summaryLines']),
      inspectionAdded: asStringList(json['inspectionAdded']),
      inspectionRemoved: asStringList(json['inspectionRemoved']),
      inspectionChanged: asStringList(json['inspectionChanged']),
      inspectionChangedCount:
          (json['inspectionChangedCount'] as num?)?.toInt() ??
          asStringList(json['inspectionChanged']).length,
      meterRoomAdded: asStringList(json['meterRoomAdded']),
      meterRoomRemoved: asStringList(json['meterRoomRemoved']),
      meterRoomChanged: asStringList(json['meterRoomChanged']),
      meterRoomChangedCount:
          (json['meterRoomChangedCount'] as num?)?.toInt() ??
          asStringList(json['meterRoomChanged']).length,
      overloadSlotAdded: asStringList(json['overloadSlotAdded']),
      overloadSlotRemoved: asStringList(json['overloadSlotRemoved']),
      overloadSlotChanged: asStringList(json['overloadSlotChanged']),
      overloadSlotChangedCount:
          (json['overloadSlotChangedCount'] as num?)?.toInt() ??
          asStringList(json['overloadSlotChanged']).length,
    );
  }
}

class CloudGuestSubmission {
  final String id;
  final String filePath;
  final String createdAt;
  final String submittedBy;
  final String note;
  final String status;
  final String baseCloudUpdatedAt;
  final String? reviewedAt;
  final String? reviewedBy;
  final Map<String, dynamic> reviewBundle;
  final CloudReviewDiff submittedDiff;
  final CloudReviewDiff? reviewDiff;

  const CloudGuestSubmission({
    required this.id,
    required this.filePath,
    required this.createdAt,
    required this.submittedBy,
    required this.note,
    required this.status,
    required this.baseCloudUpdatedAt,
    required this.reviewedAt,
    required this.reviewedBy,
    required this.reviewBundle,
    required this.submittedDiff,
    required this.reviewDiff,
  });

  CloudReviewDiff get pendingReviewDiff => reviewDiff ?? submittedDiff;

  CloudReviewDiff get displayDiff => status == guestSubmissionStatusPending
      ? pendingReviewDiff
      : submittedDiff;

  CloudGuestSubmission copyWith({
    String? status,
    String? reviewedAt,
    String? reviewedBy,
    CloudReviewDiff? reviewDiff,
  }) {
    return CloudGuestSubmission(
      id: id,
      filePath: filePath,
      createdAt: createdAt,
      submittedBy: submittedBy,
      note: note,
      status: status ?? this.status,
      baseCloudUpdatedAt: baseCloudUpdatedAt,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      reviewBundle: reviewBundle,
      submittedDiff: submittedDiff,
      reviewDiff: reviewDiff ?? this.reviewDiff,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': 1,
    'id': id,
    'createdAt': createdAt,
    'submittedBy': submittedBy,
    'note': note,
    'status': status,
    'baseCloudUpdatedAt': baseCloudUpdatedAt,
    'reviewedAt': reviewedAt,
    'reviewedBy': reviewedBy,
    'reviewBundle': reviewBundle,
    'diff': submittedDiff.toJson(),
  };

  factory CloudGuestSubmission.fromJson(
    Map<String, dynamic> json, {
    required String filePath,
  }) {
    return CloudGuestSubmission(
      id: normalizedText(json['id']).isEmpty
          ? path.posix.basenameWithoutExtension(filePath)
          : normalizedText(json['id']),
      filePath: filePath,
      createdAt: normalizedText(json['createdAt']),
      submittedBy: normalizedText(json['submittedBy']).isEmpty
          ? '游客'
          : normalizedText(json['submittedBy']),
      note: normalizedText(json['note']),
      status: normalizedText(json['status']).isEmpty
          ? guestSubmissionStatusPending
          : normalizedText(json['status']),
      baseCloudUpdatedAt: normalizedText(json['baseCloudUpdatedAt']),
      reviewedAt: normalizedText(json['reviewedAt']).isEmpty
          ? null
          : normalizedText(json['reviewedAt']),
      reviewedBy: normalizedText(json['reviewedBy']).isEmpty
          ? null
          : normalizedText(json['reviewedBy']),
      reviewBundle: asStringMap(json['reviewBundle']),
      submittedDiff: CloudReviewDiff.fromJson(asStringMap(json['diff'])),
      reviewDiff: null,
    );
  }
}
