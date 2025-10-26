import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/job.dart';
import '../../data/services/job_service.dart';
import 'dart:math';
import 'package:intl/intl.dart';
import 'job_detail_screen.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:io';
import 'package:iljujob/config/constants.dart';
import 'dart:convert'; // jsonEncode, jsonDecode
import 'package:http/http.dart' as http; // http.get, http.post
import 'dart:async' show TimeoutException;
import 'dart:async';
import 'package:flutter/foundation.dart'; // ✅ kDebugMode, debugPrint 등
import '../../data/models/banner_ad.dart';
import 'package:url_launcher/url_launcher.dart';

class HomeMainScreen extends StatefulWidget {
  const HomeMainScreen({super.key});
  
  @override
  State<HomeMainScreen> createState() => _HomeMainScreenState();
}

class _HomeMainScreenState extends State<HomeMainScreen> {
  List<Job> allJobs = [];
  List<Job> filteredJobs = [];
  List<String> bookmarkedJobIds = [];
  List<int> appliedJobIds = [];
  String searchQuery = '';
  String selectedCategory = '전체';
  String sortType = '최신순';
  double currentLatitude = 0.0;
  double currentLongitude = 0.0;
  double selectedDistance = 50;
  int _itemsToShow = 10;
  bool isLoading = true;
  bool compactView = false;
  final ScrollController _scrollController = ScrollController();
  bool isAvailableToday = false;
  String selectedPayType = 'all'; // 기본값: 전체
int _jobsReqSeq = 0;     // 최신 요청만 반영
bool _isLoadingJobs = false;  // 중복 호출 방지
List<BannerAd> bannerAds = [];
int _currentBannerIndex = 0;
Timer? _bannerTimer;
  @override
void initState() {
  super.initState();
_loadBannerAds(); // 배너 로드
  _startBannerAutoSlide(); // 자동 슬라이드 시작
  _requestNotificationPermission();

  _loadAvailableTodayStatus(); // 그대로

  _loadBookmarks().then((_) async {
    // 🔁 이 블록만 async로 바꿔 순서 보장
    await _init();                     // 3. 위치 셋업 완료까지 대기
    await _loadJobsWithAppliedStatus(); // 4. 지원내역 → 공고 로딩
    if (mounted) setState(() => isLoading = false);
  }).catchError((e) async {
    // 북마크 실패해도 부팅 계속
    print('❌ 북마크 실패: $e');
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
  _debounce?.cancel();   // ← 추가
    _bannerTimer?.cancel(); // 배너 타이머 정리
  _scrollController.dispose();
  super.dispose();
}
// 1) 디바운스 타이머
Timer? _debounce;
bool _isApplying = false;

void _runDebounced(void Function() action, [Duration delay = const Duration(milliseconds: 180)]) {
  _debounce?.cancel();
  _debounce = Timer(delay, action);
}

// ✅ 동기 호출(반환타입도 void)
void _applyFiltersThrottled() {
  if (_isApplying) return;
  _isApplying = true;
  try {
    _applyFilters();  // <- await 쓰지 말기 (_applyFilters가 void이므로)
  } finally {
    _isApplying = false;
  }
}
// _loadBannerAds() 함수에 더 자세한 로그 추가
Future<void> _loadBannerAds() async {
  try {
    print('🔍 배너 로딩 시작...');
    final response = await http.get(Uri.parse('$baseUrl/api/banners'));
    
    print('📡 응답 코드: ${response.statusCode}');
    print('📄 응답 본문: ${response.body}');
    
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      print('✅ 배너 ${data.length}개 파싱 완료');
      
      if (!mounted) return;
      
      setState(() {
        bannerAds = data.map((json) => BannerAd.fromJson(json)).toList();
      });
      
      print('✅ 배너 상태 업데이트 완료');
    } else {
      print('❌ 배너 로드 실패: ${response.statusCode}');
    }
  } catch (e, stackTrace) {
    print('❌ 배너 로드 예외: $e');
    print('스택 트레이스: $stackTrace');
  }
}

// 자동 슬라이드
void _startBannerAutoSlide() {
  _bannerTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
    if (bannerAds.isEmpty) return;
    setState(() {
      _currentBannerIndex = (_currentBannerIndex + 1) % bannerAds.length;
    });
  });
}
  Future<void> _loadJobsWithAppliedStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId');
    if (userId == null) return;

    await fetchAppliedJobs(userId); // 지원 내역 먼저 가져옴
    await _loadJobs(); // 그리고 공고 로딩
  }

  void _requestNotificationPermission() async {
    if (!Platform.isAndroid) return; // iOS에서는 요청 자체 안 함

    final settings = await FirebaseMessaging.instance.requestPermission();

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      print('❌ 알림 권한 거부됨');
    } else if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {}
  }

