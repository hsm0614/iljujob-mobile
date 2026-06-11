// worker_map_view.dart — 내 공고 중심 지도 (긴급호출 통합)
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
const _surface  = Color(0xFFFFFFFF);
const _border   = Color(0xFFE5E8EB);
const _textMain  = Color(0xFF191F28);
const _textSub   = Color(0xFF6B7280);
const _red       = Color(0xFFEF4444);
const _green     = Color(0xFF22C55E);
const _orange    = Color(0xFFFF6B00);

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
  final bool   isPinned;

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
    required this.isPinned,
  });

  factory _JobPin.fromJson(Map<String, dynamic> j) => _JobPin(
        id:             (j['id'] ?? j['job_id'] ?? 0) as int,
        title:          (j['title'] ?? j['job_title'] ?? '').toString(),
        location:       (j['location_city'] ?? j['location'] ?? '').toString(),
        status:         (j['status'] ?? 'active').toString(),
        lat:            _toDouble(j['lat']),
        lng:            _toDouble(j['lng']),
        hourlyWage:     _toInt(j['hourly_wage'] ?? j['wage']),
        startDate:      (j['start_date'] ?? '').toString(),
        applicantCount: _toInt(j['applicant_count'] ?? j['applicants']),
        isPinned:       j['is_pinned'] == true || j['is_pinned'] == 1,
      );

  static double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  bool get hasLocation => lat != 0.0 && lng != 0.0;
  LatLng get position  => LatLng(lat, lng);

  Color get statusColor {
    if (isPinned)        return _orange;
    if (status == 'active')   return _green;
    if (status == 'reserved') return _primary;
    return _textSub;
  }

  String get statusLabel {
    if (isPinned)        return '긴급';
    if (status == 'active')   return '진행';
    if (status == 'reserved') return '예약';
    return status;
  }
}

// ── 메인 위젯 ─────────────────────────────────────────────────────
class WorkerMapView extends StatefulWidget {
  const WorkerMapView({super.key});

  @override
  State<WorkerMapView> createState() => _WorkerMapViewState();
}

class _WorkerMapViewState extends State<WorkerMapView> {
  final _mapCtrl = MapController();

  List<_JobPin> _jobs        = [];
  bool          _loading     = true;
  int?          _clientId;
  LatLng?       _myLocation;

