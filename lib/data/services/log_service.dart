// 📁 lib/data/services/log_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/constants.dart';

class LogService {
  LogService._();
  static final LogService instance = LogService._();

  static const String click    = 'click';
  static const String apply    = 'apply';
  static const String bookmark = 'bookmark';
  static const String view     = 'view';

  /// 행동 로그 전송 (fire & forget — 실패해도 UI 영향 없음)
  Future<void> logEvent({
    required String eventType,
    required int jobId,
  }) async {
    try {
      final prefs    = await SharedPreferences.getInstance();
      final workerId = prefs.getInt('userId');
      final userType = prefs.getString('userType');

      // 워커만 로그 수집
      if (workerId == null || userType != 'worker') return;

      await http.post(
        Uri.parse('$baseUrl/api/log/event'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'worker_id':  workerId,
          'event_type': eventType,
          'job_id':     jobId,
        }),
      ).timeout(const Duration(seconds: 3));

    } catch (_) {
      // 로그 실패는 조용히 무시
    }
  }
}