import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:iljujob/widget/app_motion.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../../config/constants.dart';
import '../../data/services/authenticated_http_client.dart';
import '../../config/app_theme.dart';
import '../../config/messages.dart';

class ReviewScreen extends StatefulWidget {
  final int jobId;
  final int clientId;
  final String jobTitle;
  final String companyName;

  const ReviewScreen({
    super.key,
    required this.jobId,
    required this.clientId,
    required this.jobTitle,
    required this.companyName,
  });

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class ReviewScreenRouter extends StatelessWidget {
  const ReviewScreenRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is! Map) {
      return const Scaffold(body: Center(child: Text('잘못된 접근입니다.')));
    }

    final map = Map<String, dynamic>.from(args);

    int parseInt(dynamic v) =>
        v is int ? v : int.tryParse(v?.toString() ?? '') ?? 0;

    final jobId = parseInt(map['jobId']);
    final clientId = parseInt(map['clientId']);
    final jobTitle = (map['jobTitle']?.toString() ?? '').trim();
    final companyName = (map['companyName']?.toString() ?? '').trim();

    if (jobId == 0 || clientId == 0 || jobTitle.isEmpty) {
      return const Scaffold(body: Center(child: Text('잘못된 접근입니다.')));
    }

    return ReviewScreen(
      jobId: jobId,
      clientId: clientId,
      jobTitle: jobTitle,
      companyName: companyName.isEmpty ? '회사명 없음' : companyName,
    );
  }
}

class _ReviewScreenState extends State<ReviewScreen> {
  static const kBrandBlue = AppColors.primary;

