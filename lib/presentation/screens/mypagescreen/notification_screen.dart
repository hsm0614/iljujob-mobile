import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_settings/app_settings.dart'; // ✅ 추가
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

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('알림 설정이 저장되었습니다.')),
      );
    }
  }

  Widget _buildServerToggle(String title,
      {required bool value, required Function(bool) onChanged, String? subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: subtitle != null ? Text(subtitle) : null,
          value: value,
          onChanged: (v) {
            onChanged(v);
            _saveSettings();
          },
          activeColor: Colors.red,
        ),
        const Divider(height: 0),
      ],
    );
  }

  Widget _buildDeviceSettingTile() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: const Text('기기 알림 설정', style: TextStyle(fontWeight: FontWeight.bold)),
          value: true, // 항상 ON 상태처럼 보이게
          onChanged: (_) {
            AppSettings.openAppSettings(); // ✅ 기기 설정 이동
          },
          activeColor: Colors.red,
        ),
        const Divider(height: 0),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('알림설정'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text('기기 알림 설정', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          _buildDeviceSettingTile(),

          const Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text('매칭 관련 알림 동의', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          _buildServerToggle(
            '매칭 관련 알림 동의',
            value: matchAlert,
            onChanged: (v) => setState(() => matchAlert = v),
            subtitle: '매칭 완료, 취소, 채팅 등 활동 알림 수신',
          ),

          const Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text('광고성 정보 수신 동의', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          _buildServerToggle('앱 푸시 수신 동의', value: pushConsent, onChanged: (v) => setState(() => pushConsent = v)),
          _buildServerToggle('SMS/MMS 수신 동의', value: smsConsent, onChanged: (v) => setState(() => smsConsent = v)),
          _buildServerToggle('이메일 수신 동의', value: emailConsent, onChanged: (v) => setState(() => emailConsent = v)),
        ],
      ),
    );
  }
}
