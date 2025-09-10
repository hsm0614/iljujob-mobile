import 'package:flutter/material.dart';
import 'package:kakao_maps_flutter/kakao_maps_flutter.dart' as km;

class FullMapScreen extends StatefulWidget {
  final double lat;
  final double lng;
  final String? address; // 있으면 하단 바에 표시

  const FullMapScreen({
    super.key,
    required this.lat,
    required this.lng,
    this.address,
  });

  @override
  State<FullMapScreen> createState() => _FullMapScreenState();
}

class _FullMapScreenState extends State<FullMapScreen> {
  km.KakaoMapController? _c;
  bool _markerDone = false;

  Future<void> _placeMarkerWithRetry() async {
    if (_c == null || _markerDone) return;

    final pos = km.LatLng(latitude: widget.lat, longitude: widget.lng);

    // 프레임 붙은 뒤 살짝 대기 (레이어 준비)
    await Future.delayed(const Duration(milliseconds: 80));

    Exception? last;
    for (int i = 0; i < 8; i++) {
      try {
        // 엔진 워밍업 & 카메라 고정
        await _c!.setPoiVisible(isVisible: true);
        await _c!.moveCamera(
          cameraUpdate: km.CameraUpdate.fromLatLng(pos),
          animation: const km.CameraAnimation(
            duration: 250, autoElevation: true, isConsecutive: false),
        );

        // 기본 마커(이미지 없이)
        await _c!.addMarker(
          markerOption: km.MarkerOption(
            id: 'full_map_marker',
            latLng: pos,
          ),
        );

        // (선택) 인포윈도우
        await _c!.addInfoWindow(
          infoWindowOption: km.InfoWindowOption(
            id: 'full_map_iw',
            latLng: pos,
            title: '여기',
            snippet:
                '${widget.lat.toStringAsFixed(6)}, ${widget.lng.toStringAsFixed(6)}',
          ),
        );

        _markerDone = true;
        return;
      } catch (e) {
        last = e is Exception ? e : Exception(e.toString());
        await Future.delayed(const Duration(milliseconds: 120));
      }
    }
    // 디버깅용
    // ignore: avoid_print
    print('[KAKAO][FULL] addMarker failed: $last');
  }

  @override
  Widget build(BuildContext context) {
    final pos = km.LatLng(latitude: widget.lat, longitude: widget.lng);

    return Scaffold(
      appBar: AppBar(
        title: const Text('전체 지도 보기'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // 지도
          Positioned.fill(
            child: km.KakaoMap(
              initialPosition: pos,
              initialLevel: 8, // 풀맵은 조금 넓게
              onMapCreated: (c) {
                _c = c;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _placeMarkerWithRetry(); // 네이티브 마커 시도
                });
              },
            ),
          ),

          // (대응책) 중앙 고정 핀 위젯 — 네이티브 마커가 혹시 실패해도 핀은 보이게
          const IgnorePointer(
            child: Center(
              child: Icon(Icons.location_pin, size: 34, color: Colors.red),
            ),
          ),

          // 하단 주소 바
        // 하단 주소 바
if (widget.address?.trim().isNotEmpty ?? false)
  Positioned(
    left: 12,
    right: 12,
    bottom: 16,
    child: Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.place, size: 18, color: Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.address!.trim(), // 이쁘게 적힌 주소
                style: const TextStyle(fontSize: 14),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    ),
  )
else
  Positioned(
    left: 12,
    right: 12,
    bottom: 16,
    child: Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.place, size: 18, color: Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '위치: ${widget.lat.toStringAsFixed(6)}, ${widget.lng.toStringAsFixed(6)}',
                style: const TextStyle(fontSize: 14),
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
}
