//lib/presentation/screens/post_job/post_job_screen.dart
import 'package:flutter/material.dart';
import 'package:iljujob/data/models/job.dart';
import 'post_job_form.dart';

class PostJobScreen extends StatefulWidget {
  const PostJobScreen({super.key});

  @override
  State<PostJobScreen> createState() => _PostJobScreenState();
}

class _PostJobScreenState extends State<PostJobScreen> {
  Job? existingJob;
  bool isRepost = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args != null && args['mode'] == 'repost' && args['job'] != null) {
      existingJob = args['job'];
      isRepost = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('채용공고 등록'),
        backgroundColor: const Color(0xFF4C6EF5),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: PostJobForm(isRepost: isRepost, existingJob: existingJob),
      ),
    );
  }
}
