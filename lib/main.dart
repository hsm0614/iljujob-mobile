import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:iljujob/presentation/splash/splash_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:iljujob/presentation/screens/purchase_screen.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/client_home_screen.dart';
import 'presentation/screens/home_main_screen.dart';
import 'presentation/screens/client_main_screen.dart';
import 'presentation/screens/onboarding_screen.dart';
import 'presentation/screens/login_screen.dart';
import 'presentation/screens/signup_worker_screen.dart';
import 'presentation/screens/signup_client_screen.dart';
import 'presentation/screens/PostJobScreen.dart';
import 'presentation/screens/post_job/edit_job_screen.dart';
import 'presentation/screens/post_job/post_job_form.dart';
import 'presentation/screens/home_my_page_screen.dart';
import 'presentation/screens/client_my_page_screen.dart';
import 'presentation/screens/bookmarked_jobs_screen.dart';
import 'presentation/screens/mypagescreen/event_screen.dart';
import 'presentation/screens/mypagescreen/support_screen.dart';
import 'presentation/screens/mypagescreen/notice_screen.dart';
import 'presentation/screens/mypagescreen/inquiry_screen.dart';
import 'presentation/screens/mypagescreen/notification_screen.dart';
import 'presentation/screens/mypagescreen/faq_screen.dart';
import 'presentation/screens/mypagescreen/report_history_screen.dart';
import 'presentation/screens/edit_client_profile_screen.dart';
import 'presentation/screens/edit_worker_profile_screen.dart';
import 'presentation/screens/applicant_list_screen.dart';
import 'presentation/screens/worker_profile_screen.dart';
import 'presentation/screens/client_profile_screen.dart';
import 'package:iljujob/config/constants.dart';
import 'package:iljujob/presentation/chat/chat_list_screen.dart';
import 'package:iljujob/presentation/chat/chat_room_screen.dart';
import 'package:iljujob/data/models/job.dart';
import 'package:iljujob/presentation/screens/job_detail_screen.dart';
import 'package:iljujob/presentation/screens/business_info_screen.dart';
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
import 'package:iljujob/presentation/screens/pass_payment_webview.dart';
import 'package:iljujob/presentation/screens/potrone_screen.dart';
import 'package:iljujob/data/services/dio_client.dart';
import 'package:iljujob/data/services/auth_interceptor.dart';
import 'package:upgrader/upgrader.dart';
import 'package:kakao_maps_flutter/kakao_maps_flutter.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:iljujob/presentation/screens/subscription_payment_webview.dart';
import 'package:iljujob/presentation/screens/subscription_manage_screen.dart';
import 'package:iljujob/presentation/screens/signup_choice_screen.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import 'package:iljujob/presentation/screens/worker_map_screen.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:iljujob/presentation/screens/worker_calendar_screen.dart';
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

/// Firebase 및 Analytics 초기화
Future<void> _initFirebaseAndAnalytics() async {
  await Firebase.initializeApp();
  await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);
}

/// 로컬 알림 초기화
Future<void> _initializeLocalNotifications() async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosInit = DarwinInitializationSettings();
  const initSettings = InitializationSettings(android: androidInit, iOS: iosInit);
  await flutterLocalNotificationsPlugin.initialize(initSettings);
}

/// WebView 플랫폼 설정
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

/// 서버에서 유저 정보를 가져와 로컬 보정
Future<void> _hydrateUserInfo() async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('authToken');

  if (token == null || token.isEmpty || JwtDecoder.isExpired(token)) {
    return;
  }

  final userId = prefs.getInt('userId');
  final userPhone = prefs.getString('userPhone');

  // 이미 둘 다 있으면 생략
  if (userId != null && userPhone != null) return;

  try {
    final resp = await http.get(
      Uri.parse('$baseUrl/api/user/me'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      if (data['id'] != null) await prefs.setInt('userId', data['id']);
      if (data['phone'] != null) await prefs.setString('userPhone', data['phone']);
      if (data['name'] != null) await prefs.setString('userName', data['name']);
      debugPrint('✅ 유저 정보 보정 완료: id=${data['id']} phone=${data['phone']}');
    }
  } catch (e) {
    debugPrint('❌ 유저 정보 보정 실패: $e');
  }
}

