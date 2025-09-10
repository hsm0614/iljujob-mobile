// lib/presentation/screens/pass_payment_success_screen.dart
import 'package:flutter/material.dart';

class PassPaymentSuccessScreen extends StatelessWidget {
  // 결제 성공 시 전달받을 결제 번호(imp_uid)입니다.
  final String impUid;

  const PassPaymentSuccessScreen({super.key, required this.impUid});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('결제 성공'),
        automaticallyImplyLeading: false, // 뒤로 가기 버튼 숨기기
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 80),
            const SizedBox(height: 20),
            const Text(
              '결제가 성공적으로 완료되었습니다!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text('결제 번호: $impUid'),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                // 홈 화면으로 돌아가기
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