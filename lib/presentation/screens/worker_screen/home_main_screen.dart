// =====================================================================
// A안 적용: 카드에서 자세히 + 지원하기 버튼 분리
// 변경 포인트:
//   1. _buildJobCard → job_actions row: 북마크 | 자세히 | 지원하기
//   2. _showQuickApplySheet → 바텀시트 없이 바로 지원 API 호출 + 확인 다이얼로그
//   3. 자세히 버튼 → _openJobDetail 직접 호출
//   4. 카드 하단 액션 레이아웃 정리
// =====================================================================

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/models/job.dart';
import '../../../data/services/job_service.dart';
import 'dart:math';
import 'package:intl/intl.dart';
import 'job_detail_screen.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:io';
import 'package:iljujob/config/constants.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async' show TimeoutException;
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../data/models/banner_ad.dart';
import 'package:url_launcher/url_launcher.dart';
import 'job_meta_section.dart';
import '../../../data/models/job.dart';
import 'package:iljujob/data/services/log_service.dart';
import 'package:iljujob/data/services/chat_service.dart';
import 'package:iljujob/presentation/chat/chat_room_screen.dart';

class HomeMainScreen extends StatefulWidget {
  final VoidCallback? onAiRecommend;

  const HomeMainScreen({super.key, this.onAiRecommend});

  @override
  State<HomeMainScreen> createState() => _HomeMainScreenState();
}

final _reNonDigit = RegExp(r'[^0-9]');
final _reWhitespace = RegExp(r'\s+');

