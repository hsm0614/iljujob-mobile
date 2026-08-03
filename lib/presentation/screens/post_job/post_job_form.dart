import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:kpostal/kpostal.dart';
import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart';
import 'package:iljujob/data/services/job_service.dart';
import 'package:iljujob/data/models/job.dart';
import 'dart:convert';
import 'package:iljujob/config/constants.dart';
import 'package:http/http.dart' as http;
import 'package:iljujob/presentation/screens/post_job/job_preview_detail_screen.dart';
import 'package:iljujob/presentation/screens/policy_detail_screen.dart';
import 'package:iljujob/presentation/screens/post_job/SelectPreviousJobScreen.dart';
import 'package:time_picker_spinner/time_picker_spinner.dart';
import 'package:iljujob/core/suspension.dart';
import 'package:iljujob/core/suspension_guard.dart';
import '../../../data/services/ai_job_description_service.dart';
import '../../../data/services/authenticated_http_client.dart';
import 'package:iljujob/presentation/screens/client_screen/wage_report_screen.dart';
import 'package:iljujob/presentation/screens/purchase_screen.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:iljujob/config/app_theme.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../data/services/client_tracking_service.dart';
import 'post_job_controller.dart' show getCurrentLocation;
import 'package:iljujob/utils/pay_display.dart';
import 'package:iljujob/utils/date_ymd.dart';

// 2026년 적용 최저시급
const int minWagePerHour = 10320;
const int _kMaxImages = 10;
const int _totalQ = 6;
const String _draftKey = 'post_job_draft_v1';

const _blue = AppColors.primary;
const _bg = AppColors.bgPage;
const _border = AppColors.border;
// 보조 정보·아이콘. textTertiary(#9CA3AF)는 _bg 위 2.35:1로 WCAG AA 미달이라 승격.
const _label = AppColors.textSecondary;
const _text = AppColors.textPrimary;
const _sub = AppColors.textSecondary;

// ════════════════════════════════════════════════════════
//  업종 데이터
// ════════════════════════════════════════════════════════
class _CatData {
  final IconData icon;
  final String name;
  final List<String> sub;
  const _CatData({required this.icon, required this.name, required this.sub});
}

const _allCats = [
  _CatData(
    icon: Icons.restaurant_outlined,
    name: '음식점·카페',
    sub: ['홀서빙', '주방보조', '배달', '카페·바리스타', '패스트푸드', '포장·설거지'],
  ),
  _CatData(
    icon: Icons.storefront_outlined,
    name: '편의점·마트',
    sub: ['편의점', '슈퍼·마트', '창고정리', '재고관리', '계산원'],
  ),
  _CatData(
    icon: Icons.inventory_2_outlined,
    name: '물류·배송',
    sub: ['배송기사', '상하차', '물류센터', '포장', '택배분류', '입출고'],
  ),
  _CatData(
    icon: Icons.factory_outlined,
    name: '제조·공장',
    sub: ['생산·조립', '검품·포장', '식품제조', '기계조작', '단순노무'],
  ),
  _CatData(
    icon: Icons.memory_outlined,
    name: '반도체·전자생산',
    sub: ['반도체 생산', '전자부품 조립', 'PCB·SMT', '품질검사', '클린룸', '장비오퍼레이터'],
  ),
  _CatData(
    icon: Icons.construction_outlined,
    name: '건설·현장',
    sub: ['건설일용', '인테리어', '청소·마감', '자재운반', '도장·도배'],
  ),
  _CatData(
    icon: Icons.desktop_windows_outlined,
    name: '사무·행정',
    sub: ['사무보조', '데이터입력', '고객응대', '텔레마케터', '회계보조'],
  ),
  _CatData(
    icon: Icons.cleaning_services_outlined,
    name: '청소·시설관리',
    sub: ['건물청소', '시설관리', '환경미화', '방역·소독', '세탁·세차'],
  ),
  _CatData(
    icon: Icons.shopping_bag_outlined,
    name: '서비스·판매',
    sub: ['매장판매', '시식·홍보', '전단지', '주차관리', '안내·접수'],
  ),
  _CatData(
    icon: Icons.event_outlined,
    name: '이벤트·행사',
    sub: ['행사스태프', '진행보조', '설치·철거', '모델·도우미', '공연스태프'],
  ),
];

String _majorOf(String val) {
  for (final c in _allCats) {
    if (c.name == val || c.sub.contains(val)) return c.name;
  }
  return '';
}

const _qTitles = [
  '어떤 일인가요?',
  '업종을 선택해주세요',
  '근무지가 어디인가요?',
  '언제 일하나요?',
  '급여는 얼마인가요?',
  '공고 내용을 채워주세요',
];
const _qSubs = [
  '공고 제목을 입력해주세요',
  '업종 → 세부 직종 순으로 선택해주세요',
  '근무지 주소를 검색해주세요',
  '근무 날짜와 시간을 한 번에 입력해주세요',
  '최저시급 10,320원 이상이어야 해요',
  '선택 사항이에요 · 건너뛰어도 돼요',
];
const _jobPostStepEvents = [
  'job_post_title_complete',
  'job_post_category_complete',
  'job_post_location_complete',
  'job_post_schedule_complete',
  'job_post_pay_complete',
  'job_post_description_complete',
];

// ════════════════════════════════════════════════════════
//  PostJobForm
// ════════════════════════════════════════════════════════
class PostJobForm extends StatefulWidget {
  final bool isRepost;
  final Job? existingJob;
  final VoidCallback? onSubmitComplete;
  const PostJobForm({
    super.key,
    required this.isRepost,
    required this.existingJob,
    this.onSubmitComplete,
  });
  @override
  State<PostJobForm> createState() => _PostJobFormState();
}

