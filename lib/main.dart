import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:iljujob/presentation/screens/purchase_screen.dart';
import 'presentation/screens/worker_screen/home_screen.dart';
import 'presentation/screens/client_screen/client_main_screen.dart';
import 'presentation/screens/onboarding_screen.dart';
import 'presentation/screens/signup_worker_screen/signup_worker_screen.dart';
import 'presentation/screens/signup_client_screen/signup_client_screen.dart';
import 'presentation/screens/PostJobScreen.dart';
import 'presentation/screens/post_job/edit_job_screen.dart';
import 'presentation/screens/worker_screen/home_my_page_screen.dart';
import 'presentation/screens/client_screen/client_my_page_screen.dart';
import 'presentation/screens/worker_screen/bookmarked_jobs_screen.dart';
import 'presentation/screens/mypagescreen/event_screen.dart';
import 'presentation/screens/mypagescreen/support_screen.dart';
import 'presentation/screens/mypagescreen/notice_screen.dart';
import 'presentation/screens/mypagescreen/inquiry_screen.dart';
import 'presentation/screens/mypagescreen/notification_screen.dart';
import 'presentation/screens/mypagescreen/faq_screen.dart';
import 'presentation/screens/mypagescreen/report_history_screen.dart';
import 'presentation/screens/client_screen/edit_client_profile_screen.dart';
import 'presentation/screens/worker_screen/edit_worker_profile_screen.dart';
import 'presentation/screens/worker_screen/applicant_list_screen.dart';
import 'presentation/screens/worker_screen/worker_profile_screen.dart';
import 'presentation/screens/client_screen/client_profile_screen.dart';
import 'package:iljujob/config/constants.dart';
import 'package:iljujob/presentation/chat/chat_room_screen.dart';
import 'package:iljujob/data/models/job.dart';
import 'package:iljujob/presentation/screens/worker_screen/job_detail_screen.dart';
import 'package:iljujob/presentation/screens/client_screen/business_info_screen.dart';
import 'package:iljujob/presentation/screens/review_screen.dart';
import 'package:iljujob/presentation/screens/TermsListScreen.dart';
import 'package:iljujob/presentation/admin/admin_main_screen.dart';
import 'package:iljujob/presentation/admin/admin_user_list_screen.dart';
import 'package:iljujob/presentation/admin/admin_grant_pass_screen.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:iljujob/presentation/admin/admin_safe_company_screen.dart';
import 'package:iljujob/presentation/admin/admin_report_screen.dart';
import 'package:iljujob/presentation/admin/admin_event_write_screen.dart';
import 'package:iljujob/data/services/job_service.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:iljujob/presentation/screens/mypagescreen/block_detail_screen.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:iljujob/presentation/screens/potrone_screen.dart';
import 'package:iljujob/data/services/dio_client.dart';
import 'package:upgrader/upgrader.dart';
import 'package:kakao_maps_flutter/kakao_maps_flutter.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:iljujob/presentation/screens/subscription_manage_screen.dart';
import 'package:iljujob/presentation/screens/signup_worker_screen/signup_choice_screen.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import 'package:iljujob/presentation/screens/client_screen/worker_map_screen.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:iljujob/presentation/screens/worker_calendar_screen.dart';
import 'package:iljujob/presentation/screens/signup_client_screen/client_welcome_screen.dart';
import 'package:iljujob/config/app_theme.dart';
import 'package:iljujob/presentation/screens/subscription_plans_screen.dart';
import 'package:iljujob/presentation/screens/client_screen/nearby_workers_screen.dart';

// ============================================================
// 전역 변수
// ============================================================
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ============================================================
// Firebase 백그라운드 메시지 핸들러
// ============================================================
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  if (Platform.isIOS) {
    await _showNotification(message);
  }
}

// ============================================================
// 초기화 함수들
// ============================================================

Future<void> _initFirebaseAndAnalytics() async {
  await Firebase.initializeApp();
  await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);
}

Future<void> _initializeLocalNotifications() async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosInit = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );
  const initSettings = InitializationSettings(
    android: androidInit,
    iOS: iosInit,
  );
  await flutterLocalNotificationsPlugin.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (response) async {
      await _handleLocalNotificationPayload(response.payload);
    },
  );

  final androidPlugin =
      flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

  await androidPlugin?.createNotificationChannel(
    const AndroidNotificationChannel(
      'chat',
      '채팅 알림',
      description: '채팅 메시지 알림',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
    ),
  );
  await androidPlugin?.createNotificationChannel(
    const AndroidNotificationChannel(
      'basic_channel',
      '기본 알림',
      description: '일반 알림을 위한 채널',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
    ),
  );
}

