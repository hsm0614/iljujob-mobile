import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:iljujob/config/constants.dart';

const kBrand = Color(0xFF3B8AFF);

class AppleProfileSetupScreen extends StatefulWidget {
  final int workerId;
  const AppleProfileSetupScreen({super.key, required this.workerId});

  @override
  State<AppleProfileSetupScreen> createState() => _AppleProfileSetupScreenState();
}

class _AppleProfileSetupScreenState extends State<AppleProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final List<String> _strengths = [];
  final List<String> _traits = [];
  bool _loading = false;

  final strengthOptions = ['포장', '상하차', '물류', 'F&B', '사무보조', '기타'];
  final traitOptions = ['꼼꼼해요', '책임감 있어요', '상냥해요', '빠릿해요', '체력이 좋아요', '성실해요'];

  Future<void> _submitAll() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken') ?? '';

    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/worker/update-apple-profile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'workerId': widget.workerId,
          'name': _nameCtrl.text.trim(),
          'phone': _phoneCtrl.text.trim(),
          'strengths': _strengths,
          'traits': _traits,
        }),
      );

      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🎉 프로필이 저장되었습니다! 환영합니다.')),
        );
        Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? '저장 실패')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('요청 중 오류: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            '기본 정보 및 프로필 설정',
            style: TextStyle(fontWeight: FontWeight.w700, color: Colors.black),
          ),
          centerTitle: true,
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 헤더
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        gradient: LinearGradient(
                          colors: [kBrand.withOpacity(0.15), Colors.white],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: const Text(
                        '🍎 Apple로 가입을 마무리합니다.\n필수 정보를 입력하고 프로필을 완성해주세요!',
                        style: TextStyle(
                          fontSize: 15,
                          color: Color(0xFF1F2937),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // 입력 필드
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: _inputDecoration('이름', '홍길동'),
                      validator: (v) => v == null || v.isEmpty ? '이름을 입력해주세요' : null,
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: _inputDecoration('전화번호', '01012345678'),
                      validator: (v) => v == null || v.isEmpty ? '전화번호를 입력해주세요' : null,
                    ),
                    const SizedBox(height: 28),

                    _sectionTitle('💪 자신 있는 업무 (최대 2개)'),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: strengthOptions.map((item) {
                        final isSelected = _strengths.contains(item);
                        return ChoiceChip(
                          label: Text(item),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              if (selected && _strengths.length < 2) {
                                _strengths.add(item);
                              } else {
                                _strengths.remove(item);
                              }
                            });
                          },
                          selectedColor: kBrand.withOpacity(0.2),
                          backgroundColor: Colors.grey.shade200,
                          labelStyle: TextStyle(
                            color: isSelected ? kBrand : Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 28),

                    _sectionTitle('🌟 나를 표현하는 단어'),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: traitOptions.map((item) {
                        final isSelected = _traits.contains(item);
                        return FilterChip(
                          label: Text(item),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              if (selected) _traits.add(item);
                              else _traits.remove(item);
                            });
                          },
                          selectedColor: const Color(0xFF10B981).withOpacity(0.25),
                          backgroundColor: Colors.grey.shade200,
                          labelStyle: TextStyle(
                            color: isSelected ? const Color(0xFF047857) : Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 40),

                    // 버튼
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _submitAll,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kBrand,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          minimumSize: const Size.fromHeight(52),
                        ),
                        child: Text(
                          _loading ? '저장 중...' : '완료하고 시작하기',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    Center(
                      child: Text(
                        '입력한 정보는 프로필에 반영되며,\n언제든 수정할 수 있습니다.',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: kBrand.withOpacity(0.8), width: 1.5),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      );
}
