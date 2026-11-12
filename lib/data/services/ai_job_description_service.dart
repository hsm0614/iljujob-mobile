//services/ai_job_description_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart'; // StatefulWidget 사용을 위해 필요
import 'package:http/http.dart' as http;
import '../../config/constants.dart';
import 'authenticated_http_client.dart';
import '../../config/app_theme.dart';
import '../../widget/app_ui.dart';

class AIJobDescriptionService {
  static Future<({int remaining, String? plan, String yearMonth})>
  fetchQuota() async {
    final response = await AuthenticatedHttpClient.get(
      Uri.parse('$baseUrl/api/ai/job-description/quota'),
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw const AIGenerationException('AI 사용 횟수를 확인할 수 없어요. 잠시 후 다시 시도해주세요.');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (
      remaining: (data['remaining'] as num).toInt(),
      plan: data['plan'] as String?,
      yearMonth: data['yearMonth'] as String,
    );
  }

  /// 글자가 써지듯 받는다 (서버 /job-description/stream, 2026-11). onText에 지금까지 받은 글 전체.
  /// 끝나면 서버가 정리한 최종본을 돌려준다. 예전 서버(404)면 StreamUnavailable — 일반 호출로 넘어간다
  static Future<String> streamJobDescription(
    Map<String, dynamic> body, {
    required void Function(String soFar) onText,
  }) async {
    final token = await AuthenticatedHttpClient.accessToken();
    final req = http.Request('POST', Uri.parse('$baseUrl/api/ai/job-description/stream'))
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
        'Authorization': 'Bearer $token',
      })
      ..body = jsonEncode(body);
    final client = http.Client();
    try {
      final resp = await client.send(req).timeout(const Duration(seconds: 15));
      if (resp.statusCode == 404) throw const StreamUnavailable();
      if (resp.statusCode != 200) {
        final raw = await resp.stream.bytesToString();
        if (resp.statusCode == 401 || resp.statusCode == 403) throw const SubscriptionRequiredException();
        String msg = '공고문 생성에 실패했어요. 다시 시도해주세요.';
        try {
          final d = jsonDecode(raw);
          if (d['message'] is String) msg = d['message'];
        } catch (_) {}
        throw AIGenerationException(msg);
      }
      var soFar = '';
      String? finalText;
      final lines = resp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(const Duration(seconds: 40));
      await for (final line in lines) {
        if (!line.startsWith('data:')) continue;
        final ev = jsonDecode(line.substring(5).trim()) as Map<String, dynamic>;
        if (ev['t'] is String) {
          soFar += ev['t'] as String;
          onText(soFar);
        } else if (ev['done'] == true) {
          finalText = (ev['text'] ?? '').toString().trim();
        } else if (ev['error'] is String) {
          throw AIGenerationException(ev['error'] as String);
        }
      }
      if (finalText == null || finalText.isEmpty) throw const AIGenerationException('AI 응답이 비어 있습니다.');
      return finalText;
    } on TimeoutException {
      throw const AIGenerationException('AI 응답이 늦어요. 잠시 후 다시 시도해주세요.');
    } finally {
      client.close();
    }
  }

  static Map<String, dynamic> requestBody({
    required String title,
    required String category,
    required String location,
    required String payType,
    required int pay,
    String? workingTime,
    List<String>? weekdays,
    String? companyName,
    bool isShortTerm = true,
    String tone = 'friendly',
  }) => {
    'title': title,
    'category': category,
    'location': location,
    'payType': payType,
    'pay': pay,
    'workingTime': workingTime ?? '',
    'weekdays': weekdays ?? [],
    'companyName': companyName ?? '',
    'isShortTerm': isShortTerm,
    'tone': tone,
  };

  /// 사진으로 공고 만들기 — 전단·메모 사진 → 공고 칸 초안(사진에 있는 숫자만). AI 공고 작성 월 횟수 1회 사용
  static Future<Map<String, dynamic>> draftFromPhoto(File photo, List<String> categories) async {
    final bytes = await photo.readAsBytes();
    final lower = photo.path.toLowerCase();
    final resp = await AuthenticatedHttpClient.postJson(
      Uri.parse('$baseUrl/api/ai/job-from-photo'),
      body: {
        'image': base64Encode(bytes),
        'mime': lower.endsWith('.png') ? 'image/png' : 'image/jpeg',
        'categories': categories,
      },
    ).timeout(const Duration(seconds: 45));
    Map<String, dynamic> data = {};
    try {
      data = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {}
    if (resp.statusCode != 200 || data['draft'] is! Map) {
      throw AIGenerationException(data['message']?.toString() ?? '사진을 읽지 못했어요. 다시 시도해주세요.');
    }
    return (data['draft'] as Map).cast<String, dynamic>();
  }

  static Future<String> generateJobDescription({
    required String title,
    required String category,
    required String location,
    required String payType,
    required int pay,
    String? workingTime,
    List<String>? weekdays,
    String? companyName,
    bool isShortTerm = true,
    String tone = 'friendly', // 'friendly', 'professional', 'casual'
    String? managerName,
    String? managerPhone,
  }) async {
    try {
      final response = await AuthenticatedHttpClient.postJson(
        Uri.parse('$baseUrl/api/ai/job-description'),
        body: {
          'title': title,
          'category': category,
          'location': location,
          'payType': payType,
          'pay': pay,
          'workingTime': workingTime ?? '',
          'weekdays': weekdays ?? [],
          'companyName': companyName ?? '',
          'isShortTerm': isShortTerm,
          'tone': tone,
        },
      ).timeout(const Duration(seconds: 35));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = (data['text'] ?? '').toString().trim();
        if (content.isEmpty) {
          throw const AIGenerationException('AI 응답이 비어 있습니다.');
        }
        return content;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw const SubscriptionRequiredException();
      } else if (response.statusCode == 429) {
        String errMsg = 'AI 요청이 잠시 과부하 상태예요. 잠시 후 다시 시도해주세요.';
        try {
          final d = jsonDecode(response.body);
          if (d['message'] is String) errMsg = d['message'];
        } catch (_) {}
        throw AIGenerationException(errMsg);
      } else {
        String errMsg = '공고문 생성에 실패했어요. 다시 시도해주세요.';
        try {
          final d = jsonDecode(response.body);
          if (d['message'] is String) errMsg = d['message'];
        } catch (_) {}
        throw AIGenerationException(errMsg);
      }
    } catch (e) {
      if (e is AIGenerationException) rethrow;
      throw AIGenerationException('공고문 생성 중 오류가 발생했습니다: $e');
    }
  }

  // 공고문 품질 검증
  static AIQualityReport validateDescription(String description) {
    final issues = <String>[];
    final suggestions = <String>[];

    // 길이 검증
    if (description.length < 100) {
      issues.add('공고문이 너무 짧습니다 (현재: ${description.length}자)');
      suggestions.add('업무내용과 근무환경에 대한 설명을 더 자세히 추가해보세요');
    } else if (description.length > 800) {
      issues.add('공고문이 너무 깁니다 (현재: ${description.length}자)');
      suggestions.add('핵심 내용만 간결하게 정리해보세요');
    }

    // 차별적 표현 검증
    final discriminatoryWords = ['남자만', '여자만', '젊은', '예쁜', '잘생긴'];
    for (final word in discriminatoryWords) {
      if (description.contains(word)) {
        issues.add('차별적 표현("$word")이 포함되어 있습니다');
        suggestions.add('성별, 외모 관련 차별적 표현을 제거해주세요');
      }
    }

    return AIQualityReport(
      issues: issues,
      suggestions: suggestions,
    );
  }
}

