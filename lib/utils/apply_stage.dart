import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// 지원 한 건의 지금 상태와 다음 할 일.
/// 내 활동 · 지원 완료 안내 · 채팅 출근확정 카드가 **같은 이름**을 쓴다.
class ApplyStage {
  final String label;
  final String? next; // 다음 할 일 (없으면 null)
  final Color color;
  const ApplyStage(this.label, this.next, this.color);

  /// 내 활동 탭 묶음: 'todo'(내가 할 일 있음) · 'waiting'(사장님 답장 대기) · 'done'(끝남)
  String get group =>
      next == null ? 'done' : (this == waiting ? 'waiting' : 'todo');

  static const waiting = ApplyStage(
    '답장 기다리는 중',
    '채팅에서 먼저 인사하기',
    AppColors.textSecondary,
  );
}

/// 출근확정(work_confirmations.status) 이름 — 채팅 카드 칩과 내 활동이 공유
String workStatusLabel(String s) => switch (s) {
  'proposed' => '출근 확정 요청',
  'accepted' || 'scheduled' => '출근 예정',
  'day_before_confirmed' => '전날 확인 완료',
  'day_of_confirmed' => '당일 확인 완료',
  'checked_in' => '출근 완료',
  'completed' => '근무 완료',
  'cancelled' => '확정 취소',
  'no_show' => '노쇼',
  _ => s,
};

/// my-jobs 응답 한 줄 → 상태. 우선순위: 출근확정 > 채용 확정·완료 > 마감 > 사장님 답장 여부
ApplyStage applyStageOf({
  required String jobStatus,
  String? workStatus,
  bool isConfirmed = false,
  bool isCompleted = false,
  bool clientReplied = false,
}) {
  switch (workStatus) {
    case 'proposed':
      return const ApplyStage('출근 확정 요청', '채팅에서 수락하기', AppColors.badgeUrgent);
    case 'accepted' || 'scheduled' || 'day_before_confirmed' || 'day_of_confirmed':
      return ApplyStage(workStatusLabel(workStatus!), '채팅에서 일정 확인', AppColors.textPrimary);
    case 'checked_in' || 'completed':
      return ApplyStage(workStatusLabel(workStatus!), null, AppColors.badgeSameDay);
    case 'no_show':
      return const ApplyStage('노쇼', null, AppColors.error);
  }
  if (isCompleted) return const ApplyStage('근무 완료', null, AppColors.badgeSameDay);
  if (isConfirmed || jobStatus == 'hired' || jobStatus == 'confirmed') {
    return const ApplyStage('채용 확정', '채팅에서 일정 확인', AppColors.badgeSameDay);
  }
  if (jobStatus != 'active') return const ApplyStage('마감', null, AppColors.textTertiary);
  if (clientReplied) {
    return const ApplyStage('사장님이 답장했어요', '채팅 확인하기', AppColors.primary);
  }
  return ApplyStage.waiting;
}