/// Access Token 갱신
Future<bool> _refreshAccessToken(SharedPreferences prefs) async {
  final token = prefs.getString('authToken') ?? '';
  final refreshToken = prefs.getString('refreshToken');

  // 아직 만료 안 됐으면 패스
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
      // ✅ 만료된 AT를 Authorization으로 보내지 말 것
      options: Options(headers: {'Authorization': null}),
    );

    // ✅ 서버는 accessToken(표준) + token(하위호환) 둘 다 내려주게 했음
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

/// FCM 토큰을 서버에 전송 (userId 우선, userPhone 백업)
Future<void> sendFcmTokenUnified() async {
  if (kIsWeb) return;

  try {
    // iOS 권한 재확인
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

    final resp = await http.post(
      Uri.parse('$baseUrl/api/user/update-token'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        if (userId != null) 'userId': userId,
        if (userPhone != null) 'userPhone': userPhone,
        'userType': userType,
        'fcmToken': fcm,
      }),
    );

    debugPrint('✅ FCM 토큰 전송: ${resp.statusCode} ${resp.body}');
  } catch (e) {
    debugPrint('❌ FCM 토큰 전송 실패: $e');
  }
}

/// 앱 최초 실행 시 first_open 이벤트 전송
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

/// 로컬 알림 표시 (iOS용)
Future<void> _showNotification(RemoteMessage message) async {
  final notification = message.notification;
  if (notification == null) return;

  const androidDetails = AndroidNotificationDetails(
    'basic_channel',
    '기본 채널',
    channelDescription: '일반 알림을 위한 채널',
    importance: Importance.max,
    priority: Priority.high,
  );
  const platformDetails = NotificationDetails(android: androidDetails);

  await flutterLocalNotificationsPlugin.show(
    notification.hashCode,
    notification.title,
    notification.body,
    platformDetails,
  );
}

/// Job 알림 처리
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

