import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:photo_namer/models/inspection_calendar.dart';
import 'package:photo_namer/models/meter_models.dart';
import 'package:photo_namer/pages/calendar/inspection_calendar_stat_tile.dart';

class InspectionCalendarPage extends StatefulWidget {
  final Map<String, InspectionCalendarDayRecord> initialRecords;
  final Future<void> Function(Map<String, InspectionCalendarDayRecord> records)
  onChanged;

  const InspectionCalendarPage({
    super.key,
    required this.initialRecords,
    required this.onChanged,
  });

  @override
  State<InspectionCalendarPage> createState() => _InspectionCalendarPageState();
}

class _InspectionCalendarPageState extends State<InspectionCalendarPage> {
  static const List<Color> _slotColors = [
    Color(0xFF2563EB),
    Color(0xFF0F766E),
    Color(0xFFF59E0B),
    Color(0xFFEA580C),
    Color(0xFFDC2626),
  ];

  late Map<String, InspectionCalendarDayRecord> _records;
  late DateTime _visibleMonth;
  late DateTime _selectedDate;
  late final List<String> _slotLabels;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _records = cloneInspectionCalendarRecords(widget.initialRecords);
    _visibleMonth = normalizeInspectionCalendarMonth(today);
    _selectedDate = DateTime(today.year, today.month, today.day);
    _slotLabels = kDefaultMeterTimeSlots
        .map((slot) => slot.label)
        .toList(growable: false);
  }

  String get _selectedDateKey => formatInspectionCalendarDateKey(_selectedDate);

  InspectionCalendarDayRecord get _selectedRecord =>
      _records[_selectedDateKey] ??
      InspectionCalendarDayRecord.empty(_selectedDateKey);

  bool get _selectedDateIsToday =>
      DateUtils.isSameDay(_selectedDate, DateTime.now());

  String get _recommendedSlotLabel => nearestMeterTimeSlotLabel(DateTime.now());

  Color _slotColorForIndex(int index) {
    return _slotColors[index % _slotColors.length];
  }

  Future<void> _persistRecords() async {
    await widget.onChanged(cloneInspectionCalendarRecords(_records));
  }

  void _applySlotsForDate(DateTime date, Set<String> completedSlots) {
    final dateKey = formatInspectionCalendarDateKey(date);
    final normalizedSlots = <String>{};
    for (final slot in completedSlots) {
      if (_slotLabels.contains(slot)) {
        normalizedSlots.add(slot);
      }
    }

    setState(() {
      if (normalizedSlots.isEmpty) {
        _records.remove(dateKey);
      } else {
        _records[dateKey] = InspectionCalendarDayRecord(
          dateKey: dateKey,
          completedSlots: normalizedSlots,
          updatedAt: DateTime.now().toIso8601String(),
        );
      }
    });
    unawaited(_persistRecords());
  }

  void _toggleSelectedSlot(String label) {
    final nextSlots = Set<String>.from(_selectedRecord.completedSlots);
    if (!nextSlots.add(label)) {
      nextSlots.remove(label);
    }
    _applySlotsForDate(_selectedDate, nextSlots);
  }

  void _markSelectedDayAllCompleted() {
    _applySlotsForDate(_selectedDate, Set<String>.from(_slotLabels));
  }

  void _clearSelectedDay() {
    _applySlotsForDate(_selectedDate, <String>{});
  }

  void _markRecommendedSlotForSelectedDay() {
    final label = _recommendedSlotLabel;
    if (label.isEmpty) {
      return;
    }
    final nextSlots = Set<String>.from(_selectedRecord.completedSlots)
      ..add(label);
    _applySlotsForDate(_selectedDate, nextSlots);
  }

  void _jumpToToday() {
    final now = DateTime.now();
    setState(() {
      _visibleMonth = normalizeInspectionCalendarMonth(now);
      _selectedDate = DateTime(now.year, now.month, now.day);
    });
  }

  void _changeMonth(int offset) {
    final nextMonth = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + offset,
    );
    final maxDay = DateUtils.getDaysInMonth(nextMonth.year, nextMonth.month);
    setState(() {
      _visibleMonth = nextMonth;
      _selectedDate = DateTime(
        nextMonth.year,
        nextMonth.month,
        math.min(_selectedDate.day, maxDay),
      );
    });
  }

  List<DateTime?> _buildMonthCells() {
    final firstDayOfMonth = DateTime(
      _visibleMonth.year,
      _visibleMonth.month,
      1,
    );
    final daysInMonth = DateUtils.getDaysInMonth(
      _visibleMonth.year,
      _visibleMonth.month,
    );
    final leadingEmptyCount = firstDayOfMonth.weekday - 1;
    final cells = <DateTime?>[
      for (int i = 0; i < leadingEmptyCount; i++) null,
      for (int day = 1; day <= daysInMonth; day++)
        DateTime(_visibleMonth.year, _visibleMonth.month, day),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return cells;
  }

  Iterable<InspectionCalendarDayRecord> _recordsForMonth(DateTime month) sync* {
    for (final entry in _records.entries) {
      final date = parseInspectionCalendarDateKey(entry.key);
      if (date == null) {
        continue;
      }
      if (date.year == month.year && date.month == month.month) {
        yield entry.value;
      }
    }
  }

  String _formatMonthTitle(DateTime month) {
    final value = month.toLocal();
    return '${value.year}年${value.month.toString().padLeft(2, '0')}月';
  }

  String _formatFullDate(DateTime date) {
    final local = date.toLocal();
    final weekday = kInspectionCalendarWeekdayLabels[local.weekday - 1];
    return '${local.year}年${local.month.toString().padLeft(2, '0')}月${local.day.toString().padLeft(2, '0')}日 周$weekday';
  }

  String _formatUpdatedAt(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      return raw.isEmpty ? '未记录' : raw;
    }
    final local = parsed.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute';
  }

  Widget _buildWeekdayHeader() {
    return Row(
      children: [
        for (final label in kInspectionCalendarWeekdayLabels)
          Expanded(
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF475467),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLegend() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (int index = 0; index < _slotLabels.length; index++)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _slotColorForIndex(index).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: _slotColorForIndex(index).withValues(alpha: 0.26),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _slotColorForIndex(index),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _slotLabels[index],
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildDayCell(DateTime? date) {
    if (date == null) {
      return const SizedBox.shrink();
    }

    final record = _records[formatInspectionCalendarDateKey(date)];
    final completedSlots = record?.completedSlots ?? const <String>{};
    final isSelected = DateUtils.isSameDay(date, _selectedDate);
    final isToday = DateUtils.isSameDay(date, DateTime.now());
    final borderColor = isSelected
        ? Theme.of(context).colorScheme.primary
        : isToday
        ? const Color(0xFF60A5FA)
        : const Color(0xFFE4E7EC);
    final backgroundColor = isSelected
        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
        : isToday
        ? const Color(0xFFF7FBFF)
        : Colors.white;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        setState(() {
          _selectedDate = date;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: isSelected ? 1.6 : 1),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.14),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ]
              : const [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${date.day}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : const Color(0xFF101828),
                    ),
                  ),
                ),
                if (isToday)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDBEAFE),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      '今',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1D4ED8),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${completedSlots.length}/${_slotLabels.length} 时段',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF667085),
              ),
            ),
            const Spacer(),
            Wrap(
              spacing: 3,
              runSpacing: 3,
              children: [
                for (int index = 0; index < _slotLabels.length; index++)
                  Container(
                    width: completedSlots.contains(_slotLabels[index]) ? 12 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: completedSlots.contains(_slotLabels[index])
                          ? _slotColorForIndex(index)
                          : const Color(0xFFD0D5DD),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final monthRecords = _recordsForMonth(
      _visibleMonth,
    ).toList(growable: false);
    final monthActiveDays = monthRecords.length;
    final monthCompletedSlots = monthRecords.fold<int>(
      0,
      (sum, record) => sum + record.completedCount,
    );
    final monthDays = DateUtils.getDaysInMonth(
      _visibleMonth.year,
      _visibleMonth.month,
    );
    final todayRecord =
        _records[formatInspectionCalendarDateKey(DateTime.now())];
    final todayCompletedCount = todayRecord?.completedCount ?? 0;
    final cells = _buildMonthCells();

    return Scaffold(
      appBar: AppBar(
        title: const Text('巡检日历'),
        actions: [
          TextButton.icon(
            onPressed: _jumpToToday,
            icon: const Icon(Icons.today_outlined),
            label: const Text('今天'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE4E7EC)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '本月巡检概览',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_formatMonthTitle(_visibleMonth)} 已记录 $monthCompletedSlots 次时段巡检',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF667085),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: InspectionCalendarStatTile(
                        label: '有记录天数',
                        value: '$monthActiveDays/$monthDays',
                        hint: '当月覆盖',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InspectionCalendarStatTile(
                        label: '时段命中数',
                        value: '$monthCompletedSlots',
                        hint: '五时段累计',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InspectionCalendarStatTile(
                        label: '今天进度',
                        value: '$todayCompletedCount/${_slotLabels.length}',
                        hint: '今日巡检',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: monthDays == 0 ? 0 : monthActiveDays / monthDays,
                    minHeight: 8,
                    backgroundColor: const Color(0xFFE4E7EC),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF2563EB),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE4E7EC)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0A101828),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => _changeMonth(-1),
                      icon: const Icon(Icons.chevron_left_rounded),
                      tooltip: '上个月',
                    ),
                    Expanded(
                      child: Text(
                        _formatMonthTitle(_visibleMonth),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _changeMonth(1),
                      icon: const Icon(Icons.chevron_right_rounded),
                      tooltip: '下个月',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildLegend(),
                const SizedBox(height: 16),
                _buildWeekdayHeader(),
                const SizedBox(height: 10),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 7,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 0.78,
                  children: cells.map(_buildDayCell).toList(growable: false),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE4E7EC)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0A101828),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatFullDate(_selectedDate),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _selectedDateIsToday
                                ? '当前最近时段：${_recommendedSlotLabel.isEmpty ? '未匹配' : _recommendedSlotLabel}'
                                : '当天已记录 ${_selectedRecord.completedCount}/${_slotLabels.length} 个时段',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF667085),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2F4F7),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '${_selectedRecord.completedCount}/${_slotLabels.length}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (int index = 0; index < _slotLabels.length; index++)
                      FilterChip(
                        selected: _selectedRecord.completedSlots.contains(
                          _slotLabels[index],
                        ),
                        showCheckmark: false,
                        avatar:
                            _selectedDateIsToday &&
                                _recommendedSlotLabel == _slotLabels[index]
                            ? Icon(
                                Icons.access_time_rounded,
                                size: 16,
                                color: _slotColorForIndex(index),
                              )
                            : null,
                        label: Text(_slotLabels[index]),
                        selectedColor: _slotColorForIndex(
                          index,
                        ).withValues(alpha: 0.14),
                        side: BorderSide(
                          color:
                              _selectedRecord.completedSlots.contains(
                                _slotLabels[index],
                              )
                              ? _slotColorForIndex(index)
                              : const Color(0xFFD0D5DD),
                        ),
                        labelStyle: TextStyle(
                          fontWeight: FontWeight.w700,
                          color:
                              _selectedRecord.completedSlots.contains(
                                _slotLabels[index],
                              )
                              ? _slotColorForIndex(index)
                              : const Color(0xFF344054),
                        ),
                        onSelected: (_) =>
                            _toggleSelectedSlot(_slotLabels[index]),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  _selectedRecord.updatedAt.isEmpty
                      ? '当天暂未记录'
                      : '最后更新：${_formatUpdatedAt(_selectedRecord.updatedAt)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF667085),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (_selectedDateIsToday &&
                        _recommendedSlotLabel.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: _markRecommendedSlotForSelectedDay,
                        icon: const Icon(Icons.access_time_rounded),
                        label: Text('补记 $_recommendedSlotLabel'),
                      ),
                    FilledButton.icon(
                      onPressed: _slotLabels.isEmpty
                          ? null
                          : _markSelectedDayAllCompleted,
                      icon: const Icon(Icons.done_all_rounded),
                      label: const Text('当天全部完成'),
                    ),
                    TextButton.icon(
                      onPressed: _selectedRecord.completedSlots.isEmpty
                          ? null
                          : _clearSelectedDay,
                      icon: const Icon(Icons.cleaning_services_outlined),
                      label: const Text('清空当天'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  '提示：用户成功拍照后，系统会按当前时间自动记到最近的巡检时段；这里也支持手动补录和修正。',
                  style: TextStyle(fontSize: 12, color: Color(0xFF667085)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

