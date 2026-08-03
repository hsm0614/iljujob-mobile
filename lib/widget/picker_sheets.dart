// ════════════════════════════════════════════════════════
//  공용 날짜·시간 선택 시트
//
//  공고 등록 퍼널에 피커가 4종(TableCalendar 시트 / Material showDatePicker /
//  TimePickerSpinner 시트 / Material showTimePicker)으로 섞여 있어서,
//  같은 흐름 안에서 사용자가 서로 다른 인터랙션을 네 번 배워야 했다.
//  전부 이 파일의 바텀시트로 통일한다.
// ════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:iljujob/config/app_theme.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:time_picker_spinner/time_picker_spinner.dart';

const _blue = AppColors.primary;
const _border = AppColors.border;
const _text = AppColors.textPrimary;

Widget _grip() => Container(
  width: 40,
  height: 4,
  decoration: BoxDecoration(
    color: const Color(0xFFE5E7EB),
    borderRadius: BorderRadius.circular(999),
  ),
);

Widget _sheetHeader(BuildContext ctx, String title) => Padding(
  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
  child: Column(
    children: [
      _grip(),
      const SizedBox(height: 16),
      Row(
        children: [
          const SizedBox(width: 44),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: _text,
              ),
            ),
          ),
          Semantics(
            button: true,
            label: '닫기',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(ctx),
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    ],
  ),
);

Widget _confirmButton(BuildContext ctx, {required VoidCallback? onPressed}) =>
    SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: _blue,
            foregroundColor: Colors.white,
            disabledBackgroundColor: _border,
            disabledForegroundColor: AppColors.textSecondary,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text(
            '선택 완료',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );

/// 날짜 선택 바텀시트. 취소하면 null.
Future<DateTime?> pickDateSheet(
  BuildContext context, {
  required DateTime firstDate,
  required DateTime lastDate,
  DateTime? initial,
  String title = '날짜 선택',
}) {
  DateTime? selected = initial;
  DateTime focused = initial ?? firstDate;
  if (focused.isBefore(firstDate)) focused = firstDate;

  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder:
        (ctx) => StatefulBuilder(
          builder:
              (ctx, set) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _sheetHeader(ctx, title),
                  const SizedBox(height: 4),
                  TableCalendar(
                    locale: 'ko_KR',
                    focusedDay: focused,
                    firstDay: firstDate,
                    lastDay: lastDate,
                    selectedDayPredicate: (d) => isSameDay(d, selected),
                    onDaySelected:
                        (d, f) => set(() {
                          selected = DateTime(d.year, d.month, d.day);
                          focused = d;
                        }),
                    onPageChanged: (f) => set(() => focused = f),
                    calendarStyle: const CalendarStyle(
                      todayDecoration: BoxDecoration(
                        color: Color(0xFFCCDEFF),
                        shape: BoxShape.circle,
                      ),
                      todayTextStyle: TextStyle(
                        color: _blue,
                        fontWeight: FontWeight.w700,
                      ),
                      selectedDecoration: BoxDecoration(
                        color: _blue,
                        shape: BoxShape.circle,
                      ),
                      selectedTextStyle: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                      weekendTextStyle: TextStyle(color: Color(0xFFEF4444)),
                    ),
                    headerStyle: const HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                      titleTextStyle: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _text,
                      ),
                    ),
                  ),
                  _confirmButton(
                    ctx,
                    onPressed:
                        selected == null
                            ? null
                            : () => Navigator.pop(ctx, selected),
                  ),
                ],
              ),
        ),
  );
}

/// 단일 시각 선택 바텀시트. 취소하면 null.
/// 근무 시간(시작~종료 범위)은 post_job_form의 전용 시트를 쓴다.
Future<TimeOfDay?> pickTimeSheet(
  BuildContext context, {
  TimeOfDay? initial,
  String title = '시간 선택',
}) {
  // 스피너가 10분 간격이라 초기값도 맞춰준다.
  TimeOfDay align10(TimeOfDay t) {
    int m = ((t.minute + 5) ~/ 10) * 10;
    int h = t.hour;
    if (m == 60) {
      m = 0;
      h = (h + 1) % 24;
    }
    return TimeOfDay(hour: h, minute: m);
  }

  TimeOfDay picked = align10(initial ?? const TimeOfDay(hour: 9, minute: 0));

  return showModalBottomSheet<TimeOfDay>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder:
        (ctx) => StatefulBuilder(
          builder:
              (ctx, set) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _sheetHeader(ctx, title),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 200,
                    child: TimePickerSpinner(
                      is24HourMode: false,
                      minutesInterval: 10,
                      normalTextStyle: const TextStyle(
                        fontSize: 16,
                        color: AppColors.textSecondary,
                      ),
                      highlightedTextStyle: const TextStyle(
                        fontSize: 18,
                        color: _blue,
                        fontWeight: FontWeight.bold,
                      ),
                      spacing: 40,
                      itemHeight: 40,
                      isForce2Digits: true,
                      time: DateTime(2000, 1, 1, picked.hour, picked.minute),
                      onTimeChange:
                          (dt) => set(
                            () => picked = align10(TimeOfDay.fromDateTime(dt)),
                          ),
                    ),
                  ),
                  _confirmButton(ctx, onPressed: () => Navigator.pop(ctx, picked)),
                ],
              ),
        ),
  );
}
