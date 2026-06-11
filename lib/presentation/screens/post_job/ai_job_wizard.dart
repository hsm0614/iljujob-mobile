// AI 위자드 — 완전 자동화 버전
// Q1:업종(대→소) → Q2:근무지 → Q3:날짜 → Q4:시간 → Q5:시급
// 완료 시 Gemini로 제목+공고문 동시 생성 → 미리보기 바로 연결

import 'package:flutter/material.dart';
import 'package:iljujob/config/app_theme.dart';
import 'package:intl/intl.dart';
import 'package:kpostal/kpostal.dart';
import 'package:geocoding/geocoding.dart';
import '../../../data/services/ai_job_description_service.dart';
import 'package:iljujob/presentation/screens/post_job/job_preview_detail_screen.dart';

const _blue = AppColors.primary;
const _bg = AppColors.bgPage;
const _border = AppColors.border;
const _text = AppColors.textPrimary;
const _label = AppColors.textTertiary;
const _sub = AppColors.textSecondary;

// ════════════════════════════════════════════════════════
//  업종 데이터 (post_job_form과 동일)
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

// ════════════════════════════════════════════════════════
//  업종별 톤 자동 결정
// ════════════════════════════════════════════════════════
String _toneForCategory(String majorName) {
  switch (majorName) {
    case '음식점·카페':
    case '편의점·마트':
    case '서비스·판매':
    case '이벤트·행사':
      return 'friendly'; // 친근하고 따뜻하게
    case '사무·행정':
      return 'professional'; // 격식있게
    case '건설·현장':
    case '물류·배송':
    case '제조·공장':
      return 'casual'; // 간결하고 실용적으로
    default:
      return 'friendly';
  }
}

// ════════════════════════════════════════════════════════
//  제목용 지역 추출 (구/시 단위만, 상세주소 제외)
// ════════════════════════════════════════════════════════
String _extractShortCity(String fullAddress) {
  final parts = fullAddress.trim().split(' ');
  if (parts.isEmpty) return '';

  final first = parts[0];
  // 특별시/광역시 → "서울", "부산" 등
  if (first.contains('특별시')) return first.replaceAll('특별시', '');
  if (first.contains('광역시')) return first.replaceAll('광역시', '');

  // 도 단위 → "경기 수원시" 처럼 도+시 조합
  if (first.endsWith('도') && parts.length > 1) {
    final city = parts[1];
    // 시/군/구 단위까지만
    if (city.endsWith('시') || city.endsWith('군')) return city;
    return city;
  }

  return first;
}

// ════════════════════════════════════════════════════════
//  결과 모델
// ════════════════════════════════════════════════════════
class AiWizardResult {
  final String title;
  final String category;
  final String location;
  final String locationCity;
  final double lat;
  final double lng;
  final DateTime startDate;
  final DateTime endDate;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final int pay;
  final String payType;
  final String description;

  const AiWizardResult({
    required this.title,
    required this.category,
    required this.location,
    required this.locationCity,
    required this.lat,
    required this.lng,
    required this.startDate,
    required this.endDate,
    required this.startTime,
    required this.endTime,
    required this.pay,
    required this.payType,
    required this.description,
  });
}

// ════════════════════════════════════════════════════════
//  메인 위젯
// ════════════════════════════════════════════════════════
class AiJobWizard extends StatefulWidget {
  final void Function(AiWizardResult) onComplete;
  final VoidCallback onSkip;
  final String? companyName;
  final String? managerName;
  final String? managerPhone;

  const AiJobWizard({
    super.key,
    required this.onComplete,
    required this.onSkip,
    this.companyName,
    this.managerName,
    this.managerPhone,
  });

  @override
  State<AiJobWizard> createState() => _AiJobWizardState();
}

