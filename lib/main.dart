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
import 'package:iljujob/data/models/job.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:iljujob/presentation/screens/mypagescreen/block_detail_screen.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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


final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
void checkTokenExpiration(String token) {
  if (JwtDecoder.isExpired(token)) {
    print("❌ 토큰 만료됨");
  } else {
    // 토큰 유효함
  }
}
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  if (Platform.isIOS) {
    await _showNotification(message); // iOS만 수동 띄움
  }
}
Future<void> initFirebaseAndAnalytics() async {
  await Firebase.initializeApp();
  // Analytics 수집 활성화
  await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);
}

/// 앱 최초 실행 시 1회만 전송하는 커스텀 first_open 이벤트 + 디버그용 연습 이벤트
Future<void> sendFirstOpenIfNeeded() async {
  final prefs = await SharedPreferences.getInstance();
  final alreadySent = prefs.getBool('first_open_sent') ?? false;

  if (!alreadySent) {
    await FirebaseAnalytics.instance.logEvent(
      name: 'first_open_custom',              // ← GA4 전환으로 켤 이벤트 이름
      parameters: {
        'platform': Platform.isIOS ? 'ios' : 'android',
        'app': 'iljujob',
      },
    );
    await prefs.setBool('first_open_sent', true);
  }
}
Future<void> sendFcmTokenToServer(String userPhone, String userType) async {
   if (kIsWeb) {
    print('⚠️ Web 플랫폼에서는 FCM 토큰 전송을 생략합니다.');
    return;
  }
  try {
    final token = await FirebaseMessaging.instance.getToken();


    if (token == null) {
      print('❌ FCM 토큰이 null입니다. 전송 중단');
      return;
    }

    final response = await http.post(
      Uri.parse('$baseUrl/api/user/update-token'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'userPhone': userPhone,
        'userType': userType,
        'fcmToken': token,
      }),
    );
  } catch (e) {
    print('❌ FCM 토큰 전송 실패: $e');
    // ⚠️ 실패해도 앱 흐름이 중단되지 않도록
  }
}

Future<void> initializeLocalNotifications() async {
  const AndroidInitializationSettings androidInit =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const DarwinInitializationSettings iosInit = DarwinInitializationSettings();
  const InitializationSettings initSettings = InitializationSettings(
    android: androidInit,
    iOS: iosInit,
  );
  await flutterLocalNotificationsPlugin.initialize(initSettings);
}

Future<void> _showNotification(RemoteMessage message) async {
  RemoteNotification? notification = message.notification;
  if (notification != null) {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'basic_channel',
          '기본 채널',
          channelDescription: '일반 알림을 위한 채널',
          importance: Importance.max,
          priority: Priority.high,
        );
    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
    );
    await flutterLocalNotificationsPlugin.show(
      notification.hashCode,
      notification.title,
      notification.body,
      platformDetails,
    );
  }
}
void _handleJobNotification(RemoteMessage message) async {
  final jobIdStr = message.data['jobId'];
  if (jobIdStr == null) return;

  final jobId = int.tryParse(jobIdStr);
  if (jobId == null) return;

  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('authToken') ?? '';

  final job = await JobService.fetchJobByIdWithToken(jobId, token);
  if (job == null) return;

  navigatorKey.currentState?.pushNamed(
    '/job-detail',
    arguments: job, // ✅ 이제 Job 객체로 넘긴다
  );
}
void checkInitialMessage() async {
  RemoteMessage? initialMessage =
      await FirebaseMessaging.instance.getInitialMessage();


  if (initialMessage != null && initialMessage.data['chatRoomId'] != null) {
    navigatorKey.currentState?.pushNamed(
      '/chat-room',
      arguments: {
        'chatRoomId': int.parse(initialMessage.data['chatRoomId']),
        'jobInfo': {
          'id': int.parse(initialMessage.data['jobId']),
          'senderName': initialMessage.data['senderName'],

        },
      },
    );
  }
}



void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('🚀 [main.dart] Flutter 바인딩 초기화 완료');
  initializeDio();
   await KakaoMapsFlutter.init('f1091d43764e475154945e49f2aec294'); // 네이티브 앱 키
  const platform = MethodChannel('deeplink/albailju');

