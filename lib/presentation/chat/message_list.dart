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
  final double inputOverlayHeight;

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
    this.inputOverlayHeight = 112,
  });

  // ── 날짜 키 계산
  String _dateKey(DateTime date) {
    final now = DateTime.now();
    if (DateUtils.isSameDay(date, now)) return '오늘';
    if (DateUtils.isSameDay(
      date,
      DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1)),
    ))
      return '어제';
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
    // 날짜별 그룹핑
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final msg in messages) {
      final key = _dateKey(_messageDate(msg));
      grouped.putIfAbsent(key, () => []).add(msg);
    }

    // 날짜 오름차순 정렬
    final dateKeys =
        grouped.keys.toList()..sort((a, b) {
          DateTime first(String k) {
            final list =
                grouped[k]!..sort(
                  (m1, m2) => _messageDate(m1).compareTo(_messageDate(m2)),
                );
            return _messageDate(list.first);
          }

          return first(a).compareTo(first(b));
        });

    final List<Widget> children = [];

    for (final dateKey in dateKeys) {
      final dayMessages =
          grouped[dateKey]!
            ..sort((m1, m2) => _messageDate(m1).compareTo(_messageDate(m2)));

      // 날짜 구분선
      children.add(_DateDivider(label: dateKey));

      for (var i = 0; i < dayMessages.length; i++) {
        final msg = dayMessages[i];
        final sender = msg['sender']?.toString() ?? '';

        // 봇 메시지
        if (sender == 'bot' || sender == 'system') {
          children.add(
            _BotMessageBubble(message: msg['message']?.toString() ?? ''),
          );
          continue;
        }

        final isMe = sender == (userType == 'worker' ? 'worker' : 'client');
        final isPrevSameSender =
            i > 0 && dayMessages[i - 1]['sender'] == sender;
        final when = _messageDate(msg);

        children.add(
          _MessageBubble(
            msg: msg,
            isMe: isMe,
            isPrevSameSender: isPrevSameSender,
            when: when,
            targetThumbnailUrl: targetThumbnailUrl,
            targetName: targetName ?? (userType == 'worker' ? '기업' : '알바생'),
            onProfileTap: onProfileTap,
          ),
        );
      }
    }

    for (final confirm in workConfirmations) {
      children.add(
        WorkConfirmationCard(
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
        ),
      );
    }

    // 채용 확정 유도 버블
    if (showHireNudge && onConfirmHire != null) {
      children.add(_HireNudgeBubble(onConfirmHire: onConfirmHire!));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final bottomInset = MediaQuery.of(context).padding.bottom;
        return SingleChildScrollView(
          controller: scrollController,
          padding: EdgeInsets.only(
            left: 8,
            right: 8,
            top: 4,
            bottom: inputOverlayHeight + bottomInset,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        );
      },
    );
  }
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

  const _MessageBubble({
    required this.msg,
    required this.isMe,
    required this.isPrevSameSender,
    required this.when,
    required this.targetName,
    this.targetThumbnailUrl,
    this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    final messageText = msg['message']?.toString() ?? '';
    final hasImage =
        msg['imageUrl'] != null && msg['imageUrl'].toString().isNotEmpty;

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
                        color: Color(0xFF9CA3AF),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),

                // 버블
                Container(
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
                            : (isMe ? AppColors.primary : AppColors.bgMuted),
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
                        !isMe
                            ? Border.all(color: AppColors.border, width: 0.8)
                            : null,
                  ),
                  child:
                      hasImage
                          ? ChatImageBubble(
                            imageUrl: msg['imageUrl'].toString(),
                            heroTag: 'img_${when.millisecondsSinceEpoch}',
                          )
                          : Text(
                            messageText,
                            style: TextStyle(
                              fontSize: 14,
                              color:
                                  isMe ? Colors.white : const Color(0xFF111827),
                            ),
                          ),
                ),

                // 시간 + 읽음 표시
                Padding(
                  padding: EdgeInsets.only(
                    right: isMe ? 6 : 0,
                    left: isMe ? 0 : 6,
                    top: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment:
                        isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat('a h:mm', 'ko_KR').format(when),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 6),
                        Text(
                          (msg['is_read'] == 1 || msg['is_read'] == true)
                              ? '읽음'
                              : '안읽음',
                          style: TextStyle(
                            fontSize: 10,
                            color:
                                (msg['is_read'] == 1 || msg['is_read'] == true)
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
                      color: Color(0xFF2563EB),
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
                  color: Color(0xFF374151),
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
// 채용 확정 유도 버블
// ─────────────────────────────────────────────

class _HireNudgeBubble extends StatelessWidget {
  final VoidCallback onConfirmHire;
  const _HireNudgeBubble({required this.onConfirmHire});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 320),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFDBEAFE), width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: Color(0xFF2563EB),
                  ),
                  SizedBox(width: 6),
                  Text(
                    '채용 확정이 필요해요',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1D4ED8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '채용 확정을 해야\n출근 확인 절차가 진행됩니다.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: Color(0xFF374151),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 36,
                child: ElevatedButton.icon(
                  onPressed: onConfirmHire,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1675F4),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  icon: const Icon(
                    Icons.thumb_up_alt_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                  label: const Text(
                    '채용 확정하기',
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
