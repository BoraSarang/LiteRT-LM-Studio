# PLAN v52 — 재실행 복원 + 삭제 분리 (macOS, T-249/T-250)

## 1. 목표

* T-249: 다운로드 큐 영속 (`.queue.json` 원자 쓰기) + 재실행 일시정지 복원 +
  `.part` 고아 표시·삭제. 토큰 미저장.
* T-250: 모델 삭제 vs 파일 삭제 분리 (개명+의미 문구+체크박스 연쇄+매핑 퍼지).

## 2. 변경

* `DownloadItem.repo` 추가 (호출 3곳 동반).
* `DownloadCenter`: 큐 저장·복원·고아 스캔. 복원 시 final 존재분 완료 처리,
  나머지는 paused + 수신량=`.part` 크기.
* `ModelDownloader.stageForResume` 추가 (재개 정보 주입).
* `ModelStore.saveMapping` 원자 쓰기. 모델 삭제 시 stale 매핑 퍼지.
* 설치됨 행 메뉴 `모델 삭제` + 확인문 의미 명시 + "받은 파일도 함께 삭제" 체크.
  스테이징 행 `파일 삭제` + 설치 유지 경고.
* 회귀: 큐 코덱·고아 판정·복원 필터·토큰 미포함·퍼지 5건.

## 3. 검증

* unit 149+5 내외 + lint 신규 0 + `build macos` 2회 + DebugPanel ERROR 0.
* 눈확인: 종료→재실행 복원·이어받기·토큰 안내·고아 삭제·3경로 삭제.
