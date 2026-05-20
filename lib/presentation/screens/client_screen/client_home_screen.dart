import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:iljujob/config/constants.dart';
import '../../../data/models/job.dart';
import '../../../data/models/banner_ad.dart';
import '../../../data/services/job_service.dart';
import '../../../data/services/ai_api.dart';
import 'package:iljujob/widget/recommended_workers_sheet.dart';
import 'package:iljujob/presentation/screens/worker_screen/labor_consult_screen.dart';
import 'package:iljujob/presentation/screens/worker_screen/job_insight_sheet.dart';
import 'package:iljujob/presentation/screens/client_screen/wage_report_screen.dart';
import 'package:iljujob/presentation/screens/post_job/SelectPreviousJobScreen.dart';
import 'package:iljujob/widget/app_ui.dart';
import 'package:firebase_analytics/firebase_analytics.dart';

const kBrandBlue = Color(0xFF3B8AFF);

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

class ClientHomeScreen extends StatefulWidget {
  final AiApi api;

  const ClientHomeScreen({super.key, required this.api});

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen>
    with SingleTickerProviderStateMixin {
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
  bool compactView = false;
  String searchQuery = '';

  // Summary
  int todayCount = 0;
  int weekCount = 0;
  int monthCount = 0;

  // Tabs
  late TabController _tabController;

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

  // ① 삭제 다이얼로그 단일 메서드로 추출 — 중복 제거
  Future<void> _showDeleteConfirm(Job job) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder:
          (dCtx) => Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
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
                      color: const Color(0xFFFFF1F1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Icon(
                      Icons.delete_rounded,
                      color: Color(0xFFE53935),
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '공고 삭제',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '해당 공고를 삭제하시겠습니까?\n삭제 후에는 복구할 수 없습니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.35,
                      color: Color(0xFF666666),
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
                              borderRadius: BorderRadius.circular(14),
                            ),
                            side: const BorderSide(color: Color(0xFFE6E6E6)),
                            foregroundColor: const Color(0xFF111111),
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
                              borderRadius: BorderRadius.circular(14),
                            ),
                            backgroundColor: const Color(0xFFE53935),
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

    _pageController = PageController(initialPage: 0);

    _requestNotificationPermission();
    _saveClientFcmToken();
    _fetchClientProfile();

    _loadBannerHidden();
    _loadBannerAds();

    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) return;
      // ⑦ 탭 인덱스 → payTypeFilter 동기화를 리스너 한 곳에서만 처리
      setState(() {
        payTypeFilter = ['전체', '일급', '주급'][_tabController.index];
      });
      _resetAndLoadJobs();
    });

    _loadMyJobs();
    _loadSummaryData();
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _tabController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  // ======= Actions =======
  void _resetAndLoadJobs() {
    setState(() {
      currentPage = 1;
      myJobs.clear();
    });
    _loadMyJobs();
  }

  void _onFilterChanged() => _resetAndLoadJobs();

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

  Future<void> _saveClientFcmToken() async {
    if (!Platform.isAndroid) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('userPhone');
      if (phone == null || phone.isEmpty) return;
      await http.post(
        Uri.parse('$baseUrl/api/user/update-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userPhone': phone,
          'userType': 'client',
          'fcmToken': token,
        }),
      );
    } catch (e) {
      debugPrint('FCM token save error: $e');
    }
  }

  // ======= Profile =======
  Future<void> _fetchClientProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');
    if (token == null || token.isEmpty) return;

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/client/profile'),
        headers: {'Authorization': 'Bearer $token'},
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
      final response = await http.get(
        Uri.parse('$baseUrl/api/client/summary?clientId=$clientId'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (!mounted) return;
        setState(() {
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

      final response = await http.get(
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

    // ② (j as dynamic) 제거 — Job 모델의 타입 안전 필드 사용
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

  Future<void> _loadBannerAds() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/banners'));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        if (!mounted) return;
        final loaded = data.map((json) => BannerAd.fromJson(json)).toList();
        setState(() {
          bannerAds = loaded;
          if (_currentBannerIndex >= bannerAds.length) _currentBannerIndex = 0;
        });
        // ④ _logImageRatio 제거 — 개발용 디버그 코드
        if (!_isBannerHidden && bannerAds.length > 1) _startBannerAutoSlide();
      }
    } catch (e) {
      debugPrint('banner load error: $e');
    }
  }

  // ⑧ 배너 복원 버튼 — AppBar 내 compact 버튼으로 이동했으므로 별도 섹션 제거
  // (build의 AppBar actions에서 처리)

  Widget _buildBannerSlider() {
    if (_isBannerHidden || bannerAds.isEmpty) return const SizedBox.shrink();
    final canNav = bannerAds.length > 1;

    Widget circleBtn(IconData icon, VoidCallback onTap) => ClipOval(
      child: Material(
        color: Colors.black.withOpacity(0.20),
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
              borderRadius: BorderRadius.circular(14),
              child: PageView.builder(
                controller: _pageController,
                itemCount: bannerAds.length,
                onPageChanged:
                    (index) => setState(() => _currentBannerIndex = index),
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
                      decoration: BoxDecoration(color: Colors.grey.shade200),
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
                                color: Colors.black38,
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
                  color: Colors.black.withOpacity(0.18),
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
                      borderRadius: BorderRadius.circular(999),
                      color:
                          _currentBannerIndex == i
                              ? Colors.white
                              : Colors.white.withOpacity(0.45),
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

  // ======= AI Recommended Workers + Paywall =======
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
                  top: Radius.circular(16),
                ),
                child: Material(
                  color: Colors.white,
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final mq = MediaQuery.of(ctx);
        final bottomInset = mq.viewInsets.bottom;
        final bottomPad = mq.padding.bottom;

        return FractionallySizedBox(
          heightFactor: 0.62,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Material(
              color: Colors.white,
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
                          color: const Color(0xFF4F46E5).withOpacity(0.10),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.auto_awesome,
                          color: Color(0xFF4F46E5),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '맞춤 인재 기능은 구독 전용입니다',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'AI가 공고와 잘 맞는 인재를 추천해 드립니다.\n구독 후 이용해 주세요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54, height: 1.4),
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
                            backgroundColor: const Color(0xFF4F46E5),
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

  // ======= UI Parts =======
  Widget _buildKpiRow() {
    Widget kpi(String title, int value, IconData icon) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            // ⑥ border만 사용 — boxShadow 제거
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: kBrandBlue.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: kBrandBlue, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      NumberFormat.decimalPattern().format(value),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(
        children: [
          kpi('오늘 지원', todayCount, Icons.today_outlined),
          const SizedBox(width: 10),
          kpi('이번 주', weekCount, Icons.date_range_outlined),
          const SizedBox(width: 10),
          kpi('이번 달', monthCount, Icons.calendar_month_outlined),
        ],
      ),
    );
  }

  Widget _buildSafeCompanyPrompt() {
    if (isSafeCompany) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.amber.shade200),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.verified_user_outlined,
                color: Colors.orange,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '안심기업 인증',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
                  ),
                  SizedBox(height: 2),
                  Text(
                    '인증을 완료하시면 지원 전환율이 올라갈 수 있습니다.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              onPressed: () => Navigator.pushNamed(context, '/edit_profile'),
              child: const Text(
                '인증하기',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: TextField(
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search, size: 20),
            hintText: '공고 제목 또는 지역을 검색해 주세요',
            hintStyle: const TextStyle(fontSize: 14, color: Colors.black38),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
          onChanged: (val) {
            setState(() => searchQuery = val);
            _onFilterChanged();
          },
        ),
      ),
    );
  }

  Widget _buildStatusSegment() {
    Widget seg(String label) {
      final selected = filterStatus == label;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() => filterStatus = label);
            _onFilterChanged();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color:
                  selected ? kBrandBlue.withOpacity(0.12) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color:
                    selected
                        ? kBrandBlue.withOpacity(0.35)
                        : Colors.transparent,
              ),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: selected ? kBrandBlue : Colors.black54,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            seg('전체'),
            const SizedBox(width: 6),
            seg('공고중'),
            const SizedBox(width: 6),
            seg('마감'),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Row(
        children: [
          PopupMenuButton<String>(
            tooltip: '정렬',
            onSelected: (v) {
              setState(() => sortType = v);
              _onFilterChanged();
            },
            itemBuilder:
                (ctx) => const [
                  PopupMenuItem(value: '최신순', child: Text('최신순')),
                  PopupMenuItem(value: '오래된 순', child: Text('오래된 순')),
                  PopupMenuItem(value: '급여 높은 순', child: Text('급여 높은 순')),
                ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.sort, size: 18, color: Colors.black54),
                  const SizedBox(width: 8),
                  Text(
                    sortType,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.expand_more,
                    size: 18,
                    color: Colors.black45,
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: IconButton(
              tooltip: compactView ? '상세 보기' : '목록 보기',
              icon: Icon(
                compactView
                    ? Icons.view_agenda_outlined
                    : Icons.view_list_outlined,
              ),
              onPressed: () => setState(() => compactView = !compactView),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyJobsState({required bool hasAnyJobs}) {
    if (hasAnyJobs) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: Text('조건에 맞는 공고가 없습니다.')),
      );
    }

    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 28, 18, 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: kBrandBlue.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.post_add_rounded,
                color: kBrandBlue,
                size: 32,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              '첫 공고를 올리고 지원자를 받아보세요',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Color(0xFF111111),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'AI가 공고 작성을 도와드리고, 무료 등록과 이용권 보호 혜택으로 첫 채용을 가볍게 시작할 수 있어요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: Color(0xFF666666),
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: const [
                _EmptyBenefitChip(
                  icon: Icons.auto_awesome_rounded,
                  label: 'AI 1분 작성',
                ),
                _EmptyBenefitChip(
                  icon: Icons.card_giftcard_rounded,
                  label: '월 2건 무료',
                ),
                _EmptyBenefitChip(
                  icon: Icons.card_giftcard_rounded,
                  label: '지원자 없으면 환급',
                ),
              ],
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _goToPostJobFlow,
                icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                label: const Text('첫 공고 무료로 등록하기'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kBrandBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
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
            '총 ${totalCount}개 공고 · ${currentPage}/${totalPages}페이지',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black54,
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
      if (startPage > 2)
        pageButtons.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text('...', style: TextStyle(color: Colors.black38)),
          ),
        );
    }
    for (int i = startPage; i <= endPage; i++) pageButtons.add(_pageNumBtn(i));
    if (endPage < totalPages) {
      if (endPage < totalPages - 1)
        pageButtons.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text('...', style: TextStyle(color: Colors.black38)),
          ),
        );
      pageButtons.add(_pageNumBtn(totalPages));
    }
    return pageButtons;
  }

  Widget _pageNumBtn(int page) {
    final isCurrent = page == currentPage;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: isCurrent ? null : () => _goToPage(page),
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isCurrent ? kBrandBlue : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isCurrent ? kBrandBlue : Colors.grey.shade200,
            ),
          ),
          child: Text(
            '$page',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: isCurrent ? Colors.white : Colors.black54,
            ),
          ),
        ),
      ),
    );
  }

  // ======= Job Cards =======
  Widget _badge(String text, {required Color color, IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: color,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaLine(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.black45),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openJobActions(Job job) async {
    final isClosed = job.status == 'closed';
    final reserved = isJobReserved(job);

    final v = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (_) => SafeArea(
            top: false,
            child: FractionallySizedBox(
              heightFactor: 0.72,
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    ListTile(
                      leading: const Icon(Icons.people_outline),
                      title: const Text(
                        '지원자 보기',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      onTap: () => Navigator.pop(context, 'applicants'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text(
                        '상세 보기',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      onTap: () => Navigator.pop(context, 'detail'),
                    ),
                    if (!isClosed)
                      ListTile(
                        leading: const Icon(Icons.edit_outlined),
                        title: const Text(
                          '수정',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        onTap: () => Navigator.pop(context, 'edit'),
                      ),
                    if (!isClosed)
                      ListTile(
                        leading: const Icon(
                          Icons.auto_awesome,
                          color: Color(0xFF4F46E5),
                        ),
                        title: const Text(
                          '맞춤 인재',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        onTap: () => Navigator.pop(context, 'recommend'),
                      ),
                    ListTile(
                      leading: const Icon(Icons.insights, color: kBrandBlue),
                      title: const Text(
                        '인사이트',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      onTap: () => Navigator.pop(context, 'insight'),
                    ),
                    if (reserved)
                      ListTile(
                        leading: Icon(
                          Icons.flash_on,
                          color: Colors.orange.shade700,
                        ),
                        title: const Text(
                          '즉시 게시',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        onTap: () => Navigator.pop(context, 'publish-now'),
                      ),
                    if (isClosed)
                      ListTile(
                        leading: const Icon(Icons.replay_circle_filled),
                        title: const Text(
                          '재공고',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        onTap: () => Navigator.pop(context, 'repost'),
                      ),
                    const Divider(height: 18),
                    ListTile(
                      leading: const Icon(
                        Icons.delete_outline,
                        color: Colors.red,
                      ),
                      title: const Text(
                        '삭제',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Colors.red,
                        ),
                      ),
                      onTap: () => Navigator.pop(context, 'delete'),
                    ),
                  ],
                ),
              ),
            ),
          ),
    );

    if (v == null) return;

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
      case 'recommend':
        _openRecommendedWorkersByJobId(job.id.toString());
        break;
      case 'insight':
        final jobId = int.tryParse(job.id.toString());
        if (jobId != null) {
          JobInsightSheet.show(context, jobId: jobId, jobTitle: job.title);
        }
        break;
      case 'publish-now':
        try {
          await JobService.publishNow(int.parse(job.id.toString()));
          _toast('공고가 즉시 게시되었습니다.');
          _loadMyJobs();
        } catch (_) {
          _toast('즉시 게시에 실패했습니다.');
        }
        break;
      case 'repost':
        FirebaseAnalytics.instance.logEvent(name: 'client_repost_tap');
        Navigator.pushNamed(
          context,
          '/post_job',
          arguments: {'isRepost': true, 'existingJob': job},
        );
        break;
      case 'delete':
        FirebaseAnalytics.instance.logEvent(name: 'client_delete_tap');
        await _showDeleteConfirm(job);
        break;
    }
  }

  Widget _buildCompactJobCard(Job job) {
    final isClosed = job.status == 'closed';
    final reserved = isJobReserved(job);
    final pinned = isJobPinned(job);
    final formattedPay = NumberFormat('#,###').format(_payToInt(job.pay));
    final payTypeColor =
        job.payType == '주급'
            ? Colors.green.shade700
            : Colors.deepOrange.shade700;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap:
            () =>
                Navigator.pushNamed(context, '/applicants', arguments: job.id),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      job.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: isClosed ? Colors.black38 : Colors.black,
                        decoration:
                            isClosed ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: payTypeColor.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: payTypeColor.withOpacity(0.30)),
                    ),
                    child: Text(
                      job.payType,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: payTypeColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: '관리',
                    onPressed: () => _openJobActions(job),
                    icon: const Icon(Icons.more_horiz, color: Colors.black54),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (reserved)
                    _badge(
                      '예약 게시',
                      color: Colors.orange.shade700,
                      icon: Icons.schedule_outlined,
                    ),
                  if (pinned)
                    _badge(
                      '상단 고정',
                      color: Colors.deepOrange.shade700,
                      icon: Icons.push_pin_outlined,
                    ),
                  if (pinned)
                    _badge(
                      pinnedRemainText(job),
                      color: Colors.deepOrange.shade700,
                    ),
                  if (isClosed)
                    _badge(
                      '마감',
                      color: Colors.grey.shade700,
                      icon: Icons.stop_circle_outlined,
                    ),
                  if (job.expiresAt != null && !isClosed)
                    _badge(
                      getExpiryText(job),
                      color: Colors.red.shade700,
                      icon: Icons.access_time,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              _metaLine(Icons.place_outlined, job.location),
              const SizedBox(height: 6),
              _metaLine(Icons.payments_outlined, '${formattedPay}원'),
              const SizedBox(height: 6),
              _metaLine(Icons.schedule_outlined, job.workingHours),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildJobCard(Job job) {
    final isClosed = job.status == 'closed';
    final reserved = isJobReserved(job);
    final pinned = isJobPinned(job);
    final formattedPay = NumberFormat('#,###').format(_payToInt(job.pay));
    final payTypeColor =
        job.payType == '주급'
            ? Colors.green.shade700
            : Colors.deepOrange.shade700;

    final titleStyle = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w900,
      color: isClosed ? Colors.black38 : Colors.black,
      decoration: isClosed ? TextDecoration.lineThrough : null,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap:
              () => Navigator.pushNamed(context, '/job-detail', arguments: job),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        job.title,
                        style: titleStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: payTypeColor.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: payTypeColor.withOpacity(0.30),
                        ),
                      ),
                      child: Text(
                        job.payType,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: payTypeColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // ③ 더보기(···) 버튼 하나로 모든 액션 통합
                    IconButton(
                      tooltip: '관리',
                      onPressed: () => _openJobActions(job),
                      icon: const Icon(Icons.more_horiz, color: Colors.black54),
                    ),
                  ],
                ),
                if (reserved ||
                    pinned ||
                    isClosed ||
                    job.zeroApplicantRefunded ||
                    (job.expiresAt != null && !isClosed)) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (reserved)
                        _badge(
                          '예약 게시',
                          color: Colors.orange.shade700,
                          icon: Icons.schedule_outlined,
                        ),
                      if (pinned)
                        _badge(
                          '상단 고정',
                          color: Colors.deepOrange.shade700,
                          icon: Icons.push_pin_outlined,
                        ),
                      if (pinned)
                        _badge(
                          pinnedRemainText(job),
                          color: Colors.deepOrange.shade700,
                        ),
                      if (isClosed)
                        _badge(
                          '마감',
                          color: Colors.grey.shade700,
                          icon: Icons.stop_circle_outlined,
                        ),
                      if (isClosed && job.zeroApplicantRefunded)
                        _badge(
                          '이용권 환급',
                          color: Colors.green.shade700,
                          icon: Icons.card_giftcard_rounded,
                        ),
                      if (job.expiresAt != null && !isClosed)
                        _badge(
                          getExpiryText(job),
                          color: Colors.red.shade700,
                          icon: Icons.access_time,
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                _metaLine(
                  Icons.place_outlined,
                  '${job.location}  ·  ${job.category}',
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _metaLine(
                        Icons.payments_outlined,
                        '${formattedPay}원',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _metaLine(
                        Icons.schedule_outlined,
                        job.workingHours,
                      ),
                    ),
                  ],
                ),
                if (job.description?.isNotEmpty == true) ...[
                  const SizedBox(height: 10),
                  Text(
                    job.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                // 카드 하단 버튼: 지원자 / 인사이트 / 재공고(마감시만) / 더보기
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _actionBtn(
                      icon: Icons.people_outline,
                      label: '지원자',
                      onTap:
                          () => Navigator.pushNamed(
                            context,
                            '/applicants',
                            arguments: job.id,
                          ),
                    ),
                    _actionBtn(
                      icon: Icons.insights,
                      label: '인사이트',
                      color: kBrandBlue,
                      onTap: () {
                        final jobId = int.tryParse(job.id.toString());
                        if (jobId != null)
                          JobInsightSheet.show(
                            context,
                            jobId: jobId,
                            jobTitle: job.title,
                          );
                      },
                    ),
                    if (isClosed)
                      _actionBtn(
                        icon: Icons.replay_circle_filled,
                        label: '재공고',
                        color: kBrandBlue,
                        onTap:
                            () => Navigator.pushNamed(
                              context,
                              '/post_job',
                              arguments: {'isRepost': true, 'existingJob': job},
                            ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final c = color ?? Colors.black87;
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: c,
        side: BorderSide(color: Colors.grey.shade200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: c),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
      ),
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

    // 사업자 인증 체크 제거 — 바로 공고 등록으로
    Navigator.pushNamed(context, '/post_job');
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
      backgroundColor: const Color(0xFFF4F6FA),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 임금 AI 리포트 FAB
          FloatingActionButton.small(
            heroTag: 'wage_report_fab',
            onPressed: () {
              // 첫 번째 공고의 category/location으로 바로 진입
              final job = myJobs.isNotEmpty ? myJobs.first : null;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (_) => WageReportScreen(
                        category: job?.category ?? '기타',
                        locationCity: job?.locationCity,
                        payType: job?.payType ?? '시급',
                        currentPay:
                            job?.pay != null
                                ? int.tryParse(
                                  job!.pay.replaceAll(RegExp(r'[^0-9]'), ''),
                                )
                                : null,
                      ),
                ),
              );
            },
            backgroundColor: const Color(0xFF7C3AED),
            shape: const CircleBorder(),
            tooltip: '임금 AI 리포트',
            child: const Icon(
              Icons.analytics_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(height: 10),
          // 노무 상담 FAB
          FloatingActionButton(
            heroTag: 'labor_consult_fab',
            onPressed:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LaborConsultScreen()),
                ),
            backgroundColor: const Color(0xFF3B82F6),
            shape: const CircleBorder(),
            tooltip: 'AI 노무 상담',
            child: const Icon(
              Icons.balance_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text(
          '사장님 공고 관리',
          style: TextStyle(
            fontFamily: 'Jalnan2TTF',
            color: kBrandBlue,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.black38,
          indicatorColor: Colors.black,
          tabs: const [Tab(text: '전체'), Tab(text: '일급'), Tab(text: '주급')],
        ),
        actions: [
          // ⑧ 배너 숨김 상태일 때 AppBar에 복원 버튼 노출 — 눈에 잘 띄는 위치
          if (_isBannerHidden && bannerAds.isNotEmpty)
            IconButton(
              tooltip: '배너 다시 보기',
              icon: const Icon(Icons.campaign_outlined, color: kBrandBlue),
              onPressed: () => _setBannerHidden(false),
            ),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _PostJobCtaButton(onPressed: _goToPostJobFlow),
            ),
          ),
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
            SliverToBoxAdapter(child: _buildKpiRow()),
            SliverToBoxAdapter(child: _buildBannerSlider()),
            SliverToBoxAdapter(child: _buildSafeCompanyPrompt()),
            SliverToBoxAdapter(child: _buildSearchBar()),
            SliverToBoxAdapter(child: _buildStatusSegment()),
            SliverToBoxAdapter(child: _buildToolbar()),
            if (!isLoading && myJobs.isNotEmpty)
              SliverToBoxAdapter(
                child: _QuickPostEntryBand(onTap: _goToQuickPostFlow),
              ),
            if (isLoading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (jobs.isEmpty)
              _buildEmptyJobsState(hasAnyJobs: myJobs.isNotEmpty)
            else ...[
              SliverList.builder(
                itemCount: jobs.length,
                itemBuilder:
                    (context, index) =>
                        compactView
                            ? _buildCompactJobCard(jobs[index])
                            : _buildJobCard(jobs[index]),
              ),
              SliverToBoxAdapter(child: _buildPaginationWidget()),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 18)),
          ],
        ),
      ),
    );
  }
}

// ⑤ _SearchHeaderDelegate dead code 제거

class _PostJobCtaButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _PostJobCtaButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onPressed,
          child: Ink(
            padding: const EdgeInsets.fromLTRB(10, 0, 12, 0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: kBrandBlue.withValues(alpha: 0.10),
              border: Border.all(color: kBrandBlue.withValues(alpha: 0.26)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: kBrandBlue,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 7),
                const Text(
                  '공고 올리기',
                  style: TextStyle(
                    color: kBrandBlue,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
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

class _QuickPostEntryBand extends StatelessWidget {
  final VoidCallback onTap;
  const _QuickPostEntryBand({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: AppActionBand(
        icon: Icons.bolt_rounded,
        title: '이전 공고로 빠른 등록',
        subtitle: '날짜와 급여만 바꿔 바로 올릴 수 있어요',
        actionLabel: '빠른 등록',
        onTap: onTap,
      ),
    );
  }
}

class _EmptyBenefitChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _EmptyBenefitChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: kBrandBlue.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: kBrandBlue),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2D3A4A),
            ),
          ),
        ],
      ),
    );
  }
}
