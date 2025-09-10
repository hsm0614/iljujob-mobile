import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

class TermsDetailScreen extends StatelessWidget {
  final String filePath;
  final String title;

  const TermsDetailScreen({
    super.key,
    required this.filePath,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: FutureBuilder<String>(
        future: rootBundle.loadString(filePath),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Text(snapshot.data ?? ''),
          );
        },
      ),
    );
  }
}
