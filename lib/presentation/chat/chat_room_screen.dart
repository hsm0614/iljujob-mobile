import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../../config/constants.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../screens/worker_profile_screen.dart';
import '../screens/client_profile_screen.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:io' show Platform;
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:iljujob/data/models/job.dart';
import 'package:iljujob/presentation/screens/job_detail_screen.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:iljujob/presentation/chat/chat_image_screen.dart';
import 'package:uuid/uuid.dart';
import '../../data/services/ai_api.dart';
import 'package:provider/provider.dart';
class ChatRoomScreen extends StatefulWidget {
  final int chatRoomId;

  final Map<String, dynamic> jobInfo;

  const ChatRoomScreen({
    super.key,
    required this.chatRoomId,
    required this.jobInfo,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  List<Map<String, dynamic>> messages = [];
  bool isLoading = true;
  String userType = 'worker';
  IO.Socket? socket;
  bool isConfirmed = false;
  bool isCompleted = false; // ✅ 이 줄 추가
  bool _hasReviewed = false;
  Map<String, dynamic>? _jobInfo; // 🔴 빨간줄 해결
  bool _isLoadingJobInfo = true; // 🔴 빨간줄 해결
DateTime _parseToUtc(dynamic v) {
  if (v == null) return DateTime.now().toUtc();

  // epoch 숫자(초/밀리초)도 처리
  if (v is int) {
    final ms = (v < 1000000000000) ? v * 1000 : v;
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  if (v is String) {
    final s = v.trim();
    final hasTz = s.endsWith('Z') || RegExp(r'[+\-]\d{2}:\d{2}$').hasMatch(s);
    final iso = hasTz
        ? s
        : (s.contains('T') ? (s + 'Z') : (s.replaceAll(' ', 'T') + 'Z'));
    final dt = DateTime.parse(iso);
    return dt.isUtc ? dt : dt.toUtc();
  }

  return DateTime.now().toUtc();
}

int _toMs(dynamic v) {
if (v == null) return 0;
  if (v is int) {
    final len = v.toString().length; // 10=sec, 13=ms, 16+=us
    if (len >= 16) {
      return DateTime.fromMicrosecondsSinceEpoch(v, isUtc: true).millisecondsSinceEpoch;
    }
    if (len >= 13) {
      return DateTime.fromMillisecondsSinceEpoch(v, isUtc: true).millisecondsSinceEpoch;
    }
    return DateTime.fromMillisecondsSinceEpoch(v * 1000, isUtc: true).millisecondsSinceEpoch;
  }
  final s = v.toString().trim();
  if (RegExp(r'^\d+$').hasMatch(s)) return _toMs(int.parse(s));
  DateTime? dt = DateTime.tryParse(s) ?? DateTime.tryParse(s.replaceFirst(' ', 'T'));
  if (dt == null && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) {
    final p = s.split('-');
    dt = DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }
if (dt == null) return 0;
return (dt.isUtc ? dt : dt.toUtc()).millisecondsSinceEpoch;
}
String _status = 'active';      // 'pending' | 'active' | 'blocked' ...
String _initiator = 'client';   // 'client' | 'worker'

bool _consentBusy = false;

// 메시지 입력 가능 여부 (기업이 pending이면 false)
bool get _inputEnabled {
  if (userType == 'client' && _status == 'pending') return false;
  return true;
}


// 워커가 수락/거절 버튼을 봐야 하는지
bool get _workerSeeConsentButtons =>
    (userType == 'worker') && (_initiator == 'client') && (_status == 'pending');

// 클라이언트가 대기 배너를 봐야 하는지
bool get _clientSeeWaitingBanner =>
    (userType == 'client') && (_status == 'pending');
Map<String, dynamic> _normalizeIncoming(Map raw) {
  final createdRaw = raw['createdAt'] ?? raw['created_at'] ?? raw['timestamp'] ?? raw['sent_at'];
  final createdAtMs = _toMs(createdRaw);
  final createdIso = DateTime.fromMillisecondsSinceEpoch(createdAtMs, isUtc: true).toIso8601String();

  return {
    ...raw,
    'id': raw['id'] ?? raw['_id'],
    'clientTempId': raw['clientTempId'] ?? raw['tempId'] ?? raw['localId'],
    'sender': (raw['sender'] ?? raw['from'] ?? '').toString(),
    'message': (raw['message'] ?? raw['text'] ?? '').toString(),
    if (raw['imageUrl'] != null) 'imageUrl': raw['imageUrl'].toString(),
    if (raw['image_url'] != null) 'imageUrl': raw['image_url'].toString(), // 서버 snake 대응
    'is_read': (raw['is_read'] == 1 || raw['is_read'] == true),
    // 통일된 시간 필드 2종
    'createdAt': createdIso,       // ISO
    'createdAtMs': createdAtMs,    // 정렬용
    // 상태 기본값
    'pending': raw['pending'] ?? false,
    'failed': raw['failed'] ?? false,
  };
}

void _upsertMessage(Map incomingRaw) {
  final incoming = _normalizeIncoming(incomingRaw);

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
    // fallback: 같은 보낸이/내용/이미지 & ±3초
    final s = incoming['sender'];
    final txt = incoming['message'] ?? '';
    final img = incoming['imageUrl'] ?? '';
    final ts = incoming['createdAtMs'] as int;
    final i = messages.indexWhere((m) {
      final condSender = (m['sender'] ?? '') == s;
      final condBody   = (m['message'] ?? '') == txt && (m['imageUrl'] ?? '') == img;
      final mts        = (m['createdAtMs'] ?? _toMs(m['createdAt'])) as int;
      return condSender && condBody && ((ts - mts).abs() <= 3000);
    });
    return i;
  }

  final idx = findIdx();
  if (idx >= 0) {
    messages[idx] = {...messages[idx], ...incoming, 'pending': false, 'failed': false};
  } else {
    messages.add(incoming);
  }

  messages.sort((a, b) => (a['createdAtMs'] as int).compareTo(b['createdAtMs'] as int));
  if (mounted) setState(() {});
}

  @override
  void initState() {
    super.initState();
    _connectToSocket();
    _fetchChatRoomDetail().then((_) {
      _initializeChat(); // 메시지는 상세정보 받은 후에
      _checkIfReviewed();
      _loadJobInfo();
    });
  }
  @override
  void dispose() {
    socket?.clearListeners();

    socket?.disconnect();
    socket = null;
    _scrollController.dispose();
    super.dispose();
  }
@override
void didChangeDependencies() {
  super.didChangeDependencies();
  Future.microtask(_ensureConnect); // ✅ 이걸로
}

bool _socketConnecting = false;
Future<void> _ensureConnect() async {
  if (!mounted) return;
  if (_socketConnecting || (socket?.connected ?? false)) return;
  _socketConnecting = true;
  try { socket?.connect(); } finally { _socketConnecting = false; }
}
void _joinSafe(String userPhone) {
  if (!mounted) return;                 // 화면이 이미 dispose면 아무것도 안 함
  final s = socket;                     // 로컬로 캡처 (race 줄임)
  if (s == null || !(s.connected)) {    // 소켓 없거나 아직 안 붙었으면 리턴
    return;
  }
  s.emit('join_room', {
    'roomId': widget.chatRoomId,
    'userPhone': userPhone,
    // 'userId': userId, // 쓰면 더 좋음 (서버가 받도록 했으면)
  });
}

String _formatTime(dynamic value) {
  final dt = _parseServerTime(value);
  if (dt == null) return '';
  // 오전/오후 h:mm (ko_KR)
  return DateFormat('a h:mm', 'ko_KR').format(dt);
}

  Future<void> _loadJobInfo() async {
    final jobId = widget.jobInfo['id'];

    if (jobId == null) {
      print('❌ jobId 없음 → 공고 정보 불러올 수 없음');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken') ?? '';

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/job/$jobId'),
        headers: {'Authorization': 'Bearer $token'},
      );



      if (response.statusCode == 200) {
        final job = jsonDecode(response.body); // 전체가 곧 job

        setState(() {
          _jobInfo = job;
          _isLoadingJobInfo = false;
        });
      } else {
        print('❌ 서버 응답 실패: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ 예외 발생: $e');
    }
  }

  Future<void> _checkIfReviewed() async {
    final prefs = await SharedPreferences.getInstance();
    final workerId = prefs.getInt('userId');
    if (workerId == null) return;

    final clientId = widget.jobInfo['client_id'];
    final jobTitle = widget.jobInfo['title'];

    final encodedTitle = Uri.encodeComponent(jobTitle.trim());

    final url = Uri.parse(
      '$baseUrl/api/review/has-reviewed?clientId=$clientId&workerId=$workerId&jobTitle=$encodedTitle',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _hasReviewed = data['hasReviewed'] == true;
        });
      } else {
        print('❌ 리뷰 확인 실패 (${response.statusCode})');
      }
    } catch (e) {
      print('❌ 네트워크 오류: $e');
    }
  }

  Future<void> _initializeChat() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    userType = prefs.getString('userType') ?? 'worker';
    await _fetchMessages();
  }

  void _connectToSocket() async {
  final prefs = await SharedPreferences.getInstance();
  final userPhone = prefs.getString('userPhone') ?? '';
  final token = prefs.getString('authToken') ?? '';

  // 1) 중복 연결/리스너 정리
  if (socket != null) {
      socket!.clearListeners(); // ← 추가
      // 모든 리스너 해제
    socket!.disconnect();   // 연결 끊기
    socket = null;
  }

  // 2) 옵션 보강: 내가 연결 타이밍 제어 + 재연결 + 인증 헤더
  socket = IO.io(baseUrl, <String, dynamic>{
    'transports': ['websocket'],
    'autoConnect': false,                // ← 직접 connect() 호출할거라 false
    'reconnection': true,
    'reconnectionAttempts': 999999,
    'reconnectionDelay': 800,
    'reconnectionDelayMax': 5000,
    'timeout': 5000,
    'extraHeaders': {'Authorization': 'Bearer $token'}, // 서버가 쓰면 유용
    // 서버가 socket.auth를 쓰면 아래로:
    // 'auth': {'token': token},
  });
  final localUserType = prefs.getString('userType') ?? 'worker'; // ← 추가



  // 3) 이벤트 바인딩
  socket!
    ..onConnect((_) {

      _joinSafe(userPhone);
    })
    ..onReconnect((_) {

      _joinSafe(userPhone);
      _fetchMessages(); // 누락분 싱크 맞추기(선택이지만 추천)
    })
    ..onReconnectAttempt((_) => debugPrint('… 재연결 시도 중'))
    ..onConnectError((e) => debugPrint('⚠️ connect error: $e'))
    ..onError((e) => debugPrint('⚠️ socket error: $e'))
    ..onDisconnect((_) => debugPrint('❌ 소켓 연결 끊김'));

  // ===== 네가 기존에 쓰던 리스너들 그대로 유지 =====
  socket!.on('hire_confirmed', (data) {
    setState(() {
      isConfirmed = true;
    });
    _showErrorSnackbar(data['message'] ?? '채용이 확정되었습니다!');

    if (Platform.isAndroid) {
      flutterLocalNotificationsPlugin.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        '${data['senderName'] ?? '기업'}',
        data['message'] ?? '채용이 확정되었습니다!',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'basic_channel',
            '기본 채널',
            channelDescription: '채팅 메시지 알림',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
      );
    }
  });

  socket!.on('completed', (data) {
    setState(() {
      isCompleted = true;
    });
    _showErrorSnackbar(data['message'] ?? '알바가 완료되었습니다!');

    if (Platform.isAndroid) {
      flutterLocalNotificationsPlugin.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        '알바 완료 알림',
        data['message'] ?? '알바가 완료되었습니다!',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'basic_channel',
            '기본 채널',
            channelDescription: '채팅 메시지 알림',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
      );
    }
  });

