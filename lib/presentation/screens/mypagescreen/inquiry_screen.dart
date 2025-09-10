import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:iljujob/config/constants.dart';

class InquiryScreen extends StatefulWidget {
  const InquiryScreen({super.key});

  @override
  State<InquiryScreen> createState() => _InquiryScreenState();
}

class _InquiryScreenState extends State<InquiryScreen> {
  // ── UI 상태
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  String _selectedType = '선택해주세요';
  final List<String> _inquiryTypes = const ['회원문의', '결제문의', '기타문의'];
  final List<XFile> _images = [];
  final ImagePicker _picker = ImagePicker();
  bool _isSubmitting = false;

  // ── 제한
  static const int _maxImages = 5;
  static const int _maxTitleLen = 60;
  static const int _maxContentLen = 1500;
  static const int _maxFileSizeBytes = 5 * 1024 * 1024; // 5MB

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _clearForm() {
    setState(() {
      _selectedType = '선택해주세요';
      _titleController.clear();
      _contentController.clear();
      _images.clear();
    });
  }

  Future<void> _pickImageSource() async {
    if (_images.length >= _maxImages) {
      _showSnack('최대 $_maxImages장까지 첨부할 수 있어요.');
      return;
    }
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.photo_library), title: const Text('앨범에서 선택'), onTap: () => Navigator.pop(context, ImageSource.gallery)),
            ListTile(leading: const Icon(Icons.photo_camera), title: const Text('카메라로 촬영'), onTap: () => Navigator.pop(context, ImageSource.camera)),
          ],
        ),
      ),
    );
    if (src == null) return;

    final picked = await _picker.pickImage(source: src, imageQuality: 88); // 약간 압축
    if (picked == null) return;

    final file = File(picked.path);
    final size = await file.length();
    if (size > _maxFileSizeBytes) {
      _showSnack('파일 용량은 최대 5MB까지 업로드 가능합니다.');
      return;
    }

    setState(() => _images.add(picked));
  }

  Future<void> _submitInquiry() async {
    if (_isSubmitting) return;

    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid || _selectedType == '선택해주세요') {
      if (_selectedType == '선택해주세요') _showSnack('문의 유형을 선택해주세요.');
      return;
    }

    setState(() => _isSubmitting = true);

    final prefs = await SharedPreferences.getInstance();
    final userPhone = prefs.getString('userPhone') ?? '';
    final userId = prefs.getInt('userId'); // 신규 구조 호환
    final token = prefs.getString('authToken');

    try {
      final ok = await _sendInquiry(
        userPhone: userPhone,
        userId: userId,
        token: token,
        inquiryType: _selectedType,
        title: _titleController.text.trim(),
        content: _contentController.text.trim(),
        images: _images,
      );

      if (ok) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('접수 완료'),
            content: const Text('문의가 정상적으로 접수되었습니다.\n빠르게 답변드릴게요!'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('확인')),
            ],
          ),
        );
        _clearForm();
      } else {
        _showSnack('문의 전송에 실패했습니다. 잠시 후 다시 시도해주세요.');
      }
    } catch (e) {
      _showSnack('오류 발생: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<bool> _sendInquiry({
    required String userPhone,
    required int? userId,
    required String? token,
    required String inquiryType,
    required String title,
    required String content,
    required List<XFile> images,
  }) async {
    final uri = Uri.parse('$baseUrl/api/inquiry');

    final req = http.MultipartRequest('POST', uri)
      ..fields['inquiryType'] = inquiryType
      ..fields['title'] = title
      ..fields['content'] = content;

    // ── 백엔드 호환: id 우선, 없으면 phone
    if (userId != null) req.fields['userId'] = userId.toString();
    if (userPhone.isNotEmpty) req.fields['userPhone'] = userPhone;

    // ── 인증(있으면)
    if (token != null && token.isNotEmpty) {
      req.headers['Authorization'] = 'Bearer $token';
    }

    for (final x in images) {
      req.files.add(await http.MultipartFile.fromPath('images', x.path));
    }

    final resp = await req.send();
    return resp.statusCode == 200;
  }

  Future<List<Map<String, dynamic>>> _fetchInquiries() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId');
    final userPhone = prefs.getString('userPhone') ?? '';
    final token = prefs.getString('authToken');

    Uri uri;
    if (userId != null) {
      uri = Uri.parse('$baseUrl/api/inquiry/inquiries?userId=$userId');
    } else {
      uri = Uri.parse('$baseUrl/api/inquiry/inquiries?userPhone=$userPhone');
    }

    final headers = <String, String>{};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    final res = await http.get(uri, headers: headers);
    if (res.statusCode == 200) {
      final List data = jsonDecode(res.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('문의 내역 불러오기 실패 (code: ${res.statusCode})');
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.transparent,
          title: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.25)),
            ),
            child: const Text('고객센터', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          centerTitle: true,
        bottom: PreferredSize(
  preferredSize: const Size.fromHeight(72), // ← 64에서 72로
  child: Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: _PillTabBar(
      tabs: const [
        Tab(
          text: '1:1 문의하기',
          icon: Icon(Icons.edit_note_rounded, size: 18),
          iconMargin: EdgeInsets.zero, // ✅ 기본 10 하단여백 제거
        ),
        Tab(
          text: '내 문의 내역',
          icon: Icon(Icons.history_rounded, size: 18),
          iconMargin: EdgeInsets.zero, // ✅
        ),
      ],
    ),
  ),
),
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Color(0xFF3B8AFF), Color(0xFF7CC7FF), Colors.white],
              stops: [0, .25, .25],
            ),
          ),
          child: TabBarView(
            children: [
              _buildInquiryForm(),
              _buildInquiryList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInquiryForm() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 유형
              const Text('문의 유형 *', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedType,
                items: ['선택해주세요', ..._inquiryTypes]
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedType = v!),
                decoration: _inputDecoration(),
                validator: (v) => (v == null || v == '선택해주세요') ? '문의 유형을 선택해주세요.' : null,
              ),
              const SizedBox(height: 16),

              // 제목
              _Labeled(
                label: '문의 제목 *',
                child: TextFormField(
                  controller: _titleController,
                  maxLength: _maxTitleLen,
                  decoration: _inputDecoration(hint: '간단한 제목을 입력해주세요.'),
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) return '제목을 입력해주세요.';
                    if (s.length < 2) return '제목은 2자 이상 입력해주세요.';
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 12),

              // 내용
              _Labeled(
                label: '문의 내용 *',
                child: TextFormField(
                  controller: _contentController,
                  maxLines: 8,
                  maxLength: _maxContentLen,
                  decoration: _inputDecoration(hint: '상세 내용을 입력해주세요. (스크린샷/오류 메시지 포함 권장)'),
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) return '내용을 입력해주세요.';
                    if (s.length < 5) return '내용은 5자 이상 입력해주세요.';
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 16),

              // 첨부
              const Text('사진 첨부 (선택, 최대 5장 / 5MB)', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              _buildImageGrid(),
              const SizedBox(height: 24),

              // 제출 버튼
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isSubmitting ? null : _submitInquiry,
                  child: _isSubmitting
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('문의 보내기'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageGrid() {
    final canAdd = _images.length < _maxImages;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (int i = 0; i < _images.length; i++)
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(
                  File(_images[i].path),
                  width: 92,
                  height: 92,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                right: -8,
                top: -8,
                child: IconButton(
                  onPressed: () => setState(() => _images.removeAt(i)),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withOpacity(.55),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                ),
              ),
            ],
          ),
        if (canAdd)
          InkWell(
            onTap: _pickImageSource,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.black12),
              ),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_a_photo_rounded),
                    SizedBox(height: 4),
                    Text('추가', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInquiryList() {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async => setState(() {}),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _fetchInquiries(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text('❌ 오류 발생: ${snap.error}'));
            }
            final data = snap.data ?? [];
            if (data.isEmpty) {
              return const Center(child: Text('문의 내역이 없습니다.'));
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: data.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final item = data[i];
                final title = (item['title'] ?? '제목 없음').toString();
                final type = (item['inquiryType'] ?? '').toString();
                final status = (item['status'] ?? '진행 중').toString();
                final createdAt = (item['created_at'] ?? '').toString();
                final answerPreview = (item['answer'] ?? '').toString();

                return InkWell(
                  onTap: () => _showInquiryDetail(item),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          radius: 20,
                          backgroundColor: Color(0xFF3B8AFF),
                          child: Icon(Icons.question_answer_rounded, color: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                              const SizedBox(height: 4),
                              Text('$type · $createdAt', style: const TextStyle(color: Colors.black54, fontSize: 12)),
                              if (answerPreview.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  answerPreview.length > 60 ? '${answerPreview.substring(0, 60)}…' : answerPreview,
                                  style: const TextStyle(color: Colors.black87),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StatusBadge(status: status),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _showInquiryDetail(Map<String, dynamic> inquiry) {
    final title = (inquiry['title'] ?? '제목 없음').toString();
    final type = (inquiry['inquiryType'] ?? '').toString();
    final status = (inquiry['status'] ?? '진행 중').toString();
    final content = (inquiry['content'] ?? '내용 없음').toString();
    final createdAt = (inquiry['created_at'] ?? '').toString();
    final answer = (inquiry['answer'] ?? '').toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _StatusBadge(status: status),
                    const SizedBox(width: 8),
                    Text('$type · $createdAt', style: const TextStyle(color: Colors.black54, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('문의 내용', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(content),
                const SizedBox(height: 14),
                if (answer.isNotEmpty) ...[
                  const Text('답변', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B8AFF).withOpacity(.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF3B8AFF).withOpacity(.2)),
                    ),
                    child: Text(answer),
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    );
  }
}

// ── 보조 위젯들 ─────────────────────────────────────────

class _PillTabBar extends StatelessWidget {
  final List<Widget> tabs;
  const _PillTabBar({required this.tabs});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52, // ← 44에서 52로
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 14, offset: Offset(0, 6))],
      ),
      child: TabBar(
        tabs: const [
          Tab(text: '1:1 문의하기', icon: Icon(Icons.edit_note_rounded, size: 18), iconMargin: EdgeInsets.zero),
          Tab(text: '내 문의 내역', icon: Icon(Icons.history_rounded, size: 18), iconMargin: EdgeInsets.zero),
        ], 
        indicator: BoxDecoration(
          color: const Color(0xFF3B8AFF),
          borderRadius: BorderRadius.circular(26),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: const Color(0xFF3B8AFF),
        indicatorSize: TabBarIndicatorSize.tab,
        splashBorderRadius: BorderRadius.circular(26),
        labelPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0), // ✅ 세로 여백 0
      ),
    );
  }
}
class _TabItem extends StatelessWidget {
  final String label;
  final IconData icon;
  const _TabItem({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}

class _Labeled extends StatelessWidget {
  final String label;
  final Widget child;
  const _Labeled({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      child,
    ]);
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    switch (status) {
      case '완료':
      case '답변 완료':
      case 'closed':
        bg = const Color(0xFF22C55E).withOpacity(.12);
        fg = const Color(0xFF16A34A);
        break;
      case '대기':
      case '접수':
      case 'pending':
        bg = const Color(0xFFFFE08A).withOpacity(.35);
        fg = const Color(0xFFB45309);
        break;
      default:
        bg = const Color(0xFF3B8AFF).withOpacity(.12);
        fg = const Color(0xFF3B8AFF);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: ShapeDecoration(color: bg, shape: const StadiumBorder()),
      child: Text(status, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}
