# PLAN v30 — 라이브 코드·빈 방 간헐 해소 리팩토링 (macOS)

## 1. 목표

무거운 방(긴 코드·표 다수)에서 가끔 재현되는 2종 해소. 구조 리팩토링, 두 증상 동등 우선.
T-200 계측 → T-201 렌더 → T-202 스크롤 → T-203 검증 순.

## 2. 근본원인 (조사 확정)

* 렌더 R1: `splitFences` 미완성 펜스 뒤집힘 (`NativeMarkdown.swift:31-36`). 스트리밍 중간 꼬리 prose가 code로 오분류, flush마다 경계 진동.
* 렌더 R2: `ForEach id: offset` (`MarkdownView.swift:27`) 블록 수 변하면 `@State highlighted/highlightedCode`(`167-168`) 오부착.
* 렌더 R3: 작업키 `"streaming"` 공유 (`171-173,208-209`) + 빈 초깃값 (`splitCode` trim → body "").
* 스크롤 S1: 뷰 파괴/재부착 레이스. 전환 시 ScrollView 파괴, `ScrollViewFinder` 재탐색 최대 2.0초 (`FollowGate.swift:29-47`), 즉시 점프 no-op (`ChatScrollActions.swift:66-67`).
* 스크롤 S2: `entryWorks` 공유 취소. finish(`158-159`)가 폴링+지연보정(1.5/3/5초) 둘 다 취소.
* 스크롤 S3: `session==nil` 통과 (`entryPoll:100`) 구 예약이 신방 통과.
* 스크롤 S4: 편측 보정. `clampToDocument`(`183-193`)는 아래 초과만, 위 고착은 미대응.

## 3. 변경

* T-200 계측 (동작 불변): 진입 로그에 finder 부착·docH·verdict 추가. 펜스 블록 수·빈 코드 빈도 Debug 로그. 버전 0.7.136.
* T-201 렌더 (`MarkdownView`+`NativeMarkdown`): 미닫힘 펜스 별도 케이스(`codePending`), 블록 해시 id, 빈 코드 높이 예약, 블록별 안정 task id. 버전 0.7.137.
* T-202 스크롤 (`ChatScrollActions`+`FollowGate`+`ChatPaneView`): entryWorks/보정works 분리, 전환 시 scrollView nil 리셋, 진입 epoch 토큰, 양측 보정. 버전 0.7.138.
* T-203 검증·문서: full+lint+build, DESIGN·CHANGELOG·사용설명서 현행화.

## 4. 검증

* 각 단계 `test macos full` + swiftlint 신규 0 + `build macos` 설치·실행.
* 무거운 방 전환 10회 + 스트리밍 코드방 3회 눈확인 (사용자).
* PERF/CACHE 영향 없음 (렌더·점프 경로만, 모니터 1Hz 불변).

## 5. 위험·롤백

* 파서 API 변경 시 기존 테스트 수정 필요 → 순수 함수부터 교체, 구 API shim 유지.
* task id 변경 시 T-196 CPU 회귀 가능 → 스트리밍 중 승격 차단 유지, full+수동 CPU 확인.
* 스크롤 epoch 도입 시 FollowGate 필드 추가 → 기존 저장값 무영향(메모리 상태만).
