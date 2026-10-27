import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:app_settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:iljujob/data/services/chat_service.dart';
import 'package:iljujob/presentation/chat/chat_room_screen.dart';
import 'package:iljujob/presentation/screens/client_screen/client_profile_screen.dart';
import '../../../data/models/job.dart';
import '../../../config/constants.dart';
import 'package:intl/intl.dart';
import '../full_image_view_screen.dart';
import 'package:iljujob/presentation/screens/full_map_screen.dart';
import '../client_screen/client_job_list_screen.dart';
// Platform 사용을 위해 필요
import 'package:kakao_maps_flutter/kakao_maps_flutter.dart' as km;
import '../../../core/suspension.dart';
import '../../../core/suspension_guard.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/services.dart'; // Clipboard
import 'package:url_launcher/url_launcher.dart';
import 'package:iljujob/config/app_theme.dart';
import 'package:iljujob/widget/app_ui.dart';
import 'package:iljujob/data/services/log_service.dart';
import 'package:iljujob/data/services/job_service.dart';
import 'package:iljujob/data/services/screen_analytics_service.dart';
import 'package:iljujob/data/services/authenticated_http_client.dart';
import 'package:iljujob/widget/ad_banner_widget.dart';
import 'package:iljujob/widget/push_permission.dart';
import 'ai_interview_prep_sheet.dart';
import 'recent_jobs_screen.dart';
import 'my_applied_jobs_screen.dart';
import 'package:iljujob/utils/apply_stage.dart';
import 'package:iljujob/utils/pay_display.dart';
import '../../../config/messages.dart';

const kBrand = AppColors.primary;

class JobDetailScreen extends StatefulWidget {
  final Job job;

  /// 목록의 '지원하기'로 열렸으면 true — 상세가 다 뜬 뒤 상세의 지원 흐름을 그대로 탄다
  /// (로그인·마감·차단·정지·외부 신청 판단을 한 곳에서만 한다)
  final bool autoApply;

  const JobDetailScreen({super.key, required this.job, this.autoApply = false});

  /// 비로그인 '지원하기' → 가입 후 돌아올 공고 id (HomeScreen 이 읽고 지운다)
  static const pendingApplyJobKey = 'pending_apply_job_id';

