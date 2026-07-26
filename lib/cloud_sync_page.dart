import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:photo_namer/models/cloud_sync_models.dart';
import 'package:photo_namer/services/app_update_service.dart';
import 'package:photo_namer/services/cloud_sync_utils.dart';
import 'package:photo_namer/services/gitee_cloud_service.dart';



const String _cloudSyncAdminSessionPrefKey =
    'photo_namer_cloud_sync_admin_logged_in';
const String _cloudSyncGuestNamePrefKey = 'photo_namer_cloud_sync_guest_name';


const Map<String, String> _cloudSyncPreferenceLabels = <String, String>{
  'sortBy': '排序方式',
  'photoToMeterQuickJumpEnabled': '拍照后跳转抄表',
  'mergedLayoutEnabled': '拼图模式',
  'mergedDeepSearchEnabled': '深度搜索',
  'mergedUniformHeightEnabled': '统一高度',
  'mergedUltraCompactEnabled': '超紧凑模式',
  'cameraAttachDelayEnabled': '拍照延迟附加',
  'cameraAttachDelayMs': '拍照延迟时长',
  'defaultWatermarkEnabled': '默认开启水印',
  'incomingCabinetOnlineOcrEnabled': '进线柜默认在线OCR',
  'gridColumns': '首页列数',
  'mergedContentMaxHeight': '拼图高度',
  'typeColorThemeId': '类型配色主题',
  'typeColorOverrides': '类型颜色覆盖',
  'recentTypeColors': '最近使用颜色',
  'saveFolderName': '保存文件夹',
  'conflictStrategy': '重名处理策略',
};

const Set<String> _cloudSyncIgnoredPreferenceDiffKeys = <String>{
  'defaultWatermarkLocationFallback',
  'defaultWatermarkImprintText',
};

const Map<String, String> _cloudSyncWatermarkFieldLabels = <String, String>{
  'defaultWeatherText': '默认天气文案',
  'defaultLocationFallback': '默认水印地址',
  'defaultImprintText': '默认验证文案',
  'defaultAdjustments': '水印排版参数',
};


class CloudSyncPage extends StatefulWidget {
  final CloudBundleBuilder buildLocalBundle;
  final CloudBundleApplier applyRemoteBundle;

  const CloudSyncPage({
    super.key,
    required this.buildLocalBundle,
    required this.applyRemoteBundle,
  });

  @override
  State<CloudSyncPage> createState() => _CloudSyncPageState();
}

class _CloudSyncPageState extends State<CloudSyncPage> {
  final _service = const GiteeCloudSyncService();
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _passwordCtrl;
  late final TextEditingController _guestNameCtrl;
  late final TextEditingController _guestNoteCtrl;
  late final TextEditingController _updateVersionNameCtrl;
  late final TextEditingController _updateVersionCodeCtrl;
  late final TextEditingController _updateDownloadUrlCtrl;
  late final TextEditingController _updateTitleCtrl;
  late final TextEditingController _updateNotesCtrl;

  bool _isBusy = false;
  bool _isRefreshingDiff = false;
  bool _isRefreshingGuestSubmissions = false;
  bool _isAdminLoggedIn = false;
  bool _isRefreshingAppUpdate = false;
  bool _isPublishingAppUpdate = false;
  bool _isDownloadingAppUpdate = false;
  bool _updateForce = false;
  String? _statusMessage;
  Map<String, dynamic>? _manifest;
  String? _diffNoticeMessage;
  bool _diffNoticeIsError = false;
  String? _appUpdateNoticeMessage;
  bool _appUpdateNoticeIsError = false;
  CloudBundleSnapshot? _localSnapshot;
  CloudBundleSnapshot? _remoteSnapshot;
  LocalAppVersion? _localAppVersion;
  CloudAppUpdateManifest? _remoteAppUpdateManifest;
  List<String> _diffSummary = const <String>[];
  List<CloudGuestSubmission> _guestSubmissions =
      const <CloudGuestSubmission>[];
  CloudSyncApplySelection _lastPullSelection =
      const CloudSyncApplySelection.all();
  double? _appUpdateDownloadProgress;

  bool get _isUpdateActionActive =>
      _isRefreshingAppUpdate ||
      _isPublishingAppUpdate ||
      _isDownloadingAppUpdate;

  @override
  void initState() {
    super.initState();
    _usernameCtrl = TextEditingController(
      text: GiteeCloudSyncConfig.adminUser,
    );
    _passwordCtrl = TextEditingController();
    _guestNameCtrl = TextEditingController();
    _guestNoteCtrl = TextEditingController();
    _updateVersionNameCtrl = TextEditingController();
    _updateVersionCodeCtrl = TextEditingController();
    _updateDownloadUrlCtrl = TextEditingController();
    _updateTitleCtrl = TextEditingController(text: '发现新版本');
    _updateNotesCtrl = TextEditingController();
    _loadAdminSession();
    _loadGuestDraft();
    unawaited(_loadLocalAppVersion());
    _refreshCloudOverview();
  }

