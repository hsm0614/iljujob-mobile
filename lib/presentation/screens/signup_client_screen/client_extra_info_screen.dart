import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:iljujob/config/constants.dart';
import 'package:iljujob/data/services/authenticated_http_client.dart';
import '../../../config/app_theme.dart';


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

      final res = await AuthenticatedHttpClient.postJson(
        Uri.parse('$baseUrl/api/client/update-manager'),
        body: {'clientId': widget.clientId, 'manager': manager},
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
        backgroundColor: AppColors.bgCard,
        appBar: AppBar(
          title: const Text('기본 정보 입력'),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),

              // 헤더
              const Text(
                '담당자 이름을\n알려주세요',
                style: TextStyle(
                  fontSize: AppFontSize.h1,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '지원자와의 채팅 및 고객센터 안내에 사용돼요.',
                style: TextStyle(
                  fontSize: AppFontSize.button,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 32),

              // 입력 카드
              // 테두리 카드 제거 — 라벨과 입력칸만
              Container(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '담당자 이름',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: AppFontSize.body2,
                        color: AppColors.textSecondary,
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
                        fillColor: AppColors.bgMuted,
                        prefixIcon: const Icon(Icons.person_outline),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          borderSide: const BorderSide(
                            color: AppColors.primary,
                            width: 1.5,
                          ),
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
                    minimumSize: const Size.fromHeight(54),
                  ),
                  onPressed: _isLoading ? null : _submit,
                  child:
                      _isLoading
                          ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                          : const Text(
                            '완료하고 시작하기'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
