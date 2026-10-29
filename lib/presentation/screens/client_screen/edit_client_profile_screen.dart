import 'dart:convert';
import 'package:iljujob/widget/app_ui.dart';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/constants.dart';
import '../../../data/services/authenticated_http_client.dart';
import '../../../config/messages.dart';
import '../../../config/app_theme.dart';

// 유연한 키 대응
T? pickFirstNonNull<T>(Map src, List<String> keys) {
  for (final k in keys) {
    final v = src[k];
    if (v != null && v.toString().trim().isNotEmpty) return v as T;
  }
  return null;
}

class EditClientProfileScreen extends StatefulWidget {
  const EditClientProfileScreen({super.key});

  @override
  State<EditClientProfileScreen> createState() =>
      _EditClientProfileScreenState();
}

class _EditClientProfileScreenState extends State<EditClientProfileScreen> {
  // ---- 스타일

  final picker = ImagePicker();

  // ---- 상태
  bool isLoading = true;
  bool _saving = false;

  String phone = '';
  String logoUrl = '';
  String certificateUrl = '';
  // 심사 상태. 예전엔 이 값이 없어서 심사중·승인·거절이 전부 같은 화면이었고,
  // 거절당한 사장님도 "검토가 진행됩니다"만 계속 봤다.
  String certStatus = 'none';
  String certRejectReason = '';
  String? _authHeaderToken;

  File? selectedLogoImage;
  PlatformFile? selectedCertificateFile;

  // ---- 컨트롤러
  final managerController = TextEditingController();
  final companyController = TextEditingController();
  final emailController = TextEditingController();
  final descriptionController = TextEditingController();

  // ---- helpers
  String _getFullImageUrl(String path) {
    if (path.isEmpty) return path;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    if (path.startsWith('/')) return '$baseUrl$path';
    return '$baseUrl/$path';
  }

  void _showSnackbar(String message) {
    if (!mounted) return;
    final sm = ScaffoldMessenger.of(context);
    sm.hideCurrentSnackBar();
    sm.showSnackBar(SnackBar(content: Text(message)));
  }

  String _maskPhone(String raw) {
    final p = raw.replaceAll(RegExp(r'\D'), '');
    if (p.length == 11) return '${p.substring(0, 3)}-${p.substring(3, 7)}-****';
    if (p.length == 10) return '${p.substring(0, 3)}-${p.substring(3, 6)}-****';
    return raw;
  }

  bool get _canSave => !_saving;

  @override
  void initState() {
    super.initState();
    () async {
      _authHeaderToken = await AuthenticatedHttpClient.accessToken();
      if (mounted) setState(() {});
    }();
    _loadProfile();
  }

  @override
  void dispose() {
    managerController.dispose();
    companyController.dispose();
    emailController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  Future<void> _openCertificate() async {
    final url = _getFullImageUrl(certificateUrl);
    if (url.trim().isEmpty) {
      _showSnackbar('열 수 있는 파일이 없어요.');
      return;
    }

    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _showSnackbar('파일을 열 수 없어요.');
    }
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final clientId = prefs.getInt('userId');

    if (clientId == null) {
      _showSnackbar(Msg.loginRequired);
      if (mounted) setState(() => isLoading = false);
      return;
    }

    try {
      final resp = await AuthenticatedHttpClient.get(
        Uri.parse('$baseUrl/api/client/profile?id=$clientId'),
      );

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;

        final fetchedLogoUrl =
            pickFirstNonNull<String>(data, [
              'logo_url',
              'logoUrl',
              'company_logo_url',
              'logo',
            ]) ??
            '';

        final fetchedCertUrl =
            pickFirstNonNull<String>(data, [
              'certificate_url',
              'certificateUrl',
              'business_certificate_url',
              'biz_cert_url',
              'certificate',
            ]) ??
            '';

        if (!mounted) return;
        setState(() {
          phone = data['phone']?.toString() ?? '';
          managerController.text = data['manager_name']?.toString() ?? '';
          companyController.text = data['company_name']?.toString() ?? '';
          emailController.text = data['email']?.toString() ?? '';
          descriptionController.text = data['description']?.toString() ?? '';
          logoUrl = fetchedLogoUrl;
          certificateUrl = fetchedCertUrl;
          // 구버전 서버는 이 필드를 안 준다 — 없으면 서류 유무로 추정한다.
          certStatus =
              data['cert_status']?.toString() ??
              (fetchedCertUrl.isNotEmpty ? 'pending' : 'none');
          certRejectReason = data['cert_reject_reason']?.toString() ?? '';
          isLoading = false;
        });

        // 캐시(선택)
        await prefs.setString('cached_logo_url', logoUrl);
        await prefs.setString('cached_certificate_url', certificateUrl);
      } else {
        debugPrint('프로필 조회 실패 (${resp.statusCode})');
        _showSnackbar(Msg.loadFailed);
        if (mounted) setState(() => isLoading = false);
      }
    } catch (e) {
      _showSnackbar(Msg.network);
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _pickLogoImage() async {
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked != null) {
      setState(() {
        selectedLogoImage = File(picked.path);
      });
    }
  }

