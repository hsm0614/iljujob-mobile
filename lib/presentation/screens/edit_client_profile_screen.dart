import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/constants.dart';

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
  State<EditClientProfileScreen> createState() => _EditClientProfileScreenState();
}

class _EditClientProfileScreenState extends State<EditClientProfileScreen> {
  // ---- 스타일
  static const kBrand = Color(0xFF3B8AFF);
  static const kBg = Color(0xFFF6F7FB);

  final picker = ImagePicker();

  // ---- 상태
  bool isLoading = true;
  bool _saving = false;

  String phone = '';
  String logoUrl = '';
  String certificateUrl = '';
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
      final prefs = await SharedPreferences.getInstance();
      _authHeaderToken = prefs.getString('authToken');
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
      _showSnackbar('열 수 있는 파일이 없습니다.');
      return;
    }

    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _showSnackbar('파일을 열 수 없습니다.');
    }
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final clientId = prefs.getInt('userId');

    if (clientId == null) {
      _showSnackbar('로그인 정보가 없습니다.');
      if (mounted) setState(() => isLoading = false);
      return;
    }

    try {
      final token = prefs.getString('authToken') ?? '';
      final resp = await http.get(
        Uri.parse('$baseUrl/api/client/profile?id=$clientId'),
        headers: token.isNotEmpty ? {'Authorization': 'Bearer $token'} : {},
      );

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;

        final fetchedLogoUrl = pickFirstNonNull<String>(
              data,
              ['logo_url', 'logoUrl', 'company_logo_url', 'logo'],
            ) ??
            '';

        final fetchedCertUrl = pickFirstNonNull<String>(
              data,
              [
                'certificate_url',
                'certificateUrl',
                'business_certificate_url',
                'biz_cert_url',
                'certificate',
              ],
            ) ??
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
          isLoading = false;
        });

        // 캐시(선택)
        await prefs.setString('cached_logo_url', logoUrl);
        await prefs.setString('cached_certificate_url', certificateUrl);
      } else {
        _showSnackbar('프로필을 불러오지 못했습니다. (${resp.statusCode})');
        if (mounted) setState(() => isLoading = false);
      }
    } catch (e) {
      _showSnackbar('네트워크 오류가 발생했습니다.');
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _pickLogoImage() async {
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) {
      setState(() {
        selectedLogoImage = File(picked.path);
      });
    }
  }

  Future<void> _pickCertificateFromCamera() async {
    final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 90);
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
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
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
      builder: (_) => _BottomSheetCard(
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

    final prefs = await SharedPreferences.getInstance();
    final userPhone = prefs.getString('userPhone');
    if (userPhone == null || userPhone.isEmpty) {
      _showSnackbar('로그인 정보가 없습니다.');
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
      final request = http.MultipartRequest('POST', uri);

      final token = prefs.getString('authToken');
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      request.fields['phone'] = userPhone;
      request.fields['manager_name'] = managerName;
      request.fields['company_name'] = companyName;
      request.fields['email'] = email;
      request.fields['description'] = description;

      if (selectedLogoImage != null) {
        request.files.add(await http.MultipartFile.fromPath(
          'logo',
          selectedLogoImage!.path,
          contentType: MediaType('image', 'jpeg'),
        ));
      }

      if (selectedCertificateFile != null && selectedCertificateFile!.path != null) {
        final ext = (selectedCertificateFile!.extension ?? '').toLowerCase();
        final isPdf = ext == 'pdf';
        final mime = isPdf ? 'application/pdf' : 'image/${ext.isEmpty ? 'jpeg' : ext}';

        request.files.add(http.MultipartFile.fromBytes(
          'certificate',
          File(selectedCertificateFile!.path!).readAsBytesSync(),
          filename: selectedCertificateFile!.name,
          contentType: MediaType.parse(mime),
        ));
      }

      final streamed = await request.send();
      final body = await streamed.stream.bytesToString();

      if (!mounted) return;

      if (streamed.statusCode == 200) {
        _showSnackbar('저장되었습니다. 최신 정보를 불러옵니다.');
        await _loadProfile();
        setState(() {
          selectedLogoImage = null;
          selectedCertificateFile = null;
        });
      } else {
        debugPrint('upload error ${streamed.statusCode}: $body');
        _showSnackbar('저장에 실패했습니다. (${streamed.statusCode})');
      }
    } catch (e) {
      debugPrint('save error: $e');
      if (mounted) _showSnackbar('네트워크 오류가 발생했습니다.');
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

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ConfirmSheet(
        title: '저장하지 않고 나갈까요?',
        message: '변경 사항이 저장되지 않습니다.',
        confirmText: '나가기',
        confirmColor: const Color(0xFFDC2626),
        icon: Icons.warning_amber_rounded,
      ),
    );

    if (ok == true && mounted) Navigator.pop(context);
  }

  @override