socket!.on('receive_message', (data) async {
  // (선택) 내 메시지 필터는 지우는 걸 권장 — 병합으로 중복 방지됨
  // final mySender = localUserType == 'worker' ? 'worker' : 'client';
  // if (data['sender'] == mySender) return;

  // 읽음 처리는 유지
  try {
    final token = prefs.getString('authToken') ?? '';
    final url = Uri.parse('$baseUrl/api/chat/mark-read');
    await http.post(
      url,
      headers: {'Authorization': 'Bearer $token','Content-Type': 'application/json'},
      body: jsonEncode({'roomId': widget.chatRoomId, 'reader': localUserType}),
    );
  } catch (_) {}

  // ✅ 단일 진입점으로만 추가/병합
  _upsertMessage(data);

  // 알림/스크롤
  // ...
  _scrollToBottom();
});

  // 4) 마지막에 직접 연결 시작
  socket!.connect();
}


Future<void> _fetchChatRoomDetail() async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('authToken');

  try {
    final resp = await http.get(
      Uri.parse('$baseUrl/api/chat/detail/${widget.chatRoomId}'),
      headers: {
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    );

    if (resp.statusCode != 200) {
      debugPrint('❌ 상세 정보 요청 실패: ${resp.statusCode} ${resp.body}');
      if (!mounted) return;
      setState(() {
        // 최소한 로딩만 해제
        _isLoadingJobInfo = false;
      });
      return;
    }

    final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
    if (decoded is! Map) {
      debugPrint('❌ 잘못된 응답 형식: ${resp.body}');
      if (!mounted) return;
      setState(() => _isLoadingJobInfo = false);
      return;
    }

    // 1) 상태/주도자 (서버가 안주면 기본값으로 보정)
    final status = (decoded['status'] ?? decoded['room_status'] ?? 'active').toString();
    final initiator =
        (decoded['initiatorType'] ?? decoded['initiator_type'] ?? 'client').toString();

    // 2) 확정/완료 플래그 다양한 케이스 흡수
    bool _asBool(dynamic v) {
      if (v == null) return false;
      if (v is bool) return v;
      if (v is num) return v != 0;
      final s = v.toString().toLowerCase();
      return s == 'true' || s == '1' || s == 'yes';
    }

    final bool confirmed = _asBool(decoded['is_confirmed']) ||
        _asBool((decoded['application'] as Map?)?['is_confirmed']);
    final bool completed = _asBool(decoded['is_completed']) ||
        _asBool((decoded['application'] as Map?)?['is_completed']);

    // 3) jobInfo 채우기 (서버가 job 객체로 주면 그대로, 아니면 낱개 필드로 구성)
    Map<String, dynamic> jobInfo = {};
    if (decoded['job'] is Map) {
      jobInfo = Map<String, dynamic>.from(decoded['job'] as Map);
    } else {
      jobInfo = {
        if (decoded['job_id'] != null) 'id': decoded['job_id'],
        if (decoded['title'] != null) 'title': decoded['title'],
        if (decoded['job_title'] != null) 'title': decoded['job_title'],
        if (decoded['pay'] != null) 'pay': decoded['pay'],
        if (decoded['created_at'] != null) 'created_at': decoded['created_at'],
        if (decoded['client_company_name'] != null)
          'client_company_name': decoded['client_company_name'],
      }..removeWhere((_, v) => v == null);
    }

    if (!mounted) return;
    setState(() {
      // 화면 상태 반영
      _status = status;          // 'pending'이면 입력 비활성에 쓰임
      _initiator = initiator;    // 'client'가 요청한 pending이면 워커에게 수락/거절 버튼 노출

      isConfirmed = confirmed;
      isCompleted = completed;

      // 상단 요약에 사용할 jobInfo 갱신 (기존 인자와 merge)
      _jobInfo = {
        ...?widget.jobInfo,
        ...jobInfo,
      };
      _isLoadingJobInfo = false;
    });
  } catch (e) {
    debugPrint('❌ 상세 정보 요청 중 오류: $e');
    if (!mounted) return;
    setState(() {
      _isLoadingJobInfo = false;
    });
  }
}
  Future<void> _pickAndSendImage() async {
     if (!_inputEnabled) {
    _showErrorSnackbar('아직 채팅이 활성화되지 않았습니다. 상대방의 수락을 기다려주세요.');
    return;
  }
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    final imageFile = File(pickedFile.path);

    // 🔹 미리보기 다이얼로그 띄우기
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

    // ✅ 기존 이미지 전송 로직 그대로 실행
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken') ?? '';

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/chat/upload-image'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.fields['roomId'] = widget.chatRoomId.toString();
    request.fields['sender'] = userType == 'worker' ? 'worker' : 'client';
    request.files.add(
      await http.MultipartFile.fromPath('image', imageFile.path),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      final resData = jsonDecode(response.body);
      final imageUrl = resData['imageUrl'];

      if (imageUrl == null || imageUrl.isEmpty) {
        _showErrorSnackbar('서버가 이미지 URL을 반환하지 않았습니다.');
        return;
      }

      final sender = userType == 'worker' ? 'worker' : 'client';
       // ✅ 1) UTC 시간으로 고정 (Z 포함 ISO)
  final createdAtUtc = DateTime.now().toUtc();
  final createdAtIso = createdAtUtc.toIso8601String();

  // (선택) 서버가 그대로 돌려주면 병합 정확도가 좋아짐
  // final clientTempId = const Uuid().v4();
  
      socket?.emit('send_message', {
        'roomId': widget.chatRoomId,
        'sender': sender,
        'message': '[이미지]',
        'imageUrl': imageUrl,
      });

     setState(() {
    messages.add({
      'sender': sender,
      'message': '[이미지]',
      'imageUrl': imageUrl,
   'createdAt': createdAtIso,       // ← 서버가 사용하면 더 일관적    
                          // ← ISO(UTC, Z 포함)
      'createdAtMs': createdAtUtc.millisecondsSinceEpoch // ← 정렬 안정화
      // 'clientTempId': clientTempId, // (선택)
    });
      });

      _scrollToBottom();
    } else {
      _showErrorSnackbar('이미지 업로드 실패 (${response.statusCode})');
    }
  }
