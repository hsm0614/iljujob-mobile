import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/models/job.dart';
import '../../../data/services/job_service.dart';
import 'dart:math';
import 'package:intl/intl.dart';
import 'job_detail_screen.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:io';
import 'package:iljujob/config/constants.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:iljujob/data/services/log_service.dart';
import 'package:iljujob/data/services/screen_analytics_service.dart';
import 'package:iljujob/data/services/chat_service.dart';
import 'package:iljujob/presentation/chat/chat_room_screen.dart';
import 'package:iljujob/data/services/ai_labor_service.dart';
import 'package:iljujob/data/services/authenticated_http_client.dart';
import 'package:iljujob/config/app_theme.dart';
import 'package:iljujob/widget/app_ui.dart';
import 'package:iljujob/widget/ad_banner_widget.dart';
import 'package:iljujob/utils/pay_display.dart';
import 'package:iljujob/data/models/partner_recruit_post.dart';
import 'package:iljujob/presentation/screens/worker_screen/partner_recruit_detail_screen.dart';

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
  final TextEditingController _searchController = TextEditingController();
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
  bool _distanceExpanded = false;

  bool _genderHintDismissed = false;
  static const _kGenderHintKey = 'gender_hint_dismissed';

  // 파트너 채용공고 카드: 닫으면 7일간 숨김 (광고 피로도 완화)
  bool _partnerCardHidden = false;
  static const _kPartnerCardHiddenUntilKey = 'partner_card_hidden_until';
  static const _partnerCardHideDays = 7;

  // AI 추천 스트립을 공고 리스트 N번째 뒤에 삽입
  static const _aiStripAfter = 4;


  double? _distanceKmFromUser(Job job) {
    if (currentLatitude == 0.0 ||
        currentLongitude == 0.0 ||
        job.lat == 0.0 ||
        job.lng == 0.0) {
      return null;
    }
    return calculateDistance(
      currentLatitude,
      currentLongitude,
      job.lat,
      job.lng,
    );
  }

  @override
  void initState() {
    super.initState();
    ScreenAnalyticsService.instance.logScreenView('worker_home');
    _requestNotificationPermission();
    _loadGenderHintDismissed();
    _loadPartnerCardHidden();
    _loadAvailableTodayStatus();
    _loadWorkerProfileBrief();
    _loadBookmarks()
        .then((_) async {
          await _init();
          await _loadJobsWithAppliedStatus();
          if (mounted) setState(() => isLoading = false);
        })
        .catchError((e) async {
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
    _scrollController.dispose();
    _searchController.dispose();
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

  Future<void> _loadPartnerCardHidden() async {
    final prefs = await SharedPreferences.getInstance();
    final until = prefs.getInt(_kPartnerCardHiddenUntilKey) ?? 0;
    if (!mounted) return;
    setState(() {
      _partnerCardHidden = DateTime.now().millisecondsSinceEpoch < until;
    });
  }

  Future<void> _dismissPartnerCard() async {
    final prefs = await SharedPreferences.getInstance();
    final until = DateTime.now().add(
      const Duration(days: _partnerCardHideDays),
    );
    await prefs.setInt(_kPartnerCardHiddenUntilKey, until.millisecondsSinceEpoch);
    if (!mounted) return;
    setState(() => _partnerCardHidden = true);
  }

  Timer? _debounce;
  bool _isApplying = false;

  void _runDebounced(
    void Function() action, [
    Duration delay = const Duration(milliseconds: 180),
  ]) {
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

  Future<void> _loadWorkerProfileBrief() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final workerId = prefs.getInt('userId');
      if (workerId == null) return;
      final res = await http.get(
        Uri.parse('$baseUrl/api/worker/profile?id=$workerId'),
      );
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
      debugPrint('_loadWorkerProfileBrief 오류: $e');
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
      debugPrint('알림 권한 거부됨');
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
        body: jsonEncode({
          'userPhone': userPhone,
          'userType': userType,
          'fcmToken': token,
        }),
      );
    } catch (e) {
      debugPrint('토큰 전송 실패: $e');
    }
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    double lat = prefs.getDouble('currentLatitude') ?? 0.0;
    double lng = prefs.getDouble('currentLongitude') ?? 0.0;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            currentLatitude = 0.0;
            currentLongitude = 0.0;
          });
        }
        return;
      }

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            currentLatitude = 0.0;
            currentLongitude = 0.0;
          });
        }
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
          desiredAccuracy: LocationAccuracy.high,
        ).timeout(const Duration(seconds: 5));
      } on TimeoutException {}

      final finalLat = pos?.latitude ?? lat;
      final finalLng = pos?.longitude ?? lng;

      if (mounted) {
        setState(() {
          currentLatitude = finalLat;
          currentLongitude = finalLng;
        });
      }

      if (finalLat != 0.0 && finalLng != 0.0) {
        sendLocationToServer(finalLat, finalLng);
        await prefs.setDouble('currentLatitude', finalLat);
        await prefs.setDouble('currentLongitude', finalLng);
      }
    } catch (e) {
      debugPrint('위치 오류: $e');
      if (mounted) {
        setState(() {
          currentLatitude = 0.0;
          currentLongitude = 0.0;
        });
      }
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
          (json['data'] ??
              json['bookmarks'] ??
              json['items'] ??
              json['results']);
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
      debugPrint('loadBookmarks exception: $e\n$st');
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
        Uri.parse('$baseUrl/api/worker/available-status?userId=$userId'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (!mounted) return;
        setState(() {
          isAvailableToday = data['availableToday'] ?? false;
        });
      }
    } catch (e) {
      debugPrint('네트워크 오류: $e');
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
      debugPrint('위치 저장 예외: $e');
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
          if (wasBookmarked) {
            bookmarkedJobIds.remove(jobId);
          } else {
            bookmarkedJobIds.add(jobId);
          }
        });
        if (!wasBookmarked) {
          final jobIdInt = int.tryParse(jobId);
          if (jobIdInt != null) {
            LogService.instance.logEvent(
              eventType: LogService.bookmark,
              jobId: jobIdInt,
            );
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

      if (resp.body.contains('북마크 내역 없음') || resp.body.contains('존재하지')) {
        if (!mounted) return;
        setState(() {
          bookmarkedJobIds.remove(jobId);
        });
        await _loadBookmarks();
        return;
      }

      await _loadBookmarks();
    } catch (e, st) {
      debugPrint('toggle exception: $e\n$st');
      await _loadBookmarks();
    }
  }

  Future<void> fetchAppliedJobs(int userId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/apply/my-jobs?workerId=$userId'),
      );
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
      debugPrint('네트워크 오류: $e');
    }
  }

  Future<void> _loadJobs() async {
    if (_isLoadingJobs) return;
    _isLoadingJobs = true;
    final req = ++_jobsReqSeq;

    try {
      final hasLocation = currentLatitude != 0.0 && currentLongitude != 0.0;
      final jobs = await JobService.fetchJobs(
        clientId: null,
        lat: hasLocation ? currentLatitude : null,
        lng: hasLocation ? currentLongitude : null,
        radiusKm: selectedDistance,
      );
      if (req != _jobsReqSeq || !mounted) return;

      final prefs = await SharedPreferences.getInstance();
      final workerId = prefs.getInt('userId');
      final userType = prefs.getString('userType');

      Map<String, Map<String, dynamic>> scoreMap = {};

      if (workerId != null && userType == 'worker') {
        try {
          final aiRes = await http
              .get(
                Uri.parse(
                  '$baseUrl/api/rank/jobs?workerId=$workerId&lat=$currentLatitude&lng=$currentLongitude&limit=100',
                ),
              )
              .timeout(const Duration(seconds: 6));

          if (aiRes.statusCode == 200) {
            final data = jsonDecode(aiRes.body);
            final items = (data['items'] ?? data) as List? ?? [];
            for (final item in items) {
              final jobId = (item['jobId'] ?? item['job_id'])?.toString();
              if (jobId == null) continue;
              scoreMap[jobId] = {
                'score': (item['score'] as num?)?.toDouble(),
                'reasons':
                    (item['reasons'] as List?)
                        ?.map((e) => e.toString())
                        .toList() ??
                    <String>[],
              };
            }
          }
        } catch (e) {
          debugPrint('AI 매칭 로드 실패 (무시): $e');
        }
      }

      final enrichedJobs =
          jobs.map((j) {
            final ai = scoreMap[j.id];
            if (ai == null) return j;
            return j.copyWith(
              matchScore: ai['score'] as double?,
              matchReasons: ai['reasons'] as List<String>,
            );
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
          if (!hasGeo) continue;
          final d = calculateDistance(
            currentLatitude,
            currentLongitude,
            j.lat,
            j.lng,
          );
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
        final ap =
            a.publishAt ??
            a.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        final bp =
            b.publishAt ??
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
      debugPrint('_loadJobs 오류: $e');
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

    // 급여 정렬용 시급 환산.
    // 예전엔 문자열의 숫자만 비교해서 월급 390만원이 시급 11,000원보다
    // 항상 위로 왔다 — 급여순 정렬이 사실상 '월급 공고 먼저'였다.
    int hourlyPayValue(Job j) {
      final n = int.tryParse(j.pay.replaceAll(_reNonDigit, '')) ?? 0;
      if (n <= 0) return 0;
      switch (j.payType) {
        case '일급':
          return n ~/ 8; // 1일 8시간
        case '주급':
          return n ~/ 40; // 주 5일 x 8시간
        case '월급':
          return n ~/ 209; // 법정 월 소정근로시간
        default:
          return n; // 시급
      }
    }

    tempJobs =
        tempJobs.where((job) {
          final publishAt = job.publishAt ?? job.createdAt ?? nowUtc;
          final isFuture = publishAt.isAfter(nowUtc);
          final notExpired =
              (job.expiresAt == null) || job.expiresAt!.isAfter(nowUtc);
          if (isPinned(job)) return notExpired;
          return !isFuture && notExpired;
        }).toList();

    if (currentLatitude != 0.0 && currentLongitude != 0.0) {
      tempJobs =
          tempJobs.where((job) {
            final hasGeo = job.lat != 0.0 && job.lng != 0.0;
            // 좌표 없는 공고를 여기서 버리면 사장님이 올린 공고가
            // 아무에게도 안 보인다. 거리로 거르지 않고 목록 뒤로 보낸다.
            if (!hasGeo) return true;
            final distance = calculateDistance(
              currentLatitude,
              currentLongitude,
              job.lat,
              job.lng,
            );
            return distance <= selectedDistance;
          }).toList();
    }

    if (selectedPayType != 'all') {
      tempJobs =
          tempJobs.where((job) {
            final payTypeInEnglish =
                job.payType == '일급'
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
      tempJobs =
          tempJobs
              .where((job) {
                final q = searchQuery.trim();
                return job.title.contains(q) ||
                    job.location.contains(q) ||
                    job.category.contains(q) ||
                    (job.description?.contains(q) ?? false);
              })
              .toList();
    }

    int cmpPinned(Job a, Job b) {
      // 긴급 공고 최상단 (pinnedUntil보다 우선)
      if (a.isUrgent != b.isUrgent) return a.isUrgent ? -1 : 1;
      final ap = isPinned(a), bp = isPinned(b);
      if (ap != bp) return bp ? 1 : -1;
      if (ap && bp) return b.pinnedUntil!.compareTo(a.pinnedUntil!);
      return 0;
    }

    switch (sortType) {
      case '거리순':
        // 좌표 없는 공고는 거리를 알 수 없으므로 항상 뒤로
        double distOf(Job j) =>
            (j.lat == 0.0 && j.lng == 0.0)
                ? double.infinity
                : calculateDistance(
                  currentLatitude,
                  currentLongitude,
                  j.lat,
                  j.lng,
                );
        tempJobs.sort((a, b) {
          final c = cmpPinned(a, b);
          if (c != 0) return c;
          return distOf(a).compareTo(distOf(b));
        });
        break;
      case '급여 높은 순':
        tempJobs.sort((a, b) {
          final c = cmpPinned(a, b);
          if (c != 0) return c;
          return hourlyPayValue(b).compareTo(hourlyPayValue(a));
        });
        break;
      case '최신순':
      default:
        tempJobs.sort((a, b) {
          final c = cmpPinned(a, b);
          if (c != 0) return c;
          final aDate =
              a.publishAt ??
              a.createdAt ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
          final bDate =
              b.publishAt ??
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

  /// 지금 걸려 있는 필터를 칩으로. 탭하면 그 필터만 해제된다.
  /// 거리·정렬은 각각 전용 UI가 따로 있어 제외한다.
  List<Widget> get _activeFilterChips {
    Widget chip(String label, VoidCallback onRemove) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        onRemove();
        _applyFiltersThrottled();
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 5, 7, 5),
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: AppColors.primaryMid),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryDark,
              ),
            ),
            const SizedBox(width: 3),
            const Icon(
              Icons.close_rounded,
              size: 14,
              color: AppColors.primaryDark,
            ),
          ],
        ),
      ),
    );

    return [
      if (searchQuery.trim().isNotEmpty)
        chip('"${searchQuery.trim()}"', () {
          _searchController.clear();
          setState(() => searchQuery = '');
        }),
      if (selectedCategory != '전체')
        chip(selectedCategory, () => setState(() => selectedCategory = '전체')),
      if (selectedPayType != 'all')
        chip(selectedPayType == 'daily' ? '일급' : '주급', () {
          setState(() => selectedPayType = 'all');
        }),
    ];
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
              color: AppColors.bgCard,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppRadius.xxl),
              ),
            ),
            child: StatefulBuilder(
              builder: (context, setModalState) {
                final bottomInset = MediaQuery.of(context).viewInsets.bottom;
                return Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, bottomInset + 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(AppRadius.full),
                        ),
                      ),
                      Row(
                        children: [
                          const Text(
                            '필터',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primaryLight,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.full,
                                ),
                              ),
                              child: Text(
                                '${tempCategory == "전체" ? "모든 업종" : tempCategory} · '
                                '${tempPayType == "all" ? "전체 급여" : (tempPayType == "daily" ? "일급" : "주급")}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed:
                                () => setModalState(() {
                                  tempSortType = '최신순';
                                  tempPayType = 'all';
                                  tempCategory = '전체';
                                }),
                            child: const Text(
                              '초기화',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
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
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.bgMuted,
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.md,
                                  ),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: DropdownButton<String>(
                                  value: tempSortType,
                                  isExpanded: true,
                                  items:
                                      ['거리순', '최신순', '급여 높은 순']
                                          .map(
                                            (e) => DropdownMenuItem(
                                              value: e,
                                              child: Text(
                                                e,
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                          )
                                          .toList(),
                                  onChanged: (v) {
                                    if (v != null) {
                                      setModalState(() => tempSortType = v);
                                    }
                                  },
                                  underline: const SizedBox(),
                                  icon: const Icon(Icons.expand_more),
                                ),
                              ),
                              const SizedBox(height: 20),
                              _buildFilterSectionTitle('급여 유형'),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _buildPayChipInSheet(
                                    label: '전체',
                                    value: 'all',
                                    groupValue: tempPayType,
                                    onChanged:
                                        (v) => setModalState(
                                          () => tempPayType = v,
                                        ),
                                  ),
                                  _buildPayChipInSheet(
                                    label: '일급',
                                    value: 'daily',
                                    groupValue: tempPayType,
                                    onChanged:
                                        (v) => setModalState(
                                          () => tempPayType = v,
                                        ),
                                  ),
                                  _buildPayChipInSheet(
                                    label: '주급',
                                    value: 'weekly',
                                    groupValue: tempPayType,
                                    onChanged:
                                        (v) => setModalState(
                                          () => tempPayType = v,
                                        ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              _buildFilterSectionTitle('업종'),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final cat in [
                                    '전체',
                                    '제조',
                                    '물류',
                                    '서비스',
                                    '건설',
                                    '사무',
                                    '청소',
                                    '기타',
                                  ])
                                    _buildCategoryChipInSheet(
                                      label: cat,
                                      value: cat,
                                      groupValue: tempCategory,
                                      onChanged:
                                          (v) => setModalState(
                                            () => tempCategory = v,
                                          ),
                                    ),
                                ],
                              ),
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
                              onPressed:
                                  () => setModalState(() {
                                    tempSortType = '최신순';
                                    tempPayType = 'all';
                                    tempCategory = '전체';
                                  }),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.textSecondary,
                                side: const BorderSide(color: AppColors.border),
                              ),
                              child: const Text('초기화'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                minimumSize: const Size.fromHeight(44),
                              ),
                              onPressed: () {
                                setState(() {
                                  sortType = tempSortType;
                                  selectedPayType = tempPayType;
                                  selectedCategory = tempCategory;
                                });
                                _applyFiltersThrottled();
                                Navigator.pop(context);
                              },
                              child: const Text(
                                '적용하기',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
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
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 6),
        Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
        ),
      ],
    );
  }

  static const _categoryIcons = {
    '전체': Icons.search_rounded,
    '음식점·카페': Icons.restaurant_outlined,
    '편의점·마트': Icons.storefront_outlined,
    '물류·배송': Icons.local_shipping_outlined,
    '제조·공장': Icons.factory_outlined,
    '반도체·전자생산': Icons.memory_outlined,
    '건설·현장': Icons.construction_outlined,
    '사무·행정': Icons.business_center_outlined,
    '청소·시설관리': Icons.cleaning_services_outlined,
    '서비스·판매': Icons.shopping_bag_outlined,
    '이벤트·행사': Icons.event_outlined,
    'IT·개발': Icons.code_rounded,
    '교육·강의': Icons.school_outlined,
    '의료·복지': Icons.medical_services_outlined,
    '농·축산': Icons.agriculture_outlined,
    '기타': Icons.more_horiz_rounded,
    '제조': Icons.factory_outlined,
    '물류': Icons.local_shipping_outlined,
    '서비스': Icons.storefront_outlined,
    '건설': Icons.construction_outlined,
    '사무': Icons.business_center_outlined,
    '청소': Icons.cleaning_services_outlined,
  };

  Widget _buildCategoryChipInSheet({
    required String label,
    required String value,
    required String groupValue,
    required ValueChanged<String> onChanged,
  }) {
    final selected = groupValue == value;
    final icon = _categoryIcons[label] ?? Icons.push_pin_outlined;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.bgCard,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: selected ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPayChipInSheet({
    required String label,
    required String value,
    required String groupValue,
    required ValueChanged<String> onChanged,
  }) {
    final selected = groupValue == value;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.bgCard,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
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
    final parts = raw.split(_reWhitespace).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return raw;
    if (parts.first.endsWith('도')) parts.removeAt(0);
    if (parts.isEmpty) return raw;
    return parts.join(' ');
  }

  String? _buildAiSummary(Job job) {
    final score = job.matchScore;
    final reasons = job.matchReasons;
    if ((score == null || score < 0.6) && reasons.isEmpty) return null;

    // 명사구로 이어붙인다. 이전에는 '~고' + '잘 맞아요'를 조합해서
    // '의미유사'가 섞이면 "업무가 잘 맞아요 시급이 높고 잘 맞아요"처럼 문장이 깨졌다.
    final parts = <String>[];
    for (final r in reasons.take(2)) {
      switch (r) {
        case '가까움':
          parts.add('가까움');
          break;
        case '시간대겹침':
          parts.add('시간대 맞음');
          break;
        case '시급상위':
          parts.add('시급 높음');
          break;
        case '당일지급':
          parts.add('당일지급');
          break;
        case '완료이력좋음':
          parts.add('이력 좋음');
          break;
        case '의미유사':
          parts.add('업무 적합');
          break;
      }
    }

    // 점수는 높을 때만 노출. 52% 같은 낮은 숫자를 그대로 보여주면
    // 추천이 아니라 "안 맞는다"는 신호로 읽혀 신뢰를 깎는다.
    final pct =
        (score != null && score >= 0.7) ? ' ${(score * 100).round()}%' : '';
    final reasonText = parts.isEmpty ? '잘 맞는 공고예요' : parts.join(' · ');
    return 'AI 추천$pct · $reasonText';
  }

  /// 지원 완료 안내 + 되돌리기.
  /// 목록에서 한 번 누르면 바로 지원되므로, 잘못 눌렀을 때 빠져나갈 길이 필요하다
  /// (지원 후 취소는 활동점수 페널티로 이어진다).
  void _showApplySnack(
    String message, {
    required int jobId,
    required int workerId,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          action: SnackBarAction(
            label: '실행취소',
            textColor: Colors.white,
            onPressed: () => _cancelApply(jobId: jobId, workerId: workerId),
          ),
        ),
      );
  }

  Future<void> _cancelApply({
    required int jobId,
    required int workerId,
  }) async {
    try {
      final resp = await AuthenticatedHttpClient.postJson(
        Uri.parse('$baseUrl/api/job/cancel'),
        body: {'jobId': jobId, 'workerId': workerId},
      );
      if (!mounted) return;

      if (resp.statusCode == 200) {
        setState(() => appliedJobIds.remove(jobId));
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('지원을 취소했습니다.')));
      } else {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('지원 취소에 실패했어요. 내 활동에서 취소해 주세요.')),
          );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('네트워크 오류로 취소하지 못했어요.')));
    }
  }

  // 공고 상세와 동일한 지원 및 채팅방 생성 흐름
  Future<void> _applyDirectly(Job job) async {
    final jobIdInt = int.tryParse(job.id.toString());
    if (jobIdInt == null) return;

    final prefs = await SharedPreferences.getInstance();
    final workerId = prefs.getInt('userId');
    final clientId = job.clientId;

    if (workerId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('로그인이 필요해요.')));
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
      final resp = await AuthenticatedHttpClient.postJson(
        Uri.parse('$baseUrl/api/job/apply'),
        body: {'workerId': workerId, 'jobId': jobIdInt},
      );
      if (!mounted) return;

      if (resp.statusCode == 200) {
        setState(() => appliedJobIds.add(jobIdInt));
        LogService.instance.logEvent(
          eventType: LogService.apply,
          jobId: jobIdInt,
        );

        // 채팅방 생성
        final roomId = await startChatRoom(
          workerId,
          jobIdInt.toString(),
          clientId,
        );
        if (!mounted) return;

        if (roomId != null) {
          // 이동 안내 다이얼로그
          final goToChat = await _showChatMoveNoticeDialog(job);
          if (!mounted) return;

          if (goToChat) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder:
                    (_) => ChatRoomScreen(
                      chatRoomId: roomId,
                      jobInfo: {
                        'title': job.title,
                        'pay': job.pay,
                        'posted_at': '',
                        'publish_at':
                            job.publishAt?.toUtc().toIso8601String() ?? '',
                        'created_at':
                            job.createdAt?.toUtc().toIso8601String() ?? '',
                        'client_id': clientId,
                        'worker_id': workerId,
                        'client_company_name': job.company ?? '기업',
                        'client_thumbnail_url': '',
                      },
                    ),
              ),
            );
          } else {
            // 나중에 보기 → 목록에 남으므로 되돌릴 기회를 준다
            _showApplySnack(
              '지원이 완료되었습니다. 채팅 탭에서 대화를 이어가세요.',
              jobId: jobIdInt,
              workerId: workerId,
            );
          }
        } else {
          // 채팅방 생성 실패 — 지원은 됐으니 안내 + 되돌리기
          _showApplySnack(
            '지원이 완료되었습니다. 담당자 연락을 기다려주세요.',
            jobId: jobIdInt,
            workerId: workerId,
          );
        }
      } else if (resp.statusCode == 409) {
        if (!mounted) return;
        setState(() => appliedJobIds.add(jobIdInt));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('이미 지원한 공고예요.')));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('네트워크 오류가 발생했어요.')));
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
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(AppRadius.xl),
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
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        color: AppColors.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        '지원이 완료되었습니다',
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
                  '이 공고에 대한 채팅방이 열렸어요.\n사장님과 바로 대화하면서 급여, 근무 조건,\n위치 등을 한 번 더 확인해보는 걸 추천해요.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                // 취소 경로를 여기서 알려준다. 이 시트를 지나면 목록의
                // 실행취소 스낵바가 안 뜨고, 취소 방법이 어디에도 안내되지 않았다.
                const Text(
                  '잘못 지원했다면 [내 활동]에서 취소할 수 있어요.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      SizedBox(width: 6),
                      Text(
                        '지원 후 채팅에서 근무 조건을 확인할 수 있습니다',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
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
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.full),
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text(
                          '나중에 보기',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.full),
                          ),
                          elevation: 0,
                        ),
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text(
                          '채팅방으로 이동',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
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
        backgroundColor: AppColors.bgPage,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(88),
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary, AppColors.primaryDark],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              const Text(
                                '알바일주',
                                style: TextStyle(
                                  fontFamily: 'Jalnan2TTF',
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.22),
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.xs,
                                  ),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.50),
                                  ),
                                ),
                                child: const Text(
                                  '알바생',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isLoading
                                ? '공고 탐색 중...'
                                : '내 근처 단기 알바 $nearbyCount개',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.white.withValues(alpha: 0.80),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 오늘 가능 토글
                    GestureDetector(
                      onTap: () {
                        setState(() => isAvailableToday = !isAvailableToday);
                        setAvailableToday(isAvailableToday);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color:
                              isAvailableToday
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(AppRadius.full),
                          border: Border.all(
                            color:
                                isAvailableToday
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color:
                                    isAvailableToday
                                        ? AppColors.success
                                        : Colors.white.withValues(alpha: 0.70),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '오늘 가능',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color:
                                    isAvailableToday
                                        ? AppColors.success
                                        : Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
              const SliverToBoxAdapter(
                child: AdBannerWidget(placement: 'app_home_worker'),
              ),
              // AI 추천 스트립은 공고 리스트 중간(4번째 뒤)으로 이동 — 상단은 공고가 주인공
              // 노무상담 진입점은 마이페이지 > 고객센터로 이동
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildDistanceSlider(),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              // ── 파트너 채용공고 (제휴) ────────────────────────────
              // '전체 공고' 헤더 위에 둔다. 헤더 아래면 카운트(N개)에 포함된
              // 일반 공고로 오인된다.
              if (!_partnerCardHidden)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  sliver: SliverToBoxAdapter(
                    child: _buildPartnerRecruitCard(
                      PartnerRecruitPost.wonderLotte,
                    ),
                  ),
                ),
              // ── 적용 중인 필터 ───────────────────────────────────
              // 필터를 걸어둔 걸 잊으면 "공고가 없다"로 오해한다.
              // 화면에 보이고, 여기서 바로 뗄 수 있어야 한다.
              if (_activeFilterChips.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  sliver: SliverToBoxAdapter(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _activeFilterChips,
                    ),
                  ),
                ),
              // ── 섹션 헤더 ─────────────────────────────────────────
              if (!isLoading && filteredJobs.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        const Text(
                          '전체 공고',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 카운트는 액션이 아니므로 중립 톤 (파랑은 CTA 전용)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.bgMuted,
                            borderRadius: BorderRadius.circular(AppRadius.full),
                          ),
                          child: Text(
                            '${filteredJobs.length}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        const Spacer(),
                        // 정렬 기준 — 지금 무슨 순서로 보고 있는지 화면에 없으면
                        // "왜 먼 공고가 위에 있지?"가 된다. 탭하면 필터 시트.
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _openFilterSheet,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  sortType,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 16,
                                  color: AppColors.textSecondary,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // 뷰 전환 (컴팩트/일반)
                        GestureDetector(
                          onTap:
                              () => setState(() => compactView = !compactView),
                          child: Icon(
                            compactView
                                ? Icons.view_agenda_outlined
                                : Icons.view_list_rounded,
                            size: 20,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              // ── 파트너 채용공고 (제휴) — 목록 최상단 고정 ──────────
              if (isLoading)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: _buildSkeletonList(),
                )
              else if (filteredJobs.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyJobsView(),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: Builder(
                    builder: (_) {
                      final visibleCount =
                          (_itemsToShow < filteredJobs.length)
                              ? _itemsToShow
                              : filteredJobs.length;
                      // AI 추천 스트립을 4번째 공고 뒤에 끼워넣는다 (상단 다이어트).
                      // 공고가 4개 미만이면 삽입하지 않는다.
                      final stripAt = visibleCount > _aiStripAfter ? _aiStripAfter : -1;
                      return SliverList.builder(
                        itemCount: visibleCount + (stripAt >= 0 ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (stripAt >= 0 && index == stripAt) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: _AiRecommendStrip(
                                onJobTap:
                                    (job) => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => JobDetailScreen(job: job),
                                      ),
                                    ),
                              ),
                            );
                          }
                          final jobIndex =
                              (stripAt >= 0 && index > stripAt) ? index - 1 : index;
                          final job = filteredJobs[jobIndex];
                          return compactView
                              ? GestureDetector(
                                onTap: () => _openJobDetail(job),
                                child: _buildCompactJobCard(job),
                              )
                              : _buildJobCard(job);
                        },
                      );
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

  /// 파트너 채용공고 카드 (제휴 광고). 일반 공고 카드와 헷갈리지 않게
  /// '광고' 표기 + 파란 테두리로 구분한다.
  Widget _buildPartnerRecruitCard(PartnerRecruitPost post) {
    return GestureDetector(
      onTap:
          () => Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (_) => PartnerRecruitDetailScreen(
                    post: post,
                    placement: 'app_home_worker',
                  ),
            ),
          ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.primaryMid),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.bgMuted,
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                        ),
                        child: const Text(
                          '광고',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        '파트너 채용',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      const Spacer(),
                      // 닫기 — 7일간 숨김
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _dismissPartnerCard,
                        child: const Padding(
                          padding: EdgeInsets.only(left: 8, bottom: 4),
                          child: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    post.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    post.summary.map((e) => e.value).take(3).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (post.benefits.items.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      '알바일주 특별 혜택 · ${post.benefits.items.first.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGenderHintCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.warningBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.info_outline, size: 16, color: AppColors.warning),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '프로필에서 성별을 설정하면 더 잘 맞는 공고를 추천해 드려요.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.warningDark,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          GestureDetector(
            onTap: _dismissGenderHint,
            child: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.close, size: 16, color: AppColors.textTertiary),
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
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                boxShadow: AppShadows.card,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _shimmerBox(80, 11),
                        const SizedBox(height: 10),
                        _shimmerBox(double.infinity, 16),
                        const SizedBox(height: 6),
                        _shimmerBox(160, 13),
                        const SizedBox(height: 14),
                        _shimmerBox(110, 22),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            _shimmerBox(36, 36, radius: 10),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _shimmerBox(
                                double.infinity,
                                36,
                                radius: 10,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              flex: 2,
                              child: _shimmerBox(
                                double.infinity,
                                36,
                                radius: 10,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  _shimmerBox(72, 72, radius: 12),
                ],
              ),
            );
          },
        ),
        childCount: 5,
      ),
    );
  }

  Widget _shimmerBox(double width, double height, {double radius = 6}) {
    // 흐르는 shimmer 그라디언트
    final shimmerValue = _shimmerCtrl.value;
    return Container(
      width: width == double.infinity ? null : width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          colors: const [
            Color(0xFFEEEEEE),
            Color(0xFFF5F5F5),
            Color(0xFFEEEEEE),
          ],
          stops: [
            (shimmerValue - 0.3).clamp(0.0, 1.0),
            shimmerValue.clamp(0.0, 1.0),
            (shimmerValue + 0.3).clamp(0.0, 1.0),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
    );
  }

  Widget _buildEmptyJobsView() {
    // 원인별 빈 상태: 검색어 때문인지, 주변에 공고가 없는 건지 구분해서 처방
    final hasQuery = searchQuery.trim().isNotEmpty;

    // 활성 구직자의 86%가 5km 내 공고 0개를 본다(로드맵 실측).
    // 앱에서 가장 많이 노출되는 화면인데 지금까지 계측이 없었다.
    // build 중이므로 프레임 이후에 보낸다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScreenAnalyticsService.instance.logEvent(
        'worker_empty_jobs_shown',
        params: {'cause': hasQuery ? 'search' : 'no_nearby_jobs'},
      );
    });

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: const BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(
                  Icons.search_off_rounded,
                  size: 38,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              hasQuery
                  ? "'${searchQuery.trim()}' 검색 결과가 없어요"
                  : '이 근처엔 아직 공고가 없어요',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              hasQuery
                  ? '검색어를 바꾸거나 지우면\n주변 공고를 다시 볼 수 있어요.'
                  : '거리 범위를 조금 늘리거나,\n위치 권한을 켜면 더 많은 공고를 찾을 수 있어요.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed:
                    hasQuery
                        ? () {
                          _searchController.clear();
                          setState(() => searchQuery = '');
                          _applyFiltersThrottled();
                        }
                        : () async => _init(),
                icon: Icon(
                  hasQuery ? Icons.backspace_outlined : Icons.refresh_rounded,
                  size: 18,
                ),
                label: Text(
                  hasQuery ? '검색어 지우기' : '내 주변 다시 찾기',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
              ),
            ),
            if (!hasQuery) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: () async => Geolocator.openAppSettings(),
                  icon: const Icon(
                    Icons.settings_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  label: const Text(
                    '위치 권한 설정',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                      color: AppColors.primary,
                      width: 1.2,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.card,
        border: Border.all(color: AppColors.borderSub),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (value) {
          searchQuery = value;
          _runDebounced(_applyFiltersThrottled);
        },
        decoration: InputDecoration(
          hintText: '공고 제목, 업종, 지역으로 검색',
          hintStyle: const TextStyle(
            fontSize: 14,
            color: AppColors.textTertiary,
            fontWeight: FontWeight.w400,
          ),
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 14, right: 8),
            child: Icon(
              Icons.search_rounded,
              size: 20,
              color: AppColors.textTertiary,
            ),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 0,
            minHeight: 0,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
          isDense: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
        style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
      ),
    );
  }

  // AI 자연어 검색 바텀시트
  void _showAiSearchSheet() {
    final ctrl = TextEditingController();
    bool searching = false;
    List<Job> results = [];
    String? errorMsg;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setS) => DraggableScrollableSheet(
                  initialChildSize: 0.85,
                  maxChildSize: 0.95,
                  minChildSize: 0.5,
                  builder:
                      (_, scrollCtrl) => Container(
                        decoration: const BoxDecoration(
                          color: AppColors.bgCard,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(AppRadius.xl),
                          ),
                        ),
                        child: Column(
                          children: [
                            // 핸들
                            Container(
                              margin: const EdgeInsets.only(top: 10, bottom: 6),
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: AppColors.border,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.full,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.search_rounded,
                                        color: AppColors.primary,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 6),
                                      const Text(
                                        'AI 자연어 검색',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const Spacer(),
                                      IconButton(
                                        icon: const Icon(Icons.close, size: 20),
                                        onPressed: () => Navigator.pop(ctx),
                                      ),
                                    ],
                                  ),
                                  const Text(
                                    '말하듯이 검색하세요',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  // 예시 태그
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children:
                                        [
                                              '내일 강남 오전 알바',
                                              '주말 시급 15000원 이상',
                                              '50대도 할 수 있는 장기',
                                              '오늘 당일치기 물류',
                                            ]
                                            .map(
                                              (ex) => GestureDetector(
                                                onTap: () {
                                                  ctrl.text = ex;
                                                },
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 5,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        AppColors.primaryLight,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          AppRadius.full,
                                                        ),
                                                    border: Border.all(
                                                      color:
                                                          AppColors.primaryMid,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    ex,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: AppColors.primary,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            )
                                            .toList(),
                                  ),
                                  const SizedBox(height: 10),
                                  // 입력창
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: ctrl,
                                          autofocus: true,
                                          decoration: InputDecoration(
                                            hintText: '예) 내일 오전 강남 카페 알바',
                                            hintStyle: const TextStyle(
                                              fontSize: 14,
                                              color: AppColors.textTertiary,
                                            ),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    AppRadius.md,
                                                  ),
                                              borderSide: const BorderSide(
                                                color: AppColors.border,
                                              ),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    AppRadius.md,
                                                  ),
                                              borderSide: const BorderSide(
                                                color: AppColors.primary,
                                              ),
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 14,
                                                  vertical: 12,
                                                ),
                                          ),
                                          style: const TextStyle(fontSize: 14),
                                          onSubmitted: (_) async {
                                            if (ctrl.text.trim().isEmpty ||
                                                searching) {
                                              return;
                                            }
                                            setS(() {
                                              searching = true;
                                              errorMsg = null;
                                            });
                                            try {
                                              final r =
                                                  await AiLaborService.naturalSearch(
                                                    query: ctrl.text.trim(),
                                                    lat:
                                                        currentLatitude != 0
                                                            ? currentLatitude
                                                            : null,
                                                    lng:
                                                        currentLongitude != 0
                                                            ? currentLongitude
                                                            : null,
                                                  );
                                              setS(() {
                                                results = r.jobs;
                                                searching = false;
                                              });
                                            } catch (e) {
                                              setS(() {
                                                errorMsg = e.toString();
                                                searching = false;
                                              });
                                            }
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      ElevatedButton(
                                        onPressed:
                                            searching
                                                ? null
                                                : () async {
                                                  if (ctrl.text
                                                      .trim()
                                                      .isEmpty) {
                                                    return;
                                                  }
                                                  setS(() {
                                                    searching = true;
                                                    errorMsg = null;
                                                  });
                                                  try {
                                                    final r = await AiLaborService.naturalSearch(
                                                      query: ctrl.text.trim(),
                                                      lat:
                                                          currentLatitude != 0
                                                              ? currentLatitude
                                                              : null,
                                                      lng:
                                                          currentLongitude != 0
                                                              ? currentLongitude
                                                              : null,
                                                    );
                                                    setS(() {
                                                      results = r.jobs;
                                                      searching = false;
                                                    });
                                                  } catch (e) {
                                                    setS(() {
                                                      errorMsg = e.toString();
                                                      searching = false;
                                                    });
                                                  }
                                                },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.primary,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                        ),
                                        child:
                                            searching
                                                ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                        color: Colors.white,
                                                        strokeWidth: 2,
                                                      ),
                                                )
                                                : const Text(
                                                  '검색',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 20),
                            // 결과
                            Expanded(
                              child:
                                  errorMsg != null
                                      ? Center(
                                        child: Text(
                                          errorMsg!,
                                          style: const TextStyle(
                                            color: Colors.red,
                                          ),
                                        ),
                                      )
                                      : results.isEmpty
                                      ? const Center(
                                        child: Text(
                                          '위에서 자연어로 검색해보세요.',
                                          style: TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 14,
                                          ),
                                        ),
                                      )
                                      : ListView.builder(
                                        controller: scrollCtrl,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                        ),
                                        itemCount: results.length,
                                        itemBuilder: (_, i) {
                                          final job = results[i];
                                          return ListTile(
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  vertical: 4,
                                                ),
                                            title: Text(
                                              job.title,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            subtitle: Text(
                                              '${job.locationCity.isNotEmpty ? job.locationCity : job.location} · ${formatJobPay(job.pay, job.payType, includeType: true)}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                            trailing:
                                                job.jobType == 'long'
                                                    ? Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                            vertical: 3,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: const Color(
                                                          0xFF7C3AED,
                                                        ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              20,
                                                            ),
                                                      ),
                                                      child: const Text(
                                                        '장기',
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                    )
                                                    : null,
                                            onTap: () {
                                              Navigator.pop(ctx);
                                              _openJobDetail(job);
                                            },
                                          );
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

  String _distanceHint(double km) {
    if (km <= 2.0) return '집 앞 알바 거리 (도보 10분 내외)';
    if (km <= 5.0) return '동네 생활권 거리 (도보 30분 / 차로 10분)';
    if (km <= 10.0) return '퇴근 후도 무난한 거리 (차로 15~20분)';
    if (km <= 20.0) return '주말 알바 당일치기 거리 (차로 30분대)';
    return '원거리 이동이 필요한 범위 (차로 1시간 내외)';
  }

  Widget _buildDistanceSlider() {
    if (!_distanceExpanded) {
      return InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => setState(() => _distanceExpanded = true),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.tune_rounded,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '거리 설정',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                '${selectedDistance.toStringAsFixed(0)}km',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '거리 설정',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            TextButton(
              onPressed: () => setState(() => _distanceExpanded = false),
              child: const Text('접기'),
            ),
            Text(
              '${selectedDistance.toStringAsFixed(0)}km',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        Slider(
          min: 1,
          max: 30,
          divisions: 29,
          value: selectedDistance,
          onChanged: (value) => setState(() => selectedDistance = value),
          onChangeEnd: (value) async {
            if (currentLatitude == 0.0 || currentLongitude == 0.0) {
              await _init();
            }
            _applyFiltersThrottled();
          },
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.place_rounded,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _distanceHint(selectedDistance),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildJobCard(Job job) {
    final formattedPay = formatJobPay(job.pay, job.payType);
    final isNegotiablePay = isNegotiablePayType(job.payType);
    final jobIdInt = int.tryParse(job.id.toString());
    final isApplied = appliedJobIds.contains(jobIdInt);
    final isApplyingNow = _quickApplyingJobId == jobIdInt;

    final distanceKm = _distanceKmFromUser(job);
    final baseLocation = _trimProvince(job.location);
    final String? distanceText =
        distanceKm == null
            ? null
            : (distanceKm < 10
                ? distanceKm.toStringAsFixed(1)
                : distanceKm.toStringAsFixed(0));
    final String locationLine =
        distanceText == null
            ? baseLocation
            : '$baseLocation · ${distanceText}km';

    final nowUtc = DateTime.now().toUtc();
    final bool isPinned =
        job.pinnedUntil != null && job.pinnedUntil!.isAfter(nowUtc);

    final bool isUrgent =
        job.endDate != null &&
        !job.endDate!.isBefore(nowUtc) &&
        job.endDate!.difference(nowUtc).inDays <= 2;

    // 뱃지 색은 두 갈래만 쓴다.
    //   주황 = 시간이 급함 (긴급·마감임박)
    //   초록 = 돈·신뢰 보증 (당일지급·안심기업)
    //   그 외(장기)는 중립 — 예전엔 5색이 한 화면에서 경쟁했다.
    // '신규'는 뺐다: 24시간 이내면 붙어서 거의 모든 공고에 달렸고,
    // 다 붙은 뱃지는 안 붙은 것과 같다.
    final List<Widget> opBadges = [];
    if (job.isUrgent) {
      opBadges.add(const JobSignalBadge(label: '⚡ 긴급', signal: JobSignal.time));
    }
    if (isUrgent) {
      opBadges.add(const JobSignalBadge(label: '마감임박', signal: JobSignal.time));
    }
    // 급여 형태(일급/주급/월급)는 가격 옆 칩으로만 표시 — 상단 뱃지 중복 제거
    if (job.isSameDayPay == true) {
      opBadges.add(const JobSignalBadge(label: '당일지급', signal: JobSignal.money));
    } else if (job.isCertifiedCompany == true) {
      opBadges.add(const JobSignalBadge(label: '안심기업', signal: JobSignal.trust));
    }
    if (job.jobType == 'long') {
      opBadges.add(const JobSignalBadge(label: '장기'));
    }

    final displayBadges = opBadges.take(2).toList();
    final aiSummary = _buildAiSummary(job);
    // 칩 줄(거리·당일지급·긴급·안심기업·매칭이유)은 제거했다 —
    // 전부 상단 위치줄·뱃지·AI 요약에 이미 있는 내용이라 카드만 길어졌다.

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.card,
      ),
      child: Stack(
        children: [
          // 핀 고정 상단 바
          if (isPinned)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 3,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(AppRadius.lg),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: GestureDetector(
              onTap: () => _openJobDetail(job),
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 위치 + 배지 행 ──────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              size: 12,
                              color: AppColors.textTertiary,
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                locationLine,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textTertiary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (displayBadges.isNotEmpty)
                        Row(
                          children:
                              displayBadges
                                  .map(
                                    (b) => Padding(
                                      padding: const EdgeInsets.only(left: 4),
                                      child: b,
                                    ),
                                  )
                                  .toList(),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // ── 제목 + 썸네일 ────────────────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              job.title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                                height: 1.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (job.imageUrls.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          child: Builder(
                            builder: (context) {
                              final raw = job.imageUrls.first;
                              final url =
                                  raw.startsWith('http') ? raw : '$baseUrl$raw';
                              return Image.network(
                                url,
                                width: 72,
                                height: 72,
                                fit: BoxFit.cover,
                                errorBuilder:
                                    (_, __, ___) => const SizedBox.shrink(),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),

                  // ── 급여 (히어로 숫자) ──────────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      // '협의'는 숫자가 아니라 히어로 대접을 하지 않는다.
                      // 제목 바로 아래에 크고 굵게 놓으면 제목 2행처럼 읽힌다.
                      Text(
                        formattedPay,
                        style: TextStyle(
                          fontSize: isNegotiablePay ? 15 : 21,
                          fontWeight:
                              isNegotiablePay
                                  ? FontWeight.w600
                                  : FontWeight.w800,
                          color:
                              isNegotiablePay
                                  ? AppColors.textSecondary
                                  : AppColors.textPrimary,
                          height: 1.1,
                        ),
                      ),
                      if (job.payType.isNotEmpty && !isNegotiablePay) ...[
                        const SizedBox(width: 6),
                        // 급여 형태는 정보지 액션이 아니다 — 파랑은 지원하기 버튼 전용
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.bgMuted,
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                          ),
                          child: Text(
                            job.payType,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                  // ── 근무 일정 ────────────────────────────────────
                  // 알바생 판단 순서(얼마 → 언제 → 어디)에 맞춰 급여 아래에 둔다.
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    children: [
                      if (job.startDate != null && job.endDate != null)
                        _metaChip(
                          Icons.calendar_today_outlined,
                          '${_formatDate(job.startDate!)} ~ ${_formatDate(job.endDate!)}',
                        ),
                      // 시간 미입력 공고는 "~"만 노출되던 문제 — 값 있을 때만 표시
                      if (job.workingHours.replaceAll('~', '').trim().isNotEmpty)
                        _metaChip(Icons.schedule_outlined, job.workingHours),
                    ],
                  ),

                  // ── 매칭 요약 ────────────────────────────────────
                  // 배경 박스를 없앴다 — 파란 덩어리가 카드마다 셋(급여칩·AI박스·버튼)
                  // 겹쳐 시선을 분산시켰다. 아이콘 하나로 출처만 남긴다.
                  if (aiSummary != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.recommend_outlined,
                          size: 12,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            aiSummary,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 12),

                  // ── 액션 버튼 행 ────────────────────────────────
                  Row(
                    children: [
                      // 북마크
                      _BookmarkButton(
                        isBookmarked: bookmarkedJobIds.contains(
                          job.id.toString(),
                        ),
                        onTap: () => _toggleBookmark(job.id.toString()),
                      ),
                      const SizedBox(width: 8),
                      // '자세히' 버튼은 없앴다 — 카드 전체 탭이 이미 상세로 간다.
                      // 지원하기
                      Expanded(
                        child: SizedBox(
                          height: 38,
                          child: ElevatedButton(
                            onPressed:
                                isApplied || isApplyingNow
                                    ? null
                                    : () => _applyDirectly(job),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  isApplied
                                      ? AppColors.bgMuted
                                      : AppColors.primary,
                              disabledBackgroundColor: AppColors.bgMuted,
                              elevation: 0,
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.sm,
                                ),
                              ),
                            ),
                            child:
                                isApplyingNow
                                    ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                    : Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          isApplied
                                              ? Icons.check_rounded
                                              : Icons.bolt_rounded,
                                          size: 15,
                                          color:
                                              isApplied
                                                  ? AppColors.textTertiary
                                                  : Colors.white,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          isApplied ? '지원 완료' : '지원하기',
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w700,
                                            color:
                                                isApplied
                                                    ? AppColors.textTertiary
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
          ),
        ],
      ),
    );
  }

  // 메타 칩 (아이콘 + 텍스트)
  Widget _metaChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: AppColors.textTertiary),
        const SizedBox(width: 3),
        Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textTertiary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildTopControlRow(int nearbyCount) {
    return Column(
      children: [
        // 1행: 검색창
        _buildSearchField(),
        const SizedBox(height: 8),
        // 2행: AI검색 | 위치 | 필터
        Row(
          children: [
            // AI 자연어 검색 (톤 다운 — 채운 파랑은 지원하기 CTA 전용)
            Material(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                onTap: _showAiSearchSheet,
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.search_rounded,
                        color: AppColors.primary,
                        size: 14,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'AI 검색',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 위치
            Expanded(
              child: SizedBox(
                height: 36,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await _init();
                    _applyFiltersThrottled();
                  },
                  icon: const Icon(Icons.my_location_rounded, size: 15),
                  label: const Text(
                    '위치',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.border),
                    foregroundColor: AppColors.textSecondary,
                    backgroundColor: AppColors.bgCard,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 필터
            Expanded(
              child: SizedBox(
                height: 36,
                child: OutlinedButton.icon(
                  onPressed: _openFilterSheet,
                  icon: const Icon(Icons.tune_rounded, size: 15),
                  label: const Text(
                    '필터',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.border),
                    foregroundColor: AppColors.textSecondary,
                    backgroundColor: AppColors.bgCard,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCompactJobCard(Job job) {
    final formattedPay = formatJobPay(job.pay, job.payType);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              job.title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14.5,
                color: AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 13,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(
                    job.location,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.payments_outlined,
                  size: 13,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(
                    formattedPay,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(
              bookmarkedJobIds.contains(job.id)
                  ? Icons.bookmark
                  : Icons.bookmark_border,
              color:
                  bookmarkedJobIds.contains(job.id)
                      ? AppColors.warning
                      : AppColors.textTertiary,
            ),
            onPressed: () => _toggleBookmark(job.id),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final d = date.toLocal();
    return '${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
  }

}

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
            color:
                isBookmarked
                    ? AppColors.badgeNew.withValues(alpha: 0.35)
                    : AppColors.border,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Icon(
          isBookmarked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          size: 18,
          color: isBookmarked ? AppColors.badgeNew : AppColors.textTertiary,
        ),
      ),
    );
  }
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
      if (workerId == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final resp = await AuthenticatedHttpClient.get(
        Uri.parse('$baseUrl/api/rank/jobs?workerId=$workerId&limit=8'),
      ).timeout(const Duration(seconds: 6));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final List raw =
            data is List ? data : (data['data'] ?? data['jobs'] ?? []);
        setState(() {
          _items =
              raw
                  .take(6)
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
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
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(color: AppColors.primaryMid),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.recommend_outlined,
                      size: 12,
                      color: AppColors.primary,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'AI 맞춤 추천',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '조건을 반영한 추천 공고',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
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
              final city =
                  (it['location_city'] ?? it['location'] ?? '').toString();
              final payRaw = (it['pay'] ?? 0).toString().replaceAll(
                _reNonDigit,
                '',
              );
              final payInt = int.tryParse(payRaw) ?? 0;
              final payStr =
                  isNegotiablePayType((it['pay_type'] ?? '').toString())
                      ? '급여 협의'
                      : payInt > 0
                      ? '${NumberFormat('#,###').format(payInt)}원'
                      : '';
              final reasons =
                  (it['reasons'] is List)
                      ? (it['reasons'] as List)
                          .take(2)
                          .map((e) => e.toString())
                          .toList()
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
                    color: AppColors.bgCard,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppColors.border),
                    boxShadow: AppShadows.card,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                      const Spacer(),
                      if (payStr.isNotEmpty)
                        Text(
                          payStr,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      if (city.isNotEmpty)
                        Text(
                          city,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      if (reasons.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            reasons.first,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.textTertiary,
                            ),
                          ),
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
