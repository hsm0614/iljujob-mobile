// File: lib/presentation/screens/business_info_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_analytics/firebase_analytics.dart';
import '../../config/constants.dart'; // ✅ kBrandBlue, baseUrl, odCloudApiKeyEnc

const kBrandBlue = Color(0xFF3B8AFF);

class ClientBusinessInfoScreen extends StatefulWidget {
  const ClientBusinessInfoScreen({super.key});

  @override
  State<ClientBusinessInfoScreen> createState() => _ClientBusinessInfoScreenState();
}

class _ClientBusinessInfoScreenState extends State<ClientBusinessInfoScreen> {
  final _bizNumberController = TextEditingController();
  final _storeNameController = TextEditingController();
  bool _loading = false;
  bool _verified = false;
  String? _errorMessage;

  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance; // ✅ Analytics 인스턴스

  @override
  void initState() {
    super.initState();
    _analytics.logEvent(name: 'biz_verify_page_view'); // ✅ 화면 진입 이벤트
  }

  Future<void> _lookup() async {
    FocusScope.of(context).unfocus();

    final biz = _bizNumberController.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (biz.length != 10) {
      setState(() => _errorMessage = "사업자등록번호는 숫자 10자리여야 합니다.");
      return;
    }

    _analytics.logEvent(name: 'biz_verify_attempt', parameters: {"biz": biz}); // ✅ 조회 시도 이벤트

    setState(() {
      _loading = true;
      _errorMessage = null;
      _verified = false;
    });

    final uri = Uri.parse(
      "https://api.odcloud.kr/api/nts-businessman/v1/status"
      "?serviceKey=$odCloudApiKeyEnc&returnType=JSON",
    );

    final body = jsonEncode({"b_no": [biz]});

    try {
      final res = await http.post(
        uri,
        headers: {"Content-Type": "application/json"},
        body: body,
      );

      if (res.statusCode != 200) {
        setState(() => _errorMessage = "조회가 지연되고 있어요. 잠시 후 다시 시도해주세요.");
        return;
      }

      final json = jsonDecode(res.body);
      final List data = (json["data"] is List) ? json["data"] : [];

      if (data.isEmpty) {
        setState(() => _errorMessage = "등록되지 않은 사업자번호입니다.");
        _analytics.logEvent(name: 'biz_verify_fail', parameters: {"reason": "not_registered"});
        return;
      }

      final item = data.first;
      final bStt = item["b_stt"];
      final bSttCd = item["b_stt_cd"];

      if (bStt == "계속사업자" || bSttCd == "01") {
        setState(() => _verified = true);
        _analytics.logEvent(name: 'biz_verify_success', parameters: {"biz": biz}); // ✅ 성공 이벤트
      } else {
        setState(() => _errorMessage = "폐업/휴업 상태로 확인됩니다.");
        _analytics.logEvent(name: 'biz_verify_fail', parameters: {"reason": "closed_or_paused"});
      }

    } catch (_) {
      setState(() => _errorMessage = "네트워크 연결을 확인해주세요.");
      _analytics.logEvent(name: 'biz_verify_fail', parameters: {"reason": "network"});
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveAndGo() async {
    _analytics.logEvent(name: 'biz_verify_cta_post_job'); // ✅ CTA 클릭 이벤트

    final prefs = await SharedPreferences.getInstance();
    final clientId = prefs.getInt("userId");
    final biz = _bizNumberController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final storeName = _storeNameController.text.trim().isEmpty
        ? null
        : _storeNameController.text.trim();

    try {
      final res = await http.post(
        Uri.parse("$baseUrl/api/client/update-bizinfo"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "clientId": clientId,
          "bizNumber": biz,
          "companyName": storeName,
          "openDate": null,
          "address": null
        }),
      );

      final json = jsonDecode(res.body);

      if (res.statusCode == 200 && json["success"] == true) {
        await prefs.setString("bizNumber", biz);
        if (storeName != null) await prefs.setString("companyName", storeName);

Navigator.pushReplacementNamed(
  context,
  '/client_main',
  arguments: {'initialTabIndex': 2},
);
      } else {
        setState(() => _errorMessage = "저장 중 문제가 발생했어요. 다시 시도해주세요.");
      }
    } catch (_) {
      setState(() => _errorMessage = "서버 연결이 불안정합니다.");
    }
  }

@override
Widget build(BuildContext context) {
  final bottom = MediaQuery.of(context).padding.bottom; // ✅ 하단 안전구역 확보

  return GestureDetector(
    onTap: () => FocusScope.of(context).unfocus(),
    child: Scaffold(
      resizeToAvoidBottomInset: true, // ✅ 키보드/네비바 회피
      backgroundColor: Colors.white,
appBar: AppBar(
  title: const Text("사업자 인증"),
  backgroundColor: Colors.white,
  elevation: 0,
  leading: IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () {
      // ✅ client_main 으로 돌아가며 client 탭은 '내 공고(1)'
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/client_main',
        (route) => false,
        arguments: {'initialTabIndex': 1},
      );
    },
  ),
),
      body: SafeArea(
        child: SingleChildScrollView( // ✅ 가려짐 방지
          padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottom), // ✅ 하단 패딩 자동 반영
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 14),
              const Text(
                "사장님, 공고 등록 전에\n사업자번호만 확인할게요.",
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text("휴업/폐업 여부만 간단히 체크해요.", style: TextStyle(fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 6),
              Text("사업자등록번호가 없으시면\nhsm@outfind.co.kr 로 문의해주세요 😊",
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 32),

              _inputField(controller: _bizNumberController, hint: "사업자등록번호 (숫자 10자리)"),
              const SizedBox(height: 14),
              _inputField(controller: _storeNameController, hint: "상호명 (선택)"),

              if (_loading) ...[
                const SizedBox(height: 24),
                const Center(child: CircularProgressIndicator(color: kBrandBlue)),
              ],

              if (_errorMessage != null) ...[
                const SizedBox(height: 14),
                Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
              ],

              if (_verified) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Color(0xFFE9F3FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    "✅ 계속사업자로 확인되었습니다.\n바로 공고 등록하실 수 있어요.",
                    style: TextStyle(fontSize: 15, color: kBrandBlue),
                  ),
                ),
              ],

              const SizedBox(height: 28),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _verified ? _saveAndGo : _lookup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kBrandBlue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    _verified ? "공고 등록하기 🚀" : "사업자 확인하기",
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
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


  Widget _inputField({required TextEditingController controller, required String hint}) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF6F8FA),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: kBrandBlue, width: 2),
        ),
      ),
    );
  }
}