void _setupWebViewPlatform() {
  if (WebViewPlatform.instance is! WebKitWebViewPlatform &&
      defaultTargetPlatform == TargetPlatform.iOS) {
    WebViewPlatform.instance = WebKitWebViewPlatform();
  }
  if (WebViewPlatform.instance is! AndroidWebViewPlatform &&
      defaultTargetPlatform == TargetPlatform.android) {
    WebViewPlatform.instance = AndroidWebViewPlatform();
  }
}

// ============================================================
// 유저 정보 관리
// ============================================================

Future<void> _hydrateUserInfo() async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('authToken');
  if (token == null || token.isEmpty || JwtDecoder.isExpired(token)) return;

  final userId = prefs.getInt('userId');
  final userPhone = prefs.getString('userPhone');
  if (userId != null && userPhone != null) return;

  try {
    final resp = await http.get(
      Uri.parse('$baseUrl/api/user/me'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      if (data['id'] != null) await prefs.setInt('userId', data['id']);
      if (data['phone'] != null)
        await prefs.setString('userPhone', data['phone']);
      if (data['name'] != null) await prefs.setString('userName', data['name']);
      debugPrint('✅ 유저 정보 보정 완료: id=${data['id']} phone=${data['phone']}');
    }
  } catch (e) {
    debugPrint('❌ 유저 정보 보정 실패: $e');
  }
}

Future<bool> _refreshAccessToken(SharedPreferences prefs) async {
  final token = prefs.getString('authToken') ?? '';
  final refreshToken = prefs.getString('refreshToken');

  if (token.isEmpty || !JwtDecoder.isExpired(token)) return true;

  debugPrint('⛔️ accessToken 만료됨 → refresh-token 요청');

  if (refreshToken == null || refreshToken.isEmpty) {
    debugPrint('❌ refreshToken 없음');
    await prefs.clear();
    return false;
  }

  try {
    final dio = Dio();
    final response = await dio.post(
      '$baseUrl/api/auth/refresh-token',
      data: {'refreshToken': refreshToken},
      options: Options(headers: {'Authorization': null}),
    );
    final newAT = response.data['accessToken'] ?? response.data['token'];
    if (response.statusCode == 200 && newAT is String && newAT.isNotEmpty) {
      await prefs.setString('authToken', newAT);
      debugPrint('✅ 토큰 갱신 성공');
      return true;
    } else {
      await prefs.clear();
      return false;
    }
  } catch (e) {
    debugPrint('🔥 토큰 갱신 실패: $e');
    await prefs.clear();
    return false;
  }
}

// ============================================================
// FCM 토큰 관리
// ============================================================

/// 알림 허용 상태 → 토큰 서버에 저장
Future<void> sendFcmTokenUnified() async {
  if (kIsWeb) return;

  try {
    if (Platform.isIOS) {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        debugPrint('⚠️ iOS 알림 권한 없음');
        return;
      }
    }

    final fcm = await FirebaseMessaging.instance.getToken();
    if (fcm == null) {
      debugPrint('❌ FCM 토큰 null');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId');
    final userPhone = prefs.getString('userPhone');
    final userType = prefs.getString('userType') ?? 'worker';

    if (userId == null && userPhone == null) {
      debugPrint('⚠️ userId와 userPhone 모두 없음, FCM 전송 생략');
      return;
    }

    await http.post(
      Uri.parse('$baseUrl/api/user/update-token'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        if (userId != null) 'userId': userId,
        if (userPhone != null) 'userPhone': userPhone,
        'userType': userType,
        'fcmToken': fcm,
      }),
    );
  } catch (e) {
    debugPrint('❌ FCM 토큰 전송 실패: $e');
  }
}

