import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/constants.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ReviewScreen extends StatefulWidget {
  final int clientId;
  final String jobTitle;
  final String companyName;

  const ReviewScreen({
    super.key,
    required this.clientId,
    required this.jobTitle,
    required this.companyName,
  });

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class ReviewScreenRouter extends StatelessWidget {
  const ReviewScreenRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
    
    final int jobId = args['jobId'] is int
        ? args['jobId']
        : int.tryParse(args['jobId']?.toString() ?? '') ?? 0;

    final int clientId = args['clientId'] is int
        ? args['clientId']
        : int.tryParse(args['clientId']?.toString() ?? '') ?? 0;

    final String jobTitle = args['jobTitle']?.toString() ?? '제목 없음';
    final String companyName = args['companyName']?.toString() ?? '회사명 없음';
    

    // 잘못된 값 방지
    if (jobId == 0 || clientId == 0) {
      return const Scaffold(
        body: Center(child: Text('잘못된 접근입니다.')),
      );
    }

    return ReviewScreen(

      clientId: clientId,
      jobTitle: jobTitle,
      companyName: companyName,
    );
  }
}

class _ReviewScreenState extends State<ReviewScreen> {
  int satisfaction = 0; // 1: 별로, 2: 보통, 3: 추천
  String duration = '';
  final Set<String> tags = {};
  final TextEditingController commentController = TextEditingController();
  bool isSubmitting = false;

    @override
  void initState() {
   
    super.initState();
    _checkIfAlreadyReviewed(); // ✅ 리뷰 중복 여부 확인
  }

  void _toggleTag(String tag) {
    setState(() {
      if (tags.contains(tag)) {
        tags.remove(tag);
      } else {
        tags.add(tag);
      }
    });
  }

  bool _isValid() {
    return satisfaction > 0 && duration.isNotEmpty;
  }
 Future<void> _checkIfAlreadyReviewed() async {
    final prefs = await SharedPreferences.getInstance();
    final workerId = prefs.getInt('userId') ?? 0;

    if (workerId == 0) return;

    final response = await http.get(Uri.parse(
      '$baseUrl/api/review/hasReviewed?clientId=${widget.clientId}&workerId=$workerId&jobTitle=${Uri.encodeComponent(widget.jobTitle)}',
    ));

    if (response.statusCode == 200) {
      final result = jsonDecode(response.body);
      if (result['hasReviewed'] == true && mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이미 이 공고에 리뷰를 남기셨어요.')),
        );
      }
    }
  }
  Future<void> _submitReview() async {
  if (!_isValid()) return;

  setState(() => isSubmitting = true);

  final prefs = await SharedPreferences.getInstance();
  final workerId = prefs.getInt('userId') ?? 0;

  if (workerId == 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('로그인 정보를 확인할 수 없습니다.')),
    );
    return;
  }

  final reviewData = {

    'clientId': widget.clientId,
    'workerId': workerId, // ✅ 여기에 추가!
    'jobTitle': widget.jobTitle, // ✅ 추가!
    'satisfaction': satisfaction,
    'duration': duration,
    'tags': tags.toList(),
    'comment': commentController.text.trim(),
  };

  final response = await http.post(
    Uri.parse('$baseUrl/api/review/submit'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode(reviewData),
  );

  setState(() => isSubmitting = false);

  if (response.statusCode == 200) {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('후기가 등록되었습니다!')),
    );
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('후기 등록에 실패했습니다.')),
    );
  }
}
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('후기 보내기')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _buildJobInfo(),
          const SizedBox(height: 24),
          _buildSatisfaction(),
          const SizedBox(height: 24),
          _buildDuration(),
          const SizedBox(height: 24),
          _buildTagsSection(),
          const SizedBox(height: 24),
          _buildCommentBox(),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isValid() && !isSubmitting ? _submitReview : null,
              child: const Text('작성 완료'),
            ),
          )
        ]),
      ),
    );
  }

Widget _buildJobInfo() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Center(
        child: Text(
          widget.jobTitle,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
      ),
      const SizedBox(height: 6),
      Center(
        child: Text(
          widget.companyName,
          style: const TextStyle(color: Colors.grey, fontSize: 16),
          textAlign: TextAlign.center,
        ),
      ),
    ],
  );
}

  Widget _buildSatisfaction() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('일해보니 어땠나요?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _emojiButton('별로였어요', 1),
          _emojiButton('보통이에요', 2),
          _emojiButton('추천해요', 3),
        ],
      ),
    ]);
  }

 Widget _emojiButton(String label, int value) {
  final selected = satisfaction == value;
  final List<String> emojis = ['😕', '🙂', '😄'];
  final List<String> labels = ['아쉬워요', '만족해요', '좋아요'];

  return GestureDetector(
    onTap: () => setState(() => satisfaction = value),
    child: Column(
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: selected ? Colors.blue : Colors.grey[300],
          child: Text(emojis[value - 1], style: const TextStyle(fontSize: 24)),
        ),
        const SizedBox(height: 4),
        Text(
          labels[value - 1],
          style: TextStyle(color: selected ? Colors.blue : Colors.black),
        ),
      ],
    ),
  );
}

  Widget _buildDuration() {
  final options = ['채팅', '하루', '1주', '한 달 이내', '한 달 이상'];

  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('얼마나 일하셨나요?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    Wrap(
      spacing: 8,
      children: options.map((opt) {
        final selected = duration == opt;
        return ChoiceChip(
          label: Text(opt),
          selected: selected,
          onSelected: (_) => setState(() => duration = opt),
        );
      }).toList(),
    )
  ]);
}
  Widget _buildTagsSection() {
    const tagGroups = {
      '일하는 환경': ['휴게공간이 있어요', '식사/간식을 챙겨줘요', '분위기가 좋아요'],
      '급여/계약': ['급여를 제때 줘요', '계약서를 작성했어요', '계약 내용을 지키지 않았어요'],
      '업무 경험': ['친절했어요', '일이 설명과 달라요', '존중해줬어요'],
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: tagGroups.entries.map((group) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('🔸 ${group.key}', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: group.value.map((tag) {
              final selected = tags.contains(tag);
              return FilterChip(
                label: Text(tag),
                selected: selected,
                onSelected: (_) => _toggleTag(tag),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ]);
      }).toList(),
    );
  }

  Widget _buildCommentBox() {
    return TextField(
      controller: commentController,
      decoration: const InputDecoration(
        labelText: '후기 남기기',
        hintText: '부적절하거나 불쾌감을 줄 수 있는 내용을 작성할 경우 제재를 받을 수 있습니다.',
        border: OutlineInputBorder(),
      ),
      maxLines: 3,
    );
  }
}