Future<void> _init() async {
  final prefs = await SharedPreferences.getInstance();

  // 1) 저장된 좌표 로드 (없으면 0,0)
  double lat = prefs.getDouble('currentLatitude') ?? 0.0;
  double lng = prefs.getDouble('currentLongitude') ?? 0.0;

  try {
    // 2) 서비스/권한 체크
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print('❌ 위치 서비스 꺼짐');
      if (mounted) setState(() { currentLatitude = 0.0; currentLongitude = 0.0; });
      return; // 거리 필터 스킵
    }

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      print('❌ 위치 권한 거부');
      if (mounted) setState(() { currentLatitude = 0.0; currentLongitude = 0.0; });
      return; // 거리 필터 스킵
    }

    // 3) 빠른 값: 최근 위치 (있으면 먼저 사용)
    final last = await Geolocator.getLastKnownPosition();
    if ((lat == 0.0 && lng == 0.0) && last != null) {
      lat = last.latitude;
      lng = last.longitude;
    }

    // 4) 최신값: 타임아웃 방어
    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 5));
    } on TimeoutException {

    }

    // 5) 최종 좌표 결정
    final finalLat = pos?.latitude ?? lat;
    final finalLng = pos?.longitude ?? lng;

    if (mounted) {
      setState(() {
        currentLatitude = finalLat;
        currentLongitude = finalLng;
      });
    }

    if (finalLat != 0.0 && finalLng != 0.0) {
      // 서버 전송은 화면과 독립적으로 처리(대기 불필요)
      // ignore: unawaited_futures
      sendLocationToServer(finalLat, finalLng);
      await prefs.setDouble('currentLatitude', finalLat);
      await prefs.setDouble('currentLongitude', finalLng);
    }
  } catch (e) {
    print('❌ 위치 오류: $e');
    if (mounted) {
      // ⚠️ 예외 시 (0,0)로 둬서 거리 필터 스킵
      setState(() {
        currentLatitude = 0.0;
        currentLongitude = 0.0;
      });
    }
  }
}

  Future<void> retryFcmTokenSend() async {
    final token = await FirebaseMessaging.instance.getToken();

    if (token == null) {
      print('❌ 토큰 없음');
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final userPhone = prefs.getString('userPhone');
      final userType = prefs.getString('userType');

      final response = await http.post(
        Uri.parse('$baseUrl/api/user/update-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userPhone': userPhone,
          'userType': userType,
          'fcmToken': token,
        }),
      );
    } catch (e) {
      print('❌ 토큰 전송 실패: $e');
    }
  }
  
  // ✅ 서버 응답 모양을 전부 커버해 jobId 리스트로 변환
