import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../config/app_theme.dart';

/// 자주 묻는 질문 (2026-10 리디자인 — 토스 고객센터 FAQ 참고).
/// 알약 탭·그림자 카드 → 분류 칩 + 검색 + 흰 줄 펼치기.
/// 답이 실제와 달라진 것(공고 무료 → 유료 상품 있음, 지원 취소 위치)도 고쳤다.
class FaqScreen extends StatefulWidget {
  const FaqScreen({super.key});

  @override
  State<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends State<FaqScreen> {
  static const _all = [
    ('공통', '가입은 무료인가요?', '네, 가입과 공고 보기·지원·채팅은 모두 무료예요.'),
    (
      '공통',
      '제 전화번호가 상대에게 보이나요?',
      '아니요. 사장님과 알바생은 앱 채팅으로 이야기해요. 긴급 호출도 앱 메시지로 가서 번호가 공개되지 않아요.',
    ),
    (
      '공통',
      '고객센터는 어떻게 연락하나요?',
      '마이 > 고객센터 > 1:1 문의하기로 남기거나 hsm@outfind.co.kr로 메일 주세요.',
    ),
    (
      '알바생',
      '지원을 취소할 수 있나요?',
      '내 활동에서 공고 오른쪽 ⋯ 을 눌러 취소할 수 있어요. 출근을 약속한 뒤 취소하면 신뢰도가 3점 깎여요.',
    ),
    (
      '알바생',
      '급여는 언제 받나요?',
      '사장님이 공고에 적은 지급 방식(당일 지급·주급 등)에 따라 받아요. 공고 상세의 급여 칸을 확인해 주세요.',
    ),
    (
      '알바생',
      '신뢰도 점수는 어떻게 오르나요?',
      '앱에 접속하고, 사장님 메시지에 답하고, 약속한 날 출근하면 올라요. 노쇼는 10점이 깎여요. 점수가 높을수록 사장님 후보 목록 위쪽에 보여요.',
    ),
    (
      '알바생',
      "'오늘 가능'은 뭔가요?",
      '홈에서 오늘 가능을 켜면 오늘 급하게 사람을 찾는 사장님께 먼저 보여요.',
    ),
    (
      '사장님',
      '공고 올리는 데 비용이 드나요?',
      '일반 게시는 무료이고 등록 12시간 뒤 노출돼요. 바로 노출하려면 즉시 게시(4,900원), 근처 알바생에게 직접 연락하려면 긴급 호출(7,900원)을 쓰면 돼요.',
    ),
    (
      '사장님',
      '긴급 호출에 아무도 답하지 않으면요?',
      '응답한 알바생이 한 명도 없으면 이용권이 자동으로 돌아와요.',
    ),
    (
      '사장님',
      '알바생이 노쇼하면요?',
      '노쇼가 확정되면 즉시 게시 이용권 1개를 자동으로 돌려드려요.',
    ),
  ];

  String _cat = '전체';
  String _q = '';

  @override
  void initState() {
    super.initState();
    // 내 역할 질문을 먼저 — 사장님에게 알바생 질문부터 보이지 않게
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      final type = p.getString('userType');
      if (type == 'client') setState(() => _cat = '사장님');
      if (type == 'worker') setState(() => _cat = '알바생');
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _q.trim();
    final items =
        _all
            .where((e) => _cat == '전체' || e.$1 == _cat || e.$1 == '공통')
            .where((e) => s.isEmpty || e.$2.contains(s) || e.$3.contains(s))
            .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('자주 묻는 질문')),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          Container(
            color: AppColors.bgCard,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Column(
              children: [
                TextField(
                  onChanged: (v) => setState(() => _q = v),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: '궁금한 내용을 검색해 보세요',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: AppColors.bgMuted,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (final c in const ['전체', '알바생', '사장님'])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(c),
                          selected: _cat == c,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => _cat = c),
                          labelStyle: AppTextStyles.btnMd.copyWith(
                            color:
                                _cat == c
                                    ? Colors.white
                                    : AppColors.textSecondary,
                          ),
                          selectedColor: AppColors.textPrimary,
                          backgroundColor: AppColors.bgMuted,
                          side: BorderSide.none,
                          shape: const StadiumBorder(),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            color: AppColors.bgCard,
            child:
                items.isEmpty
                    ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: Text(
                        "'$s'에 맞는 질문이 없어요.\n고객센터 1:1 문의로 물어봐 주세요.",
                        textAlign: TextAlign.center,
                        style: AppTextStyles.body2,
                      ),
                    )
                    : Column(
                      children: [
                        for (final (_, q, a) in items)
                          _FaqRow(
                            key: ValueKey(q),
                            question: q,
                            answer: a,
                          ),
                      ],
                    ),
          ),
        ],
      ),
    );
  }
}

class _FaqRow extends StatefulWidget {
  final String question;
  final String answer;
  const _FaqRow({
    super.key,
    required this.question,
    required this.answer,
  });

  @override
  State<_FaqRow> createState() => _FaqRowState();
}

class _FaqRowState extends State<_FaqRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderSub)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Q',
                    style: AppTextStyles.jobTitle.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(widget.question, style: AppTextStyles.jobTitle),
                  ),
                  Icon(
                    _open
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: AppColors.textTertiary,
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Container(
              color: AppColors.bgMuted,
              padding: const EdgeInsets.fromLTRB(44, 14, 20, 16),
              child: Text(
                widget.answer,
                style: AppTextStyles.body2.copyWith(
                  color: AppColors.textPrimary,
                  height: 1.6,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
