import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:badges/badges.dart' as badges;
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'home_main_screen.dart';
import 'package:iljujob/presentation/screens/my_applied_jobs_screen.dart';
import '../chat/chat_list_screen.dart';
import 'home_my_page_screen.dart';
import 'edit_worker_profile_screen.dart';
import '../../config/constants.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:io';
import 'package:iljujob/presentation/chat/chat_room_screen.dart';
import 'package:iljujob/config/constants.dart';
import 'package:iljujob/data/services/promo_service.dart';
import 'package:iljujob/data/models/promo_model.dart';
class HomeScreen extends StatefulWidget {
  final int initialTabIndex;

  const HomeScreen({super.key, this.initialTabIndex = 2}); // 기본값은 홈탭
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 2;
  int unreadCount = 0;
  String userPhone = '';
  String userType = 'worker';
  Timer? _unreadTimer;
  IO.Socket? socket;
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
bool _promoShownThisSession = false; // 세션 중 중복 방지
late final PromoService promoService = PromoService(baseUrl); // baseUrl 주입



Future<void> _maybeShowPromoIfHomeTab() async {
  if (_selectedIndex != 2) return;
  if (_promoShownThisSession) return;
  if (!mounted) return;

  final promo = await promoService.fetchPromo(
    platform: Theme.of(context).platform == TargetPlatform.iOS ? 'ios' : 'android',
    userType: userType,
  );
  if (promo == null) return;

  final should = await promoService.shouldShow(promo);
  if (!should) return;

  _promoShownThisSession = true;

  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    _showPromoDialogFromRemote(promo);
  });
}

