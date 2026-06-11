// worker_map_view.dart — 공고 중심 지도 (긴급호출 통합)
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:iljujob/config/constants.dart';
import 'package:iljujob/presentation/chat/chat_room_screen.dart';
import 'nearby_workers_screen.dart';

// ── 디자인 토큰 ───────────────────────────────────────────────────
const _primary  = Color(0xFF3B8AFF);
const _surface  = Color(0xFFFFFFFF);
const _border   = Color(0xFFE5E8EB);
const _textMain = Color(0xFF191F28);
const _textSub  = Color(0xFF6B7280);
const _red      = Color(0xFFEF4444);
const _green    = Color(0xFF22C55E);
const _orange   = Color(0xFFFF6B00);

// ── 공고 모델 ─────────────────────────────────────────────────────
class _JobPin {
  final int    id;
  final String title;
  final String location;
  final String status;
  final double lat;
  final double lng;
  final int    hourlyWage;
  final String startDate;
  final int    applicantCount;
  final bool   isPinnedNow;

  const _JobPin({
    required this.id,
    required this.title,
    required this.location,
    required this.status,
    required this.lat,
    required this.lng,
    required this.hourlyWage,
    required this.startDate,
    required this.applicantCount,
    required this.isPinnedNow,
  });

  factory _JobPin.fromJson(Map<String, dynamic> j) => _JobPin(
        id:             _i(j['id'] ?? j['job_id']),
        title:          (j['title'] ?? j['job_title'] ?? '').toString(),
        location:       (j['location_city'] ?? j['location'] ?? '').toString(),
        status:         (j['status'] ?? 'active').toString(),
        lat:            _d(j['lat']),
        lng:            _d(j['lng']),
        hourlyWage:     _i(j['hourly_wage'] ?? j['wage']),
        startDate:      _dateStr(j['start_date']),
        applicantCount: _i(j['applicant_count'] ?? j['applicants']),
        isPinnedNow:    j['is_pinned_now'] == true || j['is_pinned_now'] == 1,
      );

