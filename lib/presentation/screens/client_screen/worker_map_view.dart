// worker_map_view.dart — 카카오맵 기반 공고 지도
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kakao_maps_flutter/kakao_maps_flutter.dart' as km;
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
const _purple   = Color(0xFF8B5CF6);

// ── 공고 모델 ─────────────────────────────────────────────────────
class _Job {
  final int id;
  final String title, location, status, startDate, startTime, endTime, description, category;
  final double lat, lng;
  final int hourlyWage, applicantCount;
  final bool isPinnedNow;

  const _Job({
    required this.id, required this.title, required this.location,
    required this.status, required this.startDate,
    required this.startTime, required this.endTime,
    required this.description, required this.category,
    required this.lat, required this.lng,
    required this.hourlyWage, required this.applicantCount,
    required this.isPinnedNow,
  });

  factory _Job.fromJson(Map<String, dynamic> j) => _Job(
    id: _i(j['id'] ?? j['job_id']),
    title: (j['title'] ?? j['job_title'] ?? '').toString(),
    location: (j['location_city'] ?? j['location'] ?? '').toString(),
    status: (j['status'] ?? 'active').toString(),
    startDate: _ds(j['start_date']),
    startTime: _ts(j['start_time']),
    endTime: _ts(j['end_time']),
    description: (j['description'] ?? '').toString().trim(),
    category: (j['category'] ?? j['job_category'] ?? '').toString(),
    lat: _d(j['lat']), lng: _d(j['lng']),
    hourlyWage: _i(j['hourly_wage'] ?? j['wage']),
    applicantCount: _i(j['applicant_count'] ?? j['applicants']),
    isPinnedNow: j['is_pinned_now'] == true || j['is_pinned_now'] == 1,
  );

  static double _d(dynamic v) { if (v is num) return v.toDouble(); if (v is String) return double.tryParse(v) ?? 0.0; return 0.0; }
  static int    _i(dynamic v) { if (v is int) return v; if (v is num) return v.toInt(); if (v is String) return int.tryParse(v) ?? 0; return 0; }
  static String _ds(dynamic v) { if (v == null) return ''; final s = v.toString(); return s.length >= 10 ? s.substring(0, 10) : s; }
  static String _ts(dynamic v) { if (v == null) return ''; final s = v.toString(); return s.length >= 5 ? s.substring(0, 5) : s; }

  bool   get hasLocation => lat != 0.0 && lng != 0.0;
  km.LatLng get pos => km.LatLng(latitude: lat, longitude: lng);

  String get timeRange => (startTime.isNotEmpty && endTime.isNotEmpty) ? '$startTime~$endTime' : '';

  Color get pinColor {
    if (isPinnedNow) return _red;
    if (status == 'active') return _primary;
    return _textSub;
  }
  String get statusLabel {
    if (isPinnedNow) return '긴급';
    if (status == 'active') return '진행중';
    if (status == 'reserved') return '예약';
    return '마감';
  }
}

// ── 구직자 모델 ───────────────────────────────────────────────────
class _Worker {
  final int id; final String name;
  final double lat, lng;
  final int activityScore;

  const _Worker({ required this.id, required this.name, required this.lat, required this.lng, required this.activityScore });

  factory _Worker.fromJson(Map<String, dynamic> j) => _Worker(
    id: _i(j['id']), name: (j['name'] ?? '').toString(),
    lat: _d(j['lat']), lng: _d(j['lng']),
    activityScore: _i(j['activity_score']),
  );

  static double _d(dynamic v) { if (v is num) return v.toDouble(); if (v is String) return double.tryParse(v) ?? 0.0; return 0.0; }
  static int    _i(dynamic v) { if (v is int) return v; if (v is num) return v.toInt(); if (v is String) return int.tryParse(v) ?? 0; return 0; }

  bool   get hasLocation => lat != 0.0 && lng != 0.0;
  km.LatLng get pos => km.LatLng(latitude: lat, longitude: lng);

  String get grade {
    if (activityScore >= 100) return 'S';
    if (activityScore >= 70)  return 'A';
    if (activityScore >= 40)  return 'B';
    return 'C';
  }
}

// ── 메인 위젯 ─────────────────────────────────────────────────────
class WorkerMapView extends StatefulWidget {
  const WorkerMapView({super.key});

  @override
  State<WorkerMapView> createState() => _WorkerMapViewState();
}