List<String> _parseBookmarksResponse(String body) {
  final ids = <String>[];
  dynamic json;
  try {
    json = jsonDecode(body);
  } catch (e) {
    debugPrint('❌ parse error: $e');
    return ids;
  }

  void pickFromList(List list) {
    for (final e in list) {
      if (e is Map) {
        // 🔥 서버가 job 객체 자체를 주므로 id가 곧 jobId
        final jobId = (e['job_id'] ?? e['jobId'] ?? e['job'] ?? e['id'])?.toString();
        if (jobId != null && jobId.isNotEmpty) ids.add(jobId);
      }
    }
  }

  if (json is List) {
    pickFromList(json);
  } else if (json is Map) {
    final list = (json['data'] ?? json['bookmarks'] ?? json['items'] ?? json['results']);
    if (list is List) pickFromList(list);
  }

  return ids;
}

Future<void> _loadBookmarks() async {
  final prefs = await SharedPreferences.getInstance();
  final userId = prefs.getInt('userId');
  final userType = prefs.getString('userType');
  if (userId == null) {
    return;
  }

  // 1차: 서버가 요구했던 userId
  final url1 = Uri.parse('$baseUrl/api/bookmark/list?userId=$userId');
  try {
    var resp = await http.get(url1);

    if (resp.statusCode == 200) {
      final ids = _parseBookmarksResponse(resp.body);
      if (!mounted) return;
      setState(() => bookmarkedJobIds = ids.toSet().toList());
      return;
    }

    // 2차: 혹시 workerId를 요구하는 서버일 경우 재시도
    final url2 = Uri.parse('$baseUrl/api/bookmark/list?workerId=$userId');
    final resp2 = await http.get(url2);

    if (resp2.statusCode == 200) {
      final ids = _parseBookmarksResponse(resp2.body);
      if (!mounted) return;
      setState(() => bookmarkedJobIds = ids.toSet().toList());
      return;
    }

  } catch (e, st) {
    debugPrint('❌ loadBookmarks exception: $e\n$st');
  }
}


  Future<void> setAvailableToday(bool available) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId'); // 로그인 시 저장된 값

    if (userId == null) {
      print('❌ userId 없음');
      return;
    }

    final response = await http.patch(
      Uri.parse('$baseUrl/api/worker/available-today'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': userId, 'availableToday': available}),
    );

    if (response.statusCode == 200) {
    } else {
      print('❌ 서버 오류: ${response.body}');
    }
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

        setState(() {
          isAvailableToday = data['availableToday'] ?? false;
        });
      } else {
        print('❌ 상태 불러오기 실패: ${response.body}');
      }
    } catch (e) {
      print('❌ 네트워크 오류: $e');
    }
  }

  Future<void> sendLocationToServer(double lat, double lng) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId');

    if (userId == null) return;

    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/api/worker/update-location'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': userId, 'lat': lat, 'lng': lng}),
      );

      if (response.statusCode == 200) {
      } else {
        print('❌ 위치 저장 실패: ${response.body}');
      }
    } catch (e) {
      print('❌ 위치 저장 예외: $e');
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
      return;
    }

    // ❗ 여기: 서버가 '이미 북마크됨'이면 로컬을 북마크된 상태로 교정
    if (resp.body.contains('이미 북마크됨')) {
      if (!mounted) return;
      setState(() {
        if (!bookmarkedJobIds.contains(jobId)) {
          bookmarkedJobIds.add(jobId);
        }
      });
      // 즉시 전체 재동기화해서 확정
      await _loadBookmarks();
      return;
    }

    // 반대 케이스(없음/삭제됨)도 교정
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
      final response = await http.get(
        Uri.parse('$baseUrl/api/apply/my-jobs?workerId=$userId'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        appliedJobIds = List<int>.from(data.map((item) => item['id']));
      } else {
        print('❌ 지원한 공고 조회 실패');
      }
    } catch (e) {
      print('❌ 네트워크 오류: $e');
    }
  }