class _HomeMainScreenState extends State<HomeMainScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);
  String? _workerGender;

  List<Job> allJobs = [];
  List<Job> filteredJobs = [];
  List<String> bookmarkedJobIds = [];
  List<int> appliedJobIds = [];
  int? _quickApplyingJobId;
  String searchQuery = '';
  String selectedCategory = '전체';
  String sortType = '최신순';
  double currentLatitude = 0.0;
  double currentLongitude = 0.0;
  double selectedDistance = 30;
  int _itemsToShow = 10;
  bool isLoading = true;
  bool compactView = false;
  final ScrollController _scrollController = ScrollController();
  bool isAvailableToday = false;
  String selectedPayType = 'all';
  int _jobsReqSeq = 0;
  bool _isLoadingJobs = false;
  List<BannerAd> bannerAds = [];
  int _currentBannerIndex = 0;
  Timer? _bannerTimer;
  PageController? _pageController;
  bool _isBannerHidden = false;

  bool _genderHintDismissed = false;
  static const _kGenderHintKey = 'gender_hint_dismissed';

  double? _distanceKmFromUser(Job job) {
    if (currentLatitude == 0.0 ||
        currentLongitude == 0.0 ||
        job.lat == 0.0 ||
        job.lng == 0.0) {
      return null;
    }
    return calculateDistance(
        currentLatitude, currentLongitude, job.lat, job.lng);
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _loadBannerAds();
    _startBannerAutoSlide();
    _requestNotificationPermission();
    _loadGenderHintDismissed();
    _loadAvailableTodayStatus();
    _loadWorkerProfileBrief();
    _loadBookmarks().then((_) async {
      await _init();
      await _loadJobsWithAppliedStatus();
      if (mounted) setState(() => isLoading = false);
    }).catchError((e) async {
      await _init();
      await _loadJobsWithAppliedStatus();
      if (mounted) setState(() => isLoading = false);
    });

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        _loadMoreItems();
      }
    });
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    _debounce?.cancel();
    _bannerTimer?.cancel();
    _pageController?.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadGenderHintDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _genderHintDismissed = prefs.getBool(_kGenderHintKey) ?? false;
    });
  }

  Future<void> _dismissGenderHint() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kGenderHintKey, true);
    if (!mounted) return;
    setState(() => _genderHintDismissed = true);
  }

  Timer? _debounce;
  bool _isApplying = false;

  void _runDebounced(void Function() action,
      [Duration delay = const Duration(milliseconds: 180)]) {
    _debounce?.cancel();
    _debounce = Timer(delay, action);
  }

  void _applyFiltersThrottled() {
    if (_isApplying) return;
    _isApplying = true;
    try {
      _applyFilters();
    } finally {
      _isApplying = false;
    }
  }

  Future<void> _recordBannerClick(int bannerId) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/api/banners/click'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"bannerId": bannerId}),
      );
    } catch (e) {
      debugPrint('❌ 배너 클릭 기록 실패: $e');
    }
  }

  Future<void> _loadBannerAds() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/banners'));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        if (!mounted) return;
        setState(() {
          bannerAds = data.map((json) => BannerAd.fromJson(json)).toList();
        });
        if (bannerAds.length > 1) _startBannerAutoSlide();
      }
    } catch (e) {
      debugPrint('❌ 배너 로드 예외: $e');
    }
  }

  void _startBannerAutoSlide() {
    if (bannerAds.length <= 1) return;
    if (_bannerTimer != null && _bannerTimer!.isActive) return;

    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (!mounted || bannerAds.isEmpty || _pageController == null) return;
      if (!_pageController!.hasClients) return;
      final nextPage = (_currentBannerIndex + 1) % bannerAds.length;
      _pageController!.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  Future<void> _loadWorkerProfileBrief() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final workerId = prefs.getInt('userId');
      if (workerId == null) return;
      final res = await http
          .get(Uri.parse('$baseUrl/api/worker/profile?id=$workerId'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final gender = data['gender'];
        if (!mounted) return;
        setState(() {
          _workerGender =
              (gender is String && gender.trim().isNotEmpty) ? gender : null;
        });
      }
    } catch (e) {
      debugPrint('❌ _loadWorkerProfileBrief 오류: $e');
    }
  }

  Future<void> _loadJobsWithAppliedStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId');
    if (userId == null) return;
    await fetchAppliedJobs(userId);
    await _loadJobs();
  }

  void _requestNotificationPermission() async {
    if (!Platform.isAndroid) return;
    final settings = await FirebaseMessaging.instance.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('❌ 알림 권한 거부됨');
    }
  }

  Future<void> retryFcmTokenSend() async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final userPhone = prefs.getString('userPhone');
      final userType = prefs.getString('userType');
      await http.post(
        Uri.parse('$baseUrl/api/user/update-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(
            {'userPhone': userPhone, 'userType': userType, 'fcmToken': token}),
      );
    } catch (e) {
      debugPrint('❌ 토큰 전송 실패: $e');
    }
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    double lat = prefs.getDouble('currentLatitude') ?? 0.0;
    double lng = prefs.getDouble('currentLongitude') ?? 0.0;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted)
          setState(() {
            currentLatitude = 0.0;
            currentLongitude = 0.0;
          });
        return;
      }

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied)
        perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted)
          setState(() {
            currentLatitude = 0.0;
            currentLongitude = 0.0;
          });
        return;
      }

      final last = await Geolocator.getLastKnownPosition();
      if ((lat == 0.0 && lng == 0.0) && last != null) {
        lat = last.latitude;
        lng = last.longitude;
      }

      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
                desiredAccuracy: LocationAccuracy.high)
            .timeout(const Duration(seconds: 5));
      } on TimeoutException {}

      final finalLat = pos?.latitude ?? lat;
      final finalLng = pos?.longitude ?? lng;

      if (mounted)
        setState(() {
          currentLatitude = finalLat;
          currentLongitude = finalLng;
        });

      if (finalLat != 0.0 && finalLng != 0.0) {
        sendLocationToServer(finalLat, finalLng);
        await prefs.setDouble('currentLatitude', finalLat);
        await prefs.setDouble('currentLongitude', finalLng);
      }
    } catch (e) {
      debugPrint('❌ 위치 오류: $e');
      if (mounted)
        setState(() {
          currentLatitude = 0.0;
          currentLongitude = 0.0;
        });
    }
  }

  List<String> _parseBookmarksResponse(String body) {
    final ids = <String>[];
    dynamic json;
    try {
      json = jsonDecode(body);
    } catch (e) {
      return ids;
    }

    void pickFromList(List list) {
      for (final e in list) {
        if (e is Map) {
          final jobId =
              (e['job_id'] ?? e['jobId'] ?? e['job'] ?? e['id'])?.toString();
          if (jobId != null && jobId.isNotEmpty) ids.add(jobId);
        }
      }
    }

    if (json is List) {
      pickFromList(json);
    } else if (json is Map) {
      final list =
          (json['data'] ?? json['bookmarks'] ?? json['items'] ?? json['results']);
      if (list is List) pickFromList(list);
    }
    return ids;
  }

  Future<void> _loadBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId');
    if (userId == null) return;

    final url1 = Uri.parse('$baseUrl/api/bookmark/list?userId=$userId');
    try {
      var resp = await http.get(url1);
      if (resp.statusCode == 200) {
        final ids = _parseBookmarksResponse(resp.body);
        if (!mounted) return;
        setState(() => bookmarkedJobIds = ids.toSet().toList());
        return;
      }
      final url2 = Uri.parse('$baseUrl/api/bookmark/list?workerId=$userId');
      final resp2 = await http.get(url2);
      if (resp2.statusCode == 200) {
        final ids = _parseBookmarksResponse(resp2.body);
        if (!mounted) return;
        setState(() => bookmarkedJobIds = ids.toSet().toList());
      }
    } catch (e, st) {
      debugPrint('❌ loadBookmarks exception: $e\n$st');
    }
  }

  Future<void> _openJobDetail(Job job) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => JobDetailScreen(job: job)),
    );
    if (result == true) {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('userId');
      if (userId != null) {
        await fetchAppliedJobs(userId);
        setState(() {});
      }
    }
  }

  Future<void> setAvailableToday(bool available) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId');
    if (userId == null) return;
    await http.patch(
      Uri.parse('$baseUrl/api/worker/available-today'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': userId, 'availableToday': available}),
    );
  }

  Future<void> _loadAvailableTodayStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId');
    if (userId == null) return;
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/worker/available-status?userId=$userId'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (!mounted) return;
        setState(() {
          isAvailableToday = data['availableToday'] ?? false;
        });
      }
    } catch (e) {
      debugPrint('❌ 네트워크 오류: $e');
    }
  }

  Future<void> sendLocationToServer(double lat, double lng) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId');
    if (userId == null) return;
    try {
      await http.patch(
        Uri.parse('$baseUrl/api/worker/update-location'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': userId, 'lat': lat, 'lng': lng}),
      );
    } catch (e) {
      debugPrint('❌ 위치 저장 예외: $e');
    }
  }

  Future<void> _toggleBookmark(String jobId) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId');
    if (userId == null) return;

    final wasBookmarked = bookmarkedJobIds.contains(jobId);
    final endpoint = wasBookmarked ? 'remove' : 'add';
    final url = Uri.parse('$baseUrl/api/bookmark/$endpoint');

    try {
      final resp = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'worker_id': userId, 'job_id': jobId}),
      );

      if (resp.statusCode == 200) {
        if (!mounted) return;
        setState(() {
          if (wasBookmarked)
            bookmarkedJobIds.remove(jobId);
          else
            bookmarkedJobIds.add(jobId);
        });
        if (!wasBookmarked) {
          final jobIdInt = int.tryParse(jobId);
          if (jobIdInt != null) {
            LogService.instance.logEvent(
                eventType: LogService.bookmark, jobId: jobIdInt);
          }
        }
        return;
      }

      if (resp.body.contains('이미 북마크됨')) {
        if (!mounted) return;
        setState(() {
          if (!bookmarkedJobIds.contains(jobId)) bookmarkedJobIds.add(jobId);
        });
        await _loadBookmarks();
        return;
      }

      if (resp.body.contains('북마크 내역 없음') ||
          resp.body.contains('존재하지')) {
        if (!mounted) return;
        setState(() {
          bookmarkedJobIds.remove(jobId);
        });
        await _loadBookmarks();
        return;
      }

      await _loadBookmarks();
    } catch (e, st) {
      debugPrint('❌ toggle exception: $e\n$st');
      await _loadBookmarks();
    }
  }

  Future<void> fetchAppliedJobs(int userId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/apply/my-jobs?workerId=$userId'));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final List<int> ids = [];
        for (final item in data) {
          final isCanceled = (item['is_canceled_by_worker'] ?? 0) == 1;
          if (isCanceled) continue;
          final dynamic rawJobId = item['job_id'] ?? item['id'];
          if (rawJobId == null) continue;
          final int? parsed = int.tryParse(rawJobId.toString());
          if (parsed != null) ids.add(parsed);
        }
        if (!mounted) return;
        setState(() {
          appliedJobIds = ids;
        });
      }
    } catch (e) {
      debugPrint('❌ 네트워크 오류: $e');
    }
  }

  Future<void> _loadJobs() async {
    if (_isLoadingJobs) return;
    _isLoadingJobs = true;
    final req = ++_jobsReqSeq;

    try {
      final jobs = await JobService.fetchJobs(clientId: null);
      if (req != _jobsReqSeq || !mounted) return;

      final prefs = await SharedPreferences.getInstance();
      final workerId = prefs.getInt('userId');
      final userType = prefs.getString('userType');

      Map<String, Map<String, dynamic>> scoreMap = {};

      if (workerId != null && userType == 'worker') {
        try {
          final aiRes = await http.get(
            Uri.parse(
                '$baseUrl/api/rank/jobs?workerId=$workerId&lat=$currentLatitude&lng=$currentLongitude&limit=100'),
          ).timeout(const Duration(seconds: 6));

          if (aiRes.statusCode == 200) {
            final data = jsonDecode(aiRes.body);
            final items = (data['items'] ?? data) as List? ?? [];
            for (final item in items) {
              final jobId = (item['jobId'] ?? item['job_id'])?.toString();
              if (jobId == null) continue;
              scoreMap[jobId] = {
                'score': (item['score'] as num?)?.toDouble(),
                'reasons': (item['reasons'] as List?)
                        ?.map((e) => e.toString())
                        .toList() ??
                    <String>[],
              };
            }
          }
        } catch (e) {
          debugPrint('⚠️ AI 매칭 로드 실패 (무시): $e');
        }
      }

      final enrichedJobs = jobs.map((j) {
        final ai = scoreMap[j.id];
        if (ai == null) return j;
        return j.copyWith(
            matchScore: ai['score'] as double?,
            matchReasons: ai['reasons'] as List<String>);
      }).toList();

      if (req != _jobsReqSeq || !mounted) return;

      final nowUtc = DateTime.now().toUtc();

      bool isPinnedActive(Job j) =>
          j.pinnedUntil != null && j.pinnedUntil!.isAfter(nowUtc);
      bool isFutureScheduled(Job j) =>
          j.publishAt != null && j.publishAt!.isAfter(nowUtc);
      bool isExpired(Job j) =>
          j.expiresAt != null && !j.expiresAt!.isAfter(nowUtc);

      final validJobs = <Job>[];
      for (final j in enrichedJobs) {
        if (j.status == 'closed' || j.status == 'deleted') continue;
        if (isExpired(j)) continue;
        if (!isPinnedActive(j) && isFutureScheduled(j)) continue;
        validJobs.add(j);
      }

      List<Job> filtered = validJobs;
      if (currentLatitude != 0.0 && currentLongitude != 0.0) {
        final tmp = <Job>[];
        for (final j in validJobs) {
          final hasGeo = j.lat != 0.0 && j.lng != 0.0;
          if (!hasGeo) {
            tmp.add(j);
            continue;
          }
          final d = calculateDistance(
              currentLatitude, currentLongitude, j.lat, j.lng);
          if (d <= selectedDistance) tmp.add(j);
        }
        filtered = tmp;
      }

      int idAsInt(String s) => int.tryParse(s) ?? 0;
      filtered.sort((a, b) {
        final apin = isPinnedActive(a), bpin = isPinnedActive(b);
        if (apin != bpin) return bpin ? 1 : -1;
        if (apin && bpin) {
          final cp = b.pinnedUntil!.compareTo(a.pinnedUntil!);
          if (cp != 0) return cp;
        }
        final ap = a.publishAt ??
            a.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        final bp = b.publishAt ??
            b.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        final cd = bp.compareTo(ap);
        if (cd != 0) return cd;
        return idAsInt(b.id).compareTo(idAsInt(a.id));
      });

      if (req != _jobsReqSeq || !mounted) return;
      setState(() {
        allJobs = validJobs;
        filteredJobs = filtered;
        _itemsToShow = 10;
      });
    } catch (e) {
      debugPrint('❌ _loadJobs 오류: $e');
    } finally {
      if (req == _jobsReqSeq) _isLoadingJobs = false;
    }
  }

  void _loadMoreItems() {
    if (_itemsToShow < filteredJobs.length) {
      setState(() {
        _itemsToShow += 10;
      });
    }
  }

  void _applyFilters() {
    List<Job> tempJobs = List.from(allJobs);

    final nowUtc = DateTime.now().toUtc();

    bool isPinned(Job j) =>
        j.pinnedUntil != null && j.pinnedUntil!.isAfter(nowUtc);

    int payValue(Job j) {
      final onlyNum = j.pay.replaceAll(_reNonDigit, '');
      return int.tryParse(onlyNum) ?? 0;
    }

    tempJobs = tempJobs.where((job) {
      final publishAt = job.publishAt ?? job.createdAt ?? nowUtc;
      final isFuture = publishAt.isAfter(nowUtc);
      final notExpired =
          (job.expiresAt == null) || job.expiresAt!.isAfter(nowUtc);
      if (isPinned(job)) return notExpired;
      return !isFuture && notExpired;
    }).toList();

    if (currentLatitude != 0.0 && currentLongitude != 0.0) {
      tempJobs = tempJobs.where((job) {
        final hasGeo = job.lat != 0.0 && job.lng != 0.0;
        if (!hasGeo) return false;
        final distance = calculateDistance(
            currentLatitude, currentLongitude, job.lat, job.lng);
        return distance <= selectedDistance;
      }).toList();
    }

    if (selectedPayType != 'all') {
      tempJobs = tempJobs.where((job) {
        final payTypeInEnglish = job.payType == '일급'
            ? 'daily'
            : job.payType == '주급'
                ? 'weekly'
                : 'all';
        return payTypeInEnglish == selectedPayType;
      }).toList();
    }

    if (selectedCategory != '전체') {
      tempJobs =
          tempJobs.where((job) => job.category == selectedCategory).toList();
    }

    if (searchQuery.isNotEmpty) {
      tempJobs = tempJobs
          .where((job) =>
              job.title.contains(searchQuery) ||
              job.location.contains(searchQuery))
          .toList();
    }

    int cmpPinned(Job a, Job b) {
      final ap = isPinned(a), bp = isPinned(b);
      if (ap != bp) return bp ? 1 : -1;
      if (ap && bp) return b.pinnedUntil!.compareTo(a.pinnedUntil!);
      return 0;
    }

    switch (sortType) {
      case '거리순':
        tempJobs.sort((a, b) {
          final c = cmpPinned(a, b);
          if (c != 0) return c;
          final distA = calculateDistance(
              currentLatitude, currentLongitude, a.lat, a.lng);
          final distB = calculateDistance(
              currentLatitude, currentLongitude, b.lat, b.lng);
          return distA.compareTo(distB);
        });
        break;
      case '급여 높은 순':
        tempJobs.sort((a, b) {
          final c = cmpPinned(a, b);
          if (c != 0) return c;
          return payValue(b).compareTo(payValue(a));
        });
        break;
      case '최신순':
      default:
        tempJobs.sort((a, b) {
          final c = cmpPinned(a, b);
          if (c != 0) return c;
          final aDate = a.publishAt ??
              a.createdAt ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
          final bDate = b.publishAt ??
              b.createdAt ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
          return bDate.compareTo(aDate);
        });
    }

    setState(() {
      filteredJobs = tempJobs;
      _itemsToShow = 10;
    });
  }

  void _openFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        String tempSortType = sortType;
        String tempPayType = selectedPayType;
        String tempCategory = selectedCategory;

        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.only(top: 40),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: StatefulBuilder(
              builder: (context, setModalState) {
                final bottomInset = MediaQuery.of(context).viewInsets.bottom;
                return Padding(
                  padding:
                      EdgeInsets.fromLTRB(16, 12, 16, bottomInset + 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(999))),
                      Row(
                        children: [
                          const Text('필터',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w700)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                  color: const Color(0xFFE7F0FF),
                                  borderRadius: BorderRadius.circular(999)),
                              child: Text(
                                '${tempCategory == "전체" ? "모든 업종" : tempCategory} · '
                                '${tempPayType == "all" ? "전체 급여" : (tempPayType == "daily" ? "일급" : "주급")}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11, color: Color(0xFF3B8AFF)),
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => setModalState(() {
                              tempSortType = '최신순';
                              tempPayType = 'all';
                              tempCategory = '전체';
                            }),
                            child: const Text('초기화',
                                style: TextStyle(
                                    fontSize: 13, color: Colors.grey)),
                          ),
                          IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.pop(context)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Flexible(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 8),
                              _buildFilterSectionTitle('정렬'),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                    color: Colors.grey[50],
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: Colors.grey.shade200)),
                                child: DropdownButton<String>(
                                  value: tempSortType,
                                  isExpanded: true,
                                  items: ['거리순', '최신순', '급여 높은 순']
                                      .map((e) => DropdownMenuItem(
                                          value: e,
                                          child: Text(e,
                                              style: const TextStyle(
                                                  fontSize: 14))))
                                      .toList(),
                                  onChanged: (v) {
                                    if (v != null)
                                      setModalState(() => tempSortType = v);
                                  },
                                  underline: const SizedBox(),
                                  icon: const Icon(Icons.expand_more),
                                ),
                              ),
                              const SizedBox(height: 20),
                              _buildFilterSectionTitle('급여 유형'),
                              const SizedBox(height: 8),
                              Wrap(spacing: 8, runSpacing: 8, children: [
                                _buildPayChipInSheet(
                                    label: '전체',
                                    value: 'all',
                                    groupValue: tempPayType,
                                    onChanged: (v) => setModalState(
                                        () => tempPayType = v)),
                                _buildPayChipInSheet(
                                    label: '일급',
                                    value: 'daily',
                                    groupValue: tempPayType,
                                    onChanged: (v) => setModalState(
                                        () => tempPayType = v)),
                                _buildPayChipInSheet(
                                    label: '주급',
                                    value: 'weekly',
                                    groupValue: tempPayType,
                                    onChanged: (v) => setModalState(
                                        () => tempPayType = v)),
                              ]),
                              const SizedBox(height: 20),
                              _buildFilterSectionTitle('업종'),
                              const SizedBox(height: 8),
                              Wrap(spacing: 8, runSpacing: 8, children: [
                                for (final cat in [
                                  '전체',
                                  '제조',
                                  '물류',
                                  '서비스',
                                  '건설',
                                  '사무',
                                  '청소',
                                  '기타'
                                ])
                                  _buildCategoryChipInSheet(
                                      label: cat,
                                      value: cat,
                                      groupValue: tempCategory,
                                      onChanged: (v) => setModalState(
                                          () => tempCategory = v)),
                              ]),
                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                              child: OutlinedButton(
                            onPressed: () => setModalState(() {
                              tempSortType = '최신순';
                              tempPayType = 'all';
                              tempCategory = '전체';
                            }),
                            style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.grey[800],
                                side: BorderSide(
                                    color: Colors.grey.shade300)),
                            child: const Text('초기화'),
                          )),
                          const SizedBox(width: 8),
                          Expanded(
                              child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF3B8AFF),
                                minimumSize: const Size.fromHeight(44)),
                            onPressed: () {
                              setState(() {
                                sortType = tempSortType;
                                selectedPayType = tempPayType;
                                selectedCategory = tempCategory;
                              });
                              _applyFiltersThrottled();
                              Navigator.pop(context);
                            },
                            child: const Text('적용하기',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600)),
                          )),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterSectionTitle(String title) {
    return Row(children: [
      Text(title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      const SizedBox(width: 6),
      Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
              color: const Color(0xFF3B8AFF),
              borderRadius: BorderRadius.circular(999))),
    ]);
  }

  Widget _buildCategoryChipInSheet(
      {required String label,
      required String value,
      required String groupValue,
      required ValueChanged<String> onChanged}) {
    final selected = groupValue == value;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 13)),
      selected: selected,
      onSelected: (_) => onChanged(value),
      selectedColor: const Color(0xFFDDE3FF),
      backgroundColor: Colors.grey.shade100,
      labelStyle:
          TextStyle(color: selected ? Colors.black : Colors.grey[700]),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
              color: selected ? Colors.transparent : Colors.grey.shade300)),
    );
  }

  Widget _buildPayChipInSheet(
      {required String label,
      required String value,
      required String groupValue,
      required ValueChanged<String> onChanged}) {
    final selected = groupValue == value;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 13)),
      selected: selected,
      onSelected: (_) => onChanged(value),
      selectedColor: const Color(0xFFDDE3FF),
      backgroundColor: Colors.grey.shade100,
      labelStyle:
          TextStyle(color: selected ? Colors.black : Colors.grey[700]),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
              color: selected ? Colors.transparent : Colors.grey.shade300)),
    );
  }

  double calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) *
            cos(_deg2rad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _deg2rad(double deg) => deg * (pi / 180);

  String _trimProvince(String raw) {
    if (raw.isEmpty) return raw;
    final parts =
        raw.split(_reWhitespace).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return raw;
    if (parts.first.endsWith('도')) parts.removeAt(0);
    if (parts.isEmpty) return raw;
    return parts.join(' ');
  }

  String? _buildAiSummary(Job job) {
    final score = job.matchScore;
    final reasons = job.matchReasons;
    if ((score == null || score < 0.6) && reasons.isEmpty) return null;

    final parts = <String>[];
    for (final r in reasons.take(2)) {
      switch (r) {
        case '가까움': parts.add('가깝고'); break;
        case '시간대겹침': parts.add('시간대가 맞고'); break;
        case '시급상위': parts.add('시급이 높고'); break;
        case '당일지급': parts.add('당일 지급이고'); break;
        case '완료이력좋음': parts.add('완료 이력이 좋고'); break;
        case '의미유사': parts.add('업무가 잘 맞아요'); break;
      }
    }

    final pct = score != null ? ' ${(score * 100).round()}%' : '';
    final reasonText =
        parts.isEmpty ? '잘 맞는 공고예요' : '${parts.join(' ')} 잘 맞아요';
    return 'AI$pct · $reasonText';
  }

  // ─────────────────────────────────────────────
  // [A안] 지원하기 직접 API 호출 + 채팅방 생성 플로우
  // job_detail_screen의 _applyToJob과 동일한 플로우
  // ─────────────────────────────────────────────
  Future<void> _applyDirectly(Job job) async {
    final jobIdInt = int.tryParse(job.id.toString());
    if (jobIdInt == null) return;

    final prefs = await SharedPreferences.getInstance();
    final workerId = prefs.getInt('userId');
    final clientId = job.clientId;

    if (workerId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요해요.')),
      );
      return;
    }

    if (clientId == null) {
      if (!mounted) return;
      // clientId 없으면 상세화면으로 유도
      _openJobDetail(job);
      return;
    }

    if (!mounted) return;
    setState(() => _quickApplyingJobId = jobIdInt);

    try {
      final resp = await http.post(
        Uri.parse('$baseUrl/api/job/apply'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'workerId': workerId, 'jobId': jobIdInt}),
      );
      if (!mounted) return;

      if (resp.statusCode == 200) {
        setState(() => appliedJobIds.add(jobIdInt));
        LogService.instance.logEvent(eventType: LogService.apply, jobId: jobIdInt);

        // 채팅방 생성
        final roomId = await startChatRoom(workerId, jobIdInt.toString(), clientId);
        if (!mounted) return;

        if (roomId != null) {
          // 이동 안내 다이얼로그
          final goToChat = await _showChatMoveNoticeDialog(job);
          if (!mounted) return;

          if (goToChat) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatRoomScreen(
                  chatRoomId: roomId,
                  jobInfo: {
                    'title': job.title,
                    'pay': job.pay,
                    'posted_at': '',
                    'publish_at': job.publishAt?.toUtc().toIso8601String() ?? '',
                    'created_at': job.createdAt?.toUtc().toIso8601String() ?? '',
                    'client_id': clientId,
                    'worker_id': workerId,
                    'client_company_name': job.company ?? '기업',
                    'client_thumbnail_url': '',
                  },
                ),
              ),
            );
          } else {
            // 나중에 보기 → 스낵바만
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text('지원 완료! 채팅탭에서 대화를 이어가세요.'),
                  ],
                ),
                backgroundColor: const Color(0xFF3B8AFF),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            );
          }
        } else {
          // 채팅방 생성 실패 — 지원은 됐으니 스낵바만
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('지원 완료! 사장님 연락을 기다려주세요.'),
                ],
              ),
              backgroundColor: const Color(0xFF3B8AFF),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      } else if (resp.statusCode == 409) {
        if (!mounted) return;
        setState(() => appliedJobIds.add(jobIdInt));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이미 지원한 공고예요.')),
        );
      } else {
        if (!mounted) return;
        String msg = '지원에 실패했어요. 다시 시도해주세요.';
        try {
          final data = jsonDecode(resp.body);
          if (data is Map && data['message'] is String) msg = data['message'];
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red.shade400),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('네트워크 오류가 발생했어요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _quickApplyingJobId = null);
    }
  }

  // ─────────────────────────────────────────────
  // 채팅방 이동 안내 다이얼로그 (job_detail과 동일)
  // ─────────────────────────────────────────────
  Future<bool> _showChatMoveNoticeDialog(Job job) async {
    if (!mounted) return false;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B8AFF).withOpacity(0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        color: Color(0xFF3B8AFF),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        '지원이 완료되었어요!',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Jalnan2TTF',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  '이 공고에 대한 채팅방이 열렸어요.\n사장님과 바로 대화하면서 급여, 근무 조건,\n위치 등을 한 번 더 확인해보는 걸 추천해요 🙂',
                  style: TextStyle(fontSize: 14, height: 1.5, color: Color(0xFF444444)),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE7F0FF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.flash_on_rounded, size: 16, color: Color(0xFF3B8AFF)),
                      SizedBox(width: 6),
                      Text(
                        '빠른 응답일수록 채용 가능성이 커져요',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF3B8AFF),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          side: BorderSide(color: Colors.grey.shade300),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('나중에 보기',
                            style: TextStyle(fontSize: 14, color: Colors.black87)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B8AFF),
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                          elevation: 0,
                        ),
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('채팅방으로 이동',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final nearbyCount = isLoading ? 0 : filteredJobs.length;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(86),
          child: AppBar(
            backgroundColor: Colors.white,
            elevation: 1,
            toolbarHeight: 74,
            titleSpacing: 16,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '알바일주 알바생',
                      style: TextStyle(
                          fontFamily: 'Jalnan2TTF',
                          fontSize: 22,
                          color: Color(0xFF3B8AFF),
                          fontWeight: FontWeight.w800),
                    ),
                    Row(
                      children: [
                        Text('오늘 가능',
                            style: TextStyle(
                                fontSize: 14,
                                color: isAvailableToday
                                    ? Colors.green
                                    : Colors.grey)),
                        const SizedBox(width: 4),
                        Switch(
                          value: isAvailableToday,
                          activeThumbColor: Colors.green,
                          onChanged: (value) {
                            setState(() => isAvailableToday = value);
                            setAvailableToday(value);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  isLoading
                      ? '내 근처 단기 알바 탐색 중...'
                      : '내 근처 단기 알바 ${nearbyCount}개',
                  style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                      height: 1.1),
                ),
              ],
            ),
          ),
        ),
        body: SafeArea(
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTopControlRow(nearbyCount),
                      if (!isLoading &&
                          _workerGender == null &&
                          !_genderHintDismissed) ...[
                        const SizedBox(height: 8),
                        _buildGenderHintCard(),
                      ],
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(child: _buildBannerSlider()),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              SliverToBoxAdapter(
                child: _AiRecommendStrip(
                  onJobTap: (job) => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => JobDetailScreen(job: job)),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 4)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildDistanceSlider(),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              if (isLoading)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: _buildSkeletonList(),
                )
              else if (filteredJobs.isEmpty)
                SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildEmptyJobsView())
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList.builder(
                    itemCount: (_itemsToShow < filteredJobs.length)
                        ? _itemsToShow
                        : filteredJobs.length,
                    itemBuilder: (context, index) {
                      final job = filteredJobs[index];
                      return compactView
                          ? GestureDetector(
                              onTap: () => _openJobDetail(job),
                              child: _buildCompactJobCard(job),
                            )
                          : _buildJobCard(job);
                    },
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGenderHintCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFCC80)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.info_outline,
              size: 16, color: Color(0xFFFB8C00)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '프로필에서 성별을 설정하면 더 잘 맞는 공고를 추천해 드려요.',
              style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6D4C41),
                  fontWeight: FontWeight.w500),
            ),
          ),
          GestureDetector(
            onTap: _dismissGenderHint,
            child: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.close, size: 16, color: Color(0xFF9E9E9E)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonList() {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (_, __) => AnimatedBuilder(
          animation: _shimmerCtrl,
          builder: (_, __) {
            final opacity = 0.4 + _shimmerCtrl.value * 0.4;
            return Opacity(
              opacity: opacity,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 0.8)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _shimmerBox(60, 11),
                          const SizedBox(height: 6),
                          _shimmerBox(180, 15),
                          const SizedBox(height: 4),
                          _shimmerBox(140, 11),
                          const SizedBox(height: 8),
                          _shimmerBox(90, 17),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _shimmerBox(70, 70, radius: 12),
                  ],
                ),
              ),
            );
          },
        ),
        childCount: 6,
      ),
    );
  }

  Widget _shimmerBox(double width, double height, {double radius = 6}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  Widget _buildEmptyJobsView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                  color: const Color(0xFFE7F0FF),
                  borderRadius: BorderRadius.circular(999)),
              child: const Icon(Icons.place_rounded,
                  size: 34, color: Color(0xFF3B8AFF)),
            ),
            const SizedBox(height: 14),
            const Text('지금 이 거리에는 공고가 없어요 😭',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E2A3A),
                    height: 1.2)),
            const SizedBox(height: 8),
            Text(
                '거리 범위를 조금 늘리거나,\n위치 권한을 켜면 더 많은 공고를 찾을 수 있어요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    height: 1.35,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: () async => _init(),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('내 주변 다시 찾기',
                    style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B8AFF),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton.icon(
                onPressed: () async => Geolocator.openAppSettings(),
                icon: const Icon(Icons.settings_rounded,
                    size: 18, color: Color(0xFF3B8AFF)),
                label: const Text('위치 권한 설정',
                    style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF3B8AFF))),
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                        color: Color(0xFF3B8AFF), width: 1.2),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return SizedBox(
      height: 36,
      child: TextField(
        onChanged: (value) {
          searchQuery = value;
          _runDebounced(_applyFiltersThrottled);
        },
        decoration: InputDecoration(
          hintText: '알바를 검색해보세요',
          prefixIcon: const Icon(Icons.search, size: 18),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          isDense: true,
          border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        style: const TextStyle(fontSize: 13),
      ),
    );
  }

  String _distanceHint(double km) {
    if (km <= 2.0) return '집 앞 알바감 👣 (도보 10분 컷)';
    if (km <= 5.0) return '동네 한 바퀴 거리 ☕ (도보 30분 / 차로 10분)';
    if (km <= 10.0) return '퇴근 후도 무난한 거리 🚗 (차로 15~20분)';
    if (km <= 20.0) return '주말 알바 당일치기 존 ✨ (차로 30분대)';
    return '마음먹으면 충분히 가는 거리 💨 (차로 1시간 내외)';
  }

  Widget _buildDistanceSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('📏 거리 설정',
                style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            Text('${selectedDistance.toStringAsFixed(0)}km',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF3B8AFF))),
          ],
        ),
        Slider(
          min: 1,
          max: 30,
          divisions: 29,
          value: selectedDistance,
          onChanged: (value) =>
              setState(() => selectedDistance = value),
          onChangeEnd: (value) async {
            if (currentLatitude == 0.0 || currentLongitude == 0.0)
              await _init();
            _applyFiltersThrottled();
          },
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
              color: const Color(0xFFE7F0FF),
              borderRadius: BorderRadius.circular(10)),
          child: Row(
            children: [
              const Icon(Icons.place_rounded,
                  size: 18, color: Color(0xFF3B8AFF)),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(_distanceHint(selectedDistance),
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E2A3A)))),
            ],
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // [A안] 핵심 변경: 카드 하단 액션 버튼
  // 북마크 | 자세히(아웃라인) | 지원하기(채워진)
  // ─────────────────────────────────────────────
  Widget _buildJobCard(Job job) {
    final payInt =
        int.tryParse(job.pay.replaceAll(_reNonDigit, '')) ?? 0;
    final formattedPay = NumberFormat('#,###').format(payInt);
    final jobIdInt = int.tryParse(job.id.toString());
    final isApplied = appliedJobIds.contains(jobIdInt);
    final isApplyingNow = _quickApplyingJobId == jobIdInt;

    final distanceKm = _distanceKmFromUser(job);
    final baseLocation = _trimProvince(job.location);
    final String? distanceText = distanceKm == null
        ? null
        : (distanceKm < 10
            ? distanceKm.toStringAsFixed(1)
            : distanceKm.toStringAsFixed(0));
    final String locationLine = distanceText == null
        ? baseLocation
        : '$baseLocation · ${distanceText}km';

    final nowUtc = DateTime.now().toUtc();
    final bool isPinned =
        job.pinnedUntil != null && job.pinnedUntil!.isAfter(nowUtc);

    final postedAt = job.publishAt ?? job.createdAt;
    final bool isNew = postedAt != null &&
        nowUtc.difference(postedAt).inHours < 24;

    final bool isUrgent = job.endDate != null &&
        !job.endDate!.isBefore(nowUtc) &&
        job.endDate!.difference(nowUtc).inDays <= 2;

    final List<Widget> opBadges = [];
    if (job.jobType == 'long')
      opBadges.add(_buildBadge('장기', color: const Color(0xFF7C3AED)));
    if (isNew)
      opBadges.add(_buildBadge('신규', color: const Color(0xFFEF4444)));
    if (isUrgent)
      opBadges.add(_buildBadge('마감임박', color: const Color(0xFFF97316)));
    if (job.payType == '월급')
      opBadges.add(_buildBadge('월급', color: const Color(0xFF0369A1)));
    else if (job.payType == '일급')
      opBadges.add(_buildBadge('일급', color: const Color(0xFF185FA5)));
    else if (job.payType == '주급')
      opBadges.add(_buildBadge('주급', color: const Color(0xFF534AB7)));
    if (job.isSameDayPay == true)
      opBadges.add(_buildBadge('당일지급', color: const Color(0xFF0F6E56)));
    else if (job.isCertifiedCompany == true)
      opBadges.add(_buildBadge('안심기업', color: const Color(0xFF3B6D11)));

    final displayBadges = opBadges.take(2).toList();
    final aiSummary = _buildAiSummary(job);

    return Stack(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 0),
          margin: const EdgeInsets.only(bottom: 2),
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(
                    color: Colors.grey.shade200, width: 0.8)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 상단: 정보 + 썸네일
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _openJobDetail(job),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(locationLine,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                  fontWeight: FontWeight.w500)),
                          const SizedBox(height: 4),
                          Text(job.title,
                              style: const TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1A1A1A)),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 5),
                          Wrap(spacing: 10, runSpacing: 2, children: [
                            if (job.startDate != null && job.endDate != null)
                              _metaText('기간',
                                  '${_formatDate(job.startDate!)} ~ ${_formatDate(job.endDate!)}'),
                            _metaText('시간', job.workingHours),
                          ]),
                          const SizedBox(height: 6),
                          RichText(
                            text: TextSpan(
                              children: [
                                if (job.payType.isNotEmpty)
                                  TextSpan(
                                    text: '${job.payType} ',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF3B8AFF),
                                    ),
                                  ),
                                TextSpan(
                                  text: '$formattedPay원',
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF111111),
                                    height: 1.1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (job.imageUrls.isNotEmpty)
                    GestureDetector(
                      onTap: () => _openJobDetail(job),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Builder(builder: (context) {
                            final raw = job.imageUrls.first;
                            final url = raw.startsWith('http')
                                ? raw
                                : '$baseUrl$raw';
                            return Image.network(url,
                                width: 68,
                                height: 68,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const SizedBox.shrink());
                          }),
                        ),
                      ),
                    ),
                ],
              ),

              // 배지
              if (displayBadges.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 4, children: displayBadges),
              ],

              // AI 요약
              if (aiSummary != null) ...[
                const SizedBox(height: 5),
                Row(children: [
                  const Text('✦',
                      style: TextStyle(
                          fontSize: 11, color: Color(0xFF3B8AFF))),
                  const SizedBox(width: 5),
                  Expanded(
                      child: Text(aiSummary,
                          style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.grey.shade500,
                              fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis)),
                ]),
              ],

              const SizedBox(height: 10),

              // ── [A안] 하단 액션 행: 북마크 | 자세히 | 지원하기 ──
              Row(
                children: [
                  // 북마크
                  _BookmarkButton(
                    isBookmarked: bookmarkedJobIds.contains(job.id.toString()),
                    onTap: () => _toggleBookmark(job.id.toString()),
                  ),
                  const SizedBox(width: 8),
                  // 자세히 보기
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: OutlinedButton(
                        onPressed: () => _openJobDetail(job),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.grey.shade300),
                          foregroundColor: Colors.grey.shade700,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('자세히',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // 지원하기
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 36,
                      child: ElevatedButton(
                        onPressed: isApplied || isApplyingNow
                            ? null
                            : () => _applyDirectly(job),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isApplied
                              ? Colors.grey.shade300
                              : const Color(0xFF3B8AFF),
                          disabledBackgroundColor: Colors.grey.shade300,
                          elevation: 0,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: isApplyingNow
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    isApplied
                                        ? Icons.check_circle_outline
                                        : Icons.bolt_rounded,
                                    size: 16,
                                    color: isApplied
                                        ? Colors.grey.shade600
                                        : Colors.white,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isApplied ? '지원 완료' : '지원하기',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: isApplied
                                          ? Colors.grey.shade600
                                          : Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (isPinned)
          const Positioned(top: 6, right: 0, child: _PinnedBadge()),
      ],
    );
  }

  Widget _buildTopControlRow(int nearbyCount) {
    return Row(
      children: [
        Expanded(child: _buildSearchField()),
        const SizedBox(width: 8),
        SizedBox(
          height: 36,
          child: OutlinedButton.icon(
            onPressed: () async {
              await _init();
              _applyFiltersThrottled();
            },
            icon: const Icon(Icons.my_location, size: 18),
            label: const Text('위치', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF3B8AFF)),
              foregroundColor: const Color(0xFF3B8AFF),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 36,
          child: OutlinedButton.icon(
            onPressed: _openFilterSheet,
            icon: const Icon(Icons.tune, size: 18),
            label: const Text('필터', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF3B8AFF)),
              foregroundColor: const Color(0xFF3B8AFF),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBadge(String label, {Color color = const Color(0xFF185FA5)}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        border: Border.all(color: color.withOpacity(0.35)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildCompactJobCard(Job job) {
    final payInt =
        int.tryParse(job.pay.replaceAll(_reNonDigit, '')) ?? 0;
    final formattedPay = NumberFormat('#,###').format(payInt);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(
                  color: Colors.grey.shade300, width: 0.7))),
      child: Row(
        children: [
          Expanded(
            child: Text(job.title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.indigo,
                    decoration: TextDecoration.underline),
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 6),
          Flexible(
              child: Text('📍 ${job.location}',
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 6),
          Flexible(
              child: Text('💰 $formattedPay원',
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis)),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(
              bookmarkedJobIds.contains(job.id)
                  ? Icons.bookmark
                  : Icons.bookmark_border,
              color: bookmarkedJobIds.contains(job.id)
                  ? Colors.orange
                  : Colors.grey,
            ),
            onPressed: () => _toggleBookmark(job.id),
          ),
        ],
      ),
    );
  }

  Widget _metaText(String label, String value) {
    return RichText(
      text: TextSpan(
        text: '$label ',
        style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade400,
            fontWeight: FontWeight.w400,
            height: 1.3),
        children: [
          TextSpan(
              text: value,
              style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w400))
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final d = date.toLocal();
    return '${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
  }

  Widget _buildBannerSlider() {
    if (_isBannerHidden || bannerAds.isEmpty) return const SizedBox.shrink();

    final canNav = bannerAds.length > 1;

    void goTo(int index) {
      if (!mounted || _pageController == null || !_pageController!.hasClients)
        return;
      final len = bannerAds.length;
      final safe = ((index % len) + len) % len;
      _pageController!.animateToPage(safe,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic);
    }

    Widget circleBtn(IconData icon, VoidCallback onTap) => ClipOval(
          child: Material(
            color: Colors.black.withOpacity(0.22),
            child: InkWell(
                onTap: onTap,
                child: SizedBox(
                    width: 30,
                    height: 30,
                    child: Icon(icon, size: 18, color: Colors.white))),
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AspectRatio(
        aspectRatio: 4 / 1,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: PageView.builder(
                controller: _pageController,
                itemCount: bannerAds.length,
                onPageChanged: (index) {
                  if (!mounted) return;
                  setState(() => _currentBannerIndex = index);
                },
                itemBuilder: (context, index) {
                  final banner = bannerAds[index];
                  return GestureDetector(
                    onTap: () => _onBannerTap(banner),
                    child: DecoratedBox(
                      decoration:
                          BoxDecoration(color: Colors.grey.shade200),
                      child: Image.network(
                        '$baseUrl${banner.imageUrl}',
                        fit: BoxFit.contain,
                        alignment: Alignment.center,
                        filterQuality: FilterQuality.high,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const Center(
                              child: CircularProgressIndicator(
                                  strokeWidth: 2));
                        },
                        errorBuilder: (context, error, stackTrace) =>
                            const Center(
                                child: Icon(Icons.error_outline,
                                    color: Colors.grey)),
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
                      child: circleBtn(Icons.chevron_left,
                          () => goTo(_currentBannerIndex - 1)))),
              Positioned(
                  right: 8,
                  top: 0,
                  bottom: 0,
                  child: Center(
                      child: circleBtn(Icons.chevron_right,
                          () => goTo(_currentBannerIndex + 1)))),
            ],
            Positioned(
              top: 6,
              right: 6,
              child: GestureDetector(
                onTap: () => setState(() => _isBannerHidden = true),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.22),
                      shape: BoxShape.circle),
                  child: const Icon(Icons.close,
                      size: 14, color: Colors.white),
                ),
              ),
            ),
            Positioned(
              bottom: 6,
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
                          margin:
                              const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: _currentBannerIndex == i
                                ? Colors.white
                                : Colors.white.withOpacity(0.45),
                          ),
                        )),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onBannerTap(BannerAd banner) async {
    if (banner.linkUrl == null || banner.linkUrl!.isEmpty) return;
    final bannerId = int.tryParse(banner.id.toString());
    if (bannerId != null) _recordBannerClick(bannerId);
    final Uri url = Uri.parse(banner.linkUrl!);
    try {
      await launchUrl(url, mode: LaunchMode.platformDefault);
    } catch (e) {
      debugPrint('❌ 링크 열기 오류: $e');
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('링크 열기 실패: $e')));
    }
  }
}

// ─────────────────────────────────────────────
// [A안] 북마크 버튼 - 별도 위젯으로 분리
// ─────────────────────────────────────────────
class _BookmarkButton extends StatelessWidget {
  final bool isBookmarked;
  final VoidCallback onTap;

  const _BookmarkButton({required this.isBookmarked, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          border: Border.all(
            color: isBookmarked
                ? Colors.red.shade200
                : Colors.grey.shade300,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          isBookmarked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          size: 18,
          color: isBookmarked ? const Color(0xFFEF4444) : Colors.grey.shade400,
        ),
      ),
    );
  }
}

class _PinnedBadge extends StatelessWidget {
  const _PinnedBadge();
  @override
  Widget build(BuildContext context) => const Text(
        '광고',
        style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: Colors.grey,
            height: 1.0),
      );
}

