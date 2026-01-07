//worker_map_view.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:geocoding/geocoding.dart';
import 'package:iljujob/config/constants.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'worker_profile_screen.dart';

class WorkerMapView extends StatefulWidget {
  const WorkerMapView({super.key});

  @override
  State<WorkerMapView> createState() => _WorkerMapViewState();
}

class _WorkerMapViewState extends State<WorkerMapView> with WidgetsBindingObserver {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _workersRaw = [];
  List<Map<String, dynamic>> workers = [];

  bool isLoading = true;
  bool showOnlyAvailableToday = false;

  double _currentZoom = 14.0;
  Timer? _debounceTimer;
  bool _locationReady = false;
LatLng? _currentLocation;
  // 상수
  static const double _minZoom = 7.0;
  static const double _maxZoom = 19.0;
  static const Duration _searchDebounce = Duration(milliseconds: 300);
  static const Duration _networkTimeout = Duration(seconds: 10);

  // 대한민국 경계
  static final LatLngBounds KOREA_BOUNDS = LatLngBounds(
    const LatLng(33.0, 124.5),
    const LatLng(38.7, 132.1),
  );

  // 줌 버킷 (리빌드 최적화)
  static const _zoomBuckets = <int, double>{
    0: 20.0, // 7~9
    1: 28.0, // 10~12
    2: 36.0, // 13~15
    3: 46.0, // 16~19
  };

  int _zoomBucket(double z) {
    if (z < 10) return 0;
    if (z < 13) return 1;
    if (z < 16) return 2;
    return 3;
  }

  double _iconSizeForZoom(double z) => _zoomBuckets[_zoomBucket(z)]!;

Future<LatLng?> _getCurrentLocation() async {
  // 위치서비스 체크
  if (!await Geolocator.isLocationServiceEnabled()) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('위치 서비스가 꺼져 있어요. 켜주세요!')),
      );
    }
    return null;
  }

  // 권한 체크 & 요청
  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) return null;
  }
  if (permission == LocationPermission.deniedForever) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('설정에서 위치 접근 허용을 해주세요.')),
      );
    }
    return null;
  }

  // ✅ 1) 최근 위치(캐시된 위치)를 *즉시* 얻기 (1~50ms 수준)
  final lastPos = await Geolocator.getLastKnownPosition();
  if (lastPos != null) {
    // 일단 빠르게 화면 이동
    final quickLoc = LatLng(lastPos.latitude, lastPos.longitude);
    // 뒤에서 정확한 위치 다시 업데이트
    _updatePreciseLocationLater();
    return quickLoc;
  }

  // ✅ 2) 최근 위치가 없다면 → "빠른" 위치 먼저
  try {
    final quickPos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.low,
      timeLimit: const Duration(seconds: 2), // 오래 기다리지 않음
    );
    // 그리고 나중에 정밀 업데이트
    _updatePreciseLocationLater();
    return LatLng(quickPos.latitude, quickPos.longitude);
  } catch (_) {}

  // ✅ 3) 그래도 안 되면 → 정밀 위치 한 번만 시도 (최대 4초)
  try {
    final precisePos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
      timeLimit: const Duration(seconds: 4),
    );
    return LatLng(precisePos.latitude, precisePos.longitude);
  } catch (_) {
    return null;
  }
}

Future<void> _updatePreciseLocationLater() async {
  try {
    final precise = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
      timeLimit: const Duration(seconds: 6),
    );

    if (mounted) {
      setState(() => _currentLocation = LatLng(precise.latitude, precise.longitude));
      _mapController.move(_currentLocation!, 14); // 부드럽게 보정 이동
    }
  } catch (_) {}
}

