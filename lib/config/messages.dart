/// 사용자에게 보이는 공통 문구.
///
/// 화면마다 따로 쓰던 걸 여기 하나로 모은다. 규칙 두 가지:
///   1. 말투는 '-해요'체로 통일한다. ('-합니다'체와 섞이면 앱이 여러 사람이 만든 것처럼 읽힌다)
///   2. 예외 객체($e)·서버 응답 본문을 절대 넣지 않는다. 진단은 debugPrint 로만 남긴다.
class Msg {
  Msg._();

  // ── 연결·서버 ────────────────────────────────────────
  static const network = '연결이 불안정해요. 잠시 후 다시 시도해 주세요.';
  static const server = '잠시 문제가 생겼어요. 잠시 후 다시 시도해 주세요.';

  // ── 인증 ─────────────────────────────────────────────
  static const loginRequired = '로그인이 필요해요.';
  static const loginExpired = '로그인이 만료됐어요. 다시 로그인해 주세요.';
  static const verifyFailed = '본인인증에 실패했어요. 잠시 후 다시 시도해 주세요.';
  static const signupFailed = '가입을 완료하지 못했어요. 잠시 후 다시 시도해 주세요.';

  // ── 지원·찜 ──────────────────────────────────────────
  static const applyDone = '지원했어요.';
  static const applyDuplicate = '이미 지원한 공고예요.';
  static const applyFailed = '지원하지 못했어요. 잠시 후 다시 시도해 주세요.';
  static const applyCancelFailed = '지원을 취소하지 못했어요. 잠시 후 다시 시도해 주세요.';
  static const bookmarkFailed = '찜을 해제하지 못했어요. 잠시 후 다시 시도해 주세요.';

  // ── 채팅 ─────────────────────────────────────────────
  static const chatCreateFailed = '채팅방을 열지 못했어요. 잠시 후 다시 시도해 주세요.';
  static const chatListFailed = '채팅 목록을 불러오지 못했어요. 잠시 후 다시 시도해 주세요.';
  static const chatLeaveFailed = '채팅방을 나가지 못했어요. 잠시 후 다시 시도해 주세요.';

  // ── 저장·조회 ────────────────────────────────────────
  static const saveFailed = '저장하지 못했어요. 잠시 후 다시 시도해 주세요.';
  static const loadFailed = '불러오지 못했어요. 잠시 후 다시 시도해 주세요.';
  static const deleteFailed = '삭제하지 못했어요. 잠시 후 다시 시도해 주세요.';
  static const reviewFailed = '후기를 등록하지 못했어요. 잠시 후 다시 시도해 주세요.';
  static const applicantLoadFailed = '지원자 정보를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.';
  static const messageSendFailed = '메시지를 보내지 못했어요. 잠시 후 다시 시도해 주세요.';
  static const withdrawFailed = '탈퇴를 처리하지 못했어요. 잠시 후 다시 시도해 주세요.';
}