class _WorkerMapViewState extends State<WorkerMapView> {
  km.KakaoMapController? _ctrl;
  StreamSubscription<km.LabelClickEvent>? _clickSub;
  bool _mapReady = false;

  final _scrollCtrl = ScrollController();
  List<_Job>    _jobs           = [];
  List<_Worker> _currentWorkers = [];
  int?          _selectedIdx;
  int           _workerCount = 0;
  bool          _loading     = true;
  bool          _workersLoading = false;
  bool          _isSubscribed   = false;
  int           _urgentCredits  = 0;
  bool          _broadcastSending = false;

  int?    _clientId;
  String? _authToken;

  final Map<int, int>       _countCache = {};
  final Map<int, List<_Worker>> _dotCache = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _clickSub?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _clientId  = prefs.getInt('userId');
    _authToken = prefs.getString('authToken') ?? '';
    await Future.wait([_fetchJobs(), _fetchSubscription()]);
  }

  Map<String, String> get _auth =>
      (_authToken?.isNotEmpty ?? false) ? {'Authorization': 'Bearer $_authToken'} : {};

  // ── 구독 + 이용권 상태 ────────────────────────────────────────
  Future<void> _fetchSubscription() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/api/subscription/status'),
        headers: _auth,
      ).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200 && mounted) {
        final d = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _isSubscribed  = d['active'] == true;
          _urgentCredits = (d['credits'] as Map?)?['urgent'] as int? ?? 0;
        });
      }
    } catch (_) {}
  }

  bool get _canUrgentCall => _isSubscribed || _urgentCredits > 0;

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
        final list = raw is List ? raw : (raw is Map ? (raw['jobs'] ?? raw['data'] ?? []) as List : []);
        final jobs = list
            .whereType<Map<String, dynamic>>()
            .map(_Job.fromJson)
            .where((j) => j.status != 'deleted' && j.status != 'closed')
            .toList()
          ..sort((a, b) => (b.isPinnedNow ? 1 : 0) - (a.isPinnedNow ? 1 : 0));

        setState(() { _jobs = jobs; _loading = false; });
        // 지도 준비됐으면 바로 핀 표시
        if (_mapReady && jobs.isNotEmpty) {
          await _refreshMarkers();
          _selectJob(0);
        }
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } on TimeoutException { if (mounted) setState(() => _loading = false); }
      on SocketException  { if (mounted) setState(() => _loading = false); }
      catch (_)           { if (mounted) setState(() => _loading = false); }
  }

  // ── 카카오맵 준비 ──────────────────────────────────────────────
  void _onMapCreated(km.KakaoMapController ctrl) {
    _ctrl = ctrl;
    _clickSub = ctrl.onLabelClickedStream.listen(_onLabelClick);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 100));
      await _setupMap();
    });
  }

  Future<void> _setupMap() async {
    if (_ctrl == null) return;
    // setPoiVisible은 보조 기능(카카오 POI 레이블 숨김) — 실패해도 계속 진행
    try { await _ctrl!.setPoiVisible(isVisible: true); } catch (_) {}
    if (!mounted) return;
    _mapReady = true;
    if (_jobs.isNotEmpty) {
      await _refreshMarkers(workers: []);
      _selectJob(0);
    }
  }

  // ── 마커 전체 재그리기 (공고 + 구직자 단일 레이어) ───────────
  Future<void> _refreshMarkers({List<_Worker>? workers}) async {
    if (_ctrl == null) return;
    final w = workers ?? _currentWorkers;
    try {
      await _ctrl!.clearMarkers();
      final jobOpts = _jobs.where((j) => j.hasLocation).map((j) => km.MarkerOption(
        id: 'job_${j.id}',
        latLng: j.pos,
        text: '${j.isPinnedNow ? "[긴급] " : ""}${j.title.length > 9 ? '${j.title.substring(0, 9)}…' : j.title}',
      )).toList();
      final workerOpts = w.where((wk) => wk.hasLocation).map((wk) => km.MarkerOption(
        id: 'w_${wk.id}',
        latLng: wk.pos,
        text: wk.grade,
      )).toList();
      final all = [...jobOpts, ...workerOpts];
      if (all.isNotEmpty) await _ctrl!.addMarkers(markerOptions: all);
      // 카메라: 선택된 공고 or 첫 공고
      final target = (_selectedIdx != null && _jobs[_selectedIdx!].hasLocation)
          ? _jobs[_selectedIdx!]
          : _jobs.where((j) => j.hasLocation).firstOrNull;
      if (target != null) {
        await _ctrl!.moveCamera(
          cameraUpdate: km.CameraUpdate.fromLatLng(target.pos),
          animation: const km.CameraAnimation(duration: 300, autoElevation: true, isConsecutive: false),
        );
      }
    } catch (e) {
      debugPrint('[MAP] refreshMarkers: $e');
    }
  }

  // ── 라벨 클릭 ─────────────────────────────────────────────────
  void _onLabelClick(km.LabelClickEvent e) {
    if (!e.labelId.startsWith('job_')) return;
    final id = int.tryParse(e.labelId.substring(4));
    if (id == null) return;
    final idx = _jobs.indexWhere((j) => j.id == id);
    if (idx >= 0) _selectJob(idx);
  }

  // ── 공고 선택 ─────────────────────────────────────────────────
  void _selectJob(int idx) {
    if (idx < 0 || idx >= _jobs.length) return;
    setState(() {
      _selectedIdx = idx;
      _workerCount = 0;
    });
    final job = _jobs[idx];
    // 카메라 이동
    if (job.hasLocation && _ctrl != null) {
      _ctrl!.moveCamera(
        cameraUpdate: km.CameraUpdate.fromLatLng(job.pos),
        animation: const km.CameraAnimation(duration: 350, autoElevation: true, isConsecutive: false),
      );
    }
    // 구직자 로드 (위치 있는 공고만)
    if (job.hasLocation) _loadWorkers(job);
  }

  Future<void> _loadWorkers(_Job job) async {
    if (mounted) setState(() => _workersLoading = true);
    final results = await Future.wait([
      _dotCache.containsKey(job.id)
          ? Future.value(_dotCache[job.id]!)
          : _fetchWorkers(job.id),
      _fetchCount(job.id),
    ]);
    if (!mounted) return;
    final workers = results[0] as List<_Worker>;
    final count   = results[1] as int;
    _dotCache[job.id] = workers;
    setState(() {
      _currentWorkers = workers;
      _workerCount    = count;
      _workersLoading = false;
    });
    if (_mapReady) await _refreshMarkers(workers: workers);
  }

  Future<List<_Worker>> _fetchWorkers(int jobId) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/api/direct-messages/nearby-workers?jobId=$jobId&radius=5000'),
        headers: _auth,
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        return (jsonDecode(res.body)['workers'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(_Worker.fromJson)
            .where((w) => w.hasLocation)
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<int> _fetchCount(int jobId) async {
    if (_countCache.containsKey(jobId)) return _countCache[jobId]!;
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/api/direct-messages/nearby-count?jobId=$jobId&radius=5000'),
        headers: _auth,
      ).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final n = (jsonDecode(res.body)['count'] as num?)?.toInt() ?? 0;
        _countCache[jobId] = n;
        return n;
      }
    } catch (_) {}
    return 0;
  }

  // ── 공고 알림 발송 ────────────────────────────────────────────
  Future<void> _sendBroadcast() async {
    final job = _selectedJob;
    if (job == null || _broadcastSending) return;
    setState(() => _broadcastSending = true);
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/notification-settings/send-nearby'),
        headers: {..._auth, 'Content-Type': 'application/json'},
        body: jsonEncode({'jobId': job.id, 'clientId': _clientId, 'radiusMeters': 5000}),
      ).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      _showSnack(
        res.statusCode == 200
            ? '${body['sentCount'] ?? 0}명에게 알림을 발송했어요!'
            : (body['message']?.toString() ?? '발송 실패'),
        isError: res.statusCode != 200,
      );
    } catch (_) { if (mounted) _showSnack('네트워크 오류', isError: true); }
    finally { if (mounted) setState(() => _broadcastSending = false); }
  }

  void _showSnack(String msg, {required bool isError}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: isError ? _red : _green,
        duration: const Duration(seconds: 3),
      ));

  _Job? get _selectedJob =>
      _selectedIdx != null && _selectedIdx! < _jobs.length ? _jobs[_selectedIdx!] : null;

  // ── build ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final topPad    = MediaQuery.of(context).padding.top;

    return Stack(
      children: [
        // ── 카카오맵 (항상 풀스크린) ────────────────────────────────
        Positioned.fill(
          child: km.KakaoMap(
            initialPosition: const km.LatLng(latitude: 37.5665, longitude: 126.9780),
            initialLevel: 5,
            onMapCreated: _onMapCreated,
          ),
        ),

        // ── 상단 공고 칩 ──────────────────────────────────────────
        Positioned(
          top: topPad + 12, left: 0, right: 0,
          child: SizedBox(
            height: 40,
            child: _loading
                ? Center(child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8)],
                    ),
                    child: const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: _primary)),
                  ))
                : _jobs.isEmpty
                    ? Center(child: _chipContainer(child: const Text('등록된 공고 없음',
                        style: TextStyle(fontSize: 12, color: _textSub))))
                    : ListView.separated(
                        controller: _scrollCtrl,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _jobs.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final job = _jobs[i];
                          final sel = i == _selectedIdx;
                          return GestureDetector(
                            onTap: () => _selectJob(i),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              decoration: BoxDecoration(
                                color: sel ? job.pinColor : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: sel ? Colors.transparent : _border),
                                boxShadow: [BoxShadow(
                                  color: Colors.black.withValues(alpha: sel ? 0.14 : 0.07),
                                  blurRadius: sel ? 14 : 7,
                                  offset: const Offset(0, 2),
                                )],
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Container(width: 6, height: 6,
                                  decoration: BoxDecoration(
                                    color: sel ? Colors.white.withValues(alpha: 0.75) : job.pinColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  job.title.length > 11 ? '${job.title.substring(0, 11)}…' : job.title,
                                  style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600,
                                    color: sel ? Colors.white : _textMain,
                                  ),
                                ),
                                if (job.applicantCount > 0) ...[
                                  const SizedBox(width: 5),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: sel ? Colors.white.withValues(alpha: 0.25) : _primary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text('${job.applicantCount}',
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                                            color: sel ? Colors.white : _primary)),
                                  ),
                                ],
                              ]),
                            ),
                          );
                        },
                      ),
          ),
        ),

        // ── 우측 FAB (collapsed 카드 높이 165 + safe area 위에 고정) ──
        Positioned(
          right: 14,
          bottom: 175 + bottomPad,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _Fab(icon: Icons.my_location_rounded, onTap: _goToMyLocation),
            const SizedBox(height: 8),
            _Fab(
              icon: Icons.refresh_rounded,
              onTap: () { _dotCache.clear(); _countCache.clear(); _fetchJobs(); },
            ),
          ]),
        ),

        // ── 구직자 로딩 표시 ──────────────────────────────────────
        if (_workersLoading)
          Positioned(
            right: 66, bottom: 179 + bottomPad,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8)],
              ),
              child: const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _primary)),
            ),
          ),

        // ── 공고 카드 (확장형) ────────────────────────────────────
        if (_selectedJob != null)
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: _ExpandableJobCard(
              key: ValueKey(_selectedJob!.id),
              job:           _selectedJob!,
              workerCount:   _workerCount,
              canUrgentCall: _canUrgentCall,
              isSubscribed:  _isSubscribed,
              broadcasting:  _broadcastSending,
              bottomPad:     bottomPad,
              onUrgentCall: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => NearbyWorkersScreen(
                  jobId: _selectedJob!.id,
                  clientId: _clientId ?? 0,
                  jobTitle: _selectedJob!.title,
                ),
              )).then((_) {
                _dotCache.remove(_selectedJob?.id);
                _countCache.remove(_selectedJob?.id);
                final idx = _selectedIdx;
                if (idx != null) _loadWorkers(_jobs[idx]);
              }),
              onBroadcast: _sendBroadcast,
              onBuyPass: () => Navigator.pushNamed(context, '/pass_store'),
            ),
          ),
      ],
    );
  }

  static Widget _chipContainer({required Widget child}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 8)],
    ),
    child: child,
  );

  Future<void> _goToMyLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) return;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
      ).timeout(const Duration(seconds: 5));
      if (_ctrl != null) {
        await _ctrl!.moveCamera(
          cameraUpdate: km.CameraUpdate.fromLatLng(km.LatLng(latitude: p.latitude, longitude: p.longitude)),
          animation: const km.CameraAnimation(duration: 400, autoElevation: true, isConsecutive: false),
        );
      }
    } catch (_) {}
  }
}

