// lib/presentation/chat/chat_room_screen.dart
//
// 채팅방 화면 — build() 전담.
// 모든 상태/로직은 ChatRoomController에 있음.

import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:iljujob/widget/app_motion.dart';
import 'package:iljujob/utils/chat_stage.dart';
import 'package:iljujob/config/constants.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:iljujob/data/models/job.dart';
import 'package:iljujob/data/services/authenticated_http_client.dart';
import 'package:iljujob/config/app_theme.dart';
import 'package:iljujob/presentation/widgets/albailju_common.dart';
import 'package:iljujob/presentation/screens/worker_screen/job_detail_screen.dart';
import 'package:iljujob/data/services/screen_analytics_service.dart';
import 'package:iljujob/utiles/keyboard_mode.dart';

import 'chat_room_controller.dart';
import 'chat_room_components.dart';
import 'chat_room_job_panel.dart';
import 'message_list.dart';
import 'chat_room_helpers.dart';
import 'work_confirmation_card.dart';
import '../../data/services/work_confirmation_service.dart';
import '../screens/worker_calendar_screen.dart';

class ChatRoomScreen extends StatelessWidget {
  final int chatRoomId;
  final Map<String, dynamic> jobInfo;

  const ChatRoomScreen({
    super.key,
    required this.chatRoomId,
    required this.jobInfo,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create:
          (_) => ChatRoomController(chatRoomId: chatRoomId, jobInfo: jobInfo),
      child: _ChatRoomView(jobInfo: jobInfo),
    );
  }
}

// ─────────────────────────────────────────────
// 실제 화면
// ─────────────────────────────────────────────

class _ChatRoomView extends StatefulWidget {
  final Map<String, dynamic> jobInfo;
  const _ChatRoomView({required this.jobInfo});

  @override
  State<_ChatRoomView> createState() => _ChatRoomViewState();
}

class _ChatRoomViewState extends State<_ChatRoomView> {
  final _scrollController = ScrollController();
  final _messageController = TextEditingController();
  final _inputFocusNode = FocusNode();
  /// 위로 올려 읽는 중에 새 메시지가 도착했는지. 자동 스크롤을 막는 대신
  /// "새 메시지" 버튼으로 알린다.
  bool _hasNewBelow = false;

  // 긴급호출 수락/거절 상태 (worker 전용)
  String? _urgentCallStatus;
  bool _urgentCallBusy = false;

