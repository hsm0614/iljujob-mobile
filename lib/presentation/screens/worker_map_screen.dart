import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:iljujob/config/constants.dart';
import 'package:http/http.dart' as http;
import 'package:kakao_map_sdk/kakao_map_sdk.dart';

import 'worker_profile_screen.dart';
import 'dart:math' as math;

class WorkerMapSheet extends StatefulWidget {
  const WorkerMapSheet({super.key});

  @override
  State<WorkerMapSheet> createState() => _WorkerMapSheetState();
}

class _WorkerMapSheetState extends State<WorkerMapSheet> with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> workers = [];
  bool isLoading = true;
  bool showOnlyAvailableToday = false;

  KakaoMapController? _mapController;
  static const LatLng _defaultCenter = LatLng(37.5665, 126.9780);

  // 렌더링 상태 관리
  final Map<String, KImage> _iconCache = {};
  int _lastZoomLevel = -1;
  Timer? _renderDebounce;
  bool _isRendering = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    fetchWorkers();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _renderDebounce?.cancel();
    _iconCache.clear();
    super.dispose();
  }

  // Worker 데이터 가져오기
  Future<void> fetchWorkers() async {
    if (!mounted) return;
    setState(() => isLoading = true);

    final endpoint = showOnlyAvailableToday
        ? '$baseUrl/api/worker/available-today'
        : '$baseUrl/api/worker/all';

    try {
      final response = await http
          .get(Uri.parse(endpoint), headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final dynamic decoded = jsonDecode(response.body);
        final List<Map<String, dynamic>> items = _parseWorkerData(decoded);
        final cleaned = _validateWorkerCoordinates(items);

        if (!mounted) return;
        setState(() {
          workers = cleaned;
          isLoading = false;
        });

        if (_mapController != null) {
          await _renderWorkers();
          await _fitToWorkersOrCenter();
        }
      } else {
        if (!mounted) return;
        setState(() => isLoading = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      debugPrint('Worker 데이터 로딩 실패: $e');
    }
  }

  List<Map<String, dynamic>> _parseWorkerData(dynamic decoded) {
    if (decoded is! List) return [];
    
    return decoded.map<Map<String, dynamic>>((e) {
      if (e is Map<String, dynamic>) return e;
      if (e is Map) return Map<String, dynamic>.from(e);
      return <String, dynamic>{};
    }).toList();
  }

  List<Map<String, dynamic>> _validateWorkerCoordinates(List<Map<String, dynamic>> items) {
    return items.where((worker) {
      final lat = worker['lat'];
      final lng = worker['lng'];
      
      if (lat is! num || lng is! num) return false;
      if (!lat.isFinite || !lng.isFinite) return false;
      if (lat < -90 || lat > 90) return false;
      if (lng < -180 || lng > 180) return false;
      
      return true;
    }).toList();
  }

  // 간단한 클러스터링 로직
  Future<void> _renderWorkers() async {
    if (_mapController == null || workers.isEmpty || _isRendering) return;
    
    _isRendering = true;
    try {
      final cameraPos = await _mapController!.getCameraPosition();
      final zoomLevel = cameraPos.zoomLevel;
      
      // 모든 POI 제거
      await _mapController!.labelLayer.hideAllPoi();
      
      if (zoomLevel >= 14) {
        // 충분히 확대된 경우: 개별 워커 표시
        await _renderIndividualWorkers();
      } else {
        // 축소된 경우: 클러스터 표시
        await _renderClusters(zoomLevel);
      }
      
      _lastZoomLevel = zoomLevel;
    } finally {
      _isRendering = false;
    }
  }

  Future<void> _renderIndividualWorkers() async {
    for (int i = 0; i < workers.length; i++) {
      final worker = workers[i];
      final workerId = (worker['id'] as num).toInt();
      final lat = (worker['lat'] as num).toDouble();
      final lng = (worker['lng'] as num).toDouble();
      final profileUrl = worker['profileUrl']?.toString();
      
      final icon = await _getWorkerIcon(profileUrl, 32);
      
      await _mapController!.labelLayer.addPoi(
        LatLng(lat, lng),
        id: 'worker_$workerId',
        style: PoiStyle(icon: icon),
        onClick: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => WorkerProfileScreen(workerId: workerId),
            ),
          );
        },
      );
    }
  }

  Future<void> _renderClusters(int zoomLevel) async {
    // 간단한 거리 기반 클러스터링
    final clusters = _createClusters(zoomLevel);
    
    for (int i = 0; i < clusters.length; i++) {
      final cluster = clusters[i];
      final workerCount = cluster['workers'].length;
      final centerLat = cluster['centerLat'] as double;
      final centerLng = cluster['centerLng'] as double;
      
      if (workerCount == 1) {
        // 단일 워커
        final worker = cluster['workers'][0];
        final workerId = (worker['id'] as num).toInt();
        final profileUrl = worker['profileUrl']?.toString();
        final icon = await _getWorkerIcon(profileUrl, 28);
        
        await _mapController!.labelLayer.addPoi(
          LatLng(centerLat, centerLng),
          id: 'single_$workerId',
          style: PoiStyle(icon: icon),
          onClick: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => WorkerProfileScreen(workerId: workerId),
              ),
            );
          },
        );
      } else {
        // 클러스터
        final icon = await _getClusterIcon(workerCount, 36);
        
        await _mapController!.labelLayer.addPoi(
          LatLng(centerLat, centerLng),
          id: 'cluster_$i',
          style: PoiStyle(icon: icon),
          onClick: () async {
            final nextZoom = (zoomLevel + 3).clamp(3, 20);
            await _mapController!.moveCamera(
              CameraUpdate.newCenterPosition(
                LatLng(centerLat, centerLng),
                zoomLevel: nextZoom,
              ),
              animation: const CameraAnimation.new(300, autoElevation: true),
            );
          },
        );
      }
    }
  }

  List<Map<String, dynamic>> _createClusters(int zoomLevel) {
    if (workers.isEmpty) return [];
    
    // 줌 레벨에 따른 클러스터 반경 - 간단하고 직관적으로
    double clusterRadius;
    if (zoomLevel >= 14) {
      clusterRadius = 0.008; // ~800m - 개별 표시 직전
    } else if (zoomLevel >= 12) {
      clusterRadius = 0.025; // ~2.5km - 동네 단위
    } else if (zoomLevel >= 10) {
      clusterRadius = 0.08; // ~8km - 구/시 단위  
    } else if (zoomLevel >= 8) {
      clusterRadius = 0.25; // ~25km - 시/군 단위
    } else {
      clusterRadius = 0.8; // ~80km - 광역시/도 단위
    }
    
    final clusters = <Map<String, dynamic>>[];
    final processed = List<bool>.filled(workers.length, false);
    
    for (int i = 0; i < workers.length; i++) {
      if (processed[i]) continue;
      
      final mainWorker = workers[i];
      final mainLat = (mainWorker['lat'] as num).toDouble();
      final mainLng = (mainWorker['lng'] as num).toDouble();
      
      final clusterWorkers = <Map<String, dynamic>>[mainWorker];
      processed[i] = true;
      
      // 근처 워커들 찾기
      for (int j = i + 1; j < workers.length; j++) {
        if (processed[j]) continue;
        
        final otherWorker = workers[j];
        final otherLat = (otherWorker['lat'] as num).toDouble();
        final otherLng = (otherWorker['lng'] as num).toDouble();
        
        final distance = _calculateDistance(mainLat, mainLng, otherLat, otherLng);
        
        if (distance <= clusterRadius) {
          clusterWorkers.add(otherWorker);
          processed[j] = true;
        }
      }
      
      // 클러스터 중심 계산
      double centerLat = 0;
      double centerLng = 0;
      for (final worker in clusterWorkers) {
        centerLat += (worker['lat'] as num).toDouble();
        centerLng += (worker['lng'] as num).toDouble();
      }
      centerLat /= clusterWorkers.length;
      centerLng /= clusterWorkers.length;
      
      clusters.add({
        'workers': clusterWorkers,
        'centerLat': centerLat,
        'centerLng': centerLng,
      });
    }
    
    return clusters;
  }

  double _calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    return math.sqrt(math.pow(lat2 - lat1, 2) + math.pow(lng2 - lng1, 2));
  }

  // 아이콘 생성
  Future<KImage> _getWorkerIcon(String? profileUrl, double size) async {
    final key = 'worker_${profileUrl ?? 'default'}_$size';
    if (_iconCache.containsKey(key)) {
      return _iconCache[key]!;
    }

    final widget = ClipOval(
      child: Container(
        width: size, 
        height: size,
        color: Colors.indigo.shade300,
        child: (profileUrl != null && profileUrl.isNotEmpty)
            ? Image.network(
                profileUrl, 
                fit: BoxFit.cover, 
                width: size, 
                height: size,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.person, 
                  size: size * 0.6, 
                  color: Colors.white
                ),
              )
            : Center(
                child: Icon(Icons.person, size: size * 0.6, color: Colors.white),
              ),
      ),
    );

    final icon = await KImage.fromWidget(
      widget,
      Size(size, size),
      pixelRatio: MediaQuery.of(context).devicePixelRatio.clamp(1.0, 3.0),
    );
    
    _iconCache[key] = icon;
    return icon;
  }

  Future<KImage> _getClusterIcon(int count, double size) async {
    final key = 'cluster_${count}_$size';
    if (_iconCache.containsKey(key)) {
      return _iconCache[key]!;
    }

    final widget = Container(
      width: size, 
      height: size,
      decoration: BoxDecoration(
        color: Colors.indigo.withOpacity(0.95),
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(
            color: Colors.black26, 
            blurRadius: 6, 
            offset: Offset(0, 2)
          )
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        count > 999 ? '999+' : '$count',
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    final icon = await KImage.fromWidget(
      widget,
      Size(size, size),
      pixelRatio: MediaQuery.of(context).devicePixelRatio.clamp(1.0, 3.0),
    );
    
    _iconCache[key] = icon;
    return icon;
  }

  // 카메라 조작
  Future<void> _centerToFirstOrDefault() async {
    if (_mapController == null) return;

    if (workers.isNotEmpty) {
      final worker = workers.first;
      final target = LatLng(
        (worker['lat'] as num).toDouble(),
        (worker['lng'] as num).toDouble(),
      );
      await _mapController!.moveCamera(
        CameraUpdate.newCenterPosition(target, zoomLevel: 16),
        animation: const CameraAnimation.new(350),
      );
    } else {
      await _mapController!.moveCamera(
        CameraUpdate.newCenterPosition(_defaultCenter, zoomLevel: 14),
        animation: const CameraAnimation.new(350),
      );
    }
  }

  Future<void> _fitToWorkersOrCenter() async {
    if (_mapController == null) return;

    if (workers.isEmpty) {
      await _mapController!.moveCamera(
        CameraUpdate.newCenterPosition(_defaultCenter, zoomLevel: 14),
        animation: const CameraAnimation.new(300),
      );
      return;
    }

    final points = workers
        .map((w) => LatLng(
              (w['lat'] as num).toDouble(),
              (w['lng'] as num).toDouble(),
            ))
        .toList();

    await _mapController!.moveCamera(
      CameraUpdate.fitMapPoints(points, padding: 50),
      animation: const CameraAnimation.new(300),
    );
  }

  // 주소 검색
  Future<void> _searchLocation() async {
    final query = _searchController.text.trim();
    if (query.isEmpty || _mapController == null) return;

    try {
      final locations = await locationFromAddress(query);
      if (locations.isNotEmpty) {
        final target = LatLng(locations.first.latitude, locations.first.longitude);
        await _mapController!.moveCamera(
          CameraUpdate.newCenterPosition(target, zoomLevel: 16),
          animation: const CameraAnimation.new(300),
        );
      }
    } catch (e) {
      debugPrint('위치 검색 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('위치를 찾을 수 없습니다.')),
        );
      }
    }
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
              // 검색 + 토글 UI
              Padding(
                padding: const EdgeInsets.all(12),
                child: Material(
                  elevation: 1,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        TextField(
                          controller: _searchController,
                          onSubmitted: (_) => _searchLocation(),
                          decoration: InputDecoration(
                            hintText: '위치 검색',
                            prefixIcon: const Icon(Icons.search),
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
                        const SizedBox(height: 12),
                        SwitchListTile.adaptive(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            showOnlyAvailableToday ? '오늘 가능한 알바생만' : '전체 알바생',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          value: showOnlyAvailableToday,
                          onChanged: (value) {
                            setState(() => showOnlyAvailableToday = value);
                            fetchWorkers();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 헤더
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                        color: Colors.indigo.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${workers.length}명',
                        style: const TextStyle(fontSize: 12, color: Colors.indigo),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: fetchWorkers,
                    ),
                  ],
                ),
              ),

              // 지도
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  child: Stack(
                    children: [
                      KakaoMap(
                        option: KakaoMapOption(
                          position: workers.isNotEmpty
                              ? LatLng(
                                  (workers.first['lat'] as num).toDouble(),
                                  (workers.first['lng'] as num).toDouble(),
                                )
                              : _defaultCenter,
                          zoomLevel: 12,
                          mapType: MapType.normal,
                        ),
                        onMapReady: (controller) async {
                          _mapController = controller;
                          await Future.delayed(const Duration(milliseconds: 100)); // 안정화 대기
                          await _fitToWorkersOrCenter();
                          await _renderWorkers();
                        },
                        onCameraMoveEnd: (position, gesture) {
                          _renderDebounce?.cancel();
                          _renderDebounce = Timer(const Duration(milliseconds: 200), () {
                            if (position.zoomLevel != _lastZoomLevel) {
                              _renderWorkers();
                            }
                          });
                        },
                      ),

                      // 필터 표시
                      Positioned(
                        top: 10,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              showOnlyAvailableToday ? '오늘 가능한 알바생만' : '전체 알바생',
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ),
                        ),
                      ),

                      // 컨트롤 버튼
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: Column(
                          children: [
                            FloatingActionButton.small(
                              heroTag: 'location',
                              onPressed: _centerToFirstOrDefault,
                              backgroundColor: Colors.white,
                              child: const Icon(Icons.my_location, color: Colors.black87),
                            ),
                            const SizedBox(height: 8),
                            FloatingActionButton.small(
                              heroTag: 'refresh',
                              onPressed: fetchWorkers,
                              backgroundColor: Colors.white,
                              child: const Icon(Icons.refresh, color: Colors.black87),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}