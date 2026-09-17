# PLAN v72 — wigolo 설정 통합 (T-284)

## 목표

* 설정 UI에서 설치(터미널식 진행 표시)+상태+시작/중지.
* 폴백 전면 제거, 미설치 시 사용 불가, 앱 시작·종료와 생명주기 연동.

## 변경

* `WigoloManager`: install()+npm 탐색+상태 installing+ensureRunning().
* `WebSearch`: DDG/Wiki 경로·DTO·테스트 삭제, 단일화, 미설치 즉시 반환.
* `SettingsView` 상태+버튼+로그뷰, `AppServices` 공유+시작/종료 연동.
