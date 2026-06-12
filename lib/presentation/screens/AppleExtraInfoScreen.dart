import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:iljujob/config/constants.dart';

const kBrand = Color(0xFF3B8AFF);

class AppleProfileSetupScreen extends StatefulWidget {
  final int workerId;

  const AppleProfileSetupScreen({
    super.key,
    required this.workerId,
  });

  @override
  State<AppleProfileSetupScreen> createState() =>
      _AppleProfileSetupScreenState();
}

class _AppleProfileSetupScreenState extends State<AppleProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();

  // 기본 정보
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _birthYearCtrl = TextEditingController();

  // 프로필 선택값
  final List<String> _strengths = [];
  final List<String> _traits = [];

  // 성별: '남성' / '여성' / null
  String? _gender;

  bool _loading = false;

  final List<String> strengthOptions = [
    '포장',
    '상하차',
    '물류',
    'F&B',
    '사무보조',
    '기타',
  ];

  final List<String> traitOptions = [
    '꼼꼼해요',
    '책임감 있어요',
    '상냥해요',
    '빠릿해요',
    '체력이 좋아요',
    '성실해요',
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _birthYearCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitAll() async {
    if (!_formKey.currentState!.validate()) return;

    if (_gender == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('성별을 선택해주세요.')),
      );
      return;
    }

    final birthText = _birthYearCtrl.text.trim();
    final birthYear = int.tryParse(birthText);
    final nowYear = DateTime.now().year;

    if (birthYear == null || birthYear < 1960 || birthYear > nowYear) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('올바른 출생년도를 입력해주세요. (1960 ~ $nowYear)'),
        ),
      );
      return;
    }

    setState(() => _loading = true);

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken') ?? '';

    // 전화번호 정제
    final rawPhone = _phoneCtrl.text.trim();
    String cleanPhone = rawPhone.replaceAll(RegExp(r'\D'), '');
    if (cleanPhone.startsWith('82')) {
      cleanPhone = '0${cleanPhone.substring(2)}';
    }

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
          'phone': cleanPhone,
          'strengths': _strengths,
          'traits': _traits,
          // 🔥 DB에 그대로 '남성' / '여성' 들어가게 전송
          'gender': _gender,
          // 🔥 출생년도도 같이 전송 (서버에서 birth_year로 매핑하면 됨)
          'birthYear': birthYear,
        }),
      );

      final data = jsonDecode(res.body);

      if (res.statusCode == 200 && data['success'] == true) {
        // 로컬에 기본 정보 저장
        await prefs.setString('userPhone', cleanPhone);
        await prefs.setString('userName', _nameCtrl.text.trim());
        await prefs.setInt('birthYear', birthYear);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🎉 프로필이 저장되었습니다! 환영합니다.')),
        );
        Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? '저장에 실패했습니다.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('요청 중 오류가 발생했습니다: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F6FA),
        appBar: AppBar(
          elevation: 0,
          centerTitle: true,
          title: const Text('기본 정보 및 프로필 설정'),
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
                    // 헤더 카드
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        gradient: LinearGradient(
                          colors: [
                            kBrand.withOpacity(0.15),
                            Colors.white,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: const Text(
                        '🍎 Apple로 가입을 마무리합니다.\n'
                        '필수 정보를 입력하고 프로필을 완성해주세요!',
                        style: TextStyle(
                          fontSize: 15,
                          color: Color(0xFF1F2937),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // 이름
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: _inputDecoration('이름', '홍길동'),
                      validator: (v) =>
                          v == null || v.isEmpty ? '이름을 입력해주세요' : null,
                    ),
                    const SizedBox(height: 16),

                    // 전화번호
                    TextFormField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: _inputDecoration('전화번호', '01012345678'),
                      validator: (v) =>
                          v == null || v.isEmpty ? '전화번호를 입력해주세요' : null,
                    ),
                    const SizedBox(height: 16),

                    // 출생년도
                    _sectionTitle('🎂 출생년도'),
                    TextFormField(
                      controller: _birthYearCtrl,
                      keyboardType: TextInputType.number,
                      decoration: _inputDecoration('출생년도', '1998'),
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return '출생년도를 입력해주세요';
                        }
                        final year = int.tryParse(v);
                        final nowYear = DateTime.now().year;
                        if (year == null ||
                            year < 1960 ||
                            year > nowYear) {
                          return '올바른 출생년도를 입력해주세요. (1960 ~ $nowYear)';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    // 성별
                    _sectionTitle('👤 성별'),
                    Wrap(
                      spacing: 10,
                      children: [
                        ChoiceChip(
                          label: const Text('남자'),
                          selected: _gender == '남성',
                          onSelected: (selected) {
                            setState(() {
                              _gender = selected ? '남성' : null;
                            });
                          },
                          selectedColor: kBrand.withOpacity(0.2),
                          backgroundColor: const Color(0xFFE5E8EB),
                          labelStyle: TextStyle(
                            color: _gender == '남성' ? kBrand : const Color(0xFF191F28),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        ChoiceChip(
                          label: const Text('여자'),
                          selected: _gender == '여성',
                          onSelected: (selected) {
                            setState(() {
                              _gender = selected ? '여성' : null;
                            });
                          },
                          selectedColor: kBrand.withOpacity(0.2),
                          backgroundColor: const Color(0xFFE5E8EB),
                          labelStyle: TextStyle(
                            color: _gender == '여성' ? kBrand : const Color(0xFF191F28),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),

                    // 강점
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
                              if (selected && !_strengths.contains(item)) {
                                if (_strengths.length < 2) {
                                  _strengths.add(item);
                                }
                              } else {
                                _strengths.remove(item);
                              }
                            });
                          },
                          selectedColor: kBrand.withOpacity(0.2),
                          backgroundColor: const Color(0xFFE5E8EB),
                          labelStyle: TextStyle(
                            color: isSelected ? kBrand : const Color(0xFF191F28),
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 28),

                    // 성격
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
                              if (selected) {
                                if (!_traits.contains(item)) {
                                  _traits.add(item);
                                }
                              } else {
                                _traits.remove(item);
                              }
                            });
                          },
                          selectedColor:
                              const Color(0xFF10B981).withOpacity(0.25),
                          backgroundColor: const Color(0xFFE5E8EB),
                          labelStyle: TextStyle(
                            color: isSelected
                                ? const Color(0xFF047857)
                                : const Color(0xFF191F28),
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 40),

                    // 완료 버튼
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
                          color: const Color(0xFF6B7280),
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
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: kBrand.withOpacity(0.8),
          width: 1.5,
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
