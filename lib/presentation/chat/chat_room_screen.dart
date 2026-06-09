// lib/presentation/chat/chat_room_screen.dart
//
// 채팅방 화면 — build() 전담.
// 모든 상태/로직은 ChatRoomController에 있음.

import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:iljujob/data/models/job.dart';
import 'package:iljujob/config/app_theme.dart';
import 'package:iljujob/presentation/screens/worker_screen/job_detail_screen.dart';
import 'package:iljujob/utiles/keyboard_mode.dart';

import 'chat_room_controller.dart';
import 'chat_room_components.dart';
import 'chat_room_job_panel.dart';
import 'message_list.dart';
import 'chat_room_helpers.dart';
import 'work_confirmation_card.dart';
import '../../data/services/work_confirmation_service.dart';

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
  bool _jobPanelExpanded = true;

  @override
  void initState() {
    super.initState();
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

      ctrl.onScrollToBottom = () => _scrollToBottom();

      ctrl.onPopScreen = () {
        if (mounted) Navigator.of(context).maybePop();
      };

      ctrl.onShowEvaluationDialog = () => _showEvaluationDialog(ctrl);

      ctrl.onShowCalendarBlockedDialog =
          () => _showCancelBlockedByCalendarDialog(ctrl);

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

  void _scrollToBottom({bool initial = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      final max = position.maxScrollExtent;

      if (initial) {
        final contentHeight = max + position.viewportDimension;
        if (contentHeight <= position.viewportDimension * 1.1) {
          _scrollController.jumpTo(position.minScrollExtent);
          return;
        }
      }
      _scrollController.animateTo(
        max,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  // ─────────────────────────────────────────────
  // 이미지 전송
  // ─────────────────────────────────────────────

  Future<void> _pickAndSendImage(ChatRoomController ctrl) async {
    if (!ctrl.inputEnabled) {
      ctrl.onShowSnackbar?.call('아직 채팅이 활성화되지 않았습니다.');
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
    final jobId     = int.tryParse(jobSource['id']?.toString() ?? jobSource['job_id']?.toString() ?? '');
    final workerId  = ctrl.roomWorkerId;
    final clientId  = ctrl.roomClientId;
    if (jobId == null || workerId == null || clientId == null) {
      ctrl.onShowSnackbar?.call('채팅방 정보를 불러오는 중입니다.');
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
      builder: (_) => ProposeWorkConfirmationSheet(
        chatRoomId: ctrl.chatRoomId,
        jobId: jobId,
        workerId: workerId,
        clientId: clientId,
        jobLocation: jobSource['location']?.toString(),
        onPropose: (_) {
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
      if (rawId != null && rawId.isNotEmpty) {
        _navigatingToDetail = true;
        await Navigator.pushNamed(context, '/job-detail', arguments: rawId);
      } else {
        ctrl.onShowSnackbar?.call('공고 상세를 열 수 없습니다.');
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

  Widget _buildJobPanelHandle(ChatRoomController ctrl, String jobTitle) {
    final title =
        jobTitle.isNotEmpty
            ? jobTitle
            : (ctrl.jobSource['title'] ?? ctrl.jobSource['job_title'] ?? '공고')
                .toString();

    return Material(
      color: AppColors.bgCard,
      child: InkWell(
        onTap: () => setState(() => _jobPanelExpanded = !_jobPanelExpanded),
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.borderSub, width: 1),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.work_outline_rounded,
                size: 17,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _jobPanelExpanded ? '접기' : '공고 보기',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              Icon(
                _jobPanelExpanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: AppColors.primary,
              ),
            ],
          ),
        ),
      ),
    );
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
  // 평가 다이얼로그
  // ─────────────────────────────────────────────

  Future<void> _showEvaluationDialog(ChatRoomController ctrl) async {
    if (!mounted) return;

    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        bool sending = false;
        return StatefulBuilder(
          builder: (ctx, setState) {
            Future<void> press(bool isGood) async {
              if (sending) return;
              setState(() => sending = true);
              try {
                await ctrl.submitEvaluation(isGood: isGood);
                if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop(true);
              } catch (_) {
                if (mounted) setState(() => sending = false);
              }
            }

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.rate_review_rounded,
                      size: 48,
                      color: Color(0xFF1675F4),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '이번 알바생은 어땠나요?',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '매너 좋은 알바였나요, 아니면 문제가 있었나요?',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    if (sending) ...[
                      const CircularProgressIndicator(),
                      const SizedBox(height: 14),
                      const Text(
                        '전송 중...',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                              onPressed: () => press(true),
                              icon: const Icon(
                                Icons.thumb_up,
                                color: Colors.white,
                              ),
                              label: const Text(
                                '좋았어요',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                              onPressed: () => press(false),
                              icon: const Icon(
                                Icons.thumb_down,
                                color: Colors.white,
                              ),
                              label: const Text(
                                '별로였어요',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('나중에 할게요'),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
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
                        color: Color(0xFF2563EB),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '이미 캘린더에 등록된 일정이에요',
                          style: TextStyle(
                            fontSize: 16,
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
                      fontSize: 13,
                      height: 1.4,
                      color: Color(0xFF4B5563),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFE5E7EB)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text(
                            '닫기',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF374151),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3B8AFF),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text(
                            '캘린더로 이동',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x143B8AFF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'T I P',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF3B8AFF),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                isClient ? '여기서 첫 채용 대화를 시작해 보세요' : '여기서 첫 인사를 남겨보세요',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 6),
              RichText(
                text: TextSpan(
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Color(0xFF4B5563),
                  ),
                  children: [
                    TextSpan(text: isClient ? '사장님께 ' : '상대방에게 '),
                    const TextSpan(
                      text: '자기소개와 장점',
                      style: TextStyle(
                        color: Color(0xFF3B8AFF),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const TextSpan(text: '을 함께 첫 메시지로 보내면\n채용 확률이 더 높아져요.'),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(
                    Icons.bolt_rounded,
                    size: 14,
                    color: Color(0xFF9CA3AF),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    '알바일주 데이터 기준',
                    style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      _scrollToBottom();
                      _inputFocusNode.requestFocus();
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor: const Color(0xFF3B8AFF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    icon: const Icon(Icons.edit_rounded, size: 14),
                    label: const Text(
                      '첫 메시지 쓰기',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
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

    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, 'updated');
        return false;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          backgroundColor: AppColors.bgPage,

          // ── 앱바
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0.5,
            foregroundColor: Colors.black87,
            titleSpacing: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context, 'updated'),
            ),
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: onProfileTap ?? () {},
                  child: CircleAvatar(
                    radius: 18,
                    backgroundImage:
                        (targetThumbnailUrl != null &&
                                targetThumbnailUrl.isNotEmpty)
                            ? NetworkImage(targetThumbnailUrl)
                            : null,
                    child:
                        (targetThumbnailUrl == null ||
                                targetThumbnailUrl.isEmpty)
                            ? const Icon(Icons.person)
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
                _buildJobPanelHandle(ctrl, jobTitle),
                if (_jobPanelExpanded)
                  ChatRoomJobPanel(
                    jobSource: ctrl.jobSource,
                    userType: ctrl.userType,
                    isConfirmed: ctrl.isConfirmed,
                    isCompleted: ctrl.isCompleted,
                    status: ctrl.status,
                    onConfirmHire: ctrl.confirmHire,
                    onMarkCompleted: ctrl.markJobAsCompleted,
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

              // 메시지 영역
              Expanded(
                child: Stack(
                  children: [
                    // 메시지 목록
                    Positioned.fill(
                      child:
                          ctrl.isLoading
                              ? const Center(child: CircularProgressIndicator())
                              : ctrl.messages.isEmpty
                              ? _buildEmptyChatNotice(ctrl.isClient)
                              : NotificationListener<ScrollStartNotification>(
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
                                  showHireNudge: ctrl.shouldShowHireNudge(),
                                  onConfirmHire: ctrl.confirmHire,
                                  inputOverlayHeight: 112,
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
                                      onTapOutside:
                                          (_) =>
                                              FocusScope.of(context).unfocus(),
                                      decoration: InputDecoration(
                                        border: InputBorder.none,
                                        hintText:
                                            ctrl.inputEnabled
                                                ? '메시지를 입력하세요...'
                                                : (ctrl.status == 'pending'
                                                    ? '상대방의 수락을 기다리는 중입니다'
                                                    : (ctrl.status ==
                                                                'cancelled' ||
                                                            ctrl.status ==
                                                                'canceled'
                                                        ? (ctrl.userType ==
                                                                'client'
                                                            ? '알바생이 지원을 취소한 채팅입니다'
                                                            : '지원 취소 후에는 채팅을 보낼 수 없습니다')
                                                        : '지금은 채팅을 보낼 수 없습니다')),
                                        hintStyle: const TextStyle(
                                          fontSize: 14,
                                          color: Color(0xFF9CA3AF),
                                        ),
                                      ),
                                      onSubmitted: (_) => _sendMessage(ctrl),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                // 출근 확정 제안 (사장님 전용)
                                if (ctrl.isClient && ctrl.inputEnabled)
                                  IconButton(
                                    icon: const Icon(Icons.calendar_month_rounded),
                                    color: AppColors.primary,
                                    tooltip: '출근 확정 제안',
                                    onPressed: () => _showProposeSheet(ctrl),
                                  ),
                                IconButton(
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
                                GestureDetector(
                                  onTap:
                                      ctrl.inputEnabled
                                          ? () => _sendMessage(ctrl)
                                          : null,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color:
                                          ctrl.inputEnabled
                                              ? AppColors.primary
                                              : AppColors.textDisabled,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.send_rounded,
                                      size: 18,
                                      color: Colors.white,
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
