// File: lib/presentation/screens/business_info_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:kpostal/kpostal.dart';
import '../../config/constants.dart';
import 'post_job/post_job_form.dart';
import 'post_job/post_job_screen.dart'; // ← 전체 등록 흐름을 포함한 진짜 화면

class ClientBusinessInfoScreen extends StatefulWidget {
  const ClientBusinessInfoScreen({super.key});

  @override
  State<ClientBusinessInfoScreen> createState() => _ClientBusinessInfoScreenState();
}

class _ClientBusinessInfoScreenState extends State<ClientBusinessInfoScreen> {
  final _bizNumberController = TextEditingController();
  final _companyNameController = TextEditingController();
  DateTime? _selectedDate;
  String? _selectedAddress;
  bool _isLoading = false;

  Future<void> _submitBusinessInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final clientId = prefs.getInt('userId');
    final bizNumber = _bizNumberController.text.trim();
    final companyName = _companyNameController.text.trim();
    final address = _selectedAddress;

    if (bizNumber.length != 10 || _selectedDate == null || companyName.isEmpty || address == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('모든 항목을 정확히 입력해주세요')),
      );
      
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/client/update-bizinfo'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'clientId': clientId,
          'bizNumber': bizNumber,
          'companyName': companyName,
          'openDate': _selectedDate!.toIso8601String().split('T')[0],
          'address': address,
        }),
      );

if (response.statusCode == 200) {
  // ✅ SharedPreferences에 저장
  await prefs.setString('companyName', companyName);

Navigator.pushReplacementNamed(context, '/post_job');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('등록 실패')),
        );
      }
    } catch (e) {
      print('❌ 오류: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('서버 오류 발생')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(title: const Text('사업자 정보 입력')),
    body: GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(), // ✅ 다른 데 탭하면 키보드 내림
      child: SingleChildScrollView( // ✅ overflow 방지
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('사업자 정보를 입력해주세요', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('공고 등록 전에 사업자 정보를 한 번만 입력하시면 됩니다.', style: TextStyle(fontSize: 14, color: Colors.grey)),
             const SizedBox(height: 4),
             const Text(
      '사업자 번호가 없을 땐 hsm@outfind.co.kr 로 문의 주세요.',
      style: TextStyle(fontSize: 13, color: Colors.grey),
    ),
            const SizedBox(height: 32),

            const Text('사업자등록번호', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _bizNumberController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: '예) 1234567890',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 20),
            const Text('상호(법인/단체명)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _companyNameController,
              decoration: const InputDecoration(
                hintText: '예) (주)알바일주',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 20),
            const Text('개업연월일', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(1980),
                  lastDate: DateTime.now(),
                );
                if (picked != null) {
                  setState(() => _selectedDate = picked);
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _selectedDate == null
                      ? '예) 2022년 1월 30일'
                      : DateFormat('yyyy년 M월 d일').format(_selectedDate!),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),

            const SizedBox(height: 20),
            const Text('사업장 주소', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => KpostalView(
                      useLocalServer: false,
                      callback: (result) {
                        setState(() {
                          _selectedAddress = result.address;
                        });
                      },
                    ),
                  ),
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _selectedAddress ?? '주소 검색',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),

            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submitBusinessInfo,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('완료'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
}
