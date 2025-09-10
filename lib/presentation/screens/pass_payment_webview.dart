import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../../config/constants.dart';
class PassPaymentWebView extends StatefulWidget {
  final int count;
  final String? impUid;
  final Uri? uri;

  const PassPaymentWebView({
    super.key,
    required this.count,
    this.impUid,
    this.uri,
  
   
  });

  @override
  State<PassPaymentWebView> createState() => _PassPaymentWebViewState();
}

class _PassPaymentWebViewState extends State<PassPaymentWebView> with WidgetsBindingObserver {
  WebViewController? _controller;
  bool _isVerifying = false;
  String? _pendingRedirectUrl;

  static const Set<String> _externalSchemes = {
    'market://', 'app_card://', 'ispmobile://', 'hdcardappcardansimclick://',
    'shinhan-sr-ansimclick://', 'kb-acp://', 'kbbank://', 'kftc-bankpay://',
    'kakaotalk://', 'lpayapp://', 'payco://', 'smilepayapp://', 'hanawalletmembers://',
    'wooripay://', 'shinsegaeeasypayment://', 'com.wooricard.wcardapp://',
    'kakaolink://', 'supertoss://', 'naverpayapp://', 'nhallonepayansimclick://',
    'kakaobank://', 
  };
 String? _initialWebUrl;
 
  @override
void initState() {
  super.initState();

  WidgetsBinding.instance.addObserver(this); // ✅ observer 등록

  if (widget.uri != null) {
   debugPrint('🔗 딥링크 URI 감지됨: ${widget.uri}');
    // ✅ 한 프레임 뒤에 딥링크 처리
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleDeepLink(widget.uri!);
    });
  } else {
    // ✅ 딥링크 아니면 일반 결제 플로우 시작
    _initializeWebView();
  }
}

@override
void dispose() {
  WidgetsBinding.instance.removeObserver(this); // ✅ 꼭 제거
  super.dispose();
}@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.resumed) {
    debugPrint('📲 앱 복귀 감지됨 (resumed)');
    debugPrint('📦 현재 _pendingRedirectUrl = $_pendingRedirectUrl');

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      debugPrint('ℹ️ iOS 환경: 리다이렉션 생략');
      _pendingRedirectUrl = null;
      return;
    }

    if (_pendingRedirectUrl != null) {
      final redirectUrl = _pendingRedirectUrl!;
      _pendingRedirectUrl = null; // 재진입 방지

      final merchantUid = Uri.tryParse(redirectUrl)
          ?.queryParameters['merchant_uid'];

      if (merchantUid != null && merchantUid.isNotEmpty) {
        debugPrint('🧾 merchant_uid 추출 성공: $merchantUid');
        _isVerifying = true;
        _verifyWithServerByMerchantUid(merchantUid); // ✅ 서버에 직접 검증 요청
      } else {
        debugPrint('❌ redirectUrl에 merchant_uid 없음: $redirectUrl');
        _showErrorDialog('결제 정보가 유효하지 않습니다.');
      }
    } else {
      debugPrint('❌ 복귀 시 _pendingRedirectUrl이 null임 → 아무 동작 안 함');
    }
  }
}


 Future<void> _initializeWebView() async {
  final prefs = await SharedPreferences.getInstance();
  final spoofedCount = widget.count == 1 ? 101 : widget.count;
  final companyName = Uri.encodeComponent(prefs.getString('companyName') ?? '홍길동');
  final companyPhone = Uri.encodeComponent(prefs.getString('userPhone') ?? '01012345678');

  // ✅ merchant_uid Flutter에서 직접 생성
  final merchantUid = 'order_${DateTime.now().millisecondsSinceEpoch}';

  // ✅ URL에 merchant_uid 포함
  final url =
      'https://albailju.co.kr/payment.html?count=$spoofedCount&name=$companyName&tel=$companyPhone&merchant_uid=$merchantUid';

  // ✅ WebView → 복귀 시 강제로 로드할 redirect URL도 저장
  _initialWebUrl = url;
  _pendingRedirectUrl = 'https://albailju.co.kr/payment-success.html?merchant_uid=$merchantUid';

  debugPrint('🌐 WebView 초기화 시작: $url');
  debugPrint('✅ _initialWebUrl 저장됨: $_initialWebUrl');
  debugPrint('✅ _pendingRedirectUrl 저장됨: $_pendingRedirectUrl');

  final controller = _createWebViewController();
  _controller = controller;

  controller
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setNavigationDelegate(NavigationDelegate(
      onNavigationRequest: _handleNavigationRequest,
     onPageStarted: (url) {
  log('onPageStarted', url);

  // ✅ 외부 앱이면 blank로
  if (_isExternalScheme(url)) {
    debugPrint('🛡️ 외부 앱 스킴 감지됨 → about:blank 로 덮기');
    _controller?.loadRequest(Uri.parse('about:blank'));
  }

 if (url.contains('payment-success.html') && !_hasHandledResult) {
  _hasHandledResult = true; // ✅ 중복 방지 플래그 먼저 설정
  debugPrint('🟢 payment-success.html 감지됨 → 서버 검증 실행');
debugPrint('💬 imp_uid 있음 && _hasHandledResult=$_hasHandledResult');
  final uri = Uri.tryParse(url);
  final merchantUid = uri?.queryParameters['merchant_uid'];

  if (merchantUid != null && merchantUid.isNotEmpty) {
    _handleDeepLink(uri!); // ✅ 딥링크 처리
  } else {
    _showErrorDialog('❌ 결제 정보 누락 (merchant_uid 없음)');
    Navigator.pop(context, null);
  }

  } else {
    debugPrint('🌐 현재 로딩 중인 URL: $url');
  }


},
      onPageFinished: (url) => log('onPageFinished', url),
      onWebResourceError: _handleWebError,
      onUrlChange: (change) {
        if (change.url != null) log('onUrlChange', change.url!);
      },
    ));

  // ✅ 마지막에 로딩
  controller.loadRequest(Uri.parse(url));

  setState(() {});
}

