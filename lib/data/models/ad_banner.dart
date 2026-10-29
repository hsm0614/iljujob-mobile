// 원더(wonder) 등 광고 제휴 배너 (ad_banners 테이블)
// 레거시 홈 배너(BannerAd/banners)와 별개 시스템
class AdBanner {
  final int id;
  final String partnerCode;
  final String placement;
  final String imageUrl;
  final String targetUrl;
  final int sortOrder;

  /// 공고형 광고(app_partner_recruit) 목록 줄 문구. 이미지 배너는 null
  final String? title;
  final String? subtitle;

  AdBanner({
    required this.id,
    required this.partnerCode,
    required this.placement,
    required this.imageUrl,
    required this.targetUrl,
    required this.sortOrder,
    this.title,
    this.subtitle,
  });

  factory AdBanner.fromJson(Map<String, dynamic> json) {
    return AdBanner(
      id: (json['id'] as num).toInt(),
      partnerCode: json['partner_code'] ?? '',
      placement: json['placement'] ?? '',
      imageUrl: json['image_url'] ?? '',
      targetUrl: json['target_url'] ?? '',
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      title:
          (json['title'] as String?)?.trim().isEmpty ?? true
              ? null
              : (json['title'] as String).trim(),
      subtitle:
          (json['subtitle'] as String?)?.trim().isEmpty ?? true
              ? null
              : (json['subtitle'] as String).trim(),
    );
  }
}
