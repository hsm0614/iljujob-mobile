// lib/presentation/chat/message_list.dart
//
// 채팅방 메시지 목록 렌더링 전담 위젯.
// - ChatMessageList   : 날짜별 그룹핑 + 메시지 버블 렌더링
// - _BotMessageBubble : 일주봇 시스템 메시지
// - _HireNudgeBubble  : 채용 확정 유도 버블

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:iljujob/config/app_theme.dart';
import '../../data/services/work_confirmation_service.dart';
import 'chat_room_helpers.dart';
import 'chat_room_components.dart';
import 'work_confirmation_card.dart';

// ─────────────────────────────────────────────
// 메시지 목록 메인 위젯
// ─────────────────────────────────────────────

class ChatMessageList extends StatelessWidget {
  final List<Map<String, dynamic>> messages;
  final ScrollController scrollController;
  final String userType;

  /// 상대방 프로필 탭 시 호출
  final VoidCallback? onProfileTap;

  /// 상대방 썸네일 URL
  final String? targetThumbnailUrl;

  /// 상대방 이름
  final String? targetName;

  /// 채용 확정 유도 버블 표시 여부
  final bool showHireNudge;

  /// "채용 확정하기" 버튼 콜백
  final VoidCallback? onConfirmHire;
  final List<WorkConfirmation> workConfirmations;
  final void Function(WorkConfirmation confirm)? onAcceptWorkConfirmation;
  final void Function(WorkConfirmation confirm)? onRejectWorkConfirmation;
  final void Function(WorkConfirmation confirm)? onNoShowWorkConfirmation;
  final double inputOverlayHeight;

  /// 전송 실패 메시지 탭 → 재전송
  final void Function(Map<String, dynamic> msg)? onRetryMessage;

  const ChatMessageList({
    super.key,
    required this.messages,
    required this.scrollController,
    required this.userType,
    this.onProfileTap,
    this.targetThumbnailUrl,
    this.targetName,
    this.showHireNudge = false,
    this.onConfirmHire,
    this.workConfirmations = const [],
    this.onAcceptWorkConfirmation,
    this.onRejectWorkConfirmation,
    this.onNoShowWorkConfirmation,
    this.inputOverlayHeight = 112,
    this.onRetryMessage,
  });

