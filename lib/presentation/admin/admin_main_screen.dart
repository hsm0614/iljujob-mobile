import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
class AdminMainScreen extends StatelessWidget {
  const AdminMainScreen({super.key});
void _logout(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear(); // 모든 저장된 정보 삭제

  // 로그인 화면으로 이동 및 히스토리 제거
  Navigator.pushNamedAndRemoveUntil(context, '/onboarding', (route) => false);
}
void checkToken(String token) {
  Map<String, dynamic> decodedToken = JwtDecoder.decode(token);
  print(decodedToken);
}

  @override
  Widget build(BuildContext context) {
     SharedPreferences.getInstance().then((prefs) {
      
    final token = prefs.getString('authToken') ?? '';
    
    if (token.isNotEmpty) {
      checkToken(token);  // ✅ 호출 추가
    } else {
      print("❌ 토큰 없음");
    }
  });
    return Scaffold(
      appBar: AppBar(
  title: const Text(
    '관리자 홈',
    style: TextStyle(fontWeight: FontWeight.bold),
  ),
  backgroundColor: Colors.indigo,
  actions: [
    IconButton(
      icon: const Icon(Icons.logout),
      tooltip: '로그아웃',
      onPressed: () {
        _logout(context);
      },
    ),
  ],
),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '관리자 기능',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          ListTile(
            leading: const Icon(Icons.people),
            title: const Text('회원 목록'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.pushNamed(context, '/admin_users');
            },
          ),

          ListTile(
            leading: const Icon(Icons.work),
            title: const Text('공고 내역 확인'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.pushNamed(context, '/admin/jobs');
            },
          ),

          ListTile(
            leading: const Icon(Icons.report),
            title: const Text('신고 내역 확인'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.pushNamed(context, '/admin_report');
            },
          ),
          ListTile(
            leading: const Icon(Icons.card_giftcard),
            title: const Text('이용권 지급'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.pushNamed(context, '/admin_grant_pass');
            },
          ),
          ListTile(
            leading: const Icon(Icons.bar_chart),
            title: const Text('통계 보기'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.pushNamed(context, '/admin/stats');
            },
          ),
                      ListTile(
              leading: const Icon(Icons.verified_user),
              title: const Text('안심기업 승인 관리'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pushNamed(context, '/admin_safe_company');
              },
            ),
        ListTile(
          leading: const Icon(Icons.verified_user),
          title: const Text('이벤트 작성'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.pushNamed(context, '/admin_event_write');
          },
        ),
        ],
      ),
    );
  }
}