  @override
  State<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> {
  SuspensionState? _suspension; // /me에서 가져온 정지 상태
  bool hasApplied = false;
  bool isBookmarked = false;
  int applicantCount = 0;
  int viewCount = 0;
  int bookmarkCount = 0;
  bool isLoading = true;
  Map<String, dynamic>? clientProfile;
  String? userType;
  int? myUserId;
  bool isBlocked = false;
  double? _distanceMeters;
  String? _nearStationName;
  int? _nearStationWalkMin;

  Future<void> _loadSuspension() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getInt('userId');
      final type = (prefs.getString('userType') ?? 'worker').toLowerCase();
      if (id == null) throw Exception('no userId');

      final uri = Uri.parse('$baseUrl/api/public/suspension?type=$type&id=$id');
      final res = await http.get(uri); // ← 토큰 없이
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
        });
        return;
      }
    } catch (_) {}

    // 기본 정상
    setState(() {
      _suspension = const SuspensionState(
        suspendedType: null,
        suspendedUntil: null,
        suspendedReason: null,
      );
    });
  }

  String _getWorkingPeriodText(Job job) {
    // 장기 알바
    if (formatWeekdays(job.weekdays) case final w?) return w;

    // 단기 알바
    if (job.startDate != null && job.endDate != null) {
      final start = _formatDate(job.startDate!);
      final end = _formatDate(job.endDate!);
      return '$start ~ $end';
    }

    return '근무 기간 미정';
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal(); // ✅ 로컬(KST)로 변환
    return '${local.month}월 ${local.day}일';
  }

  Future<void> _loadBookmarked() async {
    final userId = (await SharedPreferences.getInstance()).getInt('userId');
    if (userId == null) return;
    try {
      final jobs = await JobService.fetchBookmarkedJobs(userId);
      final mine = jobs.any((j) => '${j.id}' == '${widget.job.id}');
      if (mounted) setState(() => isBookmarked = mine);
    } catch (_) {}
  }

  /// 홈 목록 하트와 같은 API. 화면 먼저 바꾸고 실패하면 되돌린다
  Future<void> _toggleBookmark() async {
    final userId = (await SharedPreferences.getInstance()).getInt('userId');
    if (userId == null || !mounted) return;
    final was = isBookmarked;
    setState(() => isBookmarked = !was);
    try {
      final resp = await AuthenticatedHttpClient.postJson(
        Uri.parse('$baseUrl/api/bookmark/${was ? 'remove' : 'add'}'),
        body: {'worker_id': userId, 'job_id': '${widget.job.id}'},
      );
      // '이미 북마크됨' · '북마크 내역 없음'은 서버가 이미 원하는 상태
      final ok =
          resp.statusCode == 200 ||
          resp.body.contains('이미 북마크됨') ||
          resp.body.contains('북마크 내역 없음');
      if (!ok) throw Exception(resp.statusCode);
      if (!was) {
        final jobId = int.tryParse('${widget.job.id}');
        if (jobId != null) {
          LogService.instance.logEvent(
            eventType: LogService.bookmark,
            jobId: jobId,
          );
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => isBookmarked = was);
      _showSnack('관심 공고 저장에 실패했어요. 잠시 후 다시 시도해주세요.');
    }
  }

  void _openInterviewPrep() {
    final payInt =
        int.tryParse(widget.job.pay.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder:
          (_) => AiInterviewPrepSheet(
            jobTitle: widget.job.title,
            category: widget.job.category,
            location: widget.job.location,
            payType: widget.job.payType,
            pay: payInt,
          ),
    );
  }

  bool _shouldShowReportButton() {
    // 클라이언트이고 내 공고라면 신고 버튼 숨김
    if (userType == 'client' && widget.job.clientId == myUserId) {
      return false;
    }
    return true;
  }

  bool get isClosed =>
      widget.job.status == 'closed' || widget.job.status == 'deleted';
  Map<String, dynamic>? reviewSummary;

  @override
  void initState() {
    super.initState();
    ScreenAnalyticsService.instance.logScreenView('job_detail');
    RecentJobs.add(widget.job.id);
    _loadUserType();
    _initializePage();
    _incrementViewCount();
    _loadReviewSummary();

    // 공고 상세를 본 사람의 82%가 지원하지 않는데, 그 중 몇 명이 애초에
    // 지원 버튼을 누를 수 없는 상태(마감·기지원·차단·정지)였는지 알 수가 없었다.
    // 세 로드가 끝나야 버튼 상태가 정해지므로 그 뒤에 찍는다.
    Future.wait([
      _checkAlreadyApplied(),
      _checkBlockStatus(),
      _loadSuspension(),
      _loadBookmarked(),
    ]).whenComplete(() {
      _logDetailView();
      if (widget.autoApply) _autoApplyFromList();
    });

    // 첫 공고 상세를 본 구직자에게 한 번, 왜 알림이 필요한지 말하고 묻는다.
    // 목록에서 바로 지원하는 경우엔 지원 흐름이 알림 권한을 따로 묻는다
    Future.delayed(const Duration(seconds: 2), () async {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted || widget.autoApply || prefs.getString('userType') != 'worker') return;
      await maybeShowPushPrimer(context);
    });
    _loadLocationContext();
    final jobId = int.tryParse(widget.job.id.toString());
    if (jobId != null) {
      LogService.instance.logEvent(
        eventType: LogService.view, // ← view 로 수정
        jobId: jobId,
      );
    }
  }

  String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }

  String _interestLabel(int views, int bookmarks, int applicants) {
    // 과장 없이 “분류”만
    if (views >= 200 || bookmarks >= 20 || applicants >= 10) return '인기 공고';
    if (views >= 50 || bookmarks >= 8 || applicants >= 3) return '관심 많아요';
    if (views >= 10 || bookmarks >= 2 || applicants >= 1) return '관심 쌓이는 중';
    return '새 공고';
  }

  String _shortLocationText() {
    final city = widget.job.locationCity.trim();
    if (city.isNotEmpty) return city;

    final location = widget.job.location.trim();
    if (location.isEmpty) return '위치 확인';
    return location.split(RegExp(r'\s+')).take(2).join(' ');
  }

  /// '인천 남동구 석남로 12 · 9.4km'. 거리만으론 어디인지 모른다 (2026-10 실기기)
  String _distanceOrLocationText() {
    final m = _distanceMeters;
    final place =
        widget.job.location.trim().isNotEmpty
            ? widget.job.location.trim()
            : _shortLocationText();
    if (m == null) return place;
    final dist =
        m >= 1000
            ? '${(m / 1000).toStringAsFixed(1)}km'
            : '${m.toStringAsFixed(0)}m';
    return '$place · $dist';
  }

  String _applicantSummaryText() {
    if (applicantCount <= 0) return '첫 지원 가능';
    return '지원 $applicantCount명';
  }

  @override
  void dispose() {
    super.dispose();
  }

  String _getCompanyName() {
    // 회사명 → (없으면) 담당자명 → (없으면) 목록에서 온 company → 최후 문구.
    // 담당자명은 가입 필수라 프로필만 로드되면 '회사 정보 없음'은 거의 안 뜬다.
    if (clientProfile != null) {
      final company = clientProfile!['company_name']?.toString().trim() ?? '';
      if (company.isNotEmpty) return company;

      final manager = clientProfile!['manager_name']?.toString().trim() ?? '';
      if (manager.isNotEmpty) return manager;
    }

    if (widget.job.company != null && widget.job.company!.trim().isNotEmpty) {
      return widget.job.company!;
    }

    return '회사 정보를 찾을 수 없습니다.';
  }

  Future<void> _initializePage() async {
    await _fetchApplicantCount();
    await _fetchClientProfile();
    await _fetchCounts();
    setState(() => isLoading = false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  Future<void> _loadLocationContext() async {
    final lat = double.tryParse(widget.job.lat.toString()) ?? 0;
    final lng = double.tryParse(widget.job.lng.toString()) ?? 0;
    if (lat == 0 || lng == 0) return;

    try {
      // 1) 내 위치 -> 거리 계산
      // (권한/서비스 문제 있으면 실패해도 그냥 넘어가면 됨)
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 3),
      );
      final meters = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        lat,
        lng,
      );
      setState(() => _distanceMeters = meters);

      // 2) (선택/강추) 서버에서 “가까운 지하철역” 조회해서 가져오기
      // - 앱에 카카오 로컬 REST 키 박지 말고 서버에서 처리!
      final res = await http.get(
        Uri.parse('$baseUrl/api/geo/nearby-station?lat=$lat&lng=$lng'),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final name = (data['name'] ?? '').toString();
        final distM = (data['distanceM'] ?? 0).toDouble();
        if (name.trim().isNotEmpty) {
          setState(() {
            _nearStationName = name.trim();
            // 도보 1분=80m 정도(대략치, 과장 방지)
            _nearStationWalkMin = (distM / 80).ceil().clamp(1, 60);
          });
        }
      }
    } catch (_) {
      // 실패해도 UI는 계속 돌아가게
    } finally {
      if (mounted) setState(() {}); // 가까운 역 정보 반영
    }
  }

  Future<void> _copyAddress(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    _showSnack('주소가 복사됐어요');
  }

  Future<void> _openKakaoDirections(
    double lat,
    double lng, {
    String name = '근무지',
  }) async {
    // 앱 스킴 -> 실패하면 웹 fallback
    final app = Uri.parse('kakaomap://look?p=$lat,$lng');
    final web = Uri.parse('https://map.kakao.com/link/map/$name,$lat,$lng');
    if (await canLaunchUrl(app)) {
      await launchUrl(app);
    } else {
      await launchUrl(web, mode: LaunchMode.externalApplication);
    }
  }

  /// 상세 진입 시 지원 버튼이 실제로 눌릴 수 있는 상태였는지 기록한다.
  /// `_buildApplyBar` 의 `isButtonDisabled` 와 같은 조건을 쓴다 — 어긋나면 지표가 거짓말이 된다.
  void _logDetailView() {
    if (!mounted) return;
    final isSuspended = _suspension?.isSuspended ?? false;
    final hasExternalApply = widget.job.hasExternalApply;

    final String buttonState;
    if (isClosed) {
      buttonState = 'closed';
    } else if (hasExternalApply) {
      buttonState = 'external';
    } else if (hasApplied) {
      buttonState = 'already_applied';
    } else if (isBlocked) {
      buttonState = 'blocked';
    } else if (isSuspended) {
      buttonState = 'suspended';
    } else {
      buttonState = 'enabled';
    }

    ScreenAnalyticsService.instance.logEvent(
      'worker_job_detail_view',
      params: {
        'job_id': widget.job.id,
        'category': widget.job.category,
        'button_state': buttonState,
      },
    );
  }

  Future<void> _checkBlockStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId') ?? 0;

    final res = await http.get(
      Uri.parse(
        '$baseUrl/api/job/${widget.job.id}/block-status?userId=$userId',
      ),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      setState(() {
        isBlocked = data['isBlocked'] == true;
      });
    }
  }

  Future<void> _loadUserType() async {
    final prefs = await SharedPreferences.getInstance();

    final userId = prefs.getInt('userId'); // 👈 오해 없도록 명확하게
    final userTypeFromPrefs = prefs.getString('userType');

    setState(() {
      myUserId = userId;
      userType = userTypeFromPrefs;
    });
  }

  Future<void> _fetchApplicantCount() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/job/${widget.job.id}/applicant-count'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() => applicantCount = data['count']);
      }
    } catch (e) {
      print('❌ 지원자 수 조회 오류: $e');
    }
  }

  Future<void> _checkAlreadyApplied() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId'); // 🔥 userPhone 말고 userId!
    final jobId = int.tryParse(widget.job.id.toString());

    if (userId == null || jobId == null) return;

    try {
      final response = await AuthenticatedHttpClient.postJson(
        Uri.parse('$baseUrl/api/job/check-applied'),
        body: {'workerId': userId, 'jobId': jobId},
      );

      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          hasApplied = data['applied'];
        });
      }
    } catch (e) {
      debugPrint('❌ 지원 여부 확인 실패: $e');
    }
  }

  Future<void> _fetchClientProfile() async {
    if (widget.job.clientId == null) return;

    try {
      // 인증 불필요 경로(getClientProfile). 예전 /api/client/profile은
      // verifyToken이 걸려 구직자 토큰 만료/게스트면 401 → 회사명이 안 떴다.
      final url = Uri.parse('$baseUrl/api/job/profile/${widget.job.clientId}');
      final res = await http.get(url);
      if (res.statusCode == 200) {
        setState(() => clientProfile = jsonDecode(res.body));
      } else {
        print('❌ 클라이언트 프로필 응답 실패: ${res.statusCode}');
      }
    } catch (e) {
      print('❌ 클라이언트 프로필 불러오기 실패: $e');
    }
  }

  Future<void> _loadReviewSummary() async {
    final clientId = widget.job.clientId;
    if (clientId == null) {
      print('❌ clientId가 null임');
      return;
    }

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/review/summary?clientId=$clientId'),
      );

      if (response.statusCode == 200) {
        setState(() {
          reviewSummary = jsonDecode(response.body);
        });
      } else {
        print('❌ review summary 응답 오류: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ 리뷰 요약 불러오기 실패: $e');
    }
  }

  Future<void> _fetchCounts() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/job/${widget.job.id}/counts'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          viewCount = data['views'] ?? 0;
          bookmarkCount = data['bookmarks'] ?? 0;
        });
      } else {
        print('❌ 카운트 불러오기 실패: ${response.body}');
      }
    } catch (e) {
      print('❌ 카운트 네트워크 오류: $e');
    }
  }

  Future<void> _incrementViewCount() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/job/${widget.job.id}/increment-view'),
      );
      if (response.statusCode != 200) {
        print('❌ 조회수 증가 실패: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ 조회수 증가 중 예외 발생: $e');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // 지원 후 알림이 꺼져 있으면 사장님 답장을 못 받는다.
  // 권한 상태를 확인하고, 꺼져 있으면 켜도록 안내한다.
  Future<void> _ensureNotificationForReply() async {
    try {
      final s = await FirebaseMessaging.instance.getNotificationSettings();
      final st = s.authorizationStatus;
      // 이미 허용/임시허용이면 아무것도 안 함
      if (st == AuthorizationStatus.authorized ||
          st == AuthorizationStatus.provisional) {
        return;
      }
      // notDetermined면 OS 권한 팝업이 뜬다(한 번). 그 뒤 상태 재확인.
      if (st == AuthorizationStatus.notDetermined) {
        final r = await FirebaseMessaging.instance.requestPermission();
        if (r.authorizationStatus == AuthorizationStatus.authorized ||
            r.authorizationStatus == AuthorizationStatus.provisional) {
          return;
        }
      }
      // 여기까지 왔으면 denied — OS 팝업이 다시 안 뜨므로 설정으로 안내.
      // 매 지원마다 띄우면 성가시니 7일에 한 번만.
      final prefs = await SharedPreferences.getInstance();
      final lastMs = prefs.getInt('notifSheetLastShownMs') ?? 0;
      final weekMs = 7 * 24 * 60 * 60 * 1000;
      if (DateTime.now().millisecondsSinceEpoch - lastMs < weekMs) return;
      if (!mounted) return;
      await _showEnableNotificationSheet();
      await prefs.setInt(
        'notifSheetLastShownMs',
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      // 권한 조회 실패는 지원 흐름을 막지 않는다
    }
  }

  Future<void> _showEnableNotificationSheet() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.notifications_active_outlined,
                    size: 40,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '알림을 켜면 사장님 답장을 바로 받아요',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '지금은 알림이 꺼져 있어 사장님이 연락해도\n모르고 지나칠 수 있어요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      AppSettings.openAppSettings(
                        type: AppSettingsType.notification,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '알림 설정 열기',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text(
                      '나중에',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  /// 지원 완료 안내. 상태 이름·다음 할 일은 내 활동과 같은 기준(apply_stage.dart).
  /// 반환: 'chat'(채팅으로) · 'activity'(내 활동으로) · null(닫기)
  Future<String?> _showApplyDoneSheet() async {
    if (!mounted) return null;
    const stage = ApplyStage.waiting;
    return showModalBottomSheet<String>(
      context: context,
      builder:
          (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 44,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '지원했어요',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.h2,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '지금 상태: ${stage.label}\n사장님이 답하면 알림으로 알려드려요.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body2,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, 'chat'),
                      child: Text(stage.next!),
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, 'activity'),
                    child: const Text('내 활동에서 상태 확인'),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  /// 상세 하단 버튼을 누른 것과 같은 판단. 지원할 수 없는 상태면 아무것도 하지 않고 상세에 머문다
  Future<void> _autoApplyFromList() async {
    if (!mounted) return;
    final type = (await SharedPreferences.getInstance()).getString('userType');
    if (!mounted) return;
    if (type == null) return _askSignupToApply();
    if (type != 'worker' || hasApplied || isClosed || isBlocked) return;
    if (_suspension?.isSuspended ?? false) return;
    if (widget.job.hasExternalApply) return _openExternalApplyPage();
    // 목록에서 바로 누른 지원은 조건을 읽기 전이다 — 급여·일정·장소를 보여주고 한 번 더 묻는다
    // (확인 없이 보내면 조건이 안 맞아 취소·무응답이 늘어난다, 2026-10 평가)
    final job = widget.job;
    final pay = isNegotiablePayType(job.payType)
        ? '급여 협의'
        : '${job.payType} ${formatJobPay(job.pay, job.payType)}';
    final when = [
      _getWorkingPeriodText(job),
      if (job.workingHours.replaceAll('~', '').trim().isNotEmpty)
        job.workingHours,
    ].join(' · ');
    final ok = await showAppSheet(
      context,
      title: '이 조건으로 지원할까요?',
      message: '$pay\n$when\n${_distanceOrLocationText()}',
      confirmLabel: '지원하기',
      cancelLabel: '공고 더 보기',
    );
    if (!ok || !mounted) return;
    await _applyToJob();
  }

  Future<void> _applyToJob() async {
    // 퍼널: 지원 의도 → 성공/실패. 셋을 다 찍어야 어디서 깨지는지 보인다.
    ScreenAnalyticsService.instance.logEvent(
      'worker_apply_tap',
      params: {'job_id': widget.job.id, 'category': widget.job.category},
    );
    // 0) 정지(차단) 가드: _suspension이 없다면 기본값(정상)으로 판단
    final s =
        _suspension ??
        const SuspensionState(
          suspendedType: null,
          suspendedUntil: null,
          suspendedReason: null,
        );
    if (!guardSuspended(context, s)) {
      ScreenAnalyticsService.instance.logEvent(
        'worker_apply_fail',
        params: {'reason': 'suspended'},
      );
      return; // 정지면 토스트 띄우고 중단
    }

    // 1) 기본 검증
    final prefs = await SharedPreferences.getInstance();
    final workerId = prefs.getInt('userId');
    final clientId = widget.job.clientId;
    final String jobId = widget.job.id.toString();

    if (workerId == null || clientId == null || jobId.isEmpty) {
      _showSnack(Msg.loginRequired);
      return;
    }

    // 2) 요청
    final applyUrl = Uri.parse('$baseUrl/api/job/apply');

    try {
      final response = await AuthenticatedHttpClient.postJson(
        applyUrl,
        body: {
          'workerId': workerId,
          'jobId': widget.job.id, // int로 직접 전달
        },
      );

      // 2-1) 서버가 정지 계정으로 막을 경우(권장: 423 Locked 또는 403)
      if (response.statusCode == 423 || response.statusCode == 403) {
        var msg = '정지 상태에서는 지원할 수 없습니다.';
        try {
          final data = jsonDecode(response.body);
          if (data is Map &&
              (data['code'] == 'SUSPENDED' || data['message'] != null)) {
            msg = data['message']?.toString() ?? msg;
          }
        } catch (_) {}
        ScreenAnalyticsService.instance.logEvent(
          'worker_apply_fail',
          params: {'reason': 'blocked', 'status': response.statusCode},
        );
        _showSnack(msg);
        return;
      }

      // 2-2) 정상 처리
      if (response.statusCode == 200) {
        ScreenAnalyticsService.instance.logEvent(
          'worker_apply_complete',
          params: {'job_id': widget.job.id, 'category': widget.job.category},
        );
        // ✅ apply 로그 추가
        final jobIdInt = int.tryParse(widget.job.id.toString());
        if (jobIdInt != null) {
          LogService.instance.logEvent(
            eventType: LogService.apply, // ← apply 로 수정
            jobId: jobIdInt,
          );
        }

        await _fetchApplicantCount();
        setState(() => hasApplied = true);

        // 지원 직후 알림 권한 점검 — 꺼져 있으면 사장님 답장을 놓친다.
        await _ensureNotificationForReply();

        final roomId = await startChatRoom(workerId, jobId, clientId);
        if (roomId != null) {
          // 지원 완료 안내 → 채팅 / 내 활동 / 닫기(화면 유지)
          final choice = await _showApplyDoneSheet();
          if (!mounted || choice == null) return;
          if (choice == 'activity') {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MyAppliedJobsScreen()),
            );
            return;
          }

          Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (context) => ChatRoomScreen(
                    chatRoomId: roomId,
                    jobInfo: {
                      'title': widget.job.title,
                      'pay': widget.job.pay,
                      'posted_at':
                          widget.job.postedAtUtc?.toUtc().toIso8601String() ??
                          '',
                      'publish_at':
                          widget.job.publishAt?.toUtc().toIso8601String() ?? '',
                      'created_at':
                          widget.job.createdAt?.toUtc().toIso8601String() ?? '',
                      'client_id': clientId,
                      'worker_id': workerId,
                      'client_company_name':
                          clientProfile?['company_name'] ??
                          widget.job.company ??
                          '기업',
                      'client_thumbnail_url': clientProfile?['logo_url'] ?? '',
                    },
                  ),
            ),
          );
        } else {
          // 지원은 됐다 — 안내 시트가 없으니 지원 사실을 같이 알린다
          _showSnack('${Msg.applyDone} ${Msg.chatCreateFailed}');
        }
      } else if (response.statusCode == 409) {
        _showSnack(Msg.applyDuplicate);
        setState(() => hasApplied = true);
      } else {
        debugPrint('지원 실패: ${response.body}');
        _showSnack(Msg.applyFailed);
      }
    } catch (e) {
      print('❌ 지원 중 예외: $e');
      _showSnack(Msg.network);
    }
  }

  Future<void> _openExternalApplyPage() async {
    final rawUrl = widget.job.externalApplyUrl?.trim();
    final uri = rawUrl == null ? null : Uri.tryParse(rawUrl);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.trim().isEmpty) {
      _showSnack('외부 신청 페이지 주소가 올바르지 않아요.');
      return;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      _showSnack('외부 신청 페이지를 열 수 없어요.');
    }
  }

  Future<void> _submitReport(
    String category,
    String detail,
    int jobId,
    int userId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final userPhone = prefs.getString('userPhone');
    final userType = prefs.getString('userType');

    try {
      final response = await AuthenticatedHttpClient.postJson(
        Uri.parse('$baseUrl/api/report/job'),
        body: {
          'jobId': jobId,
          'userId': userId,
          if (userType != null && userType.isNotEmpty) 'userType': userType,
          'userPhone': userPhone,
          'reasonCategory': category,
          'reasonDetail': detail,
        },
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('신고를 접수했어요. 24시간 이내에 조치할게요.')),
        );
      } else {
        debugPrint('신고 전송 실패: ${response.body}');
        _showSnack(Msg.server);
      }
    } catch (e) {
      print('❌ 예외 발생: $e');
      _showSnack('신고를 접수하지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  Future<void> _callAgencyPhone(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _showSnack('전화 앱을 열 수 없어요');
    }
  }

  Widget _buildGuestApplyBar() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        border: Border(top: BorderSide(color: AppColors.borderSub)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: isClosed ? null : _askSignupToApply,
              child: Text(isClosed ? '마감된 공고' : '지원하기'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _askSignupToApply() async {
    final go = await showModalBottomSheet<bool>(
      context: context,
      builder:
          (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '가입하고 지원하기',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.h2,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '가입하면 이 공고로 바로 돌아와 지원할 수 있어요.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body2,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('가입하기'),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('더 둘러보기'),
                  ),
                ],
              ),
            ),
          ),
    );
    if (go != true || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      JobDetailScreen.pendingApplyJobKey,
      '${widget.job.id}',
    );
    if (!mounted) return;
    Navigator.pushNamed(context, '/signup-choice');
  }

  Widget _buildApplyButton() {
    if (isLoading) return const SizedBox();

    // 대행 공고도 앱 지원을 받는다. 예전엔 지원·채팅을 막고 전화/이메일만 보여줬는데
    // 그 경로는 플랫폼 밖이라 결과를 알 수 없었다. 막힘이 새서(AI 검색에 is_agency 누락)
    // 앱으로 들어온 지원 48건은 사장님 답장률 50%로 일반 공고(48.8%)와 같았다 —
    // 게스트 사장님도 알림톡 → 웹 보드로 받아 답한다(2026-09-21 실측).
    // 연락 방식은 둘로 나눈다 — '전화로 지원'(사장님 번호) · '앱으로 지원'(채팅).
    final isAgency = (widget.job.isAgency == true);
    final agencyPhone =
        widget.job.agencyPhone?.trim().replaceAll(RegExp(r'[^0-9+]'), '') ?? '';
    final showPhoneApply = isAgency && agencyPhone.isNotEmpty;

    final isSuspended = _suspension?.isSuspended ?? false;
    final hasExternalApply = widget.job.hasExternalApply;
    final isButtonDisabled =
        isClosed ||
        (!hasExternalApply && (hasApplied || isBlocked || isSuspended));

    // 하단 고정 바: 흰 면 + 위 구분선. 주 버튼(파랑)은 하나만.
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        border: Border(top: BorderSide(color: AppColors.borderSub)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 정상 상태 안내('채팅방이 바로 열려요')는 버튼 이름과 같은 말이라 뺐다.
              // 막힌 이유(마감·차단·정지·지원함)만 띠로 알린다.
              if (isButtonDisabled || hasExternalApply) ...[
                _buildApplyHint(isButtonDisabled: isButtonDisabled),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  if (showPhoneApply)
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: () => _callAgencyPhone(agencyPhone),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.primary),
                            foregroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.call_outlined, size: 18),
                          label: Text('전화로 지원', style: AppTextStyles.btnLg),
                        ),
                      ),
                    )
                  else
                    // 관심 — 홈 목록의 하트와 같은 저장 (당근식: 지원 버튼 왼쪽)
                    SizedBox(
                      height: 52,
                      width: 52,
                      child: IconButton(
                        onPressed: _toggleBookmark,
                        tooltip: isBookmarked ? '관심 해제' : '관심 공고 저장',
                        icon: Icon(
                          isBookmarked
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 26,
                          color:
                              isBookmarked
                                  ? AppColors.badgeNew
                                  : AppColors.textTertiary,
                        ),
                      ),
                    ),
                  const SizedBox(width: 10),
                  // 지원하기 버튼
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kBrand,
                          disabledBackgroundColor: AppColors.bgMuted,
                          disabledForegroundColor: AppColors.textTertiary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          elevation: 0,
                        ),
                        onPressed:
                            isButtonDisabled
                                ? null
                                : hasExternalApply
                                ? _openExternalApplyPage
                                : _applyToJob,
                        child: Text(
                          isClosed
                              ? '마감된 공고'
                              : hasExternalApply
                              ? ((widget.job.externalApplyLabel
                                          ?.trim()
                                          .isNotEmpty ??
                                      false)
                                  ? widget.job.externalApplyLabel!.trim()
                                  : '자세히 보고 신청하기')
                              : hasApplied
                              ? '지원 완료'
                              : isBlocked
                              ? '차단된 기업'
                              : isSuspended
                              ? '정지된 계정'
                              : isAgency
                              ? '앱으로 지원'
                              : '지원하고 채팅 시작',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (hasExternalApply) ...[
                const SizedBox(height: 8),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.open_in_new_rounded,
                      size: 14,
                      color: AppColors.textSecondary,
                    ),
                    SizedBox(width: 4),
                    Text(
                      '외부 페이지로 이동합니다',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildApplyHint({required bool isButtonDisabled}) {
    String text;
    IconData icon;

    if (widget.job.hasExternalApply && !isClosed) {
      text = '공고 내용을 확인한 뒤 별도 신청 페이지에서 진행해요.';
      icon = Icons.open_in_new_rounded;
    } else if (hasApplied) {
      text = '이미 지원한 공고예요. 채팅에서 사장님 답변을 확인해보세요.';
      icon = Icons.check_circle_rounded;
    } else if (isClosed) {
      text = '마감된 공고라 새 지원을 받을 수 없어요.';
      icon = Icons.lock_clock_rounded;
    } else if (isBlocked) {
      text = '차단한 기업의 공고라 지원할 수 없어요.';
      icon = Icons.block_rounded;
    } else if (_suspension?.isSuspended ?? false) {
      text = '계정 상태 확인이 필요해 지원할 수 없어요.';
      icon = Icons.info_outline_rounded;
    } else {
      text = '지원하면 사장님과 대화할 채팅방이 바로 열려요.';
      icon = Icons.chat_bubble_outline_rounded;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.bgMuted, // 안내 문구는 누를 수 없다 — 파랑 금지
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.25,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showReportDialog() {
    final TextEditingController reasonDetailController =
        TextEditingController();
    String? selectedCategory;

    final List<String> reasonCategories = [
      '사기 또는 허위 공고',
      '불법 또는 음란성 콘텐츠',
      '중복/도배/광고성',
      '연락 불가/잠수',
      '기타',
    ];

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('공고 신고하기'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('문제가 되는 내용을 선택해주세요.\n운영팀이 확인 후 24시간 이내 조치합니다.'),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedCategory,
                  onChanged: (val) => selectedCategory = val,
                  items:
                      reasonCategories
                          .map(
                            (c) => DropdownMenuItem(value: c, child: Text(c)),
                          )
                          .toList(),
                  decoration: const InputDecoration(
                    labelText: '신고 사유',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: reasonDetailController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: '상세한 내용을 작성해주세요 (선택)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final category = selectedCategory;
                  final detail = reasonDetailController.text.trim();

                  if (category == null || category.isEmpty) {
                    _showSnack('신고 사유를 선택해주세요.');
                    return;
                  }

                  final prefs = await SharedPreferences.getInstance();
                  final userId = prefs.getInt('userId');
                  final jobId = int.tryParse(widget.job.id.toString());

                  if (userId != null && jobId != null) {
                    Navigator.pop(context);
                    await _submitReport(category, detail, jobId, userId);
                  } else {
                    _showSnack(Msg.loginRequired);
                  }
                },
                child: const Text('신고하기'),
              ),
            ],
          ),
    );
  }

  Widget _buildReviewSummary() {
    // 후기 0건이면 막대 3개가 전부 0 — 숨기는 게 '0'을 보여주는 것보다 낫다
    if (reviewSummary == null ||
        ((reviewSummary!['total'] as num?) ?? 0) == 0) {
      return const SizedBox.shrink();
    }

    final tags = reviewSummary!['tags'] as Map<String, dynamic>;
    final satisfaction = reviewSummary!['satisfaction'] as Map<String, dynamic>;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 12),
        const Text('알바 후기', style: AppTextStyles.h3),
        const SizedBox(height: 10),

        // 🔹 태그 시각화
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children:
              tags.entries.take(5).map((entry) {
                return Chip(
                  label: Text('${entry.key} (${entry.value})'),
                  backgroundColor: AppColors.border,
                  labelStyle: const TextStyle(fontSize: 13),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                );
              }).toList(),
        ),

        const SizedBox(height: 16),
        const Text('지원자 만족도', style: TextStyle(fontWeight: FontWeight.w600)),

        const SizedBox(height: 6),
        _buildProgressRow('추천해요', satisfaction['recommend'], AppColors.badgeUrgent),
        const SizedBox(height: 6),
        _buildProgressRow('만족해요', satisfaction['okay'], AppColors.textTertiary),
        const SizedBox(height: 6),
        _buildProgressRow('아쉬워요', satisfaction['bad'], AppColors.textDisabled),
      ],
    );
  }

  Widget _buildProgressRow(String label, int count, Color color) {
    final int total = (reviewSummary?['total'] ?? 0) as int;
    // 0으로 나눔 방지 + [0,1] 클램프
    final double percent = (total > 0) ? (count / total).clamp(0.0, 1.0) : 0.0;

    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label, style: const TextStyle(fontSize: 14)),
        ),
        Expanded(
          child: LinearProgressIndicator(
            value: percent,
            color: color,
            backgroundColor: AppColors.border,
            minHeight: 10,
          ),
        ),
        const SizedBox(width: 8),
        Text('$count명', style: const TextStyle(fontSize: 13)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final postedUtc =
        widget
            .job
            .postedAtUtc; // == widget.job.publishAt ?? widget.job.createdAt
    final postedLabel = widget.job.isScheduled ? '게시 예정' : '게시일';

    return Scaffold(
      backgroundColor: AppColors.bgPage,
      appBar: AppBar(
        title: const Text('공고 상세'),
        centerTitle: false,
        actions: [
          if (_shouldShowReportButton())
            IconButton(
              tooltip: '신고',
              icon: const Icon(
                Icons.flag_outlined,
                color: AppColors.textSecondary,
              ),
              onPressed: () => _showReportDialog(),
            ),
        ],
      ),
      body:
          isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  if (isClosed)
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.22),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.block_rounded,
                            size: 18,
                            color: AppColors.error,
                          ),
                          SizedBox(width: 8),
                          Text(
                            '이 공고는 마감됐어요.',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // 섹션은 화면 끝까지 흰 면, 사이는 8px 회색 띠 (리디자인 2026-10)
                  _buildHeaderCard(postedLabel, postedUtc),
                  const SizedBox(height: 8),
                  _buildJobCoreSection(),
                  if (widget.job.imageUrls.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _ImagesCarousel(
                      imageUrls: widget.job.imageUrls,
                      baseUrl: baseUrl,
                    ),
                  ],
                  if (widget.job.lat != 0 && widget.job.lng != 0) ...[
                    const SizedBox(height: 8),
                    Container(
                      color: AppColors.bgCard,
                      padding: const EdgeInsets.all(20),
                      child: _buildLocationSection(),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _buildStatsSection(),
                  const SizedBox(height: 8),
                  _buildClientSection(),
                  // 면접 준비는 근무 조건을 다 읽은 뒤에 — 설명 바로 아래선 읽는 흐름을 끊었다
                  if (userType == 'worker') ...[
                    const SizedBox(height: 8),
                    _buildInterviewPrepRow(),
                  ],
                  const SizedBox(height: 16),

                  // 🔹 광고 배너 (원더 제휴)
                  const AdBannerWidget(
                    placement: 'app_job_detail',
                    margin: EdgeInsets.symmetric(horizontal: 16),
                  ),
                ],
              ),
      // 구직자: 지원 버튼. 비로그인: 같은 자리에 지원하기 → 가입 후 이 공고로 돌아온다.
      // (예전엔 비로그인이면 버튼이 아예 없어 둘러보던 신규 구직자가 지원할 길이 없었다)
      bottomNavigationBar:
          userType == 'worker'
              ? _buildApplyButton()
              : userType == null && !isLoading
              ? _buildGuestApplyBar()
              : null,
    );
  }

  /// 상단 요약. 급구식 순서: 뱃지 → 제목 → **급여(가장 크게)** → 일정·시간·거리·지원자 줄.
  /// 예전엔 색 아이콘 2×2 타일(JobMetaSection)과 아래 '근무 정보'가 같은 값을 두 번 보여줬다.
  Widget _buildHeaderCard(String postedLabel, DateTime? postedUtc) {
    final job = widget.job;
    final negotiable = isNegotiablePayType(job.payType);
    final hours =
        job.workingHours.replaceAll('~', '').trim().isEmpty
            ? null
            : job.workingHours;
    final badges = <Widget>[
      if (job.isUrgent)
        const JobSignalBadge(
          label: '긴급',
          signal: JobSignal.time,
          icon: Icons.bolt_rounded,
        ),
      if (job.isSameDayPay == true)
        const JobSignalBadge(label: '당일지급', signal: JobSignal.money),
      if (job.isCertifiedCompany)
        const JobSignalBadge(label: '인증업체', signal: JobSignal.trust),
      if (job.category.trim().isNotEmpty) JobSignalBadge(label: job.category),
    ];
    // 목록과 같은 값만 — 예전엔 회사명이 없으면 담당자 실명이 떠서 목록(주소)과 달랐다
    final company = (job.company ?? '').trim();
    final requirements = formatRequirements(job.requiredCerts);

    return Container(
      width: double.infinity,
      color: AppColors.bgCard,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (badges.isNotEmpty) ...[
            Wrap(spacing: 6, runSpacing: 6, children: badges),
            const SizedBox(height: 10),
          ],
          if (company.isNotEmpty) ...[
            Text(
              company,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body2,
            ),
            const SizedBox(height: 4),
          ],
          Text(
            job.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.h2,
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                formatJobPay(job.pay, job.payType),
                style:
                    negotiable
                        ? AppTextStyles.h3.copyWith(
                          color: AppColors.textSecondary,
                        )
                        : AppTextStyles.jobPayDisplay,
              ),
              if (!negotiable && job.payType.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(job.payType, style: AppTextStyles.jobPayUnit),
              ],
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 14),
          _factRow(Icons.calendar_today_outlined, _getWorkingPeriodText(job)),
          if (hours != null) _factRow(Icons.schedule_outlined, hours),
          _factRow(Icons.near_me_outlined, _distanceOrLocationText()),
          // 지원 조건(이수증·검진 등)은 긴 설명 속에 묻혀 지원 뒤에야 알게 됐다 — 지원 버튼 전에 보이게
          if (requirements != null)
            _factRow(Icons.assignment_outlined, '지원 조건 · $requirements'),
          _factRow(Icons.groups_outlined, _applicantSummaryText()),
          const SizedBox(height: 2),
          if (postedUtc != null)
            Text(
              widget.job.isScheduled
                  ? '$postedLabel ${DateFormat('M월 d일 HH:mm').format(postedUtc.toLocal())}'
                  : '${formatPostedAgo(postedUtc)} 등록',
              style: AppTextStyles.caption,
            ),
        ],
      ),
    );
  }

  Widget _factRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJobCoreSection() {
    final isAgency = (widget.job.isAgency == true);
    final description =
        widget.job.description?.trim().isNotEmpty == true
            ? widget.job.description!.trim()
            : isAgency
            ? '상세 설명이 많이 적혀 있지 않아요.\n아래에서 전화로 지원하거나 앱으로 지원할 수 있어요.'
            : '상세 설명이 많이 적혀 있지 않아요.\n궁금한 점은 채팅으로 바로 물어보면 좋아요';

    return Container(
      padding: const EdgeInsets.all(20),
      color: AppColors.bgCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('상세 설명', style: AppTextStyles.h3),
          const SizedBox(height: 10),
          Text(description, style: AppTextStyles.body1.copyWith(height: 1.65)),
        ],
      ),
    );
  }

  Widget _buildInterviewPrepRow() {
    return Container(
      color: AppColors.bgCard,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: InkWell(
              onTap: _openInterviewPrep,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.bgMuted,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.auto_awesome_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'AI로 면접 준비하기',
                        style: AppTextStyles.body2.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: AppColors.textTertiary,
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildStatsSection() {
    final label = _interestLabel(viewCount, bookmarkCount, applicantCount);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('공고 통계', style: AppTextStyles.h3),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                // 누를 수 없는 분류 — 파랑 대신 중립 (CTA Blue 규칙)
                decoration: BoxDecoration(
                  color: AppColors.bgMuted,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ✅ 숫자는 “k 포맷”으로 예쁘게
          Row(
            children: [
              _statItem(
                icon: Icons.remove_red_eye,
                iconColor: AppColors.textTertiary,
                label: '열람',
                valueText: _formatCount(viewCount),
              ),
              _verticalDivider(),
              _statItem(
                icon: Icons.favorite_border_rounded,
                iconColor: AppColors.textTertiary,
                label: '저장',
                valueText: _formatCount(bookmarkCount),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statItem({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String valueText,
    bool emphasize = false,
  }) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: iconColor),
          const SizedBox(height: 4),
          Text(
            valueText,
            style: TextStyle(
              fontSize: emphasize ? 18 : 16,
              fontWeight: emphasize ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _verticalDivider() {
    return Container(
      width: 1,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: AppColors.border,
    );
  }

  Widget _buildLocationSection() {
    final lat = double.tryParse(widget.job.lat.toString()) ?? 0;
    final lng = double.tryParse(widget.job.lng.toString()) ?? 0;
    final address = widget.job.location.toString().trim();

    String stationText() {
      if (_nearStationName == null || _nearStationName!.isEmpty) return '';
      final w = _nearStationWalkMin;
      if (w == null) return '가까운 ${_nearStationName!}';
      return '가까운 ${_nearStationName!}역 도보 $w분';
    }

    final coordText = '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';
    final copyText = address.isNotEmpty ? address : coordText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('근무 위치', style: AppTextStyles.h3),
        const SizedBox(height: 6),
        Text(
          address.isNotEmpty ? address : '위치: $coordText',
          style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),

        // 거리는 맨 위 요약에 이미 있다 — 여기선 거기 없는 '가까운 역'만 (2026-10 평가: 거리 3번 반복)
        if (stationText().isNotEmpty)
          Text(
            stationText(),
            style: AppTextStyles.body2.copyWith(color: AppColors.textPrimary),
          ),

        // 근무지가 여러 곳인 공고. 아래 지도·길찾기·주소복사는 전부 대표 근무지
        // 기준이라, 나머지를 안 보여주면 구직자가 다른 지점으로 갈 수 있다.
        if (widget.job.locations.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '이 공고는 근무지가 ${widget.job.geoPoints.length}곳이에요',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                for (final loc in widget.job.geoPoints)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.place_outlined,
                            size: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            loc.address,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const Text(
                  '어느 지점인지는 사장님과 대화하면서 정해요.',
                  style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 10),

        // ✅ 지도(기존 풀맵 이동 유지)
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder:
                    (_) => FullMapScreen(
                      lat: lat,
                      lng: lng,
                      address: address.isNotEmpty ? address : null,
                    ),
              ),
            );
          },
          child: Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.textDisabled),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: km.KakaoMap(
                    initialPosition: km.LatLng(latitude: lat, longitude: lng),
                    initialLevel: 17,
                  ),
                ),
                const Align(
                  alignment: Alignment.center,
                  child: IgnorePointer(
                    child: Icon(
                      Icons.location_pin,
                      size: 32,
                      color: AppColors.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        // ✅ 액션 버튼들 (길찾기 / 주소복사)
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  side: BorderSide(color: AppColors.textDisabled),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed:
                    () =>
                        _openKakaoDirections(lat, lng, name: widget.job.title),
                icon: const Icon(Icons.directions, size: 18, color: kBrand),
                label: const Text(
                  '길찾기',
                  style: TextStyle(color: kBrand, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  side: BorderSide(color: AppColors.textDisabled),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => _copyAddress(copyText),
                icon: const Icon(
                  Icons.copy_rounded,
                  size: 18,
                  color: AppColors.textPrimary,
                ),
                label: const Text(
                  '주소 복사',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),
        const Text(
          '정확한 위치는 사장님과 대화하면서 한 번 더 확인해보는 게 좋아요',
          style: AppTextStyles.caption,
        ),
      ],
    );
  }

  Widget _buildClientSection() {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap:
          userType == 'worker' && widget.job.clientId != null
              ? () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) =>
                            ClientProfileScreen(clientId: widget.job.clientId!),
                  ),
                );
              }
              : null,
      child: Container(
        decoration: BoxDecoration(color: Colors.white),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ===== 상단 프로필 헤더 =====
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 로고(원형 테두리)
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.border, width: 2),
                  ),
                  child: CircleAvatar(
                    radius: 26,
                    backgroundColor: AppColors.bgMuted,
                    backgroundImage:
                        clientProfile != null &&
                                clientProfile!['logo_url'] != null
                            ? NetworkImage(clientProfile!['logo_url'])
                            : null,
                    child:
                        (clientProfile == null ||
                                clientProfile!['logo_url'] == null)
                            ? const Icon(
                              Icons.business,
                              color: AppColors.textTertiary,
                            )
                            : null,
                  ),
                ),
                const SizedBox(width: 14),
                // 회사명/설명/배지
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 회사명
                      Text(
                        _getCompanyName(),
                        style: AppTextStyles.h3,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      // 배지 + 설명 한 줄
                      Row(
                        children: [
                          if (widget.job.isCertifiedCompany == true) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 0,
                              ),
                              child: const JobSignalBadge(
                                label: '인증업체',
                                signal: JobSignal.trust,
                                icon: Icons.verified,
                                pill: true,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Text(
                              clientProfile?['description'] ??
                                  widget.job.locationCity,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // 액션 (워커만)
                if (userType == 'worker') ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.bgPage,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.textDisabled),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Text(
                          '사업자 정보',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(width: 6),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 12,
                          color: AppColors.textTertiary,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 16),
            const Divider(height: 1),

            // 이 회사의 다른 공고. 예전 '등록한 공고 0 · 채용 확정 0' 타일은 서버가 숫자를 안 줘 늘 0이었다
            if (((clientProfile?['job_count'] as num?) ?? 0) > 1 &&
                userType == 'worker' &&
                widget.job.clientId != null) ...[
              const SizedBox(height: 4),
              InkWell(
                onTap:
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (_) => ClientJobListScreen(
                              clientId: widget.job.clientId!,
                            ),
                      ),
                    ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Text(
                        '이 회사 공고 ${clientProfile!['job_count']}개 보기',
                        style: AppTextStyles.body1.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.textTertiary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            // 리뷰 요약 섹션 (후기 없으면 구분선까지 숨김)
            _buildReviewSummary(),
          ],
        ),
      ),
    );
  }
}

class _ImagesCarousel extends StatelessWidget {
  final List<String> imageUrls;
  final String baseUrl;

  const _ImagesCarousel({required this.imageUrls, required this.baseUrl});

  @override
  Widget build(BuildContext context) {
    final normalizedUrls =
        imageUrls.map((u) => u.startsWith('http') ? u : '$baseUrl$u').toList();

    return SizedBox(
      height: 200,
      child: PageView.builder(
        itemCount: normalizedUrls.length,
        itemBuilder: (context, index) {
          final fullUrl = normalizedUrls[index];
          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (_) => FullImageGalleryScreen(
                        urls: normalizedUrls,
                        initialIndex: index,
                      ),
                ),
              );
            },
            child: Container(
              width: double.infinity,
              height: 200,
              decoration: BoxDecoration(
                color: AppColors.border,
                image: DecorationImage(
                  image: NetworkImage(fullUrl),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class MapWithSafeMarker extends StatefulWidget {
  final double lat, lng;
  const MapWithSafeMarker({super.key, required this.lat, required this.lng});
  @override
  State<MapWithSafeMarker> createState() => _MapWithSafeMarkerState();
}

class _MapWithSafeMarkerState extends State<MapWithSafeMarker> {
  km.KakaoMapController? _c;
  bool _done = false;

  Future<void> _place() async {
    if (_c == null || _done) return;

    // 1) 프레임이 실제로 붙을 때까지 대기
    await Future<void>.delayed(const Duration(milliseconds: 50));
    // 사이즈 0이면 또 대기
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.height < 10) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    final pos = km.LatLng(latitude: widget.lat, longitude: widget.lng);

    // setPoiVisible은 실패해도 무시 — 루프 밖에서 단 1회 호출
    try {
      await _c!.setPoiVisible(isVisible: true);
    } catch (_) {}

    // 2) 최대 10회, 100ms 간격 재시도
    Exception? last;
    for (var i = 0; i < 10; i++) {
      try {
        await _c!.moveCamera(
          cameraUpdate: km.CameraUpdate.fromLatLng(pos),
          animation: const km.CameraAnimation(
            duration: 200,
            autoElevation: true,
            isConsecutive: false,
          ),
        );

        await _c!.addMarker(
          markerOption: km.MarkerOption(id: 'one_pin', latLng: pos),
        );

        // (시각 확인용) 인포윈도우
        await _c!.addInfoWindow(
          infoWindowOption: km.InfoWindowOption(
            id: 'iw_one_pin',
            latLng: pos,
            title: '여기',
          ),
        );

        _done = true;
        return;
      } catch (e) {
        last = e is Exception ? e : Exception(e.toString());
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    debugPrint('[KAKAO] still failing: $last');
  }

  @override
  Widget build(BuildContext context) {
    final pos = km.LatLng(latitude: widget.lat, longitude: widget.lng);
    return SizedBox(
      height: 200, // 0이 아니게 확실히 고정
      child: km.KakaoMap(
        initialPosition: pos,
        initialLevel: 17,
        onMapCreated: (c) {
          _c = c;
          WidgetsBinding.instance.addPostFrameCallback((_) => _place());
        },
      ),
    );
  }
}
