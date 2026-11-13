// ════════════════════════════════════════════════════════
//  공용 날짜·시간 선택 시트
//
//  공고 등록 퍼널에 피커가 4종(TableCalendar 시트 / Material showDatePicker /
//  TimePickerSpinner 시트 / Material showTimePicker)으로 섞여 있어서,
//  같은 흐름 안에서 사용자가 서로 다른 인터랙션을 네 번 배워야 했다.
//  전부 이 파일의 바텀시트로 통일한다.
// ════════════════════════════════════════════════════════

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:iljujob/config/app_theme.dart';
import 'package:table_calendar/table_calendar.dart';

const _blue = AppColors.primary;
const _border = AppColors.border;
const _text = AppColors.textPrimary;

Widget _grip() => Container(
  width: 40,
  height: 4,
  decoration: BoxDecoration(
    color: AppColors.border,
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
                fontSize: AppFontSize.buttonLg,
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
            disabledBackgroundColor: _border,
            disabledForegroundColor: AppColors.textSecondary,
          ),
          child: const Text('선택 완료'),
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
                    // 토요일까지 빨강이던 것 — 한국 달력처럼 일요일만
                    weekendDays: const [DateTime.sunday],
                    daysOfWeekStyle: const DaysOfWeekStyle(
                      weekendStyle: TextStyle(color: AppColors.urgentCall),
                    ),
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
                        color: AppColors.primaryLight,
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
                      weekendTextStyle: TextStyle(color: AppColors.urgentCall),
                    ),
                    headerStyle: const HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                      titleTextStyle: TextStyle(
                        fontSize: AppFontSize.body1,
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
                    child: KoTimeWheel(
                      hour: picked.hour,
                      minute: picked.minute,
                      onTimeChange:
                          (dt) => set(
                            () => picked = align10(TimeOfDay.fromDateTime(dt)),
                          ),
                    ),
                  ),
                  _confirmButton(
                    ctx,
                    onPressed: () => Navigator.pop(ctx, picked),
                  ),
                ],
              ),
        ),
  );
}

/// 10분 단위 시간 바퀴. 오전/오후를 한국어로 보여준다
/// (time_picker_spinner는 'AM/PM' 영어가 패키지에 고정돼 있었다).
class KoTimeWheel extends StatelessWidget {
  final int hour;
  final int minute;
  final ValueChanged<DateTime> onTimeChange;
  const KoTimeWheel({
    super.key,
    required this.hour,
    required this.minute,
    required this.onTimeChange,
  });

  @override
  Widget build(BuildContext context) => CupertinoTheme(
    data: const CupertinoThemeData(
      textTheme: CupertinoTextThemeData(
        dateTimePickerTextStyle: TextStyle(
          fontSize: AppFontSize.buttonLg,
          color: AppColors.textPrimary,
        ),
      ),
    ),
    child: CupertinoDatePicker(
      mode: CupertinoDatePickerMode.time,
      minuteInterval: 10,
      // 간격에 안 맞는 초기값(09:15 등)이면 CupertinoDatePicker가 assert로 죽는다
      initialDateTime: DateTime(2000, 1, 1, hour, (minute ~/ 10) * 10),
      onDateTimeChanged: onTimeChange,
    ),
  );
}
