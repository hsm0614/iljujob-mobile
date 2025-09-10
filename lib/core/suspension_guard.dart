// lib/core/suspension_guard.dart
import 'package:flutter/material.dart';
import 'suspension.dart';

bool guardSuspended(BuildContext context, SuspensionState s) {
  if (!s.isSuspended) return true;
  final isPerm = s.isPermanent;
  final msg = isPerm
      ? '영구 정지된 계정은 이용할 수 없습니다. 문의는 1:1 채팅으로 남겨주세요.'
      : '정지 상태에서는 이용할 수 없습니다. 해제 예정: ${s.untilText ?? '-'}';

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
  );
  return false;
}
