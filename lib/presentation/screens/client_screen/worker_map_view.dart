// worker_map_view.dart — 카카오맵 기반 공고 지도
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:kakao_maps_flutter/kakao_maps_flutter.dart' as km;
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:iljujob/config/constants.dart';
import 'nearby_workers_screen.dart';

// ── 디자인 토큰 ───────────────────────────────────────────────────
const _primary = Color(0xFF3B8AFF);
const _border = Color(0xFFE5E8EB);
const _textMain = Color(0xFF191F28);
const _textSub = Color(0xFF6B7280);
const _red = Color(0xFFFF3B30);
const _green = Color(0xFF22C55E);
const _purple = Color(0xFF8B5CF6);
const _jobMarkerLayerId = 'iljujob_job_markers';
const _workerMarkerLayerId = 'iljujob_worker_markers';

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

  Color get pinColor {
    if (isUrgent) return _red;
    if (status == 'active') return _primary;
    return _textSub;
  }

  String get statusLabel {
    if (isUrgent) return '긴급';
    if (status == 'active') return '진행중';
    if (status == 'reserved') return '예약';
    return '마감';
  }
}

// ── 구직자 모델 ───────────────────────────────────────────────────
class _Worker {
  final int id;
  final String name;
  final double lat, lng;
  final int activityScore;

  const _Worker({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.activityScore,
  });