final _uuid = const Uuid();
  Future<void> _fetchMessages() async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('authToken') ?? '';

  final url = Uri.parse(
    '$baseUrl/api/chat/messages?roomId=${widget.chatRoomId}&reader=$userType',
  );

  try {
    final resp = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (resp.statusCode != 200) {
      _showErrorSnackbar('메시지 불러오기 실패 (${resp.statusCode})');
      return;
    }

    final decoded = jsonDecode(resp.body);

    // 응답이 List인 경우 / data 리스트로 래핑된 경우 모두 커버
    final List items = decoded is List
        ? decoded
        : (decoded is Map && decoded['data'] is List ? decoded['data'] as List : const []);

    // ✅ 기존 메시지에 덮어쓰지 말고, 업서트로 병합 (중복 방지 & 정렬 일관)
    for (final raw in items) {
      if (raw is Map) {
        _upsertMessage({
          ...raw,
          if (raw['image_url'] != null) 'imageUrl': raw['image_url'], // snake → camel 보정
        });
      }
    }

    if (mounted) setState(() => isLoading = false);
    _scrollToBottom();
  } catch (e) {
    _showErrorSnackbar('네트워크 오류 발생');
  }
}

void _replaceOptimistic(String clientTempId, Map<String, dynamic> serverMsg) {
  final idx = messages.indexWhere((m) => m['clientTempId'] == clientTempId);
  setState(() {
    if (idx >= 0) {
      messages[idx] = {
        ...messages[idx],
        ...serverMsg,
        'pending': false,
        'failed': false,
      };
    } else {
      messages.add({...serverMsg, 'pending': false, 'failed': false});
    }
  });
}