// 예외 처리 클래스
class AIGenerationException implements Exception {
  final String message;
  const AIGenerationException(this.message);

  @override
  String toString() => 'AIGenerationException: $message';
}

class SubscriptionRequiredException implements Exception {
  const SubscriptionRequiredException();
  @override
  String toString() => 'SubscriptionRequiredException';
}

// 품질 평가 결과 클래스
class AIQualityReport {
  final List<String> issues;
  final List<String> suggestions;

  const AIQualityReport({
    required this.issues,
    required this.suggestions,
  });

  bool get hasIssues => issues.isNotEmpty;
}

// 프리셋 관리 클래스
// AI 공고문 생성 위젯
class AIJobDescriptionWidget extends StatefulWidget {
  final String title;
  final String category;
  final String location;
  final String payType;
  final int pay;
  final String? workingTime;
  final List<String>? weekdays;
  final String? companyName;
  final bool isShortTerm;
  final Function(String) onGenerated;
  final VoidCallback? onClose;
  final String? managerName; // 추가
  final String? managerPhone; // 추가

  const AIJobDescriptionWidget({
    super.key,
    required this.title,
    required this.category,
    required this.location,
    required this.payType,
    required this.pay,
    this.workingTime,
    this.weekdays,
    this.companyName,
    required this.isShortTerm,
    required this.onGenerated,
    this.onClose,
    this.managerName, // 추가
    this.managerPhone, // 추가
  });

