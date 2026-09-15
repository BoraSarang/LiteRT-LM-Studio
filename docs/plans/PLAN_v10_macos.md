# PLAN v10 — 이름 변경 시트 반복 표시 수정 (macOS, T-138)

## 1. 목표

우클릭 컨텍스트 메뉴 → 이름 변경 → 저장/엔터 후 변경 시트가 계속 다시 뜨는 반복을 해소.
최근 순 정렬에서 재현됨.

## 2. 원인

* `SessionListView`가 `.sheet(isPresented: 파생 Bool)` 사용 (`renameTarget != nil`).
* `commitRename()` 순서가 `renameSession()`(→ `@Published sessions` 변경 + `updatedAt` 갱신으로 최근 순 재정렬) → `renameTarget=nil`(닫기).
* Published 변경 시점에 시트가 아직 열려 있어 `Section+ForEach` 재구성과 닫기 애니메이션이 경쟁 → 닫힌 시트가 새 인스턴스에 재표시되는 것으로 추정.
* `onSubmit + 저장 버튼` 이중 호출 가능, `renameText` 잔존으로 반복 시 이전 값 재사용.

## 3. 동작 명세

* 이름 변경 메뉴 선택 시 1회만 시트 표시.
* 저장/엔터/취소/ESC 모두 1회로 종료, 재표시 없음.
* 저장 내용은 `renameSession` 기존 규칙 유지 (trim, 빈값→자동 제목).
* 정렬(최근/이름/생성)·호버 ⋯/우클릭 두 경로 모두 동일.

## 4. 파일별 변경

1. `SessionListView.swift`:
   - `renameTarget: UUID?` → `renameItem: RenameTarget?` (`Identifiable` 래퍼) + `isCommitting` 가드.
   - `.sheet(isPresented: 파생)` → `.sheet(item: $renameItem)` + `onDismiss`에서 `renameText` 초기화.
   - `sessionMenu`에서 `renameItem = RenameTarget(id:)` 세팅.
   - `commitRename()`를 nil-먼저로 변경: id·text 캡처 → `renameItem=nil` → `renameText=""` → `renameSession`.
   - 취소 버튼도 동일하게 nil-먼저 + 텍스트 초기화.
   - 순수 헬퍼 `resolvedRenameCommit(current: Senators...)`는 테스트 가능 형태로 분리하지 않고, 기존 `allowDelete` 패턴 준용해 필요 시 `commitRenamePayload` 순수 함수 추가 검토.
2. 테스트: 기존 `testRenamePin` 유지. 시트 상태 전이는 SwiftUI 런타임 의존이라 unit 불가 → 수동 눈확인으로 대체.
3. 문서: TODO T-138 + CHANGELOG 0.7.81 + 본 PLAN.

## 5. 주의·위험

* `UUID` 직접 `sheet(item:)` 불가 → 래퍼 필수.
* AppKit 직접 사용 금지 유지 (시트는 SwiftUI만).
* `renameSession`의 `updatedAt` 갱신은 유지 (최근 순 명세). 순서만 바꿔 경쟁 제거.

## 6. 검증

* `test macos unit` + `swiftlint` 신규 0.
* `./build_and_run.sh build macos` 성공.
* 눈확인: 최근 순 + 우클릭 + 저장/엔터/취소/ESC, 이름 순/생성 순 각 1회, ⋯ 메뉴 경로 대조.
* DebugPanel ERROR 0.
