import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../config/constants.dart';
import '../models/notice.dart';

class NoticeService {
  static Future<List<Notice>> fetchNotices() async {
    final response = await http.get(Uri.parse('$baseUrl/api/notices'));
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((json) => Notice.fromJson(json)).toList();
    } else {
      throw Exception('공지사항 목록 로딩 실패');
    }
  }

  static Future<Notice> fetchNoticeDetail(int id) async {
    final response = await http.get(Uri.parse('$baseUrl/api/notices/$id'));
    if (response.statusCode == 200) {
      return Notice.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('공지사항 상세 로딩 실패');
    }
  }

  static Future<bool> createNotice(String title, String content, String writer) async {
  final response = await http.post(
    Uri.parse('$baseUrl/api/notices/create'), // <-- 여기 수정
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'title': title,
      'content': content,
      'writer': writer,
    }),
  );

  if (response.statusCode == 200) {
    return true;
  } else {
    print('❌ 공지 작성 실패: ${response.body}');
    return false;
  }
}

}
