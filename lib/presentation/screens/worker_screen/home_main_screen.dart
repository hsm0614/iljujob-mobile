import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/models/job.dart';
import '../../../data/services/job_service.dart';
import 'job_detail_screen.dart';
import 'recent_jobs_screen.dart';
import 'package:iljujob/config/constants.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:iljujob/data/services/log_service.dart';
import 'package:iljujob/data/services/screen_analytics_service.dart';
import 'package:iljujob/data/services/ai_labor_service.dart';
import 'package:iljujob/data/services/authenticated_http_client.dart';
import 'package:iljujob/config/app_theme.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'package:iljujob/widget/app_ui.dart';
import 'package:iljujob/widget/job_list_tile.dart';
import 'package:iljujob/widget/ad_banner_widget.dart';
import 'package:iljujob/data/services/ad_banner_service.dart';
import 'package:iljujob/utils/pay_display.dart';
import 'package:iljujob/data/models/partner_recruit_post.dart';
import 'package:iljujob/presentation/screens/worker_screen/partner_recruit_detail_screen.dart';
import 'package:iljujob/data/services/notificaion_service.dart';
import 'package:iljujob/main.dart'; // sendFcmTokenUnified
import 'package:iljujob/widget/push_permission.dart';
import 'home_nudges.dart';

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
  String searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  String selectedCategory = '전체';
  String sortType = '최신순';
  double currentLatitude = 0.0;
  double currentLongitude = 0.0;
  double selectedDistance = 30;
  int _itemsToShow = 10;
  bool isLoading = true;
  // 칩 줄의 '당일지급' 빠른 필터
  bool _onlySameDayPay = false;
  final ScrollController _scrollController = ScrollController();
  bool _loadingMore = false;
  bool isAvailableToday = false;
  String selectedPayType = 'all';
  int _jobsReqSeq = 0;
  bool _isLoadingJobs = false;
  bool _distanceExpanded = false;

  // 목록 보기 방식: 'near'(내 주변, 기본) · 'region'(지역) · 'nationwide'(전국).
  // 반경만 있을 땐 노출 중인 공고가 전국 17건인데(2026-09-21) 대전 구직자는 0건,
  // 부산은 2건만 봤다. 푸시·긴급호출은 계속 거리 기준이고 목록만 넓힌다.
  String _scope = 'near';
  String? _regionSido;
  String? _regionSigungu;
  static const _kScopeKey = 'job_list_scope';
  static const _kRegionSidoKey = 'job_list_region_sido';
  static const _kRegionSigunguKey = 'job_list_region_sigungu';
  bool get _isNearScope => _scope == 'near';

  // 검색창은 기본 접힘. 검색어가 있으면 목록 위 필터 칩으로 보인다.
  bool _searchExpanded = false;
  final FocusNode _searchFocus = FocusNode();

  bool _genderHintDismissed = false;
  static const _kGenderHintKey = 'gender_hint_dismissed';

  // 파트너 채용공고 카드: 닫으면 7일간 숨김 (광고 피로도 완화)
  bool _partnerCardHidden = false;

  /// 어드민 '광고 배너(제휴)'의 `app_partner_recruit` 행이 활성인지.
  /// 계약 종료·사고 시 앱 배포 없이 즉시 내리기 위한 스위치.
  /// 기본 false — 서버 확인 전이나 조회 실패 시엔 노출하지 않는다(안전한 기본값).
  bool _partnerAdActive = false;
  static const _kPartnerCardHiddenUntilKey = 'partner_card_hidden_until';
  static const _partnerCardHideDays = 7;


  // 근무지가 여러 곳이면 가장 가까운 곳까지의 거리. 필터가 '고양으로 통과'시킨
  // 공고에 대표좌표(수원) 거리를 표시하면 목록과 카드가 서로 다른 말을 한다.
  double? _distanceKmFromUser(Job job) {
    if (currentLatitude == 0.0 || currentLongitude == 0.0) return null;
    return job.distanceKmFrom(currentLatitude, currentLongitude);
  }

  @override
  void initState() {
    super.initState();
    ScreenAnalyticsService.instance.logScreenView('worker_home');
    // 알림 권한은 첫 공고 상세 뒤에 묻는다(widget/push_permission.dart).
    _loadGenderHintDismissed();
    _loadPartnerCardHidden();
    _loadPartnerAdActive();
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
      if (!_scrollController.hasClients) return;
      final pos = _scrollController.position;
      if (pos.pixels >= pos.maxScrollExtent - 200) {
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
    _searchFocus.dispose();
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

  /// 어드민 토글·노출기간을 서버에서 확인한다.
  /// `GET /api/banners?placement=`는 is_active=1 + start_at/end_at 범위만 돌려주므로
  /// 행이 하나라도 오면 활성, 비었으면 비활성이다.
  Future<void> _loadPartnerAdActive() async {
    final rows = await AdBannerService.instance.fetchBanners(
      'app_partner_recruit',
    );
    if (!mounted) return;
    setState(() => _partnerAdActive = rows.isNotEmpty);
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
    await prefs.setInt(
      _kPartnerCardHiddenUntilKey,
      until.millisecondsSinceEpoch,
    );
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

  // main.dart 의 sendFcmTokenUnified 로 위임 (iOS APNS 대기·응답 확인·재시도 포함)
  Future<void> retryFcmTokenSend() => sendFcmTokenUnified();

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    // 직접 고른 적이 없으면 기본은 '내 지역'(현재 위치의 시·구). 아래 위치 확인 뒤 정한다
    final savedScope = prefs.getString(_kScopeKey);
    _scope = savedScope ?? 'near';
    _regionSido = prefs.getString(_kRegionSidoKey);
    _regionSigungu = prefs.getString(_kRegionSigunguKey);
    if (_scope == 'region' && (_regionSido ?? '').isEmpty) _scope = 'near';
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
        if (savedScope == null) await _defaultToMyRegion(finalLat, finalLng);
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

  /// 현재 좌표 → 시·도/시·군·구 (서버 utils/geocode.js 의 sidoOf·sigunguOf 와 같은 규칙).
  /// 저장하지 않는다 — 다른 동네로 가면 다음 실행 때 그 동네가 기본이 된다.
  Future<void> _defaultToMyRegion(double lat, double lng) async {
    try {
      final marks = await placemarkFromCoordinates(lat, lng);
      if (marks.isEmpty) return;
      final m = marks.first;
      const sidoAliases = {
        '전남광주': '광주', '충청북': '충북', '충청남': '충남', '전라북': '전북',
        '전라남': '전남', '경상북': '경북', '경상남': '경남',
      };
      const sidos = ['서울', '부산', '대구', '인천', '광주', '대전', '울산', '세종',
        '경기', '강원', '충북', '충남', '전북', '전남', '경북', '경남', '제주'];
      final area = (m.administrativeArea ?? '').replaceAll(' ', '');
      String? sido;
      for (final e in sidoAliases.entries) {
        if (area.startsWith(e.key)) sido = e.value;
      }
      sido ??= sidos.where(area.startsWith).firstOrNull;
      if (sido == null) return;
      final sigungu =
          [m.subAdministrativeArea, m.locality, m.subLocality]
              .whereType<String>()
              .expand((t) => t.split(' '))
              .where(
                (t) =>
                    t.length >= 2 &&
                    RegExp(r'(시|군|구)$').hasMatch(t) &&
                    !t.startsWith(sido!),
              )
              .firstOrNull;
      if (!mounted) return;
      setState(() {
        _scope = 'region';
        _regionSido = sido;
        _regionSigungu = sigungu;
      });
    } catch (_) {}
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
      await AuthenticatedHttpClient.patchJson(
        Uri.parse('$baseUrl/api/worker/update-location'),
        body: {'userId': userId, 'lat': lat, 'lng': lng},
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
      final resp = await AuthenticatedHttpClient.postJson(
        url,
        body: {'worker_id': userId, 'job_id': jobId},
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
      // 토큰을 실어야 서버가 query 의 workerId 대신 본인 것만 돌려준다.
      final response = await AuthenticatedHttpClient.get(
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
        scope: _scope,
        sido: _regionSido,
        sigungu: _regionSigungu,
      );
      if (req != _jobsReqSeq || !mounted) return;

      final prefs = await SharedPreferences.getInstance();
      final workerId = prefs.getInt('userId');
      final userType = prefs.getString('userType');

      Map<String, Map<String, dynamic>> scoreMap = {};

      if (workerId != null && userType == 'worker') {
        try {
          final aiRes = await AuthenticatedHttpClient.get(
            Uri.parse(
              '$baseUrl/api/rank/jobs?workerId=$workerId&lat=$currentLatitude&lng=$currentLongitude&limit=100',
            ),
          ).timeout(const Duration(seconds: 6));

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
        if (isFutureScheduled(j)) continue;
        validJobs.add(j);
      }

      List<Job> filtered = validJobs;
      if (_isNearScope && currentLatitude != 0.0 && currentLongitude != 0.0) {
        // 근무지가 여러 곳인 공고는 하나만 반경 안이어도 통과한다.
        // 전국 공고·좌표 없는 공고도 여기서 버리지 않는다 — Job.withinRadiusKm이
        // 목록·필터 양쪽에서 같은 판단을 하도록 모아뒀다.
        filtered =
            validJobs
                .where(
                  (j) => j.withinRadiusKm(
                    currentLatitude,
                    currentLongitude,
                    selectedDistance,
                  ),
                )
                .toList();
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
    // 스크롤 리스너는 매 프레임 돈다. 가드가 없으면 하단 200px 안에 들어간
    // 순간부터 초당 수십 번 호출돼 홈 전체가 그만큼 리빌드되고,
    // _itemsToShow 도 10이 아니라 수백씩 뛴다. 한 프레임에 한 번만 허용한다.
    if (_loadingMore) return;
    if (_itemsToShow < filteredJobs.length) {
      _loadingMore = true;
      setState(() {
        _itemsToShow += 10;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadingMore = false);
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
          return !isFuture && notExpired;
        }).toList();

    if (_isNearScope && currentLatitude != 0.0 && currentLongitude != 0.0) {
      tempJobs =
          tempJobs
              .where(
                (job) => job.withinRadiusKm(
                  currentLatitude,
                  currentLongitude,
                  selectedDistance,
                ),
              )
              .toList();
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

    if (_onlySameDayPay) {
      tempJobs = tempJobs.where((job) => job.isSameDayPay == true).toList();
    }

    if (searchQuery.isNotEmpty) {
      tempJobs =
          tempJobs.where((job) {
            final q = searchQuery.trim();
            // 추가 근무지도 검색 대상. '고양'으로 찾는데 대표 주소가
            // 수원이라 안 나오면 다중 근무지 공고는 검색으로 못 만난다.
            return job.title.contains(q) ||
                job.location.contains(q) ||
                job.locationCity.contains(q) ||
                job.locations.any(
                  (l) =>
                      l.address.contains(q) ||
                      (l.locationCity?.contains(q) ?? false),
                ) ||
                job.category.contains(q) ||
                (job.description?.contains(q) ?? false);
          }).toList();
    }

    int cmpPinned(Job a, Job b) {
      // 상단 노출은 상품명이 아니라 실제 pinned_until 만 따른다.
      // 긴급호출도 24시간이 지나면 일반 정렬로 돌아가야 한다.
      final ap = isPinned(a), bp = isPinned(b);
      if (ap != bp) return bp ? 1 : -1;
      if (ap && bp) return b.pinnedUntil!.compareTo(a.pinnedUntil!);
      return 0;
    }

    switch (sortType) {
      case '거리순':
        // 좌표 없는 공고는 거리를 알 수 없으므로 항상 뒤로
        double distOf(Job j) =>
            j.distanceKmFrom(currentLatitude, currentLongitude) ??
            double.infinity;
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
                            tooltip: '닫기',
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

  String _trimProvince(String raw) {
    if (raw.isEmpty) return raw;
    final parts = raw.split(_reWhitespace).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return raw;
    if (parts.first.endsWith('도')) parts.removeAt(0);
    if (parts.isEmpty) return raw;
    return parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.bgPage,
        // 한 줄 앱바. 예전 88px 파란 그라데이션은 첫 화면 공고를 하나 밀어냈다.
        appBar: AppBar(
          backgroundColor: AppColors.bgCard,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          toolbarHeight: 52,
          titleSpacing: 20,
          // 급구처럼 제목 자리에 지금 보는 범위. 탭하면 범위 선택 시트
          title: _buildScopeTitle(),
          actions: [
            IconButton(
              tooltip: _searchExpanded ? '검색 닫기' : '검색',
              onPressed: _toggleSearch,
              icon: Icon(
                _searchExpanded ? Icons.close_rounded : Icons.search_rounded,
                color: AppColors.textPrimary,
              ),
            ),
            IconButton(
              tooltip: '최근 본 공고',
              onPressed:
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RecentJobsScreen()),
                  ),
              icon: const Icon(
                Icons.history_rounded,
                color: AppColors.textPrimary,
              ),
            ),
            IconButton(
              tooltip: '알림 설정',
              onPressed: () => Navigator.pushNamed(context, '/notifications'),
              icon: const Icon(
                Icons.notifications_none_rounded,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: SafeArea(
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: Container(
                  color: AppColors.bgCard,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: _buildTopControlRow(),
                ),
              ),
              // 공고 위에는 '사장님이 먼저 연락했어요' 같은 내 일 안내만 둔다.
              // 알림 꺼짐·성별 안내·배너·파트너 광고는 목록 3번째 공고 뒤 한 칸으로 (첫 공고를 위로)
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
                sliver: SliverToBoxAdapter(child: HomeNudges()),
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
              if (isLoading)
                _buildSkeletonList()
              else if (filteredJobs.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyJobsView(),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.zero,
                  sliver: Builder(
                    builder: (_) {
                      final visibleCount =
                          (_itemsToShow < filteredJobs.length)
                              ? _itemsToShow
                              : filteredJobs.length;
                      final slotAt = visibleCount < 3 ? visibleCount : 3;
                      return SliverList.builder(
                        itemCount: visibleCount + 1,
                        itemBuilder: (context, index) {
                          if (index == slotAt) return _buildFeedSlot();
                          final job =
                              filteredJobs[index > slotAt ? index - 1 : index];
                          return _buildJobCard(job);
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
    // 배너와 같은 3단 집계: 노출(50% 이상 보였을 때) → 카드 탭 → 지원하기
    return VisibilityDetector(
      key: Key('partner_card_${post.partnerCode}'),
      onVisibilityChanged: (info) {
        if (info.visibleFraction < 0.5) return;
        AdBannerService.instance.logPartnerImpression(
          post.partnerCode,
          placement: 'app_home_worker',
        );
      },
      child: GestureDetector(
        onTap: () {
          AdBannerService.instance.logPartnerClick(
            post.partnerCode,
            placement: 'app_home_worker',
          );
          Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (_) => PartnerRecruitDetailScreen(
                    post: post,
                    placement: 'app_home_worker',
                  ),
            ),
          );
        },
        // 일반 공고 줄과 같은 모양 + '광고' 표기 (급구식). 파란 테두리 카드는 시선을 뺏었다
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
          decoration: const BoxDecoration(
            color: AppColors.bgCard,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('파트너 채용 · 광고', style: AppTextStyles.jobMeta),
                        const Spacer(),
                        // 닫기 — 7일간 숨김. 16px 회색 X는 안 보이고 누르기도 어려웠다(2026-10 대표)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _dismissPartnerCard,
                          child: Padding(
                            // 보이는 알약보다 터치 영역을 넓게
                            padding: const EdgeInsets.fromLTRB(12, 4, 0, 4),
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(9, 4, 6, 4),
                              decoration: BoxDecoration(
                                color: AppColors.bgMuted,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.full,
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '닫기',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  SizedBox(width: 2),
                                  Icon(
                                    Icons.close_rounded,
                                    size: 15,
                                    color: AppColors.textSecondary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
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
                    // 요약(업종·경력·근무지)은 상세화면에 있다. 카드엔 누를 이유 한 줄만.
                    if (post.benefits.items.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        '재택근무 · ${post.benefits.items.first.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.jobMeta.copyWith(
                          color: AppColors.textSecondary,
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

  /// 로딩 자리표시 — JobListTile 과 같은 모양(풀폭 흰 줄 + 구분선, 급여 → 제목 → 메타).
  Widget _buildSkeletonList() {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (_, __) => AnimatedBuilder(
          animation: _shimmerCtrl,
          builder: (_, __) {
            return Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              decoration: const BoxDecoration(
                color: AppColors.bgCard,
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _shimmerBox(120, 22),
                  const SizedBox(height: 10),
                  _shimmerBox(double.infinity, 15),
                  const SizedBox(height: 8),
                  _shimmerBox(170, 12),
                  const SizedBox(height: 6),
                  _shimmerBox(130, 12),
                ],
              ),
            );
          },
        ),
        childCount: 6,
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
            AppColors.bgMuted,
            AppColors.bgPage,
            AppColors.bgMuted,
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

  /// 빈 화면에서 유일하게 재방문 이유를 만드는 액션.
  /// 새 테이블 없이 기존 notification_settings(match_alert·push_consent)를 켠다.
  Future<void> _enableJobAlerts() async {
    ScreenAnalyticsService.instance.logEvent('worker_empty_alert_optin');
    final ok = await NotificationService.updateSettings({
      'matchAlert': true,
      'pushConsent': true,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? '새 공고가 올라오면 알려드릴게요.' : '알림 설정에 실패했어요. 잠시 후 다시 시도해주세요.',
        ),
      ),
    );
  }

  Widget _buildEmptyJobsView() {
    // 원인별 빈 상태: 검색어 때문인지, 주변에 공고가 없는 건지 구분해서 처방
    final hasQuery = searchQuery.trim().isNotEmpty;

    // 위치 권한이 없으면 좌표가 0으로 떨어진다. 권한이 멀쩡한 사람에게
    // "위치 권한 설정" 버튼을 계속 보여주고 있었다 — 원인이 아닌 경우가 대부분이다.
    final noLocation = currentLatitude == 0.0 && currentLongitude == 0.0;

    // 30일간 283명에게 5,090회(인당 18회) 노출됐다.
    // build 중이므로 프레임 이후에 보낸다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScreenAnalyticsService.instance.logEvent(
        'worker_empty_jobs_shown',
        params: {
          'cause': hasQuery ? 'search' : 'no_nearby_jobs',
          'no_location': noLocation,
        },
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
                  : _scope == 'region'
                  ? '이 지역에는 지금 노출 중인 공고가 없어요.\n다른 지역이나 전국 공고를 둘러보세요.'
                  : _scope == 'nationwide'
                  ? '지금 노출 중인 공고가 없어요.\n새 공고 알림을 켜두고 다시 확인해보세요.'
                  : '설정한 거리 안에는 공고가 없어요.\n지역이나 전국으로 넓혀서 볼 수 있어요.',
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
                        : () async {
                          await _init();
                          await _loadJobs();
                        },
                icon: Icon(
                  hasQuery ? Icons.backspace_outlined : Icons.refresh_rounded,
                  size: 18,
                ),
                label: Text(
                  hasQuery ? '검색어 지우기' : '새로고침',
                  style: const TextStyle(
                    fontSize: 15,
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
                // 위치 권한 버튼은 실제로 권한이 없을 때만 의미가 있다.
                // 권한이 멀쩡한 사람에게 띄우면 눌러도 아무것도 안 바뀐다.
                // 그 외에는 재방문 이유를 만드는 유일한 훅인 알림 신청을 준다.
                child: OutlinedButton.icon(
                  onPressed:
                      noLocation
                          ? () async => Geolocator.openAppSettings()
                          : _enableJobAlerts,
                  icon: Icon(
                    noLocation
                        ? Icons.settings_rounded
                        : Icons.notifications_active_outlined,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  label: Text(
                    noLocation ? '위치 권한 설정' : '새 공고 뜨면 알림 받기',
                    style: const TextStyle(
                      fontSize: 15,
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
              if (_scope != 'nationwide') ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (_isNearScope)
                      Expanded(
                        child: TextButton(
                          onPressed: _openRegionPicker,
                          child: const Text('지역으로 보기'),
                        ),
                      ),
                    Expanded(
                      child: TextButton(
                        onPressed: () => _setScope('nationwide'),
                        child: const Text('전국 공고 보기'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// 접으면 검색어도 함께 지운다. 접힌 채로 검색이 걸려 있으면
  /// "왜 공고가 이것뿐이지"가 된다 (필터 칩이 있지만 안전하게 초기화).
  void _toggleSearch() {
    if (_searchExpanded) {
      _searchController.clear();
      setState(() {
        searchQuery = '';
        _searchExpanded = false;
      });
      _applyFiltersThrottled();
    } else {
      setState(() => _searchExpanded = true);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _searchFocus.requestFocus(),
      );
    }
  }

  /// 검색창은 기본으로 접혀 있다. 공고가 몇 개뿐인 지면에서 상단 56pt를
  /// 상시 점유할 만큼 자주 쓰이지 않는다. 검색어가 걸려 있으면 목록 위
  /// 필터 칩(_activeFilterChips)에 그대로 보인다.
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
        focusNode: _searchFocus,
        textInputAction: TextInputAction.search,
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
                                        tooltip: '닫기',
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
                                                        // DESIGN.md: 장기 같은 분류 뱃지는 중립 회색
                                                        color: AppColors.bgMuted,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              20,
                                                            ),
                                                      ),
                                                      child: const Text(
                                                        '장기',
                                                        style: TextStyle(
                                                          color: AppColors.textSecondary,
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

  Future<void> _setScope(String scope, {String? sido, String? sigungu}) async {
    setState(() {
      _scope = scope;
      if (scope == 'region') {
        _regionSido = sido;
        _regionSigungu = sigungu;
      }
      _itemsToShow = 10;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kScopeKey, scope);
      if (scope == 'region') {
        await prefs.setString(_kRegionSidoKey, sido ?? '');
        if (sigungu == null) {
          await prefs.remove(_kRegionSigunguKey);
        } else {
          await prefs.setString(_kRegionSigunguKey, sigungu);
        }
      }
    } catch (_) {}
    // 불러오는 중이면 _loadJobs 가 그냥 돌아가 버려 옛 보기가 남는다 — 끝날 때까지 잠깐 기다린다.
    for (var i = 0; i < 40 && _isLoadingJobs; i++) {
      await Future.delayed(const Duration(milliseconds: 150));
      if (!mounted) return;
    }
    await _loadJobs();
  }

  Future<void> _openRegionPicker() async {
    List<Map<String, dynamic>> regions = [];
    try {
      final resp = await AuthenticatedHttpClient.get(
        Uri.parse('$baseUrl/api/job/regions'),
      ).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final d = jsonDecode(resp.body) as Map<String, dynamic>;
        regions =
            ((d['regions'] as List?) ?? const [])
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
      }
    } catch (_) {}
    if (!mounted) return;
    if (regions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('지역 정보를 불러오지 못했어요. 잠시 후 다시 시도해주세요.')),
      );
      return;
    }

    String? pickedSido =
        regions.any((r) => r['sido'] == _regionSido)
            ? _regionSido
            : regions.first['sido'] as String?;
    String? pickedGu = pickedSido == _regionSido ? _regionSigungu : null;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (ctx) => StatefulBuilder(
            builder: (ctx, setSheet) {
              final current = regions.firstWhere(
                (r) => r['sido'] == pickedSido,
                orElse: () => regions.first,
              );
              final gus =
                  ((current['sigungu'] as List?) ?? const [])
                      .whereType<Map>()
                      .toList();
              return SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('지역으로 보기', style: AppTextStyles.h3),
                      const SizedBox(height: 4),
                      Text(
                        '지금 공고가 있는 지역만 보여드려요.',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text('시·도', style: AppTextStyles.captionBold),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final r in regions)
                            ChoiceChip(
                              label: Text('${r['sido']} ${r['count']}'),
                              selected: pickedSido == r['sido'],
                              onSelected:
                                  (_) => setSheet(() {
                                    pickedSido = r['sido'] as String?;
                                    pickedGu = null;
                                  }),
                            ),
                        ],
                      ),
                      if (gus.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text('시·군·구', style: AppTextStyles.captionBold),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('전체'),
                              selected: pickedGu == null,
                              onSelected:
                                  (_) => setSheet(() => pickedGu = null),
                            ),
                            for (final g in gus)
                              ChoiceChip(
                                label: Text('${g['name']} ${g['count']}'),
                                selected: pickedGu == g['name'],
                                onSelected:
                                    (_) => setSheet(
                                      () => pickedGu = g['name'] as String?,
                                    ),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _setScope(
                              'region',
                              sido: pickedSido,
                              sigungu: pickedGu,
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                          ),
                          child: Text(
                            '이 지역 공고 보기',
                            style: AppTextStyles.btnLg.copyWith(
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
    );
  }

  Widget _buildDistanceSlider() {
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
          onChanged:
              (value) => setState(() {
                selectedDistance = value;
              }),
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
                    fontSize: 13,
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

    final distanceKm = _distanceKmFromUser(job);

    // 근무지가 여러 곳이면 '가장 가까운 곳'을 보여준다. 대표 주소를 쓰면
    // "수원 · 12km"처럼 주소와 거리가 서로 다른 지점을 가리킨다.
    final nearest =
        (currentLatitude == 0.0 || currentLongitude == 0.0)
            ? null
            : job.nearestFrom(currentLatitude, currentLongitude);
    final baseLocation = _trimProvince(nearest?.address ?? job.location);
    final extraCount = job.geoPoints.length - 1;
    final String placeText =
        extraCount > 0 ? '$baseLocation 외 $extraCount곳' : baseLocation;

    final String? distanceText =
        distanceKm == null
            ? null
            : (distanceKm < 10
                ? distanceKm.toStringAsFixed(1)
                : distanceKm.toStringAsFixed(0));
    final String locationLine =
        distanceText == null ? placeText : '$placeText · ${distanceText}km';

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
      opBadges.add(
        const JobSignalBadge(
          label: '긴급',
          signal: JobSignal.time,
          icon: Icons.bolt_rounded,
        ),
      );
    }
    if (isUrgent) {
      opBadges.add(const JobSignalBadge(label: '마감임박', signal: JobSignal.time));
    }
    // 급여 형태(일급/주급/월급)는 가격 옆 칩으로만 표시 — 상단 뱃지 중복 제거
    if (job.isSameDayPay == true) {
      opBadges.add(
        const JobSignalBadge(label: '당일지급', signal: JobSignal.money),
      );
    } else if (job.isCertifiedCompany == true) {
      opBadges.add(
        const JobSignalBadge(label: '안심기업', signal: JobSignal.trust),
      );
    }
    if (job.jobType == 'long') {
      opBadges.add(const JobSignalBadge(label: '장기'));
    }

    final displayBadges = opBadges.take(2).toList();
    // 칩 줄(거리·당일지급·긴급·안심기업·매칭이유)은 제거했다 —
    // 전부 상단 위치줄·뱃지·AI 요약에 이미 있는 내용이라 카드만 길어졌다.

    final schedule = [
      if (job.startDate != null && job.endDate != null)
        '${_formatDate(job.startDate!)} ~ ${_formatDate(job.endDate!)}',
      // 시간 미입력 공고는 "~"만 노출되던 문제 — 값 있을 때만 표시
      if (job.workingHours.replaceAll('~', '').trim().isNotEmpty)
        job.workingHours,
    ].join(' · ');
    final rawImage = job.imageUrls.isEmpty ? null : job.imageUrls.first;

    return JobListTile(
      pay: formattedPay,
      payType: job.payType,
      negotiablePay: isNegotiablePay,
      title: job.title,
      schedule: schedule.isEmpty ? null : schedule,
      location: locationLine,
      badges: displayBadges,
      imageUrl:
          rawImage == null
              ? null
              : (rawImage.startsWith('http') ? rawImage : '$baseUrl$rawImage'),
      isBookmarked: bookmarkedJobIds.contains(job.id.toString()),
      isApplied: isApplied,
      isPinned: isPinned,
      onTap: () => _openJobDetail(job),
      onBookmark: () => _toggleBookmark(job.id.toString()),
    );
  }

  /// 검색창(펼쳤을 때) + 한 줄 알약 행: 범위 · AI 검색 · 필터 · 위치.
  /// 예전엔 버튼 4개 행 + 범위 박스 3개 + 거리 박스가 각각 한 줄씩이었다.
  /// 앱바 제목: 지금 보는 범위 + ▾
  Widget _buildScopeTitle() {
    final label =
        _isNearScope
            ? '내 주변 ${selectedDistance.toStringAsFixed(0)}km'
            : _scope == 'region' && (_regionSido ?? '').isNotEmpty
            ? [_regionSido, _regionSigungu].whereType<String>().join(' ')
            : '전국';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _openScopeSheet,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // 예전 로고처럼 파랑 (대표 요청 — DESIGN.md '제목 파랑 금지'의 예외: 홈 앱바 한 곳)
              style: AppTextStyles.tabTitle.copyWith(color: AppColors.primary),
            ),
          ),
          const SizedBox(width: 2),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColors.primary,
          ),
        ],
      ),
    );
  }

  void _openScopeSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        Widget item(String title, String? sub, bool on, VoidCallback onTap) =>
            ListTile(
              title: Text(title, style: AppTextStyles.body1),
              subtitle: sub == null ? null : Text(sub, style: AppTextStyles.caption),
              trailing:
                  on
                      ? const Icon(Icons.check_rounded, color: AppColors.primary)
                      : null,
              onTap: () {
                Navigator.pop(ctx);
                onTap();
              },
            );
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              item('내 주변', '거리를 조절할 수 있어요', _isNearScope, () {
                if (!_isNearScope) _setScope('near');
                setState(() => _distanceExpanded = true);
              }),
              item('지역 선택', null, _scope == 'region', _openRegionPicker),
              item('전국', null, _scope == 'nationwide', () => _setScope('nationwide')),
              item('현재 위치 다시 찾기', null, false, () async {
                await _init();
                _applyFiltersThrottled();
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _openSortSheet() {
    showModalBottomSheet(
      context: context,
      builder:
          (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                for (final t in const ['최신순', '거리순', '급여 높은 순'])
                  ListTile(
                    title: Text(t, style: AppTextStyles.body1),
                    trailing:
                        sortType == t
                            ? const Icon(
                              Icons.check_rounded,
                              color: AppColors.primary,
                            )
                            : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() => sortType = t);
                      _applyFiltersThrottled();
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
    );
  }

  /// 칩 줄 (급구식): 정렬 · 상세필터 · 당일지급 · AI 검색 · 오늘 근무 가능. 급여형·업종은 상세필터 안
  Widget _buildTopControlRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_searchExpanded) ...[
          _buildSearchField(),
          const SizedBox(height: 10),
        ],
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _pill(
                label: sortType,
                trailing: Icons.keyboard_arrow_down_rounded,
                onTap: _openSortSheet,
              ),
              const SizedBox(width: 6),
              _pill(
                label: '상세필터',
                icon: Icons.tune_rounded,
                selected: selectedCategory != '전체' || selectedPayType != 'all',
                onTap: _openFilterSheet,
              ),
              const SizedBox(width: 6),
              _pill(
                label: '당일지급',
                selected: _onlySameDayPay,
                onTap: () {
                  setState(() => _onlySameDayPay = !_onlySameDayPay);
                  _applyFiltersThrottled();
                },
              ),
              const SizedBox(width: 6),
              _pill(
                label: 'AI 검색',
                icon: Icons.auto_awesome_outlined,
                onTap: _showAiSearchSheet,
              ),
              const SizedBox(width: 6),
              _buildTodayToggle(),
            ],
          ),
        ),
        if (_isNearScope && _distanceExpanded) ...[
          const SizedBox(height: 10),
          _buildDistanceSlider(),
        ],
      ],
    );
  }

  /// 목록 3번째 공고 뒤 한 칸: 알림 꺼짐 · 성별 안내 · 배너 · 파트너 광고
  Widget _buildFeedSlot() {
    final showPartner = _partnerAdActive && !_partnerCardHidden;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showPartner)
          _buildPartnerRecruitCard(PartnerRecruitPost.wonderLotte),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PushOffBanner(
                message: '알림이 꺼져 있어요 · 켜면 근처 새 공고를 바로 받아요',
                source: 'worker_home_banner',
              ),
              if (!isLoading &&
                  _workerGender == null &&
                  !_genderHintDismissed) ...[
                const SizedBox(height: 8),
                _buildGenderHintCard(),
              ],
            ],
          ),
        ),
        const AdBannerWidget(placement: 'app_home_worker'),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _pill({
    required String label,
    required VoidCallback onTap,
    bool selected = false,
    IconData? icon,
    IconData? trailing,
  }) {
    final fg = selected ? AppColors.primary : AppColors.textSecondary;
    return Material(
      color: selected ? AppColors.primaryLight : AppColors.bgMuted,
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.full),
        onTap: onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 4),
              ],
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.btnSm.copyWith(
                    fontSize: 13,
                    color: selected ? AppColors.primary : AppColors.textPrimary,
                  ),
                ),
              ),
              if (trailing != null) Icon(trailing, size: 16, color: fg),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTodayToggle() {
    return GestureDetector(
      onTap: () {
        setState(() => isAvailableToday = !isAvailableToday);
        setAvailableToday(isAvailableToday);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color:
              isAvailableToday
                  ? AppColors.success.withValues(alpha: 0.1)
                  : AppColors.bgMuted,
          borderRadius: BorderRadius.circular(AppRadius.full),
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
                        : AppColors.textTertiary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '오늘 가능',
              style: AppTextStyles.btnSm.copyWith(
                color:
                    isAvailableToday
                        ? AppColors.badgeSameDay
                        : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final d = date.toLocal();
    return '${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
  }
}

// ─────────────────────────────────────────────
// AI 추천 가로 스크롤 스트립
// ─────────────────────────────────────────────

