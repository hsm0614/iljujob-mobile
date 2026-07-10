// 광고 제휴 배너 공통 위젯 (원더 등, ad_banners)
// - 배너 없으면 영역 완전 접힘 (SizedBox.shrink)
// - impression은 화면 단위 1회 (스크롤 재진입 중복 전송 방지)
// - 탭 시 click 기록 후 인앱브라우저로 target_url?src=<placement> 오픈
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_theme.dart';
import '../config/constants.dart';
import '../data/models/ad_banner.dart';
import '../data/services/ad_banner_service.dart';

class AdBannerWidget extends StatefulWidget {
  final String placement;
  final EdgeInsetsGeometry margin;

  const AdBannerWidget({
    super.key,
    required this.placement,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  @override
  State<AdBannerWidget> createState() => _AdBannerWidgetState();
}

class _AdBannerWidgetState extends State<AdBannerWidget> {
  // 스크롤로 위젯이 재생성돼도 impression이 중복 전송되지 않도록
  // 앱 세션 단위 정적 맵으로 디듀프 (같은 배너·지면은 3분에 1회만)
  static final Map<String, DateTime> _lastImpression = {};
  static const _impressionDedupe = Duration(minutes: 3);

  AdBanner? _banner;
  bool _imageFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final banners = await AdBannerService.instance.fetchBanners(
      widget.placement,
    );
    if (!mounted || banners.isEmpty) return;

    setState(() => _banner = banners.first);
    _sendImpression(banners.first);
  }

  void _sendImpression(AdBanner banner) {
    final key = '${widget.placement}:${banner.id}';
    final last = _lastImpression[key];
    final now = DateTime.now();
    if (last != null && now.difference(last) < _impressionDedupe) return;

    _lastImpression[key] = now;
    AdBannerService.instance.logEvent(
      banner.id,
      'impression',
      widget.placement,
    );
  }

  Future<void> _onTap(AdBanner banner) async {
    AdBannerService.instance.logEvent(banner.id, 'click', widget.placement);

    final uri = Uri.parse(banner.targetUrl).replace(
      queryParameters: {
        ...Uri.parse(banner.targetUrl).queryParameters,
        'src': widget.placement,
        'bid': banner.id.toString(),
      },
    );

    try {
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (_) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
  }

  String _imageUrl(AdBanner banner) {
    if (banner.imageUrl.startsWith('http')) return banner.imageUrl;
    return '$baseUrl${banner.imageUrl}';
  }

  @override
  Widget build(BuildContext context) {
    final banner = _banner;
    if (banner == null || _imageFailed) return const SizedBox.shrink();

    return Padding(
      padding: widget.margin,
      child: AspectRatio(
        aspectRatio: 4 / 1,
        child: GestureDetector(
          onTap: () => _onTap(banner),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: const BoxDecoration(color: AppColors.bgMuted),
                  child: Image.network(
                    _imageUrl(banner),
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.high,
                    errorBuilder: (context, error, stackTrace) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && !_imageFailed) {
                          setState(() => _imageFailed = true);
                        }
                      });
                      return const SizedBox.shrink();
                    },
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