class _PostJobFormState extends State<PostJobForm>
    with TickerProviderStateMixin {
  int _q = 0;
  bool _submitted = false;

  String _title = '';
  String _category = '';
  String _majorCat = '';
  String _location = '', _locationCity = '';
  double _lat = 0, _lng = 0;
  bool _gpsLoading = false;
  bool _isShortTerm = true;
  DateTime? _startDate, _endDate;
  List<String> _weekdays = [];
  String _longTermMode = '요일 지정';
  String _negotiationText = '';
  TimeOfDay? _startTime, _endTime;
  String _payType = '시급';
  int _pay = 0;
  bool _isSameDayPay = false;
  // 장기 공고 전용
  bool _isAlwaysOpen = false;
  int? _workDaysPerWeek;
  final _requiredCertsCtrl = TextEditingController();
  final _welfareCtrl = TextEditingController();
  String _description = '';
  bool _externalApplyEnabled = false;
  final List<File> _images = [];
  List<String> _imageUrls = [], _deleteImageUrls = [];

  final _payCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _negoCtrl = TextEditingController();
  final _externalApplyUrlCtrl = TextEditingController();

  String companyName = '', managerName = '', managerPhone = '';
  DateTime? publishAt;
  bool _isAIGenerating = false, _isSubmitting = false;
  bool _passCountLoading = false, _suspLoaded = false;
  // 조회 실패와 "이용권 0개"는 다른 상태다. 섞으면 보유자에게 구매를 유도하게 된다.
  bool _passCountFailed = false;
  int _paidPassCount = 0;
  int _urgentPassCount = 0;
  // AI 할당량: -1=무제한(pro), 0=소진, N=잔여
  String? _subscriptionPlan;
  int _aiQuotaRemaining = 0;
  String _aiQuotaResetText = '';
  String? _payWarning;
  SuspensionState? _suspension;
  Timer? _draftSaveTimer;

  static const _kAiFreeWeekKey = 'ai_free_week_key';
  static const _kAiFreeUsedKey = 'ai_free_used';

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;
  final ScrollController _contentScrollCtrl = ScrollController();
  bool get _canNext {
    switch (_q) {
      case 0:
        return _title.trim().isNotEmpty;
      case 1:
        return _category.isNotEmpty;
      case 2:
        return _location.isNotEmpty;
      case 3:
        final hasDate =
            _isShortTerm
                ? _startDate != null
                : _longTermMode == '요일 지정'
                ? _weekdays.isNotEmpty
                : true;
        return hasDate && _startTime != null && _endTime != null;
      case 4:
        return isNegotiablePayType(_payType) ||
            (_pay > 0 && _payWarning == null);
      case 5:
        return true;
      default:
        return false;
    }
  }

  @override
  void initState() {
    super.initState();
    ClientTrackingService.instance.track('job_post_start');
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
    _loadInitialData();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _refreshPaidPassCount(),
    );
    _loadSuspension();
    _checkProStatus();
    _loadAiQuota();
  }

  @override
  void dispose() {
    if (!_submitted) {
      ClientTrackingService.instance.track('job_post_abandon');
    }
    _draftSaveTimer?.cancel();
    _saveDraft();
    _fadeCtrl.dispose();
    _contentScrollCtrl.dispose();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _negoCtrl.dispose();
    _externalApplyUrlCtrl.dispose();
    _payCtrl.dispose();
    super.dispose();
  }

  Future<void> _nextQ() async {
    if (!_canNext) return;
    FocusManager.instance.primaryFocus?.unfocus();

    // GA4 퍼널 이벤트
    FirebaseAnalytics.instance.logEvent(
      name: 'post_job_step_complete',
      parameters: {
        'step': _q,
        'step_name': _qTitles[_q],
        'pay_type': _payType,
        'is_short_term': _isShortTerm ? 1 : 0,
      },
    );
    ClientTrackingService.instance.track(
      _jobPostStepEvents[_q],
      properties: {
        'step': _q,
        'step_name': _qTitles[_q],
        'pay_type': _payType,
        'is_short_term': _isShortTerm,
      },
    );

    if (_q == _totalQ - 1) {
      _saveDraft();
      _onPreview();
      return;
    }
    await _fadeCtrl.reverse();
    setState(() {
      _q++;
    });
    _scheduleDraftSave();
    _fadeCtrl.forward();
  }

  Future<void> _prevQ() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_q == 0) {
      Navigator.pop(context);
      return;
    }
    await _fadeCtrl.reverse();
    setState(() => _q--);
    _scheduleDraftSave();
    _fadeCtrl.forward();
  }

  // ── 날짜 유틸 ──
  DateTime _weekStart(DateTime d) => DateTime(
    d.year,
    d.month,
    d.day,
  ).subtract(Duration(days: DateTime(d.year, d.month, d.day).weekday - 1));
  String _currentWeekKey() =>
      DateFormat('yyyy-MM-dd').format(_weekStart(DateTime.now()));
  DateTime _nextWeekStart() =>
      _weekStart(DateTime.now()).add(const Duration(days: 7));
  // 날짜를 "YYYY-MM-DD" 문자열로 변환 (로컬 날짜 기준) → utils/date_ymd.dart
  String _dateToYmd(DateTime d) => toYmd(d);

  Future<void> _loadSuspension() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getInt('userId');
      if (id == null) throw Exception();
      final res = await http.get(
        Uri.parse('$baseUrl/api/public/suspension?type=client&id=$id'),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _suspension = SuspensionState(
            suspendedType:
                (data['suspended_type'] ?? data['suspendedType'])?.toString(),
            suspendedUntil:
                (data['suspended_until'] ?? data['suspendedUntil'])?.toString(),
            suspendedReason:
                (data['suspended_reason'] ?? data['suspendedReason'])
                    ?.toString(),
          );
          _suspLoaded = true;
        });
        return;
      }
    } catch (_) {}
    setState(() {
      _suspension = const SuspensionState(
        suspendedType: null,
        suspendedUntil: null,
        suspendedReason: null,
      );
      _suspLoaded = true;
    });
  }

  Future<void> _checkProStatus() async {
    try {
      final res = await AuthenticatedHttpClient.get(
        Uri.parse('$baseUrl/api/subscription/status'),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        final plan = d['plan']?.toString();
        final isActive = d['active'] == true;
        setState(() {
          _subscriptionPlan = isActive ? plan : null;
        });
      }
    } catch (_) {
      setState(() => _subscriptionPlan = null);
    }
  }

  Future<void> _refreshPaidPassCount() async {
    try {
      setState(() {
        _passCountLoading = true;
        _passCountFailed = false;
      });
      final prefs = await SharedPreferences.getInstance();
      final clientId = prefs.getInt('userId');
      if (clientId == null || clientId <= 0) {
        setState(() {
          _passCountLoading = false;
          _passCountFailed = true;
        });
        return;
      }
      final res = await AuthenticatedHttpClient.get(
        Uri.parse(
          '$baseUrl/api/pass/remain',
        ).replace(queryParameters: {'clientId': '$clientId'}),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 8));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final d = jsonDecode(utf8.decode(res.bodyBytes));
        setState(() {
          _paidPassCount =
              int.tryParse(
                '${d['instant'] ?? d['remaining'] ?? d['remain'] ?? 0}',
              ) ??
              0;
          _urgentPassCount = int.tryParse('${d['urgent'] ?? 0}') ?? 0;
        });
      } else {
        setState(() => _passCountFailed = true);
      }
    } catch (_) {
      // 실패를 0개로 두면 이용권 보유자에게 결제 화면을 띄우게 된다.
      if (mounted) setState(() => _passCountFailed = true);
    } finally {
      if (mounted) setState(() => _passCountLoading = false);
    }
  }

  // AI 할당량 로드: 구독자 무제한(-1), 비구독자 주 1회 무료
  Future<void> _loadAiQuota() async {
    if (_subscriptionPlan != null) {
      if (!mounted) return;
      setState(() => _aiQuotaRemaining = -1);
      return;
    }

    // 비구독: 주 1회 무료
    final prefs = await SharedPreferences.getInstance();
    final nowKey = _currentWeekKey();
    int used = prefs.getInt(_kAiFreeUsedKey) ?? 0;
    if (prefs.getString(_kAiFreeWeekKey) != nowKey) {
      await prefs.setString(_kAiFreeWeekKey, nowKey);
      await prefs.setInt(_kAiFreeUsedKey, 0);
      used = 0;
    }
    if (!mounted) return;
    setState(() {
      _aiQuotaRemaining = used >= 1 ? 0 : 1;
      _aiQuotaResetText = DateFormat(
        'M월 d일 00:00',
        'ko_KR',
      ).format(_nextWeekStart());
    });
  }

  Future<void> _consumeAiUsage() async {
    if (_subscriptionPlan != null) return; // 구독자는 소비 없음

    // 비구독: 주 1회 소진
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAiFreeWeekKey, _currentWeekKey());
    await prefs.setInt(_kAiFreeUsedKey, 1);
    if (!mounted) return;
    setState(() => _aiQuotaRemaining = 0);
  }

  Future<void> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    final clientId = prefs.getInt('userId');
    if (clientId != null) await _fetchClientProfile(clientId);
    if (widget.isRepost && widget.existingJob != null) {
      final job = widget.existingJob!;
      setState(() {
        _title = job.title;
        _titleCtrl.text = job.title;
        _category = job.category;
        _majorCat = _majorOf(job.category);
        _location = job.location;
        _locationCity = job.locationCity;
        _lat = job.lat;
        _lng = job.lng;
        _pay = int.tryParse(job.pay) ?? 0;
        _payType = job.payType;
        _payCtrl.text = NumberFormat('#,###').format(_pay);
        _description = job.description ?? '';
        _descCtrl.text = _description;
        final weekdaysText = job.weekdays?.trim() ?? '';
        _isShortTerm = weekdaysText.isEmpty;
        if (weekdaysText == '협의' || weekdaysText.startsWith('협의:')) {
          _longTermMode = '요일 협의';
          _negotiationText = weekdaysText.replaceFirst(
            RegExp(r'^협의\s*:?\s*'),
            '',
          );
          _negoCtrl.text = _negotiationText;
          _weekdays = [];
        } else {
          _longTermMode = '요일 지정';
          _weekdays =
              weekdaysText
                  .split(',')
                  .where((d) => d.trim().isNotEmpty)
                  .toList();
        }
        // startDate는 UTC → 로컬로 변환해서 날짜 표기 기준 맞춤
        _startDate = job.startDate?.toLocal();
        _endDate = job.endDate?.toLocal() ?? job.startDate?.toLocal();
        _startTime = _parseTime(job.startTime);
        _endTime = _parseTime(job.endTime);
      });
    }
    await _maybeOfferDraftRestore();
  }

  Future<void> _fetchClientProfile(int clientId) async {
    final res = await AuthenticatedHttpClient.get(
      Uri.parse('$baseUrl/api/client/profile?id=$clientId'),
    );
    if (res.statusCode == 200) {
      final d = json.decode(res.body);
      setState(() {
        companyName = d['company_name'] ?? '';
        managerName = d['manager_name'] ?? '';
        managerPhone = d['manager_phone'] ?? d['phone'] ?? '';
      });
    }
  }

  // ── 유틸 ──
  TimeOfDay? _parseTime(String? s) {
    if (s == null || !s.contains(':')) return null;
    final p = s.trim().split(':');
    if (p.length != 2) return null;
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }

  String _fmt24(TimeOfDay? t) =>
      t == null
          ? ''
          : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  String _extractCity(String addr) {
    final parts = addr.split(' ');
    if (parts.isEmpty) return '';
    final first = parts[0];
    if (first.contains('광역시') || first.contains('특별시')) {
      return first.replaceAll(RegExp(r'(광역시|특별시)'), '');
    }
    if (first.contains('도') && parts.length > 1) return parts[1];
    return first;
  }

  int _toMin(TimeOfDay t) => t.hour * 60 + t.minute;
  int _workMins() {
    if (_startTime == null || _endTime == null) return 0;
    int d = _toMin(_endTime!) - _toMin(_startTime!);
    if (d <= 0) d += 1440;
    return d;
  }

  int _inclDays(DateTime s, DateTime e) =>
      DateTime(
        e.year,
        e.month,
        e.day,
      ).difference(DateTime(s.year, s.month, s.day)).inDays +
      1;
  void _validatePay() {
    if (isNegotiablePayType(_payType)) {
      setState(() => _payWarning = null);
      return;
    }
    if (_pay <= 0) {
      setState(() => _payWarning = null);
      return;
    }

    // ── 시급: 직접 시급 검증
    if (_payType == '시급') {
      setState(
        () =>
            _payWarning =
                _pay >= minWagePerHour
                    ? null
                    : '최저시급 미달 · 최소 ${NumberFormat('#,###').format(minWagePerHour)}원 이상',
      );
      return;
    }

    // ── 월급: 209시간 기준 최저 월급여 검증
    if (_payType == '월급') {
      const int minMonthly = 2156880; // 10,320 × 209h
      setState(
        () =>
            _payWarning =
                _pay >= minMonthly
                    ? null
                    : '최저임금 미달 · 최소 ${NumberFormat('#,###').format(minMonthly)}원 이상',
      );
      return;
    }

    final mins = _workMins();
    if (mins == 0) {
      setState(() => _payWarning = null);
      return;
    }
    final hours = mins / 60.0;

    // ── 일급
    if (_payType == '일급') {
      final req = (minWagePerHour * hours).ceil();
      setState(
        () =>
            _payWarning =
                _pay >= req
                    ? null
                    : '최저시급 미달 · 최소 ${NumberFormat('#,###').format(req)}원 이상',
      );
      return;
    }

    // ── 주급
    if (_payType == '주급') {
      int dpw = 0;
      if (_isShortTerm) {
        if (_startDate != null && _endDate != null) {
          dpw = _inclDays(_startDate!, _endDate!).clamp(1, 7);
        } else {
          return;
        }
      } else {
        if (_longTermMode == '요일 지정') {
          dpw = _weekdays.length;
          if (dpw <= 0) return;
        } else {
          return;
        }
      }
      final req = (minWagePerHour * hours * dpw).ceil();
      setState(
        () =>
            _payWarning =
                _pay >= req
                    ? null
                    : '최저시급 미달 · 최소 ${NumberFormat('#,###').format(req)}원 이상',
      );
      return;
    }

    setState(() => _payWarning = null);
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(
      imageQuality: 85,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (picked.isEmpty) return;
    final available = _kMaxImages - _images.length - _imageUrls.length;
    if (available <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('사진은 최대 10장까지 등록할 수 있어요')));
      }
      return;
    }
    setState(
      () => _images.addAll(picked.take(available).map((x) => File(x.path))),
    );
  }

  void _showError(String msg) => showDialog(
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

  Future<void> _submit({required bool isPaid, String? passType}) async {
    if (_isSubmitting) return;
    final prefs = await SharedPreferences.getInstance();
    final clientId = prefs.getInt('userId');
    final userType = prefs.getString('userType') ?? '';
    if (clientId == null) {
      _showError('로그인 정보가 올바르지 않습니다.');
      return;
    }

    // 단기 공고인데 날짜가 없으면 등록 막기
    if (_isShortTerm && _startDate == null) {
      _showError('근무 날짜를 선택해주세요.');
      return;
    }
    final externalApplyUrl = _normalizedExternalApplyUrl();
    if (_externalApplyEnabled && externalApplyUrl == null) {
      _showError('외부 신청 페이지 주소를 확인해주세요.');
      return;
    }
    if (_externalApplyEnabled && !isPaid) {
      _showError('외부 신청 연결은 즉시게시·긴급호출 공고에서만 사용할 수 있어요.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final isDays = !_isShortTerm && _longTermMode == '요일 지정';
      final isNeg = !_isShortTerm && _longTermMode == '요일 협의';
      final negotiationText = _negotiationText.trim();
      final wdPayload =
          isDays
              ? (_weekdays.isNotEmpty ? _weekdays.join(',') : null)
              : (isNeg
                  ? (negotiationText.isEmpty ? '협의' : '협의: $negotiationText')
                  : null);

      // 날짜를 로컬 기준 YYYY-MM-DD 문자열로 명시적 변환
      //         toIso8601String().split('T')[0] 는 UTC 변환 후 날짜를 잘라
      //         자정 근처에 KST와 UTC 날짜가 달라지는 버그 있음
      final startDateStr =
          _startDate != null
              ? _dateToYmd(_startDate!)
              : _dateToYmd(DateTime.now());
      final endDateStr =
          _endDate != null ? _dateToYmd(_endDate!) : startDateStr;

      // 예약 공개 시각 — 로컬 시간 기준으로 생성한 뒤 UTC로 변환
      //         DateTime()은 로컬 기준이므로 toUtc()로 명시 변환
      final publishAtUtcStr = publishAt?.toUtc().toIso8601String();

      final result = await JobService.postJobWithImages(
        title: _title.trim(),
        category: _category,
        categoryMajor: _majorOf(_category),
        categorySub: _category,
        location: _location,
        locationCity: _locationCity,
        startDate: startDateStr,
        endDate: endDateStr,
        startTime: _fmt24(_startTime),
        endTime: _fmt24(_endTime),
        payType: _payType,
        pay: _pay,
        description: _description.trim(),
        images: _images,
        clientId: clientId,
        weekdays: (wdPayload?.trim().isNotEmpty ?? false) ? wdPayload : null,
        lat: _lat,
        lng: _lng,
        isScheduled: publishAt != null,
        publishAt: publishAtUtcStr, // UTC ISO 문자열
        isSameDayPay: _isSameDayPay,
        isPaid: isPaid,
        passType: passType,
        isAgency: clientId == 1,
        // 장기 공고 전용
        jobType: _isShortTerm ? 'short' : 'long',
        isAlwaysOpen: !_isShortTerm && _isAlwaysOpen,
        workDaysPerWeek: !_isShortTerm ? _workDaysPerWeek : null,
        requiredCerts: !_isShortTerm ? _requiredCertsCtrl.text.trim() : null,
        welfare: !_isShortTerm ? _welfareCtrl.text.trim() : null,
        externalApplyEnabled: isPaid && _externalApplyEnabled,
        externalApplyUrl: externalApplyUrl,
      );

      if (!mounted) return;
      await _clearDraft();
      _submitted = true;
      final jobId = result['jobId'] as int?;
      final postType = passType ?? 'free';
      ClientTrackingService.instance.track(
        'job_post_complete',
        properties: {'type': postType, 'job_id': jobId},
      );
      // 위 track()은 우리 DB에만 쌓여서 구글이 못 본다. 구글애즈 앱 캠페인이
      // '설치'가 아니라 '공고 등록'을 최적화하려면 Firebase로도 나가야 한다.
      // (이게 없어서 11개월간 인앱 액션 0 → 설치만 최적화 → 구직자를 샀다)
      FirebaseAnalytics.instance.logEvent(
        name: 'job_post_complete',
        parameters: {'type': postType, 'job_id': jobId ?? 0},
      );
      final isUrgent = passType == 'urgent';
      final isDelayed = !isPaid && result['status'] == 'reserved';
      final eta = DateTime.now().add(const Duration(hours: 12));
      final etaStr =
          '${eta.hour.toString().padLeft(2, '0')}:${eta.minute.toString().padLeft(2, '0')}';
      await showModalBottomSheet(
        context: context,
        isDismissible: false,
        enableDrag: false,
        useSafeArea: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        backgroundColor: Colors.white,
        builder:
            (sheetCtx) => Padding(
              padding: EdgeInsets.fromLTRB(
                28,
                32,
                28,
                MediaQuery.of(sheetCtx).padding.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color:
                          isUrgent
                              ? const Color(0xFFFFEBEB)
                              : isDelayed
                              ? const Color(0xFFFFF3E0)
                              : const Color(0xFFEEF5FF),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      isUrgent
                          ? Icons.emergency_rounded
                          : isDelayed
                          ? Icons.schedule_rounded
                          : Icons.check_circle_rounded,
                      size: 38,
                      color:
                          isUrgent
                              ? const Color(0xFFEF4444)
                              : isDelayed
                              ? const Color(0xFFFF9500)
                              : _blue,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    isUrgent ? '긴급 공고 등록 완료!' : '공고 등록 완료!',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: _text,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isUrgent
                        ? '공고가 즉시 노출됩니다.\n지금 바로 긴급 호출을 발송해보세요!'
                        : isDelayed
                        ? '오늘 $etaStr 이후 구직자에게 노출됩니다.\n그 전까지 언제든 수정할 수 있어요.'
                        : '지금 바로 구직자에게 노출됩니다.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: _sub,
                      height: 1.55,
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        widget.onSubmitComplete?.call();
                        Navigator.pop(sheetCtx);
                        if (isUrgent && jobId != null) {
                          Navigator.pushNamedAndRemoveUntil(
                            context,
                            '/client_main',
                            (_) => false,
                          );
                          Navigator.pushNamed(
                            context,
                            '/nearby-workers',
                            arguments: {
                              'jobId': jobId,
                              'clientId': clientId,
                              'jobTitle': _title.trim(),
                            },
                          );
                        } else if (userType == 'client') {
                          Navigator.pushNamedAndRemoveUntil(
                            context,
                            '/client_main',
                            (_) => false,
                          );
                        } else {
                          Navigator.pushNamedAndRemoveUntil(
                            context,
                            '/home',
                            (_) => false,
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            isUrgent ? const Color(0xFFEF4444) : _blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        isUrgent ? '⚡ 긴급 호출 발송하기' : '내 공고 보러가기',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
      );
    } catch (e) {
      _showError('서버 오류: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _onPreview() {
    final susp =
        _suspension ??
        const SuspensionState(
          suspendedType: null,
          suspendedUntil: null,
          suspendedReason: null,
        );
    if (!guardSuspended(context, susp)) return;
    ClientTrackingService.instance.track('job_post_preview_view');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => JobPreviewDetailScreen(
              title: _title,
              category: _category,
              location: _location,
              lat: _lat,
              lng: _lng,
              companyName: companyName,
              managerName: managerName,
              startDate:
                  _isShortTerm
                      ? (_startDate != null ? _dateToYmd(_startDate!) : null)
                      : null,
              endDate:
                  _isShortTerm
                      ? (_endDate != null ? _dateToYmd(_endDate!) : null)
                      : null,
              weekdays: _isShortTerm ? [] : _weekdays,
              workingTime:
                  (_startTime != null && _endTime != null)
                      ? '${_startTime!.format(context)} ~ ${_endTime!.format(context)}'
                      : '시간 미정',
              payType: _payType,
              pay: isNegotiablePayType(_payType) ? 0 : _pay,
              description: _description,
              images: _images,
              onSubmit: () {
                Navigator.pop(context);
                _showPublishSheet();
              },
            ),
      ),
    );
  }

  Future<void> _showPublishSheet() async {
    ClientTrackingService.instance.track('job_post_publish_options_view');
    await _refreshPaidPassCount();

    // 근무지 위치 기반 오늘 가능 구직자 수
    int availableCount = 0;
    if (_lat != 0 && _lng != 0) {
      availableCount = await JobService.fetchAvailableWorkersCount(
        lat: _lat,
        lng: _lng,
      ).catchError((_) => 0);
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: Colors.white,
      builder:
          (ctx) => _PublishSheet(
            paidPassCount: _paidPassCount,
            urgentPassCount: _urgentPassCount,
            passCountLoading: _passCountLoading,
            passCountFailed: _passCountFailed,
            availableWorkersCount: availableCount,
            externalApplyEnabled: _externalApplyEnabled,
            onRetryPassCount: () {
              Navigator.pop(ctx);
              _showPublishSheet();
            },
            onFreeSubmit: () {
              Navigator.pop(ctx);
              if (_externalApplyEnabled) {
                _showError('외부 신청 연결은 즉시게시·긴급호출 공고에서만 사용할 수 있어요.');
                return;
              }
              _submit(isPaid: false);
            },
            onPaidSubmit: (dt) {
              Navigator.pop(ctx);
              publishAt = dt;
              ClientTrackingService.instance.track(
                'job_post_paid_publish_start',
                properties: {'pass_type': 'instant'},
              );
              _submit(isPaid: true, passType: 'instant');
            },
            onUrgentSubmit: () {
              Navigator.pop(ctx);
              ClientTrackingService.instance.track(
                'job_post_paid_publish_start',
                properties: {'pass_type': 'urgent'},
              );
              _submit(isPaid: true, passType: 'urgent');
            },
            onBuyPass: () async {
              Navigator.pop(ctx);
              ClientTrackingService.instance.track('job_post_payment_start');
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PurchasePassScreen(fromPostJob: true),
                ),
              );
              await _refreshPaidPassCount();
              if (result is Map && result['success'] == true && mounted) {
                ClientTrackingService.instance.track(
                  'job_post_payment_success',
                );
                _showPublishSheet();
              }
            },
          ),
    );
  }

  void _fillFromJob(Map<String, dynamic> job) {
    setState(() {
      _title = job['title'] ?? '';
      _titleCtrl.text = _title;
      _category = job['category'] ?? '';
      _majorCat = _majorOf(_category);
      _location = job['location'] ?? '';
      _locationCity = job['location_city'] ?? '';
      _lat = (job['lat'] ?? 0.0) as double;
      _lng = (job['lng'] ?? 0.0) as double;
      _pay = int.tryParse(job['pay']?.toString() ?? '') ?? 0;
      _payType = job['pay_type'] ?? '일급';
      _payCtrl.text = _pay > 0 ? NumberFormat('#,###').format(_pay) : '';
      _description = job['description'] ?? '';
      _descCtrl.text = _description;
      // 날짜 파싱 시 toLocal() 명시
      _startDate =
          job['start_date'] != null
              ? DateTime.tryParse(job['start_date'])?.toLocal()
              : null;
      final parsedEnd =
          job['end_date'] != null
              ? DateTime.tryParse(job['end_date'])?.toLocal()
              : null;
      _endDate = parsedEnd ?? _startDate;
      _startTime = _parseTime(job['start_time']);
      _endTime = _parseTime(job['end_time']);
      _weekdays =
          job['weekdays'] != null ? (job['weekdays'] as String).split(',') : [];
      _isSameDayPay = job['is_same_day_pay'] == 1;
      final raw = job['image_urls'];
      _imageUrls = raw is List ? List<String>.from(raw) : [];
    });
    _scheduleDraftSave();
  }

  String? _normalizedExternalApplyUrl() {
    final raw = _externalApplyUrlCtrl.text.trim();
    if (raw.isEmpty) return null;
    final withScheme =
        raw.startsWith(RegExp(r'https?://')) ? raw : 'https://$raw';
    final uri = Uri.tryParse(withScheme);
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (uri.host.trim().isEmpty) return null;
    return uri.toString();
  }

  void _scheduleDraftSave() {
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(milliseconds: 450), _saveDraft);
  }

  Future<void> _saveDraft() async {
    if (widget.isRepost || widget.existingJob != null) return;
    final hasDraft =
        _title.trim().isNotEmpty ||
        _category.isNotEmpty ||
        _location.isNotEmpty ||
        _pay > 0 ||
        _description.trim().isNotEmpty ||
        _externalApplyEnabled ||
        _externalApplyUrlCtrl.text.trim().isNotEmpty;
    final prefs = await SharedPreferences.getInstance();
    if (!hasDraft) {
      await prefs.remove(_draftKey);
      return;
    }
    await prefs.setString(
      _draftKey,
      jsonEncode({
        'q': _q,
        'title': _title,
        'category': _category,
        'majorCat': _majorCat,
        'location': _location,
        'locationCity': _locationCity,
        'lat': _lat,
        'lng': _lng,
        'isShortTerm': _isShortTerm,
        'startDate': _startDate?.toIso8601String(),
        'endDate': _endDate?.toIso8601String(),
        'weekdays': _weekdays,
        'longTermMode': _longTermMode,
        'negotiationText': _negotiationText,
        'startTime': _fmt24(_startTime),
        'endTime': _fmt24(_endTime),
        'payType': _payType,
        'pay': _pay,
        'isSameDayPay': _isSameDayPay,
        'description': _description,
        'externalApplyEnabled': _externalApplyEnabled,
        'externalApplyUrl': _externalApplyUrlCtrl.text.trim(),
      }),
    );
  }

  Future<void> _restoreDraft() async {
    if (widget.isRepost || widget.existingJob != null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_draftKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final d = jsonDecode(raw) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _q = (d['q'] as int? ?? 0).clamp(0, _totalQ - 1);
        _title = d['title']?.toString() ?? '';
        _titleCtrl.text = _title;
        _category = d['category']?.toString() ?? '';
        _majorCat = d['majorCat']?.toString() ?? _majorOf(_category);
        _location = d['location']?.toString() ?? '';
        _locationCity = d['locationCity']?.toString() ?? '';
        _lat = (d['lat'] as num?)?.toDouble() ?? 0;
        _lng = (d['lng'] as num?)?.toDouble() ?? 0;
        _isShortTerm = d['isShortTerm'] as bool? ?? true;
        _startDate = DateTime.tryParse(d['startDate']?.toString() ?? '');
        _endDate = DateTime.tryParse(d['endDate']?.toString() ?? '');
        _weekdays = List<String>.from(d['weekdays'] as List? ?? const []);
        _longTermMode = d['longTermMode']?.toString() ?? '요일 지정';
        _negotiationText = d['negotiationText']?.toString() ?? '';
        _negoCtrl.text = _negotiationText;
        _startTime = _parseTime(d['startTime']?.toString());
        _endTime = _parseTime(d['endTime']?.toString());
        _payType = d['payType']?.toString() ?? '시급';
        _pay = d['pay'] as int? ?? 0;
        _payCtrl.text = _pay > 0 ? NumberFormat('#,###').format(_pay) : '';
        _isSameDayPay = d['isSameDayPay'] as bool? ?? false;
        _description = d['description']?.toString() ?? '';
        _descCtrl.text = _description;
        _externalApplyEnabled = d['externalApplyEnabled'] as bool? ?? false;
        _externalApplyUrlCtrl.text = d['externalApplyUrl']?.toString() ?? '';
      });
      _validatePay();
    } catch (_) {
      await prefs.remove(_draftKey);
    }
  }

  Future<void> _maybeOfferDraftRestore() async {
    if (widget.isRepost || widget.existingJob != null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_draftKey);
    if (raw == null || raw.isEmpty || !mounted) return;

    final shouldRestore = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isDismissible: false,
      enableDrag: false,
      builder:
          (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '✏️ 작성 중인 공고가 있어요',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '이전에 입력하던 내용을 이어서 작성할까요?',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('새로 시작'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            '이어서 작성',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
    );

    if (shouldRestore == true) {
      await _restoreDraft();
    } else {
      await _clearDraft();
    }
  }

  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey);
  }

  // ════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _prevQ,
                    icon: Icon(
                      _q == 0 ? Icons.close : Icons.arrow_back_ios_new_rounded,
                      size: 20,
                      color: _text,
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: (_q + 1) / _totalQ,
                  minHeight: 4,
                  backgroundColor: _border,
                  valueColor: const AlwaysStoppedAnimation<Color>(_blue),
                ),
              ),
            ),
            FadeTransition(
              opacity: _fadeAnim,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _qTitles[_q],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: _text,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${_q + 1}/$_totalQ',
                          style: const TextStyle(
                            fontSize: 12,
                            color: _label,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _qSubs[_q],
                      style: const TextStyle(fontSize: 13, color: _label),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SingleChildScrollView(
                  controller: _contentScrollCtrl,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  child: _buildQ(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQ() {
    switch (_q) {
      case 0:
        return _buildQ0();
      case 1:
        return _buildQ1();
      case 2:
        return _buildQ2();
      case 3:
        return _buildQ3();
      case 4:
        return _buildQ5();
      case 5:
        return _buildQ6();
      default:
        return const SizedBox();
    }
  }

  // Q0: 제목
  Widget _buildQ0() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        button: true,
        label: '이전 공고 불러오기',
        child: GestureDetector(
        onTap: () async {
          final job = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SelectPreviousJobScreen()),
          );
          if (job != null) _fillFromJob(job);
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _border),
          ),
          child: const Row(
            children: [
              Icon(Icons.history_rounded, size: 16, color: _label),
              SizedBox(width: 8),
              Text(
                '이전 공고 불러오기',
                style: TextStyle(
                  fontSize: 13,
                  color: _sub,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Spacer(),
              Icon(Icons.chevron_right_rounded, size: 16, color: _label),
            ],
          ),
        ),
        ),
      ),
      TextField(
        controller: _titleCtrl,
        autofocus: false,
        textInputAction: TextInputAction.done,
        onChanged: (v) {
          setState(() => _title = v.trim());
          _scheduleDraftSave();
        },
        onSubmitted: (_) {
          if (_canNext) _nextQ();
        },
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: _text,
        ),
        decoration: InputDecoration(
          hintText: '예) 물류창고 일일 상·하차 알바',
          hintStyle: const TextStyle(
            fontSize: 16,
            color: _label,
            fontWeight: FontWeight.w400,
          ),
          filled: true,
          fillColor: _bg,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 18,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _blue, width: 1.5),
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      const SizedBox(height: 24),
      if (_title.isNotEmpty) _NextBtn(onTap: _nextQ),
    ],
  );

  // Q1: 업종
  Widget _buildQ1() {
    String? majorOf(String val) {
      for (final c in _allCats) {
        if (c.name == val || c.sub.contains(val)) return c.name;
      }
      return null;
    }

    final selectedMajor = majorOf(_category);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.05,
          children:
              _allCats.map((cat) {
                final isSel = selectedMajor == cat.name;
                final isOpen = _majorCat == cat.name;
                return Semantics(
                  button: true,
                  selected: isSel,
                  label:
                      isSel && _category != cat.name
                          ? '${cat.name}, $_category 선택됨'
                          : cat.name,
                  child: GestureDetector(
                  onTap: () {
                    final opening = !isOpen;
                    setState(() => _majorCat = isOpen ? '' : cat.name);
                    if (opening) {
                      Future.delayed(const Duration(milliseconds: 280), () {
                        if (_contentScrollCtrl.hasClients) {
                          _contentScrollCtrl.animateTo(
                            _contentScrollCtrl.position.maxScrollExtent,
                            duration: const Duration(milliseconds: 320),
                            curve: Curves.easeOutCubic,
                          );
                        }
                      });
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      color:
                          isSel
                              ? _blue
                              : isOpen
                              ? const Color(0xFFEEF5FF)
                              : const Color(0xFFF5F6F8),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color:
                            isSel
                                ? _blue
                                : isOpen
                                ? _blue.withOpacity(0.4)
                                : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color:
                                isSel
                                    ? Colors.white.withOpacity(0.2)
                                    : isOpen
                                    ? _blue.withOpacity(0.08)
                                    : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Icon(
                              cat.icon,
                              size: 18,
                              color: isSel ? Colors.white : _blue,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          cat.name,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight:
                                isSel ? FontWeight.w700 : FontWeight.w500,
                            color:
                                isSel
                                    ? Colors.white
                                    : isOpen
                                    ? _blue
                                    : _sub,
                            height: 1.3,
                          ),
                        ),
                        if (isSel &&
                            _category.isNotEmpty &&
                            _category != cat.name) ...[
                          const SizedBox(height: 2),
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              _category,
                              // 9px → 11px (최소 가독 크기)
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  ),
                );
              }).toList(),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child:
              _majorCat.isEmpty
                  ? const SizedBox.shrink()
                  : Builder(
                    builder: (_) {
                      final cat = _allCats.firstWhere(
                        (c) => c.name == _majorCat,
                      );
                      return Container(
                        margin: const EdgeInsets.only(top: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F5FF),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _blue.withOpacity(0.12),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(cat.icon, size: 14, color: _blue),
                                const SizedBox(width: 5),
                                Text(
                                  cat.name,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: _blue,
                                  ),
                                ),
                                const Spacer(),
                                Semantics(
                                  button: true,
                                  label: '$_majorCat 세부 직종 목록 닫기',
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => setState(() => _majorCat = ''),
                                    child: const SizedBox(
                                      width: 44,
                                      height: 44,
                                      child: Center(
                                        child: Icon(
                                          Icons.close_rounded,
                                          size: 16,
                                          color: _label,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 7,
                              runSpacing: 7,
                              children:
                                  cat.sub.map((s) {
                                    final sel = _category == s;
                                    return Semantics(
                                      button: true,
                                      selected: sel,
                                      label: s,
                                      child: GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _category = s;
                                          _majorCat = '';
                                        });
                                        Future.delayed(
                                          const Duration(milliseconds: 200),
                                          _nextQ,
                                        );
                                      },
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 130,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: sel ? _blue : Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            99,
                                          ),
                                          border: Border.all(
                                            color:
                                                sel
                                                    ? _blue
                                                    : const Color(0xFFDDE3EC),
                                            width: sel ? 0 : 1,
                                          ),
                                          boxShadow:
                                              sel
                                                  ? []
                                                  : [
                                                    BoxShadow(
                                                      color: Colors.black
                                                          .withOpacity(0.04),
                                                      blurRadius: 4,
                                                      offset: const Offset(
                                                        0,
                                                        1,
                                                      ),
                                                    ),
                                                  ],
                                        ),
                                        child: Text(
                                          s,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight:
                                                sel
                                                    ? FontWeight.w700
                                                    : FontWeight.w500,
                                            color: sel ? Colors.white : _sub,
                                          ),
                                        ),
                                      ),
                                      ),
                                    );
                                  }).toList(),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
        ),
        const SizedBox(height: 16),
        if (_category.isNotEmpty) _NextBtn(onTap: _nextQ),
      ],
    );
  }

  // 현재 위치(GPS)로 근무지 자동 채우기 — 주소 검색 마찰 제거
  Future<void> _useCurrentLocation() async {
    if (_gpsLoading) return;
    setState(() => _gpsLoading = true);
    try {
      final pos = await getCurrentLocation();
      if (pos == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('위치 권한을 켜주세요. 허용하면 현재 위치로 바로 채워져요.')),
          );
        }
        return;
      }
      String address = '';
      try {
        final marks = await placemarkFromCoordinates(
          pos.latitude,
          pos.longitude,
        );
        if (marks.isNotEmpty) address = _addressFromPlacemark(marks.first);
      } catch (_) {}
      if (address.isEmpty) address = '내 위치';
      if (!mounted) return;
      setState(() {
        _location = address;
        _locationCity = _extractCity(address);
        _lat = pos.latitude;
        _lng = pos.longitude;
      });
    } finally {
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

  // 역지오코딩 Placemark → 한국 주소 문자열 (중복 제거)
  String _addressFromPlacemark(Placemark p) {
    final parts = <String>[
      p.administrativeArea ?? '',
      p.subAdministrativeArea ?? '',
      p.locality ?? '',
      p.subLocality ?? '',
      p.thoroughfare ?? '',
      p.subThoroughfare ?? '',
    ];
    final seen = <String>{};
    final out = <String>[];
    for (final raw in parts) {
      final s = raw.trim();
      if (s.isEmpty || s == 'null' || seen.contains(s)) continue;
      seen.add(s);
      out.add(s);
    }
    return out.join(' ');
  }

  Widget _gpsButton() => SizedBox(
    width: double.infinity,
    child: OutlinedButton.icon(
      onPressed: _gpsLoading ? null : _useCurrentLocation,
      icon:
          _gpsLoading
              ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: _blue),
              )
              : const Icon(Icons.my_location_rounded, size: 18, color: _blue),
      label: Text(
        _gpsLoading ? '위치 찾는 중…' : '현재 위치로 설정',
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: _blue,
        ),
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        side: const BorderSide(color: _blue),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );

  // 단기 근무 날짜 빠른 선택 (오늘/내일/모레) — 급구 페르소나 정조준
  Widget _quickDateChips(DateTime today) {
    Widget chip(String label, DateTime date) {
      final sel = isSameDay(_startDate, date);
      return Expanded(
        child: Semantics(
          button: true,
          selected: sel,
          label: '$label 근무',
          child: GestureDetector(
            onTap:
                () => setState(() {
                  _startDate = date;
                  _endDate = date;
                }),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: sel ? _blue : _bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: sel ? _blue : _border),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: sel ? Colors.white : _text,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip('오늘', today),
        const SizedBox(width: 8),
        chip('내일', today.add(const Duration(days: 1))),
        const SizedBox(width: 8),
        chip('모레', today.add(const Duration(days: 2))),
      ],
    );
  }

  // Q2: 근무지
  Widget _buildQ2() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        button: true,
        label:
            _location.isNotEmpty
                ? '근무지 주소 $_location, 변경하려면 두 번 탭'
                : '근무지 주소 검색',
        child: GestureDetector(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (_) => KpostalView(
                    useLocalServer: false,
                    callback: (result) async {
                      setState(() {
                        _location = result.address;
                        _locationCity = _extractCity(result.address);
                      });
                      try {
                        final locs = await locationFromAddress(result.address);
                        if (locs.isNotEmpty) {
                          setState(() {
                            _lat = locs.first.latitude;
                            _lng = locs.first.longitude;
                          });
                        }
                      } catch (_) {}
                    },
                  ),
            ),
          );
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _location.isNotEmpty ? const Color(0xFFEEF5FF) : _bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _location.isNotEmpty ? _blue : _border),
          ),
          child: Row(
            children: [
              Icon(
                Icons.place_outlined,
                size: 22,
                color: _location.isNotEmpty ? _blue : _label,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '근무지 주소',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _location.isNotEmpty ? _blue : _label,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _location.isNotEmpty ? _location : '주소를 검색해주세요',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _location.isNotEmpty ? _text : _label,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: _location.isNotEmpty ? _blue : _label,
              ),
            ],
          ),
        ),
        ),
      ),
      const SizedBox(height: 10),
      _gpsButton(),
      const SizedBox(height: 24),
      if (_location.isNotEmpty) _NextBtn(onTap: _nextQ),
    ],
  );

  // Q3: 날짜 + 시간
  Widget _buildQ3() {
    final df = DateFormat('M월 d일 (E)', 'ko_KR');
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    String fmtTime(TimeOfDay? t) {
      if (t == null) return '';
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _ToggleBtn(
              '단기',
              _isShortTerm,
              () => setState(() {
                _isShortTerm = true;
                if (_payType == '월급') _payType = '시급';
              }),
            ),
            const SizedBox(width: 10),
            _ToggleBtn(
              '장기 (1개월+)',
              !_isShortTerm,
              () => setState(() {
                _isShortTerm = false;
                _startDate = null;
                _endDate = null;
                _payType = '월급';
              }),
            ),
          ],
        ),
        const SizedBox(height: 20),

        if (_isShortTerm) ...[
          _quickDateChips(today),
          const SizedBox(height: 12),
          Semantics(
            button: true,
            label:
                _startDate != null
                    ? '근무 날짜 ${df.format(_startDate!)}, 변경하려면 두 번 탭'
                    : '근무 날짜 선택',
            child: GestureDetector(
            onTap: () async {
              DateTime focused = _startDate ?? today;
              DateTime? selected = _startDate;
              final picked = await showModalBottomSheet<DateTime>(
                context: context,
                backgroundColor: Colors.white,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                isScrollControlled: true,
                builder: (ctx) {
                  return StatefulBuilder(
                    builder:
                        (ctx, set) => SafeArea(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 12),
                              Container(
                                width: 40,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.black12,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                '근무 날짜 선택',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: _text,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TableCalendar(
                                locale: 'ko_KR',
                                focusedDay: focused,
                                firstDay: today,
                                lastDay: today.add(const Duration(days: 365)),
                                selectedDayPredicate:
                                    (d) => isSameDay(d, selected),
                                onDaySelected:
                                    (d, f) => set(() {
                                      selected = DateTime(
                                        d.year,
                                        d.month,
                                        d.day,
                                      );
                                      focused = d;
                                    }),
                                onPageChanged: (f) => set(() => focused = f),
                                calendarStyle: const CalendarStyle(
                                  todayDecoration: BoxDecoration(
                                    color: Color(0xFFCCDEFF),
                                    shape: BoxShape.circle,
                                  ),
                                  todayTextStyle: TextStyle(
                                    color: _blue,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  selectedDecoration: BoxDecoration(
                                    color: _blue,
                                    shape: BoxShape.circle,
                                  ),
                                  selectedTextStyle: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  weekendTextStyle: TextStyle(
                                    color: Color(0xFFEF4444),
                                  ),
                                ),
                                headerStyle: const HeaderStyle(
                                  formatButtonVisible: false,
                                  titleCentered: true,
                                  titleTextStyle: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: _text,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  8,
                                  16,
                                  16,
                                ),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed:
                                        selected == null
                                            ? null
                                            : () =>
                                                Navigator.pop(ctx, selected),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _blue,
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor: _border,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text(
                                      '선택 완료',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                  );
                },
              );
              if (picked != null) {
                setState(() {
                  _startDate = picked;
                  _endDate = picked;
                });
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              decoration: BoxDecoration(
                color: _startDate != null ? const Color(0xFFEEF5FF) : _bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _startDate != null ? _blue : _border),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 18,
                    color: _startDate != null ? _blue : _label,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '근무 날짜',
                          style: TextStyle(
                            fontSize: 11,
                            color: _text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _startDate != null
                              ? df.format(_startDate!)
                              : '날짜를 선택해주세요',
                          style: TextStyle(
                            fontSize: 15,
                            color: _startDate != null ? _text : _label,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: _startDate != null ? _blue : _label,
                  ),
                ],
              ),
            ),
          ),
          ),
        ] else ...[
          Row(
            children: [
              _SmallToggle(
                '요일 지정',
                _longTermMode == '요일 지정',
                () => setState(() {
                  _longTermMode = '요일 지정';
                  _negotiationText = '';
                }),
              ),
              const SizedBox(width: 10),
              _SmallToggle(
                '요일 협의',
                _longTermMode == '요일 협의',
                () => setState(() {
                  _longTermMode = '요일 협의';
                  _weekdays.clear();
                }),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_longTermMode == '요일 지정')
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  days.map((d) {
                    final sel = _weekdays.contains(d);
                    return Semantics(
                      button: true,
                      selected: sel,
                      label: '$d요일',
                      child: GestureDetector(
                      onTap:
                          () => setState(() {
                            sel ? _weekdays.remove(d) : _weekdays.add(d);
                          }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: sel ? _blue : _bg,
                          border: Border.all(color: sel ? _blue : _border),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            d,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: sel ? Colors.white : _sub,
                            ),
                          ),
                        ),
                      ),
                      ),
                    );
                  }).toList(),
            )
          else ...[
            TextField(
              controller: _negoCtrl,
              onChanged: (v) => setState(() => _negotiationText = v),
              style: const TextStyle(fontSize: 15, color: _text),
              decoration: InputDecoration(
                hintText: '예) 주 3회, 주중 오후 가능',
                hintStyle: const TextStyle(fontSize: 14, color: _label),
                filled: true,
                fillColor: _bg,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _blue, width: 1.5),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '비워두면 요일 협의로 등록돼요.',
              style: TextStyle(fontSize: 11, color: _label),
            ),
          ],
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _TimeInputCard(
                label: '시작 시간',
                value: fmtTime(_startTime),
                onTap: () {
                  _showTimeSheet();
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _TimeInputCard(
                label: '종료 시간',
                value: fmtTime(_endTime),
                onTap: () {
                  _showTimeSheet();
                },
              ),
            ),
          ],
        ),
        if (_startTime != null && _endTime != null) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: _blue.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '근무시간 ${fmtTime(_startTime)} ~ ${fmtTime(_endTime)} · 총 ${_workMins() ~/ 60}시간${_workMins() % 60 == 0 ? '' : ' ${_workMins() % 60}분'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: _blue,
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        if (_canNext) _NextBtn(onTap: _nextQ),
      ],
    );
  }

  void _showTimeSheet() {
    TimeOfDay align10(TimeOfDay t) {
      int m = ((t.minute + 5) ~/ 10) * 10;
      int h = t.hour;
      if (m == 60) {
        m = 0;
        h = (h + 1) % 24;
      }
      return TimeOfDay(hour: h, minute: m);
    }

    int toMin(TimeOfDay t) => t.hour * 60 + t.minute;
    int durMin(TimeOfDay s, TimeOfDay e) {
      int d = toMin(e) - toMin(s);
      if (d <= 0) d += 1440;
      return d;
    }

    String fmt12(TimeOfDay t) {
      final p = t.period == DayPeriod.am ? '오전' : '오후';
      int h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
      return '$p $h:${t.minute.toString().padLeft(2, '0')}';
    }

    TimeOfDay s = align10(_startTime ?? TimeOfDay.now());
    TimeOfDay e = align10(_endTime ?? s.replacing(hour: (s.hour + 1) % 24));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (ctx) => StatefulBuilder(
            builder: (ctx, set) {
              return FractionallySizedBox(
                heightFactor: 0.85,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Column(
                        children: [
                          const Text(
                            '근무 시간 설정',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F5FF),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${fmt12(s)} ~ ${toMin(e) <= toMin(s) ? "익일 " : ""}${fmt12(e)}  '
                              '(${(() {
                                int d = durMin(s, e);
                                final h = d ~/ 60;
                                final m = d % 60;
                                return h == 0
                                    ? '$m분'
                                    : m == 0
                                    ? '$h시간'
                                    : '$h시간 $m분';
                              })()})',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                        child: LayoutBuilder(
                          builder: (ctx, box) {
                            double each = ((box.maxHeight - 80) / 2).clamp(
                              120,
                              double.infinity,
                            );
                            return Column(
                              children: [
                                const Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    '시작 시간',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: each,
                                  child: TimePickerSpinner(
                                    key: const ValueKey('s'),
                                    is24HourMode: false,
                                    minutesInterval: 10,
                                    normalTextStyle: const TextStyle(
                                      fontSize: 16,
                                      color: Color(0xFF9CA3AF),
                                    ),
                                    highlightedTextStyle: const TextStyle(
                                      fontSize: 18,
                                      color: _blue,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    spacing: 40,
                                    itemHeight: 40,
                                    isForce2Digits: true,
                                    time: DateTime(
                                      2000,
                                      1,
                                      1,
                                      s.hour,
                                      s.minute,
                                    ),
                                    onTimeChange:
                                        (dt) => set(
                                          () =>
                                              s = align10(
                                                TimeOfDay.fromDateTime(dt),
                                              ),
                                        ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                const Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    '종료 시간',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: each,
                                  child: TimePickerSpinner(
                                    key: const ValueKey('e'),
                                    is24HourMode: false,
                                    minutesInterval: 10,
                                    normalTextStyle: const TextStyle(
                                      fontSize: 16,
                                      color: Color(0xFF9CA3AF),
                                    ),
                                    highlightedTextStyle: const TextStyle(
                                      fontSize: 18,
                                      color: _blue,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    spacing: 40,
                                    itemHeight: 40,
                                    isForce2Digits: true,
                                    time: DateTime(
                                      2000,
                                      1,
                                      1,
                                      e.hour,
                                      e.minute,
                                    ),
                                    onTimeChange:
                                        (dt) => set(
                                          () =>
                                              e = align10(
                                                TimeOfDay.fromDateTime(dt),
                                              ),
                                        ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                    SafeArea(
                      top: false,
                      minimum: EdgeInsets.fromLTRB(
                        20,
                        8,
                        20,
                        MediaQuery.of(ctx).viewInsets.bottom > 0
                            ? MediaQuery.of(ctx).viewInsets.bottom
                            : MediaQuery.of(ctx).viewPadding.bottom + 8,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            if (toMin(s) == toMin(e)) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text('시작과 종료 시간이 같습니다'),
                                ),
                              );
                              return;
                            }
                            setState(() {
                              _startTime = s;
                              _endTime = e;
                            });
                            _validatePay();
                            Navigator.pop(ctx);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            '확인',
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
          ),
    );
  }

  // Q5: 급여
  Widget _buildQ5() {
    final fmt = NumberFormat('#,###');
    final payTypes =
        _isShortTerm
            ? ['시급', '일급', '주급', '협의']
            : ['시급', '월급', '일급', '주급', '협의'];
    final isNegotiable = isNegotiablePayType(_payType);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 급여 유형 탭
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children:
              payTypes.map((t) {
                final sel = _payType == t;
                return Semantics(
                  button: true,
                  selected: sel,
                  label: t,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _payType = t;
                        _pay = 0;
                        _payCtrl.clear();
                      });
                      _validatePay();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: sel ? _blue : _bg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: sel ? _blue : _border),
                      ),
                      child: Text(
                        t,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: sel ? Colors.white : _sub,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
        ),
        const SizedBox(height: 12),

        // ── 직접 입력 필드
        if (isNegotiable)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withOpacity(0.18)),
            ),
            child: const Text(
              '금액은 공고에 급여 협의로 표시됩니다. 상세 정산 방식은 본문에 적어주세요.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          )
        else
          TextField(
            controller: _payCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              const _CommaNumberInputFormatter(),
            ],
            decoration: InputDecoration(
              hintText:
                  _payType == '월급'
                      ? '예) 2,500,000'
                      : _payType == '주급'
                      ? '예) 412,800'
                      : _payType == '시급'
                      ? '예) 10,320'
                      : '예) 100,000',
              suffixText: _payType == '시급' ? '원/시간' : '원',
              helperText:
                  _payType == '월급'
                      ? '최저 2,156,880원 이상 (209h 기준)'
                      : _payType == '시급'
                      ? '2026년 기준 최저시급 ${fmt.format(minWagePerHour)}원'
                      : '최저 ${fmt.format(minWagePerHour)}원/시간 이상',
              filled: true,
              fillColor: _bg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
            onChanged: (v) {
              final n = v.replaceAll(RegExp(r'[^0-9]'), '');
              setState(() => _pay = n.isEmpty ? 0 : int.parse(n));
              _validatePay();
            },
          ),
        if (_payWarning != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, size: 16, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _payWarning!,
                    style: const TextStyle(fontSize: 12, color: Colors.red),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (_canNext) _NextBtn(onTap: _nextQ),

        // ── 임금 AI 리포트 버튼
        if (_category.isNotEmpty) ...[
          const SizedBox(height: 10),
          Semantics(
            button: true,
            label:
                _subscriptionPlan != null
                    ? '이 업종 임금 AI 리포트 보기'
                    : '이 업종 임금 AI 리포트 보기, 구독자 전용',
            child: GestureDetector(
            onTap: () {
              if (_subscriptionPlan != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => WageReportScreen(
                          category: _category,
                          locationCity:
                              _locationCity.isNotEmpty ? _locationCity : null,
                          payType: _payType,
                          currentPay: _pay > 0 ? _pay : null,
                          hours: (_workMins() / 60).round().clamp(1, 24),
                        ),
                  ),
                );
              } else {
                showModalBottomSheet(
                  context: context,
                  backgroundColor: Colors.transparent,
                  builder:
                      (_) => Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                        ),
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
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
                            const Icon(
                              Icons.analytics_rounded,
                              color: Color(0xFF3B8AFF),
                              size: 32,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              '임금 AI 리포트는 구독자 전용이에요',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: Color(0xFF191F28),
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              '업종·지역·경쟁 공고 시급을 분석해\n적정 급여를 AI가 추천해 드려요.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF6B7280),
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  Navigator.pushNamed(
                                    context,
                                    '/subscription/manage',
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF3B8AFF),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  '구독 시작하기',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text(
                                  '닫기',
                                  style: TextStyle(
                                    color: Color(0xFF6B7280),
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
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color:
                    _subscriptionPlan != null
                        ? const Color(0xFFEFF6FF)
                        : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color:
                      _subscriptionPlan != null
                          ? const Color(0xFF93C5FD)
                          : const Color(0xFFD1D5DB),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _subscriptionPlan != null
                        ? Icons.analytics_rounded
                        : Icons.lock_outline_rounded,
                    size: 16,
                    color:
                        _subscriptionPlan != null
                            ? const Color(0xFF2563EB)
                            : const Color(0xFF9CA3AF),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '이 업종 임금 AI 리포트 보기',
                    style: TextStyle(
                      fontSize: 12,
                      // #9CA3AF는 이 배경에서 2.5:1 — AA 미달
                      color:
                          _subscriptionPlan != null
                              ? const Color(0xFF2563EB)
                              : AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 14,
                    color:
                        _subscriptionPlan != null
                            ? const Color(0xFF2563EB)
                            : AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          ),
        ],

        // ── 당일지급 토글 (월급 제외)
        if (_pay > 0 &&
            _payWarning == null &&
            _payType != '월급' &&
            !isNegotiablePayType(_payType)) ...[
          const SizedBox(height: 20),
          const Divider(color: _border),
          const SizedBox(height: 16),
          Semantics(
            toggled: _isSameDayPay,
            label: '당일지급, 근무 당일 현금 지급',
            child: GestureDetector(
            onTap: () => setState(() => _isSameDayPay = !_isSameDayPay),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _isSameDayPay ? const Color(0xFFEEF5FF) : _bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _isSameDayPay ? _blue : _border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.payments_rounded, size: 24, color: _blue),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '당일지급',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _text,
                        ),
                      ),
                      Text(
                        '근무 당일 현금 지급',
                        style: TextStyle(fontSize: 12, color: _label),
                      ),
                    ],
                  ),
                  const Spacer(),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isSameDayPay ? _blue : _border,
                    ),
                    child:
                        _isSameDayPay
                            ? const Icon(
                              Icons.check_rounded,
                              size: 14,
                              color: Colors.white,
                            )
                            : null,
                  ),
                ],
              ),
            ),
          ),
          ),
        ],
      ],
    );
  }

  // Q6: 공고 내용
  Widget _buildQ6() {
    final total = _images.length + _imageUrls.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          enabled: !_isAIGenerating,
          label: _isAIGenerating ? '공고문 생성 중' : '공고문 작성 도움 받기',
          child: GestureDetector(
          onTap:
              _isAIGenerating
                  ? null
                  : () async {
                    await _loadAiQuota();
                    // -1=무제한(pro), N>0=잔여, 0=소진
                    if (_aiQuotaRemaining != 0) {
                      _showAIDialog();
                    } else {
                      _showAiPaywall();
                    }
                  },
          child: Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF3182F6), Color(0xFF6C5CE7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child:
                _isAIGenerating
                    ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 10),
                        Text(
                          '공고문을 정리하고 있어요…',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    )
                    : Row(
                      children: [
                        const Icon(
                          Icons.description_outlined,
                          size: 18,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            '공고문 작성 도움',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _description.isNotEmpty ? '다시 생성' : '생성하기',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: _blue,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _aiQuotaRemaining == -1
                                ? '무제한'
                                : _aiQuotaRemaining <= 0
                                ? '이번 주 소진'
                                : '이번 주 $_aiQuotaRemaining회',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
          ),
        ),
        ),
        Container(
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border),
          ),
          child: TextField(
            controller: _descCtrl,
            maxLines: null,
            minLines: 6,
            keyboardType: TextInputType.multiline,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(fontSize: 14, color: _text, height: 1.6),
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(14),
              hintText: '근무 내용, 환경, 혜택 등을 자유롭게 적어주세요',
              hintStyle: const TextStyle(
                fontSize: 13,
                color: _label,
                height: 1.6,
              ),
            ),
            onChanged: (v) {
              setState(() => _description = v);
              _scheduleDraftSave();
            },
          ),
        ),

        // ── 장기 공고 전용 필드 ──────────────────────────
        if (!_isShortTerm) ...[
          const SizedBox(height: 20),
          // 상시모집 토글
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '상시모집',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _sub,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      '종료일 없이 계속 모집합니다',
                      style: TextStyle(fontSize: 11, color: _label),
                    ),
                  ],
                ),
              ),
              Semantics(
                toggled: _isAlwaysOpen,
                label: '상시모집, 종료일 없이 계속 모집',
                child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _isAlwaysOpen = !_isAlwaysOpen),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 46,
                  height: 26,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: _isAlwaysOpen ? _blue : _border,
                  ),
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 200),
                    alignment:
                        _isAlwaysOpen
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.all(3),
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 주 N일 근무
          const SizedBox(height: 16),
          // 자격요건
          const Text(
            '자격요건 (선택)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _sub,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: TextField(
              controller: _requiredCertsCtrl,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _text,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: '예) 건설업 이수증, 현장 경력 1개월',
                hintStyle: TextStyle(fontSize: 13, color: Color(0xFFBCC0C8)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 복리후생
          const Text(
            '복리후생 (선택)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _sub,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: TextField(
              controller: _welfareCtrl,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _text,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: '예) 4대보험, 안전장구류 지급, 식대 별도',
                hintStyle: TextStyle(fontSize: 13, color: Color(0xFFBCC0C8)),
              ),
            ),
          ),
        ],

        const SizedBox(height: 20),
        Row(
          children: [
            const Text(
              '사진',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _sub,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _bg,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: _border),
              ),
              child: const Text(
                '선택',
                style: TextStyle(fontSize: 11, color: _label),
              ),
            ),
            const Spacer(),
            Text(
              '$total / 10',
              style: const TextStyle(fontSize: 12, color: _label),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 80,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              GestureDetector(
                onTap: _pickImages,
                child: Container(
                  width: 80,
                  height: 80,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: _bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _border),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        color: _label,
                        size: 24,
                      ),
                      SizedBox(height: 4),
                      Text('추가', style: TextStyle(fontSize: 11, color: _label)),
                    ],
                  ),
                ),
              ),
              ..._imageUrls.asMap().entries.map(
                (e) => _ImgThumb(
                  Image.network(
                    e.value,
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                  ),
                  () => setState(() {
                    _deleteImageUrls.add(_imageUrls[e.key]);
                    _imageUrls.removeAt(e.key);
                  }),
                ),
              ),
              ..._images.asMap().entries.map(
                (e) => _ImgThumb(
                  Image.file(e.value, width: 80, height: 80, fit: BoxFit.cover),
                  () => setState(() => _images.removeAt(e.key)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _ExternalApplyOption(
          enabled: _externalApplyEnabled,
          controller: _externalApplyUrlCtrl,
          onChanged: (enabled) {
            setState(() => _externalApplyEnabled = enabled);
            _scheduleDraftSave();
          },
          onUrlChanged: (_) => _scheduleDraftSave(),
        ),
        const SizedBox(height: 20),
        _LaborNotice(),
        const SizedBox(height: 24),
        _NextBtn(
          onTap: _nextQ,
          label:
              !_suspLoaded
                  ? '계정 확인 중…'
                  : (_suspension?.isSuspended ?? false)
                  ? '정지된 계정'
                  : '미리보기 후 등록',
        ),
      ],
    );
  }

  void _showAiPaywall() {
    final planLabel =
        _subscriptionPlan == 'lite'
            ? '라이트'
            : _subscriptionPlan == 'standard'
            ? '스탠다드'
            : null;
    final resetInfo =
        planLabel != null
            ? '$planLabel 플랜 · 다음 충전: $_aiQuotaResetText'
            : '다음 충전: $_aiQuotaResetText';
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
                const Icon(
                  Icons.auto_awesome,
                  color: Color(0xFF3B8AFF),
                  size: 32,
                ),
                const SizedBox(height: 12),
                const Text(
                  'AI 공고문 작성 횟수를 모두 사용했어요',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: Color(0xFF191F28),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  resetInfo,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 8),
                // _loadAiQuota() 구현과 일치시킬 것 — 구독=무제한 / 비구독=주 1회.
                // 플랜별 횟수를 여기 적으려면 _loadAiQuota()부터 그렇게 고쳐야 한다.
                const Text(
                  '구독하면 횟수 제한 없이 사용할 수 있어요',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/subscription/manage');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B8AFF),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '구독 플랜 보기',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      '닫기',
                      style: TextStyle(color: Color(0xFF6B7280), fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
    );
  }

  void _showAIDialog() {
    if (_title.trim().isEmpty ||
        _location.isEmpty ||
        (_pay <= 0 && !isNegotiablePayType(_payType))) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('제목, 지역, 급여를 먼저 입력해주세요')));
      return;
    }
    setState(() => _isAIGenerating = true);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder:
          (ctx) => Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.9,
            ),
            child: AIJobDescriptionWidget(
              title: _titleCtrl.text.trim(),
              category: _category,
              location: _location,
              payType: _payType,
              pay: isNegotiablePayType(_payType) ? 0 : _pay,
              workingTime:
                  (_startTime != null && _endTime != null)
                      ? '${_startTime!.format(ctx)} ~ ${_endTime!.format(ctx)}'
                      : null,
              weekdays: _isShortTerm ? null : _weekdays,
              companyName: companyName.isNotEmpty ? companyName : null,
              managerName: managerName.isNotEmpty ? managerName : null,
              managerPhone: managerPhone.isNotEmpty ? managerPhone : null,
              isShortTerm: _isShortTerm,
              onGenerated: (text) async {
                await _consumeAiUsage();
                if (!mounted) return;
                setState(() {
                  _description = text;
                  _descCtrl.text = text;
                  _isAIGenerating = false;
                });
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _subscriptionPlan == null
                          ? '이번 주 작성 도움 기능을 사용했습니다.'
                          : '공고문이 적용되었습니다.',
                    ),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              onClose: () {
                if (mounted) setState(() => _isAIGenerating = false);
                Navigator.pop(ctx);
              },
            ),
          ),
    );
  }
}

