// worker_map_view.dart
// 클라이언트용 알바생 지도뷰
// 프리미엄: 구독자 프로필 열람 + 채팅 시작 + 내 공고 주변 알림 보내기

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:geocoding/geocoding.dart';
import 'package:iljujob/config/constants.dart';
import 'package:iljujob/presentation/chat/chat_room_screen.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ──────────────────────────────────────────────
// 상수
// ──────────────────────────────────────────────
class _MapConst {
  const _MapConst._();

  static const double minZoom = 7.0;
  static const double maxZoom = 19.0;
  static const double defaultZoom = 14.0;
  static const LatLng seoulCenter = LatLng(37.5665, 126.9780);

  static final LatLngBounds koreaBounds = LatLngBounds(
    const LatLng(33.0, 124.5),
    const LatLng(38.7, 132.1),
  );

  static const Duration searchDebounce = Duration(milliseconds: 300);
  static const Duration networkTimeout = Duration(seconds: 10);

  static const Map<int, double> zoomBuckets = {
    0: 20.0,
    1: 28.0,
    2: 36.0,
    3: 46.0,
  };

  static int zoomBucket(double z) {
    if (z < 10) return 0;
    if (z < 13) return 1;
    if (z < 16) return 2;
    return 3;
  }

  static double iconSize(double z) => zoomBuckets[zoomBucket(z)]!;
}

// ──────────────────────────────────────────────
// 디자인 토큰
// ──────────────────────────────────────────────
class _C {
  const _C._();
  static const primary = Color(0xFF3B8AFF);
  static const primaryLight = Color(0xFFEEF5FF);
  static const surface = Color(0xFFFFFFFF);
  static const background = Color(0xFFF4F6FA);
  static const textPrimary = Color(0xFF191F28);
  static const textSecondary = Color(0xFF6B7280);
  static const border = Color(0xFFE5E8EB);
  static const gold = Color(0xFFFFB300);
  static const goldLight = Color(0xFFFFF8E1);
}

// ──────────────────────────────────────────────
// 반경 enum
// ──────────────────────────────────────────────
enum RadiusFilter {
  none(label: '전체', meters: 0),
  km1(label: '1km', meters: 1000),
  km3(label: '3km', meters: 3000),
  km5(label: '5km', meters: 5000);

  const RadiusFilter({required this.label, required this.meters});
  final String label;
  final int meters;
}

// ──────────────────────────────────────────────
// 모델
// ──────────────────────────────────────────────
class WorkerMarkerData {
  const WorkerMarkerData({
    required this.id,
    required this.lat,
    required this.lng,
    required this.profileUrl,
    this.name = '',
    this.skills = '',
    this.rating,
  });

  final int id;
  final double lat;
  final double lng;
  final String profileUrl;
  final String name;
  final String skills;
  final double? rating;

  LatLng get position => LatLng(lat, lng);

  factory WorkerMarkerData.fromMap(Map<String, dynamic> map) {
    return WorkerMarkerData(
      id: (map['id'] as num).toInt(),
      lat: (map['lat'] as num).toDouble(),
      lng: (map['lng'] as num).toDouble(),
      profileUrl: (map['profileUrl'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      skills: (map['skills'] ?? '').toString(),
      rating: map['rating'] != null ? (map['rating'] as num).toDouble() : null,
    );
  }

  static bool isValid(Map<String, dynamic> m) {
    final lat = m['lat'];
    final lng = m['lng'];
    if (lat is! num || lng is! num) return false;
    final la = lat.toDouble();
    final lo = lng.toDouble();
    if (la.isNaN || lo.isNaN || la.isInfinite || lo.isInfinite) return false;
    if (la < -90 || la > 90 || lo < -180 || lo > 180) return false;
    return true;
  }

  double distanceTo(LatLng other) {
    const r = 6371000.0;
    final dLat = _rad(other.latitude - lat);
    final dLng = _rad(other.longitude - lng);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat)) *
            math.cos(_rad(other.latitude)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double deg) => deg * math.pi / 180;
}

// ──────────────────────────────────────────────
// 공고 모델 (내 공고 선택용)
// ──────────────────────────────────────────────
class _ClientJob {
  final int id;
  final String title;
  final String location;
  final String startDate;

  const _ClientJob({
    required this.id,
    required this.title,
    required this.location,
    required this.startDate,
  });

