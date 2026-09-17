# HANDOFF — 새 세션 인수인계 (2026-09-16 macos)

## 현재 상태

- 브랜치: `main` (최신 커밋에 T-260 포함 여부는 `git log --oneline -3` 확인).
  T-257까지 커밋됨 (`193d684`, `5159736`). T-258~260은 미커밋일 수 있음 → 먼저 `git status` 확인.
- 테스트: 159/159, lint 신규 0 (기준선 3건: DaemonManager·ChatStore·SystemMonitor).
- 앱: `~/Applications/LiteRT-LM Studio.app` 설치·실행됨.

## 남은 일

- [ ] T-215 스크롤 간헐 미도달 방 (장기 백로그, PLAN_v31~v40 참조).
- [ ] 눈확인 대기열: T-234 카탈로그, T-246 이어받기 실측, T-258~260 목차·핀, T-257 랜딩 첫 실행.
- [ ] 미커밋 있으면 커밋 (feat/docs 분리, `.agent/` 제외, 푸시는 지시 후).

## 핵심 규칙 (AGENTS.local.md)

- 한국어 필수, SwiftUI만, `xcodebuild`만 (`swift build` 금지).
- 빌드 후 항상 설치·실행 2회: `./build_and_run.sh build macos`.
- 단위 테스트: `./build_and_run.sh test macos unit` + swiftlint 신규 0.
- 새 파일은 pbxproj 등록 필수 (fileRef+BuildFile+group+sources).
- ContentView body 타입추론 한계: modifier 체인은 rootDialogs/rootEvents 분리 유지.
- 구조체에서 NSEvent 클로저 상태 변경 불가 → Notification 경유 (T-260 선례).
- no-op edit 주의: oldString末尾 `\n` 제거 시 다음 줄과 병합됨. 붙여넣기 후 빌드로 확인.
- 세션 시작: `docs/TODO.md` + `docs/plans/` 최신 + 본 파일. 종료: session 로그 8줄 요약.

## 주요 파일

- 모델 관리: `ModelManagerView` + Sections + `CatalogBrowser*` + `DownloadRowView` + `ImportSheetView`.
- 다운로드: `Core/ModelDownload` (순수) + `Core/ModelDownloader` (실행기).
- 스크롤: `ChatPaneView` + `ChatScrollActions` + `FollowGate` + `ScrollMath`.
- 목차: `ChatOutlineView` + 설정 채팅 탭.
- 랜딩: `LandingView` + `Core/OnboardingGate` + `AppStorage("onboardingDone")`.

## 최근 교훈

- HF resolve는 302+Xet: 크기는 `x-linked-size`, 추종 HEAD 금지.
- `/{org}/avatar` 무효 → 로컬 뱃지. 게이트 저장소는 토큰 필수.
- `.part`·`.queue.json`·`.mapping.json`은 원자 쓰기, 토큰 미저장.
