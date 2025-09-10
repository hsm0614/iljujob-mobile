// lib/widgets/suspension_banner.dart
import 'package:flutter/material.dart';
import '../core/suspension.dart';

class SuspensionBanner extends StatelessWidget {
  final SuspensionState state;
  const SuspensionBanner({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    if (!state.isSuspended) return const SizedBox.shrink();
    final isPerm = state.isPermanent;
    final text = isPerm
        ? '계정이 영구 정지되었습니다. 문의는 1:1 채팅으로 남겨주세요.'
        : '계정이 일시 정지되었습니다. 해제 예정: ${state.untilText ?? '-'}';
    return Material(
      color: isPerm ? Colors.red.withOpacity(0.12) : Colors.orange.withOpacity(0.12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(isPerm ? Icons.block : Icons.lock_clock, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
            TextButton(
              onPressed: () {
                // 시스템 DM 방으로 이동 (jobId=0 방)
                Navigator.of(context).pushNamed('/chat/system');
              },
              child: const Text('문의'),
            ),
          ],
        ),
      ),
    );
  }
}