  factory _ClientJob.fromJson(Map<String, dynamic> j) => _ClientJob(
    id: (j['id'] ?? j['job_id'] ?? 0) as int,
    title: (j['title'] ?? j['job_title'] ?? '공고').toString(),
    location: (j['location_city'] ?? j['location'] ?? '위치 미상').toString(),
    startDate: (j['start_date'] ?? '').toString(),
  );
}

// ──────────────────────────────────────────────
// 메인 위젯
// ──────────────────────────────────────────────
class WorkerMapView extends StatefulWidget {
  const WorkerMapView({super.key});

  @override
  State<WorkerMapView> createState() => _WorkerMapViewState();
}

class _WorkerMapViewState extends State<WorkerMapView>
    with WidgetsBindingObserver {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  List<WorkerMarkerData> _allWorkers = [];
  List<WorkerMarkerData> _workers = [];
  bool _isLoading = true;
  bool _showOnlyAvailableToday = false;
  double _currentZoom = _MapConst.defaultZoom;
  LatLng? _currentLocation;
  RadiusFilter _radiusFilter = RadiusFilter.none;
  Timer? _debounceTimer;

  // ── 구독 / 클라이언트 정보
  bool _isSubscribed = false;
  int? _myClientId;
  String _myCompanyName = '';
  String _myThumbnailUrl = '';
  bool _subChecked = false;

  // ── lifecycle ──────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initClientInfo();
    _fetchWorkers();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  // ── 클라이언트 정보 + 구독 체크 ───────────

  Future<void> _initClientInfo() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _myClientId = prefs.getInt('userId');
      _myCompanyName = prefs.getString('companyName') ?? '';
      _myThumbnailUrl = prefs.getString('profileImageUrl') ?? '';
    });
    await _checkSubscription(prefs);
  }

  Future<void> _checkSubscription(SharedPreferences prefs) async {
    if (_subChecked) return;
    _subChecked = true;
    final token = prefs.getString('authToken') ?? '';
    if (token.isEmpty) return;
    try {
      final res = await http
          .get(
            Uri.parse('$baseUrl/api/subscription/status'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(_MapConst.networkTimeout);

      if (res.statusCode == 200 && mounted) {
        final d = jsonDecode(res.body) as Map<String, dynamic>;
        final plan = (d['plan']?.toString() ?? '').toLowerCase();
        final active = d['active'] == true;
        setState(
          () => _isSubscribed = active && (plan == 'pro' || plan == 'premium'),
        );
      }
    } catch (_) {}
  }

  // ── 필터 ───────────────────────────────────

  void _applyFilters() {
    List<WorkerMarkerData> filtered = _allWorkers;
    if (_radiusFilter != RadiusFilter.none && _currentLocation != null) {
      filtered =
          filtered
              .where(
                (w) => w.distanceTo(_currentLocation!) <= _radiusFilter.meters,
              )
              .toList();
    }
    setState(() => _workers = filtered);
  }

  // ── 데이터 로딩 ────────────────────────────

  Future<void> _fetchWorkers() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final endpoint =
        _showOnlyAvailableToday
            ? '$baseUrl/api/worker/available-today'
            : '$baseUrl/api/worker/all';

    try {
      final response = await http
          .get(Uri.parse(endpoint), headers: {'Accept': 'application/json'})
          .timeout(_MapConst.networkTimeout);

      if (!mounted) return;

      if (response.statusCode == 200) {
        _allWorkers = _parseWorkers(response.body);
        _applyFilters();
        setState(() => _isLoading = false);
      } else {
        _onLoadError('알바생 정보를 불러오지 못했어요.');
      }
    } on TimeoutException {
      _onLoadError('요청 시간이 초과됐어요. 다시 시도해 주세요.');
    } on SocketException {
      _onLoadError('네트워크 연결을 확인해 주세요.');
    } catch (e) {
      debugPrint('worker loading error: $e');
      _onLoadError('잠시 오류가 발생했어요.');
    }
  }

  void _onLoadError(String message) {
    if (!mounted) return;
    setState(() => _isLoading = false);
    _showSnackBar(message);
  }

  List<WorkerMarkerData> _parseWorkers(String body) {
    try {
      final dynamic decoded = jsonDecode(body);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .where(WorkerMarkerData.isValid)
          .where(
            (m) => _MapConst.koreaBounds.contains(
              LatLng(
                (m['lat'] as num).toDouble(),
                (m['lng'] as num).toDouble(),
              ),
            ),
          )
          .map(WorkerMarkerData.fromMap)
          .toList(growable: false);
    } catch (e) {
      debugPrint('worker parse error: $e');
      return [];
    }
  }

  // ── 위치 ───────────────────────────────────

  Future<void> _initLocation() async {
    final loc = await _getLocation();
    if (loc != null && mounted) {
      setState(() => _currentLocation = loc);
      _mapController.move(loc, _MapConst.defaultZoom);
      _applyFilters();
    }
  }

  Future<void> _goToMyLocation() async {
    if (_currentLocation != null) {
      _mapController.move(_currentLocation!, _MapConst.defaultZoom);
      return;
    }
    final loc = await _getLocation();
    if (loc != null && mounted) {
      setState(() => _currentLocation = loc);
      _mapController.move(loc, _MapConst.defaultZoom);
      _applyFilters();
    }
  }

  Future<LatLng?> _getLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      _showSnackBar('위치 서비스를 켜 주세요.');
      return null;
    }
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) return null;
    }
    if (perm == LocationPermission.deniedForever) {
      _showSnackBar('설정에서 위치 접근을 허용해 주세요.');
      return null;
    }
    final last = await Geolocator.getLastKnownPosition();
    if (last != null) {
      _refinePreciseLocation();
      return LatLng(last.latitude, last.longitude);
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 2),
      );
      _refinePreciseLocation();
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {}
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 4),
      );
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }

  Future<void> _refinePreciseLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 6),
      );
      if (!mounted) return;
      setState(() => _currentLocation = LatLng(pos.latitude, pos.longitude));
      _applyFilters();
    } catch (_) {}
  }

  // ── 검색 ───────────────────────────────────

  Future<void> _searchLocation() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    try {
      final locations = await locationFromAddress(query);
      if (!mounted) return;
      if (locations.isEmpty) {
        _showSnackBar('검색 결과가 없어요. 동 이름이나 지하철역으로 검색해 보세요.');
        return;
      }
      final target = LatLng(
        locations.first.latitude,
        locations.first.longitude,
      );
      if (!_MapConst.koreaBounds.contains(target)) {
        _showSnackBar('한국 외 지역은 아직 지원하지 않아요.');
        return;
      }
      _mapController.move(target, 13);
    } catch (_) {
      if (!mounted) return;
      _showSnackBar('잠시 연결이 불안정해요. 다시 시도해 주세요.');
    }
  }

  // ── 워커 바텀시트 ────────────────────────────

  void _showWorkerSheet(WorkerMarkerData worker) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (_) => _WorkerBottomSheet(
            worker: worker,
            isSubscribed: _isSubscribed,
            onViewProfile: () => _openProfile(worker),
            onStartChat: () => _pickJobForChat(worker),
            onSubscribePrompt: _showSubscribePrompt,
          ),
    );
  }

  // ── 프로필 이동 ────────────────────────────

  void _openProfile(WorkerMarkerData worker) {
    Navigator.pop(context);
    Navigator.pushNamed(context, '/worker-profile', arguments: worker.id);
  }

  // ── 채팅 (공고 선택 → 채팅방) ───────────────

  Future<void> _pickJobForChat(WorkerMarkerData worker) async {
    Navigator.pop(context);
    final jobs = await _fetchMyActiveJobs();
    if (!mounted) return;

    if (jobs.isEmpty) {
      _showSnackBar('활성 공고가 없어요. 공고를 먼저 등록해 주세요.');
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (_) => _JobPickSheet(
            title: '어떤 공고로 채팅을 시작할까요?',
            subtitle:
                '${worker.name.isEmpty ? '알바생' : worker.name}님에게 공고를 소개해요.',
            jobs: jobs,
            actionLabel: '채팅 시작',
            onSelect: (job) => _openChatRoom(worker: worker, job: job),
          ),
    );
  }

  Future<void> _openChatRoom({
    required WorkerMarkerData worker,
    required _ClientJob job,
  }) async {
    Navigator.pop(context);
    _showSnackBar('채팅방을 준비하는 중이에요...');

    try {
      // requestChatFromClient: 채팅방 생성 + 알바생에게 수락 요청
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/chat/request'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'jobId': job.id,
              'workerId': worker.id,
              'clientId': _myClientId,
              'openerMessage': '안녕하세요! ${job.title} 공고를 보고 연락드려요.',
            }),
          )
          .timeout(_MapConst.networkTimeout);

      if (!mounted) return;

      final data = jsonDecode(res.body) as Map<String, dynamic>;

      if (res.statusCode == 200 && data['ok'] == true) {
        final roomId = data['roomId'];
        if (roomId == null) throw Exception('채팅방 ID 없음');

        // pending 상태 안내 (알바생이 수락해야 대화 가능)
        if (data['status'] == 'pending') {
          _showSnackBar('채팅 요청을 보냈어요! 알바생이 수락하면 대화할 수 있어요.');
        }

        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) => ChatRoomScreen(
                  chatRoomId:
                      roomId is int ? roomId : int.parse(roomId.toString()),
                  jobInfo: {
                    'id': job.id,
                    'job_id': job.id,
                    'title': job.title,
                    'location_city': job.location,
                    'worker_id': worker.id,
                    'user_name': worker.name,
                    'user_thumbnail_url': worker.profileUrl,
                    'client_id': _myClientId,
                    'client_company_name': _myCompanyName,
                    'client_thumbnail_url': _myThumbnailUrl,
                  },
                ),
          ),
        );
      } else {
        _showSnackBar(data['message']?.toString() ?? '채팅방을 여는 데 실패했어요.');
      }
    } catch (_) {
      if (!mounted) return;
      _showSnackBar('채팅방을 여는 데 실패했어요. 다시 시도해 주세요.');
    }
  }

  // ── 내 공고 주변 알림 보내기 ────────────────

  Future<void> _onNearbyAlertTap() async {
    if (!_isSubscribed) {
      _showSubscribePrompt(reason: '내 공고 주변 알림 보내기는\n구독 멤버십 전용 기능이에요.');
      return;
    }
    final jobs = await _fetchMyActiveJobs();
    if (!mounted) return;

    if (jobs.isEmpty) {
      _showSnackBar('활성 공고가 없어요. 공고를 먼저 등록해 주세요.');
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (_) => _JobPickSheet(
            title: '내 공고 주변 알바생에게 알림 보내기',
            subtitle: '선택한 공고 주변 3km 이내 알바생에게\n공고 알림을 전송해요.',
            jobs: jobs,
            actionLabel: '알림 보내기',
            onSelect: _sendNearbyAlert,
            showInfoBadge: true,
          ),
    );
  }

  Future<void> _sendNearbyAlert(_ClientJob job) async {
    Navigator.pop(context);
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/notification/send-nearby'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'jobId': job.id,
              'clientId': _myClientId,
              'radiusMeters': 3000,
            }),
          )
          .timeout(_MapConst.networkTimeout);

      if (!mounted) return;

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final count = data['sentCount'] ?? data['count'] ?? 0;
        _showSnackBar('주변 알바생 $count명에게 알림을 보냈어요!');
      } else {
        _showSnackBar('알림 발송에 실패했어요. 잠시 후 다시 시도해 주세요.');
      }
    } catch (_) {
      if (!mounted) return;
      _showSnackBar('네트워크 오류가 발생했어요.');
    }
  }

  // ── 내 공고 목록 ────────────────────────────

  Future<List<_ClientJob>> _fetchMyActiveJobs() async {
    if (_myClientId == null) return [];
    try {
      final res = await http
          .get(
            Uri.parse(
              '$baseUrl/api/job/my-jobs?clientId=$_myClientId&status=active',
            ),
          )
          .timeout(_MapConst.networkTimeout);

      if (res.statusCode == 200) {
        final dynamic raw = jsonDecode(res.body);
        final List<dynamic> list =
            raw is List
                ? raw
                : (raw is Map
                    ? ((raw['jobs'] ?? raw['data'] ?? []) as List)
                    : []);
        return list
            .whereType<Map<String, dynamic>>()
            .map(_ClientJob.fromJson)
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // ── 구독 유도 ───────────────────────────────

  void _showSubscribePrompt({String? reason}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SubscribePromptSheet(reason: reason),
    );
  }

  // ── 유틸 ───────────────────────────────────

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            fontSize: 14,
            height: 1.45,
            color: Colors.white,
          ),
        ),
        backgroundColor: _C.textPrimary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── build ──────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return SafeArea(
      top: true,
      bottom: false,
      child: Stack(
        children: [
          // 지도
          _MapLayer(
            mapController: _mapController,
            workers: _workers,
            currentLocation: _currentLocation,
            currentZoom: _currentZoom,
            radiusFilter: _radiusFilter,
            onMapReady: _initLocation,
            onZoomChanged: (z) {
              _debounceTimer?.cancel();
              _debounceTimer = Timer(_MapConst.searchDebounce, () {
                final prev = _MapConst.zoomBucket(_currentZoom);
                final next = _MapConst.zoomBucket(z);
                if (prev != next) {
                  setState(() => _currentZoom = z);
                } else {
                  _currentZoom = z;
                }
              });
            },
            onMarkerTap: _showWorkerSheet,
          ),

          // 검색창
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: _SearchBar(
              controller: _searchController,
              onSubmit: (_) => _searchLocation(),
            ),
          ),

          // 오늘 가능 토글
          Positioned(
            top: 72,
            left: 16,
            right: 16,
            child: _FilterToggle(
              value: _showOnlyAvailableToday,
              onChanged: (val) {
                setState(() => _showOnlyAvailableToday = val);
                _fetchWorkers();
              },
            ),
          ),

          // 반경 필터 칩
          Positioned(
            top: 126,
            left: 16,
            right: 16,
            child: _RadiusChips(
              selected: _radiusFilter,
              hasLocation: _currentLocation != null,
              onSelected: (r) {
                if (r != RadiusFilter.none && _currentLocation == null) {
                  _showSnackBar('위치 정보가 필요해요. 잠시 후 다시 시도해 주세요.');
                  return;
                }
                setState(() => _radiusFilter = r);
                _applyFilters();
              },
            ),
          ),

          // 공고 주변 알림 FAB (위) — 프리미엄
          Positioned(
            right: 16,
            bottom: bottomPad + 136,
            child: _NearbyAlertFab(
              isSubscribed: _isSubscribed,
              onTap: _onNearbyAlertTap,
            ),
          ),

          // 내 위치 FAB (아래)
          Positioned(
            right: 16,
            bottom: bottomPad + 80,
            child: _MyLocationFab(onTap: _goToMyLocation),
          ),

          // 로딩
          if (_isLoading) const Positioned.fill(child: _LoadingOverlay()),

          // 공고 등록 버튼
          Positioned(
            left: 16,
            right: 16,
            bottom: bottomPad + 16,
            child: _PostJobButton(
              onTap: () => Navigator.pushNamed(context, '/post_job'),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 지도 레이어
// ──────────────────────────────────────────────
class _MapLayer extends StatelessWidget {
  const _MapLayer({
    required this.mapController,
    required this.workers,
    required this.currentLocation,
    required this.currentZoom,
    required this.radiusFilter,
    required this.onMapReady,
    required this.onZoomChanged,
    required this.onMarkerTap,
  });

  final MapController mapController;
  final List<WorkerMarkerData> workers;
  final LatLng? currentLocation;
  final double currentZoom;
  final RadiusFilter radiusFilter;
  final VoidCallback onMapReady;
  final ValueChanged<double> onZoomChanged;
  final ValueChanged<WorkerMarkerData> onMarkerTap;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: FlutterMap(
        mapController: mapController,
        options: MapOptions(
          center: _MapConst.seoulCenter,
          zoom: 12,
          minZoom: _MapConst.minZoom,
          maxZoom: _MapConst.maxZoom,
          cameraConstraint: CameraConstraint.contain(
            bounds: _MapConst.koreaBounds,
          ),
          onMapReady: onMapReady,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
          ),
          onMapEvent: (evt) => onZoomChanged(mapController.camera.zoom),
        ),
        children: [
          TileLayer(
            urlTemplate:
                'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
            subdomains: ['a', 'b', 'c', 'd'],
            userAgentPackageName: 'kr.co.iljujob',
          ),

          if (currentLocation != null && radiusFilter != RadiusFilter.none)
            CircleLayer(
              circles: [
                CircleMarker(
                  point: currentLocation!,
                  radius: radiusFilter.meters.toDouble(),
                  useRadiusInMeter: true,
                  color: _C.primary.withOpacity(0.07),
                  borderColor: _C.primary.withOpacity(0.4),
                  borderStrokeWidth: 1.5,
                ),
              ],
            ),

          if (currentLocation != null)
            MarkerLayer(
              markers: [
                Marker(
                  point: currentLocation!,
                  width: 20,
                  height: 20,
                  child: _MyLocationDot(),
                ),
              ],
            ),

          _WorkerMarkerCluster(
            workers: workers,
            currentZoom: currentZoom,
            onMarkerTap: onMarkerTap,
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 내 위치 점
// ──────────────────────────────────────────────
class _MyLocationDot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _C.primary,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: _C.primary.withOpacity(0.35),
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 마커 클러스터
// ──────────────────────────────────────────────
class _WorkerMarkerCluster extends StatelessWidget {
  const _WorkerMarkerCluster({
    required this.workers,
    required this.currentZoom,
    required this.onMarkerTap,
  });

  final List<WorkerMarkerData> workers;
  final double currentZoom;
  final ValueChanged<WorkerMarkerData> onMarkerTap;

  @override
  Widget build(BuildContext context) {
    return MarkerClusterLayerWidget(
      options: MarkerClusterLayerOptions(
        maxClusterRadius: 60,
        size: const Size(44, 44),
        alignment: Alignment.center,
        spiderfyCircleRadius: 60,
        spiderfySpiralDistanceMultiplier: 2,
        showPolygon: false,
        builder: (ctx, cluster) => _ClusterBubble(count: cluster.length),
        markers: _buildMarkers(),
      ),
    );
  }

  List<Marker> _buildMarkers() {
    final size = _MapConst.iconSize(currentZoom);
    return workers
        .map((w) {
          return Marker(
            point: w.position,
            width: size,
            height: size,
            alignment: Alignment.center,
            child: GestureDetector(
              onTap: () => onMarkerTap(w),
              child: _WorkerAvatar(imageUrl: w.profileUrl, size: size),
            ),
          );
        })
        .toList(growable: false);
  }
}

// ──────────────────────────────────────────────
// 클러스터 버블
// ──────────────────────────────────────────────
class _ClusterBubble extends StatelessWidget {
  const _ClusterBubble({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _C.primary,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: _C.primary.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 워커 아바타
// ──────────────────────────────────────────────
class _WorkerAvatar extends StatelessWidget {
  const _WorkerAvatar({required this.imageUrl, required this.size});
  final String imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child:
            imageUrl.isEmpty
                ? _Placeholder(size: size)
                : CachedNetworkImage(
                  imageUrl: imageUrl,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  memCacheWidth: (size * 2).toInt(),
                  memCacheHeight: (size * 2).toInt(),
                  placeholder: (_, __) => _Placeholder(size: size),
                  errorWidget: (_, __, ___) => _Placeholder(size: size),
                ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _C.background,
      child: Icon(
        Icons.person_rounded,
        size: size * 0.55,
        color: _C.textSecondary,
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 내 위치 FAB
// ──────────────────────────────────────────────
class _MyLocationFab extends StatelessWidget {
  const _MyLocationFab({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: _C.surface,
          shape: BoxShape.circle,
          border: Border.all(color: _C.border, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.10),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: const Icon(
          Icons.my_location_rounded,
          color: _C.primary,
          size: 22,
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 내 공고 주변 알림 FAB (프리미엄)
// ──────────────────────────────────────────────
class _NearbyAlertFab extends StatelessWidget {
  const _NearbyAlertFab({required this.isSubscribed, required this.onTap});
  final bool isSubscribed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isSubscribed ? _C.gold : _C.surface,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSubscribed ? _C.gold : _C.border,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: (isSubscribed ? _C.gold : Colors.black).withOpacity(0.15),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              Icons.campaign_rounded,
              color: isSubscribed ? Colors.white : _C.textSecondary,
              size: 22,
            ),
            if (!isSubscribed)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(
                    color: _C.gold,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_rounded,
                    size: 9,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 반경 필터 칩
// ──────────────────────────────────────────────
class _RadiusChips extends StatelessWidget {
  const _RadiusChips({
    required this.selected,
    required this.hasLocation,
    required this.onSelected,
  });

  final RadiusFilter selected;
  final bool hasLocation;
  final ValueChanged<RadiusFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children:
            RadiusFilter.values.map((r) {
              final isSelected = selected == r;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () => onSelected(r),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected ? _C.primary : _C.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? _C.primary : _C.border,
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      r.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: isSelected ? Colors.white : _C.textSecondary,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 워커 바텀시트 (구독/비구독 분기)
// ──────────────────────────────────────────────
class _WorkerBottomSheet extends StatelessWidget {
  const _WorkerBottomSheet({
    required this.worker,
    required this.isSubscribed,
    required this.onViewProfile,
    required this.onStartChat,
    required this.onSubscribePrompt,
  });

  final WorkerMarkerData worker;
  final bool isSubscribed;
  final VoidCallback onViewProfile;
  final VoidCallback onStartChat;
  final VoidCallback onSubscribePrompt;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 20, 24, bottomPad + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 핸들
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: _C.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // 프로필 행
          Row(
            children: [
              _SheetAvatar(url: worker.profileUrl),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      worker.name.isEmpty ? '알바생' : worker.name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _C.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (worker.skills.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        worker.skills,
                        style: const TextStyle(
                          fontSize: 13,
                          color: _C.textSecondary,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (worker.rating != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 15,
                            color: Color(0xFFFFC107),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            worker.rating!.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _C.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // 구독 / 비구독 분기
          if (isSubscribed)
            _SubscriberActions(
              onViewProfile: onViewProfile,
              onStartChat: onStartChat,
            )
          else
            _NonSubscriberBanner(onSubscribe: onSubscribePrompt),
        ],
      ),
    );
  }
}

// 구독자 액션
class _SubscriberActions extends StatelessWidget {
  const _SubscriberActions({
    required this.onViewProfile,
    required this.onStartChat,
  });
  final VoidCallback onViewProfile;
  final VoidCallback onStartChat;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Divider(color: _C.border, height: 1),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onViewProfile,
                icon: const Icon(Icons.person_search_rounded, size: 18),
                label: const Text('프로필 보기'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _C.primary,
                  side: const BorderSide(color: _C.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: onStartChat,
                icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                label: const Text('채팅 시작'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _C.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// 비구독자 배너
class _NonSubscriberBanner extends StatelessWidget {
  const _NonSubscriberBanner({required this.onSubscribe});
  final VoidCallback onSubscribe;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Divider(color: _C.border, height: 1),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _C.goldLight,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _C.gold.withOpacity(0.35)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _C.gold.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.lock_rounded, color: _C.gold, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      '구독 전용 기능',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF856404),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '구독하면 프로필 열람과 채팅을 시작할 수 있어요.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF856404),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: onSubscribe,
            style: ElevatedButton.styleFrom(
              backgroundColor: _C.gold,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.workspace_premium_rounded, size: 18),
                SizedBox(width: 6),
                Text(
                  '구독하고 시작하기',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// 아바타 (바텀시트용)
class _SheetAvatar extends StatelessWidget {
  const _SheetAvatar({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _C.border, width: 1.5),
      ),
      child: ClipOval(
        child:
            url.isEmpty
                ? Container(
                  color: _C.background,
                  child: const Icon(
                    Icons.person_rounded,
                    size: 34,
                    color: _C.textSecondary,
                  ),
                )
                : CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: _C.background),
                  errorWidget:
                      (_, __, ___) => Container(
                        color: _C.background,
                        child: const Icon(
                          Icons.person_rounded,
                          size: 34,
                          color: _C.textSecondary,
                        ),
                      ),
                ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 공고 선택 시트 (채팅 / 알림 공용)
// ──────────────────────────────────────────────
class _JobPickSheet extends StatelessWidget {
  const _JobPickSheet({
    required this.title,
    required this.subtitle,
    required this.jobs,
    required this.actionLabel,
    required this.onSelect,
    this.showInfoBadge = false,
  });

  final String title;
  final String subtitle;
  final List<_ClientJob> jobs;
  final String actionLabel;
  final ValueChanged<_ClientJob> onSelect;
  final bool showInfoBadge;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.72,
      ),
      decoration: const BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 핸들
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 16),
            decoration: BoxDecoration(
              color: _C.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // 헤더
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _C.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: _C.textSecondary,
                    height: 1.4,
                  ),
                ),
                if (showInfoBadge) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _C.primaryLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 14,
                          color: _C.primary,
                        ),
                        SizedBox(width: 5),
                        Text(
                          '하루 최대 3회 발송 · 구독자 전용',
                          style: TextStyle(
                            fontSize: 12,
                            color: _C.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          const Divider(color: _C.border, height: 1),

          // 공고 목록
          Flexible(
            child: ListView.separated(
              padding: EdgeInsets.fromLTRB(16, 10, 16, bottomPad + 16),
              shrinkWrap: true,
              itemCount: jobs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder:
                  (_, i) => _JobPickTile(
                    job: jobs[i],
                    actionLabel: actionLabel,
                    onTap: () => onSelect(jobs[i]),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JobPickTile extends StatelessWidget {
  const _JobPickTile({
    required this.job,
    required this.actionLabel,
    required this.onTap,
  });

  final _ClientJob job;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _C.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _C.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // 아이콘
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _C.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.work_rounded,
                  color: _C.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              // 공고 정보
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _C.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${job.location}'
                      '${job.startDate.isNotEmpty ? '  ·  ${job.startDate}' : ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: _C.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 버튼
              ElevatedButton(
                onPressed: onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _C.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 구독 유도 바텀시트
// ──────────────────────────────────────────────
class _SubscribePromptSheet extends StatelessWidget {
  const _SubscribePromptSheet({this.reason});
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 20, 24, bottomPad + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 핸들
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: _C.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // 골드 아이콘
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: _C.goldLight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.workspace_premium_rounded,
              color: _C.gold,
              size: 34,
            ),
          ),
          const SizedBox(height: 16),

          const Text(
            '구독 멤버십 전용',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _C.textPrimary,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            reason ?? '구독하면 알바생 프로필 열람,\n채팅 시작, 공고 주변 알림 보내기를 사용할 수 있어요.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: _C.textSecondary,
              height: 1.55,
            ),
          ),

          const SizedBox(height: 24),

          _BenefitRow(
            icon: Icons.person_search_rounded,
            color: _C.primary,
            label: '알바생 프로필 전체 열람',
          ),
          _BenefitRow(
            icon: Icons.chat_bubble_rounded,
            color: Color(0xFF10B981),
            label: '알바생에게 직접 채팅 시작',
          ),
          _BenefitRow(
            icon: Icons.campaign_rounded,
            color: _C.gold,
            label: '내 공고 주변 알바생 알림 보내기',
          ),

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/subscribe');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _C.gold,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                '지금 구독하기',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              '나중에',
              style: TextStyle(
                color: _C.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({
    required this.icon,
    required this.color,
    required this.label,
  });
  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: _C.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.check_rounded, size: 16, color: Color(0xFF10B981)),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 검색바
// ──────────────────────────────────────────────
class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onSubmit});
  final TextEditingController controller;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _C.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        onSubmitted: onSubmit,
        style: const TextStyle(
          fontSize: 15,
          color: _C.textPrimary,
          fontWeight: FontWeight.w500,
        ),
        decoration: const InputDecoration(
          hintText: '위치, 지하철역, 동 이름 검색',
          hintStyle: TextStyle(
            fontSize: 15,
            color: _C.textSecondary,
            fontWeight: FontWeight.w400,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: _C.textSecondary,
            size: 22,
          ),
          contentPadding: EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 오늘 가능 토글
// ──────────────────────────────────────────────
class _FilterToggle extends StatelessWidget {
  const _FilterToggle({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          _Seg(label: '전체', selected: !value, onTap: () => onChanged(false)),
          _Seg(label: '오늘 가능', selected: value, onTap: () => onChanged(true)),
        ],
      ),
    );
  }
}

class _Seg extends StatelessWidget {
  const _Seg({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? _C.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? Colors.white : _C.textSecondary,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 로딩 오버레이
// ──────────────────────────────────────────────
class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white.withOpacity(0.7),
      child: const Center(
        child: CircularProgressIndicator(strokeWidth: 2.5, color: _C.primary),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 공고 등록 버튼
// ──────────────────────────────────────────────
class _PostJobButton extends StatelessWidget {
  const _PostJobButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: _C.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, size: 20, color: Colors.white),
            SizedBox(width: 6),
            Text(
              '공고 등록하기',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
