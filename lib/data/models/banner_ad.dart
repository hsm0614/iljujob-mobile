class BannerAd {
  final String id;
  final String imageUrl;
  final String? linkUrl;
  final String? title;

  BannerAd({
    required this.id,
    required this.imageUrl,
    this.linkUrl,
    this.title,
  });

  // 서버 응답을 파싱할 때 사용
  factory BannerAd.fromJson(Map<String, dynamic> json) {
    return BannerAd(
      id: json['id'].toString(),
      imageUrl: json['imageUrl'] ?? json['image_url'] ?? '',
      linkUrl: json['linkUrl'] ?? json['link_url'],
      title: json['title'],
    );
  }
}