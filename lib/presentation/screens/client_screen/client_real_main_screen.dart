import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import '../../../data/models/job.dart';
import '../../../data/services/job_service.dart';
import '../worker_screen/job_detail_screen.dart';
import '../../../data/services/screen_analytics_service.dart';
import 'worker_map_screen.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../../config/constants.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'package:iljujob/utils/pay_display.dart';

const kBrandBlue = Color(0xFF3B8AFF);
const kTextPrimary = Colors.black87;
const kTextSecondary = Colors.black54;

class ClientRealMainScreen extends StatefulWidget {
  const ClientRealMainScreen({super.key});

  static const Color kBrandBlue = Color(0xFF3B8AFF);
  static const Color kTextPrimary = Colors.black87;
  static const Color kTextSecondary = Colors.black54;
  @override
  State<ClientRealMainScreen> createState() => _ClientRealMainScreenState();
}

class _ClientRealMainScreenState extends State<ClientRealMainScreen> {
  List<Job> allJobs = [];
  List<Job> filteredJobs = [];
  bool isLoading = true;
  bool compactView = false;
  String sortType = '최신순';
  double currentLatitude = 0.0;
  double currentLongitude = 0.0;
  double selectedDistance = 30;
  final ScrollController _scrollController = ScrollController();
  int _itemsToShow = 10;
  bool showNearbyOnly = false;
  String searchQuery = '';
  int _remainingPass = 0;
  // 상단 유틸
  int _payNum(Job j) {
    final s = j.pay.toString() ?? '0';
    return int.tryParse(s.replaceAll(',', '')) ?? 0;
  }

  int _createdTs(Job j) => j.createdAt?.millisecondsSinceEpoch ?? 0;
  @override
  void initState() {
    super.initState();
    ScreenAnalyticsService.instance.logScreenView('client_home');
    _init();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        _loadMoreItems();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final inst = identityHashCode(this);
    final t0 = DateTime.now();

    // 컨텍스트(로그인/토큰) 상태 확인
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getInt('userId');
      final hasToken = (prefs.getString('authToken') ?? '').isNotEmpty;
    } catch (e) {}

    final fLoc = _prepareLocation()
        .then(
          (_) => debugPrint(
            '[_init] location done lat=$currentLatitude lon=$currentLongitude',
          ),
        )
        .catchError((e) => debugPrint('[_init] location error: $e'));

    final fJobs = _loadJobs()
        .then(
          (_) => debugPrint(
            '[_init] loadJobs done all=${allJobs.length} filtered=${filteredJobs.length}',
          ),
        )
        .catchError((e) => debugPrint('[_init] loadJobs error: $e'));

