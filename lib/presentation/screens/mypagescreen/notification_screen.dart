import 'package:flutter/material.dart';
import 'package:iljujob/config/app_theme.dart';
import 'package:app_settings/app_settings.dart';
import 'package:iljujob/widget/app_ui.dart';
import '../../../data/services/notificaion_service.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  // 기기 설정은 저장 X
  bool matchAlert = true;
  bool adAlert = true;
  bool pushConsent = true;
  bool smsConsent = false;
  bool emailConsent = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await NotificationService.fetchSettings();
    if (settings != null) {
      setState(() {
        matchAlert = settings['match_alert'] == 1;
        adAlert = settings['ad_alert'] == 1;
        pushConsent = settings['push_consent'] == 1;
        smsConsent = settings['sms_consent'] == 1;
        emailConsent = settings['email_consent'] == 1;
      });
    }
  }

  Future<void> _saveSettings() async {
    final success = await NotificationService.updateSettings({
      'matchAlert': matchAlert,
      'adAlert': adAlert,
      'pushConsent': pushConsent,
      'smsConsent': smsConsent,
      'emailConsent': emailConsent,
    });

    // 토글마다 '저장했어요'를 띄우면 시끄럽다 — 실패만 알린다
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('저장하지 못했어요. 잠시 후 다시 해 주세요.')),
      );
      _loadSettings();
    }
  }

  // 2026-10: 제목과 같은 이름의 토글이 한 번 더 나오던 것 · 늘 켜진 척하던 '기기 알림' 스위치 정리
  Widget _toggle(
    String title, {
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return AppMenuRow(
      label: title,
      subtitle: subtitle,
      onTap: () {
        onChanged(!value);
        _saveSettings();
      },
      trailing: Switch.adaptive(
        value: value,
        activeTrackColor: AppColors.primary,
        onChanged: (v) {
          onChanged(v);
          _saveSettings();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('알림 설정')),
      body: ListView(
        children: [
          AppMenuSection(
            children: [
              AppMenuRow(
                label: '휴대폰 알림 설정',
                subtitle: '알림이 안 오면 여기서 알바일주 알림을 켜 주세요',
                value: '열기',
                onTap: AppSettings.openAppSettings,
              ),
            ],
          ),
          const SizedBox(height: 8),
          AppMenuSection(
            title: '활동 알림',
            children: [
              _toggle(
                '지원·채팅 알림',
                subtitle: '사장님 답장, 채용 확정, 출근 확인',
                value: matchAlert,
                onChanged: (v) => setState(() => matchAlert = v),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AppMenuSection(
            title: '혜택·이벤트 소식',
            children: [
              _toggle(
                '앱 푸시',
                value: pushConsent,
                onChanged: (v) => setState(() => pushConsent = v),
              ),
              _toggle(
                '문자(SMS)',
                value: smsConsent,
                onChanged: (v) => setState(() => smsConsent = v),
              ),
              _toggle(
                '이메일',
                value: emailConsent,
                onChanged: (v) => setState(() => emailConsent = v),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
