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
import 'package:geolocator/geolocator.dart';
import 'dart:async'; // TimeoutException
import 'dart:math' as math; // ✅ Math -> math 로 사용
import 'package:iljujob/utiles/keyboard_mode.dart'; // ✅ 추가
import 'dart:ui';

const kBrandBlue = Color(0xFF3B8AFF); // 이미 있으면 중복 정의 말고 기존 거 사용!

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
  final FocusNode _inputFocusNode = FocusNode(); // ✅ 추가
  List<Map<String, dynamic>> messages = [];
  bool isLoading = true;
  String userType = 'worker';
  IO.Socket? socket;
  bool isConfirmed = false;
  bool isCompleted = false; // ✅ 이 줄 추가
  bool _hasReviewed = false;
  Map<String, dynamic>? _jobInfo; // 🔴 빨간줄 해결
  bool _isLoadingJobInfo = true; // 🔴 빨간줄 해결
  bool _workerWorkConfirmed = false; // worker_confirmed_at != null
  bool _workLoading = false;
bool _canCancel = false;           // 취소 가능 여부
String? _workError;   
bool _hasWorkSession = false; // 캘린더(내부 worker_session) 존재 여부
int? _workSessionId;          // 있으면 저장(선택)             // (선택) 디버그용
int? _roomWorkerId;
int? _roomClientId;
bool _checkinLoading = false;
bool _checkedIn = false;
int? _checkinDistanceM;
int? _checkinRadiusM;
bool _claimLoading = false;
bool _hasClaim = false;
String? _claimStatus; // pending/approved/rejected
String? _claimError;
bool get _isClient => userType == 'client';


bool _asBool(dynamic v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v.toString().trim().toLowerCase();
  return s == 'true' || s == '1' || s == 'yes' || s == 'y';
}

bool get _isWeekdaysJob {
  final info = _jobSource();
  final s = (info['weekdays'] ?? info['weekday'] ?? info['days'] ?? '').toString().trim();
  return s.isNotEmpty;
}

bool get _isPaidJob {
  final info = _jobSource();
  return _asBool(info['is_paid']) || _asBool(info['isPaid']) || (info['is_paid'] == 1);
}

// 채용 확정 기준(너 서버에서 status=active로 오니까 그걸 우선)
bool get _isHiredActive => (_status == 'active' || _status == 'confirmed');

// 체크인 완료면 노쇼 신청 불가
bool get _canRequestNoShowClaim {
  if (!_isClient) return false;
  if (!_isHiredActive) return false;
  if (_isWeekdaysJob) return false;
  if (!_isPaidJob) return false;
  if (_checkedIn) return false;         // 출근확인 됐으면 노쇼 X
  if (_hasClaim) return false;          // 이미 신청했으면 X
  if (_claimLoading) return false;
  if (_status == 'blocked' || _status == 'expired' || _status == 'cancelled' || _status == 'canceled') return false;
  return true;
}

String? _checkinError; // 선택

double? _myLat;
double? _myLng;
double? _myAcc;
int? _myDistanceToJobM;
String? _geoError;
bool _geoLoading = false;
bool _claimRefunded = false;
int? _claimId;
DateTime? _lastGeoAt; // ✅ 마지막 위치 갱신 시간
bool get _geoFresh {
  if (_lastGeoAt == null) return false;
  return DateTime.now().difference(_lastGeoAt!).inSeconds <= 30; // 30초
}

bool get _isHireConfirmed {
  // 소켓 이벤트로 들어온 isConfirmed + workState 기반 확정 둘 다 인정
  return isConfirmed || _workerWorkConfirmed;
}

bool get _showWorkerCheckinUI {
  if (userType != 'worker') return false;
  if (!_isHireConfirmed) return false;       // ✅ 채용확정 전엔 숨김
  if (_status != 'active') return false;     // 안전장치
  return true;
}
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
double _toRad(double x) => x * math.pi / 180.0;

int _haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  const R = 6371000.0; // meters
  final dLat = _toRad(lat2 - lat1);
  final dLng = _toRad(lng2 - lng1);

  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRad(lat1)) * math.cos(_toRad(lat2)) *
          (math.sin(dLng / 2) * math.sin(dLng / 2));

  final c = 2 * math.asin(math.sqrt(a));
  return (R * c).round();
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
  // 지원 취소 / 차단 / 만료 상태면 모두 입력 불가
  if (_status == 'cancelled' ||
      _status == 'canceled' ||
      _status == 'blocked'  ||
      _status == 'expired') {
    return false;
  }

  // 클라이언트 + pending 이면 대기 상태
  if (userType == 'client' && _status == 'pending') return false;

  return true;
}
bool _shouldShowHireNudge() {
  if (userType != 'client') return false;
  if (_status != 'active') return false;
  if (isConfirmed == true) return false;
  if (messages.length < 4) return false;

  bool clientSpoke = false;
  bool workerSpoke = false;

  for (final m in messages) {
    final s = (m['sender'] ?? '').toString();
    if (s == 'client') clientSpoke = true;
    if (s == 'worker') workerSpoke = true;
  }

  return clientSpoke && workerSpoke;
}

// 워커가 수락/거절 버튼을 봐야 하는지
bool get _workerSeeConsentButtons =>
    (userType == 'worker') && (_initiator == 'client') && (_status == 'pending');

// 클라이언트가 대기 배너를 봐야 하는지
bool get _clientSeeWaitingBanner =>
    (userType == 'client') && (_status == 'pending');
Map<String, dynamic> _normalizeIncoming(Map raw) {
  // 서버/클라이언트에서 올 수 있는 여러 이름들 대응
  final createdRaw =
      raw['createdAt'] ?? raw['created_at'] ?? raw['timestamp'] ?? raw['sent_at'];

  // 1) 밀리초로 통일
  int createdAtMs = _toMs(createdRaw);

  // 2) 만약 서버가 시간을 안 보내줬거나 파싱 실패해서 0이 나오면 → 지금 시각으로 보정
  if (createdAtMs == 0) {
    createdAtMs = DateTime.now().toUtc().millisecondsSinceEpoch;
  }

  // 3) ISO 문자열도 UTC 기준으로 하나 만들어 둠
  final createdIso = DateTime.fromMillisecondsSinceEpoch(
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

    // 읽음 여부
    'is_read': (raw['is_read'] == 1 || raw['is_read'] == true),

    // 통일된 시간 필드 2종
    'createdAt': createdIso,        // ISO(UTC)
    'createdAtMs': createdAtMs,     // 정렬·표시용 밀리초

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
    KeyboardMode.setAdjustResize(); // ✅ 채팅창 진입 시
    _connectToSocket();
    _fetchChatRoomDetail().then((_) {
      
      _initializeChat(); // 메시지는 상세정보 받은 후에
      _checkIfReviewed();
      _loadJobInfo();
      _refreshLocationAndDistance(); // ✅ 추가
       _fetchWorkState(); // ✅ 추가
      _fetchCheckinStatus(); // ✅ 추가
      _fetchNoShowClaimState(); // ✅ 추가
       
    });
  }
  @override
  void dispose() {
    KeyboardMode.setAdjustPan(); // ✅ 채팅창 나갈 때 복구
    socket?.clearListeners();

    socket?.disconnect();
    socket = null;
    _scrollController.dispose();
     _inputFocusNode.dispose(); // ✅ 추가
     _messageController.dispose(); // ✅ 추가
    super.dispose();
  }
@override
void didChangeDependencies() {
  super.didChangeDependencies();
  Future.microtask(_ensureConnect); // ✅ 이걸로
}
Future<void> _fetchNoShowClaimState() async {
  final info = _jobSource();
  final jobIdRaw = info['id'] ?? info['job_id'] ?? info['jobId'];
  final jobId = int.tryParse(jobIdRaw?.toString() ?? '');
  if (jobId == null) return;

  try {
    final uri = Uri.parse('$baseUrl/api/attendance/no-show-claim-status?jobId=$jobId');

    final res = await http.get(uri, headers: await _authHeaders());

    // ✅ 401/403/404도 로그 남겨야 원인 바로 잡힘
    if (res.statusCode != 200) {
      debugPrint('❌ [claimState] ${res.statusCode} ${res.body}');
      if (!mounted) return;
      setState(() => _claimError = 'state ${res.statusCode}');
      return;
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map) return;

    // ✅ 서버가 NO_CLAIM 형태로 주는 경우도 처리
    final msg = (decoded['message'] ?? '').toString();
    if (msg == 'NO_CLAIM' || _asBool(decoded['exists']) == false) {
      if (!mounted) return;
      setState(() {
        _hasClaim = false;
        _claimStatus = null;
        _claimRefunded = false;
        _claimId = null;
        _claimError = null;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _hasClaim = _asBool(decoded['exists']);
      _claimStatus = (decoded['status'] ?? '').toString();
      _claimRefunded = _asBool(decoded['refunded_pass']) || decoded['refunded_pass'] == 1;
      _claimId = int.tryParse((decoded['claimId'] ?? '').toString());
      _claimError = null;
    });
  } catch (e) {
    debugPrint('💥 [claimState] error: $e');
    if (!mounted) return;
    setState(() => _claimError = '$e');
  }
}
Future<void> _refreshLocationAndDistance() async {
  if (_geoLoading) return;
  setState(() {
    _geoLoading = true;
    _geoError = null;
  });

  try {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      setState(() => _geoError = '위치 권한이 꺼져 있어요(설정에서 허용 필요).');
      return;
    }
    if (perm == LocationPermission.denied) {
      setState(() => _geoError = '위치 권한이 필요해요.');
      return;
    }

    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      setState(() => _geoError = 'GPS가 꺼져 있어요. 위치 서비스를 켜주세요.');
      return;
    }

    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
      timeLimit: const Duration(seconds: 10),
    );

    final info = _jobSource();
    final jobLat = double.tryParse((info['lat'] ?? '').toString());
    final jobLng = double.tryParse((info['lng'] ?? '').toString());

    debugPrint('📍 [geo] my=${pos.latitude},${pos.longitude} acc=${pos.accuracy}');
    debugPrint('🏁 [geo] job=$jobLat,$jobLng');

    int? dist;
    if (jobLat != null && jobLng != null) {
      dist = _haversineMeters(jobLat, jobLng, pos.latitude, pos.longitude);
      debugPrint('📏 [geo] dist=$dist m');
    }

    if (!mounted) return;
    setState(() {
      _myLat = pos.latitude;
      _myLng = pos.longitude;
      _myAcc = pos.accuracy;
      _myDistanceToJobM = dist;
      _lastGeoAt = DateTime.now(); // ✅ 캐시 타임 저장
    });
  } catch (e) {
    if (!mounted) return;
    setState(() => _geoError = '위치 확인 실패: $e');
  } finally {
    if (mounted) setState(() => _geoLoading = false);
  }
}

