# PLAN v44 — 사이드바 채팅식+측정 헤더 고정 (macOS)

## 1. 목표

눈확인 후속 2건. T-225 사이드바 채팅식 / T-226 우측 헤더 고정.

## 2. 변경

* T-225: `BenchmarkListView` 신규 (새 벤치마크 버튼+전체 선택행+호버 메뉴+삭제).
  선택은 `history.selectedRecordID` 공유로 창과 동기 (채팅 currentSessionID 대응).
  모델 우클릭 실행·새 벤치마크는 선택 해제 후 예약. `recent(limit:)` 유지 (창 필터용).
* T-226: 우측 `measurePane`을 상단 고정(새 측정+구분선)+하단 스크롤(결과)로 분리.

## 3. 검증

* full 125/125 + lint 신규 0 + build 설치. 눈확인: 사이드바 선택 틴트·새 벤치마크·스크롤 고정.
* PERF/CACHE 영향 없음.
