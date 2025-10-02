// lib/presentation/screens/screen_clusterer.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:kakao_map_sdk/kakao_map_sdk.dart';

/// 화면에 보이는 경계 정보 (SDK 비의존)
class ViewBounds {
  final double north;
  final double south;
  final double east;
  final double west;

  const ViewBounds({
    required this.north,
    required this.south,
    required this.east,
    required this.west,
  });

  bool contains(double lat, double lng) =>
      lat <= north && lat >= south && lng >= west && lng <= east;
}

/// 간단한 데이터 모델
class WorkerPoint {
  final int id;
  final double lat;
  final double lng;
  final String? profileUrl;

  WorkerPoint({
    required this.id,
    required this.lat,
    required this.lng,
    this.profileUrl,
  });
}

/// 클러스터 결과 모델
class ClusterBucket {
  final double centerLat;
  final double centerLng;
  final List<WorkerPoint> members;

  ClusterBucket({
    required this.centerLat,
    required this.centerLng,
    required this.members,
  });

  bool get isSingle => members.length == 1;
}

/// Web Mercator 투영 유틸 (타일/픽셀 좌표 변환)
class Mercator {
  // 256px tile 기준
  static const double tileSize = 256.0;

  /// 위경도를 줌레벨 픽셀 좌표로 변환
  static Offset project(double lat, double lng, int zoom) {
    final siny = math.min(math.max(math.sin(lat * math.pi / 180.0), -0.9999), 0.9999);
    final x = (lng + 180.0) / 360.0;
    final y = 0.5 - math.log((1 + siny) / (1 - siny)) / (4 * math.pi);

    final scale = (1 << zoom) * tileSize; // 256 * 2^zoom
    return Offset(x * scale, y * scale);
  }

  /// 픽셀 좌표를 위경도로 역변환 (필요 시 사용)
  static LatLng unproject(double px, double py, int zoom) {
    final scale = (1 << zoom) * tileSize;
    final x = px / scale - 0.0;
    final y = py / scale - 0.0;

    final lng = x * 360.0 - 180.0;
    final n = math.pi - 2.0 * math.pi * (y - 0.5);
    final lat = 180.0 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
    return LatLng(lat, lng);
  }
}

/// 화면 그리드 기반 클러스터링
class ClusterEngine {
  /// 줌별 cell 크기(px). 줌 크게 → 작은 cell.
static int cellSizeForZoom(int zoom) {
  if (zoom >= 16) return 35;
  if (zoom >= 14) return 42;
  if (zoom >= 12) return 50;   // 구/군 단위
  if (zoom >= 10) return 65;   // 시 단위
  if (zoom >= 8)  return 80;   // 광역시/도 단위
  if (zoom >= 6)  return 100;  // 지역권 단위
  return 120;                   // 최소 축소: 10-12개 클러스터
}

  /// 현재 bounds 안의 포인트만 선별
  /// bounds가 null이면 전체 반환
  static List<WorkerPoint> filterInBounds(List<WorkerPoint> all, ViewBounds? bounds) {
    if (bounds == null) return all;
    return all.where((p) => bounds.contains(p.lat, p.lng)).toList();
  }

  /// 클러스터링 수행
  static List<ClusterBucket> cluster({
    required List<WorkerPoint> points,
    required int zoom,
    required int cellSizePx,
  }) {
    if (points.isEmpty) return const [];

    // bin: (gx, gy) → members
    final Map<String, List<WorkerPoint>> bins = {};

    for (final p in points) {
      final off = Mercator.project(p.lat, p.lng, zoom);
      final gx = (off.dx / cellSizePx).floor();
      final gy = (off.dy / cellSizePx).floor();
      final key = '$gx:$gy';
      (bins[key] ??= []).add(p);
    }

    final List<ClusterBucket> result = [];
    bins.forEach((_, members) {
      if (members.length == 1) {
        final m = members.first;
        result.add(ClusterBucket(centerLat: m.lat, centerLng: m.lng, members: members));
      } else {
        double latSum = 0, lngSum = 0;
        for (final m in members) {
          latSum += m.lat;
          lngSum += m.lng;
        }
        result.add(ClusterBucket(
          centerLat: latSum / members.length,
          centerLng: lngSum / members.length,
          members: members,
        ));
      }
    });

    return result;
  }
}

/// POI 렌더링 diff를 위한 헬퍼
class PoiDiff {
  final Set<String> toAdd;
  final Set<String> toRemove;
  PoiDiff(this.toAdd, this.toRemove);
}

class PoiRenderState {
  final Set<String> visiblePoiIds = {};

  PoiDiff diff(Set<String> nextIds) {
    final remove = visiblePoiIds.difference(nextIds);
    final add = nextIds.difference(visiblePoiIds);
    return PoiDiff(add, remove);
  }

  void apply(Set<String> finalIds) {
    visiblePoiIds
      ..clear()
      ..addAll(finalIds);
  }
}
