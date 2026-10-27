// lib/presentation/screens/mypagescreen/block_detail_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../config/constants.dart'; // baseUrl이 정의되어 있다면 여기에 있어야 합니다.
import 'dart:async';
import '../../../config/app_theme.dart';
import '../../../widget/app_ui.dart';
import '../../../data/services/authenticated_http_client.dart';

class BlockedUserListScreen extends StatefulWidget {
  const BlockedUserListScreen({super.key});

  @override
  State<BlockedUserListScreen> createState() => _BlockedUserListScreenState();
}

class _BlockedUserListScreenState extends State<BlockedUserListScreen> {
  List<Map<String, dynamic>> blockedUsers = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBlockedUsers();
  }

  Future<void> _loadBlockedUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId') ?? 0;

    final res = await AuthenticatedHttpClient.get(
      Uri.parse('$baseUrl/api/user-block/list?userId=$userId'),
    );
    if (res.statusCode == 200) {
      final data = List<Map<String, dynamic>>.from(jsonDecode(res.body));
      setState(() {
        blockedUsers = data;
        isLoading = false;
      });
    } else {
      setState(() => isLoading = false);
    }
  }

  Future<void> _unblockUser(Map<String, dynamic> user) async {
    final ok = await showAppSheet(
      context,
      title: '${user['name'] ?? '이 사용자'}님 차단을 풀까요?',
      message: '다시 채팅과 공고 제안을 주고받을 수 있어요.',
      confirmLabel: '차단 해제',
      cancelLabel: '취소',
    );
    if (!ok) return;

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId') ?? 0;

    await AuthenticatedHttpClient.postJson(
      Uri.parse('$baseUrl/api/user-block/unblock'),
      body: {'userId': userId, 'targetId': user['id'], 'targetType': user['type']},
    );

    _loadBlockedUsers(); // 차단 해제 후 다시 목록 불러오기
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('차단한 사용자')),
      body:
          isLoading
              ? const Center(child: CircularProgressIndicator())
              : blockedUsers.isEmpty
              ? const AppEmptyState(
                icon: Icons.block_rounded,
                title: '차단한 사용자가 없어요',
                message: '채팅방 오른쪽 위 메뉴에서 차단할 수 있어요.',
              )
              : ListView(
                children: [
                  AppMenuSection(
                    children: [
                      for (final user in blockedUsers)
                        AppMenuRow(
                          label: (user['name'] ?? '이름 없음').toString(),
                          subtitle: user['type'] == 'worker' ? '구직자' : '사장님',
                          trailing: TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.textSecondary,
                              backgroundColor: AppColors.bgMuted,
                              textStyle: AppTextStyles.btnSm,
                            ),
                            onPressed: () => _unblockUser(user),
                            child: const Text('차단 해제'),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
    );
  }
}
