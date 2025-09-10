import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class PolicyDetailScreen extends StatelessWidget {
  final String filePath; // 예: 'assets/policies/wage_policy.md'
  final String title; // ← 이걸 추가

  const PolicyDetailScreen({
    super.key,
    required this.filePath,
    required this.title, // ← 이걸 추가
  });

  Future<String> _loadMarkdown() async {
    return await rootBundle.loadString(filePath);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _loadMarkdown(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (!snapshot.hasData) {
          return const Scaffold(body: Center(child: Text('문서를 불러올 수 없습니다.')));
        }

        return Scaffold(
          appBar: AppBar(title: Text(title)), // ← 이 부분도 title 사용
          body: Markdown(data: snapshot.data!),
        );
      },
    );
  }
}
