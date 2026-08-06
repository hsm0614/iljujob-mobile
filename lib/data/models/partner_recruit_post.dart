// 파트너 채용공고 (광고 제휴) — 앱 내 커스텀 상세 화면용 모델
// 지금은 Dart 인스턴스 1개(롯데손보) 하드코딩.
// 파트너 #2가 실제로 오면 이 모델을 서버 테이블(partner_recruit_posts) + 어드민으로 승격만 하면 됨
// (화면은 모델을 렌더하므로 그대로 재사용). 그때 fromJson 추가.

/// 본문 한 줄. 파서 없이 종류를 명시해 렌더 오류 여지를 없앤다.
enum PartnerLineKind { text, bullet, bold }

class PartnerRecruitLine {
  final String text;
  final PartnerLineKind kind;

  const PartnerRecruitLine._(this.text, this.kind);

  const PartnerRecruitLine.text(String text)
    : this._(text, PartnerLineKind.text);
  const PartnerRecruitLine.bullet(String text)
    : this._(text, PartnerLineKind.bullet);

  /// 소제목·강조 줄 (예: "1. 보험계약 수수료 지급 기준")
  const PartnerRecruitLine.bold(String text)
    : this._(text, PartnerLineKind.bold);
}

class PartnerRecruitSummaryItem {
  final String label;
  final String value;
  const PartnerRecruitSummaryItem(this.label, this.value);
}

class PartnerRecruitSection {
  final String heading;
  final List<PartnerRecruitLine> body;

  /// 섹션 안에서 박스로 강조할 한 줄 (예: "스마트플래너는 이런점이 좋아요!")
  final String? highlightLine;

  /// highlightLine 아래에 붙는 항목들
  final List<PartnerRecruitLine> highlightBody;

  const PartnerRecruitSection({
    required this.heading,
    this.body = const [],
    this.highlightLine,
    this.highlightBody = const [],
  });
}

class PartnerRecruitBenefitItem {
  final String title;
  final List<PartnerRecruitLine> details;
  const PartnerRecruitBenefitItem(this.title, this.details);
}

class PartnerRecruitBenefits {
  final String heading;

  /// 로고 자산 키. 'albailju' = assets/logo.png, 'wonder' = 원더 제공 자산(미수령 시 자리만)
  final List<String> logos;
  final List<PartnerRecruitBenefitItem> items;

  const PartnerRecruitBenefits({
    required this.heading,
    required this.logos,
    required this.items,
  });
}

class PartnerRecruitPost {
  /// 트래킹/정산 키 — ad_banners.partner_code와 동일해야 CTA가 배너 리포트에 집계됨
  final String partnerCode;
  final String title;

  /// 타이틀 형광펜 하이라이트 여부
  final bool highlightTitle;
  final List<PartnerRecruitSummaryItem> summary;
  final List<PartnerRecruitSection> sections;
  final PartnerRecruitBenefits benefits;
  final String applyUrl;
  final String applyLabel;

  /// 목록 카드에 한 줄로 노출할 클릭 이유. 카드는 좁으므로 요약을 나열하지 않고
  /// 이 한 줄만 쓴다 (상세는 화면에서 본다).
  final String cardHook;

  const PartnerRecruitPost({
    required this.partnerCode,
    required this.title,
    this.highlightTitle = true,
    required this.summary,
    required this.sections,
    required this.benefits,
    required this.applyUrl,
    this.applyLabel = '지원하기',
    required this.cardHook,
  });

