import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:photo_namer/models/inspection_calendar.dart';
import 'package:photo_namer/models/meter_models.dart';
import 'package:photo_namer/pages/calendar/inspection_calendar_stat_tile.dart';

class ShiftAwareInspectionCalendarPage extends StatefulWidget {
  final Map<String, InspectionCalendarDayRecord> initialRecords;
  final InspectionShiftScheduleConfig initialScheduleConfig;
  final Future<void> Function(Map<String, InspectionCalendarDayRecord> records)
  onRecordsChanged;
  final Future<void> Function(InspectionShiftScheduleConfig config)
  onScheduleConfigChanged;

  const ShiftAwareInspectionCalendarPage({
    super.key,
    required this.initialRecords,
    required this.initialScheduleConfig,
    required this.onRecordsChanged,
    required this.onScheduleConfigChanged,
  });

  @override
  State<ShiftAwareInspectionCalendarPage> createState() =>
      _ShiftAwareInspectionCalendarPageState();
}

class _ShiftAwareInspectionCalendarPageState
    extends State<ShiftAwareInspectionCalendarPage> {
  static const List<Color> _slotColors = [
    Color(0xFF2563EB),
    Color(0xFF0F766E),
    Color(0xFFF59E0B),
    Color(0xFFEA580C),
    Color(0xFFDC2626),
  ];

  late Map<String, InspectionCalendarDayRecord> _records;
  late InspectionShiftScheduleConfig _scheduleConfig;
  late DateTime _visibleMonth;
  late DateTime _selectedDate;
  late final List<String> _slotLabels;

  @override
  void initState() {
    super.initState();
    final today = normalizeInspectionCalendarDate(DateTime.now());
    _records = cloneInspectionCalendarRecords(widget.initialRecords);
    _scheduleConfig = widget.initialScheduleConfig;
    _visibleMonth = normalizeInspectionCalendarMonth(today);
    _selectedDate = today;
    _slotLabels = kDefaultMeterTimeSlots
        .map((slot) => slot.label)
        .toList(growable: false);
  }

  String get _selectedDateKey => formatInspectionCalendarDateKey(_selectedDate);

  InspectionCalendarDayRecord get _selectedRecord =>
      _records[_selectedDateKey] ??
      InspectionCalendarDayRecord.empty(_selectedDateKey);

  InspectionShiftType get _selectedShiftType =>
      inspectionShiftTypeForDate(_selectedDate, _scheduleConfig);

  List<String> get _selectedRequiredSlots =>
      inspectionRequiredSlotsForShift(_selectedShiftType);

  List<String> get _selectedAssignedSlots =>
      assignedInspectionSlotsForDate(_selectedDate, _scheduleConfig);

  bool get _selectedDateIsToday =>
      DateUtils.isSameDay(_selectedDate, DateTime.now());

  String get _recommendedSlotLabel =>
      matchedInspectionSlotLabelForMoment(DateTime.now(), _scheduleConfig);

  DateTime get _firstMorningShiftDate =>
      parseInspectionCalendarDateKey(
        _scheduleConfig.firstMorningShiftDateKey,
      ) ??
      normalizeInspectionCalendarDate(DateTime.now());

  DateTime get _firstInspectionDate =>
      inspectionRotationStartDateForConfig(_scheduleConfig);

  InspectionShiftType get _firstInspectionShiftType =>
      inspectionShiftTypeForDate(_firstInspectionDate, _scheduleConfig);

  List<String> get _firstInspectionCandidateSlots =>
      inspectionRequiredSlotsForDate(_firstInspectionDate, _scheduleConfig);

  String get _firstInspectionSlotLabel =>
      resolveInspectionRotationStartSlotLabel(_scheduleConfig);

  Color _slotColorForIndex(int index) =>
      _slotColors[index % _slotColors.length];

  Color _shiftColor(InspectionShiftType shiftType) {
    switch (shiftType) {
      case InspectionShiftType.morning:
        return const Color(0xFF2563EB);
      case InspectionShiftType.middle:
        return const Color(0xFFEA580C);
      case InspectionShiftType.night:
        return const Color(0xFF7C3AED);
      case InspectionShiftType.rest:
        return const Color(0xFF98A2B3);
    }
  }

  Future<void> _persistRecords() async {
    await widget.onRecordsChanged(cloneInspectionCalendarRecords(_records));
  }

  Future<void> _persistScheduleConfig() async {
    await widget.onScheduleConfigChanged(_scheduleConfig);
  }

  List<String> _assignedSlotsForDate(DateTime date) {
    return assignedInspectionSlotsForDate(date, _scheduleConfig);
  }

  int _completedAssignedCount(DateTime date, Set<String> completedSlots) {
    final assignedSlots = _assignedSlotsForDate(date);
    var count = 0;
    for (final slot in assignedSlots) {
      if (completedSlots.contains(slot)) {
        count++;
      }
    }
    return count;
  }

  bool _isAssignedInspectionDay(DateTime date) {
    return _assignedSlotsForDate(date).isNotEmpty;
  }

  bool _isAssignedInspectionDayCompleted(DateTime date) {
    final assignedSlots = _assignedSlotsForDate(date);
    if (assignedSlots.isEmpty) {
      return false;
    }
    final record =
        _records[formatInspectionCalendarDateKey(date)] ??
        InspectionCalendarDayRecord.empty(
          formatInspectionCalendarDateKey(date),
        );
    return _completedAssignedCount(date, record.completedSlots) >=
        assignedSlots.length;
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

  void _markSelectedShiftCompleted() {
    if (_selectedAssignedSlots.isEmpty) {
      return;
    }
    final nextSlots = Set<String>.from(_selectedRecord.completedSlots)
      ..addAll(_selectedAssignedSlots);
    _applySlotsForDate(_selectedDate, nextSlots);
  }

  void _markSelectedDayAllCompleted() {
    _applySlotsForDate(_selectedDate, Set<String>.from(_slotLabels));
  }

  void _clearSelectedDay() {
    _applySlotsForDate(_selectedDate, <String>{});
  }

  void _markRecommendedSlotForSelectedDay() {
    if (_recommendedSlotLabel.isEmpty) {
      return;
    }
    final nextSlots = Set<String>.from(_selectedRecord.completedSlots)
      ..add(_recommendedSlotLabel);
    _applySlotsForDate(_selectedDate, nextSlots);
  }

  void _jumpToToday() {
    final now = normalizeInspectionCalendarDate(DateTime.now());
    setState(() {
      _visibleMonth = normalizeInspectionCalendarMonth(now);
      _selectedDate = now;
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

  Future<void> _pickFirstMorningShiftDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _firstMorningShiftDate,
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: DateTime(now.year + 5, 12, 31),
      helpText: '选择第一个早班日期',
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _scheduleConfig = _scheduleConfig.copyWith(
        firstMorningShiftDateKey: formatInspectionCalendarDateKey(picked),
      );
    });
    unawaited(_persistScheduleConfig());
  }

  void _changeRotationMemberCount(int delta) {
    final nextCount = math.max(1, _scheduleConfig.rotationMemberCount + delta);
    if (nextCount == _scheduleConfig.rotationMemberCount) {
      return;
    }
    setState(() {
      _scheduleConfig = _scheduleConfig.copyWith(
        rotationMemberCount: nextCount,
      );
    });
    unawaited(_persistScheduleConfig());
  }

  Future<void> _pickFirstInspectionDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _firstInspectionDate,
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: DateTime(now.year + 5, 12, 31),
      helpText: '选择首次轮到巡检日期',
    );
    if (picked == null || !mounted) {
      return;
    }

    final normalizedPicked = normalizeInspectionCalendarDate(picked);
    final candidateSlots = inspectionRequiredSlotsForDate(
      normalizedPicked,
      _scheduleConfig,
    );
    if (candidateSlots.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('所选日期是休息日，不能作为首次轮值日期')));
      return;
    }

    final nextSlotLabel = candidateSlots.contains(_firstInspectionSlotLabel)
        ? _firstInspectionSlotLabel
        : candidateSlots.first;
    setState(() {
      _scheduleConfig = _scheduleConfig.copyWith(
        firstInspectionDateKey: formatInspectionCalendarDateKey(
          normalizedPicked,
        ),
        firstInspectionSlotLabel: nextSlotLabel,
      );
    });
    unawaited(_persistScheduleConfig());
  }

  void _setFirstInspectionSlotLabel(String label) {
    if (label.trim().isEmpty || label == _firstInspectionSlotLabel) {
      return;
    }
    setState(() {
      _scheduleConfig = _scheduleConfig.copyWith(
        firstInspectionSlotLabel: label,
      );
    });
    unawaited(_persistScheduleConfig());
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

  int _countWorkingDaysInMonth(DateTime month) {
    final monthDays = DateUtils.getDaysInMonth(month.year, month.month);
    var count = 0;
    for (int day = 1; day <= monthDays; day++) {
      if (_isAssignedInspectionDay(DateTime(month.year, month.month, day))) {
        count++;
      }
    }
    return count;
  }

  int _countCompletedWorkingDaysInMonth(DateTime month) {
    final monthDays = DateUtils.getDaysInMonth(month.year, month.month);
    var count = 0;
    for (int day = 1; day <= monthDays; day++) {
      if (_isAssignedInspectionDayCompleted(
        DateTime(month.year, month.month, day),
      )) {
        count++;
      }
    }
    return count;
  }

  int _countRequiredInspectionsInMonth(DateTime month) {
    final monthDays = DateUtils.getDaysInMonth(month.year, month.month);
    var count = 0;
    for (int day = 1; day <= monthDays; day++) {
      count += _assignedSlotsForDate(
        DateTime(month.year, month.month, day),
      ).length;
    }
    return count;
  }

  int _countCompletedRequiredInspectionsInMonth(DateTime month) {
    final monthDays = DateUtils.getDaysInMonth(month.year, month.month);
    var count = 0;
    for (int day = 1; day <= monthDays; day++) {
      final date = DateTime(month.year, month.month, day);
      final record =
          _records[formatInspectionCalendarDateKey(date)] ??
          InspectionCalendarDayRecord.empty(
            formatInspectionCalendarDateKey(date),
          );
      count += _completedAssignedCount(date, record.completedSlots);
    }
    return count;
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

  Widget _buildShiftPatternChips() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final shiftType in kInspectionShiftCycle)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _shiftColor(shiftType).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _shiftColor(shiftType).withValues(alpha: 0.2),
              ),
            ),
            child: Text(
              inspectionShiftTypeShortLabel(shiftType),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: _shiftColor(shiftType),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildShiftLegend() {
    final entries = <InspectionShiftType>[
      InspectionShiftType.morning,
      InspectionShiftType.middle,
      InspectionShiftType.night,
      InspectionShiftType.rest,
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final shiftType in entries)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _shiftColor(shiftType).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: _shiftColor(shiftType).withValues(alpha: 0.22),
              ),
            ),
            child: Text(
              shiftType == InspectionShiftType.rest
                  ? '休息：无需巡检'
                  : '${inspectionShiftTypeLabel(shiftType)}：${inspectionRequiredSlotsForShift(shiftType).join('、')}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _shiftColor(shiftType),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildUpcomingSchedulePreview() {
    final start = normalizeInspectionCalendarDate(DateTime.now());
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (int offset = 0; offset < 8; offset++)
          Builder(
            builder: (context) {
              final date = start.add(Duration(days: offset));
              final shiftType = inspectionShiftTypeForDate(
                date,
                _scheduleConfig,
              );
              final shiftSlots = inspectionRequiredSlotsForShift(shiftType);
              final assignedSlots = _assignedSlotsForDate(date);
              final isRestDay = shiftType == InspectionShiftType.rest;
              final isAssignedDay = assignedSlots.isNotEmpty;
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _shiftColor(shiftType).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _shiftColor(shiftType).withValues(alpha: 0.18),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${date.month}/${date.day}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      inspectionShiftTypeLabel(shiftType),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: _shiftColor(shiftType),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isRestDay
                          ? '当天休息'
                          : isAssignedDay
                          ? '轮到 ${assignedSlots.join('、')}'
                          : '今天轮休',
                      style: const TextStyle(fontSize: 11),
                    ),
                    if (!isRestDay) ...[
                      const SizedBox(height: 2),
                      Text(
                        '全班 ${shiftSlots.join('、')}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF667085),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
      ],
    );
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

  Widget _buildSlotLegend() {
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
            child: Text(
              _slotLabels[index],
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _slotColorForIndex(index),
              ),
            ),
          ),
      ],
    );
  }

  String _compactSlotLabel(String label) {
    return label.replaceAll('点', '').trim();
  }

  Widget _buildShiftBadge(InspectionShiftType shiftType) {
    final shiftColor = _shiftColor(shiftType);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: shiftColor.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        inspectionShiftTypeShortLabel(shiftType),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: shiftColor,
          height: 1,
        ),
      ),
    );
  }

  Widget _buildAssignedSlotBadges(
    List<String> assignedSlots,
    Set<String> completedSlots,
    InspectionShiftType shiftType,
  ) {
    if (shiftType == InspectionShiftType.rest) {
      return const Text(
        '当日休息',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Color(0xFF98A2B3),
        ),
      );
    }

    if (assignedSlots.isEmpty) {
      return Text(
        '今天轮休',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: _shiftColor(shiftType).withValues(alpha: 0.8),
        ),
      );
    }

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (int index = 0; index < assignedSlots.length; index++)
          Container(
            constraints: const BoxConstraints(minWidth: 18),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: completedSlots.contains(assignedSlots[index])
                  ? _slotColorForIndex(index).withValues(alpha: 0.16)
                  : const Color(0xFFF2F4F7),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: completedSlots.contains(assignedSlots[index])
                    ? _slotColorForIndex(index).withValues(alpha: 0.45)
                    : const Color(0xFFD0D5DD),
              ),
            ),
            child: Text(
              _compactSlotLabel(assignedSlots[index]),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w800,
                color: completedSlots.contains(assignedSlots[index])
                    ? _slotColorForIndex(index)
                    : const Color(0xFF98A2B3),
                height: 1,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDayCell(DateTime? date) {
    if (date == null) {
      return const SizedBox.shrink();
    }

    final dateKey = formatInspectionCalendarDateKey(date);
    final record = _records[dateKey];
    final completedSlots = record?.completedSlots ?? const <String>{};
    final shiftType = inspectionShiftTypeForDate(date, _scheduleConfig);
    final assignedSlots = _assignedSlotsForDate(date);
    final assignedCount = assignedSlots.length;
    final completedAssignedCount = _completedAssignedCount(
      date,
      completedSlots,
    );
    final extraCompletedCount = completedSlots
        .where((slot) => !assignedSlots.contains(slot))
        .length;
    final isSelected = DateUtils.isSameDay(date, _selectedDate);
    final isToday = DateUtils.isSameDay(date, DateTime.now());
    final shiftColor = _shiftColor(shiftType);

    final borderColor = isSelected
        ? Theme.of(context).colorScheme.primary
        : isToday
        ? shiftColor.withValues(alpha: 0.9)
        : const Color(0xFFE4E7EC);
    final backgroundColor = isSelected
        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
        : shiftType == InspectionShiftType.rest
        ? const Color(0xFFF8FAFC)
        : assignedCount == 0
        ? shiftColor.withValues(alpha: 0.025)
        : shiftColor.withValues(alpha: 0.06);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        setState(() {
          _selectedDate = date;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(7, 7, 7, 6),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: isSelected ? 1.6 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${date.day}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    height: 1,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : const Color(0xFF101828),
                  ),
                ),
                const Spacer(),
                if (isToday)
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.only(top: 3),
                    decoration: const BoxDecoration(
                      color: Color(0xFF2563EB),
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                _buildShiftBadge(shiftType),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    shiftType == InspectionShiftType.rest
                        ? '休息'
                        : assignedCount == 0
                        ? '轮休'
                        : '$completedAssignedCount/$assignedCount',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF667085),
                      height: 1.1,
                    ),
                  ),
                ),
                if (extraCompletedCount > 0)
                  Container(
                    margin: const EdgeInsets.only(left: 3),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '+$extraCompletedCount',
                      style: const TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF4F46E5),
                        height: 1,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Align(
                alignment: Alignment.topLeft,
                child: _buildAssignedSlotBadges(
                  assignedSlots,
                  completedSlots,
                  shiftType,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = normalizeInspectionCalendarDate(DateTime.now());
    final todayShiftType = inspectionShiftTypeForDate(today, _scheduleConfig);
    final todayShiftRequiredSlots = inspectionRequiredSlotsForShift(
      todayShiftType,
    );
    final todayAssignedSlots = _assignedSlotsForDate(today);
    final todayRecord =
        _records[formatInspectionCalendarDateKey(today)] ??
        InspectionCalendarDayRecord.empty(
          formatInspectionCalendarDateKey(today),
        );
    final todayCompletedCount = _completedAssignedCount(
      today,
      todayRecord.completedSlots,
    );

    final selectedShiftRequiredSlots = _selectedRequiredSlots;
    final selectedAssignedSlots = _selectedAssignedSlots;
    final selectedAssignedCount = selectedAssignedSlots.length;
    final selectedCompletedCount = _completedAssignedCount(
      _selectedDate,
      _selectedRecord.completedSlots,
    );
    final selectedExtraCount =
        _selectedRecord.completedSlots.length - selectedCompletedCount;
    final selectedSummaryLabel = _selectedShiftType == InspectionShiftType.rest
        ? '休息'
        : selectedAssignedCount == 0
        ? '轮休'
        : '$selectedCompletedCount/$selectedAssignedCount';
    final selectedPrimaryDescription =
        _selectedShiftType == InspectionShiftType.rest
        ? '这一天是休息日，无需巡检。'
        : selectedAssignedCount == 0
        ? '这一天是${inspectionShiftTypeLabel(_selectedShiftType)}，但这次没有轮到你。'
        : '这一天轮到你巡检：${selectedAssignedSlots.join('、')}。';
    final selectedSecondaryDescription =
        _selectedShiftType == InspectionShiftType.rest
        ? ''
        : '全班应巡时段：${selectedShiftRequiredSlots.join('、')}';

    final monthWorkingDays = _countWorkingDaysInMonth(_visibleMonth);
    final monthCompletedDays = _countCompletedWorkingDaysInMonth(_visibleMonth);
    final monthRequiredCount = _countRequiredInspectionsInMonth(_visibleMonth);
    final monthCompletedCount = _countCompletedRequiredInspectionsInMonth(
      _visibleMonth,
    );
    final progressValue = monthRequiredCount == 0
        ? 0.0
        : monthCompletedCount / monthRequiredCount;
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
                  '个人排班计划',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                const Text(
                  '按“早早中中晚晚休休”8天循环，再结合轮班人数与首次轮值日期，自动算出今天是否轮到你以及该巡哪个时段。',
                  style: TextStyle(fontSize: 13, color: Color(0xFF667085)),
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompact = constraints.maxWidth < 420;
                    final itemWidth = isCompact
                        ? (constraints.maxWidth - 10) / 2
                        : (constraints.maxWidth - 20) / 3;
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        SizedBox(
                          width: itemWidth,
                          child: InspectionCalendarStatTile(
                            label: '本月轮到天',
                            value: '$monthCompletedDays/$monthWorkingDays',
                            hint: '按个人轮值',
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: InspectionCalendarStatTile(
                            label: '本月轮到次',
                            value: '$monthCompletedCount/$monthRequiredCount',
                            hint: '按个人轮值',
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: InspectionCalendarStatTile(
                            label: '今日安排',
                            value: todayShiftType == InspectionShiftType.rest
                                ? '休息'
                                : todayAssignedSlots.isEmpty
                                ? '轮休'
                                : '$todayCompletedCount/${todayAssignedSlots.length}',
                            hint: todayShiftType == InspectionShiftType.rest
                                ? '今天无需巡检'
                                : todayAssignedSlots.isEmpty
                                ? '班次 ${inspectionShiftTypeLabel(todayShiftType)} · 全班 ${todayShiftRequiredSlots.join('、')}'
                                : '轮到 ${todayAssignedSlots.join('、')} · 全班 ${todayShiftRequiredSlots.join('、')}',
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progressValue.clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: const Color(0xFFE4E7EC),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF2563EB),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '第一个早班日期：${_scheduleConfig.firstMorningShiftDateKey}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _pickFirstMorningShiftDate,
                      icon: const Icon(Icons.edit_calendar_outlined),
                      label: const Text('改起始早班'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '轮班人数：${_scheduleConfig.rotationMemberCount} 人',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton.outlined(
                      onPressed: _scheduleConfig.rotationMemberCount <= 1
                          ? null
                          : () => _changeRotationMemberCount(-1),
                      icon: const Icon(Icons.remove),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: () => _changeRotationMemberCount(1),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '首次轮到巡检：${_scheduleConfig.firstInspectionDateKey}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _pickFirstInspectionDate,
                      icon: const Icon(Icons.event_repeat_outlined),
                      label: const Text('改首次轮值'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _firstInspectionShiftType == InspectionShiftType.rest
                      ? '首次轮值日期不能是休息日，请重新选择。'
                      : _firstInspectionShiftType == InspectionShiftType.night
                      ? '首次轮值是晚班，请再选一个起始时段。'
                      : '首次轮值班次：${inspectionShiftTypeLabel(_firstInspectionShiftType)}，起始时段会自动固定为 ${_firstInspectionSlotLabel}。',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF667085),
                  ),
                ),
                if (_firstInspectionCandidateSlots.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final slotLabel in _firstInspectionCandidateSlots)
                        ChoiceChip(
                          label: Text(slotLabel),
                          selected: _firstInspectionSlotLabel == slotLabel,
                          onSelected: _firstInspectionCandidateSlots.length == 1
                              ? null
                              : (_) => _setFirstInspectionSlotLabel(slotLabel),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                _buildShiftPatternChips(),
                const SizedBox(height: 12),
                _buildShiftLegend(),
                const SizedBox(height: 12),
                _buildUpcomingSchedulePreview(),
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
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildSlotLegend(),
                const SizedBox(height: 16),
                _buildWeekdayHeader(),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompact = constraints.maxWidth < 380;
                    final spacing = isCompact ? 5.0 : 8.0;
                    final cellWidth = (constraints.maxWidth - spacing * 6) / 7;
                    final cellHeight = math.max(
                      isCompact ? 92.0 : 100.0,
                      cellWidth * (isCompact ? 1.5 : 1.55),
                    );
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: cells.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7,
                        crossAxisSpacing: spacing,
                        mainAxisSpacing: spacing,
                        mainAxisExtent: cellHeight,
                      ),
                      itemBuilder: (context, index) =>
                          _buildDayCell(cells[index]),
                    );
                  },
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
                            '班次：${inspectionShiftTypeLabel(_selectedShiftType)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _shiftColor(_selectedShiftType),
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
                        color: _shiftColor(
                          _selectedShiftType,
                        ).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        selectedSummaryLabel,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _shiftColor(_selectedShiftType),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  selectedPrimaryDescription,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF667085),
                  ),
                ),
                if (selectedSecondaryDescription.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    selectedSecondaryDescription,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF667085),
                    ),
                  ),
                ],
                if (_selectedDateIsToday &&
                    _recommendedSlotLabel.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    '当前时间最适合补记：$_recommendedSlotLabel',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                ],
                if (selectedExtraCount > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '另外还记录了 $selectedExtraCount 个非计划时段，系统会一并保留。',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF667085),
                    ),
                  ),
                ],
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
                            : selectedAssignedSlots.contains(_slotLabels[index])
                            ? Icon(
                                Icons.person_pin_circle_outlined,
                                size: 16,
                                color: _slotColorForIndex(index),
                              )
                            : selectedShiftRequiredSlots.contains(
                                _slotLabels[index],
                              )
                            ? Icon(
                                Icons.flag_outlined,
                                size: 16,
                                color: _shiftColor(_selectedShiftType),
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
                    if (selectedAssignedCount > 0)
                      FilledButton.icon(
                        onPressed: _markSelectedShiftCompleted,
                        icon: const Icon(Icons.done_all_rounded),
                        label: const Text('完成我的轮值'),
                      ),
                    if (_selectedDateIsToday &&
                        _recommendedSlotLabel.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: _markRecommendedSlotForSelectedDay,
                        icon: const Icon(Icons.access_time_rounded),
                        label: Text('补记 $_recommendedSlotLabel'),
                      ),
                    OutlinedButton.icon(
                      onPressed: _markSelectedDayAllCompleted,
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('全部时段记完'),
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
                  '自动规则：排班计划会自动判断今天是不是轮到你，并给出当前最匹配的巡检时段；记录仍然会保留你手动补记的额外时段。',
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

