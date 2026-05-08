import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
// TODO: 네 프로젝트의 Job 모델 & 상세 화면 import
import 'package:iljujob/data/models/job.dart';
import 'package:iljujob/presentation/screens/worker_screen/job_detail_screen.dart';
import 'package:iljujob/config/constants.dart'; // baseUrl

class JobDetailBridgeScreen extends StatefulWidget {
  final int jobId;
  const JobDetailBridgeScreen({super.key, required this.jobId});

  @override
  State<JobDetailBridgeScreen> createState() => _JobDetailBridgeScreenState();
}

class _JobDetailBridgeScreenState extends State<JobDetailBridgeScreen> {
  @override
  void initState() {
    super.initState();
    _loadAndForward();
  }

  Future<void> _loadAndForward() async {
    try {
      // 🔧 상세 API 엔드포인트는 프로젝트에 맞게 바꿔줘
      // 예시1) GET /api/job/jobs/:id
      // 예시2) GET /api/job/detail?jobId=...
      final url = Uri.parse('$baseUrl/api/job/jobs/${widget.jobId}');
      final r = await http.get(url);
      if (r.statusCode != 200) throw Exception('status ${r.statusCode}');
      final data = jsonDecode(utf8.decode(r.bodyBytes));

      // 🔧 응답 구조에 맞게 매핑 (예: data['job'] 또는 data 자체)
      // 아래는 예시 — 네 Job.fromJson 시그니처에 맞춰 수정
      final jobJson = (data is Map && data['job'] != null) ? data['job'] : data;
      final job = Job.fromJson(jobJson);

      if (!mounted) return;
      // 기존 화면으로 그대로 연결
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => JobDetailScreen(job: job)),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        Scaffold(
          body: Center(child: Text('공고 상세 로드 실패: $e')),
        ).createElement().widget as Route, // 간단 대체; 필요시 별도 에러화면으로
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 로딩 인디케이터만 잠깐 표시
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