Future<void> _requestNoShowClaim() async {
  if (!_canRequestNoShowClaim) return;

  final info = _jobSource();
  final jobIdRaw = info['id'] ?? info['job_id'] ?? info['jobId'];
  final jobId = int.tryParse(jobIdRaw?.toString() ?? '');
  if (jobId == null) {
    _showErrorSnackbar('공고 정보를 찾을 수 없습니다.');
    return;
  }

  setState(() {
    _claimLoading = true;
    _claimError = null;
  });

  try {
    final uri = Uri.parse('$baseUrl/api/attendance/no-show-claims');

    final body = {
      'jobId': jobId,
      // workerId는 선택. 서버가 필요하면 넣고, 아니면 빼도 됨
      'workerId': _roomWorkerId, 
      'note': '채팅방에서 신청',
    };

    final res = await http.post(
      uri,
      headers: await _authHeaders(json: true),
      body: jsonEncode(body),
    );

    Map<String, dynamic> data = {};
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {}

    if (!mounted) return;

    if (res.statusCode == 200 && data['message'] == 'CLAIM_CREATED') {
      setState(() {
        _hasClaim = true;
        _claimStatus = 'pending';
        _claimLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('노쇼 환급 신청이 접수되었습니다.')),
      );

      // 채팅에 시스템 안내 메시지(선택)
      _upsertMessage({
        'sender': 'system',
        'message': '📌 사장님이 노쇼 환급 신청을 접수했어요. (검토 후 이용권이 반환됩니다)',
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });

      return;
    }

    // 실패 메시지 매핑
    final msg = (data['message'] ?? 'UNKNOWN').toString();

    String uiMsg = '신청 실패: $msg';
    if (msg == 'CLAIM_NOT_AVAILABLE_YET') uiMsg = '아직 신청 가능 시간이 아니에요.';
    if (msg == 'ALREADY_CHECKED_IN') uiMsg = '출근 확인이 완료되어 환급 신청이 불가해요.';
    if (msg == 'PASS_USAGE_NOT_FOUND') uiMsg = '이용권 사용 기록이 없어 환급이 불가해요.';
    if (msg == 'FREE_JOB_NO_REFUND') uiMsg = '무료 공고는 환급 대상이 아니에요.';
    if (msg == 'CLAIM_ALREADY_EXISTS') uiMsg = '이미 환급 신청이 진행 중이에요.';

    setState(() {
      _claimError = uiMsg;
      _claimLoading = false;
    });
    _showErrorSnackbar(uiMsg);

  } catch (e) {
    if (!mounted) return;
    setState(() {
      _claimError = '네트워크 오류: $e';
      _claimLoading = false;
    });
    _showErrorSnackbar('네트워크 오류: $e');
  } finally {
    if (mounted) setState(() => _claimLoading = false);
  }
}


Future<void> _fetchWorkState() async {
  debugPrint('🧭 [workState] start roomId=${widget.chatRoomId}');

  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('authToken') ?? '';

  debugPrint('🔑 [workState] tokenLen=${token.length}');

  if (token.isEmpty) {
    if (!mounted) return;
    setState(() => _workError = 'token empty');
    debugPrint('❌ [workState] token empty');
    return;
  }

  final uri = Uri.parse('$baseUrl/api/chat/work-session-state?roomId=${widget.chatRoomId}');
  debugPrint('🌐 [workState] GET $uri');

  try {
    final resp = await http.get(uri, headers: {'Authorization': 'Bearer $token'});

    debugPrint('📡 [workState] status=${resp.statusCode}');
    debugPrint('📦 [workState] body=${resp.body}');

    if (!mounted) return;

    if (resp.statusCode != 200) {
      setState(() => _workError = 'state ${resp.statusCode}: ${resp.body}');
      return;
    }

    final data = jsonDecode(resp.body);
    if (data is! Map) {
      setState(() => _workError = 'invalid json: ${resp.body}');
      return;
    }

    bool asBool(dynamic v) {
      if (v == null) return false;
      if (v is bool) return v;
      if (v is num) return v != 0;
      final s = v.toString().trim().toLowerCase();
      return s == 'true' || s == '1' || s == 'yes' || s == 'y';
    }

    final confirmed =
        asBool(data['confirmed']) ||
        asBool(data['workerConfirmed']) ||
        asBool(data['worker_confirmed']) ||
        (data['worker_confirmed_at'] != null) ||
        (data['confirmed_at'] != null) ||
        (data['confirmedAt'] != null);

    final canCancel =
        asBool(data['canCancel']) ||
        asBool(data['can_cancel']) ||
        asBool(data['cancelable']) ||
        asBool(data['isCancelable']);

    final sessionIdRaw = data['sessionId'] ?? data['workSessionId'] ?? data['id'];
    final sessionId = int.tryParse(sessionIdRaw?.toString() ?? '');
    final hasSession =
        asBool(data['hasSession']) ||
        asBool(data['has_session']) ||
        (sessionId != null);


    setState(() {
      _workerWorkConfirmed = confirmed;
      _canCancel = canCancel;
      _hasWorkSession = hasSession;
      _workSessionId = sessionId;
      _workError = null;
    });
  } catch (e) {
    debugPrint('💥 [workState] exception: $e');
    if (!mounted) return;
    setState(() => _workError = 'state error: $e');
  }
}
Future<void> _fetchCheckinStatus() async {
  final jobId = int.tryParse(
    (_pick(_jobSource(), ['id', 'job_id', 'jobId']) ?? '').toString(),
  );
  if (jobId == null) return;

  try {
    final uri = Uri.parse('$baseUrl/api/attendance/checkin-status?jobId=$jobId');
    final res = await http.get(uri, headers: await _authHeaders());

    if (res.statusCode != 200) {
      debugPrint('❌ [checkinStatus] status=${res.statusCode} body=${res.body}');
      return;
    }

    final data = jsonDecode(res.body);
    if (data is! Map) return;

    if (data['message'] == 'CHECKIN_STATUS' && data['status'] == 'success') {
      if (!mounted) return;
      setState(() {
        _checkedIn = true;
        _checkinDistanceM = data['distance_m'];
        _checkinRadiusM = data['radius_m'];
      });
    }
  } catch (e) {
    debugPrint('💥 [checkinStatus] error: $e');
  }
}
Future<void> _checkinNow() async {
  if (_checkinLoading) return;

  final info = _jobSource();
  final weekdays = (info['weekdays'] ?? '').toString().trim();
  if (weekdays.isNotEmpty) {
    _showErrorSnackbar('요일 공고는 출근확인이 아직 지원되지 않습니다.');
    return;
  }

  final jobIdRaw = _pick(info, ['id', 'job_id', 'jobId']);
  final jobId = int.tryParse(jobIdRaw?.toString() ?? '');
  if (jobId == null) {
    _showErrorSnackbar('공고 정보를 찾을 수 없습니다.');
    return;
  }

  setState(() => _checkinLoading = true);

  try {
    // 권한/GPS 최소 체크
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.deniedForever) {
      _showErrorSnackbar('위치 권한이 필요합니다. 설정에서 허용해 주세요.');
      return;
    }
    if (perm == LocationPermission.denied) {
      _showErrorSnackbar('위치 권한이 필요합니다.');
      return;
    }

    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      _showErrorSnackbar('GPS가 꺼져 있습니다. 위치 서비스를 켜주세요.');
      return;
    }

    // ✅ 1) 채팅방 들어오며 캐시된 위치가 최신이면 그거 사용
    if (!_geoFresh || _myLat == null || _myLng == null) {
      await _refreshLocationAndDistance();
    }

    if (_myLat == null || _myLng == null) {
      _showErrorSnackbar('현재 위치를 가져올 수 없습니다. 잠시 후 다시 시도해 주세요.');
      return;
    }

    final body = {
      'jobId': jobId,
      'lat': _myLat,
      'lng': _myLng,
      'accuracy_m': _myAcc,
    };

    final uri = Uri.parse('$baseUrl/api/attendance/checkin');
    final res = await http.post(
      uri,
      headers: await _authHeaders(json: true),
      body: jsonEncode(body),
    );

    Map<String, dynamic> data = {};
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {}

    final msg = (data['message'] ?? 'UNKNOWN').toString();

    if (res.statusCode == 200 && msg == 'CHECKIN_OK') {
      if (!mounted) return;
      setState(() {
        _checkedIn = true;
        _checkinDistanceM = data['distance_m'];
        _checkinRadiusM = data['radius_m'];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('출근 확인 완료! (${_checkinDistanceM ?? ''}m)')),
      );
      return;
    }

    if (msg == 'OUT_OF_RADIUS') {
      _showErrorSnackbar('현장 반경 밖입니다. (${data['distance_m']}m / ${data['radius_m']}m)');
      return;
    }
    if (msg == 'LOW_GPS_ACCURACY') {
      _showErrorSnackbar('GPS 정확도가 낮아요. (${data['accuracy_m']}m) 밖에서 다시 시도해 주세요.');
      return;
    }
    if (msg == 'CHECKIN_DEADLINE_PASSED') {
      _showErrorSnackbar('출근 확인 가능 시간이 지났습니다.');
      return;
    }
    if (msg == 'JOB_LOCATION_MISSING') {
      _showErrorSnackbar('공고 위치 정보가 없어 출근 확인이 불가합니다.');
      debugPrint('❌ [checkin] status=${res.statusCode} body=${res.body}');
      return;
    }
    if (msg == 'LONG_TERM_NOT_SUPPORTED_YET') {
      _showErrorSnackbar('요일 공고 출근확인은 아직 지원되지 않습니다.');
      return;
    }
    if (msg == 'CLAIM_ALREADY_EXISTS') {
      _showErrorSnackbar('이미 환급 요청이 진행 중이라 출근 확인이 막혀 있습니다.');
      return;
    }
    if (msg == 'JOB_NOT_ACTIVE') {
      _showErrorSnackbar('진행 중인 공고가 아닙니다.');
      return;
    }

    _showErrorSnackbar('출근 확인 실패: $msg');
  } on TimeoutException {
    _showErrorSnackbar('위치 확인이 지연되고 있어요. 다시 시도해 주세요.');
  } catch (e) {
    _showErrorSnackbar('출근 확인 중 오류: $e');
  } finally {
    if (mounted) setState(() => _checkinLoading = false);
  }
}
Future<String?> _getAuthToken() async {
  final prefs = await SharedPreferences.getInstance();
  final t = prefs.getString('authToken');
  if (t == null || t.trim().isEmpty) return null;
  return t;
}

