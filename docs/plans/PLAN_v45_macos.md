# PLAN v45 — 전역 권한 3단계+입력창 모델 피커 (macOS)

## 1. 목표

* T-228 전역 단일 권한 (Off / Ask every time / Allow all). 기본값 Ask.
* T-229 채팅 입력창 내장 모델 선택 (설치된 모델만, Gemma→Qwen 우선 정렬).
* 받아쓰기/녹음 제외 (사용자 결정). 모델 관리 별도 창은 후속 (apps-docs 명세 참조).

## 2. 현상 근거

* 모델 선택은 사이드바만 (`SidebarView.swift:9`, `ContentView.swift:23` SceneStorage).
* 입력창은 경로 피커만 (`ChatInputBar.swift:108-114`). 모델 피커 없음.
* 권한 개념 없음. 삭제는 즉시 실행 (확인 다이얼로그는 spec에서만 요구).
* 설치 목록은 `ModelStore.refresh()`가 `litert-lm list`로 보장 (필터 불필요, 정렬만).

## 3. 변경

* T-228: `Core/GlobalPermission.swift` 신규 (enum off/ask/allowAll + `allows(action:confirmed:)` 순수 게이트).
  AppStorage `globalPermission` 기본 ask. 게이트 대상: 채팅 전송+모델 삭제 (가져오기는 훅만).
  off=차단+E-MAC-PERM-0011, ask=NSAlert 단발 확인 (T-113/T-139 선례), allowAll=통과.
  설정 일반 탭 Segmented 3칸 + 입력창 상태 표시. `[INFO] [FEATURE] 권한` 로그.
* T-229: `ChatInputBar`에 모델 Menu 내장 (경로 피커 옆). 값은 `selectedModelID` 공유 바인딩.
  `ModelStore.preferredOrder` 순수 정렬 (Gemma→Qwen→기타). 빈 목록은 안내 문구.
  변경 시 기존 `config.load`+`chat.model` 동기 경로 재사용.

## 4. 검증

* unit: 게이트 3단계·정렬·빈 목록·동기 회귀. 기존 125건 유지.
* `test macos unit` + swiftlint 신규 0 + `xcodebuild build` (open 없이). DebugPanel ERROR 0.
* PERF/CACHE 영향 없음.