// ─────────────────────────────────────────────
// AI 추천 가로 스크롤 스트립
// ─────────────────────────────────────────────

class _AiRecommendStrip extends StatefulWidget {
  final void Function(Job job) onJobTap;
  const _AiRecommendStrip({required this.onJobTap});

  @override
  State<_AiRecommendStrip> createState() => _AiRecommendStripState();
}

class _AiRecommendStripState extends State<_AiRecommendStrip> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final workerId = prefs.getInt('userId');
      final token = prefs.getString('authToken') ?? '';
      if (workerId == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final resp = await http.get(
        Uri.parse('$baseUrl/api/rank/jobs?workerId=$workerId&limit=8'),
        headers: {if (token.isNotEmpty) 'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 6));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final List raw = data is List ? data : (data['data'] ?? data['jobs'] ?? []);
        setState(() {
          _items = raw.take(6).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF3B8AFF), Color(0xFF6C63FF)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, size: 12, color: Colors.white),
                    SizedBox(width: 4),
                    Text('AI 맞춤 추천',
                        style: TextStyle(
                            fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text('나에게 딱 맞는 공고',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ],
          ),
        ),
        SizedBox(
          height: 110,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _items.length,
            itemBuilder: (_, i) {
              final it = _items[i];
              final title = (it['title'] ?? '').toString();
              final city = (it['location_city'] ?? it['location'] ?? '').toString();
              final payRaw = (it['pay'] ?? 0).toString().replaceAll(_reNonDigit, '');
              final payInt = int.tryParse(payRaw) ?? 0;
              final payStr = payInt > 0 ? '${NumberFormat('#,###').format(payInt)}원' : '';
              final reasons = (it['reasons'] is List)
                  ? (it['reasons'] as List).take(2).map((e) => e.toString()).toList()
                  : <String>[];
              final jobId = it['jobId'] ?? it['job_id'] ?? it['id'];

              return GestureDetector(
                onTap: () async {
                  final raw = await http.get(
                    Uri.parse('$baseUrl/api/job/$jobId'),
                  );
                  if (raw.statusCode == 200) {
                    try {
                      final job = Job.fromJson(jsonDecode(raw.body));
                      widget.onJobTap(job);
                    } catch (_) {}
                  }
                },
                child: Container(
                  width: 180,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE8EDFF), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF3B8AFF).withOpacity(0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700, height: 1.3)),
                      const Spacer(),
                      if (payStr.isNotEmpty)
                        Text(payStr,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF3B8AFF))),
                      if (city.isNotEmpty)
                        Text(city,
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                      if (reasons.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('✦ ${reasons.first}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}