void _markFailed(String clientTempId, [String? reason]) {
  final idx = messages.indexWhere((m) => m['clientTempId'] == clientTempId);
  if (idx == -1) return;
  setState(() {
    messages[idx]['pending'] = false;
    messages[idx]['failed'] = true;
    if (reason != null) messages[idx]['error'] = reason;
  });
}
void _sendMessage() async {
  if (socket == null || !socket!.connected) return;
 if (!_inputEnabled) {
    _showErrorSnackbar('아직 채팅이 활성화되지 않았습니다. 상대방의 수락을 기다려주세요.');
    return;
  }
  final prefs = await SharedPreferences.getInstance();
  final userId = prefs.getInt('userId');
  final sender = userType == 'worker' ? 'worker' : 'client';
  final content = _messageController.text.trim();
  if (content.isEmpty || userId == null) return;

  final clientTempId = _uuid.v4();
  final nowIso = DateTime.now().toUtc().toIso8601String();

  // ✅ 낙관적 추가 — 업서트로
  _upsertMessage({
    'clientTempId': clientTempId,
    'sender': sender,
    'senderId': userId,
    'message': content,
    'createdAt': nowIso,
    'pending': true,
  });
  _messageController.clear();
  _scrollToBottom();

  final payload = {
    'roomId': widget.chatRoomId,
    'sender': sender,
    'senderId': userId,
    'message': content,
    'clientTempId': clientTempId,
    'clientCreatedAt': nowIso,
  };

  try {
    socket!.emitWithAck('send_message', payload, ack: (dynamic resp) {
      if (resp is Map && (resp['ok'] == true || resp['id'] != null)) {
        _upsertMessage({
          ...resp,
          'clientTempId': resp['clientTempId'] ?? clientTempId,
          'createdAt': resp['createdAt'] ?? nowIso,
        });
      } else {
        _markFailed(clientTempId, (resp is Map ? resp['error'] : null) ?? '전송 실패');
      }
    });
  } catch (_) {
    socket!.emit('send_message', payload);
  }

  Future.delayed(const Duration(seconds: 7), () {
    final stillPending = messages.any((m) => m['clientTempId'] == clientTempId && m['pending'] == true);
    if (stillPending) _markFailed(clientTempId, '서버 응답 없음');
  });
}
late final AiApi _api = AiApi(baseUrl);
Future<void> _sendConsent(bool accept) async {
  if (!mounted || _consentBusy) return;
  setState(() => _consentBusy = true);

  try {
    final result = await _api.consentDecision(
      roomId: widget.chatRoomId,
      accept: accept,
    );

    if (!mounted) return;
    setState(() => _consentBusy = false);

    if (!result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? '처리에 실패했습니다.')),
      );
      return;
    }

    final newStatus = (result.status ?? (accept ? 'active' : 'blocked')).toLowerCase();
    setState(() => _status = newStatus);

    if (accept) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('수락되었습니다. 이제 채팅이 가능합니다.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('대화 요청을 거절했습니다.')),
      );
      Navigator.of(context).maybePop();
    }
  } catch (e) {
    if (!mounted) return;
    setState(() => _consentBusy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('네트워크 오류: $e')),
    );
  }
}
  Future<void> _confirmHire() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken') ?? '';

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/chat/confirm/${widget.chatRoomId}'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        setState(() {
          isConfirmed = true;
        });
        _showErrorSnackbar('✅ 채용 확정 완료');
      } else {
        _showErrorSnackbar('❌ 채용 확정 실패: ${response.statusCode}');
      }
    } catch (e) {
      _showErrorSnackbar('❌ 오류 발생: $e');
    }
  }

  Future<void> _markJobAsCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken') ?? '';
    if (socket == null || !socket!.connected) {
      _showErrorSnackbar('소켓 연결이 안되어 있습니다.');
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/chat/applications/complete'), // ✅ 수정된 경로
        headers: {
          'Authorization': 'Bearer $token', // ✅ 토큰 추가
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'roomId': widget.chatRoomId}),
      );

      if (response.statusCode == 200) {
        _showEvaluationDialog(); // ⭐️ 평가 모달 호출
        _showErrorSnackbar('🎉 알바 완료 처리되었습니다.');
        setState(() {
          isCompleted = true;
        });
      } else {
        _showErrorSnackbar('알바 완료 실패');
      }
    } catch (e) {
      _showErrorSnackbar('서버 오류: $e');
    }
  }

  void _showEvaluationDialog() {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => Dialog(
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
              color: Color(0xFF1675F4), // 브랜드 컬러
            ),
            const SizedBox(height: 12),
            const Text(
              '이번 알바는 어땠나요?',
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
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => _submitEvaluation(isGood: true),
                    icon: const Icon(Icons.thumb_up, color: Colors.white),
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
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => _submitEvaluation(isGood: false),
                    icon: const Icon(Icons.thumb_down, color: Colors.white),
                    label: const Text(
                      '별로였어요',
                      style: TextStyle(color: Colors.white),
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

  Future<void> _submitEvaluation({required bool isGood}) async {
    Navigator.pop(context); // 모달 닫기

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken') ?? '';

    final url = Uri.parse('$baseUrl/api/chat/evaluate');
    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'chatRoomId': widget.chatRoomId,
          'evaluate': isGood ? 'good' : 'bad',
        }),
      );


      if (response.statusCode == 200) {
        _showErrorSnackbar('감사합니다! 평가가 반영되었습니다.');
      } else {
        _showErrorSnackbar('평가 전송 실패');
      }
    } catch (e) {
      print('❌ 평가 전송 오류: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }
  // ======================================================
// 1) 상세 화면 열기 (연타 가드 + 디버그 + 안전한 fallback)
// ======================================================
bool _navigatingToDetail = false;

void _openJobDetail() async {
  if (_navigatingToDetail) return;
  final map = _jobInfo ?? widget.jobInfo;
  if (map == null) return;

  // 🔎 원본 상태 로그


  // ✅ 정규화
  final normalized = _normalizeJobMap(map);


  try {
   final job = Job.fromJson(normalized);

    _navigatingToDetail = true;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JobDetailScreen(job: job),
        settings: const RouteSettings(name: '/job-detail'),
      ),
    );
  } catch (e, st) {
    debugPrint('❌ _openJobDetail error: $e\n$st');

    // 🔁 선택적 fallback: 라우트가 id(String)도 받도록 되어 있을 때만 사용
    final rawId = normalized['id'];
    final idStr = rawId?.toString();
    if (idStr != null && idStr.isNotEmpty) {
      try {
        _navigatingToDetail = true;
        await Navigator.pushNamed(context, '/job-detail', arguments: idStr);
      } catch (e2) {
        debugPrint('❌ fallback pushNamed 실패: $e2');
        _showErrorSnackbar('공고 상세를 열 수 없습니다.');
      }
    } else {
      _showErrorSnackbar('공고 상세 정보를 열 수 없습니다.');
    }
  } finally {
    _navigatingToDetail = false;
  }
}

