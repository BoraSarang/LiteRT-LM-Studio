# PLAN_v101 — 리스트 배경·카드화 (T-327, macOS)

> 스킬: `macos-app-design` + `apple-design` + `ios-the-final-5-percent`.
> 사용자 결정: 시맨틱 대체 / 흰색 카드 전체 섹션.

## 매핑 (라이트 동일 발색, 다크 대응)

* 리스트 `#F5F5F7` → `Color(nsColor: .controlBackgroundColor)` 3곳.
* 상세 `#FFFFFF` → `Color(nsColor: .textBackgroundColor)` 명시 보강.
* 사이 divider → `Divider()` + `.separator` 2곳 (찾아보기·벤치 HSplit).

## 구현

* `Components.swift`: `DSCardRow` 신규 (흰 배경·radius 12·padding 12·
  shadow 0/1/2 6%). List `.scrollContentBackground(.hidden)` 후 배경 지정.
* 내 모델 4행 (`DownloadRow`·`orphanRow`·`installedRow`·`stagedRow`) 카드화.
  선택 틴트·메뉴·Badge 유지.

## 검증

* 회귀 test + lint 신규 0 + build + 눈확인 (라이트/다크).
