import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/constants.dart'; // baseUrl

class WorkerMyPageScreen extends StatefulWidget {
  const WorkerMyPageScreen({super.key});
  @override
  State<WorkerMyPageScreen> createState() => _WorkerMyPageScreenState();
}

class _WorkerMyPageScreenState extends State<WorkerMyPageScreen> {
  // Branding
  static const Color brandBlue = Color(0xFF3B8AFF);
  static const Color brandBlueLight = Color(0xFF6EB6FF);

  // Profile State
  String phoneNumber = '전화번호';
  String profileImageUrl = '';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      phoneNumber = prefs.getString('userPhone') ?? '전화번호';
      profileImageUrl = prefs.getString('workerProfileImageUrl') ?? '';
    });
  }

  String _formatPhone(String phone) {
    final p = phone.replaceAll(RegExp(r'\D'), '');
    if (p.length == 11) return '${p.substring(0,3)}-${p.substring(3,7)}-${p.substring(7)}';
    if (p.length == 10) return '${p.substring(0,2)}-${p.substring(2,6)}-${p.substring(6)}';
    return phone;
  }

  String _getFullImageUrl(String path) {
    if (path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    return '$baseUrl$path';
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/onboarding', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: RefreshIndicator(
        onRefresh: _loadProfile,
        color: brandBlue,
        child: CustomScrollView(
          slivers: [
            // 클라이언트 화면과 동일하게: 헤더 내부에 프로필 카드 포함
            SliverAppBar(
              pinned: true,
              elevation: 0,
              backgroundColor: Colors.white,
              expandedHeight: 200, // 클라이언트와 동일
              automaticallyImplyLeading: false,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  clipBehavior: Clip.hardEdge, // 미세 오버플로우 방지
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF3B8AFF), Color(0xFF6EB6FF)],
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '마이페이지',
                            style: TextStyle(
                              fontFamily: 'Jalnan2TTF',
                              color: Colors.white,
                              fontSize: 22,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 14),
                        _WorkerProfileCard(
  brandBlue: brandBlue,
  brandBlueLight: brandBlueLight,
  imageUrl: _getFullImageUrl(profileImageUrl),
  phoneText: _formatPhone(phoneNumber),
  // 기존
  // onEdit: () => Navigator.pushNamed(context, '/edit_profile'),
  // 변경 (워커 전용 라우트로)
  onEdit: () => Navigator.pushNamed(context, '/edit_profile_worker'),
),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              toolbarHeight: 0,
            ),

            // 섹션들 (클라이언트와 동일한 카드 스타일)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: _SectionCard(
                  title: '사용자',
                  children: [
                    _ItemTile(
                      icon: Icons.favorite_border,
                      label: '찜한 공고',
                      onTap: () => Navigator.pushNamed(context, '/bookmarked-jobs'),
                    ),
                    _ItemTile(
                      icon: Icons.notifications_active,
                      label: '알림 설정',
                      onTap: () => Navigator.pushNamed(context, '/notifications'),
                    ),
                    _ItemTile(
                      icon: Icons.report,
                      label: '신고 내역',
                      onTap: () => Navigator.pushNamed(context, '/report-history'),
                    ),
                    _ItemTile(
                      icon: Icons.block,
                      label: '차단한 사용자',
                      onTap: () => Navigator.pushNamed(context, '/blocked-users'),
                    ),
                  ],
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: _SectionCard(
                  title: '고객센터',
                  children: [
                    _ItemTile(
                      icon: Icons.campaign,
                      label: '공지사항',
                      onTap: () => Navigator.pushNamed(context, '/notices'),
                    ),
                    _ItemTile(
                      icon: Icons.local_activity_outlined,
                      label: '이벤트',
                      onTap: () => Navigator.pushNamed(context, '/events'),
                    ),
                    _ItemTile(
                      icon: Icons.support_agent,
                      label: '고객센터',
                      onTap: () => Navigator.pushNamed(context, '/support'),
                    ),
                  ],
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: _SectionCard(
                  title: '서비스',
                  children: [
                    _ItemTile(
                      icon: Icons.policy,
                      label: '약관 및 정책',
                      onTap: () => Navigator.pushNamed(context, '/terms-list'),
                    ),
                    _ExpandableBizInfo(brandBlue: brandBlue),
                  ],
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: _SectionCard(
                  title: '계정',
                  children: [
                    _ItemTile(
                      icon: Icons.logout,
                      label: '로그아웃',
                      labelStyle: const TextStyle(fontWeight: FontWeight.w600, color: Colors.red),
                      trailing: const Icon(Icons.logout, size: 18, color: Colors.red),
                      onTap: _logout,
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

/* --------------------------- Widgets --------------------------- */

class _WorkerProfileCard extends StatelessWidget {
  final Color brandBlue;
  final Color brandBlueLight;
  final String imageUrl;
  final String phoneText;
  final VoidCallback onEdit;

  const _WorkerProfileCard({
    required this.brandBlue,
    required this.brandBlueLight,
    required this.imageUrl,
    required this.phoneText,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final hasImg = imageUrl.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 6))],
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: const Color(0xFFEAF2FF),
                backgroundImage: hasImg ? NetworkImage(imageUrl) : null,
                child: hasImg ? null : const Icon(Icons.account_circle, size: 30, color: Colors.black54),
              ),
              Positioned(
                bottom: -2,
                right: -2,
                child: Material(
                  color: Colors.white,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onEdit,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: brandBlue,
                        shape: BoxShape.circle,
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                      ),
                      child: const Icon(Icons.edit, size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _TwoLine(
                  title: '내 전화번호', // 라벨
                  subtitle: '정보',
                ),
                const SizedBox(height: 6),
                // 칩으로 실제 전화번호와 액션들 배치 (자동 줄바꿈)
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _ChipText(text: phoneText, icon: Icons.call),
                    _ChipText(text: '알림 설정', icon: Icons.notifications),
                  ],
                ),
              ],
            ),
          ),
          // 반응형 버튼(좁으면 아이콘만)
          Flexible(
            fit: FlexFit.loose,
            child: LayoutBuilder(
              builder: (_, c) {
                final narrow = c.maxWidth < 120;
                if (narrow) {
                  return Align(
                    alignment: Alignment.centerRight,
                    child: IconButton.filledTonal(
                      onPressed: onEdit,
                      icon: const Icon(Icons.arrow_forward_ios, size: 16),
                    ),
                  );
                }
                return Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    child: FilledButton.tonalIcon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.arrow_forward_ios, size: 16),
                      label: const Text('프로필'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFEAF2FF),
                        foregroundColor: Color(0xFF3B8AFF),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        textStyle: const TextStyle(fontWeight: FontWeight.w600),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        minimumSize: const Size(0, 40),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TwoLine extends StatelessWidget {
  final String title;
  final String subtitle;
  const _TwoLine({required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) {
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        children: [
          TextSpan(
            text: '$subtitle: ',
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
          TextSpan(
            text: title,
            style: const TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipText extends StatelessWidget {
  final String text;
  final IconData icon;
  const _ChipText({required this.text, required this.icon});
  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 160),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F6FF),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: const Color(0xFF3B8AFF)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Container(
                  width: 6, height: 20,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B8AFF),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Jalnan2TTF',
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ..._withDividers(children),
        ],
      ),
    );
  }

  List<Widget> _withDividers(List<Widget> items) {
    final List<Widget> out = [];
    for (var i = 0; i < items.length; i++) {
      out.add(items[i]);
      if (i != items.length - 1) {
        out.add(const Divider(height: 1, indent: 56));
      }
    }
    return out;
  }
}

class _ItemTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final TextStyle? labelStyle;
  final Widget? trailing;
  final VoidCallback onTap;

  const _ItemTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.labelStyle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: ListTile(
          leading: Icon(icon, size: 22, color: const Color(0xFF3B8AFF)),
          title: Text(
            label,
            style: labelStyle ?? t.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          trailing: trailing ?? const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.black38),
          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          dense: true,
          minLeadingWidth: 0,
        ),
      ),
    );
  }
}

class _ExpandableBizInfo extends StatelessWidget {
  final Color brandBlue;
  const _ExpandableBizInfo({required this.brandBlue});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        leading: Icon(Icons.info_outline, color: brandBlue),
        title: const Text('사업자 정보', style: TextStyle(fontWeight: FontWeight.w700)),
        shape: const RoundedRectangleBorder(side: BorderSide(color: Colors.transparent)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: const [
          _BizInfoItem('법인명', '주식회사 찾다'),
          _BizInfoItem('대표자', '황성민'),
          _BizInfoItem('사업자등록번호', '480-88-03690'),
          _BizInfoItem('법인등록번호', '120111-0146420'),
          _BizInfoItem('통신판매업 번호', '2025-인천연수구-2179호'),
          _BizInfoItem('이메일', 'hsm@outfind.co.kr'),
          _BizInfoItem('고객센터', '070-4792-3001 / 010-4653-3002'),
          _BizInfoItem('개업연월일', '2025년 05월 26일'),
          _BizInfoItem('사업장 소재지', '인천광역시 연수구 하모니로178번길 22, 7층 707-나60호 (송도동)'),
          _BizInfoItem('본점 소재지', '인천광역시 연수구 하모니로178번길 22, 7층 707-나60호 (송도동)'),
          _BizInfoItem('업태', '정보통신업'),
          _BizInfoItem('종목', '데이터베이스 및 온라인 정보제공업, 온라인활용마케팅 및 관련사업지원서비스'),
        ],
      ),
    );
  }
}

class _BizInfoItem extends StatelessWidget {
  final String k;
  final String v;
  const _BizInfoItem(this.k, this.v);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text('$k', style: const TextStyle(color: Colors.black54, fontSize: 13.5)),
          ),
          Expanded(
            child: Text(v, style: const TextStyle(fontSize: 13.5, color: Colors.black87)),
          ),
        ],
      ),
    );
  }
}
