import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:iljujob/config/constants.dart';
import 'package:iljujob/main.dart';
import 'package:iljujob/presentation/screens/TermsDetailScreen.dart';
import 'package:iljujob/presentation/screens/webview_screen.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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
  final TextEditingController _smsCodeController = TextEditingController();

  bool _agreedTerms = false;
  bool _agreedPrivacy = false;
  bool _agreedLocation = false;
  bool _agreedMarketing = false;
  bool _isLoading = false;
  bool _useSmsMode = false;
  bool _smsSent = false;
  int _currentPage = 0;

  bool get _allRequiredAgreed =>
      _agreedTerms && _agreedPrivacy && _agreedLocation;
  bool get _allAgreed =>
      _agreedTerms && _agreedPrivacy && _agreedLocation && _agreedMarketing;

  void _toggleAll(bool value) {
    setState(() {
      _agreedTerms = value;
      _agreedPrivacy = value;
      _agreedLocation = value;
      _agreedMarketing = value;
    });
  }

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
  // PASS 본인인증
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
  // ✅ SMS 인증 전송
  // ============================================================
  Future<void> _sendSmsCode() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      _showSnackbar('휴대폰 번호를 입력해주세요');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/send-sms'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone}),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        setState(() => _smsSent = true);
        _showSnackbar('인증번호가 발송됐어요');
      } else {
        _showSnackbar('발송 실패: ${data['message'] ?? '다시 시도해주세요'}');
      }
    } catch (e) {
      _showSnackbar('발송 오류: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ============================================================
  // ✅ SMS 인증 확인
  // ============================================================
  Future<void> _verifySmsCode() async {
    final phone = _phoneController.text.trim();
    final code = _smsCodeController.text.trim();
    if (code.isEmpty) {
      _showSnackbar('인증번호를 입력해주세요');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/verify-sms'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone, 'code': code}),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        _phoneController.text = phone;
        await _checkPhoneThenProceed();
      } else {
        _showSnackbar('인증번호가 틀렸어요');
      }
    } catch (e) {
      _showSnackbar('확인 오류: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ============================================================
  // 서버 본인인증 검증
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
        if (phone != null && phone.isNotEmpty) _phoneController.text = phone;
        if (name != null && name.isNotEmpty) _managerController.text = name;
        await _checkPhoneThenProceed();
      } else {
        _showSnackbar('본인인증 실패: ${data['message'] ?? '알 수 없음'}');
      }
    } catch (e) {
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
  body: jsonEncode({
    'phone': phone,
    'fcmToken': await FirebaseMessaging.instance.getToken(), // ✅ 추가
  }),
);
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        if (data['exists'] == true) {
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
          await sendFcmTokenUnified();
          _showSnackbar('자동 로그인 완료');
          if (!mounted) return;
          Navigator.pushNamedAndRemoveUntil(
            context,
            data['isAdmin'] == true ? '/admin' : '/client_main',
            (_) => false,
          );
        } else {
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
    if (!_allRequiredAgreed) {
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
    'fcmToken': await FirebaseMessaging.instance.getToken(), // ✅ 추가
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
        await sendFcmTokenUnified();
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(
          context,
          // ✅ 가입 완료 후 웰컴 화면으로 이동 (공고 등록 유도)
          isAdmin ? '/admin' : '/client_welcome',
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
  // 테스트용 직접 로그인
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
        await sendFcmTokenUnified();
        final isAdmin = data['isAdmin'] ?? false;
        _showSnackbar(isAdmin ? '관리자 계정 로그인' : '자동 로그인 완료');
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(
          context,
          isAdmin ? '/admin' : '/client_main',
          (_) => false,
        );
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
  InputDecoration _inputDecoration({required String hint, IconData? icon}) {
    return InputDecoration(
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      prefixIcon: icon != null ? Icon(icon) : null,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ============================================================
  // 약관 체크박스 위젯 (인라인)
  // ============================================================
  Widget _termsRow({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    required String assetPath,
    required String title,
  }) {
    return Row(
      children: [
        GestureDetector(
          onTap: () => onChanged(!value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value ? kBrand : Colors.transparent,
              border: Border.all(
                color: value ? kBrand : const Color(0xFFD1D5DB),
                width: 1.5,
              ),
            ),
            child: value
                ? const Icon(Icons.check, size: 13, color: Colors.white)
                : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
                fontSize: 13.5, color: Color(0xFF374151)),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TermsDetailScreen(
                filePath: assetPath,
                title: title,
              ),
            ),
          ),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(36, 36),
          ),
          child: const Text('보기',
              style: TextStyle(fontSize: 12, color: kBrand)),
        ),
      ],
    );
  }

  // ============================================================
  // 빌드
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xFFEFF3F8),
        appBar: AppBar(
          title: const Text('기업 회원가입'),
          centerTitle: true,
          elevation: 0,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: _StepIndicator(currentPage: _currentPage, totalPages: 2),
          ),
        ),
        body: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          children: [_buildPhonePage(), _buildInfoPage()],
        ),
      ),
    );
  }

  // ============================================================
  // Page 1: 전화번호 + 인증 선택
  // ============================================================
  Widget _buildPhonePage() {
    final bypassPhones = ['01046533004', '01046533005', '01048838013'];
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            const Text(
              '사장님 전화번호로\n시작해요',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                  color: Color(0xFF191F28)),
            ),
            const SizedBox(height: 8),
            const Text(
              '기존 회원이면 자동으로 로그인돼요.',
              style: TextStyle(fontSize: 13.5, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 20),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('휴대폰 번호',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: _inputDecoration(
                      hint: "'-' 없이 숫자만 입력",
                      icon: Icons.phone_outlined,
                    ),
                  ),
                  // ✅ SMS 모드일 때 인증번호 입력
                  if (_useSmsMode && _smsSent) ...[
                    const SizedBox(height: 12),
                    const Text('인증번호',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _smsCodeController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: _inputDecoration(
                        hint: '6자리 입력',
                        icon: Icons.lock_outline,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ✅ PASS 버튼
            if (!_useSmsMode)
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
                              strokeWidth: 2, color: Colors.white))
                      : const Text('PASS 본인인증 하기',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),

            // ✅ SMS 버튼 (PASS 모드일 때)
            if (!_useSmsMode)
              TextButton(
                onPressed: () => setState(() => _useSmsMode = true),
                child: const Text(
                  'PASS 앱이 없으세요? SMS 인증으로 하기',
                  style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                ),
              ),

            // ✅ SMS 발송 / 확인 버튼
            if (_useSmsMode) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: _primaryBtnStyle(enabled: !_isLoading),
                  onPressed: _isLoading
                      ? null
                      : (_smsSent ? _verifySmsCode : _sendSmsCode),
                  child: _isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(
                          _smsSent ? '인증번호 확인' : 'SMS 인증번호 받기',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                ),
              ),
              TextButton(
                onPressed: () =>
                    setState(() {
                      _useSmsMode = false;
                      _smsSent = false;
                      _smsCodeController.clear();
                    }),
                child: const Text('PASS 인증으로 돌아가기',
                    style:
                        TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================
  // Page 2: 담당자 정보 + 약관 인라인
  // ============================================================
  Widget _buildInfoPage() {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '담당자 정보를\n입력해주세요',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                  color: Color(0xFF191F28)),
            ),
            const SizedBox(height: 8),
            const Text(
              '채팅 및 고객센터 안내에 사용돼요.',
              style: TextStyle(fontSize: 13.5, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 20),

            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('담당자 이름',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _managerController,
                    decoration:
                        _inputDecoration(hint: '홍길동', icon: Icons.person_outline),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ✅ 약관 인라인 (모달 제거)
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
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              child: Column(
                children: [
                  // 전체 동의
                  GestureDetector(
                    onTap: () => _toggleAll(!_allAgreed),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 4),
                      decoration: BoxDecoration(
                        color: _allAgreed
                            ? const Color(0xFFEFF6FF)
                            : const Color(0xFFF4F6FA),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _allAgreed
                                  ? kBrand
                                  : Colors.transparent,
                              border: Border.all(
                                color: _allAgreed
                                    ? kBrand
                                    : const Color(0xFFD1D5DB),
                                width: 1.5,
                              ),
                            ),
                            child: _allAgreed
                                ? const Icon(Icons.check,
                                    size: 13, color: Colors.white)
                                : null,
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            '약관 전체 동의',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 20, thickness: 0.5),

                  _termsRow(
                    label: '[필수] 서비스 이용약관',
                    value: _agreedTerms,
                    onChanged: (v) => setState(() => _agreedTerms = v),
                    assetPath: 'assets/terms/terms_of_service.txt',
                    title: '서비스 이용약관',
                  ),
                  const SizedBox(height: 8),
                  _termsRow(
                    label: '[필수] 개인정보 수집 및 이용',
                    value: _agreedPrivacy,
                    onChanged: (v) => setState(() => _agreedPrivacy = v),
                    assetPath: 'assets/terms/privacy_policy.txt',
                    title: '개인정보 처리방침',
                  ),
                  const SizedBox(height: 8),
                  _termsRow(
                    label: '[필수] 위치기반서비스 이용',
                    value: _agreedLocation,
                    onChanged: (v) => setState(() => _agreedLocation = v),
                    assetPath: 'assets/terms/location_terms.txt',
                    title: '위치기반서비스 이용약관',
                  ),
                  const SizedBox(height: 8),
                  _termsRow(
                    label: '[선택] 마케팅 정보 수신',
                    value: _agreedMarketing,
                    onChanged: (v) => setState(() => _agreedMarketing = v),
                    assetPath: 'assets/terms/marketing_terms.txt',
                    title: '마케팅 수신 동의',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: _primaryBtnStyle(
                    enabled: !_isLoading && _allRequiredAgreed),
                onPressed:
                    (_isLoading || !_allRequiredAgreed) ? null : _submitSignup,
                child: _isLoading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text(
                        '동의하고 가입 완료',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 스텝 인디케이터
// ============================================================
class _StepIndicator extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  const _StepIndicator(
      {required this.currentPage, required this.totalPages});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: List.generate(totalPages, (i) {
          final isActive = i == currentPage;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.only(right: 6),
            height: 4,
            width: isActive ? 24 : 8,
            decoration: BoxDecoration(
              color: isActive ? kBrand : const Color(0xFFD1D5DB),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }
}