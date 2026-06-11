// lib/presentation/chat/chat_room_controller.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:uuid/uuid.dart';

import '../../config/constants.dart';
import '../../data/services/ai_api.dart';
import '../../data/services/work_confirmation_service.dart';
import 'chat_room_helpers.dart';

class ChatRoomController extends ChangeNotifier {
  final int chatRoomId;
  final Map<String, dynamic> jobInfo;

  ChatRoomController({required this.chatRoomId, required this.jobInfo});

  // ─────────────────────────────────────────────
  // dispose 가드
  // ─────────────────────────────────────────────

  bool _disposed = false;

  /// notifyListeners의 안전한 래퍼 — dispose 후 호출 방지
  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    socket?.clearListeners();
    socket?.disconnect();
    socket = null;
    // 콜백 참조 해제 (메모리 누수 방지)
    onShowSnackbar = null;
    onScrollToBottom = null;
    onSystemMessage = null;
    onShowEvaluationDialog = null;
    onWorkConfirmationAccepted = null;
    onPopScreen = null;
    onShowCalendarBlockedDialog = null;
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // 상태 변수
  // ─────────────────────────────────────────────

  List<Map<String, dynamic>> messages = [];
  bool isLoading = true;
  String userType = 'worker';
  IO.Socket? socket;

  bool isConfirmed = false;
  bool isCompleted = false;
  bool hasReviewed = false;
  List<WorkConfirmation> workConfirmations = [];

  Map<String, dynamic>? jobInfoDetail;
  bool isLoadingJobInfo = true;

  bool workerWorkConfirmed = false;
  bool workLoading = false;
  bool canCancel = false;
  String? workError;
  bool hasWorkSession = false;
  int? workSessionId;

  int? roomWorkerId;
  int? roomClientId;

  bool checkinLoading = false;
  bool checkedIn = false;
  int? checkinDistanceM;
  int? checkinRadiusM;

  double? myLat;
  double? myLng;
  double? myAcc;
  int? myDistanceToJobM;
  String? geoError;
  bool geoLoading = false;
  DateTime? lastGeoAt;

  String status = 'active';
  String initiator = 'client';
  bool consentBusy = false;

  final _uuid = const Uuid();

  // ─────────────────────────────────────────────
  // UI 콜백 (화면에서 주입)
  // ─────────────────────────────────────────────

  void Function(String)? onShowSnackbar;
  void Function()? onScrollToBottom;
  void Function(String)? onSystemMessage;
  void Function()? onShowEvaluationDialog;
  void Function()? onPopScreen;
  void Function()? onShowCalendarBlockedDialog;
  void Function(WorkConfirmation)? onWorkConfirmationAccepted;

  // ─────────────────────────────────────────────
  // 계산 프로퍼티
  // ─────────────────────────────────────────────

  bool get geoFresh {
    if (lastGeoAt == null) return false;
    return DateTime.now().difference(lastGeoAt!).inSeconds <= 30;
  }

  bool get isHireConfirmed => isConfirmed || workerWorkConfirmed;

  bool get hasOpenWorkConfirmation {
    return workConfirmations.any(
      (c) =>
          c.status == 'proposed' ||
          c.status == 'accepted' ||
          c.status == 'scheduled',
    );
  }

  bool get hasPendingWorkConfirmation {
    return workConfirmations.any((c) => c.status == 'proposed');
  }

  bool get inputEnabled {
    if (status == 'cancelled' ||
        status == 'canceled' ||
        status == 'blocked' ||
        status == 'expired') {
      return false;
    }
    if (userType == 'client' && status == 'pending') return false;
    return true;
  }

  bool get workerSeeConsentButtons =>
      userType == 'worker' && initiator == 'client' && status == 'pending';

  bool get clientSeeWaitingBanner =>
      userType == 'client' && status == 'pending';

  bool get isClient => userType == 'client';

  bool get isWeekdaysJob {
    final s =
        (jobSource['weekdays'] ??
                jobSource['weekday'] ??
                jobSource['days'] ??
                '')
            .toString()
            .trim();
    return s.isNotEmpty;
  }

  bool get isPaidJob {
    final src = jobSource;
    return asBool(src['is_paid']) ||
        asBool(src['isPaid']) ||
        src['is_paid'] == 1;
  }

  bool shouldShowHireNudge() {
    if (userType != 'client') return false;
    if (status != 'active') return false;
    if (isConfirmed) return false;
    if (messages.length < 4) return false;
    bool clientSpoke = false, workerSpoke = false;
    for (final m in messages) {
      final s = (m['sender'] ?? '').toString();
      if (s == 'client') clientSpoke = true;
      if (s == 'worker') workerSpoke = true;
    }
    return clientSpoke && workerSpoke;
  }

  Map<String, dynamic> get jobSource {
    final w = Map<String, dynamic>.from(jobInfo);
    return {...w, ...?jobInfoDetail};
  }

  // ─────────────────────────────────────────────
  // 초기화
  // ─────────────────────────────────────────────