  void _maybeAutoCheckForAppUpdate() {
    if (!mounted || hasAutoCheckedAppUpdateThisSession) {
      return;
    }
    if (_localAppVersion == null || _remoteAppUpdateManifest == null) {
      return;
    }

    hasAutoCheckedAppUpdateThisSession = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_checkForAppUpdate(userInitiated: false));
    });
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _guestNameCtrl.dispose();
    _guestNoteCtrl.dispose();
    _updateVersionNameCtrl.dispose();
    _updateVersionCodeCtrl.dispose();
    _updateDownloadUrlCtrl.dispose();
    _updateTitleCtrl.dispose();
    _updateNotesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAdminSession() async {
    final prefs = await SharedPreferences.getInstance();
    final loggedIn = prefs.getBool(_cloudSyncAdminSessionPrefKey) ?? false;
    if (!mounted) {
      return;
    }
    setState(() {
      _isAdminLoggedIn = loggedIn;
    });
  }

  Future<void> _persistAdminSession(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_cloudSyncAdminSessionPrefKey, value);
  }

  Future<void> _loadGuestDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final guestName = prefs.getString(_cloudSyncGuestNamePrefKey) ?? '';
    if (!mounted) {
      return;
    }
    _guestNameCtrl.text = guestName;
  }

  Future<void> _persistGuestName(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cloudSyncGuestNamePrefKey, value);
  }

  Future<void> _loadLocalAppVersion() async {
    try {
      final localVersion = await readInstalledAppVersion();
      if (localVersion == null) {
        throw Exception('未能读取本机安装版本');
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _localAppVersion = localVersion;
        if (_updateVersionNameCtrl.text.trim().isEmpty) {
          _updateVersionNameCtrl.text = localVersion.versionName;
        }
        if (_updateVersionCodeCtrl.text.trim().isEmpty &&
            localVersion.versionCode > 0) {
          _updateVersionCodeCtrl.text = localVersion.versionCode.toString();
        }
      });
      _maybeAutoCheckForAppUpdate();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _appUpdateNoticeMessage = '读取本机版本失败: $error';
        _appUpdateNoticeIsError = true;
      });
    }
  }

  Future<Map<String, dynamic>?> _refreshManifest() async {
    try {
      final manifest = await _service.fetchManifest();
      if (!mounted) {
        return manifest;
      }
      setState(() {
        _manifest = manifest;
      });
      return manifest;
    } catch (error) {
      if (!mounted) {
        return null;
      }
      setState(() {
        _statusMessage = '读取云端配置失败: $error';
      });
      return null;
    }
  }

  Future<void> _refreshCloudOverview() async {
    final manifest = await _refreshManifest();
    await _refreshDiffSummary(manifest: manifest);
    await _refreshGuestSubmissions(manifest: manifest);
    await _refreshAppUpdateManifest();
  }

  Future<CloudAppUpdateManifest?> _refreshAppUpdateManifest({
    bool silent = true,
  }) async {
    if (!mounted) {
      return null;
    }

    setState(() {
      _isRefreshingAppUpdate = true;
      if (!silent) {
        _appUpdateNoticeMessage = null;
        _appUpdateNoticeIsError = false;
      }
    });

    try {
      final manifest = await _service.fetchAppUpdateManifest();
      if (!mounted) {
        return manifest;
      }
      setState(() {
        _remoteAppUpdateManifest = manifest;
        if (manifest != null) {
          if (_updateDownloadUrlCtrl.text.trim().isEmpty) {
            _updateDownloadUrlCtrl.text = manifest.downloadUrl;
          }
          if (_updateNotesCtrl.text.trim().isEmpty &&
              manifest.changelog.isNotEmpty) {
            _updateNotesCtrl.text = manifest.changelog.join('\n');
          }
          if (_updateVersionNameCtrl.text.trim().isEmpty) {
            _updateVersionNameCtrl.text = manifest.versionName;
          }
          if (_updateVersionCodeCtrl.text.trim().isEmpty &&
              manifest.versionCode > 0) {
            _updateVersionCodeCtrl.text = manifest.versionCode.toString();
          }
          if (_updateTitleCtrl.text.trim().isEmpty ||
              _updateTitleCtrl.text.trim() == '发现新版本') {
            _updateTitleCtrl.text = manifest.title;
          }
        }
        if (!silent) {
          _appUpdateNoticeMessage = manifest == null ? '云端还没有发布版本信息。' : null;
          _appUpdateNoticeIsError = false;
        }
      });
      _maybeAutoCheckForAppUpdate();
      return manifest;
    } catch (error) {
      if (!mounted) {
        return null;
      }
      setState(() {
        if (!silent) {
          _appUpdateNoticeMessage = '读取云端版本信息失败: $error';
          _appUpdateNoticeIsError = true;
        }
      });
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingAppUpdate = false;
        });
      }
    }
  }

  Future<void> _refreshDiffSummary({Map<String, dynamic>? manifest}) async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isRefreshingDiff = true;
      _diffNoticeMessage = null;
      _diffNoticeIsError = false;
    });

    CloudBundleSnapshot? localSnapshot;
    CloudBundleSnapshot? remoteSnapshot;
    final diffSummary = <String>[];
    String? noticeMessage;
    var noticeIsError = false;

    try {
      final localBundle = await widget.buildLocalBundle();
      localSnapshot = CloudBundleSnapshot.fromBundle(localBundle);

      try {
        final remoteBundle = await _service.downloadBundle(manifest: manifest);
        remoteSnapshot = CloudBundleSnapshot.fromBundle(remoteBundle);
        diffSummary.addAll(_buildDiffSummary(localSnapshot, remoteSnapshot));
      } catch (error) {
        if (_isMissingRemoteBundleError(error)) {
          noticeMessage = '云端还没有可对比的已发布数据，当前先显示本机概览。';
        } else {
          noticeMessage = '差异检测失败: $error';
          noticeIsError = true;
        }
      }
    } catch (error) {
      noticeMessage = '生成本机差异概览失败: $error';
      noticeIsError = true;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _localSnapshot = localSnapshot;
      _remoteSnapshot = remoteSnapshot;
      _diffSummary = List<String>.unmodifiable(diffSummary);
      _diffNoticeMessage = noticeMessage;
      _diffNoticeIsError = noticeIsError;
      _isRefreshingDiff = false;
    });
  }

  Future<void> _refreshGuestSubmissions({
    Map<String, dynamic>? manifest,
  }) async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isRefreshingGuestSubmissions = true;
    });

    try {
      final submissions = await _service.fetchGuestSubmissions();
      Map<String, dynamic> remoteReviewBundle = emptyReviewTargetBundle();
      try {
        final remoteBundle = await _service.downloadBundle(manifest: manifest);
        remoteReviewBundle = buildReviewTargetBundle(remoteBundle);
      } catch (error) {
        if (!_isMissingRemoteBundleError(error)) {
          rethrow;
        }
      }

      final resolved =
          submissions
              .map(
                (submission) => submission.copyWith(
                  reviewDiff: buildReviewDiff(
                    candidateReviewBundle: submission.reviewBundle,
                    remoteReviewBundle: remoteReviewBundle,
                  ),
                ),
              )
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (!mounted) {
        return;
      }
      setState(() {
        _guestSubmissions = List<CloudGuestSubmission>.unmodifiable(resolved);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = '读取游客更新列表失败: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingGuestSubmissions = false;
        });
      }
    }
  }

  bool _isMissingRemoteBundleError(Object error) {
    final text = error.toString();
    return text.contains('还没有可用的 photo_namer 配置数据') ||
        text.contains('云端配置文件格式不正确') ||
        text.contains('404');
  }

  String _buildSyncConfirmMessage(
    String baseMessage, {
    required bool isPublish,
  }) {
    final parts = <String>[baseMessage];
    if (_isRefreshingDiff) {
      parts.add('当前正在重新检测本机和云端差异，稍后操作会看到更准确的覆盖提示。');
    } else if (_diffNoticeIsError &&
        _diffNoticeMessage != null &&
        _diffNoticeMessage!.trim().isNotEmpty) {
      parts.add(_diffNoticeMessage!);
    } else if (_remoteSnapshot == null) {
      parts.add(
        isPublish
            ? '当前云端还没有已发布数据，本次发布会直接创建首份云端配置。'
            : '当前还没有读取到云端可用数据，继续拉取可能会失败。',
      );
      if (_diffNoticeMessage != null && _diffNoticeMessage!.trim().isNotEmpty) {
        parts.add(_diffNoticeMessage!);
      }
    } else if (_diffNoticeMessage != null &&
        _diffNoticeMessage!.trim().isNotEmpty) {
      parts.add(_diffNoticeMessage!);
    } else if (_diffSummary.isEmpty) {
      parts.add('当前检测到本机和云端关键配置没有明显差异。');
    } else {
      final highlights = _diffSummary
          .take(4)
          .map((line) => '• $line')
          .join('\n');
      parts.add('当前检测到的主要差异：\n$highlights');
    }
    return parts.join('\n\n');
  }

  String _formatApplySelection(CloudSyncApplySelection selection) {
    final labels = selection.labels;
    if (labels.isEmpty) {
      return '未选择任何同步范围';
    }
    return labels.join('、');
  }

  Future<CloudSyncApplySelection?> _showPullScopeDialog() async {
    var selection = _lastPullSelection;
    return showDialog<CloudSyncApplySelection>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Widget buildTile({
            required String title,
            required String subtitle,
            required bool value,
            required ValueChanged<bool> onChanged,
          }) {
            return CheckboxListTile(
              value: value,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(title),
              subtitle: Text(subtitle),
              onChanged: (next) => onChanged(next ?? false),
            );
          }

          return AlertDialog(
            title: const Text('选择同步到本地的范围'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('只勾选需要从云端覆盖到本机的项目，未勾选的本地数据会保持不变。'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton(
                        onPressed: () {
                          setDialogState(() {
                            selection = const CloudSyncApplySelection.all();
                          });
                        },
                        child: const Text('全选'),
                      ),
                      TextButton(
                        onPressed: () {
                          setDialogState(() {
                            selection = const CloudSyncApplySelection(
                              inspectionItems: false,
                              meterRooms: false,
                              overloadTemplates: false,
                              appPreferences: false,
                              watermarkTemplate: false,
                            );
                          });
                        },
                        child: const Text('清空'),
                      ),
                    ],
                  ),
                  buildTile(
                    title: '拍照房间模板',
                    subtitle: '同步首页拍照房间、房间名、位置等拍照模板数据',
                    value: selection.inspectionItems,
                    onChanged: (value) {
                      setDialogState(() {
                        selection = selection.copyWith(inspectionItems: value);
                      });
                    },
                  ),
                  buildTile(
                    title: '动力抄表模板',
                    subtitle: '同步抄表房间和设备命名模板',
                    value: selection.meterRooms,
                    onChanged: (value) {
                      setDialogState(() {
                        selection = selection.copyWith(meterRooms: value);
                      });
                    },
                  ),
                  buildTile(
                    title: '动力超标时段',
                    subtitle: '同步各个时间段的超标模板数据',
                    value: selection.overloadTemplates,
                    onChanged: (value) {
                      setDialogState(() {
                        selection = selection.copyWith(
                          overloadTemplates: value,
                        );
                      });
                    },
                  ),
                  buildTile(
                    title: '应用参数',
                    subtitle: '同步排序、布局、拍照跳转、进线柜OCR等设置',
                    value: selection.appPreferences,
                    onChanged: (value) {
                      setDialogState(() {
                        selection = selection.copyWith(appPreferences: value);
                      });
                    },
                  ),
                  buildTile(
                    title: '水印参数',
                    subtitle: '同步默认水印地址和验证文案等水印设置',
                    value: selection.watermarkTemplate,
                    onChanged: (value) {
                      setDialogState(() {
                        selection = selection.copyWith(
                          watermarkTemplate: value,
                        );
                      });
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: selection.hasAny
                    ? () => Navigator.of(dialogContext).pop(selection)
                    : null,
                child: const Text('按所选范围拉取'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _buildGuestSubmitConfirmMessage(
    CloudReviewDiff diff, {
    required bool hasRemoteBundle,
  }) {
    final parts = <String>[
      '这次提交不会直接覆盖正式云端配置，而是会进入游客更新列表，等待管理员审核后再决定是否并入云端。',
      hasRemoteBundle
          ? '本次将按拍照房间、动力抄表模板、动力超标时段三类数据和当前云端做差异比对。'
          : '当前云端还没有正式配置，本次会提交一份待审核草案。',
    ];
    if (diff.summaryLines.isNotEmpty) {
      parts.add(
        '检测到的主要差异：\n${diff.summaryLines.map((line) => '• $line').join('\n')}',
      );
    } else {
      parts.add('当前这三类模板和云端没有明显差异，通常不需要重复提交。');
    }
    final note = _guestNoteCtrl.text.trim();
    if (note.isNotEmpty) {
      parts.add('提交说明：$note');
    }
    return parts.join('\n\n');
  }

  String _buildGuestReviewConfirmMessage(
    CloudGuestSubmission submission, {
    required bool approve,
  }) {
    final diff = submission.pendingReviewDiff;
    final actionText = approve ? '并入正式云端配置' : '标记为已驳回';
    final parts = <String>[
      '提交人：${submission.submittedBy}',
      '提交时间：${submission.createdAt}',
      '这次操作会把该游客更新$actionText。',
    ];
    if (submission.note.trim().isNotEmpty) {
      parts.add('提交说明：${submission.note.trim()}');
    }
    if (diff.summaryLines.isNotEmpty) {
      parts.add(
        '当前和云端对比的主要差异：\n${diff.summaryLines.map((line) => '• $line').join('\n')}',
      );
    }
    if (approve) {
      parts.add('并入时只会覆盖拍照房间、动力抄表模板、动力超标时段三类数据，不会覆盖其它同步参数。');
    }
    return parts.join('\n\n');
  }

  List<String> _buildDiffSummary(
    CloudBundleSnapshot local,
    CloudBundleSnapshot remote,
  ) {
    final lines = <String>[];

    if (local.inspectionItemCount != remote.inspectionItemCount) {
      lines.add(
        '房间模板数量不同：本机 ${local.inspectionItemCount} 个，云端 ${remote.inspectionItemCount} 个',
      );
    }

    final inspectionNameDiff = formatBidirectionalDifference(
      local.inspectionNames,
      remote.inspectionNames,
    );
    if (inspectionNameDiff != null) {
      lines.add('房间模板名称差异：$inspectionNameDiff');
    } else if (local.inspectionFingerprint != remote.inspectionFingerprint) {
      lines.add('房间模板内容有修改，可能是位置、类型或编号发生了变化');
    }

    if (local.meterRoomCount != remote.meterRoomCount ||
        local.meterDeviceCount != remote.meterDeviceCount) {
      lines.add(
        '动力抄表模板规模不同：本机 ${local.meterRoomCount} 个房间 / ${local.meterDeviceCount} 台设备，云端 ${remote.meterRoomCount} 个房间 / ${remote.meterDeviceCount} 台设备',
      );
    }

    final meterRoomNameDiff = formatBidirectionalDifference(
      local.meterRoomNames,
      remote.meterRoomNames,
    );
    if (meterRoomNameDiff != null) {
      lines.add('动力抄表房间差异：$meterRoomNameDiff');
    } else if (local.meterRoomsFingerprint != remote.meterRoomsFingerprint) {
      lines.add('动力抄表模板内容有调整，可能是房间信息或设备名单发生了变化');
    }

    if (local.overloadTemplateCount != remote.overloadTemplateCount) {
      lines.add(
        '动力超标时段数量不同：本机 ${local.overloadTemplateCount} 个，云端 ${remote.overloadTemplateCount} 个',
      );
    }

    final overloadSlotDiff = formatBidirectionalDifference(
      local.overloadSlotLabels,
      remote.overloadSlotLabels,
    );
    if (overloadSlotDiff != null) {
      lines.add('动力超标时段差异：$overloadSlotDiff');
    }

    final changedOverloadSlots = <String>[];
    for (final label in local.overloadSlotLabels.intersection(
      remote.overloadSlotLabels,
    )) {
      final localSlot = local.overloadSlots[label]!;
      final remoteSlot = remote.overloadSlots[label]!;
      if (localSlot.roomCount != remoteSlot.roomCount ||
          localSlot.deviceCount != remoteSlot.deviceCount) {
        changedOverloadSlots.add(
          '$label 时段本机 ${localSlot.roomCount} 房 / ${localSlot.deviceCount} 台，云端 ${remoteSlot.roomCount} 房 / ${remoteSlot.deviceCount} 台',
        );
      } else if (localSlot.fingerprint != remoteSlot.fingerprint) {
        changedOverloadSlots.add('$label 时段数据内容不同');
      }
    }
    if (changedOverloadSlots.isNotEmpty) {
      lines.add('动力超标模板变化：${previewItems(changedOverloadSlots)}');
    }

    final changedWatermarkFields = <String>[];
    for (final entry in _cloudSyncWatermarkFieldLabels.entries) {
      if (stableJsonString(local.watermarkTemplate[entry.key]) !=
          stableJsonString(remote.watermarkTemplate[entry.key])) {
        changedWatermarkFields.add(entry.value);
      }
    }
    if (changedWatermarkFields.isNotEmpty) {
      lines.add('水印参数差异：${previewItems(changedWatermarkFields)}');
    }

    final changedPreferenceLabels = <String>[];
    final preferenceKeys = <String>{
      ...local.appPreferences.keys,
      ...remote.appPreferences.keys,
    };
    for (final key in preferenceKeys) {
      if (_cloudSyncIgnoredPreferenceDiffKeys.contains(key)) {
        continue;
      }
      if (stableJsonString(local.appPreferences[key]) !=
          stableJsonString(remote.appPreferences[key])) {
        changedPreferenceLabels.add(_cloudSyncPreferenceLabels[key] ?? key);
      }
    }
    if (changedPreferenceLabels.isNotEmpty) {
      lines.add('应用参数差异：${previewItems(changedPreferenceLabels)}');
    }

    return lines;
  }

  Future<void> _login() async {
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (username != GiteeCloudSyncConfig.adminUser ||
        password != GiteeCloudSyncConfig.adminPassword) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('管理员账号或密码不正确')));
      return;
    }

    await _persistAdminSession(true);
    if (!mounted) {
      return;
    }
    setState(() {
      _isAdminLoggedIn = true;
      _passwordCtrl.clear();
      _statusMessage = '管理员已登录，可以发布当前模板配置到云端';
    });
  }

  Future<void> _logout() async {
    await _persistAdminSession(false);
    if (!mounted) {
      return;
    }
    setState(() {
      _isAdminLoggedIn = false;
      _passwordCtrl.clear();
      _statusMessage = '管理员已退出登录';
    });
  }

  Future<void> _showAdminLoginDialog() async {
    _passwordCtrl.clear();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('管理员验证'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('登录后可以发布正式云端配置，并审核游客提交的更新。'),
            const SizedBox(height: 16),
            TextField(
              controller: _usernameCtrl,
              decoration: const InputDecoration(
                labelText: '管理员用户名',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '管理员密码',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) async {
                if (_isBusy) {
                  return;
                }
                await _login();
                if (dialogContext.mounted && _isAdminLoggedIn) {
                  Navigator.of(dialogContext).pop();
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: _isBusy
                ? null
                : () async {
                    await _login();
                    if (dialogContext.mounted && _isAdminLoggedIn) {
                      Navigator.of(dialogContext).pop();
                    }
                  },
            icon: const Icon(Icons.login),
            label: const Text('登录'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmAction({
    required String title,
    required String message,
    required String confirmText,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<bool> _showAppUpdateDialog(CloudAppUpdateManifest manifest) async {
    return showCloudAppUpdateDialog(
      context,
      manifest,
      localVersion: _localAppVersion,
    );
  }

  Future<void> _checkForAppUpdate({bool userInitiated = true}) async {
    if (_isRefreshingAppUpdate ||
        _isDownloadingAppUpdate ||
        _isPublishingAppUpdate) {
      return;
    }

    if (mounted) {
      setState(() {
        _appUpdateNoticeMessage = '正在检查云端版本信息...';
        _appUpdateNoticeIsError = false;
      });
    }

    final manifest = await _refreshAppUpdateManifest(silent: true);
    if (!mounted) {
      return;
    }

    if (manifest == null) {
      setState(() {
        _appUpdateNoticeMessage = '云端还没有发布应用更新信息。';
        _appUpdateNoticeIsError = false;
      });
      if (userInitiated) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('云端还没有发布应用更新信息')));
      }
      return;
    }

    final localVersion = _localAppVersion;
    if (localVersion == null) {
      setState(() {
        _appUpdateNoticeMessage = '当前无法读取本机版本信息，请稍后重试。';
        _appUpdateNoticeIsError = true;
      });
      return;
    }

    if (!manifest.isNewerThan(localVersion)) {
      setState(() {
        _appUpdateNoticeMessage = '当前已是最新版本：${localVersion.label}';
        _appUpdateNoticeIsError = false;
      });
      if (userInitiated) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('当前已是最新版本')));
      }
      return;
    }

    if (!manifest.hasDownloadUrl) {
      setState(() {
        _appUpdateNoticeMessage = '检测到新版本，但云端尚未配置下载地址。';
        _appUpdateNoticeIsError = true;
      });
      if (userInitiated) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('检测到新版本，但未配置下载地址')));
      }
      return;
    }

    setState(() {
      _appUpdateNoticeMessage = '检测到新版本 ${manifest.label}';
      _appUpdateNoticeIsError = false;
    });

    if (!userInitiated && !manifest.forceUpdate) {
      return;
    }

    final shouldDownload = await _showAppUpdateDialog(manifest);
    if (!shouldDownload) {
      return;
    }
    await _downloadAndInstallUpdate(manifest);
  }

  Future<void> _downloadAndInstallUpdate(
    CloudAppUpdateManifest manifest,
  ) async {
    if (_isDownloadingAppUpdate || _isPublishingAppUpdate) {
      return;
    }
    try {
      setState(() {
        _isDownloadingAppUpdate = true;
        _appUpdateDownloadProgress = null;
        _appUpdateNoticeMessage = '正在下载更新包...';
        _appUpdateNoticeIsError = false;
      });
      await performAppUpdateDownloadAndInstall(
        context,
        manifest,
        onStatus: (message, isError) {
          if (!mounted) {
            return;
          }
          setState(() {
            _appUpdateNoticeMessage = message;
            _appUpdateNoticeIsError = isError;
          });
        },
        onProgress: (progress) {
          if (!mounted) {
            return;
          }
          setState(() {
            _appUpdateDownloadProgress = progress;
          });
        },
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDownloadingAppUpdate = false;
          _appUpdateDownloadProgress = null;
        });
      }
    }
  }

  Future<void> _publishAppUpdateManifest() async {
    if (!_isAdminLoggedIn ||
        _isPublishingAppUpdate ||
        _isDownloadingAppUpdate) {
      return;
    }

    final versionName = _updateVersionNameCtrl.text.trim();
    final versionCode = int.tryParse(_updateVersionCodeCtrl.text.trim()) ?? 0;
    final downloadUrl = _updateDownloadUrlCtrl.text.trim();
    final title = _updateTitleCtrl.text.trim().isEmpty
        ? '发现新版本'
        : _updateTitleCtrl.text.trim();
    final changelog = _updateNotesCtrl.text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);

    if (versionName.isEmpty || versionCode <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请填写有效的版本号和版本码')));
      return;
    }
    if (downloadUrl.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请填写更新包下载地址')));
      return;
    }

    final confirm = await _confirmAction(
      title: '发布版本更新信息',
      message:
          '将把版本 $versionName ($versionCode) 的更新信息写入云端。\n\n'
          '下载地址：$downloadUrl\n\n'
          '更新类型：${_updateForce ? '重要更新' : '普通更新'}\n\n'
          '更新说明：${changelog.isEmpty ? '未填写' : changelog.join('；')}',
      confirmText: '发布版本',
    );
    if (!confirm) {
      return;
    }

    try {
      setState(() {
        _isPublishingAppUpdate = true;
        _appUpdateNoticeMessage = '正在发布云端版本信息...';
        _appUpdateNoticeIsError = false;
      });

      final published = await _service.publishAppUpdateManifest(
        CloudAppUpdateManifest(
          versionName: versionName,
          versionCode: versionCode,
          title: title,
          downloadUrl: downloadUrl,
          changelog: changelog,
          forceUpdate: _updateForce,
          publishedAt: '',
          publishedBy: '',
        ),
        operatorName: _usernameCtrl.text.trim(),
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _remoteAppUpdateManifest = published;
        _appUpdateNoticeMessage = '版本更新信息已发布到云端';
        _appUpdateNoticeIsError = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('云端版本信息发布成功')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _appUpdateNoticeMessage = '发布云端版本信息失败: $error';
        _appUpdateNoticeIsError = true;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('发布云端版本信息失败: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isPublishingAppUpdate = false;
        });
      }
    }
  }

  Future<void> _publishToCloud() async {
    if (!_isAdminLoggedIn || _isBusy || _isUpdateActionActive) {
      return;
    }

    final confirm = await _confirmAction(
      title: '发布当前配置',
      message: _buildSyncConfirmMessage(
        '将把当前房间模板、动力超标模板和应用配置覆盖发布到 Gitee 云端，继续吗？',
        isPublish: true,
      ),
      confirmText: '发布',
    );
    if (!confirm) {
      return;
    }

    setState(() {
      _isBusy = true;
      _statusMessage = '正在整理本地配置并发布到云端...';
    });

    try {
      final bundle = await widget.buildLocalBundle();
      await _service.publishBundle(
        bundle,
        operatorName: _usernameCtrl.text.trim(),
      );
      await _refreshCloudOverview();
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = '发布成功，云端模板已更新';
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('云端发布成功')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = '发布失败: $error';
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('发布失败: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _pullFromCloud() async {
    if (_isBusy || _isUpdateActionActive) {
      return;
    }

    final selection = await _showPullScopeDialog();
    if (selection == null || !selection.hasAny) {
      return;
    }

    final confirm = await _confirmAction(
      title: '拉取云端配置',
      message: _buildSyncConfirmMessage(
        '将把云端的 ${_formatApplySelection(selection)} 覆盖到本机，未勾选的本地内容保持不变，继续吗？',
        isPublish: false,
      ),
      confirmText: '拉取覆盖',
    );
    if (!confirm) {
      return;
    }

    setState(() {
      _isBusy = true;
      _lastPullSelection = selection;
      _statusMessage = '正在从云端拉取并应用：${_formatApplySelection(selection)}...';
    });

    try {
      final bundle = await _service.downloadBundle();
      await widget.applyRemoteBundle(bundle, selection);
      await _refreshCloudOverview();
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = '拉取成功，已同步：${_formatApplySelection(selection)}';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('云端同步完成：${_formatApplySelection(selection)}')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = '拉取失败: $error';
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('拉取失败: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _submitGuestUpdate() async {
    if (_isBusy || _isUpdateActionActive) {
      return;
    }

    final submittedBy = _guestNameCtrl.text.trim().isEmpty
        ? '游客'
        : _guestNameCtrl.text.trim();
    await _persistGuestName(submittedBy);

    setState(() {
      _isBusy = true;
      _statusMessage = '正在整理本机配置并生成游客更新草案...';
    });

    try {
      final localBundle = await widget.buildLocalBundle();
      final reviewBundle = buildReviewTargetBundle(localBundle);

      Map<String, dynamic> remoteBundle = <String, dynamic>{};
      var hasRemoteBundle = true;
      try {
        remoteBundle = await _service.downloadBundle(manifest: _manifest);
      } catch (error) {
        if (_isMissingRemoteBundleError(error)) {
          hasRemoteBundle = false;
          remoteBundle = <String, dynamic>{};
        } else {
          rethrow;
        }
      }

      final diff = buildReviewDiff(
        candidateReviewBundle: reviewBundle,
        remoteReviewBundle: buildReviewTargetBundle(remoteBundle),
      );

      if (hasRemoteBundle && diff.isEmpty) {
        if (!mounted) {
          return;
        }
        setState(() {
          _statusMessage = '当前拍照房间、动力抄表模板和动力超标时段和云端没有明显差异，无需提交审核。';
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('没有检测到需要提交审核的差异')));
        return;
      }

      if (!mounted) {
        return;
      }
      final confirm = await _confirmAction(
        title: '提交游客更新',
        message: _buildGuestSubmitConfirmMessage(
          diff,
          hasRemoteBundle: hasRemoteBundle,
        ),
        confirmText: '提交审核',
      );
      if (!confirm) {
        return;
      }

      if (mounted) {
        setState(() {
          _statusMessage = '正在上传游客更新草案到云端...';
        });
      }

      final submission = await _service.submitGuestSubmission(
        reviewBundle: reviewBundle,
        submittedBy: submittedBy,
        note: _guestNoteCtrl.text.trim(),
        diff: diff,
        baseCloudUpdatedAt: hasRemoteBundle
            ? (remoteBundle['publishedAt'] ?? _manifest?['updatedAt'] ?? '')
                  .toString()
            : '',
      );

      _guestNoteCtrl.clear();
      await _refreshGuestSubmissions(manifest: _manifest);
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = '提交成功，已进入待审核列表：${submission.id}';
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('游客更新已提交，等待管理员审核')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = '提交游客更新失败: $error';
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('提交游客更新失败: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _reviewGuestSubmission(
    CloudGuestSubmission submission, {
    required bool approve,
  }) async {
    if (_isBusy || !_isAdminLoggedIn || _isUpdateActionActive) {
      return;
    }

    final confirm = await _confirmAction(
      title: approve ? '并入游客更新' : '驳回游客更新',
      message: _buildGuestReviewConfirmMessage(submission, approve: approve),
      confirmText: approve ? '并入云端' : '确认驳回',
    );
    if (!confirm) {
      return;
    }

    setState(() {
      _isBusy = true;
      _statusMessage = approve ? '正在将游客更新并入云端...' : '正在标记游客更新为已驳回...';
    });

    try {
      final now = DateTime.now().toIso8601String();
      if (approve) {
        Map<String, dynamic> remoteBundle = emptyPublishedBundle();
        try {
          remoteBundle = await _service.downloadBundle(manifest: _manifest);
        } catch (error) {
          if (!_isMissingRemoteBundleError(error)) {
            rethrow;
          }
        }
        final mergedBundle = mergeReviewBundleIntoFullBundle(
          baseBundle: remoteBundle,
          reviewBundle: submission.reviewBundle,
        );
        await _service.publishBundle(
          mergedBundle,
          operatorName: _usernameCtrl.text.trim(),
        );
      }

      final updatedSubmission = submission.copyWith(
        status: approve
            ? guestSubmissionStatusApproved
            : guestSubmissionStatusRejected,
        reviewedAt: now,
        reviewedBy: _usernameCtrl.text.trim(),
      );
      await _service.saveGuestSubmission(updatedSubmission);
      await _refreshCloudOverview();
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = approve ? '游客更新已审核通过，并已并入正式云端配置' : '游客更新已标记为驳回';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(approve ? '游客更新已并入云端' : '游客更新已驳回')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = '${approve ? '并入' : '驳回'}游客更新失败: $error';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${approve ? '并入' : '驳回'}游客更新失败: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  String _formatManifestCategories(Map<String, dynamic>? manifest) {
    if (manifest == null) {
      return '尚未发布';
    }
    final categories = manifest['categories'];
    if (categories is! List) {
      return '未记录分类';
    }
    final labels = categories
        .whereType<Map>()
        .map((entry) => (entry['name'] ?? '').toString().trim())
        .where((text) => text.isNotEmpty)
        .toList();
    if (labels.isEmpty) {
      return '未记录分类';
    }
    return labels.join(' / ');
  }

  Widget _buildAdminAppBarAction() {
    final theme = Theme.of(context);
    if (_isAdminLoggedIn) {
      return PopupMenuButton<String>(
        enabled: !_isBusy && !_isUpdateActionActive,
        tooltip: '管理员已登录',
        onSelected: (value) {
          if (value == 'logout') {
            unawaited(_logout());
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem<String>(
            enabled: false,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.verified_user_outlined),
              title: Text('管理员已登录'),
              subtitle: Text('当前可发布和审核'),
            ),
          ),
          PopupMenuDivider(),
          PopupMenuItem<String>(
            value: 'logout',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.logout_outlined),
              title: Text('退出登录'),
            ),
          ),
        ],
        child: Container(
          margin: const EdgeInsets.only(right: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.verified_user_outlined,
                size: 18,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 6),
              Text(
                '管理员',
                style: TextStyle(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: TextButton.icon(
        onPressed: _isBusy || _isUpdateActionActive
            ? null
            : _showAdminLoginDialog,
        icon: const Icon(Icons.admin_panel_settings_outlined),
        label: const Text('管理员'),
      ),
    );
  }

  Widget _buildOverviewChip({
    required IconData icon,
    required String label,
    Color? backgroundColor,
    Color? foregroundColor,
  }) {
    final theme = Theme.of(context);
    final resolvedForeground =
        foregroundColor ?? theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor ?? theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: resolvedForeground),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: resolvedForeground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailLine(String label, String value) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label：',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }

  Widget _buildGuestSubmissionStatusChip(CloudGuestSubmission submission) {
    final theme = Theme.of(context);
    final status = submission.status;
    final backgroundColor = switch (status) {
      guestSubmissionStatusApproved => Colors.green.withValues(alpha: 0.12),
      guestSubmissionStatusRejected => theme.colorScheme.errorContainer,
      _ => Colors.orange.withValues(alpha: 0.14),
    };
    final foregroundColor = switch (status) {
      guestSubmissionStatusApproved => Colors.green.shade700,
      guestSubmissionStatusRejected => theme.colorScheme.onErrorContainer,
      _ => Colors.orange.shade800,
    };
    final label = switch (status) {
      guestSubmissionStatusApproved => '已并入',
      guestSubmissionStatusRejected => '已驳回',
      _ => '待审核',
    };
    return Chip(
      backgroundColor: backgroundColor,
      side: BorderSide(color: foregroundColor.withValues(alpha: 0.16)),
      label: Text(label, style: TextStyle(color: foregroundColor)),
    );
  }

  List<String> _composeSubmissionCategoryLines({
    required List<String> added,
    required List<String> removed,
    required List<String> changed,
  }) {
    return <String>[
      ...added.map((line) => '新增：$line'),
      ...removed.map((line) => '删除：$line'),
      ...changed.map((line) => '修改：$line'),
    ];
  }

  Widget _buildSubmissionDetailSection(String title, List<String> lines) {
    if (lines.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ...lines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Icon(
                      Icons.fiber_manual_record,
                      size: 8,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(line)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuestSubmissionCard(CloudGuestSubmission submission) {
    final diff = submission.displayDiff;
    final inspectionLines = _composeSubmissionCategoryLines(
      added: diff.inspectionAdded,
      removed: diff.inspectionRemoved,
      changed: diff.inspectionChanged,
    );
    final meterLines = _composeSubmissionCategoryLines(
      added: diff.meterRoomAdded,
      removed: diff.meterRoomRemoved,
      changed: diff.meterRoomChanged,
    );
    final overloadLines = _composeSubmissionCategoryLines(
      added: diff.overloadSlotAdded,
      removed: diff.overloadSlotRemoved,
      changed: diff.overloadSlotChanged,
    );
    final previewSummary = diff.summaryLines.take(2).join('；');

    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Text(
          submission.submittedBy,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          [
            submission.createdAt,
            if (previewSummary.isNotEmpty) previewSummary,
          ].join('\n'),
        ),
        trailing: _buildGuestSubmissionStatusChip(submission),
        children: [
          if (submission.note.trim().isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text('提交说明：${submission.note.trim()}'),
            ),
          if (submission.baseCloudUpdatedAt.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('提交时云端版本：${submission.baseCloudUpdatedAt.trim()}'),
            ),
          ],
          if ((submission.reviewedBy ?? '').trim().isNotEmpty ||
              (submission.reviewedAt ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '审核信息：${(submission.reviewedBy ?? '').trim().isEmpty ? '未记录审核人' : submission.reviewedBy!.trim()}'
                '${(submission.reviewedAt ?? '').trim().isEmpty ? '' : ' · ${submission.reviewedAt!.trim()}'}',
              ),
            ),
          ],
          _buildSubmissionDetailSection('差异摘要', diff.summaryLines),
          _buildSubmissionDetailSection('拍照房间', inspectionLines),
          _buildSubmissionDetailSection('动力抄表模板', meterLines),
          _buildSubmissionDetailSection('动力超标时段', overloadLines),
          if (diff.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '当前没有检测到需要展示的差异明细。',
                  style: TextStyle(color: Colors.black54),
                ),
              ),
            ),
          if (_isAdminLoggedIn &&
              submission.status == guestSubmissionStatusPending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isBusy
                        ? null
                        : () =>
                              _reviewGuestSubmission(submission, approve: true),
                    icon: const Icon(Icons.done_all_outlined),
                    label: const Text('审核并入云端'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isBusy
                        ? null
                        : () => _reviewGuestSubmission(
                            submission,
                            approve: false,
                          ),
                    icon: const Icon(Icons.close_outlined),
                    label: const Text('驳回本次提交'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final manifest = _manifest;
    final updatedAt = (manifest?['updatedAt'] ?? '').toString();
    final updatedBy = (manifest?['updatedBy'] ?? '').toString();
    final dataFilePath = (manifest?['dataFilePath'] ?? '').toString();
    final localSnapshot = _localSnapshot;
    final remoteSnapshot = _remoteSnapshot;
    final localAppVersion = _localAppVersion;
    final remoteAppUpdateManifest = _remoteAppUpdateManifest;
    final pendingGuestCount = _guestSubmissions
        .where(
          (submission) => submission.status == guestSubmissionStatusPending,
        )
        .length;
    final approvedGuestCount = _guestSubmissions
        .where(
          (submission) => submission.status == guestSubmissionStatusApproved,
        )
        .length;
    final rejectedGuestCount = _guestSubmissions
        .where(
          (submission) => submission.status == guestSubmissionStatusRejected,
        )
        .length;
    final statusMessage = _statusMessage?.trim() ?? '';
    final hasStatusMessage = statusMessage.isNotEmpty;
    final statusIsError = statusMessage.contains('失败');
    final appUpdateNoticeMessage = _appUpdateNoticeMessage?.trim() ?? '';
    final hasAppUpdateNotice = appUpdateNoticeMessage.isNotEmpty;
    final hasRemoteNewVersion =
        remoteAppUpdateManifest?.isNewerThan(localAppVersion) ?? false;
    final isAnyPageBusy =
        _isBusy ||
        _isRefreshingDiff ||
        _isRefreshingGuestSubmissions ||
        _isRefreshingAppUpdate ||
        _isPublishingAppUpdate ||
        _isDownloadingAppUpdate;
    const syncScopeSummary = '房间模板、动力抄表模板、动力超标时段、水印参数与拍照设置';

    return Scaffold(
      appBar: AppBar(
        title: const Text('云端同步'),
        actions: [_buildAdminAppBarAction()],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshCloudOverview,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '同步中心',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                manifest == null
                                    ? '云端还没有正式配置，可以先整理本机模板后再发布。'
                                    : '先看差异，再决定拉取覆盖、本机发布，或提交游客更新。',
                                style: const TextStyle(color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                        if (isAnyPageBusy)
                          const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildOverviewChip(
                          icon: manifest == null
                              ? Icons.cloud_off_outlined
                              : Icons.cloud_done_outlined,
                          label: manifest == null ? '云端未发布' : '云端已发布',
                          backgroundColor: manifest == null
                              ? theme.colorScheme.surfaceContainerHighest
                              : Colors.green.withValues(alpha: 0.12),
                          foregroundColor: manifest == null
                              ? theme.colorScheme.onSurfaceVariant
                              : Colors.green.shade700,
                        ),
                        _buildOverviewChip(
                          icon: _isAdminLoggedIn
                              ? Icons.verified_user_outlined
                              : Icons.person_outline,
                          label: _isAdminLoggedIn ? '管理员模式' : '游客模式',
                          backgroundColor: _isAdminLoggedIn
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.surfaceContainerHighest,
                          foregroundColor: _isAdminLoggedIn
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        _buildOverviewChip(
                          icon: Icons.pending_actions_outlined,
                          label: '待审核 $pendingGuestCount',
                        ),
                        _buildOverviewChip(
                          icon: Icons.compare_arrows_outlined,
                          label: remoteSnapshot == null
                              ? '待读取云端'
                              : _diffSummary.isEmpty
                              ? '暂无明显差异'
                              : '差异 ${_diffSummary.length} 项',
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _buildDetailLine(
                      '最近发布',
                      updatedAt.isEmpty ? '暂无' : updatedAt,
                    ),
                    const SizedBox(height: 4),
                    _buildDetailLine(
                      '发布人',
                      updatedBy.isEmpty ? '暂无' : updatedBy,
                    ),
                    const SizedBox(height: 4),
                    _buildDetailLine(
                      '同步分类',
                      _formatManifestCategories(manifest),
                    ),
                    const SizedBox(height: 4),
                    _buildDetailLine('同步范围', syncScopeSummary),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: isAnyPageBusy ? null : _pullFromCloud,
                        icon: isAnyPageBusy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.download_outlined),
                        label: Text(isAnyPageBusy ? '处理中...' : '选择范围后拉取覆盖'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: isAnyPageBusy || !_isAdminLoggedIn
                                ? null
                                : _publishToCloud,
                            icon: Icon(
                              _isAdminLoggedIn
                                  ? Icons.cloud_upload_outlined
                                  : Icons.lock_outline,
                            ),
                            label: Text(
                              _isAdminLoggedIn ? '发布当前配置' : '管理员登录后可发布',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: isAnyPageBusy
                                ? null
                                : _refreshCloudOverview,
                            icon: const Icon(Icons.refresh),
                            label: Text(
                              _isRefreshingDiff || _isRefreshingGuestSubmissions
                                  ? '刷新中...'
                                  : '刷新概览',
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (!_isAdminLoggedIn) ...[
                      const SizedBox(height: 10),
                      const Text(
                        '管理员登录入口已移到右上角。登录后可直接发布云端配置并审核游客更新。',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (hasStatusMessage) ...[
              const SizedBox(height: 12),
              Card(
                color: statusIsError
                    ? theme.colorScheme.errorContainer
                    : theme.colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    statusMessage,
                    style: TextStyle(
                      color: statusIsError
                          ? theme.colorScheme.onErrorContainer
                          : null,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '应用更新',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                '普通用户可检查更新并下载安装包，管理员可发布最新版本信息。',
                                style: TextStyle(color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                        if (hasRemoteNewVersion)
                          Chip(
                            avatar: const Icon(
                              Icons.system_update_alt,
                              size: 18,
                            ),
                            label: Text(
                              remoteAppUpdateManifest == null
                                  ? '有新版本'
                                  : '新版本 ${remoteAppUpdateManifest.versionName}',
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildDetailLine(
                      '当前版本',
                      localAppVersion?.label ?? '读取中...',
                    ),
                    const SizedBox(height: 4),
                    _buildDetailLine(
                      '云端版本',
                      remoteAppUpdateManifest == null
                          ? '尚未发布'
                          : remoteAppUpdateManifest.versionCode > 0
                          ? '${remoteAppUpdateManifest.versionName} (${remoteAppUpdateManifest.versionCode})'
                          : remoteAppUpdateManifest.versionName,
                    ),
                    if (remoteAppUpdateManifest != null &&
                        remoteAppUpdateManifest.publishedAt
                            .trim()
                            .isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _buildDetailLine(
                        '发布时间',
                        remoteAppUpdateManifest.publishedAt,
                      ),
                    ],
                    if (remoteAppUpdateManifest != null &&
                        remoteAppUpdateManifest.publishedBy
                            .trim()
                            .isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _buildDetailLine(
                        '发布人',
                        remoteAppUpdateManifest.publishedBy,
                      ),
                    ],
                    if (remoteAppUpdateManifest != null &&
                        remoteAppUpdateManifest.forceUpdate) ...[
                      const SizedBox(height: 10),
                      const Chip(
                        avatar: Icon(Icons.priority_high_outlined, size: 18),
                        label: Text('云端标记为重要更新'),
                      ),
                    ],
                    if (remoteAppUpdateManifest != null &&
                        remoteAppUpdateManifest.changelog.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        '最近更新内容',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      ...remoteAppUpdateManifest.changelog.map(
                        (line) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Icon(
                                  Icons.fiber_manual_record,
                                  size: 8,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: Text(line)),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (hasAppUpdateNotice) ...[
                      const SizedBox(height: 12),
                      Text(
                        appUpdateNoticeMessage,
                        style: TextStyle(
                          color: _appUpdateNoticeIsError
                              ? theme.colorScheme.error
                              : Colors.black54,
                        ),
                      ),
                    ],
                    if (_isDownloadingAppUpdate) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: _appUpdateDownloadProgress,
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed:
                                _isRefreshingAppUpdate ||
                                    _isDownloadingAppUpdate ||
                                    _isPublishingAppUpdate
                                ? null
                                : () => _checkForAppUpdate(),
                            icon: const Icon(Icons.system_update_outlined),
                            label: Text(
                              _isRefreshingAppUpdate ? '检查中...' : '检查应用更新',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed:
                                remoteAppUpdateManifest == null ||
                                    !hasRemoteNewVersion ||
                                    !remoteAppUpdateManifest.hasDownloadUrl ||
                                    _isDownloadingAppUpdate ||
                                    _isPublishingAppUpdate
                                ? null
                                : () => _downloadAndInstallUpdate(
                                    remoteAppUpdateManifest,
                                  ),
                            icon: const Icon(
                              Icons.download_for_offline_outlined,
                            ),
                            label: Text(
                              _isDownloadingAppUpdate ? '下载中...' : '下载并安装',
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_isAdminLoggedIn) ...[
                      const SizedBox(height: 16),
                      Divider(color: theme.colorScheme.outlineVariant),
                      const SizedBox(height: 12),
                      const Text(
                        '管理员发布版本信息',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '这里发布的是版本说明和下载地址。安装包文件请先上传到 Gitee Release 或其它可直链下载的位置。',
                        style: TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _updateVersionNameCtrl,
                              decoration: const InputDecoration(
                                labelText: '版本号',
                                hintText: '例如：1.2.3',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _updateVersionCodeCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '版本码',
                                hintText: '例如：23',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _updateTitleCtrl,
                        decoration: const InputDecoration(
                          labelText: '弹窗标题',
                          hintText: '例如：发现新版本',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _updateDownloadUrlCtrl,
                        decoration: const InputDecoration(
                          labelText: '更新包下载地址',
                          hintText: '请填写可直接下载 APK 的完整 URL',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        value: _updateForce,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('标记为重要更新'),
                        subtitle: const Text('会在更新弹窗中高亮提醒用户尽快更新'),
                        onChanged:
                            _isPublishingAppUpdate || _isDownloadingAppUpdate
                            ? null
                            : (value) {
                                setState(() {
                                  _updateForce = value;
                                });
                              },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _updateNotesCtrl,
                        minLines: 3,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          labelText: '更新说明',
                          hintText: '每行一条，例如：\\n新增云端更新检测\\n优化同步页面体验',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed:
                              _isPublishingAppUpdate || _isDownloadingAppUpdate
                              ? null
                              : _publishAppUpdateManifest,
                          icon: const Icon(Icons.publish_outlined),
                          label: Text(
                            _isPublishingAppUpdate ? '发布中...' : '发布云端版本信息',
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 2,
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                title: const Text(
                  '仓库与同步配置',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${GiteeCloudSyncConfig.repoOwner}/${GiteeCloudSyncConfig.repoName}',
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('同步方式：Gitee Contents API'),
                        const SizedBox(height: 6),
                        Text('分支：${GiteeCloudSyncConfig.branch}'),
                        const SizedBox(height: 4),
                        Text('配置文件：${GiteeCloudSyncConfig.configFilePath}'),
                        const SizedBox(height: 4),
                        Text(
                          '数据文件：${dataFilePath.isEmpty ? GiteeCloudSyncConfig.dataFilePath : dataFilePath}',
                        ),
                        const SizedBox(height: 4),
                        Text('版本文件：${GiteeCloudSyncConfig.appUpdateFilePath}'),
                        const SizedBox(height: 4),
                        Text(
                          '游客提交目录：${GiteeCloudSyncConfig.guestSubmissionDirectoryPath}',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '游客更新提交',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '没有管理员密码也可以把当前模板提交到待审核区。管理员确认后，才会并入正式云端配置。',
                      style: TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: const [
                        Chip(label: Text('拍照房间')),
                        Chip(label: Text('动力抄表模板')),
                        Chip(label: Text('动力超标时段')),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _guestNameCtrl,
                      decoration: const InputDecoration(
                        labelText: '提交人名称',
                        hintText: '例如：现场值班机 / 张三',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        unawaited(_persistGuestName(value.trim()));
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _guestNoteCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: '提交说明',
                        hintText: '例如：新增 3 个拍照房间，删除 1 个超标设备模板',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isBusy ? null : _submitGuestUpdate,
                        icon: const Icon(Icons.rate_review_outlined),
                        label: Text(_isBusy ? '处理中...' : '提交当前模板供管理员审核'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '覆盖差异概览',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '覆盖前会按关键字段做一次大致比对，帮助判断本机和云端哪里不一样。',
                      style: TextStyle(color: Colors.black54),
                    ),
                    if (_isRefreshingDiff) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      localSnapshot == null
                          ? '本机：正在整理本地配置概览...'
                          : '本机：${localSnapshot.summaryText}',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      remoteSnapshot == null
                          ? '云端：暂无可对比的已发布数据'
                          : '云端：${remoteSnapshot.summaryText}',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '本机默认水印地址：${formatWatermarkFieldValue(localSnapshot?.watermarkTemplate, 'defaultLocationFallback')}',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '云端默认水印地址：${formatWatermarkFieldValue(remoteSnapshot?.watermarkTemplate, 'defaultLocationFallback')}',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '本机默认验证文案：${formatWatermarkFieldValue(localSnapshot?.watermarkTemplate, 'defaultImprintText')}',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '云端默认验证文案：${formatWatermarkFieldValue(remoteSnapshot?.watermarkTemplate, 'defaultImprintText')}',
                    ),
                    if (_diffNoticeMessage != null &&
                        _diffNoticeMessage!.trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        _diffNoticeMessage!,
                        style: TextStyle(
                          color: _diffNoticeIsError
                              ? Theme.of(context).colorScheme.error
                              : Colors.black54,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (remoteSnapshot != null && _diffSummary.isEmpty)
                      const Text(
                        '当前没有检测到明显差异，可以直接进行覆盖同步。',
                        style: TextStyle(color: Colors.black54),
                      ),
                    if (_diffSummary.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _diffSummary
                            .map(
                              (line) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Icon(
                                        Icons.fiber_manual_record,
                                        size: 8,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(line)),
                                  ],
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '游客更新审核区',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isAdminLoggedIn
                          ? '当前已登录管理员账号，可以直接审核游客提交并决定是否并入正式云端配置。'
                          : '任何人都可以查看游客提交记录；登录管理员后可执行并入或驳回。',
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(label: Text('待审核 $pendingGuestCount')),
                        Chip(label: Text('已并入 $approvedGuestCount')),
                        Chip(label: Text('已驳回 $rejectedGuestCount')),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isBusy || _isRefreshingGuestSubmissions
                            ? null
                            : () =>
                                  _refreshGuestSubmissions(manifest: manifest),
                        icon: const Icon(
                          Icons.playlist_add_check_circle_outlined,
                        ),
                        label: Text(
                          _isRefreshingGuestSubmissions
                              ? '正在刷新提交列表...'
                              : '刷新游客提交列表',
                        ),
                      ),
                    ),
                    if (_isRefreshingGuestSubmissions) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
                    if (_guestSubmissions.isEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        '当前还没有游客提交记录。',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ],
                    if (_guestSubmissions.isNotEmpty)
                      ..._guestSubmissions.map(_buildGuestSubmissionCard),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}