Future<Map<String, String>> _authHeaders({bool json = false}) async {
  final token = await _getAuthToken();

  final h = <String, String>{};
  if (json) h['Content-Type'] = 'application/json';
  if (token != null) h['Authorization'] = 'Bearer $token';

  return h;
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
  final dynamic rawJobId =
      widget.jobInfo['id'] ?? widget.jobInfo['job_id'] ?? widget.jobInfo['jobId'];

  final jobId = int.tryParse(rawJobId?.toString() ?? '');
  
  if (jobId == null) {
    debugPrint('❌ jobId 없음: jobInfo=${
      widget.jobInfo.keys.toList()
    }');
    if (!mounted) return;
    setState(() => _isLoadingJobInfo = false);
    return;
  }

  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('authToken') ?? '';

  try {
    final response = await http.get(
      Uri.parse('$baseUrl/api/job/$jobId'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (!mounted) return;

    if (response.statusCode == 200) {
      final job = jsonDecode(response.body);
      setState(() {
        _jobInfo = (job is Map) ? Map<String, dynamic>.from(job) : null;
        _isLoadingJobInfo = false;
      });
        debugPrint('📦 /api/job/$jobId response start_date=${(job as Map?)?['start_date']} start_time=${(job as Map?)?['start_time']} created_at=${(job as Map?)?['created_at']}');
    } else {
      debugPrint('❌ /api/job/$jobId 실패: ${response.statusCode} ${response.body}');
      setState(() => _isLoadingJobInfo = false);
    }
  } catch (e) {
    debugPrint('❌ _loadJobInfo 예외: $e');
    if (!mounted) return;
    setState(() => _isLoadingJobInfo = false);
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
      setState(() => _isLoadingJobInfo = false);
      return;
    }

    final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
    if (decoded is! Map) {
      debugPrint('❌ 잘못된 응답 형식: ${resp.body}');
      if (!mounted) return;
      setState(() => _isLoadingJobInfo = false);
      return;
    }

    final status = (decoded['roomStatus'] ?? decoded['status'] ?? 'active').toString();
    final initiator = (decoded['initiatorType'] ?? decoded['initiator_type'] ?? 'client').toString();

    bool _asBool(dynamic v) {
      if (v == null) return false;
      if (v is bool) return v;
      if (v is num) return v != 0;
      final s = v.toString().toLowerCase();
      return s == 'true' || s == '1' || s == 'yes';
    }

    final app = decoded['application'] is Map ? (decoded['application'] as Map) : null;
    final bool confirmed =
        _asBool(decoded['is_confirmed']) || _asBool(app?['isConfirmed']) || _asBool(app?['is_confirmed']);
    final bool completed =
        _asBool(decoded['is_completed']) || _asBool(app?['isCompleted']) || _asBool(app?['is_completed']);

    final int? workerId = int.tryParse((decoded['workerId'] ?? decoded['worker_id'])?.toString() ?? '');
    final int? clientId = int.tryParse((decoded['clientId'] ?? decoded['client_id'])?.toString() ?? '');

    debugPrint('✅ [chatDetail] parsed workerId=$workerId clientId=$clientId status=$status initiator=$initiator');

    Map<String, dynamic> jobInfo = {};
    if (decoded['job'] is Map) {
      jobInfo = Map<String, dynamic>.from(decoded['job'] as Map);
      if (jobInfo['job_id'] == null && jobInfo['id'] != null) {
        jobInfo['job_id'] = jobInfo['id'];
      }
    } else {
      jobInfo = {
        if (decoded['job_id'] != null) 'id': decoded['job_id'],
        if (decoded['title'] != null) 'title': decoded['title'],
        if (decoded['job_title'] != null) 'title': decoded['job_title'],
        if (decoded['pay'] != null) 'pay': decoded['pay'],
        if (decoded['created_at'] != null) 'created_at': decoded['created_at'],
        if (decoded['client_company_name'] != null) 'client_company_name': decoded['client_company_name'],
      }..removeWhere((_, v) => v == null);
    }

    // (선택) _jobInfo에도 심어두되, “진짜 소스”는 아래 roomId state
    if (workerId != null) {
      jobInfo['worker_id'] = workerId;
      jobInfo['workerId'] = workerId;
    }
    if (clientId != null) {
      jobInfo['client_id'] = clientId;
      jobInfo['clientId'] = clientId;
    }

    if (!mounted) return;
    setState(() {
      _status = status;
      _initiator = initiator;

      isConfirmed = confirmed;
      isCompleted = completed;

      _roomWorkerId = workerId;
      _roomClientId = clientId;

      _jobInfo = {
        ...?widget.jobInfo,
        ...jobInfo,
      };

      _isLoadingJobInfo = false;
    });

    debugPrint('✅ [chatDetail] saved _roomWorkerId=$_roomWorkerId _roomClientId=$_roomClientId');
  } catch (e) {
    debugPrint('❌ 상세 정보 요청 중 오류: $e');
    if (!mounted) return;
    setState(() => _isLoadingJobInfo = false);
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
   _scrollToBottom(initial: true);
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
    final fixed = <String, dynamic>{
      ...resp,
      if (resp['image_url'] != null) 'imageUrl': resp['image_url'],
      if (resp['created_at'] != null && resp['createdAt'] == null) 'createdAt': resp['created_at'],
      'clientTempId': resp['clientTempId'] ?? clientTempId,
      'createdAt': resp['createdAt'] ?? nowIso,
    };
    _upsertMessage(fixed);
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
Future<bool> _confirmStartWork() async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('authToken') ?? '';
  if (token.isEmpty) {
    _showErrorSnackbar('로그인 정보가 없습니다.');
    return false;
  }

  final info = (_jobInfo ?? widget.jobInfo ?? <String, dynamic>{});
 debugPrint('🧩 [confirm] widget.jobInfo start_date=${widget.jobInfo['start_date']} start_time=${widget.jobInfo['start_time']} id=${widget.jobInfo['id']}');
  debugPrint('🧩 [confirm] _jobInfo start_date=${_jobInfo?['start_date']} start_time=${_jobInfo?['start_time']} id=${_jobInfo?['id']}');
  debugPrint('🧩 [confirm] merged info keys=${info.keys.toList()}');
  final jobIdRaw = info['job_id'] ?? info['jobId'] ?? info['id'];
  final applicationIdRaw = info['application_id'] ?? info['applicationId'];

  final jobId = int.tryParse(jobIdRaw?.toString() ?? '');
  final applicationId = int.tryParse(applicationIdRaw?.toString() ?? '');

  // start_at을 문자열로 확정해서 보내면 서버에서 Date 변환하다 터질 일이 확 줄어듦
  // (네가 jobInfo에 start_date/start_time을 갖고 있다는 전제)
  final startDate = (info['start_date'] ?? info['startDate'])?.toString(); // "YYYY-MM-DD"
  final startTime = (info['start_time'] ?? info['startTime'])?.toString(); // "HH:mm" or "HH:mm:ss"
  String? startAt;
  if (startDate != null && startDate.length >= 10 && startTime != null && startTime.isNotEmpty) {
    final t = startTime.length == 5 ? '$startTime:00' : startTime.substring(0, 8);
    startAt = '${startDate.substring(0, 10)} $t'; // "YYYY-MM-DD HH:mm:ss"
  }

  try {
    final body = <String, dynamic>{
      'roomId': widget.chatRoomId,
      if (jobId != null) 'jobId': jobId,
      if (applicationId != null) 'applicationId': applicationId,
      if (startAt != null) 'startAt': startAt,
      // 필요하면 endAt도 같이 (없으면 서버에서 startAt+4시간 같은 기본값)
      // if (endAt != null) 'endAt': endAt,
    };

    final resp = await http.post(
      Uri.parse('$baseUrl/api/chat/confirm-work'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    print('status=${resp.statusCode}');
    print('body=${resp.body}');

   if (resp.statusCode == 200 || resp.statusCode == 409) {
  await _fetchWorkState(); // ✅ 이걸로 확정/취소가능 상태까지 동기화
  return true;
}


    String msg = '근무확정 실패 (${resp.statusCode})';
    try {
      final data = jsonDecode(resp.body);
      if (data is Map && data['message'] is String) msg = data['message'];
    } catch (_) {}
    _showErrorSnackbar(msg);
    return false;
  } catch (e) {
    _showErrorSnackbar('네트워크 오류: $e');
    return false;
  }
}


void _openWorkerCalendar() {
  final info = _jobInfo ?? widget.jobInfo;

  final jobId = int.tryParse((info['id'] ?? info['job_id'] ?? info['jobId'])?.toString() ?? '');
  final jobTitle = (info['title'] ?? info['job_title'] ?? '').toString().trim();

  Navigator.pushNamed(
    context,
    '/worker-calendar',
    arguments: {
      'focusJobId': jobId,       // 캘린더 화면에서 이 공고 하이라이트용(선택)
      'focusTitle': jobTitle,    // (선택)
      'fromChatRoom': true,
    },
  );
}

void _goReview() {
  final info = _jobInfo ?? widget.jobInfo;

  final jobId = int.tryParse((info['id'] ?? info['job_id'] ?? info['jobId'])?.toString() ?? '');
  final clientId = int.tryParse((info['client_id'] ?? info['clientId'])?.toString() ?? '');
  final jobTitle = (info['title'] ?? info['job_title'] ?? '').toString().trim();
  final companyName = (info['client_company_name'] ?? info['company'] ?? '기업').toString().trim();

  // ✅ 여기서 하나라도 비면 리뷰 화면이 "잘못된 접근" 띄울 확률 99%
  if (jobId == null || clientId == null || jobTitle.isEmpty) {
    debugPrint('❌ review args invalid: jobId=$jobId clientId=$clientId jobTitle="$jobTitle" info=$info');
    _showErrorSnackbar('리뷰에 필요한 공고 정보가 부족합니다. (jobId/clientId/title)');
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

 Future<void> _showEvaluationDialog() async {
  if (!mounted) return;

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      bool sending = false;

      return StatefulBuilder(
        builder: (context, setState) {
          Future<void> press(bool isGood) async {
            if (sending) return;
            setState(() => sending = true);

            try {
              await _submitEvaluation(isGood: isGood);
              if (Navigator.of(context).canPop()) Navigator.of(context).pop(true);
            } catch (_) {
              // _submitEvaluation 내부에서 스낵바 처리
              if (mounted) setState(() => sending = false);
            }
          }

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.rate_review_rounded, size: 48, color: Color(0xFF1675F4)),
                  const SizedBox(height: 12),
                  const Text('이번 알바생은 어땠나요?',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  const Text('매너 좋은 알바였나요, 아니면 문제가 있었나요?',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 20),

                  if (sending) ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 14),
                    const Text('전송 중...', style: TextStyle(color: Colors.grey)),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () => press(true),
                            icon: const Icon(Icons.thumb_up, color: Colors.white),
                            label: const Text('좋았어요', style: TextStyle(color: Colors.white)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () => press(false),
                            icon: const Icon(Icons.thumb_down, color: Colors.white),
                            label: const Text('별로였어요', style: TextStyle(color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
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

  if (result == true) {
    // 성공 처리 필요하면 여기서
  }
}

 
Future<void> _submitEvaluation({required bool isGood}) async {
  final info = _jobInfo ?? widget.jobInfo;

  final myType = userType; // 'worker' or 'client'
  final targetType = (myType == 'worker') ? 'client' : 'worker';

  dynamic targetIdRaw;
  if (targetType == 'worker') {
    targetIdRaw = _roomWorkerId ?? info['worker_id'] ?? info['workerId'];
  } else {
    targetIdRaw = _roomClientId ?? info['client_id'] ?? info['clientId'];
  }

  final targetId = int.tryParse(targetIdRaw?.toString() ?? '');
  debugPrint('🧪 [eval] myType=$myType targetType=$targetType targetIdRaw=$targetIdRaw -> targetId=$targetId');

  if (targetId == null) {
    _showSnackbar('평가 대상 정보가 없어요. (workerId/clientId가 없음)');
    throw Exception('targetId missing');
  }

  final jobId = int.tryParse((info['job_id'] ?? info['jobId'] ?? info['id'])?.toString() ?? '');

  final mannerDelta = isGood ? 1 : -1;
  final penaltyDelta = isGood ? 0 : 1;

  await submitEvaluation(
    targetId: targetId,
    targetType: targetType,
    mannerDelta: mannerDelta,
    penaltyDelta: penaltyDelta,
    chatRoomId: widget.chatRoomId,
    jobId: jobId,
    comment: null,
  );
}

Future<void> submitEvaluation({
  required int targetId,
  required String targetType, // 'worker' | 'client'
  required int mannerDelta,   // +1 or -1
  required int penaltyDelta,  // 0 or 1
  required int chatRoomId,
  int? jobId,
  String? comment,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('authToken');

  if (token == null || token.isEmpty) {
    _showSnackbar('로그인이 필요해요. (토큰 없음)');
    throw Exception('authToken missing');
  }

final url = Uri.parse('$baseUrl/api/chat/evaluate');
  final body = {
    "targetId": targetId,
    "targetType": targetType,
    "mannerDelta": mannerDelta,
    "penaltyDelta": penaltyDelta,
    "chatRoomId": chatRoomId,
    "jobId": jobId,
    "comment": comment,
  };

  final res = await http.post(
    url,
    headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $token",
    },
    body: jsonEncode(body),
  );

  if (res.statusCode < 200 || res.statusCode >= 300) {
    String msg = '평가 저장 실패';
    try {
      final data = jsonDecode(res.body);
      msg = (data['message'] ?? data['error'] ?? msg).toString();
    } catch (_) {}
    _showSnackbar(msg);
    throw Exception('submitEvaluation failed: ${res.statusCode} ${res.body}');
  }

  _showSnackbar('평가가 반영됐어요');
}

/// ===== helpers =====

int? _tryParseInt(dynamic v) => int.tryParse(v?.toString() ?? '');

Future<int?> _resolveTargetId({
  required String myType,
  required String targetType,
  required Map<String, dynamic> info,
  required int chatRoomId,
}) async {
  // 1) 공고에서 바로 구해지는 케이스 (worker -> client 평가는 거의 여기서 끝)
  if (targetType == 'client') {
    final direct = _tryParseInt(info['client_id'] ?? info['clientId']);
    if (direct != null) return direct;
  }

  // 2) client -> worker 평가는 jobInfo에 worker_id 없으니 채팅방 메타에서 구해야 정상
  //    (만약 widget.workerId 같은 걸 이미 갖고 있으면 그걸 우선 사용)
  try {
    // widget에 workerId를 넣어뒀다면 여기서 우선 리턴하도록 바꿔도 됨
    final meta = await fetchChatRoomMeta(chatRoomId);
    if (meta == null) return null;

    if (targetType == 'worker') {
      return _tryParseInt(meta['worker_id'] ?? meta['workerId']);
    } else {
      return _tryParseInt(meta['client_id'] ?? meta['clientId']);
    }
  } catch (_) {
    return null;
  }
}

/// ✅ 채팅방에 worker_id / client_id / job_id 같은 메타를 주는 API가 필요함.
/// 아래 URL만 네 서버 라우트에 맞게 수정하면 됨.
Future<Map<String, dynamic>?> fetchChatRoomMeta(int chatRoomId) async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('authToken');
  if (token == null || token.isEmpty) return null;

  // TODO: 네 서버 라우트에 맞게 수정
  // 예: /api/chat/rooms/:id  또는 /api/chat/room/:id  또는 /api/chat/room-info/:id
  final url = Uri.parse('$baseUrl/api/chat/rooms/$chatRoomId');

  final res = await http.get(url, headers: {
    "Authorization": "Bearer $token",
  });

  if (res.statusCode < 200 || res.statusCode >= 300) return null;

  final data = jsonDecode(res.body);
  // 응답이 {room:{...}} 형태면 여기서 data['room'] 리턴하게 바꿔
  return (data is Map<String, dynamic>) ? data : null;
}
Future<void> _confirmCancelApplicationInRoom() async {
  if (!mounted) return;

  if (userType != 'worker') {
    _showErrorSnackbar('지원 취소는 구직자만 가능합니다.');
    return;
  }

  final jobIdRaw = _jobInfo?['id'] ?? widget.jobInfo['id'];
  final int? jobId = jobIdRaw is int ? jobIdRaw : int.tryParse(jobIdRaw?.toString() ?? '');
  if (jobId == null || jobId == 0) {
    _showErrorSnackbar('공고 정보가 없어 취소할 수 없습니다.');
    return;
  }

  if (isCompleted == true) {
    _showErrorSnackbar('이미 완료된 공고는 지원 취소가 불가합니다.');
    return;
  }

  if (_hasWorkSession == true) {
    await _showCancelBlockedByCalendarDialog();
    return;
  }

  final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const CancelApplicationDialog(),
      ) ??
      false;

  if (!confirmed) return;

  await _cancelApplicationInRoom(jobId);
}



Future<void> _cancelApplicationInRoom(dynamic jobIdRaw) async {
  final jobId = int.tryParse(jobIdRaw.toString());
  if (jobId == null) {
    _showErrorSnackbar('공고 ID가 올바르지 않습니다.');
    return;
  }

  final prefs = await SharedPreferences.getInstance();
  final workerId = prefs.getInt('userId');
  final token =
      prefs.getString('authToken') ?? prefs.getString('accessToken') ?? '';

  if (workerId == null || token.isEmpty) {
    _showErrorSnackbar('로그인 정보가 없습니다. 다시 로그인해주세요.');
    return;
  }

  final uri = Uri.parse('$baseUrl/api/applications/cancel');

  try {
    final resp = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'jobId': jobId,
        'workerId': workerId,
      }),
    );

    if (resp.statusCode == 200) {
      String message = '이 공고에 대한 지원을 취소했어요.';
      try {
        final data = jsonDecode(resp.body);
        if (data is Map && data['message'] is String) {
          message = data['message'];
        }
      } catch (_) {}

      setState(() {
        _status = 'cancelled';
      });

      _showErrorSnackbar(message); // 공용 snackbar 쓰는 거면 그냥 이대로 사용
    } else {
      String message = '지원 취소에 실패했습니다. (${resp.statusCode})';
      try {
        final data = jsonDecode(resp.body);
        if (data is Map && data['message'] is String) {
          message = data['message'];
        }
      } catch (_) {}
      _showErrorSnackbar(message);
    }
  } catch (e) {
    _showErrorSnackbar('지원 취소 중 오류가 발생했습니다: $e');
  }
}
Future<void> _showCancelBlockedByCalendarDialog() async {
  final go = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.event_available_rounded, color: Color(0xFF2563EB)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '이미 캘린더에 등록된 일정이에요',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _canCancel
                  ? '이 공고는 근무확정(캘박) 상태라 바로 지원 취소가 불가해요.\n먼저 “캘박 취소”를 하거나 캘린더에서 일정을 확인해 주세요.'
                  : '이 공고는 근무확정(캘박) 상태라 바로 지원 취소가 불가해요.\n현재는 취소 가능 시간이 지나 캘박 취소도 제한될 수 있어요.\n캘린더에서 일정을 확인해 주세요.',
              style: const TextStyle(fontSize: 13, height: 1.4, color: Color(0xFF4B5563)),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    ),
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text(
                      '닫기',
                      style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF374151)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B8AFF),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    ),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text(
                      '캘린더로 이동',
                      style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
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
    // 다이얼로그 pop 직후 push 충돌 방지
    Future.microtask(() => _openWorkerCalendar());
  }
}
Future<void> _cancelWorkSession() async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('authToken') ?? '';
  if (token.isEmpty) {
    _showErrorSnackbar('로그인 정보가 없습니다.');
    return;
  }

  setState(() => _workLoading = true);
  try {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/chat/cancel-work'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'roomId': widget.chatRoomId}),
    );

    if (resp.statusCode == 200) {
      await _fetchWorkState(); // ✅ 상태 재조회 (confirmed/canCancel 다시 계산)
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('일정이 취소됐어요.')),
      );
      return;
    }

    String msg = '일정 취소 실패 (${resp.statusCode})';
    try {
      final data = jsonDecode(resp.body);
      if (data is Map && data['message'] is String) msg = data['message'];
    } catch (_) {}
    _showErrorSnackbar(msg);
  } catch (e) {
    _showErrorSnackbar('네트워크 오류: $e');
  } finally {
    if (mounted) setState(() => _workLoading = false);
  }
}