// ── FAB ──────────────────────────────────────────────────────────
class _Fab extends StatelessWidget {
  final IconData icon; final VoidCallback? onTap;
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

// ── 확장형 공고 카드 ──────────────────────────────────────────────
class _ExpandableJobCard extends StatefulWidget {
  final _Job job;
  final int workerCount;
  final bool canUrgentCall, isSubscribed, broadcasting;
  final double bottomPad;
  final VoidCallback onUrgentCall, onBroadcast, onBuyPass;

  const _ExpandableJobCard({
    super.key,
    required this.job, required this.workerCount,
    required this.canUrgentCall, required this.isSubscribed,
    required this.broadcasting, required this.bottomPad,
    required this.onUrgentCall, required this.onBroadcast, required this.onBuyPass,
  });

  @override
  State<_ExpandableJobCard> createState() => _ExpandableJobCardState();
}

class _ExpandableJobCardState extends State<_ExpandableJobCard> {
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    return GestureDetector(
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -250 && !_expanded) _toggle();
        if ((d.primaryVelocity ?? 0) >  250 && _expanded)  _toggle();
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 18, offset: const Offset(0, -3))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // 드래그 핸들
          GestureDetector(
            onTap: _toggle,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: _expanded ? 44 : 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _expanded ? _primary.withValues(alpha: 0.5) : _border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),

