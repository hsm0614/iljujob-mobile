import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:iljujob/config/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'admin_user_detail_screen.dart';
class AdminUserListScreen extends StatefulWidget {
  const AdminUserListScreen({super.key});

  @override
  State<AdminUserListScreen> createState() => _AdminUserListScreenState();
}

class _AdminUserListScreenState extends State<AdminUserListScreen>
    with SingleTickerProviderStateMixin {
  List<dynamic> users = [];
  bool isLoading = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchUsers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken') ?? '';

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/admin/users'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        setState(() {
          users = jsonDecode(response.body);
          isLoading = false;
        });
      } else {
        print('❌ 사용자 조회 실패: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('❌ 네트워크 오류: $e');
    }
  }

  Future<void> _deleteUser(int userId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('회원 삭제'),
        content: const Text('정말 이 회원을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken') ?? '';
      try {
        final response = await http.delete(
          Uri.parse('$baseUrl/api/admin/users/$userId'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        );
        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('삭제 완료')),
          );
          _fetchUsers();
        } else {
          print('❌ 삭제 실패: ${response.body}');
        }
      } catch (e) {
        print('❌ 네트워크 삭제 오류: $e');
      }
    }
  }

  List<dynamic> _filterUsersByType(String type) {
    if (type == 'all') return users;
    return users.where((user) => user['type'] == type).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('회원 리스트'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '전체'),
            Tab(text: '알바생'),
            Tab(text: '기업'),
          ],
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildUserList(_filterUsersByType('all')),
                _buildUserList(_filterUsersByType('worker')),
                _buildUserList(_filterUsersByType('client')),
              ],
            ),
    );
  }

  Widget _buildUserList(List<dynamic> filteredUsers) {
    if (filteredUsers.isEmpty) {
      return const Center(child: Text('회원이 없습니다.'));
    }

    return ListView.builder(
      itemCount: filteredUsers.length,
      itemBuilder: (context, index) {
        final user = filteredUsers[index];
        return ListTile(
          leading: const Icon(Icons.person),
          title: Text('${user['name']} (${user['type']})'),
          subtitle: Text(user['phone'] ?? ''),
          trailing: IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () => _deleteUser(user['id']),
          ),
          onTap: () {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => AdminUserDetailScreen(userId: user['id']),
    ),
  );
},
        );
      },
    );
  }
}
