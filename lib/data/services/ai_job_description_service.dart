//services/ai_job_description_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../../config/ai_secrets.dart';
import 'package:flutter/material.dart';  // StatefulWidget 사용을 위해 필요

class AIJobDescriptionService {
  
  static Future<String> generateJobDescription({
    required String title,
    required String category,
    required String location,
    required String payType,
    required int pay,
    String? workingTime,
    List<String>? weekdays,
    String? companyName,
    bool isShortTerm = true,
    String tone = 'friendly', // 'friendly', 'professional', 'casual'
     String? managerName, // 추가
  String? managerPhone, // 추가
  }) async {
    try {
      final prompt = _buildAdvancedPrompt(
        title: title,
        category: category,
        location: location,
        payType: payType,
        pay: pay,
        workingTime: workingTime,
        weekdays: weekdays,
        companyName: companyName,
        isShortTerm: isShortTerm,
        tone: tone,
      );

      final response = await http.post(
        Uri.parse('${AIConfig.geminiBaseUrl}?key=${AIConfig.geminiApiKey}'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'contents': [{
            'parts': [{
              'text': prompt
            }]
          }],
          'generationConfig': {
            'temperature': 0.7,
            'topK': 40,
            'topP': 0.95,
            'maxOutputTokens': 1024,
            'stopSequences': ['---END---']
          },
          'safetySettings': [
            {
              'category': 'HARM_CATEGORY_HARASSMENT',
              'threshold': 'BLOCK_MEDIUM_AND_ABOVE'
            },
            {
              'category': 'HARM_CATEGORY_HATE_SPEECH',
              'threshold': 'BLOCK_MEDIUM_AND_ABOVE'
            }
          ]
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? '';
        
        // 후처리: 불필요한 텍스트 제거 및 정리
        return _postProcessDescription(content.trim());
      } else {
        final errorData = jsonDecode(response.body);
        final errorMessage = errorData['error']?['message'] ?? '알 수 없는 오류';
        throw AIGenerationException('API 호출 실패: $errorMessage');
      }
    } catch (e) {
      if (e is AIGenerationException) rethrow;
      throw AIGenerationException('공고문 생성 중 오류가 발생했습니다: $e');
    }
  }

  static String _buildAdvancedPrompt({
  required String title,
  required String category,
  required String location,
  required String payType,
  required int pay,
  String? workingTime,
  List<String>? weekdays,
  String? companyName,
  required bool isShortTerm,
  required String tone,
}) {
  final weekdaysText = weekdays?.isNotEmpty == true ? weekdays!.join(', ') : '';
  final periodText = isShortTerm ? '단기' : '장기';
  final payFormatted = NumberFormat('#,###').format(pay);

  String toneInstruction = '';
  switch (tone) {
    case 'professional':
      toneInstruction = '정중하고 신뢰감 있는 문장. 과장/이모티콘 최소.';
      break;
    case 'casual':
      toneInstruction = '친근하고 가벼운 문장. 이모티콘 1개까지 허용. 반말 금지.';
      break;
    default:
      toneInstruction = '친근하지만 깔끔한 문장. 과장 없이 따뜻하게.';
  }

  final wt = (workingTime != null && workingTime.trim().isNotEmpty) ? workingTime.trim() : '';
  final wn = weekdaysText.isNotEmpty ? weekdaysText : '';
  final cn = (companyName != null && companyName.trim().isNotEmpty) ? companyName.trim() : '';

  return '''
너는 한국 알바 채용 공고 전문 카피라이터다.
알바일주 앱에 게시될 공고문을 작성한다.

[절대 규칙]
- 허위 정보 금지: 복지/간식/셔틀/교통비/식사 제공 등 언급 금지
- 성별/연령/외모 차별 표현 금지
- 과장 문구 금지 (압도적/최고/무조건 등)
- 마크다운 금지 (별표/샵/목록기호). 일반 텍스트만
- 글자수 280~380자
- 업종명을 그대로 반복하지 말 것 (예: "슈퍼·마트 보조" 같은 표현 금지)
- 자연스러운 사람 말투로 작성할 것
- "알바일주" 언급은 마지막 지원 안내 줄에서만

[업무 추측 금지]
- 업종만 주어진 경우, 업무를 특정하지 말 것
- 대신 "간단한 보조 업무", "현장 보조", "단순 반복 업무" 같은 표현 사용
- 제목에 특정 업무 단어가 있을 때만 그 단어 1회 사용 가능

[입력 정보]
제목: $title
업종: $category
지역: $location
근무형태: $periodText
급여: $payType ${payFormatted}원
근무시간: ${wt.isNotEmpty ? wt : '협의 가능'}
근무요일: ${wn.isNotEmpty ? wn : '협의 가능'}
회사명: ${cn.isNotEmpty ? cn : '미정'}

[문체]
$toneInstruction

[반드시 포함]
1) 어떤 일인지 자연스럽게 1~2문장 (업종명 반복 금지)
2) 초보·경험무관 환영 1문장
3) 근무 조건 (시간/요일/급여)
4) 2026년 최저시급 10,030원 준수 문장 (숫자 정확히)
5) 마지막 줄 고정: 지원: 알바일주 앱에서 '지원하기' 버튼

[좋은 예시 느낌]
"가볍게 시작할 수 있는 단기 알바예요. 특별한 경험 없어도 괜찮고, 하루 4시간으로 부담 없이 일할 수 있어요."

공고문만 출력하라.
''';
  }
  static String _postProcessDescription(String content) {
    // 불필요한 접두사/접미사 제거
    content = content.replaceAll(RegExp(r'^.*?공고문.*?[:：]\s*'), '');
    content = content.replaceAll(RegExp(r'---END---.*$'), '');
    content = content.replaceAll(RegExp(r'\*\*.*?\*\*'), ''); // 볼드 마크다운 제거
    content = content.replaceAll(RegExp(r'#{1,6}\s*'), ''); // 헤더 마크다운 제거
    
    // 연속된 공백이나 줄바꿈 정리
    content = content.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    content = content.replaceAll(RegExp(r' {2,}'), ' ');
    
    // 앞뒤 공백 제거
    content = content.trim();
    
    return content;
  }

  // 공고문 품질 검증
  static AIQualityReport validateDescription(String description) {
    final issues = <String>[];
    final suggestions = <String>[];
    
    // 길이 검증
    if (description.length < 100) {
      issues.add('공고문이 너무 짧습니다 (현재: ${description.length}자)');
      suggestions.add('업무내용과 근무환경에 대한 설명을 더 자세히 추가해보세요');
    } else if (description.length > 800) {
      issues.add('공고문이 너무 깁니다 (현재: ${description.length}자)');
      suggestions.add('핵심 내용만 간결하게 정리해보세요');
    }
    
    // 필수 키워드 검증
    final requiredKeywords = ['업무', '근무', '급여', '지원'];
    for (final keyword in requiredKeywords) {
      if (!description.contains(keyword)) {
        suggestions.add('$keyword 관련 내용을 추가하면 더 완성도 높은 공고가 됩니다');
      }
    }
    
    // 차별적 표현 검증
    final discriminatoryWords = ['남자만', '여자만', '젊은', '예쁜', '잘생긴'];
    for (final word in discriminatoryWords) {
      if (description.contains(word)) {
        issues.add('차별적 표현("$word")이 포함되어 있습니다');
        suggestions.add('성별, 외모 관련 차별적 표현을 제거해주세요');
      }
    }
    
    return AIQualityReport(
      score: _calculateQualityScore(description, issues.length),
      issues: issues,
      suggestions: suggestions,
    );
  }
  
  static int _calculateQualityScore(String description, int issueCount) {
    int score = 100;
    
    // 글자 수 기준 점수
    if (description.length < 200) score -= 20;
    else if (description.length > 600) score -= 10;
    
    // 이슈 개수별 점수 차감
    score -= (issueCount * 15);
    
    // 문단 구성 점수
    final paragraphs = description.split('\n').where((p) => p.trim().isNotEmpty).length;
    if (paragraphs < 2) score -= 10;
    
    return score.clamp(0, 100);
  }
}

// 예외 처리 클래스
class AIGenerationException implements Exception {
  final String message;
  const AIGenerationException(this.message);
  
