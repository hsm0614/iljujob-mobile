// lib/presentation/screens/worker_screen/ai_interview_prep_sheet.dart
//
// AI 면접 준비 도우미 — 서버를 통해 Gemini 호출 (키 노출 방지)
//
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:iljujob/config/constants.dart';

/// 공고 상세에서 호출: showModalBottomSheet
class AiInterviewPrepSheet extends StatefulWidget {
  final String jobTitle;
  final String category;
  final String location;
  final String payType;
  final int pay;

  const AiInterviewPrepSheet({
    super.key,
    required this.jobTitle,
    required this.category,
    required this.location,
    required this.payType,
    required this.pay,
  });

  @override
  State<AiInterviewPrepSheet> createState() => _AiInterviewPrepSheetState();
}

class _AiInterviewPrepSheetState extends State<AiInterviewPrepSheet> {
  bool _loading = true;
  String? _result;
  String? _error;
  bool _isDailyLimit = false;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  Future<void> _generate({int retryCount = 0}) async {
    setState(() {
      _loading = true;
      _result = null;
      _error = null;
      _isDailyLimit = false;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken') ?? '';

      final resp = await http
          .post(
            Uri.parse('$baseUrl/api/ai/interview-prep'),
            headers: {
              'Content-Type': 'application/json',
              if (token.isNotEmpty) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'jobTitle': widget.jobTitle,
              'category': widget.category,
              'location': widget.location,
              'payType': widget.payType,
              'pay': widget.pay,
            }),
          )
          .timeout(const Duration(seconds: 25));

      if (!mounted) return;

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final text = (data['text'] ?? '').toString().trim();
        setState(() {
          _result = text;
          _loading = false;
        });
      } else if (resp.statusCode == 429) {
        final d = jsonDecode(resp.body);
        final isDailyLimit = d['dailyLimitExceeded'] == true;
        if (isDailyLimit) {
          // 일일 한도 초과 → 재시도 의미 없음
          setState(() {
            _error = d['message'] ?? '오늘 사용 한도를 초과했어요.\n내일 다시 시도해주세요.';
            _isDailyLimit = true;
            _loading = false;
          });
        } else if (retryCount < 2) {
          // Gemini 과부하 → 재시도
          await Future.delayed(Duration(seconds: 3 + retryCount * 3));
          if (!mounted) return;
          return _generate(retryCount: retryCount + 1);
        } else {
          setState(() {
            _error = 'AI 요청이 잠시 과부하 상태예요.\n잠시 후 다시 시도해주세요.';
            _loading = false;
          });
        }
      } else {
        String errMsg = '생성에 실패했어요. 다시 시도해주세요.';
        try {
          final d = jsonDecode(resp.body);
          if (d['message'] is String) errMsg = d['message'];
        } catch (_) {}
        setState(() {
          _error = errMsg;
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '네트워크 오류가 발생했어요. 연결을 확인해주세요.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom;

    final maxH = MediaQuery.of(context).size.height * 0.85;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottomPad),
        child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 핸들
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),

            // 헤더
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF3B8AFF), Color(0xFF6C63FF)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded,
                      size: 20, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('AI 면접 준비 도우미',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                    Text(
                      widget.jobTitle,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),

            if (_loading) ...[
              const Center(
                child: Column(
                  children: [
                    SizedBox(height: 24),
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        color: Color(0xFF3B8AFF),
                        strokeWidth: 3,
                      ),
                    ),
                    SizedBox(height: 16),
                    Text('AI가 면접 준비 가이드를 만들고 있어요...',
                        style: TextStyle(color: Colors.black54, fontSize: 13)),
                    SizedBox(height: 6),
                    Text('보통 5~10초 걸려요',
                        style: TextStyle(color: Color(0xFF6B7280), fontSize: 11)),
                    SizedBox(height: 24),
                  ],
                ),
              ),
            ] else if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _isDailyLimit
                      ? Colors.orange.shade50
                      : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _isDailyLimit
                          ? Icons.access_time_rounded
                          : Icons.error_outline,
                      color: _isDailyLimit
                          ? Colors.orange.shade400
                          : Colors.red.shade400,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: _isDailyLimit
                              ? Colors.orange.shade700
                              : Colors.red.shade600,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!_isDailyLimit) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _generate,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('다시 시도'),
                  ),
                ),
              ],
            ] else ...[
              // 결과
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F8FF),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: const Color(0xFF3B8AFF).withOpacity(0.15)),
                ),
                child: Text(
                  _result ?? '',
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.65,
                    color: Color(0xFF1E2A3A),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // 면책 안내
              Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 13, color: Colors.grey.shade400),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      'AI가 생성한 내용이에요. 실제 면접과 다를 수 있어요.',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade400),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // 다시 생성 버튼
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _generate,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('다시 생성',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF3B8AFF),
                    side: BorderSide(
                        color: const Color(0xFF3B8AFF).withOpacity(0.4)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
    );
  }
}
