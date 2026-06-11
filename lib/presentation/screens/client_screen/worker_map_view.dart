// worker_map_view.dart — 공고 지도 (깔끔 리디자인)
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
import 'nearby_workers_screen.dart';

// ── 디자인 토큰 ───────────────────────────────────────────────────
const _primary  = Color(0xFF3B8AFF);
const _border   = Color(0xFFE5E8EB);
const _textMain = Color(0xFF191F28);
const _textSub  = Color(0xFF6B7280);
const _red      = Color(0xFFFF3B30);
const _green    = Color(0xFF22C55E);
const _orange   = Color(0xFFFF6B00);
const _purple   = Color(0xFF8B5CF6);

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
    required this.id,    required this.title,
    required this.location, required this.status,
    required this.lat,   required this.lng,
    required this.hourlyWage, required this.startDate,
    required this.applicantCount, required this.isPinnedNow,
  });

  factory _JobPin.fromJson(Map<String, dynamic> j) => _JobPin(
    id: _i(j['id'] ?? j['job_id']),
    title: (j['title'] ?? j['job_title'] ?? '').toString(),
    location: (j['location_city'] ?? j['location'] ?? '').toString(),
    status: (j['status'] ?? 'active').toString(),
    lat: _d(j['lat']), lng: _d(j['lng']),
    hourlyWage: _i(j['hourly_wage'] ?? j['wage']),
    startDate: _ds(j['start_date']),
    applicantCount: _i(j['applicant_count'] ?? j['applicants']),
    isPinnedNow: j['is_pinned_now'] == true || j['is_pinned_now'] == 1,
  );

  static double _d(dynamic v) { if (v is num) return v.toDouble(); if (v is String) return double.tryParse(v) ?? 0.0; return 0.0; }
  static int    _i(dynamic v) { if (v is int) return v; if (v is num) return v.toInt(); if (v is String) return int.tryParse(v) ?? 0; return 0; }
  static String _ds(dynamic v) { if (v == null) return ''; final s = v.toString(); return s.length >= 10 ? s.substring(0, 10) : s; }

  bool   get hasLocation => lat != 0.0 && lng != 0.0;
  LatLng get position    => LatLng(lat, lng);

  Color get pinColor {
    if (isPinnedNow) return _red;
    if (status == 'active') return _primary;
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

// ── 구직자 핀 모델 ────────────────────────────────────────────────
class _WorkerDot {
  final int    id;
  final String name;
  final double lat;
  final double lng;
  final int    activityScore;

  const _WorkerDot({
    required this.id, required this.name,
    required this.lat, required this.lng,
    required this.activityScore,
  });

  factory _WorkerDot.fromJson(Map<String, dynamic> j) => _WorkerDot(
    id: _i(j['id']),
    name: (j['name'] ?? '').toString(),
    lat: _d(j['lat']), lng: _d(j['lng']),
    activityScore: _i(j['activity_score']),
  );

  static double _d(dynamic v) { if (v is num) return v.toDouble(); if (v is String) return double.tryParse(v) ?? 0.0; return 0.0; }
  static int    _i(dynamic v) { if (v is int) return v; if (v is num) return v.toInt(); if (v is String) return int.tryParse(v) ?? 0; return 0; }

  bool   get hasLocation => lat != 0.0 && lng != 0.0;
  LatLng get position    => LatLng(lat, lng);

  String get grade {
    if (activityScore >= 100) return 'S';
    if (activityScore >= 70)  return 'A';
    if (activityScore >= 40)  return 'B';
    if (activityScore >= 20)  return 'C';
    return 'N';
  }

  Color get gradeColor {
    switch (grade) {
      case 'S': return _orange;
      case 'A': return _primary;
      case 'B': return _green;
      default:  return _textSub;
    }
  }
}

// ── 메인 위젯 ─────────────────────────────────────────────────────
class WorkerMapView extends StatefulWidget {
  const WorkerMapView({super.key});

  @override
  State<WorkerMapView> createState() => _WorkerMapViewState();
}

class _WorkerMapViewState extends State<WorkerMapView> {
  final _mapCtrl  = MapController();
  final _scrollCtrl = ScrollController();

  List<_JobPin>    _jobs        = [];
  List<_WorkerDot> _workerDots  = [];
  int?             _selectedIdx;       // 선택된 job index
  bool             _loading     = true;
  bool             _workersLoading = false;
  bool             _isSubscribed    = false;
  bool             _broadcastSending = false;
  int              _selectedWorkerCount = 0;

  int?    _clientId;
  String? _authToken;
  LatLng? _myLocation;

  final Map<int, int>          _countCache   = {};
  final Map<int, List<_WorkerDot>> _dotCache = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _clientId  = prefs.getInt('userId');
    _authToken = prefs.getString('authToken') ?? '';
    await Future.wait([_fetchJobs(), _fetchSubscription(), _initLocation()]);
  }

  Map<String, String> get _auth =>
      _authToken != null && _authToken!.isNotEmpty
          ? {'Authorization': 'Bearer $_authToken'}
          : {};

  // ── 구독 상태 ─────────────────────────────────────────────────
  Future<void> _fetchSubscription() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/api/subscription/status'),
        headers: _auth,
      ).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200 && mounted) {
        setState(() => _isSubscribed =
            (jsonDecode(res.body) as Map<String, dynamic>)['active'] == true);
      }
    } catch (_) {}
  }

  // ── 내 공고 ───────────────────────────────────────────────────
  Future<void> _fetchJobs() async {
    if (_clientId == null) return;
    if (mounted) setState(() => _loading = true);
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/api/job/my-jobs?clientId=$_clientId&limit=50'))
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final raw = jsonDecode(res.body);
        final list = raw is List
            ? raw
            : (raw is Map ? ((raw['jobs'] ?? raw['data'] ?? []) as List) : []);
        final jobs = list
            .whereType<Map<String, dynamic>>()
            .map(_JobPin.fromJson)
            .where((j) => j.status != 'deleted' && j.status != 'closed')
            .toList();

        // 핀된 공고 우선 정렬
        jobs.sort((a, b) {
          if (a.isPinnedNow && !b.isPinnedNow) return -1;
          if (!a.isPinnedNow && b.isPinnedNow) return 1;
          return 0;
        });

        setState(() {
          _jobs    = jobs;
          _loading = false;
        });

        // 첫 공고 자동 선택
        if (jobs.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _selectJob(0));
        }
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

  // ── 위치 ──────────────────────────────────────────────────────
  Future<void> _initLocation() async {
    final loc = await _getLocation();
    if (loc != null && mounted) setState(() => _myLocation = loc);
  }

  Future<LatLng?> _getLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
      ).timeout(const Duration(seconds: 4));
      return LatLng(p.latitude, p.longitude);
    } catch (_) { return null; }
  }

  // ── 공고 선택 ─────────────────────────────────────────────────
  Future<void> _selectJob(int idx) async {
    if (idx < 0 || idx >= _jobs.length) return;
    final job = _jobs[idx];

    setState(() {
      _selectedIdx         = idx;
      _workerDots          = [];
      _selectedWorkerCount = 0;
    });

    // 카메라 이동
    if (job.hasLocation) {
      _mapCtrl.move(job.position, 13.5);
    }

    // 구직자 핀 + 인원수 병렬 로드
    if (job.hasLocation) {
      setState(() => _workersLoading = true);
      final results = await Future.wait([
        _dotCache.containsKey(job.id)
            ? Future.value(_dotCache[job.id]!)
            : _fetchWorkers(job.id),
        _nearbyCount(job.id),
      ]);
      if (mounted) {
        setState(() {
          _workerDots          = results[0] as List<_WorkerDot>;
          _selectedWorkerCount = results[1] as int;
          _workersLoading      = false;
        });
      }
    }
  }

  Future<List<_WorkerDot>> _fetchWorkers(int jobId) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/api/direct-messages/nearby-workers?jobId=$jobId&radius=10000'),
        headers: _auth,
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final dots = (jsonDecode(res.body)['workers'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(_WorkerDot.fromJson)
            .where((d) => d.hasLocation)
            .toList();
        _dotCache[jobId] = dots;
        return dots;
      }
    } catch (_) {}
    return [];
  }

  Future<int> _nearbyCount(int jobId) async {
    if (_countCache.containsKey(jobId)) return _countCache[jobId]!;
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/api/direct-messages/nearby-count?jobId=$jobId&radius=10000'),
        headers: _auth,
      ).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final count = (jsonDecode(res.body)['count'] as num?)?.toInt() ?? 0;
        _countCache[jobId] = count;
        return count;
      }
    } catch (_) {}
    return 0;
  }

  // ── 공고 알림 발송 (구독자 전용) ─────────────────────────────
  Future<void> _sendBroadcast(int jobId) async {
    if (_broadcastSending) return;
    setState(() => _broadcastSending = true);
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/notification-settings/send-nearby'),
        headers: {..._auth, 'Content-Type': 'application/json'},
        body: jsonEncode({'jobId': jobId, 'clientId': _clientId, 'radiusMeters': 10000}),
      ).timeout(const Duration(seconds: 10));

      if (!mounted) return;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200) {
        final cnt = body['sentCount'] ?? 0;
        _showSnack('$cnt명에게 알림을 발송했어요!', isError: false);
      } else {
        _showSnack(body['message']?.toString() ?? '발송 실패', isError: true);
      }
    } catch (_) {
      if (mounted) _showSnack('네트워크 오류', isError: true);
    } finally {
      if (mounted) setState(() => _broadcastSending = false);
    }
  }

  void _showSnack(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? _red : _green,
      duration: const Duration(seconds: 3),
    ));
  }

  // ── 선택된 공고 ───────────────────────────────────────────────
  _JobPin? get _selectedJob =>
      _selectedIdx != null && _selectedIdx! < _jobs.length
          ? _jobs[_selectedIdx!]
          : null;

  // ── build ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bottom  = MediaQuery.of(context).padding.bottom;
    final cardH   = _selectedJob != null ? 148.0 : 0.0;
    final chipH   = 52.0;
    final mapBottomPad = bottom + cardH + (cardH > 0 ? 4 : 0);

    return Stack(
      children: [
        // ── 지도 ─────────────────────────────────────────────────
        Positioned.fill(
          bottom: mapBottomPad,
          child: FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: _myLocation ?? const LatLng(37.5665, 126.9780),
              initialZoom: 13,
              minZoom: 7,
              maxZoom: 19,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'kr.co.albailju',
                errorTileCallback: (_, __, ___) {},
              ),
              // 내 위치 핀
              if (_myLocation != null)
                MarkerLayer(markers: [
                  Marker(
                    point: _myLocation!,
                    width: 18, height: 18,
                    child: Container(
                      decoration: BoxDecoration(
                        color: _primary, shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.5),
                        boxShadow: [BoxShadow(color: _primary.withValues(alpha: 0.4), blurRadius: 8, spreadRadius: 2)],
                      ),
                    ),
                  ),
                ]),
              // 구직자 점 (선택된 공고 기준)
              if (_workerDots.isNotEmpty)
                MarkerLayer(
                  markers: _workerDots.map((d) => Marker(
                    point: d.position,
                    width: 20, height: 20,
                    child: GestureDetector(
                      onTap: () => _showWorkerTooltip(d),
                      child: Container(
                        decoration: BoxDecoration(
                          color: d.gradeColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                          boxShadow: [BoxShadow(color: d.gradeColor.withValues(alpha: 0.35), blurRadius: 5)],
                        ),
                        child: Center(
                          child: Text(
                            d.grade == 'N' ? '' : d.grade,
                            style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ),
                  )).toList(),
                ),
              // 공고 핀 (위치 있는 공고만)
              MarkerLayer(
                markers: _jobs.asMap().entries
                    .where((e) => e.value.hasLocation)
                    .map((e) {
                  final selected = e.key == _selectedIdx;
                  final job = e.value;
                  return Marker(
                    point: job.position,
                    width: selected ? 100 : 80,
                    height: selected ? 44 : 36,
                    alignment: Alignment.bottomCenter,
                    child: GestureDetector(
                      onTap: () => _selectJob(e.key),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: selected ? job.pinColor : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: job.pinColor,
                            width: selected ? 0 : 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: job.pinColor.withValues(alpha: selected ? 0.4 : 0.15),
                              blurRadius: selected ? 10 : 5,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          job.title.length > 8 ? '${job.title.substring(0, 8)}…' : job.title,
                          style: TextStyle(
                            color: selected ? Colors.white : job.pinColor,
                            fontSize: selected ? 12 : 10,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),

        // ── 상단 공고 칩 셀렉터 ─────────────────────────────────
        Positioned(
          top: 12, left: 0, right: 0,
          child: SizedBox(
            height: chipH,
            child: _loading
                ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _primary)))
                : _jobs.isEmpty
                    ? Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8)],
                          ),
                          child: const Text('등록된 공고가 없어요', style: TextStyle(color: _textSub, fontSize: 13)),
                        ),
                      )
                    : ListView.separated(
                        controller: _scrollCtrl,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _jobs.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final job   = _jobs[i];
                          final sel   = i == _selectedIdx;
                          return GestureDetector(
                            onTap: () => _selectJob(i),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                              decoration: BoxDecoration(
                                color: sel ? job.pinColor : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: sel ? Colors.transparent : _border),
                                boxShadow: [BoxShadow(
                                  color: Colors.black.withValues(alpha: sel ? 0.12 : 0.06),
                                  blurRadius: sel ? 12 : 6,
                                  offset: const Offset(0, 2),
                                )],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 7, height: 7,
                                    decoration: BoxDecoration(
                                      color: sel ? Colors.white.withValues(alpha: 0.8) : job.pinColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    job.title.length > 10 ? '${job.title.substring(0, 10)}…' : job.title,
                                    style: TextStyle(
                                      color: sel ? Colors.white : _textMain,
                                      fontSize: 13, fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (job.applicantCount > 0) ...[
                                    const SizedBox(width: 5),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: sel
                                            ? Colors.white.withValues(alpha: 0.25)
                                            : _primary.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        '${job.applicantCount}',
                                        style: TextStyle(
                                          fontSize: 10, fontWeight: FontWeight.w700,
                                          color: sel ? Colors.white : _primary,
                                        ),
                                      ),
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

        // ── 로딩 스피너 (구직자) ─────────────────────────────────
        if (_workersLoading)
          Positioned(
            right: 60, bottom: mapBottomPad + 12,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8)],
              ),
              child: const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _primary)),
            ),
          ),

        // ── 오른쪽 FAB ───────────────────────────────────────────
        Positioned(
          right: 16,
          bottom: mapBottomPad + 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Fab(icon: Icons.my_location_rounded, onTap: _goToMyLocation),
              const SizedBox(height: 8),
              _Fab(
                icon: Icons.fit_screen_rounded,
                onTap: _selectedJob?.hasLocation == true ? _fitToJob : null,
              ),
              const SizedBox(height: 8),
              _Fab(
                icon: Icons.refresh_rounded,
                onTap: () { _dotCache.clear(); _countCache.clear(); _fetchJobs(); },
              ),
            ],
          ),
        ),

        // ── 선택된 공고 카드 (하단 고정) ─────────────────────────
        if (_selectedJob != null)
          Positioned(
            left: 0, right: 0,
            bottom: 0,
            child: _JobCard(
              job:          _selectedJob!,
              workerCount:  _selectedWorkerCount,
              isSubscribed: _isSubscribed,
              broadcasting: _broadcastSending,
              bottomPad:    bottom,
              onUrgentCall: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => NearbyWorkersScreen(
                  jobId:    _selectedJob!.id,
                  clientId: _clientId ?? 0,
                  jobTitle: _selectedJob!.title,
                ),
              )).then((_) { _dotCache.remove(_selectedJob!.id); _countCache.remove(_selectedJob!.id); _selectJob(_selectedIdx!); }),
              onBroadcast: () => _sendBroadcast(_selectedJob!.id),
            ),
          ),
      ],
    );
  }

  // ── 구직자 툴팁 ──────────────────────────────────────────────
  void _showWorkerTooltip(_WorkerDot d) {
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: d.gradeColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(d.grade, style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800, color: d.gradeColor,
                )),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('구직자', style: TextStyle(fontSize: 10, color: _textSub)),
                Text('활동등급 ${d.grade}',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: d.gradeColor)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _goToMyLocation() async {
    if (_myLocation != null) { _mapCtrl.move(_myLocation!, 14); return; }
    final loc = await _getLocation();
    if (loc != null && mounted) {
      setState(() => _myLocation = loc);
      _mapCtrl.move(loc, 14);
    }
  }

  void _fitToJob() {
    final job = _selectedJob;
    if (job == null || !job.hasLocation) return;
    if (_workerDots.isEmpty) {
      _mapCtrl.move(job.position, 13.5);
      return;
    }
    final lats = [job.lat, ..._workerDots.map((d) => d.lat)];
    final lngs = [job.lng, ..._workerDots.map((d) => d.lng)];
    _mapCtrl.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds(
        LatLng(lats.reduce((a, b) => a < b ? a : b) - 0.005,
               lngs.reduce((a, b) => a < b ? a : b) - 0.005),
        LatLng(lats.reduce((a, b) => a > b ? a : b) + 0.005,
               lngs.reduce((a, b) => a > b ? a : b) + 0.005),
      ),
      padding: const EdgeInsets.all(56),
    ));
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
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: _border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Icon(icon, color: onTap != null ? _primary : _textSub, size: 21),
    ),
  );
}

