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
import 'package:iljujob/data/services/authenticated_http_client.dart';
import 'package:iljujob/presentation/chat/chat_room_screen.dart';
import '../worker_screen/worker_profile_screen.dart';
import 'nearby_workers_screen.dart';
import '../../../config/app_theme.dart';
import 'package:iljujob/data/models/job.dart';
import 'package:iljujob/utils/pay_display.dart';
import 'package:iljujob/widget/app_ui.dart';

// ── 디자인 토큰 ───────────────────────────────────────────────────
const _red = Color(0xFFFF3B30);
// 알림 발송 버튼(누를 수 있음) — 보라 폐지, CTA 파랑 (2026-10)

// ── 공고 모델 ─────────────────────────────────────────────────────
class _Job {
  final int id;
  final String title,
      location,
      status,
      startDate,
      startTime,
      endTime,
      description,
      category;
  final double lat, lng;
  final int hourlyWage, applicantCount;
  final bool isPinnedNow, isUrgent;
  final String pay, payType, endDate, weekdays;
  final DateTime? publishAt; // UTC
  final Map<String, dynamic> raw; // 공고 상세(Job.fromJson)로 넘길 원본

  const _Job({
    required this.id,
    required this.title,
    required this.location,
    required this.status,
    required this.startDate,
    required this.startTime,
    required this.endTime,
    required this.description,
    required this.category,
    required this.lat,
    required this.lng,
    required this.hourlyWage,
    required this.applicantCount,
    required this.isPinnedNow,
    required this.isUrgent,
    required this.pay,
    required this.payType,
    required this.endDate,
    required this.weekdays,
    required this.publishAt,
    required this.raw,
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
    lat: _d(j['lat']),
    lng: _d(j['lng']),
    hourlyWage: _i(j['hourly_wage'] ?? j['wage']),
    applicantCount: _i(j['applicant_count'] ?? j['applicants']),
    isPinnedNow: j['is_pinned_now'] == true || j['is_pinned_now'] == 1,
    isUrgent: j['is_urgent'] == true || j['is_urgent'] == 1,
    pay: (j['pay'] ?? '').toString(),
    payType: (j['pay_type'] ?? '').toString(),
    endDate: _ds(j['end_date']),
    weekdays: (j['weekdays'] ?? '').toString(),
    publishAt: DateTime.tryParse('${j['publish_at'] ?? ''}')?.toUtc(),
    raw: j,
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

  static String _ds(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  static String _ts(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    return s.length >= 5 ? s.substring(0, 5) : s;
  }

  bool get hasLocation => lat != 0.0 && lng != 0.0;
  km.LatLng get pos => km.LatLng(latitude: lat, longitude: lng);

  String get timeRange =>
      (startTime.isNotEmpty && endTime.isNotEmpty) ? '$startTime~$endTime' : '';

  /// 공개 시각 전(무료 12시간 대기·예약) — 알바생 지도·목록에 아직 안 보인다
  bool get isReserved => publishAt != null && publishAt!.isAfter(DateTime.now().toUtc());

  Color get pinColor {
    if (isUrgent) return _red;
    if (status == 'active' && !isReserved) return AppColors.primary;
    return AppColors.textSecondary;
  }

  /// 지도 위 표시·하단 카드용 급여 ('일급 120,000원'). 없으면 null
  String? get payLabel {
    if (payType.isEmpty && pay.isEmpty) return null;
    return formatJobPay(pay, payType, includeType: true);
  }

  /// '11월 7일(토) ~ 8일(일) 10:00~18:00' — 날짜 DATE는 KST 벽시계라 문자열 그대로 자른다
  String get whenLabel {
    DateTime? d(String ymd) {
      final p = ymd.split('-').map(int.tryParse).toList();
      return p.length == 3 && !p.contains(null) ? DateTime(p[0]!, p[1]!, p[2]!) : null;
    }
    return [
      if (formatWorkDays(d(startDate), d(endDate), weekdays) case final w?) w,
      if (timeRange.isNotEmpty) timeRange,
    ].join(' ');
  }
}

// ── 구직자 모델 ───────────────────────────────────────────────────
class _Worker {
  final int id;
  final String name, profileImageUrl;
  final double lat, lng;
  final int activityScore;
  final double distanceM;
  final bool alreadySent;

  const _Worker({
    required this.id,
    required this.name,
    required this.profileImageUrl,
    required this.lat,
    required this.lng,
    required this.activityScore,
    required this.distanceM,
    required this.alreadySent,
  });

  factory _Worker.fromJson(Map<String, dynamic> j) => _Worker(
    id: _i(j['id']),
    name: (j['name'] ?? '').toString(),
    profileImageUrl: (j['profile_image_url'] ?? '').toString(),
    lat: _d(j['lat']),
    lng: _d(j['lng']),
    activityScore: _i(j['activity_score']),
    distanceM: _d(j['distance_m']),
    alreadySent: j['already_sent'] == true || j['already_sent'] == 1,
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

  bool get hasLocation => lat != 0.0 && lng != 0.0;
  km.LatLng get pos => km.LatLng(latitude: lat, longitude: lng);

  String get grade {
    if (activityScore >= 100) return 'S';
    if (activityScore >= 70) return 'A';
    if (activityScore >= 40) return 'B';
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
  bool _mapReady = false;
  bool _mapMoving = false;

  final _scrollCtrl = ScrollController();
  List<_Job> _jobs = [];
  List<_Worker> _currentWorkers = [];
  int? _selectedIdx;
  int _workerCount = 0;
  bool _loading = true;
  bool _workersLoading = false;
  bool _isSubscribed = false;
  String? _entitlementVersion;
  int _directMonthlyRemaining = 0;
  int _pushMonthlyRemaining = 0;
  final Map<int, int> _directJobRemaining = {};
  final Map<int, int> _pushJobRemaining = {};
  bool _broadcastSending = false;
  bool _directSending = false;

  int? _clientId;
  String? _authToken;

  final Map<int, int> _countCache = {};
  final Map<int, List<_Worker>> _dotCache = {};
  // 직방 스타일 오버레이: LatLng → 화면 좌표
  final Map<int, Offset?> _jobScreenPos = {};
  final Map<int, Offset?> _workerScreenPos = {};
  // 뷰포트 좌표 변환용 (fromScreenPoint 칼리브레이션)
  Size? _viewSize;
  Timer? _positionSyncTimer;
  int _positionSyncSeq = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _positionSyncTimer?.cancel();
    _cameraSub?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _clientId = prefs.getInt('userId');
    _authToken = await AuthenticatedHttpClient.accessToken();
    await Future.wait([_fetchJobs(), _fetchSubscription()]);
  }

  Map<String, String> get _auth =>
      (_authToken?.isNotEmpty ?? false)
          ? {'Authorization': 'Bearer $_authToken'}
          : {};

  // ── 구독 + 이용권 상태 ────────────────────────────────────────
  Future<void> _fetchSubscription() async {
    try {
      final selectedJobId = _selectedJob?.id;
      final res = await AuthenticatedHttpClient.get(
        Uri.parse(
          '$baseUrl/api/subscription/status${selectedJobId == null ? '' : '?jobId=$selectedJobId'}',
        ),
      ).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200 && mounted) {
        final d = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _isSubscribed = d['active'] == true;
          _entitlementVersion = d['entitlementVersion']?.toString();
          _directMonthlyRemaining =
              (d['directMonthlyRemaining'] as num?)?.toInt() ?? 0;
          _pushMonthlyRemaining =
              (d['pushMonthlyRemaining'] as num?)?.toInt() ?? 0;
          if (selectedJobId != null && d['directPerJobRemaining'] is num) {
            _directJobRemaining[selectedJobId] =
                (d['directPerJobRemaining'] as num).toInt();
          }
          if (selectedJobId != null && d['pushPerJobRemaining'] is num) {
            _pushJobRemaining[selectedJobId] =
                (d['pushPerJobRemaining'] as num).toInt();
          }
        });
      }
    } catch (_) {}
  }

  bool get _canBroadcastSelected =>
      _selectedJob?.status == 'active' &&
      (_selectedJob?.isUrgent == true ||
          (_isSubscribed &&
              (_entitlementVersion != 'v3' ||
                  (_pushMonthlyRemaining > 0 &&
                      (_pushJobRemaining[_selectedJob!.id] ?? 0) > 0))));

  // ── 내 공고 ───────────────────────────────────────────────────
  Future<void> _fetchJobs() async {
    if (_clientId == null) {
      debugPrint('[MAP][JOBS] clientId null — 중단');
      return;
    }
    if (mounted) setState(() => _loading = true);
    debugPrint('[MAP][JOBS] 요청 시작 clientId=$_clientId');
    try {
      final res = await AuthenticatedHttpClient.get(
        Uri.parse('$baseUrl/api/job/my-jobs?clientId=$_clientId&limit=50'),
      ).timeout(const Duration(seconds: 10));
      debugPrint('[MAP][JOBS] 응답 status=${res.statusCode}');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final raw = jsonDecode(res.body);
        final list =
            raw is List
                ? raw
                : (raw is Map
                    ? (raw['jobs'] ?? raw['data'] ?? []) as List
                    : []);
        final jobs =
            list
                .whereType<Map<String, dynamic>>()
                .map(_Job.fromJson)
                .where(
                  (j) =>
                      j.status != 'deleted' &&
                      j.status != 'closed' &&
                      j.status != 'reserved',
                )
                .toList()
              ..sort((a, b) => (b.isUrgent ? 1 : 0) - (a.isUrgent ? 1 : 0));

        debugPrint(
          '[MAP][JOBS] 공고 ${jobs.length}개 로드 / 위치있는것: ${jobs.where((j) => j.hasLocation).length}개',
        );
        for (final j in jobs) {
          debugPrint(
            '  └ [${j.id}] "${j.title}" lat=${j.lat} lng=${j.lng} hasLoc=${j.hasLocation}',
          );
        }

        setState(() {
          _jobs = jobs;
          _loading = false;
        });
        // 지도 준비됐으면 바로 카드 오버레이 표시
        if (_mapReady && jobs.isNotEmpty) {
          debugPrint(
            '[MAP][JOBS] mapReady=true → selectJob(0) + updateCardPositions',
          );
          _selectJob(0);
          await _updateCardPositions();
        } else {
          debugPrint(
            '[MAP][JOBS] mapReady=$_mapReady, jobs=${jobs.length} → 지도 준비 대기',
          );
        }
      } else {
        debugPrint('[MAP][JOBS] 에러 body=${res.body}');
        if (mounted) setState(() => _loading = false);
      }
    } on TimeoutException {
      debugPrint('[MAP][JOBS] Timeout');
      if (mounted) setState(() => _loading = false);
    } on SocketException {
      debugPrint('[MAP][JOBS] SocketException');
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      debugPrint('[MAP][JOBS] catch: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── 카카오맵 준비 ──────────────────────────────────────────────
  void _onMapCreated(km.KakaoMapController ctrl) {
    debugPrint('[MAP] onMapCreated 호출됨');
    _ctrl = ctrl;
    _cameraSub = ctrl.onCameraMoveEndStream.listen((_) async {
      debugPrint('[MAP] onCameraMoveEnd — 위치 동기화');
      if (mounted) {
        _schedulePositionSync();
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
    try {
      await _ctrl!.setPoiVisible(isVisible: true);
      debugPrint('[MAP] setPoiVisible OK');
    } catch (e) {
      debugPrint('[MAP] setPoiVisible 실패: $e');
    }
    if (!mounted) return;
    _mapReady = true;
    debugPrint('[MAP] _setupMap 완료 — mapReady=true, jobs=${_jobs.length}');
    if (_jobs.isNotEmpty) {
      _selectJob(0);
      await _updateCardPositions();
    }
  }

  void _markMapMoving() {
    if (!_mapMoving && mounted) setState(() => _mapMoving = true);
    _positionSyncTimer?.cancel();
  }

  void _schedulePositionSync({bool reveal = true}) {
    final seq = ++_positionSyncSeq;
    _positionSyncTimer?.cancel();
    Future<void> runAfter(Duration delay, {bool last = false}) async {
      await Future.delayed(delay);
      if (!mounted || seq != _positionSyncSeq) return;
      await _updateCardPositions();
      if (last && reveal && mounted && seq == _positionSyncSeq) {
        setState(() => _mapMoving = false);
      }
    }

    // 카카오맵은 이동 종료 이벤트만 제공하므로 종료 직후 좌표 안정화를 몇 차례 보정한다.
    for (final delay in const [
      Duration.zero,
      Duration(milliseconds: 80),
      Duration(milliseconds: 160),
    ]) {
      unawaited(runAfter(delay));
    }
    _positionSyncTimer = Timer(const Duration(milliseconds: 540), () {
      if (!mounted || seq != _positionSyncSeq) return;
      unawaited(runAfter(Duration.zero, last: true));
    });
  }

  // ── 직방 스타일: toScreenPoint 우선, 실패 시 fromScreenPoint 보간 ────────
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

    final jobsWithLoc = _jobs.where((j) => j.hasLocation).toList();
    final workersWithLoc = _currentWorkers.where((w) => w.hasLocation).toList();
    debugPrint(
      '[MAP][CARD] 위치 계산 시작 — jobs=${jobsWithLoc.length}, workers=${workersWithLoc.length}, view=$vs',
    );

    final newJobPos = <int, Offset?>{};
    final newWorkerPos = <int, Offset?>{};
    var nativeOk = 0;

    for (final j in jobsWithLoc) {
      try {
        final p = await _ctrl!.toScreenPoint(position: j.pos);
        if (p != null) {
          newJobPos[j.id] = p;
          nativeOk++;
          debugPrint(
            '[MAP][CARD] toScreen job[${j.id}] → screen(${p.dx.toStringAsFixed(1)},${p.dy.toStringAsFixed(1)})',
          );
        }
      } catch (e) {
        debugPrint('[MAP][CARD] toScreen job[${j.id}] 예외: $e');
      }
    }
    for (final w in workersWithLoc) {
      try {
        final p = await _ctrl!.toScreenPoint(position: w.pos);
        if (p != null) newWorkerPos[w.id] = p;
      } catch (_) {}
    }

    if (!mounted) return;
    if (nativeOk == jobsWithLoc.length) {
      setState(() {
        _jobScreenPos
          ..clear()
          ..addAll(newJobPos);
        _workerScreenPos
          ..clear()
          ..addAll(newWorkerPos);
      });
      debugPrint(
        '[MAP][CARD] 완료 — toScreenPoint ${newJobPos.length}개 job 위치 계산',
      );
      return;
    }

    debugPrint(
      '[MAP][CARD] toScreenPoint 일부 실패($nativeOk/${jobsWithLoc.length}) → 칼리브레이션 fallback',
    );

    // 뷰포트 네 모서리 → LatLng 획득 (fromScreenPoint)
    km.LatLng? tl, br;
    try {
      tl = await _ctrl!.fromScreenPoint(point: Offset.zero);
      br = await _ctrl!.fromScreenPoint(point: Offset(vs.width, vs.height));
      debugPrint(
        '[MAP][CARD] TL=(${tl?.latitude.toStringAsFixed(5)}, ${tl?.longitude.toStringAsFixed(5)}) BR=(${br?.latitude.toStringAsFixed(5)}, ${br?.longitude.toStringAsFixed(5)})',
      );
    } catch (e) {
      debugPrint('[MAP][CARD] fromScreenPoint 예외: $e');
    }

    if (!mounted) return;

    if (tl == null || br == null) {
      debugPrint('[MAP][CARD] fromScreenPoint null → 카드 위치 계산 불가');
      setState(() {
        _jobScreenPos.clear();
        _workerScreenPos.clear();
      });
      return;
    }

    final latRange = tl.latitude - br.latitude;
    final lngRange = br.longitude - tl.longitude;
    if (latRange.abs() < 1e-10 || lngRange.abs() < 1e-10) {
      debugPrint('[MAP][CARD] latRange/lngRange 너무 작음 → 스킵');
      return;
    }

    // 선형 보간 함수
    Offset latLngToScreen(double lat, double lng) => Offset(
      (lng - tl!.longitude) / lngRange * vs.width,
      (tl.latitude - lat) / latRange * vs.height,
    );

    for (final j in jobsWithLoc) {
      if (newJobPos[j.id] != null) continue;
      final p = latLngToScreen(j.lat, j.lng);
      debugPrint(
        '[MAP][CARD] job[${j.id}] lat=${j.lat.toStringAsFixed(5)},${j.lng.toStringAsFixed(5)} → screen(${p.dx.toStringAsFixed(1)},${p.dy.toStringAsFixed(1)})',
      );
      newJobPos[j.id] = p;
    }
    for (final w in workersWithLoc) {
      if (newWorkerPos[w.id] != null) continue;
      newWorkerPos[w.id] = latLngToScreen(w.lat, w.lng);
    }

    if (!mounted) return;
    setState(() {
      _jobScreenPos
        ..clear()
        ..addAll(newJobPos);
      _workerScreenPos
        ..clear()
        ..addAll(newWorkerPos);
    });
    debugPrint('[MAP][CARD] 완료 — ${newJobPos.length}개 job 위치 계산');
  }

  // ── 공고 선택 ─────────────────────────────────────────────────
  void _selectJob(int idx) {
    debugPrint('[MAP] selectJob($idx)');
    if (idx < 0 || idx >= _jobs.length) return;
    setState(() {
      _selectedIdx = idx;
      _workerCount = 0;
      _currentWorkers = [];
      _workerScreenPos.clear();
      _mapMoving = true;
    });
    final job = _jobs[idx];
    unawaited(_fetchSubscription());
    debugPrint(
      '[MAP] 선택 공고 id=${job.id} lat=${job.lat} lng=${job.lng} hasLoc=${job.hasLocation}',
    );
    if (job.hasLocation && _ctrl != null) {
      _ctrl!.moveCamera(
        cameraUpdate: km.CameraUpdate(
          position: job.pos,
          zoomLevel: 12,
          type: 0,
        ),
        animation: const km.CameraAnimation(
          duration: 350,
          autoElevation: true,
          isConsecutive: false,
        ),
      );
      _schedulePositionSync(reveal: false);
    }
    if (job.hasLocation) {
      _loadWorkers(job);
    } else {
      debugPrint('[MAP] hasLocation=false → _loadWorkers 스킵');
      if (mounted) setState(() => _mapMoving = false);
    }
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
    final count = results[1] as int;
    debugPrint('[MAP][WORKER] 알바생 ${workers.length}명 / 반경 count=$count');
    _dotCache[job.id] = workers;
    setState(() {
      _currentWorkers = workers;
      _workerCount = count;
      _workersLoading = false;
    });

    // 알바생이 있으면 공고 + 모든 알바생 위치를 한 화면에 fitPoints
    final workersWithLoc = workers.where((w) => w.hasLocation).toList();
    if (_ctrl != null && workersWithLoc.isNotEmpty) {
      if (mounted) setState(() => _mapMoving = true);
      final pts = [job.pos, ...workersWithLoc.map((w) => w.pos)];
      debugPrint('[MAP][WORKER] fitPoints ${pts.length}개');
      await _ctrl!.moveCamera(
        cameraUpdate: km.CameraUpdate(fitPoints: pts, padding: 80),
        animation: const km.CameraAnimation(
          duration: 500,
          autoElevation: true,
          isConsecutive: true,
        ),
      );
      _schedulePositionSync();
    } else if (_mapReady) {
      await _updateCardPositions();
      if (mounted) setState(() => _mapMoving = false);
    }
  }

  Future<List<_Worker>> _fetchWorkers(int jobId) async {
    try {
      final res = await http
          .get(
            Uri.parse(
              '$baseUrl/api/direct-message/nearby-workers?jobId=$jobId&radius=5000',
            ),
            headers: _auth,
          )
          .timeout(const Duration(seconds: 8));
      debugPrint('[MAP][WORKER] API status=${res.statusCode}');
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        _directJobRemaining[jobId] =
            (body['remainingRecipients'] as num?)?.toInt() ?? 0;
        final list = body['workers'] as List? ?? [];
        debugPrint('[MAP][WORKER] raw workers=${list.length}');
        final workers =
            list
                .whereType<Map<String, dynamic>>()
                .map(_Worker.fromJson)
                .toList();
        final withLoc = workers.where((w) => w.hasLocation).toList();
        debugPrint(
          '[MAP][WORKER] 위치있는 알바생=${withLoc.length}/${workers.length}',
        );
        return withLoc;
      } else {
        if (res.statusCode == 429) _directJobRemaining[jobId] = 0;
        debugPrint('[MAP][WORKER] 에러 body=${res.body}');
      }
    } catch (e) {
      debugPrint('[MAP][WORKER] fetchWorkers 예외: $e');
    }
    return [];
  }

  Future<int> _fetchCount(int jobId) async {
    if (_countCache.containsKey(jobId)) return _countCache[jobId]!;
    try {
      final res = await http
          .get(
            Uri.parse(
              '$baseUrl/api/direct-message/nearby-count?jobId=$jobId&radius=5000',
            ),
            headers: _auth,
          )
          .timeout(const Duration(seconds: 6));
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
    final messageText = await _showPushMessageSheet(
      title: '알림 문구 수정',
      subtitle: '반경 5km 알바생에게 보낼 푸시 문구예요.',
      initialText:
          '${job.location.isNotEmpty ? '[${job.location}] ' : ''}${job.title}',
      actionLabel: '알림 발송',
    );
    if (messageText == null) return;
    setState(() => _broadcastSending = true);
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/notification-settings/send-nearby'),
            headers: {..._auth, 'Content-Type': 'application/json'},
            body: jsonEncode({
              'jobId': job.id,
              'clientId': _clientId,
              'radiusMeters': 5000,
              if (messageText.trim().isNotEmpty) 'pushBody': messageText.trim(),
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      _showSnack(
        res.statusCode == 200
            ? ((body['sentCount'] as num?)?.toInt() ?? 0) > 0
                ? '${body['sentCount']}명에게 알림을 발송했어요!'
                : '알림을 받은 사람이 없어 제공량은 차감되지 않았어요.'
            : (body['message']?.toString() ?? '발송 실패'),
        isError: res.statusCode != 200,
      );
      if (res.statusCode == 200) await _fetchSubscription();
    } catch (_) {
      if (mounted) _showSnack('네트워크 오류', isError: true);
    } finally {
      if (mounted) setState(() => _broadcastSending = false);
    }
  }

  bool get _canDirectMessageSelected {
    final job = _selectedJob;
    if (job == null || job.status != 'active') return false;
    if (job.isUrgent) return (_directJobRemaining[job.id] ?? 1) > 0;
    if (!_isSubscribed) return false;
    if (_entitlementVersion != 'v3') {
      return (_directJobRemaining[job.id] ?? 1) > 0;
    }
    return _directMonthlyRemaining > 0 &&
        (_directJobRemaining[job.id] ?? 0) > 0;
  }

  String _maskName(String name) {
    if (name.isEmpty) return '알바생';
    if (name.length == 1) return name;
    if (name.length == 2) return '${name[0]}*';
    final mid = name.length ~/ 2;
    return name.replaceRange(mid, mid + 1, '*');
  }

  String _distanceLabel(double meters) {
    if (meters <= 0) return '거리 정보 없음';
    if (meters < 1000) return '${meters.round()}m';
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }

  Future<void> _sendDirectToWorker(_Worker worker) async {
    final job = _selectedJob;
    if (job == null || _clientId == null || _directSending) return;
    if (!_canDirectMessageSelected) {
      _showSnack('구독 중이거나 긴급호출 공고일 때만 메시지를 보낼 수 있어요.', isError: true);
      return;
    }
    final messageText = await _showPushMessageSheet(
      title: '먼저 연락 문구 수정',
      subtitle: '${_maskName(worker.name)}님에게 채팅과 푸시로 함께 전달돼요.',
      initialText: '${job.title} 공고에서 지금 바로 일할 분을 찾고 있어요. 가능하시면 답장해주세요!',
      actionLabel: '메시지 보내기',
    );
    if (messageText == null) return;
    setState(() => _directSending = true);
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/direct-message/send'),
            headers: {..._auth, 'Content-Type': 'application/json'},
            body: jsonEncode({
              'jobId': job.id,
              'clientId': _clientId,
              'workerIds': [worker.id],
              if (messageText.trim().isNotEmpty)
                'messageText': messageText.trim(),
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200) {
        _showSnack(
          body['message']?.toString() ?? '메시지 발송에 실패했어요.',
          isError: true,
        );
        return;
      }
      final results = body['results'] as List? ?? [];
      final roomId = results.isNotEmpty ? results.first['chatRoomId'] : null;
      _dotCache.remove(job.id);
      _countCache.remove(job.id);
      _directJobRemaining[job.id] =
          (body['remainingRecipients'] as num?)?.toInt() ?? 0;
      unawaited(_fetchSubscription());
      Navigator.pop(context);
      _showSnack('메시지를 보냈어요.', isError: false);
      if (roomId != null) {
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
                    'client_id': _clientId,
                    'worker_id': worker.id,
                    'user_name': worker.name,
                    'user_thumbnail_url': worker.profileImageUrl,
                  },
                ),
          ),
        );
      }
      unawaited(_loadWorkers(job));
    } catch (_) {
      if (mounted) _showSnack('네트워크 오류', isError: true);
    } finally {
      if (mounted) setState(() => _directSending = false);
    }
  }

  Future<String?> _showPushMessageSheet({
    required String title,
    required String subtitle,
    required String initialText,
    required String actionLabel,
  }) async {
    final controller = TextEditingController(text: initialText);
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 16 + bottomInset),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: AppFontSize.titleLg,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: AppFontSize.body2,
                    height: 1.35,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 120,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: '예: 오늘 18시부터 가능하신 분을 찾고 있어요. 시급 우대합니다.',
                    filled: true,
                    fillColor: AppColors.bgMuted,
                    contentPadding: const EdgeInsets.all(14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: const Text('취소'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed:
                            () => Navigator.pop(
                              sheetContext,
                              controller.text.trim(),
                            ),
                        child: Text(
                          actionLabel),
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
    controller.dispose();
    return result;
  }

  void _showWorkerSheet(_Worker worker) {
    final job = _selectedJob;
    final canMessage = _canDirectMessageSelected;
    final gradeColor = switch (worker.grade) {
      'S' => AppColors.gradeS,
      'A' => AppColors.primary,
      'B' => AppColors.gradeB,
      _ => AppColors.textTertiary,
    };
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder:
          (_) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: const Color(0xFFF2F4F6),
                        backgroundImage:
                            worker.profileImageUrl.isNotEmpty
                                ? NetworkImage(worker.profileImageUrl)
                                : null,
                        child:
                            worker.profileImageUrl.isEmpty
                                ? const Icon(
                                  Icons.person_rounded,
                                  color: AppColors.textSecondary,
                                )
                                : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _maskName(worker.name),
                              style: const TextStyle(
                                fontSize: AppFontSize.title,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_distanceLabel(worker.distanceM)} · 활동등급 ${worker.grade}',
                              style: const TextStyle(
                                fontSize: AppFontSize.meta,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: gradeColor.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            worker.grade,
                            style: TextStyle(
                              fontSize: AppFontSize.body1,
                              fontWeight: FontWeight.w800,
                              color: gradeColor,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (worker.alreadySent) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.bgMuted,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Text(
                        '이미 이 공고로 메시지를 보낸 알바생입니다.',
                        style: TextStyle(fontSize: AppFontSize.meta, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => WorkerProfileScreen(workerId: worker.id),
                                ),
                              );
                            },
                            child: const Text('프로필 보기'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // 빨간 채운 버튼 → 파랑(누르는 건 파랑 하나)
                      Expanded(
                        child: AppPrimaryButton(
                          label:
                              worker.alreadySent
                                  ? '발송 완료'
                                  : canMessage
                                  ? '메시지 보내기'
                                  : '제공량 확인',
                          loading: _directSending,
                          onPressed:
                              canMessage &&
                                      !worker.alreadySent &&
                                      !_directSending
                                  ? () => _sendDirectToWorker(worker)
                                  : null,
                        ),
                      ),
                    ],
                  ),
                  if (!canMessage && job != null) ...[
                    const SizedBox(height: 10),
                    const Text(
                      '게시 중인 공고와 남은 먼저 연락하기 제공량을 확인해 주세요.',
                      style: TextStyle(fontSize: AppFontSize.meta, color: AppColors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ),
    );
  }

  void _showSnack(String msg, {required bool isError}) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: isError ? _red : AppColors.gradeB,
          duration: const Duration(seconds: 3),
        ),
      );

  _Job? get _selectedJob =>
      _selectedIdx != null && _selectedIdx! < _jobs.length
          ? _jobs[_selectedIdx!]
          : null;

  // ── build ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final topPad = MediaQuery.of(context).padding.top;

    return Stack(
      children: [
        // ── 카카오맵 (항상 풀스크린) ────────────────────────────────
        Positioned.fill(
          child: LayoutBuilder(
            builder: (_, constraints) {
              _viewSize = constraints.biggest;
              return Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _markMapMoving(),
                onPointerCancel: (_) => _schedulePositionSync(),
                onPointerUp: (_) => _schedulePositionSync(),
                child: km.KakaoMap(
                  initialPosition: const km.LatLng(
                    latitude: 37.5665,
                    longitude: 126.9780,
                  ),
                  initialLevel: 5,
                  onMapCreated: _onMapCreated,
                ),
              );
            },
          ),
        ),

        if (!_mapMoving) ...[
          // ── 구직자 도트 오버레이 ───────────────────────────────
          for (final w in _currentWorkers.where((w) => w.hasLocation)) ...[
            if (_workerScreenPos[w.id] case final Offset p
                when p.dx >= 0 && p.dy >= 0)
              Positioned(
                left: p.dx - 14,
                top: p.dy - 14,
                child: GestureDetector(
                  onTap: () => _showWorkerSheet(w),
                  child: _WorkerDot(worker: w),
                ),
              ),
          ],

          // ── 공고 카드 오버레이 (직방 스타일) ───────────────────
          // 같은 위치 공고들은 살짝 오프셋으로 구별 가능하게
          ..._buildJobCards(),
        ],

        // ── 상단 공고 칩 ──────────────────────────────────────────
        Positioned(
          top: topPad + 12,
          left: 0,
          right: 0,
          child: SizedBox(
            height: 40,
            child:
                _loading
                    ? Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(AppRadius.xl),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    )
                    : _jobs.isEmpty
                    ? Center(
                      child: _chipContainer(
                        child: const Text(
                          '등록된 공고 없음',
                          style: TextStyle(fontSize: AppFontSize.meta, color: AppColors.textSecondary),
                        ),
                      ),
                    )
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
                              color: sel ? AppColors.primary : Colors.white,
                              borderRadius: BorderRadius.circular(AppRadius.xl),
                              border: Border.all(
                                color: sel ? Colors.transparent : AppColors.border,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: 0.08,
                                  ),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: job.pinColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  job.title.length > 11
                                      ? '${job.title.substring(0, 11)}…'
                                      : job.title,
                                  style: TextStyle(
                                    fontSize: AppFontSize.body2,
                                    fontWeight: FontWeight.w600,
                                    color: sel ? Colors.white : AppColors.textPrimary,
                                  ),
                                ),
                                if (job.applicantCount > 0) ...[
                                  const SizedBox(width: 5),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          sel
                                              ? Colors.white.withValues(
                                                alpha: 0.25,
                                              )
                                              : AppColors.bgMuted,
                                      borderRadius: BorderRadius.circular(AppRadius.full),
                                    ),
                                    child: Text(
                                      '${job.applicantCount}',
                                      style: TextStyle(
                                        fontSize: AppFontSize.caption,
                                        fontWeight: FontWeight.w700,
                                        color: sel ? Colors.white : AppColors.textSecondary,
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

        // ── 우측 FAB (collapsed 카드 높이 165 + safe area 위에 고정) ──
        Positioned(
          right: 14,
          bottom: 200 + bottomPad,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Fab(icon: Icons.my_location_rounded, onTap: _goToMyLocation),
              const SizedBox(height: 8),
              _Fab(
                icon: Icons.refresh_rounded,
                onTap: () {
                  _dotCache.clear();
                  _countCache.clear();
                  _fetchJobs();
                },
              ),
            ],
          ),
        ),

        // ── 구직자 로딩 표시 ──────────────────────────────────────
        if (_workersLoading)
          Positioned(
            right: 66,
            bottom: 204 + bottomPad,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.xl),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),

        // ── 공고 카드 (확장형) ────────────────────────────────────
        if (_selectedJob != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _MapJobSheet(
              key: ValueKey(_selectedJob!.id),
              job: _selectedJob!,
              workerCount: _workerCount,
              canBroadcast: _canBroadcastSelected,
              broadcasting: _broadcastSending,
              bottomPad: bottomPad,
              quota:
                  !_selectedJob!.isUrgent && _entitlementVersion == 'v3'
                      ? '이번 달 지도 알림 $_pushMonthlyRemaining회 · 이 공고 ${_pushJobRemaining[_selectedJob!.id] ?? 0}회 남음'
                      : null,
              onOpenDetail: () {
                try {
                  Navigator.pushNamed(context, '/job-detail', arguments: Job.fromJson(_selectedJob!.raw));
                } catch (_) {}
              },
              onUrgentCall:
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (_) => NearbyWorkersScreen(
                            jobId: _selectedJob!.id,
                            clientId: _clientId ?? 0,
                            jobTitle: _selectedJob!.title,
                          ),
                    ),
                  ).then((_) {
                    _dotCache.remove(_selectedJob?.id);
                    _countCache.remove(_selectedJob?.id);
                    final idx = _selectedIdx;
                    if (idx != null) _loadWorkers(_jobs[idx]);
                  }),
              onBroadcast: _sendBroadcast,
              // '/pass_store'는 없는 경로였다(눌러도 아무 일 없음) → 이용권 구매
              onBuyPass: () => Navigator.pushNamed(context, '/purchase-pass'),
            ),
          ),
      ],
    );
  }

  static Widget _chipContainer({required Widget child}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 8),
      ],
    ),
    child: child,
  );

  // ── 공고 카드 오버레이 빌드 (같은 위치 겹침 처리) ────────────
  List<Widget> _buildJobCards() {
    // 같은 화면 좌표(32px 이내)끼리 묶어서 오프셋 부여
    final entries =
        _jobs.asMap().entries.where((e) => e.value.hasLocation).where((e) {
          final p = _jobScreenPos[e.value.id];
          final vs = _viewSize;
          if (vs == null) return p != null && p.dx >= 0 && p.dy >= 0;
          return p != null &&
              p.dx >= -80 &&
              p.dy >= -80 &&
              p.dx <= vs.width + 80 &&
              p.dy <= vs.height + 80;
        }).toList();

    // 그룹별 오프셋 계산: 같은 픽셀 근방 공고들은 X축으로 벌려서 표시
    final used = <int, int>{}; // jobId → groupSlot
    final groups = <String, List<int>>{}; // "roundedX,roundedY" → [jobIds]
    for (final e in entries) {
      final p = _jobScreenPos[e.value.id]!;
      final key = '${(p.dx / 32).round()},${(p.dy / 32).round()}';
      groups.putIfAbsent(key, () => []).add(e.value.id);
    }
    for (final ids in groups.values) {
      for (int slot = 0; slot < ids.length; slot++) {
        used[ids[slot]] = slot;
      }
    }

    return entries.map((e) {
      final p = _jobScreenPos[e.value.id]!;
      final slot = used[e.value.id] ?? 0;
      // 같은 위치 여러 공고: 카드 너비(~80px) 간격으로 수평 펼침
      final offsetX = slot * 84.0;
      return Positioned(
        left: p.dx + offsetX,
        top: p.dy,
        child: FractionalTranslation(
          translation: const Offset(-0.5, -1.0),
          child: GestureDetector(
            onTap: () => _selectJob(e.key),
            child: _JobMapCard(job: e.value, isSelected: e.key == _selectedIdx),
          ),
        ),
      );
    }).toList();
  }

  Future<void> _goToMyLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) return;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
        ),
      ).timeout(const Duration(seconds: 5));
      if (_ctrl != null) {
        if (mounted) setState(() => _mapMoving = true);
        await _ctrl!.moveCamera(
          cameraUpdate: km.CameraUpdate(
            position: km.LatLng(latitude: p.latitude, longitude: p.longitude),
            type: 0,
          ),
          animation: const km.CameraAnimation(
            duration: 400,
            autoElevation: true,
            isConsecutive: false,
          ),
        );
        _schedulePositionSync();
      }
    } catch (_) {}
  }
}

