# PLAN v64 — 셸 실행 + 파일 저장 도구 (T-272)

## 목표

* `run_shell` (임의 명령+확인, 하드 차단+jail+출력 cap) +
  `save_code` (작업폴더 한정+덮어쓰기 확인) + `read_file` (검증용 읽기).

## 변경

* `Core/ShellTools.swift` (신규): 3종 Tool + `ShellGuard` 순수함수.
* `LocalTools.registered()`·`ToolCatalog` 3행, 작업폴더 선택 설정.
* `TOOLCALL_TEST.md` 6종, 사용설명서, CHANGELOG·DESIGN·TODO.

## 검증

* unit 12건, 실기 E2E, lint 0, build 2회.
