import 'dart:convert';
import 'package:flutter/material.dart';
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
import 'job_meta_section.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/services.dart'; // Clipboard
import 'package:url_launcher/url_launcher.dart';
import 'package:iljujob/data/services/log_service.dart';
import 'ai_interview_prep_sheet.dart';

const kBrand = Color(0xFF3B8AFF);
class JobDetailScreen extends StatefulWidget {
  final Job job;

  const JobDetailScreen({super.key, required this.job});

  @override
  State<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> {
  SuspensionState? _suspension; // /me에서 가져온 정지 상태
  bool hasApplied = false;
  int applicantCount = 0;
  int viewCount = 0;
  int bookmarkCount = 0;
  bool isLoading = true;
  Map<String, dynamic>? clientProfile;
  String? userType;
  int? myUserId;
  bool isBlocked = false;
  final int _currentImage = 0;
  final PageController _pageController = PageController();
double? _distanceMeters;
String? _nearStationName;
int? _nearStationWalkMin;
bool _locContextLoading = false;

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
    if ((job.weekdays != null && job.weekdays!.trim().isNotEmpty)) {
      return job.weekdays!;
    }

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
    _loadUserType();
    _checkAlreadyApplied();
    _initializePage();
    _incrementViewCount();
    _loadReviewSummary();
    _checkBlockStatus();

    _loadSuspension(); // ← 추가: 정지 상태 로드
    _loadLocationContext(); 
final jobId = int.tryParse(widget.job.id.toString());
  if (jobId != null) {
  LogService.instance.logEvent(
  eventType: LogService.view,   // ← view 로 수정
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

List<String> _jobKeywords(Job job) {
  final k = <String>[];
  if ((job.category).trim().isNotEmpty) k.add(job.category.trim());
  if (job.isSameDayPay == true) k.add('당일지급');
  if ((job.payType).trim().isNotEmpty) k.add(job.payType.trim());
  final hours = (job.workingHours).trim();
  if (hours.isNotEmpty) k.add(hours);
  final period = _getWorkingPeriodText(job).trim();
  if (period.isNotEmpty && period != '근무 기간 미정') k.add(period);

  // 너무 길면 정리
  return k.take(6).toList();
}
  @override
  void dispose() {
    _pageController.dispose(); // 여기서만 dispose
    super.dispose();
  }

  String _getCompanyName() {
    if (clientProfile != null) {
      final name = clientProfile!['company_name'];
      if (name != null && name.toString().trim().isNotEmpty) return name;
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

  setState(() => _locContextLoading = true);

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
    if (mounted) setState(() => _locContextLoading = false);
  }
}
Future<void> _copyAddress(String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  _showSnack('주소가 복사됐어요');
}

Future<void> _openKakaoDirections(double lat, double lng, {String name = '근무지'}) async {
  // 앱 스킴 -> 실패하면 웹 fallback
  final app = Uri.parse('kakaomap://look?p=$lat,$lng');
  final web = Uri.parse('https://map.kakao.com/link/map/$name,$lat,$lng');
  if (await canLaunchUrl(app)) {
    await launchUrl(app);
  } else {
    await launchUrl(web, mode: LaunchMode.externalApplication);
  }
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
      final response = await http.post(
        Uri.parse('$baseUrl/api/job/check-applied'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'workerId': userId, 'jobId': jobId}),
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
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final url = Uri.parse(
        '$baseUrl/api/client/profile?id=${widget.job.clientId}',
      );
      final res = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
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
Future<bool> _showChatMoveNoticeDialog() async {
  if (!mounted) return false;

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent, // 바깥은 투명
    builder: (context) {
      return SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 상단 그립바
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D5DB),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 아이콘 + 타이틀
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: kBrand.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: kBrand,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      '지원이 완료되었어요!',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Jalnan2TTF',
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // 본문 텍스트
              const Text(
                '이 공고에 대한 채팅방이 열렸어요.\n'
                '사장님과 바로 대화하면서 급여, 근무 조건,\n'
                '위치 등을 한 번 더 확인해보는 걸 추천해요 🙂',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: Color(0xFF444444),
                ),
              ),

              const SizedBox(height: 18),

              // 라벨/뱃지 느낌 한 줄
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE7F0FF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(
                      Icons.flash_on_rounded,
                      size: 16,
                      color: kBrand,
                    ),
                    SizedBox(width: 6),
                    Text(
                      '빠른 응답일수록 채용 가능성이 커져요',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: kBrand,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 버튼 두 개
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        side: BorderSide(color: const Color(0xFFD1D5DB)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop(false);
                      },
                      child: const Text(
                        '나중에 보기',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF191F28),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kBrand,
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () {
                        Navigator.of(context).pop(true);
                      },
                      child: const Text(
                        '채팅방으로 이동',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
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
      );
    },
  );

  return result ?? false;
}

  Future<void> _applyToJob() async {
    // 0) 정지(차단) 가드: _suspension이 없다면 기본값(정상)으로 판단
    final s =
        _suspension ??
        const SuspensionState(
          suspendedType: null,
          suspendedUntil: null,
          suspendedReason: null,
        );
    if (!guardSuspended(context, s)) return; // 정지면 토스트 띄우고 중단

    // 1) 기본 검증
    final prefs = await SharedPreferences.getInstance();
    final workerId = prefs.getInt('userId');
    final clientId = widget.job.clientId;
    final String jobId = widget.job.id.toString();

    if (workerId == null || clientId == null || jobId.isEmpty) {
      _showSnack('❗ 로그인 또는 채용공고 정보가 올바르지 않습니다.');
      return;
    }

    // 2) 요청
    final applyUrl = Uri.parse('$baseUrl/api/job/apply');

    try {
      final response = await http.post(
        applyUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'workerId': workerId,
          'jobId': widget.job.id, // int로 직접 전달
        }),
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
        _showSnack('❌ $msg');
        return;
      }

      // 2-2) 정상 처리
     if (response.statusCode == 200) {
  _showSnack('✅ 지원 완료');

  // ✅ apply 로그 추가
final jobIdInt = int.tryParse(widget.job.id.toString());
if (jobIdInt != null) {
 LogService.instance.logEvent(
  eventType: LogService.apply,  // ← apply 로 수정
  jobId: jobIdInt,
);
}

  await _fetchApplicantCount();
  setState(() => hasApplied = true);

        final roomId = await startChatRoom(workerId, jobId, clientId);
        if (roomId != null) {
          // ✅ 채팅방 이동 안내 다이얼로그 먼저 띄우기
          final goToChat = await _showChatMoveNoticeDialog();
          if (!goToChat) {
            // 사용자가 "나중에 보기"를 눌렀을 때: 여기서 끝, 화면 유지
            return;
          }

          if (!mounted) return;

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatRoomScreen(
                chatRoomId: roomId,
                jobInfo: {
                  'title': widget.job.title,
                  'pay': widget.job.pay,
                  'posted_at':
                      widget.job.postedAtUtc?.toUtc().toIso8601String() ?? '',
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
          _showSnack('❌ 채팅방 생성 실패');
        }
      } else if (response.statusCode == 409) {
        _showSnack('⚠️ 이미 지원했습니다');
        setState(() => hasApplied = true);
      } else {
        _showSnack('❌ 오류 발생: ${response.body}');
      }
    } catch (e) {
      print('❌ 지원 중 예외: $e');
      _showSnack('❌ 네트워크 오류가 발생했습니다');
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

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/report/job'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'jobId': jobId,
          'userId': userId,
          'userPhone': userPhone,
          'reasonCategory': category,
          'reasonDetail': detail,
        }),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('신고가 접수되었습니다. 신고 내용은 24시간 이내 조치됩니다.')),
        );
      } else {
        _showSnack('신고 전송 실패: ${response.body}');
      }
    } catch (e) {
      print('❌ 예외 발생: $e');
      _showSnack('신고 중 오류가 발생했습니다.');
    }
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade700),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
      ],
    );
  }

  Widget _buildApplyButton() {
  if (isLoading) return const SizedBox();

  // ✅ 대행공고 여부 (null-safe)
  final isAgency = (widget.job.isAgency == true);

  // ✅ 대행공고는 채팅/지원 기능을 막고, 전화/이메일만 노출
  if (isAgency) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: _AgencyApplyBar(
          phone: widget.job.agencyPhone,
          email: widget.job.agencyEmail,
          note: widget.job.agencyNote,
          onSnack: _showSnack,
        ),
      ),
    );
  }

  // ---- 기존 로직(일반 공고) 유지 ----
  final isSuspended = _suspension?.isSuspended ?? false;
  final isButtonDisabled = hasApplied || isClosed || isBlocked || isSuspended;

  return SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          // AI 면접 준비 버튼
          SizedBox(
            height: 50,
            child: OutlinedButton(
              onPressed: () {
                final payInt = int.tryParse(
                        widget.job.pay.replaceAll(RegExp(r'[^0-9]'), '')) ??
                    0;
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  useSafeArea: true,
                  builder: (_) => AiInterviewPrepSheet(
                    jobTitle: widget.job.title,
                    category: widget.job.category,
                    location: widget.job.location,
                    payType: widget.job.payType,
                    pay: payInt,
                  ),
                );
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                side: const BorderSide(color: Color(0xFF3B8AFF)),
                foregroundColor: const Color(0xFF3B8AFF),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.auto_awesome_rounded, size: 18),
                  SizedBox(height: 2),
                  Text('면접 준비', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          // 지원하기 버튼
          Expanded(
            child: SizedBox(
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isButtonDisabled ? Colors.grey : kBrand,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                onPressed: isButtonDisabled ? null : _applyToJob,
                child: Text(
                  isClosed
                      ? '마감된 공고'
                      : hasApplied
                          ? '지원 완료'
                          : isBlocked
                              ? '차단된 기업'
                              : isSuspended
                                  ? '정지된 계정'
                                  : '지원하기',
                  style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
        ],
      ),
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
                    _showSnack('로그인 정보 또는 공고 정보가 올바르지 않습니다.');
                  }
                },
                child: const Text('신고하기'),
              ),
            ],
          ),
    );
  }

  Widget _buildReviewSummary() {
    if (reviewSummary == null) return const SizedBox();

    final tags = reviewSummary!['tags'] as Map<String, dynamic>;
    final satisfaction = reviewSummary!['satisfaction'] as Map<String, dynamic>;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '알바 후기',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const SizedBox(height: 10),

        // 🔹 태그 시각화
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children:
              tags.entries.take(5).map((entry) {
                return Chip(
                  label: Text('${entry.key} (${entry.value})'),
                  backgroundColor: const Color(0xFFE5E8EB),
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
        _buildProgressRow('추천해요', satisfaction['recommend'], Colors.orange),
        const SizedBox(height: 6),
        _buildProgressRow('만족해요', satisfaction['okay'], Colors.grey),
        const SizedBox(height: 6),
        _buildProgressRow('아쉬워요', satisfaction['bad'], Colors.grey[400]!),
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
            backgroundColor: Colors.grey[200],
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
      widget.job.postedAtUtc; // == widget.job.publishAt ?? widget.job.createdAt
  final postedLabel = widget.job.isScheduled ? '게시 예정' : '게시일';

  return Scaffold(
    backgroundColor: const Color(0xFFF4F6FA),
    appBar: AppBar(
      backgroundColor: Colors.white,
      elevation: 0.5,
      title: const Text(
        '공고 상세',
        style: TextStyle(
          fontFamily: "Jalnan2TTF",
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: kBrand,
        ),
      ),
      centerTitle: false,
      actions: [
        if (_shouldShowReportButton())
          IconButton(
            icon: const Icon(Icons.report, color: Colors.red),
            onPressed: () => _showReportDialog(),
          ),
      ],
    ),
    body: isLoading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              if (isClosed)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: const Text(
                    '⛔ 이 공고는 마감되었습니다.',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

              // 🔹 이미지 캐러셀 (이미 _ImagesCarousel 존재하니까 이걸 활용)
              if (widget.job.imageUrls.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _ImagesCarousel(
                    imageUrls: widget.job.imageUrls,
                    baseUrl: baseUrl,
                  ),
                ),

              const SizedBox(height: 12),

              // 🔹 상단 헤더 카드 (카테고리, 제목, 요약)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildHeaderCard(postedLabel, postedUtc),
              ),

              const SizedBox(height: 16),
  // 🔹 위치 섹션
              if (widget.job.lat != 0 && widget.job.lng != 0)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: _buildLocationSection(),
                ),

              const SizedBox(height: 16),
              // 🔹 근무 정보 + 설명
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildJobCoreSection(),
              ),

              const SizedBox(height: 16),

              // 🔹 조회수/북마크/지원자 통계
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildStatsSection(),
              ),

              const SizedBox(height: 16),

            

              // 🔹 기업 카드 + 리뷰 요약
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildClientSection(),
              ),
            ],
          ),