          // 헤더: 상태 뱃지 + 제목 + 구직자 수
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: Row(children: [
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
              Expanded(child: Text(job.title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _textMain),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.people_alt_rounded, size: 14, color: _primary),
                const SizedBox(width: 3),
                Text('${widget.workerCount}명',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _primary)),
                const SizedBox(width: 2),
                const Text('5km', style: TextStyle(fontSize: 10, color: _textSub)),
              ]),
            ]),
          ),

          // 확장 컨텐츠
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            sizeCurve: Curves.easeOut,
            crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: _CollapsedMeta(job: job, bottomPad: widget.bottomPad,
                canUrgentCall: widget.canUrgentCall, isSubscribed: widget.isSubscribed,
                broadcasting: widget.broadcasting,
                onUrgentCall: widget.onUrgentCall, onBroadcast: widget.onBroadcast,
                onBuyPass: widget.onBuyPass),
            secondChild: _ExpandedDetail(job: job, bottomPad: widget.bottomPad,
                canUrgentCall: widget.canUrgentCall, isSubscribed: widget.isSubscribed,
                broadcasting: widget.broadcasting,
                onUrgentCall: widget.onUrgentCall, onBroadcast: widget.onBroadcast,
                onBuyPass: widget.onBuyPass),
          ),
        ]),
      ),
    );
  }
}