/// 알림 거부 상태 → 서버 토큰 NULL 처리
Future<void> _clearFcmToken() async {
  if (kIsWeb) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId');
    final userPhone = prefs.getString('userPhone');
    final userType = prefs.getString('userType') ?? 'worker';

    if (userId == null && userPhone == null) return;

    await http.post(
      Uri.parse('$baseUrl/api/user/update-token'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        if (userId != null) 'userId': userId,
        if (userPhone != null) 'userPhone': userPhone,
        'userType': userType,
        'fcmToken': null, // ✅ null → 서버에서 토큰 삭제
      }),
    );
    debugPrint('✅ FCM 토큰 서버에서 삭제 완료');
  } catch (e) {
    debugPrint('❌ FCM 토큰 삭제 실패: $e');
  }
}

/// ✅ 알림 상태 동기화 (앱 시작 + 복귀 시 호출)
/// - 허용 → 토큰 갱신
/// - 거부 → 서버 토큰 삭제
Future<void> syncNotificationStatus() async {
  if (kIsWeb) return;
  try {
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      await sendFcmTokenUnified();
      debugPrint('✅ 알림 허용 — 토큰 갱신');
    } else {
      await _clearFcmToken();
      debugPrint('🔕 알림 거부 — 서버 토큰 삭제');
    }
  } catch (e) {
    debugPrint('❌ 알림 상태 동기화 실패: $e');
  }
}

Future<void> _sendFirstOpenIfNeeded() async {
  final prefs = await SharedPreferences.getInstance();
  final alreadySent = prefs.getBool('first_open_sent') ?? false;
  if (!alreadySent) {
    await FirebaseAnalytics.instance.logEvent(
      name: 'first_open_custom',
      parameters: {
        'platform': Platform.isIOS ? 'ios' : 'android',
        'app': 'iljujob',
      },
    );
    await prefs.setBool('first_open_sent', true);
  }
}

// ============================================================
// 알림 관련
// ============================================================

Future<void> _showNotification(RemoteMessage message) async {
  final notification = message.notification;
  if (notification == null) return;

  final isChat =
      message.data['chatRoomId'] != null ||
      message.data['type'] == 'chat' ||
      message.data['type'] == 'chat_message' ||
      message.data['type'] == 'direct_message';
  final channelId = isChat ? 'chat' : 'basic_channel';
  final channelName = isChat ? '채팅 알림' : '기본 알림';

  await flutterLocalNotificationsPlugin.show(
    notification.hashCode,
    notification.title,
    notification.body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: '$channelName 채널',
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    ),
    payload: jsonEncode(message.data),
  );
}

Future<void> _handleLocalNotificationPayload(String? payload) async {
  if (payload == null || payload.isEmpty) return;
  try {
    final decoded = jsonDecode(payload);
    if (decoded is! Map) return;
    final data = decoded.map((key, value) => MapEntry('$key', '$value'));
    await _handleNotificationData(data);
  } catch (e) {
    debugPrint('❌ 로컬 알림 payload 처리 실패: $e');
  }
}

Future<void> _handleNotificationData(Map<String, String> data) async {
  final type = data['type'];
  if (type == 'new_nearby_job' || type == 'custom_matched_job') {
    await _handleJobNotification(RemoteMessage(data: data));
  } else if (data['chatRoomId'] != null) {
    await _handleChatNotification(RemoteMessage(data: data));
  }
}

Future<void> _handleJobNotification(RemoteMessage message) async {
  final jobIdStr = message.data['jobId'];
  if (jobIdStr == null) return;
  final jobId = int.tryParse(jobIdStr);
  if (jobId == null) return;

  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('authToken') ?? '';
  final job = await JobService.fetchJobByIdWithToken(jobId, token);
  if (job == null) return;

  navigatorKey.currentState?.push(
    MaterialPageRoute(builder: (_) => JobDetailScreen(job: job)),
  );
}