  // ── 날짜 키 계산
  String _dateKey(DateTime date) {
    final now = DateTime.now();
    if (DateUtils.isSameDay(date, now)) return '오늘';
    if (DateUtils.isSameDay(
      date,
      DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1)),
    )) {
      return '어제';
    }
    return DateFormat('MM/dd').format(date);
  }

  // ── 메시지에서 DateTime 추출
  DateTime _messageDate(Map<String, dynamic> msg) {
    final ms = msg['createdAtMs'];
    if (ms is int && ms > 0) {
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
    }
    final iso = msg['createdAt'];
    if (iso is String && iso.isNotEmpty) {
      final dt = DateTime.tryParse(iso);
      if (dt != null) return dt.toLocal();
    }
    return parseServerTime(
          msg['timestamp'] ?? msg['created_at'] ?? msg['sent_at'],
        ) ??
        DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    // 정렬·그룹핑은 여기서 딱 한 번. 예전엔 dateKeys 정렬의 비교자 안에서
    // 그날 메시지를 매번 다시 정렬하고 루프에서 또 정렬해서,
    // 메시지가 하나 도착할 때마다 이 전부가 다시 돌았다.
    final dated = <_Dated>[for (final m in messages) _Dated(m, _messageDate(m))]
      ..sort((a, b) => a.date.compareTo(b.date));

    // 출근확정 카드도 대화의 일부다. 예전엔 메시지를 다 그린 뒤 맨 끝에 붙여서,
    // 카드가 제안된 뒤 오간 메시지가 전부 카드 '위'로 올라갔다. 카드는 크고
    // 맨 아래에 고정돼 있으니 스크롤을 내려도 최신 메시지가 화면 밖으로 밀렸다.
    // ("출근확정카드 위로 채팅이 올라가서 안 보인다" 제보의 원인)
    // proposedAt 기준으로 제자리에 끼워넣는다. 시각을 모르는 카드만 맨 뒤로.
    final confirms =
        workConfirmations.where((c) => c.status != 'cancelled').toList()
          ..sort((a, b) {
            final x = a.proposedAt, y = b.proposedAt;
            if (x == null && y == null) return 0;
            if (x == null) return 1;
            if (y == null) return -1;
            return x.compareTo(y);
          });

    // 메시지와 카드를 한 줄기 타임라인으로 합친다. 시각을 모르는 카드(구버전
    // 응답)는 순서를 보장할 수 없으니 맨 뒤로 보낸다.
    final undated = confirms.where((c) => c.proposedAt == null).toList();
    final timeline = <_Entry>[
      for (final d in dated) _Entry(d.date, msg: d.msg),
      for (final c in confirms)
        if (c.proposedAt != null) _Entry(c.proposedAt!, confirm: c),
    ]..sort((a, b) => a.at.compareTo(b.at));

    // 위젯이 아니라 "무엇을 그릴지"만 나열한다. 실제 위젯은 ListView.builder 가
    // 화면에 보이는 것만 만든다 — 예전엔 전체를 Column 에 즉시 생성해서
    // 메시지 500개면 위젯 500개가 항상 트리에 살아 있었다.
    final rows = <_Row>[];
    String? curKey;
    String? prevSender;

    for (final e in timeline) {
      final key = _dateKey(e.at);
      if (key != curKey) {
        rows.add(_Row.divider(key));
        curKey = key;
        prevSender = null;
      }
      if (e.confirm != null) {
        rows.add(_Row.confirm(e.confirm!));
        prevSender = null; // 카드가 끼면 말풍선 묶음이 끊긴다
        continue;
      }
      final msg = e.msg!;
      final sender = msg['sender']?.toString() ?? '';
      if (sender == 'bot' || sender == 'system') {
        rows.add(_Row.bot(msg['message']?.toString() ?? ''));
      } else {
        rows.add(_Row.message(msg, e.at, sender == prevSender));
      }
      prevSender = sender;
    }

    for (final c in undated) {
      rows.add(_Row.confirm(c));
    }
    if (showHireNudge && onConfirmHire != null) rows.add(const _Row.nudge());

    // reverse: true — 새 메시지가 아래에 붙고, 위로 과거를 읽어도 위치가 밀리지
    // 않는다. 메시지가 적을 때 아래로 정렬되는 것도 공짜로 얻어서
    // 예전의 ConstrainedBox(minHeight) + MainAxisAlignment.end 조합이 필요없다.
    final ordered = rows.reversed.toList(growable: false);
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return ListView.builder(
      controller: scrollController,
      reverse: true,
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 4,
        bottom: inputOverlayHeight + bottomInset,
      ),
      itemCount: ordered.length,
      itemBuilder: (context, i) => _buildRow(ordered[i]),
    );
  }

  Widget _buildRow(_Row row) {
    switch (row.kind) {
      case _RowKind.divider:
        return _DateDivider(label: row.text!);
      case _RowKind.bot:
        return _BotMessageBubble(message: row.text!);
      case _RowKind.message:
        final msg = row.msg!;
        final sender = msg['sender']?.toString() ?? '';
        return _MessageBubble(
          msg: msg,
          isMe: sender == (userType == 'worker' ? 'worker' : 'client'),
          isPrevSameSender: row.prevSame,
          when: row.when!,
          targetThumbnailUrl: targetThumbnailUrl,
          targetName: targetName ?? (userType == 'worker' ? '기업' : '알바생'),
          onProfileTap: onProfileTap,
          onRetry: onRetryMessage == null ? null : () => onRetryMessage!(msg),
        );
      case _RowKind.confirm:
        final confirm = row.confirm!;
        return WorkConfirmationCard(
          confirm: confirm,
          userType: userType,
          onAccept:
              userType == 'worker' && confirm.status == 'proposed'
                  ? () => onAcceptWorkConfirmation?.call(confirm)
                  : null,
          onReject:
              userType == 'worker' && confirm.status == 'proposed'
                  ? () => onRejectWorkConfirmation?.call(confirm)
                  : null,
          onNoShow:
              userType == 'client'
                  ? () => onNoShowWorkConfirmation?.call(confirm)
                  : null,
        );
      case _RowKind.nudge:
        return _HireNudgeBubble(onConfirmHire: onConfirmHire!);
    }
  }
}