bottomNavigationBar: userType == 'worker' ? _buildApplyButton() : null,
  );
}
Widget _buildHeaderCard(String postedLabel, DateTime? postedUtc) {
  final pay = NumberFormat('#,###').format(
    int.tryParse(widget.job.pay) ?? 0,
  );
  final periodText = _getWorkingPeriodText(widget.job);

  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.03),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 🔹 상단 작은 라벨들
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE7F0FF),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                '내 근처 단기 알바',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF3B8AFF),
                ),
              ),
            ),
            const Spacer(),
            if (widget.job.isSameDayPay == true)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  '당일지급',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),

        // 🔹 카테고리 + 제목
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE5E8EB),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                widget.job.category,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.job.title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w200,
                  fontFamily: 'Jalnan2TTF',
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        // 🔹 여기 안에 2x2 메타 카드 네 개 넣기
        JobMetaSection(job: widget.job),

        const SizedBox(height: 8),

        // 🔹 게시일
        Row(
          children: [
            Text(
              postedLabel,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              postedUtc != null
                  ? DateFormat('yyyy-MM-dd HH:mm')
                      .format(postedUtc.toLocal())
                  : '-',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}


Widget _infoChip(String text) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFFF4F6FA),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: Color(0xFF263144),
      ),
    ),
  );
}
Widget _buildJobCoreSection() {
  final isAgency = (widget.job.isAgency == true);
final description =
    widget.job.description?.trim().isNotEmpty == true
        ? widget.job.description!.trim()
        : isAgency
            ? '상세 설명이 많이 적혀 있지 않아요.\n지원은 아래 “전화/이메일” 버튼으로 진행해주세요.'
            : '상세 설명이 많이 적혀 있지 않아요.\n궁금한 점은 채팅으로 바로 물어보면 좋아요 👀';

  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE5E8EB)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '근무 정보',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 12),
        _infoRow(
          Icons.monetization_on,
          '${NumberFormat('#,###').format(int.tryParse(widget.job.pay) ?? 0)}원 (${widget.job.payType})',
        ),
        const SizedBox(height: 8),
        _infoRow(Icons.calendar_today, _getWorkingPeriodText(widget.job)),
        const SizedBox(height: 8),
        _infoRow(Icons.access_time, widget.job.workingHours),
        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 12),
        const Text(
          '상세 설명',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          description,
          style: const TextStyle(
            fontSize: 14,
            height: 1.6,
          ),
        ),
      ],
    ),
  );
}
Widget _buildStatsSection() {
  final label = _interestLabel(viewCount, bookmarkCount, applicantCount);
  final keywords = _jobKeywords(widget.job);

  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE5E8EB)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '공고 통계',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFE7F0FF),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: kBrand,
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
              iconColor: Colors.grey,
              label: '열람',
              valueText: _formatCount(viewCount),
            ),
            _verticalDivider(),
            _statItem(
              icon: Icons.favorite,
              iconColor: Colors.red,
              label: '저장',
              valueText: _formatCount(bookmarkCount),
            ),
            _verticalDivider(),
            _statItem(
              icon: Icons.group,
              iconColor: const Color(0xFF3B8AFF),
              label: '지원',
              valueText: _formatCount(applicantCount),
              emphasize: true,
            ),
          ],
        ),

        const SizedBox(height: 12),

        // ✅ “낮은 수치”를 숫자 말고 ‘키워드’로 보강
        if (keywords.isNotEmpty) ...[
          Row(
            children: const [
              Icon(Icons.local_offer_outlined, size: 16, color: Color(0xFF6B7280)),
              SizedBox(width: 6),
              Text(
                '이 공고 키워드',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF374151)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: keywords.map((t) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F6FA),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFE5E8EB)),
                ),
                child: Text(
                  t,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF263144)),
                ),
              );
            }).toList(),
          ),
        ],
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
          style: TextStyle(fontSize: 11, color: const Color(0xFF6B7280)),
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
    color: const Color(0xFFE5E8EB),
  );
}
Widget _buildLocationSection() {
  final lat = double.tryParse(widget.job.lat.toString()) ?? 0;
  final lng = double.tryParse(widget.job.lng.toString()) ?? 0;
  final address = widget.job.location.toString().trim();

  String distanceText() {
    final m = _distanceMeters;
    if (m == null) return '';
    if (m >= 1000) return '내 위치에서 ${(m / 1000).toStringAsFixed(1)}km';
    return '내 위치에서 ${m.toStringAsFixed(0)}m';
  }

  String stationText() {
    if (_nearStationName == null || _nearStationName!.isEmpty) return '';
    final w = _nearStationWalkMin;
    if (w == null) return '가까운 ${_nearStationName!}';
    return '가까운 ${_nearStationName!}역 도보 $w분';
  }

  final coordText = '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';
  final copyText = (address.isNotEmpty ?? false) ? address : coordText;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        '근무 위치',
        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
      ),
      const SizedBox(height: 6),
      const Text(
        '정확한 위치는 사장님과 대화하면서 한 번 더 확인해보는 게 좋아요 😊',
        style: TextStyle(fontSize: 11, color: Colors.grey),
      ),
      const SizedBox(height: 10),

      // ✅ 맥락 바 (역/거리)
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E8EB)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: kBrand.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.place_outlined, color: kBrand, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stationText().isNotEmpty ? stationText() : '근무지 위치 정보',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    distanceText().isNotEmpty ? distanceText() : ' ',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                  ),
                ],
              ),
            ),
            if (_locContextLoading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
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
                side: BorderSide(color: const Color(0xFFD1D5DB)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => _openKakaoDirections(lat, lng, name: widget.job.title),
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
                side: BorderSide(color: const Color(0xFFD1D5DB)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => _copyAddress(copyText),
              icon: const Icon(Icons.copy_rounded, size: 18, color: Color(0xFF191F28)),
              label: const Text(
                '주소 복사',
                style: TextStyle(color: Color(0xFF191F28), fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),

      const SizedBox(height: 10),

      // ✅ 지도(기존 풀맵 이동 유지)
      GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FullMapScreen(
                lat: lat,
                lng: lng,
                address: (address.isNotEmpty ?? false) ? address : null,
              ),
            ),
          );
        },
        child: Container(
          height: 200,
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFD1D5DB)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: km.KakaoMap(
                  initialPosition: km.LatLng(latitude: lat, longitude: lng),
                  initialLevel: 17,
                  onMapCreated: (c) async {
                    final pos = km.LatLng(latitude: lat, longitude: lng);
                    await c.moveCamera(
                      cameraUpdate: km.CameraUpdate.fromLatLng(pos),
                      animation: const km.CameraAnimation(
                        duration: 300,
                        autoElevation: true,
                        isConsecutive: false,
                      ),
                    );
                  },
                ),
              ),
              const Align(
                alignment: Alignment.center,
                child: IgnorePointer(
                  child: Icon(Icons.location_pin, size: 32, color: Colors.red),
                ),
              ),
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.place, size: 16, color: Colors.grey),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          (address.isNotEmpty ?? false) ? address : '위치: $coordText',
                          style: const TextStyle(fontSize: 13, color: Color(0xFF191F28)),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}