/// 채팅 알림 클릭 처리
Future<void> _handleChatNotification(RemoteMessage message) async {
  final data = message.data;
  final chatRoomId = int.tryParse(data['chatRoomId'] ?? '');
  final jobId = int.tryParse(data['jobId'] ?? '');

  final prefs = await SharedPreferences.getInstance();
  final userType = prefs.getString('userType');
  final userId = prefs.getInt('userId');
  final token = prefs.getString('authToken') ?? '';

  if (chatRoomId == null || jobId == null || userId == null || userType == null) {
    debugPrint('❌ 필수 정보 누락');
    return;
  }

  final isWorker = userType == 'worker';
  final paramName = isWorker ? 'workerId' : 'clientId';
  final url = Uri.parse('$baseUrl/api/chat/get-room-by-id?jobId=$jobId&$paramName=$userId');

  try {
    final resp = await http.get(url, headers: {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    });

    if (resp.statusCode == 200) {
      final body = jsonDecode(resp.body);
      final jobInfo = body['jobInfo'];

      navigatorKey.currentState?.pushNamed(
        '/chat-room',
        arguments: {'chatRoomId': chatRoomId, 'jobInfo': jobInfo},
      );
    } else if (resp.statusCode == 401 || resp.statusCode == 403) {
      debugPrint('❌ 권한 오류(${resp.statusCode})');
      // 백업: jobInfo만 조회해서라도 이동
      final jobResp = await http.get(
        Uri.parse('$baseUrl/api/job/$jobId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (jobResp.statusCode == 200) {
        final jobInfo = jsonDecode(jobResp.body);
        navigatorKey.currentState?.pushNamed(
          '/chat-room',
          arguments: {'chatRoomId': chatRoomId, 'jobInfo': jobInfo},
        );
      }
    } else {
      debugPrint('❌ jobInfo 조회 실패(${resp.statusCode})');
    }
  } catch (e) {
    debugPrint('❌ 알림 클릭 처리 중 예외: $e');
  }
}

/// 앱 시작 시 initialMessage 처리
Future<void> _handleInitialMessage(SharedPreferences prefs, String userType) async {
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
          navigator.push(MaterialPageRoute(builder: (_) => JobDetailScreen(job: job)));
        }
      }
    } else if (initialMessage.data['chatRoomId'] != null) {
      final chatRoomId = int.tryParse(initialMessage.data['chatRoomId'] ?? '');
      final jobId = int.tryParse(initialMessage.data['jobId'] ?? '');
      final senderName = initialMessage.data['senderName'];

      if (chatRoomId != null && jobId != null) {
        final jobInfo = {'id': jobId, 'senderName': senderName};
        final homeWithChatTab = userType == 'client'
            ? const ClientMainScreen(initialTabIndex: 3)
            : const HomeScreen(initialTabIndex: 3);

        navigator.push(MaterialPageRoute(builder: (_) => homeWithChatTab));
        navigator.push(MaterialPageRoute(
          builder: (_) => ChatRoomScreen(chatRoomId: chatRoomId, jobInfo: jobInfo),
        ));
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
  if (!hasSeenOnboarding) {
    return const OnboardingScreen();
  }
  if (userPhone == null && userId == null) {
    return const OnboardingScreen();
  }
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

  // 1. 기본 SDK 초기화
  kakao.KakaoSdk.init(
    nativeAppKey: 'f1091d43764e475154945e49f2aec294',
    loggingEnabled: true,
  );
  initializeDio();
  await KakaoMapsFlutter.init('f1091d43764e475154945e49f2aec294');

  // 2. WebView 설정
  _setupWebViewPlatform();

  // 3. Upgrader 설정
  final upgrader = Upgrader(
    countryCode: 'KR',
    messages: UpgraderMessagesKo(),
    durationUntilAlertAgain: const Duration(days: 3),
  );

  // 4. 날짜, 알림, Firebase 초기화
  await initializeDateFormatting('ko', null);
  await _initializeLocalNotifications();
  await _initFirebaseAndAnalytics();

  // 5. Firebase Messaging 권한 요청
  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  // 6. 백그라운드 메시지 핸들러 등록
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // 7. FCM 토큰 갱신 리스너
  FirebaseMessaging.instance.onTokenRefresh.listen((_) async {
    await _sendFirstOpenIfNeeded();
    await sendFcmTokenUnified();
  });

  // 8. SharedPreferences 로드
  final prefs = await SharedPreferences.getInstance();
  await Future.delayed(const Duration(milliseconds: 300));

  final userType = prefs.getString('userType') ?? 'worker';
  final userPhone = prefs.getString('userPhone');
  final userId = prefs.getInt('userId');
  final token = prefs.getString('authToken') ?? '';


  // 9. 토큰 갱신
  await _refreshAccessToken(prefs);

  // 10. 유저 정보 보정
  await _hydrateUserInfo();
final hasSeenOnboarding   = prefs.getBool('hasSeenOnboarding') ?? false;
final refreshedToken      = prefs.getString('authToken') ?? '';
final refreshedUserType   = prefs.getString('userType') ?? 'worker';
final refreshedUserPhone  = prefs.getString('userPhone');
final refreshedUserId     = prefs.getInt('userId');
  // 11. FCM 토큰 등록
  final fcmSettings = await FirebaseMessaging.instance.getNotificationSettings();
  if (fcmSettings.authorizationStatus == AuthorizationStatus.authorized) {
    await sendFcmTokenUnified();
  }

  // 12. 포그라운드 알림 수신
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    if (Platform.isIOS) {
      final notification = message.notification;
      if (notification != null) {
        flutterLocalNotificationsPlugin.show(
          0,
          notification.title,
          notification.body,
          const NotificationDetails(iOS: DarwinNotificationDetails()),
        );
      }
    }
  });

  // 13. 백그라운드 알림 클릭 처리
  FirebaseMessaging.onMessageOpenedApp.listen((message) async {
    final type = message.data['type'];
    if (type == 'new_nearby_job' || type == 'custom_matched_job') {
      await _handleJobNotification(message);
    } else if (message.data['chatRoomId'] != null) {
      await _handleChatNotification(message);
    }
  });

  // 14. 시작 화면 결정
final startScreen = _determineStartScreen(
  hasSeenOnboarding: hasSeenOnboarding,
  userPhone: refreshedUserPhone,
  userId: refreshedUserId,
  token: refreshedToken,
  userType: refreshedUserType,
);

  // 15. 앱 실행
  runApp(MyApp(startScreen: startScreen, upgrader: upgrader));
