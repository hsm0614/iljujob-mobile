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
import 'package:iljujob/presentation/screens/signup_worker_screen/signup_worker_screen.dart';
import 'package:iljujob/presentation/screens/AppleExtraInfoScreen.dart';
const kBrand = Color(0xFF3B8AFF);

class SignupChoiceScreen extends StatefulWidget {
  const SignupChoiceScreen({super.key});
  @override
  State<SignupChoiceScreen> createState() => _SignupChoiceScreenState();
}

class _SignupChoiceScreenState extends State<SignupChoiceScreen> {
  bool _loading = false;
bool _showProfileSetup = false;
  // final _google = GoogleSignIn(scopes: ['email', 'profile']); // ❌ 구글 비활성화

  ButtonStyle _primaryBtnStyle({Color? bg, Color? fg}) {
    return ElevatedButton.styleFrom(
      backgroundColor: bg ?? kBrand,
      foregroundColor: fg ?? Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      minimumSize: const Size.fromHeight(52),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
        MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: const Color(0xFFF8FAFC),
            appBar: AppBar(title: const Text('프로필 설정'), centerTitle: true, elevation: 0),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _buildProfileSetupWidget(),
            ),
          ),
        ),
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
    const chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final rnd = Random.secure();
    return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
  }
  String _sha256of(String input) => sha256.convert(utf8.encode(input)).toString();

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
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
        nonce: nonce,
      );

      final identityToken = credential.identityToken;
      if (identityToken == null) {
        _toast('Apple identityToken을 받지 못했어요.');
        return;
      }

      final fullName = credential.givenName == null && credential.familyName == null
          ? null
          : '${credential.familyName ?? ''}${credential.givenName ?? ''}'.trim();

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
    Navigator.push(context, MaterialPageRoute(builder: (_) => const SignupWorkerScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final isIOS = Platform.isIOS;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(title: const Text('가입 방법 선택'), centerTitle: true, elevation: 0),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              
              child: Column(
                
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '알바일주 시작하기 👋',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '카카오/애플로 간편하게 가입하고 바로 시작하세요.\n전화번호 인증은 나중에 프로필에서 선택할 수 있어요.',
                    style: TextStyle(fontSize: 13.5, color: Color(0xFF6B7280)),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: Offset(0, 6))],
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Kakao
                        ElevatedButton.icon(
                          onPressed: _signInWithKakao,
                          icon: Image.asset(
                            'assets/icons/kakao.png',
                            height: 20, width: 20,
                            errorBuilder: (_, __, ___) => const Icon(Icons.bolt),
                          ),
                          label: Text(_loading ? '처리 중...' : '카카오로 시작하기'),
                          style: _primaryBtnStyle(bg: const Color(0xFFFFE812), fg: Colors.black87),
                        ),
                        const SizedBox(height: 12),

                        // Google (숨김)
                        // ElevatedButton.icon(
                        //   onPressed: _signInWithGoogle,
                        //   icon: Image.asset('assets/icons/google.png', height: 20, width: 20,
                        //       errorBuilder: (_, __, ___) => const Icon(Icons.g_mobiledata)),
                        //   label: Text(_loading ? '처리 중...' : 'Google로 시작하기'),
                        //   style: _primaryBtnStyle(bg: Colors.white, fg: const Color(0xFF111827)).copyWith(
                        //     side: WidgetStateProperty.all(const BorderSide(color: Color(0xFFE5E7EB))),
                        //   ),
                        // ),
                        // const SizedBox(height: 12),

                        // Apple (iOS)
                        if (isIOS)
                          ElevatedButton.icon(
                            onPressed: _signInWithApple,
                            icon: const Icon(Icons.apple),
                            label: Text(_loading ? '처리 중...' : 'Apple로 시작하기'),
                            style: _primaryBtnStyle(bg: Colors.black, fg: Colors.white),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Center(
                                child: Text('Apple은 iOS에서만 제공됩니다', style: TextStyle(color: Color(0xFF6B7280))),
                              ),
                            ),
                          ),

                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 16),

                        // Phone (PASS)
                        ElevatedButton.icon(
                          onPressed: _goPhoneSignup,
                          icon: const Icon(Icons.phone_iphone),
                          label: const Text('휴대폰으로 시작하기'),
                          style: _primaryBtnStyle(),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                  const Text(
                    '※ 프로필을 더 채우면 사장님이 관심을 더 가져줘요. 홈에서 보강 배너로 안내해 드릴게요!',
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
 Widget _buildProfileSetupWidget() {
  final List<String> _strengths = [];
  final List<String> _traits = [];
  String? _gender; // ⬅️ 성별 저장용

  final strengthOptions = ['포장', '상하차', '물류', 'F&B', '사무보조', '기타'];
  final traitOptions = ['꼼꼼해요', '책임감 있어요', '상냥해요', '빠릿해요', '체력이 좋아요', '성실해요'];

  return StatefulBuilder( // 👈 이게 포인트!
    builder: (context, setState) {
      return Container(
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
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─────────────────────────────
            // 1) 성별 선택 영역
            // ─────────────────────────────
            const Text(
              '성별',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
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
),
ChoiceChip(
  label: const Text('여자'),
  selected: _gender == '여성',
  onSelected: (selected) {
    setState(() {
      _gender = selected ? '여성' : null;
    });
  },
),
ChoiceChip(
  label: const Text('선택 안 함'),
  selected: _gender == '선택안함',
  onSelected: (selected) {
    setState(() {
      _gender = selected ? '선택안함' : null;
    });
  },
),
              ],
            ),

            const SizedBox(height: 24),

            // ─────────────────────────────
            // 2) 자신 있는 업무
            // ─────────────────────────────
            const Text(
              '💪 자신 있는 업무 (2개까지)',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: strengthOptions.map((item) {
                final isSelected = _strengths.contains(item);
                return FilterChip(
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
                  selectedColor: kBrand.withOpacity(0.25),
                );
              }).toList(),
            ),

            const SizedBox(height: 20),

            // ─────────────────────────────
            // 3) 나를 표현하는 단어
            // ─────────────────────────────
            const Text(
              '🌟 나를 표현하는 단어',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: traitOptions.map((item) {
                final isSelected = _traits.contains(item);
                return FilterChip(
                  label: Text(item),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _traits.add(item);
                      } else {
                        _traits.remove(item);
                      }
                    });
                  },
                  selectedColor: const Color(0xFF10B981).withOpacity(0.25),
                );
              }).toList(),
            ),

            const SizedBox(height: 24),

            // ─────────────────────────────
            // 4) 완료 버튼
            // ─────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  if (_gender == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('성별을 선택해주세요.')),
                    );
                    return;
                  }

                  final prefs = await SharedPreferences.getInstance();
                  final token = prefs.getString('authToken') ?? '';
                  final workerId = prefs.getInt('userId');

                  try {
                    await http.post(
                      Uri.parse('$baseUrl/api/worker/update-profile'),
                      headers: {
                        'Content-Type': 'application/json',
                        'Authorization': 'Bearer $token',
                      },
                      body: jsonEncode({
                        'workerId': workerId,
                        'strengths': _strengths,
                        'traits': _traits,
                        'gender': _gender, // ⬅️ 서버로 같이 전송
                      }),
                    );

                    if (!context.mounted) return;
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/home',
                      (_) => false,
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('프로필 저장 중 오류: $e')),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: kBrand,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('완료하고 시작하기'),
              ),
            ),
          ],
        ),
      );
    },
  );
}
}
