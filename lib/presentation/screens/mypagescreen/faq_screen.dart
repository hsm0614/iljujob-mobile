import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  static const _brand = Color(0xFF3B8AFF);

  // ▶ 데이터
  static const List<Map<String, String>> commonFaq = [
    {'q': '가입은 무료인가요?', 'a': '네, 가입 및 기본 이용은 모두 무료입니다.'},
    {'q': '연락처는 안전하게 보호되나요?', 'a': '네, 모든 연락처는 암호화 저장됩니다.'},
    {'q': '고객센터는 어떻게 연락하나요?', 'a': '앱 내 1:1 문의하기 또는 hsm@outfind.co.kr으로 문의해주세요.'},
  ];

  static const List<Map<String, String>> workerFaq = [
    {'q': '지원 후 취소할 수 있나요?', 'a': '네, 마이페이지에서 언제든 지원 취소가 가능합니다.'},
    {'q': '급여는 언제 지급되나요?', 'a': '근무 완료 후 업체에서 지정한 일정에 따라 지급됩니다.'},
  ];

  static const List<Map<String, String>> clientFaq = [
    {'q': '공고 등록 비용이 있나요?', 'a': '현재는 무료로 제공 중이며, 추후 유료화될 수 있습니다.'},
    {'q': '채용 진행 중 알바생에게 메시지를 보낼 수 있나요?', 'a': '네, 채팅 기능을 통해 알바생에게 직접 메시지를 보낼 수 있습니다.'},
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.transparent,
          centerTitle: true,
          title: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.25)),
            ),
            child: const Text('자주 묻는 질문', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
         bottom: PreferredSize(
  preferredSize: const Size.fromHeight(72), // ← 64 → 72
  child: Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: _FancyTabBar(),
  ),
),

        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Color(0xFF3B8AFF), Color(0xFF7CC7FF), Colors.white],
              stops: [0, .25, .25],
            ),
          ),
          child: TabBarView(
            children: [
              _FaqSection(
                titleIcon: Icons.all_inclusive_rounded,
                hint: '공통 질문 검색…',
                items: commonFaq,
              ),
              _FaqSection(
                titleIcon: Icons.person_rounded,
                chipLabel: '알바생',
                chipColor: theme.colorScheme.primary.withOpacity(.12),
                hint: '알바생 질문 검색…',
                items: workerFaq,
              ),
              _FaqSection(
                titleIcon: Icons.business_rounded,
                chipLabel: '기업',
                chipColor: Colors.amber.withOpacity(.18),
                hint: '기업 질문 검색…',
                items: clientFaq,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 탭바(알약형)
class _FancyTabBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tabs = const [
      _TabItem(label: '공통 질문', icon: Icons.all_inclusive_rounded),
      _TabItem(label: '알바생',   icon: Icons.person_rounded),
      _TabItem(label: '기업',     icon: Icons.business_rounded),
    ];
    return Container(
      height: 52, // ← 44 → 52
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 14, offset: Offset(0, 6))],
      ),
      child: TabBar(
        tabs: tabs,
        isScrollable: false,
        indicator: BoxDecoration(
          color: const Color(0xFF3B8AFF),
          borderRadius: BorderRadius.circular(26),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: const Color(0xFF3B8AFF),
        indicatorSize: TabBarIndicatorSize.tab,
        splashBorderRadius: BorderRadius.circular(26),
        labelPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0), // 세로 여백 0으로
      ),
    );
  }
}
class _TabItem extends StatelessWidget {
  final String label;
  final IconData icon;
  const _TabItem({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}

/// 섹션(검색 + 리스트 + 문의 CTA)
class _FaqSection extends StatefulWidget {
  final List<Map<String, String>> items;
  final String hint;
  final IconData titleIcon;
  final String? chipLabel;
  final Color? chipColor;

  const _FaqSection({
    required this.items,
    required this.hint,
    required this.titleIcon,
    this.chipLabel,
    this.chipColor,
  });

  @override
  State<_FaqSection> createState() => _FaqSectionState();
}

class _FaqSectionState extends State<_FaqSection> {
  String q = '';

@override
Widget build(BuildContext context) {
  final filtered = widget.items.where((e) {
    final s = q.toLowerCase();
    if (s.isEmpty) return true;
    return (e['q'] ?? '').toLowerCase().contains(s) || (e['a'] ?? '').toLowerCase().contains(s);
  }).toList();

  final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Scrollbar(
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + bottomInset),

          children: [
            // 검색창
            _SearchField(
              hint: widget.hint,
              onChanged: (v) => setState(() => q = v),
            ),
            const SizedBox(height: 12),
            // 헤더
            Row(
              children: [
                Icon(widget.titleIcon, color: Colors.black54),
                const SizedBox(width: 8),
                Text('FAQ', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                if (widget.chipLabel != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: ShapeDecoration(
                      color: widget.chipColor ?? Colors.black.withOpacity(.06),
                      shape: StadiumBorder(),
                    ),
                    child: Text(widget.chipLabel!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                const Spacer(),
                Text('${filtered.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            // 리스트
            if (filtered.isEmpty)
              _Empty(q: q)
            else
              ...List.generate(filtered.length, (i) {
                final item = filtered[i];
                return _FaqCard(
                  index: i,
                  question: item['q'] ?? '',
                  answer: item['a'] ?? '',
                );
              }),
            const SizedBox(height: 20),
            // 문의 CTA
            _SupportCTA(),
          ],
        ),
      ),
    );
  }
}

/// 검색 인풋
class _SearchField extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  const _SearchField({required this.hint, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search_rounded),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}

/// FAQ 카드(애니메이션 + 확장)
class _FaqCard extends StatefulWidget {
  final int index;
  final String question;
  final String answer;

  const _FaqCard({
    required this.index,
    required this.question,
    required this.answer,
  });

  @override
  State<_FaqCard> createState() => _FaqCardState();
}

class _FaqCardState extends State<_FaqCard> {
  bool open = false;

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final a = widget.answer;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: open ? const Color(0xFF3B8AFF) : Colors.black12, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(open ? .08 : .04),
            blurRadius: open ? 18 : 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          onExpansionChanged: (v) => setState(() => open = v),
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: const Color(0xFF3B8AFF).withOpacity(.12),
            child: const Icon(Icons.help_outline_rounded, color: Color(0xFF3B8AFF), size: 18),
          ),
          trailing: AnimatedRotation(
            turns: open ? .5 : 0,
            duration: const Duration(milliseconds: 200),
            child: const Icon(Icons.keyboard_arrow_down_rounded, size: 26),
          ),
          title: Text(q, style: const TextStyle(fontWeight: FontWeight.w800)),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(width: 2),
                const Icon(Icons.lightbulb_rounded, size: 18, color: Colors.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    a,
                    style: const TextStyle(height: 1.5),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 빈 상태 표시
class _Empty extends StatelessWidget {
  final String q;
  const _Empty({required this.q});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      alignment: Alignment.center,
      child: Column(
        children: [
          const Icon(Icons.search_off_rounded, size: 44, color: Colors.black38),
          const SizedBox(height: 8),
          const Text('검색 결과가 없어요', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('‘$q’와(과) 관련된 질문을 찾지 못했어요.', style: const TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}

/// 하단 고객센터 CTA
class _SupportCTA extends StatelessWidget {
  Future<void> _email() async {
   final uri = Uri(
  scheme: 'mailto',
  path: 'hsm@outfind.co.kr',
  query: Uri(queryParameters: {'subject': '[알바일주] FAQ 문의'}).query,
);

    await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF3B8AFF).withOpacity(.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF3B8AFF).withOpacity(.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.support_agent_rounded, color: Color(0xFF3B8AFF)),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              '원하는 답이 없나요? 1:1 문의 또는 이메일로 연락주세요.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          FilledButton.tonal(
            onPressed: _email,
            child: const Text('이메일 문의'),
          ),
        ],
      ),
    );
  }
}