Future<void> _handleChatNotification(RemoteMessage message) async {
  final data = message.data;
  final chatRoomId = int.tryParse(data['chatRoomId'] ?? '');

  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('authToken') ?? '';

  if (chatRoomId == null) {
    debugPrint('❌ chatRoomId 누락');
    return;
  }

  try {
    final resp = await http.get(
      Uri.parse('$baseUrl/api/chat/detail/$chatRoomId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (resp.statusCode == 200) {
      final body = jsonDecode(resp.body);
      navigatorKey.currentState?.pushNamed(
        '/chat-room',
        arguments: {
          'chatRoomId': chatRoomId,
          'jobInfo': body['jobInfo'] ?? body,
        },
      );
    } else if (resp.statusCode == 401 || resp.statusCode == 403) {
      debugPrint('❌ 권한 오류(${resp.statusCode})');
    } else {
      debugPrint('❌ jobInfo 조회 실패(${resp.statusCode})');
    }
  } catch (e) {
    debugPrint('❌ 알림 클릭 처리 중 예외: $e');
  }
}

Future<void> _handleInitialMessage(
  SharedPreferences prefs,
  String userType,
) async {
  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage == null) return;

  final navigator = navigatorKey.currentState;
  if (navigator == null) return;

  final type = initialMessage.data['type'];

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (type == 'new_nearby_job' || type == 'custom_matched_job') {
      final jobId = int.tryParse(initialMessage.data['jobId'] ?? '');
      if (jobId != null) {
        final token = prefs.getString('authToken') ?? '';
        final job = await JobService.fetchJobByIdWithToken(jobId, token);
        if (job != null) {
          navigator.push(
            MaterialPageRoute(builder: (_) => JobDetailScreen(job: job)),
          );
        }
      }
    } else if (initialMessage.data['chatRoomId'] != null) {
      final data = initialMessage.data;
      final chatRoomId = int.tryParse(data['chatRoomId'] ?? '');
      final jobId = int.tryParse(data['jobId'] ?? '');

      if (chatRoomId != null && jobId != null) {
        final jobInfo = <String, dynamic>{
          'id': jobId,
          'senderName': data['senderName'] ?? '',
          if (data['workerId'] != null)
            'worker_id': int.tryParse(data['workerId'] ?? '') ?? 0,
          if (data['clientId'] != null)
            'client_id': int.tryParse(data['clientId'] ?? '') ?? 0,
          if (data['senderType'] != null) 'senderType': data['senderType'],
        };

        final homeWithChatTab =
            userType == 'client'
                ? const ClientMainScreen(initialTabIndex: 3)
                : const HomeScreen(initialTabIndex: 3);

        navigator.push(MaterialPageRoute(builder: (_) => homeWithChatTab));
        navigator.push(
          MaterialPageRoute(
            builder:
                (_) => ChatRoomScreen(chatRoomId: chatRoomId, jobInfo: jobInfo),
          ),
        );
      }
    }
  });
}

// ============================================================
// 시작 화면 결정
// ============================================================
Widget _determineStartScreen({
  required bool hasSeenOnboarding,
  required String? userPhone,
  required int? userId,
  required String token,
  required String userType,
}) {
  if (!hasSeenOnboarding) return const OnboardingScreen();
  if (userPhone == null && userId == null) return const OnboardingScreen();
  if (token.isNotEmpty) {
    return userType == 'client' ? const ClientMainScreen() : const HomeScreen();
  }
  return const OnboardingScreen();
}

// ============================================================
// main 함수
// ============================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('🚀 [main.dart] Flutter 바인딩 초기화 완료');

  kakao.KakaoSdk.init(
    nativeAppKey: 'f1091d43764e475154945e49f2aec294',
    loggingEnabled: true,
  );
  initializeDio();
  await KakaoMapsFlutter.init('f1091d43764e475154945e49f2aec294');

  _setupWebViewPlatform();

  final upgrader = Upgrader(
    countryCode: 'KR',
    messages: UpgraderMessagesKo(),
    durationUntilAlertAgain: const Duration(days: 3),
  );

  await initializeDateFormatting('ko', null);
  await _initializeLocalNotifications();
  await _initFirebaseAndAnalytics();

  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  FirebaseMessaging.instance.onTokenRefresh.listen((_) async {
    await _sendFirstOpenIfNeeded();
    await sendFcmTokenUnified();
  });

  final prefs = await SharedPreferences.getInstance();
  await Future.delayed(const Duration(milliseconds: 300));

  await _refreshAccessToken(prefs);
  await _hydrateUserInfo();

  final hasSeenOnboarding = prefs.getBool('hasSeenOnboarding') ?? false;
  final refreshedToken = prefs.getString('authToken') ?? '';
  final refreshedUserType = prefs.getString('userType') ?? 'worker';
  final refreshedUserPhone = prefs.getString('userPhone');
  final refreshedUserId = prefs.getInt('userId');

  // ✅ 앱 시작 시 알림 상태 동기화
  await syncNotificationStatus();

  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    _showNotification(message);
  });

  FirebaseMessaging.onMessageOpenedApp.listen((message) async {
    await _handleNotificationData(
      message.data.map((key, value) => MapEntry(key, value.toString())),
    );
  });

  final startScreen = _determineStartScreen(
    hasSeenOnboarding: hasSeenOnboarding,
    userPhone: refreshedUserPhone,
    userId: refreshedUserId,
    token: refreshedToken,
    userType: refreshedUserType,
  );

  runApp(MyApp(startScreen: startScreen, upgrader: upgrader));

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await _maybeShowUpgradeDialog(upgrader);
  });

  await _handleInitialMessage(prefs, refreshedUserType);
}

