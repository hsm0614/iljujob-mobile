import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:iljujob/config/constants.dart';
import 'package:iljujob/main.dart'; // ✅ sendFcmTokenUnified 사용을 위해
import 'package:iljujob/presentation/screens/webview_screen.dart';
import 'package:iljujob/presentation/screens/TermsDetailScreen.dart';
import 'package:iljujob/data/services/screen_analytics_service.dart';

const kBrand = Color(0xFF3B8AFF);

class SignupWorkerScreen extends StatefulWidget {
  const SignupWorkerScreen({super.key});

  @override
  State<SignupWorkerScreen> createState() => _SignupWorkerScreenState();
}

class _SignupWorkerScreenState extends State<SignupWorkerScreen> {
  final PageController _pageController = PageController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _birthController = TextEditingController();

  String _gender = '남성';
  String _birthYear = '';
  final List<String> _strengths = [];
  final List<String> _traits = [];
  int _currentPage = 0;
  bool _isLoading = false;
  bool _agreedTerms = false;
  bool _agreedPrivacy = false;
  bool _agreedMarketing = false;
  bool _agreedLocation = false;
  Position? _currentPosition;

  final List<String> strengthOptions = ['포장', '상하차', '물류', 'F&B', '사무보조', '기타'];
  final List<String> traitOptions = [
    '꼼꼼해요',
    '책임감 있어요',
    '상냥해요',
    '빠릿해요',
    '체력이 좋아요',
    '성실해요',
  ];

  bool _signupCompleted = false;

  @override
  void initState() {
    super.initState();
    // 구직자 가입 퍼널의 분모. 이게 없어 "가입→첫 지원 8%"가 어디서 깨지는지 못 봤다.
    ScreenAnalyticsService.instance.logEvent('worker_signup_start');
    _getCurrentLocation();
  }

