import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// 채팅 한 방의 '지금 단계' (2026-10). 목록·대화방이 같은 문구를 쓰게 한 곳에 둔다.
/// 흐름: 긴급호출 응답 → 출근 제안 대기 → 제안 수락 → 출근 예정 → 근무 완료.
/// [needsAction]이면 주황(내가 할 일), 확정·완료는 초록, 나머지는 회색.
class ChatStage {
  final String label;
  final Color color;
  final bool needsAction;
  const ChatStage(this.label, this.color, {this.needsAction = false});
}

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 근무일(벽시계 'YYYY-MM-DD…')이 오늘(기기 날짜)보다 앞이면 true. 비어 있으면 false
bool isWorkDatePast(String? workDate, {DateTime? now}) {
  final d = (workDate ?? '').length >= 10 ? workDate!.substring(0, 10) : '';
  if (d.isEmpty) return false;
  return d.compareTo(_ymd(now ?? DateTime.now())) < 0;
}

/// [workStatus]: work_confirmations 최신 상태 · [urgentStatus]: direct_message_logs 상태
/// · [applicationStatus]: 서버 목록의 applied/confirmed/completed/cancelled
ChatStage? chatStageOf({
  required bool isWorker,
  String? workStatus,
  String? workDate,
  String? urgentStatus,
  bool isUrgent = false,
  String? applicationStatus,
  DateTime? now,
}) {
  const action = AppColors.badgeUrgent;
  const ok = AppColors.badgeSameDay;
  const plain = AppColors.textSecondary;
  final past = isWorkDatePast(workDate, now: now);

  switch (workStatus) {
    case 'proposed':
      if (past) return const ChatStage('지난 출근 제안', plain);
      return isWorker
          ? const ChatStage('출근 제안 확인 필요', action, needsAction: true)
          : const ChatStage('출근 제안 보냄', plain);
    case 'accepted':
    case 'scheduled':
    case 'day_before_confirmed':
    case 'day_of_confirmed':
      return past
          ? const ChatStage('근무일 지남', plain)
          : const ChatStage('출근 예정', ok);
    case 'checked_in':
      return const ChatStage('출근함', ok);
    case 'completed':
      return const ChatStage('근무 완료', ok);
    case 'no_show':
      return const ChatStage('노쇼', AppColors.error);
  }

  if (applicationStatus == 'cancelled') {
    return const ChatStage('지원 취소', plain);
  }
  if (applicationStatus == 'completed') return const ChatStage('근무 완료', ok);

  if (isUrgent) {
    switch (urgentStatus) {
      case 'sent':
        return isWorker
            ? const ChatStage('긴급호출 응답 필요', action, needsAction: true)
            : const ChatStage('긴급호출 보냄', plain);
      case 'accepted':
      case 'time_adjusted':
        // 긴급호출 수락 ≠ 출근 확정 — 다음은 사장님의 출근 제안
        return isWorker
            ? const ChatStage('출근 제안 기다리는 중', plain)
            : const ChatStage('출근 제안 보내기', action, needsAction: true);
      case 'rejected':
        return const ChatStage('긴급호출 거절', plain);
    }
  }

  if (applicationStatus == 'confirmed') return const ChatStage('채용 확정', ok);
  return null;
}
