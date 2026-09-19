# PLAN_v102 — 메인 사이드바 리스트 배경 (T-328, macOS)

> T-327 후속. 사용자 결정: 스크롤 리스트 배경만 / 환경 고정 영역 현행 유지.

## 변경 (SidebarView.swift 1곳)

* 스크롤 List(`77-86`)에 `.scrollContentBackground(.hidden)` +
  `Color(nsColor: .controlBackgroundColor)` 배경.
* 환경 고정 List·탭·행 불변. 사이드바↔채팅 구분선은 네이티브 스플리터 유지.

## 검증

* 회귀 test + lint 신규 0 + build + 눈확인 (라이트/다크).
