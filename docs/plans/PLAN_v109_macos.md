# PLAN_v109 — UI P1 14건 + 리팩터 S (T-378·T-379, macOS)

## 배경
* 재감사 스캔: 색 토큰 위반·접근성·모션·DateFormatter 중복·경로 폴백 중복.
* T-368(눈확인)·T-010(벤더) 제외.

## T-378 UI P1 (화면·접근성·모션)
1. SettingsMCPSkillViews `Color.red` → `DSColor.error`
2. ChatPaneView `Color.black` 그림자 → `.primary.opacity(0.12)` (다크·라이트 공용)
3. ChatPaneView `Color.yellow` 하이라이트 → `DSColor.warning.opacity(0.25)`
4. ChatOutlineView 확장 애니메이션 reduceMotion 가드
5. ChatPaneView 후속질문 애니메이션 reduceMotion 가드
6. DebugPanelView 스크롤 애니메이션 reduceMotion 가드
7. 인스펙터 라벨 고정폭 140/100 → minWidth 유지 + flexible
8. 팔레트·시트 고정폭 시트에 minHeight 없음 → ImportSheet `minHeight` 보강
9. 아이콘 전용 버튼 대표군에 `.help`/`accessibilityLabel` 보강(세션·벤치·하단·인스펙터)
10. SystemMonitor 차트 색: 시맨틱 주석 + `DSColor` 대체 가능 구간 정리
11. WelcomeView/AboutView `NSImage()` 폴백 → symbol 대체 체인 정리
12. BenchmarkWindowSections/MessageBubbles/ChatStore+Generation `DateFormatter` 생성 → `TimeFormat` 공용 헬퍼 재사용
13. 시트 `frame(width:)`에 `minHeight`·`idealHeight`로 세로 잘림 방지(Alias·Palette·Settings)
14. BottomPanel 세그먼트 폭 160 고정 → minWidth·padding으로 한글 라벨 폭 여유

## T-379 리팩터 S (중복 제거)
* `LibrarySupport` 경로 폴백 헬퍼 신규: ChatStore·ReleaseNotes·BenchmarkHistory·StudioMigrator 4곳 통합
* `TimeFormat`에 날짜 표시 헬퍼 추가(로케일 주의), DateFormatter 중복 제거
* NSAlert confirm 2행 패턴(ModelManagerView.confirm)을 세션·다운로드 공용 가능 구간만 문서화(과도 통합 금지)

## 검증
* `swiftlint --quiet LiteRTLMStudio` 신규 0
* `xcodebuild test` 325/325 이상 유지
* pbxproj: 신규 파일 4섹션 등록

## 제외
* Tool.swift 벤더(T-010), T-368 눈확인, LogicTests 대분할(M·후속)
