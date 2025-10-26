import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:kpostal/kpostal.dart';
import 'package:time_range_picker/time_range_picker.dart';
import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart';
import 'package:iljujob/data/services/job_service.dart';
import 'package:iljujob/data/models/job.dart';
import 'dart:convert';
import 'package:iljujob/config/constants.dart';
import 'package:http/http.dart' as http;
import 'package:iljujob/presentation/screens/post_job/job_preview_detail_screen.dart';
import 'package:iljujob/presentation/screens/policy_detail_screen.dart'; // ← 경로는 실제 위치에 맞게
import 'package:iljujob/presentation/screens/post_job/SelectPreviousJobScreen.dart';
import 'package:time_picker_spinner/time_picker_spinner.dart';
import 'package:flutter/cupertino.dart';
import 'package:table_calendar/table_calendar.dart'; // ✅ 꼭 있어야 함
import 'package:intl/intl.dart';

import 'package:flutter/cupertino.dart';
import 'package:iljujob/core/suspension.dart';
import 'package:iljujob/core/suspension_guard.dart';
import 'package:iljujob/widget/suspension_banner.dart';
import '../../../config/ai_secrets.dart';

import '../../../data/services/ai_job_description_service.dart';
const int minWagePerHour = 10030;

class PostJobForm extends StatefulWidget {
  final bool isRepost;
  final Job? existingJob;

  const PostJobForm({
    super.key,
    required this.isRepost,
    required this.existingJob,
  });

  @override
  State<PostJobForm> createState() => _PostJobFormState();
}

class _PostJobFormState extends State<PostJobForm> {
  final _formKey = GlobalKey<FormState>();
  String title = '';
  String category = '제조';
  String location = '';
  String locationCity = '';
  DateTime? startDate;
  DateTime? endDate;
  List<String> selectedWeekdays = [];
  TimeOfDay? startTime;
  TimeOfDay? endTime;
  String payType = '일급';
  int pay = 0;
  String description = '';
  List<File> images = [];
  bool isShortTerm = true;
  String companyName = '';
  String managerName = '';
  double lat = 0.0;
  double lng = 0.0;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _payController = TextEditingController();
  String? _payWarning;

  bool isReservation = false;
  DateTime? publishDate;
  TimeOfDay? publishTime;
  DateTime? publishAt; // ← 서버로 전송할 최종 DateTime
  bool isSameDayPay = false;
  String negotiationText = ''; // 요일 협의 입력 값
  String longTermMode = '요일 지정'; // ← '요일 지정' or '요일 협의'

  int _freeLimit = 3;
  int _freeUsed = 0;
  int _freeRemaining = 3;
  int _paidPassCount = 0;      // 보유 이용권 수
bool _passCountLoading = false;
   SuspensionState? _suspension;
  bool _suspLoaded = false; // 로딩 완료 표시(레이스 방지)
bool _isProUser = false;
bool _isAIGenerating = false;

  String managerPhone = ''; // 이 줄 추가


  Future<void> _loadSuspension() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt('userId');
    if (id == null) throw Exception('no userId');
    final uri = Uri.parse('$baseUrl/api/public/suspension?type=client&id=$id');
    final res = await http.get(uri); // 토큰 불필요

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      setState(() {
        _suspension = SuspensionState(
          suspendedType:  (data['suspended_type'] ?? data['suspendedType'])?.toString(),
          suspendedUntil: (data['suspended_until'] ?? data['suspendedUntil'])?.toString(),
          suspendedReason:(data['suspended_reason'] ?? data['suspendedReason'])?.toString(),
        );
        _suspLoaded = true;
      });
      return;
    }
  } catch (_) {}
  setState(() {
    _suspension = const SuspensionState(
      suspendedType: null, suspendedUntil: null, suspendedReason: null,
    );
    _suspLoaded = true;
  });
}
  Future<void> _fetchFreeUsage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final clientId = prefs.getInt('userId');
      if (clientId == null) {
        print('❌ clientId 없음');
        return;
      }

      final t = DateTime.now().millisecondsSinceEpoch; // 캐시 버스터
      final url = '$baseUrl/api/job/free-post-usage?clientId=$clientId&t=$t';

      final r = await http.get(
        Uri.parse(url),
        headers: {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
      );

      if (r.statusCode == 200) {
        final d = jsonDecode(r.body);

        if (!mounted) return;
        setState(() {
          _freeLimit = (d['limit'] ?? 3) as int;
          _freeUsed = (d['used'] ?? 0) as int;
          _freeRemaining = (d['remaining'] ?? (_freeLimit - _freeUsed)) as int;
        });
      } else {
      }
    } catch (e) {
    }
  }



  @override
  void initState() {
    super.initState();
    _loadInitialData();
     WidgetsBinding.instance.addPostFrameCallback((_) => _refreshPaidPassCount());
    _fetchFreeUsage(); // 초기 무료 사용량 조회
    _loadSuspension();               
  _checkProStatus(); 
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _payController.dispose();
    _locationController.dispose();
    super.dispose();
  }


  // 기존 _checkProStatus() 메서드를 이것으로 교체