  factory _Worker.fromJson(Map<String, dynamic> j) => _Worker(
    id: _i(j['id']),
    name: (j['name'] ?? '').toString(),
    lat: _d(j['lat']),
    lng: _d(j['lng']),
    activityScore: _i(j['activity_score']),
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

Future<Uint8List> _pngFromPainter({
  required Size size,
  required void Function(Canvas canvas) paint,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  paint(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.ceil(), size.height.ceil());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}

void _drawText(
  Canvas canvas,
  String text,
  Offset offset, {
  required TextStyle style,
  double maxWidth = double.infinity,
  TextAlign align = TextAlign.left,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textAlign: align,
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth);
  painter.paint(canvas, offset);
}

Future<Uint8List> _jobMarkerBytes(_Job job, {required bool selected}) {
  final label = job.hourlyWage > 0 ? '₩${_comma(job.hourlyWage)}' : job.title;
  final subLabel = job.isUrgent ? '긴급' : job.statusLabel;
  final bg = selected ? job.pinColor : Colors.white;
  final fg = selected ? Colors.white : _textMain;
  final border = selected ? job.pinColor : _border;
  final width = selected ? 104.0 : 88.0;
  const height = 58.0;

  return _pngFromPainter(
    size: const Size(116, 72),
    paint: (canvas) {
      final shadow =
          Paint()
            ..color = Colors.black.withValues(alpha: selected ? 0.20 : 0.12)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH((116 - width) / 2, 5, width, height - 12),
        const Radius.circular(12),
      );
      canvas.drawRRect(rect.shift(const Offset(0, 3)), shadow);
      canvas.drawRRect(rect, Paint()..color = bg);
      canvas.drawRRect(
        rect,
        Paint()
          ..color = border
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2 : 1,
      );

      _drawText(
        canvas,
        subLabel,
        Offset((116 - width) / 2, 10),
        maxWidth: width,
        align: TextAlign.center,
        style: TextStyle(
          color: selected ? Colors.white.withValues(alpha: 0.9) : job.pinColor,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      );
      _drawText(
        canvas,
        label,
        Offset((116 - width) / 2 + 6, 27),
        maxWidth: width - 12,
        align: TextAlign.center,
        style: TextStyle(color: fg, fontSize: 15, fontWeight: FontWeight.w900),
      );

      final pointer =
          Path()
            ..moveTo(52, height - 7)
            ..lineTo(64, height - 7)
            ..lineTo(58, height + 1)
            ..close();
      canvas.drawPath(pointer, Paint()..color = bg);
      canvas.drawPath(
        pointer,
        Paint()
          ..color = border
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    },
  );
}

Future<Uint8List> _workerMarkerBytes(String grade, Color color) {
  return _pngFromPainter(
    size: const Size(42, 42),
    paint: (canvas) {
      canvas.drawCircle(
        const Offset(21, 21),
        17,
        Paint()..color = Colors.black.withValues(alpha: 0.18),
      );
      canvas.drawCircle(const Offset(21, 19), 15, Paint()..color = color);
      canvas.drawCircle(
        const Offset(21, 19),
        15,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      _drawText(
        canvas,
        grade,
        const Offset(0, 10),
        maxWidth: 42,
        align: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w900,
        ),
      );
    },
  );
}

Color _workerGradeColor(String grade) {
  if (grade == 'S') return const Color(0xFFFF6B00);
  if (grade == 'A') return _primary;
  if (grade == 'B') return _green;
  return const Color(0xFF9CA3AF);
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
  StreamSubscription<km.LabelClickEvent>? _labelSub;
  bool _mapReady = false;
  bool _markerLayersReady = false;

  final _scrollCtrl = ScrollController();
  List<_Job> _jobs = [];
  List<_Worker> _currentWorkers = [];
  int? _selectedIdx;
  int _workerCount = 0;
  bool _loading = true;
  bool _workersLoading = false;
  bool _isSubscribed = false;
  int _urgentCredits = 0;
  bool _broadcastSending = false;

  int? _clientId;
  String? _authToken;

  final Map<int, int> _countCache = {};
  final Map<int, List<_Worker>> _dotCache = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _labelSub?.cancel();
    _cameraSub?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _clientId = prefs.getInt('userId');
    _authToken = prefs.getString('authToken') ?? '';
    await Future.wait([_fetchJobs(), _fetchSubscription()]);
  }

  Map<String, String> get _auth =>
      (_authToken?.isNotEmpty ?? false)
          ? {'Authorization': 'Bearer $_authToken'}
          : {};

  // ── 구독 + 이용권 상태 ────────────────────────────────────────
  Future<void> _fetchSubscription() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/api/subscription/status'), headers: _auth)
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 200 && mounted) {
        final d = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _isSubscribed = d['active'] == true;
          _urgentCredits = (d['credits'] as Map?)?['urgent'] as int? ?? 0;
        });
      }
    } catch (_) {}
  }

  bool get _canUrgentCall => _isSubscribed || _urgentCredits > 0;

  // ── 내 공고 ───────────────────────────────────────────────────
  Future<void> _fetchJobs() async {
    if (_clientId == null) {
      debugPrint('[MAP][JOBS] clientId null — 중단');
      return;
    }
    if (mounted) setState(() => _loading = true);
    debugPrint('[MAP][JOBS] 요청 시작 clientId=$_clientId');
    try {
      final res = await http
          .get(
            Uri.parse('$baseUrl/api/job/my-jobs?clientId=$_clientId&limit=50'),
            headers: _auth,
          )
          .timeout(const Duration(seconds: 10));
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
            '[MAP][JOBS] mapReady=true → selectJob(0) + native marker refresh',
          );
          _selectJob(0);
          await _refreshNativeMarkers();
        } else {
          debugPrint(
            '[MAP][JOBS] mapReady=$_mapReady, jobs=${jobs.length} → 지도 준비 대기',
          );
          if (_mapReady) await _refreshNativeMarkers();
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
      debugPrint('[MAP] onCameraMoveEnd');
    });
    _labelSub = ctrl.onLabelClickedStream.listen((event) {
      debugPrint('[MAP] label click ${event.labelId}');
      if (event.labelId.startsWith('job:')) {
        final jobId = int.tryParse(event.labelId.substring(4));
        final idx = jobId == null ? -1 : _jobs.indexWhere((j) => j.id == jobId);
        if (idx >= 0) _selectJob(idx);
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
    await _ensureMarkerLayers();
    if (!mounted) return;
    _mapReady = true;
    debugPrint('[MAP] _setupMap 완료 — mapReady=true, jobs=${_jobs.length}');
    if (_jobs.isNotEmpty) {
      _selectJob(0);
      await _refreshNativeMarkers();
    }
  }

  Future<void> _ensureMarkerLayers() async {
    if (_ctrl == null || _markerLayersReady) return;
    try {
      await _ctrl!.addMarkerLayer(
        layerId: _jobMarkerLayerId,
        zOrder: 3000,
        clickable: true,
      );
      await _ctrl!.addMarkerLayer(
        layerId: _workerMarkerLayerId,
        zOrder: 2500,
        clickable: false,
      );
      _markerLayersReady = true;
      debugPrint('[MAP][MARKER] marker layers ready');
    } catch (e) {
      _markerLayersReady = true;
      debugPrint('[MAP][MARKER] marker layer create skipped/fail: $e');
    }
  }

  Future<void> _refreshNativeMarkers() async {
    if (_ctrl == null || !_mapReady || !mounted) return;
    await _ensureMarkerLayers();

    final selectedJobId = _selectedJob?.id;
    final jobsWithLoc = _jobs.where((j) => j.hasLocation).toList();
    final workersWithLoc = _currentWorkers.where((w) => w.hasLocation).toList();
    debugPrint(
      '[MAP][MARKER] refresh jobs=${jobsWithLoc.length}, workers=${workersWithLoc.length}, selected=$selectedJobId',
    );

    try {
      await _ctrl!.clearMarkers(layerId: _jobMarkerLayerId);
      await _ctrl!.clearMarkers(layerId: _workerMarkerLayerId);
    } catch (e) {
      debugPrint('[MAP][MARKER] clear fail: $e');
    }

    final styles = <km.MarkerStyle>[];
    final jobMarkers = <km.MarkerOption>[];
    for (final entry in jobsWithLoc.asMap().entries) {
      final job = entry.value;
      final selected = job.id == selectedJobId;
      final styleId =
          'job_${job.id}_${selected ? 'selected' : 'normal'}_${job.isUrgent ? 'urgent' : 'active'}';
      styles.add(
        km.MarkerStyle(
          styleId: styleId,
          perLevels: [
            km.MarkerPerLevelStyle.fromBytes(
              bytes: await _jobMarkerBytes(job, selected: selected),
            ),
          ],
        ),
      );
      jobMarkers.add(
        km.MarkerOption(
          id: 'job:${job.id}',
          latLng: job.pos,
          styleId: styleId,
          rank: selected ? 10000 : 9000 - entry.key,
        ),
      );
    }

    for (final grade in const ['S', 'A', 'B', 'C']) {
      styles.add(
        km.MarkerStyle(
          styleId: 'worker_$grade',
          perLevels: [
            km.MarkerPerLevelStyle.fromBytes(
              bytes: await _workerMarkerBytes(grade, _workerGradeColor(grade)),
            ),
          ],
        ),
      );
    }

    try {
      if (styles.isNotEmpty) {
        await _ctrl!.registerMarkerStyles(styles: styles);
      }
      if (jobMarkers.isNotEmpty) {
        await _ctrl!.addMarkers(
          markerOptions: jobMarkers,
          layerId: _jobMarkerLayerId,
        );
      }
      if (workersWithLoc.isNotEmpty) {
        await _ctrl!.addMarkers(
          markerOptions:
              workersWithLoc
                  .map(
                    (w) => km.MarkerOption(
                      id: 'worker:${w.id}',
                      latLng: w.pos,
                      styleId: 'worker_${w.grade}',
                      rank: 1000 + w.activityScore,
                    ),
                  )
                  .toList(),
          layerId: _workerMarkerLayerId,
        );
      }
      debugPrint('[MAP][MARKER] refresh done');
    } catch (e) {
      debugPrint('[MAP][MARKER] refresh fail: $e');
    }
  }

  // ── 공고 선택 ─────────────────────────────────────────────────
  void _selectJob(int idx) {
    debugPrint('[MAP] selectJob($idx)');
    if (idx < 0 || idx >= _jobs.length) return;
    setState(() {
      _selectedIdx = idx;
      _workerCount = 0;
      _currentWorkers = [];
    });
    unawaited(_refreshNativeMarkers());
    final job = _jobs[idx];
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
    }
    if (job.hasLocation) {
      _loadWorkers(job);
    } else {
      debugPrint('[MAP] hasLocation=false → _loadWorkers 스킵');
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
    await _refreshNativeMarkers();

    // 알바생이 있으면 공고 + 모든 알바생 위치를 한 화면에 fitPoints
    final workersWithLoc = workers.where((w) => w.hasLocation).toList();
    if (_ctrl != null && workersWithLoc.isNotEmpty) {
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
    } else if (_mapReady) {
      await _refreshNativeMarkers();
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
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      _showSnack(
        res.statusCode == 200
            ? '${body['sentCount'] ?? 0}명에게 알림을 발송했어요!'
            : (body['message']?.toString() ?? '발송 실패'),
        isError: res.statusCode != 200,
      );
    } catch (_) {
      if (mounted) _showSnack('네트워크 오류', isError: true);
    } finally {
      if (mounted) setState(() => _broadcastSending = false);
    }
  }

  void _showSnack(String msg, {required bool isError}) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: isError ? _red : _green,
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
          child: km.KakaoMap(
            initialPosition: const km.LatLng(
              latitude: 37.5665,
              longitude: 126.9780,
            ),
            initialLevel: 5,
            onMapCreated: _onMapCreated,
          ),
        ),

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
                          borderRadius: BorderRadius.circular(20),
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
                            color: _primary,
                          ),
                        ),
                      ),
                    )
                    : _jobs.isEmpty
                    ? Center(
                      child: _chipContainer(
                        child: const Text(
                          '등록된 공고 없음',
                          style: TextStyle(fontSize: 12, color: _textSub),
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
                              color: sel ? job.pinColor : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: sel ? Colors.transparent : _border,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: sel ? 0.14 : 0.07,
                                  ),
                                  blurRadius: sel ? 14 : 7,
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
                                    color:
                                        sel
                                            ? Colors.white.withValues(
                                              alpha: 0.75,
                                            )
                                            : job.pinColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  job.title.length > 11
                                      ? '${job.title.substring(0, 11)}…'
                                      : job.title,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: sel ? Colors.white : _textMain,
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
                                              : _primary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      '${job.applicantCount}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
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

        // ── 우측 FAB (collapsed 카드 높이 165 + safe area 위에 고정) ──
        Positioned(
          right: 14,
          bottom: 175 + bottomPad,
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
            bottom: 179 + bottomPad,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
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
                  color: _primary,
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
            child: _ExpandableJobCard(
              key: ValueKey(_selectedJob!.id),
              job: _selectedJob!,
              workerCount: _workerCount,
              canUrgentCall: _canUrgentCall,
              isSubscribed: _isSubscribed,
              broadcasting: _broadcastSending,
              bottomPad: bottomPad,
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
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 8),
      ],
    ),
    child: child,
  );

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
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
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
    required this.job,
    required this.workerCount,
    required this.canUrgentCall,
    required this.isSubscribed,
    required this.broadcasting,
    required this.bottomPad,
    required this.onUrgentCall,
    required this.onBroadcast,
    required this.onBuyPass,
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
        if ((d.primaryVelocity ?? 0) > 250 && _expanded) _toggle();
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 18,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                      color:
                          _expanded ? _primary.withValues(alpha: 0.5) : _border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),

            // 헤더: 상태 뱃지 + 제목 + 구직자 수
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: job.pinColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      job.statusLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: job.pinColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      job.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: _textMain,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.people_alt_rounded,
                        size: 14,
                        color: widget.workerCount > 0 ? _primary : _textSub,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        widget.workerCount > 0
                            ? '${widget.workerCount}명'
                            : '없음',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: widget.workerCount > 0 ? _primary : _textSub,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Text(
                        '5km',
                        style: TextStyle(fontSize: 10, color: _textSub),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 확장 컨텐츠
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 220),
              sizeCurve: Curves.easeOut,
              crossFadeState:
                  _expanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
              firstChild: _CollapsedMeta(
                job: job,
                bottomPad: widget.bottomPad,
                canUrgentCall: widget.canUrgentCall,
                isSubscribed: widget.isSubscribed,
                broadcasting: widget.broadcasting,
                onUrgentCall: widget.onUrgentCall,
                onBroadcast: widget.onBroadcast,
                onBuyPass: widget.onBuyPass,
              ),
              secondChild: _ExpandedDetail(
                job: job,
                bottomPad: widget.bottomPad,
                canUrgentCall: widget.canUrgentCall,
                isSubscribed: widget.isSubscribed,
                broadcasting: widget.broadcasting,
                onUrgentCall: widget.onUrgentCall,
                onBroadcast: widget.onBroadcast,
                onBuyPass: widget.onBuyPass,
              ),
            ),
          ],
        ),
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
    required this.job,
    required this.bottomPad,
    required this.canUrgentCall,
    required this.isSubscribed,
    required this.broadcasting,
    required this.onUrgentCall,
    required this.onBroadcast,
    required this.onBuyPass,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 0, 18, bottomPad + 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 한 줄 메타
          if (job.location.isNotEmpty ||
              job.hourlyWage > 0 ||
              job.timeRange.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  if (job.startDate.isNotEmpty) ...[
                    const Icon(
                      Icons.calendar_today_rounded,
                      size: 11,
                      color: _textSub,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      job.startDate,
                      style: const TextStyle(fontSize: 12, color: _textSub),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (job.timeRange.isNotEmpty) ...[
                    const Icon(
                      Icons.access_time_rounded,
                      size: 11,
                      color: _textSub,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      job.timeRange,
                      style: const TextStyle(fontSize: 12, color: _textSub),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (job.hourlyWage > 0) ...[
                    const Icon(
                      Icons.payments_rounded,
                      size: 11,
                      color: _textSub,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      _comma(job.hourlyWage),
                      style: const TextStyle(fontSize: 12, color: _textSub),
                    ),
                  ],
                ],
              ),
            )
          else
            const SizedBox(height: 12),
          _ActionRow(
            canUrgentCall: canUrgentCall,
            isSubscribed: isSubscribed,
            broadcasting: broadcasting,
            onUrgentCall: onUrgentCall,
            onBroadcast: onBroadcast,
            onBuyPass: onBuyPass,
          ),
        ],
      ),
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
    required this.job,
    required this.bottomPad,
    required this.canUrgentCall,
    required this.isSubscribed,
    required this.broadcasting,
    required this.onUrgentCall,
    required this.onBroadcast,
    required this.onBuyPass,
  });

  @override
  Widget build(BuildContext context) {
    final metaRows = <(IconData, String, String)>[
      if (job.startDate.isNotEmpty)
        (Icons.calendar_today_rounded, '날짜', job.startDate),
      if (job.timeRange.isNotEmpty)
        (Icons.access_time_rounded, '시간', job.timeRange),
      if (job.location.isNotEmpty) (Icons.place_rounded, '위치', job.location),
      if (job.category.isNotEmpty)
        (Icons.work_outline_rounded, '직종', job.category),
      if (job.applicantCount > 0)
        (Icons.how_to_reg_rounded, '지원', '${job.applicantCount}명'),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(18, 4, 18, bottomPad + 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
              child: Row(
                children: [
                  const Icon(Icons.payments_rounded, size: 16, color: _primary),
                  const SizedBox(width: 8),
                  Text(
                    '시급 ${_comma(job.hourlyWage)}원',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: _primary,
                    ),
                  ),
                ],
              ),
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
              child: Column(
                children: [
                  for (int i = 0; i < metaRows.length; i++) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Row(
                        children: [
                          Icon(metaRows[i].$1, size: 14, color: _textSub),
                          const SizedBox(width: 8),
                          Text(
                            metaRows[i].$2,
                            style: const TextStyle(
                              fontSize: 12,
                              color: _textSub,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              metaRows[i].$3,
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                color: _textMain,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (i < metaRows.length - 1)
                      const Divider(height: 1, color: _border),
                  ],
                ],
              ),
            ),

          // 공고 설명
          if (job.description.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              '공고 설명',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: _textSub,
              ),
            ),
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
                style: const TextStyle(
                  fontSize: 13,
                  color: _textMain,
                  height: 1.6,
                ),
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],

          const SizedBox(height: 12),
          _ActionRow(
            canUrgentCall: canUrgentCall,
            isSubscribed: isSubscribed,
            broadcasting: broadcasting,
            onUrgentCall: onUrgentCall,
            onBroadcast: onBroadcast,
            onBuyPass: onBuyPass,
          ),
        ],
      ),
    );
  }
}

