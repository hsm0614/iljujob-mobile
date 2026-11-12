import 'dart:convert';
import 'package:iljujob/config/constants.dart';
import 'authenticated_http_client.dart';

/// 자체 전자 근로계약서 (서버 /api/contracts, 2026-11-12)
class ContractService {
  static Future<({Map<String, dynamic> profile, bool complete, bool available, bool hasCertificate})> profile() async {
    final r = await AuthenticatedHttpClient.get(Uri.parse('$baseUrl/api/contracts/profile'));
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode != 200) throw Exception(body['message'] ?? '불러오지 못했어요');
    return (
      profile: (body['profile'] as Map).cast<String, dynamic>(),
      complete: body['complete'] == true,
      available: body['available'] != false, // 노무사 검토 전엔 내부 계정만(서버 CONTRACTS_PUBLIC)
      hasCertificate: body['hasCertificate'] == true, // 안심기업 서류가 있으면 사진 없이 바로 읽는다
    );
  }

  /// 사업자등록증 → 상호·사업자번호·대표자·주소 초안. image 없으면 안심기업 때 올린 서류를 읽는다
  static Future<Map<String, dynamic>> scanCertificate({String? imageBase64, String? mime}) async {
    final r = await AuthenticatedHttpClient.postJson(
      Uri.parse('$baseUrl/api/contracts/profile/scan'),
      body: {if (imageBase64 != null) 'image': imageBase64, if (mime != null) 'mime': mime},
    );
    final b = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode != 200) throw Exception(b['message'] ?? '사업자등록증을 읽지 못했어요');
    return (b['draft'] as Map).cast<String, dynamic>();
  }

  static Future<void> saveProfile(Map<String, String> p) async {
    final r = await AuthenticatedHttpClient.putJson(Uri.parse('$baseUrl/api/contracts/profile'), body: p);
    if (r.statusCode != 200) throw Exception((jsonDecode(r.body) as Map)['message'] ?? '저장하지 못했어요');
  }

  /// 보내기 전 계약서 미리보기(저장·서명 없음) — 본문은 출근 제안과 같다. 만들 수 없으면 서버 이유로 throw
  static Future<Map<String, dynamic>> preview(Map<String, dynamic> body) async {
    final r = await AuthenticatedHttpClient.postJson(Uri.parse('$baseUrl/api/contracts/preview'), body: body);
    final b = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode != 200) throw Exception(b['message'] ?? '미리보기를 만들지 못했어요');
    return b;
  }

  /// 일주봇 메시지의 '계약서 #번호' — 당사자만, 링크는 10분짜리
  static Future<Map<String, dynamic>?> byId(int id) async {
    final r = await AuthenticatedHttpClient.get(Uri.parse('$baseUrl/api/contracts/$id'));
    if (r.statusCode != 200) return null;
    return ((jsonDecode(r.body) as Map)['contract'] as Map?)?.cast<String, dynamic>();
  }

  /// 근무 카드의 계약서 — 없으면 null
  static Future<Map<String, dynamic>?> forConfirmation(int confirmId) async {
    final r = await AuthenticatedHttpClient.get(Uri.parse('$baseUrl/api/contracts/confirm/$confirmId'));
    if (r.statusCode != 200) return null;
    return ((jsonDecode(r.body) as Map)['contract'] as Map?)?.cast<String, dynamic>();
  }
}
