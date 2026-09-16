# PLAN v48 — 가져오기 정리 + 다운로드 상주화 (macOS, T-233)

## 1. 목표

* 가져오기 시트 4섹션 정리 (읽기 순서 고정·자동 조회·시작 후 잠금).
* `DownloadCenter` 앱 상주 이동 (창 닫아도 계속+재오픈 시 진행·취소).

## 2. 변경

* `AppServices.swift`: `downloads = DownloadCenter()` 추가 (bench 선례).
  `LiteRTLMStudioApp.swift` 모델 관리 Window에 `center: services.downloads` 주입.
  `ModelManagerView`는 `@ObservedObject var center`로 받음 (`@StateObject` 삭제).
* `ModelManagerSections.swift` ImportSheet 개편:
  1 모델(segmented+프리셋/직접) → 2 파일(자동 목록+실패 시 직접 폴백)
  → 3 저장(로컬ID+토큰) → 4 진행(고정 슬롯: 대기/바/완료).
  수동 "불러오기" 삭제, 저장소·프리셋·토큰 변경 시 debounce 자동 재조회.
  시작 후 입력 잠금 + "닫기"만, 완료·실패 후 "새로 받기".
  중복 시작 가드: 동일 파일명 진행 중이면 시작 비활성+안내.
* 순수 헬퍼 (테스트 대상, `ModelDownload`에 추가):
  `hasActiveDownload(items:fileName:)`, `resolveFile(siblings:fileIndex:customFile:)`,
  `authHeader(token:)` (nil이면 헤더 없음).
* 회귀 3건: 중복 가드·파일 폴백·헤더.

## 3. 검증

* unit 137/137 + lint 신규 0 + `build macos` 2회 + DebugPanel ERROR 0.
* 눈확인: 섹션 흐름·자동 조회·잠금·시트 닫고 진행·창 닫고 재오픈·취소·완료 반영.
* PERF/CACHE 영향 없음.