Future<void> _checkProStatus() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');
    
    if (token == null || token.isEmpty) {
      setState(() => _isProUser = false);
      return;
    }

    // 서버에서 구독 상태 조회
    final response = await http.get(
      Uri.parse('$baseUrl/api/subscription/status'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final isActive = data['active'] == true;
      final plan = data['plan']?.toString() ?? '';
      
      // Pro나 Premium 플랜이고 활성 상태면 Pro 사용자
      final isProPlan = (plan == 'pro' || plan == 'premium') && isActive;
      
      setState(() {
        _isProUser = isProPlan;
      });
      
      // 디버깅용 로그
      print('구독 상태: active=$isActive, plan=$plan, isProUser=$_isProUser');
      
    } else {
      print('구독 상태 조회 실패: ${response.statusCode}');
      setState(() => _isProUser = false);
    }
    
  } catch (e) {
    print('Pro 상태 확인 오류: $e');
    setState(() => _isProUser = false);
  }
}
Future<void> _refreshPaidPassCount() async {
  try {
    setState(() => _passCountLoading = true);

    final prefs = await SharedPreferences.getInstance();
    final int? clientId = prefs.getInt('userId');
    final String token = prefs.getString('authToken') ?? '';
    if (clientId == null || clientId <= 0) {
      print('❌ clientId 없음');
      setState(() => _passCountLoading = false);
      return;
    }

    final uri = Uri.parse('$baseUrl/api/pass/remain')
        .replace(queryParameters: {'clientId': '$clientId'});

    final res = await http.get(
      uri,
      headers: {
        'Accept': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    ).timeout(const Duration(seconds: 8));

    final bodyText = utf8.decode(res.bodyBytes);

    if (!mounted) return;
    if (res.statusCode == 200) {
      final data = jsonDecode(bodyText);
      final remain = int.tryParse('${data['remaining'] ?? data['remain'] ?? data['balance'] ?? 0}') ?? 0;
      setState(() => _paidPassCount = remain);
    }
  } catch (e) {
    print('❌ 이용권 수 조회 오류: $e');
  } finally {
    if (mounted) setState(() => _passCountLoading = false);
  }
}
Future<void> _openPaidFlow() async {
  // 필요 시 항상 최신값으로 맞추기
  await _refreshPaidPassCount();

  if (!mounted) return;
  if (_paidPassCount <= 0) {
    // 구매 유도
    final goBuy = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('이용권이 없습니다'),
        content: const Text('유료 등록을 진행하려면 이용권을 구매해주세요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('구매하기')),
        ],
      ),
    );
    if (goBuy == true) {
      // 구매 화면으로 이동 (라우트명 맞춰 수정)
      await Navigator.pushNamed(context, '/purchase-pass');
      // 돌아오면 다시 잔액 갱신
      await _refreshPaidPassCount();
    }
    return;
  }

  // 보유 > 0 → 기존 유료 옵션 다이얼로그 열기
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    _showPublishOptionDialog(); // 네가 이미 쓰던 함수
  });
}
  Future<void> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    final clientId = prefs.getInt('userId');
    if (clientId != null) {
      await fetchClientProfile(clientId);
    }

    if (widget.isRepost && widget.existingJob != null) {
      final job = widget.existingJob!;

      setState(() {
        title = job.title;
        _titleController.text = title; // 🔄 순서 바뀜

        category = job.category;
        location = job.location;
        locationCity = job.locationCity ?? '';
        pay = int.tryParse(job.pay) ?? 0;
        payType = job.payType;
        description = job.description ?? '';
        isShortTerm = job.weekdays == null;
        selectedWeekdays = job.weekdays?.split(',') ?? [];
        startDate = job.startDate;
        endDate = job.endDate;
        startTime = _parseTime(job.startTime);
        endTime = _parseTime(job.endTime);
        lat = job.lat;
        lng = job.lng;

        _locationController.text = location;
        _descController.text = description;
        _payController.text = pay.toString();
      });
    }
  }

  Future<void> fetchClientProfile(int clientId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken'); // 토큰 가져오기
    final response = await http.get(
      Uri.parse('$baseUrl/api/client/profile?id=$clientId'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      setState(() {
        companyName = data['company_name'] ?? '';
        managerName = data['manager_name'] ?? '';
        managerPhone = data['manager_phone'] ?? data['phone'] ?? ''; // 전화번호 추가
      });
    } else {
      print('❌ 클라이언트 정보 조회 실패: ${response.body}');
    }
  }

  TimeOfDay? _parseTime(String? timeStr) {
    if (timeStr == null || !timeStr.contains(':')) return null;
    final parts = timeStr.trim().split(':');
    if (parts.length != 2) return null;
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _formatTime24H(TimeOfDay? time) {
    if (time == null) return '';
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String _extractCity(String fullAddress) {
    final parts = fullAddress.split(' ');
    if (parts.isNotEmpty) {
      String first = parts[0];
      if (first.contains('광역시') || first.contains('특별시')) {
        return first.replaceAll(RegExp(r'[광역시|특별시]'), '');
      } else if (first.contains('도')) {
        return parts.length > 1 ? parts[1] : first;
      } else {
        return first;
      }
    }
    return '';
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();

    // 갤러리 다중 선택
    final picked = await picker.pickMultiImage(
      imageQuality: 85, // 용량 줄이기(선택)
      maxWidth: 1600,
      maxHeight: 1600,
    );

    if (picked.isNotEmpty) {
      setState(() {
        // 총 개수 제한 예: 10장
        final newFiles = picked.map((x) => File(x.path)).toList();
        images.addAll(newFiles);
        if (images.length > 10) images = images.sublist(0, 10);
      });
    }
  }

// helpers
int _toMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

int _dailyWorkingMinutes(TimeOfDay? s, TimeOfDay? e) {
  if (s == null || e == null) return 0;
  int d = _toMinutes(e) - _toMinutes(s);
  if (d <= 0) d += 24 * 60; // 자정 넘어가는 야간 근무 처리
  return d;
}

int _inclusiveDays(DateTime s, DateTime e) {
  final s0 = DateTime(s.year, s.month, s.day);
  final e0 = DateTime(e.year, e.month, e.day);
  return e0.difference(s0).inDays + 1; // 양끝 포함
}

// ✅ 협의만 제외하고 모두 검증
int _requiredPayKrw() {
  final mins = _dailyWorkingMinutes(startTime, endTime);
  if (mins == 0) return 0; // 시간 미정이면 계산 보류(경고 X)

  final hours = mins / 60.0;

  if (payType == '일급') {
    // 하루 근무시간 × 최저시급
    return (minWagePerHour * hours).ceil();
  }

  // payType == '주급'
  int daysPerWeek = 0;

  if (isShortTerm) {
    // 단기 + 주급: 시작~종료일 기준으로 '그 주에 일하는 일수' 추정 (최대 7일)
    if (startDate != null && endDate != null) {
      final d = _inclusiveDays(startDate!, endDate!);
      daysPerWeek = d.clamp(1, 7); // Dart에서 int.clamp는 num 반환 → 사용에 문제 없음
    } else {
      return 0; // 날짜 없으면 보류
    }
  } else {
    // 장기
    if (longTermMode == '요일 지정') {
      daysPerWeek = selectedWeekdays.length; // 예: 월수금 = 3
      if (daysPerWeek <= 0) return 0;        // 선택 안 했으면 보류
    } else {
      // 장기 '요일 협의'는 검증 제외
      return 0;
    }
  }

  return (minWagePerHour * hours * daysPerWeek).ceil();
}

void _validatePay() {
  final req = _requiredPayKrw();
  setState(() {
    if (req == 0) {
      // 계산 불가 케이스(시간 미정, 장기-협의, 단기인데 주급 등)
      _payWarning = null; // 강제 경고는 띄우지 않음
    } else {
      _payWarning = (pay >= req)
          ? null
          : '💰 최저시급 기준 미달입니다. 최소 ${NumberFormat('#,###').format(req)}원 이상';
    }
  });
}

  void _showError(String msg) {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('오류'),
            content: Text(msg),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('확인'),
              ),
            ],
          ),
    );
  }

  Future<void> _submit({required bool isPaid}) async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    // 1) 기본 검증
    const int minWorkingHours = 4;
    final int minWage = minWagePerHour * minWorkingHours;
    if (pay < minWage) {
      _showError('급여가 너무 낮습니다');
      return;
    }

    // 단기: 날짜 필수
    if (isShortTerm && (startDate == null || endDate == null)) {
      _showError('시작일과 종료일을 선택해주세요');
      return;
    }

    // 장기: 모드별 검증
    if (!isShortTerm && longTermMode == '요일 지정' && selectedWeekdays.isEmpty) {
      _showError('요일을 1개 이상 선택해주세요');
      return;
    }
    if (!isShortTerm &&
        longTermMode == '요일 협의' &&
        negotiationText.trim().isEmpty) {
      _showError('요일 협의 내용을 입력해주세요');
      return;
    }

    // 2) 로그인 확인
    final prefs = await SharedPreferences.getInstance();
    final int? clientId = prefs.getInt('userId');
    final String userType = prefs.getString('userType') ?? '';
    if (clientId == null) {
      _showError('로그인 정보가 올바르지 않습니다.');
      return;
    }

    // 3) 예약 공개 시간(UTC ISO Z)
    String? publishAtIso;
    DateTime? scheduled;
    if (publishAt != null) {
      scheduled = publishAt;
    } else if (publishDate != null && publishTime != null) {
      scheduled = DateTime(
        publishDate!.year,
        publishDate!.month,
        publishDate!.day,
        publishTime!.hour,
        publishTime!.minute,
      );
    }
    if (scheduled != null) {
      publishAtIso = scheduled.toUtc().toIso8601String();
    }

    // 4) 요일/협의 전송값 정리
    final bool isDays = (!isShortTerm && longTermMode == '요일 지정');
    final bool isNegotiation = (!isShortTerm && longTermMode == '요일 협의');

    // A안(문자열 규약): 요일 지정 → "월,수,금", 협의 → "협의: 내용"
    final String? weekdaysPayload =
        isDays
            ? (selectedWeekdays.isNotEmpty ? selectedWeekdays.join(',') : null)
            : (isNegotiation ? '협의: ${negotiationText.trim()}' : null);

    // 설명 원문 그대로
    final String descriptionToSend = description.trim();

    try {
      await JobService.postJobWithImages(
        title: title.trim(),
        category: category.trim(),
        location: location.trim(),
        locationCity: locationCity.trim(),

        // 서버가 단기일 때만 검사하므로 값은 보내되 서버에서 무시/보정
        startDate:
            (startDate ?? DateTime.now()).toIso8601String().split('T')[0],
        endDate:
            (endDate ?? startDate ?? DateTime.now()).toIso8601String().split(
              'T',
            )[0],

        startTime: _formatTime24H(startTime),
        endTime: _formatTime24H(endTime),

        payType: payType,
        pay: pay,
        description: descriptionToSend,
        images: images,
        clientId: clientId,

        // ✅ 요일 지정/협의
        weekdays:
            (weekdaysPayload != null && weekdaysPayload.trim().isNotEmpty)
                ? weekdaysPayload
                : null,

        lat: lat,
        lng: lng,
        isScheduled: publishAtIso != null,
        publishAt: publishAtIso, // UTC ISO(Z)
        isSameDayPay: isSameDayPay,
        isPaid: isPaid,
      );

      if (!mounted) return;

      // ✅ 무료 등록이라면: 한도 즉시 갱신 (서버 조회 권장)
      if (!isPaid) {
        await _fetchFreeUsage(); // ← 여기서 새 값 받아와서 3/3 → 2/3 등 즉시 반영
        // (대신 네트워크 줄이고 싶으면 낙관적 갱신도 가능)
        // setState(() {
        //   _freeUsed = (_freeUsed + 1).clamp(0, _freeLimit);
        //   _freeRemaining = (_freeLimit - _freeUsed).clamp(0, _freeLimit);
        // });
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('공고 등록 완료')));

      // 5) 라우팅
      if (userType == 'client') {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/client_main',
          (_) => false,
        );
      } else if (userType == 'worker') {
        Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
      } else {
        _showError('로그인 정보를 확인해주세요.');
      }
    } catch (e) {
      _showError('서버 오류: $e');
    }
  }

  final _df = DateFormat('yyyy-MM-dd');

  Future<String?> _pickDate({
    required BuildContext context,
    DateTime? current, // 현재 필드 값(있으면 그 날짜로 초기 포커스)
    DateTime? minDate, // 최소 가능 날짜(없으면 오늘)
    DateTime? maxDate, // 최대 가능 날짜(선택)
  }) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final initial =
        (current ?? minDate ?? today).isBefore(today)
            ? today
            : (current ?? minDate ?? today);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: minDate ?? today, // 👈 과거 선택 금지
      lastDate: maxDate ?? DateTime(today.year + 1, 12, 31),
      locale: const Locale('ko'),
      helpText: '날짜 선택',
      builder: (context, child) {
        // 다크모드/브랜드 컬러 적용하고 싶으면 여기서 Theme 조정
        return child!;
      },
    );

    if (picked == null) return null;
    return _df.format(picked);
  }

  List<String> imageUrls = [];
  List<String> deleteImageUrls = [];
  void _fillFormWithJob(Map<String, dynamic> job) {
    setState(() {
      _titleController.text = job['title'] ?? '';
      _payController.text = job['pay']?.toString() ?? '';
      _descController.text = job['description'] ?? '';
      category = job['category'] ?? '';
      location = job['location'] ?? '';
      locationCity = job['location_city'] ?? '';
      payType = job['pay_type'] ?? '일급';

      startDate =
          job['start_date'] != null
              ? DateTime.tryParse(job['start_date'])
              : null;
      endDate =
          job['end_date'] != null ? DateTime.tryParse(job['end_date']) : null;

      startTime =
          job['start_time'] != null ? _parseTime(job['start_time']) : null;
      endTime = job['end_time'] != null ? _parseTime(job['end_time']) : null;

      selectedWeekdays =
          job['weekdays'] != null ? job['weekdays'].split(',') : [];

      isSameDayPay = job['is_same_day_pay'] == 1;

      lat = job['lat'] ?? 0.0;
      lng = job['lng'] ?? 0.0;

      // ✅ 이미지 URL 리스트 채우기
      final List<String> serverUrls =
          (() {
            final raw = job['image_urls'];
            if (raw == null) return <String>[];
            if (raw is List) return List<String>.from(raw);
            if (raw is String) {
              try {
                final parsed = jsonDecode(raw);
                if (parsed is List) return List<String>.from(parsed);
              } catch (_) {}
            }
            return <String>[];
          })();

      imageUrls =
          serverUrls
              .map((u) => u.startsWith('http') ? u : '$baseUrl$u')
              .toList();
    });
  }

  Future<bool?> _showTicketUsageDialog() {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true, // ✅ 안드 하단 제스처바 회피
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        // ✅ 키보드/네비바 중 더 큰 쪽으로 하단 패딩
        final kb = MediaQuery.of(context).viewInsets.bottom;
        final sys = MediaQuery.of(context).padding.bottom;
        final bottomPad = (kb > 0 ? kb : sys) + 16;

        return SafeArea(
          top: false,
          minimum: EdgeInsets.fromLTRB(20, 24, 20, bottomPad),
          child: SingleChildScrollView(
            // 작은 화면/큰 폰트 대비
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 36,
                  color: Color(0xFF3B8AFF),
                ),
                const SizedBox(height: 12),
                const Text(
                  '이용권 1회 차감',
                  style: TextStyle(
                    fontFamily: 'Jalnan2TTF',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '이 공고를 등록하면 보유 이용권이\n1회 차감됩니다. 진행하시겠어요?',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.black87),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('아니요'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B8AFF),
                          foregroundColor: Colors.white, // ✅ 텍스트 흰색 보장
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('예, 진행할게요'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showPublishOptionDialog() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true, // ✅ 하단 제스처바/노치 회피
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final kb = MediaQuery.of(ctx).viewInsets.bottom; // 키보드
        final sys = MediaQuery.of(ctx).padding.bottom; // 제스처바/네비바
        final bottomPad = (kb > 0 ? kb : sys) + 16;

        return SafeArea(
          top: false,
          minimum: EdgeInsets.fromLTRB(20, 24, 20, bottomPad), // ✅ 하단 안전 패딩
          child: SingleChildScrollView(
            // 작은 화면/큰 폰트 대비
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '공고 공개 방식을 선택해주세요',
                  style: TextStyle(
                    fontFamily: 'Jalnan2TTF',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF3B8AFF),
                  ),
                ),
                const SizedBox(height: 20),

                // 즉시 공개 (유료)
                _buildPublishOptionCard(
                  icon: Icons.flash_on,
                  title: '즉시 공개',
                  subtitle: '지금 바로 알바생에게 노출',
                  onTap: () async {
                    final confirmed = await _showTicketUsageDialog();
                    if (confirmed == true) {
                      final prefs = await SharedPreferences.getInstance();
                      final clientId = prefs.getInt('userId') ?? 0;

                      final passUsed = await _usePassAndSubmit(clientId);
                      if (passUsed) {
                        publishAt = null; // 즉시
                        Navigator.pop(ctx);
                        _submit(isPaid: true); // ✅ 명시적으로 유료
                      }
                    }
                  },
                ),

                const SizedBox(height: 16),

                // 예약 공개 (유료)
                _buildPublishOptionCard(
                  icon: Icons.schedule,
                  title: '예약 공개',
                  subtitle: '선택한 날짜와 시간에 자동 공개',
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2100),
                    );
                    if (date == null) return;

                    final time = await showTimePicker(
                      context: context,
                      initialTime: const TimeOfDay(hour: 9, minute: 0),
                    );
                    if (time == null) return;

                    final confirmed = await _showTicketUsageDialog();
                    if (confirmed == true) {
                      final prefs = await SharedPreferences.getInstance();
                      final clientId = prefs.getInt('userId') ?? 0;

                      final passUsed = await _usePassAndSubmit(clientId);
                      if (passUsed) {
                        publishAt = DateTime(
                          // ✅ 예약 시각 저장
                          date.year,
                          date.month,
                          date.day,
                          time.hour,
                          time.minute,
                        );
                        Navigator.pop(ctx);
                        _submit(isPaid: true); // ✅ 명시적으로 유료
                      }
                    }
                  },
                ),

                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool> _usePassAndSubmit(int clientId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/pass/remain?clientId=$clientId'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final remaining = int.tryParse(data['remaining'].toString()) ?? 0;

        if (remaining > 0) {
          return true;
        } else {
          final goToPurchase = await showDialog<bool>(
            context: context,
            builder:
                (_) => AlertDialog(
                  title: const Text('이용권 부족'),
                  content: const Text('이용권이 부족합니다. 구매 페이지로 이동하시겠습니까?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('아니오'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('예'),
                    ),
                  ],
                ),
          );

          if (goToPurchase == true) {
            Navigator.pushNamed(context, '/purchase-pass');
          }

          return false;
        }
      } else {
        final msg = jsonDecode(response.body)['message'] ?? '이용권 확인 실패';
        _showErrorDialog(msg);
        return false;
      }
    } catch (e) {
      print('❌ 네트워크 예외: $e');
      _showErrorDialog('네트워크 오류: $e');
      return false;
    }
  }

  void _showErrorDialog(String msg) {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('오류'),
            content: Text(msg),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('확인'),
              ),
            ],
          ),
    );
  }
