// lib/presentation/screens/pass_payment_failed_screen.dart
import 'package:flutter/material.dart';

class PassPaymentFailedScreen extends StatelessWidget {
  final String? errorMsg;

  const PassPaymentFailedScreen({super.key, this.errorMsg});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('결제 실패'),
        automaticallyImplyLeading: false, // 뒤로 가기 버튼 숨기기
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, color: Colors.red, size: 80),
            const SizedBox(height: 20),
            const Text(
              '결제에 실패했습니다.',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            if (errorMsg != null) Text('오류 메시지: $errorMsg'),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                // 결제 재시도 화면 또는 홈 화면으로 돌아가기
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              child: const Text('확인'),
            ),
          ],
        ),
      ),
    );
  }
}