// ════════════════════════════════════════════════════════
//  공통 위젯
// ════════════════════════════════════════════════════════
class _NextBtn extends StatelessWidget {
  final VoidCallback onTap;
  final String label;
  const _NextBtn({required this.onTap, this.label = '다음'});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
    ),
  );
}

class _TimeInputCard extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _TimeInputCard({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = value.isNotEmpty;
    return Semantics(
      button: true,
      label: hasValue ? '$label $value, 변경하려면 두 번 탭' : '$label 입력',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: hasValue ? const Color(0xFFEEF5FF) : _bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: hasValue ? _blue : _border),
          ),
          child: Row(
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 18,
                color: hasValue ? _blue : _label,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 11,
                        color: _text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      hasValue ? value : '입력',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        color: hasValue ? _text : _label,
                        fontWeight: FontWeight.w900,
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

class _ToggleBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ToggleBtn(this.label, this.selected, this.onTap);
  @override
  Widget build(BuildContext context) => Expanded(
    child: Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEEF5FF) : _bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _blue : _border,
            width: selected ? 1.5 : 1,
          ),
        ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: selected ? _blue : _sub,
            ),
          ),
        ),
      ),
    ),
  );
}

class _SmallToggle extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SmallToggle(this.label, this.selected, this.onTap);
  @override
  Widget build(BuildContext context) => Expanded(
    child: Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? _blue : _bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? _blue : _border),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : _sub,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _ImgThumb extends StatelessWidget {
  final Widget img;
  final VoidCallback onRemove;
  const _ImgThumb(this.img, this.onRemove);
  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      Container(
        width: 80,
        height: 80,
        margin: const EdgeInsets.only(right: 8),
        child: ClipRRect(borderRadius: BorderRadius.circular(10), child: img),
      ),
      // 탭 영역 44×44 확보. Stack이 clipBehavior:none이라 바깥으로 빼면 히트테스트가
      // 안 먹으므로, 히트박스는 썸네일 안쪽(right:8 = 이미지 우측 끝)에 둔다.
      Positioned(
        right: 8,
        top: 0,
        child: Semantics(
          button: true,
          label: '사진 삭제',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onRemove,
            child: const SizedBox(
              width: 44,
              height: 44,
              child: Align(
                alignment: Alignment.topRight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class _ExternalApplyOption extends StatelessWidget {
  final bool enabled;
  final TextEditingController controller;
  final ValueChanged<bool> onChanged;
  final ValueChanged<String> onUrlChanged;

  const _ExternalApplyOption({
    required this.enabled,
    required this.controller,
    required this.onChanged,
    required this.onUrlChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: enabled ? const Color(0xFFEEF5FF) : _bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: enabled ? _blue : _border),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => onChanged(!enabled),
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                Icon(
                  enabled
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  color: enabled ? _blue : _label,
                  size: 22,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '별도 페이지로 지원을 받을래요',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: _text,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        '유료 공고에서만 가능 · 공고 상세 확인 후 외부 페이지로 이동',
                        style: TextStyle(fontSize: 11, color: _sub),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (enabled) ...[
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              onChanged: onUrlChanged,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _text,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                hintText: 'https://example.com/apply',
                hintStyle: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFFBCC0C8),
                ),
                prefixIcon: const Icon(
                  Icons.link_rounded,
                  size: 18,
                  color: _label,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 13,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _blue, width: 1.4),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LaborNotice extends StatefulWidget {
  @override
  State<_LaborNotice> createState() => _LaborNoticeState();
}

class _LaborNoticeState extends State<_LaborNotice> {
  bool _open = false;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: _bg,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _border),
    ),
    child: Column(
      children: [
        Semantics(
          button: true,
          expanded: _open,
          label: '공고 등록 시 알바 준수사항에 동의합니다, 자세히 보기',
          child: GestureDetector(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.shield_outlined, size: 14, color: _label),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '공고 등록 시 알바 준수사항에 동의합니다',
                    style: TextStyle(fontSize: 12, color: _sub),
                  ),
                ),
                Icon(
                  _open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  color: _label,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
        ),
        if (_open) ...[
          const Divider(height: 1, color: _border),
          ListTile(
            dense: true,
            leading: const Icon(Icons.gavel_rounded, size: 16, color: _blue),
            title: const Text('최저임금법 준수', style: TextStyle(fontSize: 12)),
            subtitle: const Text(
              '2026년 기준 시급 10,320원 이상',
              style: TextStyle(fontSize: 11),
            ),
            trailing: const Icon(Icons.chevron_right, size: 14),
            onTap:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => PolicyDetailScreen(
                          filePath: 'assets/policies/wage_policy.md',
                          title: '최저임금법',
                        ),
                  ),
                ),
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.schedule_rounded, size: 16, color: _blue),
            title: const Text('근로기준법 준수', style: TextStyle(fontSize: 12)),
            subtitle: const Text(
              '근무시간·휴게시간 법적 기준 준수',
              style: TextStyle(fontSize: 11),
            ),
            trailing: const Icon(Icons.chevron_right, size: 14),
            onTap:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => PolicyDetailScreen(
                          filePath: 'assets/policies/labor_policy.md',
                          title: '근로기준법',
                        ),
                  ),
                ),
          ),
          ListTile(
            dense: true,
            leading: const Icon(
              Icons.verified_user_rounded,
              size: 16,
              color: _blue,
            ),
            title: const Text('고용차별 금지', style: TextStyle(fontSize: 12)),
            subtitle: const Text(
              '성별·연령·외모 등 차별 금지',
              style: TextStyle(fontSize: 11),
            ),
            trailing: const Icon(Icons.chevron_right, size: 14),
            onTap:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => PolicyDetailScreen(
                          filePath: 'assets/policies/equality_policy.md',
                          title: '고용차별 금지',
                        ),
                  ),
                ),
          ),
        ],
      ],
    ),
  );
}