// ── 공통 액션 버튼 행 ─────────────────────────────────────────────
class _ActionRow extends StatelessWidget {
  final bool canUrgentCall, isSubscribed, broadcasting;
  final VoidCallback onUrgentCall, onBroadcast, onBuyPass;

  const _ActionRow({
    required this.canUrgentCall,
    required this.isSubscribed,
    required this.broadcasting,
    required this.onUrgentCall,
    required this.onBroadcast,
    required this.onBuyPass,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child:
              canUrgentCall
                  ? _Btn(
                    label: '긴급 호출',
                    icon: Icons.emergency_rounded,
                    color: _red,
                    filled: true,
                    onTap: onUrgentCall,
                  )
                  : _Btn(
                    label: '이용권 구매',
                    icon: Icons.add_shopping_cart_rounded,
                    color: _textSub,
                    filled: false,
                    onTap: onBuyPass,
                  ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child:
              isSubscribed
                  ? _Btn(
                    label: broadcasting ? '발송 중…' : '알림 발송',
                    icon:
                        broadcasting
                            ? Icons.hourglass_top_rounded
                            : Icons.campaign_rounded,
                    color: _purple,
                    filled: false,
                    onTap: broadcasting ? null : onBroadcast,
                  )
                  : _Btn(
                    label: '구독 시 발송',
                    icon: Icons.lock_rounded,
                    color: _textSub,
                    filled: false,
                    onTap: () => Navigator.pushNamed(context, '/subscribe'),
                  ),
        ),
      ],
    );
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
  final String label;
  final IconData icon;
  final Color color;
  final bool filled;
  final VoidCallback? onTap;

  const _Btn({
    required this.label,
    required this.icon,
    required this.color,
    required this.filled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dis = onTap == null;
    final bg =
        filled ? (dis ? const Color(0xFFD1D5DB) : color) : Colors.transparent;
    final fg = filled ? Colors.white : (dis ? _textSub : color);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: filled ? null : Border.all(color: dis ? _border : color),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
