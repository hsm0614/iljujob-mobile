import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:iljujob/config/constants.dart';
import '../../../data/models/job.dart';
import '../../../data/models/banner_ad.dart';
import '../../../data/services/job_service.dart';
import '../../../data/services/authenticated_http_client.dart';
import '../../../data/services/ai_api.dart';
import 'package:iljujob/widget/recommended_workers_sheet.dart';
import 'package:iljujob/presentation/screens/worker_screen/job_insight_sheet.dart';
import 'package:iljujob/presentation/screens/client_screen/wage_report_screen.dart';
import 'package:iljujob/presentation/screens/post_job/SelectPreviousJobScreen.dart';
import 'package:iljujob/widget/app_ui.dart';
import 'package:iljujob/widget/app_motion.dart';
import 'package:iljujob/config/app_theme.dart';
import 'package:iljujob/widget/ad_banner_widget.dart';
import 'package:iljujob/utils/pay_display.dart';
import 'package:iljujob/presentation/widgets/albailju_common.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:iljujob/presentation/screens/purchase_screen.dart';
import 'package:iljujob/presentation/screens/subscription_plans_screen.dart';
import '../../../data/services/client_tracking_service.dart';
import 'package:iljujob/main.dart'; // sendFcmTokenUnified

DateTime _nowLocal() => DateTime.now();

DateTime _toLocal(DateTime? dt) {
  if (dt == null) return DateTime.fromMillisecondsSinceEpoch(0);
  return dt.isUtc ? dt.toLocal() : dt;
}

DateTime _toUtc(DateTime? dt) {
  if (dt == null) return DateTime.fromMillisecondsSinceEpoch(0).toUtc();
  return dt.isUtc ? dt : dt.toUtc();
}

bool isJobReserved(Job j) {
  final dt = j.publishAt;
  if (dt == null) return false;
  return _toLocal(dt).isAfter(_nowLocal());
}

bool isJobPinned(Job j) {
  final dt = j.pinnedUntil;
  if (dt == null) return false;
  return _toUtc(dt).isAfter(DateTime.now().toUtc());
}

String pinnedRemainText(Job j) {
  if (!isJobPinned(j) || j.pinnedUntil == null) return '';
  final diff = _toUtc(j.pinnedUntil).difference(DateTime.now().toUtc());
  final h = diff.inHours;
  final m = diff.inMinutes % 60;
  return h > 0 ? '$h시간 $m분 남음' : '$m분 남음';
}

String publishRemainText(Job j) {
  if (!isJobReserved(j) || j.publishAt == null) return '';
  final diff = _toLocal(j.publishAt!).difference(_nowLocal());
  final h = diff.inHours;
  final m = diff.inMinutes % 60;
  if (h > 0) return '$h시간 $m분 후 노출';
  return m > 0 ? '$m분 후 노출' : '곧 노출';
}

class ClientHomeScreen extends StatefulWidget {
  final AiApi api;
  // 미확인 지원자 배너 탭 시 지원자관리 탭으로 전환 (main_screen이 넘김)
  final VoidCallback? onOpenApplicants;

  const ClientHomeScreen({super.key, required this.api, this.onOpenApplicants});

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // Data
  List<Job> myJobs = [];
  bool isLoading = false;
  static const String _bannerHideUntilKey = 'client_banner_hide_until';
  static const String _legacyBannerHiddenKey = 'client_banner_hidden';
  // Banner
  List<BannerAd> bannerAds = [];
  int _currentBannerIndex = 0;
  Timer? _bannerTimer;
  bool _isBannerHidden = false;
  late final PageController _pageController;

  // Paging
  int currentPage = 1;
  int totalPages = 1;
  int totalCount = 0;
  static const int pageSize = 10;

  // Filters
  String filterStatus = '전체';
  String sortType = '최신순';
  String payTypeFilter = '전체';
  String searchQuery = '';

  // Summary
  int unansweredCount = 0;
  int todayCount = 0;
  int weekCount = 0;
  int monthCount = 0;

  // Tabs

  // Safe company
  bool isSafeCompany = false;

  // ======= Utils =======
  String getExpiryText(Job job) {
    if (job.expiresAt == null) return '';

    final nowUtc = DateTime.now().toUtc();
    final expiresAtUtc = _toUtc(job.expiresAt);

    if (expiresAtUtc.isBefore(nowUtc)) return '만료되었습니다';

    final diff = expiresAtUtc.difference(nowUtc);
    final hours = diff.inHours;
    final minutes = diff.inMinutes % 60;

    if (hours > 24) {
      final days = hours ~/ 24;
      return '$days일 ${hours % 24}시간 후 만료됩니다';
    } else if (hours > 0) {
      return '$hours시간 $minutes분 후 만료됩니다';
    } else {
      return '$minutes분 후 만료됩니다';
    }
  }