// ════════════════════════════════════════════════════════
//  등록 방식 바텀시트
// ════════════════════════════════════════════════════════
class _PublishSheet extends StatefulWidget {
  final int paidPassCount;
  final int urgentPassCount;
  final bool passCountLoading;
  final bool passCountFailed;
  final int availableWorkersCount;
  final VoidCallback onFreeSubmit;
  final void Function(DateTime?) onPaidSubmit;
  final VoidCallback onUrgentSubmit;
  final VoidCallback onBuyPass;
  final VoidCallback onRetryPassCount;
  final bool externalApplyEnabled;
  const _PublishSheet({
    required this.paidPassCount,
    required this.passCountLoading,
    required this.onFreeSubmit,
    required this.onPaidSubmit,
    required this.onUrgentSubmit,
    required this.onBuyPass,
    required this.onRetryPassCount,
    this.passCountFailed = false,
    this.externalApplyEnabled = false,
    this.urgentPassCount = 0,
    this.availableWorkersCount = 0,
  });
  @override
  State<_PublishSheet> createState() => _PublishSheetState();
}

class _PublishSheetState extends State<_PublishSheet> {
  bool? _boosterSelected;
  bool _isScheduled = false;
  DateTime? _scheduledDate;
  TimeOfDay? _scheduledTime;
  bool _confirming = false;