class _AiJobWizardState extends State<AiJobWizard>
    with TickerProviderStateMixin {
  // Q0:업종 Q1:근무지 Q2:날짜 Q3:시간 Q4:시급 (총 5단계)
  int _q = 0;
  static const _totalQ = 5;

  // ── 입력값 ──
  String _majorCat = ''; // 대분류 펼침
  String _category = ''; // 소분류 (선택 완료)
  String? _location;
  String _locationCity = '';
  double? _lat, _lng;
  DateTime? _startDate;
  int? _workHours;
  int? _hourlyWage;
  bool _customHours = false;
  bool _customWage = false;

  // ── 생성 상태 ──
  bool _isGenerating = false;
  String? _generateError;

  // ── 컨트롤러 ──
  final _hoursCtrl = TextEditingController();
  final _wageCtrl = TextEditingController();

  // ── 애니메이션 ──
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  static const _qTitles = [
    '어떤 일인가요?',
    '근무지가 어디인가요?',
    '언제 시작하나요?',
    '하루 몇 시간 일하나요?',
    '시급은 얼마인가요?',
  ];
  static const _qSubs = [
    '업종을 선택하면 제목까지 자동으로 완성돼요',
    '근무지 주소를 검색해주세요',
    '시작일을 선택해주세요',
    '하루 근무 시간을 알려주세요',
    '최저시급 10,320원 이상이어야 해요',
  ];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _hoursCtrl.dispose();
    _wageCtrl.dispose();
    super.dispose();
  }

  Future<void> _nextQ() async {
    await _fadeCtrl.reverse();
    setState(() {
      _q++;
      _customHours = false;
      _customWage = false;
    });
    _fadeCtrl.forward();
  }

  Future<void> _prevQ() async {
    if (_q == 0) {
      widget.onSkip();
      return;
    }
    await _fadeCtrl.reverse();
    setState(() => _q--);
    _fadeCtrl.forward();
  }

  // ════════════════════════════════════════════════════════
  //  완료: 제목 + 공고문 동시 생성 → 미리보기 바로 연결
  // ════════════════════════════════════════════════════════
  Future<void> _onComplete() async {
    final hours = _workHours ?? 8;
    final wage = _hourlyWage ?? 10320;
    final start = _startDate ?? DateTime.now();
    final pay = (wage * hours).round();
    final endTime = TimeOfDay(hour: (9 + hours) % 24, minute: 0);

    // 업종에서 대분류 찾기
    String majorName = '';
    for (final c in _allCats) {
      if (c.sub.contains(_category)) {
        majorName = c.name;
        break;
      }
    }

    // 제목용 지역 (구/시 단위)
    final shortCity =
        _locationCity.isNotEmpty
            ? _locationCity
            : _extractShortCity(_location ?? '');

    // 업종별 톤 자동 결정
    final tone = _toneForCategory(majorName);

    setState(() {
      _isGenerating = true;
      _generateError = null;
    });

    try {
      // ── 제목 + 공고문 병렬 생성 ──
      final results = await Future.wait([
        _generateTitle(
          category: _category,
          majorName: majorName,
          shortCity: shortCity,
          hours: hours,
          wage: wage,
        ),
        AIJobDescriptionService.generateJobDescription(
          title: '$shortCity $_category 알바', // 임시 제목 (실제 생성 후 교체)
          category: _category,
          location: _location ?? '',
          payType: '일급',
          pay: pay,
          workingTime: '09:00 ~ ${endTime.hour.toString().padLeft(2, '0')}:00',
          companyName: widget.companyName,
          managerName: widget.managerName,
          managerPhone: widget.managerPhone,
          isShortTerm: true,
          tone: tone,
        ),
      ]);

      if (!mounted) return;

      final generatedTitle = results[0];
      final generatedDesc = results[1];

      final result = AiWizardResult(
        title: generatedTitle,
        category: _category,
        location: _location ?? '',
        locationCity: _locationCity,
        lat: _lat ?? 0.0,
        lng: _lng ?? 0.0,
        startDate: start,
        endDate: start,
        startTime: const TimeOfDay(hour: 9, minute: 0),
        endTime: endTime,
        pay: pay,
        payType: '일급',
        description: generatedDesc,
      );

      // 미리보기 화면 바로 연결
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => JobPreviewDetailScreen(
                title: result.title,
                category: result.category,
                location: result.location,
                lat: result.lat,
                lng: result.lng,
                companyName: widget.companyName ?? '',
                managerName: widget.managerName ?? '',
                startDate: result.startDate.toIso8601String().split('T')[0],
                endDate: result.endDate.toIso8601String().split('T')[0],
                weekdays: const [],
                workingTime:
                    '09:00 ~ ${endTime.hour.toString().padLeft(2, '0')}:00',
                payType: result.payType,
                pay: result.pay,
                description: result.description,
                images: const [],
                onSubmit: () {
                  // 데이터를 post_job_form에 채우고
                  int count = 0;
                  Navigator.popUntil(context, (_) => count++ >= 2);
                  widget.onComplete(result); // post_job_form의 onComplete 호출
                },
                onEdit: () {
                  widget.onComplete(result); // onComplete에서 _q=0으로 처리
                },
              ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _generateError = 'AI 생성 실패 — 다시 시도해주세요';
      });
    }
  }

  // ── 제목 자동 생성 ──────────────────────────────────────
  Future<String> _generateTitle({
    required String category,
    required String majorName,
    required String shortCity,
    required int hours,
    required int wage,
  }) async {
    // 기본 제목 패턴으로 생성 (서버 AI는 공고문 전체 생성용이므로 제목은 규칙 기반으로)
    try {
      final patterns = [
        '$shortCity $category 단기 알바',
        '$shortCity $category 구인',
        '$category 단기 알바 ($shortCity)',
      ];
      // 업종 길이에 따라 적절한 패턴 선택
      if (category.length <= 4) return patterns[0];
      if (category.length <= 6) return patterns[1];
      return patterns[2];
    } catch (_) {
      return '$shortCity $category 단기 알바';
    }
  }

  // ════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (_isGenerating) return _buildLoadingScreen();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // ── 헤더 ──
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
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF5FF),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: _blue.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_note_rounded, size: 14, color: _blue),
                        SizedBox(width: 4),
                        Text(
                          '공고 작성 지원',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _blue,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: widget.onSkip,
                    child: const Text(
                      '건너뛰기',
                      style: TextStyle(fontSize: 13, color: _label),
                    ),
                  ),
                ],
              ),
            ),

            // ── 진행 바 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
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

            // ── 질문 타이틀 ──
            FadeTransition(
              opacity: _fadeAnim,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_q + 1} / $_totalQ',
                      style: const TextStyle(
                        fontSize: 12,
                        color: _label,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _qTitles[_q],
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: _text,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _qSubs[_q],
                      style: const TextStyle(fontSize: 14, color: _label),
                    ),
                  ],
                ),
              ),
            ),

            // ── 질문 컨텐츠 ──
            Expanded(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  child: _buildQuestion(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestion() {
    switch (_q) {
      case 0:
        return _buildCategoryQ();
      case 1:
        return _buildLocationQ();
      case 2:
        return _buildDateQ();
      case 3:
        return _buildHoursQ();
      case 4:
        return _buildWageQ();
      default:
        return const SizedBox();
    }
  }

  // ════════════════════════════════════════════════════════
  //  Q0: 업종 — 대분류 그리드 → 소분류 칩 (2단계)
  // ════════════════════════════════════════════════════════
  Widget _buildCategoryQ() {
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
        // 대분류 3열 그리드
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
                return GestureDetector(
                  onTap:
                      () => setState(() => _majorCat = isOpen ? '' : cat.name),
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
                              style: const TextStyle(
                                fontSize: 9,
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
                );
              }).toList(),
        ),

        // 소분류 펼침
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
                                GestureDetector(
                                  onTap: () => setState(() => _majorCat = ''),
                                  child: const Icon(
                                    Icons.close_rounded,
                                    size: 16,
                                    color: _label,
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
                                    return GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _category = s;
                                          _majorCat = '';
                                        });
                                        // 소분류 선택 즉시 다음으로
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

  // ════════════════════════════════════════════════════════
  //  Q1: 근무지
  // ════════════════════════════════════════════════════════
  Widget _buildLocationQ() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
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
                          _locationCity = _extractShortCity(result.address);
                        });
                        try {
                          final locs = await locationFromAddress(
                            result.address,
                          );
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
              color: _location != null ? const Color(0xFFEEF5FF) : _bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _location != null ? _blue : _border),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.place_outlined,
                  size: 22,
                  color: _location != null ? _blue : _label,
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
                          color: _location != null ? _blue : _label,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _location ?? '주소를 검색해주세요',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _location != null ? _text : _label,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: _location != null ? _blue : _label,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (_location != null) _NextBtn(onTap: _nextQ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════
  //  Q2: 날짜
  // ════════════════════════════════════════════════════════
  Widget _buildDateQ() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final fmt = DateFormat('M월 d일 (E)', 'ko_KR');

    final presets = [
      {'label': '오늘', 'date': today},
      {'label': '내일', 'date': today.add(const Duration(days: 1))},
      {'label': '이번 주 토', 'date': _nextWeekday(today, DateTime.saturday)},
      {'label': '이번 주 일', 'date': _nextWeekday(today, DateTime.sunday)},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children:
              presets.map((p) {
                final d = p['date'] as DateTime;
                final sel = _startDate != null && _isSameDay(_startDate!, d);
                return GestureDetector(
                  onTap: () => setState(() => _startDate = d),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: sel ? _blue : _bg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: sel ? _blue : _border,
                        width: sel ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          p['label'] as String,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: sel ? Colors.white : _text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          fmt.format(d),
                          style: TextStyle(
                            fontSize: 11,
                            color: sel ? Colors.white70 : _label,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _startDate ?? today,
              firstDate: today,
              lastDate: today.add(const Duration(days: 365)),
            );
            if (picked != null) setState(() => _startDate = picked);
          },
          child: Container(
            padding: const EdgeInsets.all(14),
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
                Text(
                  _startDate != null ? fmt.format(_startDate!) : '날짜 직접 선택',
                  style: TextStyle(
                    fontSize: 14,
                    color: _startDate != null ? _text : _label,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.chevron_right,
                  color: _startDate != null ? _blue : _label,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (_startDate != null) _NextBtn(onTap: _nextQ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════
  //  Q3: 근무 시간
  // ════════════════════════════════════════════════════════
  Widget _buildHoursQ() {
    final presets = [4, 6, 8];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children:
              presets.map((h) {
                final sel = !_customHours && _workHours == h;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _workHours = h;
                      _customHours = false;
                    });
                    Future.delayed(const Duration(milliseconds: 180), _nextQ);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 18,
                    ),
                    decoration: BoxDecoration(
                      color: sel ? _blue : _bg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: sel ? _blue : _border,
                        width: sel ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '$h시간',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: sel ? Colors.white : _text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '09:00 ~ ${9 + h}:00',
                          style: TextStyle(
                            fontSize: 11,
                            color: sel ? Colors.white70 : _label,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
        ),
        const SizedBox(height: 12),
        _CustomInputToggle(
          active: _customHours,
          onTap: () => setState(() => _customHours = true),
        ),
        if (_customHours) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _hoursCtrl,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(
              hintText: '예) 5',
              suffixText: '시간',
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
            onChanged: (v) => setState(() => _workHours = int.tryParse(v)),
          ),
          const SizedBox(height: 12),
          if (_workHours != null && _workHours! > 0) _NextBtn(onTap: _nextQ),
        ],
      ],
    );
  }

  // ════════════════════════════════════════════════════════
  //  Q4: 시급
  // ════════════════════════════════════════════════════════
  Widget _buildWageQ() {
    const minWage = 10320;
    final fmt = NumberFormat('#,###');
    final hours = _workHours ?? 8;
    final presets = [
      {'wage': minWage, 'label': '최저시급', 'pay': minWage * hours},
      {'wage': 12000, 'label': '평균 수준', 'pay': 12000 * hours},
      {'wage': 15000, 'label': '높은 편', 'pay': 15000 * hours},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 일급 미리보기 안내
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F5FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, size: 15, color: _blue),
              const SizedBox(width: 8),
              Text(
                '$hours시간 기준 일급으로 계산돼요',
                style: const TextStyle(
                  fontSize: 12,
                  color: _blue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),

        Wrap(
          spacing: 10,
          runSpacing: 10,
          children:
              presets.map((p) {
                final sel = !_customWage && _hourlyWage == p['wage'];
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _hourlyWage = p['wage'] as int;
                      _customWage = false;
                    });
                    Future.delayed(
                      const Duration(milliseconds: 180),
                      _onComplete,
                    );
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    decoration: BoxDecoration(
                      color: sel ? _blue : _bg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: sel ? _blue : _border,
                        width: sel ? 2 : 1,
                      ),
                      boxShadow:
                          sel
                              ? [
                                BoxShadow(
                                  color: _blue.withOpacity(0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                              : [],
                    ),
                    child: Column(
                      children: [
                        Text(
                          '일급 ${fmt.format(p['pay'])}원',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: sel ? Colors.white : _text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '시급 ${fmt.format(p['wage'])}원 · ${p['label']}',
                          style: TextStyle(
                            fontSize: 11,
                            color: sel ? Colors.white70 : _label,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
        ),
        const SizedBox(height: 12),
        _CustomInputToggle(
          active: _customWage,
          onTap: () => setState(() => _customWage = true),
        ),
        if (_customWage) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _wageCtrl,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(
              hintText: '예) 13000',
              suffixText: '원/시간',
              helperText: '최저 ${fmt.format(minWage)}원 이상',
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
            onChanged:
                (v) => setState(
                  () => _hourlyWage = int.tryParse(v.replaceAll(',', '')),
                ),
          ),
          const SizedBox(height: 12),
          if (_generateError != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, size: 16, color: Colors.red),
                  const SizedBox(width: 8),
                  Text(
                    _generateError!,
                    style: const TextStyle(fontSize: 12, color: Colors.red),
                  ),
                ],
              ),
            ),
          if (_hourlyWage != null && _hourlyWage! >= minWage)
            _NextBtn(label: '완료 후 공고문 적용', onTap: _onComplete),
        ],
      ],
    );
  }

  // ════════════════════════════════════════════════════════
  //  로딩 화면
  // ════════════════════════════════════════════════════════
  Widget _buildLoadingScreen() {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: _text,
          ),
          onPressed: () {
            setState(() => _isGenerating = false); // 로딩 상태 해제
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF3182F6), Color(0xFF6C5CE7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: _blue.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.edit_note_rounded,
                    size: 36,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                '제목과 공고문을 동시에 만들고 있어요',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _text,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '입력한 정보로 30초 안에 완성돼요',
                style: TextStyle(fontSize: 14, color: _label),
              ),
              const SizedBox(height: 32),
              const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(_blue),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 유틸 ──
  DateTime _nextWeekday(DateTime from, int weekday) {
    int diff = weekday - from.weekday;
    if (diff <= 0) diff += 7;
    return from.add(Duration(days: diff));
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
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

class _CustomInputToggle extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  const _CustomInputToggle({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFEEF5FF) : _bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: active ? _blue : _border),
      ),
      child: Row(
        children: [
          const Icon(Icons.edit_outlined, size: 18, color: _label),
          const SizedBox(width: 10),
          const Text(
            '직접 입력',
            style: TextStyle(
              fontSize: 14,
              color: _sub,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}
