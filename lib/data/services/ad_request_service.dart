import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../config/constants.dart';
import 'authenticated_http_client.dart';

class AdEligibleJob {
  const AdEligibleJob({required this.id, required this.title});
  final int id;
  final String title;
}

class AdRequestSummary {
  const AdRequestSummary({
    required this.id,
    required this.kind,
    required this.title,
    required this.status,
    this.reviewNote,
    this.companyName,
    this.subtitle,
    this.description,
    this.imageUrl,
    this.destinationType,
    this.destinationUrl,
    this.jobId,
  });
  final int id;
  final String kind;
  final String title;
  final String status;
  final String? reviewNote;
  final String? companyName;
  final String? subtitle;
  final String? description;
  final String? imageUrl;
  final String? destinationType;
  final String? destinationUrl;
  final int? jobId;
}

class AdRequestDraft {
  const AdRequestDraft({
    this.requestId,
    required this.kind,
    required this.companyName,
    required this.title,
    required this.description,
    required this.destinationType,
    this.destinationUrl,
    this.jobId,
    this.subtitle,
    this.imageFile,
  });
  final String kind;
  final int? requestId;
  final String companyName;
  final String title;
  final String description;
  final String destinationType;
  final String? destinationUrl;
  final int? jobId;
  final String? subtitle;
  final File? imageFile;
}

abstract class AdRequestApi {
  Future<List<AdEligibleJob>> fetchEligibleJobs();
  Future<List<AdRequestSummary>> fetchMine();
  Future<int> submit(AdRequestDraft draft);
}

class AdRequestService implements AdRequestApi {
  @override
  Future<List<AdRequestSummary>> fetchMine() async {
    final response = await AuthenticatedHttpClient.get(
      Uri.parse('$baseUrl/api/ad-requests/mine'),
    );
    if (response.statusCode != 200) throw Exception('신청 내역을 불러오지 못했습니다.');
    final rows = jsonDecode(response.body)['requests'] as List<dynamic>;
    return rows
        .map(
          (row) => AdRequestSummary(
            id: (row['id'] as num).toInt(),
            kind: row['kind'] as String,
            title: row['title'] as String,
            status: (row['display_status'] ?? row['status']) as String,
            reviewNote: row['review_note'] as String?,
            companyName: row['company_name'] as String?,
            subtitle: row['subtitle'] as String?,
            description: row['description'] as String?,
            imageUrl: row['image_url'] as String?,
            destinationType: row['destination_type'] as String?,
            destinationUrl: row['destination_url'] as String?,
            jobId: (row['job_id'] as num?)?.toInt(),
          ),
        )
        .toList();
  }

  @override
  Future<List<AdEligibleJob>> fetchEligibleJobs() async {
    final response = await AuthenticatedHttpClient.get(
      Uri.parse('$baseUrl/api/ad-requests/my-jobs'),
    );
    if (response.statusCode != 200) throw Exception('게시 중인 공고를 불러오지 못했습니다.');
    final jobs = (jsonDecode(response.body)['jobs'] as List<dynamic>);
    return jobs
        .map(
          (job) => AdEligibleJob(
            id: job['id'] as int,
            title: job['title'] as String,
          ),
        )
        .toList();
  }

  @override
  Future<int> submit(AdRequestDraft draft) async {
    final response = await AuthenticatedHttpClient.sendMultipart((token) async {
      final request = http.MultipartRequest(
        draft.requestId == null ? 'POST' : 'PUT',
        Uri.parse(
          '$baseUrl/api/ad-requests${draft.requestId == null ? '' : '/${draft.requestId}'}',
        ),
      );
      request.headers['Authorization'] = 'Bearer $token';
      request.fields.addAll({
        'kind': draft.kind,
        'company_name': draft.companyName,
        'title': draft.title,
        'subtitle': draft.subtitle ?? '',
        'description': draft.description,
        'destination_type': draft.destinationType,
        if (draft.destinationUrl != null)
          'destination_url': draft.destinationUrl!,
        if (draft.jobId != null) 'job_id': '${draft.jobId}',
      });
      if (draft.imageFile != null)
        request.files.add(
          await http.MultipartFile.fromPath('image', draft.imageFile!.path),
        );
      return request;
    });
    final body = await response.stream.bytesToString();
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    if (response.statusCode != (draft.requestId == null ? 201 : 200))
      throw Exception(decoded['message'] ?? '신청을 저장하지 못했습니다.');
    return decoded['id'] as int;
  }
}
