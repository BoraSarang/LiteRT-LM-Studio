# PLAN v50 — 카탈로그 다듬기 묶음 (macOS, T-237~240)

## 1. 목표

* T-237 README HTML 표: `<table>` 구간 → 네이티브 표, 링크 셀은 파일명만.
* T-238 용어: Staff picks → 추천 모델 (노출 2건+내부 정리).
* T-239 용량: HEAD 리다이렉트 차단 + `x-linked-size` 우선 + Range 폴백.
* T-240 탭·컨트롤: segmented 고정폭 → 전폭 버튼 (탭 50/50·패밀리 4등분).
  AGENTS.local 규칙 1줄 추가.

## 2. 변경

* `NativeMarkdown.swift`: HTML 표 파싱 순수 3건 + `parseProse` 구간 연동.
* `ModelCatalog.swift`: `StaffPick`→`RecommendedModel`, `staffPicks()`→`recommendedModels()`,
  `CatalogStore.picks`→`recommended`. 호출부·테스트 동반 수정.
* `ModelDownload.swift`: `linkedSize(headers:)`·`redirectTarget`·`rangeTotal` 순수 3건 +
  `remoteFileSize` 재작성 (리다이렉트 차단 delegate).
* `CatalogBrowserView.swift`: 탭·패밀리 전폭 버튼, 용어 찾아보기·내 모델 (T-240에서 확정분 반영).
* `ModelManagerView.swift`: 탭 라벨 찾아보기·내 모델.
* `AGENTS.local.md`: 탭·필터 전폭 버튼 규칙 1줄.
* `error_message_ko.json`: 변경 없음 (E-MAC-NET-0013 재사용).
* 회귀 6건: HTML 스트립·표 변환·혼합 통합 + linkedSize·redirect·range.

## 3. 검증

* unit 148/148 + lint 신규 0 + `build macos` 2회 + DebugPanel ERROR 0.
* 눈확인: 표 렌더·용어·전폭 탭·용량 표시·추천 목록.
