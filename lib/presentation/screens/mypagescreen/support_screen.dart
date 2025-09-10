import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, rootBundle;

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: color.surface,
      appBar: AppBar(
        title: const Text('고객센터'),
        elevation: 0,
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _HeaderCard(),

          const SizedBox(height: 16),
          _SectionTitle('빠른 연결'),

          _SupportItemCard(
            icon: Icons.question_answer_rounded,
            iconBg: Colors.blue,
            title: 'FAQ (자주 묻는 질문)',
            subtitle: '자주 찾는 답변을 한곳에 모았어요',
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.pushNamed(context, '/faq');
            },
          ),
          _SupportItemCard(
            icon: Icons.contact_mail_rounded,
            iconBg: Colors.indigo,
            title: '1:1 문의하기',
            subtitle: '스크린샷/사진 첨부 가능',
            trailing: const _Badge(text: '권장'),
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.pushNamed(context, '/inquiry');
            },
          ),

          const SizedBox(height: 16),
          const _SectionTitle('기타 도움말'),

          // ✅ 약관(assets에서 읽어서 표시)
          _SupportItemCard(
            icon: Icons.policy_rounded,
            iconBg: Colors.teal,
            title: '이용약관',
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AssetDocumentScreen(
                    title: '이용약관',
                    assetPath: 'assets/terms/terms_of_service.txt',
                  ),
                ),
              );
            },
          ),

          // ✅ 개인정보처리방침(assets에서 읽어서 표시)
          _SupportItemCard(
            icon: Icons.privacy_tip_rounded,
            iconBg: Colors.deepPurple,
            title: '개인정보처리방침',
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AssetDocumentScreen(
                    title: '개인정보처리방침',
                    assetPath: 'assets/terms/privacy_policy.txt',
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// ===== 재사용 가능한 asset 문서 뷰어 =====
class AssetDocumentScreen extends StatefulWidget {
  final String title;
  final String assetPath;

  const AssetDocumentScreen({
    super.key,
    required this.title,
    required this.assetPath,
  });

  @override
  State<AssetDocumentScreen> createState() => _AssetDocumentScreenState();
}

class _AssetDocumentScreenState extends State<AssetDocumentScreen> {
  String? _content;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final text = await rootBundle.loadString(widget.assetPath);
      setState(() => _content = text);
    } catch (e) {
      setState(() => _error = '파일을 불러오지 못했습니다.\n(${widget.assetPath})');
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Builder(
        builder: (_) {
          if (_error != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: color.error),
                ),
              ),
            );
          }
          if (_content == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return Scrollbar(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: SelectableText(
                _content!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.5,
                      color: color.onSurface,
                    ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// ===== 아래는 SupportScreen용 작은 UI 컴포넌트들 =====
class _HeaderCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.primaryContainer.withOpacity(.9),
            color.primaryContainer.withOpacity(.6),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.onPrimaryContainer.withOpacity(.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.support_agent_rounded,
                size: 32, color: color.onPrimaryContainer),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('무엇을 도와드릴까요?',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: color.onPrimaryContainer,
                        )),
                const SizedBox(height: 6),
                Text(
                  'FAQ에서 빠르게 확인하거나,\n필요하면 바로 1:1 문의를 남겨주세요.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: color.onPrimaryContainer.withOpacity(.85),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4, right: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: color.onSurface.withOpacity(.85),
              letterSpacing: .2,
            ),
      ),
    );
  }
}

class _SupportItemCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  const _SupportItemCard({
    required this.icon,
    required this.iconBg,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: color.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: iconBg.withOpacity(.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconBg, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: color.onSurface,
                                  ),
                            ),
                          ),
                          if (trailing != null) trailing!,
                          const SizedBox(width: 6),
                          Icon(Icons.chevron_right_rounded,
                              color: color.onSurfaceVariant, size: 22),
                        ],
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color:
                                        color.onSurfaceVariant.withOpacity(.9),
                                  ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  const _Badge({required this.text});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.primary.withOpacity(.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.primary.withOpacity(.3)),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: .2,
            ),
      ),
    );
  }
}
