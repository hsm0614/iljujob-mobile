import 'package:flutter/material.dart';
import 'TermsDetailScreen.dart';
class TermsListScreen extends StatelessWidget {
  const TermsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('약관 및 정책')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '서비스 관련 약관',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey),
            ),
          ),
          ListTile(
            title: const Text('서비스 이용약관'),
            onTap: () {
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
          ),
          ListTile(
            title: const Text('위치기반서비스 이용약관'),
            onTap: () {
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
          ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '개인정보 보호',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey),
            ),
          ),
          ListTile(
            title: const Text('개인정보 처리방침'),
            onTap: () {
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
          ),
          ListTile(
            title: const Text('마케팅 수신 동의'),
            onTap: () {
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
          ),
        ],
      ),
    );
  }
}