  int satisfaction = 0; // 1,2,3
  String duration = '';
  final Set<String> tags = {};
  final TextEditingController commentController = TextEditingController();
  bool isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _checkIfAlreadyReviewed();
  }

  @override
  void dispose() {
    commentController.dispose();
    super.dispose();
  }

  bool get _isValid => satisfaction > 0 && duration.isNotEmpty;

  void _toggleTag(String tag) {
    setState(() {
      if (tags.contains(tag)) {
        tags.remove(tag);
      } else {
        tags.add(tag);
      }
    });
  }

  Future<void> _checkIfAlreadyReviewed() async {
    final prefs = await SharedPreferences.getInstance();
    final workerId = prefs.getInt('userId') ?? 0;
    if (workerId == 0) return;

    // ✅ 네 ChatRoomScreen에서 쓰던 엔드포인트와 "동일하게" 맞추는 게 안전
    final url = Uri.parse(
      '$baseUrl/api/review/has-reviewed?clientId=${widget.clientId}&workerId=$workerId&jobTitle=${Uri.encodeComponent(widget.jobTitle)}',
    );

    try {
      final resp = await http.get(url);
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is Map && data['hasReviewed'] == true) {
          Navigator.pop(context);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('이미 이 공고에 리뷰를 남기셨어요.')));
        }
      }
    } catch (_) {}
  }

  Future<void> _submitReview() async {
    if (!_isValid || isSubmitting) return;

    setState(() => isSubmitting = true);

    final prefs = await SharedPreferences.getInstance();
    final workerId = prefs.getInt('userId') ?? 0;

    if (!mounted) return;
    if (workerId == 0) {
      setState(() => isSubmitting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(Msg.loginRequired)));
      return;
    }

    final body = {
      'jobId': widget.jobId, // ✅ 추가 (서버가 쓰기 더 좋음)
      'clientId': widget.clientId,
      'workerId': workerId,
      'jobTitle': widget.jobTitle,
      'satisfaction': satisfaction,
      'duration': duration,
      'tags': tags.toList(),
      'comment': commentController.text.trim(),
    };

    try {
      final resp = await AuthenticatedHttpClient.postJson(
        Uri.parse('$baseUrl/api/review/submit'),
        body: body,
      );

      if (!mounted) return;
      setState(() => isSubmitting = false);

      if (resp.statusCode == 200) {
        await showAppSuccess(
          context,
          title: '후기를 남겼어요',
          message: '다른 알바생이 이 가게를 고를 때 도움이 돼요.',
          primaryLabel: '확인',
        );
        if (!mounted) return;
        Navigator.pop(context, 'reviewed');
      } else {
        // 서버가 거절 이유를 주면 그대로 (예: '근무일이 지난 뒤에 후기를 남길 수 있어요.')
        String msg = Msg.reviewFailed;
        try {
          final m = jsonDecode(resp.body)['message'];
          if (resp.statusCode == 403 && m is String && m.isNotEmpty) msg = m;
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => isSubmitting = false);
      debugPrint('후기 등록 네트워크 오류: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(Msg.network)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.bgPage,
        appBar: AppBar(
          backgroundColor: Colors.white,
          title: const Text('후기 보내기'),
          leading: IconButton(
            tooltip: '뒤로',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),

        // ✅ 바디는 스크롤 + 하단 고정 CTA가 안전하게 분리됨
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(top: 8, bottom: 24),
                child: Column(
                  children: [
                    _JobHeaderCard(
                      title: widget.jobTitle,
                      company: widget.companyName,
                      brand: kBrandBlue,
                    ),
                    const SizedBox(height: 8),
                    _SectionCard(
                      title: '일해보니 어땠나요?',
                      child: _SatisfactionRow(
                        value: satisfaction,
                        onChanged: (v) => setState(() => satisfaction = v),
                        brand: kBrandBlue,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _SectionCard(
                      title: '얼마나 일하셨나요?',
                      child: _ChoiceWrap(
                        options: const ['채팅', '하루', '1주', '한 달 이내', '한 달 이상'],
                        value: duration,
                        onChanged: (v) => setState(() => duration = v),
                        brand: kBrandBlue,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _SectionCard(
                      title: '어떤 점이 기억에 남나요?',
                      subTitle: '중복 선택 가능',
                      child: _TagGroups(
                        selected: tags,
                        onToggle: _toggleTag,
                        brand: kBrandBlue,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _SectionCard(
                      title: '한 줄 후기',
                      subTitle: '불쾌감을 줄 수 있는 내용은 제재 대상이 될 수 있어요.',
                      child: TextField(
                        controller: commentController,
                        maxLines: 4,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText: '예) 설명이 친절했고 급여도 제때 주셨어요.',
                          filled: true,
                          fillColor: AppColors.bgMuted,
                          contentPadding: const EdgeInsets.all(14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: bottomInset > 0 ? 12 : 0),
                  ],
                ),
              ),
            ),

            // ✅ Android 뒤로가기/제스처/홈바 영역 침범 방지: SafeArea + padding
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: const BoxDecoration(
                  color: AppColors.bgCard,
                  border: Border(top: BorderSide(color: AppColors.borderSub)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            isSubmitting ? null : () => Navigator.pop(context),
                        child: const Text(
                          '나중에'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed:
                            (_isValid && !isSubmitting) ? _submitReview : null,
                        child:
                            isSubmitting
                                ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                                : const Text(
                                  '작성 완료'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ======================= UI Components =======================

class _JobHeaderCard extends StatelessWidget {
  final String title;
  final String company;
  final Color brand;

  const _JobHeaderCard({
    required this.title,
    required this.company,
    required this.brand,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.bgCard,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (company.isNotEmpty) ...[Text(company, style: AppTextStyles.body2), const SizedBox(height: 2)],
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTextStyles.h3),
        ],
      ),
    );
  }
}

// 테두리 카드(굵기 w900) → 화면 폭 흰 블록, 사이 8px 회색 띠 (다른 화면과 같은 문법)
class _SectionCard extends StatelessWidget {
  final String title;
  final String? subTitle;
  final Widget child;

  const _SectionCard({required this.title, this.subTitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.bgCard,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.h3),
          if (subTitle != null) ...[
            const SizedBox(height: 4),
            Text(subTitle!, style: AppTextStyles.body2),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// 만족도 — 이모지 얼굴 3개(화면 이모지 금지 규칙) → 글자 세 칸, 고른 칸은 큰 선택 규칙(연파랑+파란 테두리)
class _SatisfactionRow extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final Color brand;

  const _SatisfactionRow({
    required this.value,
    required this.onChanged,
    required this.brand,
  });

  @override
  Widget build(BuildContext context) {
    const items = [('아쉬워요', 1), ('만족해요', 2), ('좋아요', 3)];
    return Row(
      children: [
        for (final (label, v) in items) ...[
          if (v != 1) const SizedBox(width: 8),
          Expanded(
            child: Material(
              color: value == v ? AppColors.primaryLight : AppColors.bgCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                side: BorderSide(color: value == v ? AppColors.primary : AppColors.border, width: value == v ? 1.5 : 1),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.md),
                onTap: () => onChanged(v),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(
                      label,
                      style: AppTextStyles.body1.copyWith(
                        fontWeight: value == v ? FontWeight.w700 : FontWeight.w500,
                        color: value == v ? AppColors.primary : AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ChoiceWrap extends StatelessWidget {
  final List<String> options;
  final String value;
  final ValueChanged<String> onChanged;
  final Color brand;

  const _ChoiceWrap({
    required this.options,
    required this.value,
    required this.onChanged,
    required this.brand,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children:
          options.map((opt) {
            final selected = value == opt;
            return ChoiceChip(
              label: Text(opt),
              selected: selected,
              onSelected: (_) => onChanged(opt),
              selectedColor: brand.withOpacity(0.14),
              labelStyle: TextStyle(
                fontWeight: FontWeight.w800,
                color: selected ? brand : AppColors.textPrimary,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              side: BorderSide(
                color:
                    selected
                        ? brand.withOpacity(0.35)
                        : AppColors.border,
              ),
              backgroundColor: AppColors.bgMuted,
            );
          }).toList(),
    );
  }
}

class _TagGroups extends StatelessWidget {
  final Set<String> selected;
  final void Function(String) onToggle;
  final Color brand;

  const _TagGroups({
    required this.selected,
    required this.onToggle,
    required this.brand,
  });

  @override
  Widget build(BuildContext context) {
    const groups = {
      '일하는 환경': ['휴게공간이 있어요', '식사/간식을 챙겨줘요', '분위기가 좋아요'],
      '급여/계약': ['급여를 제때 줘요', '계약서를 작성했어요', '계약 내용을 지키지 않았어요'],
      '업무 경험': ['친절했어요', '일이 설명과 달라요', '존중해줬어요'],
    };

    Widget chips(List<String> tags) => Wrap(
      spacing: 8,
      runSpacing: 8,
      children:
          tags.map((t) {
            final isOn = selected.contains(t);
            return FilterChip(
              label: Text(t),
              selected: isOn,
              onSelected: (_) => onToggle(t),
              selectedColor: brand.withOpacity(0.14),
              labelStyle: TextStyle(
                fontWeight: FontWeight.w800,
                color: isOn ? brand : AppColors.textPrimary,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              side: BorderSide(
                color: isOn ? brand.withOpacity(0.35) : AppColors.border,
              ),
              backgroundColor: AppColors.bgMuted,
              showCheckmark: false,
            );
          }).toList(),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children:
          groups.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• ${entry.key}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  chips(entry.value),
                ],
              ),
            );
          }).toList(),
    );
  }
}