// ======================================================
// 2) 정규화: id는 String, clientId는 int로 추출(+nested 지원)
//    날짜는 DateTime? 반환(네 모델이 String을 원하면 ISO로 바꿔서 넣어도 됨)
// ======================================================
double? _asDouble(dynamic v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  return double.tryParse(s);
}

Map<String, dynamic> _normalizeJobMap(Map<String, dynamic> m) {
  dynamic pick(List keys) {
    for (final k in keys) {
      if (m[k] != null) return m[k];
    }
    return null;
  }

  String? _asString(dynamic v) => v == null ? null : v.toString();
  int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return int.tryParse(s);
  }

  DateTime? parseDateLoose(dynamic v) => _parseDateLoose(v); // 네 헬퍼 재사용

  // ── 공통 id/clientId
  final idStr = _asString(pick(['id', 'job_id', 'jobId']));
  final clientId = _asInt(pick(['client_id', 'clientId'])) ??
      _asInt((pick(['client', 'client_profile', 'clientProfile']) as Map?)?['id']);

  // ── 위치
  final location      = _asString(pick(['location', 'address', 'addr']));
  final locationCity  = _asString(pick(['location_city', 'locationCity', 'city']));
  final lat           = _asDouble(pick(['lat', 'latitude']));
  final lng           = _asDouble(pick(['lng', 'longitude', 'lon']));

  // ── 날짜/시간
  final startDate = parseDateLoose(pick(['start_date', 'startDate']));
  final endDate   = parseDateLoose(pick(['end_date', 'endDate']));
  final startTime = _asString(pick(['start_time', 'startTime']));
  final endTime   = _asString(pick(['end_time', 'endTime']));

  final normalized = <String, dynamic>{
    // id/string
    'id': idStr,

    // client
    'clientId': clientId,
    'client_id': clientId, // ← fromJson이 snake만 볼 수도 있어서 같이 넣음

    // meta
    'title': _asString(pick(['title'])),
    'company': _asString(pick(['client_company_name', 'company'])),
    'status': _asString(pick(['status'])),
    'pay': _asInt(pick(['pay', 'salary', 'wage'])) ?? 0,

    // 위치 (snake+camel 동시에 세팅)
    'location': location,
    'location_city': locationCity,
    'locationCity': locationCity,
    'lat': lat,
    'lng': lng,

    // 기간/시간 (snake+camel)
    'startDate': startDate,
    'endDate': endDate,
    'start_date': startDate,
    'end_date': endDate,
    'startTime': startTime,
    'endTime': endTime,
    'start_time': startTime,
    'end_time': endTime,

    // 장기 알바 요일
    'weekdays': _asString(pick(['weekdays'])),

    // 썸네일/이미지
    'thumbnailUrl': _asString(pick(['thumbnail_url', 'thumbnailUrl'])),
  };


  return normalized;
}
Widget _buildAlbailjuButton({
  required String text,
  required IconData icon,
  required Color color,
  required VoidCallback onPressed,
}) {
  return ElevatedButton.icon(
    style: ElevatedButton.styleFrom(
      backgroundColor: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(30), // 둥글게
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      elevation: 4, // 그림자
    ),
    icon: Icon(icon, size: 20, color: Colors.white),
    label: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 14,
      ),
    ),
    onPressed: onPressed,
  );
}
Widget _buildJobSummary() {
  if (_isLoadingJobInfo || _jobInfo == null) {
    return const SizedBox(); // 또는 로딩 인디케이터
  }

  final jobId = widget.jobInfo['id'] ?? _jobInfo?['id'];

  final jobTitle =
      _jobInfo?['title']?.toString() ??
      widget.jobInfo['title']?.toString() ??
      '공고 제목 없음';

  final jobPayRaw =
      _jobInfo?['pay']?.toString() ??
      widget.jobInfo['pay']?.toString() ??
      '0';
  final int jobPayValue = int.tryParse(jobPayRaw) ?? 0;
  final formattedPay = NumberFormat('#,###').format(jobPayValue);

  // 날짜(start/end): snake/camel 모두 대비
  final startDateRaw = _jobInfo?['start_date'] ?? _jobInfo?['startDate']
      ?? widget.jobInfo['start_date'] ?? widget.jobInfo['startDate'];
  final endDateRaw   = _jobInfo?['end_date']   ?? _jobInfo?['endDate']
      ?? widget.jobInfo['end_date']   ?? widget.jobInfo['endDate'];

  // 시간(start_time/end_time): snake/camel 모두 대비
  final startTimeRaw = _jobInfo?['start_time'] ?? _jobInfo?['startTime']
      ?? widget.jobInfo['start_time'] ?? widget.jobInfo['startTime'];
  final endTimeRaw   = _jobInfo?['end_time']   ?? _jobInfo?['endTime']
      ?? widget.jobInfo['end_time']   ?? widget.jobInfo['endTime'];

  final periodText = _formatPeriod(startDateRaw, endDateRaw);     // ex) 2025-08-20 ~ 2025-08-21
  final timeText   = _formatTimeRange(startTimeRaw, endTimeRaw);  // ex) 오전 9:00 ~ 오후 6:00 (익일)

  final canGoDetail = jobId != null;

  // ── 글 섹션 스타일 유지 ──
  final children = <Widget>[
    // 제목
    Text(
      jobTitle,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      overflow: TextOverflow.ellipsis,
      maxLines: 2,
    ),
    const SizedBox(height: 8),

    // 칩들 (급여 / 근무기간 / 근무시간)
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // 급여: 클릭 없음
        _pill(
          icon: Icons.monetization_on_rounded,
          text: '$formattedPay원',
          bg: Colors.green.shade50,
          fg: Colors.green.shade800,
        ),

        // 근무기간: 상세로 이동
        InkWell(
        onTap: () => _openJobDetail(),
          borderRadius: BorderRadius.circular(999),
          child: _pill(
            icon: Icons.calendar_today,
            text: periodText,
            bg: Colors.indigo.shade50,
            fg: Colors.indigo.shade700,
          ),
        ),

        // 근무시간: 상세로 이동
        InkWell(
  onTap: canGoDetail ? _openJobDetail : null,  // ✅ 여기 통일!
  borderRadius: BorderRadius.circular(999),
  child: _pill(
    icon: Icons.access_time_rounded,
    text: timeText,
    bg: Colors.indigo.shade50,
    fg: Colors.indigo.shade700,
  ),
),
      ],
    ),

    const SizedBox(height: 10),
  ];

  // 버튼 영역 (오른쪽 정렬)
  if (userType == 'client') {
    children.add(
      Align(
        alignment: Alignment.centerRight,
        child: !isConfirmed
            ? _buildAlbailjuButton(
                text: '채용 확정',
                icon: Icons.thumb_up_alt_rounded,
                color: const Color(0xFF1675F4),
                onPressed: _confirmHire,
              )
            : !isCompleted
                ? _buildAlbailjuButton(
                    text: '알바 완료',
                    icon: Icons.check_circle_rounded,
                    color: Colors.green,
                    onPressed: _markJobAsCompleted,
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '✔ 알바 완료됨',
                      style: TextStyle(
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
      ),
    );
  } else if (userType == 'worker') {
    children.add(
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: _hasReviewed
              ? null
              : () {
                  Navigator.pushNamed(
                    context,
                    '/review',
                    arguments: {
                      'jobId': widget.jobInfo['id'],
                      'clientId': widget.jobInfo['client_id'],
                      'jobTitle': widget.jobInfo['title'],
                      'companyName': widget.jobInfo['client_company_name'],
                    },
                  );
                },
          icon: Icon(
            Icons.edit_note,
            size: 18,
            color: _hasReviewed ? Colors.grey : Colors.blue,
          ),
          label: Text(
            _hasReviewed ? '후기 작성 완료' : '후기 남기기',
            style: TextStyle(
              fontSize: 14,
              color: _hasReviewed ? Colors.grey : Colors.blue,
            ),
          ),
        ),
      ),
    );
  }

  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: Colors.grey, width: 0.5)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}
