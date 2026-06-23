// 📁 lib/data/services/job_insight_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:iljujob/config/constants.dart';

class InsightSubscriptionRequiredException implements Exception {
  const InsightSubscriptionRequiredException();
}

// ════════════════════════════════════════════════════════
//  모델
// ════════════════════════════════════════════════════════

class PayInsight {
  final int    sampleCount;
  final int    avgHourly;
  final int    minHourly;
  final int    maxHourly;
  final int    recommended;
  final int    nationAvg;
  final double avgApplyRate;
  final List<String> messages;
  final String dataSource; // 'local' | 'national'

  const PayInsight({
    required this.sampleCount,
    required this.avgHourly,
    required this.minHourly,
    required this.maxHourly,
    required this.recommended,
    required this.nationAvg,
    required this.avgApplyRate,
    required this.messages,
    required this.dataSource,
  });

  factory PayInsight.fromJson(Map<String, dynamic> j) => PayInsight(
    sampleCount:  (j['sampleCount']  as num?)?.toInt()    ?? 0,
    avgHourly:    (j['hourly']?['avg']        as num?)?.toInt() ?? 10030,
    minHourly:    (j['hourly']?['min']        as num?)?.toInt() ?? 10030,
    maxHourly:    (j['hourly']?['max']        as num?)?.toInt() ?? 15000,
    recommended:  (j['hourly']?['recommended'] as num?)?.toInt() ?? 10030,
    nationAvg:    (j['hourly']?['nationAvg']  as num?)?.toInt() ?? 10030,
    avgApplyRate: (j['avgApplyRate'] as num?)?.toDouble() ?? 0,
    messages:     List<String>.from(j['messages'] ?? []),
    dataSource:   j['dataSource']?.toString() ?? 'national',
  );
}

class QualityScore {
  final int    score;
  final String gradeLabel;
  final String gradeColor;
  final List<QualityTip> tips;
  final List<String>     boosts;
  final int    predictMin;
  final int    predictMax;
  final String predictLabel;

  const QualityScore({
    required this.score,
    required this.gradeLabel,
    required this.gradeColor,
    required this.tips,
    required this.boosts,
    required this.predictMin,
    required this.predictMax,
    required this.predictLabel,
  });

  factory QualityScore.fromJson(Map<String, dynamic> j) => QualityScore(
    score:        (j['score'] as num?)?.toInt() ?? 0,
    gradeLabel:   j['grade']?['label']?.toString() ?? '',
    gradeColor:   j['grade']?['color']?.toString() ?? '#8B95A1',
    tips:         (j['tips'] as List? ?? [])
                    .map((t) => QualityTip.fromJson(t as Map<String, dynamic>))
                    .toList(),
    boosts:       List<String>.from(j['boosts'] ?? []),
    predictMin:   (j['prediction']?['min']  as num?)?.toInt() ?? 1,
    predictMax:   (j['prediction']?['max']  as num?)?.toInt() ?? 3,
    predictLabel: j['prediction']?['label']?.toString() ?? '',
  );
}

class QualityTip {
  final String type;
  final String msg;
  final String impact; // 'critical' | 'high' | 'medium'

  const QualityTip({required this.type, required this.msg, required this.impact});

  factory QualityTip.fromJson(Map<String, dynamic> j) => QualityTip(
    type:   j['type']?.toString()   ?? '',
    msg:    j['msg']?.toString()    ?? '',
    impact: j['impact']?.toString() ?? 'medium',
  );
}

class RepostInsight {
  final int    views, applies, bookmarks;
  final double applyRate;
  final double avgApplyRate;
  final int    avgPay;
  final String performance; // 'great' | 'normal' | 'poor'
  final List<RepostSuggestion> suggestions;
  final int?   improvedPay;

  const RepostInsight({
    required this.views,
    required this.applies,
    required this.bookmarks,
    required this.applyRate,
    required this.avgApplyRate,
    required this.avgPay,
    required this.performance,
    required this.suggestions,
    this.improvedPay,
  });

  factory RepostInsight.fromJson(Map<String, dynamic> j) => RepostInsight(
    views:         (j['stats']?['views']       as num?)?.toInt()    ?? 0,
    applies:       (j['stats']?['applies']     as num?)?.toInt()    ?? 0,
    bookmarks:     (j['stats']?['bookmarks']   as num?)?.toInt()    ?? 0,
    applyRate:     (j['stats']?['applyRate']   as num?)?.toDouble() ?? 0,
    avgApplyRate:  (j['benchmark']?['avgApplyRate'] as num?)?.toDouble() ?? 0,
    avgPay:        (j['benchmark']?['avgPay']  as num?)?.toInt()    ?? 0,
    performance:   j['performance']?.toString() ?? 'normal',
    suggestions:   (j['suggestions'] as List? ?? [])
                     .map((s) => RepostSuggestion.fromJson(s as Map<String, dynamic>))
                     .toList(),
    improvedPay:   (j['improved']?['pay'] as num?)?.toInt(),
  );
}

