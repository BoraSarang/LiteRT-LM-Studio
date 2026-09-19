# PLAN_v108 — 한/영 다국어(즉시 전환) + 한국어 문구 다듬기 (T-361~T-366, macOS)

> 요구: 설정에 언어 항목(기본=시스템 언어), 한국어/영어 지원.
> 변경 시 재시작 없이 즉시 적용. 한국어 문구는 korean-humanizer로 다듬는다.

## 결정 사항

* 키 형식: **전부 시맨틱 키**(`settings.general.appearance` 형식).
* 번역 범위: 사용자 UI만. `DebugLogger` 로그·디버그 패널은 한국어 유지.
* 키 표현: 영역별 네임스페이스 + `static let`(없는 키는 컴파일 에러). 영역별 파일 분리.
  swiftlint `nesting` 때문에 타입 중첩은 1단계까지 → `L10n.Settings.generalTab` 꼴.
  호출은 항상 `L(L10n.…)`로 완전 정규화(선행 점 표기는 `L10nKey`로 추론돼 실패).
* 라이브 전환: `.environment(\.locale)` 의존 대신 **`L()` 명시 조회 + 루트 `.id(language)` 강제 리빌드**.
* 기준 언어: 한국어(`developmentRegion = ko` 유지). `Localizable.xcstrings`에 ko·en 병기.
* 미번역 키는 키 원문이 노출되므로 **커버리지 테스트**로 ko/en 누락을 차단.

## 단계

* T-361 인프라(**완료**): `LanguageManager`, `L()`/`T()`/`LK()`, `L10n` 키 레지스트리,
  `Localizable.xcstrings` 뼈대(9키 ko/en), 빌드 설정
  (`LOCALIZATION_PREFERS_STRING_CATALOGS=YES`, `SWIFT_EMIT_LOC_STRINGS=NO`), pbxproj 등록,
  설정 > 일반 > 외관 언어 세그먼트(시스템/한국어/English), 루트 주입(`languageAware`),
  커버리지 테스트(`LiteRTLMStudioLocalizationTests`). 315/315·build OK·lint 0.
* T-362 키 체계 + 순수 로직(**완료**): `L10n` 네임스페이스 13종(Appearance·Permission·Engine·History·
  Status·Benchmark·ModelCatalog·Model·Session·Sidebar·Inspector·Skill·Time·ToolStatus·MenuBar) 추가,
  `ToolCatalog`(키 파생)·`ModelCatalog`·`ModelAlias.modalities`·`BenchmarkHistory`·`MenuBarStatusText`·
  `ModelStore`·`ChatStore`·`SkillsStore`·`UnifiedStatus`·`MessageBubbles`(상대 시간)를 키 기반으로 전환.
  카탈로그 147키(도구 40키 포함), `LocalizationKeyIndex`로 전 키 인덱스 분리. 테스트는
  `LiteRTLMStudioTestCase`에서 한국어 고정 + 영어 전환·포맷·전 키 해석 검증. 318/318·build OK·lint 0.
* T-363 화면 치환(**완료**): 사이드바 → 메인/채팅 → 인스펙터 → 설정 5탭 → 모델관리/다운로드 → 벤치마크 →
  MCP·스킬 → 웰컴/정보/팔레트 → 카탈로그/가져오기 → 시스템 모니터·디버그·메뉴바·단축어 → 창 제목/앱 메뉴/마크다운
  순서로 영역별 12커밋. 키 파일은 `LocalizationKeys{Screens,Models,Views,Core}.swift`로 분할(file_length 회피).
  남은 한국어는 로그·도구 결과·프롬프트라 의도적 유지. 창 제목·앱 메뉴만 다음 실행 반영.
* T-364 카탈로그 채우기(**완료**): 표시 문자열이 있는 Core 로직까지 키 전환(설정 요약·추천 설명·PERF 뱃지·오류 문구·
  전원 요약·세션 기본 제목·칩 툴팁). 레지스트리 774키 / 카탈로그 814키, ko·en 100%.
* T-365 한국어 다듬기(**완료**): 카탈로그 ko·en 전수 스캔 후 연결어미 쉼표 1건·줄표 20건만 정리(번역체·피동·hype 0건).
* T-366 시스템/문서(**완료**): `InfoPlist.xcstrings`(권한 4건), 오류 코드 29개를 카탈로그 `error.<코드>`로 이관하고
  `error_message_ko.json` 삭제, README(한/영)·사용설명서·TODO·CHANGELOG·세션 로그에 언어 안내.
  창/메뉴 제목 즉시 갱신은 씬·메뉴 1회 구성 특성상 다음 실행 반영(눈확인 대기).

## 시스템 표면 한계

* 앱 내부(창 제목·메뉴·툴팁 포함)는 즉시 반영.
* 권한 요청 대화상자·macOS 기본 메뉴·Dock 메뉴는 OS 소유라 **다음 실행 때** 반영.
  변경 시 `AppleLanguages`를 함께 기록해 다음 실행에서 자동 일치시킨다.

## 검증

* 각 단계 build OK · 315/315 · swiftlint 0.
* 실측: 5탭·사이드바·메뉴바·창 제목을 한국어↔English로 전환해 즉시 반영 확인.
* 재실행 후 시스템 문구(권한 대화상자) 언어 일치 확인.

## 릴리스 (0.7.150)

* T-361~T-366 완료 후 `feat/i18n` PR #3 머지(`fb574be`) → 태그 `v0.7.150` → GitHub Release.
* MARKETING_VERSION 0.7.150 / CURRENT_PROJECT_VERSION 136, 단위 테스트 319/319.
* 문서: README(한/영) 스크린샷 4종, CHANGELOG는 릴리스 요약(상세는 `docs/CHANGELOG-DETAIL.md`) — 머리말에 기록 규칙 명시.
* 남은 확인: T-368(창 제목·앱 메뉴 다음 실행 반영, 권한 대화상자 문구).
