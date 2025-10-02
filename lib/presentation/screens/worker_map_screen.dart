// lib/presentation/screens/worker_map_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:kakao_map_sdk/kakao_map_sdk.dart';

import '../../config/constants.dart';
import 'screen_clusterer.dart'; // ← WorkerPoint, ClusterEngine, PoiRenderState 가 들어있다고 가정
import '../screens/worker_profile_screen.dart';
import 'dart:math' as math;

class WorkerMapSheet extends StatefulWidget {
  const WorkerMapSheet({super.key});
  @override
  State<WorkerMapSheet> createState() => _WorkerMapSheetState();
}

class _WorkerMapSheetState extends State<WorkerMapSheet> {
  final TextEditingController _searchController = TextEditingController();

  KakaoMapController? _map;
  List<WorkerPoint> _all = [];
  bool _isLoading = true;
  bool _onlyToday = false;

  final Map<String, KImage> _iconCache = {};
  final PoiRenderState _renderState = PoiRenderState();
  final Map<String, Poi> _poiById = {}; // ← addPoi가 반환한 Poi를 보관
  Timer? _debounce;

  static const LatLng _defaultCenter = LatLng(37.5665, 126.9780);

  // ── 뷰포트 크기/Bounds 계산용 ──────────────────────────────
  final GlobalKey _mapKey = GlobalKey();
  Size _mapSize = const Size(0, 0);

  @override
  void initState() {
    super.initState();
    _fetchWorkers();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _iconCache.clear();
    super.dispose();
  }

  Future<void> _fetchWorkers() async {
    setState(() => _isLoading = true);
    final endpoint = _onlyToday
        ? '$baseUrl/api/worker/available-today'
        : '$baseUrl/api/worker/all';
    try {
      final res = await http
          .get(Uri.parse(endpoint), headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final list = (body is List ? body : []) as List;
        _all = list.map((e) {
          final m = (e as Map).map((k, v) => MapEntry(k.toString(), v));
          final id = (m['id'] as num).toInt();
          final lat = (m['lat'] as num).toDouble();
          final lng = (m['lng'] as num).toDouble();
          final url = m['profileUrl']?.toString();
          if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
          return WorkerPoint(id: id, lat: lat, lng: lng, profileUrl: url);
        }).whereType<WorkerPoint>().toList();
      }
    } catch (_) {
      // noop
    } finally {
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (_map != null) {
        await _fitInitial();
        await _render();
      }
    }
  }

  Future<void> _fitInitial() async {
    if (_map == null) return;
    if (_all.isEmpty) {
      await _map!.moveCamera(
        CameraUpdate.newCenterPosition(_defaultCenter, zoomLevel: 13),
        animation: const CameraAnimation.new(260),
      );
      return;
    }
    final points = _all.map((p) => LatLng(p.lat, p.lng)).toList();
    await _map!.moveCamera(
      CameraUpdate.fitMapPoints(points, padding: 48),
      animation: const CameraAnimation.new(260),
    );
  }

  // ── 화면 Bounds 계산 (fromScreenPoint 사용) ────────────────


 Future<ViewBounds?> _currentViewBounds() async {
  if (_map == null || _mapSize.width == 0 || _mapSize.height == 0) return null;

  final lt = await _map!.fromScreenPoint(0, 0);
  final rb = await _map!.fromScreenPoint(
    _mapSize.width.toInt(), 
    _mapSize.height.toInt()
  );
  if (lt == null || rb == null) return null;

  // ✅ 명확히 min/max 계산
  final north = math.max(lt.latitude, rb.latitude);
  final south = math.min(lt.latitude, rb.latitude);
  final west  = math.min(lt.longitude, rb.longitude);
  final east  = math.max(lt.longitude, rb.longitude);

  return ViewBounds(north: north, south: south, east: east, west: west);
}

Future<void> _render() async {
  if (_map == null || _isLoading) return;

  final cam = await _map!.getCameraPosition();
  final zoomInt = cam.zoomLevel.round();
  final vb = await _currentViewBounds();

  final inView = vb == null
      ? _all
      : _all.where((p) => vb.contains(p.lat, p.lng)).toList();

  final cell = ClusterEngine.cellSizeForZoom(zoomInt);
  final clusters = ClusterEngine.cluster(
    points: inView,
    zoom: zoomInt,
    cellSizePx: cell,
  );

  // 다음 렌더에 필요한 id 집합
  final Set<String> nextIds = {};
  final Map<String, ClusterBucket> clusterMap = {}; // 클러스터 정보 보관
  
  for (final c in clusters) {
    if (c.isSingle) {
      final id = 'w_${c.members.first.id}';
      nextIds.add(id);
    } else {
      final latKey = (c.centerLat * 1000).round();
      final lngKey = (c.centerLng * 1000).round();
      final id = 'c_${latKey}_${lngKey}';
      nextIds.add(id);
      clusterMap[id] = c;
    }
  }

  // diff 계산
  final diff = _renderState.diff(nextIds);

  // 제거
  for (final id in diff.toRemove) {
    final poi = _poiById.remove(id);
    if (poi != null) {
      await _map!.labelLayer.removePoi(poi);
    }
  }

  // 추가
  for (final c in clusters) {
    if (c.isSingle) {
      final w = c.members.first;
      final id = 'w_${w.id}';
    if (diff.toAdd.contains(id)) {
  final icon = await _getClusterIcon(c.members.length, 40); // baseSize 40
  final poi = await _map!.labelLayer.addPoi(
    LatLng(c.centerLat, c.centerLng),
    id: id,
    style: PoiStyle(icon: icon),
    onClick: () async {
      final pts = c.members.map((m) => LatLng(m.lat, m.lng)).toList();
      await _map!.moveCamera(
        CameraUpdate.fitMapPoints(pts, padding: 64),
        animation: const CameraAnimation.new(280, autoElevation: true),
      );
    },
  );
  _poiById[id] = poi;
}
    } else {
      final latKey = (c.centerLat * 1000).round();
      final lngKey = (c.centerLng * 1000).round();
      final id = 'c_${latKey}_${lngKey}';
      
      if (diff.toAdd.contains(id)) {
        final icon = await _getClusterIcon(c.members.length, 40);
        final poi = await _map!.labelLayer.addPoi(
          LatLng(c.centerLat, c.centerLng),
          id: id,
          style: PoiStyle(icon: icon),
          onClick: () async {
            final pts = c.members.map((m) => LatLng(m.lat, m.lng)).toList();
            await _map!.moveCamera(
              CameraUpdate.fitMapPoints(pts, padding: 64),
              animation: const CameraAnimation.new(280, autoElevation: true),
            );
          },
        );
        _poiById[id] = poi;
      }
    }
  }

  _renderState.apply(nextIds);
}

