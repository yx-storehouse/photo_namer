import 'package:flutter/material.dart';

import 'capture_location_service.dart';

class BatchComposeOptions {
  final bool useStoredLocation;
  final String customLocation;
  final bool useStoredWeatherText;
  final String customWeatherText;
  final bool useStoredRoomCode;
  final String customRoomCode;
  final bool useStoredImprintText;
  final String customImprintText;
  final bool useCaptureTime;
  final DateTime customCaptureTime;

  const BatchComposeOptions({
    required this.useStoredLocation,
    required this.customLocation,
    required this.useStoredWeatherText,
    required this.customWeatherText,
    required this.useStoredRoomCode,
    required this.customRoomCode,
    required this.useStoredImprintText,
    required this.customImprintText,
    required this.useCaptureTime,
    required this.customCaptureTime,
  });
}

class RawCaptureBatchPage extends StatefulWidget {
  final int pendingCount;
  final String initialLocation;
  final String initialWeatherText;
  final String initialRoomCode;
  final String initialImprintText;

  const RawCaptureBatchPage({
    super.key,
    required this.pendingCount,
    required this.initialLocation,
    required this.initialWeatherText,
    required this.initialRoomCode,
    required this.initialImprintText,
  });

  @override
  State<RawCaptureBatchPage> createState() => _RawCaptureBatchPageState();
}

class _RawCaptureBatchPageState extends State<RawCaptureBatchPage> {
  late final TextEditingController _locationCtrl;
  late final TextEditingController _weatherCtrl;
  late final TextEditingController _roomCodeCtrl;
  late final TextEditingController _imprintCtrl;

  bool _useStoredLocation = true;
  bool _useStoredWeatherText = true;
  bool _useStoredRoomCode = true;
  bool _useStoredImprintText = true;
  bool _useCaptureTime = true;
  bool _isResolvingLocation = false;
  late DateTime _customCaptureTime;

  @override
  void initState() {
    super.initState();
    _locationCtrl = TextEditingController(text: widget.initialLocation);
    _weatherCtrl = TextEditingController(text: widget.initialWeatherText);
    _roomCodeCtrl = TextEditingController(text: widget.initialRoomCode);
    _imprintCtrl = TextEditingController(text: widget.initialImprintText);
    _customCaptureTime = DateTime.now();
  }

  @override
  void dispose() {
    _locationCtrl.dispose();
    _weatherCtrl.dispose();
    _roomCodeCtrl.dispose();
    _imprintCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickCustomDate() async {
    final initial = _customCaptureTime;
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (pickedDate == null || !mounted) {
      return;
    }

    setState(() {
      _customCaptureTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        _customCaptureTime.hour,
        _customCaptureTime.minute,
      );
    });
  }