// ============================================================
// MyApp 위젯 — ✅ StatefulWidget으로 변경 (생명주기 감지)
// ============================================================
class MyApp extends StatefulWidget {
  final Widget startScreen;
  final Upgrader upgrader;

  const MyApp({super.key, required this.startScreen, required this.upgrader});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 앱 첫 실행(콜드 스타트) 시 접속 점수 기록
    WidgetsBinding.instance.addPostFrameCallback((_) => _recordAppOpen());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ✅ 앱 복귀할 때마다 알림 상태 동기화
  // 알림 켜면 토큰 갱신, 끄면 서버 토큰 삭제
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      syncNotificationStatus();
      _recordAppOpen();
    }
  }

  Future<void> _recordAppOpen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken') ?? '';
      final userType = prefs.getString('userType') ?? '';
      if (token.isEmpty || userType != 'worker') return;
      await http.post(
        Uri.parse('$baseUrl/api/worker/app-open'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: '알바일주',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ko', 'KR'),
      supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.theme,
      navigatorObservers: [
        FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance),
      ],
      home: widget.startScreen,
      routes: {
        '/admin': (context) => const AdminMainScreen(),
        '/admin_users': (context) => const AdminUserListScreen(),
        '/admin_grant_pass': (context) => const AdminGrantPassScreen(),
        '/admin_safe_company': (context) => const AdminSafeCompanyScreen(),
        '/admin_report': (context) => const AdminReportScreen(),
        '/admin_event_write': (context) => const EventWriteScreen(),
        '/onboarding': (context) => const OnboardingScreen(),
        '/home': (context) => const HomeScreen(),
        '/signup_worker': (context) => const SignupWorkerScreen(),
        '/signup_client': (context) => const SignupClientScreen(),
        '/post_job': (context) => const PostJobScreen(),
        '/client_main': (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          int initialTabIndex = 1;
          if (args is Map && args['initialTabIndex'] is int) {
            initialTabIndex = args['initialTabIndex'];
          }
          return ClientMainScreen(initialTabIndex: initialTabIndex);
        },
        '/edit_job': (context) => const EditJobScreen(),
        '/mypage': (context) => const WorkerMyPageScreen(),
        '/client-mypage': (context) => const ClientMyPageScreen(),
        '/bookmarked-jobs': (context) => const BookmarkedJobsScreen(),
        '/notices': (context) => const NoticeListScreen(),
        '/events': (context) => const EventScreen(),
        '/support': (context) => const SupportScreen(),
        '/inquiry': (context) => const InquiryScreen(),
        '/faq': (context) => const FaqScreen(),
        '/report-history': (context) => const ReportHistoryScreen(),
        '/applicants': (context) => const ApplicantListScreen(),
        '/client_business_info': (context) => const ClientBusinessInfoScreen(),
        '/review': (context) => ReviewScreenRouter(),
        '/purchase-pass': (context) => const PurchasePassScreen(),
        '/blocked-users': (context) => const BlockedUserListScreen(),
        '/worker_map': (context) => const WorkerMapScreen(),
        '/client_welcome': (context) => const ClientWelcomeScreen(),
        '/portone-payment': (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          if (args == null || args is! Map<String, dynamic>) {
            return const Scaffold(body: Center(child: Text('잘못된 접근입니다.')));
          }
          return PortonePaymentScreen(
            count: args['count'],
            companyName: args['companyName'],
            companyPhone: args['companyPhone'],
          );
        },
        '/subscribe': (_) => const SubscriptionPlansScreen(),
        '/nearby-workers': (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          if (args == null || args is! Map<String, dynamic>) {
            return const Scaffold(body: Center(child: Text('잘못된 접근입니다.')));
          }
          int toInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
          return NearbyWorkersScreen(
            jobId: toInt(args['jobId']),
            clientId: toInt(args['clientId']),
            jobTitle: args['jobTitle']?.toString() ?? '',
          );
        },
        '/subscription/manage': (_) => const SubscriptionManageScreen(),
        '/job-detail': (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          if (args == null || args is! Job) {
            return const Scaffold(body: Center(child: Text('잘못된 접근입니다.')));
          }
          return JobDetailScreen(job: args);
        },
        '/worker-profile': (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          if (args == null || args is! int) {
            return const Scaffold(body: Center(child: Text('잘못된 접근입니다.')));
          }
          return WorkerProfileScreen(workerId: args);
        },
        '/client-profile': (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          if (args == null || args is! int) {
            return const Scaffold(body: Center(child: Text('잘못된 접근입니다.')));
          }
          return ClientProfileScreen(clientId: args);
        },
        '/signup-choice': (context) => const SignupChoiceScreen(),
        '/edit_profile': (context) => const EditClientProfileScreen(),
        '/edit_profile_worker': (_) => const EditWorkerProfileScreen(),
        '/notifications': (context) => const NotificationSettingsScreen(),
        '/terms-list': (context) => const TermsListScreen(),
        '/worker-calendar': (_) => const WorkerCalendarScreen(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/chat-room') {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder:
                (context) => ChatRoomScreen(
                  chatRoomId: args['chatRoomId'],
                  jobInfo: args['jobInfo'],
                ),
          );
        }
        return MaterialPageRoute(
          builder:
              (_) =>
                  const Scaffold(body: Center(child: Text('페이지를 찾을 수 없습니다'))),
        );
      },
    );
  }
}

