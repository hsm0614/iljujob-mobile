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
  StreamSubscription<km.CameraMoveEndEvent>? _cameraSub;
  bool _mapReady  = false;
  bool _mapMoving = false; // 카드 숨김 여부 (이동 중)

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

  final Map<int, int>           _countCache  = {};
  final Map<int, List<_Worker>> _dotCache    = {};
  // 직방 스타일 오버레이: LatLng → 화면 좌표
  final Map<int, Offset?> _jobScreenPos    = {};
  final Map<int, Offset?> _workerScreenPos = {};
  // 뷰포트 좌표 변환용 (fromScreenPoint 칼리브레이션)
  Size? _viewSize;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _cameraSub?.cancel();
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
    if (_clientId == null) { debugPrint('[MAP][JOBS] clientId null — 중단'); return; }
    if (mounted) setState(() => _loading = true);
    debugPrint('[MAP][JOBS] 요청 시작 clientId=$_clientId');
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/api/job/my-jobs?clientId=$_clientId&limit=50'))
          .timeout(const Duration(seconds: 10));
      debugPrint('[MAP][JOBS] 응답 status=${res.statusCode}');
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

        debugPrint('[MAP][JOBS] 공고 ${jobs.length}개 로드 / 위치있는것: ${jobs.where((j) => j.hasLocation).length}개');
        for (final j in jobs) {
          debugPrint('  └ [${j.id}] "${j.title}" lat=${j.lat} lng=${j.lng} hasLoc=${j.hasLocation}');
        }

        setState(() { _jobs = jobs; _loading = false; });
        // 지도 준비됐으면 바로 카드 오버레이 표시
        if (_mapReady && jobs.isNotEmpty) {
          debugPrint('[MAP][JOBS] mapReady=true → selectJob(0) + updateCardPositions');
          _selectJob(0);
          await _updateCardPositions();
        } else {
          debugPrint('[MAP][JOBS] mapReady=$_mapReady, jobs=${jobs.length} → 지도 준비 대기');
        }
      } else {
        debugPrint('[MAP][JOBS] 에러 body=${res.body}');
        if (mounted) setState(() => _loading = false);
      }
    } on TimeoutException { debugPrint('[MAP][JOBS] Timeout'); if (mounted) setState(() => _loading = false); }
      on SocketException  { debugPrint('[MAP][JOBS] SocketException'); if (mounted) setState(() => _loading = false); }
      catch (e)           { debugPrint('[MAP][JOBS] catch: $e'); if (mounted) setState(() => _loading = false); }
  }

  // ── 카카오맵 준비 ──────────────────────────────────────────────
  void _onMapCreated(km.KakaoMapController ctrl) {
    debugPrint('[MAP] onMapCreated 호출됨');
    _ctrl = ctrl;
    _cameraSub = ctrl.onCameraMoveEndStream.listen((_) async {
      debugPrint('[MAP] onCameraMoveEnd — 즉시 위치 재계산');
      if (mounted) {
        await _updateCardPositions();
        if (mounted) setState(() => _mapMoving = false);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 100));
      await _setupMap();
    });
  }

  Future<void> _setupMap() async {
    debugPrint('[MAP] _setupMap 시작 ctrl=${_ctrl != null}');
    if (_ctrl == null) return;
    try { await _ctrl!.setPoiVisible(isVisible: true); debugPrint('[MAP] setPoiVisible OK'); } catch (e) { debugPrint('[MAP] setPoiVisible 실패: $e'); }
    if (!mounted) return;
    _mapReady = true;
    debugPrint('[MAP] _setupMap 완료 — mapReady=true, jobs=${_jobs.length}');
    if (_jobs.isNotEmpty) {
      _selectJob(0);
      await _updateCardPositions();
    }
  }

  // ── 직방 스타일: fromScreenPoint 칼리브레이션 → 선형 보간 ────────
  Future<void> _updateCardPositions() async {
    if (_ctrl == null || !mounted) {
      debugPrint('[MAP][CARD] 스킵 — ctrl=${_ctrl != null}, mounted=$mounted');
      return;
    }
    final vs = _viewSize;
    if (vs == null || vs.isEmpty) {
      debugPrint('[MAP][CARD] viewSize null → 스킵');
      return;
    }

    final jobsWithLoc     = _jobs.where((j) => j.hasLocation).toList();
    final workersWithLoc  = _currentWorkers.where((w) => w.hasLocation).toList();
    debugPrint('[MAP][CARD] 칼리브레이션 시작 — jobs=${jobsWithLoc.length}, workers=${workersWithLoc.length}, view=$vs');

    // 뷰포트 네 모서리 → LatLng 획득 (fromScreenPoint)
    km.LatLng? tl, br;
    try {
      tl = await _ctrl!.fromScreenPoint(point: Offset.zero);
      br = await _ctrl!.fromScreenPoint(point: Offset(vs.width, vs.height));
      debugPrint('[MAP][CARD] TL=$tl  BR=$br');
    } catch (e) {
      debugPrint('[MAP][CARD] fromScreenPoint 예외: $e');
    }

    if (!mounted) return;

    if (tl == null || br == null) {
      debugPrint('[MAP][CARD] fromScreenPoint null → 카드 위치 계산 불가');
      setState(() { _jobScreenPos.clear(); _workerScreenPos.clear(); });
      return;
    }

    final latRange = tl.latitude  - br.latitude;
    final lngRange = br.longitude - tl.longitude;
    if (latRange.abs() < 1e-10 || lngRange.abs() < 1e-10) {
      debugPrint('[MAP][CARD] latRange/lngRange 너무 작음 → 스킵');
      return;
    }

    // 선형 보간 함수
    Offset latLngToScreen(double lat, double lng) => Offset(
      (lng - tl!.longitude) / lngRange * vs.width,
      (tl.latitude - lat)   / latRange * vs.height,
    );

    final newJobPos = <int, Offset?>{};
    for (final j in jobsWithLoc) {
      final p = latLngToScreen(j.lat, j.lng);
      debugPrint('[MAP][CARD] job[${j.id}] "${j.title}" → ${p.dx.toStringAsFixed(1)},${p.dy.toStringAsFixed(1)}');
      newJobPos[j.id] = p;
    }
    final newWorkerPos = <int, Offset?>{};
    for (final w in workersWithLoc) {
      newWorkerPos[w.id] = latLngToScreen(w.lat, w.lng);
    }

    if (!mounted) return;
    setState(() {
      _jobScreenPos..clear()..addAll(newJobPos);
      _workerScreenPos..clear()..addAll(newWorkerPos);
    });
    debugPrint('[MAP][CARD] 완료 — ${newJobPos.length}개 job 위치 계산');
  }

  // ── 공고 선택 ─────────────────────────────────────────────────
  void _selectJob(int idx) {
    debugPrint('[MAP] selectJob($idx) — jobs=${_jobs.length}');
    if (idx < 0 || idx >= _jobs.length) return;
    setState(() {
      _selectedIdx = idx;
      _workerCount = 0;
    });
    final job = _jobs[idx];
    debugPrint('[MAP] selectJob → "${job.title}" lat=${job.lat} lng=${job.lng} hasLoc=${job.hasLocation}');
    if (job.hasLocation && _ctrl != null) {
      setState(() => _mapMoving = true); // 이동 시작 → 카드 즉시 숨김
      _ctrl!.moveCamera(
        cameraUpdate: km.CameraUpdate.fromLatLng(job.pos),
        animation: const km.CameraAnimation(duration: 350, autoElevation: true, isConsecutive: false),
      );
      debugPrint('[MAP] moveCamera 호출 — 카드 숨김, onCameraMoveEnd 대기');
    } else {
      debugPrint('[MAP] moveCamera 스킵 — hasLoc=${job.hasLocation}, ctrl=${_ctrl != null}');
    }
    if (job.hasLocation) _loadWorkers(job);
  }

  Future<void> _loadWorkers(_Job job) async {
    debugPrint('[MAP][WORKER] loadWorkers jobId=${job.id}');
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
    debugPrint('[MAP][WORKER] 알바생 ${workers.length}명 / 반경 count=$count');
    _dotCache[job.id] = workers;
    setState(() {
      _currentWorkers = workers;
      _workerCount    = count;
      _workersLoading = false;
    });
    if (_mapReady) await _updateCardPositions();
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
          child: LayoutBuilder(
            builder: (_, constraints) {
              _viewSize = constraints.biggest;
              return km.KakaoMap(
                initialPosition: const km.LatLng(latitude: 37.5665, longitude: 126.9780),
                initialLevel: 5,
                onMapCreated: _onMapCreated,
              );
            },
          ),
        ),

        // ── 구직자 도트 오버레이 ─────────────────────────────────
        for (final w in _currentWorkers.where((w) => w.hasLocation)) ...[
          if (_workerScreenPos[w.id] case final Offset p
              when p.dx >= 0 && p.dy >= 0)
            Positioned(
              left: p.dx - 14,
              top: p.dy - 14,
              child: AnimatedOpacity(
                opacity: _mapMoving ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 180),
                child: _WorkerDot(worker: w),
              ),
            ),
        ],

        // ── 공고 카드 오버레이 (직방 스타일) ─────────────────────
        for (final e in _jobs.asMap().entries.where((e) => e.value.hasLocation)) ...[
          if (_jobScreenPos[e.value.id] case final Offset p
              when p.dx >= 0 && p.dy >= 0)
            Positioned(
              left: p.dx,
              top: p.dy,
              child: FractionalTranslation(
                translation: const Offset(-0.5, -1.0),
                child: AnimatedOpacity(
                  opacity: _mapMoving ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 180),
                  child: GestureDetector(
                    onTap: () => _selectJob(e.key),
                    child: _JobMapCard(job: e.value, isSelected: e.key == _selectedIdx),
                  ),
                ),
              ),
            ),
        ],

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
          cameraUpdate: km.CameraUpdate(
            position: km.LatLng(latitude: p.latitude, longitude: p.longitude),
            type: 0,
          ),
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
                Icon(Icons.people_alt_rounded, size: 14, color: widget.workerCount > 0 ? _primary : _textSub),
                const SizedBox(width: 3),
                Text(
                  widget.workerCount > 0 ? '${widget.workerCount}명' : '없음',
                  style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700,
                    color: widget.workerCount > 0 ? _primary : _textSub,
                  ),
                ),
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

