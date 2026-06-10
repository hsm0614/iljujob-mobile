// lib/presentation/chat/chat_room_job_panel.dart
//
// 채팅방 상단 공고 요약 패널과 관련 배너 모음.
// - ChatRoomJobPanel      : 공고 요약 + 클라이언트/워커 액션 버튼
// - ChatRoomConsentBanner : 워커 수락/거절 배너
// - ChatRoomWaitingBanner : 클라이언트 대기 배너
// - ChatRoomCancelledBanner : 알바생 취소 배너

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:iljujob/config/app_theme.dart';
import 'chat_room_helpers.dart';

// ─────────────────────────────────────────────
// 공고 요약 패널
// ─────────────────────────────────────────────

class ChatRoomJobPanel extends StatelessWidget {
  final Map<String, dynamic> jobSource;
  final String userType;

  // 공통 상태
  final bool isConfirmed;
  final bool isCompleted;
  final bool hasPendingWorkConfirmation;
  final String status;

  // 클라이언트 액션 콜백
  final VoidCallback? onConfirmHire;
  final VoidCallback? onMarkCompleted;
  final VoidCallback? onProposeWorkConfirmation;

  // 워커 액션 콜백
  final bool workLoading;
  final bool hasWorkSession;
  final bool canCancel;
  final bool checkedIn;
  final int? checkinDistanceM;
  final bool checkinLoading;
  final bool hasReviewed;
  final bool workerWorkConfirmed;
  final VoidCallback? onAddToCalendar;
  final VoidCallback? onOpenCalendar;
  final VoidCallback? onCancelWorkSession;
  final VoidCallback? onCheckin;
  final VoidCallback? onCancelApplication;
  final VoidCallback? onGoReview;

  // 공고 상세 이동
  final VoidCallback? onOpenJobDetail;

  const ChatRoomJobPanel({
    super.key,
    required this.jobSource,
    required this.userType,
    required this.isConfirmed,
    required this.isCompleted,
    this.hasPendingWorkConfirmation = false,
    required this.status,
    // 클라이언트
    this.onConfirmHire,
    this.onMarkCompleted,
    this.onProposeWorkConfirmation,
    // 워커
    this.workLoading = false,
    this.hasWorkSession = false,
    this.canCancel = false,
    this.checkedIn = false,
    this.checkinDistanceM,
    this.checkinLoading = false,
    this.hasReviewed = false,
    this.workerWorkConfirmed = false,
    this.onAddToCalendar,
    this.onOpenCalendar,
    this.onCancelWorkSession,
    this.onCheckin,
    this.onCancelApplication,
    this.onGoReview,
    this.onOpenJobDetail,
  });

  // ── 공고 정보 추출 헬퍼
  dynamic _pick(List<String> keys) {
    for (final k in keys) {
      if (jobSource[k] != null) return jobSource[k];
    }
    return null;
  }

  String get _title {
    final t = _pick(['title', 'job_title'])?.toString().trim() ?? '';
    return t.isNotEmpty ? t : '공고 제목 없음';
  }

  String get _payText {
    final raw = _pick(['pay', 'salary', 'wage'])?.toString() ?? '0';
    final v = int.tryParse(raw) ?? 0;
    return '${NumberFormat('#,###').format(v)}원';
  }

  String get _periodText => formatPeriod(
    _pick(['start_date', 'startDate']),
    _pick(['end_date', 'endDate']),
  );

  String get _timeText => formatTimeRange(
    _pick(['start_time', 'startTime']),
    _pick(['end_time', 'endTime']),
  );

