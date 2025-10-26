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

import 'worker_profile_screen.dart';

class WorkerMapSheet extends StatefulWidget {
  const WorkerMapSheet({super.key});

  @override
  State<WorkerMapSheet> createState() => _WorkerMapSheetState();
}

class _WorkerMapSheetState extends State<WorkerMapSheet> with WidgetsBindingObserver {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _workersRaw = [];
  List<Map<String, dynamic>> workers = [];

  bool isLoading = true;
  bool showOnlyAvailableToday = false;

  double _currentZoom = 14.0;
  Timer? _debounceTimer;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _searchController.addListener(_onSearchChanged);
    fetchWorkers();
    
    // 맵 로드 후 강제로 한 번 렌더링
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _mapController.move(_mapController.camera.center, _mapController.camera.zoom);
      }
    });
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
          _fitCameraToBounds();
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
      if (locations.isNotEmpty && mounted) {
        final lat = locations.first.latitude;
        final lng = locations.first.longitude;
        final target = LatLng(lat, lng);

        if (!KOREA_BOUNDS.contains(target)) {
          _showErrorSnackBar('검색 결과가 한국 외 지역입니다.');
          return;
        }

        _mapController.move(target, 13);
      }
    } catch (e) {
      debugPrint('❌ 위치 검색 실패: $e');
      if (!mounted) return;
      _showErrorSnackBar('위치 검색에 실패했습니다.');
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
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
      child: Padding(
        padding: MediaQuery.of(context).viewInsets,
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.85,
          child: Column(
            children: [
              _buildSearchAndFilter(),
              _buildHeader(),
              _buildMap(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchAndFilter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Material(
        elevation: 1,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                onSubmitted: (_) => _searchLocation(),
                decoration: InputDecoration(
                  hintText: '위치, 지하철역, 동 이름으로 검색',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  showOnlyAvailableToday
                      ? '오늘 가능한 알바생만 보는중'
                      : '전체 알바생 보는중',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                value: showOnlyAvailableToday,
                onChanged: (v) async {
                  setState(() => showOnlyAvailableToday = v);
                  await fetchWorkers();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          const Text(
            '알바생 위치',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.indigo.withOpacity(0.10),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${workers.length}명',
              style: const TextStyle(fontSize: 12, color: Colors.indigo),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '새로고침',
            onPressed: fetchWorkers,
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return Expanded(
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                center: const LatLng(37.5665, 126.9780),
                zoom: 12,
                minZoom: _minZoom,
                maxZoom: _maxZoom,
                cameraConstraint: CameraConstraint.contain(
                  bounds: KOREA_BOUNDS,
                ),
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.pinchZoom |
                      InteractiveFlag.drag |
                      InteractiveFlag.doubleTapZoom,
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
                  // 일단 OSM으로 복구 (안정적)
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName:
                      Platform.isAndroid ? 'kr.co.iljujob' : 'com.iljujob.kr',
                  maxZoom: 19,
                ),
                _buildMarkerLayer(),
              ],
            ),
            _buildFilterBadge(),
            _buildActionButtons(),
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
          onTap: () => _navigateToProfile(workerId),
          child: _WorkerAvatar(imageUrl: imageUrl, size: size),
        ),
      );
    }).toList(growable: false);
  }

  void _navigateToProfile(int workerId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WorkerProfileScreen(workerId: workerId),
      ),
    );
  }

  Widget _buildFilterBadge() {
    return Positioned(
      top: 10,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.55),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            showOnlyAvailableToday ? '오늘 가능한 알바생만 보기' : '전체 알바생 보기',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Positioned(
      right: 12,
      bottom: 12,
      child: Column(
        children: [
          _SmallFab(
            icon: Icons.my_location,
            onTap: () {
              final center = _mapController.camera.center;
              if (!KOREA_BOUNDS.contains(center)) {
                _mapController.move(const LatLng(37.5665, 126.9780), 12);
              } else {
                _centerToFirstOrDefault();
              }
            },
          ),
          const SizedBox(height: 8),
          _SmallFab(
            icon: Icons.refresh,
            onTap: fetchWorkers,
          ),
        ],
      ),
    );
  }
}

class _SmallFab extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _SmallFab({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 20),
        ),
      ),
    );
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
}