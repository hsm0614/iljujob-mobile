import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:iljujob/config/app_theme.dart';
import 'package:iljujob/config/constants.dart';
import 'package:iljujob/data/services/authenticated_http_client.dart';
import 'package:iljujob/data/services/screen_analytics_service.dart';
import 'package:iljujob/presentation/screens/TermsDetailScreen.dart';
import 'package:iljujob/widget/push_permission.dart';

/// 알바생 동의 받기 — 카카오·애플 가입에는 약관 화면이 없었다.
/// 2026-11 실측: 최근 60일 카카오 가입 1,396명 중 위치 동의 61명(4%), 애플 0명.
/// 위치·광고성 정보 동의가 없으면 근처 공고 알림 대상에서 빠진다.
class _Item {
  final String key, label, asset, title;
  final bool required;
  const _Item(this.key, this.label, this.asset, this.title, {this.required = false});
}

const _terms = _Item('terms', '[필수] 서비스 이용약관 및 커뮤니티 정책', 'assets/terms/terms_of_service.txt', '서비스 이용약관', required: true);
const _privacy = _Item('privacy', '[필수] 개인정보 수집 및 이용', 'assets/terms/privacy_policy.txt', '개인정보 처리방침', required: true);
const _location = _Item('location', '위치기반서비스 이용', 'assets/terms/location_terms.txt', '위치기반서비스 이용약관');
const _marketing = _Item('marketing', '공고 추천 알림(광고성 정보) 수신', 'assets/terms/marketing_terms.txt', '마케팅 수신 동의');

const _askedKey = 'worker_nearby_consent_asked_v1';

/// 카카오·애플 신규 가입 직후. 필수 항목에 동의해야 닫힌다.
Future<void> showSignupConsentSheet(BuildContext context) async {
  final agreed = await _show(
    context,
    title: '알바일주 이용에 동의해 주세요',
    message: null,
    items: [
      _terms,
      _privacy,
      const _Item('location', '[필수] 위치기반서비스 이용', 'assets/terms/location_terms.txt', '위치기반서비스 이용약관', required: true),
      const _Item('marketing', '[선택] 공고 추천 알림(광고성 정보) 수신', 'assets/terms/marketing_terms.txt', '마케팅 수신 동의'),
    ],
    confirmLabel: '동의하고 시작하기',
    dismissible: false,
  );
  if (agreed != null && context.mounted) await _save(context, agreed, 'signup_social');
}

/// 기존 알바생: 위치·광고성 정보 동의가 없으면 홈에서 한 번. 보여줬으면 true.
Future<bool> maybeShowNearbyConsentSheet(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_askedKey) ?? false) return false;
  final workerId = prefs.getInt('userId');
  if (workerId == null) return false;

  Map<String, dynamic> p;
  try {
    final res = await AuthenticatedHttpClient.get(Uri.parse('$baseUrl/api/worker/profile?id=$workerId'));
    if (res.statusCode != 200) return false;
    p = jsonDecode(res.body) as Map<String, dynamic>;
  } catch (_) {
    return false;
  }
  bool on(Object? v) => v == 1 || v == true;
  final items = [
    if (!on(p['agreed_location'])) _location,
    if (!on(p['agreed_marketing'])) _marketing,
  ];
  if (items.isEmpty) {
    await prefs.setBool(_askedKey, true);
    return false;
  }
  if (!context.mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return false;
  prefs.setBool(_askedKey, true); // 기다리지 않는다 — 아래 context 사용 전에 비동기 틈을 두지 않기 위해

  final agreed = await _show(
    context,
    title: '근처에 새 일급 공고가 올라오면\n바로 알려드릴까요?',
    message: '일급 알바는 하루 안에 마감되는 경우가 많아요.\n내 위치 근처 공고만 골라 앱 알림으로 보내 드려요.',
    items: items,
    confirmLabel: '알림 받기',
    dismissible: true,
  );
  ScreenAnalyticsService.instance.logEvent('worker_consent_sheet', params: {
    'result': agreed == null ? 'later' : agreed.join(','),
  });
  if (agreed == null || !context.mounted) return true;
  await _save(context, agreed, 'home_sheet');
  if (agreed.contains('marketing')) await requestPushPermission(source: 'consent_sheet');
  return true;
}

Future<void> _save(BuildContext context, Set<String> agreed, String source) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final res = await AuthenticatedHttpClient.postJson(
      Uri.parse('$baseUrl/api/worker/consents'),
      body: {for (final k in agreed) k: true, 'source': source},
    );
    // 광고성 정보 수신 동의 처리 결과 통지(정보통신망법 제50조 ⑦): 전송자·일자·처리 내용
    if (res.statusCode == 200 && agreed.contains('marketing')) {
      final now = DateTime.now();
      messenger.showSnackBar(SnackBar(
        content: Text('알바일주 공고 추천 알림 수신에 동의하셨어요 (${now.year}. ${now.month}. ${now.day}.)'),
      ));
    }
  } catch (_) {
    // 저장 실패 시 다음 홈 진입 때 다시 묻지 않는다 — 알림 설정에서 켤 수 있다.
  }
}

Future<Set<String>?> _show(
  BuildContext context, {
  required String title,
  required String? message,
  required List<_Item> items,
  required String confirmLabel,
  required bool dismissible,
}) {
  return showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (ctx) => PopScope(
      canPop: dismissible,
      child: _ConsentBody(
        title: title,
        message: message,
        items: items,
        confirmLabel: confirmLabel,
        dismissible: dismissible,
      ),
    ),
  );
}

class _ConsentBody extends StatefulWidget {
  final String title;
  final String? message;
  final List<_Item> items;
  final String confirmLabel;
  final bool dismissible;
  const _ConsentBody({
    required this.title,
    required this.message,
    required this.items,
    required this.confirmLabel,
    required this.dismissible,
  });

  @override
  State<_ConsentBody> createState() => _ConsentBodyState();
}

class _ConsentBodyState extends State<_ConsentBody> {
  final Set<String> _checked = {};

  bool get _all => _checked.length == widget.items.length;
  bool get _canConfirm =>
      _checked.isNotEmpty && widget.items.where((i) => i.required).every((i) => _checked.contains(i.key));

  Widget _row(_Item item) => Row(
        children: [
          Checkbox(
            value: _checked.contains(item.key),
            onChanged: (v) => setState(() => v == true ? _checked.add(item.key) : _checked.remove(item.key)),
          ),
          Expanded(child: Text(item.label, style: AppTextStyles.body2.copyWith(color: AppColors.textPrimary))),
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => TermsDetailScreen(filePath: item.asset, title: item.title)),
            ),
            child: const Text('보기'),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 24, 16, 16 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(widget.title, style: AppTextStyles.h3.copyWith(color: AppColors.textPrimary)),
          ),
          if (widget.message != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(widget.message!,
                  style: AppTextStyles.body2.copyWith(color: AppColors.textSecondary, height: 1.5)),
            ),
          ],
          const SizedBox(height: 16),
          CheckboxListTile(
            value: _all,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            onChanged: (v) => setState(() {
              _checked.clear();
              if (v == true) _checked.addAll(widget.items.map((i) => i.key));
            }),
            title: Text('모두 동의하기', style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w700)),
          ),
          const Divider(height: 1),
          ...widget.items.map(_row),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _canConfirm ? () => Navigator.pop(context, Set<String>.of(_checked)) : null,
              child: Text(widget.confirmLabel),
            ),
          ),
          if (widget.dismissible)
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('나중에', style: AppTextStyles.body2.copyWith(color: AppColors.textSecondary)),
              ),
            ),
        ],
      ),
    );
  }
}