void _showPromoDialogFromRemote(PromoConfig p) {
  bool dontShow = false;

  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      final size = MediaQuery.of(ctx).size;
      final maxWidth = size.width - 48;
      final dialogWidth = maxWidth.clamp(320.0, 431.0);
      final ratio = (p.imageH / p.imageW);
      final imageHeight = dialogWidth * ratio;

      return StatefulBuilder(
        builder: (context, setState) {
          return Dialog(
            elevation: 8,
            backgroundColor: Colors.white,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: SizedBox(
                    width: dialogWidth,
                    height: imageHeight,
                    child: Image.network(
                      p.imageUrl,
                      fit: BoxFit.cover,
                      loadingBuilder: (c, child, progress) =>
                        progress == null ? child : const Center(child: CircularProgressIndicator()),
                      errorBuilder: (c, e, s) => const Center(child: Icon(Icons.broken_image)),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Checkbox(
                        value: dontShow,
                        onChanged: (v) => setState(() => dontShow = v ?? false),
                      ),
                      Expanded(
                        child: Text(p.checkboxLabel, style: const TextStyle(fontSize: 14)),
                      ),
                      if (p.deeplink != null)
                        TextButton(
                          onPressed: () async {
                            if (dontShow) await promoService.snooze(p);
                            if (!context.mounted) return;
                            Navigator.pop(context);
                            await _openDeeplink(p.deeplink!);
                          },
                          child: Text(p.ctaLabel),
                        ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                        onPressed: () async {
                          if (dontShow) await promoService.snooze(p);
                          if (!context.mounted) return;
                          Navigator.pop(context);
                        },
                        child: const Text('닫기', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
Future<void> _openDeeplink(String link) async {
  // url_launcher 사용: launchUrlString(link);
}

@override
void initState() {
  super.initState();
  _initializeHomeScreen();
  _setupFirebaseMessagingListeners();
  WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowPromoIfHomeTab());
}

Future<void> _initializeHomeScreen() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('userPhone');
    final userType = prefs.getString('userType');

    if (phone != null && userType != null) {
      await _sendFcmTokenToServer(phone, userType);
    } else {
    }

    _loadUserInfoAndUnreadCount();
    _startUnreadTimer();

  } catch (e) {
    print('❌ SharedPreferences 초기화 중 예외 발생: $e');
  }
}

Future<void> _sendFcmTokenToServer(String? phone, String? userType) async {
  if (phone == null || phone.trim().isEmpty ||
      userType == null || userType.trim().isEmpty) {
    print('❌ SharedPreferences에서 userPhone 또는 userType이 비어 있음 → 전송 생략');
    return;
  }

  final token = await FirebaseMessaging.instance.getToken();

  if (token == null || token.trim().isEmpty) {
    print('❌ FCM 토큰 없음 → 서버 전송 생략');
    return;
  }


  try {
    final response = await http.post(
      Uri.parse('$baseUrl/api/user/update-token'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'userPhone': phone,
        'userType': userType,
        'fcmToken': token,
      }),
    );



    if (response.statusCode == 200) {

    } else {
      print('❌ 서버 오류: ${response.statusCode}');
    }
  } catch (e) {
    print('❌ 예외 발생: $e');
  }
}

void _setupFirebaseMessagingListeners() {
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    
    _showNotification(message);
  });


}

  @override
  void dispose() {
    _unreadTimer?.cancel();
    socket?.disconnect();
    super.dispose();
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

Future<void> _loadUserInfoAndUnreadCount() async {

  final prefs = await SharedPreferences.getInstance();
  userPhone = prefs.getString('userPhone') ?? '';
  userType = prefs.getString('userType') ?? 'worker';


  await _fetchUnreadCount(); // 여기까지 도달하는지 확인
  _initSocket();
}


  void _startUnreadTimer() {
    _unreadTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _fetchUnreadCount();
    });
  }

  void _initSocket() {
    if (socket != null && socket!.connected) return;

    socket = IO.io(baseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
    });

    socket!.onConnect((_) {

      socket!.emit('register_user', {'userPhone': userPhone});
    });

    socket!.on('unreadCountUpdated', (data) {
      final updatedPhone = data['userPhone'];
      final updatedType = data['userType'];
      final newCount = int.tryParse(data['newCount'].toString()) ?? 0;

      if (updatedPhone == userPhone && updatedType == userType) {
        setState(() {
          unreadCount = newCount;
        });
      }
    });

    socket!.onDisconnect((_) => print('❌ 소켓 연결 종료'));
  }

  Future<void> _fetchUnreadCount() async {
  final prefs = await SharedPreferences.getInstance();
  userPhone = prefs.getString('userPhone') ?? '';
  userType = prefs.getString('userType') ?? 'worker';
  final token = prefs.getString('authToken') ?? '';



  if (userPhone.trim().isEmpty || userType.trim().isEmpty || token.trim().isEmpty) {

    return;
  }
final userId = prefs.getInt('userId')?.toString() ?? '';
final url = Uri.parse('$baseUrl/api/chat/unread-count?userId=$userId&userType=$userType');

  try {
    final response = await http.get(
      url,
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final newCount = int.tryParse(data['unreadCount'].toString()) ?? 0;

      setState(() {
        unreadCount = newCount;
      });
    } else {
      print('❌ 서버 응답 오류 상태 코드: ${response.statusCode}');
    }
  } catch (e) {
    print('❌ 예외 발생: $e');
  }
}

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
     if (index == 2) {
    _maybeShowPromoIfHomeTab();
  }
  }

  List<Widget> _buildScreens() {
    return [
      const EditWorkerProfileScreen(),
      const MyAppliedJobsScreen(),
      const HomeMainScreen(),
      ChatListScreen(onMessagesRead: _fetchUnreadCount),
      const WorkerMyPageScreen(),
    ];
  }

  List<BottomNavigationBarItem> _buildNavItems() {
    return [
      const BottomNavigationBarItem(icon: Icon(Icons.settings), label: '프로필 수정'),
      const BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: '지원 공고'),
      const BottomNavigationBarItem(icon: Icon(Icons.home), label: '홈'),
      BottomNavigationBarItem(
        icon: badges.Badge(
          showBadge: unreadCount > 0,
          badgeContent: Text(
            unreadCount > 99 ? '99+' : '$unreadCount',
            style: const TextStyle(color: Colors.white, fontSize: 10),
          ),
          position: badges.BadgePosition.topEnd(top: -10, end: -12),
          badgeStyle: const badges.BadgeStyle(
            badgeColor: Colors.red,
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            elevation: 0,
          ),
          child: const Icon(Icons.chat),
        ),
        label: '채팅',
      ),
      const BottomNavigationBarItem(icon: Icon(Icons.person), label: '마이페이지'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildScreens()[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: Colors.indigo,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: _buildNavItems(),
      ),
    );
  }
}