// ── 확장 상태: 잡 디테일 스타일 ──────────────────────────────────
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
    final metaRows = <(IconData, String, String)>[
      if (job.startDate.isNotEmpty)  (Icons.calendar_today_rounded, '날짜', job.startDate),
      if (job.timeRange.isNotEmpty)  (Icons.access_time_rounded,    '시간', job.timeRange),
      if (job.location.isNotEmpty)   (Icons.place_rounded,          '위치', job.location),
      if (job.category.isNotEmpty)   (Icons.work_outline_rounded,   '직종', job.category),
      if (job.applicantCount > 0)    (Icons.how_to_reg_rounded,     '지원', '${job.applicantCount}명'),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(18, 4, 18, bottomPad + 14),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [

        // 시급 강조 박스
        if (job.hourlyWage > 0) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F7FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _primary.withValues(alpha: 0.25)),
            ),
            child: Row(children: [
              const Icon(Icons.payments_rounded, size: 16, color: _primary),
              const SizedBox(width: 8),
              Text(
                '시급 ${_comma(job.hourlyWage)}원',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: _primary),
              ),
            ]),
          ),
          const SizedBox(height: 10),
        ],

        // 메타 정보 박스
        if (metaRows.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border),
            ),
            child: Column(children: [
              for (int i = 0; i < metaRows.length; i++) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Row(children: [
                    Icon(metaRows[i].$1, size: 14, color: _textSub),
                    const SizedBox(width: 8),
                    Text(metaRows[i].$2,
                        style: const TextStyle(fontSize: 12, color: _textSub, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(metaRows[i].$3,
                          textAlign: TextAlign.right,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, color: _textMain, fontWeight: FontWeight.w800)),
                    ),
                  ]),
                ),
                if (i < metaRows.length - 1) const Divider(height: 1, color: _border),
              ],
            ]),
          ),

        // 공고 설명
        if (job.description.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text('공고 설명',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _textSub)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border),
            ),
            child: Text(
              job.description,
              style: const TextStyle(fontSize: 13, color: _textMain, height: 1.6),
              maxLines: 6, overflow: TextOverflow.ellipsis,
            ),
          ),
        ],

        const SizedBox(height: 12),
        _ActionRow(canUrgentCall: canUrgentCall, isSubscribed: isSubscribed,
            broadcasting: broadcasting, onUrgentCall: onUrgentCall,
            onBroadcast: onBroadcast, onBuyPass: onBuyPass),
      ]),
    );
  }
}

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

