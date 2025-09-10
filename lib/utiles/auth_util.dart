import 'package:shared_preferences/shared_preferences.dart';

Future<String?> _getTokenCompat() async {
  final prefs = await SharedPreferences.getInstance();
  // 1순위: accessToken (신규)
  String? t = prefs.getString('accessToken');
  // 2순위: authToken (기존)
  t ??= prefs.getString('authToken');
  t = t?.trim();
  if (t == null || t.isEmpty) return null;

  // ✅ 읽을 때 자동 마이그레이션(accessToken에 통일 저장)
  await prefs.setString('accessToken', t);
  return t;
}

Future<Map<String, String>> authHeaders() async {
  final t = await _getTokenCompat();
  if (t == null) throw Exception('NOT_AUTHENTICATED');
  return {
    'Authorization': 'Bearer $t',
    'Content-Type': 'application/json',
  };
}
