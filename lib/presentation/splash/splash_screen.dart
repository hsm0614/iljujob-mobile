import 'package:flutter/material.dart';
import 'package:iljujob/config/app_theme.dart';
import 'package:iljujob/widget/app_ui.dart';

class SplashScreen extends StatefulWidget {
  final Widget nextScreen;

  const SplashScreen({super.key, required this.nextScreen});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 3), () {
      print('⏩ Splash → ${widget.nextScreen.runtimeType}');
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => widget.nextScreen),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // 네이티브 스플래시(파랑 + 흰 일주이)와 이어지게 같은 바탕 (2026-11)
    return const Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Iljui(size: 128, mood: IljuiMood.white, animate: true),
            SizedBox(height: 20),
            AlbailjuLockup(height: 40, onBlue: true),
          ],
        ),
      ),
    );
  }
}
