import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../../config/constants.dart';

class ReportHistoryScreen extends StatefulWidget {
  const ReportHistoryScreen({super.key});

  @override
  State<ReportHistoryScreen> createState() => _ReportHistoryScreenState();
}

class _ReportHistoryScreenState extends State<ReportHistoryScreen> {
  List<Map<String, dynamic>> allReports = [];
  String selectedType = 'job'; // 'job' 또는 'user'
  String userType = 'worker'; // 'worker' 또는 'client'

  @override
  void initState() {
    super.initState();
    _initUserTypeAndLoadReports();
  }

  Future<void> _initUserTypeAndLoadReports() async {
    final prefs = await SharedPreferences.getInstance();
    userType = prefs.getString('userType') ?? 'worker';
    await _loadReports();
  }

  Future<void> _loadReports() async {
  final prefs = await SharedPreferences.getInstance();
  final userPhone = prefs.getString('userPhone') ?? '';
  final userId = prefs.getInt('userId') ?? 0;

String url = selectedType == 'job'
    ? '$baseUrl/api/report/job?userId=$userId' // ✅ 경로 수정 + userId 사용
    : '$baseUrl/api/report/user?reporterId=$userId';
  try {
    final res = await http.get(Uri.parse(url));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      setState(() => allReports = List<Map<String, dynamic>>.from(data));
    } else {
      setState(() => allReports = []);
    }
  } catch (e) {
    print('❌ 예외 발생: $e');
    setState(() => allReports = []);
  }
}


  @override
  Widget build(BuildContext context) {
    final filtered = selectedType == 'job'
        ? allReports
        : allReports.where((r) {
            // target_type이 없기 때문에 target_id만 보고 필터링 불가, 전부 표시
            // 향후 target_type이 생기면 여기서 분기 가능
            return true;
          }).toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('신고 내역', style: TextStyle(color: Colors.black)),
        iconTheme: const IconThemeData(color: Colors.black),
        elevation: 1,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _filterButton('job', '공고 신고'),
                const SizedBox(width: 12),
                _filterButton('user', '사용자 신고'),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('📭 신고 내역이 없습니다.', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) => _buildReportCard(filtered[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filterButton(String type, String label) {
    final isSelected = selectedType == type;
    return Expanded(
      child: ElevatedButton(
        onPressed: () {
          setState(() {
            selectedType = type;
          });
          _loadReports();
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: isSelected ? Colors.blue : Colors.grey.shade300,
          foregroundColor: isSelected ? Colors.white : Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(label),
      ),
    );
  }
Widget _buildReportCard(Map<String, dynamic> report) {
  final createdAt = _formatDate(report['created_at']);
  final status = report['status'] ?? 'pending';
  final reasonCategory = report['reason_category'] ?? '사유 없음';
  final reasonDetail = report['reason_detail'];

  String targetInfo;
  if (selectedType == 'job') {
    final title = report['job_title'] ?? '제목 없음';
    targetInfo = '공고: $title';
  } else {
    final targetName = report['target_name'] ?? '알 수 없음';
    final label = userType == 'worker' ? '기업' : '알바생';
    targetInfo = '$label: $targetName';
  }

  return Card(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('📌 $targetInfo'),
              _buildStatusBadge(status),
            ],
          ),
          const SizedBox(height: 6),
          Text('📝 사유: $reasonCategory${reasonDetail != null && reasonDetail.isNotEmpty ? ' - $reasonDetail' : ''}'),
          const SizedBox(height: 6),
          Text('⏰ 날짜: $createdAt', style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    ),
  );
}

  Widget _buildStatusBadge(String status) {
  Color bgColor;
  String label;

  switch (status) {
    case 'approved': // ✅ 추가
    case 'confirmed': // 기존 값
      bgColor = Colors.green;
      label = '조치 완료';
      break;
    case 'rejected':
      bgColor = Colors.red;
      label = '기각됨';
      break;
    default:
      bgColor = Colors.grey;
      label = '검토 중';
  }

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: bgColor.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: bgColor),
    ),
    child: Text(label, style: TextStyle(color: bgColor, fontWeight: FontWeight.bold, fontSize: 12)),
  );
}

  String _formatDate(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
  }
}
