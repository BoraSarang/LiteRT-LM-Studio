# PLAN v27 — 입력창 Menu 피커 + 툴바 경로 추종 (macOS)

## 1. 목표

깨진 segmented 피커 레이아웃 수정 + 툴바 시작/중지를 선택 경로 추종으로.
(사용자 선택: 피커 2안 Menu, 툴바 1안 추종. 스킬 macos-app-design 경유.)

## 2. 변경

* T-188 입력창 경로 피커 Menu화: `.pickerStyle(.menu)`, 고정폭 제거,
  help 유지. 동작·게이트 변경 없음 (`ChatInputBar.swift` 1곳).
* T-189 툴바 경로 추종: `serverIcon`·`toggleServer()`·`serverHelp`를
  route 분기로. 네이티브 선택 시 prepare/release, 데몬 선택 시 start/stop.
  "다시 실행"은 사이드바 전용 유지. ⌘R/⌘.는 현재 경로에 추종.
  (`ChatScrollActions.swift` 3곳, 폴러·상태 로직 불변.)

## 3. 비범위

* 툴바 버튼 분리 (2안 기각), segmented 유지 (1안 기각).
* 전송 게이트·네이티브 수명주기 변경 없음.

## 4. 검증

* unit 기존 101 유지 (순수 로직 추가 없음) + lint 신규 0.
* `build macos` 설치·눈확인: 메뉴 펼침, 툴바 경로별 전환 4종.