  @override
  void dispose() {
    // 사장님 job_post_abandon 과 같은 패턴. 완료 없이 화면을 떠난 지점을 남긴다.
    if (!_signupCompleted) {
      ScreenAnalyticsService.instance.logEvent(
        'worker_signup_abandon',
        params: {'step': _currentPage},
      );
    }
    _pageController.dispose();
    _phoneController.dispose();
    _nameController.dispose();
    _birthController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(title: const Text('회원가입')),
        body: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          children: [_buildPhonePage(), _buildFirstPage(), _buildSecondPage()],
        ),
      ),
    );
  }

  // ============================================================
  // 위치 정보
  // ============================================================
  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _currentPosition = position;
      });
    } catch (e) {
      print('❌ 위치 정보 오류: $e');
    }
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
    await prefs.setString('authToken', accessToken);

    // 빈 refreshToken은 저장하지 않음
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await prefs.setString('refreshToken', refreshToken);
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
  // 전화번호 체크 및 로그인/회원가입 분기
  // ============================================================
  Future<void> _checkPhoneThenProceed() async {
    final phone = _phoneController.text.trim();

    if (phone.isEmpty) {
      _showSnackbar('전화번호가 비어있습니다.');
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final url = Uri.parse('$baseUrl/api/worker/check');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode != 200 || data['success'] != true) {
        final msg = data['message'] ?? '응답 실패';
        _showSnackbar('서버 오류: $msg');
        return;
      }

      final bool isExisting = data['exists'] == true;
      final int? workerId = data['workerId'];
      final String? token = data['token'];

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userPhone', phone);
      await prefs.setString('userType', 'worker');
      await prefs.setBool('hasSeenOnboarding', true);

      if (isExisting && workerId != null && token != null) {
        // ✅ 기존 회원 로그인
        await _saveAuthCommon(
          prefs: prefs,
          accessToken: token,
          refreshToken: data['refreshToken'] as String?,
          userType: 'worker',
          userPhone: phone,
          userIdOrClientId: workerId,
        );

        // ✅ main.dart의 통합 FCM 함수 사용
        await sendFcmTokenUnified();

        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
      } else {
        // ⚠️ 여기는 전화 인증 성공 지점이지 가입 완료가 아니다.
        //    예전엔 worker_signup_complete 로 찍혀 있어 퍼널이 거꾸로 읽혔다.
        ScreenAnalyticsService.instance.logEvent('worker_signup_step_complete',
            params: {'step': 0, 'name': 'phone_verified'});

        // ✅ 신규 회원 → 다음 단계
        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _pageController.nextPage(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
          setState(() => _currentPage = 1);
        });
      }
    } catch (e) {
      if (mounted) _showSnackbar('서버 오류: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ============================================================
  // 본인인증 시작
  // ============================================================
  Future<void> _startWebViewCertification() async {
    final rawPhone = _phoneController.text.replaceAll('-', '');
    const bypassPhone = '01046533004';

    // 테스트 계정 우회
    if (rawPhone == bypassPhone) {
      _phoneController.text = bypassPhone;
      _birthYear = '19910101';
      _birthController.text = _birthYear;
      _nameController.text = '테스트사용자';
      _gender = '남성';
      await _checkPhoneThenProceed();
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/worker/danal-certification-url'),
        headers: {'Content-Type': 'application/json'},
      );

      final contentType = response.headers['content-type'];
      if (contentType == null || !contentType.contains('application/json')) {
        _showSnackbar('서버가 JSON이 아닌 응답을 보냈습니다.');
        return;
      }

      final data = jsonDecode(response.body);
      final url = data['certificationUrl'];

      if (url == null || url.toString().isEmpty) {
        _showSnackbar('본인인증 URL이 비어 있습니다.');
        return;
      }

      // WebView 진입
      final impUid = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => WebViewScreen(url: url),
        ),
      );

      if (impUid != null && mounted) {
        await Future.delayed(const Duration(milliseconds: 500));
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          await _verifyWithServer(impUid);
        });
      } else {
        _showSnackbar('본인인증이 완료되지 않았습니다.');
      }
    } catch (e) {
      print('❌ 본인인증 시작 실패: $e');
      _showSnackbar('본인인증 시작 실패: $e');
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
        final name = data['name']?.toString() ?? '';
        final gender = data['gender']?.toString() ?? '';
        final timestamp = data['birth'];

        final prefs = await SharedPreferences.getInstance();

        // 전화번호 저장
        final receivedPhone = data['phone']?.toString() ?? _phoneController.text.trim();
        if (receivedPhone.isNotEmpty) {
          await prefs.setString('userPhone', receivedPhone);
        }

        // 생년월일 처리
        if (timestamp != null) {
          final dateUtc = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: true);
          final localDate = dateUtc.toLocal();
          _birthYear = "${localDate.year}${localDate.month.toString().padLeft(2, '0')}${localDate.day.toString().padLeft(2, '0')}";
          _birthController.text = _birthYear;
        }

        _nameController.text = name;
        _gender = (gender == 'male') ? '남성' : '여성';

        await prefs.setString('userType', 'worker');
        await prefs.setInt('userId', data['userId'] ?? 0);

        // 회원 여부 판단
        await _checkPhoneThenProceed();
      } else {
        if (!mounted) return;
        _showSnackbar('본인인증 실패: ${data['message'] ?? '알 수 없음'}');
      }
    } catch (e) {
      print('❌ 서버 확인 중 오류 발생: $e');
      if (!mounted) return;
      _showSnackbar('서버 오류: $e');
    }
  }

  // ============================================================
  // 회원가입 제출
  // ============================================================
  Future<void> _submitSignupData() async {
    if (!_agreedTerms || !_agreedPrivacy) {
      _showSnackbar('필수 약관에 동의해주세요');
      return;
    }

    final url = Uri.parse('$baseUrl/api/worker/signup');
    try {
      setState(() => _isLoading = true);

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': _phoneController.text,
          'name': _nameController.text,
          'gender': _gender,
          'birthYear': _birthYear,
          'strengths': _strengths,
          'traits': _traits,
          'userType': 'worker',
          'agreedTerms': _agreedTerms,
          'agreedPrivacy': _agreedPrivacy,
          'agreed_location': _agreedLocation,
          'agreedMarketing': _agreedMarketing,
          'matchAlert': _agreedMarketing ? true : false,
          'adAlert': _agreedMarketing ? true : false,
          'pushConsent': _agreedMarketing ? true : false,
          'smsConsent': _agreedMarketing ? false : false,
          'emailConsent': _agreedMarketing ? false : false,
          'lat': _currentPosition?.latitude,
          'lng': _currentPosition?.longitude,
        }),
      );

      final data = jsonDecode(response.body);

      if (data['success']) {
        _signupCompleted = true;
        ScreenAnalyticsService.instance.logEvent('worker_signup_complete');
        final prefs = await SharedPreferences.getInstance();
        await _saveAuthCommon(
          prefs: prefs,
          accessToken: (data['token'] ?? '') as String,
          refreshToken: (data['refreshToken'] ?? '') as String?,
          userType: 'worker',
          userPhone: _phoneController.text,
          userIdOrClientId: data['workerId'] as int,
          userName: _nameController.text,
        );

        // ✅ main.dart의 통합 FCM 함수 사용
        await sendFcmTokenUnified();
      } else {
        _showSnackbar('회원가입 실패: ${data['message']}');
      }
    } catch (e) {
      _showSnackbar('회원가입 실패: $e');
    } finally {
      setState(() => _isLoading = false);
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

  Widget _buildLabeledField(String label, Widget field) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14.5,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 8),
        field,
      ],
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
                value: _agreedTerms && _agreedPrivacy && _agreedMarketing && _agreedLocation,
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
                  const Expanded(
                    child: Text('[필수] 서비스 이용약관 및 커뮤니티 정책 동의'),
                  ),
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
                              _submitSignupData();
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B8AFF),
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
  void _nextPage() async {
    if (_currentPage == 0) {
      if (_phoneController.text.isEmpty || _birthYear.isEmpty) {
        _showSnackbar('모든 정보를 입력해주세요');
        return;
      }
      await _checkPhoneThenProceed();
    } else {
      _showAgreementModal();
    }
  }

  Widget _buildPhonePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              const Text(
                '알바일주 가입을 환영합니다',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF191F28)),
              ),
              const SizedBox(height: 8),
              const Text(
                '전화번호 인증만으로 바로 시작할 수 있어요.',
                style: TextStyle(fontSize: 13.5, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 18),
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
                child: _buildLabeledField(
                  '휴대폰 번호',
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: _inputDecoration(
                      hint: '01012345678',
                      icon: Icons.phone_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: _primaryBtnStyle(enabled: !_isLoading),
                  onPressed: _isLoading ? null : _startWebViewCertification,
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
                          '본인인증 하기',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '인증 후 기존 회원이라면 자동 로그인, 신규 회원이면 다음 단계로 이어집니다.',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF6B7280)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFirstPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              const Text(
                '기본 정보를 입력해주세요',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF191F28)),
              ),
              const SizedBox(height: 12),
              const Text(
                '이름과 성별, 출생년도를 정확히 입력해 주세요.',
                style: TextStyle(fontSize: 13.5, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 18),
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
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabeledField(
                      '이름',
                      TextField(
                        controller: _nameController,
                        decoration: _inputDecoration(
                          hint: '홍길동',
                          icon: Icons.person_outline,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '성별',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          RadioListTile<String>(
                            value: '남성',
                            groupValue: _gender,
                            onChanged: (val) => setState(() => _gender = val!),
                            title: const Text('남성'),
                            dense: true,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            activeColor: kBrand,
                          ),
                          const Divider(height: 1, color: Color(0xFFE5E7EB)),
                          RadioListTile<String>(
                            value: '여성',
                            groupValue: _gender,
                            onChanged: (val) => setState(() => _gender = val!),
                            title: const Text('여성'),
                            dense: true,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            activeColor: kBrand,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildLabeledField(
                      '출생년도',
                      TextField(
                        controller: _birthController,
                        keyboardType: TextInputType.number,
                        decoration: _inputDecoration(
                          hint: '예: 19950614',
                          icon: Icons.cake_outlined,
                        ),
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
                  onPressed: _isLoading
                      ? null
                      : () {
                          ScreenAnalyticsService.instance.logEvent(
                            'worker_signup_step_complete',
                            params: {'step': 1, 'name': 'profile'},
                          );
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                          setState(() => _currentPage = 2);
                        },
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
                          '다음',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSecondPage() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 자신 있는 업무
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
                        '자신 있는 업무 (2개까지 선택)',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: strengthOptions.map((item) {
                          final isSelected = _strengths.contains(item);
                          return FilterChip(
                            label: Text(
                              item,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : const Color(0xFF111827),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
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
                            selectedColor: kBrand,
                            checkmarkColor: Colors.white,
                            backgroundColor: const Color(0xFFF3F4F6),
                            shape: StadiumBorder(
                              side: BorderSide(
                                color: isSelected
                                    ? kBrand
                                    : const Color(0xFFE5E7EB),
                                width: 1,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 나를 표현하는 단어
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
                        '나를 표현하는 단어',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: traitOptions.map((item) {
                          final isSelected = _traits.contains(item);
                          return FilterChip(
                            label: Text(
                              item,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : const Color(0xFF111827),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
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
                            selectedColor: const Color(0xFF10B981),
                            checkmarkColor: Colors.white,
                            backgroundColor: const Color(0xFFF3F4F6),
                            shape: StadiumBorder(
                              side: BorderSide(
                                color: isSelected
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFFE5E7EB),
                                width: 1,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: _primaryBtnStyle(enabled: !_isLoading),
                    onPressed: _isLoading ? null : _nextPage,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}