  Future<void> init() async {
    _connectToSocket();
    await fetchChatRoomDetail();
    await _initializeChat();
    // 나머지는 병렬로 (await 없이)
    unawaited(checkIfReviewed());
    unawaited(loadJobInfo());
    unawaited(refreshLocationAndDistance());
    unawaited(fetchWorkState());
    unawaited(fetchWorkConfirmations());
    unawaited(fetchCheckinStatus());
  }

  Future<void> _initializeChat() async {
    if (_disposed) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    userType = prefs.getString('userType') ?? 'worker';
    await fetchMessages();
  }

  // ─────────────────────────────────────────────
  // Auth 헬퍼
  // ─────────────────────────────────────────────

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getString('authToken');
    return (t == null || t.trim().isEmpty) ? null : t;
  }

  Future<Map<String, String>> _authHeaders({bool json = false}) async {
    final token = await _getToken();
    return {
      if (json) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ─────────────────────────────────────────────
  // 메시지 정규화 / 업서트
  // ─────────────────────────────────────────────

  Map<String, dynamic> normalizeIncoming(Map raw) {
    final createdRaw =
        raw['createdAt'] ??
        raw['created_at'] ??
        raw['timestamp'] ??
        raw['sent_at'];
    int createdAtMs = toMs(createdRaw);
    if (createdAtMs == 0) {
      createdAtMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    }
    final createdIso =
        DateTime.fromMillisecondsSinceEpoch(
          createdAtMs,
          isUtc: true,
        ).toIso8601String();

    return {
      ...raw,
      'id': raw['id'] ?? raw['_id'],
      'clientTempId': raw['clientTempId'] ?? raw['tempId'] ?? raw['localId'],
      'sender': (raw['sender'] ?? raw['from'] ?? '').toString(),
      'message': (raw['message'] ?? raw['text'] ?? '').toString(),
      if (raw['imageUrl'] != null) 'imageUrl': raw['imageUrl'].toString(),
      if (raw['image_url'] != null) 'imageUrl': raw['image_url'].toString(),
      'is_read': (raw['is_read'] == 1 || raw['is_read'] == true),
      'createdAt': createdIso,
      'createdAtMs': createdAtMs,
      'pending': raw['pending'] ?? false,
      'failed': raw['failed'] ?? false,
    };
  }

  void upsertMessage(Map incomingRaw) {
    if (_disposed) return;
    final incoming = normalizeIncoming(incomingRaw);

    int findIdx() {
      final t = incoming['clientTempId'];
      if (t != null) {
        final i = messages.indexWhere((m) => m['clientTempId'] == t);
        if (i >= 0) return i;
      }
      final id = incoming['id'];
      if (id != null) {
        final i = messages.indexWhere((m) => m['id'] == id);
        if (i >= 0) return i;
      }
      final s = incoming['sender'];
      final txt = incoming['message'] ?? '';
      final img = incoming['imageUrl'] ?? '';
      final ts = incoming['createdAtMs'] as int;
      return messages.indexWhere((m) {
        final condSender = (m['sender'] ?? '') == s;
        final condBody =
            (m['message'] ?? '') == txt && (m['imageUrl'] ?? '') == img;
        final mts = (m['createdAtMs'] ?? toMs(m['createdAt'])) as int;
        return condSender && condBody && ((ts - mts).abs() <= 3000);
      });
    }

    final idx = findIdx();
    if (idx >= 0) {
      messages[idx] = {
        ...messages[idx],
        ...incoming,
        'pending': false,
        'failed': false,
      };
    } else {
      messages.add(incoming);
    }
    messages.sort(
      (a, b) => (a['createdAtMs'] as int).compareTo(b['createdAtMs'] as int),
    );
    _notify();
  }

  void _markFailed(String clientTempId, [String? reason]) {
    if (_disposed) return;
    final idx = messages.indexWhere((m) => m['clientTempId'] == clientTempId);
    if (idx == -1) return;
    messages[idx]['pending'] = false;
    messages[idx]['failed'] = true;
    if (reason != null) messages[idx]['error'] = reason;
    _notify();
  }

  // ─────────────────────────────────────────────
  // 소켓
  // ─────────────────────────────────────────────

  bool _socketConnecting = false;

  void _connectToSocket() async {
    if (_disposed) return;
    final prefs = await SharedPreferences.getInstance();
    final userPhone = prefs.getString('userPhone') ?? '';
    final token = prefs.getString('authToken') ?? '';
    final localUserType = prefs.getString('userType') ?? 'worker';

    socket?.clearListeners();
    socket?.disconnect();
    socket = null;
    if (_disposed) return;

    socket = IO.io(baseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'reconnection': true,
      'reconnectionAttempts': 999999,
      'reconnectionDelay': 800,
      'reconnectionDelayMax': 5000,
      'timeout': 5000,
      'extraHeaders': {'Authorization': 'Bearer $token'},
    });

    socket!
      ..onConnect((_) {
        if (_disposed) return;
        _joinSafe(userPhone);
      })
      ..onReconnect((_) {
        if (_disposed) return;
        _joinSafe(userPhone);
        unawaited(fetchMessages());
      })
      ..onConnectError((e) => debugPrint('⚠️ connect error: $e'))
      ..onError((e) => debugPrint('⚠️ socket error: $e'))
      ..onDisconnect((_) => debugPrint('❌ 소켓 연결 끊김'));

    socket!.on('hire_confirmed', (data) {
      if (_disposed) return;
      isConfirmed = true;
      _notify();
      onSystemMessage?.call(data['message'] ?? '채용이 확정되었습니다!');
    });

    socket!.on('completed', (data) {
      if (_disposed) return;
      isCompleted = true;
      _notify();
      onSystemMessage?.call(data['message'] ?? '알바가 완료되었습니다!');
    });

    socket!.on('receive_message', (data) async {
      if (_disposed) return;
      try {
        await http.post(
          Uri.parse('$baseUrl/api/chat/mark-read'),
          headers: {
            'Authorization': 'Bearer ${prefs.getString('authToken') ?? ''}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'roomId': chatRoomId, 'reader': localUserType}),
        );
      } catch (_) {}
      if (_disposed) return;
      upsertMessage(data);
      onScrollToBottom?.call();
    });

    socket!.connect();
  }

  void _joinSafe(String userPhone) {
    if (_disposed) return;
    final s = socket;
    if (s == null || !s.connected) return;
    s.emit('join_room', {'roomId': chatRoomId, 'userPhone': userPhone});
  }

  Future<void> ensureConnect() async {
    if (_disposed) return;
    if (_socketConnecting || (socket?.connected ?? false)) return;
    _socketConnecting = true;
    try {
      socket?.connect();
    } finally {
      _socketConnecting = false;
    }
  }

  // ─────────────────────────────────────────────
  // 메시지 fetch / send
  // ─────────────────────────────────────────────

  Future<void> fetchMessages() async {
    if (_disposed) return;
    final url = Uri.parse(
      '$baseUrl/api/chat/messages?roomId=$chatRoomId&reader=$userType',
    );
    try {
      final resp = await http.get(url, headers: await _authHeaders());
      if (_disposed) return;

      if (resp.statusCode != 200) {
        onShowSnackbar?.call('메시지 불러오기 실패 (${resp.statusCode})');
        return;
      }

      final decoded = jsonDecode(resp.body);
      final List items =
          decoded is List
              ? decoded
              : (decoded is Map && decoded['data'] is List
                  ? decoded['data'] as List
                  : const []);

      for (final raw in items) {
        if (_disposed) return;
        if (raw is Map) {
          upsertMessage({
            ...raw,
            if (raw['image_url'] != null) 'imageUrl': raw['image_url'],
          });
        }
      }
      onScrollToBottom?.call();
    } catch (e) {
      debugPrint('❌ fetchMessages error: $e');
      if (!_disposed) onShowSnackbar?.call('네트워크 오류 발생');
    } finally {
      if (!_disposed) {
        isLoading = false;
        _notify();
      }
    }
  }

  void sendMessage(String content, int userId) {
    if (_disposed) return;
    if (socket == null || !socket!.connected) return;
    if (!inputEnabled) return;
    if (content.trim().isEmpty) return;

    final sender = userType == 'worker' ? 'worker' : 'client';
    final clientTempId = _uuid.v4();
    final nowIso = DateTime.now().toUtc().toIso8601String();

    upsertMessage({
      'clientTempId': clientTempId,
      'sender': sender,
      'senderId': userId,
      'message': content,
      'createdAt': nowIso,
      'pending': true,
    });
    onScrollToBottom?.call();

    final payload = {
      'roomId': chatRoomId,
      'sender': sender,
      'senderId': userId,
      'message': content,
      'clientTempId': clientTempId,
      'clientCreatedAt': nowIso,
    };

    try {
      socket!.emitWithAck(
        'send_message',
        payload,
        ack: (dynamic resp) {
          if (_disposed) return;
          if (resp is Map && (resp['ok'] == true || resp['id'] != null)) {
            upsertMessage(<String, dynamic>{
              ...resp,
              if (resp['image_url'] != null) 'imageUrl': resp['image_url'],
              if (resp['created_at'] != null && resp['createdAt'] == null)
                'createdAt': resp['created_at'],
              'clientTempId': resp['clientTempId'] ?? clientTempId,
              'createdAt': resp['createdAt'] ?? nowIso,
            });
          } else {
            _markFailed(
              clientTempId,
              (resp is Map ? resp['error'] : null) ?? '전송 실패',
            );
          }
        },
      );
    } catch (_) {
      if (!_disposed) socket!.emit('send_message', payload);
    }

    Future.delayed(const Duration(seconds: 7), () {
      if (_disposed) return;
      final stillPending = messages.any(
        (m) => m['clientTempId'] == clientTempId && m['pending'] == true,
      );
      if (stillPending) _markFailed(clientTempId, '서버 응답 없음');
    });
  }

  // ─────────────────────────────────────────────
  // 채팅방 상세 정보
  // ─────────────────────────────────────────────

  Future<void> fetchChatRoomDetail() async {
    if (_disposed) return;
    final token = await _getToken();
    try {
      final resp = await http.get(
        Uri.parse('$baseUrl/api/chat/detail/$chatRoomId'),
        headers: {
          if (token != null && token.isNotEmpty)
            'Authorization': 'Bearer $token',
        },
      );
      if (_disposed) return;
      if (resp.statusCode != 200) return;

      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      if (decoded is! Map) return;

      final s =
          (decoded['roomStatus'] ?? decoded['status'] ?? 'active').toString();
      final ini =
          (decoded['initiatorType'] ?? decoded['initiator_type'] ?? 'client')
              .toString();

      final app =
          decoded['application'] is Map ? decoded['application'] as Map : null;
      final bool confirmed =
          asBool(decoded['is_confirmed']) ||
          asBool(app?['isConfirmed']) ||
          asBool(app?['is_confirmed']);
      final bool completed =
          asBool(decoded['is_completed']) ||
          asBool(app?['isCompleted']) ||
          asBool(app?['is_completed']);

      final int? wId = int.tryParse(
        (decoded['workerId'] ?? decoded['worker_id'])?.toString() ?? '',
      );
      final int? cId = int.tryParse(
        (decoded['clientId'] ?? decoded['client_id'])?.toString() ?? '',
      );

      Map<String, dynamic> ji = {};
      if (decoded['job'] is Map) {
        ji = Map<String, dynamic>.from(decoded['job'] as Map);
        if (ji['job_id'] == null && ji['id'] != null) ji['job_id'] = ji['id'];
      } else {
        ji = {
          if (decoded['job_id'] != null) 'id': decoded['job_id'],
          if (decoded['title'] != null) 'title': decoded['title'],
          if (decoded['job_title'] != null) 'title': decoded['job_title'],
          if (decoded['pay'] != null) 'pay': decoded['pay'],
          if (decoded['created_at'] != null)
            'created_at': decoded['created_at'],
          if (decoded['client_company_name'] != null)
            'client_company_name': decoded['client_company_name'],
        }..removeWhere((_, v) => v == null);
      }

      if (wId != null) {
        ji['worker_id'] = wId;
        ji['workerId'] = wId;
      }
      if (cId != null) {
        ji['client_id'] = cId;
        ji['clientId'] = cId;
      }

      status = s;
      initiator = ini;
      isConfirmed = confirmed;
      isCompleted = completed;
      roomWorkerId = wId;
      roomClientId = cId;
      jobInfoDetail = {...jobInfo, ...ji};
    } catch (e) {
      debugPrint('❌ fetchChatRoomDetail error: $e');
    } finally {
      if (!_disposed) {
        isLoadingJobInfo = false;
        _notify();
      }
    }
  }

  // ─────────────────────────────────────────────
  // 공고 상세 fetch
  // ─────────────────────────────────────────────

  Future<void> loadJobInfo() async {
    if (_disposed) return;
    final rawJobId =
        jobSource['id'] ?? jobSource['job_id'] ?? jobSource['jobId'];
    final jobId = int.tryParse(rawJobId?.toString() ?? '');
    if (jobId == null) return;

    try {
      final resp = await http.get(
        Uri.parse('$baseUrl/api/job/$jobId'),
        headers: await _authHeaders(),
      );
      if (_disposed) return;
      if (resp.statusCode == 200) {
        final job = jsonDecode(resp.body);
        jobInfoDetail = {
          ...?jobInfoDetail,
          if (job is Map) ...Map<String, dynamic>.from(job),
        };
        _notify();
      }
    } catch (e) {
      debugPrint('❌ loadJobInfo error: $e');
    }
  }

  // ─────────────────────────────────────────────
  // 리뷰 확인
  // ─────────────────────────────────────────────

  Future<void> checkIfReviewed() async {
    if (_disposed) return;
    final prefs = await SharedPreferences.getInstance();
    final workerId = prefs.getInt('userId');
    if (workerId == null) return;

    final clientId = jobInfo['client_id'];
    final jobTitle = jobInfo['title'] ?? '';
    final url = Uri.parse(
      '$baseUrl/api/review/has-reviewed?clientId=$clientId&workerId=$workerId'
      '&jobTitle=${Uri.encodeComponent(jobTitle.toString().trim())}',
    );
    try {
      final resp = await http.get(url);
      if (_disposed) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        hasReviewed = data['hasReviewed'] == true;
        _notify();
      }
    } catch (_) {}
  }

  // ─────────────────────────────────────────────
  // 채용 확정
  // ─────────────────────────────────────────────

  Future<void> confirmHire() async {
    if (_disposed) return;
    try {
      final resp = await http.post(
        Uri.parse('$baseUrl/api/chat/confirm/$chatRoomId'),
        headers: await _authHeaders(),
      );
      if (_disposed) return;
      if (resp.statusCode == 200) {
        isConfirmed = true;
        _notify();
        onShowSnackbar?.call('✅ 채용 확정 완료');
      } else {
        onShowSnackbar?.call('❌ 채용 확정 실패: ${resp.statusCode}');
      }
    } catch (e) {
      if (!_disposed) onShowSnackbar?.call('❌ 오류 발생: $e');
    }
  }

  // ─────────────────────────────────────────────
  // 출근 확정 카드
  // ─────────────────────────────────────────────

  Future<void> fetchWorkConfirmations() async {
    if (_disposed) return;
    try {
      final items = await WorkConfirmationService.getByRoom(chatRoomId);
      if (_disposed) return;
      workConfirmations = items;
      // completed 상태일 때만 채팅을 "완료" 처리 — accepted/scheduled는 여전히 진행 중
      if (items.any((c) => c.status == 'completed')) {
        isConfirmed = true;
      }
      _notify();
    } catch (e) {
      debugPrint('❌ fetchWorkConfirmations error: $e');
    }
  }

  Future<void> respondToWorkConfirmation(
    WorkConfirmation confirm,
    String nextStatus,
  ) async {
    if (_disposed || workLoading) return;
    workLoading = true;
    _notify();
    try {
      await WorkConfirmationService.updateStatus(
        confirm.id,
        nextStatus,
        actorType: userType,
      );
      await fetchWorkConfirmations();
      await fetchWorkState();
      if (nextStatus == 'accepted') {
        onShowSnackbar?.call('출근 확정 제안을 수락했어요. 근무일에 꼭 출근해주세요!');
        onWorkConfirmationAccepted?.call(confirm);
      } else if (nextStatus == 'cancelled') {
        onShowSnackbar?.call('출근 확정 제안을 거절했어요.');
      } else if (nextStatus == 'completed') {
        onShowEvaluationDialog?.call();
      }
    } catch (e) {
      if (!_disposed) onShowSnackbar?.call('처리에 실패했어요: $e');
    } finally {
      if (_disposed) return;
      workLoading = false;
      _notify();
    }
  }

  // ─────────────────────────────────────────────
  // 알바 완료
  // ─────────────────────────────────────────────

  Future<void> markJobAsCompleted() async {
    if (_disposed) return;
    if (socket == null || !socket!.connected) {
      onShowSnackbar?.call('소켓 연결이 안되어 있습니다.');
      return;
    }
    try {
      final resp = await http.post(
        Uri.parse('$baseUrl/api/chat/applications/complete'),
        headers: await _authHeaders(json: true),
        body: jsonEncode({'roomId': chatRoomId}),
      );
      if (_disposed) return;
      if (resp.statusCode == 200) {
        isCompleted = true;
        _notify();
        onShowSnackbar?.call('🎉 알바 완료 처리되었습니다.');
        onShowEvaluationDialog?.call();
      } else {
        onShowSnackbar?.call('알바 완료 실패');
      }
    } catch (e) {
      if (!_disposed) onShowSnackbar?.call('서버 오류: $e');
    }
  }

  // ─────────────────────────────────────────────
  // 수락/거절 (consent)
  // ─────────────────────────────────────────────

  late final AiApi _api = AiApi(baseUrl);

  Future<void> sendConsent(bool accept) async {
    if (_disposed) return;
    if (consentBusy) return;
    consentBusy = true;
    _notify();

    try {
      final result = await _api.consentDecision(
        roomId: chatRoomId,
        accept: accept,
      );
      if (_disposed) return;

      consentBusy = false;
      if (!result.ok) {
        onShowSnackbar?.call(result.message ?? '처리에 실패했습니다.');
        _notify();
        return;
      }

      status = (result.status ?? (accept ? 'active' : 'blocked')).toLowerCase();
      _notify();

      if (accept) {
        onShowSnackbar?.call('수락되었습니다. 이제 채팅이 가능합니다.');
      } else {
        onShowSnackbar?.call('대화 요청을 거절했습니다.');
        onPopScreen?.call();
      }
    } catch (e) {
      if (_disposed) return;
      consentBusy = false;
      _notify();
      onShowSnackbar?.call('네트워크 오류: $e');
    }
  }

  // ─────────────────────────────────────────────
  // 근무 확정 (캘박)
  // ─────────────────────────────────────────────

  Future<bool> confirmStartWork() async {
    if (_disposed) return false;
    final token = await _getToken();
    if (token == null || token.isEmpty) {
      onShowSnackbar?.call('로그인 정보가 없습니다.');
      return false;
    }

    final src = jobSource;
    final jobId = int.tryParse(
      (src['job_id'] ?? src['jobId'] ?? src['id'])?.toString() ?? '',
    );
    final applicationId = int.tryParse(
      (src['application_id'] ?? src['applicationId'])?.toString() ?? '',
    );
    final startDate = (src['start_date'] ?? src['startDate'])?.toString();
    final startTime = (src['start_time'] ?? src['startTime'])?.toString();
    String? startAt;
    if (startDate != null &&
        startDate.length >= 10 &&
        startTime != null &&
        startTime.isNotEmpty) {
      final t =
          startTime.length == 5 ? '$startTime:00' : startTime.substring(0, 8);
      startAt = '${startDate.substring(0, 10)} $t';
    }

    try {
      final body = <String, dynamic>{
        'roomId': chatRoomId,
        if (jobId != null) 'jobId': jobId,
        if (applicationId != null) 'applicationId': applicationId,
        if (startAt != null) 'startAt': startAt,
      };
      final resp = await http.post(
        Uri.parse('$baseUrl/api/chat/confirm-work'),
        headers: await _authHeaders(json: true),
        body: jsonEncode(body),
      );
      if (_disposed) return false;
      if (resp.statusCode == 200 || resp.statusCode == 409) {
        await fetchWorkState();
        return !_disposed;
      }
      String msg = '근무확정 실패 (${resp.statusCode})';
      try {
        final data = jsonDecode(resp.body);
        if (data is Map && data['message'] is String) msg = data['message'];
      } catch (_) {}
      if (!_disposed) onShowSnackbar?.call(msg);
      return false;
    } catch (e) {
      if (!_disposed) onShowSnackbar?.call('네트워크 오류: $e');
      return false;
    }
  }

  Future<void> addCurrentWorkToCalendar() async {
    if (_disposed || workLoading) return;
    workLoading = true;
    _notify();
    try {
      final ok = await confirmStartWork();
      if (ok) onShowSnackbar?.call('캘린더에 등록했어요.');
    } finally {
      if (_disposed) return;
      workLoading = false;
      _notify();
    }
  }

  Future<void> fetchWorkState() async {
    if (_disposed) return;
    final token = await _getToken();
    if (token == null || token.isEmpty) return;

    try {
      final resp = await http.get(
        Uri.parse('$baseUrl/api/chat/work-session-state?roomId=$chatRoomId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (_disposed) return;
      if (resp.statusCode != 200) return;

      final data = jsonDecode(resp.body);
      if (data is! Map) return;

      final confirmed =
          asBool(data['confirmed']) ||
          asBool(data['workerConfirmed']) ||
          asBool(data['worker_confirmed']) ||
          data['worker_confirmed_at'] != null ||
          data['confirmed_at'] != null ||
          data['confirmedAt'] != null;

      final cancelable =
          asBool(data['canCancel']) ||
          asBool(data['can_cancel']) ||
          asBool(data['cancelable']) ||
          asBool(data['isCancelable']);

      final sessionIdRaw =
          data['sessionId'] ?? data['workSessionId'] ?? data['id'];
      final sessionId = int.tryParse(sessionIdRaw?.toString() ?? '');

      workerWorkConfirmed = confirmed;
      canCancel = cancelable;
      hasWorkSession =
          asBool(data['hasSession']) ||
          asBool(data['has_session']) ||
          sessionId != null;
      workSessionId = sessionId;
      workError = null;
      _notify();
    } catch (e) {
      if (_disposed) return;
      workError = '$e';
      _notify();
    }
  }

  Future<void> cancelWorkSession() async {
    if (_disposed) return;
    workLoading = true;
    _notify();
    try {
      final resp = await http.post(
        Uri.parse('$baseUrl/api/chat/cancel-work'),
        headers: await _authHeaders(json: true),
        body: jsonEncode({'roomId': chatRoomId}),
      );
      if (_disposed) return;
      if (resp.statusCode == 200) {
        await fetchWorkState();
        onShowSnackbar?.call('일정이 취소됐어요.');
        return;
      }
      String msg = '일정 취소 실패 (${resp.statusCode})';
      try {
        final data = jsonDecode(resp.body);
        if (data is Map && data['message'] is String) msg = data['message'];
      } catch (_) {}
      onShowSnackbar?.call(msg);
    } catch (e) {
      if (!_disposed) onShowSnackbar?.call('네트워크 오류: $e');
    } finally {
      if (!_disposed) {
        workLoading = false;
        _notify();
      }
    }
  }

  // ─────────────────────────────────────────────
  // 출근 확인 (체크인)
  // ─────────────────────────────────────────────

  Future<void> fetchCheckinStatus() async {
    if (_disposed) return;
    final src = jobSource;
    final jobId = int.tryParse(
      (src['id'] ?? src['job_id'] ?? src['jobId'])?.toString() ?? '',
    );
    if (jobId == null) return;

    try {
      final resp = await http.get(
        Uri.parse('$baseUrl/api/attendance/checkin-status?jobId=$jobId'),
        headers: await _authHeaders(),
      );
      if (_disposed) return;
      if (resp.statusCode != 200) return;
      final data = jsonDecode(resp.body);
      if (data is! Map) return;
      if (data['message'] == 'CHECKIN_STATUS' && data['status'] == 'success') {
        checkedIn = true;
        checkinDistanceM = data['distance_m'];
        checkinRadiusM = data['radius_m'];
        _notify();
      }
    } catch (_) {}
  }

  Future<void> refreshLocationAndDistance() async {
    if (_disposed) return;
    if (geoLoading) return;
    geoLoading = true;
    geoError = null;
    _notify();

    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (_disposed) return;

      if (perm == LocationPermission.deniedForever) {
        geoError = '위치 권한이 꺼져 있어요(설정에서 허용 필요).';
        return;
      }
      if (perm == LocationPermission.denied) {
        geoError = '위치 권한이 필요해요.';
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        geoError = 'GPS가 꺼져 있어요. 위치 서비스를 켜주세요.';
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 10),
      );
      if (_disposed) return;

      final src = jobSource;
      final jobLat = asDouble(src['lat']);
      final jobLng = asDouble(src['lng']);
      int? dist;
      if (jobLat != null && jobLng != null) {
        dist = haversineMeters(jobLat, jobLng, pos.latitude, pos.longitude);
      }

      myLat = pos.latitude;
      myLng = pos.longitude;
      myAcc = pos.accuracy;
      myDistanceToJobM = dist;
      lastGeoAt = DateTime.now();
    } catch (e) {
      if (!_disposed) geoError = '위치 확인 실패: $e';
    } finally {
      if (!_disposed) {
        geoLoading = false;
        _notify();
      }
    }
  }

  Future<void> checkinNow() async {
    if (_disposed) return;
    if (checkinLoading) return;

    final src = jobSource;
    final weekdays = (src['weekdays'] ?? '').toString().trim();
    if (weekdays.isNotEmpty) {
      onShowSnackbar?.call('요일 공고는 출근확인이 아직 지원되지 않습니다.');
      return;
    }

    final jobId = int.tryParse(
      (src['id'] ?? src['job_id'] ?? src['jobId'])?.toString() ?? '',
    );
    if (jobId == null) {
      onShowSnackbar?.call('공고 정보를 찾을 수 없습니다.');
      return;
    }

    checkinLoading = true;
    _notify();

    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (_disposed) return;

      if (perm == LocationPermission.deniedForever) {
        onShowSnackbar?.call('위치 권한이 필요합니다. 설정에서 허용해 주세요.');
        return;
      }
      if (perm == LocationPermission.denied) {
        onShowSnackbar?.call('위치 권한이 필요합니다.');
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        onShowSnackbar?.call('GPS가 꺼져 있습니다. 위치 서비스를 켜주세요.');
        return;
      }

      if (!geoFresh || myLat == null || myLng == null) {
        await refreshLocationAndDistance();
      }
      if (_disposed) return;

      if (myLat == null || myLng == null) {
        onShowSnackbar?.call('현재 위치를 가져올 수 없습니다. 잠시 후 다시 시도해 주세요.');
        return;
      }

      final resp = await http.post(
        Uri.parse('$baseUrl/api/attendance/checkin'),
        headers: await _authHeaders(json: true),
        body: jsonEncode({
          'jobId': jobId,
          'lat': myLat,
          'lng': myLng,
          'accuracy_m': myAcc,
        }),
      );
      if (_disposed) return;

      Map<String, dynamic> data = {};
      try {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map<String, dynamic>) data = decoded;
      } catch (_) {}

      final msg = (data['message'] ?? 'UNKNOWN').toString();
      if (resp.statusCode == 200 && msg == 'CHECKIN_OK') {
        checkedIn = true;
        checkinDistanceM = data['distance_m'];
        checkinRadiusM = data['radius_m'];
        _notify();
        onShowSnackbar?.call('출근 확인 완료! (${checkinDistanceM ?? ''}m)');
        return;
      }

      final errMap = {
        'OUT_OF_RADIUS':
            '현장 반경 밖입니다. (${data['distance_m']}m / ${data['radius_m']}m)',
        'LOW_GPS_ACCURACY': 'GPS 정확도가 낮아요. (${data['accuracy_m']}m)',
        'CHECKIN_DEADLINE_PASSED': '출근 확인 가능 시간이 지났습니다.',
        'JOB_LOCATION_MISSING': '공고 위치 정보가 없어 출근 확인이 불가합니다.',
        'LONG_TERM_NOT_SUPPORTED_YET': '요일 공고 출근확인은 아직 지원되지 않습니다.',
        'CLAIM_ALREADY_EXISTS': '이미 환급 요청이 진행 중이라 출근 확인이 막혀 있습니다.',
        'JOB_NOT_ACTIVE': '진행 중인 공고가 아닙니다.',
      };
      onShowSnackbar?.call(errMap[msg] ?? '출근 확인 실패: $msg');
    } on TimeoutException {
      if (!_disposed) onShowSnackbar?.call('위치 확인이 지연되고 있어요. 다시 시도해 주세요.');
    } catch (e) {
      if (!_disposed) onShowSnackbar?.call('출근 확인 중 오류: $e');
    } finally {
      if (!_disposed) {
        checkinLoading = false;
        _notify();
      }
    }
  }

  // ─────────────────────────────────────────────
  // 지원 취소
  // ─────────────────────────────────────────────

  Future<void> cancelApplication() async {
    if (_disposed) return;
    final src = jobSource;
    final jobId = int.tryParse(
      (src['id'] ?? src['job_id'] ?? src['jobId'])?.toString() ?? '',
    );
    if (jobId == null) {
      onShowSnackbar?.call('공고 정보가 없어 취소할 수 없습니다.');
      return;
    }
    if (isCompleted) {
      onShowSnackbar?.call('이미 완료된 공고는 지원 취소가 불가합니다.');
      return;
    }
    if (hasWorkSession) {
      onShowCalendarBlockedDialog?.call();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    if (_disposed) return;
    final workerId = prefs.getInt('userId');
    final token = prefs.getString('authToken') ?? '';

    if (workerId == null || token.isEmpty) {
      onShowSnackbar?.call('로그인 정보가 없습니다. 다시 로그인해주세요.');
      return;
    }

    try {
      final resp = await http.post(
        Uri.parse('$baseUrl/api/applications/cancel'),
        headers: await _authHeaders(json: true),
        body: jsonEncode({'jobId': jobId, 'workerId': workerId}),
      );
      if (_disposed) return;

      String message =
          resp.statusCode == 200
              ? '이 공고에 대한 지원을 취소했어요.'
              : '지원 취소에 실패했습니다. (${resp.statusCode})';
      try {
        final data = jsonDecode(resp.body);
        if (data is Map && data['message'] is String) message = data['message'];
      } catch (_) {}

      if (resp.statusCode == 200) {
        status = 'cancelled';
        _notify();
      }
      onShowSnackbar?.call(message);
    } catch (e) {
      if (!_disposed) onShowSnackbar?.call('지원 취소 중 오류가 발생했습니다: $e');
    }
  }

  // ─────────────────────────────────────────────
  // 평가 제출
  // ─────────────────────────────────────────────

  Future<void> submitEvaluation({required bool isGood}) async {
    if (_disposed) return;
    final src = jobSource;
    final targetType = (userType == 'worker') ? 'client' : 'worker';
    final targetIdRaw =
        targetType == 'worker'
            ? (roomWorkerId ?? src['worker_id'] ?? src['workerId'])
            : (roomClientId ?? src['client_id'] ?? src['clientId']);

    final targetId = int.tryParse(targetIdRaw?.toString() ?? '');
    if (targetId == null) {
      onShowSnackbar?.call('평가 대상 정보가 없어요.');
      throw Exception('targetId missing');
    }

    final jobId = int.tryParse(
      (src['job_id'] ?? src['jobId'] ?? src['id'])?.toString() ?? '',
    );
    final token = await _getToken();
    if (token == null || token.isEmpty) {
      onShowSnackbar?.call('로그인이 필요해요.');
      throw Exception('authToken missing');
    }

    final resp = await http.post(
      Uri.parse('$baseUrl/api/chat/evaluate'),
      headers: await _authHeaders(json: true),
      body: jsonEncode({
        'targetId': targetId,
        'targetType': targetType,
        'isGood': isGood,
        'chatRoomId': chatRoomId,
        'jobId': jobId,
      }),
    );
    if (_disposed) return;

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      String msg = '평가 저장 실패';
      try {
        final data = jsonDecode(resp.body);
        msg = (data['message'] ?? data['error'] ?? msg).toString();
      } catch (_) {}
      onShowSnackbar?.call(msg);
      throw Exception('submitEvaluation failed: ${resp.statusCode}');
    }
    onShowSnackbar?.call('평가가 반영됐어요');
  }

  // ─────────────────────────────────────────────
  // 이미지 전송
  // ─────────────────────────────────────────────

  Future<void> sendImage(File imageFile) async {
    if (_disposed) return;
    final token = await _getToken() ?? '';
    final sender = userType == 'worker' ? 'worker' : 'client';

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/chat/upload-image'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.fields['roomId'] = chatRoomId.toString();
    request.fields['sender'] = sender;
    request.files.add(
      await http.MultipartFile.fromPath('image', imageFile.path),
    );

    final streamedResp = await request.send();
    final resp = await http.Response.fromStream(streamedResp);
    if (_disposed) return;

    if (resp.statusCode == 200) {
      final resData = jsonDecode(resp.body);
      final imageUrl = resData['imageUrl'];
      if (imageUrl == null || imageUrl.isEmpty) {
        onShowSnackbar?.call('서버가 이미지 URL을 반환하지 않았습니다.');
        return;
      }
      final createdAtUtc = DateTime.now().toUtc();
      socket?.emit('send_message', {
        'roomId': chatRoomId,
        'sender': sender,
        'message': '[이미지]',
        'imageUrl': imageUrl,
      });
      upsertMessage({
        'sender': sender,
        'message': '[이미지]',
        'imageUrl': imageUrl,
        'createdAt': createdAtUtc.toIso8601String(),
        'createdAtMs': createdAtUtc.millisecondsSinceEpoch,
      });
      onScrollToBottom?.call();
    } else {
      onShowSnackbar?.call('이미지 업로드 실패 (${resp.statusCode})');
    }
  }
}