Widget _pill({
  required IconData icon,
  required String text,
  Color? bg,
  Color? fg,
  EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
}) {
  return Container(
    padding: padding,
    decoration: BoxDecoration(
      color: bg ?? Colors.indigo.shade50,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: fg ?? Colors.indigo.shade700),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: fg ?? Colors.indigo.shade700,
          ),
        ),
      ],
    ),
  );
}
String _formatHm(DateTime d) => DateFormat('a h:mm', 'ko_KR').format(d);

// "09:00", "09:00:30", "0900", epoch(ms/sec/us), ISO 등 느슨하게 파싱
DateTime? _parseTimeLoose(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;

  final s = v.toString().trim();
  if (s.isEmpty) return null;

  // 1) 숫자 epoch
  if (RegExp(r'^\d+$').hasMatch(s)) {
    final n = int.parse(s);
    final len = s.length;
    final dtUtc = len >= 16
        ? DateTime.fromMicrosecondsSinceEpoch(n, isUtc: true)
        : len >= 13
            ? DateTime.fromMillisecondsSinceEpoch(n, isUtc: true)
            : DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true);
    return dtUtc.toLocal();
  }

  // 2) HH:mm(:ss)
  final m1 = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$').firstMatch(s);
  if (m1 != null) {
    final h = int.parse(m1.group(1)!);
    final m = int.parse(m1.group(2)!);
    final sec = m1.group(3) != null ? int.parse(m1.group(3)!) : 0;
    return DateTime(1970, 1, 1, h, m, sec);
  }

  // 3) HHmm (예: "0930")
  final m2 = RegExp(r'^(\d{2})(\d{2})$').firstMatch(s);
  if (m2 != null) {
    final h = int.parse(m2.group(1)!);
    final m = int.parse(m2.group(2)!);
    return DateTime(1970, 1, 1, h, m);
  }

  // 4) ISO/그 외
  final dt = DateTime.tryParse(s) ??
      DateTime.tryParse(s.replaceFirst(' ', 'T')) ??
      DateTime.tryParse('${s}Z');
  return dt?.toLocal();
}

int _secondsOfDay(DateTime t) => t.hour * 3600 + t.minute * 60 + t.second;

// ⏰ "근무시간: 오전 9:00 ~ 오후 6:00 (익일)" 형태로 반환
String _formatTimeRange(dynamic startRaw, dynamic endRaw) {
  final s = _parseTimeLoose(startRaw);
  final e = _parseTimeLoose(endRaw);

  if (s == null && e == null) return '시간 미정';
  if (s != null && e == null) return '${_formatHm(s)} ~';
  if (s == null && e != null) return '~ ${_formatHm(e)}';

  final sSec = _secondsOfDay(s!);
  final eSec = _secondsOfDay(e!);
  final crossMidnight = eSec <= sSec; // 자정 넘김 판단

  final base = '${_formatHm(s)} ~ ${_formatHm(e)}';
  return crossMidnight ? '$base (익일)' : base;
}
String _formatDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// 날짜만 온 값(YYYY-MM-DD)은 '로컬 자정'으로, 그 외는 _parseServerTime에 위임
DateTime? _parseDateLoose(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  if (s.isEmpty) return null;

  // YYYY-MM-DD (날짜만) → 로컬 자정으로 안전 파싱
  final dateOnly = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  if (dateOnly.hasMatch(s)) {
    final parts = s.split('-'); // ["yyyy","MM","dd"]
    return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
  }

  // 그 외 포맷은 범용 파서로
  return _parseServerTime(v);
}