  static double _d(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  static int _i(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static String _dateStr(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  bool get hasLocation => lat != 0.0 && lng != 0.0;
  LatLng get position  => LatLng(lat, lng);

  Color get pinColor {
    if (isPinnedNow)          return _orange;
    if (status == 'active')   return _green;
    if (status == 'reserved') return _primary;
    return _textSub;
  }

  String get statusLabel {
    if (isPinnedNow)          return '긴급';
    if (status == 'active')   return '진행중';
    if (status == 'reserved') return '예약';
    if (status == 'closed')   return '마감';
    return status;
  }
}

// ── 발송 이력 모델 ────────────────────────────────────────────────
class _SentLog {
  final int    logId;
  final int    workerId;
  final String workerName;
  final String? profileUrl;
  final int    activityScore;
  final String status;
  final int?   chatRoomId;

  const _SentLog({
    required this.logId,
    required this.workerId,
    required this.workerName,
    this.profileUrl,
    required this.activityScore,
    required this.status,
    this.chatRoomId,
  });

  factory _SentLog.fromJson(Map<String, dynamic> j) => _SentLog(
        logId:         _i(j['id']),
        workerId:      _i(j['worker_id']),
        workerName:    (j['worker_name'] ?? j['name'] ?? '').toString(),
        profileUrl:    j['profile_image_url']?.toString(),
        activityScore: _i(j['activity_score']),
        status:        (j['status'] ?? 'sent').toString(),
        chatRoomId:    j['chat_room_id'] != null ? _i(j['chat_room_id']) : null,
      );

  static int _i(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  Color get statusColor {
    switch (status) {
      case 'accepted':      return _green;
      case 'time_adjusted': return _primary;
      case 'rejected':      return _red;
      case 'no_response':   return _textSub;
      default:              return _orange;
    }
  }

  String get statusLabel {
    switch (status) {
      case 'sent':          return '대기중';
      case 'accepted':      return '수락됨';
      case 'time_adjusted': return '시간조정';
      case 'rejected':      return '거절됨';
      case 'no_response':   return '무응답';
      default:              return status;
    }
  }

  bool get canChat => status != 'rejected' && status != 'no_response';
}

// ── 메인 위젯 ─────────────────────────────────────────────────────
class WorkerMapView extends StatefulWidget {
  const WorkerMapView({super.key});

  @override
  State<WorkerMapView> createState() => _WorkerMapViewState();
}

class _WorkerMapViewState extends State<WorkerMapView> {
  final _mapCtrl = MapController();

  List<_JobPin> _allJobs    = [];
  List<_JobPin> _mappedJobs = [];   // lat/lng 있는 공고
  List<_JobPin> _unmapped   = [];   // lat/lng 없는 공고 (하단 목록)
  bool          _loading    = true;
  int?          _clientId;
  String?       _authToken;
  String        _companyName = '';
  String        _thumbnailUrl = '';
  LatLng?       _myLocation;
  bool          _isSubscribed = false;

  // 캐시
  final Map<int, int>         _nearbyCountCache = {};
  final Map<int, List<_SentLog>> _sentCache     = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _clientId    = prefs.getInt('userId');
    _authToken   = prefs.getString('authToken') ?? '';
    _companyName = prefs.getString('companyName') ?? '';
    _thumbnailUrl = prefs.getString('profileImageUrl') ?? '';
    await Future.wait([_fetchJobs(), _fetchSubscription(), _initLocation()]);
  }

  // ── 구독 상태 ─────────────────────────────────────────────────
  Future<void> _fetchSubscription() async {
    if (_authToken == null || _authToken!.isEmpty) return;
    try {
      final res = await http
          .get(
            Uri.parse('$baseUrl/api/subscription/status'),
            headers: {'Authorization': 'Bearer $_authToken'},
          )
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 200 && mounted) {
        final d = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() => _isSubscribed = d['active'] == true);
      }
    } catch (_) {}
  }

  // ── 내 공고 로딩 ──────────────────────────────────────────────
  Future<void> _fetchJobs() async {
    if (_clientId == null) return;
    if (mounted) setState(() => _loading = true);
    try {
      final res = await http
          .get(Uri.parse(
              '$baseUrl/api/job/my-jobs?clientId=$_clientId&limit=50'))
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final dynamic raw = jsonDecode(res.body);
        final List<dynamic> list = raw is List
            ? raw
            : (raw is Map ? ((raw['jobs'] ?? raw['data'] ?? []) as List) : []);
        final jobs = list
            .whereType<Map<String, dynamic>>()
            .map(_JobPin.fromJson)
            .where((j) => j.status != 'deleted' && j.status != 'closed')
            .toList();
        setState(() {
          _allJobs    = jobs;
          _mappedJobs = jobs.where((j) => j.hasLocation).toList();
          _unmapped   = jobs.where((j) => !j.hasLocation).toList();
          _loading    = false;
        });
        // 초기 포커스: 긴급공고 우선 → 최신 공고 → 내 위치
        WidgetsBinding.instance.addPostFrameCallback((_) => _setInitialFocus());
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } on TimeoutException {
      if (mounted) setState(() => _loading = false);
    } on SocketException {
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setInitialFocus() {
    // 우선순위: 긴급/핀된 공고 → 최신 위치 공고 → 내 위치
    _JobPin? focal = _mappedJobs.firstWhere(
      (j) => j.isPinnedNow,
      orElse: () => _mappedJobs.isNotEmpty ? _mappedJobs.first : _JobPin(
        id: 0, title: '', location: '', status: '', lat: 0, lng: 0,
        hourlyWage: 0, startDate: '', applicantCount: 0, isPinnedNow: false,
      ),
    );

    if (focal.hasLocation) {
      _mapCtrl.move(focal.position, 14);
    } else if (_myLocation != null) {
      _mapCtrl.move(_myLocation!, 13);
    }
  }

  // ── 위치 ──────────────────────────────────────────────────────
  Future<void> _initLocation() async {
    final loc = await _getLocation();
    if (loc != null && mounted) setState(() => _myLocation = loc);
  }

  Future<LatLng?> _getLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) return null;
    }
    if (perm == LocationPermission.deniedForever) return null;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
      ).timeout(const Duration(seconds: 4));
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }

  // ── 반경 내 가능 인원 ──────────────────────────────────────────
  Future<int> _nearbyCount(int jobId) async {
    if (_nearbyCountCache.containsKey(jobId)) return _nearbyCountCache[jobId]!;
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/api/direct-messages/nearby-count?jobId=$jobId'))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final count = (jsonDecode(res.body)['count'] as num?)?.toInt() ?? 0;
        _nearbyCountCache[jobId] = count;
        return count;
      }
    } catch (_) {}
    return 0;
  }

  // ── 발송 이력 ─────────────────────────────────────────────────
  Future<List<_SentLog>> _sentHistory(int jobId) async {
    if (_sentCache.containsKey(jobId)) return _sentCache[jobId]!;
    try {
      final res = await http
          .get(Uri.parse(
              '$baseUrl/api/direct-messages/sent-history?clientId=$_clientId&jobId=$jobId'))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final logs = (jsonDecode(res.body)['logs'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(_SentLog.fromJson)
            .toList();
        _sentCache[jobId] = logs;
        return logs;
      }
    } catch (_) {}
    return [];
  }

  // ── 공고 탭 ───────────────────────────────────────────────────
  void _onPinTap(_JobPin job) async {
    final results = await Future.wait([
      _nearbyCount(job.id),
      _sentHistory(job.id),
    ]);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _JobSheet(
        job:          job,
        nearbyCount:  results[0] as int,
        sentLogs:     results[1] as List<_SentLog>,
        isSubscribed: _isSubscribed,
        clientId:     _clientId ?? 0,
        companyName:  _companyName,
        thumbnailUrl: _thumbnailUrl,
        onUrgentCall: () {
          Navigator.pop(context);
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => NearbyWorkersScreen(
              jobId:    job.id,
              clientId: _clientId ?? 0,
              jobTitle: job.title,
            ),
          )).then((_) {
            _sentCache.remove(job.id);       // 발송 이력 캐시 무효화
            _nearbyCountCache.remove(job.id);
          });
        },
        onViewApplicants: () {
          Navigator.pop(context);
          Navigator.pushNamed(context, '/applicants');
        },
      ),
    );
  }

  // ── build ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    // 하단 공고 리스트 높이: 위치 없는 공고 있을 때만
    final hasUnmapped   = _unmapped.isNotEmpty;
    final listH         = hasUnmapped ? 72.0 : 0.0;
    final bottomBtnH    = 60.0;
    final fabBottom     = bottomPad + listH + bottomBtnH + 16;

    return Stack(
      children: [
        // ── 지도 ─────────────────────────────────────────────────
        Positioned.fill(
          bottom: bottomPad + listH + bottomBtnH,
          child: FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: _myLocation ?? const LatLng(37.5665, 126.9780),
              initialZoom: 13,
              minZoom: 7,
              maxZoom: 19,
              cameraConstraint: CameraConstraint.contain(
                bounds: LatLngBounds(
                  const LatLng(33.0, 124.5),
                  const LatLng(38.7, 132.1),
                ),
              ),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              // OSM 타일 (안정적)
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'kr.co.albailju',
                tileBuilder: (ctx, child, tile) => child,
                errorTileCallback: (tile, err, stack) {},
              ),
              // 내 위치
              if (_myLocation != null)
                MarkerLayer(markers: [
                  Marker(
                    point: _myLocation!,
                    width: 18, height: 18,
                    child: Container(
                      decoration: BoxDecoration(
                        color: _primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: _primary.withValues(alpha: 0.4),
                            blurRadius: 8, spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                ]),
              // 공고 핀
              MarkerLayer(
                markers: _mappedJobs.map((job) => Marker(
                  point: job.position,
                  width: 80, height: 70,
                  alignment: Alignment.topCenter,
                  child: GestureDetector(
                    onTap: () => _onPinTap(job),
                    child: _JobMarker(job: job),
                  ),
                )).toList(),
              ),
            ],
          ),
        ),

        // ── 공고 없음 안내 ────────────────────────────────────────
        if (!_loading && _mappedJobs.isEmpty)
          Positioned(
            top: 16, left: 24, right: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 3))],
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: _textSub, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _allJobs.isEmpty
                          ? '등록된 공고가 없어요. 공고를 등록해 주세요.'
                          : '위치 정보 없는 공고 ${_unmapped.length}개는 아래 목록에서 확인하세요.',
                      style: const TextStyle(fontSize: 12, color: _textSub),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // ── 로딩 ─────────────────────────────────────────────────
        if (_loading)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x55FFFFFF),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.5, color: _primary)),
            ),
          ),

        // ── 우측 FAB ─────────────────────────────────────────────
        Positioned(
          right: 16,
          bottom: fabBottom,
          child: Column(
            children: [
              _Fab(icon: Icons.my_location_rounded, onTap: _goToMyLocation),
              const SizedBox(height: 10),
              _Fab(icon: Icons.fit_screen_rounded,  onTap: _mappedJobs.isNotEmpty ? _fitBounds : null),
              const SizedBox(height: 10),
              _Fab(icon: Icons.refresh_rounded,     onTap: () { _sentCache.clear(); _nearbyCountCache.clear(); _fetchJobs(); }),
            ],
          ),
        ),

        // ── 위치 없는 공고 목록 (하단 스크롤) ────────────────────
        if (hasUnmapped)
          Positioned(
            left: 0, right: 0,
            bottom: bottomPad + bottomBtnH,
            child: SizedBox(
              height: listH,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                itemCount: _unmapped.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final job = _unmapped[i];
                  return GestureDetector(
                    onTap: () => _onPinTap(job),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: job.pinColor.withValues(alpha: 0.4)),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.work_rounded, size: 14, color: job.pinColor),
                          const SizedBox(width: 6),
                          Text(
                            job.title.length > 14 ? '${job.title.substring(0, 14)}…' : job.title,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _textMain),
                          ),
                          if (job.applicantCount > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: _primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
                              child: Text('${job.applicantCount}명', style: const TextStyle(fontSize: 10, color: _primary, fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

        // ── 공고 등록 버튼 ────────────────────────────────────────
        Positioned(
          left: 16, right: 16,
          bottom: bottomPad + 8,
          child: SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/post_job').then((_) => _fetchJobs()),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('공고 등록하기', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ],
    );
  }

  // ── FAB 헬퍼 ─────────────────────────────────────────────────
  Future<void> _goToMyLocation() async {
    if (_myLocation != null) {
      _mapCtrl.move(_myLocation!, 14);
      return;
    }
    final loc = await _getLocation();
    if (loc != null && mounted) {
      setState(() => _myLocation = loc);
      _mapCtrl.move(loc, 14);
    }
  }

  void _fitBounds() {
    if (_mappedJobs.isEmpty) return;
    final lats = _mappedJobs.map((j) => j.lat);
    final lngs = _mappedJobs.map((j) => j.lng);
    _mapCtrl.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds(
        LatLng(lats.reduce((a, b) => a < b ? a : b) - 0.01,
               lngs.reduce((a, b) => a < b ? a : b) - 0.01),
        LatLng(lats.reduce((a, b) => a > b ? a : b) + 0.01,
               lngs.reduce((a, b) => a > b ? a : b) + 0.01),
      ),
      padding: const EdgeInsets.all(60),
    ));
  }
}

