import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'package:iljujob/config/constants.dart';
import 'package:iljujob/main.dart'; // sendFcmTokenUnified
import 'package:iljujob/presentation/screens/signup_client_screen/signup_client_screen.dart';
import 'package:iljujob/presentation/screens/signup_client_screen/client_extra_info_screen.dart';

const kBrand = Color(0xFF3B8AFF);

class SignupClientChoiceScreen extends StatefulWidget {
  const SignupClientChoiceScreen({super.key});

  @override
  State<SignupClientChoiceScreen> createState() => _SignupClientChoiceScreenState();
}

class _SignupClientChoiceScreenState extends State<SignupClientChoiceScreen> {
  bool _loading = false;

  // ── 버튼 스타일 ──────────────────────────────────────────────
  ButtonStyle _btnStyle({Color? bg, Color? fg, Color? borderColor}) {
    return ElevatedButton.styleFrom(
      backgroundColor: bg ?? kBrand,
      foregroundColor: fg ?? Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: borderColor != null
            ? BorderSide(color: borderColor)
            : BorderSide.none,
      ),
      minimumSize: const Size.fromHeight(52),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    );
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  // ── 소셜 로그인 공통 처리 ────────────────────────────────────
  Future<void> _handleSocialResponse(Map<String, dynamic> data) async {
    if (data['success'] != true) {
      _toast('로그인 실패: ${data['message'] ?? '알 수 없음'}');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('authToken', data['token'] ?? '');
    await prefs.setString('refreshToken', data['refreshToken'] ?? '');
    await prefs.setString('userType', 'client');
    await prefs.setInt('userId', data['clientId'] ?? 0);
    await prefs.setInt('clientId', data['clientId'] ?? 0);
    await prefs.setBool('hasSeenOnboarding', true);

    if (data['manager'] != null && (data['manager'] as String).isNotEmpty) {
      await prefs.setString('userName', data['manager']);
    }
    if (data['companyName'] != null) {
      await prefs.setString('companyName', data['companyName']);
    }

    await sendFcmTokenUnified();

    if (!mounted) return;

    final isAdmin   = data['isAdmin'] ?? false;
    final isNewUser = data['isNewUser'] ?? false;

    if (isAdmin) {
      Navigator.pushNamedAndRemoveUntil(context, '/admin', (_) => false);
      return;
    }

    if (isNewUser) {
      // ✅ 신규: 담당자 이름 입력 화면으로
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ClientExtraInfoScreen(
            clientId: data['clientId'] as int,
          ),
        ),
      );
    } else {
      // 기존 회원: 바로 메인
      Navigator.pushNamedAndRemoveUntil(context, '/client_main', (_) => false);
    }
  }

  // ── 카카오 로그인 ────────────────────────────────────────────
  Future<void> _kakao() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final isInstalled = await kakao.isKakaoTalkInstalled();
      final token = isInstalled
          ? await kakao.UserApi.instance.loginWithKakaoTalk()
          : await kakao.UserApi.instance.loginWithKakaoAccount();

      final res = await http.post(
        Uri.parse('$baseUrl/api/client/social-login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'provider': 'kakao',
          'accessToken': token.accessToken,
        }),
      );

      if (res.statusCode != 200) {
        _toast('로그인 실패: ${jsonDecode(res.body)['message'] ?? '알 수 없는 오류'}');
        return;
      }

      await _handleSocialResponse(jsonDecode(res.body));
    } catch (e) {
      _toast('카카오 로그인 오류: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── 애플 로그인 (iOS 전용) ───────────────────────────────────
  String _randomNonce([int length = 32]) {
    const chars =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final rnd = Random.secure();
    return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  String _sha256of(String input) =>
      sha256.convert(utf8.encode(input)).toString();

  Future<void> _apple() async {
    if (!Platform.isIOS) {
      _toast('Apple 로그인은 iOS에서만 지원됩니다.');
      return;
    }
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final rawNonce = _randomNonce();
      final nonce    = _sha256of(rawNonce);

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );

      final identityToken = credential.identityToken;
      if (identityToken == null) {
        _toast('Apple identityToken을 받지 못했어요.');
        return;
      }

      final fullName = [credential.givenName, credential.familyName]
          .where((e) => e != null && e.isNotEmpty)
          .join(' ');

      final res = await http.post(
        Uri.parse('$baseUrl/api/client/social-login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'provider': 'apple',
          'idToken':  identityToken,
          'rawNonce': rawNonce,
          'name':     fullName.isNotEmpty ? fullName : null,
        }),
      );

      await _handleSocialResponse(jsonDecode(res.body));
    } catch (e) {
      _toast('Apple 로그인 오류: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── 전화번호(PASS) ───────────────────────────────────────────
  void _goPhone() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SignupClientScreen()),
    );
  }

  // ── UI ───────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isIOS = Platform.isIOS;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F6FA),
        appBar: AppBar(
          title: const Text('가입 방법 선택'),
          centerTitle: true,
          elevation: 0,
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '알바일주 시작하기',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF191F28),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '카카오/애플로 간편하게 가입하고\n바로 공고를 올려보세요.',
                    style: TextStyle(fontSize: 13.5, color: Color(0xFF6B7280)),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

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
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 카카오
                        ElevatedButton.icon(
                          onPressed: _loading ? null : _kakao,
                          icon: Image.asset(
                            'assets/icons/kakao.png',
                            height: 20, width: 20,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.chat_bubble, size: 20,
                                    color: Color(0xFF191919)),
                          ),
                          label: Text(_loading ? '처리 중...' : '카카오로 시작하기'),
                          style: _btnStyle(
                            bg: const Color(0xFFFFE812),
                            fg: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 애플 (iOS)
                        if (isIOS)
                          ElevatedButton.icon(
                            onPressed: _loading ? null : _apple,
                            icon: const Icon(Icons.apple, size: 22),
                            label: Text(_loading ? '처리 중...' : 'Apple로 시작하기'),
                            style: _btnStyle(bg: Colors.black),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Center(
                              child: Text(
                                'Apple은 iOS에서만 제공됩니다',
                                style: TextStyle(color: Color(0xFF6B7280)),
                              ),
                            ),
                          ),

                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 16),

                        // 전화번호 (PASS)
                        ElevatedButton.icon(
                          onPressed: _loading ? null : _goPhone,
                          icon: const Icon(Icons.phone_iphone),
                          label: const Text('휴대폰으로 시작하기'),
                          style: _btnStyle(),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                  const Text(
                    '※ 공고 등록 후 지원자와 채팅으로 바로 연결됩니다.',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF6B7280)),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}