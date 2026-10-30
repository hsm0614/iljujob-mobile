// 제휴 이미지 배너. 구직자 홈은 여러 배너를 한 지면에서 자동 회전한다.
import 'dart:async';

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
  final bool autoRotate;
  final Future<void> Function(int jobId)? onInternalJobTap;

  const AdBannerWidget({
    super.key,
    required this.placement,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.autoRotate = false,
    this.onInternalJobTap,
  });

  @override
  State<AdBannerWidget> createState() => _AdBannerWidgetState();
}

class _AdBannerWidgetState extends State<AdBannerWidget> {
  static final Map<String, DateTime> _lastImpression = {};
  static const _impressionDedupe = Duration(minutes: 3);
  static const _rotationInterval = Duration(seconds: 7);

  final PageController _pageController = PageController();
  List<AdBanner> _banners = [];
  final Set<int> _loadedImages = {};
  final Set<int> _failedImages = {};
  Timer? _rotationTimer;
  int _currentIndex = 0;
  double _visibleFraction = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _rotationTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final banners = await AdBannerService.instance.fetchBanners(
      widget.placement,
    );
    if (!mounted || banners.isEmpty) return;

    setState(() {
      _banners = widget.autoRotate ? banners : [banners.first];
      _currentIndex = 0;
    });
    if (_banners.length > 1) {
      _rotationTimer = Timer.periodic(_rotationInterval, (_) => _advance());
    }
  }

  void _advance() {
    if (!mounted || _banners.length < 2 || _visibleFraction < 0.5) return;
    if (!_pageController.hasClients) return;
    for (var offset = 1; offset < _banners.length; offset++) {
      final next = (_currentIndex + offset) % _banners.length;
      if (_failedImages.contains(_banners[next].id)) continue;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
      return;
    }
  }

  void _recordImpression() {
    if (_banners.isEmpty || _visibleFraction < 0.5) return;
    final banner = _banners[_currentIndex];
    if (!_loadedImages.contains(banner.id) ||
        _failedImages.contains(banner.id)) {
      return;
    }
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

  void _onImageLoaded(int id) {
    if (!mounted || _loadedImages.contains(id)) return;
    setState(() => _loadedImages.add(id));
    _recordImpression();
  }

  void _onImageFailed(int id) {
    if (!mounted || _failedImages.contains(id)) return;
    setState(() => _failedImages.add(id));
    if (_banners[_currentIndex].id == id) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _advance());
    }
  }

  Future<void> _onTap(AdBanner banner) async {
    final destination = Uri.tryParse(banner.targetUrl);
    if (destination?.scheme == 'iljujob' && destination?.host == 'job') {
      final active = await AdBannerService.instance.fetchBanners(
        widget.placement,
      );
      if (!active.any((ad) => ad.id == banner.id)) {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('종료된 광고입니다.')));
        return;
      }
      final jobId = int.tryParse(destination!.pathSegments.firstOrNull ?? '');
      AdBannerService.instance.logEvent(banner.id, 'click', widget.placement);
      if (jobId != null) await widget.onInternalJobTap?.call(jobId);
      return;
    }

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
    if (_banners.isEmpty || _failedImages.length == _banners.length) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: widget.margin,
      child: VisibilityDetector(
        key: Key('ad_banner_${widget.placement}'),
        onVisibilityChanged: (info) {
          _visibleFraction = info.visibleFraction;
          _recordImpression();
          if (_banners.isNotEmpty &&
              _failedImages.contains(_banners[_currentIndex].id)) {
            _advance();
          }
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 4 / 1,
              child:
                  _banners.length == 1
                      ? _buildBanner(_banners.first)
                      : PageView.builder(
                        controller: _pageController,
                        itemCount: _banners.length,
                        onPageChanged: (index) {
                          setState(() => _currentIndex = index);
                          _recordImpression();
                          if (_failedImages.contains(_banners[index].id)) {
                            WidgetsBinding.instance.addPostFrameCallback(
                              (_) => _advance(),
                            );
                          }
                        },
                        itemBuilder:
                            (context, index) => _buildBanner(_banners[index]),
                      ),
            ),
            if (_banners.length > 1) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var index = 0; index < _banners.length; index++)
                    if (!_failedImages.contains(_banners[index].id))
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Container(
                          width: index == _currentIndex ? 12 : 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color:
                                index == _currentIndex
                                    ? AppColors.textPrimary
                                    : AppColors.textTertiary,
                            borderRadius: BorderRadius.circular(AppRadius.full),
                          ),
                        ),
                      ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBanner(AdBanner banner) {
    return Semantics(
      button: true,
      label:
          banner.title?.trim().isNotEmpty == true
              ? '${banner.title!.trim()} 보기'
              : '광고 배너 보기',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: const BoxDecoration(color: AppColors.bgMuted),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final dpr = MediaQuery.of(context).devicePixelRatio;
                  final cacheWidth = (constraints.maxWidth * dpr).ceil();
                  return Image.network(
                    _imageUrl(banner),
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.high,
                    cacheWidth: cacheWidth,
                    excludeFromSemantics: true,
                    frameBuilder: (context, child, frame, wasSyncLoaded) {
                      if (frame != null || wasSyncLoaded) {
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => _onImageLoaded(banner.id),
                        );
                      }
                      return child;
                    },
                    errorBuilder: (context, error, stackTrace) {
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => _onImageFailed(banner.id),
                      );
                      return const SizedBox.shrink();
                    },
                  );
                },
              ),
            ),
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap:
                      !_loadedImages.contains(banner.id) ||
                              _failedImages.contains(banner.id)
                          ? null
                          : () => _onTap(banner),
                  splashColor: Colors.black.withValues(alpha: 0.08),
                  highlightColor: Colors.black.withValues(alpha: 0.04),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
