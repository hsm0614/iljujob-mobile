import 'dart:convert';
import 'package:iljujob/widget/app_ui.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:iljujob/config/constants.dart';
import 'package:iljujob/data/services/authenticated_http_client.dart';
import '../../../config/messages.dart';
import '../../../config/app_theme.dart';

class InquiryScreen extends StatefulWidget {
  const InquiryScreen({super.key});

  @override
  State<InquiryScreen> createState() => _InquiryScreenState();
}

class _InquiryScreenState extends State<InquiryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);
  // 목록은 탭을 다시 그릴 때마다 새로 부르지 않게 한 번 받아 둔다
  late Future<List<Map<String, dynamic>>> _listFuture = _fetchInquiries();

  void _reloadList() => setState(() => _listFuture = _fetchInquiries());

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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
      builder:
          (_) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('앨범에서 선택'),
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera),
                  title: const Text('카메라로 촬영'),
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
              ],
            ),
          ),
    );
    if (src == null) return;

    final picked = await _picker.pickImage(
      source: src,
      imageQuality: 88,
    ); // 약간 압축
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
    final userType = prefs.getString('userType');

    try {
      final ok = await _sendInquiry(
        userPhone: userPhone,
        userId: userId,
        userType: userType,
        inquiryType: _selectedType,
        title: _titleController.text.trim(),
        content: _contentController.text.trim(),
        images: _images,
      );

      if (ok) {
        if (!mounted) return;
        _clearForm();
        _reloadList();
        _tab.animateTo(1);
        showAppSheet(
          context,
          title: '문의를 접수했어요',
          message: '답변이 달리면 알림으로 알려 드려요.',
        );
      } else {
        _showSnack('문의를 보내지 못했어요. 잠시 후 다시 시도해 주세요.');
      }
    } catch (e) {
      debugPrint('오류 발생: $e');
      _showSnack(Msg.server);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<bool> _sendInquiry({
    required String userPhone,
    required int? userId,
    required String? userType,
    required String inquiryType,
    required String title,
    required String content,
    required List<XFile> images,
  }) async {
    final uri = Uri.parse('$baseUrl/api/inquiry');

    Future<http.MultipartRequest> buildRequest(String token) async {
      final req =
          http.MultipartRequest('POST', uri)
            ..fields['inquiryType'] = inquiryType
            ..fields['title'] = title
            ..fields['content'] = content;

      // ── 백엔드 호환: id 우선, 없으면 phone
      if (userId != null) req.fields['userId'] = userId.toString();
      if (userType != null && userType.isNotEmpty) {
        req.fields['userType'] = userType;
      }
      if (userPhone.isNotEmpty) req.fields['userPhone'] = userPhone;

      if (token.isNotEmpty) {
        req.headers['Authorization'] = 'Bearer $token';
      }

      for (final x in images) {
        req.files.add(await http.MultipartFile.fromPath('images', x.path));
      }
      return req;
    }

    final resp = await AuthenticatedHttpClient.sendMultipart(buildRequest);
    return resp.statusCode == 200;
  }

  Future<List<Map<String, dynamic>>> _fetchInquiries() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId');
    final userPhone = prefs.getString('userPhone') ?? '';
    final userType = prefs.getString('userType');

    Uri uri;
    if (userId != null) {
      final userTypeQuery =
          userType != null && userType.isNotEmpty ? '&userType=$userType' : '';
      uri = Uri.parse(
        '$baseUrl/api/inquiry/inquiries?userId=$userId$userTypeQuery',
      );
    } else {
      final userTypeQuery =
          userType != null && userType.isNotEmpty ? '&userType=$userType' : '';
      uri = Uri.parse(
        '$baseUrl/api/inquiry/inquiries?userPhone=$userPhone$userTypeQuery',
      );
    }

    final res = await AuthenticatedHttpClient.get(uri);
    if (res.statusCode == 200) {
      final List data = jsonDecode(res.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('문의 내역 불러오기 실패 (code: ${res.statusCode})');
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  // ───────────────────────── UI ─────────────────────────
  // 2026-10 리디자인: 알약 탭·흰 바탕 위 흰 입력칸(칸이 안 보였다) → 밑줄 탭 + 회색 입력칸,
  // 유형 드롭다운 → 칩, 카드 목록 → 흰 줄

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgCard,
      appBar: AppBar(
        title: const Text('1:1 문의'),
        bottom: TabBar(
          controller: _tab,
          labelColor: AppColors.textPrimary,
          unselectedLabelColor: AppColors.textTertiary,
          labelStyle: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w700),
          unselectedLabelStyle: AppTextStyles.body1,
          indicatorColor: AppColors.textPrimary,
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: AppColors.border,
          tabs: const [Tab(text: '문의하기'), Tab(text: '내 문의 내역')],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [_buildInquiryForm(), _buildInquiryList()],
      ),
    );
  }

  Widget _buildInquiryForm() {
    return SafeArea(
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Label('어떤 문의인가요?'),
              Wrap(
                spacing: 8,
                children: [
                  for (final t in _inquiryTypes)
                    ChoiceChip(
                      label: Text(t),
                      selected: _selectedType == t,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _selectedType = t),
                      labelStyle: AppTextStyles.btnMd.copyWith(
                        color:
                            _selectedType == t
                                ? AppColors.primary
                                : AppColors.textSecondary,
                      ),
                      selectedColor: AppColors.primaryLight,
                      backgroundColor: AppColors.bgCard,
                      side: BorderSide(
                        color:
                            _selectedType == t
                                ? AppColors.primary
                                : AppColors.border,
                      ),
                      shape: const StadiumBorder(),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              const _Label('제목'),
              TextFormField(
                controller: _titleController,
                maxLength: _maxTitleLen,
                decoration: _inputDecoration(hint: '예) 지원 버튼이 눌리지 않아요'),
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return '제목을 입력해 주세요.';
                  if (s.length < 2) return '제목은 2자 이상 입력해 주세요.';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              const _Label('내용'),
              TextFormField(
                controller: _contentController,
                maxLines: 8,
                maxLength: _maxContentLen,
                decoration: _inputDecoration(
                  hint: '언제, 어떤 화면에서 무슨 일이 있었는지 적어 주시면 더 빨리 도와드릴 수 있어요.',
                ),
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return '내용을 입력해 주세요.';
                  if (s.length < 5) return '내용은 5자 이상 입력해 주세요.';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const _Label('사진'),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '선택 · ${_images.length}/$_maxImages',
                      style: AppTextStyles.caption,
                    ),
                  ),
                ],
              ),
              _buildImageGrid(),
              const SizedBox(height: 32),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _isSubmitting ? null : _submitInquiry,
                  child:
                      _isSubmitting
                          ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
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
        if (canAdd)
          InkWell(
            onTap: _pickImageSource,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.bgMuted,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: const Icon(
                Icons.add_a_photo_outlined,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        for (int i = 0; i < _images.length; i++)
          Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Image.file(
                  File(_images[i].path),
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                right: -6,
                top: -6,
                child: GestureDetector(
                  onTap: () => setState(() => _images.removeAt(i)),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: AppColors.textPrimary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: Colors.white,
                      semanticLabel: '사진 빼기',
                    ),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  /// 서버는 '+09:00' 붙은 한국 시각 문자열을 준다 → 앞 10자리만
  String _date(String raw) =>
      raw.length >= 10 ? raw.substring(0, 10).replaceAll('-', '.') : raw;

  bool _answered(String status) =>
      const ['완료', '답변 완료', 'closed'].contains(status);

  Widget _buildInquiryList() {
    return RefreshIndicator(
      onRefresh: () async {
        _reloadList();
        await _listFuture;
      },
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _listFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return ListView(
              children: [
                const SizedBox(height: 80),
                Center(child: Text(Msg.server, style: AppTextStyles.body2)),
              ],
            );
          }
          final data = snap.data ?? [];
          if (data.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 60),
                AppEmptyState(
                  icon: Icons.mail_outline_rounded,
                  title: '아직 남긴 문의가 없어요',
                  message: '답변이 달리면 알림으로 알려 드려요.',
                ),
              ],
            );
          }

          return ListView.builder(
            itemCount: data.length,
            itemBuilder: (context, i) {
              final item = data[i];
              final title = (item['title'] ?? '제목 없음').toString();
              final type = (item['inquiryType'] ?? '').toString();
              final status = (item['status'] ?? '진행 중').toString();
              final answered = _answered(status);
              final answer = (item['answer'] ?? '').toString().trim();

              return InkWell(
                onTap: () => _showInquiryDetail(item),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: AppColors.borderSub),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              [
                                if (type.isNotEmpty) type,
                                _date((item['createdAt'] ?? '').toString()),
                              ].join(' · '),
                              style: AppTextStyles.jobMeta,
                            ),
                          ),
                          Text(
                            answered ? '답변 완료' : '답변 기다리는 중',
                            style: AppTextStyles.captionBold.copyWith(
                              fontSize: 12,
                              color:
                                  answered
                                      ? AppColors.badgeSameDay
                                      : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.jobTitle,
                      ),
                      if (answer.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          answer,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body2,
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showInquiryDetail(Map<String, dynamic> inquiry) {
    final title = (inquiry['title'] ?? '제목 없음').toString();
    final type = (inquiry['inquiryType'] ?? '').toString();
    final content = (inquiry['content'] ?? '내용 없음').toString();
    final createdAt = _date((inquiry['createdAt'] ?? '').toString());
    final answer = (inquiry['answer'] ?? '').toString().trim();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder:
          (_) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [if (type.isNotEmpty) type, createdAt].join(' · '),
                  style: AppTextStyles.jobMeta,
                ),
                const SizedBox(height: 4),
                Text(title, style: AppTextStyles.h3),
                const SizedBox(height: 12),
                Text(content, style: AppTextStyles.body1),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.bgMuted,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '알바일주 답변',
                        style: AppTextStyles.captionBold,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        answer.isEmpty ? '아직 답변 전이에요. 답변이 달리면 알림으로 알려 드려요.' : answer,
                        style: AppTextStyles.body1.copyWith(
                          color:
                              answer.isEmpty
                                  ? AppColors.textSecondary
                                  : AppColors.textPrimary,
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

  InputDecoration _inputDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppTextStyles.body1.copyWith(color: AppColors.textTertiary),
      hintMaxLines: 3,
      filled: true,
      fillColor: AppColors.bgMuted,
      counterStyle: AppTextStyles.caption,
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}