@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addObserver(this);
  _searchController.addListener(_onSearchChanged);
  fetchWorkers();

}

  @override
  void dispose() {
    _debounceTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {});
  }

  void _applyKoreaFilter() {
    workers = _workersRaw.where((w) {
      final latRaw = w['lat'];
      final lngRaw = w['lng'];
      if (latRaw is! num || lngRaw is! num) return false;
      final p = LatLng(latRaw.toDouble(), lngRaw.toDouble());
      return KOREA_BOUNDS.contains(p);
    }).toList(growable: false);
  }

  void _centerToFirstOrDefault() {
    if (workers.isNotEmpty) {
      final w = workers.first;
      _mapController.move(
        LatLng((w['lat'] as num).toDouble(), (w['lng'] as num).toDouble()),
        13,
      );
    } else {
      _mapController.move(const LatLng(37.5665, 126.9780), 12);
    }
  }

  Future<void> fetchWorkers() async {
    if (!mounted) return;
    setState(() => isLoading = true);

    final endpoint = showOnlyAvailableToday
        ? '$baseUrl/api/worker/available-today'
        : '$baseUrl/api/worker/all';

    try {
      final response = await http
          .get(Uri.parse(endpoint), headers: {'Accept': 'application/json'})
          .timeout(_networkTimeout);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final cleaned = _parseAndValidateWorkers(response.body);

        setState(() {
          _workersRaw = cleaned;
          _applyKoreaFilter();
          isLoading = false;
        });

        if (workers.isNotEmpty) {

        } else {
          _centerToFirstOrDefault();
        }
      } else {
        setState(() => isLoading = false);
        _showErrorSnackBar('알바생 정보를 불러오지 못했습니다.');
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() => isLoading = false);
      _showErrorSnackBar('요청 시간이 초과되었습니다.');
    } on SocketException {
      if (!mounted) return;
      setState(() => isLoading = false);
      _showErrorSnackBar('네트워크 연결을 확인해주세요.');
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      debugPrint('❌ 알 수 없는 오류: $e');
      _showErrorSnackBar('오류가 발생했습니다.');
    }
  }

  List<Map<String, dynamic>> _parseAndValidateWorkers(String body) {
    try {
      final dynamic decoded = jsonDecode(body);
      final List<Map<String, dynamic>> items = (decoded is List)
          ? decoded.map<Map<String, dynamic>>((e) {
              if (e is Map<String, dynamic>) return e;
              if (e is Map) return Map<String, dynamic>.from(e);
              return <String, dynamic>{};
            }).toList()
          : <Map<String, dynamic>>[];

      return items.where(_isValidWorker).toList(growable: false);
    } catch (e) {
      debugPrint('❌ 파싱 오류: $e');
      return [];
    }
  }

  bool _isValidWorker(Map<String, dynamic> worker) {
    final latRaw = worker['lat'];
    final lngRaw = worker['lng'];
    if (latRaw is! num || lngRaw is! num) return false;

    final lat = latRaw.toDouble();
    final lng = lngRaw.toDouble();
    if (lat.isNaN || lng.isNaN || lat.isInfinite || lng.isInfinite) return false;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return false;

    return true;
  }

  void _fitCameraToBounds() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || workers.isEmpty) return;
      
      // 약간의 딜레이를 주고 실행 (맵이 완전히 렌더링된 후)
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!mounted) return;
        try {
          final bounds = LatLngBounds.fromPoints([
            for (final w in workers)
              LatLng((w['lat'] as num).toDouble(), (w['lng'] as num).toDouble()),
          ]);

          final effective = _intersectBounds(bounds, KOREA_BOUNDS) ?? KOREA_BOUNDS;

          _mapController.fitCamera(
            CameraFit.bounds(bounds: effective, padding: const EdgeInsets.all(32)),
          );
          
          // fitCamera 후 한 번 더 강제 렌더링
          Future.delayed(const Duration(milliseconds: 50), () {
            if (mounted) {
              _mapController.move(
                _mapController.camera.center,
                _mapController.camera.zoom,
              );
            }
          });
        } catch (e) {
          debugPrint('❌ 카메라 이동 실패: $e');
          _centerToFirstOrDefault();
        }
      });
    });
  }

  LatLngBounds? _intersectBounds(LatLngBounds a, LatLngBounds b) {
    final south = a.south > b.south ? a.south : b.south;
    final west = a.west > b.west ? a.west : b.west;
    final north = a.north < b.north ? a.north : b.north;
    final east = a.east < b.east ? a.east : b.east;
    if (south <= north && west <= east) {
      return LatLngBounds(LatLng(south, west), LatLng(north, east));
    }
    return null;
  }

  Future<void> _searchLocation() async {
  final query = _searchController.text.trim();
  if (query.isEmpty) return;

  try {
    final locations = await locationFromAddress(query);

    if (!mounted) return;

    if (locations.isEmpty) {
      // ✅ '실패' 대신 부드러운 안내
      _showErrorSnackBar(
        '아직 검색 결과가 없어요.\n'
        '조금 더 구체적인 위치나 지하철역, 동 이름으로 검색해 주세요.',
      );
      return;
    }

    final first = locations.first;
    final target = LatLng(first.latitude, first.longitude);

    if (!KOREA_BOUNDS.contains(target)) {
      _showErrorSnackBar('한국 외 지역은 아직 지원하지 않아요.');
      return;
    }

    _mapController.move(target, 13);
  } catch (e) {
    debugPrint('❌ 위치 검색 오류: $e');
    if (!mounted) return;
    // ✅ '실패' 대신 재시도/네트워크 안내
    _showErrorSnackBar(
      '잠시 연결이 불안정해요.\n'
      '네트워크 상태를 확인한 뒤 다시 한 번 시도해 주세요.',
    );
  }
}

