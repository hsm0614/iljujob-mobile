import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:iljujob/config/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http_parser/http_parser.dart';

class EventWriteScreen extends StatefulWidget {
  const EventWriteScreen({super.key});

  @override
  State<EventWriteScreen> createState() => _EventWriteScreenState();
}

class _EventWriteScreenState extends State<EventWriteScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _startDateController = TextEditingController();
  final _endDateController = TextEditingController();
  File? _selectedImage;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _selectedImage = File(picked.path);
      });
    }
  }

  Future<void> _submitEvent() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken') ?? '';

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/events'),
    );

    request.headers['Authorization'] = 'Bearer $token';
    request.fields['title'] = _titleController.text;
    request.fields['description'] = _descriptionController.text;
    request.fields['start_date'] = _startDateController.text;
    request.fields['end_date'] = _endDateController.text;

    if (_selectedImage != null) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'image',
          _selectedImage!.path,
          contentType: MediaType('image', 'jpeg'),
        ),
      );
    }
    
    final response = await request.send();

final resBody = await response.stream.bytesToString();

    if (response.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이벤트가 등록되었습니다')),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('등록 실패')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('이벤트 작성')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(controller: _titleController, decoration: const InputDecoration(labelText: '제목')),
            TextField(controller: _descriptionController, decoration: const InputDecoration(labelText: '설명')),
TextField(
  controller: _startDateController,
  readOnly: true,
  decoration: const InputDecoration(labelText: '시작일 (YYYY-MM-DD)'),
  onTap: () async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      _startDateController.text = picked.toIso8601String().split('T').first;
    }
  },
),

const SizedBox(height: 8),

TextField(
  controller: _endDateController,
  readOnly: true,
  decoration: const InputDecoration(labelText: '종료일 (YYYY-MM-DD)'),
  onTap: () async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      _endDateController.text = picked.toIso8601String().split('T').first;
    }
  },
),
            const SizedBox(height: 16),
            _selectedImage != null
                ? Image.file(_selectedImage!, height: 150)
                : const Text('선택된 이미지 없음'),
            TextButton.icon(
              icon: const Icon(Icons.image),
              label: const Text('이미지 선택'),
              onPressed: _pickImage,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _submitEvent,
              child: const Text('등록하기'),
            )
          ],
        ),
      ),
    );
  }
}