// ─────────────────────────────────────────────
// 목록 항목 — 위젯이 아니라 "무엇을 그릴지"만 담는다
// ─────────────────────────────────────────────

class _Dated {
  final Map<String, dynamic> msg;
  final DateTime date;
  const _Dated(this.msg, this.date);
}

/// 메시지와 출근확정 카드를 한 줄기로 세우기 위한 타임라인 항목.
/// 둘 중 하나만 채워진다.
class _Entry {
  final DateTime at;
  final Map<String, dynamic>? msg;
  final WorkConfirmation? confirm;
  const _Entry(this.at, {this.msg, this.confirm});
}

enum _RowKind { divider, bot, message, confirm, nudge }

class _Row {
  final _RowKind kind;
  final String? text;
  final Map<String, dynamic>? msg;
  final DateTime? when;
  final bool prevSame;
  final WorkConfirmation? confirm;

  const _Row._(
    this.kind, {
    this.text,
    this.msg,
    this.when,
    this.prevSame = false,
    this.confirm,
  });

  const _Row.divider(String label) : this._(_RowKind.divider, text: label);
  const _Row.bot(String message) : this._(_RowKind.bot, text: message);
  const _Row.message(Map<String, dynamic> m, DateTime w, bool prev)
    : this._(_RowKind.message, msg: m, when: w, prevSame: prev);
  const _Row.confirm(WorkConfirmation c) : this._(_RowKind.confirm, confirm: c);
  const _Row.nudge() : this._(_RowKind.nudge);
}

// ─────────────────────────────────────────────
// 날짜 구분선
// ─────────────────────────────────────────────

class _DateDivider extends StatelessWidget {
  final String label;
  const _DateDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 개별 메시지 버블
// ─────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> msg;
  final bool isMe;
  final bool isPrevSameSender;
  final DateTime when;
  final String? targetThumbnailUrl;
  final String targetName;
  final VoidCallback? onProfileTap;
  final VoidCallback? onRetry;

  const _MessageBubble({
    required this.msg,
    required this.isMe,
    required this.isPrevSameSender,
    required this.when,
    required this.targetName,
    this.targetThumbnailUrl,
    this.onProfileTap,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final messageText = msg['message']?.toString() ?? '';
    final hasImage =
        msg['imageUrl'] != null && msg['imageUrl'].toString().isNotEmpty;
    final isPending = msg['pending'] == true;
    final isFailed = msg['failed'] == true;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          // 상대방 아바타
          if (!isMe && !isPrevSameSender) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onProfileTap ?? () {},
              child: CircleAvatar(
                radius: 16,
                backgroundImage:
                    (targetThumbnailUrl != null &&
                            targetThumbnailUrl!.isNotEmpty)
                        ? NetworkImage(targetThumbnailUrl!)
                        : null,
                child:
                    (targetThumbnailUrl == null || targetThumbnailUrl!.isEmpty)
                        ? const Icon(Icons.person, size: 16)
                        : null,
              ),
            ),
            const SizedBox(width: 6),
          ] else if (!isMe && isPrevSameSender) ...[
            const SizedBox(width: 46),
          ],

          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // 상대방 이름 (첫 메시지만)
                if (!isMe && !isPrevSameSender)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Text(
                      targetName,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),

