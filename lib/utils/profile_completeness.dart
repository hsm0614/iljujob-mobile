/// 알바생 프로필 완성도 (자이가르닉 — 덜 끝낸 걸 마저 채우게, 2026-11).
/// 사장님이 지원자를 고를 때 보는 항목만 센다. 순서 = 채우기 쉬운 순 → '다음 하나'로 권한다.
/// 11-02 실측(14일 활동 922명): 사진 2% · 자기소개 4% · 희망 일 5% · 요일 5% · 강점 28% · 성별 77%
const profileItems = <(String, String)>[
  ('available_days', '가능한 요일'),
  ('desired_work', '희망하는 일'),
  ('strengths', '나의 강점'),
  ('gender', '성별'),
  ('introduction', '자기소개'),
  ('profile_image_url', '프로필 사진'),
];

bool _filled(Object? v) {
  if (v == null) return false;
  if (v is List) return v.isNotEmpty;
  if (v is Map) return v.isNotEmpty;
  final s = v.toString().trim();
  return s.isNotEmpty && s != '[]' && s != '{}' && s != 'null';
}

/// (완성 %, 아직 안 채운 첫 항목 이름 — 다 채웠으면 null)
({int percent, String? next}) profileCompleteness(Map<String, dynamic> profile) {
  final missing = [for (final (key, label) in profileItems) if (!_filled(profile[key])) label];
  final done = profileItems.length - missing.length;
  return (percent: (done * 100 / profileItems.length).round(), next: missing.isEmpty ? null : missing.first);
}
