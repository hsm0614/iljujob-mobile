import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../../config/app_theme.dart';

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
      backgroundColor: AppColors.bgCard,
      appBar: AppBar(title: Text(title)),
      body: FutureBuilder<String>(
        future: rootBundle.loadString(filePath),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            child: Text(
              snapshot.data ?? '',
              style: AppTextStyles.body2.copyWith(
                color: AppColors.textPrimary,
                height: 1.7,
              ),
            ),
          );
        },
      ),
    );
  }
}
