import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 스토어 별점 요청. 좋은 순간에만 부른다: 알바생 [도착했어요] 성공, 사장님 지원자 도착.
/// 앱스토어 평가 10개(경쟁 앱 수천 개) — 검색 순위가 평가 수에 묶여 있다(2026-11-15).
/// OS가 횟수를 막는다(iOS 365일 3회, 안드로이드 쿼터). 우리도 90일에 한 번만 시도한다.
Future<void> maybeRequestStoreReview() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    const key = 'store_review_asked_at_ms';
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - (prefs.getInt(key) ?? 0) < const Duration(days: 90).inMilliseconds) return;
    final review = InAppReview.instance;
    if (!await review.isAvailable()) return;
    await prefs.setInt(key, now);
    await review.requestReview();
  } catch (_) {
    // 별점 창은 부가 기능 — 실패해도 흐름을 막지 않는다
  }
}
