import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/constants.dart';

class AdminJobReportTab extends StatefulWidget {
  const AdminJobReportTab({super.key});

  @override
  State<AdminJobReportTab> createState() => _AdminJobReportTabState();
}

class _AdminJobReportTabState extends State<AdminJobReportTab> {
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
      Uri.parse('$baseUrl/api/report/admin/job-reports'),
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
      print('❌ 공고 신고 조회 실패: ${response.statusCode}');
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
              final jobTitle = report['job_title'] ?? '제목 없음';
              final reporterPhone = report['user_phone'] ?? '비공개';

              return ListTile(
                title: Text('공고: $jobTitle'),
                subtitle: Text(report['reason']),
                trailing: Text(report['created_at'].toString().split('T').first),
                onTap: () {
                  // TODO: 공고 상세 보기 또는 신고자 정보 보기
                },
              );
            },
          );
  }
}
