import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../../config/constants.dart';

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

    final map = Map<String, dynamic>.from(args as Map);

    int parseInt(dynamic v) => v is int ? v : int.tryParse(v?.toString() ?? '') ?? 0;

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
  static const kBrandBlue = Color(0xFF3B8AFF);

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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('이미 이 공고에 리뷰를 남기셨어요.')),
          );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인 정보를 확인할 수 없습니다.')),
      );
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
      final resp = await http.post(
        Uri.parse('$baseUrl/api/review/submit'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (!mounted) return;
      setState(() => isSubmitting = false);

      if (resp.statusCode == 200) {
        Navigator.pop(context, 'reviewed');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('후기가 등록되었습니다!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('후기 등록 실패 (${resp.statusCode})')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('네트워크 오류: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F7FB),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0.5,
          foregroundColor: Colors.black87,
          title: const Text(
            '후기 보내기',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),

        // ✅ 바디는 스크롤 + 하단 고정 CTA가 안전하게 분리됨
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                child: Column(
                  children: [
                    _JobHeaderCard(
                      title: widget.jobTitle,
                      company: widget.companyName,
                      brand: kBrandBlue,
                    ),
                    const SizedBox(height: 12),
                    _SectionCard(
                      title: '일해보니 어땠나요?',
                      child: _SatisfactionRow(
                        value: satisfaction,
                        onChanged: (v) => setState(() => satisfaction = v),
                        brand: kBrandBlue,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SectionCard(
                      title: '얼마나 일하셨나요?',
                      child: _ChoiceWrap(
                        options: const ['채팅', '하루', '1주', '한 달 이내', '한 달 이상'],
                        value: duration,
                        onChanged: (v) => setState(() => duration = v),
                        brand: kBrandBlue,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SectionCard(
                      title: '어떤 점이 기억에 남나요?',
                      subTitle: '중복 선택 가능',
                      child: _TagGroups(
                        selected: tags,
                        onToggle: _toggleTag,
                        brand: kBrandBlue,
                      ),
                    ),
                    const SizedBox(height: 12),
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
                          fillColor: const Color(0xFFF3F5F9),
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
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 16,
                      offset: const Offset(0, -6),
                      color: Colors.black.withOpacity(0.06),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: isSubmitting ? null : () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          side: const BorderSide(color: Color(0xFFE5E7EB)),
                          foregroundColor: Colors.black87,
                        ),
                        child: const Text('나중에', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: (_isValid && !isSubmitting) ? _submitReview : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kBrandBlue,
                          disabledBackgroundColor: const Color(0xFFB7C7FF),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('작성 완료', style: TextStyle(fontWeight: FontWeight.w800)),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            offset: const Offset(0, 8),
            color: Colors.black.withOpacity(0.05),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: brand.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.rate_review_rounded, color: brand),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  company,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String? subTitle;
  final Widget child;

  const _SectionCard({
    required this.title,
    this.subTitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            offset: const Offset(0, 8),
            color: Colors.black.withOpacity(0.05),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          if (subTitle != null) ...[
            const SizedBox(height: 6),
            Text(subTitle!, style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

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
    final items = const [
      ('아쉬워요', '😕', 1),
      ('만족해요', '🙂', 2),
      ('좋아요', '😄', 3),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: items.map((e) {
        final selected = value == e.$3;
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => onChanged(e.$3),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: selected ? brand : const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  alignment: Alignment.center,
                  child: Text(e.$2, style: const TextStyle(fontSize: 26)),
                ),
                const SizedBox(height: 8),
                Text(
                  e.$1,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: selected ? brand : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
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
      children: options.map((opt) {
        final selected = value == opt;
        return ChoiceChip(
          label: Text(opt),
          selected: selected,
          onSelected: (_) => onChanged(opt),
          selectedColor: brand.withOpacity(0.14),
          labelStyle: TextStyle(
            fontWeight: FontWeight.w800,
            color: selected ? brand : Colors.black87,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          side: BorderSide(color: selected ? brand.withOpacity(0.35) : const Color(0xFFE5E7EB)),
          backgroundColor: const Color(0xFFF3F5F9),
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
          children: tags.map((t) {
            final isOn = selected.contains(t);
            return FilterChip(
              label: Text(t),
              selected: isOn,
              onSelected: (_) => onToggle(t),
              selectedColor: brand.withOpacity(0.14),
              labelStyle: TextStyle(
                fontWeight: FontWeight.w800,
                color: isOn ? brand : Colors.black87,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              side: BorderSide(color: isOn ? brand.withOpacity(0.35) : const Color(0xFFE5E7EB)),
              backgroundColor: const Color(0xFFF3F5F9),
              showCheckmark: false,
            );
          }).toList(),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: groups.entries.map((entry) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('• ${entry.key}', style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              chips(entry.value),
            ],
          ),
        );
      }).toList(),
    );
  }
}