void _showSnackbar(String message) {
  if (!mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
  void _scrollToBottom({bool initial = false}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    final max = position.maxScrollExtent;

    // ✅ 초기 진입일 때, 컨텐츠가 거의 한 화면 이하면 굳이 아래로 내리지 않기
    //   → max가 작다는 건 이미 거의 상단에 다 보인다는 뜻이니까
    if (initial) {
      final contentHeight = max + position.viewportDimension;
      if (contentHeight <= position.viewportDimension * 1.1) {
        // 그냥 맨 위에 둔다 (바닥까지 안내림)
        _scrollController.jumpTo(position.minScrollExtent);
        return;
      }
    }

    // ✅ 그 외(메시지 새로 보낼 때/받을 때)는 항상 아래로
    _scrollController.animateTo(
      max,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
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
  VoidCallback? onPressed,
}) {
  final bool disabled = onPressed == null;
  return ElevatedButton.icon(
    style: ElevatedButton.styleFrom(
      backgroundColor: disabled ? const Color(0xFFE5E7EB) : color,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10), // ✅ 30 → 10, 더 모던하게
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      elevation: 0, // ✅ 그림자 제거 → 플랫하게
      shadowColor: Colors.transparent,
    ),
    icon: Icon(icon, size: 15, color: disabled ? const Color(0xFF9CA3AF) : Colors.white),
    label: Text(
      text,
      style: TextStyle(
        color: disabled ? const Color(0xFF9CA3AF) : Colors.white,
        fontWeight: FontWeight.w700,
        fontSize: 13,
        letterSpacing: -0.3,
      ),
    ),
    onPressed: onPressed,
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
Widget _buildHireNudgeBubble() {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFDBEAFE), width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF2563EB)),
                SizedBox(width: 6),
                Text(
                  '채용 확정이 필요해요',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF1D4ED8)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '채용 확정을 해야\n출근 확인/노쇼 환급 절차가 진행됩니다.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, height: 1.35, color: Color(0xFF374151)),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 36,
              child: ElevatedButton.icon(
                onPressed: _confirmHire,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1675F4),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                icon: const Icon(Icons.thumb_up_alt_rounded, size: 16, color: Colors.white),
                label: const Text(
                  '채용 확정하기',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ===============================
// Job Summary (FULL REFACTOR)
// ===============================

Widget _buildJobSummary() {
  if (_isLoadingJobInfo) return const SizedBox.shrink();

  final source = _jobSource();
  final jobId = _pick(source, ['id', 'job_id', 'jobId']);
  final canGoDetail = jobId != null;

  void safeOpenDetail() {
    if (!canGoDetail) return;
    _openJobDetail();
  }

  final title = _jobTitle(source);
  final payText = _jobPayText(source);
  final periodText = _periodText(source);
  final timeText = _timeText(source);

 return Container(
    width: double.infinity,
    // ✅ padding 줄이기
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB), width: 0.7)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // title + 상세보기 버튼
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,  // ✅ 2줄 → 1줄
              ),
            ),
            if (canGoDetail)
              TextButton.icon(
                onPressed: safeOpenDetail,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.open_in_new_rounded, size: 14, color: Color(0xFF3B8AFF)),
                label: const Text('상세', style: TextStyle(fontSize: 11, color: Color(0xFF3B8AFF))),
              ),
          ],
        ),

        // ✅ pills를 한 줄로 압축
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _pill(icon: Icons.monetization_on_rounded, text: payText,
                bg: const Color(0x143B8AFF), fg: const Color(0xFF1E40AF)),
              const SizedBox(width: 6),
              _pill(icon: Icons.calendar_today, text: periodText,
                bg: Colors.indigo.shade50, fg: Colors.indigo.shade700),
              const SizedBox(width: 6),
              _pill(icon: Icons.access_time_rounded, text: timeText,
                bg: Colors.indigo.shade50, fg: Colors.indigo.shade700),
            ],
          ),
        ),

        const SizedBox(height: 6),

        // ✅ 액션 버튼 — 가로 스크롤로 한 줄에
        userType == 'client'
            ? _buildClientActions()
            : _buildWorkerActions(),
      ],
    ),
  );

}

