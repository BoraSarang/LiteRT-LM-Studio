# PLAN v88 — 검색 데몬 실행 로그 수집+팝오버 (macOS, T-308)

> 사용자 요청: "검색 데몬 실행 로그 말이야" / "로그 보기 버튼 누르면 나오게".

## 원인

* `WigoloManager.start()`가 `wigolo serve`를 Pipe 없이 실행 → stdout/stderr가 어디로도 안 감.
* 설정 도구 탭 로그박스는 설치 파이프라인(`installLog`) 전용이라 serve 출력은 표시 불가.
* 그래서 `시작`→3초 후 `중지`로 돌아가도 이유를 볼 방법이 없음 ("로그가 없어").

## 변경 (1관심사)

1. `WigoloManager` (`Core/WigoloManager.swift`):
   * `@Published serveLog: [String]` 추가 (300줄 cap, `appendServeLog`).
   * `start()`에서 serve 프로세스에 Pipe 연결, 출력을 `serveLog`로 스트리밍.
   * `$ <bin> serve` 명령줄 + 헬스 결과(실행 중/중지) + 비정상 종료코드 기록.
   * `stop()`은 로그 유지 (중지 원인 추적용), "중지 요청" 1줄 추가.
   * 순수 헬퍼 `cappedServeLog(_:cap:)` (테스트용).
2. 설정 도구 탭 (`SettingsMCPSkillViews.swift` `wigoloRows`):
   * `시작` 옆에 `로그 보기` 버튼 + 팝오버 (serveLog 표시, 빈 상태 문구, `복사` 버튼).
3. unit 1건: `testServeLogCap` (300 cap·꼬리 유지).

## 비범위

* 하단 패널(`⌘J`)·디버그 윈도우(`⇧⌘D`)·툴바 동작 변경 없음.
* serve 실패 자체의 수정이 아니라 원인 가시화가 목적.

## 검증

* `test macos unit` + swiftlint 신규 0 + `build macos` 1회.
* 눈확인: 시작 → 로그 보기 팝오버에 `$ ... serve` + 출력 표시. 실패 시 종료코드·헬스 실패 줄 확인.
