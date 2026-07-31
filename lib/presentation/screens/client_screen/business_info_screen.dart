// File: lib/presentation/screens/business_info_screen.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_analytics/firebase_analytics.dart';
import '../../../config/constants.dart';
import '../../../data/services/authenticated_http_client.dart';

const kBrandBlue = Color(0xFF3B8AFF);

class ClientBusinessInfoScreen extends StatefulWidget {
  const ClientBusinessInfoScreen({super.key});

  @override
  State<ClientBusinessInfoScreen> createState() =>
      _ClientBusinessInfoScreenState();
}

class _ClientBusinessInfoScreenState extends State<ClientBusinessInfoScreen> {
  // ── 컨트롤러 ──────────────────────────────────────────────────
  final _bizNumberController = TextEditingController();
  final _storeNameController = TextEditingController();

  // ── 상태 ──────────────────────────────────────────────────────
  bool _loading = false;
  bool _verified = false;
  String? _errorMessage;

  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  // ── 생명주기 ──────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _analytics.logEvent(name: 'biz_verify_page_view');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowOnboardingSheet();
    });
  }

  @override
  void dispose() {
    _bizNumberController.dispose();
    _storeNameController.dispose();
    super.dispose();
  }

  // ── 온보딩 바텀시트 (추천인 코드) ────────────
  //   유입경로 설문은 제거됨 — 가입 흐름의 마찰을 줄이기 위해(응답률도 낮았음).
  //   유입경로가 필요하면 가입 이후 별도 채널(문자/알림)에서 보상과 함께 물을 것.
  Future<void> _maybeShowOnboardingSheet() async {
    final prefs = await SharedPreferences.getInstance();
    final already = prefs.getBool('onboarding_sheet_shown') ?? false;
    if (already) return;

    await prefs.setBool('onboarding_sheet_shown', true);
    if (!mounted) return;

    final referralCodeController = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setSheet) => Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    24,
                    20,
                    MediaQuery.of(ctx).viewInsets.bottom + 36,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 핸들
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE5E7EB),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),

                      // ── 추천인 코드 ──────────────────────────────────
                      const Text(
                        '추천인 코드가 있으신가요?',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '없으시면 비워두셔도 돼요.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: referralCodeController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: _sheetInputDecoration('추천인 번호 입력 (선택)'),
                      ),

                      const SizedBox(height: 28),

                      // ── 확인 버튼 ────────────────────────────────────
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () async {
                            await _submitOnboarding(
                              referralCode: referralCodeController.text.trim(),
                            );

                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                          },
                          style: _primaryButtonStyle(),
                          child: const Text(
                            '확인',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Center(
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text(
                            '건너뛰기',
                            style: TextStyle(
                              color: Color(0xFF9CA3AF),
                              fontSize: 13,
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

  // ── 온보딩 제출 ───────────────────────────────────────────────
  Future<void> _submitOnboarding({required String referralCode}) async {
    final prefs = await SharedPreferences.getInstance();

    final clientId = prefs.getInt('userId') ?? prefs.getInt('clientId');
    final authToken = prefs.getString('authToken');

    debugPrint('=== onboarding submit start ===');
    debugPrint('clientId=$clientId');
    debugPrint('referralCode=$referralCode');
    debugPrint('authToken exists=${authToken != null && authToken.isNotEmpty}');

    if (clientId == null) {
      _showSnackbar('회원 정보가 없어 저장할 수 없어요.');
      debugPrint('clientId is null -> stop');
      return;
    }

    // 추천인 코드 적용
    if (referralCode.isNotEmpty) {
      try {
        final res = await AuthenticatedHttpClient.postJson(
          Uri.parse('$baseUrl/api/client/apply-referral'),
          body: {'clientId': clientId, 'referralCode': referralCode},
        );

        debugPrint('apply-referral status=${res.statusCode}');
        debugPrint('apply-referral body=${res.body}');

        final data = jsonDecode(res.body);

        if (res.statusCode == 200 && data['success'] == true) {
          _showSnackbar('추천인 코드가 적용되었습니다.');
        } else {
          _showSnackbar(data['message'] ?? '유효하지 않은 추천인 코드예요.');
        }
      } catch (e) {
        debugPrint('apply-referral error=$e');
        _showSnackbar('추천인 등록 중 오류가 발생했어요.');
      }
    }

    debugPrint('=== onboarding submit end ===');
  }

  // ── 건너뛰기 ──────────────────────────────────────────────────
  Future<void> _skip() async {
    _analytics.logEvent(name: 'biz_verify_skipped');
    Navigator.pushReplacementNamed(
      context,
      '/client_main',
      arguments: {'initialTabIndex': 2},
    );
  }

  // ── 사업자 조회 ───────────────────────────────────────────────
  Future<void> _lookup() async {
    FocusScope.of(context).unfocus();

    final biz = _bizNumberController.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (biz.length != 10) {
      setState(() => _errorMessage = '사업자등록번호는 숫자 10자리여야 합니다.');
      return;
    }

    _analytics.logEvent(name: 'biz_verify_attempt', parameters: {'biz': biz});

    setState(() {
      _loading = true;
      _errorMessage = null;
      _verified = false;
    });

    final uri = Uri.parse(
      'https://api.odcloud.kr/api/nts-businessman/v1/status'
      '?serviceKey=$odCloudApiKeyEnc&returnType=JSON',
    );

    try {
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'b_no': [biz],
        }),
      );

      if (res.statusCode != 200) {
        setState(() => _errorMessage = '조회가 지연되고 있어요. 잠시 후 다시 시도해주세요.');
        return;
      }

      final json = jsonDecode(res.body);
      final List data = (json['data'] is List) ? json['data'] : [];

      if (data.isEmpty) {
        setState(() => _errorMessage = '등록되지 않은 사업자번호입니다.');
        _analytics.logEvent(
          name: 'biz_verify_fail',
          parameters: {'reason': 'not_registered'},
        );
        return;
      }

      final item = data.first;
      if (item['b_stt'] == '계속사업자' || item['b_stt_cd'] == '01') {
        setState(() => _verified = true);
        _analytics.logEvent(
          name: 'biz_verify_success',
          parameters: {'biz': biz},
        );
      } else {
        setState(() => _errorMessage = '폐업/휴업 상태로 확인됩니다.');
        _analytics.logEvent(
          name: 'biz_verify_fail',
          parameters: {'reason': 'closed_or_paused'},
        );
      }
    } catch (_) {
      setState(() => _errorMessage = '네트워크 연결을 확인해주세요.');
      _analytics.logEvent(
        name: 'biz_verify_fail',
        parameters: {'reason': 'network'},
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  // ── 저장 후 이동 ──────────────────────────────────────────────
  Future<void> _saveAndGo() async {
    _analytics.logEvent(name: 'biz_verify_cta_post_job');

    final prefs = await SharedPreferences.getInstance();
    final clientId = prefs.getInt('userId');
    final biz = _bizNumberController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final storeName =
        _storeNameController.text.trim().isEmpty
            ? null
            : _storeNameController.text.trim();

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final res = await AuthenticatedHttpClient.postJson(
        Uri.parse('$baseUrl/api/client/update-bizinfo'),
        body: {
          'clientId': clientId,
          'bizNumber': biz,
          'companyName': storeName,
          'openDate': null,
          'address': null,
        },
      );

      final json = jsonDecode(res.body);

      if (res.statusCode == 200 && json['success'] == true) {
        await prefs.setString('bizNumber', biz);
        if (storeName != null) await prefs.setString('companyName', storeName);

        Navigator.pushReplacementNamed(
          context,
          '/client_main',
          arguments: {'initialTabIndex': 2},
        );
      } else {
        setState(() => _errorMessage = '저장 중 문제가 발생했어요. 다시 시도해주세요.');
      }
    } catch (_) {
      setState(() => _errorMessage = '서버 연결이 불안정합니다.');
    } finally {
      setState(() => _loading = false);
    }
  }

  // ── build ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('사업자 인증'),
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed:
                () => Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/client_main',
                  (route) => false,
                  arguments: {'initialTabIndex': 2},
                ),
          ),
          actions: [
            TextButton(
              onPressed: _skip,
              child: const Text(
                '건너뛰기',
                style: TextStyle(
                  color: Color(0xFF8B95A1),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              20 + MediaQuery.of(context).padding.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 14),
                const Text(
                  '사장님, 공고 등록 전에\n사업자번호만 확인할게요.',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  '휴업/폐업 여부만 간단히 체크해요.',
                  style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
                ),
                const SizedBox(height: 6),
                const Text(
                  '사업자등록번호가 없으시면\nhsm@outfind.co.kr 로 문의해주세요.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                ),
                const SizedBox(height: 12),

                // 건너뛰기 배너
                GestureDetector(
                  onTap: _skip,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F6FA),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE5E8EB)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: Color(0xFF8B95A1),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '지금 당장 없으셔도 괜찮아요. 나중에 마이페이지에서 인증할 수 있어요.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                              height: 1.4,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          '건너뛰기 →',
                          style: TextStyle(
                            fontSize: 13,
                            color: kBrandBlue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // 사업자번호 입력
                _bizInputField(
                  controller: _bizNumberController,
                  hint: '사업자등록번호 (숫자 10자리)',
                ),
                const SizedBox(height: 14),
                _bizInputField(
                  controller: _storeNameController,
                  hint: '상호명 (선택)',
                  keyboardType: TextInputType.text,
                ),

                // 로딩
                if (_loading) ...[
                  const SizedBox(height: 24),
                  const Center(
                    child: CircularProgressIndicator(color: kBrandBlue),
                  ),
                ],

                // 에러 메시지
                if (_errorMessage != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ],

                // 인증 성공 배너
                if (_verified) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE9F3FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 18,
                          color: kBrandBlue,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '계속사업자로 확인되었습니다.\n바로 공고 등록하실 수 있어요.',
                            style: TextStyle(fontSize: 15, color: kBrandBlue),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 28),

                // CTA 버튼
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed:
                        _loading ? null : (_verified ? _saveAndGo : _lookup),
                    style: _primaryButtonStyle(),
                    child: Text(
                      _verified ? '공고 등록하기' : '사업자 확인하기',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
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

  // ── 위젯 헬퍼 ─────────────────────────────────────────────────
  Widget _bizInputField({
    required TextEditingController controller,
    required String hint,
    TextInputType keyboardType = TextInputType.number,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF6F8FA),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kBrandBlue, width: 2),
        ),
      ),
    );
  }

  InputDecoration _sheetInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFFD1D5DB)),
      filled: true,
      fillColor: const Color(0xFFF6F8FA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kBrandBlue, width: 1.5),
      ),
    );
  }

  ButtonStyle _primaryButtonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: kBrandBlue,
      disabledBackgroundColor: kBrandBlue.withOpacity(0.4),
      foregroundColor: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  void _showSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

// ── 상수 ──────────────────────────────────────────────────────
