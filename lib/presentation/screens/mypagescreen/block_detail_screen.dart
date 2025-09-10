// lib/presentation/screens/mypagescreen/block_detail_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../config/constants.dart'; // baseUrl이 정의되어 있다면 여기에 있어야 합니다.
import 'dart:async';
import 'package:http/http.dart' as http;
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

    final res = await http.get(Uri.parse('$baseUrl/api/user-block/list?userId=$userId'));
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

  Future<void> _unblockUser(int targetId, String targetType) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId') ?? 0;

    await http.post(
      Uri.parse('$baseUrl/api/user-block/unblock'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'userId': userId,
        'targetId': targetId,
        'targetType': targetType,
      }),
    );

    _loadBlockedUsers(); // 차단 해제 후 다시 목록 불러오기
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('차단한 사용자')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : blockedUsers.isEmpty
              ? const Center(child: Text('차단한 사용자가 없습니다.'))
              : ListView.separated(
                  itemCount: blockedUsers.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final user = blockedUsers[index];
                    return ListTile(
                      leading: const Icon(Icons.person_off),
                      title: Text(user['name'] ?? '이름 없음'),
                      subtitle: Text(user['type'] == 'worker' ? '구직자' : '기업'),
                      trailing: TextButton(
                        child: const Text('차단 해제'),
                        onPressed: () => _unblockUser(user['id'], user['type']),
                      ),
                    );
                  },
                ),
    );
  }
}