  final ScrollController _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  bool get _paidOk => widget.paidPassCount > 0 || widget.paidPassCount == -1;

  void _selectInstant() {
    // 조회 실패 상태에서는 결제로 보내지 않는다 — 이미 보유 중일 수 있다.
    if (widget.passCountFailed) {
      widget.onRetryPassCount();
      return;
    }
    if (!_paidOk) {
      widget.onBuyPass();
      return;
    }
    setState(() => _boosterSelected = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showFreeUpsell() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (ctx) => Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              20,
              24,
              MediaQuery.of(ctx).padding.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.schedule_rounded,
                    size: 26,
                    color: Color(0xFFFF9500),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  '무료 게시는 12시간 뒤에 노출돼요',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  // 이용권 보유 여부에 따라 "얼마 드는지"를 여기서 미리 밝힌다.
                  widget.paidPassCount == -1
                      ? '구독 혜택으로 지금 바로 상단에 노출할 수 있어요.\n이용권 차감 없이 진행됩니다.'
                      : widget.paidPassCount > 0
                      ? '보유 중인 즉시게시 이용권 ${widget.paidPassCount}개로\n지금 바로 상단에 노출할 수 있어요. 추가 결제 없어요.'
                      : '즉시게시 이용권(₩4,900)을 구매하면 지금 바로\n상단에 노출할 수 있어요.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B7280),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          widget.onFreeSubmit();
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: Color(0xFFE5E7EB)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          '무료로 올리기',
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _selectInstant();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _blue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          '즉시게시로 올리기',
                          style: TextStyle(fontWeight: FontWeight.w700),
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

  String get _scheduledLabel {
    if (_scheduledDate == null || _scheduledTime == null) return '날짜·시간 선택';
    return '${DateFormat('M월 d일', 'ko_KR').format(_scheduledDate!)} '
        '${_scheduledTime!.hour.toString().padLeft(2, '0')}:${_scheduledTime!.minute.toString().padLeft(2, '0')}';
  }

  bool get _canConfirm =>
      !_isScheduled || (_scheduledDate != null && _scheduledTime != null);

  // 예약 시각을 로컬 DateTime으로 명시적 생성
  //         → _submit()에서 .toUtc()로 변환되므로 여기선 로컬로 넘겨야 함
  void _exec() {
    DateTime? at;
    if (_isScheduled && _scheduledDate != null && _scheduledTime != null) {
      // 사용자가 선택한 날짜+시간을 로컬 DateTime으로 생성
      at = DateTime(
        _scheduledDate!.year,
        _scheduledDate!.month,
        _scheduledDate!.day,
        _scheduledTime!.hour,
        _scheduledTime!.minute,
      );
      // 로컬 DateTime임을 명시 — Dart의 DateTime()은 기본 로컬이지만
      //    isUtc == false를 확인해서 toUtc() 변환이 올바르게 동작하도록 보장
      assert(!at.isUtc, '예약 시각은 로컬 DateTime이어야 합니다');
    }
    widget.onPaidSubmit(at);
  }

  @override
  Widget build(BuildContext context) {
    final kb = MediaQuery.of(context).viewInsets.bottom;
    final pad = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, (kb > 0 ? kb : pad) + 16),
      child: SingleChildScrollView(
        controller: _scrollCtrl,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 20),
            if (widget.availableWorkersCount > 0) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.people_alt_rounded,
                      size: 16,
                      color: Color(0xFFFF9500),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '근무지 반경 5km 내 오늘 가능한 알바생 ${widget.availableWorkersCount}명',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        // #FF9500는 이 배경에서 2.01:1 — AA 미달
                        color: AppColors.warningDark,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (!_confirming) ...[
              // ── 긴급호출 (최우선 CTA)
              Semantics(
                button: true,
                label:
                    widget.passCountFailed
                        ? '긴급 호출, 이용권 확인 실패. 다시 시도'
                        : (widget.urgentPassCount > 0 ||
                            widget.urgentPassCount == -1)
                        ? '긴급 호출로 등록하기, 이용권 사용'
                        : '긴급 호출로 등록하기, 7900원',
                child: GestureDetector(
                onTap:
                    widget.passCountFailed
                        ? widget.onRetryPassCount
                        : (widget.urgentPassCount > 0 ||
                            widget.urgentPassCount == -1)
                        ? widget.onUrgentSubmit
                        : widget.onBuyPass,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors:
                          (widget.urgentPassCount > 0 ||
                                  widget.urgentPassCount == -1)
                              ? [
                                const Color(0xFFEF4444),
                                const Color(0xFFDC2626),
                              ]
                              : [
                                const Color(0xFFF87171),
                                const Color(0xFFEF4444),
                              ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.30),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.20),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.bolt_rounded,
                          size: 22,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  '긴급 호출',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    widget.passCountFailed
                                        ? '확인 필요'
                                        : widget.urgentPassCount == -1
                                        ? '무제한 (구독)'
                                        : widget.urgentPassCount > 0
                                        ? '${widget.urgentPassCount}회 보유'
                                        : '₩7,900',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              widget.passCountFailed
                                  ? '보유 이용권을 확인하지 못했어요. 탭해서 다시 시도해주세요.'
                                  : (widget.urgentPassCount > 0 ||
                                      widget.urgentPassCount == -1)
                                  ? '즉시 노출 · 반경 5km 알바생 최대 10명 · 무응답 100% 환급 · 추가 결제 없음'
                                  : '₩7,900로 즉시 노출 + 반경 5km 알바생 직접 호출 · 무응답 100% 환급',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.88),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ],
                  ),
                ),
              ),
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Expanded(child: Divider(color: _border)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      '또는 일반 등록',
                      style: TextStyle(fontSize: 12, color: _sub),
                    ),
                  ),
                  Expanded(child: Divider(color: _border)),
                ],
              ),
              const SizedBox(height: 16),
              _CompareCard(
                paidPassCount: widget.paidPassCount,
                passCountLoading: widget.passCountLoading,
                passCountFailed: widget.passCountFailed,
                onFreeTap: _showFreeUpsell,
                onPaidTap: _selectInstant,
              ),
              if (_boosterSelected == true) ...[
                const SizedBox(height: 20),
                const Divider(height: 1),
                const SizedBox(height: 16),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '공개 시점',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _text,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: !_isScheduled,
                        label: '즉시 공개, 지금 바로 노출',
                        child: GestureDetector(
                          onTap:
                              () => setState(() {
                                _isScheduled = false;
                                _scheduledDate = null;
                                _scheduledTime = null;
                              }),
                          child: _pubOpt(
                            Icons.flash_on_rounded,
                            '즉시 공개',
                            '지금 바로 노출',
                            !_isScheduled,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: _isScheduled,
                        label: '예약 공개, 날짜와 시간 지정',
                        child: GestureDetector(
                          onTap: () => setState(() => _isScheduled = true),
                          child: _pubOpt(
                            Icons.schedule_rounded,
                            '예약 공개',
                            '날짜·시간 지정',
                            _isScheduled,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_isScheduled) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _dateBtn(context)),
                      const SizedBox(width: 10),
                      Expanded(child: _timeBtn(context)),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                _NextBtn(
                  onTap:
                      _canConfirm
                          ? () => setState(() => _confirming = true)
                          : () {},
                  label:
                      _isScheduled &&
                              (_scheduledDate == null || _scheduledTime == null)
                          ? '날짜·시간을 선택해주세요'
                          : _isScheduled
                          ? '$_scheduledLabel 예약 등록'
                          : '즉시 등록하기',
                ),
              ],
            ] else ...[
              const SizedBox(height: 8),
              const Icon(Icons.flash_on_rounded, size: 36, color: _blue),
              const SizedBox(height: 12),
              Text(
                widget.paidPassCount == -1 ? '즉시게시로 등록할까요?' : '이용권 1회 차감',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.paidPassCount == -1
                    ? '구독 혜택으로 즉시 노출됩니다.\n이용권 차감 없이 진행됩니다.'
                    : '이 공고를 등록하면 보유 이용권이\n1회 차감됩니다. 진행하시겠어요?',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Colors.black87),
              ),
              if (widget.externalApplyEnabled) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF5FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFD8E8FF)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.open_in_new_rounded, size: 16, color: _blue),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '구직자는 공고 정보를 본 뒤 외부 신청 페이지로 이동합니다.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _blue,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _confirming = false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('아니요'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _exec,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('예, 진행할게요'),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _pubOpt(IconData icon, String label, String sub, bool sel) =>
      AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFFEEF5FF) : _bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: sel ? _blue : _border,
            width: sel ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: sel ? _blue : _label),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: sel ? _blue : _text,
                  ),
                ),
                Text(
                  sub,
                  style: TextStyle(
                    fontSize: 11,
                    color: sel ? _blue.withOpacity(0.7) : _label,
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _dateBtn(BuildContext context) => Semantics(
    button: true,
    label:
        _scheduledDate != null
            ? '공개 날짜 ${DateFormat('M월 d일', 'ko_KR').format(_scheduledDate!)}, 변경하려면 두 번 탭'
            : '공개 날짜 선택',
    child: GestureDetector(
    onTap: () async {
      final p = await showDatePicker(
        context: context,
        initialDate:
            _scheduledDate ?? DateTime.now().add(const Duration(days: 1)),
        firstDate: DateTime.now(),
        lastDate: DateTime(2100),
      );
      if (p != null) setState(() => _scheduledDate = p);
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: _scheduledDate != null ? const Color(0xFFEEF5FF) : _bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _scheduledDate != null ? _blue : _border),
      ),
      child: Row(
        children: [
          Icon(
            Icons.calendar_today_outlined,
            size: 15,
            color: _scheduledDate != null ? _blue : _label,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _scheduledDate != null
                  ? DateFormat('M월 d일', 'ko_KR').format(_scheduledDate!)
                  : '날짜',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _scheduledDate != null ? _text : _label,
              ),
            ),
          ),
        ],
      ),
    ),
    ),
  );

  Widget _timeBtn(BuildContext context) => Semantics(
    button: true,
    label:
        _scheduledTime != null
            ? '공개 시각 ${_scheduledTime!.hour}시 ${_scheduledTime!.minute}분, 변경하려면 두 번 탭'
            : '공개 시각 선택',
    child: GestureDetector(
    onTap: () async {
      final p = await showTimePicker(
        context: context,
        initialTime: _scheduledTime ?? const TimeOfDay(hour: 9, minute: 0),
      );
      if (p != null) setState(() => _scheduledTime = p);
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: _scheduledTime != null ? const Color(0xFFEEF5FF) : _bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _scheduledTime != null ? _blue : _border),
      ),
      child: Row(
        children: [
          Icon(
            Icons.access_time_rounded,
            size: 15,
            color: _scheduledTime != null ? _blue : _label,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _scheduledTime != null
                  ? '${_scheduledTime!.hour.toString().padLeft(2, '0')}:${_scheduledTime!.minute.toString().padLeft(2, '0')}'
                  : '시간',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _scheduledTime != null ? _text : _label,
              ),
            ),
          ),
        ],
      ),
    ),
    ),
  );
}