  // 공고별 반경 내 가능 인원 캐시
  final Map<int, int> _nearbyCount = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _clientId = prefs.getInt('userId');
    await Future.wait([_fetchJobs(), _initLocation()]);
  }

  // ── 내 공고 로딩 ──────────────────────────────────────────────
  Future<void> _fetchJobs() async {
    if (_clientId == null) return;
    setState(() => _loading = true);
    try {
      final res = await http
          .get(Uri.parse(
              '$baseUrl/api/job/my-jobs?clientId=$_clientId&status=active'))
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final dynamic raw = jsonDecode(res.body);
        final List<dynamic> list = raw is List
            ? raw
            : (raw is Map ? ((raw['jobs'] ?? raw['data'] ?? []) as List) : []);
        setState(() {
          _jobs = list
              .whereType<Map<String, dynamic>>()
              .map(_JobPin.fromJson)
              .where((j) => j.hasLocation)
              .toList();
          _loading = false;
        });
        // 지도 범위 맞추기
        if (_jobs.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _fitBounds());
        }
      } else {
        setState(() => _loading = false);
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
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) return null;
    }
    if (perm == LocationPermission.deniedForever) return null;
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 4),
      );
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }

  void _fitBounds() {
    if (_jobs.isEmpty) return;
    final lats = _jobs.map((j) => j.lat);
    final lngs = _jobs.map((j) => j.lng);
    final bounds = LatLngBounds(
      LatLng(lats.reduce((a, b) => a < b ? a : b) - 0.01,
             lngs.reduce((a, b) => a < b ? a : b) - 0.01),
      LatLng(lats.reduce((a, b) => a > b ? a : b) + 0.01,
             lngs.reduce((a, b) => a > b ? a : b) + 0.01),
    );
    _mapCtrl.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(60)),
    );
  }

  // ── 반경 내 가능 인원 조회 ─────────────────────────────────────
  Future<int> _fetchNearbyCount(int jobId) async {
    if (_nearbyCount.containsKey(jobId)) return _nearbyCount[jobId]!;
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/api/direct-messages/nearby-count?jobId=$jobId'))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final count = (jsonDecode(res.body)['count'] as num?)?.toInt() ?? 0;
        _nearbyCount[jobId] = count;
        return count;
      }
    } catch (_) {}
    return 0;
  }

  // ── 공고 핀 탭 → 바텀시트 ─────────────────────────────────────
  void _onPinTap(_JobPin job) async {
    final count = await _fetchNearbyCount(job.id);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _JobBottomSheet(
        job: job,
        nearbyCount: count,
        onUrgentCall: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => NearbyWorkersScreen(
                jobId: job.id,
                clientId: _clientId ?? 0,
                jobTitle: job.title,
              ),
            ),
          );
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

    return Stack(
      children: [
        // 지도
        FlutterMap(
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
            TileLayer(
              urlTemplate:
                  'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              userAgentPackageName: 'kr.co.iljujob',
            ),
            // 내 위치 점
            if (_myLocation != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _myLocation!,
                    width: 18,
                    height: 18,
                    child: Container(
                      decoration: BoxDecoration(
                        color: _primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: _primary.withValues(alpha: 0.4),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            // 공고 핀
            MarkerLayer(
              markers: _jobs.map((job) {
                return Marker(
                  point: job.position,
                  width: 56,
                  height: 64,
                  alignment: Alignment.topCenter,
                  child: GestureDetector(
                    onTap: () => _onPinTap(job),
                    child: _JobMarker(job: job),
                  ),
                );
              }).toList(),
            ),
          ],
        ),

        // 로딩
        if (_loading)
          Container(
            color: Colors.white.withValues(alpha: 0.7),
            child: const Center(
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: _primary),
            ),
          ),

        // 공고 없음 안내
        if (!_loading && _jobs.isEmpty)
          Positioned(
            top: 70,
            left: 24,
            right: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: _textSub, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '위치 정보가 있는 활성 공고가 없어요.',
                      style: TextStyle(
                          fontSize: 13,
                          color: _textSub,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // 우측 하단 FAB 버튼들
        Positioned(
          right: 16,
          bottom: bottomPad + 80,
          child: Column(
            children: [
              // 내 위치
              _Fab(
                icon: Icons.my_location_rounded,
                onTap: () async {
                  if (_myLocation != null) {
                    _mapCtrl.move(_myLocation!, 14);
                  } else {
                    final loc = await _getLocation();
                    if (loc != null && mounted) {
                      setState(() => _myLocation = loc);
                      _mapCtrl.move(loc, 14);
                    }
                  }
                },
              ),
              const SizedBox(height: 10),
              // 공고 범위 맞추기
              _Fab(
                icon: Icons.fit_screen_rounded,
                onTap: _jobs.isNotEmpty ? _fitBounds : null,
              ),
              const SizedBox(height: 10),
              // 새로고침
              _Fab(
                icon: Icons.refresh_rounded,
                onTap: _fetchJobs,
              ),
            ],
          ),
        ),

        // 하단 공고 등록 버튼
        Positioned(
          left: 16,
          right: 16,
          bottom: bottomPad + 16,
          child: SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/post_job'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text(
                '공고 등록하기',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ],
    );
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
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: job.statusColor,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: job.statusColor.withValues(alpha: 0.4),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Text(
            job.statusLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        // 삼각형 꼬리 (Transform 방식 — Path 충돌 회피)
        Transform.rotate(
          angle: 0.785,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: job.statusColor,
              borderRadius: const BorderRadius.only(
                bottomRight: Radius.circular(2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── FAB 버튼 ─────────────────────────────────────────────────────
class _Fab extends StatelessWidget {
  final IconData     icon;
  final VoidCallback? onTap;
  const _Fab({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: _surface,
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
        child: Icon(
          icon,
          color: onTap != null ? _primary : _textSub,
          size: 22,
        ),
      ),
    );
  }
}

// ── 공고 바텀시트 ─────────────────────────────────────────────────
class _JobBottomSheet extends StatelessWidget {
  final _JobPin      job;
  final int          nearbyCount;
  final VoidCallback onUrgentCall;
  final VoidCallback onViewApplicants;

  const _JobBottomSheet({
    required this.job,
    required this.nearbyCount,
    required this.onUrgentCall,
    required this.onViewApplicants,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final wage = job.hourlyWage > 0
        ? '시급 ${_comma(job.hourlyWage)}원'
        : null;
    final date = job.startDate.length >= 10
        ? job.startDate.substring(0, 10)
        : job.startDate;

    return Container(
      decoration: const BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPad + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 핸들
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: _border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // 공고 상태 + 제목
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: job.statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  job.statusLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: job.statusColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  job.title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _textMain,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // 위치·날짜·시급
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              if (job.location.isNotEmpty)
                _meta(Icons.location_on_rounded, job.location),
              if (date.isNotEmpty) _meta(Icons.calendar_today_rounded, date),
              if (wage != null) _meta(Icons.payments_rounded, wage),
            ],
          ),

          const SizedBox(height: 16),
          const Divider(color: _border, height: 1),
          const SizedBox(height: 16),

          // 반경 내 가능 인원 카드
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
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.people_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '반경 3km 내 가능한 알바생',
                      style: const TextStyle(
                          fontSize: 12, color: _textSub),
                    ),
                    const SizedBox(height: 2),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '$nearbyCount명',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: _primary,
                            ),
                          ),
                          const TextSpan(
                            text: ' 오늘 연락 가능',
                            style: TextStyle(
                              fontSize: 13,
                              color: _textSub,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 액션 버튼 2개
          Row(
            children: [
              // 지원자 보기
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onViewApplicants,
                  icon: const Icon(Icons.people_outline_rounded, size: 18),
                  label: Text('지원자 ${job.applicantCount}명 보기'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _primary,
                    side: const BorderSide(color: _primary),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // 긴급 호출
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: nearbyCount > 0 ? onUrgentCall : null,
                  icon: const Icon(Icons.emergency_rounded, size: 18),
                  label: const Text('긴급 호출'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _red,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFD1D5DB),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
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
          Icon(icon, size: 13, color: _textSub),
          const SizedBox(width: 3),
          Text(text,
              style: const TextStyle(fontSize: 13, color: _textSub)),
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
