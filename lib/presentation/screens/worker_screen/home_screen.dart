import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'home_main_screen.dart';
import 'package:iljujob/presentation/screens/worker_screen/my_applied_jobs_screen.dart';
import '../../chat/chat_list_screen.dart';
import 'home_my_page_screen.dart';
import '../../../config/constants.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:iljujob/data/services/promo_service.dart';
import 'package:iljujob/data/models/promo_model.dart';
import 'package:iljujob/data/services/ai_api.dart';
import 'package:iljujob/data/services/authenticated_http_client.dart';
import 'package:iljujob/widget/recommended_section.dart';
import '../worker_calendar_screen.dart';
import 'package:iljujob/config/app_theme.dart';
import 'package:iljujob/widget/app_ui.dart';

class HomeScreen extends StatefulWidget {
  final int initialTabIndex;
  const HomeScreen({super.key, this.initialTabIndex = 2});

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

  bool _promoShownThisSession = false;
  late final PromoService promoService = PromoService(baseUrl);
  late final AiApi _aiApi = AiApi(baseUrl);

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTabIndex;
    _initializeHomeScreen();
    _setupFirebaseMessagingListeners();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeShowPromoIfHomeTab(),
    );
  }

  @override
  void dispose() {
    _unreadTimer?.cancel();
    socket?.disconnect();
    super.dispose();
  }

  Future<void> _maybeShowPromoIfHomeTab() async {
    if (_selectedIndex != 2) return;
    if (_promoShownThisSession) return;
    if (!mounted) return;
    final promo = await promoService.fetchPromo(
      platform:
          Theme.of(context).platform == TargetPlatform.iOS ? 'ios' : 'android',
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
        final dialogWidth = (size.width - 48).clamp(320.0, 431.0);
        final imageHeight = dialogWidth * (p.imageH / p.imageW);
        return StatefulBuilder(
          builder:
              (context, setState) => Dialog(
                elevation: 8,
                backgroundColor: AppColors.bgCard,
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      child: SizedBox(
                        width: dialogWidth,
                        height: imageHeight,
                        child: Image.network(
                          p.imageUrl,
                          fit: BoxFit.cover,
                          loadingBuilder:
                              (c, child, progress) =>
                                  progress == null
                                      ? child
                                      : const Center(
                                        child: CircularProgressIndicator(),
                                      ),
                          errorBuilder:
                              (c, e, s) =>
                                  const Center(child: Icon(Icons.broken_image)),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Checkbox(
                            value: dontShow,
                            onChanged:
                                (v) => setState(() => dontShow = v ?? false),
                          ),
                          Expanded(
                            child: Text(
                              p.checkboxLabel,
                              style: const TextStyle(fontSize: 14),
                            ),
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
                              backgroundColor: AppColors.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                            ),
                            onPressed: () async {
                              if (dontShow) await promoService.snooze(p);
                              if (!context.mounted) return;
                              Navigator.pop(context);
                            },
                            child: const Text(
                              '닫기',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        );
      },
    );
  }

  Future<void> _openDeeplink(String link) async {}

  Future<void> _initializeHomeScreen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('userPhone');
      final type = prefs.getString('userType');
      if (phone != null && type != null) {
        await _sendFcmTokenToServer(phone, type);
      }
      _loadUserInfoAndUnreadCount();
      _startUnreadTimer();
    } catch (e) {
      debugPrint('초기화 오류: $e');
    }
  }

  Future<void> _sendFcmTokenToServer(String? phone, String? userType) async {
    if (phone == null ||
        phone.trim().isEmpty ||
        userType == null ||
        userType.trim().isEmpty) {
      return;
    }
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.trim().isEmpty) return;
    try {
      await http.post(
        Uri.parse('$baseUrl/api/user/update-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userPhone': phone,
          'userType': userType,
          'fcmToken': token,
        }),
      );
    } catch (e) {
      debugPrint('FCM 토큰 전송 오류: $e');
    }
  }

  void _setupFirebaseMessagingListeners() {
    FirebaseMessaging.onMessage.listen(_showNotification);
  }

  Future<void> _showNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    await flutterLocalNotificationsPlugin.show(
      notification.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'basic_channel',
          '기본 채널',
          channelDescription: '일반 알림을 위한 채널',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
    );
  }

  Future<void> _loadUserInfoAndUnreadCount() async {
    final prefs = await SharedPreferences.getInstance();
    userPhone = prefs.getString('userPhone') ?? '';
    userType = prefs.getString('userType') ?? 'worker';
    await _fetchUnreadCount();
    _initSocket();
  }

  void _startUnreadTimer() {
    _unreadTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _fetchUnreadCount(),
    );
  }

  void _initSocket() {
    if (socket != null && socket!.connected) return;
    socket = IO.io(baseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
    });
    socket!.onConnect(
      (_) => socket!.emit('register_user', {'userPhone': userPhone}),
    );
    socket!.on('unreadCountUpdated', (data) {
      if (data['userPhone'] == userPhone && data['userType'] == userType) {
        setState(
          () => unreadCount = int.tryParse(data['newCount'].toString()) ?? 0,
        );
      }
    });
    socket!.onDisconnect((_) => debugPrint('소켓 연결 종료'));
  }

  Future<void> _fetchUnreadCount() async {
    final prefs = await SharedPreferences.getInstance();
    userPhone = prefs.getString('userPhone') ?? '';
    userType = prefs.getString('userType') ?? 'worker';
    final token = await AuthenticatedHttpClient.accessToken();
    if (userPhone.isEmpty || userType.isEmpty || token.isEmpty) return;
    final userId = prefs.getInt('userId')?.toString() ?? '';
    try {
      final response = await AuthenticatedHttpClient.get(
        Uri.parse(
          '$baseUrl/api/chat/unread-count?userId=$userId&userType=$userType',
        ),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(
          () => unreadCount = int.tryParse(data['unreadCount'].toString()) ?? 0,
        );
      }
    } catch (e) {
      debugPrint('안읽은 메시지 수 오류: $e');
    }
  }

  // ─────────────────────────────────────────────
  // 탭 선택 — 5탭 그대로
  // ─────────────────────────────────────────────
  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
    if (index == 2) _maybeShowPromoIfHomeTab();
  }

  List<Widget> _buildScreens() {
    return [
      const WorkerCalendarScreen(),
      const MyAppliedJobsScreen(),
      HomeMainScreen(onAiRecommend: _openRecommendSheet),
      ChatListScreen(onMessagesRead: _fetchUnreadCount),
      const WorkerMyPageScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildScreens()[_selectedIndex],
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ─────────────────────────────────────────────
  // 탭바 — 각 항목은 화면 이동만 담당
  // ─────────────────────────────────────────────
  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        boxShadow: AppShadows.bottomNav,
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              _navItem(
                index: 0,
                icon: Icons.calendar_month_outlined,
                activeIcon: Icons.calendar_month_rounded,
                label: '캘린더',
              ),
              _navItem(
                index: 1,
                icon: Icons.format_list_bulleted_rounded,
                activeIcon: Icons.format_list_bulleted_rounded,
                label: '내 활동',
              ),
              _navItem(
                index: 2,
                icon: Icons.home_outlined,
                activeIcon: Icons.home_rounded,
                label: '홈',
              ),
              _navItemChat(),
              _navItem(
                index: 4,
                icon: Icons.person_outline_rounded,
                activeIcon: Icons.person_rounded,
                label: '마이',
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 일반 탭
  Widget _navItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
  }) {
    final isActive = _selectedIndex == index;
    return AppBottomNavItem(
      isActive: isActive,
      icon: icon,
      activeIcon: activeIcon,
      label: label,
      onTap: () => _onItemTapped(index),
    );
  }

  // 채팅 탭 (뱃지 포함)
  Widget _navItemChat() {
    final isActive = _selectedIndex == 3;
    return AppBottomNavItem(
      isActive: isActive,
      icon: Icons.chat_bubble_outline_rounded,
      activeIcon: Icons.chat_bubble_rounded,
      label: '채팅',
      onTap: () => _onItemTapped(3),
      badgeLabel:
          unreadCount > 0 ? (unreadCount > 99 ? '99+' : '$unreadCount') : null,
    );
  }

  // ─────────────────────────────────────────────
  // AI 추천 바텀시트
  // ─────────────────────────────────────────────
  Future<void> _openRecommendSheet() async {
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder:
          (ctx) => DraggableScrollableSheet(
            initialChildSize: 0.88,
            minChildSize: 0.55,
            maxChildSize: 0.96,
            builder:
                (context, scrollController) => ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppRadius.xl),
                  ),
                  child: Material(
                    color: AppColors.bgCard,
                    child: _RecommendSheet(
                      api: _aiApi,
                      scrollController: scrollController,
                    ),
                  ),
                ),
          ),
    );
  }
}

