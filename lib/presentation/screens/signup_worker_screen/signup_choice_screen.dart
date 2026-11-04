import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// Social SDKs
// import 'package:google_sign_in/google_sign_in.dart'; // ❌ 일단 구글 비활성화
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'package:iljujob/config/constants.dart';
import 'package:iljujob/main.dart';
import 'package:iljujob/presentation/screens/signup_worker_screen/signup_worker_screen.dart';
import 'package:iljujob/presentation/screens/signup_worker_screen/worker_quick_setup_screen.dart';
import 'package:iljujob/presentation/screens/AppleExtraInfoScreen.dart';
import '../../../config/app_theme.dart';

const kBrand = AppColors.primary;

class SignupChoiceScreen extends StatefulWidget {
  const SignupChoiceScreen({super.key});
  @override
  State<SignupChoiceScreen> createState() => _SignupChoiceScreenState();
}

class _SignupChoiceScreenState extends State<SignupChoiceScreen> {
  bool _loading = false;
  // final _google = GoogleSignIn(scopes: ['email', 'profile']); // ❌ 구글 비활성화

  ButtonStyle _primaryBtnStyle({Color? bg, Color? fg}) {
    return ElevatedButton.styleFrom(
      backgroundColor: bg ?? kBrand,
      foregroundColor: fg ?? Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      minimumSize: const Size.fromHeight(52),
      textStyle: const TextStyle(fontSize: AppFontSize.buttonLg, fontWeight: FontWeight.w700),
    );
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _saveAndGoHome(Map<String, dynamic> data) async {
    if (data['success'] != true) {
      _toast('로그인 실패: ${data['message'] ?? '알 수 없음'}');
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('authToken', data['token'] ?? '');
    await prefs.setString('refreshToken', data['refreshToken'] ?? '');
    await prefs.setString('userType', 'worker');
    await prefs.setInt('userId', data['workerId'] ?? 0);

    // ⭐ 여기 추가 1: 온보딩은 본 걸로 처리
    await prefs.setBool('hasSeenOnboarding', true);

    // ⭐ 여기 추가 2: 서버에서 내려준 phone도 있으면 같이 저장
    final profile = data['profile'];
    if (profile is Map && profile['phone'] is String) {
      await prefs.setString('userPhone', profile['phone']);
    }

    await sendFcmTokenUnified();

    final isNewUser = data['isNewUser'] == true;
    final provider = data['socialProvider'] ?? '';

    if (!mounted) return;

    if (isNewUser) {
      if (provider == 'apple') {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AppleProfileSetupScreen(workerId: data['workerId']),
          ),
        );
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const WorkerQuickSetupScreen()),
        );
      }
    } else {
      Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
    }
  }

  // ───────────────────────────────────────────
  // Google (비활성화)
  // ───────────────────────────────────────────
  // Future<void> _signInWithGoogle() async {
  //   if (_loading) return;
  //   setState(() => _loading = true);
  //   try {
  //     final account = await _google.signIn();
  //     if (account == null) {
  //       _toast('로그인을 취소했어요.');
  //       return;
  //     }
  //     final auth = await account.authentication;
  //     final idToken = auth.idToken;
  //     if (idToken == null) {
  //       _toast('Google idToken을 가져오지 못했어요.');
  //       return;
  //     }
  //     final res = await http.post(
  //       Uri.parse('$baseUrl/api/auth/social/login'),
  //       headers: {'Content-Type': 'application/json'},
  //       body: jsonEncode({'provider': 'google', 'idToken': idToken}),
  //     );
  //     final data = jsonDecode(res.body);
  //     await _saveAndGoHome(data);
  //   } catch (e) {
  //     _toast('Google 로그인 오류: $e');
  //   } finally {
  //     if (mounted) setState(() => _loading = false);
  //   }
  // }

  // ───────────────────────────────────────────
  // Kakao
  // ───────────────────────────────────────────
  Future<void> _signInWithKakao() async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      kakao.OAuthToken token;
      final isInstalled = await kakao.isKakaoTalkInstalled();

      if (isInstalled) {
        token = await kakao.UserApi.instance.loginWithKakaoTalk();
      } else {
        token = await kakao.UserApi.instance.loginWithKakaoAccount();
      }

      debugPrint('✅ 카카오 토큰 획득 성공');
      debugPrint('🔑 accessToken: ${token.accessToken.substring(0, 20)}...');

      final res = await http.post(
        Uri.parse('$baseUrl/api/worker/social/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'provider': 'kakao',
          'accessToken': token.accessToken,
        }),
      );

      debugPrint('📡 서버 응답: ${res.statusCode}');
      debugPrint('📄 응답 내용: ${res.body}');

      if (res.statusCode != 200) {
        final errorData = jsonDecode(res.body);
        _toast('로그인 실패: ${errorData['message'] ?? '알 수 없는 오류'}');
        return;
      }

      final data = jsonDecode(res.body);
      await _saveAndGoHome(data);
    } catch (e, stackTrace) {
      debugPrint('❌ 카카오 로그인 오류: $e');
      debugPrint('Stack trace: $stackTrace');
      _toast('로그인 중 오류가 발생했습니다. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ───────────────────────────────────────────
  // Apple (iOS만)
  // ───────────────────────────────────────────
  String _randomNonce([int length = 32]) {
    const chars =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final rnd = Random.secure();
    return List.generate(
      length,
      (_) => chars[rnd.nextInt(chars.length)],
    ).join();
  }

  String _sha256of(String input) =>
      sha256.convert(utf8.encode(input)).toString();

  Future<void> _signInWithApple() async {
    if (!Platform.isIOS) {
      _toast('Apple 로그인은 iOS에서만 지원됩니다.');
      return;
    }
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final rawNonce = _randomNonce();
      final nonce = _sha256of(rawNonce);

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

      final fullName =
          credential.givenName == null && credential.familyName == null
              ? null
              : '${credential.familyName ?? ''}${credential.givenName ?? ''}'
                  .trim();

      final res = await http.post(
        Uri.parse('$baseUrl/api/worker/social/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'provider': 'apple',
          'idToken': identityToken,
          'rawNonce': rawNonce,
          'name': fullName,
        }),
      );
      final data = jsonDecode(res.body);
      await _saveAndGoHome(data);
    } catch (e) {
      _toast('Apple 로그인 오류: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ───────────────────────────────────────────
  // Phone(PASS)
  // ───────────────────────────────────────────
  void _goPhoneSignup() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SignupWorkerScreen()),
    );
  }

  Widget _point(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(Icons.check_rounded, size: 20, color: AppColors.primary),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: AppTextStyles.body1.copyWith(height: 1.5))),
          ],
        ),
      );

  // 시안 BQvB3zzVYLBcMNbGP6Kznk 2번: 제목·좋은 점 두 줄 위, 가입 버튼은 엄지 닿는 아래
  @override
  Widget build(BuildContext context) {
    final isIOS = Platform.isIOS;
    return Scaffold(
      backgroundColor: AppColors.bgCard,
      appBar: AppBar(elevation: 0),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('카카오로 바로 가입해요', style: AppTextStyles.h2),
              const SizedBox(height: 8),
              Text('가입하면 내 근처 공고에 바로 지원할 수 있어요',
                  style: AppTextStyles.body1.copyWith(color: AppColors.textBody)),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
                decoration: BoxDecoration(
                  color: AppColors.bgSoft,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Column(
                  children: [
                    _point('사장님과 채팅해도 내 번호는 안 보여요'),
                    _point('근처 사장님이 급하게 사람을 찾으면 알림이 와요'),
                  ],
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _loading ? null : _signInWithKakao,
                icon: const Icon(Icons.chat_bubble, size: 20),
                label: Text(_loading ? '처리 중...' : '카카오로 시작하기'),
                style: _primaryBtnStyle(bg: const Color(0xFFFEE500), fg: const Color(0xFF191919)),
              ),
              if (isIOS) ...[
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: _loading ? null : _signInWithApple,
                  icon: const Icon(Icons.apple),
                  label: Text(_loading ? '처리 중...' : 'Apple로 시작하기'),
                  style: _primaryBtnStyle(bg: Colors.black, fg: Colors.white),
                ),
              ],
              const SizedBox(height: 4),
              TextButton(
                onPressed: _loading ? null : _goPhoneSignup,
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  foregroundColor: AppColors.textBody,
                ),
                child: const Text('휴대폰 번호로 시작하기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
