# AGENTS.local.md — LiteRT-LM Studio

> 공통 가이드는 상위 AGENTS.min 참조. 여기엔 프로젝트 특화 예외만 기록.

* 적용 플랫폼 확정: **macOS 단일** (iOS/Android/Web/확장 제외).
* 네이티브 필수: SwiftUI만. AppKit 뷰 직접 사용 금지. 예외: NSOpenPanel/NSPasteboard/NSImage 크기변환 같은 비(非)뷰 API만 허용. 추가 예외(T-047): 채팅 NSScrollView 탐색용 0크기 `ScrollViewFinder` 1건 (렌더 없음, 절대좌표 점프 진입점).
* 정렬 규칙 (전역 기본, 별도 요구 없으면 전 화면 적용): 데이터 있음 → 콘텐츠 영역 좌측·상단 정렬. 데이터 없음(빈 상태) → 가로·세로 중앙 정렬.
* 번들ID: `com.borasarang.litert-lm-studio` (T-060 개명, 변경 시 파괴적 가드).
* 외부 도구: `/opt/homebrew/bin/uv` 절대경로 사용 (Swift Process PATH 미의존).
* 데몬: `litert-lm serve --host 127.0.0.1 --port 9379` 고정. 포트 변경 시 본 파일 갱신.
* 모델 경로: `~/.litert-lm/models` 읽기 전용 참조. `.litertlm` 앱 번들 금지.
* 캐시 삭제(`rm -r ~/.litert-lm`)는 파괴적 동작 → 확인 팝업 필수.
* 빌드: `xcodebuild`만 사용 (`swift build/test` 금지). 결과물 `~/Applications/LiteRT-LM Studio.app` (번들명=DisplayName 규칙, 기존 있으면 rm 후 복사 — 본 프로젝트 결과물에 한함).
* 상주형: 메뉴바(MenuBarExtra) 기본, Dock은 설정 토글. 창 닫기≠종료. 종료(⌘Q·메뉴바) 시 앱 소유 데몬 함께 종료, 외부 데몬은 유지.
* App.init에서 NSApp 호출 금지 (테스트 부트스트랩 크래시 전례). 정책·활성화는 화면 표시 이후.
* 다운로드 대행 금지: 필요 파일(URL+용도+저장 경로)만 사용자에게 요청, 직접 다운로드 금지.
