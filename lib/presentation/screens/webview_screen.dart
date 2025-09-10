// lib/screens/webview_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

// ✅ StatefulWidget으로 변경
class WebViewScreen extends StatefulWidget {
  final String url;
  const WebViewScreen({super.key, required this.url});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

// ✅ State 클래스 생성
class _WebViewScreenState extends State<WebViewScreen> {
  bool _hasPopped = false; // ✅ 중복 방지용

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('본인 인증')),
      body: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(widget.url)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          allowsInlineMediaPlayback: true,
          mediaPlaybackRequiresUserGesture: false,
        ),
        onLoadStop: (controller, url) {
          final currentUrl = url?.toString() ?? '';
          if (!_hasPopped && currentUrl.contains('/verify/redirect')) {
            final uri = Uri.parse(currentUrl);
            final impUid = uri.queryParameters['imp_uid'];
            if (impUid != null && impUid.isNotEmpty && Navigator.of(context).canPop()) {
        

              _hasPopped = true; // ✅ 중복 pop 방지

final startTime = DateTime.now();
Future.delayed(const Duration(seconds: 2), () {
  final elapsed = DateTime.now().difference(startTime).inMilliseconds;

  Navigator.pop(context, impUid);
});
            }
          }
        },
      ),
    );
  }
}