  // ----------------- 아이콘 캐시 -----------------
  Future<KImage> _getWorkerIcon(String? profileUrl, double size) async {
    final key = 'worker_${profileUrl ?? 'null'}_${size.toInt()}';
    final cached = _iconCache[key];
    if (cached != null) return cached;

    final widget = ClipOval(
      child: Container(
        width: size, height: size, color: const Color(0xFF3B8AFF),
        alignment: Alignment.center,
        child: (profileUrl != null && profileUrl.isNotEmpty)
            ? Image.network(profileUrl, width: size, height: size, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Icon(Icons.person, color: Colors.white, size: size * .6))
            : Icon(Icons.person, color: Colors.white, size: size * .6),
      ),
    );

    final img = await KImage.fromWidget(
      widget, Size(size, size),
      pixelRatio: MediaQuery.of(context).devicePixelRatio.clamp(1.0, 3.0),
    );
    _iconCache[key] = img;
    return img;
  }

 Future<KImage> _getClusterIcon(int count, double size) async {
  // 크기 고정 - 동적 증가 제거
  String label;
  if (count >= 1000) {
    label = '999+';
  } else if (count >= 100) {
    label = '${(count ~/ 10) * 10}+';
  } else if (count >= 10) {
    label = '${(count ~/ 5) * 5}+';
  } else {
    label = '$count';
  }

  final key = 'cluster_${label}_${size.toInt()}';
  final cached = _iconCache[key];
  if (cached != null) return cached;

  final widget = Container(
    width: size, 
    height: size,
    decoration: BoxDecoration(
      color: const Color(0xFF3B8AFF),
      shape: BoxShape.circle,
      boxShadow: const [
        BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))
      ]
    ),
    alignment: Alignment.center,
  child: Text(
  label,
  style: TextStyle(
    color: Colors.white,
    fontWeight: FontWeight.w900, // 더 두껍게
    fontSize: label.length >= 4 
        ? size * 0.28  // "190+"처럼 긴 텍스트
        : label.length >= 3
            ? size * 0.32  // "140"처럼 3자리
            : size * 0.38, // "25", "5"처럼 짧은 텍스트
  ),
)
  );

  final img = await KImage.fromWidget(
    widget, Size(size, size),
    pixelRatio: MediaQuery.of(context).devicePixelRatio.clamp(1.0, 3.0),
  );
  _iconCache[key] = img;
  return img;
}
  // -----------------------------------------------

  Future<void> _searchAndMove() async {
    final q = _searchController.text.trim();
    if (q.isEmpty || _map == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('주소 검색 로직을 연결해 주세요.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _map == null) {
      return const SizedBox(height: 300, child: Center(child: CircularProgressIndicator()));
    }

    return SafeArea(
      top: true,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          children: [
            // 검색/토글
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
                        onSubmitted: (_) => _searchAndMove(),
                        decoration: InputDecoration(
                          hintText: '위치 검색',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () { _searchController.clear(); setState(() {}); },
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(_onlyToday ? '오늘 가능한 알바생만' : '전체 알바생'),
                        value: _onlyToday,
                        onChanged: (v) async {
                          setState(() => _onlyToday = v);
                          await _fetchWorkers();
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
                  const Text('알바생 위치', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B8AFF).withOpacity(.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('${_all.length}명',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF3B8AFF))),
                  ),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchWorkers),
                ],
              ),
            ),

            // 지도
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _mapSize = Size(constraints.maxWidth, constraints.maxHeight);
                  return ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    child: Stack(
                      children: [
                        KakaoMap(
                          key: _mapKey,
                          option: KakaoMapOption(
                            position: _all.isNotEmpty
                                ? LatLng(_all.first.lat, _all.first.lng)
                                : _defaultCenter,
                            zoomLevel: 12,
                            mapType: MapType.normal,
                          ),
                          onMapReady: (c) async {
                            _map = c;
                            await Future.delayed(const Duration(milliseconds: 100));
                            await _fitInitial();
                            await _render();
                          },
                          onCameraMoveEnd: (pos, byGesture) {
                            _debounce?.cancel();
                            _debounce = Timer(const Duration(milliseconds: 300), _render);
                          },
                        ),

                        // 우하단 컨트롤
                        Positioned(
                          right: 12, bottom: 12,
                          child: Column(
                            children: [
                              FloatingActionButton.small(
                                heroTag: 'refresh',
                                backgroundColor: Colors.white,
                                onPressed: _fetchWorkers,
                                child: const Icon(Icons.refresh, color: Colors.black87),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
