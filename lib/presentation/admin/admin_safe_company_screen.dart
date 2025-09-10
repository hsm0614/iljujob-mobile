import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../config/constants.dart';

class AdminSafeCompanyScreen extends StatefulWidget {
  const AdminSafeCompanyScreen({super.key});

  @override
  State<AdminSafeCompanyScreen> createState() => _AdminSafeCompanyScreenState();
}

class _AdminSafeCompanyScreenState extends State<AdminSafeCompanyScreen> {
  List<dynamic> companies = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchPendingCompanies();
  }

  Future<void> _fetchPendingCompanies() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/admin/pending-safe-companies'));
      if (response.statusCode == 200) {
        setState(() {
          companies = jsonDecode(response.body);
          isLoading = false;
        });
      } else {
        print('불러오기 실패: ${response.statusCode}');
      }
    } catch (e) {
      print('에러: $e');
    }
  }

  Future<void> _updateStatus(int clientId, String status) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/api/admin/approve-safe-company'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'clientId': clientId, 'status': status}),
    );
    if (response.statusCode == 200) {
      _fetchPendingCompanies(); // 다시 불러오기
    } else {
      print('상태 업데이트 실패');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('안심기업 승인 관리'),
        backgroundColor: Colors.indigo,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: companies.length,
              itemBuilder: (context, index) {
                final company = companies[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    title: Text(company['company_name'] ?? '회사명 없음'),
                    subtitle: Text('담당자: ${company['manager_name']}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.check, color: Colors.green),
                          tooltip: '승인',
                          onPressed: () => _updateStatus(company['id'], 'approved'),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.red),
                          tooltip: '거절',
                          onPressed: () => _updateStatus(company['id'], 'rejected'),
                        ),
                      ],
                    ),
                    onTap: () {
                      final certUrl = company['business_certificate_url'];
                      if (certUrl != null && certUrl.isNotEmpty) {
                        showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('사업자등록증 미리보기'),
                            content: Image.network('$baseUrl$certUrl'),
                            actions: [
                              TextButton(
                                child: const Text('닫기'),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ],
                          ),
                        );
                      }
                    },
                  ),
                );
              },
            ),
    );
  }
}