final upgrader = Upgrader(
  countryCode: 'KR',

  messages: UpgraderMessagesKo(),
  durationUntilAlertAgain: const Duration(days: 3),
  
);


  // ✅ WebView 설정
  if (WebViewPlatform.instance is! WebKitWebViewPlatform &&
      defaultTargetPlatform == TargetPlatform.iOS) {
    WebViewPlatform.instance = WebKitWebViewPlatform();
  }

  if (WebViewPlatform.instance is! AndroidWebViewPlatform &&
      defaultTargetPlatform == TargetPlatform.android) {
    WebViewPlatform.instance = AndroidWebViewPlatform();
  }

  print('🔥 main 시작');
  await initializeDateFormatting('ko', null);
  await initializeLocalNotifications();
  await initFirebaseAndAnalytics();
  await FirebaseMessaging.instance.requestPermission();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
  await sendFirstOpenIfNeeded();   
  final prefs = await SharedPreferences.getInstance();
  final userPhone = prefs.getString('userPhone');
  final userType = prefs.getString('userType');

  if (userPhone != null && userType != null) {
    await sendFcmTokenToServer(userPhone, userType);
   
  }
});

  final prefs = await SharedPreferences.getInstance();
  await Future.delayed(const Duration(milliseconds: 300));

  final userType = prefs.getString('userType') ?? 'worker';
  final userPhone = prefs.getString('userPhone');
  final token = prefs.getString('authToken') ?? '';
  final refreshToken = prefs.getString('refreshToken');

  // ✅ 토큰 갱신
  if (token.isNotEmpty && JwtDecoder.isExpired(token)) {
    print('⛔️ accessToken 만료됨 → refresh-token 요청');
    if (refreshToken == null) {


    }
    try {
      final dio = Dio();
      final response = await dio.post(
        '$baseUrl/api/auth/refresh-token',
        data: {'refreshToken': refreshToken},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode == 200 && response.data['token'] != null) {
        await prefs.setString('authToken', response.data['token']);
        print('✅ 토큰 갱신 성공');
      } else {
        await prefs.clear();
      }
    } catch (e) {
      print('🔥 네트워크 오류: $e');
      await prefs.clear();
    }
  }

  final hasSeenOnboarding = prefs.getBool('hasSeenOnboarding') ?? false;

  // ✅ FCM 토큰 등록
  final fcmSettings = await FirebaseMessaging.instance.getNotificationSettings();
  if (fcmSettings.authorizationStatus == AuthorizationStatus.authorized &&
      userPhone != null) {
    await sendFcmTokenToServer(userPhone, userType);
  }

  // ✅ 알림 수신 (포그라운드)
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    if (Theme.of(navigatorKey.currentContext!).platform == TargetPlatform.iOS) {
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

  // ✅ 알림 클릭 처리 (백그라운드)
  FirebaseMessaging.onMessageOpenedApp.listen((message) async {
    final type = message.data['type'];

    if (type == 'new_nearby_job' || type == 'custom_matched_job') {
      _handleJobNotification(message);
    } else if (message.data['chatRoomId'] != null) {
      await _handleNotificationClick(message);
    }
  });

  // ✅ 알림 클릭으로 앱 시작된 경우
  final RemoteMessage? initialMessage =
      await FirebaseMessaging.instance.getInitialMessage();

  /// ✅ 초기 화면은 무조건 홈 또는 온보딩/로그인
  Widget startScreen;
  if (!hasSeenOnboarding) {
    startScreen = const OnboardingScreen();
  } else if (userPhone == null) {
    startScreen = const LoginScreen();
  } else {
    startScreen = userType == 'client'
        ? const ClientMainScreen()
        : const HomeScreen();
  }


// 테스트 중엔 이전 ‘표시함’ 기록을 지워서 항상 뜨게


runApp(MyApp(startScreen: startScreen, upgrader: upgrader));

  // ✅ runApp 이후 채팅 알림이면 ChatRoom push
    if (initialMessage != null) {
    final navigator = navigatorKey.currentState;
    final type = initialMessage.data['type'];



    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (navigator == null) return;

      if (type == 'new_nearby_job' || type == 'custom_matched_job') {
        final jobId = int.tryParse(initialMessage.data['jobId'] ?? '');
        if (jobId != null) {
          final token = prefs.getString('authToken') ?? '';
          final job = await JobService.fetchJobByIdWithToken(jobId, token);

          
          if (job != null) {
            navigator.push(MaterialPageRoute(
              builder: (_) => JobDetailScreen(job: job),
            ));
          }
        }
      } else if (initialMessage.data['chatRoomId'] != null) {
        final chatRoomId = int.tryParse(initialMessage.data['chatRoomId'] ?? '');
        final jobId = int.tryParse(initialMessage.data['jobId'] ?? '');
        final senderName = initialMessage.data['senderName'];

        if (chatRoomId != null && jobId != null) {
          final jobInfo = {'id': jobId, 'senderName': senderName};
          
          // ✅ 홈 화면에 채팅탭으로 먼저 이동
          final Widget homeWithChatTab = userType == 'client'
              ? const ClientMainScreen(initialTabIndex: 3) // ← 채팅 탭 index
              : const HomeScreen(initialTabIndex: 3);

          navigator.push(MaterialPageRoute(builder: (_) => homeWithChatTab));

          // ✅ 그 다음 채팅방 push
          navigator.push(MaterialPageRoute(
            builder: (_) => ChatRoomScreen(
              chatRoomId: chatRoomId,
              jobInfo: jobInfo,
            ),
          ));
        }
      }
    });
    };
  }

