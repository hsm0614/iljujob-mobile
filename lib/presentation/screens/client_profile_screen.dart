import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../config/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
class ClientProfileScreen extends StatefulWidget {
  final int clientId;   // <-- 반드시 int PK!
  const ClientProfileScreen({super.key, required this.clientId});

  @override
  State<ClientProfileScreen> createState() => _ClientProfileScreenState();
}

class _ClientProfileScreenState extends State<ClientProfileScreen> {
  Map<String, dynamic>? profile;
  bool isLoading = true;
  bool isBlocked = false;
  @override
  void initState() {
    super.initState();
     _checkBlockStatus(); // ← 이거 추가
    _fetchProfile();

  }

  Future<void> _fetchProfile() async {
    final url = Uri.parse('$baseUrl/api/client/public-profile?id=${widget.clientId}');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          profile = jsonDecode(response.body);
          isLoading = false;
        });
      } else {
        _showError('불러오기 실패: ${response.body}');
      }
    } catch (e) {
      _showError('네트워크 오류: $e');
    }
  }
  Future<void> _checkBlockStatus() async {
  final prefs = await SharedPreferences.getInstance();
  final userId = prefs.getInt('userId') ?? 0;

  final url = Uri.parse('$baseUrl/api/user-block/check?userId=$userId&targetId=${widget.clientId}&targetType=client');

  try {
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() {
        isBlocked = data['isBlocked'] == true;
      });
    }
  } catch (e) {
    print('❌ 차단 상태 조회 실패: $e');
  }
}
Future<void> _toggleBlockStatus() async {
  final prefs = await SharedPreferences.getInstance();
  final userId = prefs.getInt('userId') ?? 0;

  final url = Uri.parse('$baseUrl/api/user-block/${isBlocked ? 'unblock' : 'block'}');
  try {
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'userId': userId,
        'targetId': widget.clientId,
        'targetType': 'client',
      }),
    );

    if (response.statusCode == 200) {
      setState(() {
        isBlocked = !isBlocked;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isBlocked ? '해당 기업이 차단되었습니다.' : '차단이 해제되었습니다.'),
      ));
    } else {
      _showError('차단 요청 실패: ${response.body}');
    }
  } catch (e) {
    _showError('네트워크 오류: $e');
  }
}

  void _showReportDialog(String targetType, int targetId) {
  final TextEditingController _memoController = TextEditingController();
  String? _selectedReason;

  final List<String> reasonOptions = [
    '음란하거나 부적절한 콘텐츠',
    '폭력 또는 위협적인 언행',
    '욕설/혐오/차별 표현',
    '허위 정보 또는 사기 의심',
    '기타'
  ];

  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('사용자 신고'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            value: _selectedReason,
            items: reasonOptions
                .map((reason) => DropdownMenuItem<String>(
                      value: reason,
                      child: Text(reason),
                    ))
                .toList(),
            onChanged: (val) {
              _selectedReason = val;
            },
            decoration: const InputDecoration(
              labelText: '신고 사유 선택',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _memoController,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: '상세 내용을 입력해주세요 (선택)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '※ 신고된 내용은 검토 후 24시간 이내에 조치됩니다.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
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
      if (_selectedReason == null || _selectedReason!.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('신고 사유를 선택해주세요')),
        );
        return;
      }

      Navigator.pop(context); // 다이얼로그 닫기

      final prefs = await SharedPreferences.getInstance();
      final reporterId = prefs.getInt('userId') ?? 0;

      final response = await http.post(
        Uri.parse('$baseUrl/api/user-report'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'reporterId': reporterId,
          'targetId': targetId,
          'targetType': targetType,
          'reasonCategory': _selectedReason,
          'reasonDetail': _memoController.text.trim(),
        }),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('신고가 접수되었습니다. 관리자 검토 후 24시간 이내 조치됩니다.'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('신고 실패: ${response.body}')),
        );
      }
    },
    child: const Text('신고'),
  ),
],
      
    ),
  );
}

  String _resolveImageUrl(String? url) {
    if (url == null || url.trim().isEmpty) return '';
    return url.startsWith('http') ? url : '$baseUrl/${url.replaceFirst(RegExp(r'^/+'), '')}';
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }


