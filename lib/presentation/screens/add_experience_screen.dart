// 📄 add_experience_screen.dart

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/constants.dart';
import 'dart:io';

class AddExperienceScreen extends StatefulWidget {
  const AddExperienceScreen({super.key});

  @override
  State<AddExperienceScreen> createState() => _AddExperienceScreenState();
}

class _AddExperienceScreenState extends State<AddExperienceScreen> {
  final placeController = TextEditingController();
  final descriptionController = TextEditingController();

  String? selectedYear;
  String? selectedDuration;

  final List<String> yearOptions = List.generate(15, (i) => '${2025 - i}');
  final List<String> durationOptions = [
    '1개월 이하',
    '3개월 이하',
    '6개월 이하',
    '1년 이상',
    '2년 이상',
  ];

Future<void> _submit() async {
  if (placeController.text.isEmpty ||
      descriptionController.text.isEmpty ||
      selectedYear == null ||
      selectedDuration == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('모든 항목을 입력해주세요')),
    );
    return;
  }

  final prefs = await SharedPreferences.getInstance();
  final workerId = prefs.getInt('userId');

  final response = await http.post(
    Uri.parse('$baseUrl/api/worker/add-experience'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'workerId': workerId,
      'place': placeController.text.trim(),
      'description': descriptionController.text.trim(),
      'year': selectedYear,
      'duration': selectedDuration,
    }),
  );

  if (response.statusCode == 200) {
    Navigator.pop(context, true); // 성공 표시
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('저장 실패')),
    );
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('경력'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: [
            const Text('일한 곳'),
            const SizedBox(height: 8),
            TextField(
              controller: placeController,
              decoration: const InputDecoration(
                hintText: '예) 알바일주 송도점',
              ),
            ),
            const SizedBox(height: 24),
            const Text('했던 일'),
            const SizedBox(height: 8),
            TextField(
              controller: descriptionController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: '어떤 일을 했었는지 설명해주세요.',
              ),
            ),
            const SizedBox(height: 24),
            const Text('일한 연도'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              items: yearOptions
                  .map((y) => DropdownMenuItem(value: y, child: Text(y)))
                  .toList(),
              onChanged: (value) => setState(() => selectedYear = value),
              decoration: const InputDecoration(hintText: '연도 선택'),
            ),
            const SizedBox(height: 24),
            const Text('일한 기간'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              items: durationOptions
                  .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                  .toList(),
              onChanged: (value) => setState(() => selectedDuration = value),
              decoration: const InputDecoration(hintText: '기간 선택'),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3B8AFF),
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(50),
          ),
          child: const Text('입력 완료'),
        ),
      ),
    );
  }
}
