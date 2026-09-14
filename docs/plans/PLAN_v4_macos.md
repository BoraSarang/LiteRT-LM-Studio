# PLAN v4 — 끊김 복구 + 채팅 다듬기 후속 (macOS)

> 전 세션 `LiteRTLM-Manager.json` idx 312~313에서 중단. T-035 완료, T-036 코드 완료·문서 미반영, T-037/T-038 코드 중단(빌드 깨짐), T-039~T-041 미착수.

## 1. 현 상태

* `ContentView.swift:276-303`: T-036 앵커를 `LazyVStack` 안으로 + 다음 런루프 스크롤 — 코드 반영됨, TODO만 미체크.
* `MarkdownView.swift:11-32`: T-037 `NoScrollWKWebView` 세로 포워딩·가로 내부 — 코드 반영됨.
* `MarkdownView.swift:64-122`: T-038 `pendingHTML` flush — 코드 반영됨, 회귀 테스트 없음.
* 빌드 깨짐: `template(scheme:)` 호출 2곳 vs `static let template` 정의 1곳 불일치 — `xcodebuild` 실패 상태.
* T-039 미착수: 하단 패널이 `NavigationSplitView` 바깥 전폭 (`ContentView.swift:82-85`).
* T-040 미착수: `MarkdownPage.template` 단일, 시스템 토큰(`-apple-system-*`)만 사용.
* T-041 부분: `MarkdownScheme` enum만 있고 `DS`·`AppearanceMode`·설정 피커 없음.

## 2. 단계

* T-036/T-037/T-038 확정: `template(scheme:)` 함수로 교체 + `needsFlush` 회귀 테스트 + TODO 체크 + CHANGELOG 0.7.8.
* T-039: 하단 패널을 `chatPane` VStack 하단으로 이동 (사이드바 제외). `logPanelVisible`·`BottomPanelView` 재사용, 높이 180 유지.
* T-040: `template(scheme:)` 명시 이중 CSS — light/dark 고정 색, auto는 기존 시스템 토큰. 수동 외관 파라미터로 선택.
* T-041: `Core/DS.swift` 경량 토큰(간격·radius·폰트) + `AppearanceMode`(시스템·라이트·다크) + `NSApp.appearance` 적용 + 설정 세그먼트 + 재실행 유지(`AppStorage`). 웹뷰는 scheme 파라미터, 차트는 시맨틱 컬러 그대로.

## 3. 검증

* 각 단계: `xcodebuild test` (변경 관련) + `swiftlint` + `xcodebuild build` (포그라운드 `open` 없이).
* 눈 확인은 빌드 성공 후 사용자 확인 시에만 앱 실행.
* 회귀: `needsFlush` 판정식, `AppearanceMode` 매핑.

## 4. T-044/T-045 후속 (2026-09-14 추가)

* T-044 추종 게이트: 토큰마다 무조건 끌어내리던 것을 휠 제스처 0.8s 우선+0.4s 스로틀로 변경 (`shouldFollow` 순수 판정).
* T-045 CPU 100%·응답 없음: `sample` 결과 메인스레드가 레이아웃 재귀에 전부 소진 — 1Hz 모니터 틱이 `ContentView` 전체(수십 웹뷰) 리렌더가 원인. `monitor` 관찰을 미터 서브트리로 축소 + `MarkdownView` equatable로 구버블 갱신 차단. 검증은 idle CPU+샘플로 확정.