bool _isExternalScheme(String url) {
  const schemes = [
    'intent://', 'market://', 'app_card://', 'ispmobile://', 'hdcardappcardansimclick://',
    'shinhan-sr-ansimclick://', 'kb-acp://', 'kbbank://', 'kftc-bankpay://',
    'kakaotalk://', 'lpayapp://', 'payco://', 'smilepayapp://', 'hanawalletmembers://',
    'wooripay://', 'shinsegaeeasypayment://', 'com.wooricard.wcardapp://',
    'kakaolink://', 'supertoss://', 'naverpayapp://', 'nhallonepayansimclick://',
    'kakaobank://'
  ];
  return schemes.any((scheme) => url.startsWith(scheme));
}


  WebViewController _createWebViewController() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final params = AndroidWebViewControllerCreationParams();
      final controller = WebViewController.fromPlatformCreationParams(params);
      (controller.platform as AndroidWebViewController)
        ..enableZoom(true)
        ..setMediaPlaybackRequiresUserGesture(false);
      return controller;
      
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      final params = WebKitWebViewControllerCreationParams();
      return WebViewController.fromPlatformCreationParams(params);
    }
    return WebViewController();
  }

  bool _hasHandledIntent = false;
  bool _hasHandledResult = false;
  bool _isInternalRedirect = false; // ✅ 내부에서 보낸 success.html → 딥링크 구분용

  NavigationDecision _handleNavigationRequest(NavigationRequest request) {
  final url = request.url;
  final uri = Uri.tryParse(url);

  if (uri == null) {
    _showErrorDialog('잘못된 URI 형식:\n$url');
    return NavigationDecision.prevent;
  }

if (uri.scheme == 'albailju' && uri.host == 'callback') {
  final impUid = uri.queryParameters['imp_uid'];
  // imp_uid가 있으면 항상 처리 (중복 방지 X)
  if (impUid != null && impUid.isNotEmpty) {
    debugPrint('🟢 결제 성공 딥링크 감지됨 → _handleDeepLink 호출');
    _handleDeepLink(uri);
    _hasHandledResult = true;
    _isInternalRedirect = false;
    return NavigationDecision.prevent;
  }
  // imp_uid가 없으면 기존 중복 방지 로직 적용
  if (_hasHandledResult && (!_isInternalRedirect || (impUid?.isEmpty ?? true))) {
    debugPrint('🛑 딥링크 이미 처리됨 → 무시');
    return NavigationDecision.prevent;
  }
  _hasHandledResult = true;
  debugPrint('🟢 딥링크 감지됨 → _handleDeepLink 호출');
  _handleDeepLink(uri);
  _isInternalRedirect = false;
  return NavigationDecision.prevent;
}

  // ✅ 2. payment-success.html 페이지 감지 시 직접 처리
  if (url.contains('payment-success.html')) {
    debugPrint('🌐 현재 로딩 중인 URL: $url'); // 이거 먼저
     _isInternalRedirect = true;
    if (_hasHandledResult) {
      debugPrint('🛑 결과 이미 처리됨 (success.html) → 무시');
      return NavigationDecision.prevent;
    }
    _hasHandledResult = true;
    debugPrint('🟢 payment-success.html 감지됨 → merchant_uid로 검증 시도');

    // ✅ URL에서 merchant_uid를 직접 파싱하여 서버 검증 로직 호출
    final merchantUid = uri.queryParameters['merchant_uid'];
    
    if (merchantUid != null) {
      _verifyWithServerByMerchantUid(merchantUid);
    } else {
      // merchant_uid가 없는 경우, 결제 정보를 확인할 수 없다고 안내
      _showErrorDialog('결제 정보를 확인할 수 없습니다. (UID 누락)');
      Navigator.pop(context, null);
    }
    
    return NavigationDecision.prevent;
  }
  
  // 3. 외부 결제 앱 실행을 위한 intent:// URL 처리
  if (url.startsWith('intent://')) {
    if (_hasHandledResult) {
      debugPrint('🛑 결제 결과 처리 후 intent:// URL 감지 → 무시');
      return NavigationDecision.prevent;
    }
    
    debugPrint('🟢 intent:// URL 감지됨 → 외부 앱 실행 시도');
    _launchIntentUri(url);

    // 웹뷰의 기본 URL 이동을 막음
    return NavigationDecision.prevent;
  }
  
  // 4. 기타 외부 앱 실행 스키마 처리
  if (_externalSchemes.any(url.startsWith)) {
    _launchExternalApp(url);
    return NavigationDecision.prevent;
  }

  // 5. http/https 또는 about:blank와 같은 정상적인 URL만 허용
  if (url.startsWith('http') || url.startsWith('about:')) {
    return NavigationDecision.navigate;
  }

  // 6. 그 외 알 수 없는 스키마 차단
  _showErrorDialog('차단된 URL:\n$url');
  return NavigationDecision.prevent;
}

  void _handleWebError(WebResourceError error) {
  final url = error.url ?? '';
  log('webview_error', {
    'description': error.description,
    'url': url,
    'code': error.errorCode,
  });

  // iOS 딥링크는 onNavigationRequest에서 처리되지 않을 경우 여기서 처리
  if (url.startsWith('albailju://')) {
    debugPrint('🟢 iOS 딥링크 WebView 에러 → 직접 딥링크 처리');
    _handleDeepLink(Uri.parse(url));
    return;
  }
  
  // onNavigationRequest에서 처리하지 못한 intent:// URL은
  // WebView 에러로 잡히므로 여기서 다시 launch 시도
if (url.startsWith('intent://')) {
  debugPrint('🌐 onWebResourceError에서 intent:// 감지됨 → launch 시도');

  if (_controller == null) {
    debugPrint('🛑 _controller가 아직 null → WebView 오류화면 차단 실패 가능성');
  } else {
    _controller!.loadRequest(Uri.parse('about:blank')); // ✅ WebView 오류 화면 덮기
  }

  _launchIntentUri(url);
  return;
}

  _showErrorDialog('WebView 오류: ${error.description}');
}
bool _hasHandledDeepLink = false;

