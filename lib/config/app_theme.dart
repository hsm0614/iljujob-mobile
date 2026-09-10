// =========================================================
// 알바일주 디자인 시스템
// =========================================================
// 모든 색상/텍스트/그림자/간격은 여기서만 정의
// 화면에서는 AppColors.primary 등으로 참조

import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────
// 색상 토큰
// ─────────────────────────────────────────────────────────
class AppColors {
  AppColors._();

  // ── Brand ──────────────────────────────────────────────
  static const primary      = Color(0xFF3B8AFF); // 브랜드 블루 (메인 액션)
  static const primaryDark  = Color(0xFF1D68E5); // Hover/Pressed
  static const primaryLight = Color(0xFFEEF5FF); // 배경 틴트
  static const primaryMid   = Color(0xFFBDD9FF); // 포커스 링/구분선

  // ── Neutral ────────────────────────────────────────────
  static const bgPage    = Color(0xFFF4F6FA); // 페이지 배경 (카드 그림자 살리는 연회색)
  static const bgBase    = Color(0xFFF4F6FA); // bgPage 별칭
  static const bgCard    = Color(0xFFFFFFFF); // 카드/시트 배경
  static const bgMuted   = Color(0xFFF2F4F8); // 비활성 배경 (칩, 인풋)

  // ── Border ─────────────────────────────────────────────
  static const border    = Color(0xFFE5E8EB); // 일반 구분선
  static const borderSub = Color(0xFFF0F2F5); // 연한 구분선

  // ── Text ───────────────────────────────────────────────
  static const textPrimary   = Color(0xFF191F28); // 제목·강조
  static const textSecondary = Color(0xFF6B7280); // 본문
  static const textTertiary  = Color(0xFF9CA3AF); // 힌트·보조
  static const textDisabled  = Color(0xFFD1D5DB); // 비활성

  // ── Semantic ───────────────────────────────────────────
  static const error   = Color(0xFFDC2626);
  static const success = Color(0xFF10B981);
  static const warning = Color(0xFFF59E0B);
  static const warningDark = Color(0xFF92400E);
  static const warningLight = Color(0xFFFFF7ED);
  static const warningBorder = Color(0xFFFED7AA);
  static const info    = Color(0xFF3B8AFF);

  // ── Badge 색상 ─────────────────────────────────────────
  // DESIGN.md Two-Signal: 뱃지 색은 주황(시간 급함)과 초록계열(돈·신뢰) 둘뿐이다.
  // 급여형(일급/주급/월급)은 모든 공고에 붙는 정보라 색을 주지 않는다 —
  // 파랑·인디고·하늘로 나눠 놨더니 서로 구분도 안 되고, 파랑은 "누를 수 있는 것"
  // 신호를 뺏어갔다. 급여형 뱃지는 중립(textSecondary)으로 그린다.
  static const badgeUrgent  = Color(0xFFEA8035); // 시간: 긴급·마감임박
  static const badgeSameDay = Color(0xFF059669); // 돈: 당일지급
  static const badgeSafe    = Color(0xFF4D7C0F); // 신뢰: 안심기업
  static const badgeNew     = Color(0xFFE55353); // 찜(하트) 전용 — 뱃지 아님

  // ── 제품·상태 색 ───────────────────────────────────────
  // 화면마다 하드코딩돼 있던 값을 여기로 올린다. 값은 그대로 두고
  // 관리 지점만 하나로 모은다 — 색 정책을 바꿀 때 여기 한 줄만 고치면 된다.
  /// 긴급호출(유료 상품) 브랜딩 색. 그라디언트 [urgentCall, error] 로 쓰인다.
  static const urgentCall = Color(0xFFEF4444);
  /// 진행 중·대기 상태(출근확정 proposed, 프로 플랜 등)
  static const pending = Color(0xFFFF9500);
  /// AI 기능 표시
  static const aiAccent = Color(0xFF6C5CE7);

  // ── 구직자 활동등급 (CLAUDE.md 스펙) ───────────────────
  static const gradeS = Color(0xFFFF6B00); // 100점 이상
  static const gradeA = primary;           // 70~99
  static const gradeB = Color(0xFF22C55E); // 40~69
  static const gradeC = textTertiary;      // 20~39 · NEW
}

