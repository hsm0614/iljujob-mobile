// lib/presentation/chat/chat_room_components.dart
//
// ChatRoomScreen에서 사용하는 독립 위젯 컴포넌트 모음.
// - CancelApplicationDialog   : 지원 취소 확인 다이얼로그
// - ChatImageBubble           : 채팅 이미지 버블 (Hero 전환 포함)
// - AlbailjuChatAppBarTitle   : 앱바 타이틀 (상태 칩 + 이름 + 공고명)

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:iljujob/presentation/chat/chat_image_screen.dart';

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
                    color: Color(0xFFE53935),
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
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827),
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '이 공고에 대한 지원이 취소되며,\n'
                        '다시 지원하려면 새로 지원해야 할 수 있어요.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: Color(0xFF6B7280),
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
                color: const Color(0xFFF4F6FA),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: Color(0xFF9CA3AF),
                  ),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '취소 이후에는 채팅만 남고,\n'
                      '해당 공고와의 매칭은 해제됩니다.',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: Color(0xFF9CA3AF),
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
                      backgroundColor: const Color(0xFFE53935),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text(
                      '네, 지원을 취소할게요',
                      style: TextStyle(
                        fontSize: 14,
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
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text(
                      '그냥 둘게요',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF374151),
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
            builder:
                (_) => ChatImageScreen(imageUrl: imageUrl, heroTag: heroTag),
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
            placeholder:
                (_, __) => Container(
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
            errorWidget:
                (_, __, ___) => Container(
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
    final bool isActive = status == 'active';
    final bool isCancelled = status == 'cancelled' || status == 'canceled';

    final String chipText;
    final Color chipBg;
    final Color chipFg;

    if (isPending) {
      chipText = '대기중';
      chipBg = const Color(0xFFFFF3E0);
      chipFg = const Color(0xFFE65100);
    } else if (isCancelled) {
      chipText = '취소됨';
      chipBg = const Color(0xFFFFEBEE);
      chipFg = const Color(0xFFC62828);
    } else if (isBlocked) {
      chipText = '차단됨';
      chipBg = const Color(0xFFFFEBEE);
      chipFg = const Color(0xFFC62828);
    } else if (isActive) {
      chipText = '채팅중';
      chipBg = const Color(0xFFE8F5E9);
      chipFg = const Color(0xFF2E7D32);
    } else {
      chipText = '알바일주';
      chipBg = const Color(0xFFF5F5F5);
      chipFg = const Color(0xFF757575);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 상태 칩
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: chipBg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: chipFg,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                chipText,
                style: TextStyle(
                  fontSize: 10,
                  color: chipFg,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),

        // 이름 + 공고 제목
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0D0D0D),
                  height: 1.2,
                ),
              ),
              if (jobTitle.isNotEmpty) ...[
                const SizedBox(height: 1),
                Text(
                  jobTitle,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF9E9E9E),
                    fontWeight: FontWeight.w400,
                    height: 1.2,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
