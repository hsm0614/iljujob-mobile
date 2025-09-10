// promo_model.dart
class PromoConfig {
  final String id;
  final bool enabled;
  final DateTime? startAt;
  final DateTime? endAt;
  final int snoozeDays;
  final String? minAppVersion;
  final String? maxAppVersion;
  final String imageUrl;
  final double imageW;
  final double imageH;
  final String ctaLabel;
  final String dismissLabel;
  final String checkboxLabel;
  final String? deeplink;
  final String? etag;

  PromoConfig({
    required this.id,
    required this.enabled,
    required this.startAt,
    required this.endAt,
    required this.snoozeDays,
    required this.minAppVersion,
    required this.maxAppVersion,
    required this.imageUrl,
    required this.imageW,
    required this.imageH,
    required this.ctaLabel,
    required this.dismissLabel,
    required this.checkboxLabel,
    required this.deeplink,
    required this.etag,
  });

  factory PromoConfig.fromJson(Map<String, dynamic> j) {
    final img = j['image'] ?? {};
    final cta = j['cta'] ?? {};
    return PromoConfig(
      id: j['id'] ?? '',
      enabled: j['enabled'] ?? false,
      startAt: j['startAt'] != null ? DateTime.parse(j['startAt']) : null,
      endAt: j['endAt'] != null ? DateTime.parse(j['endAt']) : null,
      snoozeDays: j['snoozeDays'] ?? 7,
      minAppVersion: j['minAppVersion'],
      maxAppVersion: j['maxAppVersion'],
      imageUrl: img['url'] ?? '',
      imageW: (img['width'] ?? 431).toDouble(),
      imageH: (img['height'] ?? 400).toDouble(),
      ctaLabel: cta['label'] ?? '확인',
      dismissLabel: cta['dismissLabel'] ?? '닫기',
      checkboxLabel: cta['checkboxLabel'] ?? '일주일간 보지 않기',
      deeplink: cta['deeplink'],
      etag: j['etag'],
    );
  }
}