  @override
  String toString() => 'AIGenerationException: $message';
}

// 품질 평가 결과 클래스
class AIQualityReport {
  final int score;
  final List<String> issues;
  final List<String> suggestions;
  
  const AIQualityReport({
    required this.score,
    required this.issues,
    required this.suggestions,
  });
  
  bool get isGoodQuality => score >= 80 && issues.isEmpty;
  bool get hasIssues => issues.isNotEmpty;
}

// 프리셋 관리 클래스
class AIPresetManager {
  static const List<AIPreset> presets = [
    AIPreset(
      name: '친근한 톤',
      tone: 'friendly',
      description: '친근하고 따뜻한 느낌의 공고문',
      icon: '😊',
    ),
    AIPreset(
      name: '전문적인 톤',
      tone: 'professional',
      description: '격식있고 신뢰감 있는 공고문',
      icon: '💼',
    ),
    AIPreset(
      name: '캐주얼한 톤',
      tone: 'casual',
      description: '편안하고 자유로운 분위기의 공고문',
      icon: '🎯',
    ),
  ];
  
  static AIPreset getPresetByTone(String tone) {
    return presets.firstWhere(
      (preset) => preset.tone == tone,
      orElse: () => presets.first,
    );
  }
}

class AIPreset {
  final String name;
  final String tone;
  final String description;
  final String icon;
  