void _showErrorSnackBar(String message) {
  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: const TextStyle(
          fontSize: 13,
          height: 1.4, // 줄 간격 확보
        ),
      ),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const SizedBox(
        height: 300,
        child: Center(child: CircularProgressIndicator()),
      );
    }

   return SafeArea(
  top: true,
  bottom: false, // ✅ 탭바 영역은 부모가 관리
  child: Stack(
    children: [
      _buildMap(),

      Positioned(
        top: 12,
        left: 12,
        right: 12,
        child: _buildSearchBar(),
      ),

     // ✅ 검색창보다 약간 더 아래
Positioned(
  top: 78, // ← 기존보다 +10~18 정도 내려주면 적당
  left: 12,
  right: 12,
  child: _SegmentToggle(
    value: showOnlyAvailableToday,
    onChanged: (val) async {
      setState(() => showOnlyAvailableToday = val);
      await fetchWorkers();
    },
  ),
),


    Positioned(
  left: 16,
  right: 16,
  bottom: MediaQuery.of(context).padding.bottom + 16, // ✅ 탭바 회피
  child: SizedBox(
    height: 48,
    child: ElevatedButton(
      onPressed: () => Navigator.pushNamed(context, "/post_job"),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.indigo,
        elevation: 2,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
   child: Row(
  mainAxisAlignment: MainAxisAlignment.center,
  children: const [
    Icon(Icons.add_circle_outline, color: Colors.white, size: 22),
    SizedBox(width: 8),
    Text(
      "공고 등록하기",
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.white,
        fontSize: 16,             // 살짝만 키움
        fontWeight: FontWeight.w600, // 너무 두껍지 않게
        letterSpacing: 0.4,       // 글자 간 여백 확보
        height: 1.2,
      ),
    ),
  ],
),
    ),
  ),
)
    ],
  ),
);



  }

 Widget _buildSearchBar() {
  return Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
    child: Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      child: TextField(
        controller: _searchController,
        onSubmitted: (_) => _searchLocation(),
        decoration: InputDecoration(
          
          hintText: '위치, 지하철역, 동 이름 검색',
           hintStyle: const TextStyle(
    fontSize: 14,
    letterSpacing: 0.2,
  ),
          prefixIcon: const Icon(Icons.search),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    ),
  );
}