// ── 공고 마커 ─────────────────────────────────────────────────────
class _JobMarker extends StatelessWidget {
  final _JobPin job;
  const _JobMarker({required this.job});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: job.pinColor,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(color: job.pinColor.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 3)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                job.title.length > 9 ? '${job.title.substring(0, 9)}…' : job.title,
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
              ),
              if (job.applicantCount > 0)
                Text(
                  '지원 ${job.applicantCount}명',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 9),
                ),
            ],
          ),
        ),
        // 핀 꼬리
        Transform.rotate(
          angle: 0.785,
          child: Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              color: job.pinColor,
              borderRadius: const BorderRadius.only(bottomRight: Radius.circular(2)),
            ),
          ),
        ),
      ],
    );
  }
}

// ── FAB ──────────────────────────────────────────────────────────
class _Fab extends StatelessWidget {
  final IconData      icon;
  final VoidCallback? onTap;
  const _Fab({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: _surface,
            shape: BoxShape.circle,
            border: Border.all(color: _border),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 3))],
          ),
          child: Icon(icon, color: onTap != null ? _primary : _textSub, size: 22),
        ),
      );
}

// ── 공고 상세 바텀시트 ────────────────────────────────────────────
class _JobSheet extends StatefulWidget {
  final _JobPin       job;
  final int           nearbyCount;
  final List<_SentLog> sentLogs;
  final bool          isSubscribed;
  final int           clientId;
  final String        companyName;
  final String        thumbnailUrl;
  final VoidCallback  onUrgentCall;
  final VoidCallback  onViewApplicants;

