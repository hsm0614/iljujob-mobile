// 📁 lib/data/services/notificaion_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/constants.dart';
import 'authenticated_http_client.dart';

class NotificationService {
  /// 알림 설정 불러오기
  static Future<Map<String, dynamic>?> fetchSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId');
    final userType = prefs.getString('userType');

    if (userId == null || userType == null) return null;

    try {
      final response = await AuthenticatedHttpClient.get(
        Uri.parse(
          '$baseUrl/api/notification-settings?userId=$userId&userType=$userType',
        ),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print('❌ 알림 설정 불러오기 실패: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ 네트워크 오류: $e');
      return null;
    }
  }

  /// 알림 설정 업데이트
  static Future<bool> updateSettings(Map<String, dynamic> settings) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId');
    final userType = prefs.getString('userType');

    if (userId == null || userType == null) return false;

    try {
      final response = await AuthenticatedHttpClient.postJson(
        Uri.parse('$baseUrl/api/notification-settings/update'),
        body: {'userId': userId, 'userType': userType, ...settings},
      );

      return response.statusCode == 200;
    } catch (e) {
      print('❌ 알림 설정 저장 실패: $e');
      return false;
    }
  }
}