// PostJobForm 클래스 내부에 추가할 메서드들

// AI 공고문 생성 다이얼로그 표시
void _showAIGenerationDialog() {
  // 필수 정보 검증
  if (!_validateBasicInfo()) return;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      child: AIJobDescriptionWidget(
        title: _titleController.text.trim(),
        category: category,
        location: location,
        payType: payType,
        pay: pay,
        workingTime: (startTime != null && endTime != null)
            ? '${startTime!.format(context)} ~ ${endTime!.format(context)}'
            : null,
        weekdays: isShortTerm ? null : selectedWeekdays,
        companyName: companyName.trim().isNotEmpty ? companyName.trim() : null,
         managerName: managerName.trim().isNotEmpty ? managerName.trim() : null, // 추가
  managerPhone: managerPhone.trim().isNotEmpty ? managerPhone.trim() : null, // 추가
        isShortTerm: isShortTerm,
        onGenerated: (generatedText) {
          setState(() {
            description = generatedText;
            _descController.text = generatedText;
          });
          Navigator.pop(context);
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('AI 공고문이 적용되었습니다!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        },
        onClose: () => Navigator.pop(context),
      ),
    ),
  );
}

// 기본 정보 유효성 검사
bool _validateBasicInfo() {
  final errors = <String>[];
  
  if (_titleController.text.trim().isEmpty) {
    errors.add('제목을 입력해주세요');
  }
  if (location.trim().isEmpty) {
    errors.add('지역을 선택해주세요');
  }
  if (pay <= 0) {
    errors.add('급여를 입력해주세요');
  }
  
  if (errors.isNotEmpty) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('정보 부족'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('AI 공고문 생성을 위해 다음 정보가 필요합니다:'),
            const SizedBox(height: 8),
            ...errors.map((error) => Text('• $error')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    return false;
  }
  return true;
}

// Pro 업그레이드 안내 다이얼로그
void _showProUpgradeDialog() {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.amber,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.star,
              color: Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 8),
          const Text('Pro 전용 기능'),
        ],
      ),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AI 공고문 생성은 Pro 사용자만 이용할 수 있습니다.',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 12),
          Text('Pro 플랜의 혜택:'),
          SizedBox(height: 8),
          Text('• AI 공고문 자동 생성'),
          Text('• 무제한 공고 등록'),
          Text('• 프리미엄 노출 서비스'),
          Text('• 고급 통계 및 분석'),
          Text('• 우선 고객 지원'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('나중에'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            // Pro 업그레이드 페이지로 이동 (라우트가 있다면)
             Navigator.pushNamed(context, '/subscription/manage');
           
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amber,
            foregroundColor: Colors.white,
          ),
          child: const Text('Pro로 업그레이드'),
        ),
      ],
    ),
  );
}
  Future<void> _showPublishTypeSheet() async {
    await _fetchFreeUsage(); // ← 이것만 추가

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: Colors.white,
      builder: (ctx) {
        final kb = MediaQuery.of(ctx).viewInsets.bottom;
        final pad = MediaQuery.of(ctx).padding.bottom;
        final bottomPad = (kb > 0 ? kb : pad) + 12;

        return Padding(
          padding: EdgeInsets.fromLTRB(20, 24, 20, bottomPad),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(
                  child: Text(
                    '📢 공고 등록 방식 선택',
                    style: TextStyle(
                      fontFamily: 'Jalnan2TTF',
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF3B8AFF),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ✅ 무료 등록: 남은/한도 뱃지 + 0일 때 안내문
                _buildTrendyCard(
                  emoji: '💸',
                  title: '무료 등록',
                  description: '24시간 노출, 푸시 알림 없음',
                  // trailing / subtitle 지원이 없다면 아래 3번 참고해서 확장
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color:
                          _freeRemaining > 0
                              ? const Color(0x143B8AFF)
                              : const Color(0x14FF3B30),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color:
                            _freeRemaining > 0
                                ? const Color(0xFF3B8AFF)
                                : const Color(0xFFFF3B30),
                      ),
                    ),
                    child: Text(
                      '$_freeRemaining/$_freeLimit',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color:
                            _freeRemaining > 0
                                ? const Color(0xFF3B8AFF)
                                : const Color(0xFFFF3B30),
                      ),
                    ),
                  ),
                  subtitle:
                      (_freeRemaining <= 0)
                          ? Text(
                            '오늘 무료 한도를 모두 사용했어요.\n'
                            '무료 등록은 자정 이후 다시 $_freeLimit개가 지급됩니다. ',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.redAccent,
                            ),
                          )
                          : null,
                  onTap: () async {
                    if (_freeRemaining <= 0) {
                      final goPaid = await showDialog<bool>(
                        context: ctx,
                        barrierDismissible: false, // 바깥 터치로 닫힘 방지(선택)
                        builder:
                            (dialogCtx) => AlertDialog(
                              title: const Text('무료 한도 초과'),
                              content: Text(
                                '무료 등록은 하루 $_freeLimit개까지입니다.\n'
                                '유료 등록으로 진행하시겠어요?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed:
                                      () => Navigator.of(dialogCtx).pop(false),
                                  child: const Text('닫기'),
                                ),
                                TextButton(
                                  onPressed:
                                      () => Navigator.of(dialogCtx).pop(true),
                                  child: const Text('유료로 진행'),
                                ),
                              ],
                            ),
                      );

                      if (goPaid == true) {
                        // 다이얼로그 닫힌 뒤 바텀시트 닫고 유료 플로우
                        Navigator.pop(ctx);
                        _submit(isPaid: true);
                      }
                      return;
                    }

                    // 한도 남아있으면 무료 등록 진행
                    Navigator.pop(ctx);
                    _submit(isPaid: false);
                  },
                ),

                const SizedBox(height: 16),

             _buildTrendyCard(
  emoji: '🔥',
  title: '유료 등록 (이용권 사용)',
  description: '72시간 노출, 푸시 전송, 6시간 상단 고정',
  trailing: Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: _paidPassCount > 0 ? const Color(0x143B8AFF) : const Color(0x14FF3B30),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(
        color: _paidPassCount > 0 ? const Color(0xFF3B8AFF) : const Color(0xFFFF3B30),
      ),
    ),
    child: Text(
      _passCountLoading ? '조회중…' : '보유 $_paidPassCount개',
      style: TextStyle(
        fontWeight: FontWeight.w700,
        color: _paidPassCount > 0 ? const Color(0xFF3B8AFF) : const Color(0xFFFF3B30),
      ),
    ),
  ),
  subtitle: (_paidPassCount <= 0 && !_passCountLoading)
      ? Row(
          children: [
            const Icon(Icons.info_outline, size: 14, color: Colors.redAccent),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                '이용권이 없습니다. 구매 후 진행해 주세요.',
                style: TextStyle(fontSize: 12, color: Colors.redAccent),
              ),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(ctx).pop(); // 바텀시트 닫기
                await Navigator.pushNamed(context, '/purchase-pass');
                await _refreshPaidPassCount();
              },
              child: const Text('구매하기'),
            ),
          ],
        )
      : null,
  onTap: () async {
    Navigator.of(ctx).pop();   // 바텀시트 닫기
    await _openPaidFlow();     // 보유수 체크 → 플로우 분기
  },
),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTrendyCard({
    required String emoji,
    required String title,
    required String description,
    required VoidCallback onTap,
    Widget? trailing, // ← 새로 추가 (우측 뱃지/버튼 등)
    Widget? subtitle, // ← 새로 추가 (설명 아래 안내문 등)
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              emoji,
              style: const TextStyle(fontFamily: 'Jalnan2TTF', fontSize: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 제목 + 우측 trailing 뱃지
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (trailing != null) ...[
                        const SizedBox(width: 8),
                        trailing,
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  // 기본 설명
                  Text(
                    description,
                    style: const TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                  // 추가 안내문
                  if (subtitle != null) ...[
                    const SizedBox(height: 8),
                    subtitle,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label, {
    bool isNumber = false,
    int maxLines = 1,
    required FormFieldSetter<String> onSaved,
    String? initialValue,
    TextEditingController? controller, // ✅ 추가
  }) {
    return TextFormField(
      controller: controller, // ✅ 우선순위: controller가 있으면 이걸 씀
      initialValue: controller == null ? initialValue : null, // ✅ 둘 다 쓰면 오류
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      maxLines: maxLines,
      validator: (val) => (val == null || val.isEmpty) ? '입력해주세요' : null,
      onSaved: onSaved,
    );
  }

  // ===================== 공통 헬퍼 =====================
  DateTime get _today0 {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime _d0(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _clampDate(DateTime d, DateTime min, DateTime max) {
    if (d.isBefore(min)) return min;
    if (d.isAfter(max)) return max;
    return d;
  }

  // ===================== 날짜 바텀시트 =====================
  // 기존 시그니처 확장: minDate/maxDate 옵션 추가
  void _showDatePickerBottomSheet({
    required DateTime? initialDate,
    DateTime? minDate,
    DateTime? maxDate,
    required void Function(DateTime) onSelected,
  }) {
    final first = _d0(minDate ?? _today0); // 기본: 오늘부터
    final last = _d0(maxDate ?? _today0.add(const Duration(days: 365)));

    DateTime selectedDate = _clampDate(
      _d0(initialDate ?? _today0),
      first,
      last,
    );
    DateTime focusedDay = selectedDate;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true, // 그대로 유지
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            // ✅ 시스템 인셋
            final safePad = MediaQuery.of(context).padding.bottom; // 네비/제스처바
            final kbPad = MediaQuery.of(context).viewInsets.bottom; // 키보드
            final bottomPad = (kbPad > 0 ? kbPad : safePad) + 8; // ✅ 둘 중 큰 값

            return ConstrainedBox(
              constraints: BoxConstraints(
                // ✅ SafeArea 하단만큼 실사용 높이에서 빼주기
                maxHeight: MediaQuery.of(context).size.height * 0.8 - safePad,
              ),
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            '날짜 선택',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TableCalendar(
                            locale: 'ko_KR',
                            focusedDay: focusedDay,
                            firstDay: first,
                            lastDay: last,
                            selectedDayPredicate:
                                (day) => isSameDay(day, selectedDate),
                            onDaySelected: (day, f) {
                              setModalState(() {
                                selectedDate = _d0(day);
                                focusedDay = day;
                              });
                            },
                            onPageChanged:
                                (f) => setModalState(() => focusedDay = f),
                            calendarStyle: const CalendarStyle(
                              todayDecoration: BoxDecoration(
                                color: Color(0xFF3B8AFF),
                                shape: BoxShape.circle,
                              ),
                              selectedDecoration: BoxDecoration(
                                color: Colors.black87,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // ✅ SafeArea는 유지하되, minimum.bottom만 수정
                  SafeArea(
                    top: false,
                    minimum: EdgeInsets.fromLTRB(16, 8, 16, bottomPad),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          onSelected(selectedDate);
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B8AFF),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        child: const Text(
                          '선택 완료',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
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

  // ===================== 날짜 박스 =====================
  Widget _buildDateBox(
    String label, // '시작일' or '종료일'
    DateTime? date,
    void Function(DateTime) onSelected,
  ) {
    return GestureDetector(
      onTap: () async {
        // 최소/최대 날짜 계산
        DateTime minDate = _today0;
        if (label == '종료일' && startDate != null) {
          final s0 = _d0(startDate!);
          if (s0.isAfter(minDate)) minDate = s0; // 종료일은 시작일 이상
        }
        final maxDate = _today0.add(const Duration(days: 365));

        final initial = _clampDate(_d0(date ?? minDate), minDate, maxDate);

        _showDatePickerBottomSheet(
          initialDate: initial,
          minDate: minDate,
          maxDate: maxDate,
          onSelected: (picked) {
            final p0 = _d0(picked);

            // 시작일 변경 시 종료일 보정
            if (label == '시작일' && endDate != null) {
              final e0 = _d0(endDate!);
              if (e0.isBefore(p0)) {
                setState(() => endDate = p0);
              }
            }
            onSelected(p0);
            setState(() {}); // UI 갱신
          },
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F9FF),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_today,
              size: 18,
              color: Color(0xFF3B8AFF),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                date != null
                    ? DateFormat('yyyy.MM.dd (E)', 'ko_KR').format(date)
                    : '$label 선택',
                style: const TextStyle(fontSize: 15),
              ),
            ),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }

  // ===================== 토글 버튼 =====================
  Widget _buildToggleButton(String label, bool value) {
    final selected = isShortTerm == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            isShortTerm = value;
            if (isShortTerm) {
              // 단기로 전환 시 과거일 정리 + 종료일 최소 보정
              if (startDate != null && _d0(startDate!).isBefore(_today0)) {
                startDate = _today0;
              }
              if (endDate != null) {
                final minEnd = _d0(startDate ?? _today0);
                if (_d0(endDate!).isBefore(minEnd)) endDate = minEnd;
              }
            } else {
              // 장기로 전환 시 날짜 초기화 원하면 주석 해제
              startDate = null;
              endDate = null;
            }
           
          });
          _validatePay(); // ← 추가
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF3B8AFF) : Colors.white,
            border: Border.all(
              color: selected ? const Color(0xFF3B8AFF) : Colors.grey,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.black87,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLongTermSubToggle(String label) {
    final selected = longTermMode == label;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            longTermMode = label;
            startDate = null;
            endDate = null;
            if (label == '요일 협의') {
              selectedWeekdays.clear(); // 지정 → 협의 전환 시 요일 비움
            } else {
              negotiationText = ''; // 협의 → 지정 전환 시 텍스트 비움
            }
          });
          _validatePay(); // ← 추가
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF3B8AFF) : Colors.white,
            border: Border.all(
              color: selected ? const Color(0xFF3B8AFF) : Colors.grey,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.black87,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  // ===================== 요일 선택(그대로) =====================
  Widget _buildWeekdaySelector() {
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    return SizedBox(
      height: 45,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        separatorBuilder: (context, index) => const SizedBox(width: 5),
        itemBuilder: (context, index) {
          final day = days[index];
          final isSelected = selectedWeekdays.contains(day);
          return GestureDetector(
            onTap: () {
              setState(() {
                if (isSelected) {
                  selectedWeekdays.remove(day);
                } else {
                  selectedWeekdays.add(day);
                }
              });
              _validatePay(); // ← 추가
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? Colors.blueAccent : Colors.white,
                border: Border.all(
                  color: isSelected ? Colors.blueAccent : Colors.grey,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                day,
                style: TextStyle(
                  fontSize: 16,
                  color: isSelected ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ===================== 근무기간 입력(호출부 동일) =====================
  Widget _buildWorkingPeriodInput() {
    if (isShortTerm) {
      // 단기: 시작/종료일
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('일하는 날짜'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildDateBox(
                  '시작일',
                  startDate,
                  (v) => setState(() => startDate = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDateBox(
                  '종료일',
                  endDate,
                  (v) => setState(() => endDate = v),
                ),
              ),
            ],
          ),
        ],
      );
    } else {
      // 장기: 서브 토글 + (요일 지정 / 요일 협의)
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('근무 형태 (장기)'),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildLongTermSubToggle('요일 지정'),
              const SizedBox(width: 12),
              _buildLongTermSubToggle('요일 협의'),
            ],
          ),
          const SizedBox(height: 12),

          if (longTermMode == '요일 지정') ...[
            const Text('요일 선택'),
            const SizedBox(height: 8),
            _buildWeekdaySelector(),
          ] else ...[
            const Text('요일 협의 내용'),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: negotiationText,
              onChanged: (v) => setState(() => negotiationText = v),
              decoration: const InputDecoration(
                hintText: '예: 주 3회, 주중 오후 가능 / 협의',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ],
      );
    }
  }

  // ===================== 퍼블리시 카드(그대로) =====================
  Widget _buildPublishOptionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F9FF),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, size: 28, color: const Color(0xFF3B8AFF)),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ===================== 시간 범위 바텀시트(가림 방지 버전) =====================
void _showTimeRangePickerBottomSheet() {
  // ===== helpers =====
  TimeOfDay _align10(TimeOfDay t) {
    int m = ((t.minute + 5) ~/ 10) * 10;
    int h = t.hour;
    if (m == 60) { m = 0; h = (h + 1) % 24; }
    return TimeOfDay(hour: h, minute: m);
  }
  int _toMinutes(TimeOfDay t) => t.hour * 60 + t.minute;
  bool _isOvernight(TimeOfDay s, TimeOfDay e) => _toMinutes(e) <= _toMinutes(s);
  int _durationMinutes(TimeOfDay s, TimeOfDay e) {
    final sm = _toMinutes(s), em = _toMinutes(e);
    int d = em - sm; if (d <= 0) d += 24 * 60; return d;
  }
  String _durationLabel(int mins) {
    final h = mins ~/ 60, m = mins % 60;
    if (h == 0) return '${m}분';
    if (m == 0) return '${h}시간';
    return '${h}시간 ${m}분';
  }
  String _fmt12(TimeOfDay t) {
    final period = t.period == DayPeriod.am ? '오전' : '오후';
    int h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final mm = t.minute.toString().padLeft(2, '0');
    return '$period $h:$mm';
  }

  // ===== initial =====
  TimeOfDay selectedStart = _align10(startTime ?? TimeOfDay.now());
  TimeOfDay selectedEnd = _align10(
    endTime ?? selectedStart.replacing(hour: (selectedStart.hour + 1) % 24),
  );

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    enableDrag: false,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          final bottomInset = MediaQuery.of(context).viewInsets.bottom;
          final safePad = MediaQuery.of(context).viewPadding.bottom;

          void _applyStart(TimeOfDay t) =>
              setModalState(() => selectedStart = _align10(t));
          void _applyEnd(TimeOfDay t) =>
              setModalState(() => selectedEnd = _align10(t));

          final overnight = _isOvernight(selectedStart, selectedEnd);
          final duration = _durationMinutes(selectedStart, selectedEnd);

          return FractionallySizedBox(
            heightFactor: 0.85, // ← 시트 자체를 85% 화면높이로 (여유)
            child: Column(
              mainAxisSize: MainAxisSize.max,
              children: [
                // 헤더 & 미리보기
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    children: [
                      const Text(
                        '근무 시간 설정',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F7FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_fmt12(selectedStart)} ~ ${overnight ? '익일 ' : ''}${_fmt12(selectedEnd)}',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 6),
                            Text('총 근무시간 ${_durationLabel(duration)}',
                                style: const TextStyle(color: Colors.black54)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),

                // 본문: Expanded로 남은 공간 사용 + 내부에서 동적 높이
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: LayoutBuilder(
                      builder: (ctx, box) {
                        // 남은 영역(box.maxHeight) 안에서 스피너 두 개의 높이 결정
                        // 라벨(두 개) + 사이 간격 대략 60px 예약
                        final reserved = 60.0 + 20.0; // 라벨 + 중간 간격
                        double each = (box.maxHeight - reserved) / 2;
                        if (each < 120) each = 120; // 최소 가시 높이

                        final content = Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('시작 시간', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: each,
                              child: TimePickerSpinner(
                                key: const ValueKey('startSpinner'),
                                is24HourMode: false,
                                minutesInterval: 10,
                                normalTextStyle: const TextStyle(fontSize: 16, color: Colors.grey),
                                highlightedTextStyle: const TextStyle(
                                  fontSize: 18,
                                  color: Color(0xFF3B8AFF),
                                  fontWeight: FontWeight.bold,
                                ),
                                spacing: 40,
                                itemHeight: 40,
                                isForce2Digits: true,
                                time: DateTime(2000, 1, 1,
                                    selectedStart.hour, selectedStart.minute),
                                onTimeChange: (dt) =>
                                    _applyStart(TimeOfDay.fromDateTime(dt)),
                              ),
                            ),

                            const SizedBox(height: 20),

                            const Text('종료 시간', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: each,
                              child: TimePickerSpinner(
                                key: const ValueKey('endSpinner'),
                                is24HourMode: false,
                                minutesInterval: 10,
                                normalTextStyle: const TextStyle(fontSize: 16, color: Colors.grey),
                                highlightedTextStyle: const TextStyle(
                                  fontSize: 18,
                                  color: Color(0xFF3B8AFF),
                                  fontWeight: FontWeight.bold,
                                ),
                                spacing: 40,
                                itemHeight: 40,
                                isForce2Digits: true,
                                time: DateTime(2000, 1, 1,
                                    selectedEnd.hour, selectedEnd.minute),
                                onTimeChange: (dt) =>
                                    _applyEnd(TimeOfDay.fromDateTime(dt)),
                              ),
                            ),
                          ],
                        );

                        // 아주 작은 화면(가로 모드 등)에서 공간이 더 모자라면 내부만 스크롤 허용
                        final needsScroll = (each * 2 + reserved) > box.maxHeight;
                        return needsScroll
                            ? SingleChildScrollView(
                                physics: const ClampingScrollPhysics(),
                                child: content,
                              )
                            : content;
                      },
                    ),
                  ),
                ),

                // 확인 버튼
                SafeArea(
                  top: false,
                  minimum: EdgeInsets.fromLTRB(
                    16, 8, 16, (bottomInset > 0 ? bottomInset : safePad) + 8,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        if (_toMinutes(selectedStart) == _toMinutes(selectedEnd)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('시작과 종료 시간이 같습니다')),
                          );
                          return;
                        }
                        setState(() {
                          startTime = selectedStart;
                          endTime = selectedEnd;
                        });
                        _validatePay(); // ← 추가
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B8AFF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                        shadowColor: const Color(0x553B8AFF),
                      ),
                      child: const Text('확인',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                    ),
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
void _openTimePicker() {
  if (Platform.isAndroid) {
    _pickTimeRangeAndroid();        // ← 앞서 드린 Android 다이얼 함수
  } else {
    _showTimeRangePickerBottomSheet(); // ← 지금 쓰는 iOS 휠 바텀시트
  }
}
Future<void> _pickTimeRangeAndroid() async {
  final use24 = MediaQuery.of(context).alwaysUse24HourFormat;

  // ── helpers ──────────────────────────────────────────────────────────
  String _fmt(TimeOfDay t) =>
      MaterialLocalizations.of(context).formatTimeOfDay(
        t, alwaysUse24HourFormat: use24,
      );

  int _toMin(TimeOfDay t) => t.hour * 60 + t.minute;

  TimeOfDay _snap10(TimeOfDay t) {
    int m = ((t.minute + 5) ~/ 10) * 10;
    int h = t.hour;
    if (m >= 60) { m = 0; h = (h + 1) % 24; }
    return TimeOfDay(hour: h, minute: m);
  }

  // ✅ 자정 넘어가면 +24시간 해서 양수로 만들어주는 총 근무시간
  int _durAcrossMidnight(TimeOfDay s, TimeOfDay e) {
    final sm = _toMin(s), em = _toMin(e);
    var d = em - sm;
    if (d <= 0) d += 24 * 60; // 익일(또는 동일 시각) 처리
    return d;
  }

  String _durLabel(int mins) {
    final h = mins ~/ 60, m = mins % 60;
    if (m == 0) return '총 근무시간 ${h}시간';
    if (h == 0) return '총 근무시간 ${m}분';
    return '총 근무시간 ${h}시간 ${m}분';
  }

  Future<TimeOfDay?> _pickOne(TimeOfDay init, String help) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: init,
      initialEntryMode: TimePickerEntryMode.input, // 숫자 입력 우선
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: use24),
        child: child!,
      ),
      helpText: help,
      cancelText: '취소',
      confirmText: '확인',
    );
    return picked == null ? null : _snap10(picked);
  }

  // ── 초기값 ───────────────────────────────────────────────────────────
  TimeOfDay s = _snap10(startTime ?? const TimeOfDay(hour: 9, minute: 0));
  TimeOfDay e = _snap10(endTime   ?? const TimeOfDay(hour: 18, minute: 0));

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSt) {
          final overnight = _toMin(e) <= _toMin(s);     // ✅ 익일 여부
          final mins = _durAcrossMidnight(s, e);        // ✅ 자정 넘어도 양수

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 헤더
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                      const Expanded(
                        child: Text('근무 시간 선택',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),

                // 미리보기 (익일 표시)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F7FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_fmt(s)} ~ ${overnight ? '익일 ' : ''}${_fmt(e)}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _durLabel(mins),
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ),

                // 시작/종료 선택
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final picked = await _pickOne(s, '시작 시간');
                            if (picked != null) setSt(() => s = picked);
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.play_arrow, size: 18),
                              const SizedBox(width: 6),
                              Text('시작 ${_fmt(s)}'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final picked = await _pickOne(e, '종료 시간');
                            if (picked != null) setSt(() => e = picked);
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.stop, size: 18),
                              const SizedBox(width: 6),
                              Text('종료 ${_fmt(e)}'),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),
                const Divider(height: 1),

                // 확인
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          // ✅ 동일 시각(24시간) 방지 + 최소 근무 10분 보장
                          if (_toMin(e) == _toMin(s)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('시작과 종료 시간이 같습니다')),
                            );
                            return;
                          }
                          final total = _durAcrossMidnight(s, e);
                          if (total < 10) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('근무시간은 최소 10분 이상이어야 합니다')),
                            );
                            return;
                          }

                          setState(() { startTime = s; endTime = e; });
                          _validatePay();
                          Navigator.pop(ctx);
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('확인'),
                      ),
                    ),
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



  @override
  Widget build(BuildContext context) {
    final susp = _suspension;                       // 현재 불러온 정지 상태
final suspLoaded = _suspLoaded;                 // /public/suspension 로딩 완료 여부
final previewDisabled = !suspLoaded || (susp?.isSuspended ?? false); // 로딩중 or 정지면 비활성화
    return UnfocusOnTap(
      child:
    Form(
      key: _formKey,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16), // 여기에 전체 padding 줘도 OK
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () async {
                  final selectedJob = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SelectPreviousJobScreen(),
                    ),
                  );

                  if (selectedJob != null) _fillFormWithJob(selectedJob);
                },
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F4FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF3B8AFF)),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.history, color: Color(0xFF3B8AFF)),
                      SizedBox(width: 8),
                      Text(
                        '이전에 작성한 공고 불러오기',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF3B8AFF),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _buildTextField(
                '제목',
                controller: _titleController,
                onSaved: (val) => title = val!,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: category,
                items:
                    ['제조', '물류', '서비스', '건설', '사무', '청소', '기타']
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                onChanged: (val) {
                  setState(() {
                    category = val!;
                  });
                },
                decoration: const InputDecoration(labelText: '하는 일'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _locationController,
                readOnly: true,
                decoration: const InputDecoration(labelText: '지역'),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (_) => KpostalView(
                            useLocalServer: false,
                            callback: (result) async {
                              setState(() {
                                location = result.address;
                                locationCity = _extractCity(result.address);
                                _locationController.text = result.address;
                              });
                              final loc = await locationFromAddress(
                                result.address,
                              );
                              if (loc.isNotEmpty) {
                                setState(() {
                                  lat = loc.first.latitude;
                                  lng = loc.first.longitude;
                                });
                              }
                            },
                          ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              const Text('일하는 기간은 얼마나 되나요?'),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildToggleButton('단기', true),
                  const SizedBox(width: 12),
                  _buildToggleButton('1개월 이상', false),
                ],
              ),

              const SizedBox(height: 16),
              _buildWorkingPeriodInput(),
              const SizedBox(height: 16),
              const Text('일하는 시간'),
              const SizedBox(height: 8),
              GestureDetector(
             onTap: _openTimePicker, // ← 여기만 바꾸면 플랫폼별로 자동 분기
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F9FF),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Icon(Icons.access_time, color: Color(0xFF3B8AFF)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          (startTime != null && endTime != null)
                              ? '${startTime!.format(context)} ~ ${endTime!.format(context)}'
                              : '시간 선택',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
              const Text('급여 형태'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap:
                          () => setState(() {
                            payType = '일급';
                            _validatePay(); // ✅ 추가
                          }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color:
                                payType == '일급'
                                    ? Colors.blueAccent
                                    : Colors.grey,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          color:
                              payType == '일급'
                                  ? Colors.blueAccent
                                  : Colors.white,
                        ),
                        child: Text(
                          '일급',
                          style: TextStyle(
                            fontSize: 16,

                            color:
                                payType == '일급' ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap:
                          () => setState(() {
                            payType = '주급';
                            _validatePay(); // ✅ 추가
                          }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color:
                                payType == '주급'
                                    ? Colors.blueAccent
                                    : Colors.grey,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          color:
                              payType == '주급'
                                  ? Colors.blueAccent
                                  : Colors.white,
                        ),
                        child: Text(
                          '주급',
                          style: TextStyle(
                            fontSize: 16,

                            color:
                                payType == '주급' ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _payController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '급여',
                  border: OutlineInputBorder(),
                  errorText: _payWarning,
                ),
                onChanged: (val) {
                  // 1) 숫자만 추출
                  final numeric = val.replaceAll(RegExp(r'[^0-9]'), '');

                  // 2) 상태(pay)와 경고 갱신
                  final parsed = numeric.isEmpty ? 0 : int.parse(numeric);
                  setState(() {
                    pay = parsed;
                    _validatePay();
                  });
                  final _payFormatter = NumberFormat(
                    '#,###',
                  ); // 파일 상단에 import intl 되어있음
                  // 3) 표시값을 천단위 콤마로 재설정 (커서 위치 유지)
                  if (val != _payFormatter.format(parsed)) {
                    final formatted =
                        numeric.isEmpty ? '' : _payFormatter.format(parsed);
                    _payController.value = TextEditingValue(
                      text: formatted,
                      selection: TextSelection.collapsed(
                        offset: formatted.length,
                      ),
                    );
                  }
                },
                onSaved: (val) {
                  // 저장 시에도 안전하게 숫자만 추출
                  final numeric = (val ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                  pay = numeric.isEmpty ? 0 : int.parse(numeric);
                },
              ),
              const SizedBox(height: 16),

              CheckboxListTile(
                title: const Text('당일지급'),
                value: isSameDayPay,
                onChanged: (bool? value) {
                  setState(() {
                    isSameDayPay = value ?? false;
                  });
                },
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _pickImages,
                icon: const Icon(Icons.image, size: 20, color: Colors.white),
                label: const Text(
                  '사진 선택',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B8AFF), // 💙 알바일주 메인 컬러
                  foregroundColor: Colors.white, // 아이콘/텍스트 색
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 20,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12), // 둥근 모서리
                  ),
                  elevation: 3, // 그림자
                ),
              ),
              if (imageUrls.isNotEmpty || images.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 120,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemCount: imageUrls.length + images.length,
                    itemBuilder: (context, i) {
                      final isServer = i < imageUrls.length;
                      final thumb =
                          isServer
                              ? imageUrls[i]
                              : images[i - imageUrls.length];

                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child:
                                isServer
                                    ? Image.network(
                                      thumb as String,
                                      height: 120,
                                      width: 120,
                                      fit: BoxFit.cover,
                                    )
                                    : Image.file(
                                      thumb as File,
                                      height: 120,
                                      width: 120,
                                      fit: BoxFit.cover,
                                    ),
                          ),
                          Positioned(
                            right: -6,
                            top: -6,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  if (isServer) {
                                    // 서버 이미지: 삭제대상에 담고 목록에서 제거
                                    deleteImageUrls.add(imageUrls[i]);
                                    imageUrls.removeAt(i);
                                  } else {
                                    images.removeAt(i - imageUrls.length);
                                  }
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 16),
            // AI 생성 버튼 섹션
Container(
  width: double.infinity,
  margin: const EdgeInsets.only(bottom: 12),
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    gradient: LinearGradient(
      colors: [
        const Color(0xFF3B8AFF).withOpacity(0.1),
        const Color(0xFF8B5FBF).withOpacity(0.1),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(
      color: const Color(0xFF3B8AFF).withOpacity(0.3),
    ),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF3B8AFF).withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: Color(0xFF3B8AFF),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'AI 공고문 생성',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF3B8AFF),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (!_isProUser)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'PRO',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const Text(
                  '입력 정보를 바탕으로 매력적인 공고문을 자동 생성',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _isAIGenerating
              ? null
              : (_isProUser ? _showAIGenerationDialog : _showProUpgradeDialog),
          icon: _isAIGenerating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.auto_awesome),
          label: Text(_isAIGenerating 
              ? 'AI 생성 중...' 
              : 'AI로 공고문 생성하기'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _isProUser 
                ? const Color(0xFF3B8AFF) 
                : Colors.amber,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    ],
  ),
),

// 기존 텍스트 입력 필드
SizedBox(
  height: 320,
  child: TextFormField(
    controller: _descController,
    maxLines: null,
    expands: true,
    keyboardType: TextInputType.multiline,
    textInputAction: TextInputAction.newline,
    style: const TextStyle(fontSize: 16),
    decoration: InputDecoration(
      labelText: '자세한 설명',
      hintText: description.isEmpty 
          ? '부적절하거나 불쾌감을 줄 수 있는 내용을 작성할 경우 제재를 받을 수 있습니다.'
          : null,
      border: const OutlineInputBorder(),
      alignLabelWithHint: true,
      suffixIcon: description.isNotEmpty
          ? IconButton(
              onPressed: () {
                setState(() {
                  description = '';
                  _descController.clear();
                });
              },
              icon: const Icon(Icons.clear),
              tooltip: '내용 지우기',
            )
          : null,
    ),
    onSaved: (val) => description = val ?? '',
    onChanged: (val) => setState(() => description = val),
  ),
),
              const SizedBox(height: 24),
              const LaborAgreementNotice(),
             SizedBox(
  width: double.infinity,
  child: ElevatedButton(
    style: ElevatedButton.styleFrom(
      backgroundColor: previewDisabled ? Colors.grey : const Color(0xFF3B8AFF),
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    onPressed: previewDisabled ? null : () {
      // ✅ 최종 방어(토스트/다이얼로그 포함)
      final s = susp ?? const SuspensionState(
        suspendedType: null, suspendedUntil: null, suspendedReason: null,
      );
      if (!guardSuspended(context, s)) return;

      if (_formKey.currentState!.validate()) {
        _formKey.currentState!.save();

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => JobPreviewDetailScreen(
              title: title,
              category: category,
              location: location,
              // lat/lng는 double non-null이라 ?? 필요 없음
              lat: lat,
              lng: lng,
              companyName: companyName,
              managerName: managerName,
              startDate: isShortTerm ? startDate?.toString().split(' ')[0] : null,
              endDate:   isShortTerm ? endDate?.toString().split(' ')[0]   : null,
              weekdays:  isShortTerm ? [] : selectedWeekdays,
              workingTime: (startTime != null && endTime != null)
                  ? '${startTime!.format(context)} ~ ${endTime!.format(context)}'
                  : '시간 미정',
              payType: payType,
              pay: pay,
              description: description,
              images: images,
              onSubmit: () {
                Navigator.pop(context);
                _showPublishTypeSheet();
              },
            ),
          ),
        );
      }
    },
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.visibility, color: Colors.white),
        const SizedBox(width: 8),
        Text(
          !suspLoaded
              ? '계정 상태 확인 중…'
              : (susp?.isSuspended ?? false) ? '정지된 계정' : '미리보기',
          style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ],
    ),
  ),
),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

