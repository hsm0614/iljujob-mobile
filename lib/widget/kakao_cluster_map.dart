import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:supercluster/supercluster.dart';

/// 외부에서 카카오맵을 제어하기 위한 공개 컨트롤러
class KakaoClusterMapController {
  _KakaoClusterMapState? _state;

  /// 지정 위치로 카메라 이동 (카카오 level: 숫자 작을수록 확대)
  Future<void> moveTo(double lat, double lng, {int level = 5}) async {
    await _state?.moveTo(lat, lng, level: level);
  }

  /// 현재 bounds/level 기준으로 즉시 다시 그리기 요청
  Future<void> requestIdleUpdate() async {
    await _state?.web?.evaluateJavascript(
      source: 'window.requestIdleUpdate && window.requestIdleUpdate();',
    );
  }
}

/// Kakao 지도 + Dart supercluster 조합 위젯
class KakaoClusterMap extends StatefulWidget {
  /// {id, lat, lng, profileUrl}
  final List<Map<String, dynamic>> workers;

  /// 마커 탭 시 콜백 (worker id)
  final ValueChanged<int>? onMarkerTap;

  /// 외부 제어용 컨트롤러(선택)
  final KakaoClusterMapController? controller;

  const KakaoClusterMap({
    super.key,
    required this.workers,
    this.onMarkerTap,
    this.controller,
  });

  @override
  State<KakaoClusterMap> createState() => _KakaoClusterMapState();
}

class _KakaoClusterMapState extends State<KakaoClusterMap> {
  late SuperclusterImmutable<Map<String, dynamic>> index;
  InAppWebViewController? web;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this; // 컨트롤러 연결
    _buildIndex();
  }

  @override
  void didUpdateWidget(covariant KakaoClusterMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // workers 레퍼런스가 바뀌면 재인덱싱
    if (oldWidget.workers != widget.workers) {
      _buildIndex();
      // 현재 화면 기준으로 즉시 다시 그려달라고 JS에 요청
      web?.evaluateJavascript(
        source: 'window.requestIdleUpdate && window.requestIdleUpdate();',
      );
    }
  }

  @override
  void dispose() {
    widget.controller?._state = null; // 컨트롤러 해제
    super.dispose();
  }

  void _buildIndex() {
    index = SuperclusterImmutable<Map<String, dynamic>>(
      getX: (p) => (p['lng'] as num).toDouble(),
      getY: (p) => (p['lat'] as num).toDouble(),
      minZoom: 0,
      maxZoom: 20,
      radius: 60, // 클러스터 그리드(튜닝 포인트: 40~80 사이로 조정)
    )..load(widget.workers);
  }

  // JS의 idle 콜백: {west,south,east,north,level}
  Future<void> _onIdleFromJs(Map args) async {
    final west  = (args['west']  as num).toDouble();
    final south = (args['south'] as num).toDouble();
    final east  = (args['east']  as num).toDouble();
    final north = (args['north'] as num).toDouble();
    final level = (args['level'] as int);      // 카카오: 숫자 작을수록 확대
    final int zoom = (20 - level).clamp(0, 20); // supercluster는 반대 축

    final elements = index.search(west, south, east, north, zoom);

    // handle()로 클러스터/포인트 분기
    final nodes = elements.map((el) {
      return el.handle(
        cluster: (c) => {
          'type': 'cluster',
          'id'   : c.uuid,               // 문자열 ID
          'lat'  : c.latitude,
          'lng'  : c.longitude,
          'count': c.childPointCount,
        },
        point: (p) {
          final d = p.originalPoint;
          return {
            'type': 'point',
            'id'  : d['id'],
            'lat' : p.y,                 // 인덱스 좌표 사용 권장
            'lng' : p.x,
            'profileUrl': (d['profileUrl'] ?? '').toString(),
          };
        },
      );
    }).toList();

    await web?.evaluateJavascript(
      source: 'window.renderNodes(${jsonEncode(nodes)});',
    );
  }

  /// 외부에서 호출하는 이동 API (컨트롤러가 사용)
  Future<void> moveTo(double lat, double lng, {int level = 5}) async {
    await web?.evaluateJavascript(source: 'window.moveTo($lat,$lng,$level);');
  }

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
  initialFile: 'assets/kakao_map.html',
  initialSettings:  InAppWebViewSettings(
    javaScriptEnabled: true,
    domStorageEnabled: true,
    allowFileAccessFromFileURLs: true,
    allowUniversalAccessFromFileURLs: true,
  ),
  onLoadError: (c, url, code, msg) {
    debugPrint('❌ WebView load error: $code $msg ($url)');
  },
  onConsoleMessage: (c, msg) {
    debugPrint('🌐 console: ${msg.message}');
  },
      onWebViewCreated: (controller) {
        web = controller;

        controller.addJavaScriptHandler(
          handlerName: 'onIdle',
          callback: (args) async {
            final map = (args.isNotEmpty && args.first is Map)
                ? args.first as Map
                : <String, dynamic>{};
            await _onIdleFromJs(map.cast<String, dynamic>());
            return null;
          },
        );

        controller.addJavaScriptHandler(
          handlerName: 'onMarkerTap',
          callback: (args) {
            final map = (args.isNotEmpty && args.first is Map)
                ? args.first as Map
                : <String, dynamic>{};
            final id = map['id'];
            if (id != null) {
              widget.onMarkerTap?.call(id is int ? id : int.tryParse('$id') ?? -1);
            }
            return null;
          },
        );
      },
      // WebView 로드가 끝나면 한 번 즉시 렌더 요청
      onLoadStop: (controller, _) async {
        await controller.evaluateJavascript(
          source: 'window.requestIdleUpdate && window.requestIdleUpdate();',
        );
      },
    );
  }
}