Map<String, dynamic> _jobSource() {
  // widget.jobInfo + _jobInfo merge (null-safe)
  final Map<String, dynamic> w = widget.jobInfo is Map
      ? (widget.jobInfo as Map).cast<String, dynamic>()
      : <String, dynamic>{};

  final Map<String, dynamic> s = <String, dynamic>{
    ...w,
    ...?(_jobInfo?.cast<String, dynamic>()),
  };

  return s;
}

dynamic _pick(Map<String, dynamic> m, List<String> keys) {
  for (final k in keys) {
    final v = m[k];
    if (v != null) return v;
  }
  return null;
}

String _jobTitle(Map<String, dynamic> src) {
  final t = _pick(src, ['title', 'job_title'])?.toString().trim() ?? '';
  return t.isNotEmpty ? t : '공고 제목 없음';
}

String _jobPayText(Map<String, dynamic> src) {
  final raw = _pick(src, ['pay', 'salary', 'wage'])?.toString() ?? '0';
  final v = int.tryParse(raw) ?? 0;
  return '${NumberFormat('#,###').format(v)}원';
}

String _periodText(Map<String, dynamic> src) {
  final start = _pick(src, ['start_date', 'startDate']);
  final end = _pick(src, ['end_date', 'endDate']);
  return _formatPeriod(start, end);
}

