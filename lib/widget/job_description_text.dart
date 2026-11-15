import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// 공고 '하는 일' — 사장님이 쓴 원문을 그대로 쏟던 것을(2026-11-15 평가) 읽기 좋게 나눈다.
/// 글자는 바꾸지 않는다. 줄 모양만 본다:
///   `[보상안내]`·`보상안내:`·짧은 줄 뒤에 목록이 오면 → 소제목
///   `•`·`-`·`·`·`*`·`▶`·`✔`·`○`·`1.`로 시작 → 목록(점 + 매달린 들여쓰기)
///   빈 줄 여러 개 → 한 번의 간격
enum DescKind { heading, bullet, para, gap }

typedef DescBlock = ({DescKind kind, String text});

final _bullet = RegExp(r'^\s*(?:[•\-·\*▶▷✔✓○●◦]|\d{1,2}[.)])\s*');
final _bracketHead = RegExp(r'^\s*[\[【<〈]\s*(.+?)\s*[\]】>〉]\s*$');

List<DescBlock> parseDescription(String raw) {
  final lines = raw.replaceAll('\r', '').split('\n').map((l) => l.trimRight()).toList();
  final out = <DescBlock>[];
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i].trim();
    if (l.isEmpty) {
      if (out.isNotEmpty && out.last.kind != DescKind.gap) out.add((kind: DescKind.gap, text: ''));
      continue;
    }
    final head = _bracketHead.firstMatch(l);
    if (head != null) {
      out.add((kind: DescKind.heading, text: head.group(1)!));
      continue;
    }
    if (_bullet.hasMatch(l)) {
      final t = l.replaceFirst(_bullet, '').trim();
      if (t.isNotEmpty) out.add((kind: DescKind.bullet, text: t));
      continue;
    }
    final next = i + 1 < lines.length ? lines[i + 1].trim() : '';
    final shortLabel = l.length <= 18 && !RegExp(r'[.!?。]$').hasMatch(l.replaceFirst(RegExp(r':$'), ''));
    if (l.endsWith(':') && l.length <= 24 || shortLabel && _bullet.hasMatch(next)) {
      out.add((kind: DescKind.heading, text: l.replaceFirst(RegExp(r':$'), '')));
      continue;
    }
    out.add((kind: DescKind.para, text: l));
  }
  while (out.isNotEmpty && out.last.kind == DescKind.gap) {
    out.removeLast();
  }
  return out;
}

class JobDescriptionText extends StatelessWidget {
  final String text;
  const JobDescriptionText(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final body = AppTextStyles.body1.copyWith(height: 1.6);
    final blocks = parseDescription(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++)
          switch (blocks[i].kind) {
            DescKind.gap => const SizedBox(height: 10),
            DescKind.heading => Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 8, bottom: 4),
              child: Text(
                blocks[i].text,
                style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
            ),
            DescKind.bullet => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 점은 글 첫 줄 가운데에 맞춘다 — 둘째 줄부터는 글자 아래로 매달린다
                  Padding(
                    padding: const EdgeInsets.only(top: 10, left: 2, right: 10),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(color: AppColors.textTertiary, shape: BoxShape.circle),
                    ),
                  ),
                  Expanded(child: Text(blocks[i].text, style: body)),
                ],
              ),
            ),
            DescKind.para => Text(blocks[i].text, style: body),
          },
      ],
    );
  }
}