// ── FAB ──────────────────────────────────────────────────────────
class _Fab extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _Fab({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(icon, color: onTap != null ? AppColors.primary : AppColors.textSecondary, size: 21),
    ),
  );
}

// ── 직방 스타일 공고 카드 마커 ────────────────────────────────────
class _JobMapCard extends StatelessWidget {
  final _Job job;
  final bool isSelected;
  const _JobMapCard({required this.job, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final bg = isSelected ? job.pinColor : Colors.white;
    final fg = isSelected ? Colors.white : AppColors.textPrimary;
    final border = isSelected ? job.pinColor : AppColors.border;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppRadius.sm),
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
              if (job.isUrgent)
                Text(
                  '긴급',
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w800,
                    color:
                        isSelected ? Colors.white.withValues(alpha: 0.9) : _red,
                  ),
                ),
              if (job.isUrgent) const SizedBox(height: 2),
              Text(
                job.payLabel ?? job.title,
                maxLines: 1,
                style: TextStyle(
                  fontSize: AppFontSize.body2,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
              if (isSelected && job.payLabel != null) ...[
                const SizedBox(height: 2),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    job.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppFontSize.caption,
                      color: fg.withValues(alpha: 0.8),
                    ),
                  ),
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
    final fillPaint =
        Paint()
          ..color = fill
          ..style = PaintingStyle.fill;
    final strokePaint =
        Paint()
          ..color = stroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
    final path =
        Path()
          ..moveTo(0, 0)
          ..lineTo(size.width, 0)
          ..lineTo(size.width / 2, size.height)
          ..close();
    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(_TrianglePainter o) =>
      o.fill != fill || o.stroke != stroke;
}

// ── 구직자 위치 도트 ──────────────────────────────────────────────
class _WorkerDot extends StatelessWidget {
  final _Worker worker;
  const _WorkerDot({required this.worker});