String _timeText(Map<String, dynamic> src) {
  final start = _pick(src, ['start_time', 'startTime']);
  final end = _pick(src, ['end_time', 'endTime']);
  return _formatTimeRange(start, end);
}

Widget _sectionChip(String text) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0x143B8AFF),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        color: Color(0xFF3B8AFF),
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

// ===============================
// ACTIONS
// ===============================
Widget _buildClientActions() {
  final actions = <Widget>[];

  void addWithGap(Widget w) {
    if (actions.isNotEmpty) actions.add(const SizedBox(width: 8));
    actions.add(w);
  }

  // ── 채용 확정 전
  if (!isConfirmed) {
    addWithGap(
      _buildAlbailjuButton(
        text: '채용 확정하기',
        icon: Icons.thumb_up_alt_rounded,
        color: const Color(0xFF1675F4),
        onPressed: _confirmHire,
      ),
    );

    // ✅ 채용확정 안내 버블 대신 버튼 옆에 안내 텍스트 인라인 표시
    addWithGap(
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFDBEAFE)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.info_outline_rounded, size: 13, color: Color(0xFF2563EB)),
            SizedBox(width: 5),
            Text(
              '확정 후 출근확인·노쇼환급 가능',
              style: TextStyle(
                fontSize: 11,
                color: Color(0xFF1D4ED8),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(children: actions),
    );
  }

  // ── 확정 후: 완료 처리 버튼
  if (!isCompleted) {
    addWithGap(
      _buildAlbailjuButton(
        text: '알바 완료 처리',
        icon: Icons.check_circle_rounded,
        color: Colors.green,
        onPressed: _markJobAsCompleted,
      ),
    );
  } else {
    addWithGap(
      Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text(
          '✔ 알바 완료됨',
          style: TextStyle(
            color: Colors.grey,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  // ── ✅ 노쇼 환급 (반드시 유지)
  if (_canRequestNoShowClaim) {
    addWithGap(
      _buildAlbailjuButton(
        text: _claimLoading ? '신청 중...' : '노쇼 환급 신청',
        icon: Icons.report_gmailerrorred_rounded,
        color: const Color(0xFFDC2626),
        onPressed: _claimLoading ? null : _requestNoShowClaim,
      ),
    );
  } else if (_hasClaim) {
    final text = _claimStatus == 'approved'
        ? '✔ 환급 완료'
        : _claimStatus == 'rejected'
            ? '✘ 환급 거절'
            : '⏳ 환급 검토중';

    addWithGap(
      Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0x14DC2626),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Color(0xFFB91C1C),
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    physics: const BouncingScrollPhysics(),
    child: Row(children: actions),
  );
}


Widget _buildWorkerActions() {
  final actions = <Widget>[];

  final bool isCancelled = (_status == 'cancelled' || _status == 'canceled');
  final bool blocked = (_status == 'blocked');
  final bool expired = (_status == 'expired');
  final bool completed = isCompleted == true;

  // ✅ 요일 공고 판단 (weekdays 있으면 장기/반복 공고로 보고 캘박 UI 제거)
  final Map<String, dynamic> info = _jobInfo ?? widget.jobInfo;
  final String weekdays = (info['weekdays'] ?? info['weekday'] ?? info['days'] ?? '').toString().trim();
  final bool isWeekdaysJob = weekdays.isNotEmpty; // ← 여기서 요일 공고로 판단

  void addWithGap(Widget w) {
    if (actions.isNotEmpty) actions.add(const SizedBox(width: 8));
    actions.add(w);
  }

  Widget loadingDot(Color color) => SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      );

  final bool hasSession = _hasWorkSession;

  // ✅ 캘박은 요일 공고면 아예 숨김
  // (단, 이미 세션이 생겨버린 케이스가 있을 수 있으니, 그때도 캘박 UI를 숨기는 쪽으로 통일)
  final bool allowCalendarUi = !isWeekdaysJob;

  // =========================
  // 1) 캘박/캘린더 UI (요일공고면 스킵)
  // =========================
  if (allowCalendarUi) {
    // 캘박 의미 없으니 취소/차단/만료/완료면 막기
    final bool canBookCalendar = !isCancelled && !blocked && !expired && !completed;

    // 1-1) 아직 캘박(세션) 없으면: "캘린더에 추가하기"
    if (!hasSession) {
      addWithGap(
        ElevatedButton.icon(
          onPressed: (!canBookCalendar || _workLoading)
              ? null
              : () async {
                  setState(() => _workLoading = true);
                  try {
                    final ok = await _confirmStartWork(); // 내부에서 200/409 처리 + _fetchWorkState 호출
                    if (!mounted) return;

                    if (ok) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('캘린더에 등록했어요.')),
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _workLoading = false);
                  }
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3B8AFF),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          ),
          icon: _workLoading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.event_available_rounded, size: 16, color: Colors.white),
          label: const Text(
            '캘린더에 추가하기',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white),
          ),
        ),
      );
    }

    // 1-2) 캘박(세션) 있으면: "캘린더" + (가능하면) "일정 취소"
    if (hasSession) {
      addWithGap(
        OutlinedButton.icon(
          onPressed: _openWorkerCalendar,
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF1675F4),
            side: const BorderSide(color: Color(0xFF1675F4)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
          icon: const Icon(Icons.calendar_month_rounded, size: 16),
          label: const Text(
            '캘린더',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      );

      if (_canCancel) {
        addWithGap(
          OutlinedButton.icon(
            onPressed: _workLoading ? null : _cancelWorkSession,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFDC2626),
              side: const BorderSide(color: Color(0xFFDC2626)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            icon: _workLoading
                ? loadingDot(const Color(0xFFDC2626))
                : const Icon(Icons.event_busy_rounded, size: 16),
            label: const Text(
              '일정 취소',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        );
      }
    }
  }
final bool hireConfirmed = (isConfirmed == true) || (_workerWorkConfirmed == true);

final bool canShowCheckinButton =
    !_checkedIn &&
    _status == 'active' &&
    !isWeekdaysJob &&
    !isCancelled &&
    !blocked &&
    !expired &&
    !completed &&
    hireConfirmed; // ✅ 채용확정 조건

if (canShowCheckinButton) {
  addWithGap(
    ElevatedButton.icon(
      onPressed: _checkinLoading ? null : _checkinNow,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF10B981),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      ),
      icon: _checkinLoading
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : const Icon(Icons.how_to_reg_rounded, size: 16, color: Colors.white),
      label: const Text(
        '출근 확인',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white),
      ),
    ),
  );
} else if (_checkedIn) {
  addWithGap(
    _pill(
      icon: Icons.verified_rounded,
      text: _checkinDistanceM != null ? '출근 확인됨 (${_checkinDistanceM}m)' : '출근 확인됨',
      bg: const Color(0x1410B981),
      fg: const Color(0xFF047857),
    ),
  );
}

  // =========================
  // 2) 지원 취소 (기존 정책 유지)
  // =========================
  addWithGap(
    OutlinedButton.icon(
      onPressed: _workLoading ? null : _confirmCancelApplicationInRoom,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFDC2626),
        side: const BorderSide(color: Color(0xFFDC2626)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      icon: const Icon(Icons.cancel_outlined, size: 16),
      label: Text(
        isCancelled ? '지원 취소됨' : '지원 취소',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
  );

  // =========================
  // 3) 후기
  // =========================
  addWithGap(
    TextButton.icon(
      onPressed: _hasReviewed ? null : _goReview,
      icon: Icon(
        Icons.edit_note,
        size: 18,
        color: _hasReviewed ? Colors.grey : const Color(0xFF1675F4),
      ),
      label: Text(
        _hasReviewed ? '후기 작성 완료' : '후기 남기기',
        style: TextStyle(
          fontSize: 13,
          color: _hasReviewed ? Colors.grey : const Color(0xFF1675F4),
        ),
      ),
    ),
  );

  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    physics: const BouncingScrollPhysics(),
    child: Row(children: actions),
  );
}
// ===============================
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
Widget _buildCancelledBannerForClient() {
  final bool shouldShow =
      userType == 'client' &&
      (_status == 'cancelled' || _status == 'canceled');

  if (!shouldShow) return const SizedBox.shrink();

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: const BoxDecoration(
      color: Color(0xFFFEE2E2),
      border: Border(
        bottom: BorderSide(color: Color(0xFFFCA5A5), width: 0.5),
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(
          Icons.info_outline_rounded,
          size: 18,
          color: Color(0xFFB91C1C),
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            '알바생이 이 공고에 대한 지원을 취소했어요.\n'
            '지금 다른 공고도 한 번 올려보실래요?',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF7F1D1D),
            ),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: () {
            Navigator.pushNamed(context, '/post_job');
          },
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: const Color(0xFF3B8AFF),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          child: const Text(
            '공고 더 쓰기',
            style: TextStyle(fontSize: 11),
          ),
        ),
      ],
    ),
  );
}
 Widget _buildMessageList(
  VoidCallback? onTap,
  String? thumbnailUrl,
  String? targetName,
) {
  DateTime _messageDate(Map<String, dynamic> msg) {
    final ms = msg['createdAtMs'];
    if (ms is int && ms > 0) {
      // createdAtMs가 있으면 UTC 기준으로 → 로컬로
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
    }
     final createdIso = msg['createdAt'];
    if (createdIso is String && createdIso.isNotEmpty) {
      final dt = DateTime.tryParse(createdIso);
      if (dt != null) return dt.toLocal();
    }

    final dt = _parseServerTime(
      msg['timestamp'] ?? msg['created_at'] ?? msg['sent_at'],
    );
    return dt ?? DateTime.now();
  }

  final now = DateTime.now();

  // 날짜별로 메시지 묶기
  final Map<String, List<Map<String, dynamic>>> grouped = {};
  for (var msg in messages) {
    final date = _messageDate(msg);
    String dateKey;
    if (DateUtils.isSameDay(date, now)) {
      dateKey = '오늘';
    } else if (DateUtils.isSameDay(
      date,
      DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 1)),
    )) {
      dateKey = '어제';
    } else {
      dateKey = DateFormat('MM/dd').format(date);
    }
    grouped.putIfAbsent(dateKey, () => []).add(msg);
  }

  // 날짜 그룹: 예전날짜 → 최근날짜 순서
  final dateKeys = grouped.keys.toList()
    ..sort((a, b) {
      DateTime top(String key) {
        final list = grouped[key]!;
        list.sort(
          (m1, m2) => _messageDate(m1).compareTo(_messageDate(m2)),
        );
        return _messageDate(list.first);
      }

      return top(a).compareTo(top(b));
    });

  // 화면에 뿌릴 위젯들 한 번에 만들어서 Column에 넣기
  final List<Widget> children = [];

  for (final dateKey in dateKeys) {
    final dayMessages = grouped[dateKey]!
      ..sort((m1, m2) => _messageDate(m1).compareTo(_messageDate(m2)));

    // 날짜 태그
    children.add(
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFE5E7EB),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              dateKey,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );

    // 날짜 내부 메시지들