  Future<void> _pickCustomTime() async {
    final initial = _customCaptureTime;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (pickedTime == null || !mounted) {
      return;
    }

    setState(() {
      _customCaptureTime = DateTime(
        initial.year,
        initial.month,
        initial.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  Future<void> _fillLocationFromPhone() async {
    if (_isResolvingLocation) {
      return;
    }

    setState(() {
      _isResolvingLocation = true;
    });
    try {
      final resolvedAddress = await CaptureLocationService.resolveAddress(
        fallbackAddress: _locationCtrl.text.trim(),
      );
      if (!mounted) {
        return;
      }
      final normalized = resolvedAddress.trim();
      if (normalized.isEmpty) {
        _showInvalid('当前没有获取到定位地址');
        return;
      }
      setState(() {
        _locationCtrl.text = normalized;
        _useStoredLocation = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showInvalid('定位地址获取失败: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isResolvingLocation = false;
        });
      }
    }
  }

  void _submit() {
    if (!_useStoredLocation && _locationCtrl.text.trim().isEmpty) {
      _showInvalid('请填写地址');
      return;
    }
    if (!_useStoredWeatherText && _weatherCtrl.text.trim().isEmpty) {
      _showInvalid('请填写天气');
      return;
    }
    if (!_useStoredRoomCode && _roomCodeCtrl.text.trim().isEmpty) {
      _showInvalid('请填写备注');
      return;
    }
    if (!_useStoredImprintText && _imprintCtrl.text.trim().isEmpty) {
      _showInvalid('请填写盾牌文案');
      return;
    }

    Navigator.of(context).pop(
      BatchComposeOptions(
        useStoredLocation: _useStoredLocation,
        customLocation: _locationCtrl.text.trim(),
        useStoredWeatherText: _useStoredWeatherText,
        customWeatherText: _weatherCtrl.text.trim(),
        useStoredRoomCode: _useStoredRoomCode,
        customRoomCode: _roomCodeCtrl.text.trim(),
        useStoredImprintText: _useStoredImprintText,
        customImprintText: _imprintCtrl.text.trim(),
        useCaptureTime: _useCaptureTime,
        customCaptureTime: _customCaptureTime,
      ),
    );
  }

  void _showInvalid(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatDatePart(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  String _formatTimePart(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('批量合成水印')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '待合成素材',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text('当前共有 ${widget.pendingCount} 张无水印照片待批量合成'),
                  const SizedBox(height: 6),
                  const Text(
                    '地址默认不是自动重新定位，而是沿用素材库记录；你也可以手填，或点按钮用手机当前定位填入。微调参数直接沿用你当前保存的全局调节值；防伪码会为每张重新随机生成。',
                    style: TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildSwitchField(
            title: '地址',
            subtitleStored: '使用素材库记录的地址',
            subtitleCustom: '统一覆盖全部照片地址',
            useStoredValue: _useStoredLocation,
            onChanged: (value) => setState(() => _useStoredLocation = value),
            controller: _locationCtrl,
            hintText: '输入统一地址',
            extraActions: [
              OutlinedButton.icon(
                onPressed: _isResolvingLocation ? null : _fillLocationFromPhone,
                icon: _isResolvingLocation
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location_outlined),
                label: Text(_isResolvingLocation ? '定位中' : '手机定位填入'),
              ),
            ],
          ),
          _buildSwitchField(
            title: '天气',
            subtitleStored: '使用素材库记录的天气',
            subtitleCustom: '统一覆盖全部照片天气',
            useStoredValue: _useStoredWeatherText,
            onChanged: (value) => setState(() => _useStoredWeatherText = value),
            controller: _weatherCtrl,
            hintText: '输入统一天气',
          ),
          _buildSwitchField(
            title: '备注块',
            subtitleStored: '使用每张素材保存的房间备注',
            subtitleCustom: '统一覆盖全部照片备注',
            useStoredValue: _useStoredRoomCode,
            onChanged: (value) => setState(() => _useStoredRoomCode = value),
            controller: _roomCodeCtrl,
            hintText: '输入统一备注',
          ),
          _buildSwitchField(
            title: '盾牌文案',
            subtitleStored: '使用素材库记录的盾牌文案',
            subtitleCustom: '统一覆盖全部照片盾牌文案',
            useStoredValue: _useStoredImprintText,
            onChanged: (value) => setState(() => _useStoredImprintText = value),
            controller: _imprintCtrl,
            hintText: '输入统一盾牌文案',
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('时间使用实拍时间'),
                    subtitle: Text(
                      _useCaptureTime ? '每张照片沿用素材库保存的实拍时间' : '全部照片统一使用同一个自定义时间',
                    ),
                    value: _useCaptureTime,
                    onChanged: (value) =>
                        setState(() => _useCaptureTime = value),
                  ),
                  if (!_useCaptureTime) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickCustomDate,
                            icon: const Icon(Icons.calendar_month_outlined),
                            label: Text(_formatDatePart(_customCaptureTime)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickCustomTime,
                            icon: const Icon(Icons.schedule_outlined),
                            label: Text(_formatTimePart(_customCaptureTime)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '当前自定义时间：${_formatDatePart(_customCaptureTime)} ${_formatTimePart(_customCaptureTime)}',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('开始批量合成'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchField({
    required String title,
    required String subtitleStored,
    required String subtitleCustom,
    required bool useStoredValue,
    required ValueChanged<bool> onChanged,
    required TextEditingController controller,
    required String hintText,
    List<Widget> extraActions = const <Widget>[],
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(title),
              subtitle: Text(useStoredValue ? subtitleStored : subtitleCustom),
              value: useStoredValue,
              onChanged: onChanged,
            ),
            if (!useStoredValue) ...[
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: title,
                  hintText: hintText,
                  border: const OutlineInputBorder(),
                ),
                maxLines: title == '盾牌文案' ? 2 : 1,
              ),
              if (extraActions.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: extraActions),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