  Future<void> _pickCertificateFromCamera() async {
    final picked = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );
    if (picked != null) {
      setState(() {
        selectedCertificateFile = PlatformFile(
          name: picked.name,
          path: picked.path,
          size: File(picked.path).lengthSync(),
          bytes: null,
        );
      });
    }
  }

  Future<void> _pickCertificateFromGallery() async {
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (picked != null) {
      setState(() {
        selectedCertificateFile = PlatformFile(
          name: picked.name,
          path: picked.path,
          size: File(picked.path).lengthSync(),
          bytes: null,
        );
      });
    }
  }

  Future<void> _pickCertificateFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      withData: false,
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        selectedCertificateFile = result.files.single;
      });
    }
  }

  void _showCertificatePickerOptions() {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder:
          (_) => _BottomSheetCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SheetHeader(title: '사업자등록증 업로드'),
                const SizedBox(height: 6),
                _SheetTile(
                  icon: Icons.camera_alt,
                  label: '카메라로 촬영',
                  onTap: () {
                    Navigator.pop(context);
                    _pickCertificateFromCamera();
                  },
                ),
                _SheetTile(
                  icon: Icons.photo,
                  label: '갤러리에서 선택',
                  onTap: () {
                    Navigator.pop(context);
                    _pickCertificateFromGallery();
                  },
                ),
                _SheetTile(
                  icon: Icons.insert_drive_file,
                  label: '파일에서 선택 (PDF 가능)',
                  onTap: () {
                    Navigator.pop(context);
                    _pickCertificateFromFile();
                  },
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
    );
  }

  Future<void> _saveProfile() async {
    if (_saving) return;

    if (phone.isEmpty) {
      _showSnackbar(Msg.loginRequired);
      return;
    }

    final managerName = managerController.text.trim();
    final companyName = companyController.text.trim();
    final email = emailController.text.trim();
    final description = descriptionController.text.trim();

    if (companyName.isEmpty) {
      _showSnackbar('회사명을 입력해주세요.');
      return;
    }
    if (managerName.isEmpty) {
      _showSnackbar('담당자명을 입력해주세요.');
      return;
    }

    setState(() => _saving = true);

    try {
      final uri = Uri.parse('$baseUrl/api/client/upload-logo');
      final streamed = await AuthenticatedHttpClient.sendMultipart((
        token,
      ) async {
        final request = http.MultipartRequest('POST', uri);
        request.headers['Authorization'] = 'Bearer $token';
        request.fields['phone'] = phone;
        request.fields['manager_name'] = managerName;
        request.fields['company_name'] = companyName;
        request.fields['email'] = email;
        request.fields['description'] = description;

        if (selectedLogoImage != null) {
          request.files.add(
            await http.MultipartFile.fromPath(
              'logo',
              selectedLogoImage!.path,
              contentType: MediaType('image', 'jpeg'),
            ),
          );
        }

        if (selectedCertificateFile != null &&
            selectedCertificateFile!.path != null) {
          final ext = (selectedCertificateFile!.extension ?? '').toLowerCase();
          final isPdf = ext == 'pdf';
          final mime =
              isPdf ? 'application/pdf' : 'image/${ext.isEmpty ? 'jpeg' : ext}';

          request.files.add(
            http.MultipartFile.fromBytes(
              'certificate',
              File(selectedCertificateFile!.path!).readAsBytesSync(),
              filename: selectedCertificateFile!.name,
              contentType: MediaType.parse(mime),
            ),
          );
        }
        return request;
      });
      final body = await streamed.stream.bytesToString();

      if (!mounted) return;

      if (streamed.statusCode == 200) {
        _showSnackbar('저장했어요. 최신 정보를 불러올게요.');
        await _loadProfile();
        setState(() {
          selectedLogoImage = null;
          selectedCertificateFile = null;
        });
      } else {
        debugPrint('upload error ${streamed.statusCode}: $body');
        debugPrint('프로필 저장 실패 (${streamed.statusCode})');
        _showSnackbar(Msg.saveFailed);
      }
    } catch (e) {
      debugPrint('save error: $e');
      if (mounted) _showSnackbar(Msg.network);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmLeaveIfDirty() async {
    final dirty = selectedLogoImage != null || selectedCertificateFile != null;
    if (!dirty) {
      if (mounted) Navigator.pop(context);
      return;
    }

    final ok = await showAppSheet(
      context,
      title: '저장하지 않고 나갈까요?',
      message: '바꾼 내용은 저장되지 않아요.',
      confirmLabel: '나가기',
      cancelLabel: '계속 수정',
      destructive: true,
    );

    if (ok == true && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPage,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        leading: IconButton(
          tooltip: '뒤로',
          icon: const Icon(Icons.arrow_back),
          onPressed: _confirmLeaveIfDirty,
        ),
        title: const Text('계정 관리'),
        // 저장은 하단 고정 바 하나로 통일 (우상단 저장 버튼 중복 제거)
      ),

      // 저장 버튼을 하단 고정 + SafeArea로 올림 (안드 뒤로가기 영역 회피)
      bottomNavigationBar: AppBottomBar(
        child: AppPrimaryButton(
          label: '저장하기',
          loading: _saving,
          height: 52,
          onPressed: _canSave ? _saveProfile : null,
        ),
      ),

      body:
          isLoading
              ? const AppSkeletonList(rows: 4)
              : RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _loadProfile,
                child: ListView(
                  padding: const EdgeInsets.only(top: 8, bottom: 16),
                  children: [
                    _profileHeaderCard(),
                    const SizedBox(height: 8),
                    _SectionCard(
                      title: '기본 정보',
                      children: [
                        _LabeledField(
                          label: '담당자명',
                          child: TextField(
                            controller: managerController,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              hintText: '예) 홍길동',
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _LabeledField(
                          label: '회사명',
                          child: TextField(
                            controller: companyController,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              hintText: '예) 알바일주',
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _LabeledField(
                          label: '이메일',
                          child: TextField(
                            controller: emailController,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            decoration: const InputDecoration(
                              hintText: '예) hello@company.com',
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _LabeledField(
                          label: '회사 소개',
                          child: TextField(
                            controller: descriptionController,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              hintText: '간단한 소개를 입력해주세요.',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _certificateSection(),

                    // 여기 있던 _SaveButton 제거 (bottomNavigationBar로 이동)
                    const SizedBox(height: 8),
                  ],
                ),
              ),
    );
  }

  Widget _profileHeaderCard() {
    final hasRemoteLogo = logoUrl.trim().isNotEmpty;
    final imgProvider =
        selectedLogoImage != null
            ? FileImage(selectedLogoImage!)
            : (hasRemoteLogo ? NetworkImage(_getFullImageUrl(logoUrl)) : null);

    return Container(
      color: AppColors.bgCard,
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: AppColors.bgMuted,
                backgroundImage: imgProvider as ImageProvider?,
                child:
                    (imgProvider == null)
                        ? const Icon(
                          Icons.business,
                          size: 32,
                          color: AppColors.textSecondary,
                        )
                        : null,
              ),
              Positioned(
                bottom: -2,
                right: -2,
                child: Material(
                  color: Colors.white,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _pickLogoImage,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: AppColors.bgCard,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Icon(
                        Icons.photo_camera_outlined,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  companyController.text.trim().isEmpty
                      ? '회사명'
                      : companyController.text.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.h3,
                ),
                const SizedBox(height: 4),
                Text(
                  _maskPhone(phone),
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: AppFontSize.body2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 심사 상태를 문장으로 보여준다. 이게 없어서 거절당한 사장님도 "검토가
  // 진행됩니다"만 계속 봤고, 1년 넘게 묻힌 신청도 본인은 알 길이 없었다.
  Widget _certStatusBanner() {
    late final String text;
    late final Color fg;
    late final Color bg;

    switch (certStatus) {
      case 'approved':
        text = '안심기업으로 승인되었어요. 공고에 «안심기업» 표시가 붙습니다.';
        fg = AppColors.badgeSafe;
        bg = const Color(0xFFF3F8EC);
        break;
      case 'pending':
        text = '서류를 검토하고 있어요. 결과는 알림으로 알려드립니다.';
        fg = AppColors.textSecondary;
        bg = AppColors.bgMuted;
        break;
      case 'rejected':
        text = certRejectReason.isNotEmpty
            ? '승인되지 않았어요. 사유: $certRejectReason\n서류를 다시 올리면 재심사합니다.'
            : '승인되지 않았어요. 서류를 다시 올리면 재심사합니다.';
        fg = AppColors.warningDark;
        bg = const Color(0xFFFEF3EC);
        break;
      default:
        text = '사업자등록증을 올리면 관리자 검토 후 «안심기업» 표시가 적용됩니다.';
        fg = AppColors.textSecondary;
        bg = AppColors.bgMuted;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: AppFontSize.body2, color: fg, height: 1.4),
      ),
    );
  }

  Widget _certificateSection() {
    final hasLocal = selectedCertificateFile != null;
    final extLocal = selectedCertificateFile?.extension?.toLowerCase().trim();
    final isPdfLocal = extLocal == 'pdf';

    final hasRemote = certificateUrl.trim().isNotEmpty;
    final urlLower = certificateUrl.toLowerCase().trim();
    final isPdfRemote = RegExp(r'\.pdf($|\?)').hasMatch(urlLower);

    Widget preview;

    if (hasLocal) {
      preview =
          isPdfLocal
              ? _pdfRow(selectedCertificateFile!.name)
              : ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Image.file(
                  File(selectedCertificateFile!.path!),
                  height: 120,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              );
    } else if (hasRemote) {
      if (isPdfRemote) {
        preview = _pdfRow('업로드된 사업자등록증 (PDF)');
      } else {
        preview = ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Image(
            height: 120,
            width: double.infinity,
            fit: BoxFit.cover,
            image: NetworkImage(
              _getFullImageUrl(certificateUrl),
              headers: {
                if ((_authHeaderToken ?? '').isNotEmpty)
                  'Authorization': 'Bearer ${_authHeaderToken!}',
              },
            ),
            errorBuilder:
                (_, __, ___) => Container(
                  height: 120,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.bgMuted,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: const Text(
                    '파일을 불러오지 못했어요.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
          ),
        );
      }
    } else {
      preview = const Text('아직 올린 파일이 없어요', style: AppTextStyles.body2);
    }

    return _SectionCard(
      title: '사업자등록증',
      trailing: TextButton(onPressed: _showCertificatePickerOptions, child: const Text('파일 올리기')),
      children: [
        _certStatusBanner(),
        const SizedBox(height: 10),
        preview,
        // 늘 보이던 버튼 두 개(대개 둘 다 꺼짐) → 쓸 수 있을 때만 글자 링크
        if (hasRemote || hasLocal)
          Row(
            children: [
              if (hasRemote) TextButton(onPressed: _openCertificate, child: const Text('올린 파일 보기')),
              if (hasLocal)
                TextButton(
                  onPressed: () => setState(() => selectedCertificateFile = null),
                  child: const Text('선택 취소'),
                ),
            ],
          ),
      ],
    );
  }

  Widget _pdfRow(String name) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.bgMuted,
      borderRadius: BorderRadius.circular(AppRadius.md),
    ),
    child: Row(
      children: [
        const Icon(Icons.picture_as_pdf_outlined, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
      ],
    ),
  );
}

/* --------------------------- UI pieces --------------------------- */

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.children,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgCard,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: AppTextStyles.h3)),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final Widget child;

  const _LabeledField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Theme(
          data: theme.copyWith(
            inputDecorationTheme: InputDecorationTheme(
              isDense: true,
              filled: true,
              fillColor: AppColors.bgMuted,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: const BorderSide(
                  color: AppColors.primary,
                  width: 1.3,
                ),
              ),
            ),
          ),
          child: child,
        ),
      ],
    );
  }
}

class _BottomSheetCard extends StatelessWidget {
  final Widget child;
  const _BottomSheetCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.of(context).viewPadding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + bottomSafe),
      child: child,
    );
  }
}

class _SheetHeader extends StatelessWidget {
  final String title;
  const _SheetHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 42,
          height: 5,
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            title,
            style: const TextStyle(fontSize: AppFontSize.buttonLg, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _SheetTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SheetTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      onTap: onTap,
    );
  }
}

/* --------------------------- Confirm Sheet --------------------------- */