                // 버블 (전송 실패 시 탭 → 재전송)
                GestureDetector(
                  onTap: isFailed ? onRetry : null,
                  child: Opacity(
                    opacity: isPending ? 0.6 : 1,
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.7,
                      ),
                      decoration: BoxDecoration(
                        color:
                            hasImage
                                ? (isMe ? AppColors.primary : Colors.white)
                                : (isMe
                                    ? AppColors.primary
                                    : AppColors.bgMuted),
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(14),
                          topRight: const Radius.circular(14),
                          bottomLeft: Radius.circular(
                            isMe ? 14 : (isPrevSameSender ? 4 : 14),
                          ),
                          bottomRight: Radius.circular(
                            isMe ? (isPrevSameSender ? 4 : 14) : 14,
                          ),
                        ),
                        border:
                            isFailed
                                ? Border.all(
                                  color: AppColors.error.withValues(
                                    alpha: 0.55,
                                  ),
                                  width: 1,
                                )
                                : (!isMe
                                    ? Border.all(
                                      color: AppColors.border,
                                      width: 0.8,
                                    )
                                    : null),
                      ),
                      child:
                          hasImage
                              ? ChatImageBubble(
                                imageUrl: msg['imageUrl'].toString(),
                                heroTag: 'img_${when.millisecondsSinceEpoch}',
                              )
                              // 사장님이 보내는 건 대개 주소·계좌번호·담당자
                              // 연락처다. Text 로 두면 눈으로 보고 옮겨 적어야
                              // 했다 — 계좌번호 오타는 그대로 사고다.
                              : SelectableText(
                                messageText,
                                style: TextStyle(
                                  fontSize: 14,
                                  color:
                                      isMe
                                          ? Colors.white
                                          : AppColors.textPrimary,
                                ),
                              ),
                    ),
                  ),
                ),

                // 시간 + 읽음/전송 상태 표시
                Padding(
                  padding: EdgeInsets.only(
                    right: isMe ? 6 : 0,
                    left: isMe ? 0 : 6,
                    top: 2,
                  ),
                  child:
                      isFailed
                          ? GestureDetector(
                            onTap: onRetry,
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.error_outline_rounded,
                                  size: 12,
                                  color: AppColors.error,
                                ),
                                SizedBox(width: 3),
                                Text(
                                  '전송 안 됨 · 탭해서 재전송',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.error,
                                  ),
                                ),
                              ],
                            ),
                          )
                          : isPending
                          ? const Text(
                            '전송 중…',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textTertiary,
                            ),
                          )
                          : Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment:
                                isMe
                                    ? MainAxisAlignment.end
                                    : MainAxisAlignment.start,
                            children: [
                              Text(
                                DateFormat('a h:mm', 'ko_KR').format(when),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              if (isMe) ...[
                                const SizedBox(width: 6),
                                Text(
                                  (msg['is_read'] == 1 ||
                                          msg['is_read'] == true)
                                      ? '읽음'
                                      : '안읽음',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color:
                                        (msg['is_read'] == 1 ||
                                                msg['is_read'] == true)
                                            ? AppColors.primary
                                            : AppColors.textTertiary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 봇(시스템) 메시지 버블
// ─────────────────────────────────────────────

class _BotMessageBubble extends StatelessWidget {
  final String message;
  const _BotMessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F6FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFDBEAFE), width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('🤖', style: TextStyle(fontSize: 14)),
                  SizedBox(width: 6),
                  Text(
                    '일주봇',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 출근 확정 제안 유도 버블
// ─────────────────────────────────────────────

class _HireNudgeBubble extends StatelessWidget {
  final VoidCallback onConfirmHire;
  const _HireNudgeBubble({required this.onConfirmHire});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 320),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F9FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFBAE6FD), width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.event_available_rounded,
                    size: 18,
                    color: Color(0xFF0284C7),
                  ),
                  SizedBox(width: 6),
                  Text(
                    '출근 확정을 제안해보세요',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0369A1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '일정을 확정하면 D-1 알림과\n출근 자동 확인이 진행돼요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 36,
                child: ElevatedButton.icon(
                  onPressed: onConfirmHire,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  icon: const Icon(
                    Icons.event_available_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                  label: const Text(
                    '출근 확정 제안하기',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
