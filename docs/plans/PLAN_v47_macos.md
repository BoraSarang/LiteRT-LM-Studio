# PLAN v47 — 모델 관리 창 (macOS, T-232)

## 1. 목표

* T-232: 별도 모델 관리 창. 가져오기·목록·삭제·이름변경 (명세서 `litert-lm-model-management-spec.md` 기준, 확정 사양은 §2).
* 사이드바 관리 버튼 껍데기(안내 Alert)를 진짜 창 열기로 교체.

## 2. 확정 사양 (사용자 결정)

* 스테이징 숨김 폴더: `~/Documents/.LiteRT-LM/` (미완성 `*.part` → 완료 시 `*.litertlm` 개명, 완료 후에도 유지·삭제 안 함). Finder에 안 보이므로 창에 "폴더 열기" 포함. 폴더 생성은 구현 시 사용자 확인 후.
* 다운로드 방식: 앱 직접 다운로드 후 로컬 import (B안). `import --from-huggingface-repo` 위임이 아님. HF 파일 URL은 `https://huggingface.co/<REPO>/resolve/main/<FILE>` 규칙.
* 상태 3종: `다운로드 중 n%·남은 mm:ss` / `다운로드 완료·미설치` / `설치됨`.
* 목록 = 스테이징 스캔 + `litert-lm list` 조인. 파일명 ↔ 로컬ID 매핑 JSON 저장 (스테이징 폴더 내 `.mapping.json`).
* 목록 캐싱: `list` + 스테이징 스캔 결과 캐시. 무효화 = 창 열기 새로고침·가져오기/설치/삭제/이름변경 완료·앱 시작 1회. 그 외 캐시 표시 + `[CACHE]` 로그.
* 가져오기 다이얼로그: Gemma/Qwen 대표 프리셋 + 직접입력(저장소·파일명·로컬ID·토큰). 진행률 바+퍼센트+경과+남은시간+취소.
* 이름변경 = CLI `rename OLD NEW` (실제 ID) + 매핑 갱신. 표시 별칭(`ModelAlias`)은 별도 유지.
* 로컬 파일 가져오기(`import <경로>`)는 후속 (창 구조만 열어 둠).
* 디스크 2배 사용(스테이징 + `~/.litert-lm/models`) 안내 문구 필수.

## 3. 변경

* `Core/ModelStore.swift`: 스테이징 스캔·매핑·캐시·`importFile`·`rename` 추가. `refresh()`는 캐시(`refreshCaching`) + 강제(`refresh(force:)`) 분리. 진행률·ETA·상태 판정은 순수 함수로 분리 (테스트 대상).
* `Core/ModelDownload.swift` 신규: URLSession 다운로드(`.part`→개명, 취소 시 `.part` 유지), `%`·속도·ETA 계산. `[INFO] [FEATURE] 모델가져오기` 로그 1개 이상, 실패 `[ERROR] E-MAC-STOR-0006`.
* `ModelManagerView.swift` 신규: `Window(id:modelManager)` 본체. 목록(상태 뱃지)+새로고침+가져오기 시트+설치/삭제/이름변경 메뉴+폴더 열기.
* `LiteRTLMStudioApp.swift`: 모델 관리 Window 등록. `AppNotifications`: `.openModelManager` 추가.
* `SidebarView.swift`: 관리 버튼 → `openWindow(id:modelManager)` + Notification 전달. `PaletteViews.swift`: "모델 관리 열기" 항목.
* `GlobalPermission.swift`: 가져오기·설치도 게이트 대상에 포함 (기존 삭제만 → 삭제+가져오기+설치). off 차단+E-MAC-PERM-0011, ask 확인.
* `error_message_ko.json`: rename 실패 코드 1건 추가 (E-MAC-STOR-0012 가번).
* 회귀: 상태 판정·ETA·매핑·캐시 무효화·정렬.

## 4. 검증

* unit (신규 회귀 포함) + swiftlint 신규 0 + `xcodebuild build` + 설치·실행 2회 (AGENTS.local 상시 규칙).
* DebugPanel ERROR 0 확인. 눈확인: 창 열기·프리셋 다운로드(소용량 먼저)·취소·`.part`→개명·설치 후 `설치됨`·rename·삭제 게이트.
* PERF/CACHE: 목록 캐시로 `list` 호출 감소. 영향 없음 명기.
* DoD: PLAN+TODO+DOCKER 아닌 문서(DESIGN·CHANGELOG·사용설명서 4장)·error 코드·로그·TODO/bd close·session 로그.