Widget build(BuildContext context) {
  final bottomSafe = MediaQuery.of(context).viewPadding.bottom;

  return Scaffold(
    backgroundColor: kBg,
    resizeToAvoidBottomInset: true,
    appBar: AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      iconTheme: const IconThemeData(color: Colors.black),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: _confirmLeaveIfDirty,
      ),
      title: const Text(
        '계정 관리',
        style: TextStyle(
          fontFamily: 'Jalnan2TTF',
          color: kBrand,
          fontSize: 20,
        ),
      ),
      actions: [
        TextButton(
          onPressed: _canSave ? _saveProfile : null,
          child: Text(
            _saving ? '저장 중…' : '저장',
            style: TextStyle(
              color: _canSave ? kBrand : Colors.black26,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 6),
      ],
    ),

    // ✅ 저장 버튼을 하단 고정 + SafeArea로 올림 (안드 뒤로가기 영역 회피)
    bottomNavigationBar: SafeArea(
      top: false,
      child: Container(
        color: kBg,
        padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + (bottomSafe > 0 ? 0 : 0)),
        child: _SaveButton(
          busy: _saving,
          onPressed: _canSave ? _saveProfile : null,
        ),
      ),
    ),

    body: isLoading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            color: kBrand,
            onRefresh: _loadProfile,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              children: [
                _profileHeaderCard(),
                const SizedBox(height: 14),
                _SectionCard(
                  title: '기본 정보',
                  children: [
                    _LabeledField(
                      label: '담당자명',
                      child: TextField(
                        controller: managerController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(hintText: '예) 홍길동'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _LabeledField(
                      label: '회사명',
                      child: TextField(
                        controller: companyController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(hintText: '예) 알바일주'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _LabeledField(
                      label: '이메일',
                      child: TextField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(hintText: '예) hello@company.com'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _LabeledField(
                      label: '회사 소개',
                      child: TextField(
                        controller: descriptionController,
                        maxLines: 3,
                        decoration: const InputDecoration(hintText: '간단한 소개를 입력해주세요.'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _certificateSection(),

                // ❌ 여기 있던 _SaveButton 제거 (bottomNavigationBar로 이동)
                const SizedBox(height: 8),
              ],
            ),
          ),
  );
}

  Widget _profileHeaderCard() {
    final hasRemoteLogo = logoUrl.trim().isNotEmpty;
    final imgProvider = selectedLogoImage != null
        ? FileImage(selectedLogoImage!)
        : (hasRemoteLogo ? NetworkImage(_getFullImageUrl(logoUrl)) : null);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 6)),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: const Color(0xFFEAF2FF),
                backgroundImage: imgProvider as ImageProvider?,
                child: (imgProvider == null)
                    ? const Icon(Icons.business, size: 32, color: Colors.black54)
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
                        color: kBrand,
                        shape: BoxShape.circle,
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                      ),
                      child: const Icon(Icons.edit, size: 16, color: Colors.white),
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
                  companyController.text.trim().isEmpty ? '회사명' : companyController.text.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  _maskPhone(phone),
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          IconButton.filledTonal(
            onPressed: _pickLogoImage,
            icon: const Icon(Icons.photo_camera_back_outlined),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFEAF2FF),
              foregroundColor: kBrand,
            ),
          ),
        ],
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
      preview = isPdfLocal
          ? _pdfRow(selectedCertificateFile!.name)
          : ClipRRect(
              borderRadius: BorderRadius.circular(12),
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
          borderRadius: BorderRadius.circular(12),
          child: Image(
            height: 120,
            width: double.infinity,
            fit: BoxFit.cover,
            image: NetworkImage(
              _getFullImageUrl(certificateUrl),
              headers: {
                if ((_authHeaderToken ?? '').isNotEmpty) 'Authorization': 'Bearer ${_authHeaderToken!}',
              },
            ),
            errorBuilder: (_, __, ___) => Container(
              height: 120,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('파일을 불러오지 못했습니다.', style: TextStyle(color: Colors.black45)),
            ),
          ),
        );
      }
    } else {
      preview = Container(
        height: 90,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        alignment: Alignment.center,
        child: const Text('아직 업로드된 파일이 없습니다.', style: TextStyle(color: Colors.black45)),
      );
    }

    return _SectionCard(
      title: '사업자등록증',
      trailing: TextButton.icon(
        onPressed: _showCertificatePickerOptions,
        icon: const Icon(Icons.upload_file),
        label: const Text('업로드'),
      ),
      children: [
        Text(
          '업로드 후 관리자 검토가 진행됩니다. 검토 완료 시 “안심기업” 표시가 적용됩니다.',
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600, height: 1.35),
        ),
        const SizedBox(height: 10),
        preview,
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: hasRemote ? _openCertificate : null,
                icon: const Icon(Icons.open_in_new),
                label: const Text('기존 파일 열기'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kBrand,
                  side: const BorderSide(color: Color(0xFFD1E3FF)),
                  backgroundColor: const Color(0xFFEAF2FF),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: hasLocal
                    ? () => setState(() => selectedCertificateFile = null)
                    : null,
                icon: const Icon(Icons.close),
                label: const Text('선택 해제'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.black54,
                  side: BorderSide(color: Colors.grey.shade300),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _pdfRow(String name) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1F2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: Row(
          children: [
            const Icon(Icons.picture_as_pdf, color: Colors.red),
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 18,
                decoration: BoxDecoration(
                  color: _EditClientProfileScreenState.kBrand,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Jalnan2TTF',
                    fontSize: 15,
                    color: Colors.black87,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 10),
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
        Text(label, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Theme(
          data: theme.copyWith(
            inputDecorationTheme: InputDecorationTheme(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _EditClientProfileScreenState.kBrand, width: 1.3),
              ),
            ),
          ),
          child: child,
        ),
      ],
    );
  }
}

class _SaveButton extends StatelessWidget {
  final bool busy;
  final VoidCallback? onPressed;

  const _SaveButton({required this.busy, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.save_outlined),
        label: Text(busy ? '저장 중…' : '저장하기'),
        style: ElevatedButton.styleFrom(
          backgroundColor: _EditClientProfileScreenState.kBrand,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
      ),
    );
  }
}

/* --------------------------- Bottom Sheets --------------------------- */

class _BottomSheetCard extends StatelessWidget {
  final Widget child;
  const _BottomSheetCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.of(context).viewPadding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
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
            color: const Color(0xFFE5E7EB),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        ),
      ],
    );
  }
}

class _SheetTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SheetTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: _EditClientProfileScreenState.kBrand),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      onTap: onTap,
    );
  }
}

/* --------------------------- Confirm Sheet --------------------------- */

class _ConfirmSheet extends StatelessWidget {
  final String title;
  final String message;
  final String confirmText;
  final Color confirmColor;
  final IconData icon;

  const _ConfirmSheet({
    required this.title,
    required this.message,
    required this.confirmText,
    required this.confirmColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.of(context).viewPadding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomSafe),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFFE5E7EB),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: confirmColor.withOpacity(0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: confirmColor),
          ),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF6B7280), height: 1.35),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF111827),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('취소', style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: confirmColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: Text(confirmText, style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
