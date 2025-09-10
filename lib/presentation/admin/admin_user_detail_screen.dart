import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:iljujob/config/constants.dart';

class AdminUserDetailScreen extends StatefulWidget {
  final int userId; // 리스트에서 전달받은 ID

  const AdminUserDetailScreen({super.key, required this.userId});

  @override
  State<AdminUserDetailScreen> createState() => _AdminUserDetailScreenState();
}

class _AdminUserDetailScreenState extends State<AdminUserDetailScreen> {
  Map<String, dynamic>? userDetail;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUserDetail(); // 시작하자마자 API 호출
  }

  Future<void> _fetchUserDetail() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken') ?? '';

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/admin/users/${widget.userId}'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        setState(() {
          userDetail = jsonDecode(response.body);
          isLoading = false;
        });
      } else {
        print('❌ 상세 조회 실패: ${response.statusCode}');
        setState(() => isLoading = false);
      }
    } catch (e) {
      print('❌ 네트워크 오류: $e');
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('회원 상세보기')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : userDetail == null
              ? const Center(child: Text('회원 정보가 없습니다.'))
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('이름: ${userDetail!['name'] ?? '-'}'),
                      Text('전화번호: ${userDetail!['phone'] ?? '-'}'),
                      Text('회원유형: ${userDetail!['type'] ?? '-'}'),
                      // 필요한 추가 정보들 자유롭게 추가 가능
                    ],
                  ),
                ),
    );
  }
}
