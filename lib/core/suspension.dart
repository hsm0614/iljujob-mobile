// lib/core/suspension.dart
import 'package:intl/intl.dart';

class SuspensionState {
  final String? suspendedType;   // 'temporary' | 'permanent' | null
  final String? suspendedUntil;  // 'YYYY-MM-DDTHH:mm:ss' (서버 포맷)
  final String? suspendedReason; // nullable

  const SuspensionState({
    required this.suspendedType,
    required this.suspendedUntil,
    required this.suspendedReason,
  });

  bool get isPermanent => (suspendedType ?? '').toLowerCase() == 'permanent';

  DateTime? get until {
    final u = suspendedUntil;
    if (u == null || u.isEmpty) return null;
    // 서버가 'YYYY-MM-DDTHH:mm:ss' 주면 로컬로 파싱
    try {
      return DateTime.parse(u); // ← timezone 없는 문자열이면 local로 들어옴
    } catch (_) {
      return null;
    }
  }

  bool get isTemporaryActive {
    if ((suspendedType ?? '').toLowerCase() != 'temporary') return false;
    final dt = until;
    if (dt == null) return false;
    return dt.isAfter(DateTime.now());
  }

  bool get isSuspended => isPermanent || isTemporaryActive;

  String? get untilText {
    final dt = until;
    if (dt == null) return null;
    // KST 표기 (현지 시간권 쓰면 됨. 필요하면 Asia/Seoul 로컬라이즈)
    final f = DateFormat('yyyy-MM-dd HH:mm');
    return f.format(dt);
  }

  String get label {
    if (isPermanent) return '영구 정지';
    if (isTemporaryActive) {
      final u = untilText;
      return u == null ? '임시 정지' : '임시 정지 ~ $u';
    }
    return '정상';
  }
}