class RepostSuggestion {
  final String type, icon, title, detail, action, impact;
  const RepostSuggestion({
    required this.type, required this.icon, required this.title,
    required this.detail, required this.action, required this.impact,
  });
  factory RepostSuggestion.fromJson(Map<String, dynamic> j) => RepostSuggestion(
    type:   j['type']?.toString()   ?? '',
    icon:   j['icon']?.toString()   ?? '💡',
    title:  j['title']?.toString()  ?? '',
    detail: j['detail']?.toString() ?? '',
    action: j['action']?.toString() ?? '',
    impact: j['impact']?.toString() ?? 'medium',
  );
}

class JobInsight {
  final int    views, applies, bookmarks;
  final double applyRate;
  final int    peakViewHour;
  final double benchApplyRate;
  final String rateVsBench;   // 'above' | 'normal' | 'below'
  // ✅ 급여 비교
  final int    myHourly;
  final int    avgHourly;
  final String payLevel;      // 'high' | 'normal' | 'low'
  final int    similarCount;
  // ✅ 지원자 비교
  final int    avgApplicants;
  final List<InsightMessage> messages;

  const JobInsight({
    required this.views,
    required this.applies,
    required this.bookmarks,
    required this.applyRate,
    required this.peakViewHour,
    required this.benchApplyRate,
    required this.rateVsBench,
    required this.myHourly,
    required this.avgHourly,
    required this.payLevel,
    required this.similarCount,
    required this.avgApplicants,
    required this.messages,
  });

  factory JobInsight.fromJson(Map<String, dynamic> j) => JobInsight(
    views:          (j['stats']?['views']       as num?)?.toInt()    ?? 0,
    applies:        (j['stats']?['applies']     as num?)?.toInt()    ?? 0,
    bookmarks:      (j['stats']?['bookmarks']   as num?)?.toInt()    ?? 0,
    applyRate:      (j['stats']?['applyRate']   as num?)?.toDouble() ?? 0,
    peakViewHour:   (j['peak']?['viewHour']     as num?)?.toInt()    ?? 0,
    benchApplyRate: (j['benchmark']?['applyRate'] as num?)?.toDouble() ?? 0,
    rateVsBench:    j['benchmark']?['rateVsBench']?.toString() ?? 'normal',
    myHourly:       (j['payComparison']?['myHourly']    as num?)?.toInt() ?? 0,
    avgHourly:      (j['payComparison']?['avgHourly']   as num?)?.toInt() ?? 0,
    payLevel:       j['payComparison']?['payLevel']?.toString() ?? 'normal',
    similarCount:   (j['payComparison']?['similarCount'] as num?)?.toInt() ?? 0,
    avgApplicants:  (j['applicantComparison']?['average'] as num?)?.toInt() ?? 0,
    messages:       (j['messages'] as List? ?? [])
                      .map((m) => InsightMessage.fromJson(m as Map<String, dynamic>))
                      .toList(),
  );
}

class InsightMessage {
  final String icon, text;
  const InsightMessage({required this.icon, required this.text});
  factory InsightMessage.fromJson(Map<String, dynamic> j) => InsightMessage(
    icon: j['icon']?.toString() ?? '💡',
    text: j['text']?.toString() ?? '',
  );
}

// ════════════════════════════════════════════════════════
//  서비스
// ════════════════════════════════════════════════════════
class JobInsightService {

  static Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken') ?? '';
    return {
      'Content-Type': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  // ── 1. 급여 추천 ──────────────────────────────────────
 static Future<PayInsight?> getPayInsight({
  required String category,
  required String locationCity,
  required int    hours,
  String payType = '일급', // ✅ 추가
}) async {
  try {
    final uri = Uri.parse('$baseUrl/api/job/pay-insight').replace(
      queryParameters: {
        'category':     category,
        'locationCity': locationCity,
        'hours':        '$hours',
        'payType':      payType, // ✅ 추가
      },
    );
    final res = await http.get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;
    final d = jsonDecode(res.body) as Map<String, dynamic>;
    return PayInsight.fromJson(d);
  } catch (_) { return null; }
}
  // ── 2. 품질 점수 + 지원자 예측 ────────────────────────
  static Future<QualityScore?> getQualityScore({
    required String title,
    required String category,
    required String locationCity,
    required int    pay,
    required int    hours,
    required String description,
    required bool   isPaid,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/job/quality-score'),
        headers: await _headers(),
        body: jsonEncode({
          'title':        title,
          'category':     category,
          'locationCity': locationCity,
          'pay':          pay,
          'hours':        hours,
          'description':  description,
          'isPaid':       isPaid,
        }),
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final d = jsonDecode(res.body) as Map<String, dynamic>;
      return QualityScore.fromJson(d);
    } catch (_) { return null; }
  }

  // ── 3. 재공고 분석 ────────────────────────────────────
  static Future<RepostInsight?> getRepostInsight(String jobId) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/api/job/$jobId/repost-insight'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final d = jsonDecode(res.body) as Map<String, dynamic>;
      return RepostInsight.fromJson(d);
    } catch (_) { return null; }
  }

  // ── 4. 공고 인사이트 ──────────────────────────────────
  static Future<JobInsight?> getJobInsight(String jobId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/job/$jobId/insight'),
      headers: await _headers(),
    ).timeout(const Duration(seconds: 8));
    if (res.statusCode == 403) throw const InsightSubscriptionRequiredException();
    if (res.statusCode != 200) return null;
    final d = jsonDecode(res.body) as Map<String, dynamic>;
    return JobInsight.fromJson(d);
  }
}