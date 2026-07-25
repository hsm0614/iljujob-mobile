// lib/presentation/chat/chat_room_screen.dart
//
// 채팅방 화면 — build() 전담.
// 모든 상태/로직은 ChatRoomController에 있음.

import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:iljujob/config/constants.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:iljujob/data/models/job.dart';
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
  bool _jobPanelExpanded = true;

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

      ctrl.onScrollToBottom = () => _scrollToBottom();

      ctrl.onPopScreen = () {
        if (mounted) Navigator.of(context).maybePop();
      };

      ctrl.onShowEvaluationDialog = () => _showEvaluationDialog(ctrl);

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
    final jobId = int.tryParse(
      jobSource['id']?.toString() ?? jobSource['job_id']?.toString() ?? '',
    );
    final workerId = ctrl.roomWorkerId;
    final clientId = ctrl.roomClientId;
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
      builder:
          (_) => ProposeWorkConfirmationSheet(
            chatRoomId: ctrl.chatRoomId,
            jobId: jobId,
            workerId: workerId,
            clientId: clientId,
            jobLocation: jobSource['location']?.toString(),
            defaultWage: int.tryParse(
              (jobSource['pay'] ??
                      jobSource['hourly_wage'] ??
                      jobSource['wage'] ??
                      '')
                  .toString()
                  .replaceAll(RegExp(r'[^0-9]'), ''),
            ),
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
  // 평가 다이얼로그 (별점 + 태그)
  // ─────────────────────────────────────────────

  Future<void> _showEvaluationDialog(ChatRoomController ctrl) async {
    if (!mounted) return;

    final isClient = ctrl.userType == 'client';
    final title = isClient ? '이번 알바생은 어땠나요?' : '이번 사장님은 어땠나요?';
    final goodTags =
        isClient
            ? ['시간 약속 잘 지킴', '일 잘함', '매너 좋음', '소통 원활']
            : ['급여 제때 지급', '친절한 안내', '근무 환경 좋음', '약속 잘 지킴'];
    final badTags =
        isClient
            ? ['지각/무단결근', '불성실한 태도', '연락 불가', '업무 미숙']
            : ['급여 지연', '불친절', '과도한 업무', '약속 불이행'];

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        double rating = 5.0;
        final Set<String> selectedTags = {};
        bool sending = false;

        return StatefulBuilder(
          builder: (ctx, setState) {
            final isGood = rating >= 4.0;
            final tags = isGood ? goodTags : badTags;

            Future<void> submit() async {
              if (sending) return;
              setState(() => sending = true);
              try {
                await ctrl.submitEvaluation(isGood: isGood);
                if (ctx.mounted) Navigator.of(ctx).pop();
              } catch (_) {
                if (ctx.mounted) setState(() => sending = false);
              }
            }

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B8AFF).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.rate_review_rounded,
                        size: 28,
                        color: Color(0xFF3B8AFF),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '솔직한 평가가 더 나은 매칭을 만들어요',
                      style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                    ),
                    const SizedBox(height: 20),

                    // ── 별점 ──
                    RatingBar.builder(
                      initialRating: rating,
                      minRating: 1,
                      direction: Axis.horizontal,
                      allowHalfRating: false,
                      itemCount: 5,
                      itemSize: 36,
                      itemPadding: const EdgeInsets.symmetric(horizontal: 4),
                      itemBuilder:
                          (_, __) => const Icon(
                            Icons.star_rounded,
                            color: Color(0xFFFFC107),
                          ),
                      onRatingUpdate:
                          (r) => setState(() {
                            rating = r;
                            selectedTags.clear();
                          }),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _ratingLabel(rating),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color:
                            isGood
                                ? const Color(0xFF10B981)
                                : const Color(0xFFEF4444),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── 태그 ──
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children:
                          tags.map((tag) {
                            final active = selectedTags.contains(tag);
                            return GestureDetector(
                              onTap:
                                  () => setState(() {
                                    active
                                        ? selectedTags.remove(tag)
                                        : selectedTags.add(tag);
                                  }),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 120),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      active
                                          ? (isGood
                                              ? const Color(0xFF3B8AFF)
                                              : const Color(0xFFEF4444))
                                          : const Color(0xFFF3F4F6),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(
                                  tag,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        active
                                            ? Colors.white
                                            : const Color(0xFF6B7280),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                    ),
                    const SizedBox(height: 20),

                    // ── 버튼 ──
                    if (sending)
                      const SizedBox(
                        height: 44,
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3B8AFF),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text(
                            '평가 제출',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text(
                        '나중에 할게요',
                        style: TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _ratingLabel(double r) {
    if (r >= 5) return '최고예요!';
    if (r >= 4) return '좋았어요';
    if (r >= 3) return '보통이에요';
    if (r >= 2) return '아쉬웠어요';
    return '별로였어요';
  }

  // ─────────────────────────────────────────────
  // 캘린더 추가 다이얼로그
  // ─────────────────────────────────────────────

  Future<void> _showAddToCalendarDialog(WorkConfirmation conf) async {
    if (!mounted) return;
    final fmt = NumberFormat('#,###');

    await showDialog<void>(
      context: context,
      builder:
          (ctx) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B8AFF).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.calendar_today_rounded,
                          color: Color(0xFF3B8AFF),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '캘린더에서 확인할까요?',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              '앱 내 캘린더에서 근무 일정을 확인해요',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F6FA),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        _CalRow(
                          icon: Icons.business_rounded,
                          text: conf.companyName ?? '사장님',
                        ),
                        const SizedBox(height: 6),
                        _CalRow(
                          icon: Icons.event_rounded,
                          text: conf.workDate.split('T').first,
                        ),
                        const SizedBox(height: 6),
                        _CalRow(
                          icon: Icons.access_time_rounded,
                          text:
                              '${conf.startTime.substring(0, 5)} ~ ${conf.endTime.substring(0, 5)}',
                        ),
                        if (conf.location != null) ...[
                          const SizedBox(height: 6),
                          _CalRow(
                            icon: Icons.location_on_rounded,
                            text: conf.location!,
                          ),
                        ],
                        const SizedBox(height: 6),
                        _CalRow(
                          icon: Icons.payments_rounded,
                          text: '시급 ${fmt.format(conf.hourlyWage)}원',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF6B7280),
                            side: const BorderSide(color: Color(0xFFE5E7EB)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text(
                            '나중에',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _addToCalendar(conf);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3B8AFF),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text(
                            '캘린더 보기',
                            style: TextStyle(fontWeight: FontWeight.w800),
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
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            content: const Text(
              '해당 알바생이 출근하지 않았나요?\n노쇼 처리 시 알바생 신뢰도 점수가 크게 감소합니다.',
              style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  '취소',
                  style: TextStyle(color: Color(0xFF6B7280)),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  '노쇼 확정',
                  style: TextStyle(
                    color: Color(0xFFEF4444),
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
                      color: const Color(0xFFE5E7EB),
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
                        color: Color(0xFFEF4444),
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
                              fontSize: 16,
                              color: Color(0xFF191F28),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            '즉시게시 이용권 1개가 자동 환급됩니다.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF6B7280),
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
                      gradient: const LinearGradient(
                        colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFFEF4444,
                          ).withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
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
                            fontSize: 15,
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
                        color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
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
      final prefs = await SharedPreferences.getInstance();
      final token =
          prefs.getString('authToken') ?? prefs.getString('accessToken') ?? '';
      final resp = await http.patch(
        Uri.parse('$baseUrl/api/direct-message/$logId/respond'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'status': status}),
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
                      ? const Color(0xFF22C55E)
                      : const Color(0xFF6B7280),
            ),
          );
      }
    } catch (_) {}
    if (mounted) setState(() => _urgentCallBusy = false);
  }

  // 상대가 알림을 못 받는 상태 안내. 회색 톤으로 조용히 — 경고가 아니라 정보.
  Widget _buildPeerUnreachableBanner(ChatRoomController ctrl) {
    final peer = ctrl.userType == 'worker' ? '사장님' : '알바생';
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E8EB)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.notifications_off_outlined,
            size: 16,
            color: Color(0xFF6B7280),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$peer이 알림을 꺼둔 상태라 확인이 늦을 수 있어요.',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUrgentCallBanner(ChatRoomController ctrl) {
    final isUrgent =
        widget.jobInfo['is_urgent_call'] == 1 ||
        widget.jobInfo['is_urgent_call'] == true;
    if (!isUrgent || ctrl.userType != 'worker') return const SizedBox.shrink();
    if (_urgentCallStatus == 'accepted') {
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFDCFCE7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF86EFAC)),
        ),
        child: const Row(
          children: [
            Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF22C55E),
              size: 18,
            ),
            SizedBox(width: 8),
            Text(
              '긴급호출 수락 완료',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF15803D),
              ),
            ),
          ],
        ),
      );
    }
    if (_urgentCallStatus == 'rejected') {
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            Icon(Icons.block_rounded, color: Color(0xFF9CA3AF), size: 18),
            SizedBox(width: 8),
            Text(
              '긴급호출을 거절했어요.',
              style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
            ),
          ],
        ),
      );
    }
    if (_urgentCallStatus != 'sent') return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6B1A), Color(0xFFFF9500)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF9500).withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text('⚡', style: TextStyle(fontSize: 15)),
              SizedBox(width: 6),
              Text(
                '긴급 호출이 왔어요!',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '사장님이 지금 바로 일할 분을 찾고 있어요.\n수락하면 바로 연결됩니다.',
            style: TextStyle(fontSize: 12, color: Colors.white70, height: 1.4),
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: const Text(
                    '거절',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
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
                    foregroundColor: const Color(0xFFFF6B1A),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child:
                      _urgentCallBusy
                          ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFFFF6B1A),
                            ),
                          )
                          : const Text(
                            '수락하기',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
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
                    style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
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
          backgroundColor: AppColors.bgPage,

          // ── 앱바
          appBar: AlbailjuAppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context, 'updated'),
            ),
            titleWidget: Row(
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
                    hasPendingWorkConfirmation: ctrl.hasPendingWorkConfirmation,
                    workConfirmationStatus: ctrl.openWorkConfirmation?.status,
                    status: ctrl.status,
                    onConfirmHire: ctrl.confirmHire,
                    onProposeWorkConfirmation: () => _showProposeSheet(ctrl),
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

              // 상대가 알림을 못 받는 상태면 안내 — 답장해도 상대가 못 볼 수 있음
              if (ctrl.peerReachable == false) _buildPeerUnreachableBanner(ctrl),

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
                                  showHireNudge:
                                      ctrl.userType == 'client' &&
                                      !ctrl.isConfirmed &&
                                      !ctrl.hasPendingWorkConfirmation &&
                                      ctrl.status == 'active' &&
                                      ctrl.messages.length >= 2,
                                  onConfirmHire: () => _showProposeSheet(ctrl),
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
                                      textInputAction:
                                          TextInputAction.newline,
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
                                          color: AppColors.textTertiary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
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

// ─────────────────────────────────────────────
// 캘린더 다이얼로그용 행 위젯
// ─────────────────────────────────────────────

class _CalRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _CalRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 14, color: const Color(0xFF3B8AFF)),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF374151),
            fontWeight: FontWeight.w500,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}
