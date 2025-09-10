import 'package:flutter/material.dart';
import 'package:iljujob/presentation/screens/post_job/post_job_form.dart';
import '../../../data/models/job.dart'; // Job 클래스를 사용하려면 필요함

class PostJobScreen extends StatelessWidget {
  const PostJobScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Navigator에서 넘긴 arguments를 가져옴
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

    final bool isRepost = args?['isRepost'] ?? false;
    final Job? existingJob = args?['existingJob'];

    return WillPopScope(
      onWillPop: () async {
       final shouldLeave = await showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFF3B8AFF), size: 48),
            const SizedBox(height: 16),
            const Text('작성 중입니다',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text('작성을 취소하고 나가시겠습니까?',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF3B8AFF)),
                      foregroundColor: const Color(0xFF3B8AFF),
                    ),
                    child: const Text('계속 작성'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B8AFF),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('나가기'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  },
);

        return shouldLeave ?? false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('채용공고 등록'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: PostJobForm(
            isRepost: isRepost,
            existingJob: existingJob,
          ),
        ),
      ),
    );
  }
}
