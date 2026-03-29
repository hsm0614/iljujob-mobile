import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:iljujob/config/constants.dart';
import 'package:iljujob/main.dart'; // ✅ sendFcmTokenUnified 사용
import 'package:iljujob/presentation/screens/TermsDetailScreen.dart';
import 'package:iljujob/presentation/screens/webview_screen.dart';

const kBrand = Color(0xFF3B8AFF);

class SignupClientScreen extends StatefulWidget {
  const SignupClientScreen({super.key});

  @override
  State<SignupClientScreen> createState() => _SignupClientScreenState();
}

class _SignupClientScreenState extends State<SignupClientScreen> {
  final PageController _pageController = PageController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _managerController = TextEditingController();

  bool _agreedTerms = false;
  bool _agreedPrivacy = false;
  bool _agreedLocation = false;
  bool _agreedMarketing = false;
  bool _isLoading = false;
  int _currentPage = 0;

  // ============================================================
  // 공통 인증 정보 저장
  // ============================================================
  Future<void> _saveAuthCommon({
    required SharedPreferences prefs,
    required String accessToken,
    String? refreshToken,
    required String userType,
    required String userPhone,
    required int userIdOrClientId,
    String? userName,
    String? companyName,
    bool? isAdmin,
  }) async {
    final tok = accessToken.trim();
    if (tok.isEmpty) throw Exception('토큰이 없습니다.');

    await prefs.setString('authToken', tok);

    // refreshToken 저장 (빈 값은 제거)
    final r = refreshToken?.trim();
    if (r != null && r.isNotEmpty) {
      await prefs.setString('refreshToken', r);
    } else {
      await prefs.remove('refreshToken');
    }

    await prefs.setString('userType', userType);
    await prefs.setString('userPhone', userPhone);
    await prefs.setString('userNumber', userPhone);
    await prefs.setInt('userId', userIdOrClientId);
    await prefs.setInt('clientId', userIdOrClientId);
    if (userName != null) await prefs.setString('userName', userName);
    if (companyName != null) await prefs.setString('companyName', companyName);
    if (isAdmin != null) await prefs.setBool('isAdmin', isAdmin);
    await prefs.setBool('hasSeenOnboarding', true);
  }