// ── 공고 카드 (하단 고정) ─────────────────────────────────────────
class _JobCard extends StatelessWidget {
  final _JobPin       job;
  final int           workerCount;
  final bool          isSubscribed;
  final bool          broadcasting;
  final double        bottomPad;
  final VoidCallback  onUrgentCall;
  final VoidCallback  onBroadcast;

  const _JobCard({
    required this.job, required this.workerCount,
    required this.isSubscribed, required this.broadcasting,
    required this.bottomPad,
    required this.onUrgentCall, required this.onBroadcast,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, -3))],
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPad + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상단 줄: 상태 + 타이틀
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: job.pinColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(job.statusLabel,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: job.pinColor)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(job.title,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _textMain),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              // 반경 내 구직자 수
              Row(
                children: [
                  const Icon(Icons.people_rounded, size: 14, color: _primary),
                  const SizedBox(width: 3),
                  Text('$workerCount명', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _primary)),
                  const SizedBox(width: 2),
                  const Text('10km 내', style: TextStyle(fontSize: 10, color: _textSub)),
                ],
              ),
            ],
          ),

          // 메타 정보
          if (job.location.isNotEmpty || job.startDate.isNotEmpty || job.hourlyWage > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 10),
              child: Wrap(
                spacing: 10, runSpacing: 2,
                children: [
                  if (job.location.isNotEmpty)   _meta(Icons.location_on_rounded,   job.location),
                  if (job.startDate.isNotEmpty)   _meta(Icons.calendar_today_rounded, job.startDate),
                  if (job.hourlyWage > 0)         _meta(Icons.payments_rounded,       '시급 ${_comma(job.hourlyWage)}원'),
                ],
              ),
            )
          else
            const SizedBox(height: 10),

          // 버튼
          Row(
            children: [
              Expanded(
                child: _CardBtn(
                  label: '긴급 호출',
                  icon: Icons.emergency_rounded,
                  color: _red,
                  filled: true,
                  onTap: onUrgentCall,
                ),
              ),
              const SizedBox(width: 10),
              if (isSubscribed)
                Expanded(
                  child: _CardBtn(
                    label: broadcasting ? '발송 중…' : '공고 알림 발송',
                    icon: broadcasting ? Icons.hourglass_top_rounded : Icons.campaign_rounded,
                    color: _purple,
                    filled: false,
                    onTap: broadcasting ? null : onBroadcast,
                  ),
                )
              else
                Expanded(
                  child: _CardBtn(
                    label: '구독 시 알림 발송',
                    icon: Icons.lock_rounded,
                    color: _textSub,
                    filled: false,
                    onTap: () => Navigator.pushNamed(context, '/subscription'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _meta(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 12, color: _textSub),
      const SizedBox(width: 3),
      Text(text, style: const TextStyle(fontSize: 12, color: _textSub)),
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

class _CardBtn extends StatelessWidget {
  final String        label;
  final IconData      icon;
  final Color         color;
  final bool          filled;
  final VoidCallback? onTap;

  const _CardBtn({
    required this.label, required this.icon,
    required this.color, required this.filled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: filled
              ? (disabled ? const Color(0xFFD1D5DB) : color)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: filled ? null : Border.all(color: disabled ? _border : color),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15,
                color: filled ? Colors.white : (disabled ? _textSub : color)),
            const SizedBox(width: 5),
            Text(label,
              style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: filled ? Colors.white : (disabled ? _textSub : color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
