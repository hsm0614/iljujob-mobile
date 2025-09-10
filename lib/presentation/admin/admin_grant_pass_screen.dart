import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:iljujob/config/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdminGrantPassScreen extends StatefulWidget {
  const AdminGrantPassScreen({super.key});

  @override
  State<AdminGrantPassScreen> createState() => _AdminGrantPassScreenState();
}

class _AdminGrantPassScreenState extends State<AdminGrantPassScreen> {
  List<dynamic> clients = [];
  int? selectedClientId;
  final TextEditingController countController = TextEditingController();
  final TextEditingController reasonController = TextEditingController();
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchClients();
  }

Future<void> _fetchClients() async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('authToken') ?? ''; // ✅ 토큰 불러오기

  try {
    final response = await http.get(
      Uri.parse('$baseUrl/api/admin/clients'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token', // ✅ 반드시 포함
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      setState(() => clients = data);
    } else {
      print('서버 응답 오류: ${response.statusCode}');
    }
  } catch (e) {
    print('❌ 클라이언트 목록 오류: $e');
  }
}

  Future<void> _grantPass() async {
  if (selectedClientId == null || countController.text.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('모든 필드를 입력하세요')));
    return;
  }

  setState(() => isLoading = true);

  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken') ?? '';

    final response = await http.post(
      Uri.parse('$baseUrl/api/admin/grant-pass'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token', // ✅ 토큰 포함
      },
      body: jsonEncode({
        'clientId': selectedClientId,
        'count': int.tryParse(countController.text),
        'reason': reasonController.text,
      }),
    );

   

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${data['count']}개 이용권 지급 완료')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('지급 실패: 상태 코드 ${response.statusCode}')),
      );
    }
  } catch (e) {
    print('❌ 지급 오류: $e');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('에러: $e')));
  } finally {
    setState(() => isLoading = false);
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('이용권 지급')),
      body: Padding(
  padding: const EdgeInsets.all(16),
  child: ListView(
    children: [
      DropdownButtonFormField<int>(
        isExpanded: true,
        value: selectedClientId,
        hint: const Text('기업 선택'),
        items: clients.map<DropdownMenuItem<int>>((client) {
          return DropdownMenuItem<int>(
            value: client['id'],
            child: Text('${client['companyName']} (${client['phone']})'),
          );
        }).toList(),
        onChanged: (value) => setState(() => selectedClientId = value),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: countController,
        decoration: const InputDecoration(labelText: '이용권 수', border: OutlineInputBorder()),
        keyboardType: TextInputType.number,
      ),
      const SizedBox(height: 16),
      TextField(
        controller: reasonController,
        decoration: const InputDecoration(labelText: '지급 사유', border: OutlineInputBorder()),
        maxLines: 2,
      ),
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: isLoading ? null : _grantPass,
          child: isLoading
              ? const CircularProgressIndicator(color: Colors.white)
              : const Text('이용권 지급'),
        ),
      )
    ],
  ),
),
    );
  }
}
