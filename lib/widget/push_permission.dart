import 'package:app_settings/app_settings.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:iljujob/config/app_theme.dart';
import 'package:iljujob/data/services/screen_analytics_service.dart';
import 'package:iljujob/main.dart' show sendFcmTokenUnified;

/// 알림 권한 — 앱을 켜자마자 묻지 않는다.
/// 이유를 모르는 첫 실행 팝업에서 거부가 많았다(9월 신규 구직자 58% 토큰 없음).
/// 구직자는 첫 공고 상세를 본 뒤, 사장님은 홈 진입 시 한 번.
///
/// 거부된 뒤에는 OS 가 다시 묻지 않으므로 설정 화면으로 보낸다.
/// Android 13+ 는 묻기 전에도 상태가 denied 로 보여서 '물어봤는지'를 따로 기억한다.
const _kAskedKey = 'push_permission_asked';
const _kPrimerShownKey = 'push_primer_shown';

Future<bool> isPushAllowed() async {
  try {
    final s = await FirebaseMessaging.instance.getNotificationSettings();
    return s.authorizationStatus == AuthorizationStatus.authorized ||
        s.authorizationStatus == AuthorizationStatus.provisional;
  } catch (_) {
    return true; // 조회 실패 시 안내를 띄우지 않는다
  }
}

/// OS 팝업(처음) 또는 설정 화면(이미 거부)으로 보낸다. 허용되면 토큰까지 올린다.
Future<bool> requestPushPermission({required String source}) async {
  final prefs = await SharedPreferences.getInstance();
  final asked = prefs.getBool(_kAskedKey) ?? false;
  if (await isPushAllowed()) return true;

  final before =
      (await FirebaseMessaging.instance.getNotificationSettings())
          .authorizationStatus;
  if (asked && before == AuthorizationStatus.denied) {
    ScreenAnalyticsService.instance.logEvent(
      'push_permission',
      params: {'source': source, 'result': 'open_settings'},
    );
    await AppSettings.openAppSettings(type: AppSettingsType.notification);
    return false;
  }

  await prefs.setBool(_kAskedKey, true);
  final s = await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );
  final ok =
      s.authorizationStatus == AuthorizationStatus.authorized ||
      s.authorizationStatus == AuthorizationStatus.provisional;
  ScreenAnalyticsService.instance.logEvent(
    'push_permission',
    params: {'source': source, 'result': ok ? 'granted' : 'denied'},
  );
  if (ok) await sendFcmTokenUnified();
  return ok;
}

/// 구직자 첫 공고 상세 뒤 한 번: 왜 필요한지 먼저 말하고 묻는다.
Future<void> maybeShowPushPrimer(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_kPrimerShownKey) ?? false) return;
  if (await isPushAllowed()) return;
  await prefs.setBool(_kPrimerShownKey, true);
  if (!context.mounted) return;

  final want = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder:
        (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.notifications_active_outlined,
                  size: 36,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  '이런 공고, 근처에 올라오면\n바로 알려드릴까요?',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.h3.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '일급 알바는 하루 안에 마감되는 경우가 많아요.\n사장님이 먼저 연락하면 그것도 알려드려요.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body2.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    child: const Text('알림 받기'),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(
                    '나중에',
                    style: AppTextStyles.body2.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
  );
  if (want == true) {
    await requestPushPermission(source: 'job_detail_primer');
  } else {
    ScreenAnalyticsService.instance.logEvent(
      'push_permission',
      params: {'source': 'job_detail_primer', 'result': 'later'},
    );
  }
}

/// 홈 상단 한 줄. 알림이 꺼져 있을 때만 보인다. 닫으면 이번 실행 동안 숨긴다.
class PushOffBanner extends StatefulWidget {
  final String message;
  final String source;
  const PushOffBanner({super.key, required this.message, required this.source});

  @override
  State<PushOffBanner> createState() => _PushOffBannerState();
}

class _PushOffBannerState extends State<PushOffBanner>
    with WidgetsBindingObserver {
  static bool _dismissed = false;
  bool _off = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 설정 화면에서 켜고 돌아오면 사라지게.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final allowed = await isPushAllowed();
    if (mounted) setState(() => _off = !allowed);
  }

  @override
  Widget build(BuildContext context) {
    if (!_off || _dismissed) return const SizedBox.shrink();
    // 목록 사이 얇은 회색 띠 (카드형은 공고 줄과 결이 달랐다 — 2026-10)
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 6, 12, 6),
      color: AppColors.bgMuted,
      child: Row(
        children: [
          const Icon(
            Icons.notifications_off_outlined,
            size: 18,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.message,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              await requestPushPermission(source: widget.source);
              await _check();
            },
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
            ),
            child: const Text('켜기'),
          ),
          GestureDetector(
            onTap: () => setState(() => _dismissed = true),
            child: const Icon(
              Icons.close,
              size: 16,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
