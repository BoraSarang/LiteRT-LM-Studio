# PLAN_v100 — 커맨드 팔레트 개편 (T-326, macOS)

> 파일은 기존 `PaletteViews.swift` 유지 (CommandPaletteView.swift 없음).
> 기존 T-263/264 동작·키보드(↑↓·Enter·Esc) 유지.

## 변경

* `KoreanMatch.matchRanges` 신규 (순수): 공백 건너뛰기 순차 스캔,
  `ㅅㅊㅌ`→`새 채팅` 매칭. 기존 matches/range/window 불변.
* 명령 필터에 matchRanges 적용 + 매칭 글자 Bold·Primary 하이라이트.
* `PaletteRecents` 신규 (UserDefaults, 순수·주입 가능): 실행 시 기록,
  빈 질의면 `최근 사용` 최대 5개 (없으면 기본 5종).
* 섹션: 최근 사용 / 명령 / 채팅 기록(개명) / 벤치마크(새 벤치마크·열기,
  bench/history 주입, 기존 알림 재사용).
* 행 아이콘 + 단축키 없으면 설명 문구. 선택 틴트 Primary 통일.

## 검증

* 신규 unit 4건 (ranges·recents·하이라이트 분기·벤치 필터) + 회귀.
* 완료 조건: `ㅅㅊㅌ`→새 채팅 하이라이트, 빈 상태 최근 5개.