for (var i = 0; i < dayMessages.length; i++) {
  final msg = dayMessages[i];
  final sender = msg['sender']?.toString() ?? '';

  // ✅ 알주봇 메시지 — 별도 UI로 처리
  if (sender == 'bot') {
    children.add(_buildBotMessage(msg['message']?.toString() ?? ''));
    continue;
  }
      final isMe =
          msg['sender'] == (userType == 'worker' ? 'worker' : 'client');
      final isTarget = !isMe;
      final messageText = msg['message']?.toString() ?? '';
      final isPrevSameSender =
          i > 0 && dayMessages[i - 1]['sender'] == msg['sender'];

      final thumb = userType == 'worker'
          ? widget.jobInfo['client_thumbnail_url']?.toString()
          : widget.jobInfo['user_thumbnail_url']?.toString();
      final name = userType == 'worker'
          ? widget.jobInfo['client_company_name']?.toString() ?? '기업'
          : widget.jobInfo['user_name']?.toString() ?? '알바생';

      final when = _messageDate(msg);

      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment:
                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (isTarget && !isPrevSameSender) ...[
                const SizedBox(width: 4),
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
                const SizedBox(width: 6),
              ] else if (isTarget && isPrevSameSender) ...[
                const SizedBox(width: 46),
              ],
              Flexible(
                child: Column(
                  crossAxisAlignment: isMe
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    if (isTarget && !isPrevSameSender)
                      Padding(
                        padding:
                            const EdgeInsets.only(left: 4, bottom: 2),
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF9CA3AF),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      constraints: BoxConstraints(
                        maxWidth:
                            MediaQuery.of(context).size.width * 0.7,
                      ),
                      decoration: BoxDecoration(
                        color: msg['imageUrl'] != null &&
                                msg['imageUrl'].toString().isNotEmpty
                            ? (isMe
                                ? const Color(0xFF3B82F6)
                                : Colors.white)
                            : (isMe
                                ? const Color(0xFF3B82F6)
                                : const Color(0xFFF3F4F6)),
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(14),
                          topRight: const Radius.circular(14),
                          bottomLeft: Radius.circular(
                              isMe ? 14 : (isPrevSameSender ? 4 : 14)),
                          bottomRight: Radius.circular(
                              isMe ? (isPrevSameSender ? 4 : 14) : 14),
                        ),
                        border: !isMe
                            ? Border.all(
                                color: const Color(0xFFE5E7EB),
                                width: 0.8,
                              )
                            : null,
                      ),
                      child: (msg['imageUrl'] != null &&
                              msg['imageUrl'].toString().isNotEmpty)
                          ? _ChatImageBubble(
                              imageUrl: msg['imageUrl'].toString(),
                              heroTag:
                                  'img_${when.millisecondsSinceEpoch}',
                            )
                          : Text(
                              messageText,
                              style: TextStyle(
                                fontSize: 14,
                                color: isMe
                                    ? Colors.white
                                    : const Color(0xFF111827),
                              ),
                            ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(
                        right: isMe ? 6 : 0,
                        left: isMe ? 0 : 6,
                        top: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: isMe
                            ? MainAxisAlignment.end
                            : MainAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('a h:mm', 'ko_KR').format(when),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF9CA3AF),
                            ),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 6),
                            Text(
                              (msg['is_read'] == 1 ||
                                      msg['is_read'] == true)
                                  ? '읽음'
                                  : '안읽음',
                              style: TextStyle(
                                fontSize: 10,
                                color: (msg['is_read'] == 1 ||
                                        msg['is_read'] == true)
                                    ? const Color(0xFF3B82F6)
                                    : const Color(0xFF9CA3AF),
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
        ),
      );
    }
  }
