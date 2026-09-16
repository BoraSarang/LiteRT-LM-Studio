# PLAN v43 — 분석 표기·복사+기록별 결과 분리 (macOS)

## 1. 목표

눈확인 후속 2건. T-223 분석 엔진 표기+복사 / T-224 기록별 분석·원문.

## 2. 현상 근거 (사용자 로그·스크린샷)

* T-223: AI 분석 헤더가 분석 엔진만 표시 ("CLI 데몬로 분석") → 네이티브로 측정한
  사용자가 "난 네이티브인데 CLI라고 나옴" 혼란. 실제로 헤더는 분석을 돌린 엔진이 맞음.
* T-223: 분석 결과 복사 버튼 없음.
* T-224: 분석 결과·원문 로그가 전역 상태 → 기록을 바꿔도 안 바뀜.
  결정적 조건: `store.metrics != nil`이면 기록 분기가 막혀 "측정 전"으로 떨어짐
  (완료·중단 한 번이면 이후 클릭이 전부 빈 화면).

## 3. 변경

* T-223: `AnalysisJob` 스냅샷(프롬프트+엔진 표기), 헤더를 "측정 {route} · 분석 {label}"로,
  분석 결과 복사 버튼(CopyFlag 피드백).
* T-224: `analysisCache/analysisEngineByRecord/analyzingSlotID` 슬롯별 상태,
  `BenchmarkRecord.logTail`(종료 시점 100줄, 구 JSON 호환 디코딩),
  상세 우선순위 실행 중>명시 선택>라이브 완료>최신 기록>빈 상태 (`BenchmarkDetailMode`).
* 파일 분리: `BenchmarkPower`/`BenchmarkAnalysis`/`BenchmarkWindowSections`+pbxproj.

## 4. 검증

* full 125/125 + lint 신규 0 + build 설치. 눈확인: 기록 클릭 전환·복사·헤더 표기.
* PERF/CACHE 영향 없음.
