# PLAN v2 — 시스템 그래프 복원 + 정확도 (macOS)

> T-012. 0.6.0 3선 통합 → 0.3.0 분리형 복귀 + 데몬 중심 강조. 단일코어 유지, RAM 활성상태보기 일치.

## 1. 배경
- 통합 차트(CPU전체·RAM전체·데몬CPU 한 축)가 데몬 부하 판단에 불리. 전체 CPU가 주인공이 됨.
- 시스템 섹션 목적 = 데몬이 CPU/RAM 얼마나 먹나. 전체는 참고용.

## 2. 변경
- UI: `mergedChart` 삭제 → 데몬 히어로(주황 스파크라인 60초 + CPU%·RSS) 상단 + CPU/RAM/GPU 미니 스파크라인(각 28px) + 값 행. 전체는 secondary, 데몬은 semibold 강조.
- CPU 전체: `host_processor_info` 유지 + 실측 경과초 도입(타이머 드리프트 제거).
- RAM 전체: `active+wired+compressed` 로 교정(inactive 제외, 활성 상태 보기 정의). inactive는 `캐시 x.xGB` 별도 표기.
- 데몬 CPU: `Δns/실측경과` 로 나눔, 100% 초과 허용(단일코어). 히스토리는 원값 저장.
- 데몬 RSS: `ri_resident_size` → `ri_phys_footprint` 합산(공유메모리 중복 제거, 활성 상태 보기와 동일).
- `lsof` 5틱 캐시 + 상태 전이 시 무효화(`invalidateDaemonCache`, daemon 시작/중지/인수 시 호출).
- GPU: 그대로(순간 추정치 문구 유지).

## 3. 검증
- unit: RAM 신공식·경과나눗·footprint 변환·전이표 기존. 목표 12/12.
- `./build_and_run.sh test macos unit` + swiftlint + DebugPanel PERF 확인.

## 4. T-013 툴바 분리 (추가)
- 원인: `ToolbarItemGroup(.primaryAction)` 분할 캡슐 + 아이콘 교체(play↔stop, 너비 상이) + 터미널 활성 전환이 겹쳐 정지 버튼이 캡슐 밖으로 밀려나며 아이콘 실종.
- 처방: 그룹→`ToolbarItem` 2개 분리(독립 캡슐) + 서버 버튼 고정폭(28)으로 글리프 너비차 흡수.

## 5. T-016 인스펙터 4섹션 on/off
- 시스템·백엔드·샘플링·Thinking 접기(FoldSection) 폐지 → 섹션별 완전 보이기/숨기기.
- 툴바 4칸 분할 컨트롤 상시 표시(진실원천) + SceneStorage 4개(기본 true).
- 전체 off → detail 미렌더 → 2분할. 마스터 토글(⌥⌘I)은 전체 off 상태에서 전체 복원(보이기)으로 동작.
- T-015 CPU 버그는 별도 후속.

## 6. T-015+T-017 CPU/RAM 패리티
- T-015: 틱 인덱스 교정 (used=.0+.1+.3, idle=.2) + 순수 헬퍼 분리.
- T-017: CPU 사용자(파랑)+시스템(빨강) 스택, RAM App(노랑)+Wired(빨강)+Compressed(파랑) 스택. inactive=캐시된 파일.
- 데몬 히어로·GPU 불변. 색 상수 분리.