/// 근무기간 텍스트: "yyyy-MM-dd ~ yyyy-MM-dd" / 하루면 "yyyy-MM-dd" / 일부 미정 처리
String _formatPeriod(dynamic startRaw, dynamic endRaw) {
  final start = _parseDateLoose(startRaw);
  final end   = _parseDateLoose(endRaw);

  if (start == null && end == null) return '기간 미정';
  if (start != null && end == null) return '${_formatDate(start)} ~';
  if (start == null && end != null) return '~ ${_formatDate(end)}';

  // 둘 다 존재
  if (start!.year == end!.year && start.month == end.month && start.day == end.day) {
    return _formatDate(start); // 하루짜리
  }
  return '${_formatDate(start)} ~ ${_formatDate(end)}';
}

/// 서버/소켓에서 오는 다양한 시각 표현을 '로컬 시간'으로 변환
/// - int(epoch sec/ms/us), 숫자 문자열
/// - ISO8601(타임존 포함/미포함)
/// - "YYYY-MM-DD HH:mm:ss(.SSS)"
DateTime? _parseServerTime(dynamic v) {
  if (v == null) return null;

  DateTime _toLocal(DateTime dt) => dt.toLocal();

  // A) 정수 epoch
  if (v is int) {
    final len = v.toString().length; // 10=sec, 13=ms, 16=us+
    if (len >= 16) return _toLocal(DateTime.fromMicrosecondsSinceEpoch(v, isUtc: true));
    if (len >= 13) return _toLocal(DateTime.fromMillisecondsSinceEpoch(v, isUtc: true));
    return _toLocal(DateTime.fromMillisecondsSinceEpoch(v * 1000, isUtc: true));
  }

  final s = v.toString().trim();
  if (s.isEmpty) return null;

  // B) 숫자 문자열 epoch
  if (RegExp(r'^\d+$').hasMatch(s)) {
    final n = int.tryParse(s);
    if (n != null) return _parseServerTime(n);
  }

  // C) ISO8601 + 타임존(Z 또는 +hh:mm)
  if (RegExp(r'T.*(Z|[+-]\d{2}:\d{2})$').hasMatch(s)) {
    final dt = DateTime.tryParse(s);
    return dt == null ? null : _toLocal(dt);
  }

  // D) ISO8601 (TZ 없음) → 로컬로 해석 (Z 붙이지 않음)
if (RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?$').hasMatch(s)) {
  final dt = DateTime.tryParse('$s+09:00'); // 한국시간 가정
  return dt == null ? null : _toLocal(dt);
}

  // E) "YYYY-MM-DD HH:mm:ss(.SSS)" → 로컬
if (RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(\.\d+)?$').hasMatch(s)) {
  final iso = s.replaceFirst(' ', 'T');
  final dt = DateTime.tryParse('$iso+09:00'); // 한국시간 가정
  return dt == null ? null : _toLocal(dt);
}
if (RegExp(r'^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(\.\d+)?$').hasMatch(s)) {
  return null; // D/E에서 이미 처리되어야 함. 여기까지 오면 포맷 애매 → null
}
  // F) 마지막 시도
  final dt = DateTime.tryParse(s);
  return dt == null ? null : _toLocal(dt);
}
  Widget _buildMessageList(
  VoidCallback? onTap,
  String? thumbnailUrl,
  String? targetName,
) {
  // 1) 공통으로 쓸 '메시지 시각' 결정 함수
DateTime _messageDate(Map<String, dynamic> msg) {
  // 1순위: 정규화된 createdAtMs
  final ms = msg['createdAtMs'];
  if (ms is int) return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();

  // 2순위: 정규화된 createdAt(ISO)
  final createdIso = msg['createdAt'];
  if (createdIso is String) {
    final dt = DateTime.tryParse(createdIso);
    if (dt != null) return dt.toLocal();
  }

  // 3순위: 원본 필드 (과거 호환)
  final dt = _parseServerTime(
    msg['timestamp'] ?? msg['created_at'] ?? msg['sent_at']
  );
  // ❌ 파싱 실패 시 now() 사용 금지 (그룹 오염 방지)
  return dt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true).toLocal();
}

  final now = DateTime.now(); // ← for문 밖(그룹핑 시작 전)에 한 번만
  // 2) 그룹핑
  final Map<String, List<Map<String, dynamic>>> grouped = {};
