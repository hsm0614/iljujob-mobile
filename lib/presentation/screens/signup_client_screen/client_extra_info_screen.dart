import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:iljujob/config/constants.dart';

const kBrand = Color(0xFF3B8AFF);

/// 소셜 로그인(카카오/애플)으로 기업 신규 가입 시
/// 담당자 이름을 추가로 입력받는 화면
class ClientExtraInfoScreen extends StatefulWidget {
  final int clientId;

  const ClientExtraInfoScreen({super.key, required this.clientId});

  @override
  State<ClientExtraInfoScreen> createState() => _ClientExtraInfoScreenState();
}

class _ClientExtraInfoScreenState extends State<ClientExtraInfoScreen> {
  final TextEditingController _managerController = TextEditingController();
  bool _isLoading = false;

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _submit() async {
    final manager = _managerController.text.trim();
    if (manager.isEmpty) {
      _toast('담당자 이름을 입력해주세요');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken') ?? '';

      final res = await http.post(
        Uri.parse('$baseUrl/api/client/update-manager'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'clientId': widget.clientId,
          'manager':  manager,
        }),
      );

      final data = jsonDecode(res.body);

      if (res.statusCode == 200 && data['success'] == true) {
        // SharedPreferences에 담당자 이름 저장
        await prefs.setString('userName', manager);

        if (!mounted) return;
        // ✅ 가입 완료 → 웰컴 화면으로
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/client_welcome',
          (_) => false,
        );
      } else {
        _toast('저장 실패: ${data['message'] ?? '다시 시도해주세요'}');
      }
    } catch (e) {
      _toast('오류: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xFFEFF3F8),
        appBar: AppBar(
          title: const Text('기본 정보 입력'),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0.5,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),

              // 헤더
              const Text(
                '담당자 이름을\n알려주세요 👋',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '지원자와의 채팅 및 고객센터 안내에 사용돼요.',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 32),

              // 입력 카드
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '🙋 담당자 이름',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Color(0xFF374151),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _managerController,
                      autofocus: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        hintText: '홍길동',
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFFF4F6FA),
                        prefixIcon: const Icon(Icons.person_outline),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: Color(0xFFE5E7EB)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: Color(0xFFE5E7EB)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: kBrand, width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // 완료 버튼
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kBrand,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    minimumSize: const Size.fromHeight(54),
                  ),
                  onPressed: _isLoading ? null : _submit,
                  child: _isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          '완료하고 시작하기',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}