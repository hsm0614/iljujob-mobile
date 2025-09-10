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

  List<Map<String, dynamic>> workers = [];
  bool isLoading = true;
  bool showOnlyAvailableToday = false;
  double _currentZoom = 14.0;

  // ==== Zoom -> Marker size (28~56px) ====
  double _iconSizeForZoom(double z) {
    final clamped = z.clamp(10.0, 18.0);
    return 28 + (clamped - 10) * 3.5;
  }

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
    super.dispose();
  }

  void _centerToFirstOrDefault() {
    if (workers.isNotEmpty) {
      final w = workers.first;
      _mapController.move(
        LatLng((w['lat'] as num).toDouble(), (w['lng'] as num).toDouble()),
        14,
      );
    } else {
      _mapController.move(const LatLng(37.5665, 126.9780), 13);
    }
  }

  // ==== Fetch workers with robust parsing + camera fit ====
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

        final List<Map<String, dynamic>> items = (decoded is List)
            ? decoded.map<Map<String, dynamic>>((e) {
                if (e is Map<String, dynamic>) return e;
                if (e is Map) return Map<String, dynamic>.from(e);
                return <String, dynamic>{};
              }).toList()
            : <Map<String, dynamic>>[];

        bool _isNum(x) => x is num;
        bool _finite(num v) => !v.isNaN && v.isFinite;
        bool _validLat(num v) => v >= -90 && v <= 90;
        bool _validLng(num v) => v >= -180 && v <= 180;

        final cleaned = items.where((m) {
          final latRaw = m['lat'];
          final lngRaw = m['lng'];
          if (!_isNum(latRaw) || !_isNum(lngRaw)) return false;
          final lat = latRaw as num;
          final lng = lngRaw as num;
          return _finite(lat) && _finite(lng) && _validLat(lat) && _validLng(lng);
        }).toList();

        if (!mounted) return;
        setState(() {
          workers = cleaned;
          isLoading = false;
        });

        if (workers.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            try {
              final bounds = LatLngBounds.fromPoints([
                for (final w in workers)
                  LatLng((w['lat'] as num).toDouble(), (w['lng'] as num).toDouble()),
              ]);
              _mapController.fitCamera(
                CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(32)),
              );
            } catch (_) {
              final first = workers.first;
              _mapController.move(
                LatLng((first['lat'] as num).toDouble(), (first['lng'] as num).toDouble()),
                14,
              );
            }
          });
        }
      } else {
        if (!mounted) return;
        setState(() => isLoading = false);
      }
    } on FormatException {
      if (!mounted) return;
      setState(() => isLoading = false);
    } on SocketException {
      if (!mounted) return;
      setState(() => isLoading = false);
    } on TimeoutException {
      if (!mounted) return;
      setState(() => isLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      debugPrint('❌ 알 수 없는 오류: $e');
    }
  }

  // ==== Address search -> move camera ====
  Future<void> _searchLocation() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    try {
      final locations = await locationFromAddress(query);
      if (locations.isNotEmpty) {
        final lat = locations.first.latitude;
        final lng = locations.first.longitude;
        _mapController.move(LatLng(lat, lng), 13);
      }
    } catch (e) {
      debugPrint('❌ 위치 검색 실패: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('위치 검색에 실패했습니다. 다른 키워드로 시도해 주세요.')),
      );
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
        padding: MediaQuery.of(context).viewInsets, // 키보드 대응
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.85,
          child: Column(
            children: [
              // ==== Search + Toggle (카드로 묶기) ====
              Padding(
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
                            suffixIcon: (_searchController.text.isNotEmpty)
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
              ),

              // ==== 섹션 헤더 ====
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    const Text(
                      '알바생 위치',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${workers.length}명',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.indigo),
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
              ),

              // ==== Map ====
              Expanded(
                child: ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(12)),
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          center: workers.isNotEmpty
                              ? LatLng(
                                  (workers.first['lat'] as num).toDouble(),
                                  (workers.first['lng'] as num).toDouble(),
                                )
                              : const LatLng(37.5665, 126.9780),
                          zoom: 14,
                          onMapEvent: (evt) {
                            final z = _mapController.camera.zoom;
                            if (z != _currentZoom) {
                              setState(() => _currentZoom = z);
                            }
                          },
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: Platform.isAndroid
                                ? 'kr.co.iljujob'
                                : 'com.iljujob.kr',
                          ),
                          MarkerClusterLayerWidget(
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
                              markers: workers.map((w) {
                                final pos = LatLng(
                                  (w['lat'] as num).toDouble(),
                                  (w['lng'] as num).toDouble(),
                                );
                                final imageUrl =
                                    (w['profileUrl'] ?? '').toString();
                                final workerId = (w['id'] as num).toInt();
                                final size = _iconSizeForZoom(_currentZoom);

                                return Marker(
                                  point: pos,
                                  width: size,
                                  height: size,
                                  alignment: Alignment.center,
                                  child: GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => WorkerProfileScreen(
                                            workerId: workerId,
                                          ),
                                        ),
                                      );
                                    },
                                    child:
                                        ClipOval(child: _avatar(imageUrl, size)),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),

                      // 상단 중앙: 현재 필터 배지 (전체/오늘가능)
                      Positioned(
                        top: 10,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.55),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              showOnlyAvailableToday
                                  ? '오늘 가능한 알바생만 보기'
                                  : '전체 알바생 보기',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),

                      // 오른쪽 아래: 내 위치 / 새로고침
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: Column(
                          children: [
                            _SmallFab(
                              icon: Icons.my_location,
                              onTap: _centerToFirstOrDefault,
                            ),
                            const SizedBox(height: 8),
                            _SmallFab(
                              icon: Icons.refresh,
                              onTap: fetchWorkers,
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

// 작은 플로팅 버튼
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

// 아바타 위젯
Widget _avatar(String? imageUrl, double size) {
  if (imageUrl == null || imageUrl.isEmpty) {
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
  return ClipOval(
    child: CachedNetworkImage(
      imageUrl: imageUrl,
      width: size,
      height: size,
      fit: BoxFit.cover,
      placeholder: (_, __) => const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      errorWidget: (_, __, ___) => CircleAvatar(
        radius: size / 2,
        backgroundColor: Colors.grey[300],
        child: Icon(
          Icons.person,
          size: size * 0.55,
          color: Colors.grey[700],
        ),
      ),
    ),
  );
}
