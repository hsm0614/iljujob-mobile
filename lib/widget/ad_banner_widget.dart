// 광고 제휴 배너 공통 위젯 (원더 등, ad_banners)
// - 배너 없음/API 실패/이미지 실패 시 영역 완전 접힘 (SizedBox.shrink)
// - impression은 배너가 실제로 50% 이상 보였을 때만 전송 (viewability 기준)
//   + 앱 세션 단위 3분 디듀프로 스크롤 재진입 중복 방지
// - 탭 시 click 기록(fire-and-forget) 후 인앱브라우저로 target_url?src=<placement> 오픈
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:visibility_detector/visibility_detector.dart';

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
  // 같은 배너·지면 impression은 앱 세션 기준 3분에 1회만 (중복 전송 방지)
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
  }

  // 배너가 화면에 50% 이상 노출된 순간에만 호출됨 (VisibilityDetector)
  void _onVisibilityChanged(VisibilityInfo info, AdBanner banner) {
    if (info.visibleFraction < 0.5) return;

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
        child: VisibilityDetector(
          key: Key('ad_banner_${widget.placement}_${banner.id}'),
          onVisibilityChanged: (info) => _onVisibilityChanged(info, banner),
          child: Semantics(
            button: true,
            label: '원더 제휴 혜택 보기',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: const BoxDecoration(color: AppColors.bgMuted),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // 표시 폭 기준으로만 디코딩 (1600px 원본 풀 디코딩 방지)
                        final dpr = MediaQuery.of(context).devicePixelRatio;
                        final cacheWidth = (constraints.maxWidth * dpr).ceil();

                        return Image.network(
                          _imageUrl(banner),
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.high,
                          cacheWidth: cacheWidth,
                          excludeFromSemantics: true,
                          errorBuilder: (context, error, stackTrace) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted && !_imageFailed) {
                                setState(() => _imageFailed = true);
                              }
                            });
                            return const SizedBox.shrink();
                          },
                        );
                      },
                    ),
                  ),
                  // 이미지 위 잉크 리플 (네이티브 탭 피드백)
                  Positioned.fill(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _onTap(banner),
                        splashColor: Colors.black.withValues(alpha: 0.08),
                        highlightColor: Colors.black.withValues(alpha: 0.04),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