  @override
  void initState() {
    super.initState();
    ScreenAnalyticsService.instance.logScreenView('chat_room');
    _urgentCallStatus = widget.jobInfo['direct_message_status']?.toString();
    KeyboardMode.setAdjustResize();

    // 컨트롤러에 UI 콜백 주입
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctrl = context.read<ChatRoomController>();

      ctrl.onShowSnackbar = (msg) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(msg)));
      };

      ctrl.onScrollToBottom =
          ({bool force = false}) => _scrollToBottom(force: force);

      ctrl.onPopScreen = () {
        if (mounted) Navigator.of(context).maybePop();
      };


      ctrl.onShowCalendarBlockedDialog =
          () => _showCancelBlockedByCalendarDialog(ctrl);

      ctrl.onWorkConfirmationAccepted =
          (conf) => _showAddToCalendarDialog(conf);

      ctrl.init();
    });
  }

  @override
  void dispose() {
    KeyboardMode.setAdjustPan();
    _scrollController.dispose();
    _messageController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // 스크롤
  // ─────────────────────────────────────────────

  /// 목록이 reverse: true 라 "맨 아래"는 offset 0 이다.
  /// 최신 메시지가 바닥에 붙어 있으므로 첫 진입엔 스크롤할 것도 없다.
  static const _nearBottomPx = 120.0;

  void _scrollToBottom({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;

      // 지난 대화를 읽는 중이면 끌어내리지 않는다. 예전엔 상대 메시지가 올 때마다
      // 조건 없이 바닥으로 당겨서, 위로 올려 읽던 사람이 계속 튕겨 내려갔다.
      // 내가 보낸 직후엔 이미 바닥이라 이 조건을 자연히 통과한다.
      if (!force && position.pixels > _nearBottomPx) {
        // 안 내려간다고 조용히 넘어가면 새 메시지가 온 줄도 모른다.
        // 아래에 새 글이 있다는 표시를 띄워 준다.
        if (!_hasNewBelow && mounted) setState(() => _hasNewBelow = true);
        return;
      }

      if (_hasNewBelow && mounted) setState(() => _hasNewBelow = false);
      _scrollController.animateTo(
        position.minScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  /// 바닥 근처로 돌아오면 "새 메시지" 표시를 거둔다.
  bool _onScrollUpdate(ScrollUpdateNotification n) {
    if (_hasNewBelow && n.metrics.pixels <= _nearBottomPx) {
      setState(() => _hasNewBelow = false);
    }
    return false;
  }

  // ─────────────────────────────────────────────
  // 이미지 전송
  // ─────────────────────────────────────────────

  Future<void> _pickAndSendImage(ChatRoomController ctrl) async {
    if (!ctrl.inputEnabled) {
      ctrl.onShowSnackbar?.call('아직 채팅이 열리지 않았어요.');
      return;
    }
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    final imageFile = File(pickedFile.path);
    final shouldSend = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('이미지 전송'),
            content: Image.file(imageFile, height: 250),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('보내기'),
              ),
            ],
          ),
    );
    if (shouldSend != true) return;
    await ctrl.sendImage(imageFile);
  }

  // ─────────────────────────────────────────────
  // 메시지 전송
  // ─────────────────────────────────────────────

  Future<void> _showProposeSheet(ChatRoomController ctrl) async {
    final jobSource = ctrl.jobSource;
    final jobId = int.tryParse(
      jobSource['id']?.toString() ?? jobSource['job_id']?.toString() ?? '',
    );
    final workerId = ctrl.roomWorkerId;
    final clientId = ctrl.roomClientId;
    if (jobId == null || workerId == null || clientId == null) {
      ctrl.onShowSnackbar?.call('채팅방 정보를 불러오는 중이에요.');
      return;
    }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: Colors.white,
      builder:
          (_) => ProposeWorkConfirmationSheet(
            chatRoomId: ctrl.chatRoomId,
            jobId: jobId,
            workerId: workerId,
            clientId: clientId,
            jobLocation: jobSource['location']?.toString(),
            // 일급 공고의 급여(예: 41,280원)가 '시급' 칸에 들어가 시간을 곱한 예상 금액이
            // 터무니없이 나왔다(운영 카드 61건 중 31건이 2만 원 이상 '시급'). 시급 공고일 때만 채운다
            defaultWage:
                jobSource['pay_type']?.toString() == '시급'
                    ? int.tryParse(
                      (jobSource['pay'] ?? '').toString().replaceAll(
                        RegExp(r'[^0-9]'),
                        '',
                      ),
                    )
                    : null,
            defaultStartTime: jobSource['start_time']?.toString(),
            defaultEndTime: jobSource['end_time']?.toString(),
            weekdays: jobSource['weekdays']?.toString(),
            onPropose: (_) {
              ctrl.fetchWorkConfirmations();
              ctrl.onShowSnackbar?.call('출근 확정 제안을 보냈어요!');
            },
          ),
    );
  }

  Future<void> _sendMessage(ChatRoomController ctrl) async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId');
    if (userId == null) return;

    _messageController.clear();
    ctrl.sendMessage(content, userId);
  }

  // ─────────────────────────────────────────────
  // 공고 상세 이동
  // ─────────────────────────────────────────────

  bool _navigatingToDetail = false;

  void _openJobDetail(ChatRoomController ctrl) async {
    if (_navigatingToDetail) return;
    // 공고 상세 fetch(loadJobInfo)가 아직 안 끝났으면 기다린다 — 설명 없이 열리는 것 방지
    if (ctrl.jobSource['description'] == null) {
      await ctrl.loadJobInfo();
      if (!mounted) return;
    }
    final map = ctrl.jobSource;

    try {
      final normalized = _normalizeJobMap(map);
      final job = Job.fromJson(normalized);
      _navigatingToDetail = true;
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => JobDetailScreen(job: job)));
    } catch (e) {
      final rawId = map['id']?.toString();
      if (rawId != null && rawId.isNotEmpty && mounted) {
        _navigatingToDetail = true;
        await Navigator.pushNamed(context, '/job-detail', arguments: rawId);
      } else {
        ctrl.onShowSnackbar?.call('공고를 열 수 없어요.');
      }
    } finally {
      _navigatingToDetail = false;
    }
  }

  Map<String, dynamic> _normalizeJobMap(Map<String, dynamic> m) {
    dynamic pick(List keys) {
      for (final k in keys) {
        if (m[k] != null) return m[k];
      }
      return null;
    }

    String? str(dynamic v) => v?.toString();
    int? integer(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString().trim());
    }

    double? dbl(dynamic v) {
      if (v == null) return null;
      if (v is double) return v;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString().trim());
    }

    final idStr = str(pick(['id', 'job_id', 'jobId']));
    final clientId = integer(pick(['client_id', 'clientId']));
    final lat = dbl(pick(['lat', 'latitude']));
    final lng = dbl(pick(['lng', 'longitude', 'lon']));
    final startDate = parseDateLoose(pick(['start_date', 'startDate']));
    final endDate = parseDateLoose(pick(['end_date', 'endDate']));
    final startTime = str(pick(['start_time', 'startTime']));
    final endTime = str(pick(['end_time', 'endTime']));

    return {
      // 원본 필드 보존 — 아래 정규화 키만 덮어쓴다.
      // (예전엔 화이트리스트라 description·pay_type·category·이미지 등이 통째로 유실됐다)
      ...m,
      'id': idStr,
      'clientId': clientId,
      'client_id': clientId,
      'title': str(pick(['title'])),
      'company': str(pick(['client_company_name', 'company'])),
      'status': str(pick(['status'])),
      'pay': integer(pick(['pay', 'salary', 'wage'])) ?? 0,
      'location': str(pick(['location', 'address', 'addr'])),
      'location_city': str(pick(['location_city', 'locationCity', 'city'])),
      'locationCity': str(pick(['location_city', 'locationCity', 'city'])),
      'lat': lat,
      'lng': lng,
      'startDate': startDate,
      'endDate': endDate,
      'start_date': startDate,
      'end_date': endDate,
      'startTime': startTime,
      'endTime': endTime,
      'start_time': startTime,
      'end_time': endTime,
      'weekdays': str(pick(['weekdays'])),
      'thumbnailUrl': str(pick(['thumbnail_url', 'thumbnailUrl'])),
    };
  }

  // ─────────────────────────────────────────────
  // 캘린더 이동
  // ─────────────────────────────────────────────

  void _openWorkerCalendar(ChatRoomController ctrl) {
    final src = ctrl.jobSource;
    final jobId = int.tryParse(
      (src['id'] ?? src['job_id'] ?? src['jobId'])?.toString() ?? '',
    );
    final jobTitle = (src['title'] ?? src['job_title'] ?? '').toString().trim();
    Navigator.pushNamed(
      context,
      '/worker-calendar',
      arguments: {
        'focusJobId': jobId,
        'focusTitle': jobTitle,
        'fromChatRoom': true,
      },
    );
  }

  // ─────────────────────────────────────────────
  // 리뷰 이동
  // ─────────────────────────────────────────────

  void _goReview(ChatRoomController ctrl) {
    final src = ctrl.jobSource;
    final jobId = int.tryParse(
      (src['id'] ?? src['job_id'] ?? src['jobId'])?.toString() ?? '',
    );
    final clientId = int.tryParse(
      (src['client_id'] ?? src['clientId'])?.toString() ?? '',
    );
    final jobTitle = (src['title'] ?? src['job_title'] ?? '').toString().trim();
    final companyName =
        (src['client_company_name'] ?? src['company'] ?? '기업')
            .toString()
            .trim();

    if (jobId == null || clientId == null || jobTitle.isEmpty) {
      ctrl.onShowSnackbar?.call('리뷰에 필요한 공고 정보가 부족합니다.');
      return;
    }
    Navigator.pushNamed(
      context,
      '/review',
      arguments: {
        'jobId': jobId,
        'clientId': clientId,
        'jobTitle': jobTitle,
        'companyName': companyName,
      },
    );
  }

  // ─────────────────────────────────────────────
  // 캘린더 추가 다이얼로그
  // ─────────────────────────────────────────────

  /// 출근 확정 = 이 앱에서 가장 좋은 순간. 작은 팝업 대신 완료 화면 (2026-10)
  Future<void> _showAddToCalendarDialog(WorkConfirmation conf) async {
    if (!mounted) return;
    final fmt = NumberFormat('#,###');
    final day = DateTime.tryParse(conf.workDate.split('T').first);
    final r = await showAppSuccess(
      context,
      title: '출근이 확정됐어요',
      message: '근무 전날과 2시간 전에 알림으로 다시 알려드려요.',
      facts: [
        if (conf.companyName != null) ('근무지', conf.companyName!),
        (
          '날짜',
          day == null
              ? conf.workDate.split('T').first
              : DateFormat('M월 d일 (E)', 'ko_KR').format(day),
        ),
        (
          '시간',
          '${conf.startTime.substring(0, 5)} ~ ${conf.endTime.substring(0, 5)}',
        ),
        // 예전 카드는 일급이 '시급' 칸에 들어갔다 (work_confirmation_card.dart 참고)
        (
          conf.hourlyWage >= 20000 ? '급여' : '시급',
          '${fmt.format(conf.hourlyWage)}원',
        ),
      ],
      primaryLabel: '캘린더에서 보기',
      secondaryLabel: '채팅으로 돌아가기',
    );
    if (r == 'primary') _addToCalendar(conf);
  }

  void _addToCalendar(WorkConfirmation conf) {
    // 앱 내 캘린더로 이동 — work_confirmations는 이미 DB에 저장되어 있음
    final datePart = conf.workDate.split('T').first;
    final focusDay = DateTime.tryParse(datePart);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WorkerCalendarScreen(initialFocusDay: focusDay),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // 캘박 차단 다이얼로그
  // ─────────────────────────────────────────────

  Future<void> _showCancelBlockedByCalendarDialog(
    ChatRoomController ctrl,
  ) async {
    final go = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder:
          (_) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.event_available_rounded,
                        color: AppColors.primary,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '이미 캘린더에 등록된 일정이에요',
                          style: TextStyle(
                            fontSize: AppFontSize.buttonLg,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    ctrl.canCancel
                        ? '이 공고는 근무확정(캘박) 상태라 바로 지원 취소가 불가해요.\n먼저 "캘박 취소"를 하거나 캘린더에서 일정을 확인해 주세요.'
                        : '이 공고는 근무확정(캘박) 상태라 바로 지원 취소가 불가해요.\n현재는 취소 가능 시간이 지나 캘박 취소도 제한될 수 있어요.\n캘린더에서 일정을 확인해 주세요.',
                    style: const TextStyle(
                      fontSize: AppFontSize.body2,
                      height: 1.4,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text(
                            '닫기',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text(
                            '캘린더로 이동'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
    );

    if (go == true) {
      Future.microtask(() => _openWorkerCalendar(ctrl));
    }
  }

  // ─────────────────────────────────────────────
  // 지원 취소 확인 다이얼로그
  // ─────────────────────────────────────────────

  Future<void> _confirmNoShow(
    BuildContext context,
    ChatRoomController ctrl,
    WorkConfirmation confirm,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              '노쇼 신고',
              style: TextStyle(fontSize: AppFontSize.buttonLg, fontWeight: FontWeight.w700),
            ),
            content: const Text(
              '해당 알바생이 출근하지 않았나요?\n노쇼 처리 시 알바생 신뢰도 점수가 크게 감소합니다.',
              style: TextStyle(fontSize: AppFontSize.button, color: AppColors.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  '취소',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  '노쇼 확정',
                  style: TextStyle(
                    color: AppColors.urgentCall,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
    );
    if (confirmed == true) {
      await ctrl.respondToWorkConfirmation(confirm, 'no_show');
      if (!context.mounted) return;
      _showReplaceWorkerSheet(context, confirm);
    }
  }

  void _showReplaceWorkerSheet(BuildContext context, WorkConfirmation confirm) {
    final jobTitle =
        widget.jobInfo['title']?.toString() ??
        widget.jobInfo['job_title']?.toString() ??
        '공고';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (_) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: AppColors.urgentCall,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '노쇼 처리됐어요',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: AppFontSize.buttonLg,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            '즉시게시 이용권 1개가 자동 환급됩니다.',
                            style: TextStyle(
                              fontSize: AppFontSize.body2,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(
                      context,
                      '/nearby-workers',
                      arguments: {
                        'jobId': confirm.jobId,
                        'clientId': confirm.clientId,
                        'jobTitle': jobTitle,
                      },
                    );
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.urgentCall,
                      borderRadius: BorderRadius.circular(14),
                      
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.flash_on_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        SizedBox(width: 6),
                        Text(
                          '지금 바로 대체 알바생 찾기',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: AppFontSize.body1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      '나중에 하기',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                        fontSize: AppFontSize.button,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
    );
  }

  // ─────────────────────────────────────────────
  // 긴급호출 수락/거절 (알바생 전용)
  // ─────────────────────────────────────────────

  Future<void> _respondToUrgentCall(String status) async {
    final logId = widget.jobInfo['direct_message_log_id'];
    if (logId == null || _urgentCallBusy) return;
    setState(() => _urgentCallBusy = true);
    try {
      final resp = await AuthenticatedHttpClient.patchJson(
        Uri.parse('$baseUrl/api/direct-message/$logId/respond'),
        body: {'status': status},
      );
      if (resp.statusCode == 200) {
        setState(() => _urgentCallStatus = status);
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                status == 'accepted' ? '긴급호출을 수락했어요!' : '긴급호출을 거절했어요.',
              ),
              backgroundColor:
                  status == 'accepted'
                      ? AppColors.gradeB
                      : AppColors.textSecondary,
            ),
          );
      }
    } catch (_) {}
    if (mounted) setState(() => _urgentCallBusy = false);
  }

  // 상대가 알림을 못 받는 상태 안내. 회색 톤으로 조용히 — 경고가 아니라 정보.
  /// 상태 안내 한 줄 (2026-10). 테두리 상자 두 개가 쌓여 대화가 아래로 밀렸다 → 화면 폭 얇은 띠
  Widget _statusStrip(IconData icon, String text, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.bgMuted,
        border: Border(bottom: BorderSide(color: AppColors.borderSub)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.caption.copyWith(
                fontSize: AppFontSize.meta,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeerUnreachableBanner(ChatRoomController ctrl) {
    final peer = ctrl.userType == 'worker' ? '사장님' : '알바생';
    return _statusStrip(
      Icons.notifications_off_outlined,
      '$peer이 알림을 꺼둬서 확인이 늦을 수 있어요',
      AppColors.textSecondary,
    );
  }

  Widget _buildUrgentCallBanner(ChatRoomController ctrl) {
    final isUrgent =
        widget.jobInfo['is_urgent_call'] == 1 ||
        widget.jobInfo['is_urgent_call'] == true;
    if (!isUrgent || ctrl.userType != 'worker') return const SizedBox.shrink();
    if (_urgentCallStatus == 'accepted') {
      // '수락 완료'만 쓰면 출근까지 확정된 걸로 읽혔다 — 다음에 무엇을 기다리는지 말한다
      final proposals = ctrl.workConfirmations;
      final open = proposals.where(
        (c) => c.status == 'proposed' && !isWorkDatePast(c.workDate),
      );
      if (open.isNotEmpty) {
        return _statusStrip(
          Icons.event_available_rounded,
          '출근 제안이 왔어요 · 아래 카드에서 수락해 주세요',
          AppColors.badgeUrgent,
        );
      }
      // 근무 약속 카드가 이미 있으면 카드가 상태를 말한다
      if (proposals.isNotEmpty) return const SizedBox.shrink();
      return _statusStrip(
        Icons.hourglass_empty_rounded,
        '긴급호출에 응답했어요 · 사장님의 출근 제안을 기다리는 중',
        AppColors.textSecondary,
      );
    }
    if (_urgentCallStatus == 'rejected') {
      return _statusStrip(
        Icons.block_rounded,
        '긴급호출을 거절했어요',
        AppColors.textSecondary,
      );
    }
    if (_urgentCallStatus != 'sent') return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.urgentCall,
        borderRadius: BorderRadius.circular(14),
        
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bolt_rounded, size: 17, color: Colors.white),
              SizedBox(width: 6),
              Text(
                '긴급 호출이 왔어요!',
                style: TextStyle(
                  fontSize: AppFontSize.button,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '사장님이 지금 바로 일할 분을 찾고 있어요.\n수락하면 바로 연결됩니다.',
            style: TextStyle(fontSize: AppFontSize.meta, color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _urgentCallBusy
                          ? null
                          : () => _respondToUrgentCall('rejected'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                  child: const Text(
                    '거절'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed:
                      _urgentCallBusy
                          ? null
                          : () => _respondToUrgentCall('accepted'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.urgentCall,
                  ),
                  child:
                      _urgentCallBusy
                          ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.urgentCall,
                            ),
                          )
                          : const Text(
                            '수락하기'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmCancelApplication(ChatRoomController ctrl) async {
    if (ctrl.userType != 'worker') {
      ctrl.onShowSnackbar?.call('지원 취소는 구직자만 가능합니다.');
      return;
    }
    if (ctrl.hasWorkSession) {
      _showCancelBlockedByCalendarDialog(ctrl);
      return;
    }
    final confirmed =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const CancelApplicationDialog(),
        ) ??
        false;
    if (!confirmed) return;
    await ctrl.cancelApplication();
  }

  // ─────────────────────────────────────────────
  // 빈 채팅 안내
  // ─────────────────────────────────────────────

  Widget _buildEmptyChatNotice(bool isClient) {
    // TIP 알약·테두리 카드·근거 없는 '알바일주 데이터 기준'·파란 알약 버튼 → 글 두 줄 + 글자 버튼 하나.
    // 사장님 화면에 알바생용 문구('사장님께 자기소개와 장점')가 뜨던 것도 역할별로 나눴다.
    final greeting =
        isClient
            ? '안녕하세요, 지원해 주셔서 감사해요. 근무 가능하신지 여쭤봐도 될까요?'
            : '안녕하세요, 지원한 알바생입니다. 근무 가능해서 연락드려요.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isClient ? '먼저 인사를 건네 보세요' : '사장님께 먼저 인사해 보세요',
              textAlign: TextAlign.center,
              style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              isClient
                  ? '근무 가능 여부를 물어보면 답장이 빨라요'
                  : '출근 가능한 날과 비슷한 경험을 적으면 답장이 빨라요',
              textAlign: TextAlign.center,
              style: AppTextStyles.body2,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                if (_messageController.text.trim().isEmpty) _messageController.text = greeting;
                _scrollToBottom(force: true);
                _inputFocusNode.requestFocus();
              },
              child: const Text('인사말 넣기'),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // build
  // ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<ChatRoomController>();

    // 상대방 정보
    String? targetName;
    String? targetThumbnailUrl;
    VoidCallback? onProfileTap;

    if (ctrl.userType == 'client') {
      targetName = widget.jobInfo['user_name']?.toString();
      targetThumbnailUrl = widget.jobInfo['user_thumbnail_url']?.toString();
      final wId = int.tryParse(widget.jobInfo['worker_id']?.toString() ?? '');
      if (wId != null) {
        onProfileTap =
            () =>
                Navigator.pushNamed(context, '/worker-profile', arguments: wId);
      }
    } else {
      targetName = widget.jobInfo['client_company_name']?.toString() ?? '기업';
      targetThumbnailUrl = widget.jobInfo['client_thumbnail_url']?.toString();
      final cId = int.tryParse(widget.jobInfo['client_id']?.toString() ?? '');
      if (cId != null) {
        onProfileTap =
            () =>
                Navigator.pushNamed(context, '/client-profile', arguments: cId);
      }
    }

    final src = ctrl.jobSource;
    final jobTitle = (src['title'] ?? src['job_title'] ?? '').toString().trim();

    // PopScope: 결과 전달하면서 iOS 엣지 스와이프 뒤로가기 유지
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context, 'updated');
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          // 회색 바탕 위 회색 말풍선은 구분이 약했다 — 흰 바탕 (당근·토스 채팅)
          backgroundColor: AppColors.bgCard,

          // ── 앱바
          appBar: AlbailjuAppBar(
            leading: IconButton(
              tooltip: '뒤로',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context, 'updated'),
            ),
            // 문제가 생기는 자리는 채팅방인데 신고·차단은 상대 프로필에만 있었다.
            // 구현을 옮기지는 않고(프로필 화면이 이미 갖고 있다) 진입점만 연다.
            actions:
                onProfileTap == null
                    ? null
                    : [
                      PopupMenuButton<String>(
                        tooltip: '더보기',
                        icon: const Icon(Icons.more_vert),
                        onSelected: (_) => onProfileTap!(),
                        itemBuilder:
                            (_) => const [
                              PopupMenuItem(
                                value: 'report',
                                child: Row(
                                  children: [
                                    Icon(Icons.flag_outlined, size: 18),
                                    SizedBox(width: 10),
                                    Text('신고·차단'),
                                  ],
                                ),
                              ),
                            ],
                      ),
                    ],
            titleWidget: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: onProfileTap ?? () {},
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.bgMuted,
                    backgroundImage:
                        (targetThumbnailUrl != null &&
                                targetThumbnailUrl.isNotEmpty)
                            ? NetworkImage(targetThumbnailUrl)
                            : null,
                    child:
                        (targetThumbnailUrl == null ||
                                targetThumbnailUrl.isEmpty)
                            ? const Icon(
                              Icons.person_rounded,
                              color: AppColors.textDisabled,
                            )
                            : null,
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: AlbailjuChatAppBarTitle(
                    name: targetName ?? '상대방',
                    userType: ctrl.userType,
                    status: ctrl.status,
                    jobTitle: jobTitle,
                  ),
                ),
              ],
            ),
          ),

          // ── 바디
          body: Column(
            children: [
              // 공고 요약 패널
              if (!ctrl.isLoadingJobInfo) ...[
                // 접기 줄 없이 공고 카드 한 장 (2026-10 2차) — 카드가 작아 접을 이유가 없어졌다
                ChatRoomJobPanel(
                    jobSource: ctrl.jobSource,
                    userType: ctrl.userType,
                    isConfirmed: ctrl.isConfirmed,
                    isCompleted: ctrl.isCompleted,
                    hasPendingWorkConfirmation: ctrl.hasPendingWorkConfirmation,
                    workConfirmationStatus: ctrl.openWorkConfirmation?.status,
                    status: ctrl.status,
                    onConfirmHire: ctrl.confirmHire,
                    onProposeWorkConfirmation: () => _showProposeSheet(ctrl),
                    onMarkCompleted: ctrl.markJobAsCompleted,
                    onEvaluate:
                        ctrl.userType == 'client' && !ctrl.evaluatedByMe
                            ? (good) => ctrl.submitEvaluation(isGood: good).catchError((_) {})
                            : null,
                    workLoading: ctrl.workLoading,
                    hasWorkSession: ctrl.hasWorkSession,
                    canCancel: ctrl.canCancel,
                    checkedIn: ctrl.checkedIn,
                    checkinDistanceM: ctrl.checkinDistanceM,
                    checkinLoading: ctrl.checkinLoading,
                    hasReviewed: ctrl.hasReviewed,
                    workerWorkConfirmed: ctrl.workerWorkConfirmed,
                    onAddToCalendar: ctrl.addCurrentWorkToCalendar,
                    onOpenCalendar: () => _openWorkerCalendar(ctrl),
                    onCancelWorkSession: ctrl.cancelWorkSession,
                    onCheckin: ctrl.checkinNow,
                    onCancelApplication: () => _confirmCancelApplication(ctrl),
                    onGoReview: () => _goReview(ctrl),
                    onOpenJobDetail: () => _openJobDetail(ctrl),
                  ),
              ],

              // 배너들
              ChatRoomConsentBanner(
                show: ctrl.workerSeeConsentButtons,
                busy: ctrl.consentBusy,
                onAccept: () => ctrl.sendConsent(true),
                onReject: () => ctrl.sendConsent(false),
              ),
              ChatRoomWaitingBanner(show: ctrl.clientSeeWaitingBanner),
              ChatRoomCancelledBanner(
                show:
                    ctrl.userType == 'client' &&
                    (ctrl.status == 'cancelled' || ctrl.status == 'canceled'),
                onPostJob: () => Navigator.pushNamed(context, '/post_job'),
              ),

              // 상대가 알림을 못 받는 상태면 안내 — 답장해도 상대가 못 볼 수 있음
              if (ctrl.peerReachable == false)
                _buildPeerUnreachableBanner(ctrl),

              // 긴급호출 수락/거절 배너 (알바생 전용)
              _buildUrgentCallBanner(ctrl),

              // 메시지 영역
              Expanded(
                child: Stack(
                  children: [
                    // 메시지 목록
                    Positioned.fill(
                      child:
                          ctrl.isLoading
                              ? const Center(child: CircularProgressIndicator())
                              : ctrl.messages.isEmpty &&
                                  ctrl.workConfirmations.isEmpty
                              ? _buildEmptyChatNotice(ctrl.isClient)
                              : NotificationListener<ScrollUpdateNotification>(
                                onNotification: _onScrollUpdate,
                                child: NotificationListener<
                                  ScrollStartNotification
                                >(
                                  onNotification: (_) {
                                    FocusScope.of(context).unfocus();
                                    return false;
                                  },
                                  child: ChatMessageList(
                                    messages: ctrl.messages,
                                    scrollController: _scrollController,
                                    userType: ctrl.userType,
                                    onProfileTap: onProfileTap,
                                    targetThumbnailUrl: targetThumbnailUrl,
                                    targetName: targetName,
                                    showHireNudge:
                                        ctrl.userType == 'client' &&
                                        !ctrl.isConfirmed &&
                                        !ctrl.hasPendingWorkConfirmation &&
                                        ctrl.status == 'active' &&
                                        ctrl.messages.length >= 2,
                                    onConfirmHire:
                                        () => _showProposeSheet(ctrl),
                                    workConfirmations: ctrl.workConfirmations,
                                    onAcceptWorkConfirmation:
                                        (confirm) =>
                                            ctrl.respondToWorkConfirmation(
                                              confirm,
                                              'accepted',
                                            ),
                                    onRejectWorkConfirmation:
                                        (confirm) =>
                                            ctrl.respondToWorkConfirmation(
                                              confirm,
                                              'cancelled',
                                            ),
                                    onNoShowWorkConfirmation:
                                        (confirm) => _confirmNoShow(
                                          context,
                                          ctrl,
                                          confirm,
                                        ),
                                    onRetryMessage: ctrl.retryMessage,
                                    inputOverlayHeight: 112,
                                  ),
                                ),
                              ),
                    ),

                    // 위로 올려 읽는 중에 새 메시지가 오면 알려 준다.
                    // (자동 스크롤을 막아 놨으므로 이게 없으면 온 줄을 모른다)
                    if (_hasNewBelow)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 124,
                        child: Center(
                          child: Material(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(999),
                            elevation: 1,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(999),
                              onTap: () => _scrollToBottom(force: true),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '새 메시지',
                                      style: TextStyle(
                                        fontSize: AppFontSize.body2,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                    SizedBox(width: 4),
                                    Icon(
                                      Icons.arrow_downward_rounded,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                    // 입력창 (하단 오버레이)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ClipRect(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.92),
                              border: const Border(
                                top: BorderSide(
                                  color: AppColors.border,
                                  width: 0.5,
                                ),
                              ),
                            ),
                            padding: EdgeInsets.only(
                              left: 8,
                              right: 8,
                              top: 6,
                              bottom: MediaQuery.of(context).padding.bottom + 6,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.bgMuted,
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    child: TextField(
                                      controller: _messageController,
                                      focusNode: _inputFocusNode,
                                      enabled: ctrl.inputEnabled,
                                      minLines: 1,
                                      maxLines: 5,
                                      keyboardType: TextInputType.multiline,
                                      textInputAction: TextInputAction.newline,
                                      onTapOutside:
                                          (_) =>
                                              FocusScope.of(context).unfocus(),
                                      decoration: InputDecoration(
                                        filled: false,
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        disabledBorder: InputBorder.none,
                                        hintText:
                                            ctrl.inputEnabled
                                                ? '메시지 보내기'
                                                : (ctrl.status == 'pending'
                                                    ? '상대방의 수락을 기다리는 중이에요'
                                                    : (ctrl.status ==
                                                                'cancelled' ||
                                                            ctrl.status ==
                                                                'canceled'
                                                        ? (ctrl.userType ==
                                                                'client'
                                                            ? '알바생이 지원을 취소했어요'
                                                            : '지원을 취소해서 메시지를 보낼 수 없어요')
                                                        : '지금은 메시지를 보낼 수 없어요')),
                                        hintStyle: const TextStyle(
                                          fontSize: AppFontSize.button,
                                          color: AppColors.textTertiary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  tooltip: '사진 첨부',
                                  icon: const Icon(Icons.image),
                                  color:
                                      ctrl.inputEnabled
                                          ? AppColors.textSecondary
                                          : AppColors.textDisabled,
                                  onPressed:
                                      ctrl.inputEnabled
                                          ? () => _pickAndSendImage(ctrl)
                                          : null,
                                ),
                                const SizedBox(width: 2),
                                Material(
                                  color:
                                      ctrl.inputEnabled
                                          ? AppColors.primary
                                          : AppColors.textDisabled,
                                  shape: const CircleBorder(),
                                  child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap:
                                        ctrl.inputEnabled
                                            ? () => _sendMessage(ctrl)
                                            : null,
                                    child: const SizedBox(
                                      width: 44,
                                      height: 44,
                                      child: Icon(
                                        Icons.send_rounded,
                                        size: 20,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