  bool get _isWeekdaysJob {
    final s = (_pick(['weekdays', 'weekday', 'days']) ?? '').toString().trim();
    return s.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 제목 + 상세보기
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              if (onOpenJobDetail != null)
                TextButton.icon(
                  onPressed: onOpenJobDetail,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 0,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(
                    Icons.open_in_new_rounded,
                    size: 14,
                    color: AppColors.primary,
                  ),
                  label: const Text(
                    '상세',
                    style: TextStyle(fontSize: 11, color: AppColors.primary),
                  ),
                ),
            ],
          ),

          // 공고 정보 바
          Container(
            margin: const EdgeInsets.only(top: 6, bottom: 2),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE8EEFF)),
            ),
            child: Row(
              children: [
                _InfoBit(
                  icon: Icons.monetization_on_rounded,
                  text: _payText,
                  color: AppColors.primary,
                ),
                _InfoDivider(),
                _InfoBit(
                  icon: Icons.calendar_today_outlined,
                  text: _periodText,
                  color: const Color(0xFF374151),
                ),
                _InfoDivider(),
                _InfoBit(
                  icon: Icons.access_time_outlined,
                  text: _timeText,
                  color: const Color(0xFF374151),
                ),
              ],
            ),
          ),

          const SizedBox(height: 6),

          // 액션 버튼
          userType == 'client'
              ? _ClientActions(
                isConfirmed: isConfirmed,
                isCompleted: isCompleted,
                hasPendingWorkConfirmation: hasPendingWorkConfirmation,
                status: status,
                onConfirmHire: onConfirmHire,
                onMarkCompleted: onMarkCompleted,
                onProposeWorkConfirmation: onProposeWorkConfirmation,
              )
              : _WorkerActions(
                status: status,
                isCompleted: isCompleted,
                isWeekdaysJob: _isWeekdaysJob,
                workLoading: workLoading,
                hasWorkSession: hasWorkSession,
                canCancel: canCancel,
                checkedIn: checkedIn,
                checkinDistanceM: checkinDistanceM,
                checkinLoading: checkinLoading,
                hasReviewed: hasReviewed,
                isConfirmed: isConfirmed,
                workerWorkConfirmed: workerWorkConfirmed,
                onAddToCalendar: onAddToCalendar,
                onOpenCalendar: onOpenCalendar,
                onCancelWorkSession: onCancelWorkSession,
                onCheckin: onCheckin,
                onCancelApplication: onCancelApplication,
                onGoReview: onGoReview,
              ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 클라이언트 액션 버튼
// ─────────────────────────────────────────────

class _ClientActions extends StatelessWidget {
  final bool isConfirmed;
  final bool isCompleted;
  final bool hasPendingWorkConfirmation;
  final String status;
  final VoidCallback? onConfirmHire;
  final VoidCallback? onMarkCompleted;
  final VoidCallback? onProposeWorkConfirmation;

  const _ClientActions({
    required this.isConfirmed,
    required this.isCompleted,
    required this.hasPendingWorkConfirmation,
    required this.status,
    this.onConfirmHire,
    this.onMarkCompleted,
    this.onProposeWorkConfirmation,
  });

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[];

    void add(Widget w) {
      if (actions.isNotEmpty) actions.add(const SizedBox(width: 8));
      actions.add(w);
    }

    final isActive = status == 'active';

    // 채용 확정 전: 사장님 UX는 출근 확정 제안으로 통일한다.
    if (!isConfirmed) {
      add(
        _ActionButton(
          text:
              hasPendingWorkConfirmation
                  ? '알바생 응답 대기중'
                  : onProposeWorkConfirmation != null
                  ? '출근 확정 제안하기'
                  : '채용 확정하기',
          icon:
              hasPendingWorkConfirmation
                  ? Icons.hourglass_top_rounded
                  : onProposeWorkConfirmation != null
                  ? Icons.event_available_rounded
                  : Icons.thumb_up_alt_rounded,
          color: const Color(0xFF1675F4),
          onPressed:
              isActive && !hasPendingWorkConfirmation
                  ? (onProposeWorkConfirmation ?? onConfirmHire)
                  : null,
        ),
      );
      add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFDBEAFE)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 13,
                color: Color(0xFF2563EB),
              ),
              const SizedBox(width: 5),
              Text(
                onProposeWorkConfirmation != null
                    ? hasPendingWorkConfirmation
                        ? '알바생이 제안을 확인하면 확정돼요'
                        : '알바생 수락 후 출근확인 가능'
                    : '확정 후 출근확인 가능',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF1D4ED8),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );

      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(children: actions),
      );
    }

    // 확정 후: 완료 처리
    if (!isCompleted) {
      add(
        _ActionButton(
          text: '알바 완료 처리',
          icon: Icons.check_circle_rounded,
          color: Colors.green,
          onPressed: onMarkCompleted,
        ),
      );
    } else {
      add(
        Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            '✔ 알바 완료됨',
            style: TextStyle(
              color: Colors.grey,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(children: actions),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// 워커 액션 버튼
// ─────────────────────────────────────────────

class _WorkerActions extends StatelessWidget {
  final String status;
  final bool isCompleted;
  final bool isWeekdaysJob;
  final bool workLoading;
  final bool hasWorkSession;
  final bool canCancel;
  final bool checkedIn;
  final int? checkinDistanceM;
  final bool checkinLoading;
  final bool hasReviewed;
  final bool isConfirmed;
  final bool workerWorkConfirmed;
  final VoidCallback? onAddToCalendar;
  final VoidCallback? onOpenCalendar;
  final VoidCallback? onCancelWorkSession;
  final VoidCallback? onCheckin;
  final VoidCallback? onCancelApplication;
  final VoidCallback? onGoReview;

  const _WorkerActions({
    required this.status,
    required this.isCompleted,
    required this.isWeekdaysJob,
    required this.workLoading,
    required this.hasWorkSession,
    required this.canCancel,
    required this.checkedIn,
    required this.checkinLoading,
    required this.hasReviewed,
    required this.isConfirmed,
    required this.workerWorkConfirmed,
    this.checkinDistanceM,
    this.onAddToCalendar,
    this.onOpenCalendar,
    this.onCancelWorkSession,
    this.onCheckin,
    this.onCancelApplication,
    this.onGoReview,
  });

  bool get _isCancelled => status == 'cancelled' || status == 'canceled';
  bool get _blocked => status == 'blocked';
  bool get _expired => status == 'expired';
  bool get _hireConfirmed => isConfirmed || workerWorkConfirmed;

  Widget _loadingDot(Color color) => SizedBox(
    width: 14,
    height: 14,
    child: CircularProgressIndicator(strokeWidth: 2, color: color),
  );

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[];

    void add(Widget w) {
      if (actions.isNotEmpty) actions.add(const SizedBox(width: 8));
      actions.add(w);
    }

    final canBook = !_isCancelled && !_blocked && !_expired && !isCompleted;

    // ── 캘린더 (요일 공고면 숨김)
    if (!isWeekdaysJob) {
      if (!hasWorkSession) {
        add(
          ElevatedButton.icon(
            onPressed: (!canBook || workLoading) ? null : onAddToCalendar,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B8AFF),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            ),
            icon:
                workLoading
                    ? _loadingDot(Colors.white)
                    : const Icon(
                      Icons.event_available_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
            label: const Text(
              '캘린더에 추가하기',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        );
      } else {
        add(
          OutlinedButton.icon(
            onPressed: onOpenCalendar,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF1675F4),
              side: const BorderSide(color: Color(0xFF1675F4)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            icon: const Icon(Icons.calendar_month_rounded, size: 16),
            label: const Text(
              '캘린더',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        );

        if (canCancel) {
          add(
            OutlinedButton.icon(
              onPressed: workLoading ? null : onCancelWorkSession,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFDC2626),
                side: const BorderSide(color: Color(0xFFDC2626)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
              icon:
                  workLoading
                      ? _loadingDot(const Color(0xFFDC2626))
                      : const Icon(Icons.event_busy_rounded, size: 16),
              label: const Text(
                '일정 취소',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          );
        }
      }
    }

    // ── 출근 확인
    final canCheckin =
        !checkedIn &&
        status == 'active' &&
        !isWeekdaysJob &&
        !_isCancelled &&
        !_blocked &&
        !_expired &&
        !isCompleted &&
        _hireConfirmed;

    if (canCheckin) {
      add(
        ElevatedButton.icon(
          onPressed: checkinLoading ? null : onCheckin,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          ),
          icon:
              checkinLoading
                  ? _loadingDot(Colors.white)
                  : const Icon(
                    Icons.how_to_reg_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
          label: const Text(
            '출근 확인',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
      );
    } else if (checkedIn) {
      add(
        _Pill(
          icon: Icons.verified_rounded,
          text:
              checkinDistanceM != null
                  ? '출근 확인됨 (${checkinDistanceM}m)'
                  : '출근 확인됨',
          bg: const Color(0x1410B981),
          fg: const Color(0xFF047857),
        ),
      );
    }

    // ── 지원 취소
    add(
      OutlinedButton.icon(
        onPressed: workLoading ? null : onCancelApplication,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFDC2626),
          side: const BorderSide(color: Color(0xFFDC2626)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        icon: const Icon(Icons.cancel_outlined, size: 16),
        label: Text(
          _isCancelled ? '지원 취소됨' : '지원 취소',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );

    // ── 후기
    add(
      TextButton.icon(
        onPressed: hasReviewed ? null : onGoReview,
        icon: Icon(
          Icons.edit_note,
          size: 18,
          color: hasReviewed ? Colors.grey : const Color(0xFF1675F4),
        ),
        label: Text(
          hasReviewed ? '후기 작성 완료' : '후기 남기기',
          style: TextStyle(
            fontSize: 13,
            color: hasReviewed ? Colors.grey : const Color(0xFF1675F4),
          ),
        ),
      ),
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(children: actions),
    );
  }
}

// ─────────────────────────────────────────────
// 공고 정보 바 위젯
// ─────────────────────────────────────────────

class _InfoBit extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _InfoBit({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                text,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      );
}

class _InfoDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 14,
        color: const Color(0xFFD1D5DB),
        margin: const EdgeInsets.symmetric(horizontal: 4),
      );
}

// ─────────────────────────────────────────────
// 공용 Pill 위젯
// ─────────────────────────────────────────────

class _Pill extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? bg;
  final Color? fg;

  const _Pill({required this.icon, required this.text, this.bg, this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg ?? const Color(0xFFEEF5FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg ?? const Color(0xFF1D68E5)),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: fg ?? const Color(0xFF1D68E5),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 공용 액션 버튼
// ─────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.text,
    required this.icon,
    required this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: disabled ? const Color(0xFFE5E7EB) : color,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
      icon: Icon(
        icon,
        size: 15,
        color: disabled ? const Color(0xFF9CA3AF) : Colors.white,
      ),
      label: Text(
        text,
        style: TextStyle(
          color: disabled ? const Color(0xFF9CA3AF) : Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 13,
          letterSpacing: -0.3,
        ),
      ),
      onPressed: onPressed,
    );
  }
}

// ─────────────────────────────────────────────
// 워커 수락/거절 배너
// ─────────────────────────────────────────────

class ChatRoomConsentBanner extends StatelessWidget {
  final bool show;
  final bool busy;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;

  const ChatRoomConsentBanner({
    super.key,
    required this.show,
    required this.busy,
    this.onAccept,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFFEFF6FF),
        border: Border(
          bottom: BorderSide(color: Color(0xFFDBEAFE), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: Color(0xFF2563EB),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '사장님의 대화 요청입니다.\n수락 시 채팅이 시작되고 연락이 가능해요.',
              style: TextStyle(fontSize: 12, color: Color(0xFF1D4ED8)),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: busy ? null : onReject,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFDC2626),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('거절', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 4),
          ElevatedButton(
            onPressed: busy ? null : onAccept,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            child:
                busy
                    ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                    : const Text('수락', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 클라이언트 대기 배너
// ─────────────────────────────────────────────

class ChatRoomWaitingBanner extends StatelessWidget {
  final bool show;

  const ChatRoomWaitingBanner({super.key, required this.show});

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFFFFF7E6),
        border: Border(
          bottom: BorderSide(color: Color(0xFFFDE68A), width: 0.5),
        ),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.hourglass_bottom_rounded,
            size: 18,
            color: Color(0xFFEA580C),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '구직자의 수락을 기다리는 중입니다.\n수락되면 바로 채팅이 가능해요.',
              style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 알바생 취소 배너 (클라이언트에게 표시)
// ─────────────────────────────────────────────

class ChatRoomCancelledBanner extends StatelessWidget {
  final bool show;
  final VoidCallback? onPostJob;

  const ChatRoomCancelledBanner({
    super.key,
    required this.show,
    this.onPostJob,
  });

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFFFEE2E2),
        border: Border(
          bottom: BorderSide(color: Color(0xFFFCA5A5), width: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: Color(0xFFB91C1C),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '알바생이 이 공고에 대한 지원을 취소했어요.\n'
              '지금 다른 공고도 한 번 올려보실래요?',
              style: TextStyle(fontSize: 12, color: Color(0xFF7F1D1D)),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onPostJob,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: const Color(0xFF3B8AFF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            child: const Text('공고 더 쓰기', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }
}