  Color get _color {
    if (worker.activityScore >= 100) return AppColors.gradeS; // S
    if (worker.activityScore >= 70) return AppColors.primary; // A
    if (worker.activityScore >= 40) return AppColors.gradeB; // B
    return AppColors.textTertiary; // C/NEW
  }

  String get _grade {
    if (worker.activityScore >= 100) return 'S';
    if (worker.activityScore >= 70) return 'A';
    if (worker.activityScore >= 40) return 'B';
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          _grade,
          style: const TextStyle(
            color: Colors.white,
            fontSize: AppFontSize.caption,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      ),
    );
  }
}

// ── 선택한 공고 하단 카드 (2026-10) ─────────────────────────────
// 접기·펼치기 2단 카드 → 한 장: 상태·제목 → 근무일·시간(크게) → 근처 알바생 수 → 할 수 있는 행동 하나.
// 잠긴 버튼 두 개('긴급 공고만'·'알림 이용 불가')는 누를 수 없는 걸 보여줄 뿐이라 한 줄 안내로 바꿨다.
class _MapJobSheet extends StatelessWidget {
  final _Job job;
  final int workerCount;
  final bool canBroadcast, broadcasting;
  final double bottomPad;
  final String? quota;
  final VoidCallback onOpenDetail, onUrgentCall, onBroadcast, onBuyPass;

