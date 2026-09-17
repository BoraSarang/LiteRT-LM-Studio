# PLAN v66 — 경로 고정 + 네이티브 자동 초기화 (T-275)

## 원인·목표

* 전송 경로가 서버로 돌아감: 단위 테스트가 실 UserDefaults(`engineMode`)를 덮어씀.
  저장소 주입으로 격리 + `migrateLegacyDefaults`에 `engineMode` 추가.
* 앱 내 엔진 선택+모델 선택 시 자동 초기화, 모델 변경 시 자동 전환.
  재실행 복원 시에는 자동 실행 안 함.

## 변경

* `ChatStore`: `routeDefaults` 주입, init 로드, 테스트 격리+라운드트립 테스트.
* `ContentView`: 경로 전환·모델 변경 시 `autoPrepareNativeIfNeeded`
  (`shouldAutoPrepare` 순수 판정+테스트).