for (var msg in messages) {
  final date = _messageDate(msg);
  String dateKey;
  if (DateUtils.isSameDay(date, now)) {
    dateKey = '오늘';
  } else if (DateUtils.isSameDay(
    date,
    DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1)),
  )) {
    dateKey = '어제';
  } else {
    dateKey = DateFormat('MM/dd').format(date);
  }
  grouped.putIfAbsent(dateKey, () => []).add(msg);
}

  // 3) 날짜 그룹 정렬(최신이 위)
  final dateKeys = grouped.keys.toList()
    ..sort((a, b) {
      DateTime top(String key) {
        final list = grouped[key]!;
        list.sort((m1, m2) => _messageDate(m2).compareTo(_messageDate(m1)));
        return _messageDate(list.first);
      }
      return top(b).compareTo(top(a));
    });

  return ListView.builder(
    controller: _scrollController,
    itemCount: dateKeys.length,
    itemBuilder: (context, dateIndex) {
      final dateKey = dateKeys[dateIndex];
      final dayMessages = grouped[dateKey]!
        ..sort((m1, m2) => _messageDate(m1).compareTo(_messageDate(m2))); // 당일 내 오름차순

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: Text(
              dateKey,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          ...List.generate(dayMessages.length, (index) {
            final msg = dayMessages[index];
            final isMe = msg['sender'] == (userType == 'worker' ? 'worker' : 'client');
            final isTarget = !isMe;
            final messageText = msg['message']?.toString() ?? '';
            final isPrevSameSender = index > 0 &&
                dayMessages[index - 1]['sender'] == msg['sender'];

            final thumb = userType == 'worker'
                ? widget.jobInfo['client_thumbnail_url']?.toString()
                : widget.jobInfo['user_thumbnail_url']?.toString();
            final name = userType == 'worker'
                ? widget.jobInfo['client_company_name']?.toString() ?? '기업'
                : widget.jobInfo['user_name']?.toString() ?? '알바생';

            final when = _messageDate(msg); // ← 여기서도 동일 기준 사용

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                children: [
                  if (isTarget && !isPrevSameSender) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: onTap ?? () {},
                      child: CircleAvatar(
                        radius: 16,
                        backgroundImage: (thumb != null && thumb.isNotEmpty)
                            ? NetworkImage(thumb)
                            : null,
                        child: (thumb == null || thumb.isEmpty)
                            ? const Icon(Icons.person, size: 16)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ] else if (isTarget && isPrevSameSender) ...[
                    const SizedBox(width: 48),
                  ],
                  Flexible(
                    child: Column(
                      crossAxisAlignment:
                          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        if (isTarget && !isPrevSameSender)
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isMe ? Colors.indigo[100] : Colors.grey[300],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: (msg['imageUrl'] != null &&
                                  msg['imageUrl'].toString().isNotEmpty)
                              ? _ChatImageBubble(
                                  imageUrl: msg['imageUrl'].toString(),
                                  heroTag: 'img_${when.millisecondsSinceEpoch}',
                                )
                              : Text(messageText),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 12, bottom: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment:
                                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                            children: [
                              Text(
                                DateFormat('a h:mm', 'ko_KR').format(when),
                                style: const TextStyle(fontSize: 10, color: Colors.grey),
                              ),
                              if (isMe) ...[
                                const SizedBox(width: 8),
                                Text(
                                  (msg['is_read'] == 1 || msg['is_read'] == true)
                                      ? '읽음'
                                      : '안읽음',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: (msg['is_read'] == 1 || msg['is_read'] == true)
                                        ? Colors.blue
                                        : Colors.grey,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      );
    },
  );
}


  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
Widget _buildClientWaitingBanner() {
  final shouldShow = userType == 'client' && _status == 'pending';
  if (!shouldShow) return const SizedBox.shrink();
  return Container(
    color: const Color(0xFFFFF8E1),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    child: Row(
      children: const [
        Icon(Icons.hourglass_bottom, size: 18),
        SizedBox(width: 8),
        Expanded(child: Text('구직자의 수락을 기다리는 중입니다. 메세지 전송은 수락 후 가능합니다.')),
      ],
    ),
  );
}
Widget _buildConsentBanner() {
  final bool shouldShow =
      userType == 'worker' && _status == 'pending' && _initiator == 'client';

  if (!shouldShow) return const SizedBox.shrink();

  return Container(
    color: const Color(0xFFFEF3C7), // 연한 노랑
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    child: Row(
      children: [
        const Icon(Icons.info_outline, size: 18),
        const SizedBox(width: 8),
        const Expanded(child: Text('기업의 대화 요청입니다. 수락하시겠어요?')),
        const SizedBox(width: 8),
        TextButton(
          onPressed: _consentBusy ? null : () => _sendConsent(false),
          child: const Text('거절', style: TextStyle(color: Colors.red)),
        ),
        const SizedBox(width: 4),
        ElevatedButton(
          onPressed: _consentBusy ? null : () => _sendConsent(true),
          child: _consentBusy
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('수락'),
        ),
      ],
    ),
  );
}
  @override
  Widget build(BuildContext context) {
    String? targetName;
    String? targetThumbnailUrl;
    VoidCallback? onTap;

    if (userType == 'client') {
      targetName = widget.jobInfo['user_name']?.toString();
      targetThumbnailUrl = widget.jobInfo['user_thumbnail_url']?.toString();

      // ⭐️ 항상 int로 변환해서 넘기기
      final dynamic rawWorkerId = widget.jobInfo['worker_id'];
      final int? workerId =
          (rawWorkerId is int)
              ? rawWorkerId
              : int.tryParse(rawWorkerId?.toString() ?? '');

      if (workerId != null) {
        onTap = () {
          Navigator.pushNamed(context, '/worker-profile', arguments: workerId);
        };
      }
    } else {
      final company = widget.jobInfo['client_company_name']?.toString() ?? '기업';
      targetName = company;
      targetThumbnailUrl = widget.jobInfo['client_thumbnail_url']?.toString();

      final dynamic rawClientId = widget.jobInfo['client_id'];
      final int? clientId =
          (rawClientId is int)
              ? rawClientId
              : int.tryParse(rawClientId?.toString() ?? '');

      if (clientId != null) {
        onTap = () {
          Navigator.pushNamed(context, '/client-profile', arguments: clientId);
        };
      }
    }

    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, 'updated');
        return false;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent, // 이거 있으면 빈 공간도 인식 잘 됨!
        onTap: () {
          FocusScope.of(context).unfocus(); // 🔥 키보드 내림!
        },
        child: Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                GestureDetector(
                  onTap: onTap ?? () {}, // null 안전 처리
                  child: CircleAvatar(
                    radius: 20,
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
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    targetName ?? '상대방',
                    style: const TextStyle(fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                Navigator.pop(context, 'updated');
              },
            ),
          ),

          body: Column(
            children: [
              _buildJobSummary(),
                  // ✅ 워커가 보는 수락/거절 배너
    _buildConsentBanner(),
    _buildClientWaitingBanner(),
             Expanded(
  child: isLoading
      ? const Center(child: CircularProgressIndicator())
      : NotificationListener<ScrollStartNotification>(
          onNotification: (_) {
            FocusScope.of(context).unfocus(); // ★ 추가
            return false;
          },
          child: _buildMessageList(onTap, targetThumbnailUrl, targetName),
        ),
),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                     Expanded(
  child: TextField(
  controller: _messageController,
  enabled: _inputEnabled,
  onTapOutside: (_) => FocusScope.of(context).unfocus(), // ★ 추가
  decoration: InputDecoration(
    hintText: _inputEnabled ? '메시지를 입력하세요...' : '상대방의 수락을 기다리는 중입니다',
  ),
  onSubmitted: (_) => _sendMessage(),
),
),
                    IconButton(
  icon: const Icon(Icons.image),
  onPressed: _inputEnabled ? _pickAndSendImage : null, // ✅
),
IconButton(
  icon: const Icon(Icons.send),
  onPressed: _inputEnabled ? _sendMessage : null, // ✅
),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _ChatImageBubble extends StatelessWidget {
  final String imageUrl;
  final String heroTag;

  const _ChatImageBubble({
    required this.imageUrl,
    required this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ChatImageScreen(
        imageUrl: imageUrl,
        heroTag: heroTag,
      ),
    ),
  );
},
      child: Hero(
        tag: heroTag,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            width: 200,
            height: 200,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              width: 200,
              height: 200,
              alignment: Alignment.center,
              color: Colors.black12,
              child: const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            errorWidget: (_, __, ___) => Container(
              width: 200,
              height: 200,
              alignment: Alignment.center,
              color: Colors.black12,
              child: const Icon(Icons.broken_image),
            ),
          ),
        ),
      ),
    );
  }
}