  const AIPreset({
    required this.name,
    required this.tone,
    required this.description,
    required this.icon,
  });
}

// AI 공고문 생성 위젯
class AIJobDescriptionWidget extends StatefulWidget {
  final String title;
  final String category;
  final String location;
  final String payType;
  final int pay;
  final String? workingTime;
  final List<String>? weekdays;
  final String? companyName;
  final bool isShortTerm;
  final Function(String) onGenerated;
  final VoidCallback? onClose;
  final String? managerName; // 추가
  final String? managerPhone; // 추가

  const AIJobDescriptionWidget({
    super.key,
    required this.title,
    required this.category,
    required this.location,
    required this.payType,
    required this.pay,
    this.workingTime,
    this.weekdays,
    this.companyName,
    required this.isShortTerm,
    required this.onGenerated,
    this.onClose,
       this.managerName, // 추가
    this.managerPhone, // 추가
  });

  @override
  State<AIJobDescriptionWidget> createState() => _AIJobDescriptionWidgetState();
}

class _AIJobDescriptionWidgetState extends State<AIJobDescriptionWidget> {
  String selectedTone = 'friendly';
  bool isGenerating = false;
  String? generatedContent;
  AIQualityReport? qualityReport;

  @override
Widget build(BuildContext context) {
  return SafeArea( // 전체를 SafeArea로 감싸기
    child: Container(
    padding: const EdgeInsets.all(20),
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    child: SingleChildScrollView( // ✅ 스크롤 가능하도록 추가
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B8AFF).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: Color(0xFF3B8AFF),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI 공고문 생성',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '입력한 정보로 매력적인 공고문을 자동 생성합니다',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.onClose != null)
                IconButton(
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          const SizedBox(height: 20),

          // 톤 선택
          const Text(
            '공고문 스타일 선택',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          
          Wrap(
            spacing: 8,
            children: AIPresetManager.presets.map((preset) {
              final isSelected = selectedTone == preset.tone;
              return GestureDetector(
                onTap: () => setState(() => selectedTone = preset.tone),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected 
                        ? const Color(0xFF3B8AFF)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected 
                          ? const Color(0xFF3B8AFF)
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        preset.icon,
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        preset.name,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // 생성 버튼
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isGenerating ? null : _generateDescription,
              icon: isGenerating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(isGenerating ? 'AI 생성 중...' : '공고문 생성하기'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B8AFF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),

          // 생성된 내용 표시
          if (generatedContent != null) ...[
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 16),
            
            Row(
              children: [
                const Text(
                  '생성된 공고문',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (qualityReport != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getQualityColor(qualityReport!.score),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '품질: ${qualityReport!.score}점',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 200), // ✅ 최대 높이 제한
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: SingleChildScrollView( // ✅ 내용이 길 경우 스크롤
                child: Text(
                  generatedContent!,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ),
            ),
            
            // 품질 리포트
            if (qualityReport != null && 
                (qualityReport!.hasIssues || qualityReport!.suggestions.isNotEmpty)) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.lightbulb_outline,
                          color: Colors.orange.shade700,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'AI 개선 제안',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange.shade700,
                          ),
                        ),
                      ],
                    ),
                    if (qualityReport!.issues.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ...qualityReport!.issues.map((issue) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '• $issue',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange.shade700,
                          ),
                        ),
                      )),
                    ],
                    if (qualityReport!.suggestions.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      ...qualityReport!.suggestions.map((suggestion) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '💡 $suggestion',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange.shade600,
                          ),
                        ),
                      )),
                    ],
                  ],
                ),
              ),
            ],
            
            const SizedBox(height: 16),
            
            // 액션 버튼들
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _generateDescription,
                    icon: const Icon(Icons.refresh),
                    label: const Text('다시 생성'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => widget.onGenerated(generatedContent!),
                    icon: const Icon(Icons.check),
                    label: const Text('적용하기'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
          
          // 하단 여백 (키보드 대응)
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 20), // ✅ 추가 여백
        ],
      ),
    ),
  )
  );
}
  Future<void> _generateDescription() async {
    setState(() {
      isGenerating = true;
      generatedContent = null;
      qualityReport = null;
    });

    try {
      final content = await AIJobDescriptionService.generateJobDescription(
        title: widget.title,
        category: widget.category,
        location: widget.location,
        payType: widget.payType,
        pay: widget.pay,
        workingTime: widget.workingTime,
        weekdays: widget.weekdays,
        companyName: widget.companyName,
        isShortTerm: widget.isShortTerm,
        tone: selectedTone,
        
      );

      final report = AIJobDescriptionService.validateDescription(content);

      setState(() {
        generatedContent = content;
        qualityReport = report;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('공고문 생성 실패: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        isGenerating = false;
      });
    }
  }

  Color _getQualityColor(int score) {
    if (score >= 90) return Colors.green;
    if (score >= 80) return Colors.blue;
    if (score >= 70) return Colors.orange;
    return Colors.red;
  }
}