/// ✅ 알림 클릭 처리 함수 (앱이 열려 있을 때 클릭 시)
Future<void> _handleNotificationClick(RemoteMessage message) async {
  final data = message.data;
  final roomIdStr = data['chatRoomId'];
  final jobIdStr  = data['jobId'];

  final chatRoomId = int.tryParse(roomIdStr ?? '');
  final jobId      = int.tryParse(jobIdStr ?? '');

  final prefs = await SharedPreferences.getInstance();
  final userType = prefs.getString('userType');
  final userId   = prefs.getInt('userId');           // 로그인한 나의 id
  final token    = prefs.getString('authToken') ?? '';

  if (chatRoomId == null || jobId == null || userId == null || userType == null) {
    debugPrint('❌ 필수 정보 누락: chatRoomId=$chatRoomId, jobId=$jobId, userId=$userId, userType=$userType');
    return;
  }

  // ✅ 나의 타입에 따라 올바른 파라미터 이름 사용
  final isWorker   = userType == 'worker';
  final paramName  = isWorker ? 'workerId' : 'clientId';
  final idParam    = userId.toString();  // 푸시 payload 말고 "내" 로그인 정보 사용

  final url = Uri.parse(
    '$baseUrl/api/chat/get-room-by-id?jobId=$jobId&$paramName=$idParam',
  );

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
      debugPrint('❌ 권한 오류(${resp.statusCode}): ${resp.body}');
      // 🔁 안전망: jobInfo만 별도 조회해서라도 채팅방으로 이동
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
      debugPrint('❌ jobInfo 조회 실패(${resp.statusCode}): ${resp.body}');
    }
  } catch (e) {
    debugPrint('❌ 알림 클릭 처리 중 예외: $e');
  }
}

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
  theme: ThemeData(
    fontFamily: 'Jalnan2TTF',
    textTheme: ThemeData.light().textTheme,
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
  ),
  // ✅ 여기서만 UpgradeAlert로 한 번 감싸기
   home: UpgradeAlert(
        upgrader: upgrader,
        child: startScreen,
      ),
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
        '/client_main': (context) => const ClientMainScreen(),
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
        '/review': (context) => ReviewScreenRouter(), // 예: arguments 받는 별도 래퍼
        '/purchase-pass': (context) => const PurchasePassScreen(),
        '/blocked-users': (context) => const BlockedUserListScreen(),
        '/portone-payment': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return PortonePaymentScreen(
            count: args['count'],
            companyName: args['companyName'],
            companyPhone: args['companyPhone'],
          );
        },
     '/job-detail': (context) {
  final args = ModalRoute.of(context)?.settings.arguments;
  if (args == null || args is! Job) {
    return const Scaffold(body: Center(child: Text('잘못된 접근입니다.')));
  }
  return JobDetailScreen(job: args);
},
        '/worker-profile': (context) {
          final int workerId =
              ModalRoute.of(context)!.settings.arguments as int;
          return WorkerProfileScreen(workerId: workerId);
        },
        '/client-profile': (context) {
          final int clientId =
              ModalRoute.of(context)!.settings.arguments as int;
          return ClientProfileScreen(clientId: clientId);
        },

  '/edit_profile': (context) => const EditClientProfileScreen(),
 '/edit_profile_worker': (_) => const EditWorkerProfileScreen(),
        '/notifications': (context) => const NotificationSettingsScreen(),
        '/terms-list': (context) => const TermsListScreen(),
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
class UpgraderMessagesKo extends UpgraderMessages {
  @override String get title => '업데이트 안내';
  @override String get body => '새 버전이 공개되었습니다. 지금 업데이트하시겠어요?';
  @override String get prompt => '스토어로 이동';
  @override String get ignore => '나중에';
  @override String get later  => '다음에';
  @override String get releaseNotes => '변경사항';
}