    try {
      debugPrint('[_init] waiting location and jobs in parallel');
      await Future.wait([fLoc, fJobs]);
      debugPrint('[_init] parallel wait finished');

      debugPrint('[_init] ▶ schedule fetchRemainingPass (no await)');
      unawaited(
        _fetchRemainingPass()
            .timeout(const Duration(seconds: 5))
            .then(
              (_) =>
                  debugPrint('[_init] pass fetched remaining=$_remainingPass'),
            )
            .catchError((e) => debugPrint('[_init] pass fetch error: $e')),
      );
    } finally {
      final t1 = DateTime.now();
      debugPrint(
        '[_init] end inst=$inst dt=${t1.difference(t0).inMilliseconds}ms mounted=$mounted',
      );
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  // 위치 준비: 빠르게 lastKnown → 느리면 current with timeout
  Future<void> _prepareLocation() async {
    try {
      LocationPermission p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied ||
          p == LocationPermission.deniedForever) {
        p = await Geolocator.requestPermission();
        if (p != LocationPermission.always &&
            p != LocationPermission.whileInUse) {
          return;
        }
      }

      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        currentLatitude = last.latitude;
        currentLongitude = last.longitude;
      }

      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 2),
        );
        currentLatitude = pos.latitude;
        currentLongitude = pos.longitude;
      } catch (_) {}

      // 위치가 바뀌었을 수 있으니 필터 한 번 더
      if (mounted) _applyFilters();
    } catch (e) {
      debugPrint('location prepare failed: $e');
    }
  }

  int _loadSeq = 0;
  bool _loading = false;

  Future<void> _loadJobs() async {
    if (_loading) {
      return;
    }
    _loading = true;
    final int seq = ++_loadSeq;

    try {
      final jobs = await JobService.fetchJobs().timeout(
        const Duration(seconds: 8),
      );

      if (!mounted || seq != _loadSeq) {
        return;
      }

      final validJobs =
          jobs
              .where((j) => j.status != 'closed' && j.status != 'deleted')
              .toList();

      if (!mounted) return;
      setState(() {
        allJobs = validJobs;
      });

      // 필터 적용 (여기서도 mounted 가드 권장)
      _applyFilters();
    } on TimeoutException {
      if (!mounted || seq != _loadSeq) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('네트워크가 지연됩니다. 다시 시도해주세요.')));
    } catch (e) {
      if (!mounted || seq != _loadSeq) return;
      if (allJobs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('공고를 불러오지 못했습니다. 아래 새로고침을 눌러주세요.')),
        );
      }
    } finally {
      if (mounted && seq == _loadSeq) {
        setState(() {}); // 필요한 로딩 플래그 해제 등
      }
      _loading = false;
    }
  }

  void _applyFilters() {
    if (!mounted) return;

    List<Job> temp = [...allJobs];

    if (showNearbyOnly && currentLatitude != 0.0 && currentLongitude != 0.0) {
      temp =
          temp.where((job) {
            final distance = calculateDistance(
              currentLatitude,
              currentLongitude,
              job.lat,
              job.lng,
            );
            return distance <= selectedDistance;
          }).toList();
    }

    if (searchQuery.isNotEmpty) {
      temp =
          temp
              .where(
                (job) =>
                    job.title.toLowerCase().contains(
                      searchQuery.toLowerCase(),
                    ) ||
                    job.location.toLowerCase().contains(
                      searchQuery.toLowerCase(),
                    ),
              )
              .toList();
    }

    if (sortType == '최신순') {
      temp.sort((a, b) => _createdTs(b).compareTo(_createdTs(a)));
    } else if (sortType == '급여 높은 순') {
      temp.sort((a, b) => _payNum(b).compareTo(_payNum(a)));
    }

    setState(() {
      filteredJobs = temp;
      _itemsToShow = 10;
    });
  }

  void _loadMoreItems() {
    if (_itemsToShow < filteredJobs.length) {
      setState(() {
        _itemsToShow += 10;
      });
    }
  }

  Future<void> _fetchRemainingPass() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken') ?? '';
    final clientId = prefs.getInt('userId');
    if (clientId == null) return;

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/pass/remain?clientId=$clientId'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final rawRemaining = data['remaining'];
        final parsedRemaining =
            rawRemaining is int
                ? rawRemaining
                : int.tryParse(rawRemaining.toString()) ?? 0;

        if (!mounted) return;
        setState(() {
          _remainingPass = parsedRemaining;
        });
      } else {
        debugPrint('pass fetch failed: ${response.body}');
      }
    } catch (e) {
      debugPrint('pass fetch network error: $e');
    }
  }

  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) *
            cos(_deg2rad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _deg2rad(double deg) => deg * (pi / 180);

  Widget _pill(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: kBrandBlue.withOpacity(.08),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: kBrandBlue.withOpacity(.28)),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        color: kBrandBlue,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _buildSortOptions() {
    return Row(
      children: [
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: sortType,
              items: const [
                DropdownMenuItem(value: '최신순', child: Text('최신순')),
                DropdownMenuItem(value: '급여 높은 순', child: Text('급여 높은 순')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => sortType = v);
                _applyFilters();
              },
            ),
          ),
        ),
        const Spacer(),
        Tooltip(
          message: compactView ? 'Compact View' : 'List View',
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => compactView = !compactView),
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Icon(
                compactView ? Icons.view_agenda : Icons.view_list,
                color: kBrandBlue,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildJobList() {
    if (filteredJobs.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off, size: 56, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              const Text(
                '조건에 맞는 공고가 없어요',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text('필터를 조정해보세요', style: TextStyle(color: kTextSecondary)),
            ],
          ),
        ],
      );
    }

    final count =
        (_itemsToShow < filteredJobs.length)
            ? _itemsToShow
            : filteredJobs.length;

    return ListView.separated(
      controller: _scrollController,
      itemCount: count,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final job = filteredJobs[index];
        final child =
            compactView ? _buildCompactJobCard(job) : _buildJobCard(job);
        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => JobDetailScreen(job: job),
              ),
            );
          },
          child: child,
        );
      },
    );
  }

  Widget _buildSearchField() {
    return SizedBox(
      height: 36,
      child: TextField(
        onChanged: (value) {
          searchQuery = value;
          _applyFilters();
        },
        decoration: InputDecoration(
          hintText: '공고를 검색해보세요',
          prefixIcon: const Icon(Icons.search, size: 18),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          isDense: true,
          filled: true,
          fillColor: Colors.grey.shade100,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
        ),
        style: const TextStyle(fontSize: 13),
      ),
    );
  }

  Widget _buildJobCard(Job job) {
    final formattedPay = formatJobPay(job.pay, job.payType);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 제목
            Text(
              job.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: kTextPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.place_outlined,
                  size: 15,
                  color: Colors.black54,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    job.location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      color: Colors.black87,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 배지들
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _pill(formattedPay),
                if (job.payType.isNotEmpty && !isNegotiablePayType(job.payType))
                  _pill(job.payType),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactJobCard(Job job) {
    final formattedPay = formatJobPay(job.pay, job.payType);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: .8),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              job.title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: kTextPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              job.location,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: kTextPrimary),
            ),
          ),
          const SizedBox(width: 8),
          _pill(formattedPay),
        ],
      ),
    );
  }

  Widget _buildViewToggle() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ChoiceChip(
          label: const Text('전국 보기'),
          selected: showNearbyOnly == false,
          onSelected: (selected) {
            setState(() {
              showNearbyOnly = false;
              _applyFilters();
            });
          },
          selectedColor: kBrandBlue.withOpacity(.15),
          labelStyle: TextStyle(
            color: (showNearbyOnly == false) ? kBrandBlue : kTextPrimary,
          ),
          shape: StadiumBorder(
            side: BorderSide(
              color:
                  (showNearbyOnly == false) ? kBrandBlue : Colors.grey.shade300,
            ),
          ),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('내 주변 보기'),
          selected: showNearbyOnly == true,
          onSelected: (selected) {
            setState(() {
              showNearbyOnly = true;
              _applyFilters();
            });
          },
          selectedColor: kBrandBlue.withOpacity(.15),
          labelStyle: TextStyle(
            color: (showNearbyOnly == true) ? kBrandBlue : kTextPrimary,
          ),
          shape: StadiumBorder(
            side: BorderSide(
              color:
                  (showNearbyOnly == true) ? kBrandBlue : Colors.grey.shade300,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDistanceSlider() {
    return Visibility(
      visible: showNearbyOnly,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '거리 설정: ${selectedDistance.toInt()}km 이내',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            Slider(
              min: 1,
              max: 100,
              divisions: 99,
              value: selectedDistance,
              label: '${selectedDistance.toInt()}km',
              onChanged: (v) {
                setState(() {
                  selectedDistance = v;
                  _applyFilters();
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPassInfoRow() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: kBrandBlue.withOpacity(.1),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.confirmation_num_outlined,
                color: kBrandBlue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '보유 이용권: $_remainingPass개',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: kTextPrimary,
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/purchase-pass'),
              icon: const Icon(Icons.add_card, size: 18, color: kBrandBlue),
              label: const Text('구매', style: TextStyle(color: kBrandBlue)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: kBrandBlue),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                backgroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.white,
            enableDrag: false, // ← 맵 제스처랑 충돌 방지
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: (context) => const WorkerMapScreen(),
          );
        },
        icon: const Icon(Icons.map),
        label: const Text('지도 보기'),
        backgroundColor: kBrandBlue,
        foregroundColor: Colors.white,
      ),

      appBar: AppBar(
        elevation: 0,
        centerTitle: false,
        title: const Text('알바 공고 리스트'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () async {
                final prefs = await SharedPreferences.getInstance();
                final clientId = prefs.getInt('userId')?.toString();

                if (clientId == null) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('로그인 정보가 없습니다')));
                  return;
                }

                try {
                  final response = await http.get(
                    Uri.parse(
                      '$baseUrl/api/client/business-info-status?clientId=$clientId',
                    ),
                  );

                  if (response.statusCode == 200) {
                    final data = jsonDecode(response.body);
                    final hasInfo = data['hasInfo'] == true;
                    final needsUpdate = data['needsUpdate'] == true;

                    if (hasInfo && !needsUpdate) {
                      Navigator.pushNamed(context, '/post_job');
                    } else {
                      Navigator.pushNamed(context, '/client_business_info');
                    }
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('사업자 정보 확인 실패')),
                    );
                  }
                } catch (e) {
                  debugPrint('business verification error: $e');
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('서버 통신 오류')));
                }
              },
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: kBrandBlue.withOpacity(.08),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: kBrandBlue.withOpacity(.35)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: kBrandBlue.withOpacity(.18),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.add, size: 18, color: kBrandBlue),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '공고 등록',
                      style: TextStyle(
                        color: kBrandBlue,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        // 폰트 대소문자 혼용 때문에 적용 안될 수 있어서 통일 추천
                        fontFamily: 'Jalnan2TTF',
                      ),
                    ),
                    const SizedBox(width: 2),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),

      body:
          isLoading
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPassInfoRow(),
                    const SizedBox(height: 12),
                    _buildViewToggle(),
                    _buildDistanceSlider(),
                    const SizedBox(height: 12),
                    _buildSearchField(),
                    const SizedBox(height: 8),
                    _buildSortOptions(),
                    const SizedBox(height: 10),
                    Expanded(child: _buildJobList()),
                    const SizedBox(height: 60), // FAB와 겹침 방지
                  ],
                ),
              ),
    );
  }
}