Widget _buildMap() {
  return Positioned.fill(
    child: ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          center: const LatLng(37.5665, 126.9780),
          zoom: 12,
          minZoom: _minZoom,
          maxZoom: _maxZoom,
          cameraConstraint: CameraConstraint.contain(bounds: KOREA_BOUNDS),

          onMapReady: () async {
            // ✅ 지도 준비 완료 후 위치 가져오기
            final loc = await _getCurrentLocation();
            if (loc != null && mounted) {
              setState(() => _currentLocation = loc);
              _mapController.move(loc, 14);
            }
          },

          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
          ),
          onMapEvent: (evt) {
            _debounceTimer?.cancel();
            _debounceTimer = Timer(_searchDebounce, () {
              final z = _mapController.camera.zoom;
              if (_zoomBucket(z) != _zoomBucket(_currentZoom)) {
                setState(() => _currentZoom = z);
              } else {
                _currentZoom = z;
              }
            });
          },
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png',
            subdomains: const ['a', 'b', 'c'],
            userAgentPackageName: 'kr.co.iljujob',
          ),

          // ✅ 내 위치 마커
          if (_currentLocation != null)
            MarkerLayer(
              markers: [
                Marker(
                  point: _currentLocation!,
                  width: 20,
                  height: 20,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blueAccent,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                  ),
                ),
              ],
            ),

          // ✅ 알바생 마커
          _buildMarkerLayer(),
        ],
      ),
    ),
  );
}


  Widget _buildMarkerLayer() {
    return MarkerClusterLayerWidget(
      options: MarkerClusterLayerOptions(
        maxClusterRadius: 60,
        size: const Size(44, 44),
        alignment: Alignment.center,
        spiderfyCircleRadius: 60,
        spiderfySpiralDistanceMultiplier: 2,
        showPolygon: false,
        builder: (context, cluster) => Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.indigo.withOpacity(0.92),
            shape: BoxShape.circle,
          ),
          child: Text(
            '${cluster.length}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        markers: _buildMarkers(),
      ),
    );
  }

  List<Marker> _buildMarkers() {
    final size = _iconSizeForZoom(_currentZoom);

    return workers.map((w) {
      final pos = LatLng(
        (w['lat'] as num).toDouble(),
        (w['lng'] as num).toDouble(),
      );
      final imageUrl = (w['profileUrl'] ?? '').toString();
      final workerId = (w['id'] as num).toInt();

      return Marker(
        point: pos,
        width: size,
        height: size,
        alignment: Alignment.center,
        child: GestureDetector(
          
         child: _WorkerAvatar(imageUrl: imageUrl, size: size),
        ),
      );
    }).toList(growable: false);
  }

}

class _WorkerAvatar extends StatelessWidget {
  final String imageUrl;
  final double size;

  const _WorkerAvatar({
    required this.imageUrl,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return _buildPlaceholder();
    }

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        memCacheWidth: (size * 2).toInt(),
        memCacheHeight: (size * 2).toInt(),
        placeholder: (_, __) => SizedBox(
          width: size,
          height: size,
          child: const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        errorWidget: (_, __, ___) => _buildPlaceholder(),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: Colors.grey[300],
      child: Icon(
        Icons.person,
        size: size * 0.55,
        color: Colors.grey[700],
      ),
    );
  }
}class _SegmentToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SegmentToggle({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
  return Container(
  padding: const EdgeInsets.all(4),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: Colors.black12),
    boxShadow: [
      BoxShadow(
        color: Colors.black12.withOpacity(0.06),
        blurRadius: 5,
        offset: const Offset(0, 3),
      ),
    ],
  ),
  child: Row(
    children: [
      _buildOption("전체", !value, () => onChanged(false)),
      _buildOption("오늘 가능", value, () => onChanged(true)),
    ],
  ),
);
  }

  Widget _buildOption(String label, bool selected, VoidCallback onTap) {
  return Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
          vertical: 9,
        ),
        decoration: BoxDecoration(
          color: selected ? Colors.indigo : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            letterSpacing: 0.3, // 여백 확보
            color: selected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    ),
  );
}
}