  const _MapJobSheet({
    super.key,
    required this.job,
    required this.workerCount,
    required this.canBroadcast,
    required this.broadcasting,
    required this.bottomPad,
    required this.quota,
    required this.onOpenDetail,
    required this.onUrgentCall,
    required this.onBroadcast,
    required this.onBuyPass,
  });

  @override
  Widget build(BuildContext context) {
    final when = job.whenLabel;
    final badge =
        job.isReserved
            ? const JobSignalBadge(label: '공개 대기')
            : job.isUrgent
            ? const JobSignalBadge(label: '긴급', signal: JobSignal.time, icon: Icons.bolt_rounded)
            : const JobSignalBadge(label: '모집중', signal: JobSignal.trust);

    final Widget action;
    if (job.isReserved) {
      final p = job.publishAt!.toLocal();
      action = Text(
        '${p.month}월 ${p.day}일 ${p.hour.toString().padLeft(2, '0')}:${p.minute.toString().padLeft(2, '0')} 공개 예정 · 공개 전엔 알바생 지도에 안 보여요',
        style: AppTextStyles.body2,
      );
    } else if (job.isUrgent) {
      action = AppPrimaryButton(
        label: workerCount > 0 ? '근처 알바생 $workerCount명에게 긴급 호출' : '긴급 호출',
        height: 50,
        onPressed: onUrgentCall,
      );
    } else if (canBroadcast) {
      action = AppPrimaryButton(
        label: '근처 알바생에게 알림 보내기',
        height: 50,
        loading: broadcasting,
        onPressed: onBroadcast,
      );
    } else {
      action = GestureDetector(
        onTap: onBuyPass,
        behavior: HitTestBehavior.opaque,
        child: const Text.rich(
          TextSpan(
            style: AppTextStyles.body2,
            children: [
              TextSpan(text: '긴급 공고나 구독이면 근처 알바생에게 바로 알릴 수 있어요 · '),
              TextSpan(
                text: '이용권 보기 >',
                style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, -2))],
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 12, bottomPad + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onOpenDetail,
            child: Row(
              children: [
                badge,
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    job.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body2,
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textTertiary),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(when.isEmpty ? (job.payLabel ?? job.title) : when, style: AppTextStyles.h3),
                const SizedBox(height: 4),
                Text(
                  [
                    if (when.isNotEmpty && job.payLabel != null) job.payLabel!,
                    workerCount > 0 ? '근처 알바생 $workerCount명 (5km)' : '근처 5km 안 알바생 없음',
                    if (job.applicantCount > 0) '지원 ${job.applicantCount}명',
                  ].join(' · '),
                  style: AppTextStyles.body2,
                ),
                const SizedBox(height: 14),
                action,
                if (quota != null && canBroadcast) ...[
                  const SizedBox(height: 8),
                  Text(quota!, style: AppTextStyles.caption),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
