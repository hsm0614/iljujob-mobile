// lib/presentation/chat/chat_room_components.dart
//
// ChatRoomScreen에서 사용하는 독립 위젯 컴포넌트 모음.
// - CancelApplicationDialog   : 지원 취소 확인 다이얼로그
// - ChatImageBubble           : 채팅 이미지 버블 (Hero 전환 포함)
// - AlbailjuChatAppBarTitle   : 앱바 타이틀 (상태 칩 + 이름 + 공고명)

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:iljujob/presentation/chat/chat_image_screen.dart';
import '../../config/app_theme.dart';

// ─────────────────────────────────────────────
// 지원 취소 확인 다이얼로그
// ─────────────────────────────────────────────

class CancelApplicationDialog extends StatelessWidget {
  const CancelApplicationDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 아이콘 + 타이틀
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFE4E4),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.warning_rounded,
                    color: AppColors.error,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '지원 취소하시겠어요?',
                        style: TextStyle(
                          fontSize: AppFontSize.buttonLg,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '이 공고에 대한 지원이 취소되며,\n'
                        '다시 지원하려면 새로 지원해야 할 수 있어요.',
                        style: TextStyle(
                          fontSize: AppFontSize.body2,
                          height: 1.4,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // 서브 설명 박스
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.bgPage,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 16, color: AppColors.textTertiary),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '취소 이후에는 채팅만 남고,\n'
                      '해당 공고와의 매칭은 해제됩니다.',
                      style: TextStyle(
                        fontSize: AppFontSize.meta,
                        height: 1.4,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 버튼 2개
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text(
                      '네, 지원을 취소할게요',
                      style: TextStyle(
                        fontSize: AppFontSize.button,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text(
                      '그냥 둘게요',
                      style: TextStyle(
                        fontSize: AppFontSize.button,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 채팅 이미지 버블
// ─────────────────────────────────────────────

class ChatImageBubble extends StatelessWidget {
  final String imageUrl;
  final String heroTag;

  const ChatImageBubble({
    super.key,
    required this.imageUrl,
    required this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatImageScreen(
              imageUrl: imageUrl,
              heroTag: heroTag,
            ),
          ),
        );
      },
      child: Hero(
        tag: heroTag,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            width: 200,
            height: 200,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              width: 200,
              height: 200,
              alignment: Alignment.center,
              color: Colors.black12,
              child: const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            errorWidget: (_, __, ___) => Container(
              width: 200,
              height: 200,
              alignment: Alignment.center,
              color: Colors.black12,
              child: const Icon(Icons.broken_image),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 앱바 타이틀
// ─────────────────────────────────────────────

class AlbailjuChatAppBarTitle extends StatelessWidget {
  final String name;
  final String userType;
  final String status;
  final String jobTitle;

  const AlbailjuChatAppBarTitle({
    super.key,
    required this.name,
    required this.userType,
    required this.status,
    required this.jobTitle,
  });

  @override
  Widget build(BuildContext context) {
    final bool isPending = status == 'pending';
    final bool isBlocked = status == 'blocked';
    final bool isCancelled = status == 'cancelled' || status == 'canceled';

    // 2026-10: 거의 모든 방이 '채팅중'이라 초록 칩은 정보가 없었다 → 평소엔 이름만,
    // 대기·취소·차단처럼 메시지를 못 보낼 때만 한 줄. 공고 제목은 바로 아래 공고 줄과 중복이라 뺐다
    final String? note =
        isPending
            ? '수락 기다리는 중'
            : isCancelled
            ? '지원이 취소된 채팅'
            : isBlocked
            ? '차단된 채팅'
            : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.h3.copyWith(fontSize: AppFontSize.buttonLg),
        ),
        if (note != null)
          Text(
            note,
            style: AppTextStyles.caption.copyWith(
              color: isPending ? AppColors.badgeUrgent : AppColors.textSecondary,
            ),
          ),
      ],
    );
  }
}