// ✅ 커스텀 업데이트 모달 (우리 UI)
WidgetsBinding.instance.addPostFrameCallback((_) async {
  await _maybeShowUpgradeDialog(upgrader);
});
  // 16. 앱 시작 시 initialMessage 처리
await _handleInitialMessage(prefs, refreshedUserType); // ✅
}

// ============================================================
// MyApp 위젯
// ============================================================
class MyApp extends StatelessWidget {
  final Widget startScreen;
  final Upgrader upgrader;

  const MyApp({super.key, required this.startScreen, required this.upgrader});

  @override
  Widget build(BuildContext context) {
    
    return MaterialApp(
      
      navigatorKey: navigatorKey,
      title: '알바일주',
      debugShowCheckedModeBanner: false,
       locale: const Locale('ko', 'KR'),
    supportedLocales: const [
      Locale('ko', 'KR'),
      Locale('en', 'US'),
    ],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],

      theme: ThemeData(
        useMaterial3: true, // ✅ 이게 핵심 (안드로이드 촌스러움 크게 줄어듦)
        fontFamily: 'Jalnan2TTF',
        textTheme: ThemeData.light().textTheme,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
        navigatorObservers: [
        FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance),
      ],
    home: startScreen,
      routes: {
        '/admin': (context) => const AdminMainScreen(),
        '/admin_users': (context) => const AdminUserListScreen(),
        '/admin_grant_pass': (context) => const AdminGrantPassScreen(),
        '/admin_safe_company': (context) => const AdminSafeCompanyScreen(),
        '/admin_report': (context) => const AdminReportScreen(),
        '/admin_event_write': (context) => const EventWriteScreen(),
        '/onboarding': (context) => const OnboardingScreen(),
        '/home': (context) => const HomeScreen(),
        '/login': (context) => const LoginScreen(),
        '/signup_worker': (context) => const SignupWorkerScreen(),
        '/signup_client': (context) => const SignupClientScreen(),
        '/post_job': (context) => const PostJobScreen(),
       '/client_main': (context) {
  final args = ModalRoute.of(context)?.settings.arguments;
  int initialTabIndex = 1; // 기본값

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
        '/portone-payment': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return PortonePaymentScreen(
            count: args['count'],
            companyName: args['companyName'],
            companyPhone: args['companyPhone'],
          );
        },
        '/subscribe': (_) => const SubscribeScreen(),
        '/subscription/manage': (_) => const SubscriptionManageScreen(),
        '/job-detail': (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          if (args == null || args is! Job) {
            return const Scaffold(body: Center(child: Text('잘못된 접근입니다.')));
          }
          return JobDetailScreen(job: args);
        },
        
        '/worker-profile': (context) {
          final int workerId = ModalRoute.of(context)!.settings.arguments as int;
          return WorkerProfileScreen(workerId: workerId);
        },
        '/client-profile': (context) {
          final int clientId = ModalRoute.of(context)!.settings.arguments as int;
          return ClientProfileScreen(clientId: clientId);
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
            builder: (context) => ChatRoomScreen(
              chatRoomId: args['chatRoomId'],
              jobInfo: args['jobInfo'],
            ),
          );
        }
        return MaterialPageRoute(
          builder: (_) => const Scaffold(
            body: Center(child: Text('페이지를 찾을 수 없습니다')),
          ),
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
  String get ignore => '나중에';
  @override
  String get later => '다음에';
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

  const _AlbailjuUpgradeDialog({
    required this.upgrader,
    required this.force,
  });

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
            // 헤더
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFF3B8AFF).withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.system_update_alt, color: Color(0xFF3B8AFF), size: 26),
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

            // 릴리즈 노트 (있으면)
            _ReleaseNotesBox(text: upgrader.releaseNotes),

            const SizedBox(height: 14),

            // 버튼
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: force ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                      // ✅ 스토어로 이동
                      await upgrader.sendUserToAppStore();
                      // 강제가 아니면 닫기
                      if (!force && context.mounted) Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B8AFF),
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: const Text(
                      '업데이트하기',
                      style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // 작은 안내
            if (!force)
              const Text(
                '업데이트는 스토어에서 진행됩니다.',
                style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF), fontWeight: FontWeight.w700),
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
        style: const TextStyle(fontSize: 12, height: 1.35, color: Color(0xFF374151), fontWeight: FontWeight.w700),
      ),
    );
  }
}