  int _payToInt(String s) =>
      int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _showDeleteConfirm(Job job) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder:
          (dCtx) => Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    child: const Icon(
                      Icons.delete_rounded,
                      color: AppColors.error,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '공고 삭제',
                    style: TextStyle(fontSize: AppFontSize.titleLg, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '이 공고를 삭제할까요?\n삭제하면 되돌릴 수 없어요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: AppFontSize.button,
                      height: 1.35,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(dCtx, false),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                            ),
                            side: const BorderSide(color: AppColors.border),
                            foregroundColor: AppColors.textPrimary,
                          ),
                          child: const Text('취소'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(dCtx, true),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                            ),
                            backgroundColor: AppColors.error,
                            foregroundColor: Colors.white,
                            elevation: 0,
                          ),
                          child: const Text('삭제'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
    );

    if (confirm == true) {
      try {
        await JobService.deleteJob(job.id);
        if (!mounted) return;
        _toast('공고가 삭제되었습니다.');
        _loadMyJobs();
      } catch (_) {
        if (!mounted) return;
        _toast('삭제에 실패했습니다.');
      }
    }
  }

  // ======= Lifecycle =======
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ClientTrackingService.instance.init(baseUrl);
    ClientTrackingService.instance.startSession();

    _pageController = PageController(initialPage: 0);

    _requestNotificationPermission();
    _saveClientFcmToken();
    _fetchClientProfile();

    _loadBannerHidden();
    _loadBannerAds();

    _loadMyJobs();
    _loadSummaryData();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ClientTrackingService.instance.startSession();
    } else if (state == AppLifecycleState.paused) {
      ClientTrackingService.instance.endSession();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ClientTrackingService.instance.endSession();
    _bannerTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  // ======= Actions =======
  void _goToPage(int page) {
    if (page >= 1 && page <= totalPages && page != currentPage) {
      _loadMyJobs(page: page);
    }
  }

  // ======= Notification =======
  void _requestNotificationPermission() async {
    if (!Platform.isAndroid) return;
    try {
      await FirebaseMessaging.instance.requestPermission();
    } catch (e) {
      debugPrint('notification permission error: $e');
    }
  }

  // main.dart 의 sendFcmTokenUnified 로 위임.
  // 예전엔 !Platform.isAndroid 로 막혀 있어 iOS 사장님은 이 경로로 토큰을 못 올렸다.
  Future<void> _saveClientFcmToken() => sendFcmTokenUnified();

  // ======= Profile =======
  Future<void> _fetchClientProfile() async {
    try {
      final response = await AuthenticatedHttpClient.get(
        Uri.parse('$baseUrl/api/client/profile'),
      );
      if (response.statusCode == 200) {
        final raw = jsonDecode(response.body);
        final data = raw['data'] ?? raw;
        final String? certUrl = data['business_certificate_url'] as String?;
        if (!mounted) return;
        setState(() {
          isSafeCompany = certUrl != null && certUrl.isNotEmpty;
        });
      }
    } catch (e) {
      debugPrint('client profile error: $e');
    }
  }

  // ======= Summary =======
  Future<void> _loadSummaryData() async {
    final prefs = await SharedPreferences.getInstance();
    final clientId = prefs.getInt('userId') ?? 0;
    if (clientId == 0) return;

    try {
      final response = await AuthenticatedHttpClient.get(
        Uri.parse('$baseUrl/api/client/summary?clientId=$clientId'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (!mounted) return;
        setState(() {
          unansweredCount = data['unansweredApplicants'] ?? 0;
          todayCount = data['todayApplicants'] ?? 0;
          weekCount = data['weekApplicants'] ?? 0;
          monthCount = data['monthApplicants'] ?? 0;
        });
      }
    } catch (e) {
      debugPrint('summary load error: $e');
    }
  }

  // ======= Jobs =======
  Future<void> _loadMyJobs({int? page}) async {
    if (isLoading) return;
    final targetPage = page ?? currentPage;
    setState(() => isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final clientId = prefs.getInt('userId');
      if (clientId == null) {
        _toast('로그인 정보가 확인되지 않습니다.');
        return;
      }

      final response = await AuthenticatedHttpClient.get(
        Uri.parse(
          '$baseUrl/api/job/my-jobs?clientId=$clientId&page=$targetPage&limit=$pageSize',
        ),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final jobs =
            (data['jobs'] as List).map((json) => Job.fromJson(json)).toList();
        if (!mounted) return;
        setState(() {
          myJobs = jobs;
          currentPage = targetPage;
          totalPages = data['pagination']['totalPages'] ?? 1;
          totalCount = data['pagination']['totalCount'] ?? 0;
        });
      } else {
        _toast('공고 목록을 불러오지 못했습니다.');
      }
    } catch (e) {
      debugPrint('jobs load error: $e');
      _toast('공고 목록을 불러오는 중 오류가 발생했습니다.');
    } finally {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  List<Job> _filteredJobs() {
    DateTime postedAt(Job j) => _toLocal(j.publishAt ?? j.createdAt);
    int idInt(Job j) => int.tryParse(j.id.toString()) ?? 0;

    bool matchesQuery(Job j, String q) {
      final qq = q.trim().toLowerCase();
      if (qq.isEmpty) return true;
      String lc(Object? s) => (s?.toString() ?? '').toLowerCase();
      return lc(j.title).contains(qq) ||
          lc(j.location).contains(qq) ||
          lc(j.locationCity).contains(qq) ||
          lc(j.description).contains(qq);
    }

    var filtered = List<Job>.of(myJobs);

    if (filterStatus == '공고중') {
      filtered = filtered.where((j) => j.status == 'active').toList();
    } else if (filterStatus == '마감') {
      filtered = filtered.where((j) => j.status == 'closed').toList();
    }

    if (payTypeFilter != '전체') {
      filtered = filtered.where((j) => j.payType == payTypeFilter).toList();
    }

    if (searchQuery.trim().isNotEmpty) {
      filtered = filtered.where((j) => matchesQuery(j, searchQuery)).toList();
    }

    switch (sortType) {
      case '급여 높은 순':
        filtered.sort((a, b) {
          final cmp = _payToInt(b.pay).compareTo(_payToInt(a.pay));
          if (cmp != 0) return cmp;
          return idInt(b).compareTo(idInt(a));
        });
        break;
      case '오래된 순':
        filtered.sort((a, b) {
          final cmp = postedAt(a).compareTo(postedAt(b));
          if (cmp != 0) return cmp;
          return idInt(b).compareTo(idInt(a));
        });
        break;
      default:
        filtered.sort((a, b) {
          final cmp = postedAt(b).compareTo(postedAt(a));
          if (cmp != 0) return cmp;
          return idInt(b).compareTo(idInt(a));
        });
    }

    return filtered;
  }

  // ======= Banner =======
  Future<void> _loadBannerHidden() async {
    final prefs = await SharedPreferences.getInstance();

    final hideUntilStr = prefs.getString(_bannerHideUntilKey);
    final legacyHidden = prefs.getBool(_legacyBannerHiddenKey) ?? false;

    bool hidden = false;

    if (hideUntilStr != null && hideUntilStr.isNotEmpty) {
      final hideUntil = DateTime.tryParse(hideUntilStr);
      if (hideUntil != null) {
        hidden = DateTime.now().isBefore(hideUntil);
        if (!hidden) {
          await prefs.remove(_bannerHideUntilKey);
        }
      }
    } else if (legacyHidden) {
      // 예전 bool 저장값이 남아있는 사용자 정리
      hidden = false;
      await prefs.remove(_legacyBannerHiddenKey);
    }

    if (!mounted) return;
    setState(() => _isBannerHidden = hidden);

    if (!hidden && bannerAds.length > 1) {
      _startBannerAutoSlide();
    }
  }

  Future<void> _setBannerHidden(bool v) async {
    final prefs = await SharedPreferences.getInstance();

    if (v) {
      final now = DateTime.now();
      final hideUntil = DateTime(now.year, now.month, now.day + 1);

      await prefs.setString(_bannerHideUntilKey, hideUntil.toIso8601String());
      await prefs.remove(_legacyBannerHiddenKey);
    } else {
      await prefs.remove(_bannerHideUntilKey);
      await prefs.remove(_legacyBannerHiddenKey);
    }

    if (!mounted) return;
    setState(() => _isBannerHidden = v);

    if (v) {
      _bannerTimer?.cancel();
    } else {
      if (bannerAds.length > 1) _startBannerAutoSlide();
    }
  }

  void _startBannerAutoSlide() {
    _bannerTimer?.cancel();
    if (bannerAds.length <= 1) return;

    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      if (_isBannerHidden || bannerAds.isEmpty) return;
      if (!_pageController.hasClients) return;

      final nextPage = (_currentBannerIndex + 1) % bannerAds.length;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 480),
        curve: Curves.easeInOut,
      );
    });
  }

  Future<void> _recordBannerClick(int bannerId) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/api/banners/click'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"bannerId": bannerId}),
      );
    } catch (e) {
      debugPrint('banner click record error: $e');
    }
  }

  Future<void> _recordBannerImpression(int bannerId) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/api/banners/impression'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"bannerId": bannerId}),
      );
    } catch (e) {
      debugPrint('banner impression record error: $e');
    }
  }

  Future<void> _loadBannerAds() async {
    try {
      final uri = Uri.parse(
        '$baseUrl/api/banners',
      ).replace(queryParameters: {'audience': 'client', 'placement': 'home'});
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        if (!mounted) return;
        final loaded = data.map((json) => BannerAd.fromJson(json)).toList();
        setState(() {
          bannerAds = loaded;
          if (_currentBannerIndex >= bannerAds.length) _currentBannerIndex = 0;
        });
        if (!_isBannerHidden && bannerAds.isNotEmpty) {
          final id = int.tryParse(bannerAds[_currentBannerIndex].id.toString());
          if (id != null) _recordBannerImpression(id);
        }
        if (!_isBannerHidden && bannerAds.length > 1) _startBannerAutoSlide();
      }
    } catch (e) {
      debugPrint('banner load error: $e');
    }
  }

  // ignore: unused_element
  Widget _buildBannerSlider() {
    if (_isBannerHidden || bannerAds.isEmpty) return const SizedBox.shrink();
    final canNav = bannerAds.length > 1;

    Widget circleBtn(IconData icon, VoidCallback onTap) => ClipOval(
      child: Material(
        color: Colors.black.withValues(alpha: 0.20),
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 30,
            height: 30,
            child: Icon(icon, size: 18, color: Colors.white),
          ),
        ),
      ),
    );

    void goTo(int index) {
      if (!mounted || bannerAds.isEmpty || !_pageController.hasClients) return;
      final len = bannerAds.length;
      final safe = ((index % len) + len) % len;
      _pageController.animateToPage(
        safe,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: AspectRatio(
        aspectRatio: 4 / 1,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: PageView.builder(
                controller: _pageController,
                itemCount: bannerAds.length,
                onPageChanged: (index) {
                  setState(() => _currentBannerIndex = index);
                  final id = int.tryParse(bannerAds[index].id.toString());
                  if (id != null) _recordBannerImpression(id);
                },
                itemBuilder: (context, index) {
                  final banner = bannerAds[index];
                  return GestureDetector(
                    onTap: () async {
                      final bannerId = int.tryParse(banner.id.toString());
                      if (bannerId != null) _recordBannerClick(bannerId);
                      if (banner.linkUrl != null &&
                          banner.linkUrl!.isNotEmpty) {
                        final url = Uri.parse(banner.linkUrl!);
                        try {
                          await launchUrl(
                            url,
                            mode: LaunchMode.externalApplication,
                          );
                        } catch (_) {
                          _toast('링크를 열 수 없습니다.');
                        }
                      }
                    },
                    child: DecoratedBox(
                      decoration: const BoxDecoration(color: AppColors.bgMuted),
                      child: Image.network(
                        '$baseUrl${banner.imageUrl}',
                        fit: BoxFit.contain,
                        alignment: Alignment.center,
                        filterQuality: FilterQuality.high,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          );
                        },
                        errorBuilder:
                            (_, __, ___) => const Center(
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                color: AppColors.textTertiary,
                              ),
                            ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (canNav) ...[
              Positioned(
                left: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: circleBtn(
                    Icons.chevron_left,
                    () => goTo(_currentBannerIndex - 1),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: circleBtn(
                    Icons.chevron_right,
                    () => goTo(_currentBannerIndex + 1),
                  ),
                ),
              ),
            ],
            Positioned(
              top: 8,
              right: 8,
              child: ClipOval(
                child: Material(
                  color: Colors.black.withValues(alpha: 0.18),
                  child: InkWell(
                    onTap: () => _setBannerHidden(true),
                    child: const SizedBox(
                      width: 28,
                      height: 28,
                      child: Icon(Icons.close, size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  bannerAds.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: _currentBannerIndex == i ? 18 : 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      color:
                          _currentBannerIndex == i
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ======= Recommended Workers + Paywall =======
  Future<void> _openRecommendedWorkersByJobId(String jobIdStr) async {
    final jid = int.tryParse(jobIdStr);
    if (jid == null) {
      _toast('공고 ID가 올바르지 않습니다.');
      return;
    }

    try {
      final api = AiApi(baseUrl);
      final sub = await api.fetchMySubscription();
      final isSubscribed =
          sub.active && (sub.plan != null && sub.plan!.toLowerCase() != 'free');

      if (!isSubscribed) {
        await _showPaywall();
        return;
      }
      if (!mounted) return;

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useRootNavigator: true,
        backgroundColor: Colors.transparent,
        builder:
            (_) => FractionallySizedBox(
              heightFactor: 0.90,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadius.lg),
                ),
                child: Material(
                  color: AppColors.bgCard,
                  child: RecommendedWorkersSheet(
                    api: AiApi(baseUrl),
                    jobId: jid,
                  ),
                ),
              ),
            ),
      );
    } catch (e) {
      debugPrint('open recommended workers error: $e');
      _toast('추천 인재를 불러오는 중 오류가 발생했습니다.');
    }
  }

  Future<void> _showPaywall() async {
    FirebaseAnalytics.instance.logEvent(name: 'client_paywall_shown');
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) {
        final mq = MediaQuery.of(ctx);
        final bottomInset = mq.viewInsets.bottom;
        final bottomPad = mq.padding.bottom;

        return FractionallySizedBox(
          heightFactor: 0.62,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
            child: Material(
              color: AppColors.bgCard,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    16 + bottomInset + bottomPad,
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                        ),
                        child: const Icon(
                          Icons.recommend_outlined,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '맞춤 인재 기능은 구독 전용입니다',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: AppFontSize.buttonLg,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '공고 조건에 맞는 인재를 추천해요.\n구독하면 이용할 수 있어요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('닫기'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            Navigator.pushNamed(context, '/subscribe');
                          },
                          child: const Text(
                            '구독하기',
                            style: TextStyle(color: Colors.white),
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
      },
    );
  }

  // 답장 안 한 지원자 — 있을 때만, 회색 한 줄 (파랑은 누를 수 있는 글자에만)
  Widget _buildUnansweredBanner() {
    if (unansweredCount <= 0) return const SizedBox.shrink();
    return Material(
      color: AppColors.bgCard,
      child: InkWell(
        onTap: widget.onOpenApplicants,
        child: Container(
          margin: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.bgMuted,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: AppTextStyles.body2.copyWith(color: AppColors.textPrimary),
                    children: [
                      const TextSpan(text: '답장 기다리는 지원자 '),
                      TextSpan(
                        text: '$unansweredCount명',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  // 안심기업 인증 — 주황 카드 → 목록 맨 아래 회색 한 줄
  Widget _buildSafeCompanyPrompt() {
    if (isSafeCompany) return const SizedBox.shrink();
    return InkWell(
      onTap: () => Navigator.pushNamed(context, '/edit_profile'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
        child: Row(
          children: [
            const Icon(Icons.verified_user_outlined, size: 18, color: AppColors.textTertiary),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('안심기업 인증을 받으면 공고에 인증 표시가 붙어요', style: AppTextStyles.body2),
            ),
            Text('인증하기', style: AppTextStyles.body2.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  // 검색 — 공고가 많을 때만 (10개 넘으면 목록이 페이지로 나뉜다)
  Widget _buildSearchBar() {
    if (totalCount < 8 && searchQuery.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: TextField(
        style: AppTextStyles.body1,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          hintText: '공고 제목·지역 검색',
          filled: true,
          fillColor: AppColors.bgMuted,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
        onChanged: (val) => setState(() => searchQuery = val),
      ),
    );
  }

  // 급구 '진행중 | 종료' 밑줄 탭 + 필터 칩 한 줄 (탭 두 줄 + 정렬·보기 버튼을 하나로)
  Widget _buildFilterHeader() {
    final single = totalPages <= 1; // 한 페이지일 때만 개수가 정확하다
    int n(String st) => myJobs.where((j) => st == '전체' || j.status == (st == '공고중' ? 'active' : 'closed')).length;
    Widget tab(String label, String value) {
      final on = filterStatus == value;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => filterStatus = value),
          child: Container(
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: on ? AppColors.textPrimary : AppColors.border, width: on ? 2 : 1),
              ),
            ),
            child: Text(
              single ? '$label ${n(value)}' : label,
              style: AppTextStyles.body1.copyWith(
                fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                color: on ? AppColors.textPrimary : AppColors.textTertiary,
              ),
            ),
          ),
        ),
      );
    }

    Widget chip(String label, bool on, VoidCallback onTap, {bool arrow = false}) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: on ? AppColors.textPrimary : AppColors.bgCard,
        shape: StadiumBorder(side: BorderSide(color: on ? AppColors.textPrimary : AppColors.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: AppTextStyles.body2.copyWith(color: on ? Colors.white : AppColors.textPrimary)),
                if (arrow) Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: on ? Colors.white : AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );

    return Container(
      color: AppColors.bgCard,
      child: Column(
        children: [
          Row(children: [tab('전체', '전체'), tab('모집중', '공고중'), tab('마감', '마감')]),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            // 칩이 화면보다 짧으면 가운데로 몰린다 — 넓이를 화면 폭 이상으로 잡아 왼쪽에 붙인다
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: MediaQuery.sizeOf(context).width),
              child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
            child: Row(
              children: [
                chip(sortType, false, _pickSort, arrow: true),
                for (final t in const ['일급', '주급'])
                  chip(t, payTypeFilter == t, () => setState(() => payTypeFilter = payTypeFilter == t ? '전체' : t)),
              ],
            ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickSort() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      builder:
          (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                for (final t in const ['최신순', '오래된 순', '급여 높은 순'])
                  AppMenuRow(
                    label: t,
                    trailing: sortType == t ? const Icon(Icons.check_rounded, color: AppColors.primary, size: 20) : const SizedBox.shrink(),
                    onTap: () => Navigator.pop(ctx, t),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
    );
    if (v != null && mounted) setState(() => sortType = v);
  }

  Widget _buildEmptyJobsState({required bool hasAnyJobs}) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Container(
        color: AppColors.bgCard,
        child: hasAnyJobs
            ? const AppEmptyState(icon: Icons.filter_list_off_rounded, title: '조건에 맞는 공고가 없어요')
            : AppEmptyState(
              icon: Icons.post_add_rounded,
              title: '첫 공고를 올려 보세요',
              message: '공고를 올리면 근처 알바생이 지원하고, 여기서 바로 확인할 수 있어요.',
              actionLabel: '공고 올리기',
              onAction: _goToPostJobFlow,
            ),
      ),
    );
  }

  // ======= Pagination =======
  Widget _buildPaginationWidget() {
    if (totalPages <= 1) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 22),
      child: Column(
        children: [
          Text(
            '총 $totalCount개 공고 · $currentPage/$totalPages페이지',
            style: const TextStyle(
              fontSize: AppFontSize.meta,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _pageIconBtn(
                  Icons.first_page,
                  enabled: currentPage > 1,
                  onTap: () => _goToPage(1),
                ),
                _pageIconBtn(
                  Icons.chevron_left,
                  enabled: currentPage > 1,
                  onTap: () => _goToPage(currentPage - 1),
                ),
                ..._buildPageNumbers(),
                _pageIconBtn(
                  Icons.chevron_right,
                  enabled: currentPage < totalPages,
                  onTap: () => _goToPage(currentPage + 1),
                ),
                _pageIconBtn(
                  Icons.last_page,
                  enabled: currentPage < totalPages,
                  onTap: () => _goToPage(totalPages),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pageIconBtn(
    IconData icon, {
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: SizedBox(
        width: 38,
        height: 38,
        child: IconButton(
          onPressed: enabled ? onTap : null,
          icon: Icon(icon, size: 18),
          splashRadius: 20,
        ),
      ),
    );
  }

  List<Widget> _buildPageNumbers() {
    List<Widget> pageButtons = [];
    int startPage = (currentPage - 1).clamp(1, totalPages);
    int endPage = (currentPage + 1).clamp(1, totalPages);

    if (startPage > 1) {
      pageButtons.add(_pageNumBtn(1));
      if (startPage > 2) {
        pageButtons.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text('...', style: TextStyle(color: AppColors.textTertiary)),
          ),
        );
      }
    }
    for (int i = startPage; i <= endPage; i++) {
      pageButtons.add(_pageNumBtn(i));
    }
    if (endPage < totalPages) {
      if (endPage < totalPages - 1) {
        pageButtons.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text('...', style: TextStyle(color: AppColors.textTertiary)),
          ),
        );
      }
      pageButtons.add(_pageNumBtn(totalPages));
    }
    return pageButtons;
  }

  Widget _pageNumBtn(int page) {
    final isCurrent = page == currentPage;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: isCurrent ? null : () => _goToPage(page),
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isCurrent ? AppColors.primary : AppColors.bgCard,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: isCurrent ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            '$page',
            style: TextStyle(
              fontSize: AppFontSize.meta,
              fontWeight: FontWeight.w800,
              color: isCurrent ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  // ======= Job Cards =======
  // ⋯ 공고 관리 — 카드에서 뺀 행동이 모두 여기. 인사이트·맞춤 인재는 구독 전용이라 안내를 붙였다(각 화면이 구독을 다시 확인).
  Future<void> _openJobActions(Job job) async {
    final isClosed = job.status == 'closed';
    final reserved = isJobReserved(job);
    Widget row(IconData icon, String label, String value, {String? subtitle}) =>
        AppMenuRow(icon: icon, label: label, subtitle: subtitle, onTap: () => Navigator.pop(context, value));

    final v = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder:
          (ctx) => SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Text(job.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.h3),
                  ),
                  row(Icons.people_outline_rounded, '지원자 보기', 'applicants'),
                  if (!isClosed) row(Icons.edit_outlined, '공고 수정', 'edit'),
                  if (reserved) row(Icons.publish_rounded, job.isPaid ? '예약 공고 바로 공개' : '지금 바로 공개', 'publish-now', subtitle: job.isPaid ? null : '즉시 게시 이용권 1개'),
                  if (!isClosed && job.isUrgent) row(Icons.bolt_rounded, '긴급 호출 보내기', 'urgent-call'),
                  if (isClosed) row(Icons.replay_rounded, '같은 조건으로 다시 올리기', 'repost'),
                  row(Icons.insights_rounded, '공고 인사이트', 'insight', subtitle: '구독 전용'),
                  row(Icons.analytics_outlined, '임금 리포트', 'wage', subtitle: '같은 업종·지역 급여와 비교'),
                  if (!isClosed) row(Icons.person_search_outlined, '맞춤 인재 추천', 'recommend', subtitle: '구독 전용'),
                  const Divider(height: 1, color: AppColors.borderSub),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    title: Text('공고 삭제', style: AppTextStyles.body1.copyWith(color: AppColors.error)),
                    onTap: () => Navigator.pop(ctx, 'delete'),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
    );

    if (v == null || !mounted) return;

    switch (v) {
      case 'edit':
        Navigator.pushNamed(context, '/edit_job', arguments: job.id);
        break;
      case 'detail':
        Navigator.pushNamed(context, '/job-detail', arguments: job);
        break;
      case 'applicants':
        FirebaseAnalytics.instance.logEvent(name: 'client_applicants_tap');
        Navigator.pushNamed(context, '/applicants', arguments: job.id);
        break;
      case 'insight':
        final jobId = int.tryParse(job.id.toString());
        if (jobId != null) {
          JobInsightSheet.show(context, jobId: jobId, jobTitle: job.title);
        }
        break;
      case 'publish-now':
        await _upgradeToInstant(job);
        break;
      case 'repost':
        _repost(job);
        break;
      case 'wage':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) => WageReportScreen(
                  category: job.category,
                  locationCity: job.locationCity,
                  payType: job.payType,
                  currentPay: int.tryParse(job.pay.replaceAll(RegExp(r'[^0-9]'), '')),
                ),
          ),
        );
        break;
      case 'recommend':
        await _openRecommendedWorkersByJobId(job.id.toString());
        break;
      case 'urgent-call':
        final prefs = await SharedPreferences.getInstance();
        final clientId = prefs.getInt('userId');
        if (clientId != null) {
          Navigator.pushNamed(
            context,
            '/nearby-workers',
            arguments: {
              'jobId': job.id,
              'clientId': clientId,
              'jobTitle': job.title,
            },
          );
        }
        break;
      case 'delete':
        FirebaseAnalytics.instance.logEvent(name: 'client_delete_tap');
        await _showDeleteConfirm(job);
        break;
    }
  }

  Future<void> _upgradeToInstant(Job job) async {
    final jobId = int.tryParse(job.id.toString());
    if (jobId == null) return;

    // 유료 예약 공고는 이용권 차감 없이 바로 즉시게시
    if (job.isPaid) {
      try {
        await JobService.publishNow(jobId);
        _toast('공고가 즉시 게시되었습니다.');
        _loadMyJobs();
      } catch (_) {
        _toast('즉시 게시에 실패했습니다.');
      }
      return;
    }

    // v3는 결제기간 제공량, 구버전은 기존 지급 이용권을 따로 사용한다.
    final sub = await AiApi(baseUrl).fetchMySubscription();
    final isUnlimited =
        sub.active &&
        sub.plan == 'pro' &&
        (sub.entitlementVersion == 'v3' ||
            sub.entitlementVersion == null ||
            sub.entitlementVersion == 'legacy_v1');
    final v3Available =
        sub.active &&
        sub.entitlementVersion == 'v3' &&
        (sub.instantRemaining == -1 || (sub.instantRemaining ?? 0) > 0);
    if (!mounted) return;

    // 무료 공고 → 즉시게시 확인 바텀시트
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder:
          (_) => Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  '즉시게시로 전환할까요?',
                  style: TextStyle(
                    fontSize: AppFontSize.titleLg,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  v3Available
                      ? '선택한 이 공고에 구독 즉시게시 혜택을 적용합니다. 다른 공고는 변경되지 않습니다.'
                      : isUnlimited
                      ? '구독 혜택으로 즉시 게시됩니다. 이용권 차감 없이 지금 바로 공고를 노출합니다.'
                      : '즉시게시 이용권 1개를 사용해 12시간 기다리지 않고 바로 노출합니다.\n노출 기간이 3일에서 7일로 늘어납니다.',
                  style: const TextStyle(
                    fontSize: AppFontSize.button,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                        ),
                        child: const Text(
                          '취소',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          v3Available || isUnlimited ? '즉시 게시' : '이용권 사용',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await JobService.publishNow(jobId);
      _toast('공고가 즉시 게시되었습니다.');
      _loadMyJobs();
    } on NoPassException {
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
        builder:
            (_) => Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '이용권이 없어요',
                    style: TextStyle(
                      fontSize: AppFontSize.titleLg,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '즉시게시 이용권을 구매하거나 구독 플랜을 이용해보세요.',
                    style: TextStyle(
                      fontSize: AppFontSize.button,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (_) => const PurchasePassScreen(
                                  fromPostJob: false,
                                ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        '이용권 구매하기',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        final purchased = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SubscriptionPlansScreen(),
                          ),
                        );
                        if (!mounted || purchased != true) return;
                        try {
                          await JobService.publishNow(jobId);
                          _toast('선택한 공고가 즉시 게시되었습니다.');
                          _loadMyJobs();
                        } catch (_) {
                          _toast(
                            '구독은 시작됐지만 이 공고는 아직 예약 상태예요. 공고에서 즉시게시를 다시 눌러주세요.',
                          );
                        }
                      },
                      child: const Text('구독하고 이 공고 게시하기'),
                    ),
                  ),
                ],
              ),
            ),
      );
    } catch (_) {
      _toast('즉시 게시에 실패했습니다.');
    }
  }

  // 급구 '내 일감' 카드 뼈대 (2026-10): 상태 칩 → 근무일·시간(가장 큼) → 제목·급여(회색) → 지원·조회 두 칸 → 상태별 행동 한 줄.
  // 버튼 6개(큰 파란 띠 + 둥근 버튼 3개)였던 것 → 카드 자체가 지원자 목록 입구, 나머지는 ⋯ 안으로.
  Widget _buildJobCard(Job job, {required bool last}) {
    final isClosed = job.status == 'closed';
    final reserved = isJobReserved(job);
    final pinned = isJobPinned(job);
    final when = [
      if (formatWorkDays(job.startDate, job.endDate, job.weekdays) case final d?) d,
      if (job.workingHours.replaceAll('~', '').trim().isNotEmpty) job.workingHours,
    ].join(' ');
    final chips = <Widget>[
      if (isClosed)
        const JobSignalBadge(label: '마감')
      else if (reserved)
        const JobSignalBadge(label: '공개 대기')
      else
        const JobSignalBadge(label: '모집중', signal: JobSignal.trust),
      if (job.isUrgent && !isClosed)
        const JobSignalBadge(label: '긴급', signal: JobSignal.time, icon: Icons.bolt_rounded),
      if (pinned && !isClosed) const JobSignalBadge(label: '상단 고정'),
      if (job.isSameDayPay) const JobSignalBadge(label: '당일지급', signal: JobSignal.money),
      if (isClosed && job.zeroApplicantRefunded)
        const JobSignalBadge(label: '이용권 환급', signal: JobSignal.money),
    ];

    // 상태별 행동 하나 (글자 링크) — 없으면 줄 자체가 없다
    (String, String, VoidCallback)? next;
    if (isClosed) {
      next = ('', '같은 조건으로 다시 올리기', () => _repost(job));
    } else if (reserved && !job.isPaid) {
      next = ('${publishRemainText(job)} 공개', '지금 바로 공개', () => _upgradeToInstant(job));
    } else if (reserved) {
      next = (publishRemainText(job), '', () {});
    } else if (job.isUrgent) {
      next = ('', '근처 알바생에게 긴급 호출', () => _openUrgentCall(job));
    } else if (pinned) {
      next = ('상단 고정 ${pinnedRemainText(job)}', '', () {});
    }

    Widget cell(String label, int n, VoidCallback onTap) => Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label, style: AppTextStyles.body2),
              const SizedBox(width: 6),
              Text(
                '$n',
                style: AppTextStyles.body1.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    void openApplicants() {
      FirebaseAnalytics.instance.logEvent(name: 'client_applicants_tap');
      Navigator.pushNamed(context, '/applicants', arguments: job.id);
    }

    return Material(
      color: AppColors.bgCard,
      child: InkWell(
        onTap: () => Navigator.pushNamed(context, '/job-detail', arguments: job),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
          decoration: BoxDecoration(
            border: last ? null : const Border(bottom: BorderSide(color: AppColors.borderSub, width: 8)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Wrap(spacing: 6, runSpacing: 6, children: chips)),
                  IconButton(
                    tooltip: '공고 관리',
                    onPressed: () => _openJobActions(job),
                    icon: const Icon(Icons.more_horiz_rounded, color: AppColors.textTertiary),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 6),
                    Text(
                      when.isEmpty ? job.title : when,
                      style: AppTextStyles.h3.copyWith(
                        color: isClosed ? AppColors.textTertiary : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [if (when.isNotEmpty) job.title, formatJobPay(job.pay, job.payType, includeType: true)].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body2,
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: IntrinsicHeight(
                        child: Row(
                          children: [
                            cell('지원', job.applicantCount, openApplicants),
                            const VerticalDivider(width: 1, color: AppColors.border),
                            cell('조회', job.viewCount, () => Navigator.pushNamed(context, '/job-detail', arguments: job)),
                          ],
                        ),
                      ),
                    ),
                    if (next != null) ...[
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: next.$3,
                        behavior: HitTestBehavior.opaque,
                        child: Text.rich(
                          TextSpan(
                            style: AppTextStyles.body2,
                            children: [
                              if (next.$1.isNotEmpty) TextSpan(text: next.$1),
                              if (next.$1.isNotEmpty && next.$2.isNotEmpty) const TextSpan(text: ' · '),
                              if (next.$2.isNotEmpty)
                                TextSpan(
                                  text: '${next.$2} >',
                                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
                                ),
                            ],
                          ),
                        ),
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

  void _repost(Job job) {
    FirebaseAnalytics.instance.logEvent(name: 'client_repost_tap');
    Navigator.pushNamed(context, '/post_job', arguments: {'isRepost': true, 'existingJob': job});
  }

  Future<void> _openUrgentCall(Job job) async {
    final prefs = await SharedPreferences.getInstance();
    final cid = prefs.getInt('userId');
    if (cid == null || !mounted) return;
    Navigator.pushNamed(
      context,
      '/nearby-workers',
      arguments: {'jobId': job.id, 'clientId': cid, 'jobTitle': job.title},
    );
  }

  // ======= AppBar CTA =======
  Future<void> _goToPostJobFlow() async {
    FirebaseAnalytics.instance.logEvent(name: 'client_post_job_tap');
    final prefs = await SharedPreferences.getInstance();
    final clientId = prefs.getInt('userId');
    if (clientId == null) {
      _toast('로그인 정보가 확인되지 않습니다.');
      return;
    }

    // 사업자 인증 체크 제거 — 바로 공고 등록으로.
    // 올린 공고가 있으면 '이전 공고 불러오기'를 같이 묻는다 (목록 위 빠른 등록 카드를 여기로 합침)
    if (myJobs.isEmpty) {
      Navigator.pushNamed(context, '/post_job');
      return;
    }
    final v = await showModalBottomSheet<String>(
      context: context,
      builder:
          (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                AppMenuRow(
                  icon: Icons.history_rounded,
                  label: '이전 공고 불러와 올리기',
                  subtitle: '날짜와 급여만 바꿔 바로 올려요',
                  onTap: () => Navigator.pop(ctx, 'quick'),
                ),
                AppMenuRow(
                  icon: Icons.edit_note_rounded,
                  label: '새 공고 쓰기',
                  onTap: () => Navigator.pop(ctx, 'new'),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
    );
    if (!mounted) return;
    if (v == 'quick') await _goToQuickPostFlow();
    if (v == 'new') Navigator.pushNamed(context, '/post_job');
  }

  Future<void> _goToQuickPostFlow() async {
    FirebaseAnalytics.instance.logEvent(name: 'client_quick_post_tap');
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const SelectPreviousJobScreen(quickMode: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final jobs = _filteredJobs();

    return Scaffold(
      backgroundColor: AppColors.bgPage,
      appBar: AlbailjuAppBar(
        title: '공고 관리',
        brand: true,
        actions: [
          TextButton.icon(
            onPressed: _goToPostJobFlow,
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('공고 올리기'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              textStyle: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _fetchClientProfile();
          await _loadSummaryData();
          await _loadBannerAds();
          await _loadMyJobs(page: currentPage);
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildFilterHeader()),
            SliverToBoxAdapter(
              child: Container(
                color: AppColors.bgCard,
                child: Column(children: [_buildUnansweredBanner(), _buildSearchBar()]),
              ),
            ),
            const SliverToBoxAdapter(child: Divider(height: 1, color: AppColors.border)),
            if (isLoading)
              const SliverFillRemaining(child: AppSkeletonList(rows: 4))
            else if (jobs.isEmpty)
              _buildEmptyJobsState(hasAnyJobs: myJobs.isNotEmpty)
            else ...[
              SliverList.builder(
                itemCount: jobs.length,
                itemBuilder:
                    (context, index) => Column(
                      children: [
                        AppFadeSlideIn(
                          key: ValueKey('cjob_${jobs[index].id}'),
                          index: index,
                          child: _buildJobCard(jobs[index], last: index == jobs.length - 1),
                        ),
                        // 배너는 공고 3개 뒤 (공고가 먼저) — 3개 미만이면 맨 끝
                        if (index == 2 || (jobs.length < 3 && index == jobs.length - 1))
                          const AdBannerWidget(
                            placement: 'app_home_owner',
                            margin: EdgeInsets.fromLTRB(20, 12, 20, 12),
                          ),
                      ],
                    ),
              ),
              SliverToBoxAdapter(child: _buildPaginationWidget()),
            ],
            SliverToBoxAdapter(child: _buildSafeCompanyPrompt()),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

}