// ── 축소 상태: 한 줄 메타 + 버튼 ────────────────────────────────
class _CollapsedMeta extends StatelessWidget {
  final _Job job;
  final double bottomPad;
  final bool canUrgentCall, isSubscribed, broadcasting;
  final VoidCallback onUrgentCall, onBroadcast, onBuyPass;

  const _CollapsedMeta({
    required this.job, required this.bottomPad,
    required this.canUrgentCall, required this.isSubscribed, required this.broadcasting,
    required this.onUrgentCall, required this.onBroadcast, required this.onBuyPass,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 0, 18, bottomPad + 14),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // 한 줄 메타
        if (job.location.isNotEmpty || job.hourlyWage > 0 || job.timeRange.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(children: [
              if (job.startDate.isNotEmpty) ...[
                const Icon(Icons.calendar_today_rounded, size: 11, color: _textSub),
                const SizedBox(width: 3),
                Text(job.startDate, style: const TextStyle(fontSize: 12, color: _textSub)),
                const SizedBox(width: 8),
              ],
              if (job.timeRange.isNotEmpty) ...[
                const Icon(Icons.access_time_rounded, size: 11, color: _textSub),
                const SizedBox(width: 3),
                Text(job.timeRange, style: const TextStyle(fontSize: 12, color: _textSub)),
                const SizedBox(width: 8),
              ],
              if (job.hourlyWage > 0) ...[
                const Icon(Icons.payments_rounded, size: 11, color: _textSub),
                const SizedBox(width: 3),
                Text(_comma(job.hourlyWage), style: const TextStyle(fontSize: 12, color: _textSub)),
              ],
            ]),
          )
        else
          const SizedBox(height: 12),
        _ActionRow(canUrgentCall: canUrgentCall, isSubscribed: isSubscribed,
            broadcasting: broadcasting, onUrgentCall: onUrgentCall,
            onBroadcast: onBroadcast, onBuyPass: onBuyPass),
      ]),
    );
  }
}

