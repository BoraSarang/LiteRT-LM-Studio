# PLAN_v96 — 디자인 시스템 + 4화면 UI/UX 개선 (macOS)

> 스킬: `macos-app-design` + `apple-design` + `ios-the-final-5-percent`. 기준: 딱 맥 앱 같아야 함.
> 사용자 결정: 네이티브 segmented 공통 컴포넌트화(AGENTS.local 예외 기록) / `#0A84FF` 고정 / 신규 4파일+구연동 / 종지 스킵.

## 0. 범위

- 토큰 4파일 신규: `Core/DSTokens/Colors.swift·Typography.swift·Spacing.swift·Components.swift`. `DS.swift`·`DSComponents.swift`는 별칭 유지.
- 화면: Main Chat(툴팁·GPU hover·DSSegmented·한글화) / Browse(중복 제거·한글화) / My Models(경고배너·Badge·확장자 숨김) / Benchmark(2줄 셀·수치라벨·MTP 툴팁) / Settings(Section 4개·ScrollView·DSSegmented).
- "종지" 오타: 코드 0건이므로 스킵. README 이미 마크다운 네이티브, 다운로드는 이미 Primary 위계 → 토큰 교체만.

## 1. 토큰 설계

- `Colors`: primary `#0A84FF` 고정(라이트/다크 동일, DESIGN 시맨틱 예외), success `#30D158`, warning `#FF9F0A`, error `#FF453A`.
- `Typography`: title/heading/body/callout/caption(11pt)/mono(SF Mono 12).
- `Spacing`: 4/8/12/16/24, radius 8/10/12, chatMaxWidth 768 승계.
- `Components`: DSPrimaryButton·DSSecondaryButton·DSTextLink·DSSegmented(내부 `.pickerStyle(.segmented)`)·DSSection·DSBadge(아이콘+텍스트)·DSWarningBanner(텍스트+액션)·DSTooltip(HoverTipBox 래핑)·DSCard(cardBox 래핑). 전 화면 커스텀 스타일 금지.

## 2. 화면별 변경

- Main Chat: `SidebarView` LabeledRow·모델행 `.help(전체값)`. `SystemMonitorView` GPU popover 추가. `InspectorView:157-179` → DSSegmented. 한글화: 온도/상위K/상위P/시드/추론/함수 호출/디스크/메모리/사용 안 함.
- Browse: `CatalogBrowserView:20-24,147-164` 추천 모드 listPane 제거, recommendedPane만(용량+설치 배지). `Download Options`→다운로드 옵션, `PARAMS`→매개변수.
- My Models: `ModelManagerView:287` 상단 DSWarningBanner+원본 삭제(권한 게이팅+확인 팝업). 상태 점→DSBadge. `friendlyName` 헬퍼로 `.litertlm` 숨김(스테이징·파트·Picker·예시).
- Benchmark: 2줄 셀(모델명+상태·시간·속도)+실패 사유. `miniChart:289-296` BarMark annotation 수치 라벨. `powerLine`에 MTP 풀어쓰기 툴팁.
- Settings: 일반탭 DSSection 4개(외관·시스템·대화·권한)+ScrollView. 4 Picker→DSSegmented.

## 3. 커밋 순서

- P0: 토큰 4파일 → 중복 제거·잘림·한글화.
- P1: 경고배너·버튼위계·Badge·확장자 숨김.
- P2: 차트라벨·툴팁·EmptyState.

## 4. 검증

- `xcodebuild test` 변경분 관련 + swiftlint 신규 0 + `./build_and_run.sh build macos`.
- DebugPanel ERROR 0, `[INFO] [FEATURE]` 로그 확인. `error_message_ko.json` 신규 코드 있으면 추가, CHANGELOG 기록.