// ════════════════════════════════════════════════════════
//  비교 카드
// ════════════════════════════════════════════════════════
class _CompareConfig {
  // [항목, 기본, 즉시게시, 긴급호출, 강조여부]
  static const rows = [
    ['노출 시점', '12시간 후', '즉시 노출', '즉시 노출', '1'],
    ['상단 고정', '없음', '없음', '24시간 고정', '1'],
    ['긴급 호출', '불가', '불가', '최대 10명', '1'],
    ['무응답 환급', '-', '-', '100% 자동', '1'],
    ['조건 알림', '없음', '알바생 알림', '알바생 알림', '0'],
  ];
}

class _CompareCard extends StatelessWidget {
  final int paidPassCount;
  final bool passCountLoading;
  final bool passCountFailed;
  final VoidCallback onFreeTap, onPaidTap;
  const _CompareCard({
    required this.paidPassCount,
    required this.passCountLoading,
    required this.onFreeTap,
    required this.onPaidTap,
    this.passCountFailed = false,
  });

  @override
  Widget build(BuildContext context) {
    // 조회 실패 시 paidPassCount는 0이지만 "없음"이 아니라 "모름"이다.
    final paidOk =
        !passCountFailed && (paidPassCount > 0 || paidPassCount == -1);
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _border),
          ),
          child: Column(
            children: [
              // 헤더: 기본 / 즉시게시 / 긴급호출
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                child: Row(
                  children: [
                    const Expanded(flex: 4, child: SizedBox()),
                    Expanded(
                      flex: 3,
                      child: Center(
                        child: Text(
                          '기본',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _sub,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _blue,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: const Text(
                            '즉시게시',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: const Text(
                            '긴급호출',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: _border),
              ..._CompareConfig.rows.map(
                (r) => _CompareRow(
                  label: r[0],
                  free: r[1],
                  paid: r[2],
                  urgent: r[3],
                  highlight: r[4] == '1',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                label: '무료 등록, 12시간 후 노출',
                child: GestureDetector(
                onTap: onFreeTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _border),
                  ),
                  child: const Column(
                    children: [
                      Text(
                        '무료 등록',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _text,
                        ),
                      ),
                      SizedBox(height: 5),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 11,
                            color: AppColors.warningDark,
                          ),
                          SizedBox(width: 3),
                          Text(
                            '12시간 후 노출',
                            // #FF9500는 흰 배경에서 2.20:1 — AA 미달
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.warningDark,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Semantics(
                button: true,
                label:
                    passCountFailed
                        ? '즉시게시, 이용권 확인 실패. 다시 시도'
                        : paidOk
                        ? '즉시게시로 등록, 이용권 사용'
                        : '즉시게시로 등록, 4900원',
                child: GestureDetector(
                onTap: onPaidTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF3182F6), Color(0xFF6C5CE7)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      // 이용권이 있으면 가격을 보여주지 않는다 —
                      // 실제로는 차감만 되는데 ₩4,900이 붙으면 "결제해야 하는 줄" 오해한다.
                      Text(
                        passCountFailed
                            ? '즉시게시'
                            : paidOk
                            ? '즉시게시 · 이용권 사용'
                            : '즉시게시 · ₩4,900',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        paidOk ? '즉시 노출 · 추가 결제 없음' : '즉시 노출',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        passCountLoading
                            ? '조회 중…'
                            : passCountFailed
                            ? '이용권 확인 실패 · 다시 시도'
                            : paidPassCount == -1
                            ? '무제한 (구독 혜택)'
                            : paidOk
                            ? '이용권 $paidPassCount개 보유'
                            : '이용권 없음 · 구매하기',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.85),
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
      ],
    );
  }
}

class _CompareRow extends StatelessWidget {
  final String label, free, paid, urgent;
  final bool highlight;
  const _CompareRow({
    required this.label,
    required this.free,
    required this.paid,
    required this.urgent,
    required this.highlight,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: highlight ? const Color(0xFFF8FAFF) : Colors.white,
      border: const Border(top: BorderSide(color: _border, width: 0.5)),
    ),
    child: Row(
      children: [
        Expanded(
          flex: 4,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _sub,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Center(
            child: Text(
              free,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: _label),
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Center(
            child: Text(
              paid,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: highlight ? _blue : _label,
              ),
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Center(
            child: Text(
              urgent,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: highlight ? const Color(0xFFEF4444) : _label,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _CommaNumberInputFormatter extends TextInputFormatter {
  const _CommaNumberInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    final formatted = NumberFormat('#,###').format(int.parse(digits));
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
