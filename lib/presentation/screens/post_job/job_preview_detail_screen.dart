import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';

class JobPreviewDetailScreen extends StatelessWidget {
  final String title;
  final String category;
  final String location;
  final double lat;
  final double lng;
  final String? startDate;
  final String? endDate;
  final List<String> weekdays;
  final String workingTime;
  final String payType;
  final int pay;
  final String description;
  final List<File> images;
  final String companyName;
  final String managerName;
  final VoidCallback onSubmit;

  const JobPreviewDetailScreen({
    super.key,
    required this.title,
    required this.category,
    required this.location,
    required this.lat,
    required this.lng,
    this.startDate,
    this.endDate,
    required this.weekdays,
    required this.workingTime,
    required this.payType,
    required this.pay,
    required this.description,
   this.images = const [],  
    required this.companyName,
    required this.managerName,
    required this.onSubmit,
    
  });
String _periodText() {
  // 1) 단기: 날짜 범위
  if ((startDate != null && startDate!.trim().isNotEmpty) &&
      (endDate != null && endDate!.trim().isNotEmpty)) {
    DateTime? s, e;
    try { s = DateTime.parse(startDate!.trim()); } catch (_) {}
    try { e = DateTime.parse(endDate!.trim()); } catch (_) {}
    if (s != null && e != null) {
      final fmt = DateFormat('yyyy.MM.dd (E)', 'ko_KR');
      return '${fmt.format(s)} ~ ${fmt.format(e)}';
    }
    return '$startDate ~ $endDate';
  }

  // 2) 장기: weekdays 정규화
  //    - ["월","수"] 처럼 리스트
  //    - ["월,수,금"] 처럼 한 문자열에 콤마로 합쳐진 형태
  //    - [" 협의: 주 2~3회 "] 처럼 협의 접두사
  final List<String> raw = weekdays;
  final List<String> flatDays = raw
      .where((s) => s != null)                       // null 방어 (타입상 거의 필요 없음)
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .expand((s) => s.contains(',') ? s.split(',') : [s]) // "월,수,금" → ["월","수","금"]
      .map((s) => s.trim())
      .toList();

  if (flatDays.isNotEmpty) {
    // 협의 케이스: 첫 원소가 "협의:" 로 시작하면 협의로 간주
    final first = flatDays.first;
    if (RegExp(r'^협의\s*:').hasMatch(first)) {
      final txt = first.replaceFirst(RegExp(r'^협의\s*:\s*'), '').trim();
      return '요일 협의: ${txt.isEmpty ? '상세 협의' : txt}';
    }
    // 요일 지정 케이스
    return flatDays.join(', ');
  }

  // 3) 아무 것도 없으면
  return '미정';
}
  @override
  Widget build(BuildContext context) {
    final primaryColor = const Color(0xFF3B8AFF);
    final sectionPadding = const EdgeInsets.symmetric(vertical: 12, horizontal: 16);
    final cardRadius = BorderRadius.circular(12);

    return Scaffold(
      appBar: AppBar(title: const Text('공고 미리보기')),
      body: ListView(
        children: [
     if (images.isNotEmpty)
  SizedBox(
    height: 200,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: images.length,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            images[index],
            width: 200,
            height: 200,
            fit: BoxFit.cover,
          ),
        );
      },
    ),
  ),

          Padding(
            padding: sectionPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(category, style: TextStyle(color: primaryColor, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 8),
                    Text(location, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ],
            ),
          ),

          Padding(
            padding: sectionPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoCard(primaryColor, cardRadius, Icons.monetization_on, '급여', '${NumberFormat('#,###').format(pay)}원 ($payType)'),
                const SizedBox(height: 12),
_buildInfoCard(primaryColor, cardRadius, Icons.calendar_today, '근무 기간', _periodText()),
                const SizedBox(height: 12),
                _buildInfoCard(primaryColor, cardRadius, Icons.access_time, '근무 시간', workingTime),
              ],
            ),
          ),

          Padding(
            padding: sectionPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('상세 설명', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(description, style: const TextStyle(height: 1.5)),
              ],
            ),
          ),

          if (lat != 0 && lng != 0)
            Padding(
              padding: sectionPadding,
              child: ClipRRect(
                borderRadius: cardRadius,
                child: SizedBox(
                  height: 200,
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: LatLng(lat, lng),
                      initialZoom: 16,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: Platform.isAndroid ? 'kr.co.iljujob' : 'com.iljujob.kr',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(lat, lng),
                            width: 40,
                            height: 40,
                            child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

          Padding(
            padding: sectionPadding,
            child: Card(
              shape: RoundedRectangleBorder(borderRadius: cardRadius),
              child: ListTile(
                leading: const Icon(Icons.business),
                title: Text(companyName, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('담당자: $managerName'),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: cardRadius),
                  ),
                  child: const Text('수정하기'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: onSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: cardRadius),
                  ),
                  child: const Text('공고 등록', style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(Color primaryColor, BorderRadius cardRadius, IconData icon, String title, String content) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: cardRadius,
      ),
      child: Row(
        children: [
          Icon(icon, color: primaryColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 4),
                Text(content, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
