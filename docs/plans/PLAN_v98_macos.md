# PLAN_v98 — 인스펙터 실행/생성 탭 구분 (T-324, macOS)

> 스킬: `macos-app-design` + `apple-design` + `ios-the-final-5-percent`.
> 사용자 결정: 시스템 상단 고정 + 아래 실행/생성 탭 / 툴바는 시스템 토글만.
> 이미지=사이드바 전폭 탭 패턴 (T-230/240) 이식.

## 구조 (SidebarView:20-87 패턴)

* `inspector`: `VStack(spacing: 0)` — 시스템 고정층(스크롤 밖) + 탭 + `Divider` + `List(.sidebar)`.
* 탭: `enum InspectorTab { backend, generate }` + `@AppStorage("inspectorTab")`,
  전폭 버튼·선택 `DSColor.primary` 0.15 틴트, 전환 `[INFO]` 로그.
* 시스템 고정층: 호버 ⋯(숨기기) 유지. 실행/생성은 탭에 항상 존재 →
  "숨기기" 메뉴 삭제, "기본값으로 되돌리기"만 (`onHide` optional화).
* `SectionSegments` 3칸 → gauge 단일 토글 (시스템만).
* `showBackend`/`showGenerate` 제거: `anySectionVisible`→showSystem 기준,
  `inspectorColumnShown`→`inspectorVisible` (탭 항상 존재). 구 키 잔류 무해
  (AppServices 이사는 손대지 않음).

## 비목표

* 값 편집·적용/취소·미지원 게이팅 동작 변경 없음.

## 검증

* 갱신 unit (static 헬퍼 기존 2건 유지) + 탭 기본값 1건 + 276 회귀.
* lint 신규 0 + build + 눈확인 (탭 전환·고정층·320폭).