  /// 롯데손해보험 '스마트플래너' — 원더 제휴 (본문은 기획서 PDF 원문 그대로)
  static const wonderLotte = PartnerRecruitPost(
    partnerCode: 'wonder_lotte',
    title: "롯데손해보험 '스마트플래너' 모집",
    cardHook: '재택근무 · 신세계백화점상품권 10만원',
    summary: [
      PartnerRecruitSummaryItem('업종', '금융/보험'),
      PartnerRecruitSummaryItem('경력', '무관'),
      PartnerRecruitSummaryItem('근무지', '재택근무, 장소 무관'),
      PartnerRecruitSummaryItem('근무형태', '위촉직'),
      PartnerRecruitSummaryItem('절차', '지원 > 시험,교육 > 위촉 > 소득활동'),
    ],
    sections: [
      PartnerRecruitSection(
        heading: '기업소개',
        body: [
          PartnerRecruitLine.text(
            "롯데손해보험은 '우리의 자부심이 되고 고객이 팬덤이 되는 대한민국 초우량 보험회사'라는 비전을 달성하기 위해 노력하고 있습니다. "
            '더 많은 사람들이 시간과 장소에 구애받지 않고 추가 소득을 창출할 수 있는 모바일 기반의 원더 앱을 운영하며 스마트플래너의 여정을 지원하고 있습니다.',
          ),
        ],
      ),
      PartnerRecruitSection(
        heading: '스마트플래너란',
        body: [
          PartnerRecruitLine.text(
            "출근하지 않고 앱 하나로 자유롭게 활동할 수 있는 롯데손해보험의 'N잡 설계사'입니다.",
          ),
          PartnerRecruitLine.text(
            '원하는 시간에 활동하며, 활동한 만큼 소득을 만들 수 있는 대표적인 트렌디한 N잡입니다.',
          ),
        ],
        highlightLine: '스마트플래너는 이런점이 좋아요!',
        highlightBody: [
          PartnerRecruitLine.bullet('출근 없이 앱 하나로 자유롭게 활동'),
          PartnerRecruitLine.bullet('체계적인 온라인 교육 지원'),
          PartnerRecruitLine.bullet('1:1 전문매니저 지원'),
          PartnerRecruitLine.bullet('보험 전문지식이 없는 초보자도 가능'),
          PartnerRecruitLine.bullet('자격증 취득을 위한 비용 지원'),
          PartnerRecruitLine.bullet('실적 압박 없음'),
        ],
      ),
      PartnerRecruitSection(
        heading: '예상소득',
        body: [
          PartnerRecruitLine.bold('1. 보험계약 수수료 지급 기준'),
          PartnerRecruitLine.text('(1) 선지급'),
          PartnerRecruitLine.bullet('계약 체결 익월 수수료 수령'),
          PartnerRecruitLine.bullet('총 지급액: 보험료 x 13배 (단, 유지/수금수수료는 13회차 이후 지급)'),
          PartnerRecruitLine.text('(2) 분급'),
          PartnerRecruitLine.bullet('계약 체결 익월부터 13개월 동안 나눠서 수령'),
          PartnerRecruitLine.bullet('총 지급액: 보험료 x 15배 (단, 회차별 지급 금액 상이함)'),
          PartnerRecruitLine.bold('2. 축하금'),
          PartnerRecruitLine.text('(1) 첫계약 축하금 — 장기 1건 달성 시 10만원 (보험료 무관)'),
          PartnerRecruitLine.text('(2) 더블 축하금 — 장기 합산 5만원 달성 시 20만원 추가지급'),
          PartnerRecruitLine.text('(3) 트리플 축하금 — 장기 합산 10만원 달성 시 30만원 추가지급'),
          PartnerRecruitLine.bold('3. 월 보험료 10만원 기준 소득 예시'),
          PartnerRecruitLine.bullet('(선지급) 총 예상소득 190만원'),
          PartnerRecruitLine.bullet('(분급) 총 예상소득 216만원'),
        ],
      ),
      PartnerRecruitSection(
        heading: '자격요건',
        body: [
          PartnerRecruitLine.bullet('만 19세 이상'),
          PartnerRecruitLine.bullet('학력 및 경력 무관'),
          PartnerRecruitLine.bullet('보험업 활동에 결격사유가 없는 분'),
          PartnerRecruitLine.bullet('온라인, 모바일 기반 업무 방식에 익숙한 분'),
        ],
      ),
      PartnerRecruitSection(
        heading: '지원 방법',
        body: [
          PartnerRecruitLine.text(
            '하단 링크를 통해 앱 다운로드 ▶ 회원가입(마케팅 활용동의) ▶ 시험신청 ▶ 시험응시 ▶ 합격 후 손해보험협회 등록',
          ),
        ],
      ),
    ],
    benefits: PartnerRecruitBenefits(
      heading: "'알바일주' 특별 혜택",
      logos: ['albailju', 'wonder'],
      // ⚠️ 신세계상품권·네이버페이 고유 이미지 사용 금지 — 텍스트로만 표기
      items: [
        PartnerRecruitBenefitItem('신세계백화점상품권 10만원 지급', [
          PartnerRecruitLine.text('지급 조건: (1) 롯데손보 스마트플래너 등록 시 (2) 공통혜택 적용'),
          PartnerRecruitLine.text('지급 방법: 원더 앱에서 확인'),
        ]),
        PartnerRecruitBenefitItem('네이버페이 3만원 지급', [
          PartnerRecruitLine.text(
            '지급 조건: (1) 롯데손보 스마트플래너 등록 시 (2) 아래 링크로 회원가입 후 마케팅 활용 동의 필수 (3) 공통혜택과 중복 적용 가능',
          ),
          PartnerRecruitLine.text('지급 방법: 위촉 익월 10일 내 문자로 발송'),
        ]),
      ],
    ),
    applyUrl: 'https://abr.ge/n9w3st',
  );
}
