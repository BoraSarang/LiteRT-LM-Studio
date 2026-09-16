# PLAN v63 — macOS 시스템 도구팩 (T-270)

## 목표

* 읽기 4종 + Gated 쓰기 5종의 시스템 Tool 추가. 셸·파일쓰기·발송은 제외.
* 날짜는 모델 출력 불신, 상대 표현을 시스템 시계로 계산.

## 변경

* `Core/SystemTools.swift` (신규): 9종 + `KoreanDateParser` + Shortcuts allowlist.
* `LocalTools.registered()` 추가 (시스템 토글+권한 게이트).
* 설정 토글+allowlist, Info.plist 2건, `E-MAC-PERM-0016`·`E-MAC-VALID-0017`.
* 사용설명서에 전 기능 도움말 저장 (사용자 요청).

## 검증

* unit 날짜 10건+allowlist+스키마+기존 유지, 실기 E2E, lint 0, build 2회.
