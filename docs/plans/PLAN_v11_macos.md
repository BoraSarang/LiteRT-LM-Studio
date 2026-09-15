# PLAN v11 — 이름 변경 AppKit 단발 모달 교체 (macOS, T-139)

## 1. 목표

0.7.81(item 기반 시트)에서도 정렬 무관·저장/엔터/ESC 전부 반복 → 저장 경쟁 가설 기각.
SwiftUI 시트 수명주기 문제로 확정하고 T-113 선례대로 AppKit 단발 모달로 교체.

## 2. 근거 (검증됨)

* 0.7.81 설치본에서 재현 지속. ESC(쓰기 없음)에서도 반복 → `@Published` 재정렬 경쟁 아님.
* `renameItem` 재설정 코드는 메뉴 버튼 하나뿐인데도 재표시 → 시트 표시 루프.
* 삭제 컨펌(NSAlert)은 동일 메뉴·동일 List에서 반복 없음 (T-113 눈확인) → 모달 방식 유효.

## 3. 변경

1. `SessionListView.swift`: `.sheet`·`RenameTarget`·`renameSheet`·`commitRename`·`commitPayload` 삭제.
   `promptRename(_:)` 신규 (NSAlert+NSTextField, Enter=저장/ESC=취소, 초기 포커스 입력란).
   `allowRename` 1초 가드 (allowDelete 동일 규칙). 저장 규칙은 `renameSession` 그대로 (trim·빈값→자동).
2. 테스트: `testRenameCommitPayload` 삭제 → `testAllowRename` 추가 (83종 유지 목표).
3. 문서: TODO T-139 + CHANGELOG 0.7.82 + 본 PLAN. T-138은 기각 기록 유지.

## 4. 검증

* unit + lint 신규 0 + `build macos` 설치. 눈확인: 정렬 3종 × 저장/Enter/ESC/취소 × 우클릭/⋯, 1회 표시·1회 저장.
