import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_theme.dart';

/// 개발용 계정 전환 — 디버그 빌드에서만 보인다 (릴리즈·TestFlight·스토어엔 안 나옴).
/// 로그인 정보가 전부 SharedPreferences에 있어서, 역할별로 통째 저장해 두고 바꿔 끼운다.
/// 처음 한 번: 버튼 → 로그인 화면 → 다른 역할로 로그인. 그 뒤로는 버튼 한 번으로 오간다.
/// 주의: 일반 '로그아웃'은 prefs.clear()라 저장해 둔 계정도 지운다 — 전환은 이 버튼으로만.
const _slot = 'dev_account_slot_';

class DevAccountSwitchButton extends StatelessWidget {
  const DevAccountSwitchButton({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    return Center(
      child: TextButton.icon(
        onPressed: () => _switch(context),
        icon: const Icon(Icons.swap_horiz_rounded, size: 18),
        label: const Text('[개발] 알바생 ↔ 사장님 전환'),
        style: TextButton.styleFrom(foregroundColor: AppColors.textTertiary),
      ),
    );
  }
}

Future<void> _switch(BuildContext context) async {
  final p = await SharedPreferences.getInstance();
  final me = p.getString('userType');
  final mine = {
    for (final k in p.getKeys().where((k) => !k.startsWith(_slot))) k: p.get(k),
  };
  final slots = {
    for (final k in p.getKeys().where((k) => k.startsWith(_slot)))
      k: p.getString(k)!,
  };
  if (me == 'worker' || me == 'client') slots['$_slot$me'] = jsonEncode(mine);

  final other = me == 'client' ? 'worker' : 'client';
  final saved = slots['$_slot$other'];

  await p.clear();
  for (final e in slots.entries) {
    await p.setString(e.key, e.value);
  }
  if (saved != null) {
    for (final e in (jsonDecode(saved) as Map<String, dynamic>).entries) {
      final v = e.value;
      if (v is String) await p.setString(e.key, v);
      if (v is bool) await p.setBool(e.key, v);
      if (v is int) await p.setInt(e.key, v);
      if (v is double) await p.setDouble(e.key, v);
      if (v is List) await p.setStringList(e.key, v.cast<String>());
    }
  }

  if (!context.mounted) return;
  // ponytail: 화면만 새로 연다. 채팅 소켓 등 메모리에 남은 이전 계정 상태가 이상하면 앱을 재시작.
  Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
    saved == null
        ? '/onboarding'
        : other == 'client'
        ? '/client_main'
        : '/home',
    (_) => false,
  );
}