void _handleDeepLink(Uri uri) {
  if (_hasHandledDeepLink) {
    debugPrint('🛑 딥링크 이미 처리됨 → 무시');
    return;
  }

  final impUid = uri.queryParameters['imp_uid'];
  final merchantUid = uri.queryParameters['merchant_uid'];
  final success = uri.queryParameters['success'] == 'true';
  final errorMsg = uri.queryParameters['error_msg'] ?? '알 수 없는 오류';

  log('deep_link_processed', {
    'uri': uri.toString(),
    'success': success,
    'impUid': impUid,
    'merchantUid': merchantUid
  });

  debugPrint('🔗 딥링크 처리됨: $uri');

if (impUid?.isNotEmpty == true) {
  debugPrint('🟢 imp_uid 있음 → 서버 검증 시작: $impUid');
  _hasHandledDeepLink = true;
  _hasHandledResult = true; // 또는 여기에서 명시적으로 세팅
  _isVerifying = true;
  _verifyWithServer(impUid!);
  return;
}

  // ✅ imp_uid 없을 경우에만 복구 시도
  if ((impUid == null || impUid.isEmpty) && merchantUid?.isNotEmpty == true && !_isVerifying) {
    debugPrint('🔁 imp_uid 없음 → merchant_uid로 복구 시도');
    _hasHandledDeepLink = true;
    _isVerifying = true;
    _verifyWithServerByMerchantUid(merchantUid!);
    return;
  }

  // ✅ 명시적 실패 처리
  if (!success) {
    _hasHandledDeepLink = true;
    log('deep_link_path', {'path': 'payment failed'});
    _showErrorDialog('결제 실패: ${Uri.decodeComponent(errorMsg)}');
    Navigator.pop(context, null);
    return;
  }

  // ✅ 예외 처리
  _hasHandledDeepLink = true;
  log('deep_link_path', {'path': 'unknown result'});
  _showErrorDialog('결제 결과를 확인할 수 없습니다.');
  Navigator.pop(context, null);
}
Future<void> _verifyWithServerByMerchantUid(String merchantUid, {int retryCount = 0}) async {
  final prefs = await SharedPreferences.getInstance();
  final clientId = prefs.getInt('userId') ?? 0;

  try {
    debugPrint('📡 server_verify_by_merchant: merchantUid=$merchantUid, clientId=$clientId');

    final res = await http.post(
      Uri.parse('$baseUrl/api/pass/verify'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'merchantUid': merchantUid,
        'clientId': clientId,
        'platform': defaultTargetPlatform.name,
      }),
    );

    final statusCode = res.statusCode;
    final responseBody = jsonDecode(res.body);
    final status = responseBody['status'];
    final impUid = responseBody['impUid'];

    if (statusCode == 200 && impUid != null && impUid.toString().isNotEmpty) {
  debugPrint('🟢 검증 성공 → 앱에서 직접 결제 완료 처리');
  final successUrl =
      'https://albailju.co.kr/payment-success.html?merchant_uid=$merchantUid&imp_uid=$impUid&clientId=$clientId';

  // ✅ 1. 먼저 blank로 초기화 (WebView 내부 캐시 등 방지)
  await _controller?.loadRequest(Uri.parse('about:blank'));
  await Future.delayed(const Duration(milliseconds: 300));

  // ✅ 2. 진짜 success.html 로드
Future.delayed(const Duration(seconds: 2), () async {
  if (mounted) {
    await _controller?.loadRequest(Uri.parse(successUrl));
    debugPrint('✅ successUrl 로드: $successUrl');
  }
});

  // ✅ 3. pop은 충분히 여유를 준 후 실행 (예: 2~3초)
  Future.delayed(const Duration(seconds: 2), () {
    if (mounted) Navigator.pop(context, impUid);
  });

  return;
}
    // ✅ 최대 3회까지 재시도 (점점 늘어나는 간격)
    else if (status == 'ready' && retryCount < 3) {
      final delay = 3 * (retryCount + 1);
      debugPrint('🕐 아직 결제 미완료 상태 (ready) → ${delay}초 후 재시도 (${retryCount + 1}/3)');
      await Future.delayed(Duration(seconds: delay));
      return _verifyWithServerByMerchantUid(merchantUid, retryCount: retryCount + 1);
    }

    // ❌ 최종 실패 처리
    else {
      log('server_verify_by_merchant_failure', {
        'statusCode': statusCode,
        'responseBody': res.body,
      });
      _showErrorDialog(responseBody['message'] ?? '검증 실패');
      Navigator.pop(context, null);
    }
  } catch (e) {
    log('server_verify_by_merchant_error', {'error': e.toString()});
    _showErrorDialog('서버 오류: $e');
    Navigator.pop(context, null);
  } finally {
    _isVerifying = false;
  }
}

  Future<void> _verifyWithServer(String impUid) async {
    final prefs = await SharedPreferences.getInstance();
    final clientId = prefs.getInt('userId') ?? 0;
    debugPrint('📡 server_verify: impUid=$impUid, clientId=$clientId');
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/pass/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'impUid': impUid,
          'clientId': clientId,
          
          'platform': defaultTargetPlatform.name,
        }),
      );

      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 이용권이 정상 지급되었습니다')));
          Navigator.pop(context, impUid);
        }
      } else {
        _showErrorDialog(jsonDecode(res.body)['message'] ?? '검증 실패');
        Navigator.pop(context, null);
      }
    } catch (e) {
      _showErrorDialog('서버 오류: $e');
      Navigator.pop(context, null);
    } finally {
      _isVerifying = false;
    }
  }
  
 void _launchIntentUri(String url) async {
  log('intent_launch_attempt', url);
  debugPrint('📥 _launchIntentUri 진입 - url: $url');

  try {
    final schemeMatch = RegExp(r'scheme=([^\;&]+)').firstMatch(url);
    final pkgMatch = RegExp(r'package=([^\;&]+)').firstMatch(url);
    final fallbackMatch = RegExp(r'S\.browser_fallback_url=([^\;&]+)').firstMatch(url);

    final scheme = schemeMatch?.group(1);
    final pkg = pkgMatch?.group(1);
    final fallbackUrl = fallbackMatch != null ? Uri.decodeComponent(fallbackMatch.group(1)!) : null;

    debugPrint('🔍 파싱 결과: scheme=$scheme, package=$pkg, fallbackUrl=$fallbackUrl');

    final base = url.substring(url.indexOf('intent://') + 9, url.indexOf('#Intent'));
    final launchUrl = '$scheme://$base';

    debugPrint('🚀 실행 URL: $launchUrl');
    final merchantUid = Uri.tryParse(_initialWebUrl ?? '')?.queryParameters['merchant_uid'];
   debugPrint('✅ 추출된 merchant_uid: $merchantUid');
    if (merchantUid != null) {
      _pendingRedirectUrl = 'https://albailju.co.kr/payment-success.html?merchant_uid=$merchantUid';
      debugPrint('📝 _pendingRedirectUrl 저장됨: $_pendingRedirectUrl');
    }

    if (await canLaunchUrlString(launchUrl)) {
      debugPrint('✅ launchUrl 실행 가능 → 실행 시도');
      await launchUrlString(launchUrl, mode: LaunchMode.externalApplication);
      return;
    } else {
      debugPrint('❌ launchUrl 실행 불가');
    }

    if (fallbackUrl != null && await canLaunchUrlString(fallbackUrl)) {
      debugPrint('🔁 fallback_url 실행 가능 → $fallbackUrl');
      await launchUrlString(fallbackUrl, mode: LaunchMode.externalApplication);
      return;
    } else {
      debugPrint('❌ fallback_url 실행 불가 또는 없음');
    }

    if (pkg != null) {
      final marketUrl = 'market://details?id=$pkg';
      debugPrint('🛒 마켓 이동 시도: $marketUrl');
      if (await canLaunchUrlString(marketUrl)) {
        debugPrint('✅ 마켓 실행 가능 → 이동');
        await launchUrlString(marketUrl, mode: LaunchMode.externalApplication);
        return;
      } else {
        debugPrint('❌ 마켓 실행 불가');
      }
    } else {
      debugPrint('📦 package 정보 없음');
    }

    debugPrint('🛑 모든 실행 경로 실패 → 에러 다이얼로그 호출');
    _showErrorDialog('앱 실행 또는 설치에 실패했습니다.');
  } catch (e, stack) {
    debugPrint('🚨 예외 발생: $e');
    debugPrint('📌 Stacktrace: $stack');
    _showErrorDialog('intent URL 처리 중 오류: $e');
  }
}


  void _launchExternalApp(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }

    _showErrorDialog('앱 실행이 불가능하거나 미설치 상태입니다.');
  }

  void _showErrorDialog(String msg) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('오류'),
        content: Text(msg),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('확인'))],
      ),
    );
  }

  void log(String tag, dynamic data) {
    http.post(
      Uri.parse('$baseUrl/api/log'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'tag': tag,
        'data': data.toString(),
        'platform': defaultTargetPlatform.name,
        'timestamp': DateTime.now().toIso8601String(),
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('결제하기')),
      body: _controller == null
          ? const Center(child: CircularProgressIndicator())
          : WebViewWidget(controller: _controller!),
    );
  }
}