  // ============================================================
  // 본인인증 시작
  // ============================================================
  Future<void> _startWebViewCertification() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/client/danal-certification-url'),
        headers: {'Content-Type': 'application/json'},
      );

      final data = jsonDecode(response.body);
      final url = data['certificationUrl'];

      if (url == null || url.toString().isEmpty) {
        _showSnackbar('본인인증 URL이 비어 있습니다.');
        return;
      }

      final impUid = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => WebViewScreen(url: url),
        ),
      );

      if (impUid != null && mounted) {
        await Future.delayed(const Duration(milliseconds: 500));
        await _verifyWithServer(impUid);
      } else {
        _showSnackbar('본인인증이 완료되지 않았습니다.');
      }
    } catch (e) {
      _showSnackbar('인증 시작 오류: $e');
    }
  }

  // ============================================================
  // 서버에서 본인인증 검증
  // ============================================================
  Future<void> _verifyWithServer(String impUid) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/certification/identity-verifications'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'impUid': impUid}),
      );

      final data = jsonDecode(response.body);

      if (data['success'] == true && data['status'] == 'VERIFIED') {
        final phone = data['phone'];
        final name = data['name'];

        if (phone != null && phone.isNotEmpty) {
          _phoneController.text = phone;
        }

        if (name != null && name.isNotEmpty) {
          _managerController.text = name;
        }

        await _checkPhoneThenProceed();
      } else {
        _showSnackbar('본인인증 실패: ${data['message'] ?? '알 수 없음'}');
      }
    } catch (e) {
      print('❌ 서버 확인 오류: $e');
      _showSnackbar('서버 오류: $e');
    }
  }

  // ============================================================
  // 전화번호 체크 및 로그인/회원가입 분기
  // ============================================================
  Future<void> _checkPhoneThenProceed() async {
    final phone = _phoneController.text.trim();

    if (phone.isEmpty) {
      _showSnackbar('전화번호를 입력해주세요');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/client/check'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        if (data['exists'] == true) {
          // ✅ 기존 회원 로그인
          final prefs = await SharedPreferences.getInstance();

          await _saveAuthCommon(
            prefs: prefs,
            accessToken: (data['token'] ?? '') as String,
            refreshToken: (data['refreshToken'] ?? '') as String?,
            userType: 'client',
            userPhone: phone,
            userIdOrClientId: data['clientId'] as int,
            userName: (data['manager'] ?? '') as String?,
            companyName: (data['companyName'] ?? '') as String?,
            isAdmin: (data['isAdmin'] ?? false) as bool?,
          );

          // ✅ main.dart의 통합 FCM 함수 사용
          await sendFcmTokenUnified();

          _showSnackbar('자동 로그인 완료');

          if (!mounted) return;
          Navigator.pushNamedAndRemoveUntil(
            context,
            data['isAdmin'] == true ? '/admin' : '/client_main',
            (_) => false,
          );
        } else {
          // ✅ 신규 회원 → 다음 페이지
          _pageController.nextPage(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
          );
          setState(() => _currentPage++);
        }
      } else {
        _showSnackbar('서버 응답 오류');
      }
    } catch (e) {
      _showSnackbar('조회 실패: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ============================================================
  // 회원가입 제출
  // ============================================================
  Future<void> _submitSignup() async {
    final phone = _phoneController.text.trim();
    final manager = _managerController.text.trim();

    if (manager.isEmpty) {
      _showSnackbar('담당자 이름을 입력해주세요');
      return;
    }

    if (!_agreedTerms || !_agreedPrivacy || !_agreedLocation) {
      _showSnackbar('필수 약관에 동의해주세요');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/client/signup'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': phone,
          'manager': manager,
          'marketingConsent': _agreedMarketing,
          'termsOfService': _agreedTerms,
          'privacyPolicy': _agreedPrivacy,
          'locationConsent': _agreedLocation,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        final isAdmin = data['isAdmin'] ?? false;
        final prefs = await SharedPreferences.getInstance();

        await _saveAuthCommon(
          prefs: prefs,
          accessToken: (data['token'] ?? '') as String,
          refreshToken: (data['refreshToken'] ?? '') as String?,
          userType: 'client',
          userPhone: phone,
          userIdOrClientId: data['clientId'] as int,
          userName: manager,
          companyName: (data['companyName'] ?? '') as String?,
          isAdmin: isAdmin,
        );

        // ✅ main.dart의 통합 FCM 함수 사용
        await sendFcmTokenUnified();

        _showSnackbar('가입 완료');

        if (!mounted) return;
Navigator.pushNamedAndRemoveUntil(
  context,
  isAdmin ? '/admin' : '/client_business_info',
  (_) => false,
);
      } else {
        _showSnackbar('가입 실패: ${data['message']}');
      }
    } catch (e) {
      _showSnackbar('가입 실패: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ============================================================
  // 테스트용 직접 로그인 (특정 번호 전용)
  // ============================================================
  Future<void> _loginAsClientDirectly(String phone) async {
    final prefs = await SharedPreferences.getInstance();

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/client/check-or-login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        await _saveAuthCommon(
          prefs: prefs,
          accessToken: (data['token'] ?? '') as String,
          refreshToken: (data['refreshToken'] ?? '') as String?,
          userType: 'client',
          userPhone: phone,
          userIdOrClientId: data['clientId'] as int? ?? 0,
          userName: (data['manager'] ?? '담당자') as String?,
          companyName: (data['companyName'] ?? '기업') as String?,
          isAdmin: (data['isAdmin'] ?? false) as bool,
        );

        // ✅ main.dart의 통합 FCM 함수 사용
        await sendFcmTokenUnified();

        final isAdmin = data['isAdmin'] ?? false;
        _showSnackbar(isAdmin ? '관리자 계정 로그인' : '자동 로그인 완료');

        if (!mounted) return;
        final nextRoute = isAdmin ? '/admin' : '/client_main';
        Navigator.pushNamedAndRemoveUntil(context, nextRoute, (_) => false);
      } else {
        _showSnackbar('로그인 실패');
      }
    } catch (e) {
      _showSnackbar('로그인 실패: $e');
    }
  }

  // ============================================================
  // UI 헬퍼
  // ============================================================
  InputDecoration _inputDecoration({
    required String hint,
    IconData? icon,
  }) {
    return InputDecoration(
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      prefixIcon: icon != null ? Icon(icon) : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kBrand, width: 1.5),
      ),
    );
  }

  ButtonStyle _primaryBtnStyle({bool enabled = true}) {
    return ElevatedButton.styleFrom(
      backgroundColor: enabled ? kBrand : const Color(0xFF93C5FD),
      foregroundColor: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      minimumSize: const Size.fromHeight(52),
    );
  }

  Widget _card({required Widget child}) {
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
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }

  void _showSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ============================================================
  // 약관 동의 모달
  // ============================================================
  void _showAgreementModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 전체 동의
              CheckboxListTile(
                value: _agreedTerms &&
                    _agreedPrivacy &&
                    _agreedMarketing &&
                    _agreedLocation,
                onChanged: (val) {
                  final newValue = val ?? false;
                  setState(() {
                    _agreedTerms = newValue;
                    _agreedPrivacy = newValue;
                    _agreedMarketing = newValue;
                    _agreedLocation = newValue;
                  });
                  setModalState(() {});
                },
                title: const Text('전체 동의하기'),
              ),
              const Divider(),

              // [필수] 서비스 이용약관
              Row(
                children: [
                  Checkbox(
                    value: _agreedTerms,
                    onChanged: (val) {
                      setState(() => _agreedTerms = val ?? false);
                      setModalState(() {});
                    },
                  ),
                  const Expanded(child: Text('[필수] 서비스 이용약관 동의')),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TermsDetailScreen(
                            filePath: 'assets/terms/terms_of_service.txt',
                            title: '서비스 이용약관',
                          ),
                        ),
                      );
                    },
                    child: const Text('보기'),
                  ),
                ],
              ),

              // [필수] 개인정보 수집
              Row(
                children: [
                  Checkbox(
                    value: _agreedPrivacy,
                    onChanged: (val) {
                      setState(() => _agreedPrivacy = val ?? false);
                      setModalState(() {});
                    },
                  ),
                  const Expanded(child: Text('[필수] 개인정보 수집 및 이용 동의')),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TermsDetailScreen(
                            filePath: 'assets/terms/privacy_policy.txt',
                            title: '개인정보 처리방침',
                          ),
                        ),
                      );
                    },
                    child: const Text('보기'),
                  ),
                ],
              ),

              // [필수] 위치기반서비스
              Row(
                children: [
                  Checkbox(
                    value: _agreedLocation,
                    onChanged: (val) {
                      setState(() => _agreedLocation = val ?? false);
                      setModalState(() {});
                    },
                  ),
                  const Expanded(child: Text('[필수] 위치기반서비스 이용 동의')),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TermsDetailScreen(
                            filePath: 'assets/terms/location_terms.txt',
                            title: '위치기반서비스 이용약관',
                          ),
                        ),
                      );
                    },
                    child: const Text('보기'),
                  ),
                ],
              ),

              // [선택] 마케팅
              Row(
                children: [
                  Checkbox(
                    value: _agreedMarketing,
                    onChanged: (val) {
                      setState(() => _agreedMarketing = val ?? false);
                      setModalState(() {});
                    },
                  ),
                  const Expanded(child: Text('[선택] 마케팅 정보 수신 동의')),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TermsDetailScreen(
                            filePath: 'assets/terms/marketing_terms.txt',
                            title: '마케팅 수신 동의',
                          ),
                        ),
                      );
                    },
                    child: const Text('보기'),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // 가입 버튼
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading
                          ? null
                          : () {
                              Navigator.pop(context);
                              _submitSignup();
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('동의하고 가입하기'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // 페이지 빌더
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('기업 회원가입'),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0.5,
        ),
        body: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          children: [_buildPhonePage(), _buildInfoPage()],
        ),
      ),
    );
  }

 Widget _buildPhonePage() {
  final bypassPhones = ['01046533004', '01046533005', '01048838013'];
  return SingleChildScrollView(
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: MediaQuery.of(context).size.height -
            MediaQuery.of(context).padding.top -
            kToolbarHeight,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start, // ✅ start로 변경
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            const Text(
              '알바일주 기업 가입을 시작합니다',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              '전화번호 인증만으로 바로 시작할 수 있어요.\n(기존 회원이면 자동 로그인)',
              style: TextStyle(
                fontSize: 13.5,
                color: Color(0xFF6B7280),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '📱 휴대폰 번호',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: _inputDecoration(
                      hint: "'-' 없이 숫자만 입력",
                      icon: Icons.phone_outlined,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: _primaryBtnStyle(enabled: !_isLoading),
                onPressed: _isLoading
                    ? null
                    : () {
                        final phone = _phoneController.text.trim();
                        if (phone.isEmpty) {
                          _showSnackbar('휴대폰 번호를 입력해주세요');
                          return;
                        }
                        if (bypassPhones.contains(phone)) {
                          _loginAsClientDirectly(phone);
                          return;
                        }
                        _startWebViewCertification();
                      },
                icon: const Icon(Icons.shield_outlined),
                label: _isLoading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'PASS 본인인증 하기',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    ),
  );
}

Widget _buildInfoPage() {
  return SingleChildScrollView(
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: MediaQuery.of(context).size.height -
            MediaQuery.of(context).padding.top -
            kToolbarHeight,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 40, 20, 20), // ✅ 상단 40으로 올림
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start, // ✅ start로 변경
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            const Text(
              '담당자 정보를 입력해주세요',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            const Text(
              '담당자 성함은 고객센터 및 채팅 안내에 사용돼요.',
              style: TextStyle(fontSize: 13.5, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 18),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🙋 담당자 이름',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _managerController,
                    decoration: _inputDecoration(
                      hint: '홍길동',
                      icon: Icons.person_outline,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: _primaryBtnStyle(enabled: !_isLoading),
                onPressed: _isLoading ? null : _showAgreementModal,
                child: _isLoading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        '가입 완료',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    ),
  );
}
}