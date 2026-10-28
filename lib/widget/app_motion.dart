import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../config/app_theme.dart';
import 'app_ui.dart';

/// 움직임 공용 (2026-10, 토스식). 원칙: 짧게(≤0.7초) · 한 화면에 한 번 · 정보가 늦게 보이게 하지 않는다.

/// 숫자가 0에서 올라가며 멈춘다 — 화면의 '큰 숫자 하나'에만 쓴다.
class AppCountUp extends StatelessWidget {
  final int value;
  final TextStyle style;
  final String suffix;
  const AppCountUp({
    super.key,
    required this.value,
    required this.style,
    this.suffix = '원',
  });

  static final _fmt = NumberFormat('#,###');

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder:
          (_, v, __) => Text('${_fmt.format(v.round())}$suffix', style: style),
    );
  }
}

/// 목록 줄이 처음 그려질 때 아래에서 살짝 떠오른다. [index]마다 40ms씩 늦게, 8번째부터는 같이.
/// 스크롤로 새로 들어오는 줄엔 다시 재생되지 않게 처음 그려질 때 한 번만.
class AppFadeSlideIn extends StatefulWidget {
  final int index;
  final Widget child;
  const AppFadeSlideIn({super.key, required this.index, required this.child});

  @override
  State<AppFadeSlideIn> createState() => _AppFadeSlideInState();
}

class _AppFadeSlideInState extends State<AppFadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutCubic,
  );

  @override
  void initState() {
    super.initState();
    if (widget.index >= 8) {
      _c.value = 1; // 화면 밖에서 스크롤로 들어오는 줄은 바로
    } else {
      Future.delayed(Duration(milliseconds: 40 * widget.index), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _t,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(_t),
        child: widget.child,
      ),
    );
  }
}

/// 완료 화면 (지원·출근 확정·후기 등). 스낵바 한 줄로 지나가던 좋은 순간을 전체 화면으로.
/// 체크가 튀어나오고 → 제목·설명이 올라온다. 결과: 'primary' · 'secondary' · null(닫기)
Future<String?> showAppSuccess(
  BuildContext context, {
  required String title,
  String? message,
  List<(String, String)> facts = const [],
  required String primaryLabel,
  String? secondaryLabel,
}) {
  HapticFeedback.mediumImpact();
  return Navigator.of(context).push<String>(
    PageRouteBuilder(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder:
          (_, __, ___) => _AppSuccessPage(
            title: title,
            message: message,
            facts: facts,
            primaryLabel: primaryLabel,
            secondaryLabel: secondaryLabel,
          ),
      transitionsBuilder:
          (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ),
  );
}

class _AppSuccessPage extends StatefulWidget {
  final String title;
  final String? message;
  final List<(String, String)> facts;
  final String primaryLabel;
  final String? secondaryLabel;
  const _AppSuccessPage({
    required this.title,
    this.message,
    required this.facts,
    required this.primaryLabel,
    this.secondaryLabel,
  });

  @override
  State<_AppSuccessPage> createState() => _AppSuccessPageState();
}

class _AppSuccessPageState extends State<_AppSuccessPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  Animation<double> _seg(double a, double b, [Curve c = Curves.easeOutCubic]) =>
      CurvedAnimation(parent: _c, curve: Interval(a, b, curve: c));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pop = _seg(0, 0.45, Curves.elasticOut);
    final draw = _seg(0.2, 0.55);
    final text = _seg(0.35, 0.8);
    final rest = _seg(0.55, 1);

    Widget rise(Animation<double> a, Widget child) => FadeTransition(
      opacity: a,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.25),
          end: Offset.zero,
        ).animate(a),
        child: child,
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.bgCard,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: '닫기',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              const Spacer(flex: 2),
              ScaleTransition(
                scale: pop,
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: AnimatedBuilder(
                    animation: draw,
                    builder:
                        (_, __) =>
                            CustomPaint(painter: _CheckPainter(draw.value)),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              rise(
                text,
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.h1,
                ),
              ),
              if (widget.message != null) ...[
                const SizedBox(height: 10),
                rise(
                  text,
                  Text(
                    widget.message!,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body1.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
              if (widget.facts.isNotEmpty) ...[
                const SizedBox(height: 28),
                rise(
                  rest,
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.bgMuted,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    child: Column(
                      children: [
                        for (final (k, v) in widget.facts)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 64,
                                  child: Text(k, style: AppTextStyles.body2),
                                ),
                                Expanded(
                                  child: Text(
                                    v,
                                    textAlign: TextAlign.right,
                                    style: AppTextStyles.body1.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              const Spacer(flex: 3),
              FadeTransition(
                opacity: rest,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppPressScale(
                      child: SizedBox(
                        height: 54,
                        child: FilledButton(
                          onPressed: () => Navigator.pop(context, 'primary'),
                          child: Text(widget.primaryLabel),
                        ),
                      ),
                    ),
                    if (widget.secondaryLabel != null) ...[
                      const SizedBox(height: 4),
                      TextButton(
                        onPressed: () => Navigator.pop(context, 'secondary'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: Text(widget.secondaryLabel!),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  final double t;
  _CheckPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final w = size.width;
    final path =
        Path()
          ..moveTo(w * 0.28, w * 0.52)
          ..lineTo(w * 0.44, w * 0.67)
          ..lineTo(w * 0.73, w * 0.37);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * t),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.085
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.t != t;
}
