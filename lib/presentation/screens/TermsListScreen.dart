import 'package:flutter/material.dart';
import 'TermsDetailScreen.dart';
import '../../widget/app_ui.dart';

class TermsListScreen extends StatelessWidget {
  const TermsListScreen({super.key});

  static const _terms = [
    ('서비스 이용약관', 'assets/terms/terms_of_service.txt'),
    ('위치기반서비스 이용약관', 'assets/terms/location_terms.txt'),
    ('개인정보 처리방침', 'assets/terms/privacy_policy.txt'),
    ('마케팅 수신 동의', 'assets/terms/marketing_terms.txt'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('약관 및 정책')),
      body: ListView(
        children: [
          AppMenuSection(
            children: [
              for (final (title, path) in _terms)
                AppMenuRow(
                  label: title,
                  onTap:
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (_) => TermsDetailScreen(
                                filePath: path,
                                title: title,
                              ),
                        ),
                      ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