// ─────────────────────────────────────────────
// AI 추천 시트 (기존 동일)
// ─────────────────────────────────────────────
class _RecommendSheet extends StatefulWidget {
  final AiApi api;
  final ScrollController? scrollController;
  const _RecommendSheet({required this.api, this.scrollController});

  @override
  State<_RecommendSheet> createState() => _RecommendSheetState();
}

class _RecommendSheetState extends State<_RecommendSheet> {
  int _reloadTick = 0;
  final List<String> _chips = const [
    '오늘 마감',
    '초보 가능',
    '단기/하루',
    '주급',
    '당일지급',
    '인기 공고',
  ];
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: CustomScrollView(
        controller: widget.scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI 맞춤 추천',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '프로필과 위치를 기준으로 공고를 추천합니다.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '새로고침',
                    onPressed: () => setState(() => _reloadTick++),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  IconButton(
                    tooltip: '닫기',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    _chips.map((label) {
                      final selected = _selected.contains(label);
                      return GestureDetector(
                        onTap:
                            () => setState(() {
                              selected
                                  ? _selected.remove(label)
                                  : _selected.add(label);
                              _reloadTick++;
                            }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color:
                                selected
                                    ? AppColors.primary
                                    : AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(AppRadius.full),
                            border: Border.all(
                              color:
                                  selected
                                      ? AppColors.primary
                                      : AppColors.primaryMid,
                            ),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color:
                                  selected
                                      ? Colors.white
                                      : AppColors.textPrimary,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(
              height: 1,
              color: AppColors.borderSub,
              margin: const EdgeInsets.only(bottom: 10),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.bgMuted,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline_rounded,
                        size: 18,
                        color: AppColors.primary,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '거리, 일정, 선호 조건, 최근 지원 이력을 반영합니다.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textPrimary,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                RecommendedSection(
                  key: ValueKey('reco_${_reloadTick}_${_selected.join("|")}'),
                  api: widget.api,
                ),
                const SizedBox(height: 12),
                const Opacity(
                  opacity: 0.55,
                  child: Text(
                    '추천 결과는 조건에 따라 달라질 수 있습니다.',
                    style: TextStyle(fontSize: 11.5),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
