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
import '../../../data/services/commerce_catalog_service.dart';
import '../../../data/services/ai_api.dart';
import 'package:iljujob/widget/recommended_workers_sheet.dart';
import 'package:iljujob/presentation/screens/worker_screen/job_insight_sheet.dart';
import 'package:iljujob/presentation/screens/client_screen/wage_report_screen.dart';
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
import 'package:iljujob/presentation/screens/post_job/promotion_request_screen.dart';
import 'package:iljujob/presentation/screens/post_job/post_choose_screen.dart';

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
  final at = _toLocal(j.publishAt!);
  final diff = at.difference(_nowLocal());
  final h = diff.inHours;
  final m = diff.inMinutes % 60;
  // 하루 넘게 남으면 시각으로 — '10264시간 17분 후'가 나왔다
  if (h >= 24) return '${at.month}월 ${at.day}일 ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
  if (h > 0) return '$h시간 $m분 후';
  return m > 0 ? '$m분 후' : '곧';
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
  String companyName = '';
  int? freeRemaining; // 이번 달 무료 등록 남은 횟수 (모르면 null)
  bool _loadedOnce = false; // 첫 조회 전엔 '공고 없음' 화면을 띄우지 않는다

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
                          child: const Text('취소'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(dCtx, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.error,
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
    _loadFreeQuota();
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
          companyName = '${data['company_name'] ?? ''}'.trim();
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
          _loadedOnce = true;
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

    // 노출이 끝난 공고는 status가 active여도 마감 (카드와 같은 기준)
    if (filterStatus == '공고중') {
      filtered = filtered.where(_isLive).toList();
    } else if (filterStatus == '마감') {
      filtered = filtered.where((j) => !_isLive(j)).toList();
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
    if (sortType == '최신순') {
      // 모집 중 공고가 위 — 마감은 아래에서 '다시 올리기'로 (한 페이지 안에서만)
      filtered = [...filtered.where(_isLive), ...filtered.where((j) => !_isLive(j))];
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
                          onPressed: () {
                            Navigator.pop(ctx);
                            Navigator.pushNamed(context, '/subscribe');
                          },
                          child: const Text(
                            '구독하기'),
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

  // 위쪽 안내 줄 공용 모양 — 회색 바탕 한 줄, 오른쪽 화살표 (파랑은 누를 글자에만)
  Widget _noticeRow({required IconData icon, required InlineSpan text, required VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Material(
        color: AppColors.bgMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              children: [
                Icon(icon, size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(text, style: AppTextStyles.body2.copyWith(color: AppColors.textPrimary)),
                ),
                const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 답장 기다리는 지원자 — 있을 때만
  Widget _buildUnansweredBanner() {
    if (unansweredCount <= 0) return const SizedBox.shrink();
    return _noticeRow(
      icon: Icons.mark_chat_unread_outlined,
      onTap: widget.onOpenApplicants,
      text: TextSpan(
        children: [
          const TextSpan(text: '답장 기다리는 지원자 '),
          TextSpan(text: '$unansweredCount명', style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  // 안심기업 인증 — 주황 카드 → 같은 회색 안내 줄 (인증 전까지 위에 남는다)
  Widget _buildSafeCompanyPrompt() {
    if (isSafeCompany) return const SizedBox.shrink();
    return _noticeRow(
      icon: Icons.verified_user_outlined,
      onTap: () => Navigator.pushNamed(context, '/edit_profile'),
      text: const TextSpan(
        children: [
          TextSpan(text: '안심기업 인증', style: TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: '을 받으면 공고에 인증 표시가 붙어요'),
        ],
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
    int n(String st) => myJobs.where((j) => st == '전체' || _isLive(j) == (st == '공고중')).length;
    Widget chip(String label, bool on, VoidCallback onTap, {bool arrow = false}) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: on ? AppColors.primary : AppColors.bgCard,
        shape: StadiumBorder(side: BorderSide(color: on ? AppColors.primary : AppColors.border)),
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

    // 시안 2번: 큰 제목 하나로 시작한다. 거르기·정렬은 공고가 많을 때만 (밑줄 탭은 관리 목록처럼 보였다)
    return Container(
      color: AppColors.bgCard,
      padding: const EdgeInsets.fromLTRB(20, 12, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: '내 공고 '),
              TextSpan(text: '$totalCount', style: const TextStyle(color: AppColors.primary)),
            ]),
            style: AppTextStyles.h1.copyWith(fontWeight: FontWeight.w700, height: 1.4),
          ),
          if (totalCount > 3)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Row(
                children: [
                  for (final (label, value) in const [('전체', '전체'), ('모집중', '공고중'), ('마감', '마감')])
                    chip(single ? '$label ${n(value)}' : label, filterStatus == value, () => setState(() => filterStatus = value)),
                  if (totalCount >= 8) ...[
                    chip(sortType, false, _pickSort, arrow: true),
                    for (final t in const ['일급', '주급'])
                      chip(t, payTypeFilter == t, () => setState(() => payTypeFilter = payTypeFilter == t ? '전체' : t)),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 8),
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
  // ⋯ 공고 관리 (토스 액션 시트 모양, 2026-10): 공고 요약 → 자주 쓰는 두 칸(지원자·수정)
  // → 이 상태에서 할 일 하나(파란 버튼) → 나머지는 화살표 없는 짧은 줄 → 삭제는 맨 아래 작은 빨간 글자.
  Future<void> _openJobActions(Job job) async {
    final isClosed = job.status == 'closed';
    final reserved = isJobReserved(job);
    final when = [
      if (formatWorkDays(job.startDate, job.endDate, job.weekdays) case final d?) d,
      if (job.workingHours.replaceAll('~', '').trim().isNotEmpty) job.workingHours,
    ].join(' ');

    // 상태별 주 행동 (카드 맨 아래 줄과 같은 것)
    final (String, String)? primary =
        isClosed
            ? ('같은 조건으로 다시 올리기', 'repost')
            : reserved && !job.isPaid
            ? ('지금 바로 공개 · 즉시 게시 이용권 1개', 'publish-now')
            : reserved
            ? ('예약 공고 바로 공개', 'publish-now')
            : job.isUrgent
            ? ('근처 알바생에게 긴급 호출', 'urgent-call')
            : null;

    final v = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        Widget tile(IconData icon, String label, String value, {String? sub}) => Expanded(
          child: Material(
            color: AppColors.bgMuted,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: () => Navigator.pop(ctx, value),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Column(
                  children: [
                    Icon(icon, size: 22, color: AppColors.textPrimary),
                    const SizedBox(height: 6),
                    Text(sub == null ? label : '$label $sub', style: AppTextStyles.body2.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
        );
        Widget line(String label, String value, {bool locked = false}) => InkWell(
          onTap: () => Navigator.pop(ctx, value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                Expanded(child: Text(label, style: AppTextStyles.body1)),
                if (locked)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: AppColors.bgMuted, borderRadius: BorderRadius.circular(AppRadius.full)),
                    child: const Text('구독', style: AppTextStyles.caption),
                  ),
              ],
            ),
          ),
        );

        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(job.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.h3),
                      const SizedBox(height: 2),
                      Text(
                        [if (when.isNotEmpty) when, formatJobPay(job.pay, job.payType, includeType: true)].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body2,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      tile(Icons.people_outline_rounded, '지원자', 'applicants', sub: '${job.applicantCount}'),
                      const SizedBox(width: 8),
                      if (!isClosed)
                        tile(Icons.edit_outlined, '수정', 'edit')
                      else
                        tile(Icons.description_outlined, '공고 보기', 'detail'),
                    ],
                  ),
                ),
                if (primary != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: AppPrimaryButton(label: primary.$1, onPressed: () => Navigator.pop(ctx, primary.$2)),
                  ),
                const SizedBox(height: 12),
                const Divider(height: 1, color: AppColors.borderSub),
                line('공고 인사이트', 'insight', locked: true),
                if (!isClosed) line('맞춤 인재 추천', 'recommend', locked: true),
                line('임금 리포트 · 같은 업종 급여 비교', 'wage'),
                if (job.isPaid && !isClosed) line(job.aiReplyOn ? 'AI 응대 끄기' : 'AI 응대 켜기', 'ai-reply'),
                const Divider(height: 1, color: AppColors.borderSub),
                InkWell(
                  onTap: () => Navigator.pop(ctx, 'delete'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    child: Text('공고 삭제', style: AppTextStyles.body1.copyWith(color: AppColors.error)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
      case 'ai-reply':
        await _toggleAiReply(job);
        break;
    }
  }

  // 게시 후 AI 응대 켜고 끄기. 켤 때는 기본 질문(근무 날짜)만 — 세부 질문은 게시 시트에서 고른다.
  // 끄면 진행 중인 대화에서도 AI가 더 답하지 않는다(서버 loadAiJob).
  Future<void> _toggleAiReply(Job job) async {
    final turnOn = !job.aiReplyOn;
    try {
      final resp = await AuthenticatedHttpClient.patchJson(
        Uri.parse('$baseUrl/api/job/${job.id}/ai-reply'),
        body: turnOn ? {'enabled': true, 'checks': ['date']} : {'enabled': false},
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        _toast(turnOn ? 'AI 응대를 켰어요. 새 지원자에게 AI가 먼저 물어봐요.' : 'AI 응대를 껐어요.');
        await _loadMyJobs();
        return;
      }
      final body = jsonDecode(resp.body);
      if (body is Map && body['code'] == 'AI_REPLY_JOB_INCOMPLETE') {
        const names = {'pay': '급여', 'location': '근무지', 'time': '근무 시간', 'description': '상세 설명 50자'};
        final missing = ((body['missing'] as List?) ?? []).map((k) => names[k] ?? '$k').join(' · ');
        final edit = await showAppSheet(
          context,
          title: '공고 정보를 더 채워야 켤 수 있어요',
          message: 'AI는 공고에 적힌 내용으로만 답해요.\n채울 것: $missing',
          confirmLabel: '수정하러 가기',
          cancelLabel: '닫기',
        );
        if (edit && mounted) Navigator.pushNamed(context, '/edit_job', arguments: job.id);
        return;
      }
      _toast(body is Map && body['message'] != null ? '${body['message']}' : '설정을 바꾸지 못했어요.');
    } catch (_) {
      if (mounted) _toast('설정을 바꾸지 못했어요.');
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
    var sevenDayAvailable = false;
    try {
      final catalog = await const CommerceCatalogService().fetchProducts();
      if (catalog.any((p) => p.id == 'instant7_1')) {
        final balance = await AuthenticatedHttpClient.get(Uri.parse('$baseUrl/api/pass/remain'));
        if (balance.statusCode == 200) {
          sevenDayAvailable = (jsonDecode(balance.body)['instant7'] as num? ?? 0) > 0;
        }
      }
    } catch (_) {}
    if (!mounted) return;

    // 무료 공고 → 즉시게시 확인 바텀시트
    final selectedPassType = await showModalBottomSheet<String>(
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
                  '선택한 이용권 또는 구독 혜택으로 12시간 기다리지 않고 이 공고를 바로 공개합니다. 7일권을 선택하면 별도 7일권 1개를 사용합니다.',
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
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          '취소',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, 'instant'),
                        child: Text(
                          v3Available || isUnlimited ? '즉시 게시' : '이용권 사용'),
                      ),
                    ),
                  ],
                ),
                if (sevenDayAvailable) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, 'instant_7d'),
                      child: const Text('보유한 7일권으로 바로 공개'),
                    ),
                  ),
                ],
              ],
            ),
          ),
    );

    if (selectedPassType == null || !mounted) return;

    try {
      await JobService.publishNow(jobId, passType: selectedPassType);
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
                      child: const Text(
                        '이용권 구매하기'),
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
  // 공고 카드 — 홈 시안 2번 모양(큰 카드·회색 숫자 칸·버튼 하나)을 모든 공고에 (대표 11-01).
  // 모집 중·마감이 같은 카드, 접지 않고 페이지로 넘긴다.
  Widget _buildJobCard(Job job) {
    // 노출 기간이 끝난 공고도 마감으로 — '모집중'으로 남아 있었다
    final isClosed = !_isLive(job);
    final reserved = isJobReserved(job);
    // 근무 마지막 날이 지나서야 공개되는 공고 — '공개 대기'로 두면 정상처럼 보인다
    final publishTooLate =
        reserved && job.publishAt != null && job.endDate != null &&
        !job.publishAt!.isBefore(job.endDate!.add(const Duration(days: 1)));
    final pinned = isJobPinned(job);
    final when = _jobWhen(job);
    final chips = <Widget>[
      if (isClosed)
        const JobSignalBadge(label: '마감')
      else if (publishTooLate)
        const JobSignalBadge(label: '공개 전에 근무가 끝나요', signal: JobSignal.time)
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

    void openApplicants() {
      FirebaseAnalytics.instance.logEvent(name: 'client_applicants_tap');
      Navigator.pushNamed(context, '/applicants', arguments: job.id);
    }

    // 상태마다 지금 할 일 하나
    final (String, VoidCallback) action =
        isClosed
            ? ('같은 조건으로 다시 올리기', () => _repost(job))
            : publishTooLate
            ? ('수정하기', () => Navigator.pushNamed(context, '/edit_job', arguments: job.id))
            : reserved && !job.isPaid
            ? ('지금 바로 공개', () => _upgradeToInstant(job))
            : job.applicantCount > 0
            ? ('지원자 보기', openApplicants)
            : job.isUrgent
            ? ('근처 알바생에게 긴급 호출', () => _openUrgentCall(job))
            : ('근처 알바생 추천받기', () => _openRecommendedWorkersByJobId(job.id.toString()));

    final status =
        isClosed
            ? (job.expiresAt != null ? '${_toLocal(job.expiresAt).month}월 ${_toLocal(job.expiresAt).day}일 마감' : '마감')
            : [_liveStatus(job), if (pinned) '상단 고정 ${pinnedRemainText(job)}'].join(' · ');

    Widget cell(String label, int n, VoidCallback? onTap, {bool accent = false}) => Expanded(
      child: Material(
        color: accent ? AppColors.primaryLight : AppColors.bgMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              children: [
                Text(label, style: AppTextStyles.body2.copyWith(fontSize: AppFontSize.meta, color: accent ? AppColors.primaryDark : null)),
                const SizedBox(height: 2),
                Text('$n', style: AppTextStyles.h3.copyWith(fontSize: AppFontSize.titleLg, color: accent ? AppColors.primaryDark : null)),
              ],
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Material(
        color: AppColors.bgCard,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.pushNamed(context, '/job-detail', arguments: job),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 4, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Wrap(spacing: 6, runSpacing: 6, children: chips)),
                    IconButton(
                      tooltip: '공고 관리',
                      onPressed: () => _openJobActions(job),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.more_horiz_rounded, color: AppColors.textTertiary),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        job.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.h3.copyWith(
                          fontSize: AppFontSize.titleLg,
                          color: isClosed ? AppColors.textSecondary : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [if (when.isNotEmpty) when, formatJobPay(job.pay, job.payType, includeType: true)].join(' · '),
                        style: AppTextStyles.body2.copyWith(fontSize: AppFontSize.button, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 6),
                      Text(status, style: AppTextStyles.body2),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          cell('지원', job.applicantCount, job.applicantCount > 0 ? openApplicants : null),
                          const SizedBox(width: 6),
                          cell('답장 대기', job.unansweredCount, job.unansweredCount > 0 ? openApplicants : null,
                              accent: job.unansweredCount > 0),
                          const SizedBox(width: 6),
                          cell('조회', job.viewCount, null),
                        ],
                      ),
                      const SizedBox(height: 14),
                      isClosed
                          // 마감 공고는 한 단 낮은 버튼 — 모집 중 공고의 버튼이 먼저 보이게
                          ? SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: FilledButton(
                                onPressed: action.$2,
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.primaryLight,
                                  foregroundColor: AppColors.primary,
                                  textStyle: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w600),
                                ),
                                child: Text(action.$1),
                              ),
                            )
                          : AppPrimaryButton(label: action.$1, height: 50, onPressed: action.$2),
                    ],
                  ),
                ),
              ],
            ),
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
    // 앞에 '지난 공고 / 새 공고' 선택 시트를 두었다가 뺐다(대표 10/29) — 지난 공고는 작성 1단계에서 바로 채운다
    Navigator.pushNamed(context, '/post_job');
  }


  // ════════════════════════════════════════════════════════
  //  홈 (2026-11) — 공고 중심. 지원자 이야기는 '지원자' 탭이 한다(대표: 둘이 겹친다).
  //  공고가 하나도 없으면 무엇을 올릴지 두 카드, 있으면 모집 중·마감 공고를 같은 카드로 펼쳐 페이지로
  // ════════════════════════════════════════════════════════
  Future<void> _loadFreeQuota() async {
    final q = await JobService.fetchFreeQuota();
    if (mounted && q != null) setState(() => freeRemaining = q.remaining);
  }

  bool _isLive(Job j) =>
      j.status != 'closed' && (j.expiresAt == null || _toUtc(j.expiresAt).isAfter(DateTime.now().toUtc()));

  void _openPromotion() =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const PromotionRequestScreen()));

  String _jobWhen(Job job) => [
    if (formatWorkDays(job.startDate, job.endDate, job.weekdays) case final d?) d,
    if (job.workingHours.replaceAll('~', '').trim().isNotEmpty) job.workingHours,
  ].join(' ');

  /// 공개 대기면 공개 시각, 아니면 남은 노출 시간
  String _liveStatus(Job job) {
    if (isJobReserved(job)) return '${publishRemainText(job)} 공개';
    if (job.expiresAt == null) return '공개 중';
    final d = _toUtc(job.expiresAt).difference(DateTime.now().toUtc());
    final left = d.inDays > 0 ? '${d.inDays}일 ${d.inHours % 24}시간' : d.inHours > 0 ? '${d.inHours}시간' : '${d.inMinutes}분';
    return '공개 중 · $left 남음';
  }

  Widget _choiceCard({required bool primary, required IconData icon, required String title, required String sub, required VoidCallback onTap}) {
    final fg = primary ? Colors.white : AppColors.textPrimary;
    return AppPressScale(
      scale: 0.98,
      child: Material(
        color: primary ? AppColors.primary : AppColors.bgCard,
        shape: RoundedRectangleBorder(
          side: primary ? BorderSide.none : const BorderSide(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: primary ? Colors.white.withValues(alpha: 0.18) : AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, size: 26, color: primary ? Colors.white : AppColors.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppTextStyles.h3.copyWith(fontSize: AppFontSize.titleLg, color: fg)),
                      const SizedBox(height: 3),
                      Text(sub, style: AppTextStyles.body2.copyWith(
                          fontSize: AppFontSize.button,
                          color: primary ? Colors.white.withValues(alpha: 0.92) : AppColors.textSecondary)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: primary ? Colors.white : AppColors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _howItWorks() {
    Widget step(int n, String text) => Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.primaryLight, shape: BoxShape.circle),
            child: Text('$n', style: AppTextStyles.body2.copyWith(color: AppColors.primaryDark, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: AppTextStyles.body1)),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('이렇게 진행돼요', style: AppTextStyles.h3),
        step(1, '공고를 올리면 근처 알바생에게 알림이 가요'),
        step(2, '지원이 오면 채팅으로 바로 이야기해요'),
        step(3, '마음에 드는 분과 출근 날짜를 정하면 끝이에요'),
      ],
    );
  }

  Widget _buildEmptyHome() => Scaffold(
    backgroundColor: AppColors.bgCard,
    appBar: const AlbailjuAppBar(title: '알바일주', brand: true),
    body: DefaultTextStyle.merge(
      style: const TextStyle(letterSpacing: -0.3),
      child: RefreshIndicator(
      onRefresh: () async {
        await _loadFreeQuota();
        await _loadMyJobs(page: 1);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Text(
            '${companyName.isEmpty ? '' : '$companyName '}사장님,\n오늘 사람이 필요하세요?',
            style: AppTextStyles.h1.copyWith(fontWeight: FontWeight.w700, height: 1.4),
          ),
          const SizedBox(height: 8),
          Text.rich(
            const TextSpan(children: [
              TextSpan(text: '올리면 근처 알바생에게 '),
              TextSpan(text: '바로 알려요', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
            ]),
            style: AppTextStyles.body1.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          _choiceCard(
            primary: true,
            icon: Icons.description_outlined,
            title: '공고 올리기',
            sub: freeRemaining == null ? '하루·단기 알바를 구해요' : '하루·단기 알바를 구해요 · 이번 달 무료 $freeRemaining회',
            onTap: _goToPostJobFlow,
          ),
          const SizedBox(height: 10),
          _choiceCard(
            primary: false,
            icon: Icons.campaign_outlined,
            title: '채용 홍보',
            sub: '내 공고를 알바생 홈에 30일 동안 크게 보여요',
            onTap: _openPromotion,
          ),
          const SizedBox(height: 16),
          const AdBannerWidget(placement: 'app_home_owner', margin: EdgeInsets.zero),
          Container(height: 8, margin: const EdgeInsets.symmetric(vertical: 24), color: AppColors.bgMuted),
          _howItWorks(),
        ],
      ),
    ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_loadedOnce && totalCount == 0) return _buildEmptyHome();
    final jobs = _filteredJobs();

    return Scaffold(
      backgroundColor: AppColors.bgCard, // 시안 2번: 흰 바탕 + 테두리 카드
      appBar: AlbailjuAppBar(
        title: '알바일주',
        brand: true,
        actions: [
          FilledButton.icon(
            // 시안 3번: 공고 올리기·채용 홍보 중 고르고 들어간다 (기본은 공고 올리기)
            onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const PostChooseScreen()))
                .then((_) => _loadMyJobs(page: currentPage)),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('올리기'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryLight,
              foregroundColor: AppColors.primary,
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              textStyle: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: DefaultTextStyle.merge(
        style: const TextStyle(letterSpacing: -0.3), // 시안 자간 — 따로 자간을 정한 제목 스타일은 그대로
        child: RefreshIndicator(
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
                child: Column(
                  children: [
                    // 원더 배너는 위 (대표 결정 10/29) — 공고 사이에 끼우면 카드 흐름이 끊긴다
                    const AdBannerWidget(
                      placement: 'app_home_owner',
                      margin: EdgeInsets.fromLTRB(20, 0, 20, 12),
                    ),
                    _buildUnansweredBanner(),
                    _buildSafeCompanyPrompt(),
                    _buildSearchBar(),
                  ],
                ),
              ),
            ),
            if (isLoading)
              const SliverFillRemaining(child: AppSkeletonList(rows: 4))
            else if (jobs.isEmpty)
              _buildEmptyJobsState(hasAnyJobs: myJobs.isNotEmpty)
            else ...[
              SliverList.builder(
                itemCount: jobs.length,
                itemBuilder:
                    (context, index) => AppFadeSlideIn(
                      key: ValueKey('cjob_${jobs[index].id}'),
                      index: index,
                      child: _buildJobCard(jobs[index]),
                    ),
              ),
              SliverToBoxAdapter(child: _buildPaginationWidget()),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
      ),
    );
  }

}