// ============================================================
// 한국어 업데이트 메시지
// ============================================================
class UpgraderMessagesKo extends UpgraderMessages {
  @override
  String get title => '업데이트 안내';
  @override
  String get body => '새 버전이 공개되었습니다. 지금 업데이트하시겠어요?';
  @override
  String get prompt => '스토어로 이동';
  @override
  String get buttonTitleIgnore => '나중에';
  @override
  String get buttonTitleLater => '다음에';
  @override
  String get releaseNotes => '변경사항';
}

bool _upgradeDialogShown = false;

Future<void> _maybeShowUpgradeDialog(Upgrader upgrader) async {
  if (_upgradeDialogShown) return;
  _upgradeDialogShown = true;

  try {
    await upgrader.initialize();
    final shouldDisplay = upgrader.shouldDisplayUpgrade();
    if (!shouldDisplay) return;

    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;

    const force = false;

    await showDialog(
      context: ctx,
      barrierDismissible: !force,
      builder: (_) => _AlbailjuUpgradeDialog(upgrader: upgrader, force: force),
    );
  } catch (e) {
    debugPrint('❌ 업그레이드 모달 체크 실패: $e');
  }
}

class _AlbailjuUpgradeDialog extends StatelessWidget {
  final Upgrader upgrader;
  final bool force;
  const _AlbailjuUpgradeDialog({required this.upgrader, required this.force});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFF3B8AFF).withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.system_update_alt,
                color: Color(0xFF3B8AFF),
                size: 26,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '업데이트가 있어요',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              force
                  ? '안정적인 이용을 위해 최신 버전으로 업데이트가 필요합니다.'
                  : '더 빠르고 편해진 알바일주를 써보세요.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                color: Color(0xFF4B5563),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            _ReleaseNotesBox(text: upgrader.releaseNotes),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: force ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    child: Text(
                      force ? '필수 업데이트' : '나중에',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      await upgrader.sendUserToAppStore();
                      if (!force && context.mounted) Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B8AFF),
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      '업데이트하기',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (!force)
              const Text(
                '업데이트는 스토어에서 진행됩니다.',
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFF9CA3AF),
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReleaseNotesBox extends StatelessWidget {
  final String? text;
  const _ReleaseNotesBox({this.text});

  @override
  Widget build(BuildContext context) {
    final t = (text ?? '').trim();
    if (t.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Text(
        t,
        style: const TextStyle(
          fontSize: 12,
          height: 1.35,
          color: Color(0xFF374151),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
