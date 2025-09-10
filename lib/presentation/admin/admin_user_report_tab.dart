import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/constants.dart';

class AdminUserReportTab extends StatefulWidget {
  const AdminUserReportTab({super.key});

  @override
  State<AdminUserReportTab> createState() => _AdminUserReportTabState();
}

class _AdminUserReportTabState extends State<AdminUserReportTab> {
  List<dynamic> reports = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchReports();
  }

  Future<void> _fetchReports() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken') ?? '';

    final response = await http.get(
      Uri.parse('$baseUrl/api/report/admin/reports'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      setState(() {
        reports = data;
        isLoading = false;
      });
    } else {
      print('❌ 사용자 신고 조회 실패: ${response.statusCode}');
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return isLoading
        ? const Center(child: CircularProgressIndicator())
        : ListView.separated(
            itemCount: reports.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, index) {
              final report = reports[index];
              final reporterName = report['reporter_name'] ?? '익명';
              final targetName = report['target_name'] ?? '알 수 없음';
              final targetType = report['target_type'] == 'worker' ? '알바생' : '기업';

              return ListTile(
                title: Text('$reporterName → $targetType $targetName'),
                subtitle: Text(report['reason']),
                trailing: Text(report['created_at'].toString().split('T').first),
                onTap: () {
                  // TODO: 신고 상세 보기 또는 사용자 프로필 연결
                },
              );
            },
          );
  }
}