Widget _buildClientSection() {
  return InkWell(
    borderRadius: BorderRadius.circular(16),
    onTap: userType == 'worker' && widget.job.clientId != null
        ? () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    ClientProfileScreen(clientId: widget.job.clientId!),
              ),
            );
          }
        : null,
    child: Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E8EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
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
                  border: Border.all(
                    color: const Color(0xFFE5E8EB),
                    width: 2,
                  ),
                ),
                child: CircleAvatar(
                  radius: 26,
                  backgroundImage: clientProfile != null &&
                          clientProfile!['logo_url'] != null
                      ? NetworkImage(clientProfile!['logo_url'])
                      : null,
                  child: (clientProfile == null ||
                          clientProfile!['logo_url'] == null)
                      ? const Icon(
                          Icons.business,
                          color: Colors.grey,
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
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
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
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(
                                  Icons.verified,
                                  size: 14,
                                  color: Colors.green,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  '안심기업',
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
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
                              color: Colors.grey,
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
                    color: const Color(0xFFF4F6FA),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: const Color(0xFFD1D5DB),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text(
                        '사업자 정보',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF191F28),
                        ),
                      ),
                      SizedBox(width: 6),
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 12,
                        color: Colors.grey,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 16),
          const Divider(height: 1),

          // ===== 하단 통계 카드 2개 =====
          const SizedBox(height: 12),
          Row(
            children: [
              // 등록한 공고
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFE5E8EB),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      if (userType == 'worker' && widget.job.clientId != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ClientJobListScreen(
                              clientId: widget.job.clientId!,
                            ),
                          ),
                        );
                      }
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF5FF),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.assignment_outlined,
                            size: 24,
                            color: Color(0xFF3B8AFF),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '${clientProfile?['job_count'] ?? 0}',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '등록한 공고',
                          style: TextStyle(
                            fontSize: 12,
                            color: const Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // 채용 확정
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFE5E8EB),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_circle_outline,
                          size: 24,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${clientProfile?['hire_count'] ?? 0}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '채용 확정',
                        style: TextStyle(
                          fontSize: 12,
                          color: const Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Divider(height: 1),

          // 리뷰 요약 섹션
          const SizedBox(height: 12),
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

  const _ImagesCarousel({
    super.key,
    required this.imageUrls,
    required this.baseUrl,
  });

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
                color: const Color(0xFFE5E8EB),
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
    try { await _c!.setPoiVisible(isVisible: true); } catch (_) {}

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

class _AgencyApplyBar extends StatelessWidget {
  final String? phone;
  final String? email;
  final String? note;
  final void Function(String msg) onSnack;

  const _AgencyApplyBar({
    required this.phone,
    required this.email,
    required this.note,
    required this.onSnack,
  });

  bool get _hasPhone => (phone != null && phone!.trim().isNotEmpty);
  bool get _hasEmail => (email != null && email!.trim().isNotEmpty);

  Future<void> _callPhone() async {
    final p = phone!.trim().replaceAll(' ', '');
    final uri = Uri.parse('tel:$p');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      onSnack('전화 앱을 열 수 없어요');
    }
  }

  Future<void> _sendEmail() async {
    final e = email!.trim();
    final uri = Uri.parse('mailto:$e');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      onSnack('이메일 앱을 열 수 없어요');
    }
  }

 @override
