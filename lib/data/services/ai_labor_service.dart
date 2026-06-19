// 📁 lib/data/services/ai_labor_service.dart
// 노무상담 + 자연어검색 + 자소서 AI 서비스

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:iljujob/config/constants.dart';
import 'package:iljujob/data/models/job.dart';

class SubscriptionRequiredException implements Exception {
  const SubscriptionRequiredException();
  @override
  String toString() => 'SubscriptionRequiredException';
}

// ── 임금 리포트 모델 ─────────────────────────────────────────────
class WageReport {
  final String category;
  final String locationCity;
  final String payType;
  final int sampleLocal;
  final int sampleNation;
  final int? currentHourly;
  final int avgHourly;
  final int minHourly;
  final int maxHourly;
  final int p25;
  final int p75;
  final int highApply;
  final int nationAvg;
  final int recommendedHourly;
  final int recommendedPay;
  final int? percentile;
  final int? applyRateUplift;
  final String aiAnalysis;
  final bool cached;

  const WageReport({
    required this.category,
    required this.locationCity,
    required this.payType,
    required this.sampleLocal,
    required this.sampleNation,
    this.currentHourly,
    required this.avgHourly,
    required this.minHourly,
    required this.maxHourly,
    required this.p25,
    required this.p75,
    required this.highApply,
    required this.nationAvg,
    required this.recommendedHourly,
    required this.recommendedPay,
    this.percentile,
    this.applyRateUplift,
    required this.aiAnalysis,
    this.cached = false,
  });

  factory WageReport.fromJson(Map<String, dynamic> j) {
    final h = j['hourly'] as Map? ?? {};
    final sc = j['sampleCount'] as Map? ?? {};
    return WageReport(
      category:         j['category']?.toString() ?? '',
      locationCity:     j['locationCity']?.toString() ?? '전국',
      payType:          j['payType']?.toString() ?? '시급',
      sampleLocal:      (sc['local'] as num?)?.toInt() ?? 0,
      sampleNation:     (sc['nation'] as num?)?.toInt() ?? 0,
      currentHourly:    (h['current'] as num?)?.toInt(),
      avgHourly:        (h['avg'] as num?)?.toInt() ?? 10030,
      minHourly:        (h['min'] as num?)?.toInt() ?? 10030,
      maxHourly:        (h['max'] as num?)?.toInt() ?? 10030,
      p25:              (h['p25'] as num?)?.toInt() ?? 10030,
      p75:              (h['p75'] as num?)?.toInt() ?? 10030,
      highApply:        (h['highApply'] as num?)?.toInt() ?? 10030,
      nationAvg:        (h['nationAvg'] as num?)?.toInt() ?? 10030,
      recommendedHourly:(h['recommended'] as num?)?.toInt() ?? 10030,
      recommendedPay:   (j['recommendedPay'] as num?)?.toInt() ?? 10030,
      percentile:       (j['percentile'] as num?)?.toInt(),
      applyRateUplift:  (j['applyRateUplift'] as num?)?.toInt(),
      aiAnalysis:       j['aiAnalysis']?.toString() ?? '',
      cached:           j['cached'] == true,
    );
  }
}

class AiLaborService {
  static Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken') ?? '';
    return {
      'Content-Type': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  // ── 노무 상담 ────────────────────────────────────────────────────
  static Future<({String answer, int remaining})> laborConsult({
    required String question,
    List<Map<String, String>> history = const [],
  }) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/ai/labor-consult'),
      headers: await _headers(),
      body: jsonEncode({'question': question, 'history': history}),
    ).timeout(const Duration(seconds: 20));

    final data = jsonDecode(utf8.decode(resp.bodyBytes));
    if (data['ok'] != true) throw data['message'] ?? '오류';
    return (answer: data['answer'] as String, remaining: (data['remaining'] as num).toInt());
  }

  // ── 자연어 검색 ──────────────────────────────────────────────────
  static Future<({List<Job> jobs, int total, Map filters})> naturalSearch({
    required String query,
    double? lat,
    double? lng,
  }) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/ai/search'),
      headers: await _headers(),
      body: jsonEncode({'query': query, 'lat': lat, 'lng': lng}),
    ).timeout(const Duration(seconds: 15));

    final data = jsonDecode(utf8.decode(resp.bodyBytes));
    if (data['ok'] != true) throw data['message'] ?? '검색 실패';

    final rawList = (data['jobs'] as List?) ?? [];
    final jobs = rawList.map((j) => Job.fromJson(j as Map<String, dynamic>)).toList();
    return (
      jobs: jobs,
      total: (data['total'] as num).toInt(),
      filters: data['filters'] as Map? ?? {},
    );
  }

  // ── 임금 AI 리포트 ───────────────────────────────────────────────
  static Future<WageReport> getWageReport({
    required String category,
    String? locationCity,
    String payType = '시급',
    int? pay,
    int hours = 8,
    int? jobId,
  }) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/ai/wage-report'),
      headers: await _headers(),
      body: jsonEncode({
        'category': category,
        if (locationCity != null) 'locationCity': locationCity,
        'payType': payType,
        if (pay != null) 'pay': pay,
        'hours': hours,
        if (jobId != null) 'jobId': jobId,
      }),
    ).timeout(const Duration(seconds: 20));

    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw const SubscriptionRequiredException();
    }

    final data = jsonDecode(utf8.decode(resp.bodyBytes));
    if (data['ok'] != true) throw data['message'] ?? '분석 실패';
    return WageReport.fromJson(data);
  }

  // ── 자기소개서 생성 ──────────────────────────────────────────────
  static Future<({String text, int remaining})> generateCoverLetter({
    required String jobTitle,
    required String category,
    String? location,
    int? pay,
    String? payType,
    int? workerAge,
    String? workerGender,
    String? experience,
  }) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/ai/cover-letter'),
      headers: await _headers(),
      body: jsonEncode({
        'jobTitle': jobTitle,
        'category': category,
        if (location != null) 'location': location,
        if (pay != null) 'pay': pay,
        if (payType != null) 'payType': payType,
        if (workerAge != null) 'workerAge': workerAge,
        if (workerGender != null) 'workerGender': workerGender,
        if (experience != null) 'experience': experience,
      }),
    ).timeout(const Duration(seconds: 20));

    final data = jsonDecode(utf8.decode(resp.bodyBytes));
    if (data['ok'] != true) throw data['message'] ?? '생성 실패';
    return (text: data['text'] as String, remaining: (data['remaining'] as num).toInt());
  }
}
