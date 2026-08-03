// ════════════════════════════════════════════════════════
//  공고 업종 분류 (등록·수정 화면 공용)
//
//  ⚠️ 이 목록은 DB의 jobs.category 에 그대로 저장된다.
//  등록 화면과 수정 화면이 서로 다른 목록을 쓰면, 등록된 공고를
//  수정 화면에서 열 때 DropdownButtonFormField 가 value 를 찾지 못해
//  debug 에서 assert 로 죽는다. 반드시 여기 한 곳만 고칠 것.
// ════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

class JobCategory {
  final IconData icon;
  final String name;
  final List<String> sub;
  const JobCategory({required this.icon, required this.name, required this.sub});
}

const jobCategories = [
  JobCategory(
    icon: Icons.restaurant_outlined,
    name: '음식점·카페',
    sub: ['홀서빙', '주방보조', '배달', '카페·바리스타', '패스트푸드', '포장·설거지'],
  ),
  JobCategory(
    icon: Icons.storefront_outlined,
    name: '편의점·마트',
    sub: ['편의점', '슈퍼·마트', '창고정리', '재고관리', '계산원'],
  ),
  JobCategory(
    icon: Icons.inventory_2_outlined,
    name: '물류·배송',
    sub: ['배송기사', '상하차', '물류센터', '포장', '택배분류', '입출고'],
  ),
  JobCategory(
    icon: Icons.factory_outlined,
    name: '제조·공장',
    sub: ['생산·조립', '검품·포장', '식품제조', '기계조작', '단순노무'],
  ),
  JobCategory(
    icon: Icons.memory_outlined,
    name: '반도체·전자생산',
    sub: ['반도체 생산', '전자부품 조립', 'PCB·SMT', '품질검사', '클린룸', '장비오퍼레이터'],
  ),
  JobCategory(
    icon: Icons.construction_outlined,
    name: '건설·현장',
    sub: ['건설일용', '인테리어', '청소·마감', '자재운반', '도장·도배'],
  ),
  JobCategory(
    icon: Icons.desktop_windows_outlined,
    name: '사무·행정',
    sub: ['사무보조', '데이터입력', '고객응대', '텔레마케터', '회계보조'],
  ),
  JobCategory(
    icon: Icons.cleaning_services_outlined,
    name: '청소·시설관리',
    sub: ['건물청소', '시설관리', '환경미화', '방역·소독', '세탁·세차'],
  ),
  JobCategory(
    icon: Icons.shopping_bag_outlined,
    name: '서비스·판매',
    sub: ['매장판매', '시식·홍보', '전단지', '주차관리', '안내·접수'],
  ),
  JobCategory(
    icon: Icons.event_outlined,
    name: '이벤트·행사',
    sub: ['행사스태프', '진행보조', '설치·철거', '모델·도우미', '공연스태프'],
  ),
];


/// 세부 직종 전체 (드롭다운 등 평면 목록이 필요할 때)
List<String> get allSubCategories =>
    jobCategories.expand((c) => c.sub).toList();

/// 세부 직종 → 대분류. 못 찾으면 빈 문자열.
String majorOfCategory(String val) {
  for (final c in jobCategories) {
    if (c.name == val || c.sub.contains(val)) return c.name;
  }
  return '';
}