// ─────────────────────────────────────────────────────────
// 그림자 토큰
// ─────────────────────────────────────────────────────────
class AppShadows {
  AppShadows._();

  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x0D000000), // black 5%
      blurRadius: 12,
      offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> cardElevated = [
    BoxShadow(
      color: Color(0x14000000), // black 8%
      blurRadius: 20,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> button = [
    BoxShadow(
      color: Color(0x333B8AFF), // primary 20%
      blurRadius: 10,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> bottomNav = [
    BoxShadow(
      color: Color(0x0A000000),
      blurRadius: 16,
      offset: Offset(0, -2),
    ),
  ];
}

// ─────────────────────────────────────────────────────────
// 라운드 반경 토큰
// ─────────────────────────────────────────────────────────
class AppRadius {
  AppRadius._();

  static const double xs  = 6;
  static const double sm  = 8;
  static const double md  = 12;
  static const double lg  = 16;
  static const double xl  = 20;
  static const double xxl = 24;
  static const double full = 999;
}

// ─────────────────────────────────────────────────────────
// 텍스트 스타일 토큰
// ─────────────────────────────────────────────────────────
class AppTextStyles {
  AppTextStyles._();

  // 제목
  static const h1 = TextStyle(
    fontSize: 24, fontWeight: FontWeight.w800,
    color: AppColors.textPrimary, height: 1.2,
  );
  static const h2 = TextStyle(
    fontSize: 20, fontWeight: FontWeight.w700,
    color: AppColors.textPrimary, height: 1.3,
  );
  static const h3 = TextStyle(
    fontSize: 17, fontWeight: FontWeight.w700,
    color: AppColors.textPrimary, height: 1.3,
  );

  // 본문
  static const body1 = TextStyle(
    fontSize: 15, fontWeight: FontWeight.w400,
    color: AppColors.textPrimary, height: 1.5,
  );
  static const body2 = TextStyle(
    fontSize: 13, fontWeight: FontWeight.w400,
    color: AppColors.textSecondary, height: 1.5,
  );

  // 캡션
  static const caption = TextStyle(
    fontSize: 11, fontWeight: FontWeight.w400,
    color: AppColors.textTertiary, height: 1.4,
  );
  static const captionBold = TextStyle(
    fontSize: 11, fontWeight: FontWeight.w600,
    color: AppColors.textTertiary, height: 1.4,
  );

  // 버튼
  static const btnLg = TextStyle(
    fontSize: 16, fontWeight: FontWeight.w700,
    color: Colors.white, height: 1.0,
  );
  static const btnMd = TextStyle(
    fontSize: 14, fontWeight: FontWeight.w600,
    height: 1.0,
  );
  static const btnSm = TextStyle(
    fontSize: 12, fontWeight: FontWeight.w600,
    height: 1.0,
  );

  // 공고 카드 전용
  static const jobTitle = TextStyle(
    fontSize: 15.5, fontWeight: FontWeight.w700,
    color: AppColors.textPrimary, height: 1.3,
  );
  static const jobPay = TextStyle(
    fontSize: 18, fontWeight: FontWeight.w800,
    color: AppColors.textPrimary, height: 1.1,
  );
  static const jobPayType = TextStyle(
    fontSize: 12, fontWeight: FontWeight.w600,
    color: AppColors.primary,
  );
  static const jobMeta = TextStyle(
    fontSize: 12, fontWeight: FontWeight.w500,
    color: AppColors.textTertiary,
  );
  static const jobLocation = TextStyle(
    fontSize: 12, fontWeight: FontWeight.w500,
    color: AppColors.textTertiary,
  );
}

// ─────────────────────────────────────────────────────────
// 공통 위젯 스타일 헬퍼
// ─────────────────────────────────────────────────────────
class AppDecorations {
  AppDecorations._();

  static BoxDecoration card({
    double radius = AppRadius.lg,
    bool elevated = false,
  }) =>
      BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: elevated ? AppShadows.cardElevated : AppShadows.card,
      );

  static BoxDecoration inputField({bool focused = false}) => BoxDecoration(
        color: AppColors.bgMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: focused ? AppColors.primary : AppColors.border,
          width: focused ? 1.5 : 1,
        ),
      );

  static BoxDecoration chip({bool selected = false}) => BoxDecoration(
        color: selected ? AppColors.primary : AppColors.bgMuted,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.border,
        ),
      );

  static BoxDecoration primaryButton() => BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.button,
      );
}

// ─────────────────────────────────────────────────────────
// ThemeData — MaterialApp에 적용
// ─────────────────────────────────────────────────────────
class AppTheme {
  AppTheme._();

  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        // 알바일주는 라이트 전용이다. 화면 색이 하드코딩으로 흩어져 있어
        // 다크 팔레트를 얹으면 절반만 뒤집힌 화면이 나온다.
        // brightness 를 명시해야 시스템 다크에서 키보드·시트 같은 네이티브
        // 요소까지 라이트로 따라온다. (다크 지원은 색 토큰화가 끝난 뒤)
        brightness: Brightness.light,
        // Jalnan2TTF는 브랜드명/타이틀에만 명시적으로 사용
        // 전역 적용 시 모든 텍스트가 볼드처럼 보이므로 시스템 폰트 사용
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
          primary: AppColors.primary,
          secondary: AppColors.primaryDark,
          surface: AppColors.bgCard,
          error: AppColors.error,
          onPrimary: Colors.white,
          onSurface: AppColors.textPrimary,
        ),
        scaffoldBackgroundColor: AppColors.bgPage,
        // AppBar
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.bgCard,
          foregroundColor: AppColors.primary,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          centerTitle: false,
          // 푸시된 화면 제목은 다크 잉크 + 시스템 폰트
          // (Jalnan·브랜드 블루는 탭 루트의 파란 헤더 같은 브랜드 순간 전용)
          titleTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
          iconTheme: IconThemeData(color: AppColors.primary),
        ),
        // ElevatedButton
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            textStyle: AppTextStyles.btnLg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
        ),
        // OutlinedButton
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            textStyle: AppTextStyles.btnMd,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
        ),
        // TextButton
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            textStyle: AppTextStyles.btnMd,
          ),
        ),
        // InputDecoration
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.bgMuted,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
          hintStyle: const TextStyle(
            color: AppColors.textTertiary,
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
        ),
        // Chip
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.bgMuted,
          selectedColor: AppColors.primaryLight,
          labelStyle: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
        // SnackBar
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppColors.textPrimary,
          contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
        // BottomSheet
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: AppColors.bgCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadius.xl),
            ),
          ),
        ),
        // Divider
        dividerTheme: const DividerThemeData(
          color: AppColors.borderSub,
          thickness: 1,
          space: 0,
        ),
        // FloatingActionButton
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 4,
          shape: CircleBorder(),
        ),
        // TextTheme (기본)
        textTheme: const TextTheme(
          displayLarge: AppTextStyles.h1,
          headlineMedium: AppTextStyles.h2,
          titleLarge: AppTextStyles.h3,
          bodyLarge: AppTextStyles.body1,
          bodyMedium: AppTextStyles.body2,
          labelSmall: AppTextStyles.caption,
        ),
      );
}