// ── 직방 스타일 공고 카드 마커 ────────────────────────────────────
class _JobMapCard extends StatelessWidget {
  final _Job job;
  final bool isSelected;
  const _JobMapCard({required this.job, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final bg     = isSelected ? job.pinColor : Colors.white;
    final fg     = isSelected ? Colors.white : _textMain;
    final border = isSelected ? job.pinColor : _border;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border, width: isSelected ? 1.5 : 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isSelected ? 0.18 : 0.10),
                blurRadius: isSelected ? 14 : 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (job.isPinnedNow)
                Text(
                  '⚡ 긴급',
                  style: TextStyle(
                    fontSize: 9, fontWeight: FontWeight.w800,
                    color: isSelected ? Colors.white.withValues(alpha: 0.9) : _red,
                  ),
                ),
              if (job.isPinnedNow) const SizedBox(height: 2),
              Text(
                job.hourlyWage > 0 ? '₩${_comma(job.hourlyWage)}' : job.title,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: fg),
              ),
              if (isSelected && job.title.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  job.title.length > 9 ? '${job.title.substring(0, 9)}…' : job.title,
                  style: TextStyle(fontSize: 10, color: fg.withValues(alpha: 0.8)),
                ),
              ],
            ],
          ),
        ),
        // 아래 삼각형 포인터
        CustomPaint(
          painter: _TrianglePainter(fill: bg, stroke: border),
          size: const Size(12, 6),
        ),
      ],
    );
  }
}

class _TrianglePainter extends CustomPainter {
  final Color fill, stroke;
  const _TrianglePainter({required this.fill, required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint   = Paint()..color = fill..style = PaintingStyle.fill;
    final strokePaint = Paint()..color = stroke..style = PaintingStyle.stroke..strokeWidth = 1;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(_TrianglePainter o) => o.fill != fill || o.stroke != stroke;
}

// ── 구직자 위치 도트 ──────────────────────────────────────────────
class _WorkerDot extends StatelessWidget {
  final _Worker worker;
  const _WorkerDot({required this.worker});

  Color get _color {
    if (worker.activityScore >= 100) return const Color(0xFFFF6B00); // S
    if (worker.activityScore >= 70)  return const Color(0xFF3B8AFF); // A
    if (worker.activityScore >= 40)  return const Color(0xFF22C55E); // B
    return const Color(0xFF9CA3AF);                                   // C/NEW
  }

  String get _grade {
    if (worker.activityScore >= 100) return 'S';
    if (worker.activityScore >= 70)  return 'A';
    if (worker.activityScore >= 40)  return 'B';
    return 'C';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: _color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Center(
        child: Text(
          _grade,
          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, height: 1),
        ),
      ),
    );
  }
}