if (_shouldShowHireNudge()) {
  children.add(_buildHireNudgeBubble());
}
  // 🔥 핵심: 화면 높이만큼 최소 높이를 주고, 그 안에서 Column을 아래로 붙이기
  return LayoutBuilder(
    builder: (context, constraints) {
      return SingleChildScrollView(
        controller: _scrollController,
       padding: const EdgeInsets.only(
    left: 8,
    right: 8,
    top: 4,
    bottom: 80, // ✅ 입력창 높이만큼 여백
  ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.maxHeight,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      );
    },
  );
}

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildBotMessage(String message) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
    child: Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F6FF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFDBEAFE), width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 봇 헤더
            Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text('🤖', style: TextStyle(fontSize: 14)),
                SizedBox(width: 6),
                Text(
                  '일주봇',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2563EB),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // 메시지
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF374151),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
Widget _buildClientWaitingBanner() {
  final shouldShow = userType == 'client' && _status == 'pending';
  if (!shouldShow) return const SizedBox.shrink();

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: const BoxDecoration(
      color: Color(0xFFFFF7E6),
      border: Border(
        bottom: BorderSide(color: Color(0xFFFDE68A), width: 0.5),
      ),
    ),
    child: Row(
      children: const [
        Icon(Icons.hourglass_bottom_rounded,
            size: 18, color: Color(0xFFEA580C)),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            '구직자의 수락을 기다리는 중입니다.\n수락되면 바로 채팅이 가능해요.',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF92400E),
            ),
          ),
        ),
      ],
    ),
  );
}
Widget _buildConsentBanner() {
  final bool shouldShow =
      userType == 'worker' && _status == 'pending' && _initiator == 'client';

  if (!shouldShow) return const SizedBox.shrink();

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: const BoxDecoration(
      color: Color(0xFFEFF6FF),
      border: Border(
        bottom: BorderSide(color: Color(0xFFDBEAFE), width: 0.5),
      ),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline_rounded,
            size: 18, color: Color(0xFF2563EB)),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            '사장님의 대화 요청입니다.\n수락 시 채팅이 시작되고 연락이 가능해요.',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF1D4ED8),
            ),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: _consentBusy ? null : () => _sendConsent(false),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFDC2626),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(
            '거절',
            style: TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(width: 4),
        ElevatedButton(
          onPressed: _consentBusy ? null : () => _sendConsent(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3B82F6),
            foregroundColor: Colors.white,
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          child: _consentBusy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  '수락',
                  style: TextStyle(fontSize: 12),
                ),
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
 final String jobTitle = _jobTitle(_jobSource());

  if (userType == 'client') {
    targetName = widget.jobInfo['user_name']?.toString();
    targetThumbnailUrl = widget.jobInfo['user_thumbnail_url']?.toString();

    final dynamic rawWorkerId = widget.jobInfo['worker_id'];
    final int? workerId = (rawWorkerId is int)
        ? rawWorkerId
        : int.tryParse(rawWorkerId?.toString() ?? '');

    if (workerId != null) {
      onTap = () {
        Navigator.pushNamed(context, '/worker-profile', arguments: workerId);
      };
    }
  } else {
    final company =
        widget.jobInfo['client_company_name']?.toString() ?? '기업';
    targetName = company;
    targetThumbnailUrl =
        widget.jobInfo['client_thumbnail_url']?.toString();

    final dynamic rawClientId = widget.jobInfo['client_id'];
    final int? clientId = (rawClientId is int)
        ? rawClientId
        : int.tryParse(rawClientId?.toString() ?? '');

    if (clientId != null) {
      onTap = () {
        Navigator.pushNamed(context, '/client-profile',
            arguments: clientId);
      };
    }
  }

 return WillPopScope(
  onWillPop: () async {
    Navigator.pop(context, 'updated');
    return false;
  },
  child: GestureDetector(
    behavior: HitTestBehavior.translucent,
    onTap: () => FocusScope.of(context).unfocus(),
   child: Scaffold(
  // ✅ adjustPan 환경에서도 입력창이 키보드 위로 올라오게
  resizeToAvoidBottomInset: true,
  backgroundColor: const Color(0xFFF3F4F6),
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
    mainAxisSize: MainAxisSize.min,  // ✅ 핵심
    children: [
      GestureDetector(
        onTap: onTap ?? () {},
        child: CircleAvatar(
          radius: 18,
          backgroundImage: (targetThumbnailUrl != null &&
                  targetThumbnailUrl.isNotEmpty)
              ? NetworkImage(targetThumbnailUrl)
              : null,
          child: (targetThumbnailUrl == null || targetThumbnailUrl.isEmpty)
              ? const Icon(Icons.person)
              : null,
        ),
      ),
      const SizedBox(width: 10),
      Flexible(  // ✅ Expanded → Flexible
        child: _AlbailjuChatAppBarTitle(
          name: targetName ?? '상대방',
          userType: userType,
          status: _status,
          jobTitle: jobTitle, // ✅ 추가
        ),
      ),
    ],
  ),
),
   body: Column(
  children: [
    _buildJobSummary(),
    _buildConsentBanner(),
    _buildClientWaitingBanner(),
    _buildCancelledBannerForClient(),
    Expanded(
      child: Stack(
        children: [
          // ── 채팅 리스트 (전체 영역)
          Positioned.fill(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : messages.isEmpty
                    ? _buildEmptyChatNotice()
                    : NotificationListener<ScrollStartNotification>(
                        onNotification: (_) {
                          FocusScope.of(context).unfocus();
                          return false;
                        },
                        child: _buildMessageList(onTap, targetThumbnailUrl, targetName),
                      ),
          ),

          // ── 입력창 (하단 오버레이)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.88),
                    border: const Border(
                      top: BorderSide(color: Color(0xFFE5E7EB), width: 0.5),
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
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: TextField(
                            controller: _messageController,
                            focusNode: _inputFocusNode,
                            enabled: _inputEnabled,
                            onTapOutside: (_) => FocusScope.of(context).unfocus(),
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              hintText: _inputEnabled
                                  ? '메시지를 입력하세요...'
                                  : (_status == 'pending'
                                      ? '상대방의 수락을 기다리는 중입니다'
                                      : (_status == 'cancelled' || _status == 'canceled'
                                          ? (userType == 'client'
                                              ? '알바생이 지원을 취소한 채팅입니다'
                                              : '지원 취소 후에는 채팅을 보낼 수 없습니다')
                                          : '지금은 채팅을 보낼 수 없습니다')),
                              hintStyle: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF9CA3AF),
                              ),
                            ),
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.image),
                        color: _inputEnabled
                            ? const Color(0xFF4B5563)
                            : const Color(0xFFD1D5DB),
                        onPressed: _inputEnabled ? _pickAndSendImage : null,
                      ),
                      const SizedBox(width: 2),
                      GestureDetector(
                        onTap: _inputEnabled ? _sendMessage : null,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _inputEnabled
                                ? const Color(0xFF3B82F6)
                                : const Color(0xFFD1D5DB),
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
// ✅ 입력창 위에 노출되는 슬림 액션 칩바

  Widget _buildEmptyChatNotice() {
  final bool isClient = (userType == 'client');

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
            // 상단 TIP 칩
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                const Spacer(),
              ],
            ),
            const SizedBox(height: 10),

            // 메인 타이틀
            Text(
              isClient
                  ? '여기서 첫 채용 대화를 시작해 보세요'
                  : '여기서 첫 인사를 남겨보세요',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 6),

            // 설명 텍스트 (강조 부분 컬러)
            RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: Color(0xFF4B5563),
                ),
                children: [
                  TextSpan(
                    text: isClient ? '사장님께 ' : '상대방에게 ',
                  ),
                  const TextSpan(
                    text: '자기소개와 장점',
                    style: TextStyle(
                      color: Color(0xFF3B8AFF),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const TextSpan(
                    text: '을 함께 첫 메시지로 보내면\n채용 확률이 더 높아져요.',
                  ),
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
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    _scrollToBottom();
                    _inputFocusNode.requestFocus(); // ✅ 바로 입력창으로 포커스
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
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

class _AlbailjuChatAppBarTitle extends StatelessWidget {
  final String name;
  final String userType;
  final String status;
  final String jobTitle; // ✅ NEW

  const _AlbailjuChatAppBarTitle({
    required this.name,
    required this.userType,
    required this.status,
    required this.jobTitle, // ✅ NEW
  });

  @override
  Widget build(BuildContext context) {
    final bool isPending   = status == 'pending';
    final bool isBlocked   = status == 'blocked';
    final bool isActive    = status == 'active';
    final bool isCancelled = status == 'cancelled' || status == 'canceled';

    String chipText;
    Color chipBg;
    Color chipFg;

    if (isPending) {
      chipText = '대기중'; chipBg = const Color(0xFFFFF3E0); chipFg = const Color(0xFFE65100);
    } else if (isCancelled) {
      chipText = '취소됨'; chipBg = const Color(0xFFFFEBEE); chipFg = const Color(0xFFC62828);
    } else if (isBlocked) {
      chipText = '차단됨'; chipBg = const Color(0xFFFFEBEE); chipFg = const Color(0xFFC62828);
    } else if (isActive) {
      chipText = '채팅중'; chipBg = const Color(0xFFE8F5E9); chipFg = const Color(0xFF2E7D32);
    } else {
      chipText = '알바일주'; chipBg = const Color(0xFFF5F5F5); chipFg = const Color(0xFF757575);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 상태 칩
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: chipBg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 5, height: 5,
                decoration: BoxDecoration(color: chipFg, shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              Text(chipText, style: TextStyle(
                fontSize: 10, color: chipFg, fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              )),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // 이름 + 공고 제목
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Jalnan2TTF',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0D0D0D),
                  height: 1.1,
                ),
              ),
              if (jobTitle.isNotEmpty) ...[
                const SizedBox(height: 1),
                Text(
                  jobTitle,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF9E9E9E),
                    fontWeight: FontWeight.w400,
                    height: 1.2,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
class CancelApplicationDialog extends StatelessWidget {
  const CancelApplicationDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
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
                    color: const Color(0xFFFFE4E4),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.warning_rounded,
                    color: Color(0xFFE53935),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '지원 취소하시겠어요?',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827),
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '이 공고에 대한 지원이 취소되며,\n'
                        '다시 지원하려면 새로 지원해야 할 수 있어요.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // 서브 설명 박스
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: const [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: Color(0xFF9CA3AF),
                  ),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '취소 이후에는 채팅만 남고,\n'
                      '해당 공고와의 매칭은 해제됩니다.',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 아래 버튼 2개
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE53935),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop(true);
                    },
                    child: const Text(
                      '네, 지원을 취소할게요',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop(false);
                    },
                    child: const Text(
                      '그냥 둘게요',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF374151),
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