// ── 확장 상태: 상세 정보 + 설명 + 버튼 ──────────────────────────
class _ExpandedDetail extends StatelessWidget {
  final _Job job;
  final double bottomPad;
  final bool canUrgentCall, isSubscribed, broadcasting;
  final VoidCallback onUrgentCall, onBroadcast, onBuyPass;

  const _ExpandedDetail({
    required this.job, required this.bottomPad,
    required this.canUrgentCall, required this.isSubscribed, required this.broadcasting,
    required this.onUrgentCall, required this.onBroadcast, required this.onBuyPass,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <_InfoChip>[
      if (job.startDate.isNotEmpty)   _InfoChip(Icons.calendar_today_rounded, job.startDate),
      if (job.timeRange.isNotEmpty)   _InfoChip(Icons.access_time_rounded,    job.timeRange),
      if (job.location.isNotEmpty)    _InfoChip(Icons.place_rounded,           job.location),
      if (job.hourlyWage > 0)         _InfoChip(Icons.payments_rounded,        '시급 ${_comma(job.hourlyWage)}원'),
      if (job.category.isNotEmpty)    _InfoChip(Icons.work_outline_rounded,     job.category),
      if (job.applicantCount > 0)     _InfoChip(Icons.how_to_reg_rounded,       '지원 ${job.applicantCount}명'),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(18, 0, 18, bottomPad + 14),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 정보 칩 Wrap
        if (chips.isNotEmpty) ...[
          Wrap(
            spacing: 6, runSpacing: 6,
            children: chips.map((c) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F6FA),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(c.icon, size: 12, color: _textSub),
                const SizedBox(width: 4),
                Text(c.label, style: const TextStyle(fontSize: 12, color: _textSub)),
              ]),
            )).toList(),
          ),
          const SizedBox(height: 14),
        ],

        // 공고 설명
        if (job.description.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border),
            ),
            child: Text(
              job.description,
              style: const TextStyle(fontSize: 13, color: _textMain, height: 1.6),
              maxLines: 5, overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 14),
        ],

        _ActionRow(canUrgentCall: canUrgentCall, isSubscribed: isSubscribed,
            broadcasting: broadcasting, onUrgentCall: onUrgentCall,
            onBroadcast: onBroadcast, onBuyPass: onBuyPass),
      ]),
    );
  }
}

class _InfoChip { final IconData icon; final String label; const _InfoChip(this.icon, this.label); }

// ── 공통 액션 버튼 행 ─────────────────────────────────────────────
class _ActionRow extends StatelessWidget {
  final bool canUrgentCall, isSubscribed, broadcasting;
  final VoidCallback onUrgentCall, onBroadcast, onBuyPass;

  const _ActionRow({
    required this.canUrgentCall, required this.isSubscribed, required this.broadcasting,
    required this.onUrgentCall, required this.onBroadcast, required this.onBuyPass,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: canUrgentCall
          ? _Btn(label: '긴급 호출', icon: Icons.emergency_rounded, color: _red, filled: true, onTap: onUrgentCall)
          : _Btn(label: '이용권 구매', icon: Icons.add_shopping_cart_rounded, color: _textSub, filled: false, onTap: onBuyPass)),
      const SizedBox(width: 10),
      Expanded(child: isSubscribed
          ? _Btn(
              label: broadcasting ? '발송 중…' : '알림 발송',
              icon: broadcasting ? Icons.hourglass_top_rounded : Icons.campaign_rounded,
              color: _purple, filled: false,
              onTap: broadcasting ? null : onBroadcast,
            )
          : _Btn(label: '구독 시 발송', icon: Icons.lock_rounded, color: _textSub, filled: false,
              onTap: () => Navigator.pushNamed(context, '/subscription'))),
    ]);
  }
}

String _comma(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

class _Btn extends StatelessWidget {
  final String label; final IconData icon;
  final Color color; final bool filled;
  final VoidCallback? onTap;

  const _Btn({required this.label, required this.icon, required this.color, required this.filled, this.onTap});

  @override
  Widget build(BuildContext context) {
    final dis = onTap == null;
    final bg  = filled ? (dis ? const Color(0xFFD1D5DB) : color) : Colors.transparent;
    final fg  = filled ? Colors.white : (dis ? _textSub : color);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: filled ? null : Border.all(color: dis ? _border : color),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 15, color: fg),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
        ]),
      ),
    );
  }
}
