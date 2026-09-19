# PLAN_v97 — 인스펙터 3섹션 사이드바식 개편 (T-323, macOS)

> 스킬: `macos-app-design` + `apple-design` + `ios-the-final-5-percent`.
> 사용자 결정: 우측 유지·스타일만 변경 / 호버 메뉴=기본값 복원+섹션 숨기기 / 3섹션 전부.

## 변경 (InspectorView.swift)

* `inspector`: `Form`+`.grouped` → `List(.sidebar)`. 320 고정폭·on/off 조건 유지.
* `InspectorSectionHeader` 신규 (호버 시 ⋯ 메뉴, 사이드바·벤치 패턴):
  헤더=제목 11pt semibold secondary + 우측 상태 요약 1줄.
  요약: 시스템=LIVE/중지됨, 실행=변경됨/적용됨, 생성=온도·상위K.
  메뉴: "기본값으로 되돌리기" + "이 섹션 숨기기" (다시 켜기는 툴바 SectionSegments).
  섹션 본체에 동일 메뉴 contextMenu 병행.
* 기본값 (T-176 기준, 순수 상수+unit): 온도 1.0·상위K 64·상위P 0.95·
  Max nil·시드 nil·시스템 ""·추론 off·예산 -1.
  실행 되돌리기=`config.revert()` (변경 없으면 `load(modelID: chat.model)`).
* `modelRow`·사이드바 탭 잔여 `accentColor` → `DSColor.primary` 통일.

## 비목표

* 값 편집 컨트롤 동작 변경 없음. 적용/취소 플로우 유지.

## 검증

* 신규 unit 3건 (기본값 상수·생성 요약·실행 요약) + 기존 274 회귀.
* lint 신규 0 + build + 눈확인 (320폭 세그먼트 꺾임·DisclosureGroup).
