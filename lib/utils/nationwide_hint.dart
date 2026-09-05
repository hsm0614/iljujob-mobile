/// 전국 노출이 말이 되는 공고인지 판별한다.
///
/// 숙식·기숙사·셔틀을 제공하면 지역을 넘어 지원이 온다. 그 외(동네 음식점·
/// 편의점 등)는 전국에 뿌려도 지원이 오지 않고 구직자 피드만 오염된다.
///
/// ⚠️ '행사·전시'는 일부러 뺐다. 실측 118건으로 가장 많지만
///    "행사장 서빙"처럼 그 지역 사람이 가는 공고가 대부분이라 오탐이 크다.
///    사장님이 직접 켜는 건 막지 않는다.
final RegExp _nationwideKeywords = RegExp(
  r'숙식|기숙사|셔틀|통근\s*버스|기숙|사택',
);

/// 제목·상세에서 전국 노출 자격 키워드를 찾는다.
bool hasNationwideHint(String? title, String? description) {
  final text = '${title ?? ''} ${description ?? ''}';
  return _nationwideKeywords.hasMatch(text);
}

/// 감지된 키워드(안내 문구에 쓴다). 없으면 null.
String? matchedNationwideKeyword(String? title, String? description) {
  final m = _nationwideKeywords.firstMatch('${title ?? ''} ${description ?? ''}');
  return m?.group(0)?.replaceAll(RegExp(r'\s+'), ' ');
}