Widget _mzHeaderCard() {
  final logo = profile!['logo_url'];
  final verified = profile!['is_certified_company'].toString() == '1';
  final company = profile!['company_name'] ?? '회사명 없음';
  final manager = profile!['manager_name'] ?? '정보 없음';
  final phone = profile!['phone'] ?? '정보 없음';
  final email = profile!['email'] ?? '정보 없음';

  return Container(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
    margin: const EdgeInsets.only(bottom: 24),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF1675F4), Color(0xFF5AA6FF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF1675F4).withOpacity(0.25),
          blurRadius: 16,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 34,
          backgroundColor: Colors.white,
          backgroundImage: (logo != null && logo.toString().isNotEmpty)
              ? NetworkImage(_resolveImageUrl(logo))
              : null,
          child: (logo == null || logo.toString().isEmpty)
              ? const Icon(Icons.business, size: 30, color: Color(0xFF1675F4))
              : null,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(
                    company,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (verified)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.9),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text('🔒 안심기업',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1675F4))),
                  ),
              ]),
              const SizedBox(height: 6),
              Text('담당자 $manager', style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 2),
              Text('📞 $phone', style: const TextStyle(color: Colors.white70)),
              Text('✉️ $email', style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          children: [
            _iconChip(
              icon: Icons.report_gmailerrorred_rounded,
              label: '신고',
              bg: Colors.white,
              fg: const Color(0xFFEB5757),
              onTap: () => _showReportDialog('client', widget.clientId),
            ),
            const SizedBox(height: 8),
            _iconChip(
              icon: isBlocked ? Icons.block_flipped : Icons.block,
              label: isBlocked ? '해제' : '차단',
              bg: Colors.white,
              fg: isBlocked ? Colors.grey : Colors.black87,
              onTap: _toggleBlockStatus,
            ),
          ],
        ),
      ],
    ),
  );
}

Widget _iconChip({
  required IconData icon,
  required String label,
  required Color bg,
  required Color fg,
  required VoidCallback onTap,
}) {
  return Material(
    color: bg,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    ),
  );
}
Widget _aboutCard() {
  final desc = (profile!['description'] ?? '').toString().trim();
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    margin: const EdgeInsets.only(bottom: 24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.grey.shade200),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 10, offset: const Offset(0, 6))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(
        children: [
          _pill('📢 회사 소개'),
          const Spacer(),
          if (desc.isNotEmpty) _tinyMuted('최근 업데이트'),
        ],
      ),
      const SizedBox(height: 12),
      Text(
        desc.isEmpty ? '아직 회사 소개가 작성되지 않았습니다.' : desc,
        style: const TextStyle(fontSize: 14, height: 1.6),
      ),
    ]),
  );
}

Widget _pill(String text) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  decoration: BoxDecoration(
    color: const Color(0xFFE9F2FF),
    borderRadius: BorderRadius.circular(10),
  ),
  child: Text(text, style: const TextStyle(color: Color(0xFF1675F4), fontWeight: FontWeight.w700)),
);

Widget _tinyMuted(String text) => Text(text, style: const TextStyle(fontSize: 12, color: Colors.grey));


Widget _statsCard() {
  return Container(
    padding: const EdgeInsets.all(16),
    margin: const EdgeInsets.only(bottom: 32),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.grey.shade200),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 10, offset: const Offset(0, 6))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pill('📊 채용 활동'),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _statChip(Icons.work_outline, '등록한 공고', profile!['job_count']?.toString() ?? '0')),
          const SizedBox(width: 12),
          Expanded(child: _statChip(Icons.check_circle_outline, '채용 확정', profile!['hire_count']?.toString() ?? '0')),
        ]),
      ],
    ),
  );
}

Widget _statChip(IconData icon, String title, String value) {
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFF7F9FC),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF1675F4).withOpacity(.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: const Color(0xFF1675F4)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          ]),
        ),
      ],
    ),
  );
}
  @override
Widget build(BuildContext context) {
  return Scaffold(
   appBar: AppBar(
  backgroundColor: Colors.white,
  elevation: 0,
  centerTitle: false,
  iconTheme: const IconThemeData(color: Colors.black),
  title: const Text(
    '기업 프로필',
    style: TextStyle(
      color: Color(0xFF3B8AFF),
      fontWeight: FontWeight.bold,
      fontSize: 20,
    ),
  ),

  
),
    body: isLoading
        ? const Center(child: CircularProgressIndicator())
        : profile == null
            ? const Center(child: Text('기업 정보를 불러올 수 없습니다.'))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _mzHeaderCard(),  // ✅ 여기
                    _aboutCard(),     // ✅ 여기
                    _statsCard(),     // ✅ 여기
                  ],
                ),
              ),
  );
}

  
}