  const _JobSheet({
    required this.job,
    required this.nearbyCount,
    required this.sentLogs,
    required this.isSubscribed,
    required this.clientId,
    required this.companyName,
    required this.thumbnailUrl,
    required this.onUrgentCall,
    required this.onViewApplicants,
  });

  @override
  State<_JobSheet> createState() => _JobSheetState();
}

class _JobSheetState extends State<_JobSheet> {
  bool _sentExpanded = false;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final job = widget.job;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: const BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 핸들
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              decoration: BoxDecoration(color: _border, borderRadius: BorderRadius.circular(2)),
            ),
          ),

          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPad + 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 공고 헤더 ───────────────────────────────────
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: job.pinColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(job.statusLabel,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: job.pinColor)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(job.title,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _textMain),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12, runSpacing: 4,
                    children: [
                      if (job.location.isNotEmpty) _meta(Icons.location_on_rounded, job.location),
                      if (job.startDate.isNotEmpty) _meta(Icons.calendar_today_rounded, job.startDate),
                      if (job.hourlyWage > 0)       _meta(Icons.payments_rounded, '시급 ${_comma(job.hourlyWage)}원'),
                    ],
                  ),

                  const SizedBox(height: 14),
                  const Divider(color: _border, height: 1),
                  const SizedBox(height: 14),

                  // ── 반경 내 가능 인원 ───────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F0FF),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _primary.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(color: _primary, borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.people_rounded, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('반경 3km 내 오늘 가능한 알바생',
                                style: TextStyle(fontSize: 11, color: _textSub)),
                            const SizedBox(height: 2),
                            RichText(
                              text: TextSpan(children: [
                                TextSpan(
                                  text: '${widget.nearbyCount}명',
                                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _primary),
                                ),
                                const TextSpan(
                                  text: ' 연락 가능',
                                  style: TextStyle(fontSize: 13, color: _textSub, fontWeight: FontWeight.w500),
                                ),
                              ]),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // ── 긴급 호출 / 구독 상태 표시 ──────────────────
                  if (widget.isSubscribed)
                    _chatGateBadge(
                      icon: Icons.verified_rounded,
                      label: '구독 중 · 긴급 호출 크레딧으로 메시지 발송 가능',
                      color: _green,
                    )
                  else
                    _chatGateBadge(
                      icon: Icons.info_outline_rounded,
                      label: '긴급 호출 이용권으로 알바생에게 직접 연락하세요',
                      color: _textSub,
                    ),

                  const SizedBox(height: 12),

                  // ── 발송 이력 ───────────────────────────────────
                  if (widget.sentLogs.isNotEmpty) ...[
                    GestureDetector(
                      onTap: () => setState(() => _sentExpanded = !_sentExpanded),
                      child: Row(
                        children: [
                          const Icon(Icons.send_rounded, size: 15, color: _orange),
                          const SizedBox(width: 6),
                          Text('발송 이력 · ${widget.sentLogs.length}명',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _textMain)),
                          const Spacer(),
                          Icon(
                            _sentExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                            size: 18, color: _textSub,
                          ),
                        ],
                      ),
                    ),
                    if (_sentExpanded) ...[
                      const SizedBox(height: 8),
                      ...widget.sentLogs.map((log) => _SentLogTile(
                        log: log,
                        job: job,
                        clientId: widget.clientId,
                        companyName: widget.companyName,
                        thumbnailUrl: widget.thumbnailUrl,
                        onClose: () => Navigator.pop(context),
                      )),
                    ],
                    const SizedBox(height: 12),
                    const Divider(color: _border, height: 1),
                    const SizedBox(height: 12),
                  ],

                  // ── 액션 버튼 ───────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: widget.onViewApplicants,
                          icon: const Icon(Icons.people_outline_rounded, size: 17),
                          label: Text('지원자 ${job.applicantCount}명'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _primary,
                            side: const BorderSide(color: _primary),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: widget.nearbyCount > 0 ? widget.onUrgentCall : null,
                          icon: const Icon(Icons.emergency_rounded, size: 17),
                          label: const Text('긴급 호출'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _red,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(0xFFD1D5DB),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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

  static Widget _chatGateBadge({required IconData icon, required String label, required Color color}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500))),
          ],
        ),
      );

  static Widget _meta(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: _textSub),
          const SizedBox(width: 3),
          Text(text, style: const TextStyle(fontSize: 13, color: _textSub)),
        ],
      );

  static String _comma(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

// ── 발송 이력 타일 ────────────────────────────────────────────────
class _SentLogTile extends StatelessWidget {
  final _SentLog   log;
  final _JobPin    job;
  final int        clientId;
  final String     companyName;
  final String     thumbnailUrl;
  final VoidCallback onClose;

  const _SentLogTile({
    required this.log,
    required this.job,
    required this.clientId,
    required this.companyName,
    required this.thumbnailUrl,
    required this.onClose,
  });

  void _openChat(BuildContext context) async {
    int? roomId = log.chatRoomId;

    // chat_room_id가 없으면 API로 조회
    if (roomId == null) {
      try {
        final res = await http.get(Uri.parse(
            '$baseUrl/api/chat/get-room?jobId=${job.id}&workerId=${log.workerId}'));
        if (res.statusCode == 200) {
          roomId = jsonDecode(res.body)['chatRoomId'] as int?;
        }
      } catch (_) {}
    }

    if (!context.mounted) return;

    if (roomId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('채팅방을 찾을 수 없어요.')));
      return;
    }

    onClose();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatRoomScreen(
          chatRoomId: roomId!,
          jobInfo: {
            'id': job.id, 'job_id': job.id,
            'title': job.title,
            'location_city': job.location,
            'worker_id': log.workerId,
            'user_name': log.workerName,
            'user_thumbnail_url': log.profileUrl,
            'client_id': clientId,
            'client_company_name': companyName,
            'client_thumbnail_url': thumbnailUrl,
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundImage: log.profileUrl != null && log.profileUrl!.isNotEmpty
                ? NetworkImage(log.profileUrl!)
                : null,
            backgroundColor: const Color(0xFFE8F0FF),
            child: (log.profileUrl == null || log.profileUrl!.isEmpty)
                ? Text(
                    log.workerName.isNotEmpty ? log.workerName[0] : '?',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _primary),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(log.workerName,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _textMain)),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: log.statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(log.statusLabel,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: log.statusColor)),
                ),
              ],
            ),
          ),
          if (log.canChat)
            GestureDetector(
              onTap: () => _openChat(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: _primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('채팅',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
        ],
      ),
    );
  }
}
