import 'package:flutter/material.dart';
import 'package:iljujob/widget/app_motion.dart';
import 'package:iljujob/utils/chat_stage.dart';
import 'package:iljujob/widget/app_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:intl/intl.dart';

import 'chat_room_screen.dart';
import '../../config/constants.dart';
import 'package:iljujob/data/services/authenticated_http_client.dart';
import 'dart:async';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:iljujob/widget/push_permission.dart';
import 'package:iljujob/config/app_theme.dart';
import 'package:iljujob/data/services/screen_analytics_service.dart';
import 'package:iljujob/widget/ad_banner_widget.dart';
import 'package:iljujob/widget/safe_snackbar.dart';
import '../../config/messages.dart';

class ChatListScreen extends StatefulWidget {
  final VoidCallback? onMessagesRead;

  const ChatListScreen({super.key, this.onMessagesRead});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen>
    with WidgetsBindingObserver {
  // ====== State ======
  List<dynamic> chatRooms = [];
  bool isLoading = true;
  String userType = 'worker';
  int? myId;
  String? myType;
  bool _showNotificationBanner = false;
  IO.Socket? _socket;
  Timer? _listRefreshTimer;
  String _query = '';
  final Set<int> _leavingRoomIds = {};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadMyIdAndType().then((_) {
      ScreenAnalyticsService.instance.logScreenView(
        userType == 'client' ? 'client_chat_list' : 'worker_chat_list',
      );
      _loadUserTypeAndFetchChats();
    });

    // 채팅 진입 자체를 막지 않도록 자동 팝업 대신 상단 배너만 노출합니다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkNotificationBannerNeeded();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _listRefreshTimer?.cancel();
    _socket?.clearListeners();
    _socket?.disconnect();
    _socket = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchChatRooms();
      _socket?.connect();
    }
  }

  Future<void> _checkNotificationBannerNeeded() async {
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    if (!mounted) return;
    setState(() {
      _showNotificationBanner =
          settings.authorizationStatus != AuthorizationStatus.authorized;
    });
  }

  /* ---------------- 기본 유저 정보 로드 ---------------- */

  Future<void> _loadMyIdAndType() async {
    final prefs = await SharedPreferences.getInstance();
    print(
      '📌 userId=${prefs.getInt('userId')}, phone=${prefs.getString('userPhone')}',
    );
    setState(() {
      myId = prefs.getInt('userId');
      myType = prefs.getString('userType');
    });
  }

  Future<void> _loadUserTypeAndFetchChats() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    userType = prefs.getString('userType') ?? 'worker';

    await _fetchChatRooms();
    widget.onMessagesRead?.call();
    await _initSocket(prefs.getString('userPhone') ?? '');
  }

  /* ---------------- 실시간 목록 갱신 ---------------- */

  // 목록에 소켓이 아예 없어서, 화면을 열어둔 채로는 새 메시지가 와도 갱신되지
  // 않았다(앱을 백그라운드에 보냈다 돌아와야 반영). 새 메시지·새 채팅방 신호를
  // 받아 목록만 다시 불러온다.
  Future<void> _initSocket(String userPhone) async {
    if (_socket != null || userPhone.isEmpty) return;
    final token = await AuthenticatedHttpClient.accessToken();
    if (token.isEmpty) return;

    _socket = IO.io(baseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'reconnection': true,
      'auth': {'token': token},
      'extraHeaders': {'Authorization': 'Bearer $token'},
    });

    _socket!.onConnect((_) {
      _socket!.emit('register_user', {'userPhone': userPhone});
    });

    // 여러 방에서 동시에 오면 요청이 겹치므로 묶어서 한 번만 다시 받는다.
    void refresh(dynamic _) {
      if (!mounted) return;
      _listRefreshTimer?.cancel();
      _listRefreshTimer = Timer(const Duration(milliseconds: 400), () {
        if (mounted) _fetchChatRooms();
      });
    }

    _socket!.on('unreadCountUpdated', refresh);
    _socket!.on('new_chat_room', refresh);
    _socket!.connect();
  }

  /* ---------------- 시간 처리 ---------------- */

  DateTime? _parseServerTime(dynamic v) {
    if (v == null) return null;

    // 이미 DateTime이면 그대로 (로컬 기준)
    if (v is DateTime) return v;

    // 🔹 1) 숫자(타임스탬프)인 경우: UTC라고 가정하지 말고 "그냥" 에폭 기준 시간으로 처리
    if (v is int) {
      final len = v.toString().length;
      if (len >= 16) {
        // 마이크로초
        return DateTime.fromMicrosecondsSinceEpoch(v);
      } else if (len >= 13) {
        // 밀리초
        return DateTime.fromMillisecondsSinceEpoch(v);
      } else {
        // 초
        return DateTime.fromMillisecondsSinceEpoch(v * 1000);
      }
    }

    String s = v.toString().trim();
    if (s.isEmpty) return null;

    // 🔹 2) 숫자 문자열(타임스탬프)도 위와 동일하게 처리
    if (RegExp(r'^\d+$').hasMatch(s)) {
      final n = int.tryParse(s);
      if (n != null) {
        final len = s.length;
        if (len >= 16) {
          return DateTime.fromMicrosecondsSinceEpoch(n);
        } else if (len >= 13) {
          return DateTime.fromMillisecondsSinceEpoch(n);
        } else {
          return DateTime.fromMillisecondsSinceEpoch(n * 1000);
        }
      }
    }

    // 🔹 3) 문자열 날짜 처리
    try {
      // MySQL DATETIME 형식: "2025-11-23 13:15:00"
      if (s.contains(' ') && !s.contains('T')) {
        final dt = DateTime.parse('${s.replaceFirst(' ', 'T')}Z'); // UTC 명시
        return dt.toLocal(); // KST로 변환해서 화면 표시
      }

      // ISO 형식: "2025-11-23T04:15:00.000Z" 또는 "2025-11-23T13:15:00+09:00"
      final dt = DateTime.parse(s);
      return dt.isUtc ? dt.toLocal() : dt;
    } catch (_) {
      return null;
    }
  }

  String _formatTime(dynamic timeValue) {
    final parsedTime = _parseServerTime(timeValue);
    if (parsedTime == null) return '';

    final now = DateTime.now();
    var diff = now.difference(parsedTime);

    // 미래 시간이면 0으로 보정
    if (diff.isNegative) diff = Duration.zero;

    if (diff.inMinutes < 1) {
      return '방금 전';
    }
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}분 전';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours}시간 전';
    }
    if (diff.inDays == 1) {
      return '어제';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays}일 전';
    }

    return DateFormat('MM/dd').format(parsedTime);
  }
  /* ---------------- 채팅방 목록 API ---------------- */

  Future<void> _fetchChatRooms() async {
    setState(() => isLoading = true);
    final prefs = await SharedPreferences.getInstance();

    // ⚠️ userPhone으로 막지 않는다. 서버는 토큰의 id를 우선으로 신원을 정하고,
    // 카카오/애플로 로그인한 사장님은 prefs에 userPhone이 없다 — 여기서 막으면
    // 채팅방이 멀쩡히 있는데도 목록이 영영 비어 보인다(2026-09-07 client 643).
    final userPhone = prefs.getString('userPhone') ?? '';
    final userId = prefs.getInt('userId');
    if (userPhone.isEmpty && userId == null) {
      _showSnackbar(Msg.loginRequired);
      setState(() => isLoading = false);
      return;
    }

    final url = Uri.parse(
      '$baseUrl/api/chat/list'
      '?userType=$userType'
      '${userId != null ? '&userId=$userId' : ''}'
      '${userPhone.isNotEmpty ? '&userPhone=$userPhone' : ''}',
    );

    try {
      final response = await AuthenticatedHttpClient.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          chatRooms = List.from(data)..sort((a, b) {
            final aTime = _parseServerTime(a['last_sent_at']) ?? DateTime(2000);
            final bTime = _parseServerTime(b['last_sent_at']) ?? DateTime(2000);
            return bTime.compareTo(aTime);
          });
        });
      } else {
        debugPrint('채팅방 목록 불러오기 실패 (${response.statusCode})');
        _showSnackbar(Msg.chatListFailed);
      }
    } on AuthSessionExpiredException {
      _showSnackbar(Msg.loginRequired);
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/onboarding', (_) => false);
      }
    } catch (e) {
      _showSnackbar(Msg.network);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  /* ---------------- 채팅방 나가기 확인 ---------------- */

  Future<void> _confirmLeaveChat(Map chat) async {
    final roomId = int.tryParse(chat['id']?.toString() ?? '');
    if (roomId == null) {
      _showSnackbar('채팅방 정보를 확인할 수 없어요.');
      return;
    }
    final title = (chat['job_title'] ?? '이 채팅방').toString();
    final leaveDescription =
        userType == 'worker'
            ? '채팅 목록에서 사라지고, 확정되지 않은 지원은 취소됩니다.\n사장님에게 나갔다는 안내가 전달됩니다.'
            : '내 채팅 목록에서만 사라집니다.\n구직자에게 채팅이 종료됐다는 안내가 전달됩니다.';

    final confirm = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        final bottom = MediaQuery.of(context).viewPadding.bottom;
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.exit_to_app_rounded,
                  color: AppColors.error,
                  size: 26,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '채팅방 나가기',
                style: TextStyle(
                  fontSize: AppFontSize.title,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Jalnan2TTF',
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$title\n$leaveDescription',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: AppFontSize.button,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.error,
                  ),
                  child: const Text(
                    '나가기'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    '취소',
                    style: TextStyle(fontSize: AppFontSize.button, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (confirm == true) {
      await _leaveChatRoom(roomId);
    }
  }

  /* ---------------- 채팅방 나가기 ---------------- */

  Future<void> _leaveChatRoom(int roomId) async {
    if (_leavingRoomIds.contains(roomId)) return;
    final url = Uri.parse('$baseUrl/api/chat/leave/$roomId');
    if (mounted) setState(() => _leavingRoomIds.add(roomId));

    try {
      final response = await AuthenticatedHttpClient.delete(url);

      if (response.statusCode == 200 ||
          response.statusCode == 204 ||
          response.statusCode == 404) {
        _showSnackbar('채팅방을 나갔어요.');
        setState(() {
          chatRooms.removeWhere(
            (r) =>
                r is Map && int.tryParse(r['id']?.toString() ?? '') == roomId,
          );
        });
        widget.onMessagesRead?.call();
      } else if (response.statusCode == 403) {
        _showSnackbar('권한이 없어요.');
      } else {
        debugPrint('채팅방 나가기 실패 (${response.statusCode})');
        _showSnackbar(Msg.chatLeaveFailed);
      }
    } on AuthSessionExpiredException {
      _showSnackbar(Msg.loginRequired);
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/onboarding', (_) => false);
      }
    } catch (e) {
      _showSnackbar(Msg.chatLeaveFailed);
    } finally {
      if (mounted) setState(() => _leavingRoomIds.remove(roomId));
    }
  }

  /* ---------------- 지원 취소 (채팅 목록에서) ---------------- */

  Future<void> _confirmCancelApplication(Map chat) async {
    if (userType != 'worker') {
      _showSnackbar('지원 취소는 구직자만 가능합니다.');
      return;
    }

    final jobId = chat['job_id'];
    if (jobId == null) {
      _showSnackbar('공고 정보가 없어 취소할 수 없어요.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const CancelApplicationDialog(),
    );

    if (confirmed == true) {
      await _cancelApplicationFromChat(chat);
    }
  }

  Future<void> _cancelApplicationFromChat(Map chat) async {
    final jobId = chat['job_id'];
    if (jobId == null) {
      _showSnackbar('공고 정보가 없어 취소할 수 없어요.');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final workerId = myId ?? prefs.getInt('userId');

    if (workerId == null) {
      _showSnackbar(Msg.loginExpired);
      return;
    }

    final uri = Uri.parse('$baseUrl/api/applications/cancel');

    try {
      final response = await AuthenticatedHttpClient.postJson(
        uri,
        body: {'jobId': jobId, 'workerId': workerId},
      );

      if (response.statusCode == 200) {
        String message = '지원을 취소했어요.';
        try {
          final data = jsonDecode(response.body);
          if (data is Map && data['message'] is String) {
            message = data['message'];
          }
        } catch (_) {}

        _showSnackbar(message);
        await _fetchChatRooms();
      } else {
        String message = Msg.applyCancelFailed;
        try {
          final data = jsonDecode(response.body);
          if (data is Map && data['message'] is String) {
            message = data['message'];
          }
        } catch (_) {}
        _showSnackbar(message);
      }
    } on AuthSessionExpiredException {
      _showSnackbar(Msg.loginRequired);
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/onboarding', (_) => false);
      }
    } catch (e) {
      debugPrint('지원 취소 중 오류가 발생했습니다: $e');
      _showSnackbar(Msg.applyCancelFailed);
    }
  }

  /* ---------------- 채팅 아이템 UI ---------------- */

  Future<void> _showChatActions(Map chat) async {
    final roomId = int.tryParse(chat['id']?.toString() ?? '');
    final isLeaving = roomId != null && _leavingRoomIds.contains(roomId);
    final title = (chat['job_title'] ?? '채팅방').toString();

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgCard,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AppFontSize.buttonLg,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                if (userType == 'worker') ...[
                  _ChatActionTile(
                    icon: Icons.cancel_outlined,
                    iconColor: AppColors.error,
                    title: '지원 취소',
                    subtitle: '지원 상태가 취소됩니다. 다시 지원이 필요할 수 있어요.',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _confirmCancelApplication(chat);
                    },
                  ),
                  const Divider(height: 8, color: AppColors.borderSub),
                ],
                _ChatActionTile(
                  icon: Icons.logout_rounded,
                  iconColor: AppColors.textSecondary,
                  title: '채팅방 나가기',
                  subtitle: '목록에서 정리하고 새 메시지 알림을 받지 않아요.',
                  trailing:
                      isLeaving
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : null,
                  onTap:
                      isLeaving
                          ? null
                          : () {
                            Navigator.pop(sheetContext);
                            _confirmLeaveChat(chat);
                          },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNotificationBanner() {
    if (!_showNotificationBanner) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.bgMuted,
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              color: AppColors.textSecondary,
              size: 17,
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '답변과 출근확정을 놓치지 않게 알림을 켜주세요.',
              style: TextStyle(
                fontSize: AppFontSize.body2,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          GestureDetector(
            onTap: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('notification_dialog_shown', true);
              // 이미 거부했으면 OS 가 다시 안 물어서 '켜기'가 아무 일도 안 했다 → 설정으로.
              await requestPushPermission(source: 'chat_list_banner');
              await _checkNotificationBannerNeeded(); // 허용하면 배너 사라짐
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                '켜기',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: AppFontSize.body2,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => setState(() => _showNotificationBanner = false),
            child: const Icon(
              Icons.close,
              size: 16,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatItem(Map chat) {
    final unreadCount =
        userType == 'worker'
            ? (chat['unread_count_worker'] ?? 0)
            : (chat['unread_count_client'] ?? 0);
    final hasUnread = unreadCount > 0;
    final isUrgent =
        chat['is_urgent_call'] == 1 || chat['is_urgent_call'] == true;
    // 방마다 '지금 단계' 하나 — 긴급호출 수락이 '출근확정'으로 보이던 것(상태 문자열에 accepted만 있어도 확정)
    final stage = chatStageOf(
      isWorker: userType == 'worker',
      workStatus: chat['work_status']?.toString(),
      workDate: chat['work_date']?.toString(),
      urgentStatus: chat['direct_message_status']?.toString(),
      isUrgent: isUrgent,
      applicationStatus: chat['application_status']?.toString(),
    );
    final workDay = (chat['work_date'] ?? '').toString();

    String resolveProfileImageUrl(String? url) {
      if (url == null || url.trim().isEmpty) return '';
      if (url.startsWith('http')) return url;
      return '$baseUrl/${url.replaceFirst(RegExp(r'^/+'), '')}';
    }

    final rawUrl =
        userType == 'worker'
            ? (chat['client_thumbnail_url'] ?? '')
            : (chat['user_thumbnail_url'] ?? '');
    final profileImageUrl = resolveProfileImageUrl(rawUrl);

    final lastTime = _formatTime(chat['last_sent_at']);
    final jobTitle = chat['job_title'] ?? '공고 제목 없음';
    final otherParty =
        userType == 'worker'
            ? (chat['client_company_name'] ?? '업체')
            : (chat['user_name'] ?? '알바생');

    final lastMessage = (chat['last_message'] ?? '').toString().trim();
    final lastSenderType = chat['last_sender_type'] ?? '';
    final lastSenderId = chat['last_sender_id'] ?? 0;

    bool isMine = false;
    if (myId != null && myType != null) {
      isMine = (lastSenderType == myType && lastSenderId == myId);
    }

    final fallbackText =
        userType == 'worker'
            ? (chat['client_company_name'] ?? '업체')
            : (chat['user_name'] ?? '알바생');

    final showCancel = (userType == 'worker');
    final roomId = int.tryParse(chat['id']?.toString() ?? '');
    final isLeaving = roomId != null && _leavingRoomIds.contains(roomId);

    final previewText =
        lastMessage.isEmpty
            ? '대화가 시작되지 않았어요'
            : '${isMine ? '나: ' : ''}$lastMessage';

    return Slidable(
      key: ValueKey('room_${chat['id']}'),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: showCancel ? 0.6 : 0.3,
        children: [
          if (showCancel)
            CustomSlidableAction(
              backgroundColor: AppColors.error,
              onPressed: (_) => _confirmCancelApplication(chat),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.cancel_outlined, color: Colors.white),
                  SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '지원 취소',
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: AppFontSize.body2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          CustomSlidableAction(
            backgroundColor: AppColors.textSecondary,
            onPressed: (_) {
              if (isLeaving) return;
              _confirmLeaveChat(chat);
            },
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isLeaving)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                else
                  const Icon(Icons.logout_rounded, color: Colors.white),
                const SizedBox(height: 4),
                const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '나가기',
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: AppFontSize.body2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      // 2026-10 리디자인(당근 채팅 목록): 떠 있는 카드·안읽음 파란 바탕·'새 메시지' 뱃지(숫자와 중복)·⋯ 버튼
      // → 흰 줄 + 구분선. 누가(굵게) · 무슨 공고 · 마지막 말 순서. 더보기는 길게 누르기/밀기로
      child: Material(
        color: AppColors.bgCard,
        child: InkWell(
          onTap: () => _openRoom(chat),
          onLongPress: () => _showChatActions(chat),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.borderSub)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.bgMuted,
                  backgroundImage:
                      profileImageUrl.isNotEmpty
                          ? NetworkImage(profileImageUrl)
                          : null,
                  child:
                      profileImageUrl.isEmpty
                          ? Text(
                            fallbackText.isNotEmpty ? fallbackText[0] : '?',
                            style: AppTextStyles.h3.copyWith(
                              color: AppColors.textTertiary,
                            ),
                          )
                          : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                          Flexible(
                            child: Text(
                              '$otherParty',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.jobTitle,
                            ),
                          ),
                          if (userType == 'client' &&
                              chat['user_available_today'] == 1) ...[
                            const SizedBox(width: 6),
                            const JobSignalBadge(
                              label: '오늘 가능',
                              signal: JobSignal.time,
                            ),
                          ],
                              ],
                            ),
                          ),
                          if (lastTime.isNotEmpty)
                            Text(lastTime, style: AppTextStyles.caption),
                        ],
                      ),
                      const SizedBox(height: 2),
                      // 단계(색) · 근무일 · 공고 — 같은 사장님 방이 여러 개여도 구별되게
                      Text.rich(
                        TextSpan(
                          children: [
                            if (stage != null)
                              TextSpan(
                                text: '${stage.label} · ',
                                style: AppTextStyles.jobMeta.copyWith(
                                  color: stage.color,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            if (workDay.length >= 10)
                              TextSpan(
                                text:
                                    '${int.parse(workDay.substring(5, 7))}/${int.parse(workDay.substring(8, 10))} 근무 · ',
                              ),
                            TextSpan(text: '$jobTitle'),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.jobMeta,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              previewText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.body2.copyWith(
                                color:
                                    lastMessage.isEmpty
                                        ? AppColors.textTertiary
                                        : hasUnread
                                        ? AppColors.textPrimary
                                        : AppColors.textSecondary,
                                fontWeight:
                                    hasUnread
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                              ),
                            ),
                          ),
                          if (hasUnread)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              constraints: const BoxConstraints(minWidth: 20),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                // 안읽음은 '빨리 봐야 함' — 주황(시간 신호). 파랑은 누르는 것에만
                                color: AppColors.badgeUrgent,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.full,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                unreadCount > 99 ? '99+' : '$unreadCount',
                                style: AppTextStyles.captionBold.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openRoom(Map chat) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder:
                    (_) => ChatRoomScreen(
                      chatRoomId: chat['id'],
                      jobInfo: {
                        'id': chat['job_id'],
                        'title': chat['job_title'] ?? '공고 제목 없음',
                        'pay': chat['pay']?.toString() ?? '0',
                        'created_at': chat['created_at'] ?? '',
                        'client_company_name':
                            chat['client_company_name'] ?? '기업',
                        'client_thumbnail_url':
                            chat['client_thumbnail_url'] ?? '',
                        'client_phone': chat['client_phone'] ?? '',
                        'user_name': chat['user_name'] ?? '알바생',
                        'user_thumbnail_url': chat['user_thumbnail_url'] ?? '',
                        'user_phone': chat['user_phone'] ?? '',
                        'client_id': chat['client_id'],
                        'worker_id': chat['worker_id'],
                        'lat': double.tryParse(chat['lat'].toString()) ?? 0.0,
                        'lng': double.tryParse(chat['lng'].toString()) ?? 0.0,
                        'is_urgent_call': chat['is_urgent_call'],
                        'direct_message_log_id': chat['direct_message_log_id'],
                        'direct_message_status': chat['direct_message_status'],
                      },
                    ),
              ),
            ).then((result) {
              if (result == 'updated') {
                _fetchChatRooms();
                widget.onMessagesRead?.call();
              }
            });
  }

  void _showSnackbar(String message) {
    if (!mounted) return;
    showSafeSnackBar(context, message);
  }

  /* ---------------- Build ---------------- */

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    List<dynamic> filtered =
        chatRooms.where((c) {
          final title = (c['job_title'] ?? '').toString().toLowerCase();
          final other =
              (userType == 'worker'
                      ? (c['client_company_name'] ?? '')
                      : (c['user_name'] ?? ''))
                  .toString()
                  .toLowerCase();
          final lastMsg = (c['last_message'] ?? '').toString().toLowerCase();
          if (q.isEmpty) return true;
          return title.contains(q) || other.contains(q) || lastMsg.contains(q);
        }).toList();

    final unreadOnly =
        filtered.where((c) {
          final unread =
              userType == 'worker'
                  ? (c['unread_count_worker'] ?? 0)
                  : (c['unread_count_client'] ?? 0);
          return (unread) > 0;
        }).toList();

    final urgentOnly =
        filtered
            .where(
              (c) => c['is_urgent_call'] == 1 || c['is_urgent_call'] == true,
            )
            .toList();

    // 탭별 안읽음 총합
    final totalUnread = filtered.fold<int>(0, (sum, c) {
      final n =
          userType == 'worker'
              ? (c['unread_count_worker'] ?? 0)
              : (c['unread_count_client'] ?? 0);
      return sum + (n as int);
    });
    final urgentUnread = urgentOnly.fold<int>(0, (sum, c) {
      final n =
          userType == 'worker'
              ? (c['unread_count_worker'] ?? 0)
              : (c['unread_count_client'] ?? 0);
      return sum + (n as int);
    });

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.bgCard,
        body: RefreshIndicator(
          onRefresh: () async {
            await _fetchChatRooms();
          },
          color: AppColors.primary,
          // 예전엔 CustomScrollView 의 SliverFillRemaining(hasScrollBody: true)
          // 안에 TabBarView 를 넣었다. 그러면 안쪽 ListView 가 제스처를 먹어
          // 바깥 스크롤이 움직이지 않았고, 광고 배너를 스크롤로 치울 수 없었다.
          // NestedScrollView 는 헤더와 본문 스크롤을 이어 준다 —
          // 검색바·탭은 고정으로 남고 탭 스와이프도 유지된다.
          child: NestedScrollView(
            headerSliverBuilder:
                (context, innerBoxIsScrolled) => [
                  SliverAppBar(
                    pinned: true,
                    elevation: 0,
                    backgroundColor: AppColors.bgCard,
                    surfaceTintColor: Colors.transparent,
                    foregroundColor: AppColors.textPrimary,
                    // 흰 앱바 52 + 검색창 56. 예전 파란 헤더는 130이었다.
                    expandedHeight: 108,
                    toolbarHeight: 52,
                    titleSpacing: 20,
                    title: const Text('채팅', style: AppTextStyles.tabTitle),
                    flexibleSpace: FlexibleSpaceBar(
                      background: Container(
                        color: AppColors.bgCard,
                        child: SafeArea(
                          bottom: false,
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                              child: _SearchField(
                                onChanged: (q) => setState(() => _query = q),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(child: _buildNotificationBanner()),
                  if (!isLoading && chatRooms.isEmpty)
                    const SliverToBoxAdapter(
                      child: AdBannerWidget(placement: 'app_chat_list'),
                    ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _TabHeaderDelegate(
                      TabBar(
                        indicatorColor: AppColors.textPrimary,
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor: AppColors.border,
                        labelColor: AppColors.textPrimary,
                        unselectedLabelColor: AppColors.textTertiary,
                        labelStyle: const TextStyle(
                          fontWeight: FontWeight.w700,
                        ),
                        tabs: [
                          _BadgeTab(label: '전체', count: totalUnread),
                          _BadgeTab(label: '안읽음', count: unreadOnly.length),
                          _BadgeTab(label: '긴급', count: urgentUnread),
                        ],
                      ),
                    ),
                  ),
                ],
            body:
                isLoading
                    ? const AppSkeletonList(avatar: true)
                    : chatRooms.isEmpty
                    ? const _EmptyState()
                    : TabBarView(
                      children: [
                        _PrettyListView(
                          items: filtered,
                          itemBuilder: (c) => _buildChatItem(c),
                          afterFirst:
                              q.isEmpty
                                  ? const AdBannerWidget(
                                    placement: 'app_chat_list',
                                  )
                                  : null,
                          emptyState:
                              q.isEmpty
                                  ? const _EmptyState()
                                  : _EmptyState.search(query: _query),
                        ),
                        _PrettyListView(
                          items: unreadOnly,
                          itemBuilder: (c) => _buildChatItem(c),
                          emptyState:
                              q.isEmpty
                                  ? const _EmptyState.unread()
                                  : _EmptyState.unreadSearch(query: _query),
                        ),
                        _PrettyListView(
                          items: urgentOnly,
                          itemBuilder: (c) => _buildChatItem(c),
                          emptyState: const _EmptyState.urgent(),
                        ),
                      ],
                    ),
          ),
        ),
      ),
    );
  }
}

/* ---------- Search Field ---------- */
class _SearchField extends StatefulWidget {
  final ValueChanged<String> onChanged;
  const _SearchField({required this.onChanged});

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  final controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(Icons.search, color: AppColors.textTertiary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: '채팅 검색',
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              onChanged: (v) {
                widget.onChanged(v);
                setState(() {});
              },
            ),
          ),
          if (controller.text.isNotEmpty)
            IconButton(
              tooltip: '닫기',
              onPressed: () {
                controller.clear();
                widget.onChanged('');
                setState(() {});
              },
              icon: const Icon(
                Icons.close,
                size: 18,
                color: AppColors.textTertiary,
              ),
            ),
        ],
      ),
    );
  }
}

/* ---------- Badge Tab ---------- */
class _BadgeTab extends StatelessWidget {
  final String label;
  final int count;
  const _BadgeTab({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (count > 0) ...[
            const SizedBox(width: 5),
            Text(
              count > 99 ? '99+' : '$count',
              style: const TextStyle(
                fontSize: AppFontSize.body2,
                fontWeight: FontWeight.w700,
                color: AppColors.badgeUrgent,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/* ---------- Tab Header Delegate ---------- */
class _TabHeaderDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _TabHeaderDelegate(this.tabBar);

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: AppColors.bgCard,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: tabBar,
    );
  }

  @override
  double get maxExtent => 48;

  @override
  double get minExtent => 48;

  @override
  bool shouldRebuild(covariant _TabHeaderDelegate oldDelegate) => false;
}

/* ---------- Pretty ListView Wrapper ---------- */
class _PrettyListView extends StatelessWidget {
  final List<dynamic> items;
  final Widget Function(Map chat) itemBuilder;
  final Widget emptyState;
  final Widget? afterFirst;
  const _PrettyListView({
    required this.items,
    required this.itemBuilder,
    this.emptyState = const _EmptyState(),
    this.afterFirst,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return emptyState;
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 120),
      itemBuilder: (_, i) {
        // 배너는 세 번째 대화 뒤 — 첫 대화 바로 뒤에 끼면 흐름이 끊겼다. 대화가 3개 미만이면 맨 끝
        final slot = items.length < 3 ? items.length : 3;
        if (afterFirst != null && i == slot) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: afterFirst!,
          );
        }
        final itemIndex = afterFirst != null && i > slot ? i - 1 : i;
        final chat = items[itemIndex] as Map;
        return AppFadeSlideIn(
          key: ValueKey('room_in_${chat['id']}'),
          index: itemIndex,
          child: itemBuilder(chat),
        );
      },
      itemCount: items.length + (afterFirst == null ? 0 : 1),
    );
  }
}

/* ---------- Empty State ---------- */
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyState()
    : icon = Icons.chat_bubble_outline,
      title = '지원하면 채팅이 열려요',
      message = '마음에 드는 공고에 지원하면 사장님과 바로 대화를 시작할 수 있어요.';

  const _EmptyState.search({required String query})
    : icon = Icons.search_off_rounded,
      title = '검색 결과가 없어요',
      message = '"$query"와 일치하는 채팅이 없어요.';

  const _EmptyState.unread()
    : icon = Icons.mark_chat_read_outlined,
      title = '안읽은 채팅이 없어요',
      message = '확인하지 않은 새 메시지가 생기면 여기에 모입니다.';

  const _EmptyState.urgent()
    : icon = Icons.flash_on_rounded,
      title = '긴급호출 채팅이 없어요',
      message = '사장님이 긴급 호출을 보내면 여기에 모입니다.';

  const _EmptyState.unreadSearch({required String query})
    : icon = Icons.search_off_rounded,
      title = '안읽은 채팅 검색 결과가 없어요',
      message = '"$query"와 일치하는 안읽은 채팅이 없어요.';

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(icon: icon, title: title, message: message);
  }
}

class _ChatActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _ChatActionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: onTap != null,
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconColor, size: 21),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: AppFontSize.body1,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          fontSize: AppFontSize.body2,
          color: AppColors.textSecondary,
          height: 1.35,
        ),
      ),
      trailing: trailing,
      onTap: onTap,
    );
  }
}

class CancelApplicationDialog extends StatelessWidget {
  const CancelApplicationDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 상단 아이콘 + 타이틀
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.warning_rounded,
                    color: AppColors.error,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        '지원 취소하시겠어요?',
                        style: TextStyle(
                          fontSize: AppFontSize.buttonLg,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '이 공고에 대한 지원이 취소되며,\n다시 지원하려면 새로 지원해야 할 수 있어요.',
                        style: TextStyle(
                          fontSize: AppFontSize.body2,
                          height: 1.4,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // 서브 정보/노트
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.bgPage,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: const [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: AppColors.textTertiary,
                  ),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '취소 이후에는 채팅만 남고,\n해당 공고와의 매칭은 해제됩니다.',
                      style: TextStyle(
                        fontSize: AppFontSize.meta,
                        height: 1.4,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 버튼 두 개 (세로 정렬)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                    ),
                    onPressed: () {
                      Navigator.of(context).pop(true);
                    },
                    child: const Text(
                      '네, 지원을 취소할게요'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).pop(false);
                    },
                    child: const Text(
                      '그냥 둘게요',
                      style: TextStyle(
                        fontSize: AppFontSize.button,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