Widget build(BuildContext context) {
  final defaultNote =
      '이 공고는 알바일주 공식계정이 대행 등록한 공고입니다.\n'
      '지원은 아래 연락처로 진행해주세요.\n\n'
      '연락하실 때 “알바일주 보고 연락드렸어요” 한마디만 부탁드려요 🙂';

  final safeNote = (note != null && note!.trim().isNotEmpty)
      ? note!.trim()
      : defaultNote;

  return Container(
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: const Color(0xFFE5E8EB))),
    ),
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 안내문
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: kBrand.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.campaign_outlined, color: kBrand, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                safeNote,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: Color(0xFF374151),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),

        // 버튼 두 개(가능한 것만)
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  side: BorderSide(color: const Color(0xFFD1D5DB)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _hasPhone ? _callPhone : null,
                icon: Icon(
                  Icons.call,
                  size: 18,
                  color: _hasPhone ? kBrand : const Color(0xFFBCC0CB),
                ),
                label: Text(
                  _hasPhone ? '전화로 지원' : '전화 정보 없음',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: _hasPhone ? const Color(0xFF111827) : const Color(0xFF9CA3AF),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _hasEmail ? kBrand : const Color(0xFFD1D5DB),
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: _hasEmail ? _sendEmail : null,
                icon: Icon(
                  Icons.email_outlined,
                  size: 18,
                  color: _hasEmail ? Colors.white : const Color(0xFF9CA3AF),
                ),
                label: Text(
                  _hasEmail ? '이메일 지원' : '이메일 없음',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: _hasEmail ? Colors.white : const Color(0xFF6B7280),
                  ),
                ),
              ),
            ),
          ],
        ),

        // 연락처 표시(투명하게)
        const SizedBox(height: 8),
        if (_hasPhone || _hasEmail)
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (_hasPhone) _miniChip('전화', phone!.trim()),
              if (_hasEmail) _miniChip('이메일', email!.trim()),
            ],
          ),
      ],
    ),
  );
}

static Widget _miniChip(String k, String v) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFFF4F6FA),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: const Color(0xFFE5E7EB)),
    ),
    child: Text(
      '$k: $v',
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: Color(0xFF374151),
      ),
    ),
  );
}
}