  @override
  State<AIJobDescriptionWidget> createState() => _AIJobDescriptionWidgetState();
}

class _AIJobDescriptionWidgetState extends State<AIJobDescriptionWidget> {
  bool isGenerating = false;
  String? generatedContent;
  AIQualityReport? qualityReport;

  @override
  Widget build(BuildContext context) {
    final content = generatedContent;
    final issues = qualityReport?.issues ?? const <String>[];
    return Material(
      color: AppColors.bgCard,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 12 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('공고문 대신 써 드려요', style: AppTextStyles.h2)),
                  if (widget.onClose != null)
                    IconButton(
                      tooltip: '닫기',
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                    ),
                ],
              ),
              Text(
                content == null ? '앞에서 입력한 내용으로 써요. 받아 보고 고칠 수 있어요.' : '마음에 들면 넣고, 아니면 다시 써 볼 수 있어요.',
                style: AppTextStyles.body2,
              ),
              const SizedBox(height: 20),
              if (content != null) ...[
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.bgMuted,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: SingleChildScrollView(
                      reverse: isGenerating, // 쓰는 중엔 새 글이 보이게 아래에 붙는다
                      child: Text(isGenerating ? '$content ▍' : content,
                          style: AppTextStyles.body1.copyWith(height: 1.6, color: AppColors.textPrimary)),
                    ),
                  ),
                ),
                // 차별 표현·길이 문제만 — 있을 때만 한 줄씩
                for (final issue in issues)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(issue, style: AppTextStyles.body2.copyWith(color: AppColors.error)),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.bgMuted,
                            foregroundColor: AppColors.textPrimary,
                          ),
                          onPressed: isGenerating ? null : _generateDescription,
                          child: const Text('다시 쓰기'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: AppPrimaryButton(
                        label: '이 내용 넣기',
                        onPressed: isGenerating ? null : () => widget.onGenerated(content),
                      ),
                    ),
                  ],
                ),
              ] else
                AppPrimaryButton(
                  label: isGenerating ? '쓰는 중이에요…' : '써 보기',
                  loading: isGenerating,
                  onPressed: _generateDescription,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _generateDescription() async {
    setState(() {
      isGenerating = true;
      generatedContent = null;
      qualityReport = null;
    });

    try {
      final body = AIJobDescriptionService.requestBody(
        title: widget.title,
        category: widget.category,
        location: widget.location,
        payType: widget.payType,
        pay: widget.pay,
        workingTime: widget.workingTime,
        weekdays: widget.weekdays,
        companyName: widget.companyName,
        isShortTerm: widget.isShortTerm,
      );
      String content;
      try {
        // 받는 대로 보여 준다 — 다 쓸 때까지 빈 화면으로 기다리지 않게
        content = await AIJobDescriptionService.streamJobDescription(
          body,
          onText: (soFar) {
            if (mounted) setState(() => generatedContent = soFar);
          },
        );
      } on StreamUnavailable {
        content = await AIJobDescriptionService.generateJobDescription(
          title: widget.title,
          category: widget.category,
          location: widget.location,
          payType: widget.payType,
          pay: widget.pay,
          workingTime: widget.workingTime,
          weekdays: widget.weekdays,
          companyName: widget.companyName,
          isShortTerm: widget.isShortTerm,
          tone: 'friendly',
        );
      }

      final report = AIJobDescriptionService.validateDescription(content);

      setState(() {
        generatedContent = content;
        qualityReport = report;
      });
    } on SubscriptionRequiredException {
      if (mounted) _showSubscriptionGate(context);
    } catch (e) {
      if (mounted) {
        setState(() => generatedContent = null); // 쓰다 끊긴 글은 넣지 않게
        final msg =
            e is AIGenerationException ? e.message : '공고문을 쓰지 못했어요. 잠시 후 다시 시도해 주세요.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted)
        setState(() {
          isGenerating = false;
        });
    }
  }

  Future<void> _showSubscriptionGate(BuildContext ctx) async {
    final go = await showAppSheet(
      ctx,
      title: '구독하면 쓸 수 있어요',
      message: '공고문 대신 써 주기는 베이직 월 3회, 무제한은 횟수 제한 없이 쓸 수 있어요.',
      confirmLabel: '구독 플랜 보기',
      cancelLabel: '닫기',
    );
    if (go && ctx.mounted) Navigator.pushNamed(ctx, '/subscribe', arguments: 'ai_quota');
  }
}

/// 서버에 스트리밍 경로가 없을 때(구버전 서버) — 일반 호출로 넘어간다
class StreamUnavailable implements Exception {
  const StreamUnavailable();
}
