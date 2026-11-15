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

/// 사진 받아 오는 동안 그 칸에 빛줄기가 왼쪽→오른쪽으로 흐른다 (2026-11-15). 회색 칸만 있으면 '멈춘 것'처럼 보였다.
class AppShimmer extends StatefulWidget {
  final double? width;
  final double? height;
  const AppShimmer({super.key, this.width, this.height});

  @override
  State<AppShimmer> createState() => _AppShimmerState();
}

class _AppShimmerState extends State<AppShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, __) {
      final v = _c.value * 1.6 - 0.3;
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: const [AppColors.bgMuted, AppColors.bgCard, AppColors.bgMuted],
            stops: [
              (v - 0.3).clamp(0.0, 1.0),
              v.clamp(0.0, 1.0),
              (v + 0.3).clamp(0.0, 1.0),
            ],
          ),
        ),
      );
    },
  );
}

/// Image.network 의 frameBuilder 로 쓴다: 받는 동안 빛줄기 → 다 받으면 0.22초에 걸쳐 나타난다.
/// 캐시에서 바로 오면(sync) 그대로. 부모가 크기를 정해 줘야 한다(width·height 또는 Stack expand).
Widget appImageFrame(BuildContext context, Widget child, int? frame, bool sync) {
  if (sync) return child;
  return Stack(
    fit: StackFit.passthrough,
    children: [
      if (frame == null) const Positioned.fill(child: AppShimmer()),
      AnimatedOpacity(
        opacity: frame == null ? 0 : 1,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        child: child,
      ),
    ],
  );
}

/// [on]이 꺼짐→켜짐으로 바뀌는 순간 [child] 뒤로 레이더 원이 두 번 퍼진다 (한 번만, 0.9초).
/// '오늘 일할 수 있어요'를 켰을 때 "이제 사장님에게 보여요"를 느끼게 (2026-11-15).
class AppRadarPulse extends StatefulWidget {
  final bool on;
  final Widget child;
  const AppRadarPulse({super.key, required this.on, required this.child});

  @override
  State<AppRadarPulse> createState() => _AppRadarPulseState();
}

class _AppRadarPulseState extends State<AppRadarPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didUpdateWidget(AppRadarPulse old) {
    super.didUpdateWidget(old);
    if (widget.on && !old.on) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    clipBehavior: Clip.none,
    children: [
      for (final delay in const [0.0, 0.3])
        AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            final t = ((_c.value - delay) / (1 - delay)).clamp(0.0, 1.0);
            if (t == 0 || t == 1) return const SizedBox.shrink();
            return IgnorePointer(
              child: Container(
                width: 24 + 72 * t,
                height: 24 + 72 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.5 * (1 - t)),
                    width: 2,
                  ),
                ),
              ),
            );
          },
        ),
      widget.child,
    ],
  );
}

/// 숫자가 늘어나는 순간 한 번 톡 커졌다 돌아온다 (사장님 홈 지원·답장 대기). 처음 그릴 땐 가만히.
class AppBumpNumber extends StatefulWidget {
  final int value;
  final TextStyle style;
  const AppBumpNumber({super.key, required this.value, required this.style});

  @override
  State<AppBumpNumber> createState() => _AppBumpNumberState();
}

class _AppBumpNumberState extends State<AppBumpNumber>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );
  late final Animation<double> _s = TweenSequence([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.35).chain(CurveTween(curve: Curves.easeOut)), weight: 35),
    TweenSequenceItem(tween: Tween(begin: 1.35, end: 1.0).chain(CurveTween(curve: Curves.elasticOut)), weight: 65),
  ]).animate(_c);

  @override
  void didUpdateWidget(AppBumpNumber old) {
    super.didUpdateWidget(old);
    if (widget.value > old.value) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
    scale: _s,
    child: Text('${widget.value}', style: widget.style),
  );
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
                    keepWords(widget.message!),
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
