import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../config/constants.dart';

class AdminReportScreen extends StatefulWidget {
  const AdminReportScreen({super.key});

  @override
  State<AdminReportScreen> createState() => _AdminReportScreenState();
}

class _AdminReportScreenState extends State<AdminReportScreen> with TickerProviderStateMixin {
  List<dynamic> _userReports = [];
  List<dynamic> _jobReports = [];
  bool _isLoading = true;

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchReports();
  }

  Future<void> _fetchReports() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken') ?? '';

    try {
      final responses = await Future.wait([
        http.get(
          Uri.parse('$baseUrl/api/report/admin/reports'),
          headers: _authHeaders(token),
        ),
        http.get(
          Uri.parse('$baseUrl/api/report/admin/job-reports'),
          headers: _authHeaders(token),
        ),
      ]);

      final userRes = responses[0];
      final jobRes = responses[1];

      if (userRes.statusCode == 200 && jobRes.statusCode == 200) {
        setState(() {
          _userReports = json.decode(userRes.body);
          _jobReports = json.decode(jobRes.body);
          _isLoading = false;
        });
      } else {
        print('❌ 오류: 사용자=${userRes.statusCode}, 공고=${jobRes.statusCode}');
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('❌ 서버 요청 실패: $e');
      setState(() => _isLoading = false);
    }
  }

  Map<String, String> _authHeaders(String token) {
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  void _showReportDetail({
    required String title,
    required List<Widget> contentWidgets,
  }) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: contentWidgets,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기')),
        ],
      ),
    );
  }

void _showJobReportDetail(Map report) {
  String status = report['status'] ?? 'unknown';

  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('공고 신고 상세'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('공고 ID: ${report['job_id'] ?? '정보 없음'}'),
            Text('공고 제목: ${report['job_title'] ?? '정보 없음'}'),
            Text('신고자 전화번호: ${report['user_phone'] ?? '정보 없음'}'),
            const SizedBox(height: 8),
            Text('신고 사유:\n${report['reason'] ?? '내용 없음'}'),
            const SizedBox(height: 12),
            Text('상태: $status'),
          ],
        ),
      ),
      actions: [
        if (status == 'pending') ...[
          TextButton(
            onPressed: () {
              _updateReportStatus(report['id'], 'approved', 'job');
              Navigator.pop(context);
            },
            child: const Text('승인'),
          ),
          TextButton(
            onPressed: () {
              _updateReportStatus(report['id'], 'rejected', 'job');
              Navigator.pop(context);
            },
            child: const Text('거절'),
          ),
        ],
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('닫기'),
        ),
      ],
    ),
  );
}

void _showUserReportDetail(Map report) {
  String status = report['status'] ?? 'unknown';

  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('사용자 신고 상세'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('신고자 ID: ${report['reporter_id'] ?? '정보 없음'}'),
            Text('피신고자 (${report['target_type'] ?? '알 수 없음'}) → ${report['target_name'] ?? '정보 없음'}'),
            const SizedBox(height: 8),
            Text('신고 사유:\n${report['reason'] ?? '내용 없음'}'),
            const SizedBox(height: 12),
            Text('상태: $status'),
          ],
        ),
      ),
      actions: [
        if (status == 'pending') ...[
          TextButton(
            onPressed: () {
              _updateReportStatus(report['id'], 'approved', 'user');
              Navigator.pop(context);
            },
            child: const Text('승인'),
          ),
          TextButton(
            onPressed: () {
              _updateReportStatus(report['id'], 'rejected', 'user');
              Navigator.pop(context);
            },
            child: const Text('거절'),
          ),
        ],
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('닫기'),
        ),
      ],
    ),
  );
}

Future<void> _updateReportStatus(int reportId, String newStatus, String type) async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('authToken') ?? '';

  final response = await http.put(
    Uri.parse('$baseUrl/api/admin/report/status'),
    headers: {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    },
    body: json.encode({
      'reportId': reportId,
      'status': newStatus,
      'type': type, // 'user' 또는 'job' 을 여기서 넘김
    }),
  );

  if (response.statusCode == 200) {

    _fetchReports(); // 리스트 갱신
  } else {
    print('❌ 상태 업데이트 실패: ${response.statusCode}');
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('신고 내역'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '사용자 신고'),
            Tab(text: '공고 신고'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildUserReportTab(),
                _buildJobReportTab(),
              ],
            ),
    );
  }

  Widget _buildUserReportTab() {
    if (_userReports.isEmpty) {
      return const Center(child: Text('사용자 신고 내역이 없습니다.'));
    }
    return ListView.separated(
      itemCount: _userReports.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, index) {
        final report = _userReports[index];
        final isWorker = (report['target_type'] ?? '') == 'worker';
        return ListTile(
          title: Text('신고자 → ${isWorker ? "알바생" : "기업"} ${report['target_name'] ?? "정보 없음"}'),
          subtitle: Text(report['reason'] ?? ''),
          trailing: Text(_formatDate(report['created_at'])),
          onTap: () => _showUserReportDetail(report),
        );
      },
    );
  }

  Widget _buildJobReportTab() {
    if (_jobReports.isEmpty) {
      return const Center(child: Text('공고 신고 내역이 없습니다.'));
    }
    return ListView.separated(
      itemCount: _jobReports.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, index) {
        final report = _jobReports[index];
        return ListTile(
          title: Text('공고 신고 → ${report['job_title'] ?? "정보 없음"}'),
          subtitle: Text(report['reason'] ?? ''),
          trailing: Text(_formatDate(report['created_at'])),
          onTap: () => _showJobReportDetail(report),
        );
      },
    );
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return '';
    return dateString.split('T').first;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}