Future<void> _loadJobs() async {
  if (_isLoadingJobs) return;
  _isLoadingJobs = true;
  final req = ++_jobsReqSeq;

  try {
    final jobs = await JobService.fetchJobs(clientId: null);
    if (req != _jobsReqSeq || !mounted) return;

    final nowUtc = DateTime.now().toUtc();

    bool isPinnedActive(Job j) =>
        j.pinnedUntil != null && j.pinnedUntil!.isAfter(nowUtc);

    bool isFutureScheduled(Job j) =>
        j.publishAt != null && j.publishAt!.isAfter(nowUtc);

    bool isExpired(Job j) =>
        j.expiresAt != null && !j.expiresAt!.isAfter(nowUtc);

    int closed = 0, deleted = 0, futureScheduled = 0, expired = 0;
    int filteredByDistance = 0, noGeoKept = 0;

    // 1) 상태/시간 필터 (핀 = 예약 무시 / 만료만 제외)
    final validJobs = <Job>[];
    for (final j in jobs) {
      if (j.status == 'closed')  { closed++;  continue; }
      if (j.status == 'deleted') { deleted++; continue; }

      final pin = isPinnedActive(j);
      final fut = isFutureScheduled(j);
      final exp = isExpired(j);

      // 만료는 핀이어도 제외 (정책 그대로 유지)
      if (exp) { expired++; continue; }

      // 예약은 핀이 아닐 때만 숨김 (핀은 통과)
      if (!pin && fut) { futureScheduled++; continue; }

      validJobs.add(j);
    }

    // 2) 거리 필터 — 핀은 거리 예외, 좌표 없으면 통과(기존 정책 유지)
    List<Job> filtered = validJobs;
    if (currentLatitude != 0.0 && currentLongitude != 0.0) {
      final tmp = <Job>[];
      for (final j in validJobs) {

        final hasGeo = j.lat != 0.0 && j.lng != 0.0;
        if (!hasGeo) { // 좌표 없으면 유지
          noGeoKept++;
          tmp.add(j);
          continue;
        }
        final d = calculateDistance(currentLatitude, currentLongitude, j.lat, j.lng);
        if (d <= selectedDistance) {
          tmp.add(j);
        } else {
          filteredByDistance++;
        }
      }
      filtered = tmp;
    }

    // 3) 정렬 — 핀 우선 → 핀끼리는 pinnedUntil DESC → 게시시각 DESC → id DESC(숫자)
    int idAsInt(String s) => int.tryParse(s) ?? 0;

    filtered.sort((a, b) {
      final apin = isPinnedActive(a), bpin = isPinnedActive(b);
      if (apin != bpin) return bpin ? 1 : -1;

      if (apin && bpin) {
        final cp = b.pinnedUntil!.compareTo(a.pinnedUntil!); // desc
        if (cp != 0) return cp;
      }

      final ap = a.publishAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final bp = b.publishAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final cd = bp.compareTo(ap); if (cd != 0) return cd;

      return idAsInt(b.id).compareTo(idAsInt(a.id)); // 숫자 기반 id desc
    });

    if (req != _jobsReqSeq || !mounted) return;
    setState(() {
      allJobs = validJobs;
      filteredJobs = filtered;
      _itemsToShow = 10;
    });

    // 디버그: 핀/예약/만료/거리로 빠진 이유 로그
    if (kDebugMode) {

      if (filtered.isNotEmpty) {
        final t = filtered.first;
        debugPrint('[jobs] TOP id=${t.id} pin=${isPinnedActive(t)} '
                   'pinnedUntil=${t.pinnedUntil} publishAt=${t.publishAt} created=${t.createdAt}');
      }
    }
  } catch (e) {
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
final now = DateTime.now().toLocal(); // ✅ 로컬 고정

  bool isPinned(Job j) =>
      j.pinnedUntil != null && j.pinnedUntil!.isAfter(now);

  int payValue(Job j) {
    final onlyNum = j.pay.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(onlyNum) ?? 0;
  }

  // 🔸 시간 필터 (⚠️ 핀 유효면 '예약' 허용, '만료'만 제외)
  tempJobs = tempJobs.where((job) {
    final publishAt = job.publishAt ?? job.createdAt ?? now;
    final isFuture  = publishAt.isAfter(now);
    final notExpired = (job.expiresAt == null) || job.expiresAt!.isAfter(now);

    if (isPinned(job)) {
      return notExpired;              // 핀 유효 → 예약 허용, 만료만 컷
    }
    return !isFuture && notExpired;   // 일반 공고
  }).toList();

  // 🔸 거리 필터 (⚠️ 핀 유효는 거리 예외)
// ✅ 핀도 반경 안에서만 보이게 (좌표 없는 공고는 유지)
if (currentLatitude != 0.0 && currentLongitude != 0.0) {
  tempJobs = tempJobs.where((job) {
    final hasGeo = job.lat != 0.0 && job.lng != 0.0;
    if (!hasGeo) return true; // 좌표 없는 공고는 유지 (초기 로딩과 규칙 통일)

    final distance = calculateDistance(
      currentLatitude, currentLongitude, job.lat, job.lng,
    );
    return distance <= selectedDistance; // 핀도 반경 안에서만 👍
  }).toList();
}

  // 🔸 급여 유형
  if (selectedPayType != 'all') {
    tempJobs = tempJobs.where((job) {
      final payTypeInEnglish =
          job.payType == '일급' ? 'daily'
        : job.payType == '주급' ? 'weekly'
        : 'all';
      return payTypeInEnglish == selectedPayType;
    }).toList();
  }

  // 🔸 카테고리
  if (selectedCategory != '전체') {
    tempJobs = tempJobs.where((job) => job.category == selectedCategory).toList();
  }

  // 🔸 검색어
  if (searchQuery.isNotEmpty) {
    tempJobs = tempJobs.where((job) =>
      job.title.contains(searchQuery) || job.location.contains(searchQuery)
    ).toList();
  }

  // 🔸 정렬 (항상 핀 우선)
  int cmpPinned(Job a, Job b) {
    final ap = isPinned(a), bp = isPinned(b);
    if (ap != bp) return bp ? 1 : -1;
    if (ap && bp) return b.pinnedUntil!.compareTo(a.pinnedUntil!);
    return 0;
  }

  switch (sortType) {
    case '거리순':
      tempJobs.sort((a, b) {
        final c = cmpPinned(a, b); if (c != 0) return c;
        final distA = calculateDistance(currentLatitude, currentLongitude, a.lat, a.lng);
        final distB = calculateDistance(currentLatitude, currentLongitude, b.lat, b.lng);
        return distA.compareTo(distB);
      });
      break;

    case '급여 높은 순':
      tempJobs.sort((a, b) {
        final c = cmpPinned(a, b); if (c != 0) return c;
        return payValue(b).compareTo(payValue(a));
      });
      break;

    case '최신순':
    default:
      tempJobs.sort((a, b) {
        final c = cmpPinned(a, b); if (c != 0) return c;
        final aDate = a.publishAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.publishAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
  }

  setState(() {
    filteredJobs = tempJobs;
    _itemsToShow = 10;
  });
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

  @override
Widget build(BuildContext context) {
  return GestureDetector(
    onTap: () => FocusScope.of(context).unfocus(),
    child: Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: AppBar(
          backgroundColor: Colors.white,
          elevation: 1,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '알바일주 알바생',
                style: TextStyle(
                  fontFamily: 'Jalnan2TTF',
                  fontSize: 24,
                  color: Color(0xFF3B8AFF),
                ),
              ),
              Row(
                children: [
                  Text(
                    '오늘 가능',
                    style: TextStyle(
                      fontSize: 14,
                      color: isAvailableToday ? Colors.green : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Switch(
                    value: isAvailableToday,
                    activeColor: Colors.green,
                    onChanged: (value) {
                      setState(() => isAvailableToday = value);
                      setAvailableToday(value);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),

      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: CustomScrollView(
                controller: _scrollController, // ✅ 기존 컨트롤러 재사용
                slivers: [
                  // 상단 필터들 (스크롤에 포함)
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverToBoxAdapter(child: _buildSearchAndLocationRow()),
                  ),
                   // ✨ 배너 광고 추가
                  SliverToBoxAdapter(child: _buildBannerSlider()),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildCategoryList(),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildDistanceSlider(),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildSortOptions(),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 8)),

                  // 공고 리스트
                  if (filteredJobs.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmptyJobsView(), // 아래 2) 참조
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList.builder(
                        itemCount: (_itemsToShow < filteredJobs.length)
                            ? _itemsToShow
                            : filteredJobs.length,
                        itemBuilder: (context, index) {
                          final job = filteredJobs[index];
                          return GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => JobDetailScreen(job: job)),
                            ),
                            child: compactView ? _buildCompactJobCard(job) : _buildJobCard(job),
                          );
                        },
                      ),
                    ),

                  // 로딩 더미(무한스크롤 시 하단에 살짝 여유)
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
    ),
  );
}
Widget _buildEmptyJobsView() {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('😥 현재 설정 거리 내 공고가 없습니다.', style: TextStyle(fontSize: 16)),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: () async => Geolocator.openAppSettings(),
          child: const Text('위치 권한 설정 열기'),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: () async => _init(),
          child: const Text('다시 시도'),
        ),
      ],
    ),
  );
}

  Widget _buildSearchAndLocationRow() {
    return Row(
      children: [
        Expanded(child: _buildSearchField()), // 기존 검색창
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: () async {
            LocationPermission permission = await Geolocator.checkPermission();
            if (permission == LocationPermission.denied) {
              permission = await Geolocator.requestPermission();
            }

            if (permission == LocationPermission.deniedForever) {
              await Geolocator.openAppSettings();
              return;
            }

            try {
              final position = await Geolocator.getCurrentPosition(
                desiredAccuracy: LocationAccuracy.high,
              );

              setState(() {
                currentLatitude = position.latitude;
                currentLongitude = position.longitude;
              });

              await sendLocationToServer(position.latitude, position.longitude);
             _applyFiltersThrottled(); 

              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('✅ 위치가 업데이트되었습니다')));
            } catch (e) {
              print('❌ 위치 가져오기 실패: $e');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('❌ 위치 가져오기에 실패했습니다')),
              );
            }
          },

          icon: const Icon(Icons.my_location, size: 18), // ✅ 필수
          label: const Text('위치변경'), // ✅ 필수
        ),
      ],
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
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        style: const TextStyle(fontSize: 13),
      ),
    );
  }

  Widget _buildCategoryList() {
    return SizedBox(
      height: 80,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildCategoryIcon(Icons.all_inbox, '전체'),
          _buildCategoryIcon(Icons.factory, '제조'),
          _buildCategoryIcon(Icons.local_shipping, '물류'),
          _buildCategoryIcon(Icons.support_agent, '서비스'),
          _buildCategoryIcon(Icons.engineering, '건설'),
          _buildCategoryIcon(Icons.work, '사무'),
          _buildCategoryIcon(Icons.cleaning_services, '청소'),
          _buildCategoryIcon(Icons.more_horiz, '기타'),
        ],
      ),
    );
  }

  Widget _buildCategoryIcon(IconData icon, String label) {
    final isSelected = selectedCategory == label;
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedCategory = (selectedCategory == label) ? '전체' : label;
          _applyFiltersThrottled();
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor:
                  isSelected ? Colors.indigo : Colors.grey.shade200,
              child: Icon(
                icon,
                color: isSelected ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? Colors.indigo : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDistanceSlider() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '📏 거리 설정',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text('${selectedDistance.toStringAsFixed(0)}km'),
          ],
        ),
        Slider(
          min: 1,
          max: 50,
          divisions: 49,
          value: selectedDistance,
          onChanged: (value) {
            setState(() {
              selectedDistance = value;
            });
            _runDebounced(_applyFiltersThrottled);
          },
        ),
      ],
    );
  }

  Widget _buildSortOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            DropdownButton<String>(
              value: sortType,
              items:
                  ['거리순', '최신순', '급여 높은 순']
                      .map(
                        (e) => DropdownMenuItem(
                          value: e,
                          child: Text(e, style: TextStyle(fontSize: 14)),
                        ),
                      )
                      .toList(),
              onChanged: (value) {
                setState(() {
                  sortType = value!;
                 _applyFiltersThrottled(); // ✅ 쓰로틀로 1회만 반영
                });
              },
              underline: const SizedBox(),
            ),
            const Spacer(),
            IconButton(
              icon: Icon(
                compactView ? Icons.view_agenda : Icons.view_list,
                size: 20,
              ),
              onPressed: () {
                setState(() {
                  compactView = !compactView;
                });
              },
              tooltip: compactView ? 'Compact View' : 'List View',
            ),
          ],
        ),
        const SizedBox(height: 10),

        // ✅ 한 줄로 강제 + 스크롤 되게
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildPayChip('전체', 'all'),
              const SizedBox(width: 8),
              _buildPayChip('일급', 'daily'),
              const SizedBox(width: 8),
              _buildPayChip('주급', 'weekly'),
            ],
          ),
        ),
      ],
    );
  }

  /// ✨ 재사용 가능한 Chip 위젯 분리
  Widget _buildPayChip(String label, String value) {
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 13)),
      visualDensity: VisualDensity(horizontal: -2, vertical: -2),
      selected: selectedPayType == value,
      onSelected: (_) {
        setState(() {
          selectedPayType = value;
           _applyFiltersThrottled(); // ✅ 쓰로틀로 1회만 반영
        });
      },
      selectedColor: const Color(0xFFDDE3FF),
      backgroundColor: Colors.grey.shade100,
      labelStyle: TextStyle(
        color: selectedPayType == value ? Colors.black : Colors.grey[700],
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color:
              selectedPayType == value
                  ? Colors.transparent
                  : Colors.grey.shade300,
        ),
      ),
    );
  }



  Widget _buildJobCard(Job job) {
    final formattedPay = NumberFormat('#,###').format(int.parse(job.pay));
    final isApplied = appliedJobIds.contains(int.tryParse(job.id));

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300, width: 0.8),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 제목 (상세보기로 이동)
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => JobDetailScreen(job: job),
                      ),
                    );
                  },
                  child: Text(
                    job.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
    // ✅ 상단고정 배지 (작게)
    if (job.pinnedUntil != null && job.pinnedUntil!.isAfter(DateTime.now()))
      _buildPinnedBadgeSmall(),
  
                // 위치, 기간, 시간, 급여 텍스트 정렬
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Text(
                      '📍 ${job.location}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    if (job.startDate != null && job.endDate != null)
                      Text(
                        '📆 ${_formatDate(job.startDate!)} ~ ${_formatDate(job.endDate!)}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    Text(
                      '⏰ ${job.workingHours}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    Text(
                      '💰 $formattedPay원',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    // 일급
                    if (job.payType == '일급')
                      _buildBadge('일급', color: Colors.blueAccent),

                    // 주급
                    if (job.payType == '주급')
                      _buildBadge('주급', color: Colors.deepPurple),

                    // 안심기업
                    if (job.isCertifiedCompany == true)
                      _buildBadge('안심기업', color: Colors.green),

                    // 당일지급
                    if (job.isSameDayPay == true)
                      _buildBadge('당일지급', color: Colors.lightBlue),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),

          // 오른쪽: 즐겨찾기 + 지원 버튼
          Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              IconButton(
                icon: Icon(
                  bookmarkedJobIds.contains(job.id.toString())
                      ? Icons.bookmark
                      : Icons.bookmark_border,
                  color:
                      bookmarkedJobIds.contains(job.id.toString())
                          ? Colors.orange
                          : Colors.grey,
                ),
                onPressed: () => _toggleBookmark(job.id.toString()),
                
                tooltip:
                    bookmarkedJobIds.contains(job.id.toString())
                        ? '즐겨찾기 해제'
                        : '즐겨찾기 추가',
              ),
              ElevatedButton.icon(
                icon: Icon(
                  isApplied ? Icons.check_circle : Icons.send,
                  size: 18,
                  color: Colors.white,
                ),
                label: Text(
                  isApplied ? '지원 완료' : '지원',
                  style: const TextStyle(fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(90, 36),
                  backgroundColor:
                      isApplied
                          ? Colors.grey
                          : const Color.fromARGB(255, 122, 160, 255),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => JobDetailScreen(job: job),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String label, {Color color = Colors.grey}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15), // 배경 흐리게
        border: Border.all(color: color.withOpacity(0.6)), // 테두리 연하게
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color.withOpacity(0.9),
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildCompactJobCard(Job job) {
    final formattedPay = NumberFormat('#,###').format(int.parse(job.pay));

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300, width: 0.7),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => JobDetailScreen(job: job),
                  ),
                );
              },
              child: Text(
                job.title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.indigo,
                  decoration: TextDecoration.underline,
                ),
                overflow: TextOverflow.ellipsis, // 추가: 넘치는 텍스트 말줄임표
              ),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '📍 ${job.location}',
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '💰 $formattedPay원',
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis,
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
                      ? Colors.orange
                      : Colors.grey,
            ),
            onPressed: () => _toggleBookmark(job.id),
            tooltip: bookmarkedJobIds.contains(job.id) ? '즐겨찾기 해제' : '즐겨찾기 추가',
          ),
          SizedBox(
            height: 30,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(50, 30),
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => JobDetailScreen(job: job),
                  ),
                );
              },
              child: const Text('지원', style: TextStyle(fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }

String _formatDate(DateTime date) {
  final d = date.isUtc ? date.toLocal() : date; // ✅ 로컬(KST) 변환 보정
  return '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
}
Widget _buildPinnedBadgeSmall() {
  return const Text(
    '광고',
    style: TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w500, // 너무 두껍지 않게
      color: Colors.grey,          // 연한 회색
      height: 1.0,
    ),
  );
}
Widget _buildBannerSlider() {
  if (bannerAds.isEmpty) return const SizedBox.shrink();

  return Container(
    height: 100,
    margin: const EdgeInsets.symmetric(horizontal: 16),
    child: Stack(
      children: [
        PageView.builder(
          itemCount: bannerAds.length,
          onPageChanged: (index) {
            setState(() => _currentBannerIndex = index);
          },
          itemBuilder: (context, index) {
            final banner = bannerAds[index];
            return GestureDetector(
              onTap: () => _onBannerTap(banner), // 클릭 핸들러 호출
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey[200],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    '$baseUrl${banner.imageUrl}',
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Icon(Icons.error_outline, color: Colors.grey),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
        Positioned(
          bottom: 6,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              bannerAds.length,
              (index) => Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _currentBannerIndex == index
                      ? Colors.white
                      : Colors.white.withOpacity(0.4),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

// 배너 클릭 핸들러 (기존 함수 수정)
Future<void> _onBannerTap(BannerAd banner) async {
  if (banner.linkUrl == null || banner.linkUrl!.isEmpty) {
    return;
  }

  final Uri url = Uri.parse(banner.linkUrl!);

  try {
    // ✅ 에뮬레이터용: platformDefault로 변경
    await launchUrl(
      url,
      mode: LaunchMode.platformDefault, // externalApplication → platformDefault
    );
  } catch (e) {
    print('❌ 링크 열기 오류: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('링크 열기 실패: $e')),
      );
    }
  }
}


}
