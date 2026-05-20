// 📁 lib/presentation/screens/worker_screen/labor_consult_screen.dart
// AI 노무 상담 챗봇

import 'package:flutter/material.dart';
import 'package:iljujob/config/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:iljujob/config/constants.dart';

const _blue = AppColors.primary;
const _bg = AppColors.bgPage;
const _label = AppColors.textTertiary;

class _Message {
  final bool isUser;
  final String text;
  final DateTime time;
  _Message({required this.isUser, required this.text, DateTime? time})
    : time = time ?? DateTime.now();
}

class LaborConsultScreen extends StatefulWidget {
  const LaborConsultScreen({super.key});

  @override
  State<LaborConsultScreen> createState() => _LaborConsultScreenState();
}

class _LaborConsultScreenState extends State<LaborConsultScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<_Message> _messages = [];
  bool _loading = false;
  int _remaining = 10;

  // 자주 묻는 질문 빠른 입력
  static const _quickQuestions = [
    '주휴수당 받을 수 있나요?',
    '최저임금이 얼마예요?',
    '일하다 다쳤을 때 어떻게 하나요?',
    '알바도 퇴직금 받나요?',
    '임금을 못 받았어요',
    '4대보험 꼭 들어야 하나요?',
  ];

  @override
  void initState() {
    super.initState();
    _messages.add(
      _Message(
        isUser: false,
        text:
            '안녕하세요! 👋 저는 알바일주 AI 노무 상담사예요.\n\n'
            '주휴수당, 최저임금, 임금체불, 산재보험 등\n'
            '노동법 관련 궁금한 점을 편하게 물어보세요.\n\n'
            '⚠️ 법적 구속력이 있는 공식 답변이 아니므로\n'
            '중요한 사안은 고용노동부(📞1350)를 이용하세요.',
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    text = text.trim();
    if (text.isEmpty || _loading) return;
    _ctrl.clear();

    setState(() {
      _messages.add(_Message(isUser: true, text: text));
      _loading = true;
    });
    _scrollToBottom();

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken') ?? '';

      // 최근 대화 히스토리 (최대 6개)
      final history =
          _messages
              .where((m) => m.text != _messages.first.text) // 인트로 제외
              .toList()
              .reversed
              .take(6)
              .toList()
              .reversed
              .map(
                (m) => {
                  'role': m.isUser ? 'user' : 'assistant',
                  'text': m.text,
                },
              )
              .toList();

      final resp = await http
          .post(
            Uri.parse('$baseUrl/api/ai/labor-consult'),
            headers: {
              'Content-Type': 'application/json',
              if (token.isNotEmpty) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'question': text, 'history': history}),
          )
          .timeout(const Duration(seconds: 20));

      final data = jsonDecode(utf8.decode(resp.bodyBytes));
      if (data['ok'] == true) {
        setState(() {
          _messages.add(_Message(isUser: false, text: data['answer'] ?? ''));
          _remaining = data['remaining'] ?? _remaining;
        });
      } else {
        _showError(data['message'] ?? '오류가 발생했어요.');
      }
    } catch (e) {
      _showError('네트워크 오류가 발생했어요.');
    } finally {
      setState(() => _loading = false);
      _scrollToBottom();
    }
  }

  void _showError(String msg) {
    setState(() {
      _messages.add(_Message(isUser: false, text: '⚠️ $msg'));
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            size: 18,
            color: Color(0xFF191F28),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: _blue,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.balance_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI 노무 상담사',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF191F28),
                  ),
                ),
                Text(
                  '노동법 궁금증을 해결해드려요',
                  style: TextStyle(fontSize: 11, color: Color(0xFF8B95A1)),
                ),
              ],
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '잔여 $_remaining회',
                style: const TextStyle(fontSize: 12, color: _label),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 메시지 목록
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: _messages.length + (_loading ? 1 : 0),
              itemBuilder: (ctx, i) {
                if (i == _messages.length) return _buildTyping();
                return _buildBubble(_messages[i]);
              },
            ),
          ),

          // 빠른 질문 (대화 없을 때)
          if (_messages.length <= 1) _buildQuickQuestions(),

          // 입력창
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildBubble(_Message msg) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            msg.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!msg.isUser) ...[
            Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                color: _blue,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.balance_rounded,
                color: Colors.white,
                size: 15,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress: () {
                Clipboard.setData(ClipboardData(text: msg.text));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('복사됐어요'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: msg.isUser ? _blue : Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(msg.isUser ? 16 : 4),
                    bottomRight: Radius.circular(msg.isUser ? 4 : 16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  msg.text,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.55,
                    color: msg.isUser ? Colors.white : const Color(0xFF191F28),
                  ),
                ),
              ),
            ),
          ),
          if (msg.isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildTyping() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              color: _blue,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.balance_rounded,
              color: Colors.white,
              size: 15,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6),
              ],
            ),
            child: const _TypingDots(),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickQuestions() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '💬 자주 묻는 질문',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _label,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                _quickQuestions
                    .map(
                      (q) => GestureDetector(
                        onTap: () => _send(q),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: _bg,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE5E8EB)),
                          ),
                          child: Text(
                            q,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF4E5968),
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE5E8EB))),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _ctrl,
                  minLines: 1,
                  maxLines: 4,
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: '노동법 궁금한 점을 질문해보세요',
                    hintStyle: TextStyle(fontSize: 13, color: _label),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                  onSubmitted: _send,
                  textInputAction: TextInputAction.send,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _send(_ctrl.text),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _loading ? _label : _blue,
                  shape: BoxShape.circle,
                ),
                child:
                    _loading
                        ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                        : const Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 타이핑 점 애니메이션
class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final opacity = ((_ctrl.value * 3 - i).clamp(0.0, 1.0) *
                    (1 - (_ctrl.value * 3 - i - 1).clamp(0.0, 1.0)))
                .clamp(0.3, 1.0);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: const Color(0xFF8B95A1).withOpacity(opacity),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}