class LaborAgreementNotice extends StatefulWidget {
  const LaborAgreementNotice({super.key});

  @override
  State<LaborAgreementNotice> createState() => _LaborAgreementNoticeState();
}

class _LaborAgreementNoticeState extends State<LaborAgreementNotice> {
  bool isExpanded = false;

  void _openPolicy(String filePath, String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PolicyDetailScreen(filePath: filePath, title: title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => isExpanded = !isExpanded),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                // ★ 가변폭으로 받아서 넘침 방지
                child: Text(
                  '공고 등록 시 알바 준수사항에 동의한 것으로 간주됩니다.',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis, // ★ … 처리
                  softWrap: false,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                isExpanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                semanticLabel: isExpanded ? '접기' : '펼치기',
              ),
            ],
          ),
        ),

        if (isExpanded) ...[
          const SizedBox(height: 8),
          ListTile(
            title: const Text('📌 최저임금법 준수'),
            subtitle: const Text('2025년 기준 시급 10,030원 이상 지급'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openPolicy('assets/policies/wage_policy.md', '최저임금법'),
          ),
          ListTile(
            title: const Text('📌 근로기준법 준수'),
            subtitle: const Text('근무시간, 휴게시간 등 법적 기준 준수'),
            trailing: const Icon(Icons.chevron_right),
            onTap:
                () => _openPolicy('assets/policies/labor_policy.md', '근로기준법'),
          ),
          ListTile(
            title: const Text('📌 고용차별 금지'),
            subtitle: const Text('성별, 연령, 외모 등에 의한 차별 금지'),
            trailing: const Icon(Icons.chevron_right),
            onTap:
                () => _openPolicy(
                  'assets/policies/equality_policy.md',
                  '고용차별 금지',
                ),
          ),
        ],
      ],
    );
  }
}
// 파일 상단 임포트는 그대로 두고, 클래스 밖(같은 파일 맨 아래여도 OK)에 추가
class UnfocusOnTap extends StatelessWidget {
  final Widget child;
  const UnfocusOnTap({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent, // 빈 공간 터치도 감지
      onTap: () {
        final currentFocus = FocusScope.of(context);
        if (!currentFocus.hasPrimaryFocus && currentFocus.focusedChild != null) {
          currentFocus.unfocus();
        }
      },
      child: child,
    );
  }
}
