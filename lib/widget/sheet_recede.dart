import 'package:flutter/material.dart';
import 'package:iljujob/config/app_theme.dart';

/// 바텀시트가 열리면 바로 아래 화면이 살짝 작아지며 물러난다 (iOS 시트 느낌).
/// 시트 호출 66곳을 고치지 않고 — 루트 네비게이터 관찰([SheetRecedeObserver]) +
/// 화면 전환 빌더([RecedePageTransitionsBuilder]) 두 곳에서 처리한다.
/// 시트 위에 시트가 또 열리면 아래 화면은 첫 시트 기준으로만 물러나 있다.
class SheetRecedeObserver extends NavigatorObserver {
  /// 지금 물러나 있어야 할 화면과 그 위 시트의 애니메이션
  static final current = ValueNotifier<(Route<dynamic>, Animation<double>)?>(null);
  static final _open = <(Route<dynamic> sheet, Route<dynamic> page, Animation<double>)>[];

  static void _sync() {
    current.value = _open.isEmpty ? null : (_open.last.$2, _open.last.$3);
  }

  static void _drop(Route<dynamic> sheet) {
    _open.removeWhere((e) => identical(e.$1, sheet));
    _sync();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! ModalBottomSheetRoute || previousRoute is! PageRoute) return;
    final anim = route.animation;
    if (anim == null) return;
    _open.add((route, previousRoute, anim));
    // 닫힐 때 바로 빼면 화면이 툭 돌아온다 — 시트가 다 내려간 뒤에 뺀다
    anim.addStatusListener((s) {
      if (s == AnimationStatus.dismissed) _drop(route);
    });
    _sync();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _drop(route);
}

class SheetRecede extends StatelessWidget {
  final Route<dynamic> route;
  final Widget child;
  const SheetRecede({super.key, required this.route, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: SheetRecedeObserver.current,
      child: child,
      builder: (context, e, child) {
        final anim =
            e != null && identical(e.$1, route) ? e.$2 : kAlwaysDismissedAnimation;
        return AnimatedBuilder(
          animation: anim,
          child: child,
          builder: (context, child) {
            final t = Curves.easeOut.transform(anim.value.clamp(0.0, 1.0));
            // 위젯 모양은 늘 같게 — 바뀌면 화면 상태(스크롤·입력)가 날아간다
            return ColoredBox(
              color: t > 0 ? Colors.black : Colors.transparent,
              child: Transform.scale(
                scale: 1 - 0.04 * t,
                child: ClipRRect(
                  clipBehavior: t > 0 ? Clip.antiAlias : Clip.none,
                  borderRadius: BorderRadius.circular(AppRadius.xl * t),
                  child: child,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// 기존 쿠퍼티노 전환(오른쪽에서 밀려옴·뒤로 스와이프)은 그대로, 바깥에 [SheetRecede]만 씌운다.
class RecedePageTransitionsBuilder extends PageTransitionsBuilder {
  const RecedePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return SheetRecede(
      route: route,
      child: const CupertinoPageTransitionsBuilder().buildTransitions(
        route,
        context,
        animation,
        secondaryAnimation,
        child,
      ),
    );
  }
}
