/// 알바생 조건 지킴이 — 출근 제안이 최저시급·공고 조건에 맞는지(순수 함수, 규칙 기반)
const minWagePerHour2026 = 10320;

/// 법정 최소 휴게(근로기준법 54조) — 서버 lib/laborContract.js legalBreak 과 같게
int legalBreakMinutes(int spanMin) => spanMin >= 540 ? 60 : spanMin >= 270 ? 30 : 0;

int spanMinutes(String start, String end) {
  int m(String t) {
    final p = t.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }
  final d = m(end) - m(start);
  return d > 0 ? d : d + 1440;
}

/// (괜찮은지, 문장) 목록. 예전 카드처럼 시급 칸에 일급이 들어간 경우(2만 원 이상)는 판단하지 않는다
List<(bool, String)> checkConditions({
  required int hourly,
  required String start,
  required String end,
  int? jobPay,
  String? jobPayType,
}) {
  if (hourly <= 0 || hourly >= 20000) return const [];
  final won = (int n) => '${n.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}원';
  final out = <(bool, String)>[
    hourly >= minWagePerHour2026
        ? (true, '최저시급(${won(minWagePerHour2026)}) 이상이에요')
        : (false, '최저시급(${won(minWagePerHour2026)})보다 낮아요. 수락 전에 사장님께 확인하세요'),
  ];
  if (jobPay != null && jobPay > 0) {
    if (jobPayType == '시급') {
      out.add(hourly >= jobPay ? (true, '공고 시급과 같거나 높아요') : (false, '공고 시급(${won(jobPay)})보다 낮아요'));
    } else if (jobPayType == '일급') {
      final span = spanMinutes(start, end);
      final total = (hourly * (span - legalBreakMinutes(span)) / 60).round();
      out.add(total >= jobPay - 100
          ? (true, '공고 일급(${won(jobPay)})만큼 받아요')
          : (false, '이 조건이면 약 ${won(total)} — 공고 일급(${won(jobPay)})보다 적어요'));
    }
  }
  return out;
}
