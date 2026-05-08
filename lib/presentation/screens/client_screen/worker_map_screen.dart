import 'package:flutter/material.dart';
import 'worker_map_view.dart';

const kBrandBlue = Color(0xFF3B8AFF);

class WorkerMapScreen extends StatelessWidget {
  const WorkerMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
          centerTitle: false,   // ✅ 왼쪽 정렬

        title: const Text(
          '알바생 지도 보기',
          style: TextStyle(
            fontFamily: 'jalnan2ttf',
            color: kBrandBlue,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: OutlinedButton.icon(
              onPressed: () => Navigator.pushNamed(context, "/post_job"),
              icon: const Icon(
                Icons.add_circle_outline,
                color: kBrandBlue,
                size: 18,
              ),
              label: const Text(
                '공고 등록',
                style: TextStyle(
                  color: kBrandBlue,
                  fontFamily: 'jalnan2ttf',
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: kBrandBlue.withOpacity(0.5),
                  width: 1,
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
      // ✅ 하단 탭바 영역을 침범하지 않게 처리
      body: const SafeArea(
        top: true,
        bottom: true,
        child: WorkerMapView(),
      ),
    );
  }
}
