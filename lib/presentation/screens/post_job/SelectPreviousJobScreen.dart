import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../../../config/constants.dart';

class SelectPreviousJobScreen extends StatefulWidget {
  const SelectPreviousJobScreen({super.key});

  @override
  State<SelectPreviousJobScreen> createState() => _SelectPreviousJobScreenState();
}

class _SelectPreviousJobScreenState extends State<SelectPreviousJobScreen> {
  List<dynamic> myJobs = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchMyJobs();
  }

  Future<void> _fetchMyJobs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final clientId = prefs.getInt('userId');

      if (clientId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('로그인 정보를 불러올 수 없습니다.')),
        );
        return;
      }

      final res = await http.get(Uri.parse('$baseUrl/api/job/my-jobs?clientId=$clientId'));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            myJobs = data;
            isLoading = false;
          });
        }
      } else {
        final errorMsg = jsonDecode(res.body)['message'] ?? '공고 조회 실패';
        if (mounted) {
          setState(() => isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ $errorMsg')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류 발생: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('기존 공고 선택')),
      body: isLoading
    ? const Center(child: CircularProgressIndicator())
    : myJobs.isEmpty
        ? const Center(child: Text('작성한 공고가 없습니다.'))
        : ListView.builder(
            itemCount: myJobs.length,
            itemBuilder: (_, index) {
              
  final job = myJobs[index];


 final title = (job['title'] ?? '').toString().isEmpty
      ? '제목 없음'
      : job['title'].toString();
  final location = job['location'] ?? '지역 없음';
  final category = job['category'] ?? '카테고리 없음';
  final startDate = job['start_date'] ?? '';
  final endDate = job['end_date'] ?? '';
  final startTime = job['start_time'] ?? '';
  final endTime = job['end_time'] ?? '';
  final payType = job['pay_type'] == 'daily' ? '일급' : '주급';
  final pay = job['pay']?.toString() ?? '';
  final isSameDayPay = job['is_same_day_pay'] == 1 ? ' · 당일지급' : '';

  return InkWell(
    onTap: () => Navigator.pop(context, job),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('$location · $category', style: const TextStyle(fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 4),
          Text('$startDate ~ $endDate  |  $startTime ~ $endTime',
              style: const TextStyle(fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 4),
          Text('$payType $pay원$isSameDayPay',
              style: const TextStyle(fontSize: 14, color: Colors.black)),
          const SizedBox(height: 8),
          const Divider(),
        ],
      ),
    ),
  );

            },
          ),

    );
  }
}
