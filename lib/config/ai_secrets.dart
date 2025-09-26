// lib/config/ai_config.dart
class AIConfig {
  // Gemini API 설정
  static const String geminiApiKey = 'AIzaSyD1mhHbKpWJ2Fig-xnHJ2zLZhegYsBq9DA'; // 실제 API 키로 교체
  static const String geminiBaseUrl = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash-latest:generateContent';
  
  // API 호출 설정
  static const Duration timeout = Duration(seconds: 30);
  static const int maxRetries = 2;
  
  // 업종별 특화 프롬프트 템플릿
  static const Map<String, String> categoryTemplates = {
    '제조': '''
제조업 관련 업무의 특성을 살려 다음과 같이 작성해주세요:
- 생산라인, 품질관리, 안전수칙 등 제조업 특화 내용 포함
- 체력적 요구사항이나 안전장비 착용 등 실무적 정보 제공
- 깔끔하고 체계적인 작업환경 강조
''',
    
    '물류': '''
물류업 관련 업무의 특성을 살려 다음과 같이 작성해주세요:
- 상하차, 분류, 포장, 배송 등 물류 프로세스 설명
- 체력적 요구사항과 근무환경에 대한 정확한 정보 제공
- 팀워크와 효율성을 중시하는 업무환경 강조
''',
    
    '서비스': '''
서비스업 관련 업무의 특성을 살려 다음과 같이 작성해주세요:
- 고객응대, 친절함, 소통능력 등 서비스 마인드 중요성 강조
- 깔끔한 외모나 복장 관련 요구사항 포함
- 밝고 활기찬 근무분위기 어필
''',
    
    '건설': '''
건설업 관련 업무의 특성을 살려 다음과 같이 작성해주세요:
- 안전이 최우선임을 강조하고 관련 교육 제공 언급
- 체력적 요구사항과 작업환경에 대한 솔직한 정보 제공
- 전문기술 습득 기회나 경력개발 가능성 언급
''',
    
    '사무': '''
사무직 관련 업무의 특성을 살려 다음과 같이 작성해주세요:
- 컴퓨터 활용능력, 문서작성, 업무처리 등 사무업무 특성 설명
- 쾌적한 사무환경과 안정적인 근무조건 강조
- 학습과 성장 기회 제공 등 발전가능성 언급
''',
    
    '청소': '''
청소업 관련 업무의 특성을 살려 다음과 같이 작성해주세요:
- 깔끔하고 체계적인 청소 시스템과 장비 지원 언급
- 성실함과 책임감을 중시하는 근무환경 강조
- 안정적이고 꾸준한 일자리임을 어필
''',
    
    '기타': '''
해당 업무의 특성에 맞게 다음과 같이 작성해주세요:
- 업무의 독특함이나 특별함을 적절히 어필
- 필요한 자격이나 경험에 대한 정확한 정보 제공
- 성장가능성이나 특별한 혜택 등 차별화 포인트 강조
'''
  };
  
  // 기본 프롬프트 템플릿
  static String buildBasicPrompt({
    required String title,
    required String category,
    required String location,
    required String payType,
    required int pay,
    String? workingTime,
    List<String>? weekdays,
    String? companyName,
    required bool isShortTerm,
  }) {
    final weekdaysText = weekdays?.isNotEmpty == true ? weekdays!.join(', ') : '';
    final periodText = isShortTerm ? '단기' : '장기';
    final payFormatted = pay.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), 
      (Match m) => '${m[1]},'
    );
    final categoryTemplate = categoryTemplates[category] ?? categoryTemplates['기타']!;

    return '''
알바 구인공고를 작성해주세요. 다음 정보를 바탕으로 자연스럽고 매력적인 공고문을 작성해주세요:

**기본 정보:**
- 제목: $title
- 업종: $category
- 지역: $location
- 근무형태: $periodText
- 급여: $payType ${payFormatted}원
${workingTime?.isNotEmpty == true ? '- 근무시간: $workingTime' : ''}
${weekdaysText.isNotEmpty ? '- 근무요일: $weekdaysText' : ''}
${companyName?.isNotEmpty == true ? '- 회사명: $companyName' : ''}

**업종별 가이드:**
$categoryTemplate

**작성 가이드라인:**
1. 친근하고 읽기 쉬운 톤으로 작성
2. 업무 내용을 구체적으로 설명
3. 근무 환경의 장점 강조
4. 지원자격이나 우대사항 포함
5. 300-500자 내외로 작성
6. 불필요한 특수문자나 과도한 강조 표현 피하기
7. 2025년 최저시급(10,030원) 준수 언급

공고문만 작성해주세요:
''';
  }
}