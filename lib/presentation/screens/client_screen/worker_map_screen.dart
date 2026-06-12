import 'package:flutter/material.dart';
import 'package:iljujob/presentation/widgets/albailju_common.dart';
import 'worker_map_view.dart';

class WorkerMapScreen extends StatelessWidget {
  const WorkerMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AlbailjuAppBar(
        title: '공고 지도',
        brand: true,
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: AlbailjuPostJobCta(
              onPressed: () => Navigator.pushNamed(context, "/post_job"),
                inverted: true,
              ),
            ),
          ),
        ],
      ),
      // 하단 탭바 영역을 침범하지 않게 처리
      body: const SafeArea(top: false, bottom: true, child: WorkerMapView()),
    );
  }
}
